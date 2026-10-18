import 'package:flutter/material.dart';

/// جوهرة مرسومة بالكود: ألماسة زرقاء لامعة أو ياقوتة حمراء، بأوجه متدرجة وبريق.
class GemIcon extends StatelessWidget {
  final double size;
  final bool ruby;
  const GemIcon({super.key, this.size = 20, this.ruby = false});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size, size), painter: _GemPainter(ruby));
}

/// عدد مع أيقونة الجوهرة بجانبه.
class GemAmount extends StatelessWidget {
  final Object amount;
  final bool ruby;
  final double size;
  final TextStyle? style;
  const GemAmount(this.amount, {super.key, this.ruby = false, this.size = 16, this.style});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        GemIcon(size: size, ruby: ruby),
        const SizedBox(width: 4),
        Text('$amount', style: style),
      ]);
}

class _GemPainter extends CustomPainter {
  final bool ruby;
  _GemPainter(this.ruby);

  // أوجه الجوهرة: [إضاءة اليسار، الطاولة، اليمين، سفلي يسار، سفلي وسط، سفلي يمين]
  List<Color> get _c => ruby
      ? const [
          Color(0xFFFB7185), Color(0xFFFFD5DB), Color(0xFFE11D48),
          Color(0xFFBE123C), Color(0xFFF43F5E), Color(0xFF881337),
        ]
      : const [
          Color(0xFF38BDF8), Color(0xFFD9F5FF), Color(0xFF0EA5E9),
          Color(0xFF0284C7), Color(0xFF67E8F9), Color(0xFF075985),
        ];

  @override
  void paint(Canvas canvas, Size s) {
    Offset p(double x, double y) => Offset(x * s.width, y * s.height);
    final t1 = p(0.26, 0.10), t2 = p(0.74, 0.10);
    final l = p(0.0, 0.36), r = p(1.0, 0.36);
    final g1 = p(0.32, 0.36), g2 = p(0.68, 0.36);
    final bot = p(0.5, 0.97);

    // توهّج خفيف خلف الجوهرة
    canvas.drawCircle(
      p(0.5, 0.55),
      s.width * 0.46,
      Paint()
        ..color = _c[4].withValues(alpha: 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s.width * 0.12),
    );

    void facet(List<Offset> pts, Color a, [Color? b]) {
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final o in pts.skip(1)) {
        path.lineTo(o.dx, o.dy);
      }
      path.close();
      final rect = path.getBounds();
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color.lerp(a, Colors.white, 0.25)!, b ?? a],
          ).createShader(rect),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s.width * 0.025
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white.withValues(alpha: 0.55),
      );
    }

    facet([l, t1, g1], _c[0]);
    facet([t1, t2, g2, g1], _c[1], _c[0]);
    facet([t2, r, g2], _c[2]);
    facet([l, g1, bot], _c[3]);
    facet([g1, g2, bot], _c[4], _c[3]);
    facet([g2, r, bot], _c[5], _c[2]);

    // بريق صغير
    final c = p(0.30, 0.20);
    final k = s.width * 0.11;
    final star = Path()
      ..moveTo(c.dx, c.dy - k)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + k, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + k)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - k, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - k)
      ..close();
    canvas.drawPath(star, Paint()..color = Colors.white.withValues(alpha: 0.95));
  }

  @override
  bool shouldRepaint(covariant _GemPainter old) => old.ruby != ruby;
}
