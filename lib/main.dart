import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'game_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Color(0xFF0C0A13),
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0C0A13),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const KhaminApp());
}

class KhaminApp extends StatelessWidget {
  const KhaminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'خمّن الشخصية',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0C0A13),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFF0B06C),
          secondary: Color(0xFFA493FF),
          surface: Color(0xFF171320),
        ),
      ),
      home: const GameScreen(),
    );
  }
}
