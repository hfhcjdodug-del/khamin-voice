import 'package:flutter/material.dart';

import 'ads.dart';
import 'main.dart';
import 'theme.dart';
import 'widgets/gem_icon.dart';

/// حالة الجولات اليومية من الخادم.
Future<Map<String, dynamic>> playStatus() async {
  final r = await supa.rpc('play_status');
  return Map<String, dynamic>.from(r as Map);
}

/// هل يستطيع اللاعب بدء جولة؟ إن لم يستطع تظهر له خيارات المتابعة.
/// عند فشل قراءة الحالة (انقطاع شبكة مثلاً) نسمح له ونترك الخادم يقرر.
Future<bool> ensureCanPlay(BuildContext context) async {
  Map<String, dynamic> s;
  try {
    s = await playStatus();
  } catch (_) {
    return true;
  }
  if (s['can_play'] == true) return true;
  if (!context.mounted) return false;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PlayGate(status: s),
  );
  return ok == true;
}

class _PlayGate extends StatefulWidget {
  final Map<String, dynamic> status;
  const _PlayGate({required this.status});

  @override
  State<_PlayGate> createState() => _PlayGateState();
}

class _PlayGateState extends State<_PlayGate> {
  late Map<String, dynamic> _s = widget.status;
  int _gems = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadGems();
  }

  Future<void> _loadGems() async {
    try {
      final r = await supa.rpc('my_wallet') as List;
      if (r.isNotEmpty && mounted) setState(() => _gems = ((r.first as Map)['gems'] as num?)?.toInt() ?? 0);
    } catch (_) {}
  }

  int _n(String k) => (_s[k] as num?)?.toInt() ?? 0;

  Future<void> _refresh() async {
    try {
      final s = await playStatus();
      if (mounted) setState(() => _s = s);
    } catch (_) {}
    await _loadGems();
  }

  Future<void> _adRound() async {
    setState(() => _busy = true);
    try {
      if (!await watchRewardedAd(context)) return;
      await supa.rpc('claim_ad_round');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _adGems() async {
    setState(() => _busy = true);
    try {
      if (!await watchRewardedAd(context)) return;
      final g = await supa.rpc('claim_ad_gems');
      if (mounted) toast(context, 'حصلت على $g ماسة 💎');
      await _refresh();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _buy(String kind, int price) async {
    if (_gems < price) {
      toast(context, 'ماساتك لا تكفي، شاهد إعلاناً لتحصل على المزيد');
      return;
    }
    setState(() => _busy = true);
    try {
      await supa.rpc('buy_pass', params: {'p_kind': kind});
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _passBtn(String label, String kind, int price) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: OutlinedButton(
          onPressed: _busy ? null : () => _buy(kind, price),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            side: BorderSide(color: _gems >= price ? C.pink : Colors.white24),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            GemAmount(price, size: 16),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final adRounds = _n('ad_rounds_left');
    final adGems = _n('ad_gems_left');
    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.paddingOf(context).bottom),
      decoration: const BoxDecoration(
        color: Color(0xFF1B1140),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('انتهت جولاتك المجانية اليوم',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text('تتجدد ${_n('free_total')} جولات مجانية كل يوم. أو تابع الآن:',
              textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)),
          const SizedBox(height: 16),
          if (adRounds > 0)
            GradButton(
              label: 'شاهد إعلاناً والعب جولة',
              icon: Icons.play_circle_fill_rounded,
              onPressed: _busy ? null : _adRound,
            ),
          const SizedBox(height: 18),
          Row(children: [
            const Expanded(child: Divider(color: Colors.white24)),
            const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('أو العب بلا حدود', style: TextStyle(color: Colors.white70))),
            const Expanded(child: Divider(color: Colors.white24)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            _passBtn('يوم', 'day', _n('price_day')),
            _passBtn('أسبوع', 'week', _n('price_week')),
            _passBtn('شهر', 'month', _n('price_month')),
          ]),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('رصيدك: ', style: TextStyle(color: Colors.white60)),
            GemAmount(_gems, size: 16),
          ]),
          if (adGems > 0) ...[
            const SizedBox(height: 10),
            GradButton(
              label: 'شاهد إعلاناً واحصل على ${_n('ad_gems_amount')} ماسات',
              icon: Icons.diamond_rounded,
              outlined: true,
              onPressed: _busy ? null : _adGems,
            ),
          ],
        ]),
      ),
    );
  }
}
