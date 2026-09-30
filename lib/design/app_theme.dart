import 'package:flutter/material.dart';

ThemeData buildAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  Color choose(int light, int night) => Color(dark ? night : light);
  final surface = choose(0xFFFFF9F0, 0xFF181C20);
  final container = choose(0xFFF3E8D7, 0xFF252B32);
  final ink = choose(0xFF24211E, 0xFFF7F1E7);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF8D5524),
        brightness: brightness,
      ).copyWith(
        surface: surface,
        surfaceContainer: container,
        surfaceContainerLow: container,
        surfaceContainerHigh: container,
        surfaceContainerHighest: container,
        onSurface: ink,
        onSurfaceVariant: choose(0xFF51483E, 0xFFCFC6B8),
        primary: choose(0xFF74451E, 0xFFF0BD86),
        onPrimary: choose(0xFFFFFFFF, 0xFF302012),
        primaryContainer: container,
        onPrimaryContainer: ink,
        error: choose(0xFFA52D26, 0xFFFFB4AB),
        errorContainer: container,
        onError: choose(0xFFFFFFFF, 0xFF302012),
        onErrorContainer: choose(0xFFA52D26, 0xFFFFB4AB),
        outline: choose(0xFF756B60, 0xFFA69B8B),
        outlineVariant: choose(0xFFD8CDBD, 0xFF4B535D),
      );
  TextStyle type(double size, double height, {bool bold = true}) => TextStyle(
    fontFamily: 'NotoSansJP',
    fontSize: size,
    height: height,
    fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
    letterSpacing: 0,
    color: ink,
  );
  const shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(12)),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: surface,
    fontFamily: 'NotoSansJP',
    textTheme: TextTheme(
      displayLarge: type(32, 1.25),
      displayMedium: type(28, 1.25),
      displaySmall: type(24, 1.25),
      headlineLarge: type(28, 1.3),
      headlineMedium: type(24, 1.3),
      headlineSmall: type(22, 1.3),
      titleLarge: type(20, 1.4),
      titleMedium: type(16, 1.4),
      titleSmall: type(14, 1.4),
      bodyLarge: type(16, 1.5, bold: false),
      bodyMedium: type(14, 1.5, bold: false),
      bodySmall: type(12, 1.5, bold: false),
      labelLarge: type(14, 1.4),
      labelMedium: type(12, 1.4),
      labelSmall: type(12, 1.4),
    ),
    appBarTheme: AppBarTheme(
      toolbarHeight: 48,
      backgroundColor: surface,
      foregroundColor: ink,
      scrolledUnderElevation: 0,
      titleTextStyle: type(20, 1.4),
    ),
    cardTheme: CardThemeData(color: container, elevation: 0, shape: shape),
    listTileTheme: const ListTileThemeData(minTileHeight: 56),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: ink,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: shape,
        disabledBackgroundColor: container,
        disabledForegroundColor: ink,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: shape,
        foregroundColor: ink,
        disabledForegroundColor: ink,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: scheme.primary,
        disabledForegroundColor: ink,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    ),
  );
}
