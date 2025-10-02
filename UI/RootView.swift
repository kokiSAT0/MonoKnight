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
         adsService: AdsServiceProtocol? = nil) {
        // Swift 6 ではデフォルト引数の評価が非分離コンテキストで行われるため、
        // `@MainActor` に隔離されたシングルトンを安全に利用するためにイニシャライザ内で解決する。
        let resolvedGameCenterService = gameCenterService ?? GameCenterService.shared
        let resolvedAdsService = adsService ?? AdsService.shared

        self.gameInterfaces = gameInterfaces
        self.gameCenterService = resolvedGameCenterService
        self.adsService = resolvedAdsService
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
    /// - NOTE: `RootLayoutSnapshot` が `fileprivate` 扱いで定義されているため、
    ///         アクセスレベルを合わせて `fileprivate` に揃え、ビルドエラーを避ける
    @Published fileprivate var lastLoggedLayoutSnapshot: RootView.RootLayoutSnapshot?
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
    fileprivate var pendingGameActivationWorkItem: DispatchWorkItem?
}

// MARK: - レイアウト支援メソッドと定数
private extension RootView {
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

    /// 現在のモードに対応するキャンペーンステージを取得する
    /// - Parameter mode: 判定対象のゲームモード
    /// - Returns: キャンペーンステージであれば定義、該当しなければ nil
    func campaignStage(for mode: GameMode) -> CampaignStage? {
        guard let metadata = mode.campaignMetadataSnapshot else { return nil }
        return campaignLibrary.stage(with: metadata.stageID)
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
            isAuthenticated: stateStore.binding(for: \.isAuthenticated),
            isShowingTitleScreen: stateStore.binding(for: \.isShowingTitleScreen),
            isPreparingGame: stateStore.binding(for: \.isPreparingGame),
            isGameReadyForManualStart: stateStore.binding(for: \.isGameReadyForManualStart),
            activeMode: stateStore.binding(for: \.activeMode),
            gameSessionID: stateStore.binding(for: \.gameSessionID),
            topBarHeight: stateStore.binding(for: \.topBarHeight),
            lastLoggedLayoutSnapshot: stateStore.binding(for: \.lastLoggedLayoutSnapshot),
            isPresentingTitleSettings: stateStore.binding(for: \.isPresentingTitleSettings),
            onRequestGameCenterSignInPrompt: handleGameCenterSignInRequest,
            onStartGame: { mode in
                // タイトル画面から受け取ったモードでゲーム準備フローを実行する
                startGamePreparation(for: mode)
            },
            onReturnToTitle: {
                // GameView からの戻る要求をハンドリングし、タイトル表示へ切り替える
                handleReturnToTitleRequest()
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
        /// Game Center サインインを促す処理を親へ転送するクロージャ
        let onRequestGameCenterSignInPrompt: (GameCenterSignInPromptReason) -> Void
        /// タイトル画面から開始ボタンが押下された際の処理
        let onStartGame: (GameMode) -> Void
        /// GameView からタイトルへ戻る際の処理
        let onReturnToTitle: () -> Void
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
                    isGameCenterAuthenticated: isAuthenticated,
                    onRequestGameCenterSignIn: onRequestGameCenterSignInPrompt,
                    onRequestReturnToTitle: {
                        // GameView 内からの戻り要求を親へ伝播させる
                        onReturnToTitle()
                    },
                    onRequestStartCampaignStage: { stage in
                        // クリア後に解放されたステージへの即時挑戦リクエストを受け取る
                        // 親から注入された開始ハンドラを利用してゲーム準備をやり直す
                        onStartGame(stage.makeGameMode())
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

                GamePreparationOverlayView(
                    mode: activeMode,
                    campaignStage: stage,
                    progress: progress,
                    isReady: isGameReadyForManualStart,
                    onCancel: {
                        // ローディング中にタイトルへ戻りたい場合のハンドラを橋渡しする
                        handleReturnToTitleRequest()
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
                    onStart: { mode in
                        // 選択されたモードでゲーム準備を開始する
                        onStartGame(mode)
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

    /// ゲーム開始前のローディング表示を担うオーバーレイビュー
    /// - NOTE: ペナルティ設定やリワード条件を一覧できるよう、スクロール可能なカード型レイアウトで表示する
    /// `private extension` により、この構造体自体は暗黙的に `fileprivate` として扱われる点に注意。
    /// そのため `RootContentView` など同一ファイル内のビューから直接参照でき、
    /// アクセスレベルの指定を二重に付ける必要はない。
    struct GamePreparationOverlayView: View {
        /// 開始予定のゲームモード
        let mode: GameMode
        /// キャンペーンステージ（該当する場合）
        let campaignStage: CampaignStage?
        /// これまでの達成状況
        let progress: CampaignStageProgress?
        /// 初期化が完了して開始可能かどうか
        let isReady: Bool
        /// 「前の画面へ戻る」操作を伝搬するハンドラ
        let onCancel: () -> Void
        /// ユーザーが「開始」ボタンを押した際のハンドラ
        let onStart: () -> Void

        /// テーマを利用してライト/ダーク両対応の配色を適用する
        private let theme: AppTheme

        /// 明示的なイニシャライザを定義し、`private` プロパティを含んでも呼び出し元から利用できるようにする
        /// - Parameters:
        ///   - mode: 開始予定のゲームモード
        ///   - campaignStage: キャンペーンステージ（該当する場合）
        ///   - progress: これまでの達成状況
        ///   - isReady: 初期化が完了して開始可能かどうか
        ///   - onCancel: ユーザーが戻り操作を選んだ際のハンドラ
        ///   - onStart: ユーザーが「開始」を押した際のハンドラ
        fileprivate init(mode: GameMode,
                         campaignStage: CampaignStage?,
                         progress: CampaignStageProgress?,
                         isReady: Bool,
                         onCancel: @escaping () -> Void,
                         onStart: @escaping () -> Void) {
            // 受け取った値をそのまま保持し、構造体生成直後から UI に反映できるようにする
            self.mode = mode
            self.campaignStage = campaignStage
            self.progress = progress
            self.isReady = isReady
            self.onCancel = onCancel
            self.onStart = onStart
            // テーマは常に新規生成し、カラースキームに応じた見た目を再利用する
            self.theme = AppTheme()
        }

        var body: some View {
            ZStack {
                // 盤面全体を薄暗くし、ローディング中であることを視覚的に伝える半透明レイヤー
                Color.black
                    .opacity(LayoutMetrics.dimmedBackgroundOpacity)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                        headerSection
                        penaltySection
                        campaignSummarySection
                        controlSection
                    }
                    .padding(LayoutMetrics.contentPadding)
                }
                .frame(maxWidth: LayoutMetrics.maxContentWidth)
                .background(
                    theme.spawnOverlayBackground
                        .blur(radius: LayoutMetrics.backgroundBlur)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: LayoutMetrics.cornerRadius)
                        .stroke(theme.spawnOverlayBorder, lineWidth: LayoutMetrics.borderWidth)
                )
                .clipShape(RoundedRectangle(cornerRadius: LayoutMetrics.cornerRadius))
                .shadow(
                    color: theme.spawnOverlayShadow,
                    radius: LayoutMetrics.shadowRadius,
                    x: 0,
                    y: LayoutMetrics.shadowOffsetY
                )
                .padding(.horizontal, LayoutMetrics.horizontalSafePadding)
                .accessibilityIdentifier("game_preparation_overlay")
            }
            .transition(.opacity)
        }

        /// ヘッダー（ステージ名と概要）
        private var headerSection: some View {
            VStack(alignment: .leading, spacing: LayoutMetrics.headerSpacing) {
                if let stage = campaignStage {
                    Text(stage.displayCode)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.textSecondary)
                        .accessibilityLabel("ステージ番号 \(stage.displayCode)")

                    Text(stage.title)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.textPrimary)

                    Text(stage.summary)
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundColor(theme.textSecondary)
                } else {
                    Text(mode.displayName)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.textPrimary)

                    Text(mode.primarySummaryText)
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundColor(theme.textSecondary)

                    Text(mode.secondarySummaryText)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(theme.textSecondary)
                }
            }
        }

        /// ペナルティ設定の一覧
        private var penaltySection: some View {
            InfoSection(title: "ペナルティ") {
                ForEach(penaltyItems, id: \.self) { item in
                    bulletRow(text: item)
                }
            }
        }

        /// キャンペーンのリワード条件・記録をまとめた共通ビュー
        private var campaignSummarySection: some View {
            CampaignRewardSummaryView(
                stage: campaignStage,
                progress: progress,
                theme: theme,
                context: .overlay
            )
        }

        /// 初期化状況と開始ボタン
        private var controlSection: some View {
            VStack(alignment: .leading, spacing: LayoutMetrics.controlSpacing) {
                if !isReady {
                    HStack(spacing: LayoutMetrics.rowSpacing) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(theme.accentPrimary)
                        Text("初期化中…")
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundColor(theme.textSecondary)
                    }
                    .accessibilityLabel("初期化中")
                    .accessibilityHint("完了すると開始ボタンが有効になります")
                }

                Button(action: {
                    if isReady {
                        onStart()
                    }
                }) {
                    Text("ステージを開始")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.accentOnPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, LayoutMetrics.buttonVerticalPadding)
                        .background(
                            RoundedRectangle(cornerRadius: LayoutMetrics.buttonCornerRadius)
                                .fill(theme.accentPrimary.opacity(isReady ? 1 : LayoutMetrics.disabledButtonOpacity))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!isReady)
                .accessibilityLabel("ステージを開始")
                .accessibilityHint(isReady ? "ゲームを開始します" : "準備が完了すると押せるようになります")
                // VoiceOver でボタンであることを明示（.disabled 修飾子が自動で無効状態を伝えてくれる）
                .accessibilityAddTraits(.isButton)

                Button(action: {
                    // ユーザーがローディング段階で戻る選択をした際に親へ通知する
                    onCancel()
                }) {
                    Text("前の画面に戻る")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.accentPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, LayoutMetrics.secondaryButtonVerticalPadding)
                        .background(
                            RoundedRectangle(cornerRadius: LayoutMetrics.buttonCornerRadius)
                                .stroke(theme.accentPrimary, lineWidth: LayoutMetrics.secondaryButtonBorderWidth)
                                .background(
                                    RoundedRectangle(cornerRadius: LayoutMetrics.buttonCornerRadius)
                                        .fill(Color.clear)
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("前の画面に戻る")
                .accessibilityHint("タイトルへ戻ります")
                .accessibilityAddTraits(.isButton)
            }
        }

        /// ペナルティ説明文を生成
        private var penaltyItems: [String] {
            [
                mode.deadlockPenaltyCost > 0 ? "手詰まり +\(mode.deadlockPenaltyCost) 手" : "手詰まり ペナルティなし",
                mode.manualRedrawPenaltyCost > 0 ? "引き直し +\(mode.manualRedrawPenaltyCost) 手" : "引き直し ペナルティなし",
                mode.manualDiscardPenaltyCost > 0 ? "捨て札 +\(mode.manualDiscardPenaltyCost) 手" : "捨て札 ペナルティなし",
                mode.revisitPenaltyCost > 0 ? "再訪 +\(mode.revisitPenaltyCost) 手" : "再訪ペナルティなし"
            ]
        }

        /// 箇条書きの 1 行を描画
        /// - Parameter text: 表示したい本文
        private func bulletRow(text: String) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: LayoutMetrics.bulletSpacing) {
                Circle()
                    .fill(theme.textSecondary.opacity(0.6))
                    .frame(width: LayoutMetrics.bulletSize, height: LayoutMetrics.bulletSize)
                    .accessibilityHidden(true)

                Text(text)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(theme.textPrimary)
            }
        }

