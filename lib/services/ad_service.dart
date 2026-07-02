import 'package:flutter/foundation.dart';

/// Contract for rewarded and interstitial ads.
///
/// Replace [StubAdService] with an AdMob implementation when ready.
abstract class AdService {
  Future<void> initialize();
  bool get isRewardedAdReady;
  Future<bool> showRewardedAd();
  Future<void> showInterstitialAd();
}

/// Placeholder ad service — simulates rewarded ads until AdMob is integrated.
class StubAdService implements AdService {
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    _initialized = true;
    debugPrint('[AdService] Stub initialized — replace with AdMob later');
  }

  @override
  bool get isRewardedAdReady => _initialized;

  @override
  Future<bool> showRewardedAd() async {
    if (!_initialized) return false;
    debugPrint('[AdService] Simulating rewarded ad…');
    await Future<void>.delayed(const Duration(seconds: 1));
    debugPrint('[AdService] Rewarded ad completed (stub)');
    return true;
  }

  @override
  Future<void> showInterstitialAd() async {
    if (!_initialized) return;
    debugPrint('[AdService] Interstitial ad placeholder — not shown in MVP');
  }
}
