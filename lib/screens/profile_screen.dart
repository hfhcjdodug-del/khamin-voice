import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../level.dart';
import '../main.dart';
import '../theme.dart';
import 'admin_screen.dart';
import 'challenge.dart';
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

  bool get _isMe => widget.userId == myId;

  @override
  void initState() {
    super.initState();
    _load();
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

  Widget _stat(IconData icon, Color c, String label, Object v, {VoidCallback? onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: C.glass,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: C.glassBorder),
          ),
          child: Column(children: [
            Icon(icon, color: c, size: 20),
            const SizedBox(height: 2),
            Text('$v', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
          ]),
        ),
      ),
    );
  }

  Widget _levelCard() {
    final xp = _n('xp');
    final lv = levelOf(xp);
    final tier = tierOf(lv);
    final base = levelBase(lv);
    final next = levelNext(lv);
    final prog = ((xp - base) / (next - base)).clamp(0.0, 1.0);
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: tier.colors),
            boxShadow: [BoxShadow(color: tier.colors.first.withValues(alpha: 0.5), blurRadius: 16)],
          ),
          child: const Icon(Icons.workspace_premium_rounded, size: 30),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('المستوى ${tier.name}',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: prog,
                minHeight: 7,
                backgroundColor: Colors.white12,
                valueColor: const AlwaysStoppedAnimation(C.violet),
              ),
            ),
            const SizedBox(height: 4),
            Text('$xp / $next نقطة',
                style: const TextStyle(color: Colors.white60, fontSize: 12)),
          ]),
        ),
        const SizedBox(width: 12),
        Column(children: [
          Text('$lv', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
          const Text('مستوى', style: TextStyle(color: Colors.white60, fontSize: 12)),
        ]),
      ]),
    );
  }

  Widget _badgesRow(Map<String, dynamic> p) {
    final earned = achievements.where((a) => a.test(p)).toList();
    final rest = achievements.where((a) => !a.test(p)).toList();
    final show = [...earned, ...rest].take(4).toList();
    return GestureDetector(
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => AchievementsScreen(profile: p))),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        for (final a in show) AchBadge(a: a, earned: a.test(p), size: 50),
      ]),
    );
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
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const LinearGradient(colors: [C.violet, C.pink, C.cyan]),
                                  boxShadow: [
                                    BoxShadow(color: C.violet.withValues(alpha: 0.7), blurRadius: 34),
                                  ],
                                ),
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: const BoxDecoration(shape: BoxShape.circle, color: C.bg1),
                                  child: Avatar(
                                      name: p['name'] as String,
                                      url: p['avatar_url'] as String?,
                                      size: 110),
                                ),
                              ),
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
                      const SizedBox(height: 62),
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
                          ]),
                          const SizedBox(height: 6),
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            _chip('@${p['username']}', C.cyan),
                            const SizedBox(width: 8),
                            _chip('ID ${p['num']}', C.orange),
                          ]),
                          if (((p['bio'] ?? '') as String).isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              const Icon(Icons.graphic_eq_rounded, color: C.violet, size: 18),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(p['bio'] as String,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.white70, fontSize: 15)),
                              ),
                            ]),
                          ],
                          const SizedBox(height: 18),
                          _levelCard(),
                          const SizedBox(height: 12),
                          Row(children: [
                            _stat(Icons.person_rounded, C.cyan, 'يتابعون', p['following']),
                            const SizedBox(width: 10),
                            _stat(Icons.local_fire_department_rounded, C.orange, 'زوار', p['visits'],
                                onTap: _isMe
                                    ? () => Navigator.push(context,
                                        MaterialPageRoute(builder: (_) => const VisitorsScreen()))
                                    : null),
                            const SizedBox(width: 10),
                            _stat(Icons.groups_rounded, C.violet, 'متابعين', p['followers']),
                          ]),
                          const SizedBox(height: 16),
                          _badgesRow(p),
                          const SizedBox(height: 16),
                          if (_isMe) ...[
                            _tile(Icons.edit_rounded, const [C.violet, Color(0xFF6D4AFF)],
                                'تعديل الملف الشخصي', 'إدارة معلوماتك وصورتك', _edit),
                            _tile(
                              Icons.flag_rounded,
                              const [Color(0xFF6366F1), C.cyan],
                              'لوحة التحديات',
                              'أكمل المهام اليومية',
                              () => Navigator.push(
                                  context, MaterialPageRoute(builder: (_) => ChallengesScreen(profile: p))),
                            ),
                            _tile(
                              Icons.emoji_events_rounded,
                              const [C.orange, C.pink],
                              'الإنجازات',
                              'شاراتك ونجومك في التطبيق',
                              () => Navigator.push(
                                  context, MaterialPageRoute(builder: (_) => AchievementsScreen(profile: p))),
                            ),
                            if (_viewerAdmin)
                              _tile(
                                Icons.admin_panel_settings_rounded,
                                const [Color(0xFFEF4444), C.orange],
                                'لوحة المدير',
                                'إحصائيات وأدوات الإدارة',
                                () => Navigator.push(
                                    context, MaterialPageRoute(builder: (_) => const AdminScreen())),
                              ),
                          ] else ...[
                            GradButton(
                              label: p['is_following'] == true ? 'إلغاء المتابعة' : 'متابعة',
                              icon: p['is_following'] == true
                                  ? Icons.person_remove_rounded
                                  : Icons.person_add_rounded,
                              outlined: p['is_following'] == true,
                              onPressed: _toggleFollow,
                            ),
                            const SizedBox(height: 12),
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
                            const SizedBox(height: 12),
                            GradButton(
                              label: 'تحدّي / مشاهدة فيلم',
                              icon: Icons.sports_esports_rounded,
                              outlined: true,
                              onPressed: () => showFriendActions(context,
                                  peerId: p['id'] as String, peerName: p['name'] as String),
                            ),
                            if (_viewerAdmin) ...[
                              const SizedBox(height: 12),
                              GradButton(
                                label: p['verified'] == true ? 'إلغاء التوثيق' : 'توثيق الحساب',
                                icon: Icons.verified_rounded,
                                outlined: true,
                                onPressed: _toggleVerified,
                              ),
                            ],
                            const SizedBox(height: 10),
                          ],
                          _aboutCard(p),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              gradient: const LinearGradient(
                                colors: [Color(0xFF1B1F6B), Color(0xFF5B21B6)],
                              ),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: const [
                              Text('كن دائماً كما أنت',
                                  style: TextStyle(
                                      color: Color(0xFFFBBF24), fontWeight: FontWeight.w900, fontSize: 17)),
                              SizedBox(height: 4),
                              Text('فأنت مميز بطريقتك الخاصة',
                                  style: TextStyle(color: Colors.white70, fontSize: 13)),
                            ]),
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
