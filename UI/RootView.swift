import SwiftUI

/// ゲーム画面と設定画面を切り替えるルートビュー
/// `TabView` を用いて 2 つのタブを提供する
struct RootView: View {
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
    }
}

// MARK: - プレビュー
#Preview {
    RootView()
}

