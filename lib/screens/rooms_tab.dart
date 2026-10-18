import 'dart:async';

import 'package:flutter/material.dart';

import '../active_room.dart';
import '../main.dart';
import '../room_look.dart';
import '../songs.dart';
import '../theme.dart';

/// يسأل عن كلمة سر الروم المقفلة. يرجع true إذا سُمح بالدخول.
Future<bool> _askRoomPassword(BuildContext context, String roomId) async {
  final ctrl = TextEditingController();
  String? err;
  bool busy = false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) => AlertDialog(
        title: const Text('الروم مقفلة 🔒'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('اكتب كلمة السر للدخول'),
          const SizedBox(height: 8),
          TextField(
            controller: ctrl,
            autofocus: true,
            obscureText: true,
            maxLength: 16,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(counterText: '', errorText: err),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          TextButton(
            onPressed: busy
                ? null
                : () async {
                    setS(() => busy = true);
                    try {
                      final res = await supa.rpc('join_room_with_password',
                          params: {'p_room': roomId, 'p_pass': ctrl.text});
                      if (res == 'ok') {
                        if (c.mounted) Navigator.pop(c, true);
                        return;
                      }
                      setS(() {
                        busy = false;
                        if (res == 'blocked') {
                          err = 'محاولات كثيرة، انتظر 10 دقائق';
                        } else {
                          final n = res.toString().split(':').last;
                          err = 'كلمة السر خطأ (متبقي $n محاولات)';
                        }
                      });
                    } catch (e) {
                      setS(() {
                        busy = false;
                        err = friendlyError(e);
                      });
                    }
                  },
            child: const Text('دخول'),
          ),
        ],
      ),
    ),
  );
  return ok == true;
}

Future<void> openRoom(BuildContext context, Map<String, dynamic> r) async {
  if (r['host_id'] != myId) {
    try {
      final can = await supa.rpc('can_enter_room', params: {'p_room': r['id']});
      if (can == false) {
        if (!context.mounted) return;
        if (!await _askRoomPassword(context, r['id'] as String)) return;
      }
    } catch (_) {
      // قاعدة قديمة بلا v13: نكمل كالسابق
    }
  }
  if (!context.mounted) return;
  // نرجع للشاشة الرئيسية (فوقها تُعرض الغرفة) ثم نفتح الغرفة
  Navigator.of(context).popUntil((r) => r.isFirst);
  await ActiveRoom.open(ActiveRoomData(
    roomId: r['id'] as String,
    title: r['title'] as String,
    topic: (r['topic'] ?? '') as String,
    isHost: r['host_id'] == myId,
    hostId: r['host_id'] as String?,
    hostAvatar: r['host_avatar'] as String?,
  ));
}

/// نافذة إنشاء غرفة جديدة ثم الدخول إليها (تُستعمل من زر المايك الأوسط أيضاً).
Future<void> createRoomFlow(BuildContext context) async {
  // غرفتي المحفوظة: آخر غرفة أنشأتها (الاسم والموضوع والخلفية) تُفتح مباشرة بلا سؤال.
  Map<String, dynamic>? saved;
  try {
    final r = await supa
        .from('rooms')
        .select()
        .eq('host_id', myId)
        .order('created_at', ascending: false)
        .limit(1);
    final l = List<Map<String, dynamic>>.from(r);
    if (l.isNotEmpty && ((l.first['title'] ?? '') as String).trim().length >= 2) saved = l.first;
  } catch (_) {}
  if (!context.mounted) return;
  if (saved != null) {
    try {
      final ins = <String, dynamic>{
        'title': saved['title'],
        'topic': saved['topic'] ?? '',
        'host_id': myId,
      };
      for (final k in ['bg_preset', 'bg_url', 'mic_skin', 'mic_skin_url', 'mic_count']) {
        if (saved[k] != null) ins[k] = saved[k];
      }
      final row = await supa.from('rooms').insert(ins).select().single();
      if (!context.mounted) return;
      await openRoom(context, Map<String, dynamic>.from(row));
      return;
    } catch (_) {
      // فشل النسخ (عمود ناقص مثلاً): نرجع للنافذة العادية
    }
  }
  if (!context.mounted) return;
  final title = TextEditingController();
  final topic = TextEditingController();
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (c) => Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(c).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('غرفة جديدة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        TextField(
          controller: title,
          maxLength: 60,
          decoration: const InputDecoration(labelText: 'اسم الغرفة'),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: topic,
          maxLength: 120,
          decoration: const InputDecoration(labelText: 'موضوع النقاش (اختياري)'),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: GradButton(
            label: 'ابدأ الغرفة',
            icon: Icons.mic_rounded,
            onPressed: () => Navigator.pop(c, true),
          ),
        ),
      ]),
    ),
  );
  if (ok != true || !context.mounted) return;
  final t = title.text.trim();
  if (t.length < 2) {
    toast(context, 'اسم الغرفة قصير جداً');
    return;
  }
  try {
    final row = await supa
        .from('rooms')
        .insert({'title': t, 'topic': topic.text.trim(), 'host_id': myId})
        .select()
        .single();
    if (!context.mounted) return;
    await openRoom(context, Map<String, dynamic>.from(row));
  } catch (e) {
    if (context.mounted) toast(context, 'تعذّر إنشاء الغرفة: ${friendlyError(e)}');
  }
}

