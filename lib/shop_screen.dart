import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'level.dart';
import 'main.dart';
import 'theme.dart';

/// رصيد المستخدم: الجواهر وحالة «بدون إعلانات».
Future<({int gems, bool adsFree, int rubyPts})> fetchWallet() async {
  final r = await supa.rpc('my_wallet') as List;
  if (r.isEmpty) return (gems: 0, adsFree: false, rubyPts: 0);
  final m = r.first as Map;
  return (
    gems: (m['gems'] as num?)?.toInt() ?? 0,
    adsFree: m['ads_free'] == true,
    rubyPts: (m['ruby_pts'] as num?)?.toInt() ?? 0,
  );
}

/// كل 20 جوهرة مستلمة = ياقوتة، وكل ياقوتة = 10 جواهر.
const rubyPtsPer = 20;
const rubyToGems = 10;


/// شريط «هل تريد التخلص من الإعلانات؟» أعلى قائمة الألعاب.
class AdsPromo extends StatefulWidget {
  const AdsPromo({super.key});

  @override
  State<AdsPromo> createState() => _AdsPromoState();
}

class _AdsPromoState extends State<AdsPromo> {
  bool _adsFree = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final w = await fetchWallet();
      if (mounted) setState(() {
            _adsFree = w.adsFree;
            _loaded = true;
          });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _adsFree) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF3B0764), Color(0xFFBE185D)]),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(children: [
          const Icon(Icons.block_rounded, color: Color(0xFFFDE68A)),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('هل تريد التخلص من الإعلانات؟',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          ),
          GestureDetector(
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const ShopScreen()));
              _load();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: const [
                Icon(Icons.diamond_rounded, size: 16, color: Color(0xFFBE185D)),
                SizedBox(width: 4),
                Text('شحن',
                    style: TextStyle(
                        color: Color(0xFFBE185D), fontWeight: FontWeight.w900, fontSize: 13)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  int _gems = 0;
  bool _adsFree = false;
  int _xp = 0;
  int _nextCost = 0;
  int _adsPrice = 3000;
  String _payAsia = '';
  String _payAtheer = '';
  List<Map<String, dynamic>> _pkgs = [];
  List<Map<String, dynamic>> _reqs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final w = await fetchWallet();
      final pk = await supa.from('gem_packages').select().eq('active', true).order('sort');
      final st = await supa.from('app_settings').select().inFilter(
          'key', ['pay_asiacell', 'pay_atheer', 'ads_free_price']);
      final rq = await supa
          .from('topup_requests')
          .select()
          .eq('user_id', myId)
          .order('created_at', ascending: false)
          .limit(10);
      final me = await supa.from('profiles').select('xp').eq('id', myId).single();
      int cost = 0;
      try {
        cost = (await supa.rpc('buy_level_cost', params: {'p_levels': 1}) as num).toInt();
      } catch (_) {}
      for (final x in st) {
        final v = (x['value'] ?? '') as String;
        if (x['key'] == 'pay_asiacell') _payAsia = v;
        if (x['key'] == 'pay_atheer') _payAtheer = v;
        if (x['key'] == 'ads_free_price') _adsPrice = int.tryParse(v) ?? 3000;
      }
      if (!mounted) return;
      setState(() {
        _gems = w.gems;
        _adsFree = w.adsFree;
        _pkgs = List<Map<String, dynamic>>.from(pk);
        _reqs = List<Map<String, dynamic>>.from(rq);
        _xp = (me['xp'] as num?)?.toInt() ?? 0;
        _nextCost = cost;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      toast(context, friendlyError(e));
    }
  }

  String _fmt(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  /// نافذة الدفع: اختيار آسياسيل/أثير، الرقم، ثم إدخال رقم العملية.
  Future<void> _payFlow({required String kind, String? pkgId, required String title, required int price}) async {
    var method = 'asiacell';
    final ref = TextEditingController();
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) {
          final number = method == 'asiacell' ? _payAsia : _payAtheer;
          return Padding(
            padding: EdgeInsets.fromLTRB(22, 18, 22, 22 + MediaQuery.of(c).viewInsets.bottom),
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text('المبلغ: ${_fmt(price)} دينار',
                    style: const TextStyle(color: Color(0xFFFDE68A), fontWeight: FontWeight.w800)),
                const SizedBox(height: 14),
                Wrap(spacing: 8, children: [
                  ChoiceChip(
                      label: const Text('آسياسيل'),
                      selected: method == 'asiacell',
                      onSelected: (_) => setS(() => method = 'asiacell')),
                  ChoiceChip(
                      label: const Text('أثير'),
                      selected: method == 'atheer',
                      onSelected: (_) => setS(() => method = 'atheer')),
                ]),
                const SizedBox(height: 12),
                if (number.isEmpty)
                  const Text('لم يحدد المدير رقم الدفع لهذه الطريقة بعد.',
                      style: TextStyle(color: Color(0xFFFF8A8A)))
                else
                  GlassCard(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: number));
                      toast(context, 'تم نسخ الرقم');
                    },
                    child: Row(children: [
                      const Icon(Icons.copy_rounded, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(number,
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                      ),
                      const Text('رقم التحويل', style: TextStyle(color: Colors.white60, fontSize: 12)),
                    ]),
                  ),
                const SizedBox(height: 10),
                const Text(
                    '١) حوّل المبلغ إلى الرقم أعلاه.\n٢) اكتب رقم العملية أو آخر 4 أرقام من رقمك الذي حوّلت منه.\n٣) اضغط إرسال، وتتم الموافقة بعد أن يتحقق المدير من التحويل.',
                    style: TextStyle(color: Colors.white70, height: 1.6, fontSize: 13)),
                const SizedBox(height: 10),
                TextField(
                  controller: ref,
                  maxLength: 60,
                  decoration: const InputDecoration(labelText: 'رقم العملية / آخر 4 أرقام', counterText: ''),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: GradButton(
                    label: 'تم الدفع — إرسال الطلب',
                    icon: Icons.send_rounded,
                    onPressed: () => Navigator.pop(c, true),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
    if (sent != true) return;
    if (ref.text.trim().length < 3) {
      if (mounted) toast(context, 'اكتب رقم العملية أو آخر 4 أرقام');
      return;
    }
    try {
      await supa.rpc('request_topup', params: {
        'p_kind': kind,
        'p_package': pkgId,
        'p_method': method,
        'p_ref': ref.text.trim(),
      });
      if (mounted) toast(context, 'تم إرسال الطلب، ستصلك الجواهر بعد موافقة المدير');
      await _load();
    } catch (e) {
      final s = e.toString();
      if (mounted) {
        toast(context, s.contains('too many pending') ? 'لديك طلبات كثيرة قيد المراجعة' : friendlyError(e));
      }
    }
  }

  Future<void> _buyLevel() async {
    final lv = levelOf(_xp);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('شراء المستوى ${lv + 1}؟'),
        content: Text('سيُخصم $_nextCost جوهرة من رصيدك.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('شراء')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final n = await supa.rpc('buy_level', params: {'p_levels': 1});
      if (mounted) toast(context, 'مبروك! وصلت إلى المستوى $n');
      await _load();
    } catch (e) {
      if (mounted) {
        toast(context, e.toString().contains('not enough gems') ? 'رصيدك من الجواهر لا يكفي' : friendlyError(e));
      }
    }
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
        child: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
      );

  Widget _pkgCard(Map<String, dynamic> p) {
    final gems = (p['gems'] as num).toInt();
    final price = (p['price_iqd'] as num).toInt();
    return GestureDetector(
      onTap: () => _payFlow(
          kind: 'gems', pkgId: p['id'] as String, title: '$gems جوهرة', price: price),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFF1E1B4B), Color(0xFF5B21B6)],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: C.glassBorder),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.diamond_rounded, size: 34, color: Color(0xFF67E8F9)),
          const SizedBox(height: 4),
          Text(_fmt(gems), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(gradient: brandGradient, borderRadius: BorderRadius.circular(12)),
            child: Text('${_fmt(price)} د.ع',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
          ),
        ]),
      ),
    );
  }

  String _statusText(String s) => s == 'approved' ? 'تمت الموافقة' : (s == 'rejected' ? 'مرفوض' : 'قيد المراجعة');

  @override
  Widget build(BuildContext context) {
    final lv = levelOf(_xp);
    return Scaffold(
      appBar: AppBar(title: const Text('متجر الشحن', style: TextStyle(fontWeight: FontWeight.w800))),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: C.pink))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF0E7490), Color(0xFF6D28D9)]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(children: [
                    const Icon(Icons.diamond_rounded, size: 40, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('رصيدك', style: TextStyle(color: Colors.white70)),
                        Text('${_fmt(_gems)} جوهرة',
                            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                      ]),
                    ),
                  ]),
                ),
                _section('باقات الجواهر'),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.95,
                  children: [for (final p in _pkgs) _pkgCard(p)],
                ),
                _section('بدون إعلانات'),
                GlassCard(
                  onTap: _adsFree
                      ? null
                      : () => _payFlow(
                          kind: 'ads_free', title: 'نسخة بدون إعلانات', price: _adsPrice),
                  child: Row(children: [
                    const Icon(Icons.block_rounded, color: Color(0xFFFDE68A), size: 30),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('نسخة بدون إعلانات',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        Text(_adsFree ? 'مفعّلة على حسابك ✓' : 'دفعة واحدة، تبقى دائمة',
                            style: const TextStyle(color: Colors.white60, fontSize: 12)),
                      ]),
                    ),
                    if (!_adsFree)
                      Text('${_fmt(_adsPrice)} د.ع',
                          style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFFDE68A))),
                  ]),
                ),
                _section('اشترِ مستوى بالجواهر'),
                GlassCard(
                  child: Row(children: [
                    LevelBadge(level: lv, size: 52),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('مستواك $lv',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        Text('المستوى التالي: $_nextCost جوهرة',
                            style: const TextStyle(color: Colors.white60, fontSize: 12)),
                      ]),
                    ),
                    GradButton(
                      label: 'شراء',
                      dense: true,
                      onPressed: _nextCost > 0 && _gems >= _nextCost ? _buyLevel : null,
                    ),
                  ]),
                ),
                if (_reqs.isNotEmpty) ...[
                  _section('طلباتي'),
                  for (final r in _reqs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GlassCard(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(children: [
                          Icon(
                              r['status'] == 'approved'
                                  ? Icons.check_circle_rounded
                                  : (r['status'] == 'rejected'
                                      ? Icons.cancel_rounded
                                      : Icons.hourglass_top_rounded),
                              color: r['status'] == 'approved'
                                  ? C.green
                                  : (r['status'] == 'rejected' ? const Color(0xFFFF6B6B) : C.orange)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                                r['kind'] == 'gems'
                                    ? '${r['gems']} جوهرة — ${_fmt((r['price_iqd'] as num).toInt())} د.ع'
                                    : 'نسخة بدون إعلانات',
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                          Text(_statusText(r['status'] as String),
                              style: const TextStyle(color: Colors.white60, fontSize: 12)),
                        ]),
                      ),
                    ),
                ],
              ]),
            ),
    );
  }
}
