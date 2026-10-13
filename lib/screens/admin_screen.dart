import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import '../theme.dart';

Future<String> _uploadImage(XFile f, String folder) async {
  final bytes = await f.readAsBytes();
  var ext = f.name.contains('.') ? f.name.split('.').last.toLowerCase() : 'jpg';
  if (!['jpg', 'jpeg', 'png', 'webp'].contains(ext)) ext = 'jpg';
  final path = '$folder/${DateTime.now().millisecondsSinceEpoch}_${bytes.length}.$ext';
  await supa.storage.from('game-media').uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(contentType: 'image/${ext == 'jpg' ? 'jpeg' : ext}'),
      );
  return supa.storage.from('game-media').getPublicUrl(path);
}

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('لوحة المدير', style: TextStyle(fontWeight: FontWeight.w800)),
          bottom: const TabBar(
            indicatorColor: C.pink,
            tabs: [Tab(text: 'إحصائيات'), Tab(text: 'فئات اللعبة'), Tab(text: 'الغرف')],
          ),
        ),
        body: const TabBarView(children: [_StatsTab(), _CategoriesTab(), _RoomsTab()]),
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
