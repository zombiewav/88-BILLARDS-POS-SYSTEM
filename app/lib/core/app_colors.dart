import 'package:flutter/material.dart';

/// The design's colors, sampled from the PDF. One set per theme; read them with
/// `context.c` instead of hard-coding colors in screens.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.card,
    required this.border,
    required this.raised,
    required this.selected,
    required this.input,
    required this.track,
    required this.text,
    required this.muted,
    required this.gold,
    required this.onGold,
    required this.goldTint,
    required this.blue,
    required this.green,
    required this.coral,
    required this.coralTint,
    required this.red,
  });

  final Brightness brightness;

  /// Page background.
  final Color bg;

  /// Top bar and left rail.
  final Color surface;
  final Color card;
  final Color border;

  /// Secondary buttons and keypad keys.
  final Color raised;

  /// Selected rail item.
  final Color selected;

  /// Text field fill.
  final Color input;

  /// Empty part of a progress bar.
  final Color track;
  final Color text;
  final Color muted;

  /// Primary accent: buttons, prices, selected chips.
  final Color gold;
  final Color onGold;
  final Color goldTint;

  /// Playing.
  final Color blue;

  /// Free, OK, profit.
  final Color green;

  /// Ending soon, low stock.
  final Color coral;
  final Color coralTint;

  /// End table, void, expenses.
  final Color red;

  bool get isDark => brightness == Brightness.dark;

  static const dark = AppColors(
    brightness: Brightness.dark,
    bg: Color(0xFF0E1412),
    surface: Color(0xFF111A15),
    card: Color(0xFF15201A),
    border: Color(0xFF25312A),
    raised: Color(0xFF1D2A23),
    selected: Color(0xFF1F3B2F),
    input: Color(0xFF0E1412),
    track: Color(0xFF0E1412),
    text: Color(0xFFF2F7F4),
    muted: Color(0xFF8B9A92),
    gold: Color(0xFFE9B94A),
    onGold: Color(0xFF1A1405),
    goldTint: Color(0xFF2B2411),
    blue: Color(0xFF5CA8FE),
    green: Color(0xFF4FCF8C),
    coral: Color(0xFFFD8B59),
    coralTint: Color(0xFF28130F),
    red: Color(0xFFFF6B6B),
  );

  static const light = AppColors(
    brightness: Brightness.light,
    bg: Color(0xFFF4F6F5),
    surface: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    border: Color(0xFFDCE5E0),
    raised: Color(0xFFE8EEEA),
    selected: Color(0xFFDBEBE1),
    input: Color(0xFFF1F4F2),
    track: Color(0xFFE8EEEA),
    text: Color(0xFF0F1A14),
    muted: Color(0xFF727D79),
    gold: Color(0xFF8F6300),
    onGold: Color(0xFFFFFFFF),
    goldTint: Color(0xFFFBF1D6),
    blue: Color(0xFF1C62B9),
    green: Color(0xFF0F7A4B),
    coral: Color(0xFFB84319),
    coralTint: Color(0xFFFDE8E0),
    red: Color(0xFFC62828),
  );

  @override
  AppColors copyWith() => this;

  /// Blends every color, so switching dark and light fades instead of snapping.
  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      bg: mix(bg, other.bg),
      surface: mix(surface, other.surface),
      card: mix(card, other.card),
      border: mix(border, other.border),
      raised: mix(raised, other.raised),
      selected: mix(selected, other.selected),
      input: mix(input, other.input),
      track: mix(track, other.track),
      text: mix(text, other.text),
      muted: mix(muted, other.muted),
      gold: mix(gold, other.gold),
      onGold: mix(onGold, other.onGold),
      goldTint: mix(goldTint, other.goldTint),
      blue: mix(blue, other.blue),
      green: mix(green, other.green),
      coral: mix(coral, other.coral),
      coralTint: mix(coralTint, other.coralTint),
      red: mix(red, other.red),
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColors get c => Theme.of(this).extension<AppColors>()!;
}