        /// 情報カード内のセクション共通レイアウト
        private struct InfoSection<Content: View>: View {
            let title: String
            let content: Content

            init(title: String, @ViewBuilder content: () -> Content) {
                self.title = title
                self.content = content()
            }

            var body: some View {
                VStack(alignment: .leading, spacing: LayoutMetrics.sectionContentSpacing) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme().textSecondary)

                    content
                }
            }
        }

        /// レイアウト定数を 1 箇所へ集約し、値の調整を容易にする
        private enum LayoutMetrics {
            /// 背景ディミングの透過率
            static let dimmedBackgroundOpacity: Double = 0.45
            /// コンテンツ全体の最大幅
            static let maxContentWidth: CGFloat = 360
            /// コンテンツ周囲の余白
            static let contentPadding: CGFloat = 28
            /// セクション間の余白
            static let sectionSpacing: CGFloat = 24
            /// セクション内のコンテンツ間隔
            static let sectionContentSpacing: CGFloat = 12
            /// ヘッダー内の行間
            static let headerSpacing: CGFloat = 6
            /// 箇条書きのドットと本文の間隔
            static let bulletSpacing: CGFloat = 8
            /// 箇条書きドットのサイズ
            static let bulletSize: CGFloat = 6
            /// 行要素の基本間隔
            static let rowSpacing: CGFloat = 12
            /// ボタン周辺の余白
            static let controlSpacing: CGFloat = 14
            /// ボタンの角丸
            static let buttonCornerRadius: CGFloat = 16
            /// ボタンの上下パディング
            static let buttonVerticalPadding: CGFloat = 14
            /// セカンダリボタンの上下パディング（メインボタンより軽量な見た目にする）
            static let secondaryButtonVerticalPadding: CGFloat = 12
            /// セカンダリボタンの枠線太さ
            static let secondaryButtonBorderWidth: CGFloat = 1
            /// 無効状態のボタン透過率
            static let disabledButtonOpacity: Double = 0.45
            /// カードの角丸半径
            static let cornerRadius: CGFloat = 24
            /// 枠線の太さ
            static let borderWidth: CGFloat = 1
            /// ドロップシャドウの半径
            static let shadowRadius: CGFloat = 18
            /// ドロップシャドウの縦方向オフセット
            static let shadowOffsetY: CGFloat = 8
            /// 背景に適用するブラー量
            static let backgroundBlur: CGFloat = 0
            /// 端末横幅が狭い場合に備えた左右の安全マージン
            static let horizontalSafePadding: CGFloat = 20
        }
    }

    /// タイトル画面の開始ボタン押下を受けてゲーム準備を開始する
    /// - Parameter mode: ユーザーが選択したゲームモード
    func startGamePreparation(for mode: GameMode) {
        // 連続タップで複数のワークアイテムが走らないように既存処理を必ずキャンセルする
        cancelPendingGameActivationWorkItem()

        debugLog("RootView: ゲーム準備開始リクエストを処理 選択モード=\(mode.identifier.rawValue)")

        // 今回プレイするモードを確定し、タイトル画面側の選択状態とも同期させる
        stateStore.activeMode = mode

        // GameView を強制的に再生成するためセッション ID を更新し、ログで追跡できるよう記録する
        stateStore.gameSessionID = UUID()
        let scheduledSessionID = stateStore.gameSessionID
        debugLog("RootView: 新規ゲームセッションを割り当て sessionID=\(scheduledSessionID)")

        // ゲーム開始準備が完了するまでは開始ボタンを押せないようフラグを下ろしておく
        stateStore.isGameReadyForManualStart = false

        withAnimation(.easeInOut(duration: 0.25)) {
            // タイトルを閉じ、ローディングオーバーレイを表示する
            stateStore.isShowingTitleScreen = false
            stateStore.isPreparingGame = true
        }

        // GameCore / GameView の初期化完了を待つために、一定時間経過後にローディング解除を試みる
        scheduleGameActivationCompletion(for: scheduledSessionID)
    }

    /// GameView からタイトル画面へ戻る操作をハンドリングし、状態を初期化する
    func handleReturnToTitleRequest() {
        debugLog("RootView: タイトル画面表示要求を受信 現在モード=\(stateStore.activeMode.identifier.rawValue)")

        // 進行中のローディングがあれば破棄し、表示をただちに止める
        cancelPendingGameActivationWorkItem()

        if stateStore.isPreparingGame {
            debugLog("RootView: ローディング表示中にタイトルへ戻るため強制的に解除します")
        }

        // ローディング状態は即時で解除し、タイトル遷移のみアニメーションさせる
        stateStore.isPreparingGame = false
        stateStore.isGameReadyForManualStart = false

        withAnimation(.easeInOut(duration: 0.25)) {
            stateStore.isShowingTitleScreen = true
        }
    }

    /// ローディング解除処理を一定時間後に実行する
    /// - Parameter sessionID: 解除対象となるゲームセッションの識別子
    func scheduleGameActivationCompletion(for sessionID: UUID) {
        // 既存のワークアイテムは startGamePreparation 内で必ずキャンセル済みの想定
        let workItem = DispatchWorkItem { [weak stateStore, sessionID] in
            // SwiftUI のビュー階層が破棄されている場合は安全に終了する
            guard let stateStore else {
                debugLog("RootView: 状態ストアが解放済みのためゲーム準備ワークアイテムを終了 sessionID=\(sessionID)")
                return
            }

            // キャンセル済み（もしくは新しいゲーム開始で破棄済み）の場合は何もせず終了する
            guard stateStore.pendingGameActivationWorkItem != nil else {
                debugLog("RootView: ゲーム準備ワークアイテムが実行前に破棄されました sessionID=\(sessionID)")
                return
            }

            // ゲームセッション ID が変化している場合は古いリクエストなので破棄する
            guard sessionID == stateStore.gameSessionID else {
                debugLog("RootView: ゲーム準備完了通知を破棄 scheduled=\(sessionID) current=\(stateStore.gameSessionID)")
                return
            }

            debugLog("RootView: ゲーム準備完了 手動開始待ちへ移行 sessionID=\(sessionID)")

            stateStore.isGameReadyForManualStart = true

            // 再利用を防ぐため参照を破棄する
            stateStore.pendingGameActivationWorkItem = nil
        }

        stateStore.pendingGameActivationWorkItem = workItem

        DispatchQueue.main.asyncAfter(
            deadline: .now() + RootLayoutMetrics.gamePreparationMinimumDelay,
            execute: workItem
        )
    }

    /// ローディング表示解除用のワークアイテムをキャンセルし、参照をクリアする
    func cancelPendingGameActivationWorkItem() {
        guard let workItem = stateStore.pendingGameActivationWorkItem else { return }
        debugLog("RootView: 保留中のゲーム準備ワークアイテムをキャンセル sessionID=\(stateStore.gameSessionID)")
        workItem.cancel()
        stateStore.pendingGameActivationWorkItem = nil
        stateStore.isGameReadyForManualStart = false
    }

    /// ローディング完了後にユーザーが開始ボタンを押した際の処理
    func finishGamePreparationAndStart() {
        // 既にローディングが閉じられている場合は何もしない
        guard stateStore.isPreparingGame else { return }

        debugLog("RootView: ユーザー操作によりゲームを開始")

        withAnimation(.easeInOut(duration: 0.25)) {
            stateStore.isPreparingGame = false
        }
        stateStore.isGameReadyForManualStart = false
    }

    /// Game Center 認証 API 呼び出しをカプセル化し、ビュー側からの参照を単純化する
    /// - Parameter completion: 認証成功可否を受け取るクロージャ
    private func handleGameCenterAuthenticationRequest(completion: @escaping (Bool) -> Void) {
        gameCenterService.authenticateLocalPlayer { success in
            Task { @MainActor in
                // コールバックで取得した認証状態をステートストアへ反映し、トップバーの表示とログ出力を同期させる
                stateStore.isAuthenticated = success
                completion(success)
            }
        }
    }

    /// GeometryReader から得た値と状態をまとめた内部専用コンテキスト
    struct RootLayoutContext {
        let geometrySize: CGSize
        let safeAreaInsets: EdgeInsets
        let horizontalSizeClass: UserInterfaceSizeClass?

        var safeAreaTop: CGFloat { safeAreaInsets.top }
        var safeAreaBottom: CGFloat { safeAreaInsets.bottom }
        var safeAreaLeading: CGFloat { safeAreaInsets.leading }
        var safeAreaTrailing: CGFloat { safeAreaInsets.trailing }

        private var isRegularWidth: Bool { horizontalSizeClass == .regular }

        /// トップバーに適用する左右の余白
        var topBarHorizontalPadding: CGFloat {
            isRegularWidth ? RootLayoutMetrics.topBarHorizontalPaddingRegular : RootLayoutMetrics.topBarHorizontalPaddingCompact
        }

        /// iPad では中央寄せした幅へ制限し、iPhone では nil として全幅に広げる
        var topBarMaxWidth: CGFloat? {
            isRegularWidth ? RootLayoutMetrics.topBarMaxWidthRegular : nil
        }

        /// safeAreaInsets.top が 0 の場合に追加で確保する余白
        var regularTopPaddingFallback: CGFloat {
            (isRegularWidth && safeAreaInsets.top <= 0) ? RootLayoutMetrics.regularWidthTopPaddingFallback : 0
        }
    }

    /// レイアウトログで扱う情報をまとめたスナップショット
    struct RootLayoutSnapshot: Equatable {
        let geometrySize: CGSize
        let safeAreaTop: CGFloat
        let safeAreaBottom: CGFloat
        let safeAreaLeading: CGFloat
        let safeAreaTrailing: CGFloat
        let horizontalSizeClass: UserInterfaceSizeClass?
        let isAuthenticated: Bool
        let isShowingTitleScreen: Bool
        let activeModeIdentifier: GameMode.Identifier
        let topBarHorizontalPadding: CGFloat
        let topBarMaxWidth: CGFloat?
        let regularTopPaddingFallback: CGFloat
        let topBarHeight: CGFloat

        init(
            context: RootLayoutContext,
            isAuthenticated: Bool,
            isShowingTitleScreen: Bool,
            activeMode: GameMode,
            topBarHeight: CGFloat
        ) {
            self.geometrySize = context.geometrySize
            self.safeAreaTop = context.safeAreaTop
            self.safeAreaBottom = context.safeAreaBottom
            self.safeAreaLeading = context.safeAreaLeading
            self.safeAreaTrailing = context.safeAreaTrailing
            self.horizontalSizeClass = context.horizontalSizeClass
            self.isAuthenticated = isAuthenticated
            self.isShowingTitleScreen = isShowingTitleScreen
            self.activeModeIdentifier = activeMode.identifier
            self.topBarHorizontalPadding = context.topBarHorizontalPadding
            self.topBarMaxWidth = context.topBarMaxWidth
            self.regularTopPaddingFallback = context.regularTopPaddingFallback
            self.topBarHeight = topBarHeight
        }

        /// サイズクラスの説明をログに残しやすい形式へ変換
        var horizontalSizeClassDescription: String {
            if let horizontalSizeClass {
                return horizontalSizeClass == .regular ? "regular" : "compact"
            } else {
                return "nil"
            }
        }

        /// トップバー最大幅の説明文字列
        var topBarMaxWidthDescription: String {
            if let width = topBarMaxWidth {
                let rounded = (width * 10).rounded() / 10
                return "\(rounded)"
            } else {
                return "nil"
            }
        }
    }

    /// トップバー周辺で利用する定数をまとめた列挙体
    enum RootLayoutMetrics {
        /// コンパクト幅（主に iPhone）で用いる左右余白
        static let topBarHorizontalPaddingCompact: CGFloat = 16
        /// レギュラー幅（主に iPad）で用いる左右余白
        static let topBarHorizontalPaddingRegular: CGFloat = 32
        /// トップバー上側の基本マージン
        static let topBarBaseTopPadding: CGFloat = 12
        /// トップバー下側の基本マージン
        static let topBarBaseBottomPadding: CGFloat = 10
        /// トップバー内部の要素間隔
        static let topBarContentSpacing: CGFloat = 8
        /// レギュラー幅で中央寄せする際の最大幅
        static let topBarMaxWidthRegular: CGFloat = 520
        /// レギュラー幅で safe area が 0 の場合に追加するフォールバック余白
        static let regularWidthTopPaddingFallback: CGFloat = 18
        /// トップバー背景の不透明度（0 に近いほど透過）
        static let topBarBackgroundOpacity: Double = 0.94
        /// トップバー下部の仕切り線の不透明度
        static let topBarDividerOpacity: Double = 0.45
        /// タイトルからゲームへ遷移する際にローディング表示を維持する最低時間（秒）
        static let gamePreparationMinimumDelay: Double = 0.35
    }

}

