import SwiftUI

/// ゲーム画面と設定画面を切り替えるルートビュー
/// `TabView` を用いて 2 つのタブを提供する
struct RootView: View {
    /// Game Center 認証済みかどうかを保持する状態
    /// - Note: 認証後はラベル表示に切り替える
    @State private var isAuthenticated = GameCenterService.shared.isAuthenticated

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
                    GameCenterService.shared.authenticateLocalPlayer { success in
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
                GameView()
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

