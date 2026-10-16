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

  static Future<AppConfig> load() async {
    final p = await SharedPreferences.getInstance();
    // Die andere Engine (App bzw. Dienst) kann inzwischen gespeichert haben.
    await p.reload();
    return AppConfig()
      ..baseUrl = p.getString('base_url') ?? defaultBaseUrl
      ..user = p.getString('user') ?? ''
      ..password = p.getString('password') ?? ''
      ..pollSeconds = (p.getInt('poll_seconds') ?? 5).clamp(5, 60)
      ..mode = DisplayMode.parse(p.getString('display_mode'))
      ..openDisplayOnStart = p.getBool('open_display_on_start') ?? true
      ..launchOnBoot = p.getBool('launch_on_boot') ?? false
      ..keepScreenOn = p.getBool('keep_screen_on') ?? true
      ..displayQrPercent = (p.getInt('display_qr_percent') ?? 100).clamp(20, 100)
      ..displayTextPercent = (p.getInt('display_text_percent') ?? 100).clamp(40, 200)
      ..overlayPosition = OverlayPosition.parse(p.getString('overlay_position'))
      ..overlayLayout = OverlayLayout.parse(p.getString('overlay_layout'))
      ..overlayWidthPercent = (p.getInt('overlay_width_percent') ?? 30).clamp(10, 80)
      ..overlayMarginPercent = (p.getInt('overlay_margin_percent') ?? 2).clamp(0, 20)
      ..overlayOpacityPercent = (p.getInt('overlay_opacity_percent') ?? 95).clamp(40, 100)
      ..overlayWhenClosed = p.getBool('overlay_when_closed') ?? true
      ..pickupEnabled = p.getBool('pickup_enabled') ?? true
      ..pickupSeconds = (p.getInt('pickup_seconds') ?? 30).clamp(10, 300)
      ..pickupSound = p.getBool('pickup_sound') ?? true
      ..chimeVolumePercent = (p.getInt('chime_volume_percent') ?? 100).clamp(10, 100);
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('base_url', baseUrl.trim());
    await p.setString('user', user.trim());
    await p.setString('password', password);
    await p.setInt('poll_seconds', pollSeconds);
    // display_mode und launch_on_boot liest auch der native BootReceiver/Dienst.
    await p.setString('display_mode', mode.name);
    await p.setBool('open_display_on_start', openDisplayOnStart);
    await p.setBool('launch_on_boot', launchOnBoot);
    await p.setBool('keep_screen_on', keepScreenOn);
    await p.setInt('display_qr_percent', displayQrPercent);
    await p.setInt('display_text_percent', displayTextPercent);
    await p.setString('overlay_position', overlayPosition.name);
    await p.setString('overlay_layout', overlayLayout.name);
    await p.setInt('overlay_width_percent', overlayWidthPercent);
    await p.setInt('overlay_margin_percent', overlayMarginPercent);
    await p.setInt('overlay_opacity_percent', overlayOpacityPercent);
    await p.setBool('overlay_when_closed', overlayWhenClosed);
    await p.setBool('pickup_enabled', pickupEnabled);
    await p.setInt('pickup_seconds', pickupSeconds);
    await p.setBool('pickup_sound', pickupSound);
    await p.setInt('chime_volume_percent', chimeVolumePercent);
  }
}
