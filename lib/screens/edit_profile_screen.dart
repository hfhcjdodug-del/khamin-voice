import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../main.dart';
import '../media.dart';
import '../theme.dart';
import 'profile_actions.dart';

const _ink = Color(0xFF1F1B2E);
const _sub = Color(0xFF9AA0AE);
const _line = Color(0xFFEDEEF3);
const _violet = Color(0xFF8B5CF6);
const _orange = Color(0xFFFF9F43);

/// شاشة تعديل الملف الشخصي (تصميم فاتح): نسبة الاكتمال، الصورة، جدار الصور، الحقول، العلامات.
class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> profile;
  const EditProfileScreen({super.key, required this.profile});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late Map<String, dynamic> _p;
  bool _busy = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _p = Map<String, dynamic>.from(widget.profile);
  }

  List<String> _list(String k) => ((_p[k] ?? const []) as List).map((e) => '$e').toList();
  String _s(String k) => ((_p[k] ?? '') as Object).toString();

  int get _pct {
    var s = 0;
    if (_s('avatar_url').isNotEmpty) s += 20;
    final ph = _list('photos').length;
    if (ph >= 1) s += 10;
    if (ph >= 3) s += 20;
    if (_p['birthday'] != null || _p['age'] != null) s += 10;
    if (_s('bio').isNotEmpty) s += 10;
    final tg = _list('tags').length;
    if (tg >= 1) s += 10;
    if (tg >= 3) s += 10;
    if (_s('region').isNotEmpty || _s('nationality').isNotEmpty) s += 10;
    return s;
  }

  Future<bool> _save(Map<String, dynamic> patch) async {
    try {
      await supa.from('profiles').update(patch).eq('id', myId);
      setState(() {
        _p.addAll(patch);
        _changed = true;
      });
      return true;
    } catch (e) {
      final m = e.toString();
      if (mounted) {
        toast(
            context,
            m.contains('photos') || m.contains('tags') || m.contains('birthday') || m.contains('column')
                ? 'نفّذ ملف voice_v12.sql في Supabase أولاً'
                : friendlyError(e));
      }
      return false;
    }
  }

  Future<String?> _ask(String title, String init, {int max = 40, int lines = 1, TextInputType? kb}) {
    final c = TextEditingController(text: init);
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: max,
          maxLines: lines,
          keyboardType: kb,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('حفظ')),
        ],
      ),
    );
  }

  Future<void> _editText(String col, String title, {int max = 40, int lines = 1, int min = 0}) async {
    final v = await _ask(title, _s(col), max: max, lines: lines);
    if (v == null) return;
    if (v.length < min) {
      if (mounted) toast(context, 'النص قصير');
      return;
    }
    await _save({col: v});
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final cur = DateTime.tryParse(_s('birthday'));
    final d = await showDatePicker(
      context: context,
      initialDate: cur ?? DateTime(now.year - 20, 1, 1),
      firstDate: DateTime(1940),
      lastDate: DateTime(now.year - 13, now.month, now.day),
    );
    if (d == null) return;
    var age = now.year - d.year;
    if (now.month < d.month || (now.month == d.month && now.day < d.day)) age--;
    final iso = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    await _save({'birthday': iso, 'age': age});
  }

  Future<void> _pickGender() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: const Text('ذكر'), onTap: () => Navigator.pop(c, 'ذكر')),
          ListTile(title: const Text('أنثى'), onTap: () => Navigator.pop(c, 'أنثى')),
        ]),
      ),
    );
    if (v != null) await _save({'gender': v});
  }

  Future<void> _avatar() async {
    if (await changeAvatar(context)) {
      try {
        final r = await supa.from('profiles').select('avatar_url').eq('id', myId).single();
        setState(() {
          _p['avatar_url'] = r['avatar_url'];
          _changed = true;
        });
      } catch (_) {}
    }
  }

  Future<void> _addPhoto() async {
    final photos = _list('photos');
    if (photos.length >= 9) {
      toast(context, 'الحد الأقصى 9 صور');
      return;
    }
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 85);
    if (f == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await f.readAsBytes();
      final ext = extOf(f.name, ['jpg', 'jpeg', 'png', 'webp'], 'jpg');
      final url = await uploadMedia(
        bucket: 'avatars',
        folder: myId,
        bytes: bytes,
        ext: ext,
        contentType: 'image/${ext == 'jpg' ? 'jpeg' : ext}',
      );
      await _save({'photos': [...photos, url]});
    } catch (e) {
      if (mounted) toast(context, 'تعذّر رفع الصورة: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _photoMenu(int i) async {
    final photos = _list('photos');
    final act = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (i > 0)
            ListTile(
                leading: const Icon(Icons.arrow_upward_rounded),
                title: const Text('نقلها إلى الأول'),
                onTap: () => Navigator.pop(c, 'first')),
          ListTile(
              leading: const Icon(Icons.delete_rounded, color: Colors.redAccent),
              title: const Text('حذف الصورة'),
              onTap: () => Navigator.pop(c, 'del')),
        ]),
      ),
    );
    if (act == 'del') {
      photos.removeAt(i);
      await _save({'photos': photos});
    } else if (act == 'first') {
      final x = photos.removeAt(i);
      await _save({'photos': [x, ...photos]});
    }
  }

  Future<void> _addTag() async {
    final tags = _list('tags');
    if (tags.length >= 6) {
      toast(context, 'الحد الأقصى 6 علامات');
      return;
    }
    final v = await _ask('علامة جديدة', '', max: 14);
    if (v == null || v.isEmpty) return;
    if (tags.contains(v)) return;
    await _save({'tags': [...tags, v]});
  }

  Future<void> _pickHobbies() async {
    final sel = <String>{..._list('hobbies')};
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('الهوايات المفضلة (حتى 8)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final h in hobbyOptions)
                FilterChip(
                  label: Text(h),
                  selected: sel.contains(h),
                  onSelected: (v) => setS(() {
                    if (v && sel.length < 8) sel.add(h);
                    if (!v) sel.remove(h);
                  }),
                ),
            ]),
            const SizedBox(height: 12),
            SizedBox(
                width: double.infinity,
                child: GradButton(label: 'حفظ', onPressed: () => Navigator.pop(c, true))),
          ]),
        ),
      ),
    );
    if (ok == true) await _save({'hobbies': sel.toList()});
  }

  // ---------- عناصر الواجهة ----------
  Widget _row(String label, String value, VoidCallback onTap, {bool last = false}) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
              border: last ? null : const Border(bottom: BorderSide(color: _line))),
          child: Row(children: [
            Text(label, style: const TextStyle(color: _sub, fontSize: 16)),
            const SizedBox(width: 16),
            Expanded(
              child: Text(value.isEmpty ? 'اضغط للإضافة' : value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                      color: value.isEmpty ? _sub : _ink,
                      fontSize: 16,
                      fontWeight: value.isEmpty ? FontWeight.w400 : FontWeight.w600)),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_left_rounded, color: _sub),
          ]),
        ),
      );

  Widget _photoWall() {
    final photos = _list('photos');
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: [
        for (var i = 0; i < photos.length; i++)
          GestureDetector(
            onTap: () => _photoMenu(i),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(photos[i],
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: _line)),
            ),
          ),
        if (photos.length < 9)
          GestureDetector(
            onTap: _busy ? null : _addPhoto,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF7F7FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD9DBE3)),
              ),
              child: _busy
                  ? const Center(
                      child: SizedBox(
                          width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))
                  : const Icon(Icons.add_rounded, size: 38, color: _sub),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final pct = _pct;
    final tags = _list('tags');
    final hobbies = _list('hobbies');
    final birthday = DateTime.tryParse(_s('birthday'));
    final bStr = birthday == null
        ? (_p['age'] != null ? 'العمر ${_p['age']}' : '')
        : '${birthday.day.toString().padLeft(2, '0')}/${birthday.month.toString().padLeft(2, '0')}/${birthday.year}';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: IconTheme(
          data: const IconThemeData(color: _ink),
          child: DefaultTextStyle.merge(
            style: const TextStyle(color: _ink),
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                children: [
                  Row(children: [
                    IconButton(
                        onPressed: () => Navigator.pop(context, _changed),
                        icon: const Icon(Icons.chevron_right_rounded, size: 32)),
                    const Expanded(
                        child: Text('تعديل',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
                    const SizedBox(width: 48),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    const Text('إكمال المعلومات',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: pct / 100,
                          minHeight: 8,
                          backgroundColor: const Color(0xFFEDEEF3),
                          valueColor: AlwaysStoppedAnimation(pct >= 100 ? _violet : _orange),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('$pct%', style: const TextStyle(fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 22),
                  Center(
                    child: Stack(children: [
                      Avatar(name: _s('name'), url: _p['avatar_url'] as String?, size: 112),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        child: GestureDetector(
                          onTap: _avatar,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _violet,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                            ),
                            child: const Icon(Icons.photo_camera_rounded, size: 18, color: Colors.white),
                          ),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  const Center(
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: 'الصورة الحقيقية ', style: TextStyle(color: _orange, fontWeight: FontWeight.w700)),
                      TextSpan(text: 'تجذب المزيد من الأشخاص!'),
                    ])),
                  ),
                  const SizedBox(height: 18),
                  Row(children: [
                    const Text('جداري للصور', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                          _list('photos').length >= 3 ? '' : 'أضف 3 صور لزيادة اكتمال ملفك',
                          style: const TextStyle(color: _orange, fontSize: 12)),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  _photoWall(),
                  const SizedBox(height: 6),
                  const Text('اضغط على الصورة لحذفها أو نقلها إلى الأول.',
                      style: TextStyle(color: _sub, fontSize: 12)),
                  const SizedBox(height: 10),
                  const Divider(color: _line, height: 24),
                  _row('الاسم', _s('name'), () => _editText('name', 'الاسم', max: 40, min: 2)),
                  _row('عيد ميلاد', bStr, _pickBirthday),
                  _row('حولك', _s('bio'), () => _editText('bio', 'صف نفسك في جملة واحدة', max: 150, lines: 3)),
                  _row('اليوزر', _s('username').isEmpty ? '' : '@${_s('username')}',
                      () => _editText('username', 'اليوزر (إنكليزي)', max: 20, min: 3)),
                  _row('الجنس', _s('gender'), _pickGender),
                  _row('الجنسية', _s('nationality'), () => _editText('nationality', 'الجنسية', max: 30)),
                  _row('المنطقة', _s('region'), () => _editText('region', 'المنطقة', max: 30)),
                  _row('اللغة', _s('language'), () => _editText('language', 'اللغة', max: 30)),
                  _row('الحالة الاجتماعية', _s('marital'), () => _editText('marital', 'الحالة الاجتماعية', max: 20)),
                  _row('الهوايات', hobbies.join('، '), _pickHobbies),
                  _row('الاهتمامات', _s('interests'),
                      () => _editText('interests', 'الاهتمامات (جملة قصيرة)', max: 100), last: true),
                  const SizedBox(height: 18),
                  Row(children: [
                    const Text('علامات', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(width: 10),
                    Text(tags.length >= 3 ? '' : 'أضف 3 علامات لزيادة اكتمال ملفك',
                        style: const TextStyle(color: _orange, fontSize: 12)),
                  ]),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final t in tags)
                      Container(
                        padding: const EdgeInsets.fromLTRB(8, 6, 14, 6),
                        decoration: BoxDecoration(
                            color: const Color(0xFFF3F0FF), borderRadius: BorderRadius.circular(20)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          GestureDetector(
                            onTap: () => _save({'tags': tags.where((x) => x != t).toList()}),
                            child: const Icon(Icons.close_rounded, size: 16, color: _violet),
                          ),
                          const SizedBox(width: 4),
                          Text(t, style: const TextStyle(color: _violet, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    GestureDetector(
                      onTap: _addTag,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                            color: const Color(0xFFF3F3F6), borderRadius: BorderRadius.circular(22)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: const [
                          Icon(Icons.add_rounded, size: 18, color: _violet),
                          SizedBox(width: 4),
                          Text('إضافة العلامة', style: TextStyle(fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