class RoomsTab extends StatefulWidget {
  final bool active;
  final List<Map<String, dynamic>>? seed; // للاختبار فقط
  const RoomsTab({super.key, this.active = true, this.seed});

  @override
  State<RoomsTab> createState() => _RoomsTabState();
}

const _rInk = Color(0xFF1F1B2E);
const _rSub = Color(0xFF9AA0AE);
const _rViolet = Color(0xFF7C3AED);

class _RoomsTabState extends State<RoomsTab> {
  List<Map<String, dynamic>> _rooms = [];
  bool _loading = true;
  String? _error;
  Timer? _timer;
  bool _friendsOnly = false;
  _Frames _frames = const _Frames();

  @override
  void initState() {
    super.initState();
    if (widget.seed != null) {
      _rooms = widget.seed!;
      _loading = false;
      return;
    }
    _load();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (widget.active) _load(silent: true);
    });
  }

  @override
  void didUpdateWidget(covariant RoomsTab old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _load(silent: true);
      _loadFrames();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadFrames() async {
    try {
      final r = await supa.from('app_settings').select().inFilter('key', ['room_frame_big', 'room_frame_small']);
      String? v(String k) {
        for (final m in r as List) {
          if (m['key'] == k && (m['value'] as String).isNotEmpty) return m['value'] as String;
        }
        return null;
      }

      if (mounted) setState(() => _frames = _Frames(big: v('room_frame_big'), small: v('room_frame_small')));
    } catch (_) {}
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) _loadFrames();
    try {
      List<Map<String, dynamic>> rows;
      try {
        final r = await supa.rpc('list_rooms_v2');
        rows = List<Map<String, dynamic>>.from(r as List);
      } catch (_) {
        // قاعدة بلا v15: نستعمل القائمة القديمة (الترند القديم يُعدّ ترند)
        final r = await supa.rpc('list_rooms');
        rows = [
          for (final m in List<Map<String, dynamic>>.from(r as List))
            {...m, 'week_support': m['trending'] == true ? ((m['support'] as num?)?.toInt() ?? 1) : 0}
        ];
      }
      if (!mounted) return;
      setState(() {
        _rooms = rows;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = friendlyError(e);
      });
    }
  }

  Future<void> _open(Map<String, dynamic> r) async {
    await openRoom(context, r);
    if (mounted) _load(silent: true);
  }

  int _n(Map<String, dynamic> r, String k) => (r[k] as num?)?.toInt() ?? 0;

  List<Map<String, dynamic>> get _base {
    final l = List<Map<String, dynamic>>.of(_rooms);
    if (_friendsOnly) l.removeWhere((r) => _n(r, 'friends') == 0);
    return l;
  }

  /// الترند: كل غرفة لها دعم هذا الأسبوع، مرتبة بالدعم، حتى 9 غرف.
  List<Map<String, dynamic>> get _trend {
    final l = _base.where((r) => _n(r, 'week_support') > 0).toList()
      ..sort((a, b) => _n(b, 'week_support').compareTo(_n(a, 'week_support')));
    return l.take(9).toList();
  }

  Widget _headerBtn(IconData i, String tip, VoidCallback f) => IconButton(
        tooltip: tip,
        onPressed: f,
        icon: Icon(i, color: Colors.white),
      );

  @override
  Widget build(BuildContext context) {
    final trend = _trend;
    return Scaffold(
      backgroundColor: const Color(0xFF6D28D9),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF5B21B6), Color(0xFF8B5CF6)]),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 8, 10),
              child: Row(children: [
                const Text('الغرف',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    const Icon(Icons.circle, size: 8, color: Color(0xFF4ADE80)),
                    const SizedBox(width: 5),
                    Text('${_rooms.length} مباشرة',
                        style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w700)),
                  ]),
                ),
                const Spacer(),
                _headerBtn(
                    _friendsOnly ? Icons.people_alt_rounded : Icons.people_outline_rounded,
                    'أصدقائي فقط',
                    () => setState(() => _friendsOnly = !_friendsOnly)),
                _headerBtn(Icons.library_music_rounded, 'الأغاني',
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SongsScreen()))),
                _headerBtn(Icons.history_rounded, 'الرومات السابقة', () async {
                  await Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const RecentRoomsScreen()));
                  if (mounted) _load(silent: true);
                }),
              ]),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  child: DefaultTextStyle.merge(
                    style: const TextStyle(color: _rInk),
                    child: RefreshIndicator(
                      onRefresh: _load,
                      child: _loading
                          ? ListView(children: const [
                              SizedBox(height: 200),
                              Center(child: CircularProgressIndicator(color: _rViolet)),
                            ])
                          : _error != null
                              ? ListView(children: [
                                  const SizedBox(height: 120),
                                  Center(
                                      child: Text('تعذّر تحميل الغرف\n$_error',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(color: _rSub))),
                                ])
                              : _body(),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// ترتيب العرض: الترند أولاً (حسب الدعم) ثم باقي الغرف حسب عدد المستمعين.
  List<Map<String, dynamic>> get _ordered {
    final t = _trend;
    final ids = {for (final r in t) r['id']};
    final rest = _base.where((r) => !ids.contains(r['id'])).toList()
      ..sort((a, b) => _n(b, 'listeners').compareTo(_n(a, 'listeners')));
    return [...t, ...rest];
  }

  Widget _card(List<Map<String, dynamic>> all, int i, {bool big = false}) {
    final r = all[i];
    final trending = _n(r, 'week_support') > 0;
    return _CoverCard(
      room: r,
      big: big,
      frame: trending ? (big ? _frames.big : _frames.small) : null,
      onTap: () => _open(r),
    );
  }

  Widget _body() {
    final all = _ordered;
    const g = 8.0;
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth - 24; // هوامش 12 من الجانبين
      final cell = (w - 2 * g) / 3;
      final bigSize = cell * 2 + g;
      final rows = <Widget>[];
      if (all.isNotEmpty) {
        if (all.length >= 3) {
          rows.add(SizedBox(
            height: bigSize,
            child: Row(children: [
              SizedBox(width: bigSize, child: _card(all, 0, big: true)),
              const SizedBox(width: g),
              Expanded(
                child: Column(children: [
                  SizedBox(height: cell, child: _card(all, 1)),
                  const SizedBox(height: g),
                  SizedBox(height: cell, child: _card(all, 2)),
                ]),
              ),
            ]),
          ));
        }
        final from = all.length >= 3 ? 3 : 0;
        if (all.length > from) {
          if (from == 3) rows.add(const SizedBox(height: g));
          rows.add(GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: g,
            crossAxisSpacing: g,
            childAspectRatio: 1,
            children: [for (var i = from; i < all.length; i++) _card(all, i)],
          ));
        }
      } else {
        rows.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(children: [
            const Icon(Icons.mic_none_rounded, size: 72, color: Color(0xFFD4D4E0)),
            const SizedBox(height: 12),
            Text(
                _friendsOnly
                    ? 'لا يوجد أصدقاء لك داخل الغرف الآن'
                    : 'لا توجد غرف مباشرة الآن\nكن أول من يبدأ غرفة!',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _rSub, fontSize: 16)),
          ]),
        ));
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 120),
        children: rows,
      );
    });
  }
}

