import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                child: Row(children: [
                  const Icon(Icons.grid_view_rounded, color: C.violet),
                  const SizedBox(width: 10),
                  const Text('الغرف الحية',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  const Spacer(),
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
            if (_loading)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: C.pink)))
            else if (_error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('تعذّر تحميل الغرف\n$_error', textAlign: TextAlign.center)),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                sliver: SliverList.list(children: [
                  if (_rooms.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 50),
                      child: Column(children: [
                        Icon(Icons.mic_none_rounded, size: 72, color: Colors.white38),
                        SizedBox(height: 12),
                        Text('لا توجد غرف مباشرة الآن\nكن أول من يبدأ غرفة!',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white60, fontSize: 17)),
                      ]),
                    ),
                  for (final r in _rooms)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: RoomCard(room: r, onTap: () => _open(r)),
                    ),
                  const SizedBox(height: 4),
                  GradButton(
                    label: 'إنشاء غرفة',
                    icon: Icons.add_rounded,
                    onPressed: () async {
                      await createRoomFlow(context);
                      if (mounted) _load(silent: true);
                    },
                  ),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

const _roomPalettes = [
  [Color(0xFF1E1B4B), Color(0xFF6D28D9)],
  [Color(0xFF0F172A), Color(0xFF0E7490)],
  [Color(0xFF3B0764), Color(0xFFBE185D)],
  [Color(0xFF172554), Color(0xFF4338CA)],
  [Color(0xFF1F2937), Color(0xFF7C3AED)],
];

class RoomCard extends StatelessWidget {
  final Map<String, dynamic> room;
  final VoidCallback onTap;
  const RoomCard({super.key, required this.room, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final title = room['title'] as String;
    final topic = (room['topic'] ?? '') as String;
    final pal = _roomPalettes[title.runes.fold<int>(0, (a, b) => a + b) % _roomPalettes.length];
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 128,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(colors: pal, begin: Alignment.topRight, end: Alignment.bottomLeft),
          border: Border.all(color: C.violet.withValues(alpha: 0.45)),
          boxShadow: [BoxShadow(color: C.violet.withValues(alpha: 0.18), blurRadius: 18)],
        ),
        child: Stack(children: [
          Positioned(
            top: -20,
            left: -20,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.07),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
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
              const SizedBox(height: 2),
              Text(topic.isEmpty ? 'المضيف: ${room['host_name']}' : '$topic · ${room['host_name']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
              const Spacer(),
              Row(children: [
                Avatar(
                    name: (room['host_name'] ?? '?') as String,
                    url: room['host_avatar'] as String?,
                    size: 28),
                const SizedBox(width: 8),
                const Icon(Icons.people_alt_rounded, size: 16, color: Colors.white70),
                const SizedBox(width: 4),
                Text('${room['listeners']}',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(width: 10),
                const Icon(Icons.mic_rounded, size: 15, color: C.pink),
                Text(' ${room['seated']}/9',
                    style: const TextStyle(fontSize: 12, color: Colors.white70)),
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
    );
  }
}
