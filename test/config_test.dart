import 'package:flutter_test/flutter_test.dart';
import 'package:order_manager_client/core/config.dart';

void main() {
  test('Sicherung: JSON enthaelt die komplette Konfiguration', () {
    final c = AppConfig()
      ..baseUrl = 'https://example.org'
      ..user = 'gast@example.org'
      ..password = 'geheim'
      ..pollSeconds = 15
      ..mode = DisplayMode.overlay
      ..launchOnBoot = true
      ..displayQrPercent = 60
      ..displayTextPercent = 140
      ..overlayPosition = OverlayPosition.topLeft
      ..overlayLayout = OverlayLayout.compact
      ..overlayOpacityPercent = 70
      ..pickupSound = false
      ..chimeVolumePercent = 40;

    final r = AppConfig.fromBackupJson(c.toBackupJson());
    expect(r.toMap(), c.toMap());
    expect(r.password, 'geheim');
    expect(r.mode, DisplayMode.overlay);
    expect(r.overlayLayout, OverlayLayout.compact);
  });

  test('Sicherung: Werte ausserhalb der Grenzen werden begrenzt', () {
    final r = AppConfig.fromBackupJson(
        '{"app":"order_manager_client","format":1,"config":{"poll_seconds":1,"display_qr_percent":"x"}}');
    expect(r.pollSeconds, 5);
    expect(r.displayQrPercent, 100);
    expect(r.baseUrl, AppConfig.defaultBaseUrl);
  });

  test('Sicherung: fremde Dateien werden abgelehnt', () {
    expect(() => AppConfig.fromBackupJson('{"foo": 1}'), throwsFormatException);
    expect(() => AppConfig.fromBackupJson('{"app":"home_control","format":1,"config":{}}'), throwsFormatException);
    expect(() => AppConfig.fromBackupJson('{"app":"order_manager_client","format":99,"config":{}}'),
        throwsFormatException);
  });
}
