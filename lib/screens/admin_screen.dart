import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../config.dart';
import '../level.dart';
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


/// يختار ملف هدية (صورة/GIF/WebP متحرك/Lottie JSON) ويرفعه كما هو دون ضغط حتى لا تضيع الحركة.
Future<String?> _pickGiftFile() async {
  final r = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'gif', 'json'],
    withData: true,
  );
  if (r == null || r.files.isEmpty) return null;
  final f = r.files.first;
  final bytes = f.bytes;
  if (bytes == null) throw 'تعذّر قراءة الملف';
  if (bytes.length > 4 * 1024 * 1024) throw 'الملف أكبر من 4 ميغا';
  final ext = extOf(f.name, ['png', 'jpg', 'jpeg', 'webp', 'gif', 'json'], 'png');
  final ct = ext == 'json' ? 'application/json' : 'image/${ext == 'jpg' ? 'jpeg' : ext}';
  return uploadMedia(bucket: 'game-media', folder: 'gifts', bytes: bytes, ext: ext, contentType: ct);
}

Future<String?> _askText(BuildContext context, String title, String initial, {int max = 40}) async {
  final c = TextEditingController(text: initial);
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, maxLength: max),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('حفظ')),
      ],
    ),
  );
  if (ok != true) return null;
  final t = c.text.trim();
  return t.length < 2 ? null : t;
}

Future<void> _setSetting(String key, String value) =>
    supa.from('app_settings').upsert({'key': key, 'value': value});

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 10,
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
              Tab(text: 'إشعارات'),
              Tab(text: 'مستخدمون'),
              Tab(text: 'المدفوعات'),
              Tab(text: 'المهام'),
              Tab(text: 'الألقاب والمستويات'),
              Tab(text: 'طريقة اللعب'),
              Tab(text: 'الجولات والأسعار'),
            ],
          ),
        ),
        body: const TabBarView(children: [
          _StatsTab(),
          _GamesAdminTab(),
          _CategoriesTab(),
          _NoticesAdminTab(),
          _UsersAdminTab(),
          _PaymentsAdminTab(),
          _MissionsAdminTab(),
          _BadgesAdminTab(),
          _TutorialAdminTab(),
          _PlaySettingsTab(),
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
  String _mixedName = 'منوّع';
  String _mixedCover = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await supa.from('game_categories').select().order('sort').order('created_at');
      final st = await supa.from('app_settings').select().inFilter('key', ['mixed_name', 'mixed_cover']);
      for (final x in st) {
        if (x['key'] == 'mixed_name' && (x['value'] as String).isNotEmpty) _mixedName = x['value'] as String;
        if (x['key'] == 'mixed_cover') _mixedCover = x['value'] as String;
      }
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

  Future<void> _rename(Map<String, dynamic> c) async {
    final n = await _askText(context, 'اسم الفئة', c['name'] as String);
    if (n == null) return;
    try {
      await supa.from('game_categories').update({'name': n}).eq('id', c['id']);
      await _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _mixedRename() async {
    final n = await _askText(context, 'اسم قسم «منوّع»', _mixedName);
    if (n == null) return;
    try {
      await _setSetting('mixed_name', n);
      await _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _mixedCoverPick() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 900, imageQuality: 85);
    if (f == null) return;
    try {
      final url = await _uploadImage(f, 'covers');
      await _setSetting('mixed_cover', url);
      await _load();
      if (mounted) toast(context, 'تم تغيير غلاف المنوّع');
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
              itemCount: _cats.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                if (i == 0) {
                  return GlassCard(
                    child: Row(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 56,
                          height: 56,
                          child: _mixedCover.isEmpty
                              ? Container(color: C.glass, child: const Icon(Icons.auto_awesome_rounded))
                              : Image.network(_mixedCover, fit: BoxFit.cover),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(_mixedName,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          const Text('قسم ثابت (كل الصور)',
                              style: TextStyle(color: Colors.white54, fontSize: 12)),
                        ]),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'cover') _mixedCoverPick();
                          if (v == 'name') _mixedRename();
                          if (v == 'nocover') {
                            _setSetting('mixed_cover', '').then((_) => _load());
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'cover', child: Text('تغيير الغلاف')),
                          PopupMenuItem(value: 'name', child: Text('تغيير الاسم')),
                          PopupMenuItem(value: 'nocover', child: Text('الغلاف الافتراضي')),
                        ],
                      ),
                    ]),
                  );
                }
                final c = _cats[i - 1];
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
                        if (v == 'name') _rename(c);
                        if (v == 'del') _delete(c);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'cover', child: Text('تغيير الغلاف')),
                        PopupMenuItem(value: 'name', child: Text('تغيير الاسم')),
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
                  case 'name':
                    _askText(context, 'اسم اللعبة', g['title'] as String).then((n) {
                      if (n != null) _update(g, {'title': n}, 'تم تغيير الاسم');
                    });
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'name', child: Text('تغيير اسم اللعبة')),
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








