import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'main.dart';
import 'shop_screen.dart';
import 'theme.dart';

/// أرقام الوحدات الإعلانية. الحالية «تجريبية» رسمية من Google:
/// بدّلها بأرقامك من AdMob قبل النشر على Google Play.
const _testBanner = 'ca-app-pub-3940256099942544/6300978111';
const _testInterstitial = 'ca-app-pub-3940256099942544/1033173712';
const String bannerUnitId = _testBanner; // ← games_banner
const String interstitialUnitId = _testInterstitial; // ← round_end
const _testRewarded = 'ca-app-pub-3940256099942544/5224354917';
const String rewardedUnitId = _testRewarded; // ← rewards

bool _ready = false;
bool? _adsFree;
InterstitialAd? _inter;
DateTime _lastInter = DateTime.fromMillisecondsSinceEpoch(0);

Future<void> initAds() async {
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

void _loadInter() {
  if (!_ready) return;
  InterstitialAd.load(
    adUnitId: interstitialUnitId,
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
      adUnitId: bannerUnitId,
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
  RewardedAd.load(
    adUnitId: rewardedUnitId,
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
