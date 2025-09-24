import SwiftUI
import Game

/// ゲームプレイとタイトル画面を統括するルートビュー
/// タイトル画面での設定シート表示やゲーム開始フローをまとめて制御する
@MainActor
/// SwiftUI ビュー全体を MainActor 上で扱い、MainActor 隔離されたシングルトン（GameCenterService / AdsService）へアクセスする際の競合を防ぐ
/// - NOTE: Swift 6 で厳格化された並行性モデルに追従し、ビルドエラー（MainActor 分離違反）を確実に回避するための指定
struct RootView: View {
    /// 画面全体の配色を揃えるためのテーマ。タブやトップバーの背景色を一元管理するためここで生成する
    private var theme = AppTheme()
    /// Game Center 連携を扱うサービス（プロトコル型で受け取る）
    private let gameCenterService: GameCenterServiceProtocol
    /// 広告表示を扱うサービス（GameView へ受け渡す）
    private let adsService: AdsServiceProtocol
    /// デバイスの横幅サイズクラスを参照し、iPad などレギュラー幅での余白やログ出力を調整する
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// 画面全体の状態とログ出力を一元管理するステートストア
    /// - NOTE: onChange 連鎖による複雑な型推論を避け、プロパティ監視をクラス内の didSet へ集約する
    @StateObject private var stateStore: RootViewStateStore
    /// ローディング表示解除を遅延実行するためのワークアイテム
    /// - NOTE: 新しいゲーム開始操作が走った際に古い処理をキャンセルできるよう保持しておく
    @State private var pendingGameActivationWorkItem: DispatchWorkItem?
    /// フロントエンドからログを閲覧するためのビューモデル
    /// - Note: TestFlight で素早く状況確認できるよう、アプリ内に簡易コンソールを常設する
    @StateObject private var debugLogConsoleViewModel = DebugLogConsoleViewModel()
    /// 依存サービスを外部から注入可能にする初期化処理
    /// - Parameters:
    ///   - gameCenterService: Game Center 連携用サービス（デフォルトはシングルトン）
    ///   - adsService: 広告表示用サービス（デフォルトはシングルトン）
    init(gameCenterService: GameCenterServiceProtocol? = nil,
         adsService: AdsServiceProtocol? = nil) {
        // Swift 6 ではデフォルト引数の評価が非分離コンテキストで行われるため、
        // `@MainActor` に隔離されたシングルトンを安全に利用するためにイニシャライザ内で解決する。
        let resolvedGameCenterService = gameCenterService ?? GameCenterService.shared
        let resolvedAdsService = adsService ?? AdsService.shared

        self.gameCenterService = resolvedGameCenterService
        self.adsService = resolvedAdsService
        // 画面状態を一括管理するステートストアを生成し、初期認証状態を反映する。
        _stateStore = StateObject(
            wrappedValue: RootViewStateStore(
                initialIsAuthenticated: resolvedGameCenterService.isAuthenticated
            )
        )
    }

