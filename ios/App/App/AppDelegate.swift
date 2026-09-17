import UIKit
import Capacitor
import WebKit
import StoreKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        return true
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return ApplicationDelegateProxy.shared.application(app, open: url, options: options)
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        return ApplicationDelegateProxy.shared.application(application, continue: userActivity, restorationHandler: restorationHandler)
    }
}

// Custom ViewController
class ViewController: CAPBridgeViewController, WKScriptMessageHandler {

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 画面いっぱいに表示（余白オフ）
        webView?.scrollView.contentInsetAdjustmentBehavior = .never
        
        // JSメッセージハンドラ "native" の登録
        webView?.configuration.userContentController.add(self, name: "native")
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }

        switch action {
        case "entitlements":
            checkEntitlements()
        case "purchase":
            if let id = body["id"] as? String {
                purchaseItem(id: id)
            }
        case "restore":
            restorePurchases()
        case "cloudSave":
            if let key = body["key"] as? String, let value = body["value"] as? String {
                NSUbiquitousKeyValueStore.default.set(value, forKey: key)
                NSUbiquitousKeyValueStore.default.synchronize()
            }
        case "cloudLoad":
            let val = NSUbiquitousKeyValueStore.default.string(forKey: body["key"] as? String ?? "") ?? ""
            evaluateJS("window.KingCats.cloudLoaded('\(val)')")
        default:
            break
        }
    }

    // 所有権確認 (StoreKit 2)
    func checkEntitlements() {
        Task {
            var ownedIDs: [String] = []
            for await result in Transaction.currentEntitlements {
                if case .verified(let transaction) = result, transaction.revocationDate == nil {
                    ownedIDs.append(transaction.productID)
                }
            }
            let json = (try? String(data: JSONSerialization.data(withJSONObject: ownedIDs), encoding: .utf8)) ?? "[]"
            evaluateJS("window.KingCats.entitlements(\(json))")
        }
    }

    // 購入処理 (StoreKit 2)
    func purchaseItem(id: String) {
        Task {
            do {
                let products = try await Product.products(for: [id])
                if let product = products.first {
                    let result = try await product.purchase()
                    if case .success(let verification) = result, case .verified(_) = verification {
                        evaluateJS("window.KingCats.purchaseDone('\(id)', true)")
                        return
                    }
                }
            } catch {}
            evaluateJS("window.KingCats.purchaseDone('\(id)', false)")
        }
    }

    // 復元処理 (StoreKit 2)
    func restorePurchases() {
        Task {
            try? await AppStore.sync()
            checkEntitlements()
        }
    }

    func evaluateJS(_ script: String) {
        DispatchQueue.main.async {
            self.webView?.evaluateJavaScript(script, completionHandler: nil)
        }
    }
}