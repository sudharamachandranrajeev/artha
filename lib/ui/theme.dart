import 'package:brahma_core/brahma_core.dart';
import 'package:flutter/material.dart';

/// The redesign's design tokens and palettes. See docs/ui-design-map.md for
/// the sampled values and the component contract this implements.

/// One palette at one brightness: the chromatic roles. Neutrals are shared
/// paper tones per brightness, so palettes only carry colour.
class ArthaPaletteMode {
  const ArthaPaletteMode({
    required this.primary,
    required this.deep,
    required this.soft,
    required this.onSoft,
    required this.series,
  });

  /// Icons, chart lines, badges, progress fills.
  final Color primary;

  /// Hero fills: feature cards and celebration banners.
  final Color deep;

  /// Icon-square tint, highlighted rows, progress tracks.
  final Color soft;
  final Color onSoft;

  /// Chart series slots: main, comparison, third, neutral.
  final List<Color> series;
}

class ArthaPalette {
  const ArthaPalette({
    required this.id,
    required this.name,
    required this.blurb,
    required this.light,
    required this.dark,
  });
  final String id;
  final String name;
  final String blurb;
  final ArthaPaletteMode light;
  final ArthaPaletteMode dark;

  ArthaPaletteMode mode(Brightness brightness) => brightness == Brightness.dark ? dark : light;
}

const arthaPalettes = <ArthaPalette>[
  ArthaPalette(
    id: 'indigo',
    name: 'Indigo Paper',
    blurb: 'The reference look: paper grey, indigo and sky.',
    light: ArthaPaletteMode(
      primary: Color(0xFF2C1CD1),
      deep: Color(0xFF0000C6),
      soft: Color(0xFFC8E6FE),
      onSoft: Color(0xFF2C1CD1),
      series: [Color(0xFF2C1CD1), Color(0xFF7FB8E8), Color(0xFF0000C6), Color(0xFF8A8A8A)],
    ),
    dark: ArthaPaletteMode(
      primary: Color(0xFF6E5BFF),
      deep: Color(0xFF3B2BD6),
      soft: Color(0xFF12344F),
      onSoft: Color(0xFF8FC7F2),
      series: [Color(0xFF6E5BFF), Color(0xFF4E8FC4), Color(0xFF8B8BFF), Color(0xFF9A9AA2)],
    ),
  ),
  ArthaPalette(
    id: 'emerald',
    name: 'Emerald Classic',
    blurb: 'Artha’s first brand: emerald with a gold accent.',
    light: ArthaPaletteMode(
      primary: Color(0xFF047857),
      deep: Color(0xFF065F46),
      soft: Color(0xFFCDEEDB),
      onSoft: Color(0xFF047857),
      series: [Color(0xFF047857), Color(0xFFC9A227), Color(0xFF0E9F6E), Color(0xFF8A8A8A)],
    ),
    dark: ArthaPaletteMode(
      primary: Color(0xFF34D399),
      deep: Color(0xFF059669),
      soft: Color(0xFF0E3B2E),
      onSoft: Color(0xFF6EE7B7),
      series: [Color(0xFF34D399), Color(0xFFE3C34E), Color(0xFF059669), Color(0xFF9A9AA2)],
    ),
  ),
  ArthaPalette(
    id: 'ocean',
    name: 'Ocean',
    blurb: 'Deep sea blues with a cyan current.',
    light: ArthaPaletteMode(
      primary: Color(0xFF0369A1),
      deep: Color(0xFF075985),
      soft: Color(0xFFC8E6FE),
      onSoft: Color(0xFF0369A1),
      series: [Color(0xFF0369A1), Color(0xFF7FB8E8), Color(0xFF0E7490), Color(0xFF8A8A8A)],
    ),
    dark: ArthaPaletteMode(
      primary: Color(0xFF38BDF8),
      deep: Color(0xFF0284C7),
      soft: Color(0xFF0C2F45),
      onSoft: Color(0xFF7DD3FC),
      series: [Color(0xFF38BDF8), Color(0xFF22D3EE), Color(0xFF0EA5E9), Color(0xFF9A9AA2)],
    ),
  ),
  ArthaPalette(
    id: 'rose',
    name: 'Rose',
    blurb: 'Warm crimson with a blush tint.',
    light: ArthaPaletteMode(
      primary: Color(0xFFBE123C),
      deep: Color(0xFF9F1239),
      soft: Color(0xFFFBDCE3),
      onSoft: Color(0xFFBE123C),
      series: [Color(0xFFBE123C), Color(0xFFFB7185), Color(0xFF9F1239), Color(0xFF8A8A8A)],
    ),
    dark: ArthaPaletteMode(
      primary: Color(0xFFFB7185),
      deep: Color(0xFFE11D48),
      soft: Color(0xFF451523),
      onSoft: Color(0xFFFDA4AF),
      series: [Color(0xFFFB7185), Color(0xFFF472B6), Color(0xFFE11D48), Color(0xFF9A9AA2)],
    ),
  ),
];

