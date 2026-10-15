import 'package:flutter/material.dart';
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
import 'profile_actions.dart';
import 'settings_screen.dart';
import 'visitors_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String userId;
  final bool embedded;
  const ProfileScreen({super.key, required this.userId, this.embedded = false});

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
  int _tab = 0; // 0 الملف الشخصي، 1 الشرف، 2 المنشورات، 3 العائلة

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
                foregroundColor: Colors.white,
                side: BorderSide(color: on ? red : Colors.white24),
                padding: const EdgeInsets.symmetric(horizontal: 4)),
            child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: const TextStyle(fontSize: 12))),
          ),
        );
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: InkWell(
              onTap: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const ShopScreen()));
                _loadWallet();
              },
              child: Row(children: [
                const Icon(Icons.diamond_rounded, color: Color(0xFF67E8F9)),
                const SizedBox(width: 6),
                Text('${w?.gems ?? 0}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                const SizedBox(width: 4),
                const Text('جوهرة', style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(width: 4),
                const Icon(Icons.add_circle_rounded, size: 18, color: C.pink),
              ]),
            ),
          ),
          Container(width: 1, height: 28, color: Colors.white12),
          const SizedBox(width: 12),
          Expanded(
            child: Row(children: [
              const Icon(Icons.hexagon_rounded, color: red),
              const SizedBox(width: 6),
              Text('$rubies', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              const SizedBox(width: 4),
              const Text('ياقوت', style: TextStyle(color: Colors.white54, fontSize: 12)),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
            rubies == 0
                ? 'تحصل على ياقوتة عن كل $rubyPtsPer جوهرة تُهدى إليك (تبقى $part/$rubyPtsPer)'
                : 'ياقوتاتك تساوي ${rubies * rubyToGems} 💎  (الياقوتة = $rubyToGems 💎)',
            style: const TextStyle(color: Colors.white60, fontSize: 12)),
        const SizedBox(height: 8),
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
    _load();
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
    if (await showEditProfile(context, _p!)) await _load();
  }

  Future<void> _cover() async {
    if (await changeCover(context)) await _load();
  }

  Future<void> _avatar() async {
    if (await changeAvatar(context)) await _load();
  }

  int _n(String k) => (_p![k] as num?)?.toInt() ?? 0;

  Widget _roundBtn(IconData i, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black38,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24),
          ),
          child: Icon(i, size: 20),
        ),
      );

  Widget _cover_(Map<String, dynamic> p) {
    final cover = p['cover_url'] as String?;
    return SizedBox(
      height: 290,
      child: Stack(fit: StackFit.expand, children: [
        if (cover != null && cover.isNotEmpty)
          Image.network(cover, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _defaultCover())
        else
          _defaultCover(),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x66000000), Color(0x00000000), Color(0xFF150B30)],
              stops: [0, 0.45, 1],
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
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Row(children: [
                  if (!widget.embedded) _roundBtn(Icons.arrow_back_ios_new_rounded, () => Navigator.pop(context)),
                  const Spacer(),
                  if (_isMe) ...[
                    _roundBtn(Icons.image_rounded, _cover),
                    const SizedBox(width: 8),
                    _roundBtn(Icons.settings_rounded, () async {
                      await Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const SettingsScreen()));
                      _load();
                    }),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
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


  Widget _count(String label, Object v, VoidCallback? onTap) => Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Column(children: [
            Text('$v', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
          ]),
        ),
      );

  void _openFollows(bool followers) => Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => FollowsScreen(userId: widget.userId, followers: followers)));

  Widget _counts(Map<String, dynamic> p) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: C.glass,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: C.glassBorder),
      ),
      child: Row(children: [
        _count('المتابعون', p['followers'], () => _openFollows(true)),
        Container(width: 1, height: 32, color: Colors.white12),
        _count('يتابعهم', p['following'], () => _openFollows(false)),
        Container(width: 1, height: 32, color: Colors.white12),
        _count(
            'الزوار',
            p['visits'],
            _isMe
                ? () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const VisitorsScreen()))
                : null),
      ]),
    );
  }

  /// بطاقة الألقاب: صف واحد قابل للسحب، أصغر لقب إلى أعلى لقب وصل إليه.
  Widget _titlesCard(int lv) {
    final top = titleIndex(lv);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: C.glass,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: C.glassBorder),
      ),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.workspace_premium_rounded, size: 16, color: C.violet),
          const SizedBox(width: 6),
          const Text('الألقاب والشارات',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              gradient: brandGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('المستوى $lv',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 4),
        SizedBox(
          height: 62,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: top + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) => TitleImage(level: (top - i) * 2 + 1, height: 62),
          ),
        ),
      ]),
    );
  }

  Widget _tabs() {
    const labels = ['الملف الشخصي', 'الشرف', 'المنشورات', 'العائلة'];
    const icons = [
      Icons.person_rounded,
      Icons.shield_rounded,
      Icons.chat_bubble_rounded,
      Icons.groups_rounded,
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: C.glass,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: C.glassBorder),
      ),
      child: Row(children: [
        for (var i = 0; i < 4; i++)
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _tab = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  gradient: _tab == i ? brandGradient : null,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(children: [
                  Icon(icons[i], size: 18, color: _tab == i ? Colors.white : Colors.white54),
                  const SizedBox(height: 2),
                  Text(labels[i],
                      maxLines: 1,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _tab == i ? Colors.white : Colors.white54)),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _soon(String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(children: [
          const Icon(Icons.hourglass_empty_rounded, size: 46, color: Colors.white30),
          const SizedBox(height: 10),
          Text('$t — قريباً', style: const TextStyle(color: Colors.white54, fontSize: 16)),
        ]),
      );

  Widget _infoCell(IconData i, String label, String v) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: C.glass,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: C.glassBorder),
        ),
        child: Row(children: [
          Icon(i, size: 18, color: C.violet),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11, height: 1.2)),
              const SizedBox(height: 2),
              Text(v.isEmpty ? '—' : v,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, height: 1.2)),
            ]),
          ),
        ]),
      );

  Widget _infoGrid(Map<String, dynamic> p) {
    final age = p['age'];
    final cells = [
      _infoCell(Icons.flag_rounded, 'الجنسية', (p['nationality'] ?? '') as String),
      _infoCell(Icons.cake_rounded, 'العمر', age == null ? '' : '$age'),
      _infoCell(Icons.place_rounded, 'المنطقة', (p['region'] ?? '') as String),
      _infoCell(Icons.wc_rounded, 'الجنس', (p['gender'] ?? '') as String),
      _infoCell(Icons.translate_rounded, 'اللغة', (p['language'] ?? '') as String),
      _infoCell(Icons.favorite_rounded, 'الحالة', (p['marital'] ?? '') as String),
    ];
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        mainAxisExtent: 60,
      ),
      children: cells,
    );
  }

  Widget _profileTab(Map<String, dynamic> p) {
    final bio = ((p['bio'] ?? '') as String);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_isMe) ...[_walletCard(), const SizedBox(height: 10)],
      GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: const [
            Icon(Icons.workspace_premium_rounded, color: C.violet, size: 18),
            SizedBox(width: 6),
            Text('نبذة عني', style: TextStyle(fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 8),
          Text(bio.isEmpty ? (_isMe ? 'أضف نبذة من «تعديل الملف الشخصي»' : 'لا توجد نبذة') : bio,
              style: const TextStyle(color: Colors.white70, height: 1.5)),
        ]),
      ),
      const SizedBox(height: 10),
      _infoGrid(p),
      const SizedBox(height: 10),
      _aboutCard(p),
      const SizedBox(height: 10),
      if (_isMe) ...[
        _tile(Icons.edit_rounded, const [C.violet, Color(0xFF6D4AFF)], 'تعديل الملف الشخصي',
            'إدارة معلوماتك وصورتك', _edit),
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
        color: st == 'active' ? null : C.glass,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: st == 'active' ? Colors.white54 : C.glassBorder),
      ),
      child: Row(children: [
        Icon(Icons.diamond_rounded,
            color: st == 'active' ? Colors.white : (st == 'former' ? C.orange : Colors.white30),
            size: 30),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            Text(sub,
                style: TextStyle(
                    fontSize: 12, color: st == 'active' ? Colors.white : Colors.white60)),
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
      GlassCard(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          LevelBadge(level: lv, size: 74),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('المستوى $lv',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 22, color: Color(0xFFFDE68A))),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: prog,
                  minHeight: 7,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation(C.pink),
                ),
              ),
              const SizedBox(height: 4),
              Text('$xp / $next نقطة',
                  style: const TextStyle(color: Colors.white60, fontSize: 12)),
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
          for (var i = 0; i < titleNames.length; i++)
            Opacity(
              opacity: i <= top ? 1 : 0.25,
              child: TitleImage(level: i * 2 + 1, height: 80),
            ),
        ],
      ),
      const SizedBox(height: 14),
      Row(children: [
        const Text('الهدايا المستلمة', style: TextStyle(fontWeight: FontWeight.w800)),
        const Spacer(),
        const Icon(Icons.diamond_rounded, size: 14, color: Color(0xFF67E8F9)),
        Text(' استلم $_giftRecv · أرسل $_giftSent',
            style: const TextStyle(color: Colors.white60, fontSize: 12)),
      ]),
      const SizedBox(height: 8),
      if (_gifts.isEmpty)
        const Text('لم يستلم هدايا بعد', style: TextStyle(color: Colors.white38, fontSize: 13))
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
                  color: C.glass,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: C.glassBorder),
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
          for (var l = 1; l <= 50; l++)
            Opacity(opacity: l <= lv ? 1 : 0.25, child: LevelBadge(level: l, size: 56)),
        ],
      ),
    ]);
  }

  Widget _tile(IconData icon, List<Color> colors, String title, String sub, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
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
              Text(sub, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ]),
          ),
          const Icon(Icons.chevron_left_rounded, color: Colors.white38),
        ]),
      ),
    );
  }

  Widget _aboutCard(Map<String, dynamic> p) {
    final hobbies = ((p['hobbies'] ?? []) as List).cast<String>();
    final interests = (p['interests'] ?? '') as String;
    if (hobbies.isEmpty && interests.isEmpty && !_isMe) return const SizedBox();
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('الهوايات المفضلة', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (hobbies.isEmpty)
          Text(_isMe ? 'أضف هواياتك من «تعديل الملف الشخصي»' : 'لا شيء بعد',
              style: const TextStyle(color: Colors.white54, fontSize: 13))
        else
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final h in hobbies)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: C.violet.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: C.violet.withValues(alpha: 0.5)),
                ),
                child: Text(h, style: const TextStyle(fontSize: 13)),
              ),
          ]),
        if (interests.isNotEmpty) ...[
          const Divider(height: 24, color: Colors.white12),
          const Text('الاهتمامات', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(interests, style: const TextStyle(color: Colors.white70)),
        ],
      ]),
    );
  }

  Widget _actions(Map<String, dynamic> p) {
    return Column(children: [
      GradButton(
        label: p['is_following'] == true ? 'إلغاء المتابعة' : 'متابعة',
        icon: p['is_following'] == true ? Icons.person_remove_rounded : Icons.person_add_rounded,
        outlined: p['is_following'] == true,
        onPressed: _toggleFollow,
      ),
      const SizedBox(height: 10),
      GradButton(
        label: 'إرسال رسالة',
        icon: Icons.chat_bubble_rounded,
        outlined: true,
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              peerId: p['id'] as String,
              peerName: p['name'] as String,
              peerAvatar: p['avatar_url'] as String?,
            ),
          ),
        ),
      ),
      const SizedBox(height: 10),
      GradButton(
        label: 'تحدّي / مشاهدة فيلم',
        icon: Icons.sports_esports_rounded,
        outlined: true,
        onPressed: () =>
            showFriendActions(context, peerId: p['id'] as String, peerName: p['name'] as String),
      ),
      if (_viewerAdmin) ...[
        const SizedBox(height: 10),
        GradButton(
          label: p['verified'] == true ? 'إلغاء التوثيق' : 'توثيق الحساب',
          icon: Icons.verified_rounded,
          outlined: true,
          onPressed: _toggleVerified,
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: GradButton(
                label: 'VIP 30 يوم', icon: Icons.diamond_rounded, dense: true,
                onPressed: () => _vip(30)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GradButton(
                label: 'إنهاء VIP', outlined: true, dense: true, onPressed: () => _vip(0)),
          ),
        ]),
        const SizedBox(height: 8),
        GradButton(
            label: 'تعيين المستوى', icon: Icons.trending_up_rounded, outlined: true, dense: true,
            onPressed: _setLevel),
      ],
      const SizedBox(height: 10),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: C.pink))
          : p == null
              ? const Center(child: Text('المستخدم غير موجود'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      Stack(clipBehavior: Clip.none, children: [
                        _cover_(p),
                        Positioned(
                          top: 150,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Stack(children: [
                              Avatar(
                                  name: p['name'] as String,
                                  url: p['avatar_url'] as String?,
                                  size: 112),
                              if (_isMe)
                                Positioned(
                                  bottom: 4,
                                  right: 4,
                                  child: GestureDetector(
                                    onTap: _avatar,
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        gradient: brandGradient,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: C.bg1, width: 3),
                                      ),
                                      child: const Icon(Icons.photo_camera_rounded, size: 17),
                                    ),
                                  ),
                                ),
                            ]),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(children: [
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Flexible(
                              child: Text(p['name'] as String,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                            ),
                            if (p['verified'] == true) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.verified_rounded, color: Color(0xFF4DA3FF), size: 24),
                            ],
                            if (vipState(p) == 'active') ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.diamond_rounded, color: Color(0xFFFBBF24), size: 22),
                            ],
                          ]),
                          const SizedBox(height: 6),
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            _chip('@${p['username']}', C.cyan),
                            const SizedBox(width: 8),
                            _chip('ID ${p['num']}', C.orange),
                          ]),
                          const SizedBox(height: 14),
                          _counts(p),
                          const SizedBox(height: 10),
                          _titlesCard(levelOf(_n('xp'))),
                          const SizedBox(height: 10),
                          if (!_isMe) _actions(p),
                          _tabs(),
                          const SizedBox(height: 12),
                          Align(
                            alignment: AlignmentDirectional.topStart,
                            child: SizedBox(
                              width: double.infinity,
                              child: switch (_tab) {
                                0 => _profileTab(p),
                                1 => _honorTab(p),
                                2 => _soon('المنشورات'),
                                _ => _soon('العائلة'),
                              },
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: GradButton(
                              label: 'مشاركة ملفي الشخصي',
                              icon: Icons.ios_share_rounded,
                              outlined: true,
                              onPressed: () => Share.share(
                                  'تعال تابعني على «نتونس» 🎙️\n${p['name']} — @${p['username']} (ID ${p['num']})'),
                            ),
                          ),
                          const SizedBox(height: 120),
                        ]),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _chip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(t,
            textDirection: TextDirection.ltr,
            style: TextStyle(color: c, fontWeight: FontWeight.w700)),
      );
}
