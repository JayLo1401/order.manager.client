import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'overlay/overlay_app.dart';
import 'settings/settings_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OrderClientApp());
}

/// Einstiegspunkt der Engine im Hintergrunddienst (siehe OrderOverlayService.kt).
@pragma('vm:entry-point')
Future<void> overlayMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OverlayApp());
}

class OrderClientApp extends StatelessWidget {
  const OrderClientApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Order Manager Client',
        debugShowCheckedModeBanner: false,
        theme: buildTvTheme(),
        home: const SettingsPage(openDisplayIfConfigured: true),
      );
}
