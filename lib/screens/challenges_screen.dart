import 'package:flutter/material.dart';

import '../level.dart';
import '../main.dart';
import '../theme.dart';

class ChallengesScreen extends StatefulWidget {
  final Map<String, dynamic> profile;
  const ChallengesScreen({super.key, required this.profile});

  @override
  State<ChallengesScreen> createState() => _ChallengesScreenState();
}

class _ChallengesScreenState extends State<ChallengesScreen> {
  int _rooms = 0;
  int _games = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await supa.rpc('my_daily') as List;
      if (!mounted) return;
      setState(() {
        if (r.isNotEmpty) {
          _rooms = (r.first['rooms_today'] as num).toInt();
          _games = (r.first['games_today'] as num).toInt();
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      toast(context, friendlyError(e));
    }
  }

  Widget _mission(IconData i, Color c, String title, String sub, int cur, int goal) {
    final done = cur >= goal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(done ? Icons.check_circle_rounded : i, color: done ? C.green : c),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(sub, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (cur / goal).clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation(done ? C.green : c),
                ),
              ),
            ]),
          ),
          const SizedBox(width: 10),
          Text('${cur > goal ? goal : cur}/$goal',
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final xp = (widget.profile['xp'] as num?)?.toInt() ?? 0;
    final lv = levelOf(xp);
    return Scaffold(
      appBar: AppBar(title: const Text('لوحة التحديات', style: TextStyle(fontWeight: FontWeight.w800))),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: C.pink))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                GlassCard(
                  child: Row(children: [
                    const Icon(Icons.bolt_rounded, color: C.orange, size: 30),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                          'مستواك $lv — تكسب نقاطاً ببطء عند دخول الغرف واللعب (حد أقصى 150 نقطة يومياً).',
                          style: const TextStyle(height: 1.6)),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                const Text('مهام اليوم',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                _mission(Icons.mic_rounded, C.cyan, 'ادخل غرفة صوتية', 'ادخل أي غرفة مباشرة', _rooms, 1),
                _mission(Icons.timer_rounded, C.violet, 'ابقَ في الغرف 30 دقيقة',
                    'كل 10 دقائق تُحسب', _rooms, 3),
                _mission(Icons.sports_esports_rounded, C.pink, 'العب مباراة', 'خمّن الشخصية مع صديق أو عشوائي',
                    _games, 1),
                const SizedBox(height: 8),
                const Text('تتجدد المهام كل يوم عند منتصف الليل.',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
              ]),
            ),
    );
  }
}

class AchievementsScreen extends StatelessWidget {
  final Map<String, dynamic> profile;
  const AchievementsScreen({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    final earned = achievements.where((a) => a.test(profile)).length;
    return Scaffold(
      appBar: AppBar(title: Text('الإنجازات ($earned/${achievements.length})',
          style: const TextStyle(fontWeight: FontWeight.w800))),
      body: GridView.count(
        padding: const EdgeInsets.all(16),
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.05,
        children: [
          for (final a in achievements)
            GlassCard(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                AchBadge(a: a, earned: a.test(profile), size: 58, showLabel: false),
                const SizedBox(height: 8),
                Text(a.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                Text(a.sub,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54, fontSize: 11)),
              ]),
            ),
        ],
      ),
    );
  }
}
