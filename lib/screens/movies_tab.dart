import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../theme.dart';
import 'watch_screen.dart';

Future<Map<String, dynamic>?> pickFriend(BuildContext context) async {
  List<Map<String, dynamic>> list;
  try {
    list = List<Map<String, dynamic>>.from(await supa.rpc('my_following') as List);
  } catch (e) {
    toast(context, friendlyError(e));
    return null;
  }
  if (!context.mounted) return null;
  if (list.isEmpty) {
    toast(context, 'لا تتابع أحداً بعد — ابحث عن أصدقائك وتابعهم أولاً');
    return null;
  }
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.7),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('اختر من تشاهد معه',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            for (final u in list)
              ListTile(
                leading: Avatar(name: u['name'] as String, url: u['avatar_url'] as String?, size: 40),
                title: Text(u['name'] as String),
                trailing: const Icon(Icons.send_rounded, color: C.pink),
                onTap: () => Navigator.pop(c, u),
              ),
          ],
        ),
      ),
    ),
  );
}

Future<void> inviteToWatch(
    BuildContext context, Map<String, dynamic> movie, Map<String, dynamic> friend,
    {bool replace = false}) async {
  try {
    final id = await supa.rpc('party_invite', params: {
      'p_movie': movie['id'],
      'p_guest': friend['id'],
    });
    if (!context.mounted) return;
    final route = MaterialPageRoute<void>(
        builder: (_) => WatchScreen(partyId: id as String, host: true));
    if (replace) {
      Navigator.pushReplacement(context, route);
    } else {
      Navigator.push(context, route);
    }
  } catch (e) {
    if (context.mounted) toast(context, friendlyError(e));
  }
}

class _MovieGrid extends StatelessWidget {
  final List<Map<String, dynamic>> movies;
  final void Function(Map<String, dynamic>) onTap;
  const _MovieGrid({required this.movies, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.68,
      ),
      itemCount: movies.length,
      itemBuilder: (_, i) {
        final m = movies[i];
        final poster = m['poster_url'] as String?;
        return GestureDetector(
          onTap: () => onTap(m),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Stack(fit: StackFit.expand, children: [
              Container(decoration: const BoxDecoration(gradient: brandGradient)),
              const Center(child: Icon(Icons.movie_rounded, size: 60, color: Colors.white54)),
              if (poster != null && poster.isNotEmpty)
                Image.network(poster, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0x00000000), Color(0xDD000000)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Text(m['title'] as String,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}

Future<List<Map<String, dynamic>>> _loadMovies() async {
  final r = await supa.from('movies').select().eq('active', true).order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(r);
}

class MoviesTab extends StatefulWidget {
  final bool active;
  const MoviesTab({super.key, required this.active});

  @override
  State<MoviesTab> createState() => _MoviesTabState();
}

class _MoviesTabState extends State<MoviesTab> {
  List<Map<String, dynamic>> _movies = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MoviesTab old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _load();
  }

  Future<void> _load() async {
    try {
      final r = await _loadMovies();
      if (mounted) setState(() {
        _movies = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      toast(context, friendlyError(e));
    }
  }

  Future<void> _open(Map<String, dynamic> m) async {
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m['title'] as String,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              if (((m['description'] ?? '') as String).isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(m['description'] as String,
                    style: const TextStyle(color: Colors.white70, height: 1.6)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: GradButton(
                  label: 'دعوة صديق للمشاهدة',
                  icon: Icons.group_add_rounded,
                  onPressed: () => Navigator.pop(c, true),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
    if (go != true || !mounted) return;
    final f = await pickFriend(context);
    if (f == null || !mounted) return;
    await inviteToWatch(context, m, f);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('أفلام', style: TextStyle(fontWeight: FontWeight.w800))),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: C.pink))
          : _movies.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('لا توجد أفلام بعد.\nيضيفها المدير من لوحة المدير ← الأفلام.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white60, height: 1.7)),
                  ),
                )
              : RefreshIndicator(onRefresh: _load, child: _MovieGrid(movies: _movies, onTap: _open)),
    );
  }
}

/// اختيار فيلم لدعوة صديق محدد (من المحادثة).
class MoviePickScreen extends StatefulWidget {
  final String friendId;
  final String friendName;
  const MoviePickScreen({super.key, required this.friendId, required this.friendName});

  @override
  State<MoviePickScreen> createState() => _MoviePickScreenState();
}

class _MoviePickScreenState extends State<MoviePickScreen> {
  List<Map<String, dynamic>> _movies = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMovies().then((r) {
      if (mounted) setState(() {
        _movies = r;
        _loading = false;
      });
    }).catchError((Object e) {
      if (mounted) {
        setState(() => _loading = false);
        toast(context, friendlyError(e));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('اختر فيلماً مع ${widget.friendName}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: C.pink))
          : _movies.isEmpty
              ? const Center(child: Text('لا توجد أفلام بعد', style: TextStyle(color: Colors.white60)))
              : _MovieGrid(
                  movies: _movies,
                  onTap: (m) => inviteToWatch(
                    context,
                    m,
                    {'id': widget.friendId},
                    replace: true,
                  ),
                ),
    );
  }
}
