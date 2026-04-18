import SwiftUI
import Game
import SharedSupport // 共有ログユーティリティを利用するために追加

/// ゲームプレイとタイトル画面を統括するルートビュー
/// タイトル画面での設定シート表示やゲーム開始フローをまとめて制御する
@MainActor
/// SwiftUI ビュー全体を MainActor 上で扱い、MainActor 隔離されたシングルトン（GameCenterService / AdsService）へアクセスする際の競合を防ぐ
/// - NOTE: Swift 6 で厳格化された並行性モデルに追従し、ビルドエラー（MainActor 分離違反）を確実に回避するための指定
struct RootView: View {
    /// 画面全体の配色を揃えるためのテーマ。タブやトップバーの背景色を一元管理するためここで生成する
    var theme = AppTheme()
    /// Game モジュール側の公開インターフェース束を保持し、GameView へ確実に注入できるようにする
    /// - NOTE: 依存をまとめておくことで、将来的にモック実装へ切り替える際も RootView の初期化だけで完結させられる
    let gameInterfaces: GameModuleInterfaces
    /// Game Center 連携を扱うサービス（プロトコル型で受け取る）
    let gameCenterService: GameCenterServiceProtocol
    /// 広告表示を扱うサービス（GameView へ受け渡す）
    let adsService: AdsServiceProtocol
    /// 日替わりチャレンジの挑戦回数ストア
    let dailyChallengeAttemptStore: AnyDailyChallengeAttemptStore
    /// 日替わりチャレンジのレギュレーション定義サービス
    let dailyChallengeDefinitionService: DailyChallengeDefinitionProviding
    /// ユーザー設定を集約したストア
    let gameSettingsStore: GameSettingsStore
    /// キャンペーンステージ定義を参照するライブラリ
    let campaignLibrary = CampaignLibrary.shared
    /// デバイスの横幅サイズクラスを参照し、iPad などレギュラー幅での余白やログ出力を調整する
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    /// 画面全体の状態とログ出力を一元管理するステートストア
    /// - NOTE: onChange 連鎖による複雑な型推論を避け、プロパティ監視をクラス内の didSet へ集約する
    @StateObject var stateStore: RootViewStateStore
    /// ゲーム準備のワークアイテムと開始待ち状態を調停する coordinator
    @StateObject var preparationCoordinator = RootViewPreparationCoordinator()
    /// キャンペーン進捗を管理するストア
    @StateObject var campaignProgressStore: CampaignProgressStore
    /// タイトル画面まわりの遷移要求をまとめる coordinator
    let titleFlowCoordinator = RootViewTitleFlowCoordinator()
    /// Game Center の認証要求と再サインイン促しをまとめる補助
    let gameCenterPromptPresenter = RootViewGameCenterPromptPresenter()
    /// 依存サービスを外部から注入可能にする初期化処理
    /// - Parameters:
    ///   - gameCenterService: Game Center 連携用サービス（デフォルトはシングルトン）
    ///   - adsService: 広告表示用サービス（デフォルトはシングルトン）
    init(gameInterfaces: GameModuleInterfaces = .live,
         gameCenterService: GameCenterServiceProtocol? = nil,
         adsService: AdsServiceProtocol? = nil,
         dailyChallengeAttemptStore: AnyDailyChallengeAttemptStore? = nil,
         dailyChallengeDefinitionService: DailyChallengeDefinitionProviding? = nil,
         gameSettingsStore: GameSettingsStore? = nil) {
        // Swift 6 ではデフォルト引数の評価が非分離コンテキストで行われるため、
        // `@MainActor` に隔離されたシングルトンを安全に利用するためにイニシャライザ内で解決する。
        let resolvedGameCenterService = gameCenterService ?? GameCenterService.shared
        let resolvedAdsService = adsService ?? AdsService.shared
        let resolvedDailyStore = dailyChallengeAttemptStore ?? AnyDailyChallengeAttemptStore(base: DailyChallengeAttemptStore())
        let resolvedDailyDefinitionService = dailyChallengeDefinitionService ?? DailyChallengeDefinitionService()
        let resolvedGameSettingsStore = gameSettingsStore ?? GameSettingsStore()

        self.gameInterfaces = gameInterfaces
        self.gameCenterService = resolvedGameCenterService
        self.adsService = resolvedAdsService
        self.dailyChallengeAttemptStore = resolvedDailyStore
        self.dailyChallengeDefinitionService = resolvedDailyDefinitionService
        self.gameSettingsStore = resolvedGameSettingsStore
        // 画面状態を一括管理するステートストアを生成し、初期認証状態を反映する。
        _stateStore = StateObject(
            wrappedValue: RootViewStateStore(
                initialIsAuthenticated: resolvedGameCenterService.isAuthenticated
            )
        )
        _campaignProgressStore = StateObject(wrappedValue: CampaignProgressStore())
    }

