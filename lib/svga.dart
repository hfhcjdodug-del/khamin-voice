import 'dart:async';
import 'dart:io' show ZLibCodec;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

/// مشغّل SVGA 2.0 مبسّط (صور + تحويلات + شفافية). لا يعتمد على أي حزمة خارجية.
/// لا يدعم الأشكال المتجهة ولا الأقنعة (matte) — يتجاهلها.

class _R {
  final Uint8List b;
  int i = 0;
  _R(this.b);
  bool get more => i < b.length;
  int varint() {
    var r = 0, s = 0;
    while (true) {
      final x = b[i++];
      r |= (x & 0x7f) << s;
      s += 7;
      if (x < 0x80) return r;
    }
  }

  double f32() {
    final v = ByteData.sublistView(b, i, i + 4).getFloat32(0, Endian.little);
    i += 4;
    return v;
  }

  Uint8List bytes() {
    final l = varint();
    final v = Uint8List.sublistView(b, i, i + l);
    i += l;
    return v;
  }

  void skip(int wire) {
    if (wire == 0) {
      varint();
    } else if (wire == 1) {
      i += 8;
    } else if (wire == 2) {
      i += varint();
    } else if (wire == 5) {
      i += 4;
    }
  }
}

class _Frame {
  double alpha = 0, lx = 0, ly = 0, lw = 0, lh = 0;
  Float64List? m; // مصفوفة 4x4 جاهزة
}

class _Sprite {
  String key = '';
  final List<_Frame> frames = [];
}

class SvgaMovie {
  double w = 0, h = 0;
  int fps = 20, frames = 1;
  final Map<String, ui.Image> images = {};
  final List<_Sprite> sprites = [];
  Duration get duration => Duration(milliseconds: (frames * 1000 / (fps <= 0 ? 20 : fps)).round());

  static _Frame _frame(Uint8List b) {
    final r = _R(b);
    final f = _Frame();
    double a = 1, bb = 0, c = 0, d = 1, tx = 0, ty = 0;
    bool hasT = false;
    while (r.more) {
      final k = r.varint();
      final fn = k >> 3, w = k & 7;
      if (fn == 1 && w == 5) {
        f.alpha = r.f32();
      } else if (fn == 2 && w == 2) {
        final l = _R(r.bytes());
        while (l.more) {
          final kk = l.varint();
          final n = kk >> 3;
          if ((kk & 7) == 5) {
            final v = l.f32();
            if (n == 1) f.lx = v;
            if (n == 2) f.ly = v;
            if (n == 3) f.lw = v;
            if (n == 4) f.lh = v;
          } else {
            l.skip(kk & 7);
          }
        }
      } else if (fn == 3 && w == 2) {
        hasT = true;
        a = 0;
        d = 0;
        final t = _R(r.bytes());
        while (t.more) {
          final kk = t.varint();
          final n = kk >> 3;
          if ((kk & 7) == 5) {
            final v = t.f32();
            if (n == 1) a = v;
            if (n == 2) bb = v;
            if (n == 3) c = v;
            if (n == 4) d = v;
            if (n == 5) tx = v;
            if (n == 6) ty = v;
          } else {
            t.skip(kk & 7);
          }
        }
      } else {
        r.skip(w);
      }
    }
    if (!hasT) {
      a = 1;
      d = 1;
    }
    f.m = Float64List.fromList([a, bb, 0, 0, c, d, 0, 0, 0, 0, 1, 0, tx, ty, 0, 1]);
    return f;
  }