// ============================ الإشعارات ============================
class _NoticesAdminTab extends StatefulWidget {
  const _NoticesAdminTab();

  @override
  State<_NoticesAdminTab> createState() => _NoticesAdminTabState();
}

class _NoticesAdminTabState extends State<_NoticesAdminTab> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _url = TextEditingController();
  String _kind = 'info';
  bool _sending = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_title.text.trim().isEmpty) {
      toast(context, 'اكتب عنوان الإشعار');
      return;
    }
    setState(() => _sending = true);
    try {
      final res = await supa.functions.invoke('send-push', body: {
        'title': _title.text.trim(),
        'body': _body.text.trim(),
        'kind': _kind,
        'url': _url.text.trim(),
      });
      final d = res.data;
      if (!mounted) return;
      if (d is Map && d['push'] == true) {
        toast(context, 'تم الإرسال داخل التطبيق وخارجه');
        _title.clear();
        _body.clear();
        _url.clear();
      } else if (d is Map && d['inApp'] == true) {
        final why = (d['error'] ?? d['note'] ?? '').toString();
        toast(context, 'وصل داخل التطبيق فقط. إشعار النظام لم يُرسل: $why');
      } else {
        toast(context, 'فشل الإرسال: ${d is Map ? d['error'] : d}');
      }
    } catch (e) {
      if (mounted) toast(context, 'فشل الإرسال: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('أرسل إشعاراً لكل المستخدمين',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      const Text('يظهر كشريط لمن هو داخل التطبيق، وكإشعار نظام لمن هو خارجه.',
          style: TextStyle(color: Colors.white60, fontSize: 12)),
      const SizedBox(height: 14),
      Wrap(spacing: 8, children: [
        for (final k in const [('info', 'إعلان'), ('update', 'تحديث'), ('alert', 'تنبيه')])
          ChoiceChip(
            label: Text(k.$2),
            selected: _kind == k.$1,
            onSelected: (_) => setState(() => _kind = k.$1),
          ),
      ]),
      const SizedBox(height: 10),
      TextField(
          controller: _title,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'العنوان')),
      const SizedBox(height: 6),
      TextField(
          controller: _body,
          maxLength: 400,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'النص')),
      const SizedBox(height: 6),
      TextField(
          controller: _url,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
              labelText: 'رابط (اختياري) مثل رابط تحميل التحديث', hintText: 'https://')),
      const SizedBox(height: 14),
      GradButton(
        label: _sending ? 'جارٍ الإرسال...' : 'إرسال',
        icon: Icons.send_rounded,
        onPressed: _sending ? null : _send,
      ),
    ]);
  }
}

// ============================ المستخدمون (رفع المستوى) ============================
class _UsersAdminTab extends StatefulWidget {
  const _UsersAdminTab();

  @override
  State<_UsersAdminTab> createState() => _UsersAdminTabState();
}

