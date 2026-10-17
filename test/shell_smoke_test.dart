import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:khamin_voice/screens/rooms_tab.dart';
import 'package:khamin_voice/screens/shell_screen.dart';
import 'package:khamin_voice/screens/profile_screen.dart';
import 'package:khamin_voice/theme.dart';

Widget _app(Widget child) => MaterialApp(
      locale: const Locale('ar'),
      builder: (c, ch) => Directionality(textDirection: TextDirection.rtl, child: GradientBg(child: ch!)),
      home: child,
    );

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://localhost:1',
      anonKey: 'x',
      authOptions: const FlutterAuthClientOptions(localStorage: EmptyLocalStorage(), autoRefreshToken: false),
    );
  });

  Future<void> run(WidgetTester t, Widget w, String name) async {
    await t.pumpWidget(_app(w));
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 400));
    }
    // ignore: avoid_print
    print('SMOKE-OK $name exception=${t.takeException()}');
  }

  testWidgets('rooms tab first frames', (t) async {
    await run(t, const RoomsTab(), 'RoomsTab');
  });
  testWidgets('profile first frames', (t) async {
    await run(t, const ProfileScreen(userId: 'u', embedded: true), 'Profile');
  });
  testWidgets('shell first frames', (t) async {
    await run(t, const ShellScreen(), 'Shell');
  });
}
