import 'dart:async';

import 'package:flutter/material.dart';

import '../level.dart';
import '../main.dart';
import '../theme.dart';
import 'games_tab.dart';
import 'movies_tab.dart';
import 'rooms_tab.dart';
import 'search_tab.dart';

class HomeTab extends StatefulWidget {
  final bool active;
  final VoidCallback onSeeRooms;
  const HomeTab({super.key, required this.active, required this.onSeeRooms});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  List<Map<String, dynamic>> _rooms = [];
  Map<String, dynamic>? _me;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (widget.active) _load();
    });
  }

  @override
  void didUpdateWidget(covariant HomeTab old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await supa.rpc('list_rooms') as List;
      final m = await supa.rpc('get_profile', params: {'p_id': myId}) as List;
      if (!mounted) return;
      setState(() {
        _rooms = List<Map<String, dynamic>>.from(r);
        _me = m.isEmpty ? null : Map<String, dynamic>.from(m.first as Map);
      });
    } catch (_) {}
  }

  Widget _quick(IconData i, String t, List<Color> colors, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 96,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
                colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(i, size: 34),
            const SizedBox(height: 6),
            Text(t, style: const TextStyle(fontWeight: FontWeight.w900)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    final xp = (me?['xp'] as num?)?.toInt() ?? 0;
    final lv = levelOf(xp);
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 120), children: [
            Row(children: [
              const Text('نتونس', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const Spacer(),
              if (me != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: C.glass, borderRadius: BorderRadius.circular(20)),
                  child: Row(children: [
                    const Icon(Icons.workspace_premium_rounded, size: 16, color: C.orange),
                    const SizedBox(width: 4),
                    Text('مستوى $lv', style: const TextStyle(fontWeight: FontWeight.w800)),
                  ]),
                ),
            ]),
            const SizedBox(height: 18),
            Row(children: [
              _quick(Icons.sports_esports_rounded, 'ألعاب', const [Color(0xFF7C3AED), C.pink], () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const GamesTab(active: true)));
              }),
              const SizedBox(width: 12),
              _quick(Icons.movie_rounded, 'أفلام', const [Color(0xFF0EA5E9), Color(0xFF6366F1)], () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const MoviesTab(active: true)));
              }),
              const SizedBox(width: 12),
              _quick(Icons.search_rounded, 'بحث', const [Color(0xFFF97316), Color(0xFFEF4444)], () {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => Scaffold(
                            appBar: AppBar(title: const Text('بحث')), body: const SearchTab())));
              }),
            ]),
            const SizedBox(height: 22),
            Row(children: [
              const Text('غرف مباشرة الآن',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const Spacer(),
              TextButton(onPressed: widget.onSeeRooms, child: const Text('عرض الكل')),
            ]),
            const SizedBox(height: 6),
            if (_rooms.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(
                  child: Text('لا توجد غرف الآن — اضغط زر المايك لتبدأ غرفتك',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
                ),
              ),
            for (final r in _rooms.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: RoomCard(
                  room: r,
                  onTap: () async {
                    await openRoom(context, r);
                    _load();
                  },
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
