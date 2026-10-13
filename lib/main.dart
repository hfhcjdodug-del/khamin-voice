import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'screens/home_screen.dart';
import 'screens/sign_in_screen.dart';

SupabaseClient get supa => Supabase.instance.client;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0A0A0A),
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
      title: 'خمّن',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      theme: base.copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          onPrimary: Colors.black,
          secondary: Color(0xFF4ADE80),
          surface: Color(0xFF151515),
        ),
        textTheme: GoogleFonts.rajdhaniTextTheme(base.textTheme),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0A0A0A),
          elevation: 0,
          centerTitle: true,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF151515),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
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
        return session == null ? const SignInScreen() : const HomeScreen();
      },
    );
  }
}
