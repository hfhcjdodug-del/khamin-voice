import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../main.dart';
import '../widgets/ninja.dart';

class RoomScreen extends StatefulWidget {
  final String roomId;
  final String title;
  final String topic;
  final bool isHost;
  const RoomScreen({
    super.key,
    required this.roomId,
    required this.title,
    required this.topic,
    required this.isHost,
  });

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  final Room _room = Room();
  EventsListener<RoomEvent>? _events;
  Timer? _beat;
  StreamSubscription<List<Map<String, dynamic>>>? _msgSub;
  final _input = TextEditingController();
  final Map<String, Map<String, dynamic>> _profiles = {};
  List<Map<String, dynamic>> _messages = [];
  bool _connecting = true;
  bool _micOn = false;
  String? _error;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final ok = await supa.rpc('room_heartbeat', params: {'p_room': widget.roomId});
      if (ok != true) throw 'الغرفة منتهية';
      _beat = Timer.periodic(const Duration(seconds: 15), (_) => _heartbeat());

      _listenMessages();

      final res = await supa.functions.invoke('livekit-token', body: {'room_id': widget.roomId});
      final data = res.data as Map<String, dynamic>;
      if (data['token'] == null) throw data['error'] ?? 'لا يوجد توكن';

      _events = _room.createListener();
      _events!.listen((_) {
        if (mounted) {
          setState(() {});
          _loadMissingProfiles();
        }
      });
      await _room.connect(data['url'] as String, data['token'] as String);
      if (mounted) setState(() => _connecting = false);
      _loadMissingProfiles();
    } catch (e) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _heartbeat() async {
    try {
      final ok = await supa.rpc('room_heartbeat', params: {'p_room': widget.roomId});
      if (ok != true && mounted && !_closed) {
        _closed = true;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('أنهى المضيف الغرفة')));
        Navigator.of(context).pop();
      }
    } catch (_) {}
  }

  void _listenMessages() {
    _msgSub = supa
        .from('room_messages')
        .stream(primaryKey: ['id'])
        .eq('room_id', widget.roomId)
        .order('id', ascending: false)
        .limit(60)
        .listen((rows) {
      if (!mounted) return;
      setState(() => _messages = rows);
      _loadMissingProfiles();
    });
  }

  Future<void> _loadMissingProfiles() async {
    final ids = <String>{
      for (final m in _messages) m['user_id'] as String,
      for (final p in _participants) p.identity,
    }..removeWhere((id) => id.isEmpty || _profiles.containsKey(id));
    if (ids.isEmpty) return;
    try {
      final rows = await supa.from('profiles').select().inFilter('id', ids.toList());
      for (final r in rows) {
        _profiles[r['id'] as String] = r;
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  List<Participant> get _participants => [
        if (_room.localParticipant != null) _room.localParticipant!,
        ..._room.remoteParticipants.values,
      ];

  Future<void> _toggleMic() async {
    final lp = _room.localParticipant;
    if (lp == null) return;
    if (!_micOn) {
      final st = await Permission.microphone.request();
      if (!st.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('يلزم السماح باستخدام الميكروفون')),
          );
        }
        return;
      }
    }
    try {
      await lp.setMicrophoneEnabled(!_micOn);
      if (mounted) setState(() => _micOn = !_micOn);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذّر تشغيل الميكروفون: $e')));
      }
    }
  }

  Future<void> _send() async {
    final t = _input.text.trim();
    if (t.isEmpty) return;
    _input.clear();
    try {
      await supa.from('room_messages').insert({
        'room_id': widget.roomId,
        'user_id': supa.auth.currentUser!.id,
        'body': t,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذّر الإرسال: $e')));
      }
    }
  }

  Future<void> _endRoom() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('إنهاء الغرفة؟'),
        content: const Text('ستُغلق الغرفة للجميع.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('إنهاء')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await supa.rpc('end_room', params: {'p_room': widget.roomId});
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _closed = true;
    _beat?.cancel();
    _msgSub?.cancel();
    _events?.dispose();
    _input.dispose();
    () async {
      try {
        await supa.rpc('leave_room', params: {'p_room': widget.roomId});
      } catch (_) {}
      try {
        await _room.disconnect();
      } catch (_) {}
      await _room.dispose();
    }();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parts = _participants;
    return Scaffold(
      appBar: AppBar(
        title: Column(children: [
          Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          if (widget.topic.isNotEmpty)
            Text(widget.topic, style: const TextStyle(fontSize: 12, color: Colors.white54)),
        ]),
        actions: [
          if (widget.isHost)
            IconButton(
              tooltip: 'إنهاء الغرفة',
              icon: const Icon(Icons.power_settings_new_rounded),
              onPressed: _endRoom,
            ),
        ],
      ),
      body: Column(children: [
        if (_connecting) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Container(
            width: double.infinity,
            color: const Color(0xFF3A1212),
            padding: const EdgeInsets.all(12),
            child: Text('تعذّر الاتصال بالصوت: $_error', style: const TextStyle(fontSize: 13)),
          ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 230),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Wrap(
              spacing: 14,
              runSpacing: 14,
              alignment: WrapAlignment.center,
              children: [for (final p in parts) _tile(p)],
            ),
          ),
        ),
        const Divider(height: 1, color: Colors.white12),
        Expanded(
          child: ListView.builder(
            reverse: true,
            padding: const EdgeInsets.all(12),
            itemCount: _messages.length,
            itemBuilder: (_, i) {
              final m = _messages[i];
              final mine = m['user_id'] == supa.auth.currentUser!.id;
              final name = (_profiles[m['user_id']]?['name'] ?? '...') as String;
              return Align(
                alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                  decoration: BoxDecoration(
                    color: mine ? Colors.white : const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (!mine)
                      Text(name, style: const TextStyle(fontSize: 12, color: Color(0xFF4ADE80))),
                    Text(m['body'] as String,
                        style: TextStyle(color: mine ? Colors.black : Colors.white, fontSize: 15)),
                  ]),
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
            child: Row(children: [
              IconButton.filled(
                onPressed: _room.localParticipant == null ? null : _toggleMic,
                style: IconButton.styleFrom(
                  backgroundColor: _micOn ? const Color(0xFF4ADE80) : const Color(0xFF262626),
                  foregroundColor: _micOn ? Colors.black : Colors.white,
                  minimumSize: const Size(52, 52),
                ),
                icon: Icon(_micOn ? Icons.mic_rounded : Icons.mic_off_rounded),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _input,
                  maxLength: 500,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(hintText: 'اكتب رسالة...', counterText: ''),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(onPressed: _send, icon: const Icon(Icons.send_rounded)),
              IconButton(
                tooltip: 'مغادرة',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.logout_rounded, color: Color(0xFFFF6B6B)),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _tile(Participant p) {
    final prof = _profiles[p.identity];
    final name = (prof?['name'] ?? (p.name.isNotEmpty ? p.name : '...')) as String;
    return SizedBox(
      width: 78,
      child: Column(children: [
        Stack(clipBehavior: Clip.none, children: [
          Avatar(name: name, url: prof?['avatar_url'] as String?, size: 56, speaking: p.isSpeaking),
          if (p.isMuted)
            const Positioned(
              bottom: 0,
              right: 0,
              child: CircleAvatar(
                radius: 10,
                backgroundColor: Colors.black,
                child: Icon(Icons.mic_off_rounded, size: 13, color: Colors.white70),
              ),
            ),
        ]),
        const SizedBox(height: 4),
        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
      ]),
    );
  }
}
