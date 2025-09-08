import Foundation

/// デバッグ時の一般的なログ出力を行うユーティリティ関数
/// - Parameters:
///   - message: 表示したいメッセージ
///   - file: 呼び出し元のファイルパス（自動で取得）
///   - line: 呼び出し元の行番号（自動で取得）
///   - function: 呼び出し元の関数名（自動で取得）
/// - Note: リリースビルドでは呼び出しても何も表示されない
func debugLog(
    _ message: String,
    file: String = #file,
    line: Int = #line,
    function: String = #function
) {
#if DEBUG
    // ファイル名のみを抜き出してログに含める
    let filename = URL(fileURLWithPath: file).lastPathComponent
    // 呼び出し元の関数名も合わせて出力することで、原因箇所を特定しやすくする
    print("[DEBUG] \(filename):\(line) \(function) - \(message)")
#else
    // リリースビルドでは何もしない
#endif
}

/// エラー内容を詳細に表示するためのログ出力関数
/// - Parameters:
///   - error: 発生した `Error`
///   - message: 追加で残したい説明（任意）
///   - file: 呼び出し元のファイルパス（自動で取得）
///   - line: 呼び出し元の行番号（自動で取得）
///   - function: 呼び出し元の関数名（自動で取得）
/// - Note: DEBUG ビルド専用。リリース時には出力されない
func debugError(
    _ error: Error,
    message: String? = nil,
    file: String = #file,
    line: Int = #line,
    function: String = #function
) {
#if DEBUG
    // エラーを NSError として扱うことで domain や code などの詳細を取得
    let nsError = error as NSError
    // ファイル名のみを抽出してログを簡潔にする
    let filename = URL(fileURLWithPath: file).lastPathComponent
    // 任意メッセージとエラー詳細を組み合わせた情報を作成
    var parts: [String] = []
    if let message { parts.append(message) }
    parts.append("domain: \(nsError.domain)")
    parts.append("code: \(nsError.code)")
    parts.append("description: \(nsError.localizedDescription)")
    let detail = parts.joined(separator: " | ")
    // スタックトレースを取得し、行単位で改行を入れて読みやすくする
    let stackSymbols = Thread.callStackSymbols.joined(separator: "\n")
    // [ERROR] プレフィックスを付け、発生箇所と詳細な情報を出力
    print("[ERROR] \(filename):\(line) \(function) - \(detail)\nスタックトレース:\n\(stackSymbols)")
#else
    // リリースビルドでは何もしない
#endif
}
