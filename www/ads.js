import { AdMob } from '@capacitor-community/admob';

// 広告ユニットID（スラッシュ区切り）
const BANNER_ID       = 'ca-app-pub-9887025755159214/7136735433';
const INTERSTITIAL_ID = 'ca-app-pub-9887025755159214/1884408756';
const REWARDED_ID     = 'ca-app-pub-9887025755159214/6123036666';

// 開発中は true（安全なテスト広告を表示）
const TESTING = true;

async function init() {
  await AdMob.initialize({ initializeForTesting: TESTING });
}
init();
// ゲームからの合図を受け取って広告を表示する関数
window.native = async function(action) {
  try {
    if (action === 'showBanner') {
      await AdMob.showBanner({
        adId: BANNER_ID,
        position: BannerAdPosition.BOTTOM_CENTER,
        isTesting: TESTING
      });
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