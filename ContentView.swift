import SwiftUI

// MARK: - ゲーム画面へのエントリービュー
// 現時点では `GameView` を直接表示し、後にナビゲーション構造を追加する想定
struct ContentView: View {
    var body: some View {
        // SpriteKit を埋め込んだゲーム画面を表示
        GameView()
    }
}

// MARK: - プレビュー
#Preview {
    // Xcode の Canvas 上で ContentView を表示するためのプレビュー
    ContentView()
}

