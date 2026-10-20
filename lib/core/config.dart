import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Wie Kuechenstatus und QR-Code gezeigt werden.
enum DisplayMode {
  /// App bleibt offen und zeigt Status + QR-Code im Vollbild (Display bleibt an).
  app('App-Anzeige', 'Die App bleibt offen und zeigt Küchenstatus und QR-Code im Vollbild. '
      'Das Display wird dabei nicht ausgeschaltet.'),

  /// Kleines Fenster ueber anderen Apps (home.radio, Spotify, …) – vom Hintergrunddienst.
  overlay('Einblendung über anderen Apps', 'Küchenstatus und QR-Code werden als kleines Fenster über '
      'anderen Apps (home.radio, Spotify, …) eingeblendet – nur an Bestelltagen.'),

  /// Keine Daueranzeige, nur „Bitte abholen“-Meldungen.
  none('Nur Abhol-Meldungen', 'Keine Daueranzeige – es erscheinen nur die „Bitte abholen“-Meldungen.');

  final String label;
  final String description;
  const DisplayMode(this.label, this.description);

  static DisplayMode parse(String? s) => values.asNameMap()[s] ?? DisplayMode.app;
}

/// Wo die Einblendung sitzt (3x3-Raster).
enum OverlayPosition {
  topLeft('oben links'),
  topCenter('oben Mitte'),
  topRight('oben rechts'),
  centerLeft('Mitte links'),
  center('Mitte'),
  centerRight('Mitte rechts'),
  bottomLeft('unten links'),
  bottomCenter('unten Mitte'),
  bottomRight('unten rechts');

  final String label;
  const OverlayPosition(this.label);

  static OverlayPosition parse(String? s) => values.asNameMap()[s] ?? OverlayPosition.bottomRight;
}

/// Aufbau der Einblendung.
enum OverlayLayout {
  /// Text links, QR-Code rechts (wie die Kachel im home.radio).
  wide('Breit (Text + QR-Code)', 260 / 420),

  /// QR-Code oben, Status darunter – schmal, passt gut an den Rand.
  compact('Kompakt (QR-Code + Status)', 1.32);

  final String label;

  /// Hoehe / Breite des Fensters.
  final double aspect;
  const OverlayLayout(this.label, this.aspect);

  static OverlayLayout parse(String? s) => values.asNameMap()[s] ?? OverlayLayout.wide;
}

/// Gemeinsame Einstellungen von App und Hintergrunddienst (beide lesen dieselben SharedPreferences).
class AppConfig {
  static const defaultBaseUrl = 'https://bestellung.jaycloud.at';

  // Verbindung zum order.manager (eigenes Konto des Gastgebers)
  String baseUrl = defaultBaseUrl;
  String user = '';
  String password = '';
  int pollSeconds = 5;

  // Anzeige
  DisplayMode mode = DisplayMode.app;
  bool openDisplayOnStart = true;
  bool launchOnBoot = false;
  bool keepScreenOn = true;

  /// Groesse des QR-Codes in der Vollbild-Anzeige (100 % = so gross wie moeglich).
  int displayQrPercent = 100;

  /// Schriftgroesse der Vollbild-Anzeige (100 % = an die Bildschirmgroesse angepasst).
  int displayTextPercent = 100;

  // Einblendung ueber anderen Apps
  OverlayPosition overlayPosition = OverlayPosition.bottomRight;
  OverlayLayout overlayLayout = OverlayLayout.wide;
  int overlayWidthPercent = 30;
  int overlayMarginPercent = 2;
  int overlayOpacityPercent = 95;
  bool overlayWhenClosed = true;

  // „Bitte abholen“
  bool pickupEnabled = true;
  int pickupSeconds = 30;
  bool pickupSound = true;
  int chimeVolumePercent = 100;

  bool get isConfigured => baseUrl.trim().isNotEmpty && user.trim().isNotEmpty && password.isNotEmpty;

  /// Alles, was bestimmt, *was* abgefragt wird – ohne Intervall, damit eine
  /// reine Intervall-Aenderung keinen Neustart der Abfrage ausloest.
  String get connectionKey => isConfigured ? '${baseUrl.trim()}|${user.trim()}|$password' : '';

