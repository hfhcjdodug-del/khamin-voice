import 'dart:async';

import 'package:flutter/material.dart';

import '../push.dart';
import '../theme.dart';
import 'guess_match_screen.dart';
import 'friends_tab.dart';
import 'home_tab.dart';
import 'watch_screen.dart';
import 'profile_screen.dart';
import 'rooms_tab.dart';
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

  Widget _navItem(int idx, IconData icon, IconData sel, String label) {
    final on = _i == idx;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _i = idx),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(on ? sel : icon, color: on ? C.pink : Colors.white54, size: 26),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: on ? FontWeight.w800 : FontWeight.w500,
                  color: on ? Colors.white : Colors.white54)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _i, children: [
        HomeTab(active: _i == 0, onSeeRooms: () => setState(() => _i = 1)),
        RoomsTab(active: _i == 1),
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
            height: 66,
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              _navItem(0, Icons.sports_esports_outlined, Icons.sports_esports_rounded, 'ألعاب'),
              _navItem(1, Icons.meeting_room_outlined, Icons.meeting_room_rounded, 'الغرف'),
              Expanded(
                child: Center(
                  child: GestureDetector(
                    onTap: () => createRoomFlow(context),
                    child: Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                            colors: [C.violet, C.pink],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight),
                        border: Border.all(color: Colors.white24, width: 2),
                        boxShadow: [BoxShadow(color: C.violet.withValues(alpha: 0.7), blurRadius: 18)],
                      ),
                      child: const Icon(Icons.mic_rounded, size: 28),
                    ),
                  ),
                ),
              ),
              _navItem(2, Icons.people_outline_rounded, Icons.people_rounded, 'الأصدقاء'),
              _navItem(3, Icons.person_outline_rounded, Icons.person_rounded, 'حسابي'),
            ]),
          ),
        ),
      ),
    );
  }
}
