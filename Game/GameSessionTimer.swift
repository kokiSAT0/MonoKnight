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
    }

    /// 計測をリセットして新しいゲームセッションを開始する
    /// - Parameter now: 計測開始に用いる時刻（デフォルトは現在時刻）
    mutating func reset(now: Date = Date()) {
        startDate = now
        endDate = nil
        finalizedElapsedSeconds = 0
    }

    /// 現在までの経過時間を確定させ、整数秒で返す
    /// - Parameter referenceDate: 終了処理に利用する時刻（テストからの指定用）
    /// - Returns: 四捨五入した整数秒。既に確定済みの場合は前回値を返す
    @discardableResult
    mutating func finalize(referenceDate: Date = Date()) -> Int {
        // 終了済みであれば既存値をそのまま返し、二重計算を避ける
        if let endDate {
            let duration = max(0, endDate.timeIntervalSince(startDate))
            finalizedElapsedSeconds = max(0, Int(duration.rounded()))
            return finalizedElapsedSeconds
        }

        // 終了時刻を記録し、負値が入らないように保護しながら整数秒へ丸める
        let finishDate = referenceDate
        endDate = finishDate
        let duration = max(0, finishDate.timeIntervalSince(startDate))
        finalizedElapsedSeconds = max(0, Int(duration.rounded()))
        return finalizedElapsedSeconds
    }

    /// ライブ計測としての経過秒数を返す
    /// - Parameter referenceDate: 現在時刻の代わりに使用したい値
    /// - Returns: 小数点以下を四捨五入した整数秒
    func liveElapsedSeconds(asOf referenceDate: Date = Date()) -> Int {
        // 終了済みなら確定値を返し、進行中なら現在との差分を計算する
        let effectiveEndDate = endDate ?? referenceDate
        let duration = max(0, effectiveEndDate.timeIntervalSince(startDate))
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
    }

    /// テスト専用に確定済みの経過秒数を調整する
    /// - Parameter seconds: 指定したい経過秒数
    mutating func overrideFinalizedElapsedSecondsForTesting(_ seconds: Int) {
        finalizedElapsedSeconds = max(0, seconds)
        if seconds > 0 {
            // 目視確認しやすいよう、開始時刻との差分が指定秒数となる終了時刻を仮置きする
            endDate = startDate.addingTimeInterval(TimeInterval(seconds))
        } else {
            endDate = nil
        }
    }
}
#endif
