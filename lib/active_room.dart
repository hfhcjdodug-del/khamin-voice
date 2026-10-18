import 'package:flutter/foundation.dart';

class ActiveRoomData {
  final String roomId;
  final String title;
  final String topic;
  final bool isHost;
  final String? hostId;
  final String? hostAvatar;
  const ActiveRoomData({
    required this.roomId,
    required this.title,
    required this.topic,
    required this.isHost,
    this.hostId,
    this.hostAvatar,
  });
}

/// الغرفة الحالية التي أنا فيها. تبقى شغّالة (الصوت والحضور) حين أصغّرها وأتصفح التطبيق،
/// ولا أخرج منها إلا بالخروج الصريح أو بدخول غرفة أخرى.
class ActiveRoom {
  static final ValueNotifier<ActiveRoomData?> current = ValueNotifier(null);
  static final ValueNotifier<bool> expanded = ValueNotifier(false);

  static Future<void> open(ActiveRoomData d) async {
    final cur = current.value;
    if (cur != null && cur.roomId == d.roomId) {
      expanded.value = true;
      return;
    }
    if (cur != null) {
      // الخروج من الغرفة القديمة أولاً ثم الدخول للجديدة
      expanded.value = false;
      current.value = null;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    current.value = d;
    expanded.value = true;
  }

  static void minimize() => expanded.value = false;

  static void leave() {
    expanded.value = false;
    current.value = null;
  }
}
