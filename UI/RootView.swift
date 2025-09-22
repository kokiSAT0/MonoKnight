import SwiftUI
import Game

/// ゲーム画面と設定画面を切り替えるルートビュー
/// `TabView` を用いて 2 つのタブを提供する
@MainActor
/// SwiftUI ビュー全体を MainActor 上で扱い、MainActor 隔離されたシングルトン（GameCenterService / AdsService）へアクセスする際の競合を防ぐ
/// - NOTE: Swift 6 で厳格化された並行性モデルに追従し、ビルドエラー（MainActor 分離違反）を確実に回避するための指定
struct RootView: View {
    /// Game Center 連携を扱うサービス（プロトコル型で受け取る）
    private let gameCenterService: GameCenterServiceProtocol
    /// 広告表示を扱うサービス（GameView へ受け渡す）
    private let adsService: AdsServiceProtocol
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
        VStack(spacing: 12) {
            // MARK: - Game Center サインイン UI
            if isAuthenticated {
                // 認証済みであることを示すラベル
                Text("Game Center にサインイン済み")
                    .font(.caption)
                    .accessibilityIdentifier("gc_authenticated")
                    // 画面端に密着しないよう左右と上部へ余白を個別指定
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
            } else {
                // サインインボタンをタップで認証を開始
                Button(action: {
                    gameCenterService.authenticateLocalPlayer { success in
                        // 成否に応じて状態を更新し、ラベル表示を切り替える
                        isAuthenticated = success
                    }
                }) {
                    Text("Game Center サインイン")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("gc_sign_in_button")
                // ボタン単位で左右と上部の余白を確保し、全体のパディング削除後も視認性を保つ
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }

            // MARK: - タブビュー本体
            TabView {
                // MARK: - ゲームタブ
                ZStack {
                    // MARK: - メインのゲーム画面
                    GameView(
                        mode: activeMode,
                        gameCenterService: gameCenterService,
                        adsService: adsService,
                        onRequestReturnToTitle: {
                            // メニューからの通知でタイトル画面を表示
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isShowingTitleScreen = true
                                // タイトルに戻った際は選択中のモードを現在のプレイ内容で初期化する
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
                            // タイトルからゲーム開始を選んだら元に戻す
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
            // VStack 外のパディングを削除したため、TabView 自身が画面いっぱいに広がるよう最大サイズを指定
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            Button(action: { onStart(selectedMode) }) {
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

