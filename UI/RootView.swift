import SwiftUI

/// ゲーム画面と設定画面を切り替えるルートビュー
/// `TabView` を用いて 2 つのタブを提供する
struct RootView: View {
    /// Game Center 連携を扱うサービス（プロトコル型で受け取る）
    private let gameCenterService: GameCenterServiceProtocol
    /// 広告表示を扱うサービス（GameView へ受け渡す）
    private let adsService: AdsServiceProtocol
    /// Game Center 認証済みかどうかを保持する状態
    /// - Note: 認証後はラベル表示に切り替える
    @State private var isAuthenticated: Bool
    /// ゲームタブでタイトル画面を表示するかどうかのフラグ
    /// - NOTE: メニューからタイトルへ戻る操作を受けて切り替える
    @State private var isShowingTitleScreen: Bool = false

    /// 依存サービスを外部から注入可能にする初期化処理
    /// - Parameters:
    ///   - gameCenterService: Game Center 連携用サービス（デフォルトはシングルトン）
    ///   - adsService: 広告表示用サービス（デフォルトはシングルトン）
    init(gameCenterService: GameCenterServiceProtocol = GameCenterService.shared,
         adsService: AdsServiceProtocol = AdsService.shared) {
        self.gameCenterService = gameCenterService
        self.adsService = adsService
        _isAuthenticated = State(initialValue: gameCenterService.isAuthenticated)
    }

    var body: some View {
        VStack(spacing: 12) {
            // MARK: - Game Center サインイン UI
            if isAuthenticated {
                // 認証済みであることを示すラベル
                Text("Game Center にサインイン済み")
                    .font(.caption)
                    .accessibilityIdentifier("gc_authenticated")
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
            }

            // MARK: - タブビュー本体
            TabView {
                // MARK: - ゲームタブ
                ZStack {
                    // MARK: - メインのゲーム画面
                    GameView(
                        gameCenterService: gameCenterService,
                        adsService: adsService,
                        onRequestReturnToTitle: {
                            // メニューからの通知でタイトル画面を表示
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isShowingTitleScreen = true
                            }
                        }
                    )
                    .opacity(isShowingTitleScreen ? 0 : 1)
                    .allowsHitTesting(!isShowingTitleScreen)

                    // MARK: - タイトル画面のオーバーレイ
                    if isShowingTitleScreen {
                        TitleScreenView {
                            // タイトルからゲーム開始を選んだら元に戻す
                            withAnimation(.easeInOut(duration: 0.25)) {
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
        }
        .padding()
    }
}

// MARK: - プレビュー
#Preview {
    RootView()
}

// MARK: - タイトル画面（簡易版）
private struct TitleScreenView: View {
    /// ゲーム開始ボタンが押された際の処理
    let onStart: () -> Void

    /// カラーテーマを用いてライト/ダーク両対応の配色を提供する
    private var theme = AppTheme()

    @State private var isPresentingHowToPlay: Bool = false


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
            }

            // MARK: - ゲーム開始ボタン
            Button(action: onStart) {
                Label("ゲームを開始", systemImage: "play.fill")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            // ボタンはアクセントカラーとその上の文字色をテーマから取得
            .tint(theme.accentPrimary)
            .foregroundColor(theme.accentOnPrimary)
            .controlSize(.large)
            .accessibilityIdentifier("title_start_button")

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
        .padding(.horizontal, 32)
        .padding(.bottom, 36)
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
        }
    }
}

