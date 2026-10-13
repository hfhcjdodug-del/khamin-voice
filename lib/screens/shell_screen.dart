import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'games_tab.dart';
import 'guess_match_screen.dart';
import 'movies_tab.dart';
import 'watch_screen.dart';
import 'messages_tab.dart';
import 'profile_screen.dart';
import 'rooms_tab.dart';
import 'search_tab.dart';
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
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _checkInvites() async {
    if (_dialogOpen || !mounted) return;
    try {
      final games = List<Map<String, dynamic>>.from(await supa.rpc('my_invites') as List);
      final parties = List<Map<String, dynamic>>.from(await supa.rpc('party_invites') as List);
      Map<String, dynamic>? g;
      for (final x in games) {
        if (!_seen.contains('g${x['id']}')) {
          g = x;
          break;
        }
      }
      Map<String, dynamic>? w;
      for (final x in parties) {
        if (!_seen.contains('w${x['id']}')) {
          w = x;
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
            final mid = await supa.rpc('accept_invite', params: {'p_id': g!['id']});
            if (!mounted) return;
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => GuessMatchScreen(matchId: mid as String)));
          },
          onDecline: () => supa.rpc('decline_invite', params: {'p_id': g!['id']}),
        );
      } else if (w != null) {
        _seen.add('w${w['id']}');
        await _ask(
          name: w['host_name'] as String,
          text: 'يدعوك لمشاهدة «${w['movie_title']}» معه',
          icon: Icons.movie_rounded,
          onAccept: () async {
            await supa.rpc('party_accept', params: {'p_id': w!['id']});
            if (!mounted) return;
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => WatchScreen(partyId: w!['id'] as String, host: false)));
          },
          onDecline: () => supa.rpc('party_decline', params: {'p_id': w!['id']}),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _i, children: [
        const RoomsTab(),
        GamesTab(active: _i == 1),
        MoviesTab(active: _i == 2),
        const SearchTab(),
        MessagesTab(active: _i == 4),
        ProfileScreen(userId: myId, embedded: true),
      ]),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xE60F0A26),
          border: Border(top: BorderSide(color: C.glassBorder)),
        ),
        child: NavigationBar(
          backgroundColor: Colors.transparent,
          indicatorColor: C.violet.withValues(alpha: 0.35),
          selectedIndex: _i,
          onDestinationSelected: (v) => setState(() => _i = v),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.mic_none_rounded),
                selectedIcon: Icon(Icons.mic_rounded),
                label: 'الغرف'),
            NavigationDestination(
                icon: Icon(Icons.sports_esports_outlined),
                selectedIcon: Icon(Icons.sports_esports_rounded),
                label: 'ألعاب'),
            NavigationDestination(
                icon: Icon(Icons.movie_outlined),
                selectedIcon: Icon(Icons.movie_rounded),
                label: 'أفلام'),
            NavigationDestination(
                icon: Icon(Icons.search_rounded), label: 'بحث'),
            NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline_rounded),
                selectedIcon: Icon(Icons.chat_bubble_rounded),
                label: 'الرسائل'),
            NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'حسابي'),
          ],
        ),
      ),
    );
  }
}
