import 'package:flutter/material.dart';

import '../main.dart';
import '../theme.dart';
import '../push.dart';
import 'profile_actions.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Widget _row(BuildContext c, IconData i, String t, {String? sub, VoidCallback? onTap, Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Icon(i, color: color ?? C.violet),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
              if (sub != null)
                Text(sub, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ]),
          ),
          if (onTap != null) const Icon(Icons.chevron_left_rounded, color: Colors.white38),
        ]),
      ),
    );
  }

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
        child: Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
      );

  Future<void> _signOut(BuildContext context) async {
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
    if (ok == true) {
      if (context.mounted) Navigator.popUntil(context, (r) => r.isFirst);
      await supa.auth.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = supa.auth.currentUser;
    final provider = (user?.appMetadata['provider'] ?? 'غير معروف').toString();
    final isGuest = user?.isAnonymous == true;
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات', style: TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
        _title('الحساب'),
        _row(context, Icons.photo_camera_rounded, 'تغيير الصورة الشخصية',
            onTap: () => changeAvatar(context)),
        _row(context, Icons.image_rounded, 'تغيير صورة الغلاف',
            onTap: () => changeCover(context)),
        _row(context, Icons.security_rounded, 'الحساب والأمان',
            sub: isGuest ? 'دخول كضيف' : 'مسجّل عبر $provider',
            onTap: () => showDialog<void>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('الحساب والأمان'),
                    content: Text(isGuest
                        ? 'أنت داخل كضيف. إذا سجّلت خروجك قد تفقد حسابك. سجّل بحساب Google أو Facebook للاحتفاظ به.'
                        : 'تسجيل الدخول عبر $provider.\nلا نخزّن كلمة سر لحسابك في التطبيق.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c), child: const Text('حسناً'))
                    ],
                  ),
                )),
        _title('التطبيق'),
        _row(context, Icons.notifications_rounded, 'إشعارات التطبيق',
            sub: 'إعلانات وتحديثات من الإدارة',
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const NoticesScreen()))),
        _row(context, Icons.lock_rounded, 'الخصوصية', sub: 'قريباً'),
        _row(context, Icons.language_rounded, 'اللغة', sub: 'العربية'),
        _row(context, Icons.headset_mic_rounded, 'المساعدة', sub: 'قريباً'),
        _row(context, Icons.info_rounded, 'حول التطبيق',
            onTap: () => showAboutDialog(
                  context: context,
                  applicationName: 'نستأنس',
                  applicationVersion: '1.0.0',
                  children: const [
                    Text(
                        'دردشة صوتية وألعاب ومشاهدة أفلام مع الأصدقاء.\n\nThis product uses the TMDB API but is not endorsed or certified by TMDB.'),
                  ],
                )),
        const SizedBox(height: 16),
        _row(context, Icons.logout_rounded, 'تسجيل الخروج',
            color: const Color(0xFFFF6B6B), onTap: () => _signOut(context)),
      ]),
    );
  }
}
