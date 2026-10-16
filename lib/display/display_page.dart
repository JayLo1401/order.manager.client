import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/config.dart';
import '../core/native_bridge.dart';
import '../core/theme.dart';
import '../order/order_poller.dart';
import '../order/order_service.dart';
import '../widgets/order_card.dart';
import '../widgets/pickup_popup.dart';

/// App-Anzeige: Kuechenstatus und QR-Code im Vollbild. Das Display bleibt an, solange
/// die Seite offen ist. Zurueck fuehrt zu den Einstellungen.
///
/// „Bitte abholen“ kommt normalerweise vom Hintergrunddienst (als Einblendung, auch
/// ueber dieser Seite). Laeuft der Dienst nicht, uebernimmt die Seite das selbst.
class DisplayPage extends StatefulWidget {
  const DisplayPage({super.key});

  @override
  State<DisplayPage> createState() => _DisplayPageState();
}

class _DisplayPageState extends State<DisplayPage> {
  late final _poller = OrderPoller(watchReady: false, onAnnounce: _onAnnounce);
  late final AppLifecycleListener _lifecycle;
  AppConfig _config = AppConfig();
  Timer? _clock;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _poller.addListener(_rebuild);
    _lifecycle = AppLifecycleListener(
      onResume: _onResume,
      // App im Hintergrund -> die Einblendung darf wieder erscheinen.
      onShow: () => NativeBridge.setDisplayOpen(true),
      onHide: () => NativeBridge.setDisplayOpen(false),
    );
    NativeBridge.setDisplayOpen(true);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _clock = Timer.periodic(const Duration(seconds: 10), (_) => setState(() => _now = DateTime.now()));
    _load();
  }

  Future<void> _load() async {
    final c = await AppConfig.load();
    final serviceOn = await NativeBridge.isServiceEnabled();
    if (!mounted) return;
    _config = c;
    _poller.watchReady = !serviceOn;
    _poller.configure(c);
    await NativeBridge.setKeepScreenOn(c.keepScreenOn);
    setState(() {});
  }

  void _onResume() {
    _load();
    _poller.refresh();
  }

  void _onAnnounce(List<ReadyItem> fresh) {
    if (_config.pickupSound) NativeBridge.playChime(volume: _config.chimeVolumePercent / 100);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _clock?.cancel();
    _lifecycle.dispose();
    _poller.removeListener(_rebuild);
    _poller.dispose();
    NativeBridge.setKeepScreenOn(false);
    NativeBridge.setDisplayOpen(false);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pickup = _poller.pickup;
    // Gegen Einbrennen: Inhalt wandert minuetlich um wenige Pixel.
    final shift = Offset(math.sin(_now.minute * 0.7) * 6, math.cos(_now.minute * 0.7) * 6);

    return PopScope(
      canPop: pickup == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _poller.dismiss();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // expand: sonst richtet sich der Stack nach dem 0x0-Fokus-Platzhalter und schneidet alles ab.
        body: Stack(fit: StackFit.expand, children: [
          Transform.translate(
            offset: shift,
            child: SafeArea(
              child: DisplayContent(
                config: _config,
                day: _poller.day,
                status: _poller.lastStatus,
                now: _now,
              ),
            ),
          ),
          // Fokussierbares Element, damit OK/Zurueck auf der Fernbedienung ankommen.
          if (pickup == null) const Focus(autofocus: true, child: SizedBox.shrink()),
          if (pickup != null)
            PickupPopup(
              items: pickup,
              since: _poller.pickupSince,
              durationSeconds: _config.pickupSeconds,
              onClose: _poller.dismiss,
              showCloseButton: true,
            ),
        ]),
      ),
    );
  }
}

/// Inhalt der Vollbild-Anzeige – auch fuer die Vorschau in den Einstellungen.
/// QR-Code und Schrift lassen sich getrennt skalieren (auf einem 65"-Fernseher ist 100 % riesig).
class DisplayContent extends StatelessWidget {
  final AppConfig config;
  final OrderDay? day;
  final OrderFetchStatus? status;
  final DateTime now;

  const DisplayContent({super.key, required this.config, required this.day, required this.status, required this.now});

  double get _text => config.displayTextPercent / 100;

  @override
  Widget build(BuildContext context) {
    final t = _text;
    final d = day;
    return Padding(
      padding: EdgeInsets.fromLTRB(32, 20 * t, 32, 16 * t),
      child: Column(children: [
        _header(t),
        SizedBox(height: 16 * t),
        Expanded(
          child: d != null
              ? _DayView(day: d, qrFraction: config.displayQrPercent / 100, textScale: t)
              : _idle(t),
        ),
        SizedBox(height: 8 * t),
        Text('Zurück: Einstellungen', style: TextStyle(color: Colors.white24, fontSize: 13 * t)),
      ]),
    );
  }

