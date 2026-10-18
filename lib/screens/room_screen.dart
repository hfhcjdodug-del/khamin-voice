import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../audio.dart';
import '../gift_image.dart';
import '../level.dart';
import '../main.dart';
import '../media.dart';
import '../room_look.dart';
import '../shop_screen.dart';
import '../songs.dart';
import '../theme.dart';
import '../widgets/trend_frame.dart';
import 'chat_screen.dart';
import 'farm_screen.dart';
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
  Timer? _xpTimer;
  StreamSubscription<List<Map<String, dynamic>>>? _msgSub;
  StreamSubscription<List<Map<String, dynamic>>>? _seatSub;
  StreamSubscription<List<Map<String, dynamic>>>? _flagSub;
  StreamSubscription<List<Map<String, dynamic>>>? _lookSub;
  final _input = TextEditingController();
  final Map<String, Map<String, dynamic>> _profiles = {};
  final Map<String, Map<String, dynamic>> _flags = {};
  Map<String, dynamic> _look = {};
  List<Map<String, dynamic>> _messages = [];
  Map<int, String> _seats = {};
  bool _connecting = true;
  bool _connected = false;
  bool _micOn = false;
  bool _roomMuted = false; // كتم صوت الغرفة عندي أنا فقط
  bool _closed = false;
  String? _error;
  int _lastGiftId = -1;
  int _lastBcastId = -1;
  Map<String, dynamic>? _bcast;
  Timer? _bcastTimer;
  StreamSubscription<List<Map<String, dynamic>>>? _bcastSub;
  Map<String, dynamic>? _giftFx;
  Timer? _fxTimer;
  // موسيقى الروم: كل مستمع يشغّلها محلياً بالتزامن مع وقت السيرفر
  AudioPlayer? _mp;
  String? _musicKey; // url|started لتمييز الأغنية الحالية
  int _srvOffsetMs = 0;
  bool _musicMuted = false;
  double _duck = 1.0;
  DateTime _lastSpeech = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _duckTimer;

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

  // ---------- الصلاحيات ----------

  String? get _hostId => (_look['host_id'] as String?) ?? (widget.isHost ? myId : null);

  String _roleOf(String uid) {
    if (uid == _hostId) return 'owner';
    if (_flags[uid]?['is_mod'] == true) return 'mod';
    return 'user';
  }

  int _rank(String role) => role == 'owner' ? 3 : (role == 'mod' ? 2 : 1);

  String get _myRole => _roleOf(myId);
  bool get _iAmOwner => _myRole == 'owner';
  bool get _trending {
    final t = _look['trend_until'];
    return t != null && DateTime.tryParse(t.toString())?.isAfter(DateTime.now().toUtc()) == true;
  }

  bool get _iAmMuted => _flags[myId]?['muted'] == true;
  bool get _iAmChatBanned => _flags[myId]?['chat_banned'] == true;

  /// المشرف يعاقب (حظر كتابة/طرد) من هو أقل رتبة منه فقط؛ المالك يعاقب الجميع.
  bool _canPunish(String uid) =>
      uid != myId && _rank(_myRole) >= 2 && _rank(_myRole) > _rank(_roleOf(uid));

  Future<void> _gainXp() async {
    try {
      await supa.rpc('add_xp', params: {'p_kind': 'room'});
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    Music.stop();
    _start();
    _checkFarm();
  }

  bool _farmOn = false;

  Future<void> _checkFarm() async {
    try {
      final r = await supa.rpc('farm_state');
      final m = r is List ? (r.isEmpty ? null : r.first) : r;
      if (m is Map && m['enabled'] == true && mounted) setState(() => _farmOn = true);
    } catch (_) {}
  }

  Future<void> _openFarm() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: SizedBox(height: MediaQuery.of(c).size.height * 0.88, child: const FarmScreen()),
      ),
    );
  }

  Future<void> _start() async {
    try {
      final ok = await supa.rpc('room_heartbeat', params: {'p_room': widget.roomId});
      if (ok != true) throw 'الغرفة منتهية';
      supa.rpc('room_visited', params: {'p_room': widget.roomId}).catchError((_) => null);
      _initMusic();
      _beat = Timer.periodic(const Duration(seconds: 15), (_) => _heartbeat());
      _gainXp();
      _xpTimer = Timer.periodic(const Duration(minutes: 10), (_) => _gainXp());
      _listenMessages();
      _listenSeats();
      _listenFlags();
      _listenLook();
      _listenBroadcasts();

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
          if (_roomMuted) _applySpeaker();
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
      if (!mounted) return;
      if (e.toString().contains('kicked')) {
        _handleKicked();
        return;
      }
      if (e.toString().contains('room locked')) {
        _closed = true;
        toast(context, 'الروم مقفلة 🔒');
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _connecting = false;
        _error = friendlyError(e);
      });
    }
  }

  void _handleKicked() {
    if (_closed || !mounted) return;
    _closed = true;
    toast(context, 'تم طردك من هذه الغرفة');
    Navigator.of(context).pop();
  }

  Future<void> _heartbeat() async {
    try {
      final ok = await supa.rpc('room_heartbeat', params: {'p_room': widget.roomId});
      if (ok != true && mounted && !_closed) {
        _closed = true;
        toast(context, 'أنهى المضيف الغرفة');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (e.toString().contains('kicked')) _handleKicked();
      if (e.toString().contains('room locked') && mounted && !_closed) {
        _closed = true;
        toast(context, 'الروم مقفلة 🔒 ادخل بكلمة السر');
        Navigator.of(context).pop();
      }
    }
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
      _detectGifts(rows);
      _loadProfiles();
    });
  }

  /// بعد إرسال هدية: نجلب الرسائل فوراً حتى يرى المُرسِل هديته دون انتظار أي مستخدم آخر.
  Future<void> _refreshMessages() async {
    try {
      final rows = List<Map<String, dynamic>>.from(await supa
          .from('room_messages')
          .select()
          .eq('room_id', widget.roomId)
          .order('id', ascending: false)
          .limit(60));
      if (!mounted) return;
      setState(() => _messages = rows);
      _detectGifts(rows);
      _loadProfiles();
    } catch (_) {}
  }

  /// أول تحميل لا يعيد عرض الهدايا القديمة، وبعدها تظهر أي هدية جديدة كتأثير على الشاشة.
  void _detectGifts(List<Map<String, dynamic>> rows) {
    final gifts = rows.where((r) => r['kind'] == 'gift').toList()
      ..sort((a, b) => (a['id'] as num).compareTo(b['id'] as num));
    final maxId = gifts.isEmpty ? 0 : (gifts.last['id'] as num).toInt();
    if (_lastGiftId == -1) {
      _lastGiftId = maxId;
      return;
    }
    final fresh = gifts.where((r) => (r['id'] as num).toInt() > _lastGiftId).toList();
    if (fresh.isEmpty) return;
    _lastGiftId = maxId;
    setState(() => _giftFx = fresh.last);
    _fxTimer?.cancel();
    _fxTimer = Timer(const Duration(milliseconds: 2400), () {
      if (mounted) setState(() => _giftFx = null);
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

  void _listenFlags() {
    _flagSub = supa
        .from('room_flags')
        .stream(primaryKey: ['room_id', 'user_id'])
        .eq('room_id', widget.roomId)
        .listen((rows) {
      if (!mounted) return;
      setState(() {
        _flags
          ..clear()
          ..addEntries(rows.map((r) => MapEntry(r['user_id'] as String, r)));
      });
      final k = _flags[myId]?['kicked_until'];
      if (k != null && DateTime.tryParse(k.toString())?.isAfter(DateTime.now().toUtc()) == true) {
        _handleKicked();
        return;
      }
      if (_iAmMuted && _micOn) _setMic(false);
    });
  }

  /// إعلان عام: دعم كبير (500+ جوهرة) يظهر في كل الغرف، ويطول ويكبر كلما زاد المبلغ.
  void _listenBroadcasts() {
    _bcastSub = supa
        .from('gift_broadcasts')
        .stream(primaryKey: ['id'])
        .order('id', ascending: false)
        .limit(1)
        .listen((rows) {
      if (!mounted || rows.isEmpty) return;
      final r = rows.first;
      final id = (r['id'] as num).toInt();
      if (_lastBcastId == -1) {
        _lastBcastId = id;
        return;
      }
      if (id <= _lastBcastId) return;
      _lastBcastId = id;
      final tier = (r['tier'] as num?)?.toInt() ?? 1;
      setState(() => _bcast = r);
      _bcastTimer?.cancel();
      _bcastTimer = Timer(Duration(seconds: tier == 3 ? 15 : (tier == 2 ? 10 : 6)), () {
        if (mounted) setState(() => _bcast = null);
      });
    });
  }

  Widget _bcastBanner() {
    final r = _bcast;
    if (r == null) return const SizedBox.shrink();
    final tier = (r['tier'] as num?)?.toInt() ?? 1;
    final colors = tier == 3
        ? const [Color(0xFFFDE047), Color(0xFFF97316), Color(0xFFDC2626)]
        : tier == 2
            ? const [Color(0xFFA855F7), Color(0xFFA855F7)]
            : const [Color(0xFF0EA5E9), Color(0xFF6366F1)];
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          key: ValueKey(r['id']),
          margin: EdgeInsets.fromLTRB(10, 6, 10, 0),
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: tier == 3 ? 16 : (tier == 2 ? 12 : 9)),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: colors),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: colors.first.withValues(alpha: 0.6), blurRadius: tier == 3 ? 26 : 14)],
          ),
          child: Row(children: [
            Text(tier == 3 ? '👑' : (tier == 2 ? '🔥' : '💎'), style: TextStyle(fontSize: tier == 3 ? 30 : 22)),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  const TextSpan(text: 'قام  '),
                  TextSpan(text: '${r['from_name']}', style: const TextStyle(fontWeight: FontWeight.w900)),
                  TextSpan(text: '  بإرسال ${r['gems']} ماسة إلى  '),
                  TextSpan(text: '${r['to_name']}', style: const TextStyle(fontWeight: FontWeight.w900)),
                ]),
                style: TextStyle(fontSize: tier == 3 ? 17 : (tier == 2 ? 15 : 13.5), color: tier == 3 ? Colors.black : Colors.white),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ---------- الموسيقى ----------

  bool get _canDj => _rank(_myRole) >= 2;
  String? get _songUrl => _look['song_url'] as String?;
  bool get _songPaused => _look['song_paused_ms'] != null;

  Future<void> _initMusic() async {
    try {
      final r = await supa.rpc('server_time') as String;
      _srvOffsetMs = DateTime.parse(r).millisecondsSinceEpoch - DateTime.now().millisecondsSinceEpoch;
    } catch (_) {}
    _duckTimer ??= Timer.periodic(const Duration(milliseconds: 300), (_) => _tickDuck());
    _syncMusic();
  }

  /// خفض صوت الموسيقى تلقائياً أثناء حديث أي شخص، وإرجاعه بعد ثانية ونصف من الصمت.
  void _tickDuck() {
    final p = _mp;
    if (p == null || _songUrl == null) return;
    try {
      if (_room.activeSpeakers.isNotEmpty) _lastSpeech = DateTime.now();
    } catch (_) {}
    final talking = DateTime.now().difference(_lastSpeech).inMilliseconds < 1500;
    final target = talking ? 0.2 : 1.0;
    if ((_duck - target).abs() > 0.01) {
      _duck += (target - _duck) * 0.5;
      _applyMusicVolume();
    }
  }

  void _applyMusicVolume() {
    _mp?.setVolume(_musicMuted ? 0 : (0.9 * _duck).clamp(0.0, 1.0));
  }

  Future<void> _syncMusic() async {
    final url = _songUrl;
    if (url == null) {
      _musicKey = null;
      try {
        await _mp?.stop();
      } catch (_) {}
      if (mounted) setState(() {});
      return;
    }
    try {
      final p = _mp ??= AudioPlayer();
      await p.setAudioContext(AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build());
      final started = DateTime.parse(_look['song_started'] as String).millisecondsSinceEpoch;
      final pausedMs = (_look['song_paused_ms'] as num?)?.toInt();
      final nowSrv = DateTime.now().millisecondsSinceEpoch + _srvOffsetMs;
      final pos = pausedMs ?? (nowSrv - started).clamp(0, 1 << 31);
      final key = '$url|${_look['song_started']}';
      _applyMusicVolume();
      if (pausedMs != null) {
        if (_musicKey == null || !_musicKey!.startsWith(url)) {
          await p.setSourceUrl(url);
          await p.seek(Duration(milliseconds: pos));
        }
        _musicKey = '$url|paused';
        await p.pause();
      } else if (_musicKey != key) {
        _musicKey = key;
        await p.setSourceUrl(url);
        await p.seek(Duration(milliseconds: pos));
        await p.resume();
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _song(String action, [String? id]) async {
    try {
      await supa.rpc('room_song', params: {'p_room': widget.roomId, 'p_action': action, 'p_song': id});
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _pickSong() async {
    final s = await Navigator.push<Map<String, dynamic>>(
        context, MaterialPageRoute(builder: (_) => const SongsScreen(pick: true)));
    if (s != null) await _song('play', s['id'] as String);
  }

  Future<void> _musicSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('موسيقى الروم', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            const Text('تُشغَّل الأغنية عند كل المستمعين، ويخفت صوتها تلقائياً عندما يتحدث أحد.',
                style: TextStyle(color: Colors.white60, fontSize: 12)),
            const SizedBox(height: 14),
            GradButton(
                label: _songUrl == null ? 'اختر أغنية' : 'تغيير الأغنية',
                icon: Icons.library_music_rounded,
                onPressed: () {
                  Navigator.pop(c);
                  _pickSong();
                }),
            if (_songUrl != null) ...[
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: GradButton(
                      label: _songPaused ? 'استئناف' : 'إيقاف مؤقت',
                      icon: _songPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                      outlined: true,
                      onPressed: () {
                        Navigator.pop(c);
                        _song(_songPaused ? 'resume' : 'pause');
                      }),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GradButton(
                      label: 'إيقاف',
                      icon: Icons.stop_rounded,
                      outlined: true,
                      onPressed: () {
                        Navigator.pop(c);
                        _song('stop');
                      }),
                ),
              ]),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _nowPlaying() {
    if (_songUrl == null) return const SizedBox.shrink();
    final t = (_look['song_title'] ?? '') as String;
    final a = (_look['song_artist'] ?? '') as String;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Icon(_songPaused ? Icons.pause_circle_rounded : Icons.music_note_rounded, size: 18, color: C.pink),
        const SizedBox(width: 8),
        Expanded(
          child: Text(a.isEmpty ? t : '$t · $a',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        ),
        GestureDetector(
          onTap: () {
            setState(() => _musicMuted = !_musicMuted);
            _applyMusicVolume();
          },
          child: Icon(_musicMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded, size: 20),
        ),
        if (_canDj) ...[
          const SizedBox(width: 10),
          GestureDetector(onTap: _musicSheet, child: const Icon(Icons.tune_rounded, size: 20)),
        ],
      ]),
    );
  }

  int get _micCount => (_look['mic_count'] as num?)?.toInt() ?? 8;

  Future<void> _toggleLock() async {
    final locked = _look['locked'] == true;
    final ctrl = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(locked ? 'الروم مقفلة 🔒' : 'قفل الروم بكلمة سر'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(locked
              ? 'اكتب كلمة سر جديدة لتغييرها، أو افتح الروم للجميع'
              : 'اكتب كلمة سر (4 إلى 16 حرفاً). من يحاول الدخول سيُطلب منه كتابتها'),
          const SizedBox(height: 8),
          TextField(
            controller: ctrl,
            maxLength: 16,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'كلمة السر', counterText: ''),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
          if (locked) TextButton(onPressed: () => Navigator.pop(c, ''), child: const Text('فتح الروم')),
          TextButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('حفظ')),
        ],
      ),
    );
    if (res == null) return;
    if (res.isNotEmpty && (res.length < 4 || res.length > 16)) {
      if (mounted) toast(context, 'كلمة السر من 4 إلى 16 حرفاً');
      return;
    }
    if (res.isEmpty && !locked) return;
    try {
      await supa.rpc('set_room_password', params: {'p_room': widget.roomId, 'p_pass': res.isEmpty ? null : res});
      if (mounted) {
        setState(() => _look['locked'] = res.isNotEmpty);
        toast(context, res.isNotEmpty ? 'تم قفل الروم 🔒' : 'تم فتح الروم 🔓');
      }
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  void _listenLook() {
    _lookSub = supa
        .from('rooms')
        .stream(primaryKey: ['id'])
        .eq('id', widget.roomId)
        .listen((rows) {
      if (!mounted || rows.isEmpty) return;
      setState(() => _look = Map<String, dynamic>.from(rows.first));
      _syncMusic();
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
    if (on && _iAmMuted) {
      if (mounted) toast(context, 'صاحب الغرفة كتم المايك الخاص بك');
      return;
    }
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

  /// كتم/إرجاع صوت الغرفة عندي فقط (إلغاء الاشتراك بمقاطع الصوت الواردة).
  Future<void> _applySpeaker() async {
    for (final rp in _room.remoteParticipants.values) {
      for (final pub in rp.audioTrackPublications) {
        try {
          if (_roomMuted && pub.subscribed) {
            await pub.unsubscribe();
          } else if (!_roomMuted && !pub.subscribed) {
            await pub.subscribe();
          }
        } catch (_) {}
      }
    }
  }

  Future<void> _toggleRoomMute() async {
    setState(() => _roomMuted = !_roomMuted);
    await _applySpeaker();
    if (mounted) toast(context, _roomMuted ? 'كتمت صوت الغرفة عندك فقط' : 'أعدت صوت الغرفة');
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
      if (_connected && !_iAmMuted) await _setMic(true);
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

  Future<void> _kickSeat(int n) async {
    try {
      await supa.rpc('kick_seat', params: {'p_room': widget.roomId, 'p_seat': n});
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _moderate(String uid, String action, bool on) async {
    try {
      await supa.rpc('room_moderate', params: {
        'p_room': widget.roomId,
        'p_user': uid,
        'p_action': action,
        'p_on': on,
      });
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  void _openProfile(String uid) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: uid)));
  }

  Widget _sheetAction(IconData icon, String title, String sub, VoidCallback onTap,
      {Color color = Colors.white}) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w800)),
      subtitle: sub.isEmpty
          ? null
          : Text(sub, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      onTap: onTap,
    );
  }

  /// قائمة المستخدم: الأزرار تظهر حسب رتبتي ورتبته.
  Future<void> _userSheet(String uid, {int seat = -1}) async {
    final prof = _profiles[uid];
    final name = (prof?['name'] ?? '...') as String;
    final lv = levelOf((prof?['xp'] as num?)?.toInt() ?? 0);
    final role = _roleOf(uid);
    final mine = uid == myId;
    final fl = _flags[uid] ?? const <String, dynamic>{};
    final muted = fl['muted'] == true;
    final banned = fl['chat_banned'] == true;
    final isMod = fl['is_mod'] == true;
    final ownerActs = _iAmOwner && !mine && role != 'owner';
    final punish = _canPunish(uid);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) {
        void done(VoidCallback f) {
          Navigator.pop(c);
          f();
        }

        return SafeArea(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _UserCard(
                uid: uid,
                name: name,
                avatarUrl: prof?['avatar_url'] as String?,
                level: lv,
                roleText: role == 'owner' ? 'صاحب الغرفة' : (role == 'mod' ? 'مشرف' : 'عضو'),
                framed: uid == _hostId && _trending,
                mine: mine,
                onProfile: () => done(() => _openProfile(uid)),
                onGift: () => done(() => _giftSheet(to: uid)),
                onChat: () => done(() => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ChatScreen(
                            peerId: uid, peerName: name, peerAvatar: prof?['avatar_url'] as String?)))),
              ),
              const Divider(color: Colors.white12),
              if (mine && seat > 0)
                _sheetAction(Icons.mic_off_rounded, 'النزول من المايك', '',
                    () => done(_leaveSeat),
                    color: C.orange),
              if (ownerActs && seat > 0)
                _sheetAction(
                    muted ? Icons.mic_rounded : Icons.mic_off_rounded,
                    muted ? 'إلغاء الكتم' : 'كتم المستخدم',
                    muted ? 'يعيد له صوته' : 'يمنعه من التحدث على المايك',
                    () => done(() => _moderate(uid, 'mute', !muted))),
              if (ownerActs && seat > 0)
                _sheetAction(Icons.person_off_rounded, 'إنزال من المايك', '',
                    () => done(() => _kickSeat(seat)),
                    color: C.orange),
              if (ownerActs)
                _sheetAction(
                    Icons.shield_rounded,
                    isMod ? 'سحب الإشراف' : 'منح الإشراف',
                    isMod ? 'يعود عضواً عادياً' : 'يستطيع الطرد وحظر الكتابة',
                    () => done(() => _moderate(uid, 'mod', !isMod))),
              if (punish)
                _sheetAction(
                    Icons.speaker_notes_off_rounded,
                    banned ? 'السماح بالكتابة' : 'حظر الكتابة',
                    banned ? 'يستطيع إرسال رسائل مجدداً' : 'لا يستطيع إرسال رسائل في الغرفة',
                    () => done(() => _moderate(uid, 'chatban', !banned)),
                    color: const Color(0xFFFF8A8A)),
              if (punish)
                _sheetAction(Icons.logout_rounded, 'طرد من الغرفة', 'لا يعود قبل مرور ساعة',
                    () => done(() => _moderate(uid, 'kick', true)),
                    color: const Color(0xFFFF6B6B)),
              if (!mine && !punish && !ownerActs)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('لا تملك صلاحيات على هذا المستخدم',
                      style: TextStyle(color: Colors.white38, fontSize: 12)),
                ),
              const SizedBox(height: 8),
            ]),
          ),
        );
      },
    );
  }


  // ---------- الهدايا ----------

  Widget _giftIcon(Map<String, dynamic> g, double size) =>
      GiftImage(image: g['image_url'] as String?, emoji: (g['emoji'] ?? '🎁') as String, size: size);

  Future<void> _giftSheet({String? to}) async {
    List<Map<String, dynamic>> gifts = [];
    var gems = 0;
    try {
      gifts = List<Map<String, dynamic>>.from(
          await supa.from('gifts').select().eq('active', true).order('sort'));
      gems = (await fetchWallet()).gems;
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
      return;
    }
    if (!mounted) return;
    final ids = <String>[
      if (_hostId != null && _hostId != myId) _hostId!,
      ..._seats.values.where((u) => u != myId && u != _hostId),
      ..._participants
          .map((p) => p.identity)
          .where((u) => u != myId && u != _hostId && !_seats.values.contains(u)),
    ];
    if (ids.isEmpty) {
      toast(context, 'لا يوجد أحد لإهدائه الآن');
      return;
    }
    var target = (to != null && ids.contains(to)) ? to : ids.first;
    var qty = 1;
    var sending = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Text('إهداء هدية', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const Spacer(),
                const Icon(Icons.diamond_rounded, size: 18, color: Color(0xFF67E8F9)),
                const SizedBox(width: 4),
                Text('$gems', style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ShopScreen()));
                    try {
                      final w = await fetchWallet();
                      setS(() => gems = w.gems);
                    } catch (_) {}
                  },
                  child: const Icon(Icons.add_circle_rounded, color: C.pink),
                ),
              ]),
              const SizedBox(height: 10),
              SizedBox(
                height: 74,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: ids.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final id = ids[i];
                    final pr = _profiles[id];
                    final on = id == target;
                    return GestureDetector(
                      onTap: () => setS(() => target = id),
                      child: Container(
                        width: 62,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: on ? C.pink : Colors.transparent, width: 2),
                        ),
                        child: Column(children: [
                          Avatar(name: (pr?['name'] ?? '?') as String, url: pr?['avatar_url'] as String?, size: 36),
                          Text(id == _hostId ? 'المضيف' : ((pr?['name'] ?? '...') as String),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10)),
                        ]),
                      ),
                    );
                  },
                ),
              ),
              if (target == _hostId)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('دعم صاحب الغرفة يحسب لترند الروم 🔥',
                      style: TextStyle(color: Color(0xFFFDE68A), fontSize: 12)),
                ),
              const SizedBox(height: 10),
              SizedBox(
                height: 300,
                child: GridView.count(
                  crossAxisCount: 4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.72,
                  children: [
                    for (final g in gifts)
                      GestureDetector(
                        onTap: sending
                            ? null
                            : () async {
                                setS(() => sending = true);
                                try {
                                  await supa.rpc('send_gift', params: {
                                    'p_room': widget.roomId,
                                    'p_to': target,
                                    'p_gift': g['id'],
                                    'p_qty': qty,
                                  });
                                  final w = await fetchWallet();
                                  setS(() => gems = w.gems);
                                  _refreshMessages();
                                } catch (e) {
                                  final msg = e.toString();
                                  if (mounted) {
                                    toast(
                                        context,
                                        msg.contains('not enough gems')
                                            ? 'رصيدك من الجواهر لا يكفي، اضغط + للشحن'
                                            : msg.contains('target not in room')
                                                ? 'هذا الشخص غادر الغرفة'
                                                : friendlyError(e));
                                  }
                                } finally {
                                  setS(() => sending = false);
                                }
                              },
                        child: Container(
                          decoration: BoxDecoration(
                            color: C.glass,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: C.glassBorder),
                          ),
                          padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
                          child: Column(children: [
                            Expanded(child: Center(child: _giftIcon(g, 44))),
                            SizedBox(
                              height: 16,
                              width: double.infinity,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(g['name'] as String,
                                    maxLines: 1,
                                    style: const TextStyle(fontSize: 12, height: 1.1, fontWeight: FontWeight.w700)),
                              ),
                            ),
                            SizedBox(
                              height: 16,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  const Icon(Icons.diamond_rounded, size: 12, color: Color(0xFF67E8F9)),
                                  Text(' ${g['price']}', style: const TextStyle(fontSize: 12, height: 1.1)),
                                ]),
                              ),
                            ),
                          ]),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Row(children: [
                const Text('الكمية:  '),
                for (final q in const [1, 5, 10, 50])
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: ChoiceChip(
                      label: Text('$q'),
                      selected: qty == q,
                      onSelected: (_) => setS(() => qty = q),
                    ),
                  ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _giftLine(Map<String, dynamic> m) {
    final meta = Map<String, dynamic>.from((m['meta'] as Map?) ?? const {});
    final uid = m['user_id'] as String;
    final name = (_profiles[uid]?['name'] ?? '...') as String;
    final gems = (meta['gems'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0x33F59E0B), Color(0x00F59E0B)]),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          _giftIcon(meta, 34),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: name, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFFDE68A))),
              const TextSpan(text: '  أهدى  '),
              TextSpan(text: '${meta['to_name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w900)),
              TextSpan(text: '  ${meta['name'] ?? ''} ×${meta['qty'] ?? 1}'),
            ])),
          ),
          const Icon(Icons.diamond_rounded, size: 13, color: Color(0xFF67E8F9)),
          Text(' $gems', style: const TextStyle(fontSize: 12)),
        ]),
      ),
    );
  }

  Widget _giftOverlay() {
    final m = _giftFx;
    if (m == null) return const SizedBox.shrink();
    final meta = Map<String, dynamic>.from((m['meta'] as Map?) ?? const {});
    final name = (_profiles[m['user_id']]?['name'] ?? '') as String;
    return Positioned.fill(
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          key: ValueKey(m['id']),
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 2300),
          builder: (c, t, _) {
            final grow = t < 0.25 ? t / 0.25 : 1.0;
            final fade = t > 0.8 ? (1 - t) / 0.2 : 1.0;
            return Opacity(
              opacity: fade.clamp(0.0, 1.0),
              child: Center(
                child: Transform.scale(
                  scale: 0.5 + 0.6 * grow,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    _giftIcon(meta, 84),
                    Text('$name  ×${meta['qty'] ?? 1}',
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            shadows: [Shadow(blurRadius: 8, color: Colors.black)])),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _send() async {
    if (_iAmChatBanned) return;
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
      if (mounted) {
        toast(context,
            _iAmChatBanned ? 'أنت محظور من الكتابة' : 'تعذّر الإرسال: ${friendlyError(e)}');
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

  // ---------- إعدادات الغرفة (للمالك) ----------

  Future<String?> _pickImage() async {
    final f = await ImagePicker()
        .pickImage(source: ImageSource.gallery, maxWidth: 1400, imageQuality: 85);
    if (f == null) return null;
    try {
      final bytes = await f.readAsBytes();
      final ext = extOf(f.name, ['jpg', 'jpeg', 'png', 'webp'], 'jpg');
      return await uploadMedia(
        bucket: 'avatars',
        folder: myId,
        bytes: bytes,
        ext: ext,
        contentType: 'image/${ext == 'jpg' ? 'jpeg' : ext}',
      );
    } catch (e) {
      if (mounted) toast(context, 'تعذّر رفع الصورة: ${friendlyError(e)}');
      return null;
    }
  }

  Future<void> _saveLook(String bgPreset, String? bgUrl, String skin, String? skinUrl) async {
    try {
      await supa.rpc('room_set_look', params: {
        'p_room': widget.roomId,
        'p_bg_preset': bgPreset,
        'p_bg_url': bgUrl ?? '',
        'p_mic_skin': skin,
        'p_mic_skin_url': skinUrl ?? '',
      });
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _renameRoom() async {
    final t = TextEditingController(text: (_look['title'] ?? widget.title) as String);
    final tp = TextEditingController(text: (_look['topic'] ?? widget.topic) as String);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(c).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('تعديل اسم الروم', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          TextField(controller: t, maxLength: 60, decoration: const InputDecoration(labelText: 'اسم الروم')),
          TextField(
              controller: tp,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'الموضوع (اختياري)')),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: GradButton(label: 'حفظ', onPressed: () => Navigator.pop(c, true))),
        ]),
      ),
    );
    if (ok != true) return;
    try {
      await supa.rpc('room_rename', params: {'p_room': widget.roomId, 'p_title': t.text, 'p_topic': tp.text});
      if (mounted) toast(context, 'تم تعديل الاسم');
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _micModeSheet() async {
    final n = await showModalBottomSheet<int>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('عدد المايكات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          ),
          for (final k in const [2, 8, 12])
            ListTile(
              leading: Icon(Icons.mic_rounded, color: _micCount == k ? C.pink : Colors.white54),
              title: Text('مقعد المضيف + $k ضيوف'),
              subtitle: k == 8 ? const Text('الافتراضي', style: TextStyle(fontSize: 12)) : null,
              trailing: _micCount == k ? const Icon(Icons.check_circle_rounded, color: C.green) : null,
              onTap: () => Navigator.pop(c, k),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Text('عند تقليل العدد يُنزَل من يجلس على المقاعد المحذوفة',
                style: TextStyle(fontSize: 12, color: Colors.white54)),
          ),
        ]),
      ),
    );
    if (n == null || n == _micCount) return;
    try {
      await supa.rpc('set_room_mic_count', params: {'p_room': widget.roomId, 'p_count': n});
      if (mounted) toast(context, 'تم تغيير عدد المايكات');
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _toolsSheet() async {
    Widget tile(IconData i, String label, VoidCallback f, {Color? color}) => InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.pop(context);
            f();
          },
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16)),
              child: Icon(i, color: color ?? Colors.white),
            ),
            const SizedBox(height: 6),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
          ]),
        );
    await showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('أدوات الروم', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 14,
              crossAxisSpacing: 8,
              childAspectRatio: 0.85,
              children: [
                tile(Icons.edit_rounded, 'اسم الروم', _renameRoom),
                tile(Icons.mic_external_on_rounded, 'المايكات', _micModeSheet),
                tile(Icons.wallpaper_rounded, 'الخلفية', _settingsSheet),
                tile(_look['locked'] == true ? Icons.lock_rounded : Icons.lock_open_rounded,
                    'كلمة السر', _toggleLock,
                    color: _look['locked'] == true ? const Color(0xFFFDE68A) : null),
                tile(Icons.library_music_rounded, 'الموسيقى', _musicSheet),
                tile(_roomMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    _roomMuted ? 'تشغيل الصوت' : 'كتم الروم', _toggleRoomMute),
                tile(Icons.power_settings_new_rounded, 'إنهاء الروم', _endRoom,
                    color: const Color(0xFFFF6B6B)),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _settingsSheet() async {
    var bg = (_look['bg_preset'] ?? 'violet') as String;
    var bgUrl = _look['bg_url'] as String?;
    var skin = (_look['mic_skin'] ?? 'none') as String;
    var skinUrl = _look['mic_skin_url'] as String?;
    var catalog = <Map<String, dynamic>>[];
    final owned = <String>{};
    try {
      catalog = List<Map<String, dynamic>>.from(
          await supa.from('room_backgrounds').select().eq('active', true).order('sort'));
      final o = await supa.from('user_backgrounds').select('bg_id').eq('user_id', myId);
      for (final r in o as List) {
        owned.add(r['bg_id'] as String);
      }
    } catch (_) {
      // قاعدة بلا v14: لا كتالوج
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) {
          Future<void> pickCatalog(Map<String, dynamic> b) async {
            final id = b['id'] as String;
            final price = (b['price'] as num).toInt();
            if (price > 0 && !owned.contains(id)) {
              final yes = await showDialog<bool>(
                context: context,
                builder: (d) => AlertDialog(
                  title: Text('شراء «${b['name']}»'),
                  content: Text('السعر $price جوهرة، تشتريها مرة واحدة وتبقى لك.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
                    FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('شراء')),
                  ],
                ),
              );
              if (yes != true) return;
              try {
                await supa.rpc('buy_room_background', params: {'p_bg': id});
                owned.add(id);
              } catch (e) {
                if (mounted) toast(context, friendlyError(e));
                return;
              }
            }
            setS(() => bgUrl = b['image_url'] as String);
            await _saveLook(bg, bgUrl, skin, skinUrl);
          }

          Widget upTile(String label, String? url, Future<void> Function() onTap) => GestureDetector(
                onTap: onTap,
                child: Container(
                  width: 70,
                  height: 70,
                  margin: const EdgeInsetsDirectional.only(end: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white38),
                    image: url != null
                        ? DecorationImage(image: NetworkImage(url), fit: BoxFit.cover)
                        : null,
                  ),
                  child: url != null
                      ? null
                      : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(Icons.image_rounded, size: 22),
                          Text(label, style: const TextStyle(fontSize: 10)),
                        ]),
                ),
              );
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('إعدادات الغرفة',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 14),
                const Text('خلفية الغرفة', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 70,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    upTile('رفع صورة', bgUrl, () async {
                      final u = await _pickImage();
                      if (u != null) {
                        setS(() => bgUrl = u);
                        await _saveLook(bg, bgUrl, skin, skinUrl);
                      }
                    }),
                    for (final b in catalog)
                      GestureDetector(
                        onTap: () => pickCatalog(b),
                        child: Container(
                          width: 70,
                          height: 70,
                          margin: const EdgeInsetsDirectional.only(end: 8),
                          alignment: Alignment.bottomCenter,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            image: DecorationImage(image: NetworkImage(b['image_url'] as String), fit: BoxFit.cover),
                            border: Border.all(
                                color: bgUrl == b['image_url'] ? Colors.white : Colors.white24,
                                width: bgUrl == b['image_url'] ? 2.5 : 1),
                          ),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            decoration: const BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.vertical(bottom: Radius.circular(13))),
                            child: Text(
                              (b['price'] as num) == 0
                                  ? 'مجانية'
                                  : owned.contains(b['id']) ? 'مملوكة' : '💎 ${b['price']}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 10, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    for (final pr in roomBgPresets)
                      GestureDetector(
                        onTap: () {
                          setS(() {
                            bg = pr.id;
                            bgUrl = null;
                          });
                          _saveLook(bg, null, skin, skinUrl);
                        },
                        child: Container(
                          width: 70,
                          height: 70,
                          margin: const EdgeInsetsDirectional.only(end: 8),
                          decoration: BoxDecoration(
                            gradient: pr.gradient,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: bgUrl == null && bg == pr.id ? Colors.white : Colors.white24,
                                width: bgUrl == null && bg == pr.id ? 2.5 : 1),
                          ),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 16),
                const Text('خلفية المايكات', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 84,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    upTile('رفع صورة', skinUrl, () async {
                      final u = await _pickImage();
                      if (u != null) {
                        setS(() => skinUrl = u);
                        await _saveLook(bg, bgUrl, skin, skinUrl);
                      }
                    }),
                    for (final id in micSkinIds)
                      GestureDetector(
                        onTap: () {
                          setS(() {
                            skin = id;
                            skinUrl = null;
                          });
                          _saveLook(bg, bgUrl, skin, null);
                        },
                        child: Container(
                          width: 70,
                          margin: const EdgeInsetsDirectional.only(end: 8),
                          child: Column(children: [
                            Container(
                              width: 56,
                              height: 56,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: skinUrl == null && skin == id
                                        ? Colors.white
                                        : Colors.white24,
                                    width: skinUrl == null && skin == id ? 2.5 : 1),
                              ),
                              child: MicSkin(skin: id, size: 40),
                            ),
                            Text(micSkinNames[id]!, style: const TextStyle(fontSize: 11)),
                          ]),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: GradButton(
                    label: 'إنهاء الغرفة',
                    icon: Icons.power_settings_new_rounded,
                    outlined: true,
                    onPressed: () {
                      Navigator.pop(c);
                      _endRoom();
                    },
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _closed = true;
    _beat?.cancel();
    _xpTimer?.cancel();
    _msgSub?.cancel();
    _seatSub?.cancel();
    _flagSub?.cancel();
    _lookSub?.cancel();
    _fxTimer?.cancel();
    _bcastTimer?.cancel();
    _bcastSub?.cancel();
    _duckTimer?.cancel();
    _mp?.stop();
    _mp?.dispose();
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
    final size = isHostSeat ? 66.0 : 50.0;
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
            width: size + 8,
            height: size + 8,
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black26,
              border: Border.all(color: Colors.white30),
            ),
            child: Icon(isHostSeat ? Icons.workspace_premium_rounded : Icons.mic_none_rounded,
                color: Colors.white54, size: isHostSeat ? 32 : 26),
          ),
          Text(isHostSeat ? 'المضيف' : '$n',
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ]),
      );
    }
    final prof = _profiles[uid];
    final name = (prof?['name'] ?? '...') as String;
    final p = _participantOf(uid);
    final speaking = p?.isSpeaking ?? false;
    final muted = uid == myId ? !_micOn : (p?.isMuted ?? true);
    final role = _roleOf(uid);
    final forcedMute = _flags[uid]?['muted'] == true;
    return GestureDetector(
      onTap: () => _userSheet(uid, seat: n),
      child: SizedBox(
        width: 78,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
            MicSkin(
                skin: (_look['mic_skin'] ?? 'none') as String,
                url: _look['mic_skin_url'] as String?,
                size: size + 8),
            Avatar(
              name: name,
              url: prof?['avatar_url'] as String?,
              size: size,
              speaking: speaking && !muted,
            ),
            if (role == 'owner')
              const Positioned(
                top: -4,
                left: 0,
                child: Icon(Icons.workspace_premium_rounded, color: Color(0xFFFBBF24), size: 22),
              ),
            if (role == 'mod')
              const Positioned(
                top: -2,
                left: 2,
                child: CircleAvatar(
                  radius: 10,
                  backgroundColor: Color(0xFF2563EB),
                  child: Icon(Icons.shield_rounded, size: 12, color: Colors.white),
                ),
              ),
            if (muted || forcedMute)
              Positioned(
                bottom: 0,
                right: 2,
                child: CircleAvatar(
                  radius: 10,
                  backgroundColor: forcedMute ? const Color(0xFFEF4444) : const Color(0xFF1B1040),
                  child: const Icon(Icons.mic_off_rounded, size: 12, color: Colors.white),
                ),
              ),
          ]),
          const SizedBox(height: 2),
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
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
            style: const TextStyle(color: Colors.white60, fontSize: 12)),
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
              onTap: () => _userSheet(p.identity),
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

  /// رسالة بدون إطار: صورة + اسم + مستوى + لقب + وسم الرتبة، والنص تحته.
  Widget _message(Map<String, dynamic> m) {
    if (m['kind'] == 'gift') return _giftLine(m);
    final uid = m['user_id'] as String;
    final prof = _profiles[uid];
    final name = (prof?['name'] ?? '...') as String;
    final lv = levelOf((prof?['xp'] as num?)?.toInt() ?? 0);
    final role = _roleOf(uid);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onTap: () => _userSheet(uid),
          child: Avatar(name: name, url: prof?['avatar_url'] as String?, size: 34),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 5, children: [
              Text(name,
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFFC4B5FD), fontWeight: FontWeight.w800)),
              LevelBadge(level: lv, size: 22),
              TitleImage(level: lv, height: 24),
              if (role != 'user')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: role == 'owner' ? const Color(0xFFF59E0B) : const Color(0xFF2563EB),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(role == 'owner' ? 'مالك' : 'مشرف',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                ),
            ]),
            const SizedBox(height: 2),
            Text(m['body'] as String, style: const TextStyle(fontSize: 15, height: 1.35)),
          ]),
        ),
      ]),
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback? onTap, {Color? bg, Gradient? grad}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        margin: const EdgeInsetsDirectional.only(end: 6),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: grad == null ? (bg ?? const Color(0x22FFFFFF)) : null,
          gradient: grad,
        ),
        child: Icon(icon, size: 21),
      ),
    );
  }

  Widget _composer() {
    final seated = _mySeat != null;
    final micOff = !seated || !_micOn || _iAmMuted;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
        child: Row(children: [
          _circleBtn(
            micOff ? Icons.mic_off_rounded : Icons.mic_rounded,
            seated && _connected
                ? () {
                    if (_iAmMuted) {
                      toast(context, 'صاحب الغرفة كتم المايك الخاص بك');
                    } else {
                      _setMic(!_micOn);
                    }
                  }
                : () => toast(context, 'اجلس على مقعد للتحدث'),
            bg: micOff ? const Color(0xD9EF4444) : null,
            grad: micOff ? null : brandGradient,
          ),
          _circleBtn(_roomMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              _toggleRoomMute,
              bg: _roomMuted ? const Color(0xD9EF4444) : null),
          _circleBtn(Icons.card_giftcard_rounded, () => _giftSheet(), bg: const Color(0x33F59E0B)),
          if (_canDj) _circleBtn(Icons.music_note_rounded, _musicSheet, bg: const Color(0x33EC4899)),
          Expanded(
            child: _iAmChatBanned
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('تم حظرك من الكتابة في هذه الغرفة',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFFFF8A8A), fontSize: 13)),
                  )
                : TextField(
                    controller: _input,
                    maxLength: 500,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'اكتب رسالة...',
                      counterText: '',
                      filled: false,
                    ),
                  ),
          ),
          if (!_iAmChatBanned)
            IconButton(
                onPressed: _send,
                icon: const Icon(Icons.send_rounded, color: Color(0xFFC4B5FD))),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final title = (_look['title'] ?? widget.title) as String;
    return Scaffold(
      body: Stack(fit: StackFit.expand, children: [
        RoomBackground(preset: _look['bg_preset'] as String?, url: _look['bg_url'] as String?),
        SafeArea(
          bottom: false,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_forward_ios_rounded, size: 20),
                ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                    if (((_look['topic'] ?? widget.topic) as String).isNotEmpty)
                      Text((_look['topic'] ?? widget.topic) as String,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: Colors.white70)),
                  ]),
                ),
                if (_trending)
                  Container(
                    margin: const EdgeInsetsDirectional.only(end: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFFF97316), Color(0xFFEF4444)]),
                        borderRadius: BorderRadius.circular(14)),
                    child: const Text('🔥 ترند', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration:
                      BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    const Icon(Icons.people_alt_rounded, size: 15),
                    const SizedBox(width: 4),
                    Text('${_participants.length}',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ]),
                ),
                if (_farmOn)
                  IconButton(
                    tooltip: 'المزرعة',
                    onPressed: _openFarm,
                    icon: const Icon(Icons.agriculture_rounded, color: Color(0xFF86EFAC)),
                  ),
                if (_iAmOwner)
                  IconButton(
                    tooltip: 'قفل الروم',
                    onPressed: _toggleLock,
                    icon: Icon(_look['locked'] == true ? Icons.lock_rounded : Icons.lock_open_rounded,
                        color: _look['locked'] == true ? const Color(0xFFFDE68A) : null),
                  ),
                if (_iAmOwner)
                  IconButton(
                    tooltip: 'أدوات الروم',
                    onPressed: _toolsSheet,
                    icon: const Icon(Icons.dashboard_customize_rounded),
                  ),
              ]),
            ),
            if (_connecting) const LinearProgressIndicator(minHeight: 2, color: C.pink),
            if (_error != null)
              Container(
                width: double.infinity,
                color: const Color(0x55FF0000),
                padding: const EdgeInsets.all(10),
                child: Text('تعذّر الاتصال بالصوت: $_error', style: const TextStyle(fontSize: 13)),
              ),
            _nowPlaying(),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: h * 0.50),
              child: SingleChildScrollView(
                child: Column(children: [
                  Center(child: _seat(0)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: GridView.count(
                      crossAxisCount: _micCount == 2 ? 2 : 4,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: _micCount == 2 ? 1.8 : 0.9,
                      children: [for (var n = 1; n <= _micCount; n++) Center(child: _seat(n))],
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
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                itemCount: _messages.length,
                itemBuilder: (_, i) => _message(_messages[i]),
              ),
            ),
            _composer(),
          ]),
        ),
        _giftOverlay(),
        _bcastBanner(),
      ]),
    );
  }
}


