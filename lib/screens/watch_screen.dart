import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

import '../main.dart';
import '../theme.dart';

/// مشاهدة فيلم مشتركة: صاحب الدعوة (host) يتحكم، والضيف يتبع تلقائياً.
class WatchScreen extends StatefulWidget {
  final String partyId;
  final bool host;
  const WatchScreen({super.key, required this.partyId, required this.host});

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  VideoPlayerController? _vc;
  Map<String, dynamic>? _movie;
  String _status = 'invited';
  String _peerName = '';
  bool _ready = false;
  bool _failed = false;
  bool _full = false;
  bool _closing = false;

  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  Timer? _poll;
  Timer? _beat;
  String? _lastStamp;
  DateTime _recvAt = DateTime.now();
  int _recvPos = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final row = await supa.from('watch_parties').select().eq('id', widget.partyId).single();
      final movie = await supa.from('movies').select().eq('id', row['movie_id']).single();
      final peerId = (widget.host ? row['guest_id'] : row['host_id']) as String;
      try {
        final p = await supa.rpc('get_profile', params: {'p_id': peerId}) as List;
        if (p.isNotEmpty) _peerName = p.first['name'] as String;
      } catch (_) {}
      if (!mounted) return;
      _movie = movie;

      Future<ClosedCaptionFile>? caps;
      final sub = movie['subtitle_url'] as String?;
      if (sub != null && sub.isNotEmpty) {
        caps = () async {
          final r = await http.get(Uri.parse(sub));
          final body = r.body;
          return body.contains('WEBVTT') ? WebVTTCaptionFile(body) : SubRipCaptionFile(body);
        }();
      }
      final vc = VideoPlayerController.networkUrl(
        Uri.parse(movie['video_url'] as String),
        closedCaptionFile: caps,
      );
      _vc = vc;
      vc.addListener(() {
        if (mounted) setState(() {});
      });
      try {
        await vc.initialize();
        if (mounted) setState(() => _ready = true);
      } catch (_) {
        if (mounted) setState(() => _failed = true);
      }

