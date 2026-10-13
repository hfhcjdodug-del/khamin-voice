import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../main.dart';
import '../media.dart';
import '../theme.dart';
import 'admin_screen.dart';
import 'challenge.dart';
import 'chat_screen.dart';

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
  bool _admin = false;
  bool _viewerAdmin = false;

  bool get _isMe => widget.userId == myId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final a = await supa.rpc('am_i_admin');
      if (mounted) setState(() {
        _viewerAdmin = a == true;
        _admin = _isMe && a == true;
      });
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

  Future<void> _changeAvatar() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 600, imageQuality: 85);
    if (f == null) return;
    try {
      final bytes = await f.readAsBytes();
      final ext = extOf(f.name, ['jpg', 'jpeg', 'png', 'webp'], 'jpg');
      final url = await uploadMedia(
        bucket: 'avatars',
        folder: myId,
        bytes: bytes,
        ext: ext,
        contentType: 'image/${ext == 'jpg' ? 'jpeg' : ext}',
      );
      await supa.from('profiles').update({'avatar_url': url}).eq('id', myId);
      await _load();
      if (mounted) toast(context, 'تم تغيير الصورة');
    } catch (e) {
      if (mounted) toast(context, 'تعذّر رفع الصورة: ${friendlyError(e)}');
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
    final p = _p!;
    final name = TextEditingController(text: p['name'] as String);
    final user = TextEditingController(text: p['username'] as String);
    final bio = TextEditingController(text: (p['bio'] ?? '') as String);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(c).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('تعديل الملف الشخصي',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            TextField(
              controller: name,
              maxLength: 40,
              decoration: const InputDecoration(labelText: 'الاسم'),
            ),
            TextField(
              controller: user,
              maxLength: 20,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(labelText: 'اليوزر (إنكليزي)', prefixText: '@'),
            ),
            TextField(
              controller: bio,
              maxLength: 150,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'نبذة عنك'),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: GradButton(label: 'حفظ', onPressed: () => Navigator.pop(c, true)),
            ),
          ]),
        ),
      ),
    );
    if (ok != true) return;
    final n = name.text.trim();
    if (n.length < 2) {
      if (mounted) toast(context, 'الاسم قصير');
      return;
    }
    try {
      await supa.from('profiles').update({
        'name': n,
        'username': user.text.trim(),
        'bio': bio.text.trim(),
      }).eq('id', myId);
      await _load();
      if (mounted) toast(context, 'تم الحفظ');
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تسجيل الخروج؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('خروج')),
        ],
      ),
    );
    if (ok == true) await supa.auth.signOut();
  }

  Widget _stat(IconData icon, Color c, String label, Object v) => Expanded(
        child: Column(children: [
          Icon(icon, color: c, size: 22),
          const SizedBox(height: 4),
          Text('$v', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 13)),
        ]),
      );

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

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('الملف الشخصي')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: C.pink))
          : p == null
              ? const Center(child: Text('المستخدم غير موجود'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      // الهالة العلوية
                      Stack(clipBehavior: Clip.none, children: [
                        Container(
                          height: 250,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                C.violet.withValues(alpha: 0.55),
                                C.pink.withValues(alpha: 0.22),
                                Colors.transparent,
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 60,
                          left: -50,
                          child: Container(
                            width: 180,
                            height: 180,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: C.cyan.withValues(alpha: 0.10),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: SafeArea(
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 22),
                                child: Stack(children: [
                                  Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: const LinearGradient(
                                          colors: [C.violet, C.pink, C.cyan]),
                                      boxShadow: [
                                        BoxShadow(
                                            color: C.violet.withValues(alpha: 0.6),
                                            blurRadius: 36),
                                      ],
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: const BoxDecoration(
                                          shape: BoxShape.circle, color: C.bg1),
                                      child: Avatar(
                                          name: p['name'] as String,
                                          url: p['avatar_url'] as String?,
                                          size: 118),
                                    ),
                                  ),
                                  if (_isMe)
                                    Positioned(
                                      bottom: 2,
                                      right: 2,
                                      child: GestureDetector(
                                        onTap: _changeAvatar,
                                        child: Container(
                                          padding: const EdgeInsets.all(9),
                                          decoration: BoxDecoration(
                                            gradient: brandGradient,
                                            shape: BoxShape.circle,
                                            border: Border.all(color: C.bg1, width: 3),
                                          ),
                                          child: const Icon(Icons.photo_camera_rounded, size: 18),
                                        ),
                                      ),
                                    ),
                                ]),
                              ),
                            ),
                          ),
                        ),
                      ]),
                      Transform.translate(
                        offset: const Offset(0, -34),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
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
                            const SizedBox(height: 20),
                            GlassCard(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Row(children: [
                                _stat(Icons.groups_rounded, C.violet, 'متابِعون', p['followers']),
                                Container(width: 1, height: 52, color: Colors.white12),
                                _stat(Icons.person_rounded, C.cyan, 'يتابع', p['following']),
                              ]),
                            ),
                            const SizedBox(height: 18),
                            if (_isMe) ...[
                              _tile(Icons.edit_rounded, const [C.violet, Color(0xFF6D4AFF)],
                                  'تعديل الملف الشخصي', 'الاسم، اليوزر، النبذة', _edit),
                              if (_admin)
                                _tile(
                                  Icons.admin_panel_settings_rounded,
                                  const [C.orange, C.pink],
                                  'لوحة المدير',
                                  'إحصائيات وأدوات الإدارة',
                                  () => Navigator.push(context,
                                      MaterialPageRoute(builder: (_) => const AdminScreen())),
                                ),
                              _tile(Icons.logout_rounded, const [Color(0xFF64748B), Color(0xFF475569)],
                                  'تسجيل الخروج', 'إنهاء الجلسة', _signOut),
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
                            ],
                            const SizedBox(height: 24),
                          ]),
                        ),
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
