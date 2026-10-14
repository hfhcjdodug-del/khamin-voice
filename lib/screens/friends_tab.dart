import 'package:flutter/material.dart';

import '../main.dart';
import '../theme.dart';
import 'messages_tab.dart';
import 'profile_screen.dart';
import 'search_tab.dart';

class FriendsTab extends StatelessWidget {
  final bool active;
  const FriendsTab({super.key, required this.active});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الأصدقاء', style: TextStyle(fontWeight: FontWeight.w900)),
          bottom: const TabBar(
            indicatorColor: C.pink,
            tabs: [Tab(text: 'الرسائل'), Tab(text: 'أصدقائي'), Tab(text: 'بحث')],
          ),
        ),
        body: TabBarView(children: [
          MessagesTab(active: active, embedded: true),
          _FollowingList(active: active),
          const SearchTab(),
        ]),
      ),
    );
  }
}

class _FollowingList extends StatefulWidget {
  final bool active;
  const _FollowingList({required this.active});

  @override
  State<_FollowingList> createState() => _FollowingListState();
}

class _FollowingListState extends State<_FollowingList> {
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _FollowingList old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _load();
  }

  Future<void> _load() async {
    try {
      final r = await supa.rpc('my_following');
      if (!mounted) return;
      setState(() {
        _list = List<Map<String, dynamic>>.from(r as List);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      toast(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: C.pink));
    if (_list.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('لا تتابع أحداً بعد.\nابحث عن أصدقائك من تبويب «بحث».',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60, height: 1.7)),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _list.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final u = _list[i];
          return GlassCard(
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: u['id'] as String))),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Avatar(name: u['name'] as String, url: u['avatar_url'] as String?, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(u['name'] as String, style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text('@${u['username']}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ]),
              ),
              const Icon(Icons.chevron_left_rounded, color: Colors.white38),
            ]),
          );
        },
      ),
    );
  }
}
