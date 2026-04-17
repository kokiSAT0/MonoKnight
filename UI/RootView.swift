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
    private var theme = AppTheme()
    /// Game モジュール側の公開インターフェース束を保持し、GameView へ確実に注入できるようにする
    /// - NOTE: 依存をまとめておくことで、将来的にモック実装へ切り替える際も RootView の初期化だけで完結させられる
    private let gameInterfaces: GameModuleInterfaces
    /// Game Center 連携を扱うサービス（プロトコル型で受け取る）
    private let gameCenterService: GameCenterServiceProtocol
    /// 広告表示を扱うサービス（GameView へ受け渡す）
    private let adsService: AdsServiceProtocol
    /// 日替わりチャレンジの挑戦回数ストア
    private let dailyChallengeAttemptStore: AnyDailyChallengeAttemptStore
    /// 日替わりチャレンジのレギュレーション定義サービス
    private let dailyChallengeDefinitionService: DailyChallengeDefinitionProviding
    /// ユーザー設定を集約したストア
    private let gameSettingsStore: GameSettingsStore
    /// キャンペーンステージ定義を参照するライブラリ
    private let campaignLibrary = CampaignLibrary.shared
    /// デバイスの横幅サイズクラスを参照し、iPad などレギュラー幅での余白やログ出力を調整する
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// 画面全体の状態とログ出力を一元管理するステートストア
    /// - NOTE: onChange 連鎖による複雑な型推論を避け、プロパティ監視をクラス内の didSet へ集約する
    @StateObject private var stateStore: RootViewStateStore
    /// キャンペーン進捗を管理するストア
    @StateObject private var campaignProgressStore: CampaignProgressStore
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
            performInitialAuthenticationIfNeeded()
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
        // ビューの再生成に影響されない場所でワークアイテムを保持するためここで初期化する
        self.pendingGameActivationWorkItem = nil
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

    /// ローディング表示解除を遅延実行するワークアイテム
    /// - NOTE: SwiftUI ビューの再生成で `@State` が初期化されても保持できるよう、`@StateObject` 管理下へ移動する
var pendingGameActivationWorkItem: DispatchWorkItem?
}

