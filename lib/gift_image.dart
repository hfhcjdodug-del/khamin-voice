import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// صورة الهدية: من داخل التطبيق (asset:gifts/5.png) أو رابط مرفوع، وإلا الرمز البديل.
/// الروابط المنتهية بـ .json تُعرض كحركة Lottie، وGIF/WebP المتحركة تتحرك تلقائياً.
class GiftImage extends StatelessWidget {
  final String? image;
  final String emoji;
  final double size;
  const GiftImage({super.key, this.image, this.emoji = '🎁', this.size = 48});

  static bool isLottie(String? u) => u != null && u.toLowerCase().split('?').first.endsWith('.json');

  @override
  Widget build(BuildContext context) {
    final fallback = Text(emoji, style: TextStyle(fontSize: size * 0.8));
    final img = image;
    if (img == null || img.isEmpty) return SizedBox(width: size, height: size, child: Center(child: fallback));
    if (img.startsWith('asset:')) {
      return Image.asset('assets/${img.substring(6)}',
          width: size, height: size, fit: BoxFit.contain, errorBuilder: (_, __, ___) => fallback);
    }
    if (isLottie(img)) {
      return Lottie.network(img,
          width: size,
          height: size,
          fit: BoxFit.contain,
          repeat: true,
          errorBuilder: (_, __, ___) => SizedBox(width: size, height: size, child: Center(child: fallback)));
    }
    return Image.network(img,
        width: size, height: size, fit: BoxFit.contain, errorBuilder: (_, __, ___) => fallback);
  }
}
