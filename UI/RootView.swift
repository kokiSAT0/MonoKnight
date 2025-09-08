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
                GameView(gameCenterService: gameCenterService, adsService: adsService)
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

