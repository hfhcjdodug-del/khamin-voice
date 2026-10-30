import 'dart:async';

import 'package:flutter/material.dart';

import 'main.dart';
import 'svga.dart';
import 'theme.dart';
import 'widgets/gem_icon.dart';

/// يعرض حركة الهدية (SVGA) وعند الفشل صورة/إيموجي بسيط.
class GiftAnim extends StatefulWidget {
  final String? svga;
  final String? image;
  final String emoji;
  final bool loop;
  final VoidCallback? onDone;
  const GiftAnim({super.key, this.svga, this.image, this.emoji = '🎁', this.loop = false, this.onDone});

  @override
  State<GiftAnim> createState() => _GiftAnimState();
}

class _GiftAnimState extends State<GiftAnim> {
  bool _failed = false;
  String _err = '';

  @override
  void initState() {
    super.initState();
    final s = widget.svga;
    if (s == null || s.isEmpty) _failed = true;
    if (_failed) _fallbackDone();
  }

  void _fallbackDone() {
    if (!widget.loop) Future.delayed(const Duration(seconds: 2), () => widget.onDone?.call());
  }

  @override
  Widget build(BuildContext context) {
    if (!_failed) {
      return SvgaView(
        src: widget.svga!,
        loop: widget.loop,
        onDone: widget.onDone,
        onFail: (e) {
          if (!mounted) return;
          setState(() {
            _failed = true;
            _err = '$e';
          });
          _fallbackDone();
        },
      );
    }
    final img = widget.image;
    if (img != null && img.startsWith('http')) {
      return Image.network(img, fit: BoxFit.contain, errorBuilder: (_, __, ___) => _emoji());
    }
    return _emoji();
  }

  Widget _emoji() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(widget.emoji, style: const TextStyle(fontSize: 72)),
          if (widget.loop && _err.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('تعذّر التشغيل: $_err', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
            ),
        ]),
      );
}

/// طبقة تشغيل الهدايا فوق الشاشة: تُضاف في Stack وتستقبل الهدايا بالدور.
class GiftOverlay extends StatefulWidget {
  const GiftOverlay({super.key});
  @override
  State<GiftOverlay> createState() => GiftOverlayState();
}

class GiftOverlayState extends State<GiftOverlay> {
  final List<Map<String, dynamic>> _queue = [];
  Map<String, dynamic>? _cur;

  void play(Map<String, dynamic> g) {
    _queue.add(g);
    if (_cur == null) _next();
  }

  void _next() {
    if (!mounted) return;
    setState(() => _cur = _queue.isEmpty ? null : _queue.removeAt(0));
  }

  @override
  Widget build(BuildContext context) {
    final g = _cur;
    if (g == null) return const SizedBox.shrink();
    final mine = g['from_id'] == myId;
    return IgnorePointer(
      child: Stack(alignment: Alignment.center, children: [
        Positioned.fill(
          child: GiftAnim(
            key: ValueKey(g['id']),
            svga: g['svga_url'] as String?,
            image: g['image_url'] as String?,
            emoji: (g['emoji'] as String?) ?? '🎁',
            onDone: _next,
          ),
        ),
        Positioned(
          top: 24,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
            child: Text(mine ? 'أرسلت ${g['gift_name']}' : 'وصلتك هدية: ${g['gift_name']}',
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    );
  }
}

/// نافذة اختيار الهدية. تُرجع true إذا أُرسلت.
Future<void> showGiftSheet(BuildContext context, String matchId) async {
  List<Map<String, dynamic>> gifts = [];
  int gems = 0;
  try {
    final r = await supa.from('gifts').select().eq('active', true).order('sort').order('price');
    gifts = List<Map<String, dynamic>>.from(r);
    final w = await supa.rpc('my_wallet') as List;
    if (w.isNotEmpty) gems = (w.first['gems'] as num?)?.toInt() ?? 0;
  } catch (_) {}
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1A1226),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (c) => StatefulBuilder(builder: (c, set) {
      bool busy = false;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              const Text('أرسل هدية لخصمك', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              const Spacer(),
              GemAmount(gems),
            ]),
            const SizedBox(height: 12),
            if (gifts.isEmpty)
              const Padding(padding: EdgeInsets.all(24), child: Text('لا توجد هدايا حالياً'))
            else
              Flexible(
                child: GridView.builder(
                  shrinkWrap: true,
                  itemCount: gifts.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.78),
                  itemBuilder: (_, i) {
                    final g = gifts[i];
                    final price = (g['price'] as num).toInt();
                    final enough = gems >= price;
                    final img = g['image_url'] as String?;
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () async {
                        if (busy) return;
                        if (!enough) {
                          toast(context, 'رصيدك لا يكفي');
                          return;
                        }
                        busy = true;
                        try {
                          await supa.rpc('send_match_gift', params: {'p_match': matchId, 'p_gift': g['id']});
                          if (c.mounted) Navigator.pop(c);
                        } catch (e) {
                          busy = false;
                          if (c.mounted) toast(c, friendlyError(e));
                        }
                      },
                      child: Container(
                        decoration: BoxDecoration(
                            color: C.glass, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white12)),
                        padding: const EdgeInsets.all(6),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Expanded(
                            child: img != null && img.startsWith('http')
                                ? Image.network(img, errorBuilder: (_, __, ___) => _e(g))
                                : _e(g),
                          ),
                          Text(g['name'] as String,
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                          GemAmount(price, size: 12),
                        ]),
                      ),
                    );
                  },
                ),
              ),
          ]),
        ),
      );
    }),
  );
}

Widget _e(Map<String, dynamic> g) =>
    Center(child: Text((g['emoji'] as String?) ?? '🎁', style: const TextStyle(fontSize: 34)));
