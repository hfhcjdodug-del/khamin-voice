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
    final icon = kind == 'update'
        ? Icons.system_update_rounded
        : (kind == 'alert' ? Icons.warning_amber_rounded : Icons.campaign_rounded);
    m
      ..hideCurrentMaterialBanner()
      ..showMaterialBanner(MaterialBanner(
        backgroundColor: const Color(0xFF2A1B52),
        leading: Icon(icon, color: C.pink),
        content: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(r['title'] as String, style: const TextStyle(fontWeight: FontWeight.w900)),
          if (((r['body'] ?? '') as String).isNotEmpty)
            Text(r['body'] as String, style: const TextStyle(fontSize: 13, color: Colors.white70)),
        ]),
        actions: [
          if (url != null && url.isNotEmpty)
            TextButton(
                onPressed: () {
                  m.hideCurrentMaterialBanner();
                  openLink(url);
                },
                child: Text(kind == 'update' ? 'تحديث' : 'فتح')),
          TextButton(onPressed: () => m.hideCurrentMaterialBanner(), child: const Text('إغلاق')),
        ],
      ));
    Future.delayed(const Duration(seconds: 12), () => m.hideCurrentMaterialBanner());
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
                      return GlassCard(
                        onTap: url != null && url.isNotEmpty ? () => openLink(url) : null,
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(
                              kind == 'update'
                                  ? Icons.system_update_rounded
                                  : (kind == 'alert' ? Icons.warning_amber_rounded : Icons.campaign_rounded),
                              color: kind == 'alert' ? C.orange : C.violet),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(r['title'] as String, style: const TextStyle(fontWeight: FontWeight.w800)),
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
                      );
                    },
                  ),
                ),
    );
  }
}
