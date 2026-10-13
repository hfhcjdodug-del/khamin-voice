import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../theme.dart';
import 'challenge.dart';
import 'profile_screen.dart';

class ChatScreen extends StatefulWidget {
  final String peerId;
  final String peerName;
  final String? peerAvatar;
  const ChatScreen({
    super.key,
    required this.peerId,
    required this.peerName,
    this.peerAvatar,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  List<Map<String, dynamic>> _msgs = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final me = myId;
      final p = widget.peerId;
      final r = await supa
          .from('dms')
          .select()
          .or('and(sender_id.eq.$me,receiver_id.eq.$p),and(sender_id.eq.$p,receiver_id.eq.$me)')
          .order('id', ascending: false)
          .limit(100);
      if (!mounted) return;
      setState(() => _msgs = List<Map<String, dynamic>>.from(r));
      if (_msgs.any((m) => m['sender_id'] == p && m['read_at'] == null)) {
        await supa.rpc('mark_read', params: {'p_peer': p});
      }
    } catch (_) {}
  }

  Future<void> _send() async {
    final t = _input.text.trim();
    if (t.isEmpty) return;
    _input.clear();
    try {
      await supa.from('dms').insert({
        'sender_id': myId,
        'receiver_id': widget.peerId,
        'body': t,
      });
      await _load();
    } catch (e) {
      if (mounted) toast(context, 'تعذّر الإرسال: ${friendlyError(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ProfileScreen(userId: widget.peerId)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Avatar(name: widget.peerName, url: widget.peerAvatar, size: 30),
            const SizedBox(width: 8),
            Text(widget.peerName, style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
        ),
        actions: [
          IconButton(
            tooltip: 'تحدّي / فيلم',
            icon: const Icon(Icons.sports_esports_rounded, color: C.pink),
            onPressed: () => showFriendActions(context,
                peerId: widget.peerId, peerName: widget.peerName),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: ListView.builder(
            reverse: true,
            padding: const EdgeInsets.all(12),
            itemCount: _msgs.length,
            itemBuilder: (_, i) {
              final m = _msgs[i];
              final mine = m['sender_id'] == myId;
              return Align(
                alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                  decoration: BoxDecoration(
                    gradient: mine ? brandGradient : null,
                    color: mine ? null : C.glass,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(m['body'] as String, style: const TextStyle(fontSize: 15)),
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  maxLength: 1000,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(hintText: 'اكتب رسالة...', counterText: ''),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: const BoxDecoration(gradient: brandGradient, shape: BoxShape.circle),
                child: IconButton(onPressed: _send, icon: const Icon(Icons.send_rounded)),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
