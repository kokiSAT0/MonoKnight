import SwiftUI
import Game

/// ゲーム画面と設定画面を切り替えるルートビュー
/// `TabView` を用いて 2 つのタブを提供する
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
    /// Game Center 認証済みかどうかを保持する状態
    /// - Note: 認証後はラベル表示に切り替える
    @State private var isAuthenticated: Bool
    /// ゲームタブでタイトル画面を表示するかどうかのフラグ
    /// - NOTE: アプリ起動直後にタイトルを先に表示したいので初期値は `true`
    ///         メニューからタイトルへ戻る操作でもこのフラグを再度 `true` に切り替える
    @State private var isShowingTitleScreen: Bool = true
    /// 実際にゲームへ適用しているモード
    @State private var activeMode: GameMode = .standard
    /// タイトル画面で選択中のモード（開始ボタン押下で activeMode に反映する）
    @State private var selectedModeForTitle: GameMode = .standard
    /// GameView の再生成に利用するセッション ID（モードが変わるたびに更新する）
    @State private var gameSessionID = UUID()
    /// トップステータスバーの実測高さを保持し、レイアウトログへ出力する
    @State private var topBarHeight: CGFloat = 0
    /// 直近に出力したレイアウトスナップショットを記録し、ログの重複出力を防ぐ
    @State private var lastLoggedLayoutSnapshot: RootLayoutSnapshot?
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
        // 認証状態の初期値も解決済みのサービスから取得し、@State へ格納する。
        _isAuthenticated = State(initialValue: resolvedGameCenterService.isAuthenticated)
    }

    var body: some View {
        GeometryReader { geometry in
            // MARK: - 現在のジオメトリ情報を整理し、レイアウトログとトップバー調整へ使うコンテキストを生成
            let layoutContext = RootLayoutContext(
                geometrySize: geometry.size,
                safeAreaInsets: geometry.safeAreaInsets,
                horizontalSizeClass: horizontalSizeClass
            )

            TabView {
                // MARK: - ゲームタブ
                ZStack {
                    // MARK: - メインのゲーム画面
                    GameView(
                        mode: activeMode,
                        gameCenterService: gameCenterService,
                        adsService: adsService,
                        onRequestReturnToTitle: {
                            // 右上メニューなどからタイトルへ戻るリクエストを受け取ったことを記録しておく
                            debugLog("RootView: タイトル画面表示要求を受信 現在モード=\(activeMode.identifier.rawValue)")
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isShowingTitleScreen = true
                                // タイトルに戻ったタイミングで、直前のプレイ内容をタイトル側のモード選択へ反映する
                                selectedModeForTitle = activeMode
                            }
                        }
                    )
                    .id(gameSessionID)
                    .opacity(isShowingTitleScreen ? 0 : 1)
                    .allowsHitTesting(!isShowingTitleScreen)

                    // MARK: - タイトル画面のオーバーレイ
                    if isShowingTitleScreen {
                        TitleScreenView(selectedMode: $selectedModeForTitle) { mode in
                            // ゲーム開始が選択された際の状態更新を記録し、原因調査を容易にする
                            debugLog("RootView: ゲーム開始リクエストを受信 選択モード=\(mode.identifier.rawValue)")
                            withAnimation(.easeInOut(duration: 0.25)) {
                                activeMode = mode
                                gameSessionID = UUID()
                                isShowingTitleScreen = false
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: isShowingTitleScreen)
                .tabItem {
                    // システムアイコンとラベルを組み合わせてタブを定義
                    Label("ゲーム", systemImage: "gamecontroller")
                }

                // MARK: - 設定タブ
                SettingsView()
                    .tabItem {
                        Label("設定", systemImage: "gearshape")
                    }
            }
            // `GeometryReader` 内でも最大サイズを指定し、タブが端末全体へ広がるようにする
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // MARK: - トップステータスバーを safeAreaInset で挿入し、iPhone/iPad 双方で安定させる
            .safeAreaInset(edge: .top, spacing: 0) {
                topStatusInset(context: layoutContext)
            }
            // MARK: - レイアウト計測用の不可視オーバーレイを重ね、異常値をログで把握できるようにする
            .background(layoutDiagnosticOverlay(context: layoutContext))
            // 初期表示時のレイアウト値をログに残し、ステータスバー高さなどの基準値を把握する
            .onAppear {
                debugLog(
                    "RootView.onAppear: size=\(layoutContext.geometrySize), safeArea(top=\(layoutContext.safeAreaTop), bottom=\(layoutContext.safeAreaBottom)), horizontalSizeClass=\(String(describing: horizontalSizeClass)), authenticated=\(isAuthenticated)"
                )
            }
        }
        // 背景色をタブ領域にも適用し、safe area を含めて統一感のある配色にする
        .background(theme.backgroundPrimary.ignoresSafeArea())
        // トップバーの高さが更新された際にログを残し、iPad の分割表示などでの変化を追跡する
        .onPreferenceChange(TopBarHeightPreferenceKey.self) { newHeight in
            let previousHeight = topBarHeight
            guard previousHeight != newHeight else { return }
            debugLog("RootView.topBarHeight 更新: 旧値=\(previousHeight), 新値=\(newHeight)")
            topBarHeight = newHeight
        }
        // Game Center 認証状態の変化を監視し、表示コンポーネント切り替えの契機を把握する
        .onChange(of: isAuthenticated) { _, newValue in
            debugLog("RootView.isAuthenticated 更新: \(newValue)")
        }
        // タイトル画面の表示状態を記録し、想定外のトランジションが起きていないか追跡する
        .onChange(of: isShowingTitleScreen) { _, newValue in
            debugLog("RootView.isShowingTitleScreen 更新: \(newValue)")
        }
        // 実際にプレイへ利用しているモードが切り替わったタイミングを記録する
        .onChange(of: activeMode) { _, newValue in
            debugLog("RootView.activeMode 更新: \(newValue.identifier.rawValue)")
        }
        // タイトル画面上で選択中のモードが変化した場合もログ化し、操作の追跡精度を高める
        .onChange(of: selectedModeForTitle) { _, newValue in
            debugLog("RootView.selectedModeForTitle 更新: \(newValue.identifier.rawValue)")
        }
        // サイズクラス変化（端末回転や iPad のマルチタスク）を記録し、レイアウト崩れ再現時の手掛かりとする
        .onChange(of: horizontalSizeClass) { _, newValue in
            debugLog("RootView.horizontalSizeClass 更新: \(String(describing: newValue))")
        }
    }
}

// MARK: - レイアウト支援メソッドと定数
private extension RootView {
    /// トップステータスバーを生成し、Game Center 認証状況に応じた UI を返す
    /// - Parameter context: 現在の画面サイズや safe area をまとめたレイアウトコンテキスト
    /// - Returns: safeAreaInset へ挿入するビュー
    @ViewBuilder
    func topStatusInset(context: RootLayoutContext) -> some View {
        HStack {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: RootLayoutMetrics.topBarContentSpacing) {
                if isAuthenticated {
                    Text("Game Center にサインイン済み")
                        .font(.caption)
                        // テーマ由来のサブ文字色を使い、背景とのコントラストを確保
                        .foregroundColor(theme.textSecondary)
                        .accessibilityIdentifier("gc_authenticated")
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Button(action: {
                        // 認証要求のトリガーを記録して、失敗時の切り分けを容易にする
                        debugLog("RootView: Game Center 認証開始要求 現在の認証状態=\(isAuthenticated)")
                        gameCenterService.authenticateLocalPlayer { success in
                            // コールバックでの成否もログへ残し、原因調査の手がかりとする
                            debugLog("RootView: Game Center 認証完了 success=\(success)")
                            isAuthenticated = success
                        }
                    }) {
                        Text("Game Center サインイン")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("gc_sign_in_button")
                }
            }
            .frame(maxWidth: context.topBarMaxWidth ?? .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, context.topBarHorizontalPadding)
        .padding(.top, RootLayoutMetrics.topBarBaseTopPadding + context.regularTopPaddingFallback)
        .padding(.bottom, RootLayoutMetrics.topBarBaseBottomPadding)
        .background(
            theme.backgroundPrimary
                .opacity(RootLayoutMetrics.topBarBackgroundOpacity)
                .ignoresSafeArea(edges: .top)
        )
        .overlay(alignment: .bottom) {
            Divider()
                .background(theme.statisticBadgeBorder)
                .opacity(RootLayoutMetrics.topBarDividerOpacity)
        }
        // GeometryReader で高さを取得し、PreferenceKey を介して親ビューへ伝搬する
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: TopBarHeightPreferenceKey.self, value: proxy.size.height)
            }
        )
    }

    /// レイアウト関連の情報を監視する不可視オーバーレイを返す
    /// - Parameter context: GeometryReader から抽出した値をまとめたコンテキスト
    /// - Returns: ログ出力専用のゼロサイズビュー
    func layoutDiagnosticOverlay(context: RootLayoutContext) -> some View {
        let snapshot = RootLayoutSnapshot(
            context: context,
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

    /// 取得したレイアウトスナップショットをログへ出力し、重複を避ける
    /// - Parameters:
    ///   - snapshot: 記録対象のレイアウト情報
    ///   - reason: ログ出力の契機
    func logLayoutSnapshot(_ snapshot: RootLayoutSnapshot, reason: String) {
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
    }

    /// トップバーの高さを親ビューへ伝えるための PreferenceKey
    struct TopBarHeightPreferenceKey: PreferenceKey {
        static var defaultValue: CGFloat = 0

        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }
}

// MARK: - プレビュー
#Preview {
    RootView()
}

