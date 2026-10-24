import 'package:flutter/material.dart';

import '../app_colors.dart';

/// "Slide to confirm payment": a deliberate second step, so a tap can't do it.
class SlideToConfirm extends StatefulWidget {
  const SlideToConfirm({super.key, required this.label, required this.onConfirmed});

  final String label;
  final VoidCallback onConfirmed;

  @override
  State<SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<SlideToConfirm> {
  static const _knob = 56.0;
  var _dx = 0.0;
  var _done = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LayoutBuilder(
      builder: (context, box) {
        final maxDx = box.maxWidth - _knob - 8;
        return Container(
          height: _knob + 8,
          decoration: BoxDecoration(
            color: c.isDark ? c.bg : c.raised,
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: c.border),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(left: _knob),
                  child: Text(widget.label,
                      style: TextStyle(
                          fontFamily: 'Barlow',
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: c.muted)),
                ),
              ),
              Positioned(
                left: 4 + _dx,
                child: GestureDetector(
                  onHorizontalDragUpdate: (d) {
                    if (_done) return;
                    setState(() => _dx = (_dx + d.delta.dx).clamp(0.0, maxDx));
                  },
                  onHorizontalDragEnd: (_) {
                    if (_done) return;
                    if (_dx >= maxDx * 0.9) {
                      setState(() {
                        _dx = maxDx;
                        _done = true;
                      });
                      widget.onConfirmed();
                    } else {
                      setState(() => _dx = 0);
                    }
                  },
                  child: Container(
                    width: _knob,
                    height: _knob,
                    decoration: BoxDecoration(color: c.gold, shape: BoxShape.circle),
                    child: Icon(Icons.arrow_forward, color: c.onGold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
