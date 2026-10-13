import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'main.dart';

/// يرفع ملفاً إلى Storage ويعيد رابطه العام.
Future<String> uploadMedia({
  required String bucket,
  required String folder,
  required Uint8List bytes,
  required String ext,
  required String contentType,
}) async {
  final path = '$folder/${DateTime.now().millisecondsSinceEpoch}_${bytes.length}.$ext';
  await supa.storage.from(bucket).uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(contentType: contentType, upsert: true),
      );
  return supa.storage.from(bucket).getPublicUrl(path);
}

String extOf(String name, List<String> allowed, String fallback) {
  final e = name.contains('.') ? name.split('.').last.toLowerCase() : fallback;
  return allowed.contains(e) ? e : fallback;
}