  Widget _header(double t) {
    final error = status == OrderFetchStatus.error;
    return Row(children: [
      Image.asset('assets/logo.png', width: 36 * t, height: 36 * t, filterQuality: FilterQuality.medium),
      SizedBox(width: 12 * t),
      Text('Bestellung', style: TextStyle(color: Colors.white54, fontSize: 18 * t, fontWeight: FontWeight.w600)),
      const Spacer(),
      if (error) ...[
        Icon(Icons.cloud_off, color: Colors.redAccent, size: 20 * t),
        SizedBox(width: 6 * t),
        Text('order.manager nicht erreichbar', style: TextStyle(color: Colors.redAccent, fontSize: 14 * t)),
        SizedBox(width: 20 * t),
      ],
      Text(_time(now), style: TextStyle(color: Colors.white70, fontSize: 28 * t, fontWeight: FontWeight.w300)),
    ]);
  }

  Widget _idle(double t) {
    final (icon, title, text) = !config.isConfigured
        ? (Icons.link_off, 'Noch nicht eingerichtet', 'Zurück drücken und unter „Verbindung“ das order.manager-Konto eintragen.')
        : switch (status) {
            null => (Icons.hourglass_top, 'Verbinde…', ''),
            OrderFetchStatus.unauthorized => (
                Icons.lock_outline,
                'Anmeldung fehlgeschlagen',
                'E-Mail/Passwort falsch oder Konto nicht freigeschaltet.'
              ),
            OrderFetchStatus.error => (Icons.cloud_off, 'order.manager nicht erreichbar', 'Neuer Versuch läuft…'),
            OrderFetchStatus.ok => (Icons.restaurant, 'Heute kein Bestelltag', _date(now)),
          };
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 72 * t, color: Colors.white24),
          SizedBox(height: 16 * t),
          Text(title, style: TextStyle(color: Colors.white54, fontSize: 32 * t, fontWeight: FontWeight.w600)),
          if (text.isNotEmpty) ...[
            SizedBox(height: 8 * t),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 18 * t)),
          ],
        ]),
      ),
    );
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
  static String _time(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';
  static String _date(DateTime t) {
    const days = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];
    return '${days[t.weekday - 1]}, ${t.day}.${t.month}.${t.year}';
  }
}

/// Bestelltag: Titel, Status und Gaenge neben dem QR-Code (hochkant: untereinander),
/// zusammen in der Mitte – so bleibt beides beieinander, auch wenn es kleiner gestellt ist.
class _DayView extends StatelessWidget {
  final OrderDay day;

  /// Anteil der groesstmoeglichen QR-Code-Groesse (0..1).
  final double qrFraction;

  /// Faktor auf die automatisch angepasste Schriftgroesse.
  final double textScale;

  const _DayView({required this.day, required this.qrFraction, required this.textScale});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final landscape = c.maxWidth >= c.maxHeight;
      final qrMax = landscape ? math.min(c.maxHeight, c.maxWidth * 0.48) : math.min(c.maxWidth, c.maxHeight * 0.55);
      final qr = qrMax * qrFraction;
      final s = (math.min(c.maxWidth, c.maxHeight * 1.6) / 900).clamp(0.6, 2.5) * textScale;
      final info = _info(s);
      return Center(
        child: landscape
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(child: info),
                SizedBox(width: 48 * s),
                QrBox(day: day, size: qr),
              ])
            : Column(mainAxisSize: MainAxisSize.min, children: [
                Flexible(child: info),
                SizedBox(height: 24 * s),
                QrBox(day: day, size: qr),
              ]),
      );
    });
  }

  Widget _info(double s) {
    // Bei zu wenig Platz lieber verkleinern als abschneiden.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560 * s),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Bestellung aufgeben für',
              style: TextStyle(color: Colors.white60, fontSize: 24 * s, fontWeight: FontWeight.w600)),
          SizedBox(height: 4 * s),
          Text(day.title,
              style: TextStyle(color: Colors.white, fontSize: 48 * s, fontWeight: FontWeight.w800, height: 1.1)),
          SizedBox(height: 16 * s),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.qr_code_scanner_rounded, color: brandGreen, size: 28 * s),
            SizedBox(width: 10 * s),
            Text('Scanne einfach den QR-Code', style: TextStyle(color: Colors.white70, fontSize: 22 * s)),
          ]),
          SizedBox(height: 28 * s),
          StatusBadge(day: day, scale: 1.8 * s),
          if (day.courses.isNotEmpty) ...[
            SizedBox(height: 24 * s),
            Wrap(spacing: 10 * s, runSpacing: 8 * s, children: [
              for (final course in day.courses) _CourseChip(course: course, active: course.code == day.statusCode, scale: s),
            ]),
          ],
        ]),
      ),
    );
  }
}

/// Gang des Abends; der gerade angenommene ist hervorgehoben.
class _CourseChip extends StatelessWidget {
  final Course course;
  final bool active;
  final double scale;
  const _CourseChip({required this.course, required this.active, required this.scale});

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 8 * s),
      decoration: BoxDecoration(
        color: active ? Color.lerp(tileBackground, accentAmber, 0.16) : tileBackground,
        borderRadius: BorderRadius.circular(12 * s),
        border: Border.all(color: active ? accentAmber.withValues(alpha: 0.5) : Colors.white10),
      ),
      child: Text('${course.icon} ${course.label}',
          style: TextStyle(color: active ? Colors.white : Colors.white54, fontSize: 18 * s, fontWeight: FontWeight.w600)),
    );
  }
}
