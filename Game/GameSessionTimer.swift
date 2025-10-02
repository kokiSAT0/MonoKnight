import Foundation

/// ゲームプレイ中の経過時間計測を担当するヘルパー構造体
/// - Note: `GameCore` からタイマー関連の責務を切り離し、将来的な再利用やテスト容易性を高める。
struct GameSessionTimer {
    /// 計測開始時刻。リセットのたびに現在時刻へ更新される
    private(set) var startDate: Date
    /// 計測終了時刻。未確定のあいだは `nil` を維持する
    private(set) var endDate: Date?
    /// 確定済みの経過秒数。ゲームクリアなどで確定した値を保持する
    private(set) var finalizedElapsedSeconds: Int
    /// 累計の一時停止時間（秒単位）
    /// - Note: 一時停止が複数回挟まった場合でも合計値を保持し、最終的な経過時間から差し引く。
    private(set) var pausedDuration: TimeInterval
    /// 一時停止開始時刻。`nil` の場合は現在プレイ中とみなす
    private(set) var pauseStartedAt: Date?
    /// 既に終了時刻が確定しているかどうかを示すフラグ
    var isFinalized: Bool { endDate != nil }
    /// 外部から参照しやすいように確定済みの秒数を公開
    var elapsedSeconds: Int { finalizedElapsedSeconds }

    /// 現在時刻を基準として初期化する
    /// - Parameter now: 明示的に与えたい基準時刻（テスト時に利用）
    init(now: Date = Date()) {
        // 初期化時は開始時刻を現在に合わせ、終了時刻は未確定のままとする
        self.startDate = now
        self.endDate = nil
        self.finalizedElapsedSeconds = 0
        self.pausedDuration = 0
        self.pauseStartedAt = nil
    }

    /// 計測をリセットして新しいゲームセッションを開始する
    /// - Parameter now: 計測開始に用いる時刻（デフォルトは現在時刻）
    mutating func reset(now: Date = Date()) {
        startDate = now
        endDate = nil
        finalizedElapsedSeconds = 0
        pausedDuration = 0
        pauseStartedAt = nil
    }

    /// 一時停止を開始し、以降の経過時間から差し引けるようにする
    /// - Parameter referenceDate: 一時停止が開始された時刻
    mutating func beginPause(at referenceDate: Date = Date()) {
        // 既に一時停止中であれば二重登録を避ける
        guard pauseStartedAt == nil else { return }
        pauseStartedAt = referenceDate
    }

    /// 一時停止を終了し、累積一時停止時間へ反映する
    /// - Parameter referenceDate: 一時停止終了時刻
    mutating func endPause(at referenceDate: Date = Date()) {
        guard let pauseStartedAt else { return }
        // 経過時間が負になるケースを避けるために 0 で下限を設ける
        let additionalPause = max(0, referenceDate.timeIntervalSince(pauseStartedAt))
        pausedDuration += additionalPause
        self.pauseStartedAt = nil
    }

    /// 現在までの経過時間を確定させ、整数秒で返す
    /// - Parameter referenceDate: 終了処理に利用する時刻（テストからの指定用）
    /// - Returns: 四捨五入した整数秒。既に確定済みの場合は前回値を返す
    @discardableResult
    mutating func finalize(referenceDate: Date = Date()) -> Int {
        // 終了済みであれば既存値をそのまま返し、二重計算を避ける
        if let endDate {
            let totalPaused = pausedDuration
            let duration = max(0, endDate.timeIntervalSince(startDate) - totalPaused)
            finalizedElapsedSeconds = max(0, Int(duration.rounded()))
            return finalizedElapsedSeconds
        }

        // 終了時刻を記録し、負値が入らないように保護しながら整数秒へ丸める
        let finishDate = referenceDate
        // 一時停止中に finalize された場合でも整合性が取れるように、一度 pause を終了させて累積時間へ反映する
        if pauseStartedAt != nil {
            endPause(at: finishDate)
        }
        endDate = finishDate
        let totalPaused = pausedDuration
        let duration = max(0, finishDate.timeIntervalSince(startDate) - totalPaused)
        finalizedElapsedSeconds = max(0, Int(duration.rounded()))
        return finalizedElapsedSeconds
    }

    /// ライブ計測としての経過秒数を返す
    /// - Parameter referenceDate: 現在時刻の代わりに使用したい値
    /// - Returns: 小数点以下を四捨五入した整数秒
    func liveElapsedSeconds(asOf referenceDate: Date = Date()) -> Int {
        // 終了済みなら確定値を返し、進行中なら現在との差分を計算する
        let effectiveEndDate = endDate ?? referenceDate
        let ongoingPauseDuration: TimeInterval
        if let pauseStartedAt {
            // finalize 済みでなければ現在時刻との差分を算出する。finalize 済みの場合は pauseStartedAt が nil なので通らない
            ongoingPauseDuration = max(0, effectiveEndDate.timeIntervalSince(pauseStartedAt))
        } else {
            ongoingPauseDuration = 0
        }
        let totalPaused = pausedDuration + ongoingPauseDuration
        let duration = max(0, effectiveEndDate.timeIntervalSince(startDate) - totalPaused)
        return max(0, Int(duration.rounded()))
    }
}

#if DEBUG
extension GameSessionTimer {
    /// テストから開始時刻を任意に差し替える
    /// - Parameter newStartDate: 望ましい開始時刻
    mutating func overrideStartDateForTesting(_ newStartDate: Date) {
        startDate = newStartDate
        // 進行中として扱うため、終了時刻はリセットする
        endDate = nil
        pausedDuration = 0
        pauseStartedAt = nil
    }

    /// テスト専用に確定済みの経過秒数を調整する
    /// - Parameter seconds: 指定したい経過秒数
    mutating func overrideFinalizedElapsedSecondsForTesting(_ seconds: Int) {
        finalizedElapsedSeconds = max(0, seconds)
        if seconds > 0 {
            // 目視確認しやすいよう、開始時刻との差分が指定秒数となる終了時刻を仮置きする
            endDate = startDate.addingTimeInterval(TimeInterval(seconds))
            pausedDuration = 0
            pauseStartedAt = nil
        } else {
            endDate = nil
            pausedDuration = 0
            pauseStartedAt = nil
        }
    }
}
#endif
