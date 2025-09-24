import Foundation

/// クラッシュ発生やユーザーフィードバックを履歴として保持するイベントモデル
/// - Important: アプリ全体で共有し、TestFlight や実機で発生した問題を定期的に振り返るための土台となる
public struct CrashFeedbackEvent: Codable, Identifiable, Equatable {
    /// イベントのカテゴリ区分
    public enum Category: String, Codable, CaseIterable {
        /// クラッシュや未捕捉例外などの致命的イベント
        case crash
        /// ユーザーや開発者からの手動フィードバック
        case feedback
        /// クラッシュログを確認し終えたレビュー履歴
        case review

        /// ログ出力に利用する日本語ラベル
        var japaneseLabel: String {
            switch self {
            case .crash:
                return "クラッシュ"
            case .feedback:
                return "フィードバック"
            case .review:
                return "レビュー"
            }
        }
    }

    /// 識別用の UUID
    public let id: UUID
    /// イベントの区分
    public let category: Category
    /// 一覧表示時に読みやすい短めのタイトル
    public let title: String
    /// 詳細な説明文（原因やメモ等を含む）
    public let detail: String
    /// 記録日時
    public let timestamp: Date

    /// 任意の内容でイベントを初期化する
    /// - Parameters:
    ///   - id: 既存イベントを再構築する際に利用する ID（省略時は自動生成）
    ///   - category: イベント区分
    ///   - title: 一覧表示で利用する簡易タイトル
    ///   - detail: 詳細説明やメモ
    ///   - timestamp: 記録時刻（省略時は現在時刻）
    public init(
        id: UUID = UUID(),
        category: Category,
        title: String,
        detail: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.detail = detail
        self.timestamp = timestamp
    }
}

/// クラッシュ履歴の要約結果
public struct CrashFeedbackSummary: Equatable {
    /// クラッシュカテゴリの件数
    public let crashCount: Int
    /// フィードバックカテゴリの件数
    public let feedbackCount: Int
    /// 直近のクラッシュ発生日（存在しない場合は nil）
    public let lastCrashAt: Date?
    /// 直近のイベント一覧（最新順）
    public let latestEvents: [CrashFeedbackEvent]
}

/// クラッシュログやフィードバックを保存・参照するシングルトン
/// - Note: `UserDefaults` を利用した軽量な JSON 保存のため、実機でも簡単に履歴を採取できる
public final class CrashFeedbackCollector {
    /// 共有インスタンス
    public static let shared = CrashFeedbackCollector()

    /// イベント追加時に発火する通知名
    public static let didAppendEventNotification = Notification.Name("CrashFeedbackCollectorDidAppendEventNotification")

    /// Notification.userInfo 内で使用するキー
    public enum NotificationKey {
        /// 追加された `CrashFeedbackEvent`
        public static let event = "event"
    }

    /// `UserDefaults` に保存するキー
    private let storageKey: String
    /// 永続化に利用する UserDefaults
    private let defaults: UserDefaults
    /// 内部状態の排他制御用キュー
    private let queue = DispatchQueue(label: "jp.monoknight.crash-feedback-collector")
    /// JSON エンコード／デコードに利用する共通インスタンス
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    /// 直近イベントの保持上限（必要に応じて調整可能）
    private var maxStoredEvents: Int
    /// 実際に保持しているイベント一覧
    private var events: [CrashFeedbackEvent]