String _fmt(num n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return '$n';
}

Widget _roomBg(Map<String, dynamic> r, {double dim = 0.25}) =>
    RoomBackground(preset: r['bg_preset'] as String?, url: r['bg_url'] as String?, dim: dim);

Widget _lockBadge(Map<String, dynamic> r) => r['locked'] == true
    ? const Padding(
        padding: EdgeInsetsDirectional.only(end: 4),
        child: Icon(Icons.lock_rounded, size: 14, color: Color(0xFFFDE68A)))
    : const SizedBox.shrink();


class _Frames {
  final String? big;
  final String? small;
  const _Frames({this.big, this.small});
}

/// بطاقة غرفة: صورة صاحب الغرفة كغلاف كامل + عدد المستمعين + الاسم + إطار الترند (إن وُجد).
class _CoverCard extends StatelessWidget {
  final Map<String, dynamic> room;
  final VoidCallback onTap;
  final String? frame; // رابط الإطار (للترند فقط)
  final bool big;
  const _CoverCard(
      {required this.room, required this.onTap, this.frame, this.big = false});

  @override
  Widget build(BuildContext context) {
    final listeners = (room['listeners'] as num?)?.toInt() ?? 0;
    final name = (room['host_name'] ?? '?') as String;
    final avatar = room['host_avatar'] as String?;
    final title = (room['title'] ?? '') as String;
    return GestureDetector(
      onTap: onTap,
      child: Stack(fit: StackFit.expand, clipBehavior: Clip.none, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(big ? 16 : 12),
          child: Stack(fit: StackFit.expand, children: [
            _roomBg(room, dim: 0.1),
            if (avatar != null && avatar.isNotEmpty)
              Image.network(avatar,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Center(
                      child: Text(name.isEmpty ? '?' : name.characters.first,
                          style: const TextStyle(fontSize: 40, color: Colors.white54))))
            else
              Center(
                  child: Text(name.isEmpty ? '?' : name.characters.first,
                      style: TextStyle(fontSize: big ? 90 : 40, color: Colors.white54))),
            // تظليل سفلي لقراءة الاسم
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: big ? 90 : 60,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0xCC000000), Color(0x00000000)]),
                ),
              ),
            ),
            Positioned(
              top: big ? 12 : 8,
              left: big ? 14 : 9,
              child: Text('$listeners',
                  style: TextStyle(
                      fontSize: big ? 20 : 14,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      shadows: const [Shadow(blurRadius: 4, color: Colors.black87)])),
            ),
            PositionedDirectional(
              bottom: big ? 12 : 8,
              start: big ? 14 : 9,
              end: big ? 14 : 9,
              child: Row(children: [
                _lockBadge(room),
                Expanded(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: big ? 18 : 12,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          shadows: const [Shadow(blurRadius: 4, color: Colors.black87)])),
                ),
              ]),
            ),
          ]),
        ),
        if (frame != null && frame!.isNotEmpty)
          IgnorePointer(
            child: Image.network(frame!, fit: BoxFit.fill, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          ),
      ]),
    );
  }
}

