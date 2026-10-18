import 'dart:math';

import 'package:flutter/material.dart';

import 'main.dart';
import 'theme.dart';

/// المستوى يزيد ببطء: المستوى L يحتاج 50*(L-1)^2 نقطة.
int levelOf(int xp) => sqrt(xp / 50).floor() + 1;
int levelBase(int level) => 50 * (level - 1) * (level - 1);
int levelNext(int level) => 50 * level * level;

class Tier {
  final String name;
  final List<Color> colors;
  const Tier(this.name, this.colors);
}

Tier tierOf(int level) {
  if (level >= 20) return const Tier('الماسي', [Color(0xFF22D3EE), Color(0xFF8B5CF6)]);
  if (level >= 10) return const Tier('الذهبي', [Color(0xFFFBBF24), Color(0xFFF97316)]);
  if (level >= 5) return const Tier('الفضي', [Color(0xFFCBD5E1), Color(0xFF64748B)]);
  return const Tier('البرونزي', [Color(0xFFD08A4E), Color(0xFF8A4B1E)]);
}

int _n(Map<String, dynamic> p, String k) => (p[k] as num?)?.toInt() ?? 0;

class Achv {
  final String id;
  final String title;
  final String sub;
  final IconData icon;
  final List<Color> colors;
  final bool Function(Map<String, dynamic> p) test;
  const Achv(this.id, this.title, this.sub, this.icon, this.colors, this.test);
}

final achievements = <Achv>[
  Achv('verified', 'مستخدم مميز', 'حسابك موثّق', Icons.workspace_premium_rounded,
      const [Color(0xFF8B5CF6), Color(0xFF6D4AFF)], (p) => p['verified'] == true),
  Achv('rooms', 'مستكشف الغرف', 'ادخل 5 غرف', Icons.mic_rounded,
      const [Color(0xFF22D3EE), Color(0xFF2563EB)], (p) => _n(p, 'rooms_count') >= 5),
  Achv('presence', 'صاحب حضور قوي', '25 زيارة لملفك', Icons.local_fire_department_rounded,
      const [Color(0xFFFB923C), Color(0xFFEF4444)], (p) => _n(p, 'visits') >= 25),
  Achv('fans', 'فائق التفاعل', '10 متابعين', Icons.star_rounded,
      const [Color(0xFFA78BFA), Color(0xFFA855F7)], (p) => _n(p, 'followers') >= 10),
  Achv('active', 'عضو نشط', 'وصل المستوى 3', Icons.bolt_rounded,
      const [Color(0xFF34D399), Color(0xFF0EA5E9)], (p) => levelOf(_n(p, 'xp')) >= 3),
  Achv('friend', 'صديق الجميع', 'تابع 10 أشخاص', Icons.favorite_rounded,
      const [Color(0xFFA855F7), Color(0xFF8B5CF6)], (p) => _n(p, 'following') >= 10),
  Achv('player', 'لاعب محترف', 'العب 10 مباريات', Icons.sports_esports_rounded,
      const [Color(0xFF6366F1), Color(0xFF22D3EE)], (p) => _n(p, 'games_count') >= 10),
  Achv('king', 'ملك التفاعل', 'وصل المستوى 10', Icons.emoji_events_rounded,
      const [Color(0xFFFBBF24), Color(0xFFF97316)], (p) => levelOf(_n(p, 'xp')) >= 10),
];

class AchBadge extends StatelessWidget {
  final Achv a;
  final bool earned;
  final double size;
  final bool showLabel;
  const AchBadge({
    super.key,
    required this.a,
    required this.earned,
    this.size = 54,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: earned
              ? LinearGradient(colors: a.colors, begin: Alignment.topLeft, end: Alignment.bottomRight)
              : null,
          color: earned ? null : C.glass,
          border: Border.all(color: earned ? Colors.white54 : Colors.white12, width: 1.5),
          boxShadow: earned
              ? [BoxShadow(color: a.colors.first.withValues(alpha: 0.5), blurRadius: 16)]
              : null,
        ),
        child: Icon(a.icon, size: size * 0.5, color: earned ? Colors.white : Colors.white30),
      ),
      if (showLabel) ...[
        const SizedBox(height: 6),
        SizedBox(
          width: size + 18,
          child: Text(a.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: earned ? Colors.white : Colors.white38)),
        ),
      ],
    ]);
  }
}

String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t.toLocal());
  if (d.inMinutes < 1) return 'الآن';
  if (d.inMinutes < 60) return 'منذ ${d.inMinutes} دقيقة';
  if (d.inHours < 24) return 'منذ ${d.inHours} ساعة';
  return 'منذ ${d.inDays} يوم';
}

// ---------- الألقاب والشارات والـ VIP ----------

const titleNames = [
  'المبتدئ', 'الحالم', 'المستكشف', 'المحارب الصامت', 'الأسطورة الأولى',
  'صديق الجميع', 'المغامر', 'الذئب الأزرق', 'المتميز', 'قمة البداية',
  'النجم', 'الفرسان', 'صانع المجد', 'المدافع', 'سيد المجال',
  'الملك', 'القائد', 'الأسطوري', 'الفاتح', 'الزعيم',
  'الأسطورة', 'سيد الكون', 'المهيب', 'الخالد', 'الأسطورة المطلقة',
];

class TitleDef {
  final int idx;
  final int fromLevel;
  final String name;
  final String? url; // صورة مرفوعة من المدير
  final String? asset; // صورة مدمجة في التطبيق
  const TitleDef(this.idx, this.fromLevel, this.name, {this.url, this.asset});
}

