import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../main.dart';
import '../media.dart';
import '../theme.dart';

Future<String> _uploadImage(XFile f, String folder) async {
  final bytes = await f.readAsBytes();
  final ext = extOf(f.name, ['jpg', 'jpeg', 'png', 'webp'], 'jpg');
  return uploadMedia(
    bucket: 'game-media',
    folder: folder,
    bytes: bytes,
    ext: ext,
    contentType: 'image/${ext == 'jpg' ? 'jpeg' : ext}',
  );
}

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('لوحة المدير', style: TextStyle(fontWeight: FontWeight.w800)),
          bottom: const TabBar(
            isScrollable: true,
            indicatorColor: C.pink,
            tabs: [
              Tab(text: 'إحصائيات'),
              Tab(text: 'الألعاب'),
              Tab(text: 'فئات خمّن'),
              Tab(text: 'الأفلام'),
              Tab(text: 'الغرف'),
            ],
          ),
        ),
        body: const TabBarView(children: [
          _StatsTab(),
          _GamesAdminTab(),
          _CategoriesTab(),
          _MoviesAdminTab(),
          _RoomsTab(),
        ]),
      ),
    );
  }
}

class _StatsTab extends StatefulWidget {
  const _StatsTab();

  @override
  State<_StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<_StatsTab> {
  Map<String, dynamic>? _s;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await supa.rpc('admin_stats');
      if (mounted) setState(() => _s = Map<String, dynamic>.from(r as Map));
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) return const Center(child: CircularProgressIndicator(color: C.pink));
    final items = [
      ('المستخدمون', s['users'], Icons.people_rounded, C.violet),
      ('جدد اليوم', s['users_today'], Icons.person_add_rounded, C.cyan),
      ('غرف مباشرة', s['live_rooms'], Icons.mic_rounded, C.pink),
      ('مباريات اليوم', s['matches_today'], Icons.sports_esports_rounded, C.orange),
      ('مباريات جارية', s['active_matches'], Icons.play_circle_rounded, C.green),
      ('فئات اللعبة', s['categories'], Icons.category_rounded, C.violet),
      ('صور الشخصيات', s['images'], Icons.image_rounded, C.cyan),
    ];
    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.count(
        padding: const EdgeInsets.all(16),
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.5,
        children: [
          for (final it in items)
            GlassCard(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(it.$3, color: it.$4),
                Text('${it.$2}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                Text(it.$1, style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ]),
            ),
        ],
      ),
    );
  }
}

class _CategoriesTab extends StatefulWidget {
  const _CategoriesTab();

  @override
  State<_CategoriesTab> createState() => _CategoriesTabState();
}

class _CategoriesTabState extends State<_CategoriesTab> {
  List<Map<String, dynamic>> _cats = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await supa.from('game_categories').select().order('sort').order('created_at');
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

  Future<void> _add() async {
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('فئة جديدة'),
        content: TextField(controller: name, maxLength: 40, decoration: const InputDecoration(labelText: 'اسم الفئة')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('إضافة')),
        ],
      ),
    );
    if (ok != true || name.text.trim().length < 2) return;
    try {
      await supa.from('game_categories').insert({'name': name.text.trim(), 'sort': _cats.length + 1});
      await _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _setCover(Map<String, dynamic> c) async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 900, imageQuality: 85);
    if (f == null) return;
    try {
      final url = await _uploadImage(f, 'covers');
      await supa.from('game_categories').update({'cover_url': url}).eq('id', c['id']);
      await _load();
      if (mounted) toast(context, 'تم تغيير الغلاف');
    } catch (e) {
      if (mounted) toast(context, 'فشل الرفع: ${friendlyError(e)}');
    }
  }

  Future<void> _delete(Map<String, dynamic> c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('حذف «${c['name']}»؟'),
        content: const Text('ستُحذف الفئة وكل صورها.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await supa.from('game_categories').delete().eq('id', c['id']);
      await _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _toggle(Map<String, dynamic> c, bool v) async {
    try {
      await supa.from('game_categories').update({'active': v}).eq('id', c['id']);
      await _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        backgroundColor: C.violet,
        icon: const Icon(Icons.add_rounded),
        label: const Text('فئة'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: C.pink))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              itemCount: _cats.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final c = _cats[i];
                final cover = c['cover_url'] as String?;
                return GlassCard(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => _CategoryImagesScreen(catId: c['id'] as String, name: c['name'] as String),
                    ),
                  ),
                  child: Row(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: cover == null || cover.isEmpty
                            ? Container(
                                color: C.glass, child: const Icon(Icons.image_not_supported_outlined))
                            : Image.network(cover, fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(c['name'] as String,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    ),
                    Switch(value: c['active'] == true, onChanged: (v) => _toggle(c, v)),
                    PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'cover') _setCover(c);
                        if (v == 'del') _delete(c);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'cover', child: Text('تغيير الغلاف')),
                        PopupMenuItem(value: 'del', child: Text('حذف الفئة')),
                      ],
                    ),
                  ]),
                );
              },
            ),
    );
  }
}

