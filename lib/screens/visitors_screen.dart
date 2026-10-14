import 'package:flutter/material.dart';

import '../level.dart';
import '../main.dart';
import '../theme.dart';
import 'profile_screen.dart';

class VisitorsScreen extends StatelessWidget {
  const VisitorsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الزوار', style: TextStyle(fontWeight: FontWeight.w800)),
          bottom: const TabBar(
            indicatorColor: C.pink,
            tabs: [Tab(text: 'كل الزوار'), Tab(text: 'المشاهدين'), Tab(text: 'المعجبين')],
          ),
        ),
        body: const TabBarView(children: [
          _VisList(kind: 'all'),
          _VisList(kind: 'viewers'),
          _VisList(kind: 'fans'),
        ]),
      ),
    );
  }
}

class _VisList extends StatefulWidget {
  final String kind;
  const _VisList({required this.kind});

  @override
  State<_VisList> createState() => _VisListState();
}

class _VisListState extends State<_VisList> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await supa.rpc('my_visitors', params: {'p_kind': widget.kind});
      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(r as List);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      toast(context, friendlyError(e));
    }
  }

  Future<void> _follow(Map<String, dynamic> u) async {
    final f = u['is_following'] == true;
    setState(() => u['is_following'] = !f);
    try {
      await supa.rpc(f ? 'unfollow_user' : 'follow_user', params: {'p_id': u['id']});
    } catch (e) {
      if (mounted) {
        setState(() => u['is_following'] = f);
        toast(context, friendlyError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: C.pink));
    if (_items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('لا يوجد أحد هنا بعد',
              style: TextStyle(color: Colors.white60, fontSize: 16)),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final u = _items[i];
          final following = u['is_following'] == true;
          return GlassCard(
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: u['id'] as String))),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Avatar(name: u['name'] as String, url: u['avatar_url'] as String?, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text(u['name'] as String,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                    if (u['verified'] == true)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(Icons.verified_rounded, size: 16, color: Color(0xFF4DA3FF)),
                      ),
                  ]),
                  Text('${timeAgo(DateTime.parse(u['last_at'] as String))} · @${u['username']}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ]),
              ),
              GradButton(
                label: following ? 'تتابعه' : 'متابعة',
                dense: true,
                outlined: following,
                onPressed: () => _follow(u),
              ),
            ]),
          );
        },
      ),
    );
  }
}
