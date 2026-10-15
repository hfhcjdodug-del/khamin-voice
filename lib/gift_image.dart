import 'package:flutter/material.dart';

/// صورة الهدية: من داخل التطبيق (asset:gifts/5.png) أو رابط مرفوع، وإلا الرمز البديل.
class GiftImage extends StatelessWidget {
  final String? image;
  final String emoji;
  final double size;
  const GiftImage({super.key, this.image, this.emoji = '🎁', this.size = 48});

  @override
  Widget build(BuildContext context) {
    final fallback = Text(emoji, style: TextStyle(fontSize: size * 0.8));
    final img = image;
    if (img == null || img.isEmpty) return SizedBox(width: size, height: size, child: Center(child: fallback));
    if (img.startsWith('asset:')) {
      return Image.asset('assets/${img.substring(6)}',
          width: size, height: size, fit: BoxFit.contain, errorBuilder: (_, __, ___) => fallback);
    }
    return Image.network(img,
        width: size, height: size, fit: BoxFit.contain, errorBuilder: (_, __, ___) => fallback);
  }
}