class _CategoryImagesScreen extends StatefulWidget {
  final String catId;
  final String name;
  const _CategoryImagesScreen({required this.catId, required this.name});

  @override
  State<_CategoryImagesScreen> createState() => _CategoryImagesScreenState();
}

class _CategoryImagesScreenState extends State<_CategoryImagesScreen> {
  List<Map<String, dynamic>> _imgs = [];
  bool _loading = true;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await supa
          .from('game_images')
          .select()
          .eq('category_id', widget.catId)
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _imgs = List<Map<String, dynamic>>.from(r);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      toast(context, friendlyError(e));
    }
  }

  Future<void> _add() async {
    final files = await ImagePicker().pickMultiImage(maxWidth: 900, imageQuality: 85);
    if (files.isEmpty) return;
    setState(() => _uploading = true);
    var ok = 0;
    for (final f in files) {
      try {
        final url = await _uploadImage(f, widget.catId);
        await supa.from('game_images').insert({'category_id': widget.catId, 'url': url});
        ok++;
      } catch (e) {
        if (mounted) toast(context, 'فشل رفع صورة: ${friendlyError(e)}');
      }
    }
    if (mounted) {
      setState(() => _uploading = false);
      toast(context, 'تم رفع $ok من ${files.length}');
    }
    await _load();
  }

  Future<void> _delete(Map<String, dynamic> img) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('حذف الصورة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await supa.from('game_images').delete().eq('id', img['id']);
      await _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.name} (${_imgs.length})')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploading ? null : _add,
        backgroundColor: C.violet,
        icon: _uploading
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.add_photo_alternate_rounded),
        label: Text(_uploading ? 'جاري الرفع...' : 'إضافة صور'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: C.pink))
          : _imgs.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('لا توجد صور بعد.\nأضف صور شخصيات (حتى 10 أو أكثر دفعة واحدة).\nتحتاج صورتين على الأقل ليعمل اللعب.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white60, height: 1.7)),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 0.8,
                  ),
                  itemCount: _imgs.length,
                  itemBuilder: (_, i) {
                    final img = _imgs[i];
                    return GestureDetector(
                      onLongPress: () => _delete(img),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(img['url'] as String, fit: BoxFit.cover),
                      ),
                    );
                  },
                ),
    );
  }
}

class _RoomsTab extends StatefulWidget {
  const _RoomsTab();

  @override
  State<_RoomsTab> createState() => _RoomsTabState();
}

class _RoomsTabState extends State<_RoomsTab> {
  List<Map<String, dynamic>> _rooms = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await supa.rpc('list_rooms');
      if (!mounted) return;
      setState(() {
        _rooms = List<Map<String, dynamic>>.from(r as List);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      toast(context, friendlyError(e));
    }
  }

  Future<void> _end(Map<String, dynamic> r) async {
    try {
      await supa.rpc('admin_end_room', params: {'p_id': r['id']});
      await _load();
      if (mounted) toast(context, 'تم إغلاق الغرفة');
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: C.pink));
    return RefreshIndicator(
      onRefresh: _load,
      child: _rooms.isEmpty
          ? ListView(children: const [
              SizedBox(height: 120),
              Center(child: Text('لا توجد غرف مباشرة', style: TextStyle(color: Colors.white60))),
            ])
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _rooms.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final r = _rooms[i];
                return GlassCard(
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r['title'] as String,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        Text('المضيف: ${r['host_name']} · ${r['listeners']} مستمع',
                            style: const TextStyle(color: Colors.white60, fontSize: 12)),
                      ]),
                    ),
                    GradButton(label: 'إغلاق', dense: true, outlined: true, onPressed: () => _end(r)),
                  ]),
                );
              },
            ),
    );
  }
}