/// Neutral paper tones per brightness, shared by every palette.
class _Paper {
  const _Paper({
    required this.canvas,
    required this.surface,
    required this.surfaceSoft,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.track,
    required this.hairline,
    required this.good,
  });
  final Color canvas;
  final Color surface;
  final Color surfaceSoft;
  final Color ink;
  final Color muted;
  final Color faint;
  final Color track;
  final Color hairline;
  final Color good;

  static const light = _Paper(
    canvas: Color(0xFFF2F2F2),
    surface: Color(0xFFFFFFFF),
    surfaceSoft: Color(0xFFF7F7F7),
    ink: Color(0xFF0A0A0A),
    muted: Color(0xFF8A8A8A),
    faint: Color(0xFFB9B9B9),
    track: Color(0xFFE4E4E4),
    hairline: Color(0xFFECECEC),
    good: Color(0xFF0B7A3E),
  );
  static const dark = _Paper(
    canvas: Color(0xFF121212),
    surface: Color(0xFF1C1C1F),
    surfaceSoft: Color(0xFF242428),
    ink: Color(0xFFF4F4F5),
    muted: Color(0xFF9A9AA2),
    faint: Color(0xFF6E6E76),
    track: Color(0xFF2E2E33),
    hairline: Color(0xFF26262B),
    good: Color(0xFF4CC38A),
  );
}

/// Tokens beyond Material's roles: canvas, captions, tracks and chart series.
class ArthaSkin extends ThemeExtension<ArthaSkin> {
  const ArthaSkin({
    required this.canvas,
    required this.surfaceSoft,
    required this.muted,
    required this.faint,
    required this.track,
    required this.hairline,
    required this.primaryDeep,
    required this.soft,
    required this.onSoft,
    required this.series,
    required this.good,
  });

  final Color canvas;
  final Color surfaceSoft;
  final Color muted;
  final Color faint;
  final Color track;
  final Color hairline;
  final Color primaryDeep;
  final Color soft;
  final Color onSoft;
  final List<Color> series;

  /// Income green, always shown with an icon too.
  final Color good;

  static ArthaSkin of(BuildContext context) => Theme.of(context).extension<ArthaSkin>()!;

  @override
  ArthaSkin copyWith({
    Color? canvas,
    Color? surfaceSoft,
    Color? muted,
    Color? faint,
    Color? track,
    Color? hairline,
    Color? primaryDeep,
    Color? soft,
    Color? onSoft,
    List<Color>? series,
    Color? good,
  }) => ArthaSkin(
    canvas: canvas ?? this.canvas,
    surfaceSoft: surfaceSoft ?? this.surfaceSoft,
    muted: muted ?? this.muted,
    faint: faint ?? this.faint,
    track: track ?? this.track,
    hairline: hairline ?? this.hairline,
    primaryDeep: primaryDeep ?? this.primaryDeep,
    soft: soft ?? this.soft,
    onSoft: onSoft ?? this.onSoft,
    series: series ?? this.series,
    good: good ?? this.good,
  );

  @override
  ArthaSkin lerp(ArthaSkin? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return ArthaSkin(
      canvas: l(canvas, other.canvas),
      surfaceSoft: l(surfaceSoft, other.surfaceSoft),
      muted: l(muted, other.muted),
      faint: l(faint, other.faint),
      track: l(track, other.track),
      hairline: l(hairline, other.hairline),
      primaryDeep: l(primaryDeep, other.primaryDeep),
      soft: l(soft, other.soft),
      onSoft: l(onSoft, other.onSoft),
      series: t < 0.5 ? series : other.series,
      good: l(good, other.good),
    );
  }
}

TextStyle _t(double size, FontWeight weight, Color color, {double? letterSpacing}) =>
    TextStyle(fontSize: size, fontWeight: weight, color: color, letterSpacing: letterSpacing, height: 1.25);

