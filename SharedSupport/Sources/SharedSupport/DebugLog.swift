import Foundation
#if canImport(OSLog)
import OSLog
#endif

// MARK: - フロントエンド向けログエントリ定義

/// デバッグログをフロントエンドから閲覧する際の重要度区分
/// - Note: UI 側でレベル別に色付けやアイコン表示を行うため、シンプルな列挙体として公開する
public enum DebugLogLevel: String, Codable, CaseIterable {
    /// 通常の情報ログ（`debugLog` 由来）
    case info
    /// エラー詳細ログ（`debugError` 由来）
    case error
}

/// UI で扱いやすいよう整形したデバッグログ 1 件分の情報
/// - Warning: `message` にはファイル名や行番号など個人情報に繋がりうる記述が含まれるため、公開ビルドでは閲覧制御に注意する
public struct DebugLogEntry: Identifiable, Equatable {
    /// `Identifiable` に準拠するためのユニーク ID
    public let id: UUID
    /// ログレベル（情報 or エラー）
    public let level: DebugLogLevel
    /// 実際に表示する文字列（ファイル名・行番号・メッセージを含む）
    public let message: String
    /// ログを生成した時刻
    public let timestamp: Date

    /// 指定した内容でログエントリを作成する
    /// - Parameters:
    ///   - level: ログレベル
    ///   - message: 表示するテキスト
    ///   - timestamp: 記録時刻
    public init(level: DebugLogLevel, message: String, timestamp: Date = Date()) {
        self.id = UUID()
        self.level = level
        self.message = message
        self.timestamp = timestamp
    }
}

// MARK: - フロントエンド共有用のログ履歴ストア

/// デバッグログの最新数百件を保持し、UI から参照可能にするヘルパー
/// - Note: TestFlight など Xcode 以外の環境でも素早く状況確認できるよう、軽量なメモリストアとして実装する
public final class DebugLogHistory {
    /// シングルトンインスタンス。Game モジュール・アプリ本体の双方から共有利用する
    public static let shared = DebugLogHistory()

    /// 新しいログエントリが追加された際に発火する通知名
    public static let didAppendEntryNotification = Notification.Name("DebugLogHistoryDidAppendEntryNotification")

    /// Notification.userInfo 内で使用するキー
    public enum NotificationKey {
        /// 追加されたエントリ（`DebugLogEntry`）を格納するキー
        public static let entry = "entry"
    }

    /// 内部状態へのアクセスを直列化するためのキュー
    private let queue = DispatchQueue(label: "jp.monoknight.debug-log-history")
    /// フロントエンドへ公開するログの最大保持件数
    /// - Note: 画面上でスクロールできる量を想定し、必要に応じて変更可能にしておく
    public var maximumEntryCount: Int = 250

    /// 実際に保持しているログ配列
    private var entries: [DebugLogEntry] = []
    /// フロントエンド向け履歴保持を有効化しているかどうか
    /// - Important: TestFlight での暫定デバッグを優先するため初期値は `true`
    private var isCaptureEnabled: Bool = true

    private init() {}

    /// フロントエンド用ログコンソールが利用可能かどうか
    /// - Returns: 表示可能であれば true
    public var isFrontEndViewerEnabled: Bool {
        queue.sync { isCaptureEnabled }
    }

    /// フロントエンド向けの履歴保持を切り替える
    /// - Parameters:
    ///   - enabled: `true` で保持を有効化、`false` で無効化
    /// - Note: 無効化時には既存の履歴を破棄し、公開ビルドでの露出を避ける
    public func setFrontEndViewerEnabled(_ enabled: Bool) {
        let shouldNotify: Bool = queue.sync {
            guard isCaptureEnabled != enabled else { return false }
            isCaptureEnabled = enabled
            if !enabled {
                entries.removeAll()
            }
            return true
        }

        if shouldNotify {
            NotificationCenter.default.post(name: Self.didAppendEntryNotification, object: self, userInfo: nil)
        }
    }

    /// 新しいログエントリを履歴へ追加する
    /// - Parameters:
    ///   - level: ログレベル
    ///   - message: 出力した文字列
    public func append(level: DebugLogLevel, message: String) {
        let newEntry: DebugLogEntry? = queue.sync {
            guard isCaptureEnabled else { return nil }

            // 最新ログを末尾へ追加しつつ、上限を超えた場合は古いものから破棄する
            var updatedEntries = entries
            let entry = DebugLogEntry(level: level, message: message)
            updatedEntries.append(entry)
            if updatedEntries.count > maximumEntryCount {
                let overflowCount = updatedEntries.count - maximumEntryCount
                updatedEntries.removeFirst(overflowCount)
            }
            entries = updatedEntries
            return entry
        }

        guard let entry = newEntry else { return }
        NotificationCenter.default.post(
            name: Self.didAppendEntryNotification,
            object: self,
            userInfo: [NotificationKey.entry: entry]
        )
    }

    /// これまでに保持しているログ一覧を配列として取得する
    /// - Returns: 現在保持しているログエントリのスナップショット
    public func snapshot() -> [DebugLogEntry] {
        queue.sync { entries }
    }

