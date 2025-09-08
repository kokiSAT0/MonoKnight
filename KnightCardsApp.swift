import SwiftUI

// MARK: - アプリのエントリーポイント
// `@main` 属性を付与した構造体からアプリが開始される
@main
struct KnightCardsApp: App {
    /// Game Center と広告サービスのインスタンス
    /// - NOTE: UI テスト時はモックを使用する
    private let gameCenterService: GameCenterServiceProtocol
    private let adsService: AdsServiceProtocol

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
            // MARK: 起動直後に表示するルートビュー
            // TabView でゲームと設定を切り替える `RootView` を表示
            RootView(gameCenterService: gameCenterService, adsService: adsService)
        }
    }
}

