import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'main.dart';
import 'theme.dart';

const _maxSongBytes = 15 * 1024 * 1024;

/// أغاني المستخدمين: يرفع أي مستخدم أغنية من هاتفه فتظهر للجميع،
/// ويختار صاحب الروم (أو مشرفوه) أغنية لتُشغَّل في الغرفة.
class SongsScreen extends StatefulWidget {
  /// عند true: الضغط على أغنية يعيدها لمن فتح الشاشة (اختيار أغنية للروم).
  final bool pick;
  const SongsScreen({super.key, this.pick = false});

  @override
  State<SongsScreen> createState() => _SongsScreenState();
}

class _SongsScreenState extends State<SongsScreen> {
  List<Map<String, dynamic>> _songs = [];
  final Map<String, String> _names = {};
  bool _loading = true;
  bool _uploading = false;
  String _q = '';
  final AudioPlayer _preview = AudioPlayer();
  String? _previewing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _preview.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = List<Map<String, dynamic>>.from(
          await supa.from('songs').select().order('created_at', ascending: false).limit(300));
      final ids = rows.map((r) => r['owner'] as String).toSet().toList();
      if (ids.isNotEmpty) {
        final ps = await supa.from('profiles').select('id,name').inFilter('id', ids);
        for (final p in ps) {
          _names[p['id'] as String] = (p['name'] ?? '') as String;
        }
      }
      if (mounted) {
        setState(() {
          _songs = rows;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        toast(context, friendlyError(e));
      }
    }
  }

  Future<void> _togglePreview(Map<String, dynamic> s) async {
    final id = s['id'] as String;
    try {
      if (_previewing == id) {
        await _preview.stop();
        setState(() => _previewing = null);
      } else {
        setState(() => _previewing = id);
        await _preview.play(UrlSource(s['url'] as String));
      }
    } catch (_) {
      if (mounted) setState(() => _previewing = null);
    }
  }

  Future<void> _upload() async {
    if (_uploading) return;
    final res = await FilePicker.platform.pickFiles(type: FileType.audio);
    final f = res?.files.single;
    if (f == null || f.path == null) return;
    if (f.size > _maxSongBytes) {
      if (mounted) toast(context, 'حجم الأغنية أكبر من 15 ميغابايت');
      return;
    }
    final base = f.name.contains('.') ? f.name.substring(0, f.name.lastIndexOf('.')) : f.name;
    final title = TextEditingController(text: base);
    final artist = TextEditingController();
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('نشر أغنية'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, maxLength: 80, decoration: const InputDecoration(labelText: 'اسم الأغنية')),
          TextField(controller: artist, maxLength: 60, decoration: const InputDecoration(labelText: 'الفنان (اختياري)')),
          const SizedBox(height: 4),
          const Text('تأكد أن لديك حق نشر هذه الأغنية. ستظهر لكل مستخدمي التطبيق.',
              style: TextStyle(fontSize: 12, color: Colors.white60)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('نشر')),
        ],
      ),
    );
    if (ok != true || title.text.trim().isEmpty) return;
    setState(() => _uploading = true);
    try {
      final ext = f.extension != null && f.extension!.length <= 5 ? f.extension!.toLowerCase() : 'mp3';
      final path = '$myId/${DateTime.now().millisecondsSinceEpoch}.$ext';
      final mime = switch (ext) {
        'mp3' => 'audio/mpeg',
        'm4a' || 'aac' => 'audio/mp4',
        'wav' => 'audio/wav',
        'ogg' || 'opus' => 'audio/ogg',
        _ => 'audio/mpeg',
      };
      await supa.storage.from('songs').upload(path, File(f.path!),
          fileOptions: FileOptions(contentType: mime, upsert: false));
      final url = supa.storage.from('songs').getPublicUrl(path);
      await supa.from('songs').insert({
        'owner': myId,
        'title': title.text.trim(),
        'artist': artist.text.trim(),
        'url': url,
        'path': path,
      });
      if (mounted) toast(context, 'تم نشر الأغنية 🎵');
      await _load();
    } catch (e) {
      if (mounted) {
        toast(context,
            e.toString().contains('row-level security') ? 'وصلت للحد الأقصى (30 أغنية) أو لا تملك الصلاحية' : friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('حذف الأغنية؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await supa.from('songs').delete().eq('id', s['id']);
      try {
        await supa.storage.from('songs').remove([s['path'] as String]);
      } catch (_) {}
      await _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final shown = q.isEmpty
        ? _songs
        : _songs
            .where((s) =>
                (s['title'] as String).toLowerCase().contains(q) ||
                (s['artist'] as String).toLowerCase().contains(q))
            .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pick ? 'اختر أغنية للروم' : 'الأغاني', style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploading ? null : _upload,
        backgroundColor: C.violet,
        icon: _uploading
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.upload_rounded),
        label: Text(_uploading ? 'جارٍ الرفع...' : 'نشر أغنية'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'ابحث باسم الأغنية أو الفنان'),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: C.pink))
              : shown.isEmpty
                  ? const Center(
                      child: Text('لا توجد أغاني بعد\nانشر أول أغنية!',
                          textAlign: TextAlign.center, style: TextStyle(color: Colors.white60, fontSize: 16)))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      itemCount: shown.length,
                      itemBuilder: (_, i) {
                        final s = shown[i];
                        final mine = s['owner'] == myId;
                        final playing = _previewing == s['id'];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GlassCard(
                            onTap: widget.pick ? () => Navigator.pop(context, s) : () => _togglePreview(s),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Row(children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: const BoxDecoration(gradient: brandGradient, shape: BoxShape.circle),
                                child: Icon(widget.pick
                                    ? Icons.music_note_rounded
                                    : (playing ? Icons.stop_rounded : Icons.play_arrow_rounded)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(s['title'] as String,
                                      maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w800)),
                                  Text(
                                      [
                                        if ((s['artist'] as String).isNotEmpty) s['artist'],
                                        'نشرها ${_names[s['owner']] ?? ''}',
                                      ].join(' · '),
                                      maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white60, fontSize: 12)),
                                ]),
                              ),
                              if (mine)
                                IconButton(
                                    onPressed: () => _delete(s),
                                    icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF8A8A))),
                            ]),
                          ),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}