    var body: some View {
        attachRootStateObservers(
            to: GeometryReader { geometry in
                // MARK: - GeometryReader が提供するサイズや safe area を専用コンテキストへまとめ、下層ビューへシンプルに引き渡す
                let layoutContext = makeLayoutContext(from: geometry)

                // MARK: - 生成済みのコンテキストを使い、型階層の浅いサブビューへ委譲して型チェック負荷を分散する
                makeRootContentView(with: layoutContext)
            }
        )
        .environmentObject(dailyChallengeAttemptStore)
        .environmentObject(gameSettingsStore)
        .task {
            // 初回表示時に Game Center 認証を 1 度だけ試み、UI の表示ズレを防ぐ
            gameCenterPromptPresenter.performInitialAuthenticationIfNeeded(
                stateStore: stateStore,
                gameCenterService: gameCenterService
            )
        }
    }
}

// MARK: - 画面状態ストア
@MainActor
final class RootViewStateStore: ObservableObject {
    /// Game Center 認証済みかどうか
    @Published var isAuthenticated: Bool {
        didSet {
            guard oldValue != isAuthenticated else { return }
            debugLog("RootView.isAuthenticated 更新: \(isAuthenticated)")
        }
    }
    /// タイトル画面の表示/非表示
    @Published var isShowingTitleScreen: Bool {
        didSet {
            guard oldValue != isShowingTitleScreen else { return }
            debugLog("RootView.isShowingTitleScreen 更新: \(isShowingTitleScreen)")
        }
    }
    /// ゲーム準備中（ローディング状態）かどうか
    @Published var isPreparingGame: Bool {
        didSet {
            guard oldValue != isPreparingGame else { return }
            debugLog("RootView.isPreparingGame 更新: \(isPreparingGame)")
        }
    }
    /// ゲーム開始準備が完了し、ユーザーの開始操作待ちかどうか
    @Published var isGameReadyForManualStart: Bool {
        didSet {
            guard oldValue != isGameReadyForManualStart else { return }
            debugLog("RootView.isGameReadyForManualStart 更新: \(isGameReadyForManualStart)")
        }
    }
    /// 実際にプレイへ適用しているモード
    @Published var activeMode: GameMode {
        didSet {
            guard oldValue != activeMode else { return }
            debugLog("RootView.activeMode 更新: \(activeMode.identifier.rawValue)")
        }
    }
    /// GameView の再生成に利用するセッション ID
    @Published var gameSessionID: UUID {
        didSet {
            guard oldValue != gameSessionID else { return }
            debugLog("RootView.gameSessionID 更新: \(gameSessionID)")
        }
    }
    /// トップバーの実測高さ
    @Published var topBarHeight: CGFloat {
        didSet {
            guard oldValue != topBarHeight else { return }
            debugLog("RootView.topBarHeight 更新: 旧値=\(oldValue), 新値=\(topBarHeight)")
        }
    }
    /// 直近に出力したレイアウトスナップショット
    @Published var lastLoggedLayoutSnapshot: RootView.RootLayoutSnapshot?
    /// タイトル設定シートの表示状態
    @Published var isPresentingTitleSettings: Bool {
        didSet {
            guard oldValue != isPresentingTitleSettings else { return }
            debugLog("RootView.isPresentingTitleSettings 更新: \(isPresentingTitleSettings)")
        }
    }
    /// Game Center へのサインインを促すアラート情報
    /// - Important: 直前と同じ理由でも再掲示できるように `GameCenterSignInPrompt` を利用して一意 ID を保持する
    @Published var gameCenterSignInPrompt: GameCenterSignInPrompt? {
        didSet {
            guard oldValue?.id != gameCenterSignInPrompt?.id else { return }
            debugLog("RootView.gameCenterSignInPrompt 更新: reason=\(String(describing: gameCenterSignInPrompt?.reason))")
        }
    }
    /// 直近でゲーム準備を開始した文脈
    @Published var lastPreparationContext: GamePreparationContext? {
        didSet {
            guard oldValue != lastPreparationContext else { return }
            debugLog("RootView.lastPreparationContext 更新: \(String(describing: lastPreparationContext?.logIdentifier))")
        }
    }
    /// タイトル画面で再表示したいナビゲーション先
    /// - NOTE: ローディング中に戻った際も NavigationStack が目的の画面を即座に復元できるようにする
    @Published var pendingTitleNavigationTarget: TitleNavigationTarget? {
        didSet {
            guard oldValue != pendingTitleNavigationTarget else { return }
            debugLog("RootView.pendingTitleNavigationTarget 更新: target=\(String(describing: pendingTitleNavigationTarget?.rawValue))")
        }
    }
    /// Game Center 認証の初回試行を完了したかどうか
    /// - NOTE: RootView が再描画されても `authenticateLocalPlayer` を重複呼び出ししないよう制御する
    private(set) var hasAttemptedInitialAuthentication: Bool
    /// 初期化時に必要な値をまとめて受け取り、SwiftUI の `@StateObject` から利用できるようにする
    /// - Parameter initialIsAuthenticated: Game Center 認証済みかどうかの初期値
    init(initialIsAuthenticated: Bool) {
        self.isAuthenticated = initialIsAuthenticated
        self.isShowingTitleScreen = true
        self.isPreparingGame = false
        self.isGameReadyForManualStart = false
        self.activeMode = .standard
        self.gameSessionID = UUID()
        self.topBarHeight = 0
        self.lastLoggedLayoutSnapshot = nil
        self.isPresentingTitleSettings = false
        self.gameCenterSignInPrompt = nil
        self.lastPreparationContext = nil
        self.pendingTitleNavigationTarget = nil
        self.hasAttemptedInitialAuthentication = false
    }

