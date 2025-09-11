import SwiftUI

// MARK: - MonoKnight アプリのエントリーポイント
// `@main` 属性を付与した構造体からアプリが開始される
@main
/// アプリ全体のライフサイクルを管理する構造体
struct MonoKnightApp: App {
    /// Game Center と広告サービスのインスタンスを保持する
    /// - NOTE: UI テスト時はモック、本番ではシングルトンを利用する
    /// - IMPORTANT: `init` 内で一度だけ代入し、その後は変更しない
    private var gameCenterService: GameCenterServiceProtocol
    /// 広告サービスのインスタンス（上記と同様に `init` で確定）
    private var adsService: AdsServiceProtocol

    /// 同意フローが完了したかどうかを保持するフラグ
    /// - NOTE: `UserDefaults` と連携し、次回以降はスキップする
    @AppStorage("has_completed_consent_flow") private var hasCompletedConsentFlow: Bool = false

    /// 初期化時に環境変数を確認してモックの使用有無を決定する
    init() {
        // MARK: グローバルエラーハンドラの設定
        // デバッグ中にどこでクラッシュしても詳細な情報を得られるようにする
        ErrorReporter.setup()
        // MARK: サービスのインスタンス確定
        // UI テスト環境ではモックを、それ以外では実サービスを採用
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

