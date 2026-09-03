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

let bannerShown = false;

// バナー表示・消去
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

// インタースティシャル全画面広告
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
  // 広告が出せなくても閉じた後でも、必ずゲームへ進む処理を呼ぶ
  if (window.KingCats && typeof window.KingCats.adClosed === 'function') {
    window.KingCats.adClosed();
  }
}

// ゲームからの呼び出し受信用
window.native = async function(action, options = {}) {
  try {
    if (action === 'showBanner' || action === 'banner') {
      const show = options.show !== undefined ? options.show : true;
      await showBanner(show);
    } else if (action === 'showInterstitial') {
      await showInterstitial();
    } else if (action === 'showRewarded') {
      await AdMob.prepareRewardVideoAd({ adId: REWARDED_ID, isTesting: TESTING });
      await AdMob.showRewardVideoAd();
    }
  } catch (error) {
    console.error('AdMob Error:', error);
  }
};