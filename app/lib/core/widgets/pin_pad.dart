import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../theme.dart';

const pinLength = 6;

/// Six dots that fill as digits are typed.
class PinDots extends StatelessWidget {
  const PinDots({super.key, required this.filled, this.error = false});

  final int filled;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final color = error ? c.red : c.text;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < pinLength; i++)
          Container(
            width: 16,
            height: 16,
            margin: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < filled ? color : Colors.transparent,
              border: Border.all(color: i < filled ? color : c.muted, width: 1.5),
            ),
          ),
      ],
    );
  }
}

/// 3 x 4 keypad: 1-9, then a gap, 0 and backspace.
class PinPad extends StatelessWidget {
  const PinPad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.keyHeight = 74,
    this.maxWidth = 400,
  });

  final ValueChanged<int> onDigit;
  final VoidCallback onBackspace;
  final double keyHeight;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    Widget key(Widget child, VoidCallback onTap) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Material(
              color: c.raised,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: c.border),
              ),
              child: InkWell(
                customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                onTap: onTap,
                child: SizedBox(height: keyHeight, child: Center(child: child)),
              ),
            ),
          ),
        );

    Widget digit(int n) =>
        key(Text('$n', style: condensed(34, color: c.text)), () => onDigit(n));

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in const [
            [1, 2, 3],
            [4, 5, 6],
            [7, 8, 9],
          ])
            Row(children: [for (final n in row) digit(n)]),
          Row(
            children: [
              const Expanded(child: SizedBox()),
              digit(0),
              key(Icon(Icons.backspace_outlined, color: c.text, size: 28), onBackspace),
            ],
          ),
        ],
      ),
    );
  }
}