class RoomCard extends StatelessWidget {
  final Map<String, dynamic> room;
  final VoidCallback onTap;
  final int? rank;
  const RoomCard({super.key, required this.room, required this.onTap, this.rank});

  @override
  Widget build(BuildContext context) {
    final title = room['title'] as String;
    final topic = (room['topic'] ?? '') as String;
    final seated = (room['seated'] as num?)?.toInt() ?? 0;
    final friends = (room['friends'] as num?)?.toInt() ?? 0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 142,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: C.violet.withValues(alpha: 0.45)),
          boxShadow: [BoxShadow(color: C.violet.withValues(alpha: 0.18), blurRadius: 18)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(21),
          child: Stack(fit: StackFit.expand, children: [
            RoomBackground(
                preset: room['bg_preset'] as String?, url: room['bg_url'] as String?, dim: 0.15),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (room['trending'] == true)
                    Container(
                      margin: const EdgeInsetsDirectional.only(end: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFFF97316), Color(0xFFEF4444)]),
                          borderRadius: BorderRadius.circular(12)),
                      child: Text(
                          rank == null
                              ? '🔥 ترند'
                              : '${rank == 1 ? '🥇' : (rank == 2 ? '🥈' : '🥉')} المركز $rank',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                    ),
                  Avatar(
                      name: (room['host_name'] ?? '?') as String,
                      url: room['host_avatar'] as String?,
                      size: 36),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        if (room['locked'] == true)
                          const Padding(
                            padding: EdgeInsetsDirectional.only(end: 4),
                            child: Icon(Icons.lock_rounded, size: 15, color: Color(0xFFFDE68A)),
                          ),
                        Expanded(
                          child: Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                        ),
                      ]),
                      Text(
                          topic.isEmpty
                              ? 'المضيف: ${room['host_name']}'
                              : '$topic · ${room['host_name']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ]),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: const [
                      Icon(Icons.graphic_eq_rounded, size: 13, color: C.green),
                      SizedBox(width: 4),
                      Text('الآن', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ]),
                const Spacer(),
                Row(children: [
                  for (var i = 0; i < 9; i++)
                    Container(
                      width: 9,
                      height: 9,
                      margin: const EdgeInsetsDirectional.only(end: 4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < seated ? C.pink : Colors.white24,
                      ),
                    ),
                  const SizedBox(width: 8),
                  const Icon(Icons.people_alt_rounded, size: 16, color: Colors.white70),
                  const SizedBox(width: 4),
                  Text('${room['listeners']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  if (friends > 0) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.favorite_rounded, size: 14, color: C.pink),
                    Text(' $friends', style: const TextStyle(fontSize: 12)),
                  ],
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 7),
                    decoration: BoxDecoration(
                      gradient: brandGradient,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Text('انضم', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}


/// الرومات السابقة: أصحاب الرومات الذين دخلت عندهم، مع حالة الروم الآن.
class RecentRoomsScreen extends StatefulWidget {
  const RecentRoomsScreen({super.key});

  @override
  State<RecentRoomsScreen> createState() => _RecentRoomsScreenState();
}

class _RecentRoomsScreenState extends State<RecentRoomsScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await supa.rpc('my_recent_rooms');
      if (mounted) {
        setState(() {
          _rows = List<Map<String, dynamic>>.from(r as List);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        toast(context, friendlyError(e));
      }
    }
  }

  Future<void> _open(Map<String, dynamic> r) async {
    final id = r['live_room_id'] as String?;
    if (id == null) {
      toast(context, 'هذا الروم غير مفتوح الآن');
      return;
    }
    await openRoom(context, {
      'id': id,
      'title': r['live_title'] ?? r['room_title'],
      'topic': r['live_topic'] ?? '',
      'host_id': r['host_id'],
    });
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الرومات السابقة', style: TextStyle(fontWeight: FontWeight.w800))),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: C.pink))
          : _rows.isEmpty
              ? const Center(
                  child: Text('لم تدخل أي روم بعد',
                      style: TextStyle(color: Colors.white60, fontSize: 16)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: _rows.length,
                  itemBuilder: (_, i) {
                    final r = _rows[i];
                    final live = r['live_room_id'] != null;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GlassCard(
                        onTap: () => _open(r),
                        child: Row(children: [
                          Avatar(name: (r['host_name'] ?? '?') as String, url: r['host_avatar'] as String?, size: 40),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                if (r['locked'] == true)
                                  const Padding(
                                    padding: EdgeInsetsDirectional.only(end: 4),
                                    child: Icon(Icons.lock_rounded, size: 14, color: Color(0xFFFDE68A)),
                                  ),
                                Expanded(
                                  child: Text((r['live_title'] ?? r['room_title']) as String,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w800)),
                                ),
                              ]),
                              Text('المضيف: ${r['host_name']}',
                                  style: const TextStyle(color: Colors.white60, fontSize: 12)),
                            ]),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: live ? const Color(0x3334D399) : Colors.white12,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(live ? 'مباشر الآن' : 'غير مفتوح',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: live ? C.green : Colors.white54)),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
    );
  }
}
