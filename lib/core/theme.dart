import 'package:flutter/material.dart';

/// Farben passend zu home.control / home_radio (gleiches Gruen wie order.manager).
const brandGreen = Color(0xFF2F9E5C);
const brandGreenDark = Color(0xFF1B6B3E);
const panelBackground = Color(0xFF141A22);
const tileBackground = Color(0xFF1E2630);
const accentAmber = Color(0xFFFFB300);

/// Farbe des Kuechenstatus (wie bisher im home_radio).
Color statusColor(String code) => switch (code) {
      'starter' => const Color(0xFF2E7D32),
      'main' => const Color(0xFFE65100),
      'dessert' => const Color(0xFF6A1B9A),
      _ => const Color(0xFF616161),
    };

/// TV-optimiertes dunkles Theme (gleiche Basis wie home.control).
ThemeData buildTvTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorSchemeSeed: brandGreen,
    scaffoldBackgroundColor: Colors.black,
    visualDensity: VisualDensity.standard,
  );
  // Der hellere `primary`-Ton des Seeds ist als Fokusring auf Schwarz besser lesbar.
  final focusColor = base.colorScheme.primary;

  // Deutlicher Fokusrahmen fuer D-Pad-Bedienung vom Sofa aus.
  WidgetStateProperty<BorderSide?> focusBorder({double width = 3}) {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.focused)) {
        return BorderSide(color: focusColor, width: width);
      }
      return null;
    });
  }

  return base.copyWith(
    focusColor: focusColor,
    filledButtonTheme: FilledButtonThemeData(style: ButtonStyle(side: focusBorder())),
    outlinedButtonTheme: OutlinedButtonThemeData(style: ButtonStyle(side: focusBorder())),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        side: focusBorder(),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        side: focusBorder(width: 2),
        shape: const WidgetStatePropertyAll(CircleBorder()),
      ),
    ),
    listTileTheme: ListTileThemeData(
      selectedColor: focusColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
  );
}