    /// デフォルト初期化
    /// - Parameters:
    ///   - defaults: 保存に利用する `UserDefaults`
    ///   - storageKey: 永続化用キー
    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "jp.monoknight.crash-feedback-history",
        maximumStoredEvents: Int = 300
    ) {
        self.storageKey = storageKey
        self.defaults = defaults
        self.maxStoredEvents = max(10, maximumStoredEvents)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        if
            let data = defaults.data(forKey: storageKey),
            let decoded = try? decoder.decode([CrashFeedbackEvent].self, from: data)
        {
            self.events = decoded
        } else {
            self.events = []
        }
    }

    /// 保存件数の上限を取得・更新する
    public var maximumStoredEvents: Int {
        get { queue.sync { maxStoredEvents } }
        set {
            queue.async {
                let sanitized = max(10, newValue)
                guard sanitized != self.maxStoredEvents else { return }
                self.maxStoredEvents = sanitized
                if self.events.count > sanitized {
                    self.events.removeFirst(self.events.count - sanitized)
                    self.persistCurrentEventsLocked()
                }
            }
        }
    }

    /// 未捕捉例外を記録する
    /// - Parameters:
    ///   - name: 例外名
    ///   - reason: 例外理由
    ///   - stackSymbols: スタックトレース
    /// - Returns: 追加されたイベント
    @discardableResult
    public func recordException(
        name: String,
        reason: String?,
        stackSymbols: [String]
    ) -> CrashFeedbackEvent {
        var lines: [String] = []
        lines.append("例外名: \(name)")
        if let reason, !reason.isEmpty {
            lines.append("理由: \(reason)")
        } else {
            lines.append("理由: 不明")
        }
        lines.append("スタックトレース:\n" + stackSymbols.joined(separator: "\n"))
        let detail = lines.joined(separator: "\n")
        let title = "未捕捉例外 - \(name)"
        return appendEvent(category: .crash, title: title, detail: detail)
    }

    /// シグナルなどのクラッシュ情報を記録する
    /// - Parameters:
    ///   - signalName: 受信したシグナル名
    ///   - reason: 追加理由（任意）
    ///   - stackSymbols: 発生時点のスタックトレース
    /// - Returns: 追加されたイベント
    @discardableResult
    public func recordCrashEvent(
        signalName: String,
        reason: String?,
        stackSymbols: [String]? = nil
    ) -> CrashFeedbackEvent {
        var lines: [String] = []
        lines.append("シグナル: \(signalName)")
        if let reason, !reason.isEmpty {
            lines.append("詳細: \(reason)")
        }
        if let stackSymbols, !stackSymbols.isEmpty {
            lines.append("スタックトレース:\n" + stackSymbols.joined(separator: "\n"))
        }
        let detail = lines.joined(separator: "\n")
        let title = reason.map { "\(signalName) - \($0)" } ?? signalName
        return appendEvent(category: .crash, title: title, detail: detail)
    }

    /// ユーザーまたは開発者のフィードバックを記録する
    /// - Parameters:
    ///   - source: 連絡経路や投稿者名
    ///   - message: フィードバック本文
    ///   - metadata: 端末情報など付加情報（任意）
    /// - Returns: 追加されたイベント
    @discardableResult
    public func recordUserFeedback(
        source: String,
        message: String,
        metadata: [String: String] = [:]
    ) -> CrashFeedbackEvent {
        var lines: [String] = []
        lines.append("投稿元: \(source)")
        if !metadata.isEmpty {
            lines.append("メタデータ:")
            for (key, value) in metadata.sorted(by: { $0.key < $1.key }) {
                lines.append("- \(key): \(value)")
            }
        }
        lines.append("本文:\n\(message)")
        let detail = lines.joined(separator: "\n")
        return appendEvent(category: .feedback, title: source, detail: detail)
    }

    /// クラッシュ履歴をレビューしたことを記録する（未確認のクラッシュがある場合のみ追加）
    /// - Parameters:
    ///   - note: レビュー時のメモ
    ///   - reviewer: 確認者（省略時は「定期チェック」）
    /// - Returns: 新しく追加された場合はイベント、対象がなかった場合は nil
    @discardableResult
    public func markReviewCompletedIfNeeded(
        note: String? = nil,
        reviewer: String? = nil
    ) -> CrashFeedbackEvent? {
        var appendedEvent: CrashFeedbackEvent?
        queue.sync {
            guard !events.isEmpty else { return }
            let lastReviewIndex = events.lastIndex(where: { $0.category == .review })
            let hasPendingEvents: Bool
            if let lastReviewIndex {
                let nextIndex = events.index(after: lastReviewIndex)
                if nextIndex < events.endIndex {
                    let slice = events[nextIndex..<events.endIndex]
                    hasPendingEvents = slice.contains { $0.category != .review }
                } else {
                    hasPendingEvents = false
                }
            } else {
                hasPendingEvents = true
            }
            guard hasPendingEvents else { return }

            let summary = summaryLocked(latestCount: 0)
            var lines: [String] = []
            lines.append("クラッシュ件数: \(summary.crashCount)")
            lines.append("フィードバック件数: \(summary.feedbackCount)")
            if let lastCrash = summary.lastCrashAt {
                lines.append("最終クラッシュ: \(format(date: lastCrash))")
            } else {
                lines.append("最終クラッシュ: なし")
            }
            if let note, !note.isEmpty {
                lines.append("メモ:\n\(note)")
            }

            let event = CrashFeedbackEvent(
                category: .review,
                title: reviewer ?? "定期チェック",
                detail: lines.joined(separator: "\n")
            )
            appendLocked(event: event)
            appendedEvent = event
        }

        if let event = appendedEvent {
            NotificationCenter.default.post(
                name: Self.didAppendEventNotification,
                object: self,
                userInfo: [NotificationKey.event: event]
            )
        }
        return appendedEvent
    }

    /// 最新イベントを取得する
    /// - Parameter limit: 取得件数（nil の場合は全件）
    /// - Returns: 時系列順の配列
    public func recentEvents(limit: Int? = nil) -> [CrashFeedbackEvent] {
        queue.sync {
            guard let limit else { return events }
            guard limit >= 0 else { return [] }
            if limit == 0 { return [] }
            return Array(events.suffix(limit))
        }
    }

    /// 履歴の要約を取得する
    /// - Parameter latestCount: 直近イベントを最大何件含めるか
    /// - Returns: 件数・最終クラッシュ日時・直近イベントを含むサマリー
    public func summary(latestCount: Int = 10) -> CrashFeedbackSummary {
        queue.sync {
            summaryLocked(latestCount: latestCount)
        }
    }

    /// ログへ要約を出力する
    /// - Parameters:
    ///   - label: ログ識別用ラベル
    ///   - latestCount: 表示する直近イベントの件数
    public func logSummary(label: String, latestCount: Int = 5) {
        let summary = summary(latestCount: latestCount)
        let lastCrashText = summary.lastCrashAt.map { format(date: $0) } ?? "なし"
        debugLog("CrashFeedbackCollector: \(label) | クラッシュ件数=\(summary.crashCount) | フィードバック件数=\(summary.feedbackCount) | 最終クラッシュ=\(lastCrashText)")

        if summary.latestEvents.isEmpty {
            debugLog("CrashFeedbackCollector: 直近イベントはまだ記録されていません")
            return
        }

        debugLog("CrashFeedbackCollector: 直近イベント一覧 (最大\(latestCount)件)")
        for event in summary.latestEvents.suffix(latestCount) {
            let timestamp = format(date: event.timestamp)
            debugLog(" - [\(event.category.japaneseLabel)] \(timestamp) | \(event.title)")
        }
    }

    /// すべての履歴を削除する（テスト用途やリセット操作向け）
    public func clearAll() {
        let didClear = queue.sync { () -> Bool in
            guard !events.isEmpty else { return false }
            events.removeAll()
            defaults.removeObject(forKey: storageKey)
            return true
        }
        if didClear {
            NotificationCenter.default.post(name: Self.didAppendEventNotification, object: self, userInfo: nil)
        }
    }

    /// イベントを追加し、必要に応じて上限件数を維持する
    /// - Parameters:
    ///   - category: イベント区分
    ///   - title: タイトル
    ///   - detail: 詳細説明
    /// - Returns: 追加されたイベント
    private func appendEvent(
        category: CrashFeedbackEvent.Category,
        title: String,
        detail: String
    ) -> CrashFeedbackEvent {
        let event = CrashFeedbackEvent(category: category, title: title, detail: detail)
        queue.sync {
            appendLocked(event: event)
        }
        NotificationCenter.default.post(
            name: Self.didAppendEventNotification,
            object: self,
            userInfo: [NotificationKey.event: event]
        )
        return event
    }

    /// 追加処理本体（キュー内でのみ呼び出す）
    /// - Parameter event: 追加したいイベント
    private func appendLocked(event: CrashFeedbackEvent) {
        events.append(event)
        if events.count > maxStoredEvents {
            events.removeFirst(events.count - maxStoredEvents)
        }
        persistCurrentEventsLocked()
    }

    /// サマリー計算（排他制御済みの前提で呼び出す）
    /// - Parameter latestCount: 取得したい直近イベント数
    private func summaryLocked(latestCount: Int) -> CrashFeedbackSummary {
        let crashCount = events.filter { $0.category == .crash }.count
        let feedbackCount = events.filter { $0.category == .feedback }.count
        let lastCrashAt = events.last(where: { $0.category == .crash })?.timestamp
        let latest: [CrashFeedbackEvent]
        if latestCount > 0 {
            latest = Array(events.suffix(latestCount))
        } else {
            latest = []
        }
        return CrashFeedbackSummary(
            crashCount: crashCount,
            feedbackCount: feedbackCount,
            lastCrashAt: lastCrashAt,
            latestEvents: latest
        )
    }

    /// 現在のイベント配列を JSON として保存する（排他制御済みの前提で呼び出す）
    private func persistCurrentEventsLocked() {
        do {
            let data = try encoder.encode(events)
            defaults.set(data, forKey: storageKey)
        } catch {
            debugLog("CrashFeedbackCollector: イベント保存に失敗しました - \(error)")
        }
    }

    /// ISO8601 形式で日時を整形する
    /// - Parameter date: 整形対象の日時
    /// - Returns: フラクショナル秒付きの ISO8601 文字列
    private func format(date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
