import 'package:flutter/material.dart';

import '../level.dart';
import '../main.dart';
import '../theme.dart';
import 'profile_screen.dart';

/// قائمة المتابعين أو من يتابعهم لأي مستخدم.
class FollowsScreen extends StatefulWidget {
  final String userId;
  final bool followers; // true = المتابعون، false = يتابعهم
  const FollowsScreen({super.key, required this.userId, required this.followers});

  @override
  State<FollowsScreen> createState() => _FollowsScreenState();
}

class _FollowsScreenState extends State<FollowsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await supa.rpc('user_follows', params: {
        'p_id': widget.userId,
        'p_kind': widget.followers ? 'followers' : 'following',
      });
      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(r as List);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyError(e);
      });
    }
  }

  Future<void> _toggle(Map<String, dynamic> u) async {
    final f = u['is_following'] == true;
    try {
      await supa.rpc(f ? 'unfollow_user' : 'follow_user', params: {'p_id': u['id']});
      if (mounted) setState(() => u['is_following'] = !f);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.followers ? 'المتابعون' : 'يتابعهم',
            style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: C.pink))
          : _error != null
              ? Center(child: Text(_error!))
              : _items.isEmpty
                  ? Center(
                      child: Text(widget.followers ? 'لا يوجد متابعون بعد' : 'لا يتابع أحداً بعد',
                          style: const TextStyle(color: Colors.white60)))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                        itemCount: _items.length,
                        itemBuilder: (_, i) {
                          final u = _items[i];
                          final id = u['id'] as String;
                          final lv = levelOf((u['xp'] as num?)?.toInt() ?? 0);
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => ProfileScreen(userId: id))),
                            leading: Avatar(
                                name: u['name'] as String,
                                url: u['avatar_url'] as String?,
                                size: 42),
                            title: Row(children: [
                              Flexible(
                                child: Text(u['name'] as String,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w800)),
                              ),
                              if (u['verified'] == true) ...[
                                const SizedBox(width: 4),
                                const Icon(Icons.verified_rounded,
                                    color: Color(0xFF4DA3FF), size: 16),
                              ],
                              const SizedBox(width: 6),
                              LevelBadge(level: lv, size: 22),
                            ]),
                            subtitle: Text('@${u['username']}',
                                textDirection: TextDirection.ltr,
                                textAlign: TextAlign.start,
                                style: const TextStyle(color: Colors.white54, fontSize: 12)),
                            trailing: id == myId
                                ? null
                                : OutlinedButton(
                                    onPressed: () => _toggle(u),
                                    child: Text(u['is_following'] == true ? 'تتابعه' : 'متابعة'),
                                  ),
                          );
                        },
                      ),
                    ),
    );
  }
}
