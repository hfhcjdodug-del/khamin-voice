import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../main.dart';
import '../theme.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      toast(context, 'تعذّر تسجيل الدخول: ${friendlyError(e)}');
    } finally {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _oauth(OAuthProvider p) => supa.auth.signInWithOAuth(
        p,
        redirectTo: oauthRedirect,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );

  Widget _social(String label, IconData icon, Color color, VoidCallback? onTap) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 10),
            Text(label,
                style: const TextStyle(
                    color: Color(0xFF1B1040), fontSize: 16, fontWeight: FontWeight.w800)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(children: [
            const Spacer(flex: 2),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(34),
                boxShadow: [
                  BoxShadow(color: C.violet.withValues(alpha: 0.55), blurRadius: 44),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(34),
                child: Image.asset('assets/logo.png', width: 130, height: 130),
              ),
            ),
            const SizedBox(height: 22),
            const Text('نتونس',
                style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text('تحدّث، تعرّف، واستمتع بغرف صوتية مباشرة',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 16)),
            const Spacer(flex: 2),
            _social('المتابعة بحساب Google', Icons.g_mobiledata_rounded, const Color(0xFFEA4335),
                _busy ? null : () => _run(() => _oauth(OAuthProvider.google))),
            const SizedBox(height: 12),
            _social('المتابعة بحساب Facebook', Icons.facebook_rounded, const Color(0xFF1877F2),
                _busy ? null : () => _run(() => _oauth(OAuthProvider.facebook))),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: GradButton(
                label: 'الدخول كزائر',
                icon: Icons.person_outline_rounded,
                outlined: true,
                onPressed: _busy ? null : () => _run(() async {
                      await supa.auth.signInAnonymously();
                    }),
              ),
            ),
            const SizedBox(height: 18),
            if (_busy) const LinearProgressIndicator(minHeight: 2, color: C.pink),
            const Spacer(),
          ]),
        ),
      ),
    );
  }
}