    var body: some View {
        attachRootStateObservers(
            GeometryReader { geometry in
                // MARK: - GeometryReader が提供するサイズや safe area を専用コンテキストへまとめ、下層ビューへシンプルに引き渡す
                let layoutContext = makeLayoutContext(from: geometry)

                // MARK: - 生成済みのコンテキストを使い、型階層の浅いサブビューへ委譲して型チェック負荷を分散する
                makeRootContentView(with: layoutContext)
            }
        )
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
    /// 実際にプレイへ適用しているモード
    @Published var activeMode: GameMode {
        didSet {
            guard oldValue != activeMode else { return }
            debugLog("RootView.activeMode 更新: \(activeMode.identifier.rawValue)")
        }
    }
    /// タイトル画面で選択中のモード
    @Published var selectedModeForTitle: GameMode {
        didSet {
            guard oldValue != selectedModeForTitle else { return }
            debugLog("RootView.selectedModeForTitle 更新: \(selectedModeForTitle.identifier.rawValue)")
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
    /// デバッグログコンソールの表示状態
    @Published var isPresentingDebugLogConsole: Bool {
        didSet {
            guard oldValue != isPresentingDebugLogConsole else { return }
            debugLog("RootView.isPresentingDebugLogConsole 更新: \(isPresentingDebugLogConsole)")
        }
    }

    /// 初期化時に必要な値をまとめて受け取り、SwiftUI の `@StateObject` から利用できるようにする
    /// - Parameter initialIsAuthenticated: Game Center 認証済みかどうかの初期値
    init(initialIsAuthenticated: Bool) {
        self.isAuthenticated = initialIsAuthenticated
        self.isShowingTitleScreen = true
        self.isPreparingGame = false
        self.activeMode = .standard
        self.selectedModeForTitle = .standard
        self.gameSessionID = UUID()
        self.topBarHeight = 0
        self.lastLoggedLayoutSnapshot = nil
        self.isPresentingTitleSettings = false
        self.isPresentingDebugLogConsole = false
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

    /// サイズクラス変化をログへ出力する
    /// - Parameter newValue: 更新後の横幅サイズクラス
    func logHorizontalSizeClassChange(_ newValue: UserInterfaceSizeClass?) {
        debugLog("RootView.horizontalSizeClass 更新: \(String(describing: newValue))")
    }
}

// MARK: - レイアウト支援メソッドと定数
private extension RootView {
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
            gameCenterService: gameCenterService,
            adsService: adsService,
            isAuthenticated: stateStore.binding(for: \.isAuthenticated),
            isShowingTitleScreen: stateStore.binding(for: \.isShowingTitleScreen),
            isPreparingGame: stateStore.binding(for: \.isPreparingGame),
            activeMode: stateStore.binding(for: \.activeMode),
            selectedModeForTitle: stateStore.binding(for: \.selectedModeForTitle),
            gameSessionID: stateStore.binding(for: \.gameSessionID),
            topBarHeight: stateStore.binding(for: \.topBarHeight),
            lastLoggedLayoutSnapshot: stateStore.binding(for: \.lastLoggedLayoutSnapshot),
            isPresentingTitleSettings: stateStore.binding(for: \.isPresentingTitleSettings),
            debugLogConsoleViewModel: debugLogConsoleViewModel,
            isPresentingDebugLogConsole: stateStore.binding(for: \.isPresentingDebugLogConsole),
            authenticateAction: handleGameCenterAuthenticationRequest,
            onStartGame: { mode in
                // タイトル画面から受け取ったモードでゲーム準備フローを実行する
                startGamePreparation(for: mode)
            },
            onReturnToTitle: {
                // GameView からの戻る要求をハンドリングし、タイトル表示へ切り替える
                handleReturnToTitleRequest()
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
                stateStore.topBarHeight = newHeight
            }
            // サイズクラスの更新のみは Environment 値から取得する必要があるため、専用メソッドでログを残す
            .onChange(of: horizontalSizeClass) { _, newValue in
                stateStore.logHorizontalSizeClassChange(newValue)
            }
            // タイトル設定シートの表示制御。Binding はステートストアから生成する
            .fullScreenCover(isPresented: stateStore.binding(for: \.isPresentingTitleSettings)) {
                SettingsView()
            }
            // デバッグログコンソールのシート表示。レイアウトは元実装と同じ構成を維持する
            .sheet(isPresented: stateStore.binding(for: \.isPresentingDebugLogConsole)) {
                DebugLogConsoleView(viewModel: debugLogConsoleViewModel)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
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
        /// Game Center 関連のサービスインスタンス
        let gameCenterService: GameCenterServiceProtocol
        /// 広告制御用サービス
        let adsService: AdsServiceProtocol
        /// Game Center 認証状態
        @Binding var isAuthenticated: Bool
        /// タイトル表示中かどうか
        @Binding var isShowingTitleScreen: Bool
        /// ゲーム準備中（ローディング表示中）かどうか
        @Binding var isPreparingGame: Bool
        /// 実際にプレイへ適用されているモード
        @Binding var activeMode: GameMode
        /// タイトル画面で選択中のモード
        @Binding var selectedModeForTitle: GameMode
        /// GameView 再生成用の識別子
        @Binding var gameSessionID: UUID
        /// トップバーの実測高さ
        @Binding var topBarHeight: CGFloat
        /// 直近で記録したレイアウトスナップショット
        @Binding var lastLoggedLayoutSnapshot: RootLayoutSnapshot?
        /// タイトルから設定シートを開くためのフラグ
        @Binding var isPresentingTitleSettings: Bool
        /// デバッグログコンソールのビューモデル
        let debugLogConsoleViewModel: DebugLogConsoleViewModel
        /// デバッグログコンソール表示状態
        @Binding var isPresentingDebugLogConsole: Bool
        /// Game Center 認証 API 呼び出し用クロージャ
        let authenticateAction: (@escaping (Bool) -> Void) -> Void
        /// タイトル画面から開始ボタンが押下された際の処理
        let onStartGame: (GameMode) -> Void
        /// GameView からタイトルへ戻る際の処理
        let onReturnToTitle: () -> Void

        var body: some View {
            ZStack {
                backgroundLayer
                foregroundLayer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                topStatusInset
            }
            .background(layoutDiagnosticOverlay)
            .onAppear {
                // 初期描画時のレイアウト状況をログへ残し、不具合調査を容易にする
                debugLog(
                    "RootView.onAppear: size=\(layoutContext.geometrySize), safeArea(top=\(layoutContext.safeAreaTop), bottom=\(layoutContext.safeAreaBottom)), horizontalSizeClass=\(String(describing: layoutContext.horizontalSizeClass)), authenticated=\(isAuthenticated)"
                )
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
                    gameCenterService: gameCenterService,
                    adsService: adsService,
                    onRequestReturnToTitle: {
                        // GameView 内からの戻り要求を親へ伝播させる
                        onReturnToTitle()
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
                GamePreparationOverlayView()
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
                    selectedMode: $selectedModeForTitle,
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
                theme: theme,
                isAuthenticated: $isAuthenticated,
                isDebugLogConsoleEnabled: debugLogConsoleViewModel.isViewerEnabled,
                isPresentingDebugLogConsole: $isPresentingDebugLogConsole,
                authenticateAction: authenticateAction
            )
        }

        /// レイアウト監視用の不可視オーバーレイ
        private var layoutDiagnosticOverlay: some View {
            let snapshot = RootLayoutSnapshot(
                context: layoutContext,
                isAuthenticated: isAuthenticated,
                isShowingTitleScreen: isShowingTitleScreen,
                activeMode: activeMode,
                selectedMode: selectedModeForTitle,
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

        /// レイアウトスナップショットをログに出力する
        /// - Parameters:
        ///   - snapshot: 出力対象のスナップショット
        ///   - reason: 出力理由（初期観測・値更新など）
        private func logLayoutSnapshot(_ snapshot: RootLayoutSnapshot, reason: String) {
            guard lastLoggedLayoutSnapshot != snapshot else { return }
            lastLoggedLayoutSnapshot = snapshot

            let message = """
            RootView.layout 観測: 理由=\(reason)
              geometry=\(snapshot.geometrySize)
              safeArea(top=\(snapshot.safeAreaTop), bottom=\(snapshot.safeAreaBottom), leading=\(snapshot.safeAreaLeading), trailing=\(snapshot.safeAreaTrailing))
              horizontalSizeClass=\(snapshot.horizontalSizeClassDescription) topBarPadding=\(snapshot.topBarHorizontalPadding) topBarMaxWidth=\(snapshot.topBarMaxWidthDescription) fallbackTopPadding=\(snapshot.regularTopPaddingFallback)
              states(authenticated=\(snapshot.isAuthenticated), showingTitle=\(snapshot.isShowingTitleScreen), activeMode=\(snapshot.activeModeIdentifier.rawValue), selectedMode=\(snapshot.selectedModeIdentifier.rawValue), topBarHeight=\(snapshot.topBarHeight))
            """

            debugLog(message)

            if snapshot.topBarHeight <= 0 {
                debugLog("RootView.layout 警告: topBarHeight が 0 以下です。safe area とフォールバック設定を確認してください。")
            }
            if snapshot.safeAreaTop < 0 || snapshot.safeAreaBottom < 0 {
                debugLog("RootView.layout 警告: safeArea が負値です。GeometryReader の取得値を再確認してください。")
            }
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
        stateStore.selectedModeForTitle = mode

        // GameView を強制的に再生成するためセッション ID を更新し、ログで追跡できるよう記録する
        stateStore.gameSessionID = UUID()
        let scheduledSessionID = stateStore.gameSessionID
        debugLog("RootView: 新規ゲームセッションを割り当て sessionID=\(scheduledSessionID)")

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

        withAnimation(.easeInOut(duration: 0.25)) {
            stateStore.isShowingTitleScreen = true
            // 直前にプレイしたモードをタイトル画面側の選択状態として復元する
            stateStore.selectedModeForTitle = stateStore.activeMode
        }
    }

    /// ローディング解除処理を一定時間後に実行する
    /// - Parameter sessionID: 解除対象となるゲームセッションの識別子
    func scheduleGameActivationCompletion(for sessionID: UUID) {
        // 既存のワークアイテムは startGamePreparation 内で必ずキャンセル済みの想定
        let workItem = DispatchWorkItem { [sessionID] in
            // キャンセル済み（もしくは新しいゲーム開始で破棄済み）の場合は何もせず終了する
            guard pendingGameActivationWorkItem != nil else {
                debugLog("RootView: ゲーム準備ワークアイテムが実行前に破棄されました sessionID=\(sessionID)")
                return
            }

            // ゲームセッション ID が変化している場合は古いリクエストなので破棄する
            guard sessionID == stateStore.gameSessionID else {
                debugLog("RootView: ゲーム準備完了通知を破棄 scheduled=\(sessionID) current=\(stateStore.gameSessionID)")
                return
            }

            debugLog("RootView: ゲーム準備完了 ローディング解除 sessionID=\(sessionID)")

            withAnimation(.easeInOut(duration: 0.25)) {
                stateStore.isPreparingGame = false
            }

            // 再利用を防ぐため参照を破棄する
            pendingGameActivationWorkItem = nil
        }

        pendingGameActivationWorkItem = workItem

        DispatchQueue.main.asyncAfter(
            deadline: .now() + RootLayoutMetrics.gamePreparationMinimumDelay,
            execute: workItem
        )
    }

    /// ローディング表示解除用のワークアイテムをキャンセルし、参照をクリアする
    func cancelPendingGameActivationWorkItem() {
        guard let workItem = pendingGameActivationWorkItem else { return }
        debugLog("RootView: 保留中のゲーム準備ワークアイテムをキャンセル sessionID=\(stateStore.gameSessionID)")
        workItem.cancel()
        pendingGameActivationWorkItem = nil
    }

    /// Game Center 認証 API 呼び出しをカプセル化し、ビュー側からの参照を単純化する
    /// - Parameter completion: 認証成功可否を受け取るクロージャ
    private func handleGameCenterAuthenticationRequest(completion: @escaping (Bool) -> Void) {
        gameCenterService.authenticateLocalPlayer { success in
            completion(success)
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
        let selectedModeIdentifier: GameMode.Identifier
        let topBarHorizontalPadding: CGFloat
        let topBarMaxWidth: CGFloat?
        let regularTopPaddingFallback: CGFloat
        let topBarHeight: CGFloat

        init(
            context: RootLayoutContext,
            isAuthenticated: Bool,
            isShowingTitleScreen: Bool,
            activeMode: GameMode,
            selectedMode: GameMode,
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
            self.selectedModeIdentifier = selectedMode.identifier
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
    /// Game Center 認証済みかどうかの状態をバインディングで受け取る
    @Binding var isAuthenticated: Bool
    /// デバッグログコンソールが利用可能かどうかのフラグ
    let isDebugLogConsoleEnabled: Bool
    /// デバッグログコンソールの表示状態を RootView 側と同期する
    @Binding var isPresentingDebugLogConsole: Bool
    /// Game Center 認証 API を呼び出す際の仲介クロージャ
    let authenticateAction: (@escaping (Bool) -> Void) -> Void
    /// RootView 内で定義したレイアウト定数へ素早くアクセスするための別名
    /// - Note: ネストした型名を毎回書かずに済ませ、視認性を高める狙い
    private typealias LayoutMetrics = RootView.RootLayoutMetrics

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: LayoutMetrics.topBarContentSpacing) {
                gameCenterAuthenticationSection
                debugConsoleSection
            }
            .frame(maxWidth: context.topBarMaxWidth ?? .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, context.topBarHorizontalPadding)
        .padding(.top, LayoutMetrics.topBarBaseTopPadding + context.regularTopPaddingFallback)
        .padding(.bottom, LayoutMetrics.topBarBaseBottomPadding)
        .background(
            theme.backgroundPrimary
                .opacity(LayoutMetrics.topBarBackgroundOpacity)
                .ignoresSafeArea(edges: .top)
        )
        .overlay(alignment: .bottom) {
            Divider()
                .background(theme.statisticBadgeBorder)
                .opacity(LayoutMetrics.topBarDividerOpacity)
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

    /// Game Center 認証状態を表示するセクションを切り出して見通しを改善する
    @ViewBuilder
    private var gameCenterAuthenticationSection: some View {
        if isAuthenticated {
            Text("Game Center にサインイン済み")
                .font(.caption)
                // テーマ由来のサブ文字色を使い、背景とのコントラストを確保
                .foregroundColor(theme.textSecondary)
                .accessibilityIdentifier("gc_authenticated")
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Button(action: handleGameCenterSignInTapped) {
                Text("Game Center サインイン")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("gc_sign_in_button")
        }
    }

    /// デバッグログコンソールの表示ボタンを担当するセクション
    @ViewBuilder
    private var debugConsoleSection: some View {
        if isDebugLogConsoleEnabled {
            Button(action: handleDebugConsoleTapped) {
                Label("デバッグログを表示", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("debug_log_console_button")
        }
    }

    /// Game Center サインインボタン押下時の処理を共通化する
    private func handleGameCenterSignInTapped() {
        // 認証要求のトリガーを記録して、失敗時の切り分けを容易にする
        debugLog("RootView: Game Center 認証開始要求 現在の認証状態=\(isAuthenticated)")
        authenticateAction { success in
            // コールバックでの成否もログへ残し、原因調査の手がかりとする
            debugLog("RootView: Game Center 認証完了 success=\(success)")
            Task { @MainActor in
                isAuthenticated = success
            }
        }
    }

    /// デバッグログコンソール表示ボタンのタップ処理
    private func handleDebugConsoleTapped() {
        // ログ閲覧シートを開いた履歴を残しておき、TestFlight での操作を追跡する
        debugLog("RootView: デバッグログコンソール表示要求")
        isPresentingDebugLogConsole = true
    }
}

// MARK: - デバッグログコンソール

/// フロントエンドでデバッグログ履歴を監視するビューモデル
/// - Note: `DebugLogHistory` からの通知を受け取り、UI 側へ逐次反映する
@MainActor
fileprivate final class DebugLogConsoleViewModel: ObservableObject {
    /// 表示対象のログエントリ配列
    @Published private(set) var entries: [DebugLogEntry]
    /// 共有ログ履歴ストア
    private let history: DebugLogHistory
    /// NotificationCenter の監視トークン
    private var notificationToken: NSObjectProtocol?

    /// 初期化と同時に履歴のスナップショットを取得し、通知監視を開始する
    /// - Parameter history: ログ履歴を管理するストア（デフォルトはシングルトン）
    init(history: DebugLogHistory = .shared) {
        self.history = history
        self.entries = history.snapshot()

        notificationToken = NotificationCenter.default.addObserver(
            forName: DebugLogHistory.didAppendEntryNotification,
            object: history,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }

            if let entry = notification.userInfo?[DebugLogHistory.NotificationKey.entry] as? DebugLogEntry {
                // 新規追加 1 件の場合は末尾に追加してスクロール位置を維持する
                entries.append(entry)
            } else {
                // クリアや設定変更が走った場合はスナップショットを再取得する
                entries = history.snapshot()
            }
        }
    }

    deinit {
        if let notificationToken {
            NotificationCenter.default.removeObserver(notificationToken)
        }
    }

    /// フロントエンドからの閲覧が許可されているかどうか
    var isViewerEnabled: Bool {
        history.isFrontEndViewerEnabled
    }

    /// 保持しているログを全件削除する
    /// - Note: 個人情報が含まれる恐れがあるログを即座に破棄したい場合に利用する
    func clearEntries() {
        history.clear()
        entries.removeAll()
    }
}

/// デバッグログの内容を一覧表示するシート用ビュー
@MainActor
fileprivate struct DebugLogConsoleView: View {
    /// 表示を制御するビューモデル
    @ObservedObject var viewModel: DebugLogConsoleViewModel
    /// シートを閉じるための dismiss アクション
    @Environment(\.dismiss) private var dismiss
    /// 共通のカラーテーマ
    private var theme = AppTheme()

    /// 自動スクロールのために追跡している直近のログ ID
    @State private var lastVisibleEntryID: DebugLogEntry.ID?

    /// `@ObservedObject` と `@State` を適切に初期化するための明示的なイニシャライザ
    /// - NOTE: デフォルト実装だとメンバーごとのアクセスレベル推論の結果 `private` イニシャライザとなり、
    ///         同ファイル内での生成すら失敗していたため明示的に公開範囲を `fileprivate` へ指定する
    fileprivate init(viewModel: DebugLogConsoleViewModel) {
        // `@ObservedObject` プロパティラッパーは `_viewModel` への代入で初期化する必要がある
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        // ローカル状態は初期値 `nil` で十分なため明示的に代入する
        self._lastVisibleEntryID = State(initialValue: nil)
    }

    var body: some View {
        NavigationStack {
            contentView
                .navigationTitle("デバッグログ")
        }
        .toolbar {
            toolbarContent
        }
    }

    /// ナビゲーションスタック内で実際に描画する主要コンテンツ
    /// - Returns: ステータスメッセージとログ一覧を含む縦並びレイアウト
    @ViewBuilder
    private var contentView: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusMessageSection

            if viewModel.isViewerEnabled && !viewModel.entries.isEmpty {
                logListReaderSection()
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 24)
        .background(theme.backgroundPrimary.ignoresSafeArea())
    }

    /// ビルド設定による閲覧制限やログ未存在の状況を説明するメッセージ群
    /// - Returns: 条件に応じて表示される案内テキスト。該当しない場合は `EmptyView`
    @ViewBuilder
    private var statusMessageSection: some View {
        if !viewModel.isViewerEnabled {
            // リリース向けビルドで無効化している場合の案内
            Text("このビルドではフロントエンドからのログ閲覧が無効化されています。")
                .font(.callout)
                .foregroundColor(theme.textSecondary)
                .multilineTextAlignment(.leading)
        } else if viewModel.entries.isEmpty {
            // まだログが記録されていない場合のプレースホルダー
            Text("現在表示できるログはありません。操作を行うとここに履歴が蓄積されます。")
                .font(.callout)
                .foregroundColor(theme.textSecondary)
                .multilineTextAlignment(.leading)
                .padding(.top, 8)
        }
    }

    /// ログ一覧を自動スクロール対応で表示するためのコンテナ
    /// - Returns: `ScrollViewReader` を活用したログビュー全体
    @ViewBuilder
    private func logListReaderSection() -> some View {
        ScrollViewReader { proxy in
            logListSection(proxy: proxy)
        }
    }

    /// ログ一覧本体の描画を担当する
    /// - Parameter proxy: 自動スクロール制御に利用する `ScrollViewProxy`
    /// - Returns: ログ行を縦並びで表示するスクロールビュー
    @ViewBuilder
    private func logListSection(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(viewModel.entries) { entry in
                    DebugLogEntryRowView(entry: entry)
                        .id(entry.id)
                }
            }
            .padding(.vertical, 8)
        }
        .onAppear {
            // 初回表示時に末尾のログが見えるようスクロールする
            scrollToLatestEntryIfNeeded(using: proxy, entries: viewModel.entries, animated: false)
        }
        .onChange(of: viewModel.entries) { _, entries in
            // ログの追加や削除があった際に必要に応じてスクロールを更新する
            scrollToLatestEntryIfNeeded(using: proxy, entries: entries, animated: true)
        }
    }

    /// ナビゲーションバーへ配置するツールバー項目を整理する
    /// - Returns: 閉じるボタンと全削除ボタンをまとめたツールバー構成
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("閉じる") {
                dismiss()
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("すべて削除") {
                viewModel.clearEntries()
            }
            .disabled(viewModel.entries.isEmpty)
        }
    }

    /// 末尾のログ項目が画面内に収まるよう、必要に応じてスクロール位置を更新する
    /// - Parameters:
    ///   - proxy: スクロール操作に利用する `ScrollViewProxy`
    ///   - entries: 最新状態のログ配列
    ///   - animated: スクロール時にアニメーションを付けるかどうか
    private func scrollToLatestEntryIfNeeded(using proxy: ScrollViewProxy, entries: [DebugLogEntry], animated: Bool) {
        // 表示すべき最新のログ ID が存在しない場合は何もしない
        guard let lastID = entries.last?.id else { return }
        // 直前にスクロール済みの ID と同じ場合は無駄なスクロールを避ける
        guard lastID != lastVisibleEntryID else { return }

        // 最新 ID を追跡し、メインスレッドでスクロールを実行する
        lastVisibleEntryID = lastID
        let scrollAction = {
            proxy.scrollTo(lastID, anchor: .bottom)
        }

        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeInOut(duration: 0.2)) {
                    scrollAction()
                }
            } else {
                scrollAction()
            }
        }
    }
}

/// 1 行分のデバッグログを表示する補助ビュー
fileprivate struct DebugLogEntryRowView: View {
    /// 表示対象のログ
    let entry: DebugLogEntry
    /// カラーテーマ
    private var theme = AppTheme()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: entry.level == .error ? "exclamationmark.triangle.fill" : "info.circle")
                    .foregroundColor(entry.level == .error ? Color.red : theme.textSecondary)
                    .imageScale(.small)
                Text(DateFormatter.debugLogConsoleTime.string(from: entry.timestamp))
                    .font(.caption2)
                    .foregroundColor(theme.textSecondary)
            }

            Text(entry.message)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundColor(entry.level == .error ? Color.red : theme.textPrimary)
                .multilineTextAlignment(.leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(entry.level == .error ? Color.red.opacity(0.12) : theme.backgroundElevated.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(entry.level == .error ? Color.red.opacity(0.35) : theme.statisticBadgeBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.level == .error ? "エラーログ" : "情報ログ") \(DateFormatter.debugLogConsoleTime.string(from: entry.timestamp))")
        .accessibilityValue(entry.message)
    }
}

/// デバッグログ用の日付フォーマッタ
fileprivate extension DateFormatter {
    /// `HH:mm:ss.SSS` 表記で時間を出力するフォーマッタ
    static let debugLogConsoleTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

// MARK: - プレビュー
#Preview {
    RootView()
}

// MARK: - ゲーム準備中のオーバーレイ
/// GameView の初期化中に表示するローディング用オーバーレイ
/// - Note: 盤面が読み込まれるまでプレイヤーへ待機を促し、途中状態での操作を防ぐ
fileprivate struct GamePreparationOverlayView: View {
    /// 統一感のある配色を適用するためテーマを生成しておく
    private var theme = AppTheme()

    var body: some View {
        ZStack {
            // 背景の半透明レイヤーで盤面を暗転させ、ローディング状態であることを明示する
            theme.backgroundPrimary
                .opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                // アクティビティインジケーターで読み込み中であることを視覚的に伝える
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(theme.accentPrimary)
                    .scaleEffect(1.4)

                VStack(spacing: 8) {
                    Text("ゲームを準備しています")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.textPrimary)
                    Text("カードと盤面を読み込み中です。少々お待ちください。")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 12)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 36)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(theme.backgroundPrimary.opacity(0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(theme.accentPrimary.opacity(0.35), lineWidth: 1)
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("ゲームを準備しています。カードを読み込んでいます。")
    }
}

// MARK: - タイトル画面（簡易版）
// fileprivate にすることで同ファイル内の RootView から初期化可能にする
fileprivate struct TitleScreenView: View {
    /// タイトル画面で選択中のモード
    @Binding var selectedMode: GameMode
    /// ゲーム開始ボタンが押された際の処理
    let onStart: (GameMode) -> Void
    /// 詳細設定を開くアクション
    let onOpenSettings: () -> Void

    /// カラーテーマを用いてライト/ダーク両対応の配色を提供する
    private var theme = AppTheme()
    /// フリーモードのレギュレーションを管理するストア
    @StateObject private var freeModeStore = FreeModeRegulationStore()

    @State private var isPresentingHowToPlay: Bool = false
    /// フリーモード設定シートの表示状態
    @State private var isPresentingFreeModeEditor: Bool = false
    /// サイズクラスを参照し、iPad での余白やシート表現を最適化する
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// `@State` プロパティを保持したまま、外部（同ファイル内の RootView）から初期化できるようにするカスタムイニシャライザ
    /// - Parameters:
    ///   - selectedMode: 選択中モードを共有するバインディング
    ///   - onStart: ゲーム開始ボタンが押下された際に呼び出されるクロージャ
    ///   - onOpenSettings: タイトル右上のギアアイコンから設定シートを開く際のクロージャ
    init(selectedMode: Binding<GameMode>, onStart: @escaping (GameMode) -> Void, onOpenSettings: @escaping () -> Void) {
        self._selectedMode = selectedMode
        // `let` プロパティである onStart を代入するための明示的な初期化処理
        self.onStart = onStart
        self.onOpenSettings = onOpenSettings
        // `@State` の初期値を明示しておくことで、将来的な初期値変更にも対応しやすくする
        _isPresentingHowToPlay = State(initialValue: false)
    }


    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)

            // MARK: - アプリタイトルと簡単な説明
            VStack(spacing: 12) {
                Text("MonoKnight")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    // テーマの主文字色を適用し、ライト/ダーク両方で視認性を確保
                    .foregroundColor(theme.textPrimary)
                Text("カードで騎士を導き、盤面を踏破しよう")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    // 補足テキストはサブ文字色でコントラストを調整
                    .foregroundColor(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    // レギュラー幅では最大行幅を抑えて読みやすさを確保
                    .frame(maxWidth: 320)
            }

            // MARK: - モード選択セクション
            modeSelectionSection

            // MARK: - ゲーム開始ボタン
            Button(action: {
                // ゲーム開始操作を記録し、選択モードとの対応関係を追跡できるようにする
                debugLog("TitleScreenView: ゲーム開始ボタンをタップ 選択モード=\(selectedMode.identifier.rawValue)")
                onStart(selectedMode)
            }) {
                Label("\(selectedMode.displayName)で開始", systemImage: "play.fill")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            // ボタンはアクセントカラーとその上の文字色をテーマから取得
            .tint(theme.accentPrimary)
            .foregroundColor(theme.accentOnPrimary)
            .controlSize(.large)
            .accessibilityIdentifier("title_start_button")

            // 補助テキストで手札スロット上限とスタック仕様をまとめて案内
            Text("手札スロット \(selectedMode.handSize) 種類 / 先読み \(selectedMode.nextPreviewCount) 枚。\(selectedMode.stackingRuleDetailText)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(theme.textSecondary)
                .multilineTextAlignment(.center)

            // MARK: - 遊び方シートを開くボタン
            Button {
                // 遊び方シートを開いたタイミングを記録し、重複表示の調査に役立てる
                debugLog("TitleScreenView: 遊び方シート表示要求")
                // 遊び方の詳細解説をモーダルで表示する
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

            Spacer(minLength: 0)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.bottom, 36)
        .frame(maxWidth: contentMaxWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 背景もテーマのベースカラーへ切り替え、システム設定と調和させる
        .background(theme.backgroundPrimary)
        // 右上にギアアイコンを常設し、ゲーム外の詳細設定へ誘導する
        .overlay(alignment: .topTrailing) {
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
            .accessibilityHint("広告やプライバシー設定などの詳細を確認できます")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("タイトル画面。ゲームを開始するボタンがあります。手札スロットは最大\(selectedMode.handSize)種類で、\(selectedMode.stackingRuleDetailText)")
        // 遊び方シートの表示設定
        .sheet(isPresented: $isPresentingHowToPlay) {
            // NavigationStack でタイトルバーを付与しつつ共通ビューを利用
            NavigationStack {
                HowToPlayView(showsCloseButton: true)
            }
            // iPad では初期状態から `.large` を採用して情報を全て表示、iPhone では medium/large の切り替えを許容
            .presentationDetents(
                horizontalSizeClass == .regular ? [.large] : [.medium, .large]
            )
            .presentationDragIndicator(.visible)
        }
        // フリーモードのレギュレーション設定を全画面モーダルで表示し、数値調整へ集中できる編集体験にそろえる
        .fullScreenCover(isPresented: $isPresentingFreeModeEditor) {
            // NavigationStack を内包することでフルスクリーン表示でもタイトルバーのキャンセル/保存ボタンを維持する
            NavigationStack {
                FreeModeRegulationView(
                    initialRegulation: freeModeStore.regulation,
                    presets: GameMode.builtInModes,
                    onCancel: {
                        // 全画面カバーを閉じる操作をコールバックでまとめて扱い、呼び出し元と挙動を同期する
                        isPresentingFreeModeEditor = false
                    },
                    onSave: { newRegulation in
                        // 保存後にストアへ反映し、最新のモード内容を生成してからモーダルを閉じる
                        freeModeStore.update(newRegulation)
                        selectedMode = freeModeStore.makeGameMode()
                        isPresentingFreeModeEditor = false
                    }
                )
            }
        }
        // モーダル表示状態を監視し、遊び方シートの開閉タイミングを把握する
        .onChange(of: isPresentingHowToPlay) { _, newValue in
            debugLog("TitleScreenView.isPresentingHowToPlay 更新: \(newValue)")
        }
        // フリーモード設定の表示状態もログ出力してユーザー操作を追跡する
        .onChange(of: isPresentingFreeModeEditor) { _, newValue in
            debugLog("TitleScreenView.isPresentingFreeModeEditor 更新: \(newValue)")
        }
        // フリーモードのレギュレーションが更新された場合は選択モードの内容も再生成する
        .onChange(of: freeModeStore.regulation) { _, _ in
            if selectedMode.identifier == .freeCustom {
                selectedMode = freeModeStore.makeGameMode()
            }
        }
        // サイズクラスの変化を記録し、iPad のマルチタスク時に余白が崩れないか検証しやすくする
        .onChange(of: horizontalSizeClass) { _, newValue in
            debugLog("TitleScreenView.horizontalSizeClass 更新: \(String(describing: newValue))")
        }
    }

    /// モード選択の一覧を描画するセクション
    private var modeSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ゲームモード")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(theme.textPrimary)

            ForEach(availableModes) { mode in
                modeSelectionButton(for: mode)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// モードを選択するためのボタンレイアウト
    /// - Parameter mode: 表示対象のゲームモード
    private func modeSelectionButton(for mode: GameMode) -> some View {
        let isSelected = mode == selectedMode
        let isFreeMode = mode.identifier == .freeCustom

        return Button {
            if isFreeMode {
                debugLog("TitleScreenView: フリーモード設定シートを表示 -> \(mode.identifier.rawValue)")
                selectedMode = mode
                isPresentingFreeModeEditor = true
            } else {
                // 選択モードの変更を記録し、ボタンタップ順序を追跡できるようにする
                if selectedMode == mode {
                    debugLog("TitleScreenView: モードを再選択 -> \(mode.identifier.rawValue)")
                } else {
                    debugLog("TitleScreenView: モード切り替え -> \(mode.identifier.rawValue)")
                }
                selectedMode = mode
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(mode.displayName)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.textPrimary)
                    Spacer(minLength: 0)
                    if isFreeMode {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundColor(theme.accentPrimary)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(theme.accentPrimary)
                            .font(.system(size: 18, weight: .bold))
                    }
                }
                Text(primaryDescription(for: mode))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(theme.textSecondary)
                Text(secondaryDescription(for: mode))
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(theme.textSecondary.opacity(0.85))
                if isFreeMode {
                    Text("タップしてレギュレーションを編集できます")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(theme.textSecondary.opacity(0.9))
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(theme.backgroundElevated.opacity(isSelected ? 0.95 : 0.75))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isSelected ? theme.accentPrimary : theme.statisticBadgeBorder, lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(mode.displayName): \(primaryDescription(for: mode))"))
        .accessibilityHint(Text(isFreeMode ? "レギュレーション編集を開きます" : secondaryDescription(for: mode)))
    }

    /// 各モードの主要な特徴を短文で返す
    private func primaryDescription(for mode: GameMode) -> String {
        // GameMode 側で共通ロジックを用意したため、ここでは単純に参照するだけで済む
        return mode.primarySummaryText
    }

    /// ペナルティ量などの補足情報を返す
    private func secondaryDescription(for mode: GameMode) -> String {
        // 手札・先読み・ペナルティの表記も GameMode 側で統一管理する
        return mode.secondarySummaryText
    }
}

// MARK: - レイアウト調整用のヘルパー
private extension TitleScreenView {
    /// 表示するモードの一覧（ビルトイン + フリーモード）
    var availableModes: [GameMode] {
        var modes = GameMode.builtInModes
        modes.append(freeModeStore.makeGameMode())
        return modes
    }

    /// 横幅に応じてビューの最大幅を制御し、iPad では中央寄せのカード風レイアウトにする
    var contentMaxWidth: CGFloat? {
        horizontalSizeClass == .regular ? 520 : nil
    }

    /// 端末に合わせて余白を調整する
    var horizontalPadding: CGFloat {
        horizontalSizeClass == .regular ? 80 : 32
    }
}

