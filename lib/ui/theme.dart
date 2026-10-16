import 'package:flutter/material.dart';

/// Brand colours: emerald for the app, gold as the accent.
const emerald = Color(0xFF047857);
const gold = Color(0xFFC9A227);

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: emerald, brightness: brightness, tertiary: gold);
  final radius = BorderRadius.circular(16);
  final base = ThemeData(
    colorScheme: scheme,
    brightness: brightness,
    visualDensity: VisualDensity.standard,
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: radius),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
  // Text styles come from the theme's own text theme so they keep its fonts.
  final text = base.textTheme;
  return base.copyWith(
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 450),
      exitDuration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      textStyle: text.bodyMedium?.copyWith(color: scheme.onInverseSurface, height: 1.35),
      decoration: BoxDecoration(color: scheme.inverseSurface, borderRadius: BorderRadius.circular(10)),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      // Material 3 sets trailing text in labelSmall (11 px); amounts live
      // there, so use body size instead.
      leadingAndTrailingTextStyle: text.bodyLarge,
    ),
  );
}

/// Chart colours from the data-viz reference palette, fixed per slot so a
/// series keeps its colour whatever else is on screen.
class ChartColors {
  ChartColors._(this.series, this.grid, this.axis);

  factory ChartColors.of(BuildContext context) => Theme.of(context).brightness == Brightness.dark
      ? ChartColors._(_dark, const Color(0xFF2C2C2A), const Color(0xFF898781))
      : ChartColors._(_light, const Color(0xFFE1E0D9), const Color(0xFF898781));

  final List<Color> series;
  final Color grid;
  final Color axis;

  static const _light = [
    Color(0xFF2A78D6),
    Color(0xFFEB6834),
    Color(0xFF1BAF7A),
    Color(0xFFEDA100),
    Color(0xFFE87BA4),
    Color(0xFF008300),
    Color(0xFF6250D6),
    Color(0xFFE34948),
  ];
  static const _dark = [
    Color(0xFF3987E5),
    Color(0xFFD95926),
    Color(0xFF199E70),
    Color(0xFFC98500),
    Color(0xFFD55181),
    Color(0xFF008300),
    Color(0xFF9085E9),
    Color(0xFFE66767),
  ];

  /// Asset classes in a fixed slot order (see portfolio.dart).
  static const classOrder = ['equity', 'bond', 'cash', 'property', 'commodity', 'crypto', 'alternative'];

  Color forClass(String assetClass) {
    final i = classOrder.indexOf(assetClass);
    return series[i < 0 ? classOrder.length - 1 : i];
  }
}

/// Status colours, never reused for series; always shown with an icon.
class StatusColors {
  static const good = Color(0xFF0CA30C);
  static const warning = Color(0xFFFAB219);
  static const serious = Color(0xFFEC835A);
  static const critical = Color(0xFFD03B3B);
}
