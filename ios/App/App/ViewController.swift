import UIKit
import WebKit
import Capacitor

// ============================================================================
//  ViewController
//
//  課金の処理は AppDelegate.swift の KCNative にまとめました。
//  KCNative が起動後に "native" の受け口を自分で登録するので、
//  ここでは受け口を登録しません（2つあると、付け替えの瞬間に
//  ゲームからの依頼が落ちて、価格が届かなくなるため）。
//
//  以前ここにあった StoreBridge と iCloud（cloudSave / cloudLoad）の処理は
//  削除しました。iCloud は HTML 側からも削除済みで、もう依頼は来ません。
// ============================================================================

class ViewController: CAPBridgeViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        // 画面いっぱいに表示（余白オフ）
        webView?.scrollView.contentInsetAdjustmentBehavior = .never
    }
}