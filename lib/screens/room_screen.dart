import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../main.dart';
import '../audio.dart';
import '../theme.dart';
import 'profile_screen.dart';

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
  StreamSubscription<List<Map<String, dynamic>>>? _seatSub;
  final _input = TextEditingController();
  final Map<String, Map<String, dynamic>> _profiles = {};
  List<Map<String, dynamic>> _messages = [];
  Map<int, String> _seats = {};
  bool _connecting = true;
  bool _connected = false;
  bool _micOn = false;
  bool _closed = false;
  String? _error;

  int? get _mySeat {
    for (final e in _seats.entries) {
      if (e.value == myId) return e.key;
    }
    return null;
  }

  List<Participant> get _participants => [
        if (_room.localParticipant != null) _room.localParticipant!,
        ..._room.remoteParticipants.values,
      ];

  Participant? _participantOf(String uid) {
    for (final p in _participants) {
      if (p.identity == uid) return p;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    Music.stop();
    _start();
  }

  Future<void> _start() async {
    try {
      final ok = await supa.rpc('room_heartbeat', params: {'p_room': widget.roomId});
      if (ok != true) throw 'الغرفة منتهية';
      _beat = Timer.periodic(const Duration(seconds: 15), (_) => _heartbeat());
      _listenMessages();
      _listenSeats();

      final res = await supa.functions.invoke('livekit-token', body: {'room_id': widget.roomId});
      final data = res.data;
      if (data is! Map || data['token'] == null) {
        throw (data is Map ? data['error'] : null) ?? 'لا يوجد توكن';
      }

      _events = _room.createListener();
      _events!.listen((_) {
        if (mounted) {
          setState(() {});
          _loadProfiles();
        }
      });
      await _room.connect(data['url'] as String, data['token'] as String);
      _connected = true;
      try {
        await Hardware.instance.setSpeakerphoneOn(true);
      } catch (_) {}
      if (mounted) setState(() => _connecting = false);

      if (widget.isHost) await _takeSeat(0, silent: true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  Future<void> _heartbeat() async {
    try {
      final ok = await supa.rpc('room_heartbeat', params: {'p_room': widget.roomId});
      if (ok != true && mounted && !_closed) {
        _closed = true;
        toast(context, 'أنهى المضيف الغرفة');
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
      _loadProfiles();
    });
  }

  void _listenSeats() {
    _seatSub = supa
        .from('room_seats')
        .stream(primaryKey: ['room_id', 'seat_no'])
        .eq('room_id', widget.roomId)
        .listen((rows) {
      if (!mounted) return;
      final hadSeat = _mySeat != null;
      final m = <int, String>{
        for (final r in rows) (r['seat_no'] as num).toInt(): r['user_id'] as String,
      };
      setState(() => _seats = m);
      if (hadSeat && _mySeat == null && _micOn) _setMic(false);
      _loadProfiles();
    });
  }

  Future<void> _loadProfiles() async {
    final ids = <String>{
      for (final m in _messages) m['user_id'] as String,
      ..._seats.values,
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

  Future<void> _setMic(bool on) async {
    final lp = _room.localParticipant;
    if (lp == null) return;
    if (on) {
      final st = await Permission.microphone.request();
      if (!st.isGranted) {
        if (mounted) toast(context, 'يلزم السماح باستخدام الميكروفون');
        return;
      }
    }
    try {
      await lp.setMicrophoneEnabled(on);
      if (mounted) setState(() => _micOn = on);
    } catch (e) {
      if (mounted) toast(context, 'تعذّر تشغيل الميكروفون: ${friendlyError(e)}');
    }
  }

  Future<void> _takeSeat(int n, {bool silent = false}) async {
    try {
      await supa.rpc('take_seat', params: {'p_room': widget.roomId, 'p_seat': n});
      if (mounted) {
        setState(() {
          _seats = Map.of(_seats)..removeWhere((_, v) => v == myId);
          _seats[n] = myId;
        });
      }
      if (_connected) await _setMic(true);
    } catch (e) {
      if (mounted && !silent) toast(context, friendlyError(e));
    }
  }

  Future<void> _leaveSeat() async {
    try {
      await supa.rpc('leave_seat', params: {'p_room': widget.roomId});
      await _setMic(false);
      if (mounted) setState(() => _seats = Map.of(_seats)..removeWhere((_, v) => v == myId));
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _kick(int n) async {
    try {
      await supa.rpc('kick_seat', params: {'p_room': widget.roomId, 'p_seat': n});
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  void _openProfile(String uid) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: uid)));
  }

  Future<void> _seatMenu(int n, String uid) async {
    final mine = uid == myId;
    final name = (_profiles[uid]?['name'] ?? '...') as String;
    await showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ListTile(
            leading: const Icon(Icons.person_rounded),
            title: const Text('الملف الشخصي'),
            onTap: () {
              Navigator.pop(c);
              _openProfile(uid);
            },
          ),
          if (mine && n != 0)
            ListTile(
              leading: const Icon(Icons.mic_off_rounded, color: C.orange),
              title: const Text('النزول من المايك'),
              onTap: () {
                Navigator.pop(c);
                _leaveSeat();
              },
            ),
          if (!mine && widget.isHost)
            ListTile(
              leading: const Icon(Icons.person_off_rounded, color: Color(0xFFFF6B6B)),
              title: const Text('إنزال من المايك'),
              onTap: () {
                Navigator.pop(c);
                _kick(n);
              },
            ),
        ]),
      ),
    );
  }

  Future<void> _send() async {
    final t = _input.text.trim();
    if (t.isEmpty) return;
    _input.clear();
    try {
      await supa.from('room_messages').insert({
        'room_id': widget.roomId,
        'user_id': myId,
        'body': t,
      });
    } catch (e) {
      if (mounted) toast(context, 'تعذّر الإرسال: ${friendlyError(e)}');
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
    _seatSub?.cancel();
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

  // ---------- واجهة ----------

  Widget _seat(int n) {
    final uid = _seats[n];
    final isHostSeat = n == 0;
    if (uid == null) {
      return GestureDetector(
        onTap: () {
          if (isHostSeat && !widget.isHost) {
            toast(context, 'هذا المقعد للمضيف فقط');
            return;
          }
          _takeSeat(n);
        },
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: isHostSeat ? 72 : 56,
            height: isHostSeat ? 72 : 56,
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: C.glass,
              border: Border.all(color: Colors.white24),
            ),
            child: Icon(isHostSeat ? Icons.workspace_premium_rounded : Icons.mic_none_rounded,
                color: Colors.white54, size: isHostSeat ? 32 : 26),
          ),
          Text(isHostSeat ? 'المضيف' : '$n',
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ]),
      );
    }
    final prof = _profiles[uid];
    final name = (prof?['name'] ?? '...') as String;
    final p = _participantOf(uid);
    final speaking = p?.isSpeaking ?? false;
    final muted = uid == myId ? !_micOn : (p?.isMuted ?? true);
    return GestureDetector(
      onTap: () => _seatMenu(n, uid),
      child: SizedBox(
        width: 76,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(clipBehavior: Clip.none, children: [
            Avatar(
              name: name,
              url: prof?['avatar_url'] as String?,
              size: isHostSeat ? 66 : 50,
              speaking: speaking && !muted,
            ),
            if (isHostSeat)
              const Positioned(
                top: -6,
                right: -2,
                child: Icon(Icons.workspace_premium_rounded, color: Color(0xFFFBBF24), size: 24),
              ),
            if (muted)
              const Positioned(
                bottom: 0,
                right: 0,
                child: CircleAvatar(
                  radius: 10,
                  backgroundColor: Color(0xFF1B1040),
                  child: Icon(Icons.mic_off_rounded, size: 12, color: Colors.white70),
                ),
              ),
          ]),
          const SizedBox(height: 2),
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12)),
        ]),
      ),
    );
  }

  Widget _audience() {
    final seated = _seats.values.toSet();
    final aud = _participants.where((p) => !seated.contains(p.identity)).toList();
    if (aud.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Text('المستمعون (${aud.length})',
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ),
      SizedBox(
        height: 66,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: aud.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) {
            final p = aud[i];
            final prof = _profiles[p.identity];
            final name = (prof?['name'] ?? (p.name.isNotEmpty ? p.name : '...')) as String;
            return GestureDetector(
              onTap: () => _openProfile(p.identity),
              child: SizedBox(
                width: 54,
                child: Column(children: [
                  Avatar(name: name, url: prof?['avatar_url'] as String?, size: 34),
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10)),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final seated = _mySeat != null;
    final h = MediaQuery.of(context).size.height;
    return Scaffold(
      appBar: AppBar(
        title: Column(children: [
          Text(widget.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          if (widget.topic.isNotEmpty)
            Text(widget.topic, style: const TextStyle(fontSize: 11, color: Colors.white60)),
        ]),
        actions: [
          if (widget.isHost)
            IconButton(
              tooltip: 'إنهاء الغرفة',
              icon: const Icon(Icons.power_settings_new_rounded, color: Color(0xFFFF6B6B)),
              onPressed: _endRoom,
            ),
        ],
      ),
      body: Column(children: [
        if (_connecting) const LinearProgressIndicator(minHeight: 2, color: C.pink),
        if (_error != null)
          Container(
            width: double.infinity,
            color: const Color(0x55FF0000),
            padding: const EdgeInsets.all(10),
            child: Text('تعذّر الاتصال بالصوت: $_error', style: const TextStyle(fontSize: 13)),
          ),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: h * 0.52),
          child: SingleChildScrollView(
            child: Column(children: [
              Center(child: _seat(0)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 0.95,
                  children: [for (var n = 1; n <= 8; n++) Center(child: _seat(n))],
                ),
              ),
              _audience(),
            ]),
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
              final mine = m['user_id'] == myId;
              final name = (_profiles[m['user_id']]?['name'] ?? '...') as String;
              return Align(
                alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                  decoration: BoxDecoration(
                    gradient: mine ? brandGradient : null,
                    color: mine ? null : C.glass,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (!mine)
                      Text(name,
                          style: const TextStyle(
                              fontSize: 12, color: C.cyan, fontWeight: FontWeight.w700)),
                    Text(m['body'] as String, style: const TextStyle(fontSize: 15)),
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
                onPressed: seated && _connected ? () => _setMic(!_micOn) : null,
                tooltip: seated ? 'الميكروفون' : 'اجلس على مقعد للتحدث',
                style: IconButton.styleFrom(
                  backgroundColor: _micOn ? C.green : const Color(0x33FFFFFF),
                  foregroundColor: _micOn ? Colors.black : Colors.white,
                  disabledBackgroundColor: const Color(0x14FFFFFF),
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
              const SizedBox(width: 6),
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
}
