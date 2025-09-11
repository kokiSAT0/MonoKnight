import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// アプリ全体で未捕捉のエラーを捕捉し詳細なログを出力するハンドラ
/// - Note: DEBUG ビルドのみ有効
enum ErrorReporter {
    /// グローバルなエラーハンドラを設定する
    static func setup() {
#if DEBUG
#if canImport(Darwin)
        // MARK: 未捕捉例外の捕捉
        // Swift 以外の例外(NSException)が発生した場合にも
        // 詳細な情報をログへ出力できるようハンドラを登録する
        NSSetUncaughtExceptionHandler { exception in
            // 例外名と理由をデバッグログに出力
            debugLog("未捕捉例外: \(exception.name.rawValue) - \(exception.reason ?? "理由不明")")
            // スタックトレースを取得し、改行区切りで表示
            let trace = exception.callStackSymbols.joined(separator: "\n")
            debugLog("スタックトレース:\n\(trace)")
        }

        // MARK: 致命的シグナルの捕捉
        // プロセス終了につながる代表的なシグナルを横取りし
        // スタックトレースを表示した上で終了する
        func handleSignal(_ signalValue: Int32, name: String) {
            debugLog("\(name) を受信")
            let stack = Thread.callStackSymbols.joined(separator: "\n")
            debugLog("スタックトレース:\n\(stack)")
            exit(signalValue)
        }
        signal(SIGABRT) { _ in handleSignal(SIGABRT, name: "SIGABRT") }
        signal(SIGILL)  { _ in handleSignal(SIGILL,  name: "SIGILL") }
        signal(SIGSEGV) { _ in handleSignal(SIGSEGV, name: "SIGSEGV") }
        signal(SIGFPE)  { _ in handleSignal(SIGFPE,  name: "SIGFPE") }
        signal(SIGBUS)  { _ in handleSignal(SIGBUS,  name: "SIGBUS") }
#endif
#endif
    }
}

