import SwiftUI

// MARK: - 仮のコンテンツビュー
// 開発初期段階の動作確認用としてテキストのみを表示する
struct ContentView: View {
    var body: some View {
        // 画面中央に簡単なメッセージを配置
        Text("KnightCards 開発中…")
            .font(.title)
            .padding()
    }
}

// MARK: - プレビュー
#Preview {
    // Xcode の Canvas 上で ContentView を表示するためのプレビュー
    ContentView()
}

