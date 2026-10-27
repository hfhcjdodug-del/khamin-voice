import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'main.dart';
import 'shop_screen.dart';
import 'theme.dart';

/// الوحدات الإعلانية الحقيقية (AdMob → نتونس).
const _realBanner = 'ca-app-pub-7583984100644242/3277191524'; // games_banner
const _realInterstitial = 'ca-app-pub-7583984100644242/5997442374'; // round_end
const _realRewarded = 'ca-app-pub-7583984100644242/9637304481'; // reward_gift

/// وحدات Google التجريبية: يستعملها المدير (صاحب التطبيق) دائماً
/// حتى لا يضغط على إعلان حقيقي بالخطأ فيُحظر حسابه في AdMob.
const _testBanner = 'ca-app-pub-3940256099942544/6300978111';
const _testInterstitial = 'ca-app-pub-3940256099942544/1033173712';
const _testRewarded = 'ca-app-pub-3940256099942544/5224354917';

bool? _testMode;
String? _testModeUser;

Future<bool> _useTest() async {
  // النتيجة مرتبطة بالحساب: تتغيّر إن بدّل المستخدم حسابه دون إغلاق التطبيق
  final uid = supa.auth.currentUser?.id;
  if (_testMode != null && _testModeUser == uid) return _testMode!;
  try {
    _testMode = (await supa.rpc('am_i_admin')) == true;
    _testModeUser = uid;
  } catch (_) {
    return true; // عند الشك نستعمل التجريبي (أأمن)، ولا نخزّن النتيجة
  }
  return _testMode!;
}

Future<String> _unit(String real, String test) async => (await _useTest()) ? test : real;

bool _ready = false;
bool? _adsFree;
InterstitialAd? _inter;
DateTime _lastInter = DateTime.fromMillisecondsSinceEpoch(0);

Future<void> initAds() async {
  try {
    supa.auth.onAuthStateChange.listen((_) {
      _testMode = null;
      _adsFree = null;
    });
  } catch (_) {}
  if (!Platform.isAndroid) return;
  try {
    await MobileAds.instance.initialize();
    _ready = true;
    _loadInter();
  } catch (_) {}
}

/// هل اشترى المستخدم «بدون إعلانات»؟ (يُحفظ بعد أول قراءة)
Future<bool> adsFree({bool refresh = false}) async {
  if (_adsFree != null && !refresh) return _adsFree!;
  try {
    _adsFree = (await fetchWallet()).adsFree;
  } catch (_) {
    _adsFree = false;
  }
  return _adsFree!;
}

Future<void> _loadInter() async {
  if (!_ready) return;
  final id = await _unit(_realInterstitial, _testInterstitial);
  InterstitialAd.load(
    adUnitId: id,
    request: const AdRequest(),
    adLoadCallback: InterstitialAdLoadCallback(
      onAdLoaded: (a) => _inter = a,
      onAdFailedToLoad: (_) => _inter = null,
    ),
  );
}

/// إعلان بملء الشاشة بعد انتهاء جولة، بحد أدنى 3 دقائق بين إعلانين.
Future<void> showRoundEndAd() async {
  if (!_ready || await adsFree()) return;
  final a = _inter;
  if (a == null) {
    _loadInter();
    return;
  }
  if (DateTime.now().difference(_lastInter).inMinutes < 3) return;
  _inter = null;
  _lastInter = DateTime.now();
  a.fullScreenContentCallback = FullScreenContentCallback(
    onAdDismissedFullScreenContent: (ad) {
      ad.dispose();
      _loadInter();
    },
    onAdFailedToShowFullScreenContent: (ad, _) {
      ad.dispose();
      _loadInter();
    },
  );
  await a.show();
}

/// إعلان صغير؛ يختفي تلقائياً لمن اشترى «بدون إعلانات» أو إذا فشل التحميل.
class AdBanner extends StatefulWidget {
  const AdBanner({super.key});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (!_ready || await adsFree()) return;
    final ad = BannerAd(
      adUnitId: await _unit(_realBanner, _testBanner),
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (a, _) => a.dispose(),
      ),
    );
    _ad = ad;
    await ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (!_loaded || ad == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: SizedBox(
          width: ad.size.width.toDouble(),
          height: ad.size.height.toDouble(),
          child: AdWidget(ad: ad),
        ),
      ),
    );
  }
}

/// إعلان مكافئ: يرجع true عند اكتمال المشاهدة (أو فوراً لمن اشترى «بدون إعلانات»).
Future<bool> watchRewardedAd(BuildContext context) async {
  if (await adsFree(refresh: true)) {
    supa.rpc('log_ad_view').catchError((_) => null);
    return true;
  }
  if (!_ready) {
    if (context.mounted) toast(context, 'الإعلانات غير متاحة الآن');
    return false;
  }
  final done = Completer<bool>();
  var earned = false;
  final rewardedId = await _unit(_realRewarded, _testRewarded);
  RewardedAd.load(
    adUnitId: rewardedId,
    request: const AdRequest(),
    rewardedAdLoadCallback: RewardedAdLoadCallback(
      onAdLoaded: (ad) {
        ad.fullScreenContentCallback = FullScreenContentCallback(
          onAdDismissedFullScreenContent: (a) {
            a.dispose();
            if (!done.isCompleted) done.complete(earned);
          },
          onAdFailedToShowFullScreenContent: (a, _) {
            a.dispose();
            if (!done.isCompleted) done.complete(false);
          },
        );
        ad.show(onUserEarnedReward: (_, __) => earned = true);
      },
      onAdFailedToLoad: (_) {
        if (!done.isCompleted) done.complete(false);
      },
    ),
  );
  final ok = await done.future.timeout(const Duration(seconds: 60), onTimeout: () => false);
  if (ok) {
    supa.rpc('log_ad_view').catchError((_) => null);
  } else if (context.mounted) {
    toast(context, 'لم يكتمل الإعلان أو غير متوفر الآن، حاول لاحقاً');
  }
  return ok;
}
