import SwiftUI

/// ゲーム画面と設定画面を切り替えるルートビュー
/// `TabView` を用いて 2 つのタブを提供する
struct RootView: View {
    /// Game Center 認証済みかどうかを追跡するフラグ
    /// - Note: `onAppear` が複数回呼ばれても二重認証を避ける
    @State private var didAuthenticate = false

    var body: some View {
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
        .onAppear {
            // ルート ViewController が取得できるタイミングで認証を実施
            // Game Center のログイン UI を安全に表示できる
            guard !didAuthenticate else { return } // 二重呼び出しを防止
            GameCenterService.shared.authenticateLocalPlayer()
            didAuthenticate = true
        }
    }
}

// MARK: - プレビュー
#Preview {
    RootView()
}

