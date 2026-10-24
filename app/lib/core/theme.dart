import 'package:flutter/material.dart';

import '../domain/enums.dart';
import 'app_colors.dart';

const _body = 'Barlow';
const _display = 'BarlowCondensed';

/// Big numbers and headings use the condensed face, like the design.
TextStyle condensed(double size, {FontWeight weight = FontWeight.w700, Color? color}) {
  return TextStyle(
    fontFamily: _display,
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: 1.05,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? AppColors.dark : AppColors.light;
  final radius = BorderRadius.circular(12);

  final textTheme = TextTheme(
    displayLarge: condensed(96, color: c.text),
    displayMedium: condensed(72, color: c.text),
    displaySmall: condensed(56, color: c.text),
    headlineLarge: condensed(44, color: c.text),
    headlineMedium: condensed(36, color: c.text),
    headlineSmall: condensed(30, color: c.text),
    titleLarge: condensed(26, color: c.text),
    titleMedium: TextStyle(
        fontFamily: _body, fontSize: 18, fontWeight: FontWeight.w600, color: c.text),
    titleSmall: TextStyle(
        fontFamily: _body, fontSize: 15, fontWeight: FontWeight.w600, color: c.text),
    bodyLarge: TextStyle(fontFamily: _body, fontSize: 16, color: c.text),
    bodyMedium: TextStyle(fontFamily: _body, fontSize: 14, color: c.text),
    bodySmall: TextStyle(fontFamily: _body, fontSize: 12, color: c.muted),
    labelLarge: TextStyle(
        fontFamily: _body, fontSize: 14, fontWeight: FontWeight.w600, color: c.muted),
    labelMedium: TextStyle(
        fontFamily: _body, fontSize: 13, fontWeight: FontWeight.w600, color: c.muted),
    labelSmall: TextStyle(
        fontFamily: _body, fontSize: 11, fontWeight: FontWeight.w600, color: c.muted),
  );

  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.gold,
    onPrimary: c.onGold,
    secondary: c.blue,
    onSecondary: c.bg,
    error: c.red,
    onError: c.bg,
    surface: c.card,
    onSurface: c.text,
    onSurfaceVariant: c.muted,
    surfaceContainerHighest: c.raised,
    outline: c.border,
    outlineVariant: c.border,
  );

  final buttonShape = RoundedRectangleBorder(borderRadius: radius);
  final buttonText = TextStyle(fontFamily: _body, fontSize: 16, fontWeight: FontWeight.w600);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: _body,
    textTheme: textTheme,
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    dividerColor: c.border,
    dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
    extensions: [c],
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      foregroundColor: c.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: condensed(36, color: c.text),
    ),
    cardTheme: CardThemeData(
      color: c.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: c.border),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: c.border),
      ),
      titleTextStyle: condensed(30, color: c.text),
      contentTextStyle: TextStyle(fontFamily: _body, fontSize: 15, color: c.muted),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: c.input,
      labelStyle: TextStyle(fontFamily: _body, color: c.muted),
      hintStyle: TextStyle(fontFamily: _body, color: c.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c.border)),
      enabledBorder:
          OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c.border)),
      focusedBorder:
          OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c.gold)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.gold,
        foregroundColor: c.onGold,
        disabledBackgroundColor: c.raised,
        disabledForegroundColor: c.muted,
        minimumSize: const Size(64, 52),
        shape: buttonShape,
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.text,
        backgroundColor: c.raised,
        side: BorderSide(color: c.border),
        minimumSize: const Size(64, 48),
        shape: buttonShape,
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.text,
        shape: buttonShape,
        textStyle: buttonText,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: c.text),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: c.card,
        foregroundColor: c.muted,
        selectedBackgroundColor: c.selected,
        selectedForegroundColor: c.gold,
        side: BorderSide(color: c.border),
        textStyle: buttonText,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.red : Colors.transparent),
      checkColor: WidgetStatePropertyAll(c.bg),
      side: BorderSide(color: c.muted, width: 1.5),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStatePropertyAll(c.isDark ? c.bg : Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.green : c.raised),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.raised,
      contentTextStyle: TextStyle(fontFamily: _body, fontSize: 15, color: c.text),
      behavior: SnackBarBehavior.floating,
      shape: buttonShape,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: c.gold,
      unselectedLabelColor: c.muted,
      indicatorColor: c.gold,
      dividerColor: c.border,
      labelStyle: buttonText,
      unselectedLabelStyle: buttonText,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.gold),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: c.raised, borderRadius: BorderRadius.circular(8)),
      textStyle: TextStyle(fontFamily: _body, color: c.text),
    ),
  );
}

extension PlayModeLabel on PlayMode {
  String get label => switch (this) {
        PlayMode.time => 'Time',
        PlayMode.game => 'Game',
        PlayMode.race => 'Race',
      };
}

extension TableStatusStyle on TableStatus {
  String get label => switch (this) {
        TableStatus.free => 'Free',
        TableStatus.playing => 'Playing',
        TableStatus.endingSoon => 'Ending soon',
        TableStatus.waitingToPay => 'Waiting to pay',
      };

  /// The status color for the current theme.
  Color colorIn(AppColors c) => switch (this) {
        TableStatus.free => c.green,
        TableStatus.playing => c.blue,
        TableStatus.endingSoon => c.coral,
        TableStatus.waitingToPay => c.red,
      };

  /// Legacy dark-palette color for screens not yet moved to [colorIn].
  Color get color => colorIn(AppColors.dark);
}
