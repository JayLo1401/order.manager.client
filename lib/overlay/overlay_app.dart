import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../order/order_poller.dart';
import '../order/order_service.dart';
import '../widgets/order_card.dart';
import '../widgets/pickup_popup.dart';

/// Laeuft in der vorgewaermten Engine des Hintergrunddienstes (Bedienungshilfe) und
/// fragt den order.manager dauerhaft ab – unabhaengig davon, ob die App offen ist.
///
/// Das Fenster gehoert dem Dienst; hier wird nur entschieden, *was* gezeigt wird:
/// - `none`: nichts (kein Fenster)
/// - `card`: Kuechenstatus + QR-Code in einem kleinen Fenster an der eingestellten
///   Position, nicht beruehr- und nicht fokussierbar (die App darunter bleibt bedienbar)
/// - `full`: „Bitte abholen“ ueber dem ganzen Bild; OK/Zurueck faengt der Dienst ab
class OverlayApp extends StatefulWidget {
  const OverlayApp({super.key});

  @override
  State<OverlayApp> createState() => _OverlayAppState();
}

class _OverlayAppState extends State<OverlayApp> {
  static const _channel = MethodChannel('order_manager_client/overlay');
  static const _previewDuration = Duration(seconds: 15);

  late final _poller = OrderPoller(onAnnounce: _onAnnounce);
  AppConfig _config = AppConfig();
  Timer? _previewTimer;
  bool _preview = false;

  /// Die Vollbild-Anzeige der App zeigt gerade dasselbe – dann keine Karte darueber.
  bool _displayOpen = false;
  String _window = '';

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_onCall);
    _poller.addListener(_update);
    _reload();
  }

  Future<void> _reload() async {
    final c = await AppConfig.load();
    _config = c;
    _poller.configure(c);
    _window = ''; // Groesse/Position koennen sich geaendert haben -> Fenster neu setzen
    _update();
  }

  void _onAnnounce(List<ReadyItem> fresh) {
    if (_config.pickupSound) {
      _channel.invokeMethod('playChime', {'volume': _config.chimeVolumePercent / 100});
    }
  }

  Future<dynamic> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'reload':
        await _reload();
      case 'preview':
        _previewTimer?.cancel();
        _preview = true;
        _previewTimer = Timer(_previewDuration, () {
          _preview = false;
          _update();
        });
        await _reload();
      case 'displayOpen':
        _displayOpen = call.arguments == true;
        _update();
      case 'testPickup':
        _poller.showDemo();
      case 'dismiss':
        // OK/Zurueck auf der Fernbedienung bzw. Tippen
        _poller.dismiss();
    }
    return null;
  }

  OrderDay? get _cardDay {
    if (_preview) return _poller.day ?? OrderDay.demo;
    final day = _poller.day;
    if (_config.mode != DisplayMode.overlay || day == null || _displayOpen) return null;
    if (day.isClosed && !_config.overlayWhenClosed) return null;
    return day;
  }

  /// Fenster passend zum Zustand anfordern (nur bei Aenderung).
  void _update() {
    if (!mounted) return;
    setState(() {});
    final Map<String, Object> args;
    if (_poller.pickup != null) {
      args = {'mode': 'full'};
    } else if (_cardDay != null) {
      final c = _config;
      args = {
        'mode': 'card',
        'position': c.overlayPosition.name,
        'widthFraction': c.overlayWidthPercent / 100,
        'aspect': c.overlayLayout.aspect,
        'marginFraction': c.overlayMarginPercent / 100,
      };
    } else {
      args = {'mode': 'none'};
    }
    final key = args.toString();
    if (key == _window) return;
    _window = key;
    _channel.invokeMethod('setWindow', args);
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    _poller.removeListener(_update);
    _poller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pickup = _poller.pickup;
    final day = _cardDay;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTvTheme().copyWith(scaffoldBackgroundColor: Colors.transparent),
      color: Colors.transparent,
      home: Material(
        type: MaterialType.transparency,
        child: pickup != null
            ? PickupPopup(
                items: pickup,
                since: _poller.pickupSince,
                durationSeconds: _config.pickupSeconds,
                onClose: _poller.dismiss,
              )
            : day != null
                ? Opacity(
                    opacity: _config.overlayOpacityPercent / 100,
                    child: OrderCard(day: day, layout: _config.overlayLayout),
                  )
                : const SizedBox.shrink(),
      ),
    );
  }
}