  static Future<SvgaMovie> decode(Uint8List data) async {
    if (data.length > 1 && data[0] == 0x50 && data[1] == 0x4b) {
      throw 'SVGA 1.x غير مدعوم';
    }
    final raw = Uint8List.fromList(ZLibCodec().decode(data));
    final r = _R(raw);
    final mv = SvgaMovie();
    final imgBytes = <String, Uint8List>{};
    while (r.more) {
      final k = r.varint();
      final fn = k >> 3, w = k & 7;
      if (fn == 2 && w == 2) {
        final p = _R(r.bytes());
        while (p.more) {
          final kk = p.varint();
          final n = kk >> 3;
          if ((kk & 7) == 5) {
            final v = p.f32();
            if (n == 1) mv.w = v;
            if (n == 2) mv.h = v;
          } else if ((kk & 7) == 0) {
            final v = p.varint();
            if (n == 3) mv.fps = v;
            if (n == 4) mv.frames = v;
          } else {
            p.skip(kk & 7);
          }
        }
      } else if (fn == 3 && w == 2) {
        final e = _R(r.bytes());
        String key = '';
        Uint8List? val;
        while (e.more) {
          final kk = e.varint();
          if ((kk & 7) == 2) {
            final bs = e.bytes();
            if ((kk >> 3) == 1) {
              key = String.fromCharCodes(bs);
            } else {
              val = bs;
            }
          } else {
            e.skip(kk & 7);
          }
        }
        if (val != null) imgBytes[key] = val;
      } else if (fn == 4 && w == 2) {
        final s = _R(r.bytes());
        final sp = _Sprite();
        while (s.more) {
          final kk = s.varint();
          final n = kk >> 3;
          if (n == 1 && (kk & 7) == 2) {
            sp.key = String.fromCharCodes(s.bytes());
          } else if (n == 2 && (kk & 7) == 2) {
            sp.frames.add(_frame(s.bytes()));
          } else {
            s.skip(kk & 7);
          }
        }
        mv.sprites.add(sp);
      } else {
        r.skip(w);
      }
    }
    for (final e in imgBytes.entries) {
      try {
        final codec = await ui.instantiateImageCodec(e.value);
        mv.images[e.key] = (await codec.getNextFrame()).image;
      } catch (_) {}
    }
    if (mv.w <= 0 || mv.h <= 0) throw 'ملف SVGA غير صالح';
    return mv;
  }

  static Future<SvgaMovie> load(String src) async {
    final Uint8List bytes;
    if (src.startsWith('asset:')) {
      final d = await rootBundle.load('assets/gifts/svga/${src.substring(6)}');
      bytes = d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes);
    } else {
      final res = await http.get(Uri.parse(src)).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) throw 'download failed';
      bytes = res.bodyBytes;
    }
    return decode(bytes);
  }
}

class _SvgaPainter extends CustomPainter {
  final SvgaMovie mv;
  final Animation<double> t;
  _SvgaPainter(this.mv, this.t) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final idx = (t.value * mv.frames).floor().clamp(0, mv.frames - 1);
    final sc = (size.width / mv.w) < (size.height / mv.h) ? size.width / mv.w : size.height / mv.h;
    canvas.save();
    canvas.translate((size.width - mv.w * sc) / 2, (size.height - mv.h * sc) / 2);
    canvas.scale(sc);
    final paint = Paint()..filterQuality = FilterQuality.medium;
    for (final s in mv.sprites) {
      if (s.key.endsWith('.matte')) continue;
      if (idx >= s.frames.length) continue;
      final f = s.frames[idx];
      if (f.alpha <= 0.001) continue;
      final img = mv.images[s.key];
      if (img == null) continue;
      paint.color = Color.fromRGBO(255, 255, 255, f.alpha.clamp(0.0, 1.0));
      canvas.save();
      canvas.transform(f.m!);
      final dst = (f.lw > 0 && f.lh > 0)
          ? Rect.fromLTWH(f.lx, f.ly, f.lw, f.lh)
          : Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
      canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), dst, paint);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SvgaPainter old) => old.mv != mv;
}

/// يشغّل ملف SVGA (من رابط أو asset:اسم.svga). onFail عند الفشل، onDone عند انتهاء التشغيل (غير المكرر).
class SvgaView extends StatefulWidget {
  final String src;
  final bool loop;
  final VoidCallback? onDone;
  final VoidCallback? onFail;
  const SvgaView({super.key, required this.src, this.loop = false, this.onDone, this.onFail});

  @override
  State<SvgaView> createState() => _SvgaViewState();
}

class _SvgaViewState extends State<SvgaView> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  SvgaMovie? _mv;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final mv = await SvgaMovie.load(widget.src);
      if (!mounted) return;
      _c.duration = mv.duration;
      setState(() => _mv = mv);
      if (widget.loop) {
        _c.repeat();
      } else {
        _c.forward().whenComplete(() => widget.onDone?.call());
      }
    } catch (_) {
      widget.onFail?.call();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mv = _mv;
    if (mv == null) return const SizedBox.shrink();
    return RepaintBoundary(child: CustomPaint(painter: _SvgaPainter(mv, _c), size: Size.infinite));
  }
}
