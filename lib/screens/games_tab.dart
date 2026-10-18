import 'dart:async';

import 'package:flutter/material.dart';

import '../ads.dart';
import '../main.dart';
import 'rewards_screen.dart';
import '../shop_screen.dart';
import '../theme.dart';
import 'farm_screen.dart';
import 'guess_lobby_screen.dart';
import 'guess_match_screen.dart';

class _GameDef {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final List<String> tags;
  final bool ready;
  final String? cover;
  final String? music;
  const _GameDef(this.id, this.title, this.subtitle, this.icon, this.colors, this.tags,
      {this.ready = false, this.cover, this.music});
}

const _games = [
  _GameDef(
    'guess',
    'خمّن الشخصية',
    'اعرف شخصيتك بأسئلة نعم/لا',
    Icons.face_retouching_natural_rounded,
    [Color(0xFF7C3AED), Color(0xFFA855F7)],
    ['لاعبان', 'صوت'],
    ready: true,
  ),
  _GameDef(
    'farm',
    'المزرعة',
    'عجلة الأكل: راهن بجواهرك واربح',
    Icons.agriculture_rounded,
    [Color(0xFF16A34A), Color(0xFFFACC15)],
    ['جماعية', 'جواهر'],
    ready: true,
  ),
  _GameDef(
    'xo',
    'إكس أو',
    'تحدَّ صديقك',
    Icons.grid_3x3_rounded,
    [Color(0xFF0EA5E9), Color(0xFF22D3EE)],
    ['لاعبان'],
  ),
  _GameDef(
    'rps',
    'حجرة ورقة مقص',
    'من الأسرع بديهة؟',
    Icons.back_hand_rounded,
    [Color(0xFFF97316), Color(0xFFFACC15)],
    ['لاعبان'],
  ),
];

class GamesTab extends StatefulWidget {
  final bool active;
  const GamesTab({super.key, required this.active});

  @override
  State<GamesTab> createState() => _GamesTabState();
}

class _GamesTabState extends State<GamesTab> {
  List<Map<String, dynamic>> _invites = [];
  List<_GameDef> _list = _games;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadGames();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (widget.active) _loadInvites();
    });
  }

  @override
  void didUpdateWidget(covariant GamesTab old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _loadInvites();
      _loadGames();
    }
  }

  Future<void> _loadGames() async {
    try {
      final r = await supa.from('games').select().order('sort');
      final rows = List<Map<String, dynamic>>.from(r);
      final out = <_GameDef>[];
      for (final row in rows) {
        final base = _games.firstWhere((g) => g.id == row['id'], orElse: () => _games.first);
        out.add(_GameDef(
          row['id'] as String,
          row['title'] as String,
          row['subtitle'] as String,
          base.icon,
          base.colors,
          base.tags,
          ready: row['ready'] == true,
          cover: row['cover_url'] as String?,
          music: row['music_url'] as String?,
        ));
      }
      if (mounted && out.isNotEmpty) setState(() => _list = out);
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadInvites() async {
    try {
      final r = await supa.rpc('my_invites');
      if (mounted) setState(() => _invites = List<Map<String, dynamic>>.from(r as List));
    } catch (_) {}
  }

  Future<void> _accept(Map<String, dynamic> inv) async {
    try {
      final mid = await supa.rpc('accept_invite', params: {'p_id': inv['id']});
      if (!mounted) return;
      setState(() => _invites.remove(inv));
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => GuessMatchScreen(matchId: mid as String)),
      );
    } catch (e) {
      if (mounted) {
        toast(context, friendlyError(e));
        _loadInvites();
      }
    }
  }

  Future<void> _decline(Map<String, dynamic> inv) async {
    setState(() => _invites.remove(inv));
    try {
      await supa.rpc('decline_invite', params: {'p_id': inv['id']});
    } catch (_) {}
  }

  void _open(_GameDef g) {
    if (!g.ready) {
      toast(context, 'قريباً... ${g.title}');
      return;
    }
    if (g.id == 'farm') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const FarmScreen()));
      return;
    }
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => GuessLobbyScreen(music: g.music)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الألعاب', style: TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          const AdsPromo(),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RewardsScreen())),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFA855F7)]),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(children: const [
                  Text('🎁', style: TextStyle(fontSize: 26)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text('مكافآت مجانية: هدية يومية + عجلة الحظ + مهام',
                        style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                  Icon(Icons.chevron_left_rounded),
                ]),
              ),
            ),
          ),
          const AdBanner(),
          for (final inv in _invites)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GlassCard(
                child: Row(children: [
                  Avatar(
                      name: inv['from_name'] as String,
                      url: inv['from_avatar'] as String?,
                      size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${inv['from_name']} يتحداك!',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text('خمّن الشخصية · ${inv['category_name']}',
                          style: const TextStyle(color: Colors.white60, fontSize: 12)),
                    ]),
                  ),
                  IconButton(
                    onPressed: () => _decline(inv),
                    icon: const Icon(Icons.close_rounded, color: Color(0xFFFF6B6B)),
                  ),
                  GradButton(label: 'قبول', dense: true, onPressed: () => _accept(inv)),
                ]),
              ),
            ),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 0.78,
            children: [for (final g in _list) _GameCard(g: g, onTap: () => _open(g))],
          ),
        ],
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  final _GameDef g;
  final VoidCallback onTap;
  const _GameCard({required this.g, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(fit: StackFit.expand, children: [
          // الغلاف
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: g.colors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          if (g.cover != null && g.cover!.isNotEmpty)
            Image.network(g.cover!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox())
          else ...[
          Positioned(
            top: -30,
            left: -30,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
          ),
          Positioned(
            bottom: 60,
            right: -40,
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.10),
              ),
            ),
          ),
          Align(
            alignment: const Alignment(0, -0.35),
            child: Icon(g.icon, size: 86, color: Colors.white.withValues(alpha: 0.95)),
          ),
          ],
          // الشريط السفلي
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 22, 12, 12),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0x00000000), Color(0xCC000000)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(g.title,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                Text(g.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 11)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, children: [
                  for (final t in g.tags)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(t, style: const TextStyle(fontSize: 10)),
                    ),
                ]),
              ]),
            ),
          ),
          if (!g.ready)
            Container(
              color: Colors.black.withValues(alpha: 0.45),
              alignment: Alignment.center,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white38),
                ),
                child: const Text('قريباً', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
        ]),
      ),
    );
  }
}