// ============================ الألعاب: غلاف + أغنية ============================
class _GamesAdminTab extends StatefulWidget {
  const _GamesAdminTab();

  @override
  State<_GamesAdminTab> createState() => _GamesAdminTabState();
}

class _GamesAdminTabState extends State<_GamesAdminTab> {
  List<Map<String, dynamic>> _games = [];
  bool _loading = true;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await supa.from('games').select().order('sort');
      if (!mounted) return;
      setState(() {
        _games = List<Map<String, dynamic>>.from(r);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      toast(context, friendlyError(e));
    }
  }

  Future<void> _update(Map<String, dynamic> g, Map<String, dynamic> vals, String ok) async {
    try {
      await supa.from('games').update(vals).eq('id', g['id']);
      await _load();
      if (mounted) toast(context, ok);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _cover(Map<String, dynamic> g) async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1000, imageQuality: 85);
    if (f == null) return;
    setState(() => _busy = g['id'] as String);
    try {
      final url = await _uploadImage(f, 'games');
      await _update(g, {'cover_url': url}, 'تم تغيير الغلاف');
    } catch (e) {
      if (mounted) toast(context, 'فشل الرفع: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _music(Map<String, dynamic> g) async {
    final r = await FilePicker.platform.pickFiles(type: FileType.audio, withData: true);
    if (r == null || r.files.isEmpty) return;
    final f = r.files.first;
    final bytes = f.bytes;
    if (bytes == null) {
      toast(context, 'تعذّرت قراءة الملف');
      return;
    }
    if (bytes.length > 45 * 1024 * 1024) {
      toast(context, 'الملف كبير (الحد 45 ميغا)');
      return;
    }
    setState(() => _busy = g['id'] as String);
    try {
      final ext = extOf(f.name, ['mp3', 'm4a', 'aac', 'wav', 'ogg'], 'mp3');
      final url = await uploadMedia(
        bucket: 'game-media',
        folder: 'music',
        bytes: bytes,
        ext: ext,
        contentType: ext == 'mp3' ? 'audio/mpeg' : 'audio/$ext',
      );
      await _update(g, {'music_url': url}, 'تمت إضافة الأغنية');
    } catch (e) {
      if (mounted) toast(context, 'فشل الرفع: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _musicUrl(Map<String, dynamic> g) async {
    final c = TextEditingController(text: (g['music_url'] ?? '') as String);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('رابط الأغنية (mp3)'),
        content: TextField(controller: c, textDirection: TextDirection.ltr),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok == true) await _update(g, {'music_url': c.text.trim()}, 'تم الحفظ');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: C.pink));
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _games.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final g = _games[i];
        final cover = g['cover_url'] as String?;
        final music = g['music_url'] as String?;
        final hasMusic = music != null && music.isNotEmpty;
        return GlassCard(
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 64,
                height: 64,
                child: _busy == g['id']
                    ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                    : cover == null || cover.isEmpty
                        ? Container(color: C.glass, child: const Icon(Icons.image_outlined))
                        : Image.network(cover, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(g['title'] as String,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Row(children: [
                  Icon(hasMusic ? Icons.music_note_rounded : Icons.music_off_rounded,
                      size: 14, color: hasMusic ? C.green : Colors.white38),
                  const SizedBox(width: 4),
                  Text(hasMusic ? 'فيها أغنية' : 'بدون أغنية',
                      style: const TextStyle(color: Colors.white60, fontSize: 12)),
                ]),
              ]),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                switch (v) {
                  case 'cover':
                    _cover(g);
                  case 'music':
                    _music(g);
                  case 'url':
                    _musicUrl(g);
                  case 'nomusic':
                    _update(g, {'music_url': null}, 'تم حذف الأغنية');
                  case 'nocover':
                    _update(g, {'cover_url': null}, 'تمت إعادة الغلاف الافتراضي');
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'cover', child: Text('تغيير الغلاف (من الاستديو)')),
                PopupMenuItem(value: 'music', child: Text('رفع أغنية من الهاتف')),
                PopupMenuItem(value: 'url', child: Text('أغنية من رابط')),
                PopupMenuItem(value: 'nomusic', child: Text('حذف الأغنية')),
                PopupMenuItem(value: 'nocover', child: Text('الغلاف الافتراضي')),
              ],
            ),
          ]),
        );
      },
    );
  }
}

