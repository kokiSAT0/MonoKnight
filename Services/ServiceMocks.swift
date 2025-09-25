#if canImport(UIKit)
import Game   // GameMode.Identifier を扱うために追加
import UIKit
import SwiftUI

/// Game Center の動作を即時成功させる UI テスト用モック
// プロトコル側が MainActor 隔離のため、モック実装もメインスレッド上での実行を強制してコンパイルエラーを防ぐ
@MainActor
final class MockGameCenterService: GameCenterServiceProtocol {
    /// 認証状態を保持するプロパティ
    var isAuthenticated: Bool = false

    /// 即座に認証成功とし、コールバックを呼び出す
    func authenticateLocalPlayer(completion: ((Bool) -> Void)?) {
        isAuthenticated = true
        completion?(true)
    }

    /// スコア送信は行わないダミー実装
    func submitScore(_ score: Int, for modeIdentifier: GameMode.Identifier) {}

    /// ランキング表示も行わないダミー実装
    func showLeaderboard(for modeIdentifier: GameMode.Identifier) {}
}

/// インタースティシャル広告をダミー表示する UI テスト用モック
// AdsServiceProtocol が MainActor を要求するため、UI 操作を安全に扱うべくモックもメインアクターへ明示的に載せる
@MainActor
final class MockAdsService: AdsServiceProtocol {
    /// 無効化フラグ。IAP などで広告を停止したケースを再現
    private var isDisabled = false

    /// ダミー広告を全画面で表示する
    func showInterstitial() {
        guard !isDisabled else { return }
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        // モック用の簡易ビューを作成して表示
        let vc = UIHostingController(rootView: MockAdView())
        vc.modalPresentationStyle = .fullScreen
        root.present(vc, animated: true)
    }

    /// フラグ操作は不要なので空実装
    func resetPlayFlag() {}

    /// 広告読み込み停止も不要なので空実装
    func disableAds() { isDisabled = true }

    /// ATT 許可ダイアログは表示しないダミー実装
    func requestTrackingAuthorization() async {}

    /// UMP 同意フォームも表示しないダミー実装
    func requestConsentIfNeeded() async {}

    /// 同意状況の再評価も行わないダミー実装
    func refreshConsentStatus() async {}

    /// ダミー広告ビュー
    private struct MockAdView: View {
        @Environment(\.dismiss) private var dismiss
        var body: some View {
            ZStack {
                Color.black
                Text("Test Ad")
                    .foregroundColor(.white)
            }
            .ignoresSafeArea()
            .accessibilityIdentifier("dummy_interstitial_ad")
            .onTapGesture { dismiss() }
        }
    }
}

/// StoreKit の購入フローを即座に成功させる UI テスト用モック
// StoreServiceProtocol が MainActor に制約されており、Swift 6 ビルドでの隔離違反を避けるためメインアクターを宣言
@MainActor
final class MockStoreService: ObservableObject, StoreServiceProtocol {
    /// 広告除去が購入済みかどうかのフラグ
    @Published private(set) var isRemoveAdsPurchased: Bool
    /// 価格表示用のテキスト（テスト用に任意の値を設定できる）
    @Published private(set) var removeAdsPriceText: String?

    /// - Parameters:
    ///   - isPurchased: 初期状態で購入済みにするかどうか。
    ///   - priceText: 画面に表示する価格文言。`nil` にするとローディング表示を再現できる。
    init(isPurchased: Bool = false, priceText: String? = "¥320") {
        self.isRemoveAdsPurchased = isPurchased
        self.removeAdsPriceText = priceText
    }

    /// プロダクト情報の取得は不要なので何もしない。
    func refreshProducts() async {}

    /// 購入操作を実行すると即座にフラグを立てる。
    func purchaseRemoveAds() async {
        isRemoveAdsPurchased = true
    }

    /// 復元操作は常に成功したものとして扱う。
    func restorePurchases() async -> Bool {
        isRemoveAdsPurchased = true
        return true
    }
}
#endif
