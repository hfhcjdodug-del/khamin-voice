import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../gift_image.dart';
import '../level.dart';
import '../main.dart';
import '../shop_screen.dart';
import '../theme.dart';
import 'admin_screen.dart';
import 'challenge.dart';
import 'follows_screen.dart';
import 'challenges_screen.dart';
import 'chat_screen.dart';
import 'edit_profile_screen.dart';
import 'profile_actions.dart';
import 'rewards_screen.dart';
import 'rooms_tab.dart' show openRoom;
import 'settings_screen.dart';
import 'visitors_screen.dart';
import '../widgets/gem_icon.dart';

const _ink = Color(0xFF1F1B2E);
const _ink2 = Color(0xFF4A4458);
const _sub = Color(0xFF9AA0AE);
const _line = Color(0xFFEDEEF3);
const _soft = Color(0xFFF7F7FA);
const _violet = Color(0xFF8B5CF6);

class ProfileScreen extends StatefulWidget {
  final String userId;
  final bool embedded;
  final Map<String, dynamic>? seed; // للاختبار فقط
  const ProfileScreen({super.key, required this.userId, this.embedded = false, this.seed});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _p;
  bool _loading = true;
  bool _viewerAdmin = false;
  List<Map<String, dynamic>> _gifts = [];
  int _giftRecv = 0;
  int _giftSent = 0;
  ({int gems, bool adsFree, int rubyPts})? _wallet;
  bool _converting = false;
  int _tab = 1; // 0 المنشورات، 1 الملف الشخصي، 2 الشرف، 3 العلاقة
  Map<String, dynamic> _extra = {}; // photos / tags / birthday (من v12)
  DateTime? _created;
  Map<String, dynamic>? _live; // الغرفة المباشرة التي فيها المستخدم الآن

  bool get _isMe => widget.userId == myId;

  Future<void> _loadWallet() async {
    if (!_isMe) return;
    try {
      final w = await fetchWallet();
      if (mounted) setState(() => _wallet = w);
    } catch (_) {}
  }

  Future<void> _convert(int n) async {
    if (_converting) return;
    setState(() => _converting = true);
    try {
      final g = await supa.rpc('convert_rubies', params: {'p_count': n}) as int;
      if (mounted) toast(context, 'تم تحويل الياقوت إلى $g 💎');
      await _loadWallet();
    } catch (e) {
      if (mounted) toast(context, e.toString().contains('no rubies') ? 'لا توجد ياقوتات كافية' : friendlyError(e));
    } finally {
      if (mounted) setState(() => _converting = false);
    }
  }