class _UsersAdminTabState extends State<_UsersAdminTab> {
  final _q = TextEditingController();
  final _lvl = TextEditingController();
  final _gem = TextEditingController();
  Map<String, dynamic>? _u;
  bool _busy = false;

  @override
  void dispose() {
    _q.dispose();
    _lvl.dispose();
    _gem.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    final t = _q.text.trim().replaceAll('@', '');
    if (t.isEmpty) return;
    setState(() => _busy = true);
    try {
      final n = int.tryParse(t);
      final r = n != null
          ? await supa.from('profiles').select('id,name,username,num,xp').eq('num', n).maybeSingle()
          : await supa.from('profiles').select('id,name,username,num,xp').eq('username', t).maybeSingle();
      if (!mounted) return;
      setState(() => _u = r);
      if (r == null) toast(context, 'لم أجد حساباً بهذا اليوزر أو الرقم');
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setLevel() async {
    final l = int.tryParse(_lvl.text.trim());
    if (_u == null || l == null || l < 1 || l > 100) {
      toast(context, 'اكتب مستوى بين 1 و 100');
      return;
    }
    try {
      await supa.rpc('admin_set_level', params: {'p_id': _u!['id'], 'p_level': l});
      await _find();
      if (mounted) toast(context, 'تم ضبط المستوى على $l');
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _grantGems() async {
    final a = int.tryParse(_gem.text.trim());
    if (_u == null || a == null || a == 0) {
      toast(context, 'اكتب عدد الجواهر (سالب للخصم)');
      return;
    }
    try {
      await supa.rpc('admin_grant_gems', params: {'p_user': _u!['id'], 'p_amount': a});
      if (mounted) toast(context, 'تم تعديل الجواهر بمقدار $a');
      _gem.clear();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = _u;
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('رفع مستوى أي حساب', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      const SizedBox(height: 10),
      TextField(
        controller: _q,
        textDirection: TextDirection.ltr,
        onSubmitted: (_) => _find(),
        decoration: InputDecoration(
          labelText: 'اليوزر أو رقم ID',
          suffixIcon: IconButton(onPressed: _busy ? null : _find, icon: const Icon(Icons.search_rounded)),
        ),
      ),
      if (u != null) ...[
        const SizedBox(height: 14),
        GlassCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(u['name'] as String, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            Text('@${u['username']} · ID ${u['num']}',
                textDirection: TextDirection.ltr,
                style: const TextStyle(color: Colors.white60)),
            const SizedBox(height: 6),
            Text('النقاط: ${u['xp']}', style: const TextStyle(color: Colors.white70)),
          ]),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _lvl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'المستوى الجديد (1 - 100)'),
        ),
        const SizedBox(height: 12),
        GradButton(label: 'تطبيق المستوى', icon: Icons.trending_up_rounded, onPressed: _setLevel),
        const Divider(height: 32, color: Colors.white12),
        TextField(
          controller: _gem,
          keyboardType: const TextInputType.numberWithOptions(signed: true),
          decoration: const InputDecoration(labelText: 'إضافة جواهر 💎 (سالب للخصم)'),
        ),
        const SizedBox(height: 12),
        GradButton(label: 'تطبيق الجواهر', icon: Icons.diamond_rounded, onPressed: _grantGems),
      ],
    ]);
  }
}


// ============================ المدفوعات ============================
class _PaymentsAdminTab extends StatefulWidget {
  const _PaymentsAdminTab();

  @override
  State<_PaymentsAdminTab> createState() => _PaymentsAdminTabState();
}

class _PaymentsAdminTabState extends State<_PaymentsAdminTab> {
  final _asia = TextEditingController();
  final _atheer = TextEditingController();
  final _adsPrice = TextEditingController();
  List<Map<String, dynamic>> _pending = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _asia.dispose();
    _atheer.dispose();
    _adsPrice.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final st = await supa
          .from('app_settings')
          .select()
          .inFilter('key', ['pay_asiacell', 'pay_atheer', 'ads_free_price']);
      for (final x in st) {
        final v = (x['value'] ?? '') as String;
        if (x['key'] == 'pay_asiacell') _asia.text = v;
        if (x['key'] == 'pay_atheer') _atheer.text = v;
        if (x['key'] == 'ads_free_price') _adsPrice.text = v;
      }
      final r = await supa.rpc('admin_topups', params: {'p_status': 'pending'});
      if (!mounted) return;
      setState(() {
        _pending = List<Map<String, dynamic>>.from(r as List);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      toast(context, friendlyError(e));
    }
  }

