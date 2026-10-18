import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ads.dart';
import '../main.dart';
import '../shop_screen.dart';
import '../theme.dart';

/// مكافآت مجانية: هدية يومية، روليت، ومهام يومية متبدّلة.
class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> with SingleTickerProviderStateMixin {
  bool _loading = true;
  bool _busy = false;
  bool _adsFreeUser = false;
  int _gems = 0;
  bool _dailyAvail = false;
  int _dailyGems = 5;
  List<int> _segs = [];
  int _freeLeft = 0;
  int _adLeft = 0;
  List<Map<String, dynamic>> _missions = [];

  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 4800));
  double _from = 0;
  double _to = 0;
  double _angle = 0;

  @override
  void initState() {
    super.initState();
    _spin.addListener(() {
      final t = Curves.easeOutQuart.transform(_spin.value);
      setState(() => _angle = _from + (_to - _from) * t);
    });
    _load();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final w = await fetchWallet();
      final d = (await supa.rpc('daily_status') as List).first as Map;
      final r = (await supa.rpc('roulette_info') as List).first as Map;
      final m = await supa.rpc('my_missions') as List;
      if (!mounted) return;
      setState(() {
        _gems = w.gems;
        _adsFreeUser = w.adsFree;
        _dailyAvail = d['available'] == true;
        _dailyGems = (d['gems'] as num).toInt();
        _segs = [for (final s in (r['segments'] as List)) ((s as Map)['g'] as num).toInt()];
        _freeLeft = (r['free_left'] as num).toInt();
        _adLeft = (r['ad_left'] as num).toInt();
        _missions = List<Map<String, dynamic>>.from(m);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      toast(context, friendlyError(e));
    }
  }

  Future<void> _claimDaily() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!await watchRewardedAd(context)) return;
      final g = await supa.rpc('claim_daily') as int;
      if (mounted) toast(context, 'حصلت على $g 💎 هدية اليوم');
      await _load();
    } catch (e) {
      if (mounted) toast(context, e.toString().contains('already claimed') ? 'استلمتها اليوم، عُد غداً' : friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doSpin() async {
    if (_busy || _segs.isEmpty || _spin.isAnimating) return;
    final viaAd = _freeLeft <= 0;
    if (viaAd && _adLeft <= 0) {
      toast(context, 'انتهت محاولات اليوم، عُد غداً');
      return;
    }
    setState(() => _busy = true);
    try {
      if (viaAd && !await watchRewardedAd(context)) return;
      final r = (await supa.rpc('roulette_spin', params: {'p_via_ad': viaAd}) as List).first as Map;
      final seg = (r['seg'] as num).toInt();
      final gems = (r['gems'] as num).toInt();
      final sweep = 2 * math.pi / _segs.length;
      final jitter = (math.Random().nextDouble() - 0.5) * sweep * 0.6;
      final center = (seg + 0.5) * sweep + jitter;
      final base = _angle % (2 * math.pi);
      _from = _angle;
      _to = _angle - base + 2 * math.pi * 6 + ((2 * math.pi - center) % (2 * math.pi));
      _spin.forward(from: 0);
      await Future<void>.delayed(const Duration(milliseconds: 5000));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(gems > 0 ? 'مبروك! 🎉' : 'حظ أوفر'),
          content: Text(gems > 0 ? 'ربحت $gems 💎' : 'لم تربح هذه المرة، جرّب مرة أخرى',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('حسناً'))],
        ),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        final s = e.toString();
        toast(context, s.contains('no more spins') || s.contains('no free spin') ? 'انتهت محاولات اليوم' : friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _claimMission(Map<String, dynamic> m) async {
    try {
      final g = await supa.rpc('claim_mission', params: {'p_id': m['id']}) as int;
      if (mounted) toast(context, 'تم استلام $g 💎');
      await _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Widget _gemChip(int n) => Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.diamond_rounded, size: 15, color: Color(0xFF67E8F9)),
        const SizedBox(width: 3),
        Text('$n', style: const TextStyle(fontWeight: FontWeight.w900)),
      ]);

  @override
  Widget build(BuildContext context) {
    final spinLabel = _freeLeft > 0
        ? 'لفّ مجاناً'
        : _adLeft > 0
            ? (_adsFreeUser ? 'لفّ مرة أخرى ($_adLeft)' : 'شاهد إعلاناً وجرّب مرة أخرى ($_adLeft)')
            : 'انتهت محاولات اليوم';
    return Scaffold(
      appBar: AppBar(
        title: const Text('مكافآت مجانية', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          Center(child: Padding(padding: const EdgeInsetsDirectional.only(end: 16), child: _gemChip(_gems))),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: C.pink))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
                // الهدية اليومية
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFFDB2777)]),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(children: [
                    const Text('🎁', style: TextStyle(fontSize: 38)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('هدية اليوم', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                        Text(_dailyAvail
                            ? (_adsFreeUser ? 'خذ $_dailyGems 💎 مباشرة' : 'شاهد إعلاناً واحصل على $_dailyGems 💎')
                            : 'استلمتها اليوم ✓ عُد غداً',
                            style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ]),
                    ),
                    FilledButton(
                      onPressed: _dailyAvail && !_busy ? _claimDaily : null,
                      style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF7C3AED)),
                      child: Text(_dailyAvail ? 'استلم' : 'تم'),
                    ),
                  ]),
                ),
                const SizedBox(height: 18),
                // الروليت
                const Text('عجلة الحظ', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                const SizedBox(height: 10),
                Center(
                  child: SizedBox(
                    width: 300,
                    height: 318,
                    child: Stack(alignment: Alignment.topCenter, children: [
                      Positioned(
                        top: 18,
                        child: CustomPaint(size: const Size(300, 300), painter: _WheelPainter(_segs, _angle)),
                      ),
                      const Positioned(top: 0, child: _Pointer()),
                    ]),
                  ),
                ),
                const SizedBox(height: 10),
                GradButton(
                  label: spinLabel,
                  icon: Icons.casino_rounded,
                  onPressed: (_busy || (_freeLeft <= 0 && _adLeft <= 0)) ? null : _doSpin,
                ),
                const SizedBox(height: 22),
                // المهام
                Row(children: const [
                  Text('مهام اليوم', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                  SizedBox(width: 8),
                  Text('تتبدّل كل 24 ساعة', style: TextStyle(color: Colors.white54, fontSize: 12)),
                ]),
                const SizedBox(height: 10),
                if (_missions.isEmpty)
                  const GlassCard(child: Text('لا توجد مهام اليوم', style: TextStyle(color: Colors.white60))),
                for (final m in _missions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GlassCard(
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(m['title'] as String, style: const TextStyle(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: ((m['progress'] as num) / (m['target'] as num)).clamp(0.0, 1.0).toDouble(),
                                minHeight: 6,
                                backgroundColor: Colors.white12,
                                valueColor: const AlwaysStoppedAnimation(C.green),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text('${m['progress']}/${m['target']}',
                                style: const TextStyle(color: Colors.white54, fontSize: 11)),
                          ]),
                        ),
                        const SizedBox(width: 12),
                        Column(children: [
                          _gemChip((m['reward'] as num).toInt()),
                          const SizedBox(height: 4),
                          if (m['claimed'] == true)
                            const Icon(Icons.check_circle_rounded, color: C.green)
                          else
                            SizedBox(
                              height: 32,
                              child: FilledButton(
                                onPressed: (m['progress'] as num) >= (m['target'] as num) ? () => _claimMission(m) : null,
                                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14)),
                                child: const Text('استلم', style: TextStyle(fontSize: 12)),
                              ),
                            ),
                        ]),
                      ]),
                    ),
                  ),
              ]),
            ),
    );
  }
}

