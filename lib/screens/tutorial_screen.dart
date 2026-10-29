import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../theme.dart';

const _seenKey = 'tutorial_seen_v1';

Future<List<Map<String, dynamic>>> _loadSlides() async {
  final r = await supa.from('tutorial_slides').select().order('sort');
  return List<Map<String, dynamic>>.from(r);
}

/// تظهر مرة واحدة عند أول دخول (إن كان المدير قد أضاف شرائح).
Future<void> maybeShowTutorial(BuildContext context) async {
  try {
    final sp = await SharedPreferences.getInstance();
    if (sp.getBool(_seenKey) == true) return;
    final slides = await _loadSlides();
    if (slides.isEmpty || !context.mounted) return;
    await sp.setBool(_seenKey, true);
    if (!context.mounted) return;
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => TutorialScreen(slides: slides), fullscreenDialog: true));
  } catch (_) {}
}

/// فتح الشرح يدوياً من زر «طريقة اللعب».
Future<void> openTutorial(BuildContext context) async {
  try {
    final slides = await _loadSlides();
    if (!context.mounted) return;
    if (slides.isEmpty) {
      toast(context, 'لا يوجد شرح بعد');
      return;
    }
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => TutorialScreen(slides: slides), fullscreenDialog: true));
  } catch (e) {
    if (context.mounted) toast(context, friendlyError(e));
  }
}

class TutorialScreen extends StatefulWidget {
  final List<Map<String, dynamic>> slides;
  const TutorialScreen({super.key, required this.slides});

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final _pc = PageController();
  int _i = 0;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.slides.length;
    final last = _i == n - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('تخطّي', style: TextStyle(color: Colors.white60)),
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pc,
              itemCount: n,
              onPageChanged: (v) => setState(() => _i = v),
              itemBuilder: (_, i) {
                final s = widget.slides[i];
                final img = (s['image_url'] ?? '') as String;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(children: [
                    Expanded(
                      child: img.isEmpty
                          ? const Center(child: Icon(Icons.face_retouching_natural_rounded, size: 120, color: C.pink))
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Image.network(img,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) =>
                                      const Icon(Icons.image_not_supported_outlined, size: 80, color: Colors.white38)),
                            ),
                    ),
                    const SizedBox(height: 18),
                    Text((s['title'] ?? '') as String,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    Text((s['body'] ?? '') as String,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 15, color: Colors.white70, height: 1.5)),
                    const SizedBox(height: 12),
                  ]),
                );
              },
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var k = 0; k < n; k++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.all(4),
                width: k == _i ? 22 : 8,
                height: 8,
                decoration: BoxDecoration(
                    color: k == _i ? C.pink : Colors.white24, borderRadius: BorderRadius.circular(8)),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
            child: SizedBox(
              width: double.infinity,
              child: GradButton(
                label: last ? 'ابدأ اللعب' : 'التالي',
                onPressed: () {
                  if (last) {
                    Navigator.pop(context);
                  } else {
                    _pc.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
                  }
                },
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
