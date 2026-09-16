import { AdMob, BannerAdPosition, BannerAdSize, RewardAdPluginEvents } from '@capacitor-community/admob';

// 開発・TestFlight検証中は true（App Store公開時に false へ変更）
const TESTING = true;

// 広告ユニットID（TESTINGがtrueの時はGoogle公式テストID、falseの時は本番IDを使用）
const BANNER_ID       = TESTING ? 'ca-app-pub-3940256099942544/2934735716' : 'ca-app-pub-9887025755159214/7136735433';
const INTERSTITIAL_ID = TESTING ? 'ca-app-pub-3940256099942544/4411468910' : 'ca-app-pub-9887025755159214/1884408756';
const REWARDED_ID     = TESTING ? 'ca-app-pub-3940256099942544/1712485313' : 'ca-app-pub-9887025755159214/6123036666';

async function init() {
  try {
    // iOSの追跡許諾（ATT）ダイアログを表示
    await AdMob.requestTrackingAuthorization();
    
    // AdMob初期化
    await AdMob.initialize({
      initializeForTesting: TESTING,
      testingDevices: ['0F45FC0C-DDA5-4170-8DD8-2C6BDA702240'],
    });
  } catch (e) {
    console.error('AdMob Init Error:', e);
  }
}
init();

// --- バナー広告 ---
let bannerShown = false;

async function showBanner(show = true) {
  if (show && !bannerShown) {
    await AdMob.showBanner({
      adId: BANNER_ID,
      adSize: BannerAdSize.ADAPTIVE_BANNER,
      position: BannerAdPosition.BOTTOM_CENTER,
      isTesting: TESTING,
    });
    bannerShown = true;
  } else if (!show && bannerShown) {
    await AdMob.removeBanner();
    bannerShown = false;
  }
}

// --- インタースティシャル広告 ---
async function showInterstitial() {
  try {
    await AdMob.prepareInterstitial({
      adId: INTERSTITIAL_ID,
      isTesting: TESTING,
    });
    await AdMob.showInterstitial();
  } catch (e) {
    console.error('Interstitial Error:', e);
  }
  if (window.KingCats && typeof window.KingCats.adClosed === 'function') {
    window.KingCats.adClosed();
  }
}

// --- リワード動画広告 ---
let gotReward = false;

// 動画を最後まで見たときだけ発火するイベント
AdMob.addListener(RewardAdPluginEvents.Rewarded, () => {
  gotReward = true;
});

async function showRewarded() {
  gotReward = false;
  try {
    await AdMob.prepareRewardVideoAd({
      adId: REWARDED_ID,
      isTesting: TESTING,
    });
    await AdMob.showRewardVideoAd();
  } catch (e) {
    console.error('Rewarded Error:', e);
    if (window.KingCats && typeof window.KingCats.adFailed === 'function') {
      window.KingCats.adFailed();
    }
    return;
  }

  // 広告が閉じられた後の報酬判定
  if (window.KingCats) {
    if (gotReward && typeof window.KingCats.rewardEarned === 'function') {
      window.KingCats.rewardEarned(); // 報酬付与
    } else if (typeof window.KingCats.adClosed === 'function') {
      window.KingCats.adClosed();     // 途中離脱（報酬なしでゲーム復帰）
    }
  }
}

// ゲーム本体からの呼び出し口を設定
window.KingCatsAds = { showBanner, showInterstitial, showRewarded };

// 既存合図（window.native）との互換処理
window.native = async function(action, options = {}) {
  try {
    if (action === 'showBanner' || action === 'banner') {
      const show = options.show !== undefined ? options.show : true;
      await showBanner(show);
    } else if (action === 'showInterstitial') {
      await showInterstitial();
    } else if (action === 'showRewarded') {
      await showRewarded();
    }
  } catch (error) {
    console.error('AdMob Error:', error);
  }
};