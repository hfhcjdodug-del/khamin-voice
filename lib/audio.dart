import 'package:audioplayers/audioplayers.dart';

/// أغنية خلفية للألعاب: تُشغَّل في صالة اللعبة وتتوقف عند دخول غرفة أو مباراة.
class Music {
  static AudioPlayer? _p;
  static String? _url;

  static Future<void> play(String? url) async {
    if (url == null || url.isEmpty) return;
    if (_url == url) return;
    _url = url;
    try {
      final p = _p ??= AudioPlayer();
      await p.setReleaseMode(ReleaseMode.loop);
      await p.setVolume(0.55);
      await p.play(UrlSource(url));
    } catch (_) {}
  }

  static Future<void> stop() async {
    _url = null;
    try {
      await _p?.stop();
    } catch (_) {}
  }
}
