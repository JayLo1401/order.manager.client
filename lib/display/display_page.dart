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
    _lifecycle = AppLifecycleListener(onResume: _onResume);
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
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final day = _poller.day;
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
          Positioned.fill(
            child: Transform.translate(
              offset: shift,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(32, 20, 32, 16),
                  child: Column(children: [
                    _header(),
                    const SizedBox(height: 16),
                    Expanded(child: day != null ? _DayView(day: day) : _idle()),
                    const SizedBox(height: 8),
                    const Text('Zurück: Einstellungen', style: TextStyle(color: Colors.white24, fontSize: 13)),
                  ]),
                ),
              ),
            ),
          ),
          // Fokussierbares Element, damit OK/Zurueck auf der Fernbedienung ankommen.
          if (pickup == null) const Focus(autofocus: true, child: SizedBox.shrink()),
          if (pickup != null)
            Positioned.fill(
              child: PickupPopup(
                items: pickup,
                since: _poller.pickupSince,
                durationSeconds: _config.pickupSeconds,
                onClose: _poller.dismiss,
                showCloseButton: true,
              ),
            ),
        ]),
      ),
    );
  }

  Widget _header() {
    final error = _poller.lastStatus == OrderFetchStatus.error;
    return Row(children: [
      Image.asset('assets/logo.png', width: 36, height: 36, filterQuality: FilterQuality.medium),
      const SizedBox(width: 12),
      const Text('Bestellung', style: TextStyle(color: Colors.white54, fontSize: 18, fontWeight: FontWeight.w600)),
      const Spacer(),
      if (error) ...[
        const Icon(Icons.cloud_off, color: Colors.redAccent, size: 20),
        const SizedBox(width: 6),
        const Text('order.manager nicht erreichbar', style: TextStyle(color: Colors.redAccent, fontSize: 14)),
        const SizedBox(width: 20),
      ],
      Text(_time(_now), style: const TextStyle(color: Colors.white70, fontSize: 28, fontWeight: FontWeight.w300)),
    ]);
  }

  Widget _idle() {
    final (icon, title, text) = !_config.isConfigured
        ? (Icons.link_off, 'Noch nicht eingerichtet', 'Zurück drücken und unter „Verbindung“ das order.manager-Konto eintragen.')
        : switch (_poller.lastStatus) {
            null => (Icons.hourglass_top, 'Verbinde…', ''),
            OrderFetchStatus.unauthorized => (
                Icons.lock_outline,
                'Anmeldung fehlgeschlagen',
                'E-Mail/Passwort falsch oder Konto nicht freigeschaltet.'
              ),
            OrderFetchStatus.error => (Icons.cloud_off, 'order.manager nicht erreichbar', 'Neuer Versuch läuft…'),
            OrderFetchStatus.ok => (Icons.restaurant, 'Heute kein Bestelltag', _date(_now)),
          };
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 72, color: Colors.white24),
        const SizedBox(height: 16),
        Text(title, style: const TextStyle(color: Colors.white54, fontSize: 32, fontWeight: FontWeight.w600)),
        if (text.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white38, fontSize: 18)),
        ],
      ]),
    );
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
  static String _time(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';
  static String _date(DateTime t) {
    const days = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];
    return '${days[t.weekday - 1]}, ${t.day}.${t.month}.${t.year}';
  }
}

/// Bestelltag gross: links Titel, Status und Gaenge, rechts der QR-Code (hochkant: untereinander).
class _DayView extends StatelessWidget {
  final OrderDay day;
  const _DayView({required this.day});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final landscape = c.maxWidth >= c.maxHeight;
      final qr = landscape ? math.min(c.maxHeight, c.maxWidth * 0.48) : math.min(c.maxWidth, c.maxHeight * 0.55);
      final s = (math.min(c.maxWidth, c.maxHeight * 1.6) / 900).clamp(0.6, 2.5);
      final info = _info(s);
      return landscape
          ? Row(children: [
              Expanded(child: Align(alignment: Alignment.centerLeft, child: info)),
              SizedBox(width: 32 * s),
              QrBox(day: day, size: qr),
            ])
          : Column(children: [
              Expanded(child: Center(child: info)),
              SizedBox(height: 24 * s),
              QrBox(day: day, size: qr),
            ]);
    });
  }

  Widget _info(double s) {
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
