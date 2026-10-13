import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import '../theme.dart';
import 'room_screen.dart';

class RoomsTab extends StatefulWidget {
  const RoomsTab({super.key});

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
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _load(silent: true));
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

  Future<void> _create() async {
    final title = TextEditingController();
    final topic = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(c).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('غرفة جديدة',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
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
    if (ok != true) return;
    final t = title.text.trim();
    if (t.length < 2) {
      if (mounted) toast(context, 'اسم الغرفة قصير جداً');
      return;
    }
    try {
      final row = await supa
          .from('rooms')
          .insert({'title': t, 'topic': topic.text.trim(), 'host_id': myId})
          .select()
          .single();
      if (!mounted) return;
      await _open(row['id'] as String, t, topic.text.trim(), true);
    } catch (e) {
      if (mounted) toast(context, 'تعذّر إنشاء الغرفة: ${friendlyError(e)}');
    }
  }

  Future<void> _open(String id, String title, String topic, bool isHost) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoomScreen(roomId: id, title: title, topic: topic, isHost: isHost),
      ),
    );
    if (mounted) _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: brandGradient,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [BoxShadow(color: C.pink.withValues(alpha: 0.4), blurRadius: 20)],
        ),
        child: FloatingActionButton.extended(
          onPressed: _create,
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add_rounded),
          label: const Text('غرفة جديدة', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Row(children: [
                  Text('KHAMIN',
                      style: GoogleFonts.orbitron(
                          fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 4)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: C.glass,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(children: [
                      const Icon(Icons.circle, size: 10, color: C.green),
                      const SizedBox(width: 6),
                      Text('${_rooms.length} غرفة مباشرة'),
                    ]),
                  ),
                ]),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator(color: C.pink)))
            else if (_error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('تعذّر تحميل الغرف\n$_error', textAlign: TextAlign.center)),
              )
            else if (_rooms.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.mic_none_rounded, size: 72, color: Colors.white38),
                    SizedBox(height: 12),
                    Text('لا توجد غرف مباشرة الآن\nكن أول من يبدأ غرفة!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white60, fontSize: 17)),
                  ]),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                sliver: SliverList.separated(
                  itemCount: _rooms.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final r = _rooms[i];
                    return _RoomCard(
                      room: r,
                      onTap: () => _open(
                        r['id'] as String,
                        r['title'] as String,
                        (r['topic'] ?? '') as String,
                        r['host_id'] == myId,
                      ),
                    );
                  },
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  final Map<String, dynamic> room;
  final VoidCallback onTap;
  const _RoomCard({required this.room, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final topic = (room['topic'] ?? '') as String;
    return GlassCard(
      onTap: onTap,
      child: Row(children: [
        Avatar(
          name: (room['host_name'] ?? '?') as String,
          url: room['host_avatar'] as String?,
          size: 56,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(room['title'] as String,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            if (topic.isNotEmpty)
              Text(topic,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 4),
            Text('المضيف: ${room['host_name']}',
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
        ),
        const SizedBox(width: 8),
        Column(children: [
          _pill(Icons.headphones_rounded, '${room['listeners']}', C.cyan),
          const SizedBox(height: 6),
          _pill(Icons.mic_rounded, '${room['seated']}/9', C.pink),
        ]),
      ]),
    );
  }

  Widget _pill(IconData i, String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, size: 14, color: c),
          const SizedBox(width: 4),
          Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      );
}