// MARK: - レイアウト支援メソッドと定数
// MARK: - RootView の補助ロジック（ファイル内限定公開）
/// `RootLayoutSnapshot` などをファイル内で共有するため、アクセスレベルを `fileprivate` に統一する
/// - NOTE: Swift 6 のアクセス制御強化に合わせ、関連プロパティのアクセスレベルと矛盾しないように調整している
fileprivate extension RootView {
    /// 初期表示時に Game Center 認証を 1 回だけキックする
    /// - Note: `RootViewStateStore` 側で多重呼び出しを防ぎ、`authenticateLocalPlayer` の UI が何度も提示されないようにする
    private func performInitialAuthenticationIfNeeded() {
        guard stateStore.markInitialAuthenticationAttemptedIfNeeded() else { return }

        handleGameCenterAuthenticationRequest { success in
            // 失敗時は設定画面やリザルト経由で再試行できるようにアラートを掲示する
            if !success {
                presentGameCenterSignInPrompt(for: .initialAuthenticationFailed)
            }
        }
    }

    /// Game Center 再認証を促すアラートを表示する
    /// - Parameter reason: ユーザーへ伝える失敗理由
    private func presentGameCenterSignInPrompt(for reason: GameCenterSignInPromptReason) {
        debugLog("RootView: Game Center サインイン促しアラートを要求 reason=\(reason)")
        stateStore.enqueueGameCenterSignInPrompt(reason: reason)
    }

    /// ゲーム中やリザルト画面から受け取ったサインイン要請を一元処理する
    /// - Parameter reason: 再認証を促したい具体的な理由
    private func handleGameCenterSignInRequest(reason: GameCenterSignInPromptReason) {
        presentGameCenterSignInPrompt(for: reason)
    }

    /// GeometryReader の値をまとめ直し、後続の View 生成で毎回同じ初期化コードを書かなくて済むようにする
    /// - Parameter geometry: SwiftUI が渡すレイアウト情報の生値
    /// - Returns: RootView 向けに整理したレイアウトコンテキスト
    func makeLayoutContext(from geometry: GeometryProxy) -> RootLayoutContext {
        RootLayoutContext(
            geometrySize: geometry.size,
            safeAreaInsets: geometry.safeAreaInsets,
            horizontalSizeClass: horizontalSizeClass
        )
    }

    /// RootView 本体の `body` から切り離したメソッドで、サブビュー生成ロジックを共通化する
    /// - Parameter layoutContext: GeometryReader から構築したレイアウト情報
    /// - Returns: 依存サービスや状態をバインディングした `RootContentView`
    /// - Note: 戻り値である `RootContentView` が private 構造体であるため、
    ///         アクセスレベルを private へ明示して Swift 6 のアクセス制御要件を満たす
    private func makeRootContentView(with layoutContext: RootLayoutContext) -> RootContentView {
        RootContentView(
            theme: theme,
            layoutContext: layoutContext,
            gameInterfaces: gameInterfaces,
            gameCenterService: gameCenterService,
            adsService: adsService,
            campaignLibrary: campaignLibrary,
            campaignProgressStore: campaignProgressStore,
            dailyChallengeDefinitionService: dailyChallengeDefinitionService,
            dailyChallengeAttemptStore: dailyChallengeAttemptStore,
            isAuthenticated: stateStore.binding(for: \.isAuthenticated),
            isShowingTitleScreen: stateStore.binding(for: \.isShowingTitleScreen),
            isPreparingGame: stateStore.binding(for: \.isPreparingGame),
            isGameReadyForManualStart: stateStore.binding(for: \.isGameReadyForManualStart),
            activeMode: stateStore.binding(for: \.activeMode),
            gameSessionID: stateStore.binding(for: \.gameSessionID),
            topBarHeight: stateStore.binding(for: \.topBarHeight),
            lastLoggedLayoutSnapshot: stateStore.binding(for: \.lastLoggedLayoutSnapshot),
            isPresentingTitleSettings: stateStore.binding(for: \.isPresentingTitleSettings),
            lastPreparationContext: stateStore.binding(for: \.lastPreparationContext),
            pendingTitleNavigationTarget: stateStore.binding(for: \.pendingTitleNavigationTarget),
            onRequestGameCenterSignInPrompt: handleGameCenterSignInRequest,
            onStartGame: { mode, context in
                // タイトル画面から受け取ったモードでゲーム準備フローを実行する
                startGamePreparation(for: mode, context: context)
            },
            onReturnToTitle: {
                // GameView からの戻る要求をハンドリングし、タイトル表示へ切り替える
                handleReturnToTitleRequest()
            },
            onReturnToCampaignStageSelection: {
                // キャンペーン由来の準備で戻る場合はステージ選択画面へ直接復帰させる
                handleReturnToCampaignStageSelectionRequest()
            },
            onConfirmGameStart: {
                // ローディング完了後の開始操作を受け取り、ゲームをスタートさせる
                finishGamePreparationAndStart()
            }
        )
    }

    /// `body` 末尾に連なっていた状態監視やシート表示を 1 つの修飾子へ集約し、型推論を単純化する
    /// - Parameter content: 観測対象となるコンテンツ
    /// - Returns: 各種ロギング・シート表示を適用したビュー
    func attachRootStateObservers<Content: View>(to content: Content) -> some View {
        content
            // PreferenceKey で通知されたトップバー高さをストアへ転送し、didSet 経由でログを出力する
            .onPreferenceChange(TopBarHeightPreferenceKey.self) { newHeight in
                guard stateStore.topBarHeight != newHeight else { return }
                // SwiftUI のレイアウト更新中に ObservableObject を同期更新すると
                // 「Publishing changes from within view updates is not allowed」警告が発生するため、
                // 次のメインループで反映させて安全に状態を更新する。
                DispatchQueue.main.async {
                    stateStore.topBarHeight = newHeight
                }
            }
            // サイズクラスの更新のみは Environment 値から取得する必要があるため、専用メソッドでログを残す
            .onChange(of: horizontalSizeClass) { _, newValue in
                stateStore.logHorizontalSizeClassChange(newValue)
            }
            // タイトル設定シートの表示制御。Binding はステートストアから生成する
            .fullScreenCover(isPresented: stateStore.binding(for: \.isPresentingTitleSettings)) {
                // RootView から AdsServiceProtocol を引き渡し、設定画面でも共通プロトコル経由で操作できるようにする。
                SettingsView(
                    adsService: adsService,
                    gameCenterService: gameCenterService,
                    isGameCenterAuthenticated: stateStore.binding(for: \.isAuthenticated)
                )
                    // キャンペーン進捗ストアも同じインスタンスを共有し、デバッグ用パスコード入力で即座に反映されるようにする。
                    .environmentObject(campaignProgressStore)
                    // 日替わりチャレンジの挑戦回数ストアも共有し、設定画面からデバッグ無制限を切り替えられるようにする。
                    .environmentObject(dailyChallengeAttemptStore)
                    .environmentObject(gameSettingsStore)
            }
            // Game Center の再サインインを促すためのアラートを監視する
            .alert(item: stateStore.binding(for: \.gameCenterSignInPrompt)) { prompt in
                Alert(
                    title: Text("Game Center"),
                    message: Text(prompt.reason.message),
                    primaryButton: .default(Text("再試行")) {
                        // 既存アラートを閉じてから認証を再実行する
                        stateStore.gameCenterSignInPrompt = nil
                        handleGameCenterAuthenticationRequest { success in
                            if !success {
                                presentGameCenterSignInPrompt(for: .retryFailed)
                            }
                        }
                    },
                    secondaryButton: .cancel(Text("閉じる"))
                )
            }
    }

    /// GeometryReader から得たレイアウト情報を引き受け、RootView 全体を構築する補助ビュー
    /// - NOTE: View 構築を専用の構造体へ分離することで、RootView 本体が抱えるジェネリック階層を浅くし、
    ///         Xcode の型チェック処理時間を抑える。
    private struct RootContentView: View {
        /// 共通テーマ。背景・トップバーなどで利用する
        let theme: AppTheme
        /// GeometryReader から抽出したサイズや safe area の情報
        let layoutContext: RootLayoutContext
        /// GameView へ渡すゲームモジュールのインターフェース束
        /// - NOTE: ここで受け取っておくことで、親ビューのプロパティへアクセスせずに GameView を安全に初期化できる
        let gameInterfaces: GameModuleInterfaces
        /// Game Center 関連のサービスインスタンス
        let gameCenterService: GameCenterServiceProtocol
        /// 広告制御用サービス
        let adsService: AdsServiceProtocol
        /// キャンペーン定義を参照するライブラリ
        /// - NOTE: 親ビューのプロパティへ直接アクセスするとネスト構造体のインスタンス化時にビルドエラーとなるため、依存として受け取って保持する
        let campaignLibrary: CampaignLibrary
        /// キャンペーン進捗ストア
        @ObservedObject var campaignProgressStore: CampaignProgressStore
        /// 日替わりチャレンジのレギュレーション定義サービス
        let dailyChallengeDefinitionService: DailyChallengeDefinitionProviding
        /// 日替わりチャレンジの挑戦回数ストア
        @ObservedObject var dailyChallengeAttemptStore: AnyDailyChallengeAttemptStore
        /// Game Center 認証状態
        @Binding var isAuthenticated: Bool
        /// タイトル表示中かどうか
        @Binding var isShowingTitleScreen: Bool
        /// ゲーム準備中（ローディング表示中）かどうか
        @Binding var isPreparingGame: Bool
        /// 初期化が完了しユーザー操作待ちかどうか
        @Binding var isGameReadyForManualStart: Bool
        /// 実際にプレイへ適用されているモード
        @Binding var activeMode: GameMode
        /// GameView 再生成用の識別子
        @Binding var gameSessionID: UUID
        /// トップバーの実測高さ
        @Binding var topBarHeight: CGFloat
        /// 直近で記録したレイアウトスナップショット
        @Binding var lastLoggedLayoutSnapshot: RootLayoutSnapshot?
        /// タイトルから設定シートを開くためのフラグ
        @Binding var isPresentingTitleSettings: Bool
        /// 直近のゲーム準備コンテキスト
        @Binding var lastPreparationContext: GamePreparationContext?
        /// タイトルへ戻った際に復元したいナビゲーションターゲット
        @Binding var pendingTitleNavigationTarget: TitleNavigationTarget?
        /// Game Center サインインを促す処理を親へ転送するクロージャ
        let onRequestGameCenterSignInPrompt: (GameCenterSignInPromptReason) -> Void
        /// タイトル画面から開始ボタンが押下された際の処理
        let onStartGame: (GameMode, GamePreparationContext) -> Void
        /// GameView からタイトルへ戻る際の処理
        let onReturnToTitle: () -> Void
        /// キャンペーンのステージ選択へ戻る際の処理
        let onReturnToCampaignStageSelection: () -> Void
        /// ローディング完了後にユーザーが開始ボタンを押した際の処理
        let onConfirmGameStart: () -> Void
        /// 直近でログ出力したスナップショットをローカルに保持し、重複出力と同時にレイアウト警告も防ぐキャッシュ
        @State private var loggedSnapshotCache: RootLayoutSnapshot?
        /// トップバー高さを一度でも正しく計測できたかどうかを追跡するフラグ
        /// - NOTE: シミュレーター初期描画では GeometryReader から 0 が返る場合があり、
        ///         実際には問題が無いにも関わらず警告ログが出力されてしまうため、
        ///         正常値が観測できるまで警告を抑制する目的で利用する
        @State private var hasObservedPositiveTopBarHeight = false
        /// Game Center 未認証トーストに表示する本文
        /// - NOTE: トップバーの常設テキストを廃止した代わりに、一時的なトーストで案内するための状態
        @State private var gameCenterToastMessage: String?
        /// トースト自動閉鎖用のワークアイテム
        /// - NOTE: 表示延長や画面遷移時のキャンセルを制御し、タイマーが多重起動しないようにする
        @State private var gameCenterToastDismissWorkItem: DispatchWorkItem?
        /// トーストを表示する秒数（定数扱いで構造体生成ごとに保持する）
        private let gameCenterToastDisplayDuration: TimeInterval = 4.0

        var body: some View {
            ZStack {
                backgroundLayer
                foregroundLayer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                topStatusInset
            }
            .overlay(alignment: .top) {
                gameCenterUnauthenticatedToast
            }
            .background(layoutDiagnosticOverlay)
            .onAppear {
                // 初期描画時のレイアウト状況をログへ残し、不具合調査を容易にする
                debugLog(
                    "RootView.onAppear: size=\(layoutContext.geometrySize), safeArea(top=\(layoutContext.safeAreaTop), bottom=\(layoutContext.safeAreaBottom)), horizontalSizeClass=\(String(describing: layoutContext.horizontalSizeClass)), authenticated=\(isAuthenticated)"
                )
                // 初回描画時に未サインインなら即座にトーストで通知し、常駐テキストがボタンを覆わないようにする
                if !isAuthenticated && isShowingTitleScreen {
                    showGameCenterUnauthenticatedToast()
                }
            }
            // サインイン状態が変化した際にトースト表示を更新する
            .onChange(of: isAuthenticated) { _, newValue in
                if newValue {
                    // サインイン完了後はトーストを閉じる
                    hideGameCenterUnauthenticatedToast()
                } else if isShowingTitleScreen {
                    // タイトル画面表示中に未認証へ戻った場合は再度トーストを提示する
                    showGameCenterUnauthenticatedToast()
                }
            }
            // タイトル画面とゲーム画面を行き来したときの挙動も制御する
            .onChange(of: isShowingTitleScreen) { _, isTitleVisible in
                if isTitleVisible {
                    // タイトルへ戻ったタイミングで未認証ならトーストを掲出する
                    if !isAuthenticated {
                        showGameCenterUnauthenticatedToast()
                    }
                } else {
                    // ゲームプレイへ遷移したら視界を妨げないように即座に閉じる
                    hideGameCenterUnauthenticatedToast()
                }
            }
            .onDisappear {
                // ビューが破棄される際にタイマーを止めてメモリリークを防ぐ
                cancelGameCenterToastTimer()
            }
        }

        /// 画面全体を覆う背景レイヤー
        private var backgroundLayer: some View {
            theme.backgroundPrimary
                .ignoresSafeArea()
        }

        /// ゲーム本体・ローディング・タイトルを重ね合わせた前景レイヤー
        private var foregroundLayer: some View {
            ZStack {
                gameLayer
                loadingOverlay
                titleOverlay
            }
            .animation(.easeInOut(duration: 0.25), value: isShowingTitleScreen)
            .animation(.easeInOut(duration: 0.25), value: isPreparingGame)
        }

        /// ゲームプレイ画面
        @ViewBuilder
        private var gameLayer: some View {
            if isShowingTitleScreen {
                EmptyView()
            } else {
                GameView(
                    mode: activeMode,
                    gameInterfaces: gameInterfaces,
                    gameCenterService: gameCenterService,
                    adsService: adsService,
                    campaignProgressStore: campaignProgressStore,
                    // RootView から引き継いだバインディングなので、$isPreparingGame をそのまま利用して意図を明確にする
                    isPreparationOverlayVisible: $isPreparingGame,
                    isGameCenterAuthenticated: isAuthenticated,
                    onRequestGameCenterSignIn: onRequestGameCenterSignInPrompt,
                    onRequestReturnToTitle: {
                        // GameView 内からの戻り要求を親へ伝播させる
                        onReturnToTitle()
                    },
                    onRequestStartCampaignStage: { stage in
                        // クリア後に解放されたステージへの即時挑戦リクエストを受け取る
                        // 親から注入された開始ハンドラを利用してゲーム準備をやり直す
                        onStartGame(stage.makeGameMode(), .campaignContinuation)
                    }
                )
                .id(gameSessionID)
                // トップバー高さを Environment へ伝搬し、GameView 側のレイアウト調整に利用する
                .environment(\.topOverlayHeight, topBarHeight)
                // 元の safe area 値を共有し、オーバーレイ分の差分計算を可能にする
                .environment(\.baseTopSafeAreaInset, layoutContext.safeAreaTop)
                // ローディング中は盤面を非表示にしてちらつきを防止する
                .opacity(isPreparingGame ? 0 : 1)
                // ローディング中はタップ操作を受け付けない
                .allowsHitTesting(!isPreparingGame)
            }
        }

        /// ゲーム準備オーバーレイ
        @ViewBuilder
        private var loadingOverlay: some View {
            if isPreparingGame {
                let stage = campaignStage(for: activeMode)
                let progress = stage.flatMap { campaignProgressStore.progress(for: $0.id) }
                let shouldReturnToCampaignSelection = lastPreparationContext?.isCampaignDerived ?? (stage != nil)

                GamePreparationOverlayView(
                    mode: activeMode,
                    campaignStage: stage,
                    progress: progress,
                    isReady: isGameReadyForManualStart,
                    isCampaignContext: shouldReturnToCampaignSelection,
                    onReturnToCampaignSelection: {
                        // ローディング中に戻る操作を受け取り、文脈に応じて復帰先を振り分ける
                        if shouldReturnToCampaignSelection {
                            onReturnToCampaignStageSelection()
                        } else {
                            onReturnToTitle()
                        }
                    },
                    onStart: {
                        // ユーザーが明示的に開始したタイミングでローディングを閉じる
                        onConfirmGameStart()
                    }
                )
                    .transition(.opacity)
            } else {
                EmptyView()
            }
        }

        /// タイトル画面のオーバーレイ
        @ViewBuilder
        private var titleOverlay: some View {
            if isShowingTitleScreen {
                TitleScreenView(
                    campaignProgressStore: campaignProgressStore,
                    dailyChallengeAttemptStore: dailyChallengeAttemptStore,
                    dailyChallengeDefinitionService: dailyChallengeDefinitionService,
                    adsService: adsService,
                    gameCenterService: gameCenterService,
                    pendingNavigationTarget: $pendingTitleNavigationTarget,
                    onStart: { mode, context in
                        // 選択されたモードでゲーム準備を開始する
                        onStartGame(mode, context)
                    },
                    onOpenSettings: {
                        // タイトルから詳細設定シートを開く
                        isPresentingTitleSettings = true
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                EmptyView()
            }
        }

        /// トップステータスバー
        private var topStatusInset: some View {
            TopStatusInsetView(
                context: layoutContext,
                theme: theme
            )
        }

        /// レイアウト監視用の不可視オーバーレイ
        private var layoutDiagnosticOverlay: some View {
            let snapshot = RootLayoutSnapshot(
                context: layoutContext,
                isAuthenticated: isAuthenticated,
                isShowingTitleScreen: isShowingTitleScreen,
                activeMode: activeMode,
                topBarHeight: topBarHeight
            )

            return Color.clear
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .onAppear {
                    logLayoutSnapshot(snapshot, reason: "初期観測")
                }
                .onChange(of: snapshot) { _, newValue in
                    logLayoutSnapshot(newValue, reason: "値更新")
                }
        }

        /// Game Center 未サインイン時に一時的な案内を表示するトースト
        @ViewBuilder
        private var gameCenterUnauthenticatedToast: some View {
            if let message = gameCenterToastMessage {
                Text(message)
                    .font(.footnote)
                    .multilineTextAlignment(.leading)
                    .foregroundColor(theme.textPrimary)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(theme.backgroundElevated.opacity(0.96))
                            .shadow(color: Color.black.opacity(0.2), radius: 14, x: 0, y: 8)
                    )
                    .frame(maxWidth: layoutContext.topBarMaxWidth ?? 440, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, layoutContext.safeAreaTop + 12)
                    // トースト自体はタップを受け付けず、背後のボタン操作を妨げない
                    .allowsHitTesting(false)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityIdentifier("gc_toast")
            }
        }

        /// レイアウトスナップショットをログに出力する
        /// - Parameters:
        ///   - snapshot: 出力対象のスナップショット
        ///   - reason: 出力理由（初期観測・値更新など）
        private func logLayoutSnapshot(_ snapshot: RootLayoutSnapshot, reason: String) {
            // 直近と同じスナップショットであれば何もせず抜け、無限ループを未然に防ぐ
            guard loggedSnapshotCache != snapshot else { return }
            loggedSnapshotCache = snapshot

            // ObservableObject を同期更新すると SwiftUI から警告が出るため、次のメインループで安全に反映させる
            if lastLoggedLayoutSnapshot != snapshot {
                DispatchQueue.main.async {
                    lastLoggedLayoutSnapshot = snapshot
                }
            }

            let message = """
            RootView.layout 観測: 理由=\(reason)
              geometry=\(snapshot.geometrySize)
              safeArea(top=\(snapshot.safeAreaTop), bottom=\(snapshot.safeAreaBottom), leading=\(snapshot.safeAreaLeading), trailing=\(snapshot.safeAreaTrailing))
              horizontalSizeClass=\(snapshot.horizontalSizeClassDescription) topBarPadding=\(snapshot.topBarHorizontalPadding) topBarMaxWidth=\(snapshot.topBarMaxWidthDescription) fallbackTopPadding=\(snapshot.regularTopPaddingFallback)
              states(authenticated=\(snapshot.isAuthenticated), showingTitle=\(snapshot.isShowingTitleScreen), activeMode=\(snapshot.activeModeIdentifier.rawValue), topBarHeight=\(snapshot.topBarHeight))
            """

            debugLog(message)

            if snapshot.topBarHeight > 0 {
                // 一度でも正の高さを観測したらフラグを立て、以降の 0 判定は異常として扱う
                hasObservedPositiveTopBarHeight = true
            }

            if snapshot.topBarHeight <= 0 {
                if snapshot.isAuthenticated {
                    // 表示対象があるのに高さが 0 の場合のみ警告し、想定外の消失を検知する
                    guard hasObservedPositiveTopBarHeight else { return }
                    debugLog("RootView.layout 警告: topBarHeight が 0 以下です。safe area とフォールバック設定を確認してください。")
                } else {
                    // 表示要素がない場合は 0 が正常値のため、フラグをリセットしつつ警告を抑制する
                    hasObservedPositiveTopBarHeight = false
                }
            }
            if snapshot.safeAreaTop < 0 || snapshot.safeAreaBottom < 0 {
                debugLog("RootView.layout 警告: safeArea が負値です。GeometryReader の取得値を再確認してください。")
            }
        }

        /// Game Center 未サインイン案内をトーストで提示する
        private func showGameCenterUnauthenticatedToast() {
            let message = "Game Center 未サインイン。設定画面からサインインするとランキングを利用できます。"
            // 既存タイマーを止めてから表示し直し、連続呼び出しでも秒数が延長されるようにする
            cancelGameCenterToastTimer()

            if gameCenterToastMessage == nil {
                // 初回表示のみアニメーションでフェードインさせる
                withAnimation(.easeInOut(duration: 0.25)) {
                    gameCenterToastMessage = message
                }
            } else {
                // 既に表示中であれば文面だけ最新状態へ更新する
                gameCenterToastMessage = message
            }

            scheduleGameCenterToastAutoDismiss()
        }

        /// 未サインイン案内トーストを閉じる
        private func hideGameCenterUnauthenticatedToast() {
            guard gameCenterToastMessage != nil else { return }
            cancelGameCenterToastTimer()
            withAnimation(.easeInOut(duration: 0.2)) {
                gameCenterToastMessage = nil
            }
        }

        /// トースト自動閉鎖のタイマーを停止する
        private func cancelGameCenterToastTimer() {
            gameCenterToastDismissWorkItem?.cancel()
            gameCenterToastDismissWorkItem = nil
        }

        /// 指定秒数経過後にトーストを自動的に閉じるタイマーを設定する
        private func scheduleGameCenterToastAutoDismiss() {
            var workItem: DispatchWorkItem?
            workItem = DispatchWorkItem {
                guard let workItem, !workItem.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    gameCenterToastMessage = nil
                }
                gameCenterToastDismissWorkItem = nil
            }

            guard let workItem else { return }
            gameCenterToastDismissWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + gameCenterToastDisplayDuration, execute: workItem)
        }

        /// 与えられたモードがキャンペーンステージかどうかを判定し、該当する場合は定義を返す
        /// - Parameter mode: 判定したいモード
        /// - Returns: キャンペーンステージなら定義、該当しなければ nil
        private func campaignStage(for mode: GameMode) -> CampaignStage? {
            // モードからキャンペーンステージを導出できなかった場合も記録し、表示不具合の切り分けに活用する
            guard let metadata = mode.campaignMetadataSnapshot else {
                debugLog("RootView: campaignStage(for:) -> キャンペーンメタデータ未設定 mode=\(mode.identifier.rawValue)")
                return nil
            }
            let stageID = metadata.stageID
            let stage = campaignLibrary.stage(with: stageID)
            if let stage {
                debugLog("RootView: campaignStage(for:) -> ステージ取得成功 stageID=\(stageID.displayCode) 章内タイトル=\(stage.title)")
            } else {
                debugLog("RootView: campaignStage(for:) -> ステージ取得失敗 stageID=\(stageID.displayCode) 章定義を確認してください。")
            }
            return stage
        }
    }

}
