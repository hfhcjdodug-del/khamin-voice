import 'dart:math' as math;

import 'package:flutter/material.dart';

/// إطار الترند: حلقة ذهبية متوهجة مع تاج صغير، يُرسم برمجياً (بلا صور).
/// يظهر حول صورة صاحب الروم الترند.
class TrendFrame extends StatelessWidget {
  final Widget child;
  final double size;
  final int rank; // 1 أو 2 أو 3 (يغيّر اللون)
  const TrendFrame({super.key, required this.child, required this.size, this.rank = 1});

  static List<Color> colorsOf(int rank) {
    switch (rank) {
      case 2:
        return const [Color(0xFFE5E7EB), Color(0xFF9CA3AF), Color(0xFFF3F4F6)];
      case 3:
        return const [Color(0xFFFDBA74), Color(0xFFB45309), Color(0xFFFED7AA)];
      default:
        return const [Color(0xFFFDE047), Color(0xFFF59E0B), Color(0xFFFFF7AE), Color(0xFFEF4444)];
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = size * 0.14;
    final total = size + pad * 2;
    return SizedBox(
      width: total,
      height: total + size * 0.1,
      child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
        Positioned(
          top: size * 0.1,
          child: SizedBox(
            width: total,
            height: total,
            child: CustomPaint(painter: _RingPainter(colorsOf(rank)), child: Center(child: child)),
          ),
        ),
        Positioned(top: 0, child: CustomPaint(size: Size(size * 0.5, size * 0.3), painter: _CrownPainter(colorsOf(rank)))),
      ]),
    );
  }
}

class _RingPainter extends CustomPainter {
  final List<Color> colors;
  _RingPainter(this.colors);

  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    final r = s.width / 2 - s.width * 0.06;
    final glow = Paint()
      ..color = colors[1].withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.width * 0.10
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, s.width * 0.05);
    canvas.drawCircle(c, r, glow);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.width * 0.07
      ..shader = SweepGradient(colors: [...colors, colors.first]).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, ring);
    // نقاط لامعة صغيرة حول الحلقة
    final dot = Paint()..color = Colors.white.withValues(alpha: 0.9);
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4 + 0.4;
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * r, s.width * 0.016, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.colors != colors;
}

class _CrownPainter extends CustomPainter {
  final List<Color> colors;
  _CrownPainter(this.colors);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final path = Path()
      ..moveTo(0, h)
      ..lineTo(0, h * 0.25)
      ..lineTo(w * 0.25, h * 0.6)
      ..lineTo(w * 0.5, 0)
      ..lineTo(w * 0.75, h * 0.6)
      ..lineTo(w, h * 0.25)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [colors[0], colors[1]])
              .createShader(Rect.fromLTWH(0, 0, w, h)));
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: 0.7));
  }

  @override
  bool shouldRepaint(covariant _CrownPainter old) => old.colors != colors;
}
