import { AdMob, BannerAdPosition, BannerAdSize } from '@capacitor-community/admob';

// 広告ユニットID
const BANNER_ID       = 'ca-app-pub-9887025755159214/7136735433';
const INTERSTITIAL_ID = 'ca-app-pub-9887025755159214/1884408756';
const REWARDED_ID     = 'ca-app-pub-9887025755159214/6123036666';

// 開発中は true
const TESTING = true;

async function init() {
  await AdMob.initialize({ initializeForTesting: TESTING });
}
init();

// バナーの表示状態を管理するフラグ
let bannerShown = false;

// バナー表示・消去の制御関数
async function showBanner(show) {
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

// ゲームからの合図を受け取る受け皿
window.native = async function(action, options = {}) {
  try {
    if (action === 'showBanner' || action === 'banner') {
      const show = options.show !== undefined ? options.show : true;
      await showBanner(show);
    } else if (action === 'showInterstitial') {
      await AdMob.prepareInterstitial({ adId: INTERSTITIAL_ID, isTesting: TESTING });
      await AdMob.showInterstitial();
    } else if (action === 'showRewarded') {
      await AdMob.prepareRewardVideoAd({ adId: REWARDED_ID, isTesting: TESTING });
      await AdMob.showRewardVideoAd();
    }
  } catch (error) {
    console.error('AdMob Error:', error);
  }
};