    /// 保持しているログを全て破棄する
    /// - Note: UI からのリセット操作や機密情報の即時削除に利用する
    public func clear() {
        let didClear = queue.sync { () -> Bool in
            guard !entries.isEmpty else { return false }
            entries.removeAll()
            return true
        }

        if didClear {
            NotificationCenter.default.post(name: Self.didAppendEntryNotification, object: self, userInfo: nil)
        }
    }
}

/// OSLog へ出力する際に利用する共通サブシステム名
/// - Note: Bundle ID が取得できなかった場合も識別しやすいようフォールバック文字列を用意する
private let debugLogSubsystem: String = {
    // main.bundleIdentifier が空の場合（ユニットテストなど）でも判別しやすい識別子を返す
    if let identifier = Bundle.main.bundleIdentifier, !identifier.isEmpty {
        return identifier
    }
    return "MonoKnight"
}()

#if canImport(OSLog)
/// 一般ログを書き出すための Logger インスタンス
/// - Important: TestFlight などリリースビルドでもログが収集できるよう、`Logger` を用いて統一的に出力する
private let debugLogger = Logger(subsystem: debugLogSubsystem + ".debug", category: "general")

/// エラーログを書き出すための Logger インスタンス
private let errorLogger = Logger(subsystem: debugLogSubsystem + ".debug", category: "error")

/// OSLog へ重複出力するかどうかの判定結果をキャッシュ
/// - NOTE: DEBUG ビルドで Xcode へ接続している場合、`print` と `Logger` の両方に流すと
///   コンソールへ同じ文字列が二重に表示されてしまうため、デフォルトでは片方に限定する。
///   実機デバッグなどで OSLog を確認したい場合は `MONOKNIGHT_DEBUG_OSLOG=1` の環境変数を
///   付与して起動し、このフラグを明示的に有効化する。
private let shouldForwardLogsToOSLog: Bool = {
#if DEBUG
    // 環境変数で明示的に指定されたときのみ OSLog 転送を有効化する
    let environment = ProcessInfo.processInfo.environment
    return environment["MONOKNIGHT_DEBUG_OSLOG"] == "1"
#else
    // リリースビルドでは OSLog への出力を常に有効にして TestFlight でも追跡できるようにする
    return true
#endif
}()
#endif

/// デバッグ時の一般的なログ出力を行うユーティリティ関数
/// - Parameters:
///   - message: 表示したいメッセージ
///   - file: 呼び出し元のファイルパス（自動で取得）
///   - line: 呼び出し元の行番号（自動で取得）
///   - function: 呼び出し元の関数名（自動で取得）
/// - Note: リリースビルドでは呼び出しても何も表示されない
public func debugLog(
    _ message: String,
    file: String = #file,
    line: Int = #line,
    function: String = #function
) {
    // ファイル名のみを抜き出してログに含める
    let filename = URL(fileURLWithPath: file).lastPathComponent
    // 呼び出し元の関数名も合わせて出力することで、原因箇所を特定しやすくする
    let composedMessage = "[DEBUG] \(filename):\(line) \(function) - \(message)"

#if DEBUG
    // DEBUG ビルドでは従来どおり標準出力にも表示して開発体験を維持する
    print(composedMessage)
#endif

    // TestFlight や実機デバッグでも Console.app から追跡できるよう OSLog 経由でも出力する
#if canImport(OSLog)
    if shouldForwardLogsToOSLog {
        debugLogger.log("\(composedMessage, privacy: .public)")
    }
#else
    // OSLog が利用できない環境（Linux でのテストなど）では print のみで代替する
    // - Note: Linux 上ではリリースビルドを配信しない想定のため、このフォールバックで十分
#if !DEBUG
    print(composedMessage)
#endif
#endif

    // フロントエンド向けのログ履歴にも記録して、UI から追跡できるようにする
    DebugLogHistory.shared.append(level: .info, message: composedMessage)
}

/// エラー内容を詳細に表示するためのログ出力関数
/// - Parameters:
///   - error: 発生した `Error`
///   - message: 追加で残したい説明（任意）
///   - file: 呼び出し元のファイルパス（自動で取得）
///   - line: 呼び出し元の行番号（自動で取得）
///   - function: 呼び出し元の関数名（自動で取得）
/// - Note: DEBUG ビルド専用。リリース時には出力されない
public func debugError(
    _ error: Error,
    message: String? = nil,
    file: String = #file,
    line: Int = #line,
    function: String = #function
) {
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
    let composedMessage = "[ERROR] \(filename):\(line) \(function) - \(detail)\nスタックトレース:\n\(stackSymbols)"

#if DEBUG
    // DEBUG ビルドでは従来通り標準出力に流して素早い検証を行う
    print(composedMessage)
#endif

    // エラーログは OSLog の error レベルで送出しておき、TestFlight 配信版でも収集できるようにする
#if canImport(OSLog)
    if shouldForwardLogsToOSLog {
        errorLogger.error("\(composedMessage, privacy: .public)")
    }
#else
    // OSLog が無い環境では print のみで代替（ERROR プレフィックスは保持）
#if !DEBUG
    print(composedMessage)
#endif
#endif

    // エラー情報はフロントエンド用の履歴にも残し、TestFlight 上で迅速に原因追跡できるようにする
    DebugLogHistory.shared.append(level: .error, message: composedMessage)
}