// ============================ الأفلام ============================
class _MoviesAdminTab extends StatefulWidget {
  const _MoviesAdminTab();

  @override
  State<_MoviesAdminTab> createState() => _MoviesAdminTabState();
}

class _MoviesAdminTabState extends State<_MoviesAdminTab> {
  List<Map<String, dynamic>> _movies = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await supa.from('movies').select().order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _movies = List<Map<String, dynamic>>.from(r);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      toast(context, friendlyError(e));
    }
  }

  Future<void> _addManual() async {
    final title = TextEditingController();
    final video = TextEditingController();
    final sub = TextEditingController();
    final desc = TextEditingController();
    XFile? poster;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setD) => AlertDialog(
          title: const Text('إضافة فيلم'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: title, decoration: const InputDecoration(labelText: 'اسم الفيلم')),
              TextField(
                  controller: video,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'رابط الفيلم المباشر (mp4 / m3u8)')),
              TextField(
                  controller: sub,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'رابط الترجمة (srt / vtt) — اختياري')),
              TextField(
                  controller: desc, maxLines: 2, decoration: const InputDecoration(labelText: 'وصف — اختياري')),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final f = await ImagePicker()
                      .pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 85);
                  if (f != null) setD(() => poster = f);
                },
                icon: const Icon(Icons.image_rounded),
                label: Text(poster == null ? 'اختيار بوستر من الاستديو' : 'تم اختيار البوستر ✓'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('إضافة')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (title.text.trim().isEmpty || !video.text.trim().startsWith('http')) {
      if (mounted) toast(context, 'اكتب الاسم ورابطاً صحيحاً يبدأ بـ http');
      return;
    }
    try {
      String? posterUrl;
      if (poster != null) posterUrl = await _uploadImage(poster!, 'posters');
      await supa.from('movies').insert({
        'title': title.text.trim(),
        'video_url': video.text.trim(),
        'subtitle_url': sub.text.trim().isEmpty ? null : sub.text.trim(),
        'description': desc.text.trim(),
        'poster_url': posterUrl,
      });
      await _load();
      if (mounted) toast(context, 'تمت إضافة الفيلم');
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _poster(Map<String, dynamic> m) async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 85);
    if (f == null) return;
    try {
      final url = await _uploadImage(f, 'posters');
      await supa.from('movies').update({'poster_url': url}).eq('id', m['id']);
      await _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _delete(Map<String, dynamic> m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('حذف «${m['title']}»؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await supa.from('movies').delete().eq('id', m['id']);
      await _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _toggle(Map<String, dynamic> m, bool v) async {
    try {
      await supa.from('movies').update({'active': v}).eq('id', m['id']);
      await _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: C.violet,
        icon: const Icon(Icons.add_rounded),
        label: const Text('فيلم'),
        onPressed: () async {
          final v = await showModalBottomSheet<String>(
            context: context,
            builder: (c) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ListTile(
                  leading: const Icon(Icons.link_rounded),
                  title: const Text('إضافة برابط مباشر'),
                  onTap: () => Navigator.pop(c, 'manual'),
                ),
                ListTile(
                  leading: const Icon(Icons.search_rounded),
                  title: const Text('بحث في أرشيف الإنترنت (أفلام حرة قانونية)'),
                  onTap: () => Navigator.pop(c, 'archive'),
                ),
              ]),
            ),
          );
          if (v == 'manual') await _addManual();
          if (v == 'archive' && context.mounted) {
            await Navigator.push(
                context, MaterialPageRoute(builder: (_) => const _ArchiveSearchScreen()));
            await _load();
          }
        },
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: C.pink))
          : _movies.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('لا توجد أفلام.\nاضغط «فيلم» لإضافة فيلم.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white60, height: 1.7)),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  itemCount: _movies.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final m = _movies[i];
                    final poster = m['poster_url'] as String?;
                    return GlassCard(
                      child: Row(children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 48,
                            height: 64,
                            child: poster == null || poster.isEmpty
                                ? Container(color: C.glass, child: const Icon(Icons.movie_rounded))
                                : Image.network(poster, fit: BoxFit.cover),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(m['title'] as String,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w800)),
                        ),
                        Switch(value: m['active'] == true, onChanged: (v) => _toggle(m, v)),
                        PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'poster') _poster(m);
                            if (v == 'del') _delete(m);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'poster', child: Text('تغيير البوستر')),
                            PopupMenuItem(value: 'del', child: Text('حذف الفيلم')),
                          ],
                        ),
                      ]),
                    );
                  },
                ),
    );
  }
}

