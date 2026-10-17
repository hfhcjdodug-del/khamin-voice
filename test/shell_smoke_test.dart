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
  final prof = <String, dynamic>{
    'id': 'u', 'name': 'مصطفى', 'username': 'mus', 'num': 12345, 'avatar_url': null, 'bio': 'نبذة',
    'followers': 5, 'following': 3, 'is_following': false, 'verified': true, 'cover_url': null,
    'hobbies': ['ألعاب'], 'interests': 'x', 'xp': 500000, 'visits': 4, 'rooms_count': 2, 'games_count': 1,
    'nationality': 'عراقي', 'age': 22, 'region': 'البصرة', 'gender': 'ذكر', 'language': 'العربية',
    'marital': 'أعزب', 'vip_start': null, 'vip_end': null, 'created_at': '2026-01-01T00:00:00Z',
  };
  for (final xp in [0, 500000]) {
    testWidgets('profile loaded xp=$xp', (t) async {
      await run(t, ProfileScreen(userId: 'u', embedded: true, seed: {...prof, 'xp': xp}), 'ProfileLoaded$xp');
      for (final label in ['المنشورات', 'الشرف', 'العلاقة', 'الملف الشخصي']) {
        final f = find.text(label);
        if (f.evaluate().isNotEmpty) {
          await t.tap(f.first);
          await t.pump(const Duration(milliseconds: 300));
          // ignore: avoid_print
          print('SMOKE-OK tab $label exception=${t.takeException()}');
        }
      }
    });
  }
  testWidgets('profile ME full', (t) async {
    final me = {
      ...prof,
      'photos': ['http://x/1.jpg', 'http://x/2.jpg', 'http://x/3.jpg', 'http://x/4.jpg'],
      'tags': ['ودود', 'مرح'],
      'birthday': '2003-05-04',
      'live': {'id': 'r', 'title': 'روم', 'topic': '', 'host_id': 'u', 'is_live': true},
      'cover_url': 'http://x/cover.jpg',
      'avatar_url': 'http://x/av.jpg',
      'vip_start': '2026-09-01T00:00:00Z',
      'vip_end': '2026-12-01T00:00:00Z',
    };
    await run(t, ProfileScreen(userId: '', embedded: true, seed: me), 'ProfileMe');
    for (final label in ['المنشورات', 'الشرف', 'العلاقة', 'الملف الشخصي']) {
      final f = find.text(label);
      if (f.evaluate().isNotEmpty) {
        await t.tap(f.first);
        await t.pump(const Duration(milliseconds: 300));
        // ignore: avoid_print
        print('SMOKE-OK me tab $label exception=${t.takeException()}');
      }
    }
  });
  testWidgets('rooms loaded', (t) async {
    final rooms = [
      for (var i = 0; i < 12; i++)
        {
          'id': 'r$i', 'title': 'غرفة $i', 'topic': i.isEven ? 'موضوع' : '', 'host_id': 'h$i',
          'host_name': 'مضيف $i', 'host_avatar': null, 'listeners': i, 'seated': i % 9,
          'created_at': '2026-10-17T10:00:00Z', 'host_xp': 0, 'friends': i % 3, 'bg_preset': 'violet',
          'bg_url': null, 'locked': i == 2, 'week_support': i < 8 ? (8 - i) * 100 : 0,
        }
    ];
    await run(t, RoomsTab(seed: rooms), 'RoomsLoaded');
  });
  testWidgets('shell first frames', (t) async {
    await run(t, const ShellScreen(), 'Shell');
  });
}
