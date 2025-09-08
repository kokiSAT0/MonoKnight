import SwiftUI

// MARK: - アプリのエントリーポイント
// `@main` 属性を付与した構造体からアプリが開始される
@main
struct KnightCardsApp: App {
    /// イニシャライザで Game Center 認証を実行
    /// - Note: アプリ起動時に一度だけ呼び出される
    init() {
        // Game Center のローカルプレイヤー認証を開始
        GameCenterService.shared.authenticateLocalPlayer()
    }

    var body: some Scene {
        WindowGroup {
            // MARK: 起動直後に表示するルートビュー
            // TabView でゲームと設定を切り替える `RootView` を表示
            RootView()
        }
    }
}

