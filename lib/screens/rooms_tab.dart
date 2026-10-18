import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../room_look.dart';
import '../songs.dart';
import '../theme.dart';
import '../widgets/trend_frame.dart';
import 'room_screen.dart';

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
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => RoomScreen(
        roomId: r['id'] as String,
        title: r['title'] as String,
        topic: (r['topic'] ?? '') as String,
        isHost: r['host_id'] == myId,
      ),
    ),
  );
}

/// نافذة إنشاء غرفة جديدة ثم الدخول إليها (تُستعمل من زر المايك الأوسط أيضاً).
Future<void> createRoomFlow(BuildContext context) async {
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
    if (widget.active && !old.active) _load(silent: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
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

  List<Map<String, dynamic>> _fresh(List<Map<String, dynamic>> trend) {
    final ids = {for (final r in trend) r['id']};
    final l = _base.where((r) => !ids.contains(r['id'])).toList()
      ..sort((a, b) => (b['created_at'] as String).compareTo(a['created_at'] as String));
    return l;
  }

  Widget _sectionTitle(String t, {String? sub}) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 10),
        child: Row(children: [
          Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(color: _rViolet, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Text(t, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: _rInk)),
          const Spacer(),
          if (sub != null) Text(sub, style: const TextStyle(fontSize: 11, color: _rSub)),
        ]),
      );

  Widget _headerBtn(IconData i, String tip, VoidCallback f) => IconButton(
        tooltip: tip,
        onPressed: f,
        icon: Icon(i, color: Colors.white),
      );

  @override
  Widget build(BuildContext context) {
    final trend = _trend;
    final fresh = _fresh(trend);
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
                              : _body(trend, fresh),
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

  Widget _body(List<Map<String, dynamic>> trend, List<Map<String, dynamic>> fresh) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
      children: [
        if (trend.isNotEmpty) ...[
          _sectionTitle('🔥 ترند الأسبوع', sub: 'حسب الهدايا المُهداة'),
          _TrendTop(room: trend[0], onTap: () => _open(trend[0])),
          if (trend.length > 1) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _TrendMid(room: trend[1], rank: 2, onTap: () => _open(trend[1]))),
              const SizedBox(width: 10),
              if (trend.length > 2)
                Expanded(child: _TrendMid(room: trend[2], rank: 3, onTap: () => _open(trend[2])))
              else
                const Spacer(),
            ]),
          ],
          if (trend.length > 3) ...[
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.86,
              children: [
                for (var i = 3; i < trend.length; i++)
                  _TrendSmall(room: trend[i], rank: i + 1, onTap: () => _open(trend[i])),
              ],
            ),
          ],
        ],
        if (fresh.isEmpty && trend.isEmpty)
          Padding(
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
          ),
        for (final r in fresh) _FreshRow(room: r, onTap: () => _open(r)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () async {
            await createRoomFlow(context);
            if (mounted) _load(silent: true);
          },
          child: Container(
            height: 60,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFFA855F7)]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.add_circle_rounded, color: Colors.white),
              SizedBox(width: 10),
              Text('ابدأ غرفتك الآن',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white)),
            ]),
          ),
        ),
      ],
    );
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

Widget _supportChip(Map<String, dynamic> r) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Text('💎', style: TextStyle(fontSize: 10)),
        const SizedBox(width: 3),
        Text(_fmt((r['week_support'] as num?) ?? 0),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
      ]),
    );

