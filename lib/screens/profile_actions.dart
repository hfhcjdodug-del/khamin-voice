import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../main.dart';
import '../media.dart';
import '../theme.dart';

Future<bool> _pickAndSet(BuildContext context, String column, String prefix, int maxW) async {
  final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: maxW.toDouble(), imageQuality: 85);
  if (f == null) return false;
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
    await supa.from('profiles').update({column: url}).eq('id', myId);
    if (context.mounted) toast(context, prefix);
    return true;
  } catch (e) {
    if (context.mounted) toast(context, 'تعذّر رفع الصورة: ${friendlyError(e)}');
    return false;
  }
}

Future<bool> changeAvatar(BuildContext context) =>
    _pickAndSet(context, 'avatar_url', 'تم تغيير الصورة الشخصية', 900);

Future<bool> changeCover(BuildContext context) =>
    _pickAndSet(context, 'cover_url', 'تم تغيير صورة الغلاف', 1400);

const hobbyOptions = [
  'ألعاب', 'أنمي', 'كرة القدم', 'موسيقى', 'قراءة', 'برمجة',
  'أفلام', 'سفر', 'تصوير', 'رسم', 'طبخ', 'رياضة',
];

/// نافذة تعديل الملف: الاسم، اليوزر، النبذة، الهوايات، الاهتمامات.
Future<bool> showEditProfile(BuildContext context, Map<String, dynamic> p) async {
  final name = TextEditingController(text: p['name'] as String);
  final user = TextEditingController(text: p['username'] as String);
  final bio = TextEditingController(text: (p['bio'] ?? '') as String);
  final interests = TextEditingController(text: (p['interests'] ?? '') as String);
  final hobbies = <String>{...((p['hobbies'] ?? []) as List).cast<String>()};
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(c).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('تعديل الملف الشخصي',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(
                controller: name,
                maxLength: 40,
                decoration: const InputDecoration(labelText: 'الاسم')),
            TextField(
              controller: user,
              maxLength: 20,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(labelText: 'اليوزر (إنكليزي)', prefixText: '@'),
            ),
            TextField(
                controller: bio,
                maxLength: 150,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'نبذة عنك')),
            const SizedBox(height: 8),
            const Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text('الهوايات المفضلة (حتى 8)',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final h in hobbyOptions)
                FilterChip(
                  label: Text(h),
                  selected: hobbies.contains(h),
                  onSelected: (v) => setS(() {
                    if (v && hobbies.length < 8) hobbies.add(h);
                    if (!v) hobbies.remove(h);
                  }),
                ),
            ]),
            TextField(
                controller: interests,
                maxLength: 100,
                decoration: const InputDecoration(labelText: 'الاهتمامات (جملة قصيرة)')),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: GradButton(label: 'حفظ', onPressed: () => Navigator.pop(c, true)),
            ),
          ]),
        ),
      ),
    ),
  );
  if (ok != true) return false;
  final n = name.text.trim();
  if (n.length < 2) {
    if (context.mounted) toast(context, 'الاسم قصير');
    return false;
  }
  try {
    await supa.from('profiles').update({
      'name': n,
      'username': user.text.trim(),
      'bio': bio.text.trim(),
      'hobbies': hobbies.toList(),
      'interests': interests.text.trim(),
    }).eq('id', myId);
    if (context.mounted) toast(context, 'تم الحفظ');
    return true;
  } catch (e) {
    if (context.mounted) toast(context, friendlyError(e));
    return false;
  }
}
