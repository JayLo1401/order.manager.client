import 'package:flutter/services.dart';

/// Kanal zur Android-Seite der App (MainActivity): Hintergrunddienst, Display, Gong.
class NativeBridge {
  static const _ch = MethodChannel('order_manager_client/native');

  static Future<bool> isServiceEnabled() async => await _ch.invokeMethod<bool>('isServiceEnabled') ?? false;

  /// Hat die App per adb WRITE_SECURE_SETTINGS (Dienst kann sich selbst wieder einschalten)?
  static Future<bool> canAutoEnable() async => await _ch.invokeMethod<bool>('canAutoEnable') ?? false;

  static Future<void> openAccessibilitySettings() => _ch.invokeMethod('openAccessibilitySettings');

  /// Einblendungs-Dienst laedt die Einstellungen neu.
  static Future<void> reloadOverlayConfig() => _ch.invokeMethod('reloadOverlayConfig');

  /// Einblendung fuer einige Sekunden zur Probe zeigen; `false`, wenn der Dienst nicht laeuft.
  static Future<bool> previewOverlay() async => await _ch.invokeMethod<bool>('previewOverlay') ?? false;

  /// „Bitte abholen“ ueber den Dienst testen; `false`, wenn der Dienst nicht laeuft.
  static Future<bool> testPickup() async => await _ch.invokeMethod<bool>('testPickup') ?? false;

  /// Display bleibt an (FLAG_KEEP_SCREEN_ON), solange die Anzeige offen ist.
  static Future<void> setKeepScreenOn(bool on) => _ch.invokeMethod('setKeepScreenOn', {'on': on});

  /// Gong mit kurzem Leiserstellen anderer Wiedergabe (Audio-Ducking).
  static Future<void> playChime({double volume = 1}) => _ch.invokeMethod('playChime', {'volume': volume});

  /// Link im Browser oeffnen; `false`, wenn kein Browser vorhanden ist.
  static Future<bool> openUrl(String url) async => await _ch.invokeMethod<bool>('openUrl', {'url': url}) ?? false;

  static Future<Map<String, String>> deviceInfo() async =>
      (await _ch.invokeMethod<Map>('deviceInfo') ?? {}).map((k, v) => MapEntry('$k', '${v ?? ''}'));
}
