import 'dart:async';

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
      appBar: AppBar(title: const Text('خمّن الشخصية', style: TextStyle(fontWeight: FontWeight.w800))),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: C.pink))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                GlassCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                    Text('كيف تلعب؟',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    SizedBox(height: 6),
                    Text(
                      'ترى شخصية خصمك ولا ترى شخصيتك، وهو كذلك. اسألا بعضكما أسئلة (نعم/لا) بالصوت أو الكتابة '
                      'لتعرف كل واحد منكما شخصيته. من يعرف أولاً يفوز!',
                      style: TextStyle(color: Colors.white70, height: 1.6),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                const Text('اختر الفئة',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.25,
                  children: [
                    _CatTile(name: 'منوّع', cover: null, onTap: () => _pick(null, 'منوّع')),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
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
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ),
          ),
        ]),
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
      toast(context, e.toString().contains('not enough images')
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
      appBar: AppBar(title: const Text('لعب عشوائي')),
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(width: 64, height: 64, child: CircularProgressIndicator(color: C.pink, strokeWidth: 5)),
          const SizedBox(height: 24),
          const Text('نبحث عن لاعب...', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('اترك الشاشة مفتوحة', style: TextStyle(color: Colors.white60)),
          const SizedBox(height: 28),
          GradButton(label: 'إلغاء', outlined: true, dense: true, onPressed: () => Navigator.pop(context)),
        ]),
      ),
    );
  }
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