TextTheme _textTheme(_Paper p) => TextTheme(
  displayLarge: _t(40, FontWeight.w700, p.ink),
  displayMedium: _t(34, FontWeight.w700, p.ink),
  displaySmall: _t(28, FontWeight.w700, p.ink),
  headlineLarge: _t(34, FontWeight.w700, p.ink),
  headlineMedium: _t(28, FontWeight.w700, p.ink, letterSpacing: -0.5),
  headlineSmall: _t(24, FontWeight.w700, p.ink),
  titleLarge: _t(18, FontWeight.w700, p.ink),
  titleMedium: _t(16, FontWeight.w700, p.ink),
  titleSmall: _t(14, FontWeight.w600, p.ink),
  bodyLarge: _t(14, FontWeight.w500, p.ink),
  bodyMedium: _t(13, FontWeight.w500, p.ink),
  bodySmall: _t(12, FontWeight.w500, p.muted),
  labelLarge: _t(13, FontWeight.w600, p.ink),
  labelMedium: _t(12, FontWeight.w600, p.ink),
  labelSmall: _t(11, FontWeight.w600, p.muted),
);

/// The whole app skin for one palette at one brightness. Core widgets
/// (AppShell, PageScaffold, SectionCard, dialogs) restyle themselves from
/// this because they read Theme.of(context).
ThemeData buildArthaTheme(ArthaPalette palette, Brightness brightness) {
  final m = palette.mode(brightness);
  final p = brightness == Brightness.dark ? _Paper.dark : _Paper.light;
  final text = _textTheme(p);
  final scheme = (brightness == Brightness.dark ? ColorScheme.dark() : ColorScheme.light()).copyWith(
    primary: m.primary,
    onPrimary: const Color(0xFFFFFFFF),
    primaryContainer: m.soft,
    onPrimaryContainer: m.onSoft,
    secondary: m.deep,
    onSecondary: const Color(0xFFFFFFFF),
    secondaryContainer: m.soft,
    onSecondaryContainer: m.onSoft,
    tertiary: m.deep,
    onTertiary: const Color(0xFFFFFFFF),
    surface: p.surface,
    onSurface: p.ink,
    surfaceDim: p.canvas,
    surfaceBright: p.surface,
    surfaceContainerLowest: p.surface,
    surfaceContainerLow: p.surfaceSoft,
    surfaceContainer: p.surfaceSoft,
    surfaceContainerHigh: p.surfaceSoft,
    surfaceContainerHighest: p.track,
    onSurfaceVariant: p.muted,
    outline: p.hairline,
    outlineVariant: p.track,
    inverseSurface: p.ink,
    onInverseSurface: p.canvas,
    shadow: const Color(0x00000000),
  );
  final dark = brightness == Brightness.dark;
  final card20 = BorderRadius.circular(20);
  final stadium = const StadiumBorder();
  return ThemeData(
    colorScheme: scheme,
    brightness: brightness,
    fontFamily: 'Inter',
    textTheme: text,
    visualDensity: VisualDensity.standard,
    scaffoldBackgroundColor: p.canvas,
    canvasColor: p.canvas,
    dividerColor: p.hairline,
    splashFactory: InkRipple.splashFactory,
    pageTransitionsTheme: Motion.pageTransitions,
    cardTheme: CardThemeData(
      color: p.surface,
      surfaceTintColor: const Color(0x00000000),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: card20),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: p.canvas,
      surfaceTintColor: const Color(0x00000000),
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: false,
      titleSpacing: 16,
      toolbarHeight: 64,
      titleTextStyle: text.headlineMedium,
      iconTheme: IconThemeData(color: p.ink, size: 22),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: const Color(0x00000000),
      shadowColor: const Color(0x00000000),
      elevation: 0,
      height: 68,
      indicatorColor: m.soft,
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? p.ink : p.faint, size: 22),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? _t(11, FontWeight.w600, p.ink)
            : _t(11, FontWeight.w600, p.faint),
      ),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: p.canvas,
      elevation: 0,
      indicatorColor: m.soft,
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      selectedIconTheme: IconThemeData(color: m.onSoft, size: 22),
      unselectedIconTheme: IconThemeData(color: p.muted, size: 22),
      selectedLabelTextStyle: _t(12, FontWeight.w600, p.ink),
      unselectedLabelTextStyle: _t(12, FontWeight.w500, p.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.ink,
        foregroundColor: p.canvas,
        disabledBackgroundColor: p.track,
        disabledForegroundColor: p.muted,
        elevation: 0,
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: stadium,
        textStyle: _t(14, FontWeight.w600, p.canvas),
      ).merge(buttonDepth(stadium, m.primary.withValues(alpha: dark ? 0.55 : 0.35))),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: p.surface,
        foregroundColor: p.ink,
        side: BorderSide(color: p.hairline),
        elevation: 0,
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: stadium,
        textStyle: _t(14, FontWeight.w600, p.ink),
      ).merge(buttonDepth(stadium, const Color(0x33000000))),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: m.primary,
        elevation: 0,
        shape: stadium,
        textStyle: _t(13, FontWeight.w600, m.primary),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: p.ink, shape: const CircleBorder()),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: p.ink,
      foregroundColor: p.canvas,
      elevation: 3,
      focusElevation: 4,
      highlightElevation: 1,
      hoverElevation: 6,
      shape: stadium,
      extendedTextStyle: _t(14, FontWeight.w600, p.canvas),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surfaceSoft,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: m.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.error, width: 1.5),
      ),
      prefixIconColor: p.muted,
      suffixIconColor: p.muted,
      labelStyle: _t(13, FontWeight.w500, p.muted),
      floatingLabelStyle: _t(13, FontWeight.w600, m.primary),
      helperStyle: _t(12, FontWeight.w500, p.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      minLeadingWidth: 24,
      iconColor: p.muted,
      titleTextStyle: _t(14, FontWeight.w600, p.ink),
      subtitleTextStyle: _t(12, FontWeight.w500, p.muted),
      leadingAndTrailingTextStyle: _t(14, FontWeight.w700, p.ink),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide.none,
      backgroundColor: p.surfaceSoft,
      selectedColor: m.soft,
      checkmarkColor: m.onSoft,
      labelStyle: _t(12, FontWeight.w600, p.ink),
      secondaryLabelStyle: _t(12, FontWeight.w600, m.onSoft),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: stadium,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(stadium),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? m.soft : p.surface,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? m.onSoft : p.muted,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: p.hairline)),
        textStyle: WidgetStatePropertyAll(_t(13, FontWeight.w600, p.ink)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? m.primary : p.surface,
      ),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? m.soft : p.track),
      trackOutlineColor: const WidgetStatePropertyAll(Color(0x00000000)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: m.primary,
      circularTrackColor: p.track,
      linearTrackColor: p.track,
      linearMinHeight: 8,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: const Color(0x00000000),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: _t(18, FontWeight.w700, p.ink),
      contentTextStyle: _t(14, FontWeight.w500, p.ink),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: const Color(0x00000000),
      elevation: 0,
      dragHandleColor: p.track,
      modalBarrierColor: const Color(0x59000000),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.ink,
      contentTextStyle: _t(14, FontWeight.w500, p.canvas),
      actionTextColor: brightness == Brightness.dark ? m.primary : m.soft,
      closeIconColor: p.canvas,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: DividerThemeData(color: p.hairline, thickness: 1, space: 1),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 450),
      exitDuration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      textStyle: _t(12, FontWeight.w500, p.canvas),
      decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(10)),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(p.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Color(0x00000000)),
        elevation: WidgetStatePropertyAll(0),
        side: WidgetStatePropertyAll(BorderSide(color: p.hairline)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.surface,
      surfaceTintColor: const Color(0x00000000),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: _t(14, FontWeight.w500, p.ink),
    ),
    expansionTileTheme: ExpansionTileThemeData(
      backgroundColor: p.surface,
      collapsedBackgroundColor: p.surface,
      iconColor: m.primary,
      textColor: p.ink,
      shape: const Border(),
      collapsedShape: const Border(),
    ),
    extensions: [
      ArthaSkin(
        canvas: p.canvas,
        surfaceSoft: p.surfaceSoft,
        muted: p.muted,
        faint: p.faint,
        track: p.track,
        hairline: p.hairline,
        primaryDeep: m.deep,
        soft: m.soft,
        onSoft: m.onSoft,
        series: m.series,
        good: p.good,
      ),
    ],
  );
}

/// Gives a button depth: a soft shadow (a coloured glow on filled buttons)
/// that grows on hover and sinks on press, and a sheen from the top edge
/// that flips to a shade when pressed. Disabled buttons stay flat.
ButtonStyle buttonDepth(OutlinedBorder shape, Color shadow) => ButtonStyle(
  shadowColor: WidgetStatePropertyAll(shadow),
  elevation: WidgetStateProperty.resolveWith((s) {
    if (s.contains(WidgetState.disabled) || s.contains(WidgetState.pressed)) return 0;
    if (s.contains(WidgetState.hovered) || s.contains(WidgetState.focused)) return 5;
    return 2;
  }),
  animationDuration: Motion.short,
  backgroundBuilder: (context, states, child) {
    if (states.contains(WidgetState.disabled)) return child!;
    final pressed = states.contains(WidgetState.pressed);
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: pressed
              ? const [Color(0x14000000), Color(0x00000000)]
              : const [Color(0x1FFFFFFF), Color(0x00FFFFFF), Color(0x0F000000)],
        ),
      ),
      child: child,
    );
  },
);