/// بطاقة المستخدم داخل الروم: صورة بإطار (للترند)، الاسم، متابعون، عمر، رتبة، ألقاب، وأزرار سريعة.
class _UserCard extends StatefulWidget {
  final String uid, name, roleText;
  final String? avatarUrl;
  final int level;
  final bool framed, mine;
  final VoidCallback onProfile, onGift, onChat;
  const _UserCard({
    required this.uid,
    required this.name,
    required this.roleText,
    required this.avatarUrl,
    required this.level,
    required this.framed,
    required this.mine,
    required this.onProfile,
    required this.onGift,
    required this.onChat,
  });

  @override
  State<_UserCard> createState() => _UserCardState();
}

class _UserCardState extends State<_UserCard> {
  Map<String, dynamic> _d = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    () async {
      try {
        final r = await supa.rpc('get_profile', params: {'p_id': widget.uid}) as List;
        if (r.isNotEmpty && mounted) setState(() => _d = Map<String, dynamic>.from(r.first as Map));
      } catch (_) {}
    }();
  }

  Future<void> _follow() async {
    if (_busy) return;
    setState(() => _busy = true);
    final f = _d['is_following'] == true;
    try {
      await supa.rpc(f ? 'unfollow_user' : 'follow_user', params: {'p_id': widget.uid});
      _d['is_following'] = !f;
      _d['followers'] = ((_d['followers'] as num?)?.toInt() ?? 0) + (f ? -1 : 1);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _chip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(12)),
        child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c)),
      );

  @override
  Widget build(BuildContext context) {
    final avatar = Avatar(name: widget.name, url: widget.avatarUrl, size: 72);
    final age = (_d['age'] as num?)?.toInt();
    final followers = (_d['followers'] as num?)?.toInt();
    final following = _d['is_following'] == true;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        GestureDetector(
          onTap: widget.onProfile,
          child: widget.framed
              ? TrendFrame(size: 72, child: ClipOval(child: avatar))
              : ClipOval(child: avatar),
        ),
        const SizedBox(height: 8),
        Text(widget.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(followers == null ? ' ' : '$followers متابع',
            style: const TextStyle(fontSize: 12, color: Colors.white60)),
        const SizedBox(height: 8),
        Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
          if (age != null) _chip('🎂 $age', const Color(0xFF67E8F9)),
          _chip(widget.roleText, widget.roleText == 'عضو' ? Colors.white70 : const Color(0xFFFDE68A)),
          if (_d['verified'] == true) _chip('موثّق ✓', const Color(0xFF60A5FA)),
        ]),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          LevelBadge(level: widget.level, size: 30),
          const SizedBox(width: 6),
          TitleImage(level: widget.level, height: 30),
        ]),
        const SizedBox(height: 12),
        if (!widget.mine)
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy || _d.isEmpty ? null : _follow,
                icon: Icon(following ? Icons.check_rounded : Icons.person_add_alt_1_rounded, size: 18),
                label: Text(following ? 'تتابعه' : 'متابعة'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: widget.onGift,
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF59E0B)),
                icon: const Icon(Icons.card_giftcard_rounded, size: 18),
                label: const Text('هدية'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: widget.onChat,
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                label: const Text('مراسلة'),
              ),
            ),
          ])
        else
          SizedBox(
              width: double.infinity,
              child: OutlinedButton(onPressed: widget.onProfile, child: const Text('عرض ملفي'))),
      ]),
    );
  }
}
