import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../main.dart';
import '../widgets/ninja.dart';

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر تسجيل الدخول: $e')),
        );
      }
    } finally {
      // بعد العودة من المتصفح قد لا يصل رد؛ نعيد الأزرار بعد قليل
      await Future<void>.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _oauth(OAuthProvider p) => supa.auth.signInWithOAuth(
        p,
        redirectTo: oauthRedirect,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(flex: 2),
              const Icon(Icons.graphic_eq_rounded, size: 84),
              const SizedBox(height: 16),
              Text('KHAMIN', style: logoStyle(34)),
              const SizedBox(height: 10),
              const Text('غرف دردشة صوتية مباشرة',
                  style: TextStyle(color: Colors.white60, fontSize: 17)),
              const Spacer(flex: 2),
              NinjaButton(
                label: 'المتابعة بحساب Google',
                icon: Icons.g_mobiledata_rounded,
                onPressed: _busy ? null : () => _run(() => _oauth(OAuthProvider.google)),
              ),
              const SizedBox(height: 12),
              NinjaButton(
                label: 'المتابعة بحساب Facebook',
                icon: Icons.facebook_rounded,
                onPressed: _busy ? null : () => _run(() => _oauth(OAuthProvider.facebook)),
              ),
              const SizedBox(height: 12),
              NinjaButton(
                label: 'الدخول كزائر',
                icon: Icons.person_outline_rounded,
                outlined: true,
                onPressed: _busy ? null : () => _run(() async {
                      await supa.auth.signInAnonymously();
                    }),
              ),
              const SizedBox(height: 18),
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
