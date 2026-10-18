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
  bool _fetching = false;
  int? _lastSeenRound;
  int? _flash; // العنصر الفائز المعروض
  String? _banner;
  int _spin = 0;
  final Map<int, int> _extra = {}; // رهانات لم يؤكدها الخادم بعد
  int _inflight = 0;
  bool _errShown = false;
  Future<void> _q = Future.value();
  int? _pulse;
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
    if (_fetching || _inflight > 0) return;
    _fetching = true;
    try {
      final r = await supa.rpc('farm_state');
      final s = Map<String, dynamic>.from(r as Map);
      final w = await fetchWallet();
      if (!mounted) return;
      final lastRound = s['last_round'] as int?;
      setState(() {
        _s = s;
        _extra.clear();
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

  /// كل نقرة على الطعام = رهان بقيمة المبلغ المختار. تُعرض فوراً وتُرسل للخادم بالتسلسل.
  void _tap(int item) {
    final s = _s;
    if (s == null || _left <= 2) return;
    if (_gems < _stake) {
      toast(context, 'جواهرك لا تكفي');
      return;
    }
    setState(() {
      _extra[item] = (_extra[item] ?? 0) + _stake;
      _gems -= _stake;
      _pulse = item;
    });
    Timer(const Duration(milliseconds: 140), () {
      if (mounted && _pulse == item) setState(() => _pulse = null);
    });
    final amount = _stake;
    _inflight++;
    _q = _q.then((_) async {
      try {
        await supa.rpc('farm_bet', params: {'p_item': item, 'p_amount': amount});
      } catch (e) {
        if (mounted && !_errShown) {
          _errShown = true;
          toast(context, _farmError(e));
        }
      }
      _inflight--;
      if (_inflight == 0) {
        _errShown = false;
        await _fetch();
      }
    });
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
      backgroundColor: const Color(0xFF1B0F4A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B0F4A),
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

  Future<void> _help() => showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('طريقة اللعب'),
          content: const Text(
              '١) اختر مبلغ الرهان من الأسفل.\n'
              '٢) اضغط على الطعام نفسه: كل ضغطة ترمي المبلغ المختار عليه، وضغطتان تضاعفانه.\n'
              '٣) بعد انتهاء العدّاد يُسحب عنصر واحد عشوائياً، ومن راهن عليه يربح المبلغ × المضاعف المكتوب.\n'
              'العنصر ذو المضاعف الأعلى أندر ظهوراً.\n'
              'الجواهر تُخصم عند الرهان، والفوز يُضاف بعد السحب.'),
          actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('حسناً'))],
        ),
      );

  Widget _game(Map<String, dynamic> s) {
    final items = List<Map<String, dynamic>>.from(s['items'] as List);
    final mine = Map<String, dynamic>.from(s['my_bets'] as Map);
    final history = List<int>.from((s['history'] as List).map((e) => (e as num).toInt()));
    final closed = _left <= 2;
    final daily = _n(s['daily_limit']), staked = _n(s['today_staked']);
    int myBet(int idx) => _n(mine['$idx']) + (_extra[idx] ?? 0);
    return ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 24), children: [
      Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
          child: Text('جولة ${s['round_id'] ?? '-'}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        ),
        const Spacer(),
        GestureDetector(
          onTap: _help,
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: Color(0xFFFDE047), shape: BoxShape.circle),
            child: const Text('؟', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      // العجلة: 8 فقاعات حول دائرة العدّاد، والنقر على الفقاعة نفسها يرمي المبلغ
      LayoutBuilder(builder: (ctx, c) {
        final w = c.maxWidth;
        final d = w * 0.27;
        final R = (w - d) / 2 - 2;
        final h = 2 * R + d + 4;
        final cx = w / 2, cy = h / 2;
        return SizedBox(
          height: h,
          child: Stack(children: [
            Positioned(
              left: cx - R * 1.02,
              top: cy - R * 1.02,
              child: Container(
                width: R * 2.04,
                height: R * 2.04,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.55), width: 10),
                ),
              ),
            ),
            Positioned(
              left: cx - R * 0.5,
              top: cy - R * 0.5,
              child: Container(
                width: R,
                height: R,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(colors: [Color(0xFFFDE047), Color(0xFFF59E0B)]),
                  border: Border.all(color: const Color(0xFFA855F7), width: 5),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(closed ? 'جارٍ السحب' : 'الوقت المتبقي',
                      style: TextStyle(
                          fontSize: R * 0.11, fontWeight: FontWeight.w800, color: const Color(0xFF3B1D00))),
                  Text(closed ? '⏳' : '${_left.ceil()}',
                      style: TextStyle(
                          fontSize: R * 0.34, fontWeight: FontWeight.w900, color: const Color(0xFF3B1D00))),
                ]),
              ),
            ),
            for (var i = 0; i < items.length; i++)
              () {
                final a = -math.pi / 2 + i * 2 * math.pi / items.length;
                final it = items[i];
                final idx = _n(it['idx']);
                final lit = _flash != null ? _flash == idx : (closed && _spin == i);
                final bet = myBet(idx);
                return Positioned(
                  left: cx + R * math.cos(a) - d / 2,
                  top: cy + R * math.sin(a) - d / 2,
                  child: GestureDetector(
                    onTap: () => _tap(idx),
                    child: AnimatedScale(
                      scale: _pulse == idx ? 1.1 : 1,
                      duration: const Duration(milliseconds: 120),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: d,
                        height: d,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: lit
                                  ? const [Color(0xFFFDE047), Color(0xFFF59E0B)]
                                  : const [Color(0x33FFFFFF), Color(0xFFEC77C8)]),
                          border: Border.all(
                              color: lit ? Colors.white : Colors.white54, width: lit ? 3 : 1.5),
                          boxShadow: lit ? [const BoxShadow(color: Color(0xFFFDE047), blurRadius: 18)] : null,
                        ),
                        child: Stack(alignment: Alignment.center, children: [
                          Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Text(it['emoji'] as String, style: TextStyle(fontSize: d * 0.42)),
                            Text('×${it['mult']}',
                                style: TextStyle(
                                    fontSize: d * 0.17,
                                    fontWeight: FontWeight.w900,
                                    color: lit ? Colors.black : Colors.white)),
                          ]),
                          if (bet > 0)
                            Positioned(
                              bottom: -2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                    color: const Color(0xFF4C1D95),
                                    border: Border.all(color: const Color(0xFFFDE047)),
                                    borderRadius: BorderRadius.circular(10)),
                                child: Text('💎 $bet',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                              ),
                            ),
                        ]),
                      ),
                    ),
                  ),
                );
              }(),
          ]),
        );
      }),
      if (_banner != null)
        Container(
          padding: const EdgeInsets.all(10),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(14)),
          alignment: Alignment.center,
          child: Text(_banner!, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
        ),
      // اختيار المبلغ
      Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
            color: Colors.black26, borderRadius: BorderRadius.circular(18)),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (final v in _stakes)
              GestureDetector(
                onTap: () => setState(() => _stake = v),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: _stake == v ? const Color(0xFFFDE047) : const Color(0xFF3B2A7A),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: _stake == v ? Colors.white : Colors.white24, width: _stake == v ? 2 : 1),
                  ),
                  child: Text('💎 $v',
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: _stake == v ? Colors.black : Colors.white)),
                ),
              ),
          ]),
          const SizedBox(height: 8),
          const Text('اختر المبلغ ثم اضغط على الطعام',
              style: TextStyle(fontSize: 12, color: Colors.white70)),
        ]),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              const Text('رصيدي', style: TextStyle(fontSize: 12, color: Colors.white70)),
              Text('💎 $_gems', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            ]),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              const Text('رهانات اليوم', style: TextStyle(fontSize: 12, color: Colors.white70)),
              Text('$staked / $daily',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            ]),
          ),
        ),
      ]),
      const SizedBox(height: 10),
      // سجل النتائج
      Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          const Text('النتيجة', style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(width: 8),
          Expanded(
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final h in history)
                Container(
                  width: 38,
                  margin: const EdgeInsetsDirectional.only(end: 6),
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: Color(0x22FFFFFF), shape: BoxShape.circle),
                  child: Text(
                      items.firstWhere((e) => _n(e['idx']) == h, orElse: () => {'emoji': '?'})['emoji']
                          as String,
                      style: const TextStyle(fontSize: 20)),
                ),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      Text(
        'الرهان بين ${s['min_bet']} و${s['max_bet']} 💎 للجولة. الجواهر تُخصم فوراً، والفوز يُضاف بعد السحب. العب بمسؤولية.',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11, color: Colors.white54, height: 1.6),
      ),
    ]);
  }
}
