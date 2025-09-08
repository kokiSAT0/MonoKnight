import SwiftUI

// MARK: - アプリのエントリーポイント
// `@main` 属性を付与した構造体からアプリが開始される
@main
struct KnightCardsApp: App {
    var body: some Scene {
        WindowGroup {
            // MARK: 起動直後に表示するルートビュー
            // 実際のゲーム画面である `GameView` を表示
            GameView()
        }
    }
}