  Future<void> _saveSettings() async {
    try {
      await _setSetting('pay_asiacell', _asia.text.trim());
      await _setSetting('pay_atheer', _atheer.text.trim());
      final p = int.tryParse(_adsPrice.text.trim());
      if (p != null && p > 0) await _setSetting('ads_free_price', '$p');
      if (mounted) toast(context, 'تم الحفظ');
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _decide(Map<String, dynamic> t, bool ok) async {
    try {
      await supa.rpc('admin_decide_topup', params: {'p_id': t['id'], 'p_approve': ok});
      await _load();
      if (mounted) toast(context, ok ? 'تمت الموافقة وأضيف الرصيد' : 'تم الرفض');
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: C.pink));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('أرقام استلام التحويل', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        TextField(
            controller: _asia,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'رقم آسياسيل')),
        const SizedBox(height: 8),
        TextField(
            controller: _atheer,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'رقم أثير')),
        const SizedBox(height: 8),
        TextField(
            controller: _adsPrice,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'سعر نسخة بدون إعلانات (دينار)')),
        const SizedBox(height: 10),
        GradButton(label: 'حفظ', dense: true, onPressed: _saveSettings),
        const Divider(height: 32, color: Colors.white12),
        Text('طلبات الشحن قيد المراجعة (${_pending.length})',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (_pending.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: Text('لا توجد طلبات', style: TextStyle(color: Colors.white54))),
          ),
        for (final t in _pending)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${t['name']}  @${t['username']}',
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(
                    t['kind'] == 'gems'
                        ? '${t['gems']} جوهرة — ${t['price_iqd']} د.ع'
                        : 'نسخة بدون إعلانات — ${t['price_iqd']} د.ع',
                    style: const TextStyle(color: Color(0xFFFDE68A))),
                Text('${t['method'] == 'asiacell' ? 'آسياسيل' : 'أثير'} · رقم العملية: ${t['ref']}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                      child: GradButton(
                          label: 'موافقة', dense: true, icon: Icons.check_rounded, onPressed: () => _decide(t, true))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: GradButton(
                          label: 'رفض',
                          dense: true,
                          outlined: true,
                          icon: Icons.close_rounded,
                          onPressed: () => _decide(t, false))),
                ]),
              ]),
            ),
          ),
      ]),
    );
  }
}

// ============================ الهدايا ============================



const _missionKinds = {
  'room_visit': 'الوقت في الغرف (الوحدة = 10 دقائق)',
  'play_game': 'لعب تحديات خمّن الشخصية',
  'send_gift': 'إرسال هدايا',
  'send_msg': 'كتابة رسائل في الغرف',
  'watch_ad': 'مشاهدة إعلان من المكافآت',
};

class _MissionsAdminTab extends StatefulWidget {
  const _MissionsAdminTab();

  @override
  State<_MissionsAdminTab> createState() => _MissionsAdminTabState();
}