    /// `@Published` プロパティへのバインディングを生成する補助メソッド
    /// - Parameter keyPath: 取得したいプロパティへの書き込み可能キー・パス
    /// - Returns: SwiftUI から利用できる `Binding`
    func binding<Value>(for keyPath: ReferenceWritableKeyPath<RootViewStateStore, Value>) -> Binding<Value> {
        Binding(
            get: { self[keyPath: keyPath] },
            set: { self[keyPath: keyPath] = $0 }
        )
    }

    /// 初回認証試行のフラグを更新し、まだ実行していない場合のみ true を返す
    /// - Returns: 認証を実行してよい場合は true、すでに試行済みなら false
    func markInitialAuthenticationAttemptedIfNeeded() -> Bool {
        guard !hasAttemptedInitialAuthentication else { return false }
        hasAttemptedInitialAuthentication = true
        return true
    }

    /// Game Center の再サインインを促すアラートを登録する
    /// - Parameter reason: ユーザーへ提示したい理由
    func enqueueGameCenterSignInPrompt(reason: GameCenterSignInPromptReason) {
        gameCenterSignInPrompt = GameCenterSignInPrompt(reason: reason)
    }

    /// サイズクラス変化をログへ出力する
    /// - Parameter newValue: 更新後の横幅サイズクラス
    func logHorizontalSizeClassChange(_ newValue: UserInterfaceSizeClass?) {
        debugLog("RootView.horizontalSizeClass 更新: \(String(describing: newValue))")
    }
}