/// RootView 専用のトップバー高さを伝達する PreferenceKey
/// - NOTE: `TopStatusInsetView` などファイル内の複数ビューから利用するため、
///         ファイルスコープで `fileprivate` として宣言し、スコープエラーを防ぐ
fileprivate struct TopBarHeightPreferenceKey: PreferenceKey {
    /// GeometryReader から受け取る高さのデフォルト値（未計測時は 0）
    static var defaultValue: CGFloat = 0

    /// Preference の更新処理。最新値だけを必要とするため常に `nextValue()` で上書きする
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - トップステータスバー専用ビュー
@MainActor
fileprivate struct TopStatusInsetView: View {
    /// レイアウト調整に必要な値のセット
    let context: RootView.RootLayoutContext
    /// ルートビューと同じテーマを共有し、配色の一貫性を保つ
    let theme: AppTheme
    /// RootView 内で定義したレイアウト定数へ素早くアクセスするための別名
    /// - Note: ネストした型名を毎回書かずに済ませ、視認性を高める狙い
    private typealias LayoutMetrics = RootView.RootLayoutMetrics

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            if hasVisibleContent {
                VStack(alignment: .leading, spacing: LayoutMetrics.topBarContentSpacing) {
                    statusContent
                }
                // トップバー内の情報は iPad で中央寄せにするため最大幅を制限する
                .frame(maxWidth: context.topBarMaxWidth ?? .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        // 画面上部に常駐する情報のみを表示するため、タップは背後のボタンへ届ける
        .allowsHitTesting(false)
        // ヒットテスト無効化後も VoiceOver で読み上げられるよう専用ラベルを明示
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityMessage)
        // コンテンツが存在しない場合は VoiceOver 対象から除外し、不要な読み上げを防ぐ
        .accessibilityHidden(!hasVisibleContent)
        .padding(.horizontal, horizontalPadding)
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
        .background(topBarBackground)
        .overlay(alignment: .bottom) {
            topBarDivider
        }
        // GeometryReader で高さを取得し、PreferenceKey を介して親ビューへ伝搬する
        .background(
            GeometryReader { proxy in
                Color.clear
                    // ファイルスコープで宣言した PreferenceKey を直接指定し、型推論を確実にする
                    .preference(key: TopBarHeightPreferenceKey.self, value: proxy.size.height)
            }
        )
    }

    /// トップバーへ掲出するコンテンツ
    /// - Note: Game Center まわりの通知はトーストへ統一したため、現時点では空ビューを返す
    @ViewBuilder
    private var statusContent: some View {
        EmptyView()
    }

    /// VoiceOver 用の説明文。ヒットテストを無効化しても読み上げ内容が失われないよう、状態に応じた文面を返す
    private var accessibilityMessage: LocalizedStringKey {
        // バナーを廃止し、トーストのみで案内するため読み上げも空文字を返す
        ""
    }

    /// トップバー内に可視コンテンツが存在するかを判定する
    /// - Note: 表示有無に応じて背景や余白を切り替え、空状態での白い帯を解消する
    private var hasVisibleContent: Bool {
        // Game Center 通知をトーストへ移行したため、トップバーでは常に非表示とする
        false
    }

    /// 表示状態に応じて水平方向の余白を計算する
    private var horizontalPadding: CGFloat {
        hasVisibleContent ? context.topBarHorizontalPadding : 0
    }

    /// トップ側の余白。可視要素がない場合は最小限に抑え、レイアウト計算だけを維持する
    private var topPadding: CGFloat {
        hasVisibleContent ? (LayoutMetrics.topBarBaseTopPadding + context.regularTopPaddingFallback) : 0
    }

    /// ボトム側の余白。非表示時は 0 にし、設定ボタンと重ならないよう画面上部を最大限活用する
    private var bottomPadding: CGFloat {
        hasVisibleContent ? LayoutMetrics.topBarBaseBottomPadding : 0
    }

    /// 背景ビューを状態に応じて切り替える
    @ViewBuilder
    private var topBarBackground: some View {
        if hasVisibleContent {
            theme.backgroundPrimary
                .opacity(LayoutMetrics.topBarBackgroundOpacity)
                .ignoresSafeArea(edges: .top)
        } else {
            Color.clear
        }
    }

    /// 仕切り線を表示する際だけ描画し、空状態では余計な線を出さない
    @ViewBuilder
    private var topBarDivider: some View {
        if hasVisibleContent {
            Divider()
                .background(theme.statisticBadgeBorder)
                .opacity(LayoutMetrics.topBarDividerOpacity)
        }
    }
}

// MARK: - タイトル画面（リニューアル）
fileprivate struct TitleScreenView: View {
    @ObservedObject var campaignProgressStore: CampaignProgressStore
    let onStart: (GameMode) -> Void
    let onOpenSettings: () -> Void

    private var theme = AppTheme()
    private let campaignLibrary = CampaignLibrary.shared
    @State private var isPresentingHowToPlay: Bool = false
    @State private var navigationPath: [TitleNavigationTarget] = []
    @State private var highlightedCampaignStageID: CampaignStageID?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("best_points_5x5") private var bestPoints: Int = .max
    private let instanceIdentifier = UUID()

    private enum TitleNavigationTarget: String, Hashable, Codable {
        case campaign
        case highScore
        case dailyChallenge
    }

    /// ゲーム開始要求がどこから届いたかを判定するための文脈列挙
    /// - NOTE: ログ出力時に文脈を一意に追跡できるよう rawValue を英語スネークケースで保持する
    private enum StartTriggerContext: String {
        /// キャンペーンのステージ一覧から直接開始するケース
        case campaignStageSelection = "campaign_stage_selection"
        /// ハイスコア選択画面から開始するケース
        case highScoreSelection = "high_score_selection"

        /// ログ出力向けに読みやすい説明文を返す
        var logDescription: String {
            switch self {
            case .campaignStageSelection:
                return "キャンペーン一覧から開始"
            case .highScoreSelection:
                return "ハイスコア選択から開始"
            }
        }
    }

    init(campaignProgressStore: CampaignProgressStore, onStart: @escaping (GameMode) -> Void, onOpenSettings: @escaping () -> Void) {
        self._campaignProgressStore = ObservedObject(wrappedValue: campaignProgressStore)
        self.onStart = onStart
        self.onOpenSettings = onOpenSettings
        _isPresentingHowToPlay = State(initialValue: false)
        debugLog("TitleScreenView.init開始: instance=\(instanceIdentifier.uuidString) navigationPathCount=\(_navigationPath.wrappedValue.count)")
    }

    var body: some View {
        debugLog("TitleScreenView.body評価: instance=\(instanceIdentifier.uuidString) navigationPathCount=\(navigationPath.count)")
        return NavigationStack(path: $navigationPath) {
            titleScreenMainContent
                .navigationDestination(for: TitleNavigationTarget.self) { target in
                    let stackDescription = navigationPath
                        .map { $0.rawValue }
                        .joined(separator: ",")
                    let _ = debugLog(
                        "TitleScreenView: NavigationDestination.entry -> instance=\(instanceIdentifier.uuidString) target=\(target.rawValue) targetType=\(String(describing: type(of: target))) stackCount=\(navigationPath.count) stack=[\(stackDescription)]"
                    )
                    navigationDestinationView(for: target)
                }
        }
        .sheet(isPresented: $isPresentingHowToPlay) {
            howToPlaySheetContent
        }
        .onChange(of: isPresentingHowToPlay) { _, newValue in
            debugLog("TitleScreenView.isPresentingHowToPlay 更新: \(newValue)")
        }
        .onChange(of: navigationPath) { oldValue, newValue in
            let stackDescription = newValue
                .map { String(describing: $0) }
                .joined(separator: ",")
            debugLog(
                "TitleScreenView.navigationPath 更新: instance=\(instanceIdentifier.uuidString) 旧=\(oldValue.count) -> 新=\(newValue.count) スタック=[\(stackDescription)]"
            )
        }
        .onChange(of: horizontalSizeClass) { _, newValue in
            debugLog("TitleScreenView.horizontalSizeClass 更新: \(String(describing: newValue))")
        }
    }

    @ViewBuilder
    private var titleScreenMainContent: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 28) {
                    headerSection
                    featureTilesSection
                    howToPlayButton
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 72)
                .padding(.bottom, 64)
                .frame(maxWidth: contentMaxWidth)
                .frame(maxWidth: .infinity)
            }
            .background(theme.backgroundPrimary)

            settingsButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.backgroundPrimary)
        .accessibilityElement(children: .contain)
        // VoiceOver 向けにカードメニューの概要を日本語で伝える
        .accessibilityLabel("タイトル画面。キャンペーン、ハイスコア、デイリーチャレンジの各カードから詳細へ進めます。")
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            Text("MonoKnight")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundColor(theme.textPrimary)
            Text("カードで騎士を導き、盤面を踏破しよう")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
    }

    private var howToPlayButton: some View {
        Button {
            debugLog("TitleScreenView: 遊び方シート表示要求")
            isPresentingHowToPlay = true
        } label: {
            Label("遊び方を見る", systemImage: "questionmark.circle")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.white.opacity(0.8))
        .foregroundColor(.white)
        .controlSize(.large)
        .accessibilityIdentifier("title_how_to_play_button")
        // VoiceOver でモーダルが開くことを伝える
        .accessibilityHint(Text("MonoKnight の基本ルールを確認できます"))
    }

    private var settingsButton: some View {
        Button {
            debugLog("TitleScreenView: 設定シート表示要求")
            onOpenSettings()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(theme.menuIconForeground)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(theme.menuIconBackground)
                )
                .overlay(
                    Circle()
                        .stroke(theme.menuIconBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .padding(.top, 16)
        .padding(.trailing, 20)
        .accessibilityLabel("設定")
        .accessibilityHint("広告やプライバシー設定などを確認できます")
    }

    private var featureTilesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("プレイメニュー")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(theme.textPrimary)

            // デイリーチャレンジがダミーであることを明示し、混乱を避ける
            dailyChallengeNoticeCard

            VStack(spacing: 14) {
                featureTile(
                    target: .campaign,
                    title: "キャンペーン",
                    systemImage: "flag.checkered",
                    headline: campaignTileHeadline,
                    detail: campaignTileDetail,
                    accessibilityID: "title_tile_campaign",
                    accessibilityHint: "ステージ一覧を表示します"
                )

                featureTile(
                    target: .highScore,
                    title: "ハイスコア",
                    systemImage: "trophy.fill",
                    headline: highScoreTileHeadline,
                    detail: highScoreTileDetail,
                    accessibilityID: "title_tile_high_score",
                    accessibilityHint: "スコアアタックの詳細を確認できます"
                )

                featureTile(
                    target: .dailyChallenge,
                    title: "デイリーチャレンジ",
                    systemImage: "calendar",
                    headline: dailyChallengeTileHeadline,
                    detail: dailyChallengeTileDetail,
                    accessibilityID: "title_tile_daily_challenge",
                    accessibilityHint: "日替わりチャレンジの情報を表示します"
                )
            }
        }
    }

    private func featureTile(
        target: TitleNavigationTarget,
        title: String,
        systemImage: String,
        headline: String,
        detail: String,
        accessibilityID: String,
        accessibilityHint: String
    ) -> some View {
        NavigationLink(value: target) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 12) {
                    featureIconTile(systemName: systemImage)
                        .alignmentGuide(.firstTextBaseline) { dimensions in
                            dimensions[VerticalAlignment.center]
                        }

                    Text(title)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.textPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .foregroundColor(theme.textSecondary.opacity(0.7))
                        .font(.system(size: 14, weight: .semibold))
                }

                Text(headline)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(theme.textSecondary)
                Text(detail)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(theme.textSecondary.opacity(0.85))
                    .multilineTextAlignment(.leading)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(theme.backgroundElevated.opacity(0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(theme.statisticBadgeBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            TapGesture().onEnded {
                handleTileTapLogging(for: target)
            }
        )
        .accessibilityIdentifier(accessibilityID)
        // VoiceOver でカードの役割が明確になるようにタイトル・概要・詳細をまとめて読み上げる
        .accessibilityLabel(Text("\(title)。\(headline)。\(detail)"))
        .accessibilityHint(Text(accessibilityHint))
    }

    private var dailyChallengeNoticeCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.accentPrimary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text("日替わりモードは現在プレオープン中です")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)

                Text("詳細画面では公開準備の状況のみ表示されます。実際のチャレンジは近日中に提供予定です。")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(theme.backgroundElevated.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(theme.statisticBadgeBorder.opacity(0.8), lineWidth: 1)
        )
        // VoiceOver で日替わりモードが準備中であることを冒頭で伝える
        .accessibilityElement(children: .combine)
        .accessibilityLabel("デイリーチャレンジは準備中です。詳細画面では状況のみ確認できます。")
    }

    private func navigationDestinationView(for target: TitleNavigationTarget) -> some View {
        switch target {
        case .campaign:
            let stackDescription = navigationPath
                .map { $0.rawValue }
                .joined(separator: ",")
            let _ = debugLog(
                "TitleScreenView: NavigationDestination.campaign 構築開始 -> instance=\(instanceIdentifier.uuidString) targetType=\(String(describing: type(of: target))) stackCount=\(navigationPath.count) stack=[\(stackDescription)]"
            )
            return AnyView(
                CampaignStageSelectionView(
                    campaignLibrary: campaignLibrary,
                    progressStore: campaignProgressStore,
                    selectedStageID: highlightedCampaignStageID,
                    onClose: { popNavigationStack() },
                    onSelectStage: { stage in
                        // 選択されたステージを一旦保持し、NavigationStack をリセットした後に開始処理をキューへ積む
                        handleCampaignStageSelection(stage)
                        let mode = stage.makeGameMode()
                        let context: StartTriggerContext = .campaignStageSelection
                        debugLog(
                            "TitleScreenView: キャンペーンステージ選択後 -> NavigationStack をリセットして即時開始をメインキューへ登録 context=\(context.rawValue)"
                        )
                        resetNavigationStack()
                        // NavigationStack のポップ完了を待ってからゲーム準備を走らせ、画面遷移時のクラッシュを防ぐ
                        DispatchQueue.main.async {
                            triggerImmediateStart(for: mode, context: context)
                        }
                    },
                    showsCloseButton: false
                )
                .onAppear {
                    debugLog("TitleScreenView: NavigationDestination.campaign 表示 -> 現在のスタック数=\(navigationPath.count)")
                }
                .onDisappear {
                    debugLog("TitleScreenView: NavigationDestination.campaign 非表示 -> 現在のスタック数=\(navigationPath.count)")
                }
            )
        case .highScore:
            return AnyView(
                HighScoreChallengeSelectionView(
                    onSelect: { mode in
                        startHighScoreMode(mode)
                    },
                    onClose: { popNavigationStack() },
                    bestScoreDescription: bestPointsDescription
                )
                .onAppear {
                    debugLog("TitleScreenView: NavigationDestination.highScore 表示 -> 現在のスタック数=\(navigationPath.count)")
                }
                .onDisappear {
                    debugLog("TitleScreenView: NavigationDestination.highScore 非表示 -> 現在のスタック数=\(navigationPath.count)")
                }
            )
        case .dailyChallenge:
            return AnyView(
                DailyChallengePlaceholderView(
                    onDismiss: {
                        // NavigationStack の状態を確実に戻し、タイトルへ復帰させる
                        popNavigationStack()
                    }
                )
                .onAppear {
                    debugLog("TitleScreenView: NavigationDestination.dailyChallenge 表示 -> 現在のスタック数=\(navigationPath.count)")
                }
                .onDisappear {
                    debugLog("TitleScreenView: NavigationDestination.dailyChallenge 非表示 -> 現在のスタック数=\(navigationPath.count)")
                }
            )
        }
    }

    @ViewBuilder
    private var howToPlaySheetContent: some View {
        NavigationStack {
            HowToPlayView(showsCloseButton: true)
        }
        .presentationDetents(
            horizontalSizeClass == .regular ? [.large] : [.medium, .large]
        )
        .presentationDragIndicator(.visible)
    }

    private func handleTileTapLogging(for target: TitleNavigationTarget) {
        switch target {
        case .campaign:
            logCampaignTileTap()
        case .highScore:
            debugLog("TitleScreenView: ハイスコアカードをタップ -> 詳細ページへ遷移要求")
            logNavigationDepth(prefix: "TitleScreenView: NavigationStack 遷移直前状態")
        case .dailyChallenge:
            debugLog("TitleScreenView: デイリーチャレンジカードをタップ -> 詳細ページへ遷移要求")
            logNavigationDepth(prefix: "TitleScreenView: NavigationStack 遷移直前状態")
        }
    }

    private func logCampaignTileTap() {
        let stageIDDescription = highlightedCampaignStageID?.displayCode ?? "未選択"
        let chaptersCount = campaignLibrary.chapters.count
        let totalStageCount = campaignLibrary.allStages.count
        let unlockedCount = unlockedCampaignStageCount
        debugLog("TitleScreenView: キャンペーンカードタップ -> 章数=\(chaptersCount) 総ステージ数=\(totalStageCount) 最新選択=\(stageIDDescription) 解放済=\(unlockedCount)")
        logNavigationDepth(prefix: "TitleScreenView: NavigationStack 遷移直前状態")
    }

    private func logNavigationDepth(prefix: String) {
        let currentDepth = navigationPath.count
        debugLog("\(prefix) -> 現在のスタック数=\(currentDepth)")
    }

    private func handleCampaignStageSelection(_ stage: CampaignStage) {
        debugLog("TitleScreenView: キャンペーンステージを選択 -> \(stage.id.displayCode)")
        highlightedCampaignStageID = stage.id
        // 即時開始は NavigationStack のポップ完了後に行うため、ここでは保持とログ出力のみに留める
        debugLog("TitleScreenView: キャンペーンステージ選択完了 -> 即時開始スケジュールを待機")
    }

    /// ハイスコア系モードの選択後に即時開始をリクエストする
    /// - Parameter mode: プレイヤーが挑戦したいモード
    private func startHighScoreMode(_ mode: GameMode) {
        let context: StartTriggerContext = .highScoreSelection
        debugLog(
            "TitleScreenView: ハイスコアチャレンジ開始要求 -> \(mode.identifier.rawValue) context=\(context.rawValue)"
        )
        resetNavigationStack()
        // 選択画面から戻る場合もポップ完了を待ち、同一フレームでの開始要求を避ける
        DispatchQueue.main.async {
            triggerImmediateStart(for: mode, context: context)
        }
    }

    private func featureIconTile(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(theme.accentPrimary)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.backgroundPrimary.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(theme.accentPrimary.opacity(0.7), lineWidth: 1)
            )
    }

    private func popNavigationStack() {
        guard navigationPath.count > 0 else { return }
        let currentDepth = navigationPath.count
        let callStackSnippet = Thread.callStackSymbols.prefix(4).joined(separator: " | ")
        debugLog("TitleScreenView: NavigationStack pop実行 -> 現在のスタック数=\(currentDepth) 呼び出し元候補=\(callStackSnippet)")
        navigationPath.removeLast()
        debugLog("TitleScreenView: NavigationStack pop後 -> 変更後のスタック数=\(navigationPath.count)")
    }

    private func resetNavigationStack() {
        guard navigationPath.count > 0 else { return }
        let currentDepth = navigationPath.count
        let callStackSnippet = Thread.callStackSymbols.prefix(4).joined(separator: " | ")
        debugLog("TitleScreenView: NavigationStack reset実行 -> 現在のスタック数=\(currentDepth) 呼び出し元候補=\(callStackSnippet)")
        navigationPath.removeAll()
        debugLog("TitleScreenView: NavigationStack reset後 -> 変更後のスタック数=\(navigationPath.count)")
    }

    /// 即時開始要求を処理し、文脈付きでログを出力する
    /// - Parameters:
    ///   - mode: これから開始するゲームモード
    ///   - context: 開始要求が発生した文脈
    private func triggerImmediateStart(for mode: GameMode, context: StartTriggerContext) {
        let stackDescription = navigationPath
            .map { $0.rawValue }
            .joined(separator: ",")
        debugLog(
            "TitleScreenView: triggerImmediateStart 実行 -> context=\(context.rawValue) (\(context.logDescription)) mode=\(mode.identifier.rawValue) navigationDepth=\(navigationPath.count) stack=[\(stackDescription)]"
        )
        onStart(mode)
    }
}