class _MissionsAdminTabState extends State<_MissionsAdminTab> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await supa.from('mission_pool').select().order('created_at');
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(r);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      toast(context, friendlyError(e));
    }
  }

  Future<void> _edit([Map<String, dynamic>? m]) async {
    final title = TextEditingController(text: (m?['title'] ?? '') as String);
    final target = TextEditingController(text: m == null ? '' : '${m['target']}');
    final reward = TextEditingController(text: m == null ? '' : '${m['reward']}');
    var kind = (m?['kind'] ?? 'room_visit') as String;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setS) => AlertDialog(
          title: Text(m == null ? 'مهمة جديدة' : 'تعديل المهمة'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: title, decoration: const InputDecoration(labelText: 'نص المهمة')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: kind,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'نوع المهمة'),
                items: [for (final e in _missionKinds.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setS(() => kind = v ?? kind),
              ),
              const SizedBox(height: 8),
              TextField(controller: target, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المطلوب (عدد)')),
              const SizedBox(height: 8),
              TextField(controller: reward, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المكافأة بالجواهر')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    final t = int.tryParse(target.text.trim());
    final r = int.tryParse(reward.text.trim());
    if (ok != true || title.text.trim().length < 2 || t == null || r == null || t < 1 || r < 1) return;
    try {
      final vals = {'title': title.text.trim(), 'kind': kind, 'target': t, 'reward': r};
      if (m == null) {
        await supa.from('mission_pool').insert(vals);
      } else {
        await supa.from('mission_pool').update(vals).eq('id', m['id']);
      }
      await _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _toggle(Map<String, dynamic> m, bool v) async {
    try {
      await supa.from('mission_pool').update({'active': v}).eq('id', m['id']);
      await _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _delete(Map<String, dynamic> m) async {
    try {
      await supa.from('mission_pool').delete().eq('id', m['id']);
      await _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: C.pink));
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('تختار التطبيق 3 مهام من الفعّالة كل يوم (بتوقيت بغداد) تتبدّل تلقائياً. أضف أكثر من 3 ليتنوّع اليوم.',
          style: TextStyle(color: Colors.white60, fontSize: 12)),
      const SizedBox(height: 10),
      GradButton(label: 'إضافة مهمة', icon: Icons.add_rounded, dense: true, onPressed: () => _edit()),
      const SizedBox(height: 12),
      for (final m in _rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m['title'] as String, style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text('${_missionKinds[m['kind']] ?? m['kind']} · المطلوب ${m['target']} · المكافأة ${m['reward']} 💎',
                      style: const TextStyle(color: Colors.white54, fontSize: 11)),
                ]),
              ),
              Switch(value: m['active'] == true, onChanged: (v) => _toggle(m, v)),
              IconButton(onPressed: () => _edit(m), icon: const Icon(Icons.edit_rounded, size: 20)),
              IconButton(onPressed: () => _delete(m), icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFFF8A8A))),
            ]),
          ),
        ),
    ]);
  }
}











/// يختار صورة (PNG/WebP/GIF شفافة) ويرفعها إلى game-media ويعيد رابطها، أو null عند الإلغاء.
Future<String?> _pickBadgeImage(String folder) async {
  final r = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['png', 'webp', 'gif', 'jpg', 'jpeg'],
    withData: true,
  );
  if (r == null || r.files.isEmpty) return null;
  final f = r.files.first;
  final bytes = f.bytes;
  if (bytes == null) throw 'تعذّر قراءة الملف';
  if (bytes.length > 3 * 1024 * 1024) throw 'الملف أكبر من 3 ميغا';
  final ext = extOf(f.name, ['png', 'webp', 'gif', 'jpg', 'jpeg'], 'png');
  return uploadMedia(
      bucket: 'game-media',
      folder: folder,
      bytes: bytes,
      ext: ext,
      contentType: 'image/${ext == 'jpg' ? 'jpeg' : ext}');
}

/// الألقاب والمستويات: تعديل الصور والأسماء وإضافة ألقاب ومستويات جديدة.
class _BadgesAdminTab extends StatefulWidget {
  const _BadgesAdminTab();

  @override
  State<_BadgesAdminTab> createState() => _BadgesAdminTabState();
}

