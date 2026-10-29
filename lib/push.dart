import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'main.dart';
import 'theme.dart';

final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();

/// تفعيل إشعارات النظام (خارج التطبيق). لو ملف google-services.json غير موجود يتجاهل بصمت.
Future<void> initPush() async {
  try {
    await Firebase.initializeApp();
    final m = FirebaseMessaging.instance;
    await m.requestPermission();
    await m.subscribeToTopic('all');
  } catch (_) {}
}

Future<void> openLink(String? url) async {
  if (url == null || url.isEmpty) return;
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
}

/// يستمع للإشعارات الجديدة ويعرضها كشريط أعلى الشاشة لمن هو داخل التطبيق.
class NoticeListener {
  static StreamSubscription<List<Map<String, dynamic>>>? _sub;
  static int _lastId = -1;

  static void start() {
    stop();
    _sub = supa
        .from('app_notifications')
        .stream(primaryKey: ['id'])
        .order('id', ascending: false)
        .limit(1)
        .listen((rows) {
      if (rows.isEmpty) return;
      final r = rows.first;
      final id = (r['id'] as num).toInt();
      if (_lastId == -1) {
        _lastId = id; // أول تحميل: لا نعرض القديم
        return;
      }
      if (id <= _lastId) return;
      _lastId = id;
      _show(r);
    });
  }

  static void stop() {
    _sub?.cancel();
    _sub = null;
    _lastId = -1;
  }

  static void _show(Map<String, dynamic> r) {
    final m = messengerKey.currentState;
    if (m == null) return;
    final url = r['url'] as String?;
    final kind = (r['kind'] ?? 'info') as String;
    final st = noticeStyle(kind);
    final body = ((r['body'] ?? '') as String);
    m
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        duration: const Duration(seconds: 12),
        content: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(colors: st.colors, begin: Alignment.topRight, end: Alignment.bottomLeft),
            boxShadow: [BoxShadow(color: st.colors.first.withValues(alpha: 0.5), blurRadius: 18, offset: const Offset(0, 6))],
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
              child: Icon(st.icon, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(st.label, style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w700)),
                Text(r['title'] as String,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Colors.white)),
                if (body.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(body, style: const TextStyle(fontSize: 13, color: Colors.white)),
                  ),
                if (url != null && url.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: GestureDetector(
                      onTap: () {
                        m.hideCurrentSnackBar();
                        openLink(url);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                        child: Text(kind == 'update' ? 'تحديث الآن' : 'فتح',
                            style: TextStyle(color: st.colors.last, fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ),
              ]),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => m.hideCurrentSnackBar(),
              icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
            ),
          ]),
        ),
      ));
  }
}

/// ألوان وأيقونة كل نوع إشعار.
({IconData icon, List<Color> colors, String label}) noticeStyle(String kind) {
  switch (kind) {
    case 'update':
      return (icon: Icons.system_update_rounded, colors: const [Color(0xFF10B981), Color(0xFF0EA5E9)], label: 'تحديث');
    case 'alert':
      return (icon: Icons.warning_amber_rounded, colors: const [Color(0xFFF59E0B), Color(0xFFEF4444)], label: 'تنبيه');
    default:
      return (icon: Icons.campaign_rounded, colors: const [Color(0xFF8B5CF6), Color(0xFFEC4899)], label: 'إعلان');
  }
}

/// صندوق «إشعارات التطبيق».
class NoticesScreen extends StatefulWidget {
  const NoticesScreen({super.key});

  @override
  State<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends State<NoticesScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await supa.from('app_notifications').select().order('id', ascending: false).limit(50);
      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(r);
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
    return Scaffold(
      appBar: AppBar(title: const Text('إشعارات التطبيق', style: TextStyle(fontWeight: FontWeight.w800))),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: C.pink))
          : _items.isEmpty
              ? const Center(child: Text('لا توجد إشعارات', style: TextStyle(color: Colors.white60)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final r = _items[i];
                      final kind = (r['kind'] ?? 'info') as String;
                      final url = r['url'] as String?;
                      final st = noticeStyle(kind);
                      return GestureDetector(
                        onTap: url != null && url.isNotEmpty ? () => openLink(url) : null,
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            color: const Color(0xFF241552),
                            border: Border.all(color: st.colors.first.withValues(alpha: 0.6)),
                          ),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(colors: st.colors),
                              ),
                              child: Icon(st.icon, color: Colors.white),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(st.label, style: TextStyle(fontSize: 11, color: st.colors.first, fontWeight: FontWeight.w800)),
                                Text(r['title'] as String, style: const TextStyle(fontWeight: FontWeight.w900)),
                                if (((r['body'] ?? '') as String).isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(r['body'] as String, style: const TextStyle(color: Colors.white70)),
                                  ),
                                if (url != null && url.isNotEmpty)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 4),
                                    child: Text('اضغط للفتح', style: TextStyle(color: C.cyan, fontSize: 12)),
                                  ),
                              ]),
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