// MARK: - レイアウト調整用のヘルパー
private extension TitleScreenView {
    var highlightedCampaignStage: CampaignStage? {
        highlightedCampaignStageID.flatMap { campaignLibrary.stage(with: $0) }
    }

    var totalCampaignStageCount: Int {
        campaignLibrary.allStages.count
    }

    var unlockedCampaignStageCount: Int {
        campaignLibrary.allStages.filter { campaignProgressStore.isStageUnlocked($0) }.count
    }

    var campaignTileHeadline: String {
        let unlocked = unlockedCampaignStageCount
        let total = totalCampaignStageCount
        let stars = campaignProgressStore.totalStars
        return "解放済み \(unlocked)/\(total) ステージ・スター \(stars)"
    }

    var campaignTileDetail: String {
        if let stage = highlightedCampaignStage {
            return "最新選択: \(stage.displayCode) \(stage.title)"
        } else {
            return "ステージを選んでストーリーを進めましょう"
        }
    }

    var highScoreTileHeadline: String {
        if bestPoints == .max {
            return "ベストスコア: 記録なし"
        } else {
            return "ベストスコア: \(bestPoints) pt"
        }
    }

    var highScoreTileDetail: String {
        "スタンダードで手数とタイムを縮めましょう"
    }

    var dailyChallengeTileHeadline: String {
        "準備中: 近日公開予定"
    }

    var dailyChallengeTileDetail: String {
        "現在はプレオープン情報のみ確認できます"
    }

    var bestPointsDescription: String {
        if bestPoints == .max {
            return "記録はまだありません"
        } else {
            return "現在のベスト: \(bestPoints) pt（少ないほど上位）"
        }
    }

    var contentMaxWidth: CGFloat? {
        horizontalSizeClass == .regular ? 520 : nil
    }

    var horizontalPadding: CGFloat {
        horizontalSizeClass == .regular ? 80 : 32
    }
}
