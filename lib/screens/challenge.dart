import 'package:flutter/material.dart';

import '../main.dart';
import '../theme.dart';
import 'guess_lobby_screen.dart';

/// قائمة من المحادثة: تحدّي لعبة مع هذا الصديق.
Future<void> showFriendActions(
  BuildContext context, {
  required String peerId,
  required String peerName,
}) async {
  await _challengeGame(context, peerId, peerName);
}

Future<void> _challengeGame(BuildContext context, String peerId, String peerName) async {
  List<Map<String, dynamic>> games;
  try {
    games = List<Map<String, dynamic>>.from(await supa.from('games').select().order('sort'));
  } catch (e) {
    toast(context, friendlyError(e));
    return;
  }
  if (!context.mounted) return;
  final gameId = await showModalBottomSheet<String>(
    context: context,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('اختر اللعبة',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          for (final g in games)
            ListTile(
              enabled: g['ready'] == true,
              leading: const Icon(Icons.sports_esports_rounded, color: C.pink),
              title: Text(g['title'] as String),
              subtitle: g['ready'] == true ? null : const Text('قريباً'),
              onTap: () => Navigator.pop(c, g['id'] as String),
            ),
        ]),
      ),
    ),
  );
  if (!context.mounted || gameId != 'guess') return;

  List<Map<String, dynamic>> cats;
  try {
    cats = List<Map<String, dynamic>>.from(
        await supa.from('game_categories').select().eq('active', true).order('sort'));
  } catch (e) {
    toast(context, friendlyError(e));
    return;
  }
  if (!context.mounted) return;
  final cat = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('اختر الفئة',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.shuffle_rounded, color: C.cyan),
              title: const Text('منوّع'),
              onTap: () => Navigator.pop(c, {'id': null, 'name': 'منوّع'}),
            ),
            for (final k in cats)
              ListTile(
                leading: const Icon(Icons.category_rounded, color: C.violet),
                title: Text(k['name'] as String),
                onTap: () => Navigator.pop(c, k),
              ),
          ]),
        ),
      ),
    ),
  );
  if (!context.mounted || cat == null) return;

  try {
    final id = await supa.rpc('send_invite', params: {'p_to': peerId, 'p_cat': cat['id']});
    // رسالة في المحادثة تُعلم الصديق
    try {
      await supa.from('dms').insert({
        'sender_id': myId,
        'receiver_id': peerId,
        'body': '🎮 تحدّاك في «خمّن الشخصية» — ${cat['name']}. افتح تبويب ألعاب للقبول',
      });
    } catch (_) {}
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => InviteWait(inviteId: id as String, name: peerName)),
    );
  } catch (e) {
    if (context.mounted) toast(context, friendlyError(e));
  }
}
