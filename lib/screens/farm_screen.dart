import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../main.dart';
import '../shop_screen.dart' show fetchWallet;
import '../theme.dart';

/// لعبة المزرعة: عجلة أكل، الرهان بالجواهر. كل شيء (النتيجة والدفع والحدود) يحدث في الخادم.
class FarmScreen extends StatefulWidget {
  const FarmScreen({super.key});

  @override
  State<FarmScreen> createState() => _FarmScreenState();
}

class _FarmScreenState extends State<FarmScreen> {
  Map<String, dynamic>? _s;
  String? _error;
  int _gems = 0;
  int _stake = 10;
  double _left = 0; // ثوانٍ متبقية محلياً
  DateTime _fetchedAt = DateTime.now();
  double _fetchedLeft = 0;
  Timer? _tick;
  Timer? _poll;
  bool _busy = false;
  bool _fetching = false;
  int? _lastSeenRound;
  int? _flash; // العنصر الفائز المعروض
  String? _banner;
  int _spin = 0;
  Timer? _bannerTimer;

  @override
  void initState() {
    super.initState();
    _fetch();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _fetch());
    _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || _s == null) return;
      final el = DateTime.now().difference(_fetchedAt).inMilliseconds / 1000.0;
      final left = (_fetchedLeft - el).clamp(0, 999).toDouble();
      setState(() {
        _left = left;
        _spin = (_spin + 1) % 8;
      });
      if (left <= 0 && _s!['round_id'] != null) _fetch();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _poll?.cancel();
    _bannerTimer?.cancel();
    super.dispose();
  }

  int _n(dynamic v) => (v as num?)?.toInt() ?? 0;

  Future<void> _fetch() async {
    if (_fetching) return;
    _fetching = true;
    try {
      final r = await supa.rpc('farm_state');
      final s = Map<String, dynamic>.from(r as Map);
      final w = await fetchWallet();
      if (!mounted) return;
      final lastRound = s['last_round'] as int?;
      setState(() {
        _s = s;
        _error = null;
        _gems = w.gems;
        _fetchedAt = DateTime.now();
        _fetchedLeft = ((s['ends_in'] as num?)?.toDouble()) ?? 0;
        _left = _fetchedLeft;
        final mn = _n(s['min_bet']), mx = _n(s['max_bet']);
        if (_stake < mn) _stake = mn;
        if (_stake > mx) _stake = mx;
        if (_lastSeenRound != null && lastRound != null && lastRound != _lastSeenRound) {
          _flash = s['last_result'] as int?;
          final st = _n(s['last_staked']), pay = _n(s['last_payout']);
          _banner = st == 0
              ? null
              : (pay > 0 ? '🎉 ربحت $pay 💎' : 'لم تربح هذه الجولة');
          _bannerTimer?.cancel();
          _bannerTimer = Timer(const Duration(seconds: 5), () {
            if (mounted) setState(() {
                  _flash = null;
                  _banner = null;
                });
          });
        }
        _lastSeenRound = lastRound;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
    _fetching = false;
  }

  Future<void> _bet(int item) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await supa.rpc('farm_bet', params: {'p_item': item, 'p_amount': _stake});
      await _fetch();
    } catch (e) {
      if (mounted) toast(context, _farmError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  String _farmError(Object e) {
    final t = e.toString();
    if (t.contains('farm off')) return 'اللعبة متوقفة حالياً';
    if (t.contains('round closed')) return 'انتهى وقت الرهان، انتظر الجولة القادمة';
    if (t.contains('bad amount')) return 'مبلغ الرهان خارج الحدود';
    if (t.contains('round limit')) return 'وصلت الحد الأعلى لهذه الجولة';
    if (t.contains('daily limit')) return 'وصلت الحد اليومي للّعب';
    if (t.contains('not enough gems')) return 'جواهرك لا تكفي';
    return friendlyError(e);
  }

  List<int> get _stakes {
    final mn = _n(_s?['min_bet']), mx = _n(_s?['max_bet']);
    final set = <int>{mn, mn * 5, mn * 10, mn * 50, mn * 100}..removeWhere((v) => v < mn || v > mx);
    set.add(mx);
    final l = set.toList()..sort();
    return l.length > 5 ? l.sublist(0, 5) : l;
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      backgroundColor: const Color(0xFF14391F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF14391F),
        title: const Text('المزرعة', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(16)),
            alignment: Alignment.center,
            child: Text('💎 $_gems', style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
      body: s == null
          ? Center(
              child: _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('تعذّر التحميل\n$_error\n(هل شغّلت voice_v17.sql؟)',
                          textAlign: TextAlign.center))
                  : const CircularProgressIndicator(color: C.pink))
          : s['enabled'] != true
              ? const Center(
                  child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('اللعبة متوقفة حالياً', style: TextStyle(fontSize: 18))))
              : _game(s),
    );
  }

  Widget _game(Map<String, dynamic> s) {
    final items = List<Map<String, dynamic>>.from(s['items'] as List);
    final mine = Map<String, dynamic>.from(s['my_bets'] as Map);
    final history = List<int>.from((s['history'] as List).map((e) => (e as num).toInt()));
    final closed = _left <= 2;
    final daily = _n(s['daily_limit']), staked = _n(s['today_staked']);
    return ListView(padding: const EdgeInsets.fromLTRB(14, 6, 14, 30), children: [
      // العجلة: 8 عناصر حول دائرة فيها العدّاد
      SizedBox(
        height: 300,
        child: LayoutBuilder(builder: (ctx, c) {
          final w = c.maxWidth;
          final R = w * 0.36;
          final center = Offset(w / 2, 150);
          return Stack(children: [
            Positioned(
              left: center.dx - R * 0.62,
              top: center.dy - R * 0.62,
              child: Container(
                width: R * 1.24,
                height: R * 1.24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(colors: [Color(0xFF1F5C30), Color(0xFF0D2A16)]),
                  border: Border.all(color: const Color(0xFFFDE047), width: 3),
                ),
                alignment: Alignment.center,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(closed ? '⏳' : '${_left.ceil()}',
                      style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w900, color: Colors.white)),
                  Text(closed ? 'جارٍ السحب' : 'ثانية للرهان',
                      style: const TextStyle(fontSize: 11, color: Colors.white70)),
                ]),
              ),
            ),
            for (var i = 0; i < items.length; i++)
              () {
                final a = -3.14159 / 2 + i * 2 * 3.14159 / items.length;
                final x = center.dx + R * math.cos(a) - 30;
                final y = center.dy + R * math.sin(a) - 30;
                final it = items[i];
                final idx = _n(it['idx']);
                final lit = _flash != null ? _flash == idx : (closed && _spin == i);
                return Positioned(
                  left: x,
                  top: y,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 60,
                    height: 60,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: lit ? const Color(0xFFFDE047) : Colors.black26,
                      border: Border.all(color: lit ? Colors.white : Colors.white24, width: lit ? 3 : 1),
                      boxShadow: lit ? [const BoxShadow(color: Color(0xFFFDE047), blurRadius: 18)] : null,
                    ),
                    child: Text(it['emoji'] as String, style: const TextStyle(fontSize: 30)),
                  ),
                );
              }(),
          ]);
        }),
      ),
      if (_banner != null)
        Container(
          padding: const EdgeInsets.all(10),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(14)),
          alignment: Alignment.center,
          child: Text(_banner!, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
        ),
      // السجل
      SizedBox(
        height: 36,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          const Center(child: Text('آخر النتائج  ', style: TextStyle(color: Colors.white60, fontSize: 12))),
          for (final h in history)
            Container(
              width: 34,
              margin: const EdgeInsetsDirectional.only(end: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
              child: Text(items.firstWhere((e) => _n(e['idx']) == h, orElse: () => {'emoji': '?'})['emoji'] as String,
                  style: const TextStyle(fontSize: 18)),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      // قيمة الرهان
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (final v in _stakes)
          GestureDetector(
            onTap: () => setState(() => _stake = v),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: _stake == v ? const Color(0xFFFDE047) : Colors.black26,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text('$v',
                  style: TextStyle(
                      fontWeight: FontWeight.w900, color: _stake == v ? Colors.black : Colors.white)),
            ),
          ),
      ]),
      const SizedBox(height: 12),
      // بطاقات الأكل
      GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.78,
        children: [
          for (final it in items)
            GestureDetector(
              onTap: closed || _busy ? null : () => _bet(_n(it['idx'])),
              child: Opacity(
                opacity: closed ? 0.5 : 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: mine.containsKey('${it['idx']}') ? const Color(0xFFFDE047) : Colors.white12,
                        width: mine.containsKey('${it['idx']}') ? 2 : 1),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(it['emoji'] as String, style: const TextStyle(fontSize: 32)),
                    Text('×${it['mult']}',
                        style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFFDE047))),
                    const SizedBox(height: 2),
                    Text(mine.containsKey('${it['idx']}') ? '💎 ${mine['${it['idx']}']}' : ' ',
                        style: const TextStyle(fontSize: 12)),
                  ]),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 14),
      Text(
        'الرهان بين ${s['min_bet']} و${s['max_bet']} 💎 للجولة. الحد اليومي $daily 💎 (استعملت $staked).\n'
        'الجواهر المُراهَن بها تُخصم فوراً، والفوز يُضاف بعد السحب. العب بمسؤولية.',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11, color: Colors.white54, height: 1.6),
      ),
    ]);
  }
}