class _BadgesAdminTabState extends State<_BadgesAdminTab> {
  int _mode = 0; // 0 ألقاب، 1 مستويات
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    BadgeStore.ensure(force: true);
    BadgeStore.version.addListener(_r);
  }

  @override
  void dispose() {
    BadgeStore.version.removeListener(_r);
    super.dispose();
  }

  void _r() {
    if (mounted) setState(() {});
  }

  Future<void> _editTitle(TitleDef? t) async {
    final isNew = t == null;
    final all = BadgeStore.titles;
    final newIdx = all.fold<int>(24, (m, e) => e.idx > m ? e.idx : m) + 1;
    final idx = t?.idx ?? newIdx;
    final name = TextEditingController(text: t?.name ?? '');
    final from = TextEditingController(text: '${t?.fromLevel ?? (all.isEmpty ? 1 : all.last.fromLevel + 2)}');
    String? url = t?.url;
    var up = false;
    final action = await showDialog<String>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setS) => AlertDialog(
          title: Text(isNew ? 'لقب جديد' : 'تعديل اللقب'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم اللقب')),
              const SizedBox(height: 8),
              TextField(
                  controller: from,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'يبدأ من المستوى')),
              const SizedBox(height: 12),
              SizedBox(
                height: 70,
                child: url != null
                    ? Image.network(url!, fit: BoxFit.contain)
                    : (t != null
                        ? TitleDefImage(def: t, height: 64)
                        : const Center(child: Text('لا توجد صورة'))),
              ),
              OutlinedButton.icon(
                onPressed: up
                    ? null
                    : () async {
                        setS(() => up = true);
                        try {
                          final u = await _pickBadgeImage('titles');
                          if (u != null) url = u;
                        } catch (e) {
                          if (mounted) toast(context, 'فشل الرفع: ${friendlyError(e)}');
                        }
                        setS(() => up = false);
                      },
                icon: const Icon(Icons.upload_rounded),
                label: const Text('رفع صورة اللقب'),
              ),
            ]),
          ),
          actions: [
            if (!isNew)
              TextButton(
                  onPressed: () => Navigator.pop(d, 'del'),
                  child: Text(idx < 25 ? 'استعادة الأصلي' : 'حذف')),
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('إلغاء')),
            FilledButton(onPressed: up ? null : () => Navigator.pop(d, 'save'), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (action == null) return;
    try {
      if (action == 'del') {
        await supa.from('title_defs').delete().eq('idx', idx);
      } else {
        final n = name.text.trim();
        final fl = int.tryParse(from.text.trim());
        if (n.length < 2 || fl == null || fl < 1 || fl > 500) {
          if (mounted) toast(context, 'اكتب اسماً ومستوى صحيحاً (1 إلى 500)');
          return;
        }
        await supa.from('title_defs').upsert({'idx': idx, 'from_level': fl, 'name': n, 'image_url': url ?? ''});
      }
      await BadgeStore.ensure(force: true);
      if (mounted) toast(context, 'تم الحفظ');
    } catch (e) {
      if (mounted) toast(context, 'فشل الحفظ: ${friendlyError(e)}');
    }
  }

  Future<void> _setLevelImage(int level) async {
    setState(() => _busy = true);
    try {
      final u = await _pickBadgeImage('levels');
      if (u == null) return;
      await supa.from('level_badges').upsert({'level': level, 'image_url': u});
      await BadgeStore.ensure(force: true);
      if (mounted) toast(context, 'تم حفظ شكل المستوى $level');
    } catch (e) {
      if (mounted) toast(context, 'فشل الرفع: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _levelDialog(int level) async {
    final custom = BadgeStore.levelUrls.containsKey(level);
    final a = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('المستوى $level'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          LevelBadge(level: level, size: 110),
          const SizedBox(height: 8),
          Text('يحتاج ${50 * (level - 1) * (level - 1)} نقطة',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ]),
        actions: [
          if (custom)
            TextButton(onPressed: () => Navigator.pop(d, 'reset'), child: const Text('استعادة الأصلية')),
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('إغلاق')),
          FilledButton(onPressed: () => Navigator.pop(d, 'up'), child: const Text('تغيير الصورة')),
        ],
      ),
    );
    if (a == 'up') {
      await _setLevelImage(level);
    } else if (a == 'reset') {
      try {
        await supa.from('level_badges').delete().eq('level', level);
        await BadgeStore.ensure(force: true);
      } catch (e) {
        if (mounted) toast(context, friendlyError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final titles = BadgeStore.titles;
    final maxL = BadgeStore.maxLevel;
    return ListView(padding: const EdgeInsets.all(16), children: [
      SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 0, label: Text('الألقاب')),
          ButtonSegment(value: 1, label: Text('المستويات')),
        ],
        selected: {_mode},
        onSelectionChanged: (v) => setState(() => _mode = v.first),
      ),
      const SizedBox(height: 12),
      if (_mode == 0) ...[
        FilledButton.icon(
          onPressed: () => _editTitle(null),
          icon: const Icon(Icons.add_rounded),
          label: const Text('إضافة لقب جديد'),
        ),
        const SizedBox(height: 10),
        for (final t in titles)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GlassCard(
              child: ListTile(
                leading: SizedBox(width: 70, child: TitleDefImage(def: t, height: 40)),
                title: Text(t.name),
                subtitle: Text('من المستوى ${t.fromLevel}'),
                trailing: const Icon(Icons.edit_rounded, size: 18),
                onTap: () => _editTitle(t),
              ),
            ),
          ),
      ] else ...[
        FilledButton.icon(
          onPressed: _busy ? null : () => _setLevelImage(maxL + 1),
          icon: const Icon(Icons.add_rounded),
          label: Text('إضافة المستوى ${maxL + 1}'),
        ),
        const SizedBox(height: 6),
        const Text('اضغط على أي مستوى لتغيير شكله. المستوى L يحتاج 50×(L-1)² نقطة.',
            style: TextStyle(fontSize: 12, color: Colors.white60)),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 5,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            for (var l = 1; l <= maxL; l++)
              GestureDetector(
                onTap: () => _levelDialog(l),
                child: Column(children: [
                  Expanded(child: LevelBadge(level: l, size: 52)),
                  Text('$l${BadgeStore.levelUrls.containsKey(l) ? ' ✎' : ''}',
                      style: const TextStyle(fontSize: 11, color: Colors.white70)),
                ]),
              ),
          ],
        ),
      ],
    ]);
  }
}


