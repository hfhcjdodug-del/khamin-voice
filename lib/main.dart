import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'screens/shell_screen.dart';
import 'screens/sign_in_screen.dart';
import 'theme.dart';

SupabaseClient get supa => Supabase.instance.client;
String get myId => supa.auth.currentUser!.id;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0A1030),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  runApp(const KhaminApp());
}

class KhaminApp extends StatelessWidget {
  const KhaminApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData.dark(useMaterial3: true);
    return MaterialApp(
      title: 'نتونس',
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