class _ArchiveSearchScreen extends StatefulWidget {
  const _ArchiveSearchScreen();

  @override
  State<_ArchiveSearchScreen> createState() => _ArchiveSearchScreenState();
}

class _ArchiveSearchScreenState extends State<_ArchiveSearchScreen> {
  final _q = TextEditingController();
  List<Map<String, dynamic>> _res = [];
  bool _busy = false;

  Future<void> _search() async {
    final q = _q.text.trim();
    if (q.isEmpty) return;
    setState(() => _busy = true);
    try {
      final uri = Uri.https('archive.org', '/advancedsearch.php', {
        'q': 'title:($q) AND mediatype:movies AND collection:feature_films',
        'fl[]': ['identifier', 'title'],
        'rows': '25',
        'output': 'json',
      });
      final r = await http.get(uri).timeout(const Duration(seconds: 20));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final docs = (j['response']['docs'] as List).cast<Map<String, dynamic>>();
      if (mounted) setState(() => _res = docs);
    } catch (e) {
      if (mounted) toast(context, 'تعذّر البحث: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import(Map<String, dynamic> d) async {
    final id = d['identifier'] as String;
    setState(() => _busy = true);
    try {
      final r = await http
          .get(Uri.parse('https://archive.org/metadata/$id'))
          .timeout(const Duration(seconds: 25));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final files = (j['files'] as List).cast<Map<String, dynamic>>();
      String enc(String n) => n.split('/').map(Uri.encodeComponent).join('/');
      Map<String, dynamic>? mp4;
      for (final f in files) {
        final n = (f['name'] as String).toLowerCase();
        if (n.endsWith('.mp4') && !n.contains('_thumb')) {
          if (mp4 == null || (int.tryParse('${f['size']}') ?? 0) < (int.tryParse('${mp4['size']}') ?? 0)) {
            mp4 = f; // الأصغر حجماً = أسرع تشغيلاً
          }
        }
      }
      if (mp4 == null) throw 'لا يوجد ملف mp4 لهذا الفيلم';
      String? sub;
      for (final f in files) {
        final n = (f['name'] as String).toLowerCase();
        if (n.endsWith('.vtt') || n.endsWith('.srt')) {
          sub = 'https://archive.org/download/$id/${enc(f['name'] as String)}';
          break;
        }
      }
      var desc = '${j['metadata']?['description'] ?? ''}';
      desc = desc.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (desc.length > 300) desc = '${desc.substring(0, 300)}...';
      await supa.from('movies').insert({
        'title': d['title'] as String,
        'description': desc,
        'video_url': 'https://archive.org/download/$id/${enc(mp4['name'] as String)}',
        'subtitle_url': sub,
        'poster_url': 'https://archive.org/services/img/$id',
      });
      if (mounted) {
        toast(context, 'تمت إضافة «${d['title']}»');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) toast(context, 'فشل الاستيراد: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('أرشيف الإنترنت')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _q,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: 'اسم الفيلم بالإنكليزية، مثل: Nosferatu',
              suffixIcon: IconButton(onPressed: _search, icon: const Icon(Icons.search_rounded)),
            ),
          ),
        ),
        if (_busy) const LinearProgressIndicator(color: C.pink),
        Expanded(
          child: ListView(
            children: [
              for (final d in _res)
                ListTile(
                  leading: Image.network('https://archive.org/services/img/${d['identifier']}',
                      width: 40, errorBuilder: (_, __, ___) => const Icon(Icons.movie_rounded)),
                  title: Text('${d['title']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.add_circle_rounded, color: C.pink),
                  onTap: _busy ? null : () => _import(d),
                ),
            ],
          ),
        ),
      ]),
    );
  }
}
