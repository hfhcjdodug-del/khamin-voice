import 'package:flutter/material.dart';

/// خلفيات الغرفة الجاهزة (المعرّف يُحفظ في rooms.bg_preset).
class RoomBgPreset {
  final String id;
  final String name;
  final Gradient gradient;
  const RoomBgPreset(this.id, this.name, this.gradient);
}

const roomBgPresets = <RoomBgPreset>[
  RoomBgPreset('violet', 'بنفسجي', LinearGradient(
      begin: Alignment.topRight, end: Alignment.bottomLeft,
      colors: [Color(0xFF1E1B4B), Color(0xFF6D28D9), Color(0xFFBE185D)], stops: [0, 0.6, 1])),
  RoomBgPreset('teal', 'أزرق مخضر', LinearGradient(
      begin: Alignment.topRight, end: Alignment.bottomLeft,
      colors: [Color(0xFF0F172A), Color(0xFF0E7490), Color(0xFF134E4A)], stops: [0, 0.7, 1])),
  RoomBgPreset('pink', 'وردي', LinearGradient(
      begin: Alignment.topRight, end: Alignment.bottomLeft,
      colors: [Color(0xFF3B0764), Color(0xFFBE185D)])),
  RoomBgPreset('indigo', 'نيلي', LinearGradient(
      begin: Alignment.topRight, end: Alignment.bottomLeft,
      colors: [Color(0xFF111827), Color(0xFF312E81), Color(0xFF7C3AED)], stops: [0, 0.6, 1])),
  RoomBgPreset('galaxy', 'مجرة', RadialGradient(
      center: Alignment(0.4, -0.6), radius: 1.2,
      colors: [Color(0xFFC4B5FD), Color(0xFF4C1D95), Color(0xFF0A0618)], stops: [0, 0.45, 0.85])),
  RoomBgPreset('amber', 'ذهبي', LinearGradient(
      begin: Alignment.topRight, end: Alignment.bottomLeft,
      colors: [Color(0xFF451A03), Color(0xFFB45309), Color(0xFF7C2D12)], stops: [0, 0.6, 1])),
  RoomBgPreset('green', 'أخضر', LinearGradient(
      begin: Alignment.topRight, end: Alignment.bottomLeft,
      colors: [Color(0xFF052E16), Color(0xFF15803D), Color(0xFF064E3B)], stops: [0, 0.6, 1])),
];

RoomBgPreset roomBgOf(String? id) =>
    roomBgPresets.firstWhere((p) => p.id == id, orElse: () => roomBgPresets.first);

/// خلفية الغرفة: صورة مرفوعة إن وجدت وإلا التدرّج الجاهز.
class RoomBackground extends StatelessWidget {
  final String? preset;
  final String? url;
  final double dim;
  const RoomBackground({super.key, this.preset, this.url, this.dim = 0.35});

  @override
  Widget build(BuildContext context) {
    final grad = DecoratedBox(decoration: BoxDecoration(gradient: roomBgOf(preset).gradient));
    return Stack(fit: StackFit.expand, children: [
      if (url != null && url!.isNotEmpty)
        Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => grad)
      else
        grad,
      ColoredBox(color: Colors.black.withValues(alpha: dim)),
    ]);
  }
}

/// خلفيات المايكات (rooms.mic_skin).
const micSkinIds = ['none', 'neon', 'gold', 'galaxy', 'crystal', 'emerald'];
const micSkinNames = {
  'none': 'بدون',
  'neon': 'نيون',
  'gold': 'ذهبي',
  'galaxy': 'مجرة',
  'crystal': 'بلّور',
  'emerald': 'زمرد',
};

Gradient? _skinGradient(String id) {
  switch (id) {
    case 'neon':
      return const RadialGradient(colors: [
        Colors.transparent, Colors.transparent, Color(0xD98B5CF6), Color(0x80EC4899), Colors.transparent,
      ], stops: [0, 0.52, 0.6, 0.7, 0.78]);
    case 'gold':
      return const SweepGradient(colors: [
        Color(0xFFF59E0B), Color(0xFFFDE68A), Color(0xFFF59E0B), Color(0xFFB45309), Color(0xFFF59E0B),
      ]);
    case 'galaxy':
      return const RadialGradient(
          center: Alignment(0, -0.4), colors: [Color(0xFF6366F1), Color(0xFF1E1B4B)], stops: [0, 0.7]);
    case 'crystal':
      return const SweepGradient(colors: [
        Color(0xFF22D3EE), Color(0xFF3B82F6), Color(0xFF8B5CF6), Color(0xFF22D3EE),
      ]);
    case 'emerald':
      return const RadialGradient(colors: [
        Colors.transparent, Colors.transparent, Color(0xCC34D399), Colors.transparent,
      ], stops: [0, 0.5, 0.6, 0.78]);
  }
  return null;
}

/// طبقة خلف صورة الشخص على المقعد. [size] قطر الصورة.
class MicSkin extends StatelessWidget {
  final String skin;
  final String? url;
  final double size;
  const MicSkin({super.key, required this.skin, this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    final d = size * 1.32;
    final hasImg = url != null && url!.isNotEmpty;
    final g = hasImg ? null : _skinGradient(skin);
    if (!hasImg && g == null) return SizedBox(width: d, height: d);
    return Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: g,
        border: hasImg ? Border.all(color: Colors.white54, width: 2) : null,
        image: hasImg ? DecorationImage(image: NetworkImage(url!), fit: BoxFit.cover) : null,
      ),
    );
  }
}
