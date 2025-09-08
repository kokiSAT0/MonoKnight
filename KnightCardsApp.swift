import SwiftUI

// MARK: - アプリのエントリーポイント
// `@main` 属性を付与した構造体からアプリが開始される
@main
struct KnightCardsApp: App {
    var body: some Scene {
        WindowGroup {
            // アプリ起動時に最初に表示するビュー
            // 現在は仮の画面である `ContentView` を表示
            ContentView()
        }
    }
}

