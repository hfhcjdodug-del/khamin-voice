import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../room_look.dart';
import '../songs.dart';
import '../theme.dart';
import 'room_screen.dart';

Future<void> openRoom(BuildContext context, Map<String, dynamic> r) async {
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
  const RoomsTab({super.key, this.active = true});

  @override
  State<RoomsTab> createState() => _RoomsTabState();
}

class _RoomsTabState extends State<RoomsTab> {
  List<Map<String, dynamic>> _rooms = [];
  bool _loading = true;
  String? _error;
  Timer? _timer;
  String _filter = 'all'; // all | top | new | friends

  @override
  void initState() {
    super.initState();
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
      final r = await supa.rpc('list_rooms');
      if (!mounted) return;
      setState(() {
        _rooms = List<Map<String, dynamic>>.from(r as List);
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

  /// مركز الغرفة بين الغرف الترند (حسب الدعم): 1 و2 و3.
  Map<String, int> get _ranks {
    final m = <String, int>{};
    var n = 0;
    for (final r in _rooms) {
      if (r['trending'] == true && n < 3) m[r['id'] as String] = ++n;
    }
    return m;
  }

  List<Map<String, dynamic>> get _shown {
    final l = List<Map<String, dynamic>>.of(_rooms);
    int n(Map<String, dynamic> r, String k) => (r[k] as num?)?.toInt() ?? 0;
    switch (_filter) {
      case 'top':
        l.sort((a, b) => n(b, 'listeners').compareTo(n(a, 'listeners')));
      case 'new':
        l.sort((a, b) => (b['created_at'] as String).compareTo(a['created_at'] as String));
      case 'friends':
        l.removeWhere((r) => n(r, 'friends') == 0);
    }
    // الترند دائماً أولاً (الفرز المستقر)
    return [...l.where((r) => r['trending'] == true), ...l.where((r) => r['trending'] != true)];
  }

  Widget _chipBtn(String id, String label) {
    final on = _filter == id;
    return GestureDetector(
      onTap: () => setState(() => _filter = id),
      child: Container(
        margin: const EdgeInsetsDirectional.only(end: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          gradient: on ? brandGradient : null,
          color: on ? null : C.glass,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: on ? Colors.transparent : C.glassBorder),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: on ? Colors.white : Colors.white70)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Row(children: [
                  const Icon(Icons.grid_view_rounded, color: C.violet),
                  const SizedBox(width: 10),
                  const Text('الغرف الحية',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  const Spacer(),
                  IconButton(
                    tooltip: 'الأغاني',
                    onPressed: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => const SongsScreen())),
                    icon: const Icon(Icons.library_music_rounded),
                  ),
                  IconButton(
                    tooltip: 'الرومات السابقة',
                    onPressed: () async {
                      await Navigator.push(
                          context, MaterialPageRoute(builder: (_) => const RecentRoomsScreen()));
                      if (mounted) _load(silent: true);
                    },
                    icon: const Icon(Icons.history_rounded),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: C.glass, borderRadius: BorderRadius.circular(20)),
                    child: Row(children: [
                      const Icon(Icons.circle, size: 10, color: C.green),
                      const SizedBox(width: 6),
                      Text('${_rooms.length} مباشرة'),
                    ]),
                  ),
                ]),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    _chipBtn('all', 'الكل'),
                    _chipBtn('top', 'الأكثر استماعاً'),
                    _chipBtn('new', 'الأحدث'),
                    _chipBtn('friends', 'أصدقائي'),
                  ],
                ),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: C.pink)))
            else if (_error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('تعذّر تحميل الغرف\n$_error', textAlign: TextAlign.center)),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                sliver: SliverList.list(children: [
                  if (shown.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Column(children: [
                        const Icon(Icons.mic_none_rounded, size: 72, color: Colors.white38),
                        const SizedBox(height: 12),
                        Text(
                            _filter == 'friends'
                                ? 'لا يوجد أصدقاء لك داخل الغرف الآن'
                                : 'لا توجد غرف مباشرة الآن\nكن أول من يبدأ غرفة!',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white60, fontSize: 17)),
                      ]),
                    ),
                  for (final r in shown)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: RoomCard(room: r, rank: _ranks[r['id']], onTap: () => _open(r)),
                    ),
                  GestureDetector(
                    onTap: () async {
                      await createRoomFlow(context);
                      if (mounted) _load(silent: true);
                    },
                    child: Container(
                      height: 72,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: Colors.white30, width: 1.5),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
                        Icon(Icons.add_circle_rounded, color: C.pink),
                        SizedBox(width: 10),
                        Text('ابدأ غرفتك الآن',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      ]),
                    ),
                  ),
                ]),
              ),
          ]),
        ),
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
