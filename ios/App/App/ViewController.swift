import UIKit
import WebKit
import StoreKit
import Capacitor

class ViewController: CAPBridgeViewController, WKScriptMessageHandler {

    // ① StoreBridge のインスタンスを保持
    let store = StoreBridge()

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 画面いっぱいに表示（余白オフ）
        webView?.scrollView.contentInsetAdjustmentBehavior = .never
        
        // JSメッセージハンドラ "native" の登録
        webView?.configuration.userContentController.add(self, name: "native")
        
        // ② StoreBridge に webView を渡す
        store.webView = webView
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }

        // ③ 課金系の処理（t: "purchase" など）なら StoreBridge で処理して終了
        if store.handle(body) { return }

        // ----------------------------------------------------
        // 課金以外の既存処理（action: "cloudSave" 等）
        // ----------------------------------------------------
        guard let action = body["action"] as? String else { return }

        switch action {
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

    func evaluateJS(_ script: String) {
        DispatchQueue.main.async {
            self.webView?.evaluateJavaScript(script, completionHandler: nil)
        }
    }
}

// ====================================================
// StoreBridge（課金処理クラス）
// ====================================================
@MainActor
final class StoreBridge {

    weak var webView: WKWebView?
    private var updatesTask: Task<Void, Never>?

    init() {
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

    deinit { updatesTask?.cancel() }

    // MARK: - 振り分け

    @discardableResult
    func handle(_ body: [String: Any]) -> Bool {
        guard let t = body["t"] as? String else { return false }
        switch t {
        case "purchase":
            let id = body["id"] as? String ?? ""
            let coveredBy = body["coveredBy"] as? [String] ?? []
            print("[IAP] purchase requested: \(id)")
            Task { await purchase(id, coveredBy: coveredBy) }
            return true
        case "restore":
            print("[IAP] restore requested")
            Task { await restore() }
            return true
        case "entitlements":
            Task { await sendEntitlements() }
            return true
        case "prices":
            let ids = body["ids"] as? [String] ?? []
            Task { await sendPrices(ids) }
            return true
        default:
            return false
        }
    }

    // MARK: - 購入

    private func purchase(_ id: String, coveredBy: [String]) async {
        guard !id.isEmpty else { done(id, false); return }

        let owned = await currentIDs()
        if !Set(coveredBy).isDisjoint(with: owned) {
            print("[IAP] \(id) is already covered by a set; not charging")
            js("window.KingCats.entitlements(\(json(owned)))")
            done(id, true)
            return
        }

        do {
            let products = try await Product.products(for: [id])
            guard let product = products.first else {
                print("[IAP] ❌ product not found: \(id)")
                done(id, false)
                return
            }
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    print("[IAP] ✅ purchased: \(id)")
                    done(id, true)
                case .unverified(_, let error):
                    print("[IAP] ❌ unverified: \(error)")
                    done(id, false)
                }
            case .userCancelled:
                print("[IAP] cancelled: \(id)")
                done(id, false)
            case .pending:
                print("[IAP] pending: \(id)")
                done(id, false)
            @unknown default:
                done(id, false)
            }
        } catch {
            print("[IAP] ❌ error: \(error)")
            done(id, false)
        }
    }

    // MARK: - 復元・所持

    private func restore() async {
        do { try await AppStore.sync() } catch { print("[IAP] sync error: \(error)") }
        let ids = await currentIDs()
        print("[IAP] restored: \(ids)")
        js("window.KingCats.restoreDone(\(json(ids)))")
    }

    private func sendEntitlements() async {
        let ids = await currentIDs()
        js("window.KingCats.entitlements(\(json(ids)))")
    }

    private func currentIDs() async -> [String] {
        var ids: [String] = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.revocationDate == nil {
                ids.append(t.productID)
            }
        }
        return ids
    }

    // MARK: - 現地価格

    private func sendPrices(_ ids: [String]) async {
        guard !ids.isEmpty else { return }
        do {
            let products = try await Product.products(for: ids)
            print("[IAP] prices loaded: \(products.count) / \(ids.count)")
            let list: [[String: Any]] = products.map { p in
                [
                    "id": p.id,
                    "display": p.displayPrice,
                    "value": (p.price as NSDecimalNumber).doubleValue,
                    "currency": p.priceFormatStyle.currencyCode
                ]
            }
            js("window.KingCats.prices(\(json(list)))")
        } catch {
            print("[IAP] prices error: \(error)")
        }
    }

    // MARK: - HTML へ返す

    private func done(_ id: String, _ ok: Bool) {
        js("window.KingCats.purchaseDone(\(json(id)), \(ok ? "true" : "false"))")
    }

    private func json(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
              let s = String(data: data, encoding: .utf8) else { return "null" }
        return s
    }

    private func js(_ script: String) {
        webView?.evaluateJavaScript(script) { _, error in
            if let error { print("[IAP] JS error: \(error)  script: \(script.prefix(120))") }
        }
    }
}