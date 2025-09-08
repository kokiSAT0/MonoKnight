import Foundation

/// デバッグ用ログ出力をまとめたユーティリティ
/// - Note: リリースビルドでは呼び出しても何も表示されない
func debugLog(_ message: String, file: String = #file, line: Int = #line) {
#if DEBUG
    // ファイル名のみを抜き出してログに含める
    let filename = URL(fileURLWithPath: file).lastPathComponent
    print("[DEBUG] \(filename):\(line) - \(message)")
#else
    // リリースビルドでは何もしない
#endif
}