// MARK: - タイトル画面（簡易版）
// fileprivate にすることで同ファイル内の RootView から初期化可能にする
fileprivate struct TitleScreenView: View {
    /// タイトル画面で選択中のモード
    @Binding var selectedMode: GameMode
    /// ゲーム開始ボタンが押された際の処理
    let onStart: (GameMode) -> Void

    /// カラーテーマを用いてライト/ダーク両対応の配色を提供する
    private var theme = AppTheme()

    @State private var isPresentingHowToPlay: Bool = false
    /// サイズクラスを参照し、iPad での余白やシート表現を最適化する
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// `@State` プロパティを保持したまま、外部（同ファイル内の RootView）から初期化できるようにするカスタムイニシャライザ
    /// - Parameters:
    ///   - selectedMode: 選択中モードを共有するバインディング
    ///   - onStart: ゲーム開始ボタンが押下された際に呼び出されるクロージャ
    init(selectedMode: Binding<GameMode>, onStart: @escaping (GameMode) -> Void) {
        self._selectedMode = selectedMode
        // `let` プロパティである onStart を代入するための明示的な初期化処理
        self.onStart = onStart
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

            Text("手札 \(selectedMode.handSize) 枚 / 先読み \(selectedMode.nextPreviewCount) 枚")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(theme.textSecondary)

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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("タイトル画面。ゲームを開始するボタンがあります。")
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
        // モーダル表示状態を監視し、遊び方シートの開閉タイミングを把握する
        .onChange(of: isPresentingHowToPlay) { _, newValue in
            debugLog("TitleScreenView.isPresentingHowToPlay 更新: \(newValue)")
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

            ForEach(GameMode.allModes) { mode in
                modeSelectionButton(for: mode)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// モードを選択するためのボタンレイアウト
    /// - Parameter mode: 表示対象のゲームモード
    private func modeSelectionButton(for mode: GameMode) -> some View {
        let isSelected = mode == selectedMode

        return Button {
            // 選択モードの変更を記録し、ボタンタップ順序を追跡できるようにする
            if selectedMode == mode {
                debugLog("TitleScreenView: モードを再選択 -> \(mode.identifier.rawValue)")
            } else {
                debugLog("TitleScreenView: モード切り替え -> \(mode.identifier.rawValue)")
            }
            selectedMode = mode
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(mode.displayName)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.textPrimary)
                    Spacer(minLength: 0)
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
        .accessibilityHint(Text(secondaryDescription(for: mode)))
    }

    /// 各モードの主要な特徴を短文で返す
    private func primaryDescription(for mode: GameMode) -> String {
        let spawnText = mode.requiresSpawnSelection ? "任意スポーン" : "固定スポーン"
        switch mode.identifier {
        case .standard5x5:
            return "\(mode.boardSize)×\(mode.boardSize) ・ \(spawnText) ・ 標準デッキ"
        case .classicalChallenge:
            return "\(mode.boardSize)×\(mode.boardSize) ・ \(spawnText) ・ 桂馬カードのみ"
        }
    }

    /// ペナルティ量などの補足情報を返す
    private func secondaryDescription(for mode: GameMode) -> String {
        let manualPenalty = "引き直し +\(mode.manualRedrawPenaltyCost)"
        let revisitText: String
        if mode.revisitPenaltyCost > 0 {
            revisitText = "再訪 +\(mode.revisitPenaltyCost)"
        } else {
            revisitText = "再訪ペナルティなし"
        }
        return "手札 \(mode.handSize) / 先読み \(mode.nextPreviewCount) / \(manualPenalty) / \(revisitText)"
    }
}

// MARK: - レイアウト調整用のヘルパー
private extension TitleScreenView {
    /// 横幅に応じてビューの最大幅を制御し、iPad では中央寄せのカード風レイアウトにする
    var contentMaxWidth: CGFloat? {
        horizontalSizeClass == .regular ? 520 : nil
    }

    /// 端末に合わせて余白を調整する
    var horizontalPadding: CGFloat {
        horizontalSizeClass == .regular ? 80 : 32
    }
}

