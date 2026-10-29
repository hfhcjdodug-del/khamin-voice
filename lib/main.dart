import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ads.dart';
import 'config.dart';
import 'push.dart';
import 'screens/shell_screen.dart';
import 'screens/sign_in_screen.dart';
import 'theme.dart';

SupabaseClient get supa => Supabase.instance.client;
String get myId => supa.auth.currentUser?.id ?? '';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0A1030),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  // نعرض شاشة فوراً ثم نجهّز الخلفية، حتى لا يبقى التطبيق معلّقاً بلا أي إشارة لو تأخر الاتصال.
  runApp(const _Boot());
}

class _Boot extends StatefulWidget {
  const _Boot();

  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() => _error = null);
    try {
      await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey)
          .timeout(const Duration(seconds: 20));
      initPush();
      initAds();
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return const KhaminApp();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: const Color(0xFF12111C),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: _error == null
                  ? const Column(mainAxisSize: MainAxisSize.min, children: [
                      CircularProgressIndicator(color: Color(0xFF8B5CF6)),
                      SizedBox(height: 16),
                      Text('جارٍ التشغيل…', style: TextStyle(color: Colors.white70)),
                    ])
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.wifi_off_rounded, color: Colors.white54, size: 56),
                      const SizedBox(height: 12),
                      const Text('تعذّر الاتصال بالخادم',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Text(_error!,
                          maxLines: 6,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      const SizedBox(height: 16),
                      FilledButton(onPressed: _init, child: const Text('إعادة المحاولة')),
                    ]),
            ),
          ),
        ),
      ),
    );
  }
}

class KhaminApp extends StatelessWidget {
  const KhaminApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData.dark(useMaterial3: true);
    return MaterialApp(
      title: 'نستأنس',
      scaffoldMessengerKey: messengerKey,
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: GradientBg(child: child!),
      ),
      theme: base.copyWith(
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: const Color(0xFF1B1040),
        colorScheme: const ColorScheme.dark(
          primary: C.violet,
          secondary: C.pink,
          surface: Color(0xFF1B1040),
        ),
        textTheme: GoogleFonts.cairoTextTheme(base.textTheme),
        dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF1B1040)),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Color(0xFF1B1040),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: C.glass,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
        pageTransitionsTheme: const PageTransitionsTheme(builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        }),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: supa.auth.onAuthStateChange,
      builder: (context, snap) {
        final session = snap.data?.session ?? supa.auth.currentSession;
        return session == null ? const SignInScreen() : const ShellScreen();
      },
    );
  }
}
