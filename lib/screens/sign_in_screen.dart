import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
import 'dart:ui' show ImageFilter;

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
      body: Stack(fit: StackFit.expand, children: [
        const _LoginBackdrop(),
        SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(children: [
            const Spacer(flex: 2),
            ShaderMask(
              shaderCallback: (r) => const LinearGradient(
                colors: [Colors.white, Color(0xFFD9C2FF)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ).createShader(r),
              child: Text('نستأنس',
                  style: TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    shadows: [
                      Shadow(color: C.violet.withValues(alpha: 0.9), blurRadius: 26),
                      const Shadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 3)),
                    ],
                  )),
            ),
            const SizedBox(height: 10),
            const Text('خمّن الشخصية وتحدَّ أصدقاءك',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(color: Colors.black87, blurRadius: 10)])),
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
      ]),
    );
  }
}

/// خلفية شاشة الدخول: فيديو يرفعه المدير (مكتوم وبتمويه خفيف)، وإلا تدرّج بنفسجي.
class _LoginBackdrop extends StatefulWidget {
  const _LoginBackdrop();

  @override
  State<_LoginBackdrop> createState() => _LoginBackdropState();
}

class _LoginBackdropState extends State<_LoginBackdrop> {
  VideoPlayerController? _c;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final url = (await supa.rpc('login_media'))?.toString() ?? '';
      if (url.isEmpty || !mounted) return;
      final c = VideoPlayerController.networkUrl(Uri.parse(url),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
      _c = c;
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      await c.play();
      if (mounted) setState(() => _ready = true);
    } catch (_) {}
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Stack(fit: StackFit.expand, children: [
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF3B0F7A), Color(0xFF12062B)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
      ),
      if (_ready && c != null)
        ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c)),
          ),
        ),
      if (_ready)
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF12062B).withValues(alpha: 0.55),
                  const Color(0xFF12062B).withValues(alpha: 0.78),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),
    ]);
  }
}
