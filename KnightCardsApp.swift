import SwiftUI

// MARK: - アプリのエントリーポイント
// `@main` 属性を付与した構造体からアプリが開始される
@main
struct KnightCardsApp: App {
    /// Game Center と広告サービスのインスタンス
    /// - NOTE: UI テスト時はモックを使用する
    private let gameCenterService: GameCenterServiceProtocol
    private let adsService: AdsServiceProtocol

    /// 同意フローが完了したかどうかを保持するフラグ
    /// - NOTE: `UserDefaults` と連携し、次回以降はスキップする
    @AppStorage("has_completed_consent_flow") private var hasCompletedConsentFlow: Bool = false

    /// 初期化時に環境変数を確認してモックの使用有無を決定する
    init() {
        if ProcessInfo.processInfo.environment["UITEST_MODE"] != nil {
            // UI テストではモックを利用して即時認証・ダミー広告を表示
            self.gameCenterService = MockGameCenterService()
            self.adsService = MockAdsService()
        } else {
            // 通常起動時はシングルトンを利用
            self.gameCenterService = GameCenterService.shared
            self.adsService = AdsService.shared
        }
    }

    var body: some Scene {
        WindowGroup {
            // MARK: 起動直後の表示切り替え
            // 初回のみ同意フローを表示し、完了後に `RootView` へ遷移する
            if hasCompletedConsentFlow {
                // 通常時はタブビューを提供するルート画面を表示
                RootView(gameCenterService: gameCenterService, adsService: adsService)
            } else {
                // 同意取得前はオンボーディング画面を表示
                ConsentFlowView(adsService: adsService)
            }
        }
    }
}

