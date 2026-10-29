import '../play_gate.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../main.dart';
import '../audio.dart';
import '../theme.dart';
import 'guess_match_screen.dart';

class GuessLobbyScreen extends StatefulWidget {
  final String? music;
  const GuessLobbyScreen({super.key, this.music});

  @override
  State<GuessLobbyScreen> createState() => _GuessLobbyScreenState();
}

class _GuessLobbyScreenState extends State<GuessLobbyScreen> {
  List<Map<String, dynamic>> _cats = [];
  bool _loading = true;
  String _mixedName = 'منوّع';
  String? _mixedCover;

  @override
  void initState() {
    super.initState();
    Music.play(widget.music);
    _load();
  }

  @override
  void dispose() {
    Music.stop();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await supa
          .from('game_categories')
          .select()
          .eq('active', true)
          .order('sort')
          .order('created_at');
      try {
        final st = await supa.from('app_settings').select().inFilter('key', ['mixed_name', 'mixed_cover']);
        for (final x in st) {
          final v = (x['value'] ?? '') as String;
          if (x['key'] == 'mixed_name' && v.isNotEmpty) _mixedName = v;
          if (x['key'] == 'mixed_cover' && v.isNotEmpty) _mixedCover = v;
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _cats = List<Map<String, dynamic>>.from(r);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      toast(context, friendlyError(e));
    }
  }

  Future<void> _pick(String? catId, String catName) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(catName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: GradButton(
                label: 'لعب عشوائي',
                icon: Icons.shuffle_rounded,
                onPressed: () {
                  Navigator.pop(c);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => _QueueScreen(catId: catId)),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: GradButton(
                label: 'تحدّي صديق',
                icon: Icons.people_alt_rounded,
                outlined: true,
                onPressed: () {
                  Navigator.pop(c);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => _FriendPickScreen(catId: catId)),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('خمّن الشخصية',
            style: TextStyle(fontWeight: FontWeight.w900, color: _gold, fontSize: 22)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: C.pink))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: const LinearGradient(
                        colors: [Color(0xFFF3D9A0), Color(0x55C9A24B), Color(0xFFE6C07A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: const Color(0xFF241552),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                      Text('كيف تلعب؟',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: _gold)),
                      SizedBox(height: 8),
                      Text(
                        'ترى شخصية خصمك ولا ترى شخصيتك، وهو كذلك. اسألا بعضكما أسئلة (نعم/لا) بالصوت أو الكتابة '
                        'لتعرف كل واحد منكما شخصيته. من يعرف أولاً يفوز!',
                        style: TextStyle(color: Colors.white70, height: 1.7),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 20),
                Row(children: const [
                  Icon(Icons.auto_awesome_rounded, color: _gold, size: 18),
                  SizedBox(width: 6),
                  Text('اختر الفئة',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: _gold)),
                ]),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 1.02,
                  children: [
                    _CatTile(name: _mixedName, cover: _mixedCover, onTap: () => _pick(null, _mixedName)),
                    for (final c in _cats)
                      _CatTile(
                        name: c['name'] as String,
                        cover: c['cover_url'] as String?,
                        onTap: () => _pick(c['id'] as String, c['name'] as String),
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}

const _gold = Color(0xFFE8CB8D);

class _CatTile extends StatelessWidget {
  final String name;
  final String? cover;
  final VoidCallback onTap;
  const _CatTile({required this.name, required this.cover, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hue = (name.runes.fold<int>(0, (a, b) => a + b) * 53) % 360;
    final c1 = HSLColor.fromAHSL(1, hue.toDouble(), 0.65, 0.5).toColor();
    final c2 = HSLColor.fromAHSL(1, ((hue + 60) % 360).toDouble(), 0.7, 0.35).toColor();
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(1.8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
              colors: [Color(0xFFF3D9A0), Color(0xFF8A6A2E), Color(0xFFE6C07A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(fit: StackFit.expand, children: [
          if (cover != null && cover!.isNotEmpty)
            Image.network(cover!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox())
          else
            Container(
              decoration: BoxDecoration(gradient: LinearGradient(colors: [c1, c2])),
              child: const Icon(Icons.auto_awesome_rounded, size: 46, color: Colors.white54),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 18, 10, 8),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0x00000000), Color(0xCC000000)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            ),
          ),
        ]),
      ),
      ),
    );
  }
}

/// انتظار لاعب عشوائي
class _QueueScreen extends StatefulWidget {
  final String? catId;
  const _QueueScreen({required this.catId});

  @override
  State<_QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<_QueueScreen> {
  Timer? _timer;
  int _secs = 0;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _tick());
  }

  Future<void> _tick() async {
    if (_done) return;
    _secs += 2;
    try {
      final mid = await supa.rpc('quick_match', params: {'p_cat': widget.catId});
      if (mid != null && !_done && mounted) {
        _done = true;
        _timer?.cancel();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => GuessMatchScreen(matchId: mid as String)),
        );
        return;
      }
    } catch (e) {
      if (!mounted || _done) return;
      _done = true;
      _timer?.cancel();
      toast(context, e.toString().contains('no rounds')
          ? 'انتهت جولاتك المجانية اليوم'
          : e.toString().contains('not enough images')
          ? 'لا توجد صور كافية في هذه الفئة بعد'
          : friendlyError(e));
      Navigator.pop(context);
      return;
    }
    if (_secs >= 60 && mounted && !_done) {
      _done = true;
      _timer?.cancel();
      toast(context, 'لم نجد لاعباً الآن، جرّب لاحقاً أو تحدَّ صديقاً');
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (!_done) {
      supa.rpc('cancel_queue').then((_) {}, onError: (_) {});
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('لعب عشوائي',
            style: TextStyle(fontWeight: FontWeight.w900, color: _gold, fontSize: 22)),
      ),
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const _SearchOrb(),
          const SizedBox(height: 40),
          const Text('نبحث عن لاعب...',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: _gold)),
          const SizedBox(height: 8),
          const Text('اترك الشاشة مفتوحة', style: TextStyle(color: Colors.white60, fontSize: 15)),
          const SizedBox(height: 34),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 210,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(40),
                gradient: const LinearGradient(colors: [Color(0xFFF3D9A0), Color(0xFF8A6A2E), Color(0xFFE6C07A)]),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(38),
                  gradient: const LinearGradient(
                      colors: [Color(0xFF8B5CF6), Color(0xFF5B21B6)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter),
                ),
                child: const Text('إلغاء',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// دائرة بحث متوهجة: حلقات متدرجة تدور حول قناع الشخصيات.
class _SearchOrb extends StatefulWidget {
  const _SearchOrb();

  @override
  State<_SearchOrb> createState() => _SearchOrbState();
}

class _SearchOrbState extends State<_SearchOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      height: 280,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = _c.value;
          final pulse = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
          return Stack(alignment: Alignment.center, children: [
            Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: const Color(0xFFA855F7).withValues(alpha: 0.30 + 0.25 * pulse), blurRadius: 50 + 20 * pulse, spreadRadius: 6),
                ],
              ),
            ),
            Transform.rotate(angle: t * 2 * math.pi, child: CustomPaint(size: const Size(270, 270), painter: _RingPainter(3.5, 0.0))),
            Transform.rotate(angle: -t * 2 * math.pi * 0.7, child: CustomPaint(size: const Size(230, 230), painter: _RingPainter(2.5, 1.7))),
            Transform.rotate(angle: t * 2 * math.pi * 1.4, child: CustomPaint(size: const Size(190, 190), painter: _RingPainter(2, 3.2))),
            Container(
              width: 150,
              height: 150,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [Color(0xFF5B2AA8), Color(0xFF1B0B45)]),
              ),
              child: Transform.scale(
                scale: 0.94 + 0.06 * pulse,
                child: const Icon(Icons.theater_comedy_rounded, size: 84, color: Color(0xFFE2D1FF)),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double width;
  final double phase;
  _RingPainter(this.width, this.phase);

  @override
  void paint(Canvas canvas, Size s) {
    final r = Rect.fromLTWH(width, width, s.width - 2 * width, s.height - 2 * width);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: phase,
        endAngle: phase + 2 * math.pi,
        colors: const [Color(0x00A855F7), Color(0xFFD8B4FE), Color(0xFFFFFFFF), Color(0x00A855F7)],
        stops: const [0.0, 0.55, 0.75, 1.0],
        transform: GradientRotation(phase),
      ).createShader(r);
    canvas.drawArc(r, 0, 2 * math.pi, false, paint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => false;
}

/// اختيار صديق من الذين تتابعهم
class _FriendPickScreen extends StatefulWidget {
  final String? catId;
  const _FriendPickScreen({required this.catId});

  @override
  State<_FriendPickScreen> createState() => _FriendPickScreenState();
}

class _FriendPickScreenState extends State<_FriendPickScreen> {
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
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

  Future<void> _invite(Map<String, dynamic> u) async {
    if (!await ensureCanPlay(context)) return;
    try {
      final id = await supa.rpc('send_invite', params: {'p_to': u['id'], 'p_cat': widget.catId});
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => InviteWait(inviteId: id as String, name: u['name'] as String)),
      );
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('اختر صديقاً')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: C.pink))
          : _list.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('لا تتابع أحداً بعد.\nابحث عن أصدقائك وتابعهم من تبويب «بحث».',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white60, height: 1.7)),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final u = _list[i];
                    return GlassCard(
                      onTap: () => _invite(u),
                      child: Row(children: [
                        Avatar(name: u['name'] as String, url: u['avatar_url'] as String?, size: 42),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(u['name'] as String,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        ),
                        const Icon(Icons.send_rounded, color: C.pink),
                      ]),
                    );
                  },
                ),
    );
  }
}

