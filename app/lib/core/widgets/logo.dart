import 'package:flutter/material.dart';

import '../theme.dart';

/// The logo: a pool ball, the 8 ball. Same look as the app icon.
class Logo8 extends StatelessWidget {
  const Logo8({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The ball, a little lighter at the top left like it is under a lamp.
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                center: Alignment(-0.4, -0.45),
                radius: 1.0,
                colors: [Color(0xFF45484D), Color(0xFF111214), Color(0xFF050506)],
                stops: [0, 0.55, 1],
              ),
              border: Border.all(color: const Color(0xFFE9B94A).withValues(alpha: 0.9), width: size * 0.04),
            ),
          ),
          // The white number disc.
          Container(
            width: size * 0.52,
            height: size * 0.52,
            decoration: const BoxDecoration(color: Color(0xFFF4F4F2), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text('8', style: condensed(size * 0.4, color: const Color(0xFF0B0B0C))),
          ),
          // A small shine.
          Positioned(
            left: size * 0.2,
            top: size * 0.12,
            child: Container(
              width: size * 0.22,
              height: size * 0.12,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(size),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
