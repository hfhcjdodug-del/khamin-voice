import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../theme.dart';
import 'profile_screen.dart';

class SearchTab extends StatefulWidget {
  const SearchTab({super.key});

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  final _q = TextEditingController();
  List<Map<String, dynamic>> _res = [];
  bool _loading = true;
  Timer? _deb;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _deb?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _deb?.cancel();
    _deb = Timer(const Duration(milliseconds: 350), () => _search(v));
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    try {
      final r = await supa.rpc('search_profiles', params: {'q': q});
      if (!mounted) return;
      setState(() {
        _res = List<Map<String, dynamic>>.from(r as List);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      toast(context, friendlyError(e));
    }
  }

  Future<void> _toggleFollow(Map<String, dynamic> u) async {
    final following = u['is_following'] == true;
    setState(() => u['is_following'] = !following);
    try {
      await supa.rpc(following ? 'unfollow_user' : 'follow_user', params: {'p_id': u['id']});
    } catch (e) {
      if (mounted) {
        setState(() => u['is_following'] = following);
        toast(context, friendlyError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _q,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'ابحث بالاسم أو اليوزر أو الـ ID',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: C.pink))
                : _res.isEmpty
                    ? const Center(
                        child: Text('لا توجد نتائج', style: TextStyle(color: Colors.white60)))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: _res.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final u = _res[i];
                          final f = u['is_following'] == true;
                          return GlassCard(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => ProfileScreen(userId: u['id'] as String)),
                            ),
                            child: Row(children: [
                              Avatar(
                                  name: u['name'] as String,
                                  url: u['avatar_url'] as String?,
                                  size: 46),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(u['name'] as String,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w800, fontSize: 16)),
                                      Text('@${u['username']} · ID ${u['num']}',
                                          style: const TextStyle(
                                              color: Colors.white60, fontSize: 12)),
                                    ]),
                              ),
                              GradButton(
                                label: f ? 'تتابعه' : 'متابعة',
                                dense: true,
                                outlined: f,
                                onPressed: () => _toggleFollow(u),
                              ),
                            ]),
                          );
                        },
                      ),
          ),
        ]),
      ),
    );
  }
}
