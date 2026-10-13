import 'package:flutter/material.dart';

class C {
  static const bg1 = Color(0xFF150B30);
  static const bg2 = Color(0xFF0A1030);
  static const violet = Color(0xFF8B5CF6);
  static const pink = Color(0xFFEC4899);
  static const cyan = Color(0xFF22D3EE);
  static const green = Color(0xFF34D399);
  static const orange = Color(0xFFFB923C);
  static const glass = Color(0x1AFFFFFF);
  static const glassBorder = Color(0x26FFFFFF);
}

const brandGradient = LinearGradient(
  colors: [C.violet, C.pink],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

/// خلفية متدرجة مع توهّج ملوّن
class GradientBg extends StatelessWidget {
  final Widget child;
  const GradientBg({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [C.bg1, C.bg2],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Stack(children: [
        Positioned(
          top: -120,
          right: -100,
          child: _glow(C.violet, 320),
        ),
        Positioned(
          bottom: -140,
          left: -120,
          child: _glow(C.pink, 340),
        ),
        Positioned.fill(child: child),
      ]),
    );
  }

  Widget _glow(Color c, double size) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [c.withValues(alpha: 0.35), c.withValues(alpha: 0)],
            ),
          ),
        ),
      );
}

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: C.glass,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: const BorderSide(color: C.glassBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class GradButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool outlined;
  final bool dense;
  const GradButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.outlined = false,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final h = dense ? 40.0 : 54.0;
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        height: h,
        decoration: BoxDecoration(
          gradient: outlined ? null : brandGradient,
          borderRadius: BorderRadius.circular(h / 2),
          border: outlined ? Border.all(color: Colors.white38) : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(h / 2),
            onTap: onPressed,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: dense ? 18 : 24),
              child: Row(
                mainAxisSize: dense ? MainAxisSize.min : MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: Colors.white, size: dense ? 18 : 22),
                    const SizedBox(width: 8),
                  ],
                  Text(label,
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: dense ? 14 : 16,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class Avatar extends StatelessWidget {
  final String name;
  final String? url;
  final double size;
  final bool speaking;
  const Avatar({
    super.key,
    required this.name,
    this.url,
    this.size = 52,
    this.speaking = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = name.trim();
    final initial = t.isEmpty ? '?' : t.characters.first;
    final hue = (t.runes.fold<int>(0, (a, b) => a + b) * 37) % 360;
    final c1 = HSLColor.fromAHSL(1, hue.toDouble(), 0.7, 0.55).toColor();
    final c2 = HSLColor.fromAHSL(1, ((hue + 50) % 360).toDouble(), 0.7, 0.45).toColor();
    final fallback = Container(
      decoration: BoxDecoration(gradient: LinearGradient(colors: [c1, c2])),
      alignment: Alignment.center,
      child: Text(initial,
          style: TextStyle(
              fontSize: size * 0.42, fontWeight: FontWeight.w800, color: Colors.white)),
    );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: size + 8,
      height: size + 8,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: speaking ? C.green : Colors.white24,
          width: speaking ? 3 : 1.5,
        ),
        boxShadow: speaking
            ? [BoxShadow(color: C.green.withValues(alpha: 0.6), blurRadius: 14)]
            : null,
      ),
      child: ClipOval(
        child: (url == null || url!.isEmpty)
            ? fallback
            : Image.network(url!,
                fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback),
      ),
    );
  }
}

void toast(BuildContext context, String msg) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF2A1B52),
    ));
}

String friendlyError(Object e) {
  final s = e.toString();
  if (s.contains('seat taken')) return 'المقعد محجوز';
  if (s.contains('host only')) return 'هذا المقعد للمضيف فقط';
  if (s.contains('duplicate key') || s.contains('username_key')) return 'اليوزر مستخدم، جرّب غيره';
  if (s.contains('username_fmt')) return 'اليوزر: 3-20 حرفاً إنكليزياً أو أرقاماً أو _';
  if (s.contains('SocketException') || s.contains('ClientException')) return 'تحقق من اتصال الإنترنت';
  return s.length > 120 ? s.substring(0, 120) : s;
}
