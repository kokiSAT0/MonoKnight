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

    /// 同意フローが完了したかどうかを保持するフラグ
    /// - NOTE: `UserDefaults` と連携し、次回以降はスキップする
    @AppStorage("has_completed_consent_flow") private var hasCompletedConsentFlow: Bool = false

    /// ユーザーが選択したテーマモードを永続化する。デフォルトはシステム設定に追従する。
    /// - NOTE: RawValue を直接保存し、列挙型との変換は `themePreference` プロパティで一元管理する。
    @AppStorage("preferred_color_scheme") private var preferredColorSchemeRawValue: String = ThemePreference.system.rawValue

    /// `@AppStorage` から復元した値を `ThemePreference` に変換して利用するためのヘルパー
    /// - Returns: 不正な値が保存されていた場合でも `.system` にフォールバックする。
    private var themePreference: ThemePreference {
        ThemePreference(rawValue: preferredColorSchemeRawValue) ?? .system
    }

    /// 初期化時に環境変数を確認してモックの使用有無を決定する
    init() {
        // MARK: グローバルエラーハンドラの設定
        // デバッグ中にどこでクラッシュしても詳細な情報を得られるようにする
        ErrorReporter.setup()
        // MARK: サービスのインスタンス確定
        // UI テスト環境ではモックを、それ以外では実サービスを採用
        if ProcessInfo.processInfo.environment["UITEST_MODE"] != nil {
            // UI テストではモックを利用して即時認証・ダミー広告を表示
            let mockGameCenter = MockGameCenterService()
            let mockAds = MockAdsService()
            let mockStore = MockStoreService()
            self.gameCenterService = mockGameCenter
            self.adsService = mockAds
            _storeService = StateObject(wrappedValue: AnyStoreService(base: mockStore))
        } else {
            // 通常起動時はシングルトンを利用
            let liveGameCenter = GameCenterService.shared
            let liveAds = AdsService.shared
            let liveStore = StoreService.shared
            self.gameCenterService = liveGameCenter
            self.adsService = liveAds
            _storeService = StateObject(wrappedValue: AnyStoreService(base: liveStore))
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
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
            // MARK: テーマ適用
            // `Group` に適用することで、内部のどの画面が表示されていてもユーザー設定が反映される。
            .preferredColorScheme(themePreference.preferredColorScheme)
            // - NOTE: `environmentObject` に乗せておくと、将来的に他画面からも購買状況を参照しやすくなる
            .environmentObject(storeService)
            // MARK: フォアグラウンド復帰時の Game Center 再認証
            // scenePhase が `.active` へ変化したときに再度認証を試み、バックグラウンド中に切断されていても即座に復帰させる
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                debugLog("MonoKnightApp: scenePhase が active へ遷移したため Game Center 認証を再試行します")
                gameCenterService.authenticateLocalPlayer(completion: nil)
                // MARK: クラッシュ履歴の定期レビュー
                // アプリがフォアグラウンドへ戻ったタイミングでログを要約出力し、問題の早期発見につなげる
                CrashFeedbackCollector.shared.logSummary(label: "scenePhase active", latestCount: 3)
                // 直近にクラッシュやフィードバックがあればレビュー済みの履歴としてマークする
                _ = CrashFeedbackCollector.shared.markReviewCompletedIfNeeded(
                    note: "scenePhase active で自動レビュー",
                    reviewer: "自動チェック"
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

