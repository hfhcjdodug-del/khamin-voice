import 'package:flutter/material.dart';

import '../main.dart';
import '../theme.dart';
import 'admin_screen.dart';
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

  bool get _isMe => widget.userId == myId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_isMe) {
      try {
        final a = await supa.rpc('am_i_admin');
        if (mounted) setState(() => _admin = a == true);
      } catch (_) {}
    }
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

  Widget _stat(String label, Object v) => Column(children: [
        Text('$v', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 13)),
      ]);

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(title: const Text('الملف الشخصي')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: C.pink))
            : p == null
                ? const Center(child: Text('المستخدم غير موجود'))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                      children: [
                        Center(
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                    color: C.violet.withValues(alpha: 0.5), blurRadius: 40),
                              ],
                            ),
                            child: Avatar(
                                name: p['name'] as String,
                                url: p['avatar_url'] as String?,
                                size: 104),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Center(
                          child: Text(p['name'] as String,
                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                        ),
                        const SizedBox(height: 6),
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          _chip('@${p['username']}', C.cyan),
                          const SizedBox(width: 8),
                          _chip('ID ${p['num']}', C.orange),
                        ]),
                        if (((p['bio'] ?? '') as String).isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Text(p['bio'] as String,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white70, fontSize: 15)),
                        ],
                        const SizedBox(height: 22),
                        GlassCard(
                          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                            _stat('متابِعون', p['followers']),
                            Container(width: 1, height: 36, color: Colors.white12),
                            _stat('يتابع', p['following']),
                          ]),
                        ),
                        const SizedBox(height: 18),
                        if (_isMe) ...[
                          GradButton(label: 'تعديل الملف الشخصي', icon: Icons.edit_rounded, onPressed: _edit),
                          const SizedBox(height: 12),
                          if (_admin) ...[
                            GradButton(
                              label: 'لوحة المدير',
                              icon: Icons.admin_panel_settings_rounded,
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const AdminScreen()),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          GradButton(
                              label: 'تسجيل الخروج',
                              icon: Icons.logout_rounded,
                              outlined: true,
                              onPressed: _signOut),
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
                        ],
                      ],
                    ),
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
