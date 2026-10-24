import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../theme.dart';

/// One step of the double-confirmation: "STEP 1 OF 2", a big title, then the content.
/// Shown inside a dialog; [danger] turns the border and label red (End table).
class StepCard extends StatelessWidget {
  const StepCard({
    super.key,
    required this.step,
    required this.title,
    required this.child,
    this.danger = false,
    this.width = 400,
  });

  final String step;
  final String title;
  final Widget child;
  final bool danger;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final accent = danger ? c.red : c.gold;
    return Dialog(
      backgroundColor: c.card,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: danger ? c.red.withValues(alpha: 0.8) : c.border, width: danger ? 1.5 : 1),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(step,
                  style: TextStyle(
                      fontFamily: 'Barlow',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.6,
                      color: accent)),
              const SizedBox(height: 10),
              Text(title, style: condensed(36, color: c.text)),
              const SizedBox(height: 14),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