/// ألقاب ومستويات قابلة للتعديل من لوحة المدير (جدولا level_badges و title_defs)،
/// وإن لم تُعدَّل تبقى الصور الأصلية المدمجة في التطبيق.
class BadgeStore {
  static final ValueNotifier<int> version = ValueNotifier(0);
  static final Map<int, String> _levelUrls = {};
  static List<TitleDef> _titles = _defaults();
  static bool _loaded = false;
  static bool _loading = false;

  static List<TitleDef> _defaults() => [
        for (var i = 0; i < titleNames.length; i++)
          TitleDef(i, i * 2 + 1, titleNames[i], asset: 'assets/titles/${i + 1}.png'),
      ];

  static List<TitleDef> get titles => _titles;
  static Map<int, String> get levelUrls => _levelUrls;
  static int get maxLevel => _levelUrls.keys.fold<int>(50, max);

  /// يحمّل مرة واحدة (بعد تسجيل الدخول)، و force لإعادة التحميل بعد تعديل المدير.
  static Future<void> ensure({bool force = false}) async {
    if (_loading || (_loaded && !force)) return;
    if (supa.auth.currentUser == null) return;
    _loading = true;
    try {
      final lv = await supa.from('level_badges').select();
      final td = await supa.from('title_defs').select();
      _levelUrls
        ..clear()
        ..addEntries([
          for (final r in lv as List) MapEntry((r['level'] as num).toInt(), r['image_url'] as String),
        ]);
      final byIdx = {for (final t in _defaults()) t.idx: t};
      for (final r in td as List) {
        final i = (r['idx'] as num).toInt();
        final base = byIdx[i];
        final u = r['image_url'] as String?;
        byIdx[i] = TitleDef(i, (r['from_level'] as num).toInt(), r['name'] as String,
            url: (u == null || u.isEmpty) ? null : u, asset: base?.asset);
      }
      final l = byIdx.values.toList()
        ..sort((a, b) {
          final c = a.fromLevel.compareTo(b.fromLevel);
          return c != 0 ? c : a.idx.compareTo(b.idx);
        });
      _titles = l;
      _loaded = true;
      version.value++;
    } catch (_) {
      // الجداول غير موجودة (v19 لم تُشغَّل): نبقى على الأصلي
    }
    _loading = false;
  }
}

int _cl(int level) => level < 1 ? 1 : level;

/// فهرس اللقب (في القائمة المرتبة) الذي يغطي هذا المستوى.
int titleIndex(int level) {
  final l = BadgeStore.titles;
  var r = 0;
  for (var i = 0; i < l.length; i++) {
    if (l[i].fromLevel <= level) r = i;
  }
  return r;
}

TitleDef titleDefOf(int level) => BadgeStore.titles[titleIndex(level)];
String titleName(int level) => titleDefOf(level).name;

/// شارة المستوى (حرّة بدون إطار مربع).
class LevelBadge extends StatelessWidget {
  final int level;
  final double size;
  const LevelBadge({super.key, required this.level, this.size = 28});

  @override
  Widget build(BuildContext context) {
    BadgeStore.ensure();
    return ValueListenableBuilder<int>(
      valueListenable: BadgeStore.version,
      builder: (_, __, ___) {
        final lv = _cl(level);
        final url = BadgeStore.levelUrls[lv];
        final blank = SizedBox(width: size, height: size);
        if (url != null) {
          return Image.network(url,
              width: size, height: size, fit: BoxFit.contain, errorBuilder: (_, __, ___) => blank);
        }
        return Image.asset(
          'assets/levels/${lv > 50 ? 50 : lv}.png',
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => blank,
        );
      },
    );
  }
}

/// صورة اللقب (الاسم مكتوب داخل الصورة نفسها).
class TitleImage extends StatelessWidget {
  final int level;
  final double height;
  const TitleImage({super.key, required this.level, this.height = 28});

  @override
  Widget build(BuildContext context) {
    BadgeStore.ensure();
    return ValueListenableBuilder<int>(
      valueListenable: BadgeStore.version,
      builder: (_, __, ___) => TitleDefImage(def: titleDefOf(level), height: height),
    );
  }
}

/// يرسم لقباً محدداً (يُستعمل في قائمة الألقاب ولوحة المدير).
class TitleDefImage extends StatelessWidget {
  final TitleDef def;
  final double height;
  const TitleDefImage({super.key, required this.def, this.height = 28});

  @override
  Widget build(BuildContext context) {
    final fallback = Text(def.name, style: TextStyle(fontSize: height * 0.4, color: Colors.white70));
    if (def.url != null) {
      return Image.network(def.url!,
          height: height, fit: BoxFit.contain, errorBuilder: (_, __, ___) => fallback);
    }
    if (def.asset != null) {
      return Image.asset(def.asset!,
          height: height, fit: BoxFit.contain, errorBuilder: (_, __, ___) => fallback);
    }
    return fallback;
  }
}

DateTime? _dt(Object? v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

/// حالة الـ VIP: none | active | former
String vipState(Map<String, dynamic> p) {
  final end = _dt(p['vip_end']);
  if (end == null) return 'none';
  return end.isAfter(DateTime.now()) ? 'active' : 'former';
}

int vipDaysLeft(Map<String, dynamic> p) {
  final end = _dt(p['vip_end']);
  if (end == null) return 0;
  return end.difference(DateTime.now()).inDays + 1;
}

String fmtDate(Object? v) {
  final d = _dt(v);
  return d == null ? '' : '${d.year}/${d.month}/${d.day}';
}
