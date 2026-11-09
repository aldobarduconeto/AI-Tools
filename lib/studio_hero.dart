import 'dart:math' as math;

import 'package:flutter/material.dart';

class StudioHero extends StatelessWidget {
  const StudioHero({
    super.key,
    required this.title,
    required this.description,
    required this.index,
    required this.accent,
    this.label,
  });

  final String title, description;
  final int index;
  final Color accent;
  final String? label;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(28),
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(accent, Colors.white, .22)!, accent],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ExcludeSemantics(
              child: CustomPaint(painter: _StudioPattern(index)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 25, 28, 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0x20101512),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Text(
                      label ?? 'ESTÚDIO 0${index + 1}',
                      style: const TextStyle(
                        color: Color(0xff283026),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.6,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xff121612),
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    height: 1,
                    letterSpacing: -2.8,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  description,
                  style: const TextStyle(
                    color: Color(0xff283026),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _StudioPattern extends CustomPainter {
  const _StudioPattern(this.index);

  final int index;

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()
      ..color = const Color(0x25101512)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;
    final origin = Offset(size.width - 8, size.height * .28);
    final rotated = index == 1;
    if (rotated) {
      canvas.save();
      canvas.translate(origin.dx, origin.dy);
      canvas.rotate(math.pi / 4);
    }
    for (var ring = 0; ring < 9; ring++) {
      final radius = 24.0 + ring * 12;
      if (rotated) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCircle(center: Offset.zero, radius: radius),
            const Radius.circular(10),
          ),
          ink,
        );
      } else if (index == 2) {
        final path = Path();
        for (var x = 0; x <= 160; x += 4) {
          final y =
              origin.dy + (ring - 4) * 10 + math.sin(x / 15 + ring / 3) * 18;
          final dx = origin.dx - 150 + x;
          if (x == 0) {
            path.moveTo(dx, y);
          } else {
            path.lineTo(dx, y);
          }
        }
        canvas.drawPath(path, ink);
      } else {
        canvas.drawCircle(origin, radius, ink);
      }
    }
    if (rotated) canvas.restore();
  }

  @override
  bool shouldRepaint(_StudioPattern oldDelegate) => oldDelegate.index != index;
}