  Widget _walletCard() {
    final w = _wallet;
    final rubies = (w?.rubyPts ?? 0) ~/ rubyPtsPer;
    final part = (w?.rubyPts ?? 0) % rubyPtsPer;
    const red = Color(0xFFEF4444);
    Widget conv(String label, int n, bool on) => Expanded(
          child: OutlinedButton(
            onPressed: on && !_converting ? () => _convert(n) : null,
            style: OutlinedButton.styleFrom(
                foregroundColor: _ink,
                side: BorderSide(color: on ? red : _line),
                padding: const EdgeInsets.symmetric(horizontal: 4)),
            child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: const TextStyle(fontSize: 12))),
          ),
        );
    return _lcard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: InkWell(
              onTap: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const ShopScreen()));
                _loadWallet();
              },
              child: Row(children: [
                const GemIcon(size: 24),
                const SizedBox(width: 6),
                Text('${w?.gems ?? 0}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                const SizedBox(width: 4),
                const Text('جوهرة', style: TextStyle(color: _sub, fontSize: 12)),
                const SizedBox(width: 4),
                const Icon(Icons.add_circle_rounded, size: 18, color: C.pink),
              ]),
            ),
          ),
          Container(width: 1, height: 28, color: _line),
          const SizedBox(width: 12),
          Expanded(
            child: Row(children: [
              const GemIcon(size: 24, ruby: true),
              const SizedBox(width: 6),
              Text('$rubies', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              const SizedBox(width: 4),
              const Text('ياقوت', style: TextStyle(color: _sub, fontSize: 12)),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
            rubies == 0
                ? 'تحصل على ياقوتة عن كل $rubyPtsPer جوهرة تُهدى إليك (تبقى $part/$rubyPtsPer)'
                : 'ياقوتاتك تساوي ${rubies * rubyToGems} 💎  (الياقوتة = $rubyToGems 💎)',
            style: const TextStyle(color: _sub, fontSize: 12)),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const RewardsScreen()));
            _loadWallet();
          },
          child: const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Text('🎁', style: TextStyle(fontSize: 16)),
              SizedBox(width: 6),
              Text('مكافآت مجانية: ماسات يومية وروليت ومهام',
                  style: TextStyle(color: Color(0xFFB45309), fontSize: 12, fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
        Row(children: [
          conv('تحويل 1', 1, rubies >= 1),
          const SizedBox(width: 6),
          conv('تحويل 5', 5, rubies >= 5),
          const SizedBox(width: 6),
          conv('تحويل الكل (${rubies * rubyToGems} 💎)', 0, rubies >= 1),
        ]),
      ]),
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.seed != null) {
      _p = widget.seed;
      _loading = false;
      _extra = {
        for (final k in const ['photos', 'tags', 'birthday'])
          if (widget.seed!.containsKey(k)) k: widget.seed![k]
      };
      if (widget.seed!['live'] is Map) _live = Map<String, dynamic>.from(widget.seed!['live'] as Map);
    }
    _load();
    _loadExtra();
    _loadWallet();
    if (!_isMe) {
      Future(() async {
        try {
          await supa.rpc('visit_profile', params: {'p_id': widget.userId});
        } catch (_) {}
      });
    }
  }

  Future<void> _load() async {
    try {
      final a = await supa.rpc('am_i_admin');
      if (mounted) setState(() => _viewerAdmin = a == true);
    } catch (_) {}
    try {
      final g = await supa.rpc('user_gifts', params: {'p_id': widget.userId}) as List;
      final t = await supa.rpc('user_gift_totals', params: {'p_id': widget.userId}) as List;
      if (mounted) {
        setState(() {
          _gifts = List<Map<String, dynamic>>.from(g);
          if (t.isNotEmpty) {
            _giftRecv = ((t.first as Map)['received'] as num?)?.toInt() ?? 0;
            _giftSent = ((t.first as Map)['sent'] as num?)?.toInt() ?? 0;
          }
        });
      }
    } catch (_) {}
    try {
      final r = await supa.rpc('get_profile', params: {'p_id': widget.userId}) as List;
      if (!mounted) return;
      setState(() {
        _p = r.isEmpty ? null : Map<String, dynamic>.from(r.first as Map);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      toast(context, friendlyError(e));
    }
  }

  Future<void> _toggleFollow() async {
    final p = _p!;
    final f = p['is_following'] == true;
    try {
      await supa.rpc(f ? 'unfollow_user' : 'follow_user', params: {'p_id': p['id']});
      await _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _toggleVerified() async {
    final p = _p!;
    try {
      await supa.rpc('admin_set_verified',
          params: {'p_id': p['id'], 'p_v': !(p['verified'] == true)});
      await _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _vip(int days) async {
    try {
      await supa.rpc('admin_set_vip', params: {'p_id': _p!['id'], 'p_days': days});
      await _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _setLevel() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('تعيين المستوى (1 - 100)'),
        content: TextField(controller: c, keyboardType: TextInputType.number),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('تطبيق')),
        ],
      ),
    );
    final l = int.tryParse(c.text.trim());
    if (ok != true || l == null) return;
    try {
      await supa.rpc('admin_set_level', params: {'p_id': _p!['id'], 'p_level': l});
      await _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _edit() async {
    final base = {..._p!, ..._extra};
    final ch = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => EditProfileScreen(profile: base)));
    if (ch == true) {
      await _load();
      await _loadExtra();
    }
  }

  Future<void> _cover() async {
    if (await changeCover(context)) await _load();
  }

  Future<void> _avatar() async {
    if (await changeAvatar(context)) await _load();
  }

  int _n(String k) => (_p![k] as num?)?.toInt() ?? 0;

  Future<void> _loadExtra() async {
    try {
      final r = await supa.from('profiles').select('created_at').eq('id', widget.userId).single();
      _created = DateTime.tryParse('${r['created_at']}')?.toLocal();
    } catch (_) {}
    try {
      final r = await supa
          .from('profiles')
          .select('photos, tags, birthday')
          .eq('id', widget.userId)
          .single();
      _extra = Map<String, dynamic>.from(r);
    } catch (_) {} // الأعمدة غير موجودة قبل تشغيل v12
    try {
      final since = DateTime.now().toUtc().subtract(const Duration(seconds: 45)).toIso8601String();
      final m = await supa
          .from('room_members')
          .select('room_id')
          .eq('user_id', widget.userId)
          .gt('last_seen', since)
          .limit(1);
      Map<String, dynamic>? room;
      if ((m as List).isNotEmpty) {
        room = await supa
            .from('rooms')
            .select('id,title,topic,host_id,is_live')
            .eq('id', m.first['room_id'])
            .eq('is_live', true)
            .maybeSingle();
      }
      _live = room;
    } catch (_) {
      _live = null;
    }
    if (mounted) setState(() {});
  }


  Widget _defaultCover() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1A0F4D), Color(0xFF3B1A8C), Color(0xFF6D2BD9)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(children: [
          Positioned(
            top: 30,
            right: 40,
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  const Color(0xFFB9A7FF).withValues(alpha: 0.9),
                  const Color(0xFF6D4AFF).withValues(alpha: 0.25),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
        ]),
      );

  Widget _vipCard(Map<String, dynamic> p) {
    final st = vipState(p);
    final gold = const [Color(0xFFFBBF24), Color(0xFFF97316)];
    String title, sub;
    if (st == 'active') {
      title = 'عضو VIP';
      sub = 'من ${fmtDate(p['vip_start'])} · ينتهي ${fmtDate(p['vip_end'])} (باقي ${vipDaysLeft(p)} يوم)';
    } else if (st == 'former') {
      title = 'VIP سابق';
      sub = 'كان VIP من ${fmtDate(p['vip_start'])} حتى ${fmtDate(p['vip_end'])}';
    } else {
      title = 'بدون VIP';
      sub = 'لم يشترك بعد';
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: st == 'active' ? LinearGradient(colors: gold) : null,
        color: st == 'active' ? null : _soft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: st == 'active' ? _sub : _line),
      ),
      child: Row(children: [
        Icon(Icons.diamond_rounded,
            color: st == 'active' ? Colors.white : (st == 'former' ? C.orange : _sub),
            size: 30),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            Text(sub,
                style: TextStyle(
                    fontSize: 12, color: st == 'active' ? Colors.white : _sub)),
          ]),
        ),
      ]),
    );
  }

  Widget _honorTab(Map<String, dynamic> p) {
    final xp = _n('xp');
    final lv = levelOf(xp);
    final base = levelBase(lv);
    final next = levelNext(lv);
    final prog = ((xp - base) / (next - base)).clamp(0.0, 1.0);
    final top = titleIndex(lv);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _lcard(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          LevelBadge(level: lv, size: 74),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('المستوى $lv',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 22, color: Color(0xFFB45309))),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: prog,
                  minHeight: 7,
                  backgroundColor: _line,
                  valueColor: const AlwaysStoppedAnimation(C.pink),
                ),
              ),
              const SizedBox(height: 4),
              Text('$xp / $next نقطة',
                  style: const TextStyle(color: _sub, fontSize: 12)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 10),
      _vipCard(p),
      const SizedBox(height: 14),
      const Text('لقبي الحالي', style: TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Center(child: TitleImage(level: lv, height: 96)),
      const SizedBox(height: 14),
      const Text('جميع الألقاب', style: TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: [
          for (var i = 0; i < BadgeStore.titles.length; i++)
            Opacity(
              opacity: i <= top ? 1 : 0.25,
              child: TitleDefImage(def: BadgeStore.titles[i], height: 80),
            ),
        ],
      ),
      const SizedBox(height: 14),
      Row(children: [
        const Text('الهدايا المستلمة', style: TextStyle(fontWeight: FontWeight.w800)),
        const Spacer(),
        const GemIcon(size: 14),
        Text(' استلم $_giftRecv · أرسل $_giftSent',
            style: const TextStyle(color: _sub, fontSize: 12)),
      ]),
      const SizedBox(height: 8),
      if (_gifts.isEmpty)
        const Text('لم يستلم هدايا بعد', style: TextStyle(color: _sub, fontSize: 13))
      else
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 0.85,
          children: [
            for (final g in _gifts)
              Container(
                decoration: BoxDecoration(
                  color: _soft,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _line),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  GiftImage(
                      image: g['image_url'] as String?,
                      emoji: (g['emoji'] ?? '🎁') as String,
                      size: 44),
                  const SizedBox(height: 2),
                  Text('×${g['qty']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                ]),
              ),
          ],
        ),
      const SizedBox(height: 14),
      const Text('الإنجازات', style: TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Wrap(spacing: 10, runSpacing: 12, children: [
        for (final a in achievements) AchBadge(a: a, earned: a.test(p), size: 52),
      ]),
      const SizedBox(height: 14),
      const Text('المستويات', style: TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      GridView.count(
        crossAxisCount: 5,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: [
          for (var l = 1; l <= BadgeStore.maxLevel; l++)
            Opacity(opacity: l <= lv ? 1 : 0.25, child: LevelBadge(level: l, size: 56)),
        ],
      ),
    ]);
  }

  Widget _tile(IconData icon, List<Color> colors, String title, String sub, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _lcard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colors),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              Text(sub, style: const TextStyle(color: _sub, fontSize: 12)),
            ]),
          ),
          const Icon(Icons.chevron_left_rounded, color: _sub),
        ]),
      ),
    );
  }

  // ======================= الواجهة الجديدة (ورقة فاتحة) =======================

  Widget _lcard({required Widget child, VoidCallback? onTap, EdgeInsets padding = const EdgeInsets.all(14)}) {
    final box = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: _soft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
      ),
      child: child,
    );
    return onTap == null ? box : GestureDetector(onTap: onTap, child: box);
  }

  static const _signs = [
    'الجدي', 'الدلو', 'الحوت', 'الحمل', 'الثور', 'الجوزاء',
    'السرطان', 'الأسد', 'العذراء', 'الميزان', 'العقرب', 'القوس', 'الجدي',
  ];
  static const _cuts = [20, 19, 21, 20, 21, 21, 23, 23, 23, 23, 22, 22];

  String _zodiac(DateTime d) => 'برج ${_signs[d.day < _cuts[d.month - 1] ? d.month - 1 : d.month]}';

  String _since(DateTime d) {
    final days = DateTime.now().difference(d).inDays;
    if (days < 1) return 'اليوم';
    if (days < 30) return '$days يوم';
    if (days < 365) return '${days ~/ 30} شهر';
    return '${days ~/ 365} سنة';
  }

  String _k(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';

  List<String> _plist(String k) => ((_extra[k] ?? const []) as List).map((e) => '$e').toList();

  Widget _roundBtn(IconData i, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
          child: Icon(i, size: 24, color: Colors.white),
        ),
      );

  Widget _pill(Widget child, {VoidCallback? onTap}) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(16)),
          child: child,
        ),
      );

  Widget _livePill() => _LivePill(onTap: () => openRoom(context, _live!));

  Widget _header(Map<String, dynamic> p) {
    final h = (MediaQuery.sizeOf(context).height * 0.44).clamp(340.0, 440.0).toDouble();
    final cover = (p['cover_url'] ?? '') as String;
    final av = (p['avatar_url'] ?? '') as String;
    final img = cover.isNotEmpty ? cover : av;
    final g = (p['gender'] ?? '').toString();
    final female = g.contains('أنثى') || g.toLowerCase().contains('female');
    final male = g.contains('ذكر') || g.toLowerCase() == 'male';
    final age = p['age'];
    final lv = levelOf(_n('xp'));
    final top = titleIndex(lv);
    return SizedBox(
      height: h,
      child: Stack(fit: StackFit.expand, children: [
        if (img.isNotEmpty)
          Image.network(img, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _defaultCover())
        else
          _defaultCover(),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x73000000), Color(0x00000000), Color(0x00000000), Color(0xCC000000)],
              stops: [0, 0.25, 0.5, 1],
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Row(children: [
                if (!widget.embedded)
                  _roundBtn(Icons.chevron_right_rounded, () => Navigator.pop(context))
                else
                  const SizedBox(width: 40),
                const Spacer(),
                if (_isMe) ...[
                  _roundBtn(Icons.edit_rounded, _edit),
                  const SizedBox(width: 8),
                ],
                _roundBtn(Icons.more_horiz_rounded, _menu),
              ]),
            ),
          ),
        ),
        if (_live != null) Positioned(left: 0, top: h * 0.27, child: _livePill()),
        // الصورة والاسم والأرقام (يمين الغلاف)
        Positioned(
          right: 16,
          left: 16,
          bottom: 66,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: brandGradient),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                child: Avatar(name: p['name'] as String, url: av.isEmpty ? null : av, size: 76),
              ),
            ),
            const SizedBox(height: 8),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: Text(p['name'] as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                        shadows: [Shadow(blurRadius: 6, color: Colors.black54)])),
              ),
              if (p['verified'] == true) ...[
                const SizedBox(width: 6),
                const Icon(Icons.verified_rounded, color: Color(0xFF4DA3FF), size: 22),
              ],
              if (vipState(p) == 'active') ...[
                const SizedBox(width: 6),
                const Icon(Icons.diamond_rounded, color: Color(0xFFFBBF24), size: 20),
              ],
              if (age != null || male || female) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                      color: const Color(0xFFE3F1FF), borderRadius: BorderRadius.circular(14)),
                  child: Text('${age ?? ''} ${female ? '♀' : (male ? '♂' : '')}'.trim(),
                      style: TextStyle(
                          color: female ? const Color(0xFFE0407F) : const Color(0xFF3B9BFF),
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                ),
              ],
            ]),
            const SizedBox(height: 8),
            Row(mainAxisSize: MainAxisSize.min, children: [
              _pill(
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('ID:${p['num']}',
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 6),
                  const Icon(Icons.copy_rounded, size: 15, color: Colors.white70),
                ]),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: '${p['num']}'));
                  toast(context, 'تم نسخ الرقم');
                },
              ),
              const SizedBox(width: 8),
              _pill(
                Text('${_k(_n('followers'))} متابعين',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                onTap: () => _openFollows(true),
              ),
            ]),
          ]),
        ),
        // صف الألقاب أسفل الغلاف
        Positioned(
          left: 0,
          right: 0,
          bottom: 26,
          child: SizedBox(
            height: 38,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: top + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) => TitleDefImage(def: BadgeStore.titles[top - i], height: 38),
            ),
          ),
        ),
        // حافة بيضاء مدورة تتداخل مع الغلاف
        Positioned(
          left: 0,
          right: 0,
          bottom: -1,
          child: Container(
            height: 24,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _tabsRow() {
    const labels = ['المنشورات', 'الملف الشخصي', 'الشرف', 'العلاقة'];
    return Row(children: [
      for (var i = 0; i < 4; i++)
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _tab = i),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(labels[i],
                      style: TextStyle(
                          fontSize: _tab == i ? 19 : 16,
                          fontWeight: _tab == i ? FontWeight.w900 : FontWeight.w500,
                          color: _tab == i ? _ink : _sub)),
                ),
                const SizedBox(height: 4),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: _tab == i ? 22 : 0,
                  height: 3,
                  decoration: BoxDecoration(color: _violet, borderRadius: BorderRadius.circular(2)),
                ),
              ]),
            ),
          ),
        ),
    ]);
  }

  Widget _sec(String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 10),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 118, child: Text(k, style: const TextStyle(color: _sub, fontSize: 16))),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 16, height: 1.5, fontWeight: FontWeight.w500))),
        ]),
      );

  Widget _chipSoft(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: const Color(0xFFF3F3F6), borderRadius: BorderRadius.circular(22)),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      );

  void _viewPhoto(String url) => showDialog(
        context: context,
        builder: (c) => Dialog.fullscreen(
          backgroundColor: Colors.black87,
          child: GestureDetector(
            onTap: () => Navigator.pop(c),
            child: InteractiveViewer(child: Center(child: Image.network(url))),
          ),
        ),
      );

  Widget _postsTab() => Column(children: [
        const SizedBox(height: 8),
        if (_isMe)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFFE9E4FF), Color(0xFFC4E9FF)],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(children: [
              Row(children: const [
                Icon(Icons.send_rounded, size: 46, color: Color(0xFF6D7CFF)),
                SizedBox(width: 14),
                Expanded(
                  child: Text('عندما تفكر في الوقت الماضي\nماذا تريد أن تقول لنفسك',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, height: 1.7)),
                ),
              ]),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: () => toast(context, 'المنشورات قريباً ✨'),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(26)),
                  alignment: Alignment.center,
                  child: const Text('+ انشر منشور',
                      style: TextStyle(color: _violet, fontWeight: FontWeight.w900, fontSize: 17)),
                ),
              ),
            ]),
          ),
        const SizedBox(height: 50),
        Icon(Icons.photo_camera_back_rounded, size: 96, color: _violet.withValues(alpha: 0.25)),
        const SizedBox(height: 14),
        Text(_isMe ? 'لا يوجد منشور، أنشئ واحداً الآن' : 'لا يوجد منشور',
            style: const TextStyle(color: _sub, fontSize: 16)),
        const SizedBox(height: 40),
      ]);

  Widget _profileTab(Map<String, dynamic> p) {
    final photos = _plist('photos');
    final tags = _plist('tags');
    final hobbies = ((p['hobbies'] ?? []) as List).cast<String>();
    final bd = DateTime.tryParse('${_extra['birthday'] ?? ''}');
    final rows = <(String, String)>[
      if (bd != null) ('الكوكبة', _zodiac(bd)),
      if (((p['region'] ?? '') as String).isNotEmpty) ('المنطقة', p['region'] as String),
      if (((p['nationality'] ?? '') as String).isNotEmpty) ('الجنسية', p['nationality'] as String),
      if (((p['gender'] ?? '') as String).isNotEmpty) ('الجنس', p['gender'] as String),
      if (((p['language'] ?? '') as String).isNotEmpty) ('اللغة', p['language'] as String),
      if (((p['marital'] ?? '') as String).isNotEmpty) ('الحالة', p['marital'] as String),
      if (_created != null) ('العمر في نتونس', _since(_created!)),
      if (((p['bio'] ?? '') as String).isNotEmpty) ('السيرة الذاتية', p['bio'] as String),
      if (((p['interests'] ?? '') as String).isNotEmpty) ('الاهتمامات', p['interests'] as String),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (photos.isNotEmpty) ...[
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            for (final u in photos)
              GestureDetector(
                onTap: () => _viewPhoto(u),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(u, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: _line)),
                ),
              ),
          ],
        ),
      ],
      _sec('عني'),
      if (tags.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, children: [for (final t in tags) _chipSoft(t)]),
      if (tags.isNotEmpty) const SizedBox(height: 8),
      if (rows.isEmpty && tags.isEmpty)
        Text(_isMe ? 'اضغط زر التعديل في الأعلى لإضافة معلوماتك' : 'لم يضف معلومات بعد',
            style: const TextStyle(color: _sub, fontSize: 15)),
      for (final r in rows) _kv(r.$1, r.$2),
      if (hobbies.isNotEmpty) ...[
        _sec('الهوايات'),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final h in hobbies) _chipSoft(h)]),
      ],
      if (_isMe) ...[
        const SizedBox(height: 18),
        _walletCard(),
        const SizedBox(height: 10),
        _tile(Icons.edit_rounded, const [C.violet, Color(0xFF6D4AFF)], 'تعديل الملف الشخصي',
            'الصور والمعلومات والعلامات', _edit),
        _tile(Icons.flag_rounded, const [Color(0xFF6366F1), C.cyan], 'لوحة التحديات',
            'أكمل المهام اليومية',
            () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => ChallengesScreen(profile: p)))),
        if (_viewerAdmin)
          _tile(Icons.admin_panel_settings_rounded, const [Color(0xFFEF4444), C.orange],
              'لوحة المدير', 'إحصائيات وأدوات الإدارة',
              () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const AdminScreen()))),
      ],
    ]);
  }

  void _openFollows(bool followers) => Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => FollowsScreen(userId: widget.userId, followers: followers)));

  Widget _relRow(IconData icon, String label, Object v, VoidCallback? onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _lcard(
          onTap: onTap,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(children: [
            Icon(icon, color: _violet),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const Spacer(),
            Text('$v', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            if (onTap != null) ...[
              const SizedBox(width: 6),
              const Icon(Icons.chevron_left_rounded, color: _sub),
            ],
          ]),
        ),
      );

  Widget _relationTab(Map<String, dynamic> p) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(children: [
          _relRow(Icons.people_rounded, 'المتابعون', p['followers'] ?? 0, () => _openFollows(true)),
          _relRow(Icons.person_add_alt_1_rounded, 'يتابعهم', p['following'] ?? 0, () => _openFollows(false)),
          _relRow(Icons.visibility_rounded, 'زوار الملف', p['visits'] ?? 0,
              _isMe ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VisitorsScreen())) : null),
        ]),
      );

  Future<void> _share(Map<String, dynamic> p) => Share.share(
      'تعال تابعني على «نتونس» 🎙️\n${p['name']} — @${p['username']} (ID ${p['num']})');

  void _menu() {
    final p = _p!;
    Widget item(IconData i, String t, VoidCallback f) => ListTile(
          leading: Icon(i),
          title: Text(t),
          onTap: () {
            Navigator.pop(context);
            f();
          },
        );
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_isMe) ...[
              item(Icons.image_rounded, 'تغيير صورة الغلاف', _cover),
              item(Icons.settings_rounded, 'الإعدادات', () async {
                await Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
                _load();
              }),
            ] else
              item(Icons.sports_esports_rounded, 'تحدّي / مشاهدة فيلم',
                  () => showFriendActions(context, peerId: p['id'] as String, peerName: p['name'] as String)),
            item(Icons.ios_share_rounded, 'مشاركة الملف', () => _share(p)),
            if (_viewerAdmin && !_isMe) ...[
              item(Icons.verified_rounded,
                  p['verified'] == true ? 'إلغاء التوثيق' : 'توثيق الحساب', _toggleVerified),
              item(Icons.diamond_rounded, 'VIP 30 يوم', () => _vip(30)),
              item(Icons.block_rounded, 'إنهاء VIP', () => _vip(0)),
              item(Icons.trending_up_rounded, 'تعيين المستوى', _setLevel),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _bbItem(IconData icon, List<Color> colors, String label, VoidCallback onTap, {bool big = false}) {
    final s = big ? 52.0 : 40.0;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: s,
            height: s,
            decoration: BoxDecoration(
              shape: big ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: big ? null : BorderRadius.circular(12),
              gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: Icon(icon, color: Colors.white, size: big ? 30 : 24),
          ),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(fontSize: 13, color: _ink2, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget _bottomBar(Map<String, dynamic> p) {
    final f = p['is_following'] == true;
    return Container(
      padding: EdgeInsets.fromLTRB(6, 10, 6, 8 + MediaQuery.paddingOf(context).bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Color(0x1A000000), blurRadius: 16, offset: Offset(0, -2))],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        _bbItem(Icons.ios_share_rounded, const [Color(0xFFFF8A5B), Color(0xFFA855F7)], 'مشاركة', () => _share(p)),
        _bbItem(Icons.home_rounded, const [Color(0xFF8B5CF6), Color(0xFFB07CFF)], 'غرفة', () {
          if (_live != null) {
            openRoom(context, _live!);
          } else {
            toast(context, 'ليس في غرفة الآن');
          }
        }),
        _bbItem(f ? Icons.check_rounded : Icons.add_rounded, const [Color(0xFF7C3AED), Color(0xFF8B5CF6)],
            f ? 'تتابعه' : 'متابعة', _toggleFollow,
            big: true),
        _bbItem(Icons.sports_esports_rounded, const [Color(0xFF38BDF8), Color(0xFF3B82F6)], 'تحدّي',
            () => showFriendActions(context, peerId: p['id'] as String, peerName: p['name'] as String)),
        _bbItem(Icons.chat_bubble_rounded, const [Color(0xFFFF6FA8), Color(0xFFFF3D7F)], 'دردشة',
            () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      peerId: p['id'] as String,
                      peerName: p['name'] as String,
                      peerAvatar: p['avatar_url'] as String?,
                    ),
                  ),
                )),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.white,
        bottomNavigationBar: (!_loading && p != null && !_isMe) ? _bottomBar(p) : null,
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: C.pink))
            : p == null
                ? const Center(child: Text('المستخدم غير موجود', style: TextStyle(color: _ink)))
                : RefreshIndicator(
                    onRefresh: () async {
                      await _load();
                      await _loadExtra();
                    },
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        _header(p),
                        Container(
                          color: Colors.white,
                          constraints:
                              BoxConstraints(minHeight: MediaQuery.sizeOf(context).height * 0.5),
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                          child: IconTheme(
                            data: const IconThemeData(color: _ink),
                            child: DefaultTextStyle.merge(
                              style: const TextStyle(color: _ink),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                _tabsRow(),
                                const SizedBox(height: 6),
                                switch (_tab) {
                                  0 => _postsTab(),
                                  1 => _profileTab(p),
                                  2 => _honorTab(p),
                                  _ => _relationTab(p),
                                },
                                SizedBox(height: widget.embedded ? 120 : 30),
                              ]),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}


/// زر «غرفة» يظهر فقط حين يكون المستخدم داخل غرفة: نبض خفيف وأعمدة صوت متحركة.
class _LivePill extends StatefulWidget {
  final VoidCallback onTap;
  const _LivePill({required this.onTap});

  @override
  State<_LivePill> createState() => _LivePillState();
}

class _LivePillState extends State<_LivePill> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _bar(double phase, double max) {
    final t = (_c.value + phase) % 1.0;
    final h = 5 + (max - 5) * (t < 0.5 ? t * 2 : (1 - t) * 2);
    return Container(
      width: 3.5,
      height: h,
      margin: const EdgeInsets.symmetric(horizontal: 1.2),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Transform.scale(
          scale: 1 + 0.04 * _c.value,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 9, 14, 9),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFFB07CFF)]),
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(26)),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFFA855F7).withValues(alpha: 0.35 + 0.35 * _c.value),
                    blurRadius: 10 + 10 * _c.value),
              ],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                height: 20,
                child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  _bar(0.0, 18),
                  _bar(0.3, 14),
                  _bar(0.6, 18),
                ]),
              ),
              const SizedBox(width: 6),
              const Text('غرفة',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
            ]),
          ),
        ),
      ),
    );
  }
}
