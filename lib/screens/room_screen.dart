import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../audio.dart';
import '../level.dart';
import '../main.dart';
import '../media.dart';
import '../room_look.dart';
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
  }

  Future<void> _start() async {
    try {
      final ok = await supa.rpc('room_heartbeat', params: {'p_room': widget.roomId});
      if (ok != true) throw 'الغرفة منتهية';
      _beat = Timer.periodic(const Duration(seconds: 15), (_) => _heartbeat());
      _gainXp();
      _xpTimer = Timer.periodic(const Duration(minutes: 10), (_) => _gainXp());
      _listenMessages();
      _listenSeats();
      _listenFlags();
      _listenLook();

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

  void _listenLook() {
    _lookSub = supa
        .from('rooms')
        .stream(primaryKey: ['id'])
        .eq('id', widget.roomId)
        .listen((rows) {
      if (!mounted || rows.isEmpty) return;
      setState(() => _look = Map<String, dynamic>.from(rows.first));
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
              const SizedBox(height: 14),
              Avatar(name: name, url: prof?['avatar_url'] as String?, size: 60),
              const SizedBox(height: 6),
              Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                LevelBadge(level: lv, size: 30),
                const SizedBox(width: 6),
                TitleImage(level: lv, height: 30),
              ]),
              Text(role == 'owner' ? 'صاحب الغرفة' : (role == 'mod' ? 'مشرف' : 'عضو'),
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const Divider(color: Colors.white12),
              _sheetAction(Icons.person_rounded, 'عرض الملف الشخصي', '',
                  () => done(() => _openProfile(uid))),
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

  Future<void> _settingsSheet() async {
    var bg = (_look['bg_preset'] ?? 'violet') as String;
    var bgUrl = _look['bg_url'] as String?;
    var skin = (_look['mic_skin'] ?? 'none') as String;
    var skinUrl = _look['mic_skin_url'] as String?;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) {
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
                    if (widget.topic.isNotEmpty)
                      Text(widget.topic,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: Colors.white70)),
                  ]),
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
                if (_iAmOwner)
                  IconButton(
                    onPressed: _settingsSheet,
                    icon: const Icon(Icons.settings_rounded),
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
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: h * 0.50),
              child: SingleChildScrollView(
                child: Column(children: [
                  Center(child: _seat(0)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: GridView.count(
                      crossAxisCount: 4,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: 0.9,
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
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                itemCount: _messages.length,
                itemBuilder: (_, i) => _message(_messages[i]),
              ),
            ),
            _composer(),
          ]),
        ),
      ]),
    );
  }
}
