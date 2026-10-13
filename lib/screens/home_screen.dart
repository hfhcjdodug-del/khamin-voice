import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../widgets/ninja.dart';
import 'room_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _rooms = [];
  Map<String, dynamic>? _me;
  bool _loading = true;
  String? _error;
  String _query = '';
  bool _searching = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _loadMe();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadMe() async {
    try {
      final uid = supa.auth.currentUser!.id;
      final r = await supa.from('profiles').select().eq('id', uid).maybeSingle();
      if (mounted) setState(() => _me = r);
    } catch (_) {}
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
        if (!silent) _error = '$e';
      });
    }
  }

  Future<void> _createRoom() async {
    final title = TextEditingController();
    final topic = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('غرفة جديدة'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: title,
            maxLength: 60,
            decoration: const InputDecoration(labelText: 'اسم الغرفة'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: topic,
            maxLength: 120,
            decoration: const InputDecoration(labelText: 'موضوع النقاش (اختياري)'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('إنشاء')),
        ],
      ),
    );
    if (ok != true) return;
    final t = title.text.trim();
    if (t.length < 2) {
      _snack('اسم الغرفة قصير جداً');
      return;
    }
    try {
      final row = await supa
          .from('rooms')
          .insert({'title': t, 'topic': topic.text.trim(), 'host_id': supa.auth.currentUser!.id})
          .select()
          .single();
      if (!mounted) return;
      await _open(row['id'] as String, t, topic.text.trim(), true);
    } catch (e) {
      _snack('تعذّر إنشاء الغرفة: $e');
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

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _profileSheet() async {
    final name = TextEditingController(text: (_me?['name'] ?? '') as String);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(c).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Avatar(name: name.text, url: _me?['avatar_url'] as String?, size: 72),
          const SizedBox(height: 16),
          TextField(
            controller: name,
            maxLength: 40,
            decoration: const InputDecoration(labelText: 'اسمك'),
          ),
          const SizedBox(height: 8),
          NinjaButton(
            label: 'حفظ الاسم',
            onPressed: () async {
              final n = name.text.trim();
              if (n.length < 2) return;
              await supa.from('profiles').update({'name': n}).eq('id', supa.auth.currentUser!.id);
              await _loadMe();
              if (c.mounted) Navigator.pop(c);
            },
          ),
          const SizedBox(height: 10),
          NinjaButton(
            label: 'تسجيل الخروج',
            icon: Icons.logout_rounded,
            outlined: true,
            onPressed: () async {
              Navigator.pop(c);
              await supa.auth.signOut();
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = _rooms.where((r) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return '${r['title']} ${r['topic']} ${r['host_name']}'.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(hintText: 'ابحث عن غرفة...'),
              )
            : Text('KHAMIN', style: logoStyle(20)),
        leading: IconButton(
          icon: Icon(_searching ? Icons.close : Icons.search),
          onPressed: () => setState(() {
            _searching = !_searching;
            _query = '';
          }),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: InkWell(
              onTap: _profileSheet,
              borderRadius: BorderRadius.circular(30),
              child: Avatar(
                name: (_me?['name'] ?? '?') as String,
                url: _me?['avatar_url'] as String?,
                size: 32,
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createRoom,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.mic_rounded),
        label: const Text('غرفة جديدة', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(children: [
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text('تعذّر تحميل الغرف\n$_error', textAlign: TextAlign.center),
                    ),
                  ])
                : shown.isEmpty
                    ? ListView(children: const [
                        SizedBox(height: 160),
                        Icon(Icons.mic_none_rounded, size: 64, color: Colors.white38),
                        SizedBox(height: 12),
                        Center(
                          child: Text('لا توجد غرف مباشرة الآن\nأنشئ أول غرفة!',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white60, fontSize: 17)),
                        ),
                      ])
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        itemCount: shown.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _RoomCard(
                          room: shown[i],
                          onTap: () => _open(
                            shown[i]['id'] as String,
                            shown[i]['title'] as String,
                            (shown[i]['topic'] ?? '') as String,
                            shown[i]['host_id'] == supa.auth.currentUser!.id,
                          ),
                        ),
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
    return Material(
      color: const Color(0xFF151515),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Avatar(
              name: (room['host_name'] ?? '?') as String,
              url: room['host_avatar'] as String?,
              size: 52,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(room['title'] as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                if (topic.isNotEmpty)
                  Text(topic,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white60)),
                const SizedBox(height: 4),
                Text('المضيف: ${room['host_name']}',
                    style: const TextStyle(color: Colors.white38, fontSize: 13)),
              ]),
            ),
            Column(children: [
              const Icon(Icons.headphones_rounded, size: 20, color: Color(0xFF4ADE80)),
              Text('${room['listeners']}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
          ]),
        ),
      ),
    );
  }
}