class _TrendTop extends StatelessWidget {
  final Map<String, dynamic> room;
  final VoidCallback onTap;
  const _TrendTop({required this.room, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final listeners = (room['listeners'] as num?)?.toInt() ?? 0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 156,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(color: const Color(0xFFF59E0B).withValues(alpha: 0.35), blurRadius: 16)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(fit: StackFit.expand, children: [
            _roomBg(room, dim: 0.3),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                TrendFrame(
                  size: 70,
                  rank: 1,
                  child: ClipOval(
                    child: SizedBox(
                      width: 70,
                      height: 70,
                      child: Avatar(
                          name: (room['host_name'] ?? '?') as String,
                          url: room['host_avatar'] as String?,
                          size: 70),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFEF4444)]),
                              borderRadius: BorderRadius.circular(12)),
                          child: const Text('🥇 المركز الأول',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white)),
                        ),
                        const SizedBox(height: 6),
                        Row(children: [
                          _lockBadge(room),
                          Expanded(
                            child: Text(room['title'] as String,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
                          ),
                        ]),
                        Text('${room['host_name']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: Colors.white70)),
                        const SizedBox(height: 6),
                        Row(children: [
                          _supportChip(room),
                          const SizedBox(width: 8),
                          const Icon(Icons.headphones_rounded, size: 14, color: Colors.white70),
                          const SizedBox(width: 3),
                          Text('$listeners', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                        ]),
                      ]),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _TrendMid extends StatelessWidget {
  final Map<String, dynamic> room;
  final int rank;
  final VoidCallback onTap;
  const _TrendMid({required this.room, required this.rank, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 118,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(18)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(fit: StackFit.expand, children: [
            _roomBg(room, dim: 0.3),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(rank == 2 ? '🥈' : '🥉', style: const TextStyle(fontSize: 18)),
                  const Spacer(),
                  _supportChip(room),
                ]),
                const Spacer(),
                Row(children: [
                  TrendFrame(
                    size: 30,
                    rank: rank,
                    child: ClipOval(
                      child: SizedBox(
                        width: 30,
                        height: 30,
                        child: Avatar(
                            name: (room['host_name'] ?? '?') as String,
                            url: room['host_avatar'] as String?,
                            size: 30),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        _lockBadge(room),
                        Expanded(
                          child: Text(room['title'] as String,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w900, color: Colors.white)),
                        ),
                      ]),
                      Text('${room['host_name']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10, color: Colors.white70)),
                    ]),
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

class _TrendSmall extends StatelessWidget {
  final Map<String, dynamic> room;
  final int rank;
  final VoidCallback onTap;
  const _TrendSmall({required this.room, required this.rank, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(fit: StackFit.expand, children: [
          _roomBg(room, dim: 0.35),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(children: [
              Row(children: [
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                  child: Text('$rank',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white)),
                ),
                const Spacer(),
                _lockBadge(room),
              ]),
              const Spacer(),
              ClipOval(
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: Avatar(
                      name: (room['host_name'] ?? '?') as String,
                      url: room['host_avatar'] as String?,
                      size: 36),
                ),
              ),
              const SizedBox(height: 4),
              Text(room['title'] as String,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 2),
              _supportChip(room),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _FreshRow extends StatelessWidget {
  final Map<String, dynamic> room;
  final VoidCallback onTap;
  const _FreshRow({required this.room, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final listeners = (room['listeners'] as num?)?.toInt() ?? 0;
    final friends = (room['friends'] as num?)?.toInt() ?? 0;
    final topic = (room['topic'] ?? '') as String;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7FA),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFEDEEF3)),
        ),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 56,
              height: 56,
              child: Stack(fit: StackFit.expand, children: [
                _roomBg(room, dim: 0.1),
                Center(
                  child: ClipOval(
                    child: SizedBox(
                      width: 38,
                      height: 38,
                      child: Avatar(
                          name: (room['host_name'] ?? '?') as String,
                          url: room['host_avatar'] as String?,
                          size: 38),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (room['locked'] == true)
                  const Padding(
                      padding: EdgeInsetsDirectional.only(end: 4),
                      child: Icon(Icons.lock_rounded, size: 14, color: Color(0xFFF59E0B))),
                Expanded(
                  child: Text(room['title'] as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _rInk)),
                ),
              ]),
              const SizedBox(height: 2),
              Text(topic.isEmpty ? '${room['host_name']}' : '$topic · ${room['host_name']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: _rSub)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.headphones_rounded, size: 14, color: _rViolet),
              const SizedBox(width: 3),
              Text('$listeners',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _rViolet)),
            ]),
            if (friends > 0)
              Text('$friends من أصدقائك',
                  style: const TextStyle(fontSize: 10, color: _rSub)),
          ]),
        ]),
      ),
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