class InviteWait extends StatefulWidget {
  final String inviteId;
  final String name;
  const InviteWait({super.key, required this.inviteId, required this.name});

  @override
  State<InviteWait> createState() => InviteWaitState();
}

class InviteWaitState extends State<InviteWait> {
  Timer? _timer;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _tick());
  }

  Future<void> _tick() async {
    if (_done) return;
    try {
      final r = await supa.rpc('invite_status', params: {'p_id': widget.inviteId}) as List;
      if (r.isEmpty || !mounted) return;
      final st = r.first['status'] as String;
      if (st == 'accepted' && r.first['match_id'] != null) {
        _done = true;
        _timer?.cancel();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => GuessMatchScreen(matchId: r.first['match_id'] as String)),
        );
      } else if (st == 'declined' || st == 'expired') {
        _done = true;
        _timer?.cancel();
        toast(context, st == 'declined' ? 'رفض ${widget.name} التحدي' : 'انتهت مهلة الدعوة');
        Navigator.pop(context);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تحدّي صديق')),
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(width: 64, height: 64, child: CircularProgressIndicator(color: C.pink, strokeWidth: 5)),
          const SizedBox(height: 24),
          Text('بانتظار ${widget.name}...',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('يظهر له التحدي في تبويب «ألعاب»', style: TextStyle(color: Colors.white60)),
          const SizedBox(height: 28),
          GradButton(label: 'إلغاء', outlined: true, dense: true, onPressed: () => Navigator.pop(context)),
        ]),
      ),
    );
  }
}
