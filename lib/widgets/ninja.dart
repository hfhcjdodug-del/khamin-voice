import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class NinjaButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool outlined;
  const NinjaButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = outlined ? Colors.white : Colors.black;
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: Material(
        color: outlined ? Colors.transparent : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: outlined ? const BorderSide(color: Colors.white38) : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[Icon(icon, color: fg, size: 22), const SizedBox(width: 10)],
              Text(label,
                  style: TextStyle(color: fg, fontSize: 17, fontWeight: FontWeight.w700)),
            ],
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
  const Avatar({super.key, required this.name, this.url, this.size = 56, this.speaking = false});

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim().characters.first;
    final fallback = Center(
      child: Text(initial,
          style: TextStyle(fontSize: size * 0.4, fontWeight: FontWeight.w700)),
    );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: size + 8,
      height: size + 8,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: speaking ? const Color(0xFF4ADE80) : Colors.white24,
          width: speaking ? 3 : 1.5,
        ),
      ),
      child: ClipOval(
        child: Container(
          color: const Color(0xFF262626),
          child: (url == null || url!.isEmpty)
              ? fallback
              : Image.network(url!,
                  fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback),
        ),
      ),
    );
  }
}

TextStyle logoStyle(double size) =>
    GoogleFonts.orbitron(fontSize: size, fontWeight: FontWeight.w800, letterSpacing: 4);
