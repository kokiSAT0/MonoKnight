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
    /// 日替わりチャレンジの挑戦回数を管理するストア
    @StateObject private var dailyChallengeAttemptStore: AnyDailyChallengeAttemptStore
    /// 日替わりチャレンジのレギュレーション定義を提供するサービス
    @StateObject private var dailyChallengeDefinitionService: DailyChallengeDefinitionService
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
        _dailyChallengeAttemptStore = StateObject(
            wrappedValue: dependencies.dailyChallengeAttemptStore
        )
        _dailyChallengeDefinitionService = StateObject(
            wrappedValue: dependencies.dailyChallengeDefinitionService
        )
        _gameSettingsStore = StateObject(wrappedValue: dependencies.gameSettingsStore)
    }

    var body: some Scene {
        WindowGroup {
            RootAppContent(
                hasCompletedConsentFlow: hasCompletedConsentFlow,
                gameCenterService: gameCenterService,
                adsService: adsService,
                storeService: storeService,
                dailyChallengeAttemptStore: dailyChallengeAttemptStore,
                dailyChallengeDefinitionService: dailyChallengeDefinitionService,
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

// MARK: - テーマ設定サポート
// `ThemePreference` をこのファイル内に定義しておくことで、Xcode プロジェクトに確実に読み込まれ、
// `SettingsView` など他の画面からも利用しやすくする。
/// ユーザーが選択可能なテーマモードを一元管理する列挙型
/// - NOTE: RawValue に文字列を採用し、`@AppStorage` と組み合わせることで永続化を容易にしている
enum ThemePreference: String, CaseIterable, Identifiable {
    /// システム設定に追従する（デフォルト）。環境から提供されるカラースキームをそのまま適用する。
    case system
    /// 常にライトモードで表示する。暗所でも視認しやすい配色を維持したいユーザー向け。
    case light
    /// 常にダークモードで表示する。OLED 端末での省電力や夜間プレイ重視のユーザー向け。
    case dark

    /// `Identifiable` 準拠用の一意識別子。`ForEach` などのリスト表示で活用する。
    var id: String { rawValue }

    /// `.preferredColorScheme(_)` に渡すための SwiftUI 標準 `ColorScheme?`
    /// - Returns: システム追従時は `nil` を返し、SwiftUI に環境依存の挙動を委ねる。
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    /// 設定画面などで表示するローカライズ済みの名称
    /// - Important: 日本語 UI を前提にしているため、明示的に和訳した文言を保持する。
    var displayName: String {
        switch self {
        case .system:
            return "システムに合わせる"
        case .light:
            return "ライト"
        case .dark:
            return "ダーク"
        }
    }
}