class _Pointer extends StatelessWidget {
  const _Pointer();

  @override
  Widget build(BuildContext context) => CustomPaint(size: const Size(34, 40), painter: _PointerPainter());
}

class _PointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, size.height)
      ..lineTo(0, 4)
      ..quadraticBezierTo(size.width / 2, -6, size.width, 4)
      ..close();
    canvas.drawShadow(path, Colors.black, 4, true);
    canvas.drawPath(
        path,
        Paint()
          ..shader = const LinearGradient(colors: [Color(0xFFFDE68A), Color(0xFFF59E0B)], begin: Alignment.topCenter, end: Alignment.bottomCenter)
              .createShader(Offset.zero & size));
    canvas.drawCircle(Offset(size.width / 2, 10), 4, Paint()..color = const Color(0xFF7C2D12));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _WheelPainter extends CustomPainter {
  final List<int> segs;
  final double angle;
  _WheelPainter(this.segs, this.angle);

  static const _colors = {
    0: [Color(0xFF334155), Color(0xFF1E293B)],
    5: [Color(0xFF7C3AED), Color(0xFF5B21B6)],
    10: [Color(0xFF06B6D4), Color(0xFF0E7490)],
    20: [Color(0xFFA855F7), Color(0xFFBE185D)],
    100: [Color(0xFFFBBF24), Color(0xFFD97706)],
  };

  void _gem(Canvas c, Offset o, double s, Color col) {
    final p = Path()
      ..moveTo(o.dx - s, o.dy - s * 0.3)
      ..lineTo(o.dx - s * 0.55, o.dy - s * 0.85)
      ..lineTo(o.dx + s * 0.55, o.dy - s * 0.85)
      ..lineTo(o.dx + s, o.dy - s * 0.3)
      ..lineTo(o.dx, o.dy + s)
      ..close();
    c.drawPath(p, Paint()..color = col);
    c.drawPath(p, Paint()..color = Colors.white.withValues(alpha: 0.85)..style = PaintingStyle.stroke..strokeWidth = 1.2);
    c.drawLine(Offset(o.dx - s, o.dy - s * 0.3), Offset(o.dx + s, o.dy - s * 0.3),
        Paint()..color = Colors.white.withValues(alpha: 0.6)..strokeWidth = 1);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final R = size.width / 2;
    // الإطار الذهبي
    canvas.drawCircle(c, R, Paint()..shader = const SweepGradient(colors: [Color(0xFFFDE68A), Color(0xFFF59E0B), Color(0xFFFDE68A), Color(0xFFB45309), Color(0xFFFDE68A)]).createShader(Rect.fromCircle(center: c, radius: R)));
    canvas.drawCircle(c, R, Paint()..color = const Color(0xFFA855F7).withValues(alpha: 0.0));
    final r = R - 14;
    if (segs.isEmpty) return;
    final n = segs.length;
    final sweep = 2 * math.pi / n;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    for (var i = 0; i < n; i++) {
      final start = -math.pi / 2 + i * sweep;
      final cols = _colors[segs[i]] ?? _colors[5]!;
      final rect = Rect.fromCircle(center: Offset.zero, radius: r);
      canvas.drawArc(rect, start, sweep, true,
          Paint()..shader = RadialGradient(colors: [cols[0], cols[1]], radius: 1.0).createShader(rect));
      canvas.drawArc(rect, start, sweep, true,
          Paint()..color = Colors.white.withValues(alpha: 0.25)..style = PaintingStyle.stroke..strokeWidth = 1.5);
      // المحتوى على منتصف القطاع
      canvas.save();
      canvas.rotate(start + sweep / 2 + math.pi / 2);
      final g = segs[i];
      if (g == 0) {
        final tp = TextPainter(
            text: const TextSpan(text: 'حظ\nأوفر', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w800, height: 1.1)),
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl)
          ..layout();
        tp.paint(canvas, Offset(-tp.width / 2, -r * 0.72));
      } else {
        _gem(canvas, Offset(0, -r * 0.82), g == 100 ? 11 : 8, const Color(0xFF67E8F9));
        final tp = TextPainter(
            text: TextSpan(text: '$g', style: TextStyle(color: Colors.white, fontSize: g == 100 ? 24 : 20, fontWeight: FontWeight.w900, shadows: const [Shadow(blurRadius: 4, color: Colors.black54)])),
            textDirection: TextDirection.ltr)
          ..layout();
        tp.paint(canvas, Offset(-tp.width / 2, -r * 0.7));
      }
      canvas.restore();
    }
    canvas.restore();
    // مصابيح الإطار
    for (var i = 0; i < 24; i++) {
      final a = i * 2 * math.pi / 24;
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * (R - 7), 3.2,
          Paint()..color = i.isEven ? Colors.white : const Color(0xFFFEF3C7));
    }
    // المحور
    canvas.drawCircle(c, 26, Paint()..shader = const RadialGradient(colors: [Color(0xFFFDE68A), Color(0xFFB45309)]).createShader(Rect.fromCircle(center: c, radius: 26)));
    canvas.drawCircle(c, 18, Paint()..color = const Color(0xFF1B1040));
    _gem(canvas, c, 9, const Color(0xFF67E8F9));
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) => old.angle != angle || old.segs != segs;
}
