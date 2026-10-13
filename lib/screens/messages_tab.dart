import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../theme.dart';
import 'chat_screen.dart';

class MessagesTab extends StatefulWidget {
  final bool active;
  const MessagesTab({super.key, required this.active});

  @override
  State<MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<MessagesTab> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (widget.active) _load();
    });
  }

  @override
  void didUpdateWidget(covariant MessagesTab old) {
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
      final r = await supa.rpc('my_conversations');
      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(r as List);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الرسائل', style: TextStyle(fontWeight: FontWeight.w800))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: C.pink))
            : _items.isEmpty
                ? ListView(children: const [
                    SizedBox(height: 160),
                    Icon(Icons.chat_bubble_outline_rounded, size: 64, color: Colors.white38),
                    SizedBox(height: 12),
                    Center(
                      child: Text('لا توجد محادثات بعد\nابحث عن شخص وأرسل له رسالة',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white60, fontSize: 16)),
                    ),
                  ])
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final c = _items[i];
                      final unread = (c['unread'] ?? 0) as int;
                      return GlassCard(
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                peerId: c['peer_id'] as String,
                                peerName: c['peer_name'] as String,
                                peerAvatar: c['peer_avatar'] as String?,
                              ),
                            ),
                          );
                          _load();
                        },
                        child: Row(children: [
                          Avatar(
                              name: c['peer_name'] as String,
                              url: c['peer_avatar'] as String?,
                              size: 46),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(c['peer_name'] as String,
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                              Text(c['last_body'] as String,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: unread > 0 ? Colors.white : Colors.white60)),
                            ]),
                          ),
                          if (unread > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                gradient: brandGradient,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text('$unread',
                                  style: const TextStyle(fontWeight: FontWeight.w800)),
                            ),
                        ]),
                      );
                    },
                  ),
      ),
    );
  }
}
