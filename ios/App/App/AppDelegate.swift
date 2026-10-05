import UIKit
import Capacitor
import WebKit
import StoreKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        
        // ----------------------------------------------------
        // 課金ブリッジを WebView にアタッチ（接続）
        // ----------------------------------------------------
        KCNative.shared.attach(to: window)

        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, etc.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate.
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return ApplicationDelegateProxy.shared.application(app, open: url, options: options)
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        return ApplicationDelegateProxy.shared.application(application, continue: userActivity, restorationHandler: restorationHandler)
    }
}

// ============================================================================
// KING CAT 課金ブリッジ（WKScriptMessageHandler & StoreKit 2）
// ============================================================================

@MainActor
final class KCNative: NSObject, WKScriptMessageHandler {

    static let shared = KCNative()

    /// 画面に「🛠 …」で各段階を表示する。原因が分かったら false に。
    var showDiagnostics = false

    private weak var webView: WKWebView?
    private var updatesTask: Task<Void, Never>?
    private var attached = false

    // MARK: - 起動時：Capacitor の WebView を見つけて受け口を付ける

    func attach(to window: UIWindow?, tries: Int = 0) {
        // WebView はアプリ起動の少しあとに作られるので、見つかるまで待つ
        guard !attached else { return }
        if let root = window?.rootViewController,
           let bridgeVC = findBridge(in: root),
           let wv = bridgeVC.webView {
            webView = wv
            let ucc = wv.configuration.userContentController
            ucc.removeScriptMessageHandler(forName: "native")   // 古い受け口があれば外す
            ucc.add(self, name: "native")
            attached = true
            startTransactionListener()
            // 受け口ができる前に HTML が送った依頼を、もう一度送ってもらう
            // ※ 製品IDはゲーム内IDと違うものがあるので、HTML 側の allStoreIds()
            //   （App Store Connect の製品ID一覧）でたずねてもらう。
            js("""
               try{
                 window.KingCats && window.KingCats.iapLog && window.KingCats.iapLog('課金ブリッジ 起動OK / HTML '+(window.HTML_BUILD||'旧版'));
                 if (typeof kcNative === 'function' && typeof allStoreIds === 'function') {
                   kcNative('entitlements');
                   kcNative('prices',{ids:allStoreIds()});
                 }
               }catch(e){}
               """)
            return
        }
        if tries < 40 {   // 最大 約20秒 待つ
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 500_000_000)
                let w = window ?? UIApplication.shared.connectedScenes
                    .compactMap { ($0 as? UIWindowScene)?.windows.first }.first
                self?.attach(to: w, tries: tries + 1)
            }
        } else {
            print("[IAP] ❌ Capacitor の WebView が見つかりませんでした")
        }
    }

    private func findBridge(in vc: UIViewController) -> CAPBridgeViewController? {
        if let b = vc as? CAPBridgeViewController { return b }
        for child in vc.children { if let b = findBridge(in: child) { return b } }
        if let p = vc.presentedViewController { return findBridge(in: p) }
        return nil
    }

    private func startTransactionListener() {
        // 承認待ちだった購入・中断した購入・オファーコードはここに届く
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let t) = result {
                    await t.finish()
                    if t.revocationDate == nil {
                        self.js("window.KingCats.entitlements(\(self.json([t.productID])))")
                    }
                }
            }
        }
    }

    // MARK: - HTML からの依頼

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        handle(message.body as? [String: Any] ?? [:])
    }

    private func handle(_ body: [String: Any]) {
        let t = body["t"] as? String ?? ""
        switch t {
        case "purchase":
            let id = body["id"] as? String ?? ""
            let coveredBy = body["coveredBy"] as? [String] ?? []
            log("① 購入の依頼を受信: \(id)")
            Task { await purchase(id, coveredBy: coveredBy) }
        case "restore":
            log("復元の依頼を受信")
            Task { await restore() }
        case "entitlements":
            Task { await sendEntitlements() }
        case "prices":
            let ids = body["ids"] as? [String] ?? []
            Task { await sendPrices(ids) }
        default:
            // 広告など（banner / showRewarded / showInterstitial …）は今は何もしない。
            break
        }
    }

    // MARK: - 購入

    private func purchase(_ id: String, coveredBy: [String]) async {
        guard !id.isEmpty else { done(id, false); return }

        let owned = await currentIDs()
        if !Set(coveredBy).isDisjoint(with: owned) {
            log("セットで所持済みのため請求しません: \(id)")
            js("window.KingCats.entitlements(\(json(owned)))")
            done(id, true)
            return
        }
        do {
            log("② 商品情報を取得中…")
            guard let product = try await Product.products(for: [id]).first else {
                log("❌ 商品が見つかりません: \(id)")
                done(id, false)
                return
            }
            log("③ 購入画面を表示: \(product.displayPrice)")
            switch try await product.purchase() {
            case .success(.verified(let tx)):
                await tx.finish()
                log("✅ 購入完了: \(id)")
                done(id, true)
            case .success(.unverified(_, let error)):
                log("❌ 検証失敗: \(error.localizedDescription)")
                done(id, false)
            case .userCancelled:
                log("キャンセルされました")
                done(id, false)
            case .pending:
                log("承認待ちです")
                done(id, false)
            @unknown default:
                done(id, false)
            }
        } catch {
            log("❌ エラー: \(error.localizedDescription)")
            done(id, false)
        }
    }

    // MARK: - 復元・所持・価格

    private func restore() async {
        do { try await AppStore.sync() } catch { log("同期エラー: \(error.localizedDescription)") }
        let ids = await currentIDs()
        log("復元: \(ids.count)件")
        js("window.KingCats.restoreDone(\(json(ids)))")
    }

    private func sendEntitlements() async {
        let ids = await currentIDs()
        js("window.KingCats.entitlements(\(json(ids)))")
    }

    private func currentIDs() async -> [String] {
        var ids: [String] = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.revocationDate == nil { ids.append(t.productID) }
        }
        return ids
    }

    private func sendPrices(_ ids: [String]) async {
        guard !ids.isEmpty else { return }
        do {
            let products = try await Product.products(for: ids)
            log("価格を取得: \(products.count) / \(ids.count) 件")
            let list: [[String: Any]] = products.map { p in
                ["id": p.id,
                 "display": p.displayPrice,
                 "value": (p.price as NSDecimalNumber).doubleValue,
                 "currency": p.priceFormatStyle.currencyCode]
            }
            js("window.KingCats.prices(\(json(list)))")
        } catch {
            log("価格の取得エラー: \(error.localizedDescription)")
        }
    }

    // MARK: - HTML へ返す

    private func done(_ id: String, _ ok: Bool) {
        js("window.KingCats.purchaseDone(\(json(id)), \(ok ? "true" : "false"))")
    }

    func log(_ message: String) {
        print("[IAP] \(message)")
        guard showDiagnostics else { return }
        js("window.KingCats && window.KingCats.iapLog && window.KingCats.iapLog(\(json(message)))")
    }

    private func json(_ value: Any) -> String {
        if let s = value as? String {
            guard let d = try? JSONSerialization.data(withJSONObject: [s]),
                  let w = String(data: d, encoding: .utf8) else { return "\"\"" }
            return String(w.dropFirst().dropLast())
        }
        guard JSONSerialization.isValidJSONObject(value),
              let d = try? JSONSerialization.data(withJSONObject: value),
              let s = String(data: d, encoding: .utf8) else { return "null" }
        return s
    }

    private func js(_ script: String) {
        guard let webView else { print("[IAP] ❌ webView がありません"); return }
        webView.evaluateJavaScript(script) { _, error in
            if let error { print("[IAP] JS error: \(error)") }
        }
    }
}