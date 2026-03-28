import 'dart:io';

/// Centralized AdMob IDs for platform-specific configuration.
/// Set [useTestAds] to true while testing to avoid policy violations.
class AdMobIds {
  static const bool useTestAds = false;

  static const String androidAppId = 'ca-app-pub-9985022151393867~5701483111';
  static const String iosAppId = 'ca-app-pub-9985022151393867~4001388639';

  static const String androidBanner = 'ca-app-pub-9985022151393867/2364873337';
  static const String iosBanner = 'ca-app-pub-9985022151393867/3606503514';

  static const String androidInterstitial =
      'ca-app-pub-9985022151393867/6024916746';
  static const String iosInterstitial =
      'ca-app-pub-9985022151393867/7880923895';

  static const String androidRewarded =
      'ca-app-pub-9985022151393867/5166997196';
  static const String iosRewarded = 'ca-app-pub-9985022151393867/4544314117';

  static const String androidBannerTest =
      'ca-app-pub-3940256099942544/6300978111';
  static const String iosBannerTest = 'ca-app-pub-3940256099942544/2934735716';

  static const String androidInterstitialTest =
      'ca-app-pub-3940256099942544/1033173712';
  static const String iosInterstitialTest =
      'ca-app-pub-3940256099942544/4411468910';

  static const String androidRewardedTest =
      'ca-app-pub-3940256099942544/5224354917';
  static const String iosRewardedTest =
      'ca-app-pub-3940256099942544/1712485313';

  static String get banner {
    if (Platform.isAndroid) {
      return useTestAds ? androidBannerTest : androidBanner;
    }
    if (Platform.isIOS) return useTestAds ? iosBannerTest : iosBanner;
    throw UnsupportedError('Unsupported platform for AdMob banner');
  }

  static String get interstitial {
    if (Platform.isAndroid) {
      return useTestAds ? androidInterstitialTest : androidInterstitial;
    }
    if (Platform.isIOS) {
      return useTestAds ? iosInterstitialTest : iosInterstitial;
    }
    throw UnsupportedError('Unsupported platform for AdMob interstitial');
  }

  static String get rewarded {
    if (Platform.isAndroid) {
      return useTestAds ? androidRewardedTest : androidRewarded;
    }
    if (Platform.isIOS) return useTestAds ? iosRewardedTest : iosRewarded;
    throw UnsupportedError('Unsupported platform for AdMob rewarded');
  }
}