// ===================== شرح طريقة اللعب =====================
class _TutorialAdminTab extends StatefulWidget {
  const _TutorialAdminTab();

  @override
  State<_TutorialAdminTab> createState() => _TutorialAdminTabState();
}

class _TutorialAdminTabState extends State<_TutorialAdminTab> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await supa.from('tutorial_slides').select().order('sort');
      if (mounted) setState(() => _items = List<Map<String, dynamic>>.from(r));
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    try {
      final next = _items.isEmpty ? 1 : ((_items.last['sort'] as num).toInt() + 1);
      await supa.from('tutorial_slides').insert({'sort': next, 'title': 'عنوان جديد', 'body': 'اكتب الشرح هنا'});
      await _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _update(Map<String, dynamic> s, Map<String, dynamic> v) async {
    try {
      await supa.from('tutorial_slides').update(v).eq('id', s['id']);
      await _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _image(Map<String, dynamic> s) async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1400, imageQuality: 88);
    if (f == null) return;
    setState(() => _busy = s['id'] as String);
    try {
      final url = await _uploadImage(f, 'tutorial');
      await _update(s, {'image_url': url});
    } catch (e) {
      if (mounted) toast(context, 'فشل الرفع: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _edit(Map<String, dynamic> s) async {
    final t = TextEditingController(text: (s['title'] ?? '') as String);
    final b = TextEditingController(text: (s['body'] ?? '') as String);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('تعديل الشريحة'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: t, decoration: const InputDecoration(labelText: 'العنوان')),
            const SizedBox(height: 10),
            TextField(controller: b, maxLines: 5, decoration: const InputDecoration(labelText: 'الشرح')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok == true) await _update(s, {'title': t.text.trim(), 'body': b.text.trim()});
  }

  Future<void> _move(int i, int dir) async {
    final j = i + dir;
    if (j < 0 || j >= _items.length) return;
    final a = _items[i], b = _items[j];
    try {
      await supa.from('tutorial_slides').update({'sort': b['sort']}).eq('id', a['id']);
      await supa.from('tutorial_slides').update({'sort': a['sort']}).eq('id', b['id']);
      await _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _delete(Map<String, dynamic> s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('حذف الشريحة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await supa.from('tutorial_slides').delete().eq('id', s['id']);
      await _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: C.pink));
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('تظهر هذه الشرائح للمستخدم عند أول دخول، وبزر «؟» في صفحة الألعاب.',
          style: TextStyle(color: Colors.white60)),
      const SizedBox(height: 10),
      GradButton(label: 'إضافة شريحة', icon: Icons.add_rounded, onPressed: _add),
      const SizedBox(height: 12),
      for (var i = 0; i < _items.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GlassCard(
            child: Row(children: [
              GestureDetector(
                onTap: _busy == null ? () => _image(_items[i]) : null,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 72,
                    height: 72,
                    color: Colors.white10,
                    child: _busy == _items[i]['id']
                        ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                        : ((_items[i]['image_url'] ?? '') as String).isEmpty
                            ? const Icon(Icons.add_photo_alternate_outlined)
                            : Image.network(_items[i]['image_url'] as String, fit: BoxFit.cover),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text((_items[i]['title'] ?? '') as String,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text((_items[i]['body'] ?? '') as String,
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                ]),
              ),
              Column(children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.keyboard_arrow_up_rounded), onPressed: () => _move(i, -1)),
                  IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.keyboard_arrow_down_rounded), onPressed: () => _move(i, 1)),
                ]),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.edit_rounded, size: 20), onPressed: () => _edit(_items[i])),
                  IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.redAccent), onPressed: () => _delete(_items[i])),
                ]),
              ]),
            ]),
          ),
        ),
    ]);
  }
}

