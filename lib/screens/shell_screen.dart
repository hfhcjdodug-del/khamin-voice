import 'dart:async';

import 'package:flutter/material.dart';

import '../play_gate.dart';
import '../push.dart';
import 'tutorial_screen.dart';
import '../theme.dart';
import 'guess_match_screen.dart';
import 'friends_tab.dart';
import 'games_tab.dart';
import 'messages_tab.dart';
import 'profile_screen.dart';
import '../main.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _i = 0;
  Timer? _timer;
  final _seen = <String>{};
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _checkInvites());
    _checkInvites();
    NoticeListener.start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeShowTutorial(context);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    NoticeListener.stop();
    super.dispose();
  }

  Future<void> _checkInvites() async {
    if (_dialogOpen || !mounted) return;
    try {
      final games = List<Map<String, dynamic>>.from(await supa.rpc('my_invites') as List);
      Map<String, dynamic>? g;
      for (final x in games) {
        if (!_seen.contains('g${x['id']}')) {
          g = x;
          break;
        }
      }
      if (g != null) {
        _seen.add('g${g['id']}');
        await _ask(
          name: g['from_name'] as String,
          text: 'يتحداك في «خمّن الشخصية» · ${g['category_name']}',
          icon: Icons.sports_esports_rounded,
          onAccept: () async {
            if (!await ensureCanPlay(context)) return;
            final mid = await supa.rpc('accept_invite', params: {'p_id': g!['id']});
            if (!mounted) return;
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => GuessMatchScreen(matchId: mid as String)));
          },
          onDecline: () => supa.rpc('decline_invite', params: {'p_id': g!['id']}),
        );
      }
    } catch (_) {}
  }

  Future<void> _ask({
    required String name,
    required String text,
    required IconData icon,
    required Future<void> Function() onAccept,
    required Future<dynamic> Function() onDecline,
  }) async {
    if (!mounted) return;
    _dialogOpen = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: Icon(icon, color: C.pink, size: 36),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Text(text, textAlign: TextAlign.center),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('رفض')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('قبول')),
        ],
      ),
    );
    _dialogOpen = false;
    try {
      if (ok == true) {
        await onAccept();
      } else {
        await onDecline();
      }
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Widget _navItem(int idx, IconData icon, IconData sel, String label) {
    final on = _i == idx;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _i = idx),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(on ? sel : icon, color: on ? C.pink : Colors.white54, size: 22),
          const SizedBox(height: 1),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: on ? FontWeight.w800 : FontWeight.w500,
                  color: on ? Colors.white : Colors.white54)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _scaffold();

  Widget _scaffold() {
    return Scaffold(
      body: IndexedStack(index: _i, children: [
        GamesTab(active: _i == 0),
        MessagesTab(active: _i == 1),
        FriendsTab(active: _i == 2),
        ProfileScreen(userId: myId, embedded: true),
      ]),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xF20F0A26),
          border: const Border(top: BorderSide(color: C.glassBorder)),
          boxShadow: [BoxShadow(color: C.violet.withValues(alpha: 0.2), blurRadius: 20)],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 50,
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              _navItem(0, Icons.sports_esports_outlined, Icons.sports_esports_rounded, 'ألعاب'),
              _navItem(1, Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'المحادثات'),
              _navItem(2, Icons.people_outline_rounded, Icons.people_rounded, 'الأصدقاء'),
              _navItem(3, Icons.person_outline_rounded, Icons.person_rounded, 'حسابي'),
            ]),
          ),
        ),
      ),
    );
  }
}


