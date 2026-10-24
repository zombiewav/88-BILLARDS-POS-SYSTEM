import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../theme.dart';

/// The design's panel: card color, 1 px border, 18 px corners.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.borderColor,
    this.color,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(color: borderColor ?? c.border, width: borderColor == null ? 1 : 1.5),
    );
    return Material(
      color: color ?? c.card,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

/// "● Playing": a dot and a label in a soft pill.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color, this.dot = true});

  final String label;
  final Color color;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: c.isDark ? c.bg : color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: c.isDark ? null : Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
          ],
          Text(label,
              style: TextStyle(
                  fontFamily: 'Barlow', fontSize: 13, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

/// A filter chip: pill with a border, gold when selected (or [tone] when given).
class PillChip extends StatelessWidget {
  const PillChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.tone,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Overrides gold, e.g. coral for "Ending soon" or red for a void reason.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final accent = tone ?? c.gold;
    final active = selected;
    return Material(
      color: active ? (tone == null ? c.goldTint : accent.withValues(alpha: 0.14)) : c.card,
      shape: StadiumBorder(
        side: BorderSide(color: active || tone != null ? accent : c.border, width: 1.2),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Barlow',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: active || tone != null ? accent : c.text,
            ),
          ),
        ),
      ),
    );
  }
}

/// Thin progress bar (time used on a table).
class ThinBar extends StatelessWidget {
  const ThinBar({super.key, required this.value, required this.color, this.height = 8});

  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1),
        minHeight: height,
        color: color,
        backgroundColor: context.c.track,
      ),
    );
  }
}

/// A page title in the condensed face, with an optional muted note beside it.
class PageTitle extends StatelessWidget {
  const PageTitle(this.title, {super.key, this.note});

  final String title;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: condensed(44, color: c.text)),
        if (note != null) ...[
          const SizedBox(width: 12),
          Text(note!, style: TextStyle(fontFamily: 'Barlow', fontSize: 15, color: c.muted)),
        ],
      ],
    );
  }
}

/// "Bill · T4" style card title.
class CardTitle extends StatelessWidget {
  const CardTitle(this.title, {super.key, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      children: [
        Text(title, style: condensed(28, color: c.text)),
        const Spacer(),
        if (trailing != null)
          Text(trailing!, style: TextStyle(fontFamily: 'Barlow', fontSize: 14, color: c.muted)),
      ],
    );
  }
}

/// A coloured full-width notice, like the "ending soon" or "low stock" banners.
class Banner2 extends StatelessWidget {
  const Banner2({super.key, required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: c.isDark ? c.coralTint : color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 14),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontFamily: 'Barlow',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: c.isDark ? color : c.text)),
          ),
        ],
      ),
    );
  }
}

/// Grey label over a value, used in summaries.
class SummaryRow extends StatelessWidget {
  const SummaryRow(this.label, this.value, {super.key, this.bold = true});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontFamily: 'Barlow', fontSize: 15, color: c.muted)),
          Text(value,
              style: TextStyle(
                  fontFamily: 'Barlow',
                  fontSize: 16,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                  color: c.text)),
        ],
      ),
    );
  }
}