// ===================== الجولات والأسعار =====================
class _PlaySettingsTab extends StatefulWidget {
  const _PlaySettingsTab();

  @override
  State<_PlaySettingsTab> createState() => _PlaySettingsTabState();
}

class _PlaySettingsTabState extends State<_PlaySettingsTab> {
  static const _fields = <(String, String, String)>[
    ('free_rounds_daily', 'الجولات المجانية يومياً', '5'),
    ('ad_round_max', 'أقصى جولات إضافية بالإعلانات يومياً', '10'),
    ('ad_gems_amount', 'الماسات مقابل إعلان واحد', '10'),
    ('ad_gems_max', 'أقصى إعلانات الماسات يومياً', '20'),
    ('pass_day_price', 'سعر اللعب المفتوح ليوم (ماسات)', '100'),
    ('pass_week_price', 'سعر الأسبوع (ماسات)', '500'),
    ('pass_month_price', 'سعر الشهر (ماسات)', '1500'),
  ];
  final _c = {for (final f in _fields) f.$1: TextEditingController()};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await supa.from('app_settings').select('key,value').inFilter('key', [for (final f in _fields) f.$1]);
      final m = {for (final x in r) x['key'] as String: x['value'] as String};
      for (final f in _fields) {
        _c[f.$1]!.text = m[f.$1] ?? f.$3;
      }
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      for (final f in _fields) {
        final v = int.tryParse(_c[f.$1]!.text.trim());
        if (v == null || v < 0) {
          toast(context, 'قيمة غير صحيحة: ${f.$2}');
          return;
        }
        await _setSetting(f.$1, '$v');
      }
      if (mounted) toast(context, 'تم الحفظ');
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: C.pink));
    return ListView(padding: const EdgeInsets.all(16), children: [
      for (final f in _fields)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: _c[f.$1],
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: f.$2),
          ),
        ),
      GradButton(label: _saving ? 'جارٍ الحفظ…' : 'حفظ', onPressed: _saving ? null : _save),
    ]);
  }
}
