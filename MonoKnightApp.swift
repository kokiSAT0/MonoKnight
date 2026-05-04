import SwiftUI
import Game
import SharedSupport // debugLog / debugError など共通ログユーティリティを利用するため追加

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
    /// アプリのライフサイクル変化を検知するためのシーンフェーズ
    @Environment(\.scenePhase) private var scenePhase

    /// StoreKit2 の購買状況を常に監視し、広告除去 IAP の適用状態をアプリ全体へ即時反映するためのオブジェクト
    /// - NOTE: タイプイレースしたラッパー `AnyStoreService` を採用し、UI テストではモックへ容易に差し替えられるようにする
    @StateObject private var storeService: AnyStoreService
    /// アプリ全体で共有するユーザー設定ストア
    @StateObject private var gameSettingsStore: GameSettingsStore
    /// 同意フローが完了したかどうかを保持するフラグ
    /// - NOTE: `UserDefaults` と連携し、次回以降はスキップする
    @AppStorage(StorageKey.AppStorage.hasCompletedConsentFlow) private var hasCompletedConsentFlow: Bool = false

    /// 初期化時に環境変数を確認してモックの使用有無を決定する
    init() {
        ErrorReporter.setup()
        AppBootstrap.configureDiagnosticsViewer()

        let dependencies = AppBootstrap.makeDependencies()
        self.gameCenterService = dependencies.gameCenterService
        self.adsService = dependencies.adsService
        _storeService = StateObject(wrappedValue: dependencies.storeService)
        _gameSettingsStore = StateObject(wrappedValue: dependencies.gameSettingsStore)
    }

    var body: some Scene {
        WindowGroup {
            RootAppContent(
                hasCompletedConsentFlow: hasCompletedConsentFlow,
                gameCenterService: gameCenterService,
                adsService: adsService,
                storeService: storeService,
                gameSettingsStore: gameSettingsStore
            )
            .onChange(of: scenePhase) { _, newPhase in
                AppLifecycleCoordinator.handleScenePhaseChange(
                    newPhase,
                    gameCenterService: gameCenterService
                )
            }
        }
    }
}