  /// Alle Einstellungen unter ihren SharedPreferences-Schluesseln – Grundlage fuer
  /// [save] und die Sicherung. display_mode und launch_on_boot liest auch der
  /// native BootReceiver/Dienst.
  Map<String, Object> toMap() => {
        'base_url': baseUrl.trim(),
        'user': user.trim(),
        'password': password,
        'poll_seconds': pollSeconds,
        'display_mode': mode.name,
        'open_display_on_start': openDisplayOnStart,
        'launch_on_boot': launchOnBoot,
        'keep_screen_on': keepScreenOn,
        'display_qr_percent': displayQrPercent,
        'display_text_percent': displayTextPercent,
        'overlay_position': overlayPosition.name,
        'overlay_layout': overlayLayout.name,
        'overlay_width_percent': overlayWidthPercent,
        'overlay_margin_percent': overlayMarginPercent,
        'overlay_opacity_percent': overlayOpacityPercent,
        'overlay_when_closed': overlayWhenClosed,
        'pickup_enabled': pickupEnabled,
        'pickup_seconds': pickupSeconds,
        'pickup_sound': pickupSound,
        'chime_volume_percent': chimeVolumePercent,
      };

  /// Gegenstueck zu [toMap]; fehlende oder falsch getypte Werte bekommen den Standard.
  static AppConfig fromMap(Map<String, Object?> m) {
    String str(String k, String d) => m[k] is String ? m[k]! as String : d;
    int whole(String k, int d, int min, int max) => (m[k] is int ? m[k]! as int : d).clamp(min, max);
    bool flag(String k, bool d) => m[k] is bool ? m[k]! as bool : d;
    return AppConfig()
      ..baseUrl = str('base_url', defaultBaseUrl)
      ..user = str('user', '')
      ..password = str('password', '')
      ..pollSeconds = whole('poll_seconds', 5, 5, 60)
      ..mode = DisplayMode.parse(str('display_mode', ''))
      ..openDisplayOnStart = flag('open_display_on_start', true)
      ..launchOnBoot = flag('launch_on_boot', false)
      ..keepScreenOn = flag('keep_screen_on', true)
      ..displayQrPercent = whole('display_qr_percent', 100, 20, 100)
      ..displayTextPercent = whole('display_text_percent', 100, 40, 200)
      ..overlayPosition = OverlayPosition.parse(str('overlay_position', ''))
      ..overlayLayout = OverlayLayout.parse(str('overlay_layout', ''))
      ..overlayWidthPercent = whole('overlay_width_percent', 30, 10, 80)
      ..overlayMarginPercent = whole('overlay_margin_percent', 2, 0, 20)
      ..overlayOpacityPercent = whole('overlay_opacity_percent', 95, 40, 100)
      ..overlayWhenClosed = flag('overlay_when_closed', true)
      ..pickupEnabled = flag('pickup_enabled', true)
      ..pickupSeconds = whole('pickup_seconds', 30, 10, 300)
      ..pickupSound = flag('pickup_sound', true)
      ..chimeVolumePercent = whole('chime_volume_percent', 100, 10, 100);
  }

  static Future<AppConfig> load() async {
    final p = await SharedPreferences.getInstance();
    // Die andere Engine (App bzw. Dienst) kann inzwischen gespeichert haben.
    await p.reload();
    return fromMap({for (final k in p.getKeys()) k: p.get(k)});
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    for (final MapEntry(:key, :value) in toMap().entries) {
      switch (value) {
        case String v:
          await p.setString(key, v);
        case int v:
          await p.setInt(key, v);
        case bool v:
          await p.setBool(key, v);
      }
    }
  }

  // ------------------------------------------------------------ Sicherung (JSON)
  //
  // Komplette Konfiguration inkl. Zugangsdaten, z. B. um sie nach einer
  // Neuinstallation (anderer Paketname) wiederherzustellen.

  static const backupFormat = 1;

  String toBackupJson() => const JsonEncoder.withIndent('  ').convert({
        'app': 'order_manager_client',
        'format': backupFormat,
        'created': DateTime.now().toIso8601String(),
        'config': toMap(),
      });

  /// Wirft [FormatException], wenn [json] keine Order-Manager-Client-Sicherung ist.
  static AppConfig fromBackupJson(String json) {
    final root = jsonDecode(json);
    if (root is! Map || root['app'] != 'order_manager_client' || root['config'] is! Map) {
      throw const FormatException('Keine Order-Manager-Client-Sicherung');
    }
    if ((root['format'] as int? ?? 0) > backupFormat) {
      throw const FormatException('Sicherung stammt aus einer neueren App-Version');
    }
    return fromMap((root['config'] as Map).cast<String, Object?>());
  }
}
