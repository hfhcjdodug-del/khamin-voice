import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../ads.dart';
import '../main.dart';
import '../audio.dart';
import '../theme.dart';
import '../gifts.dart';

class GuessMatchScreen extends StatefulWidget {
  final String matchId;
  const GuessMatchScreen({super.key, required this.matchId});

  @override
  State<GuessMatchScreen> createState() => _GuessMatchScreenState();
}

class _GuessMatchScreenState extends State<GuessMatchScreen> {
  final Room _room = Room();
  EventsListener<RoomEvent>? _events;
  Timer? _poll;
  final _input = TextEditingController();
  Map<String, dynamic>? _v;
  List<Map<String, dynamic>> _msgs = [];
  bool _micOn = false;
  bool _speakerOn = true;
  bool _connected = false;
  bool _ended = false;
  bool _following = false;
  final _giftKey = GlobalKey<GiftOverlayState>();
  int _lastGift = -1; // -1 = لم نحدد خط الأساس بعد
  String _voiceNote = 'جاري ربط الصوت...';

  @override
  void initState() {
    super.initState();
    Music.stop();
    Future(() async {
      try {
        await supa.rpc('add_xp', params: {'p_kind': 'game'});
      } catch (_) {}
    });
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
    _startVoice();
  }

  Future<void> _refresh() async {
    if (_ended) return;
    try {
      final r = await supa.rpc('match_view', params: {'p_id': widget.matchId}) as List;
      final m = await supa
          .from('game_messages')
          .select()
          .eq('match_id', widget.matchId)
          .order('id', ascending: false)
          .limit(60);
      if (!mounted) return;
      if (r.isEmpty || r.first['status'] == 'finished') {
        _ended = true;
        _poll?.cancel();
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (c) => AlertDialog(
            title: const Text('انتهت المنافسة'),
            content: const Text('غادر أحد اللاعبين أو انتهت الجولة.'),
            actions: [
              FilledButton(onPressed: () => Navigator.pop(c), child: const Text('حسناً')),
            ],
          ),
        );
        if (mounted) Navigator.of(context).pop();
        showRoundEndAd();
        return;
      }
      _pollGifts();
      setState(() {
        _v = Map<String, dynamic>.from(r.first as Map);
        _msgs = List<Map<String, dynamic>>.from(m);
      });
    } catch (_) {}
  }

  Future<void> _pollGifts() async {
    try {
      final g = await supa
          .from('match_gifts')
          .select()
          .eq('match_id', widget.matchId)
          .gt('id', _lastGift < 0 ? 0 : _lastGift)
          .order('id');
      final list = List<Map<String, dynamic>>.from(g);
      for (final x in list) {
        final id = (x['id'] as num).toInt();
        if (id <= _lastGift) continue;
        _lastGift = id;
        // أول جلب: نتجاهل القديم، نشغّل فقط الهدايا خلال آخر 20 ثانية
        final t = DateTime.tryParse('${x['created_at']}');
        final fresh = t == null || DateTime.now().toUtc().difference(t.toUtc()).inSeconds < 20;
        if (fresh) _giftKey.currentState?.play(x);
      }
      if (_lastGift < 0) _lastGift = 0;
    } catch (_) {}
  }

  Future<void> _startVoice() async {
    try {
      final res = await supa.functions.invoke('livekit-token', body: {'game_id': widget.matchId});
      final data = res.data;
      if (data is! Map || data['token'] == null) {
        throw (data is Map ? data['error'] : null) ?? 'لا يوجد توكن';
      }
      _events = _room.createListener();
      _events!.listen((_) {
        if (mounted) setState(() {});
      });
      await _room.connect(data['url'] as String, data['token'] as String);
      _connected = true;
      try {
        await Hardware.instance.setSpeakerphoneOn(true);
      } catch (_) {}
      if (mounted) setState(() => _voiceNote = 'الصوت متصل');
      await _setMic(true);
    } catch (e) {
      if (mounted) setState(() => _voiceNote = 'تعذّر ربط الصوت: ${friendlyError(e)}');
    }
  }

  Future<void> _setMic(bool on) async {
    final lp = _room.localParticipant;
    if (lp == null) return;
    if (on) {
      final st = await Permission.microphone.request();
      if (!st.isGranted) {
        if (mounted) toast(context, 'يلزم السماح باستخدام الميكروفون');
        return;
      }
    }
    try {
      await lp.setMicrophoneEnabled(on);
      if (mounted) setState(() => _micOn = on);
    } catch (e) {
      if (mounted) toast(context, 'تعذّر تشغيل الميكروفون');
    }
  }

  Future<void> _toggleSpeaker() async {
    final next = !_speakerOn;
    try {
      await Hardware.instance.setSpeakerphoneOn(next);
      if (mounted) setState(() => _speakerOn = next);
    } catch (_) {}
  }

  Future<void> _reveal() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('رؤية شخصيتك؟'),
        content: const Text('عند رؤيتها سيعلم خصمك أنك رأيتها.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('أرني')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await supa.rpc('reveal_mine', params: {'p_id': widget.matchId});
      await _refresh();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _send() async {
    final t = _input.text.trim();
    if (t.isEmpty) return;
    _input.clear();
    try {
      await supa.from('game_messages').insert({
        'match_id': widget.matchId,
        'user_id': myId,
        'body': t,
      });
      await _refresh();
    } catch (e) {
      if (mounted) toast(context, 'تعذّر الإرسال: ${friendlyError(e)}');
    }
  }

  Future<void> _leave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('الخروج من التحدي؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('البقاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('خروج')),
        ],
      ),
    );
    if (ok != true) return;
    _ended = true;
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _follow() async {
    final id = _v?['opponent_id'];
    if (id == null) return;
    try {
      await supa.rpc('follow_user', params: {'p_id': id});
      if (mounted) setState(() => _following = true);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _events?.dispose();
    _input.dispose();
    () async {
      try {
        await supa.rpc('leave_match', params: {'p_id': widget.matchId});
      } catch (_) {}
      try {
        await _room.disconnect();
      } catch (_) {}
      await _room.dispose();
    }();
    super.dispose();
  }

  Widget _card(String label, Widget child, {Widget? note}) {
    return Expanded(
      child: Column(children: [
        SizedBox(
          height: 34,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Text(label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, height: 1.2, color: Colors.white70, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 6),
        AspectRatio(
          aspectRatio: 0.78,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: C.glassBorder, width: 1.5),
              boxShadow: [BoxShadow(color: C.violet.withValues(alpha: 0.3), blurRadius: 20)],
            ),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        ),
        SizedBox(height: 22, child: note),
      ]),
    );
  }

  Widget _img(String? url) => url == null
      ? Container(color: C.glass)
      : Image.network(url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_rounded)),
          loadingBuilder: (c, w, p) => p == null ? w : const Center(child: CircularProgressIndicator(color: C.pink)));

  @override
  Widget build(BuildContext context) {
    final v = _v;
    final revealedMe = v?['reveal_me'] == true;
    // عند ظهور الكيبورد نخفي البطاقات حتى لا تدفع خانة الكتابة خارج الشاشة في الهواتف الصغيرة
    final kb = MediaQuery.viewInsetsOf(context).bottom > 0;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: Text(v?['category_name'] != null ? 'خمّن الشخصية · ${v!['category_name']}' : 'خمّن الشخصية',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: _leave),
        ),
        body: Stack(children: [
          Positioned.fill(
            child: v == null
            ? const Center(child: CircularProgressIndicator(color: C.pink))
            : Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(children: [
                    Avatar(
                        name: v['opponent_name'] as String,
                        url: v['opponent_avatar'] as String?,
                        size: 32),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(v['opponent_name'] as String,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    ),
                    GradButton(
                      label: _following ? 'تتابعه' : 'متابعة',
                      dense: true,
                      outlined: _following,
                      onPressed: _following ? null : _follow,
                    ),
                  ]),
                ),
                if (!kb)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _card(
                      'الشخصية التي في يدي',
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 400),
                        child: revealedMe
                            ? SizedBox.expand(key: const ValueKey('r'), child: _img(v['my_image'] as String?))
                            : Container(
                                key: const ValueKey('h'),
                                decoration: const BoxDecoration(gradient: brandGradient),
                                alignment: Alignment.center,
                                child: const Icon(Icons.question_mark_rounded, size: 80, color: Colors.white),
                              ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 80, left: 8, right: 8),
                      child: Text('VS',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w900, color: C.pink.withValues(alpha: 0.9))),
                    ),
                    _card(
                      'الشخصية التي في يد خصمك',
                      SizedBox.expand(child: _img(v['opponent_image'] as String?)),
                      note: v['reveal_opp'] == true
                          ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(Icons.visibility_rounded, size: 13, color: C.orange),
                              SizedBox(width: 4),
                              Text('خصمك رأى شخصيته', style: TextStyle(fontSize: 11, color: C.orange)),
                            ])
                          : null,
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(children: [
                    if (!revealedMe)
                      Expanded(
                        child: GradButton(
                            label: 'رؤية شخصيتي', icon: Icons.visibility_rounded, dense: true, onPressed: _reveal),
                      )
                    else
                      const Expanded(child: SizedBox()),
                    const SizedBox(width: 10),
                    IconButton.filled(
                      onPressed: () => showGiftSheet(context, widget.matchId),
                      style: IconButton.styleFrom(backgroundColor: C.pink, foregroundColor: Colors.white),
                      icon: const Icon(Icons.card_giftcard_rounded),
                    ),
                    const SizedBox(width: 8),
                    _round(_micOn ? Icons.mic_rounded : Icons.mic_off_rounded, _micOn,
                        _connected ? () => _setMic(!_micOn) : null),
                    const SizedBox(width: 8),
                    _round(_speakerOn ? Icons.volume_up_rounded : Icons.volume_off_rounded, _speakerOn,
                        _connected ? _toggleSpeaker : null),
                  ]),
                ),
                if (!kb) Text(_voiceNote, style: const TextStyle(fontSize: 11, color: Colors.white54)),
                const Divider(color: Colors.white12),
                Expanded(
                  child: ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _msgs.length,
                    itemBuilder: (_, i) {
                      final m = _msgs[i];
                      final mine = m['user_id'] == myId;
                      return Align(
                        alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                          decoration: BoxDecoration(
                            gradient: mine ? brandGradient : null,
                            color: mine ? null : C.glass,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(m['body'] as String),
                        ),
                      );
                    },
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                    child: Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          maxLength: 300,
                          onSubmitted: (_) => _send(),
                          decoration: const InputDecoration(
                              hintText: 'اكتب سؤالك أو إجابتك...', counterText: ''),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: const BoxDecoration(gradient: brandGradient, shape: BoxShape.circle),
                        child: IconButton(onPressed: _send, icon: const Icon(Icons.send_rounded)),
                      ),
                    ]),
                  ),
                ),
              ]),
          ),
          Positioned.fill(child: GiftOverlay(key: _giftKey)),
        ]),
      ),
    );
  }

  Widget _round(IconData i, bool on, VoidCallback? onTap) => IconButton.filled(
        onPressed: onTap,
        style: IconButton.styleFrom(
          backgroundColor: on ? C.green : const Color(0x33FFFFFF),
          foregroundColor: on ? Colors.black : Colors.white,
          disabledBackgroundColor: const Color(0x14FFFFFF),
        ),
        icon: Icon(i),
      );
}