      _apply(row);
      _sub = supa
          .from('watch_parties')
          .stream(primaryKey: ['id'])
          .eq('id', widget.partyId)
          .listen((rows) {
        if (rows.isNotEmpty) _apply(rows.first);
      }, onError: (_) {});
      _poll = Timer.periodic(const Duration(seconds: 3), (_) async {
        try {
          final r = await supa.from('watch_parties').select().eq('id', widget.partyId).single();
          _apply(r);
        } catch (_) {}
      });
      if (widget.host) {
        _beat = Timer.periodic(const Duration(seconds: 4), (_) {
          if (_status == 'active' && (_vc?.value.isPlaying ?? false)) _sync();
        });
      }
    } catch (e) {
      if (!mounted) return;
      toast(context, friendlyError(e));
      Navigator.pop(context);
    }
  }

  void _apply(Map<String, dynamic> row) {
    if (!mounted) return;
    final st = row['status'] as String;
    if (st == 'ended' || st == 'declined') {
      if (!_closing) {
        _closing = true;
        toast(context, st == 'declined' ? 'رفض $_peerName الدعوة' : 'انتهت جلسة المشاهدة');
        Navigator.pop(context);
      }
      return;
    }
    if (st != _status) setState(() => _status = st);
    if (widget.host) return;

    final playing = row['playing'] == true;
    final pos = (row['pos_ms'] as num).toInt();
    final stamp = '${row['updated_at']}';
    if (stamp != _lastStamp) {
      _lastStamp = stamp;
      _recvAt = DateTime.now();
      _recvPos = pos;
    }
    final vc = _vc;
    if (st != 'active' || vc == null || !_ready) return;
    final expected =
        playing ? _recvPos + DateTime.now().difference(_recvAt).inMilliseconds : _recvPos;
    final cur = vc.value.position.inMilliseconds;
    if ((cur - expected).abs() > 2000) {
      vc.seekTo(Duration(milliseconds: expected));
    }
    if (playing && !vc.value.isPlaying) vc.play();
    if (!playing && vc.value.isPlaying) vc.pause();
  }

  Future<void> _sync({bool? playing, int? pos}) async {
    final vc = _vc;
    if (vc == null) return;
    try {
      await supa.rpc('party_sync', params: {
        'p_id': widget.partyId,
        'p_playing': playing ?? vc.value.isPlaying,
        'p_pos': pos ?? vc.value.position.inMilliseconds,
      });
    } catch (_) {}
  }

  Future<void> _toggle() async {
    final vc = _vc;
    if (vc == null || !_ready) return;
    if (_status != 'active') {
      toast(context, 'بانتظار انضمام $_peerName');
      return;
    }
    if (vc.value.isPlaying) {
      await vc.pause();
      await _sync(playing: false);
    } else {
      await vc.play();
      await _sync(playing: true);
    }
  }

  Future<void> _seek(int ms) async {
    final vc = _vc;
    if (vc == null || !_ready || _status != 'active') return;
    final total = vc.value.duration.inMilliseconds;
    final t = ms.clamp(0, total);
    await vc.seekTo(Duration(milliseconds: t));
    await _sync(pos: t);
  }

  Future<void> _setFull(bool v) async {
    setState(() => _full = v);
    if (v) {
      await SystemChrome.setPreferredOrientations(
          [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _poll?.cancel();
    _beat?.cancel();
    _vc?.dispose();
    if (_full) {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    final id = widget.partyId;
    unawaited(Future(() async {
      try {
        await supa.rpc('party_end', params: {'p_id': id});
      } catch (_) {}
    }));
    super.dispose();
  }

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    return '${h > 0 ? '$h:' : ''}${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  Widget _video() {
    final vc = _vc;
    if (_failed) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('تعذّر تشغيل الفيلم (الرابط لا يعمل أو الصيغة غير مدعومة)',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
        ),
      );
    }
    if (vc == null || !_ready) {
      return const Center(child: CircularProgressIndicator(color: C.pink));
    }
    return Stack(alignment: Alignment.bottomCenter, children: [
      Center(
        child: AspectRatio(aspectRatio: vc.value.aspectRatio, child: VideoPlayer(vc)),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ClosedCaption(
          text: vc.value.caption.text,
          textStyle: const TextStyle(
              fontSize: 16, color: Colors.white, backgroundColor: Color(0xAA000000)),
        ),
      ),
      if (_status != 'active')
        Container(
          color: Colors.black54,
          alignment: Alignment.center,
          child: Text(
            widget.host ? 'بانتظار انضمام $_peerName...' : 'جاري الانضمام...',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ),
    ]);
  }

  Widget _controls() {
    final vc = _vc;
    final pos = vc?.value.position ?? Duration.zero;
    final dur = vc?.value.duration ?? Duration.zero;
    final total = dur.inMilliseconds.toDouble();
    final cur = pos.inMilliseconds.toDouble().clamp(0, total > 0 ? total : 1).toDouble();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      color: _full ? const Color(0x99000000) : Colors.transparent,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Text(_fmt(pos), style: const TextStyle(fontSize: 12)),
          Expanded(
            child: Slider(
              value: cur,
              max: total > 0 ? total : 1,
              activeColor: C.pink,
              onChanged: widget.host && _ready ? (v) => setState(() {}) : null,
              onChangeEnd: widget.host && _ready ? (v) => _seek(v.toInt()) : null,
            ),
          ),
          Text(_fmt(dur), style: const TextStyle(fontSize: 12)),
        ]),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (widget.host) ...[
            IconButton(
              iconSize: 30,
              onPressed: () => _seek(pos.inMilliseconds - 10000),
              icon: const Icon(Icons.replay_10_rounded),
            ),
            Container(
              decoration: const BoxDecoration(gradient: brandGradient, shape: BoxShape.circle),
              child: IconButton(
                iconSize: 38,
                onPressed: _toggle,
                icon: Icon(vc?.value.isPlaying == true
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded),
              ),
            ),
            IconButton(
              iconSize: 30,
              onPressed: () => _seek(pos.inMilliseconds + 10000),
              icon: const Icon(Icons.forward_10_rounded),
            ),
          ] else
            Text('$_peerName يتحكم بالتشغيل',
                style: const TextStyle(color: Colors.white70)),
          const SizedBox(width: 12),
          IconButton(
            onPressed: () => _setFull(!_full),
            icon: Icon(_full ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded),
          ),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = (_movie?['title'] ?? 'فيلم') as String;
    if (_full) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _setFull(false);
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(children: [
            Positioned.fill(child: _video()),
            Positioned(left: 0, right: 0, bottom: 0, child: _controls()),
          ]),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إنهاء', style: TextStyle(color: Color(0xFFFF6B6B))),
          ),
        ],
      ),
      body: Column(children: [
        Container(
          color: Colors.black,
          height: MediaQuery.of(context).size.width * 9 / 16,
          child: _video(),
        ),
        _controls(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: GlassCard(
            child: Row(children: [
              const Icon(Icons.people_alt_rounded, color: C.cyan),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _status == 'active'
                      ? 'تشاهد مع $_peerName — ${widget.host ? 'أنت تتحكم بالتشغيل' : 'التشغيل يتبع المضيف'}'
                      : (widget.host ? 'بانتظار قبول $_peerName للدعوة...' : 'جاري الانضمام...'),
                  style: const TextStyle(height: 1.5),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
