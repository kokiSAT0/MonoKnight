import Foundation
import Game
import SharedSupport

/// キャンペーンの進捗（獲得スターやベストスコア）を管理するストア
/// - Note: `UserDefaults` へ JSON で保存し、アプリ再起動後も進捗を復元できるようにする
@MainActor
final class CampaignProgressStore: ObservableObject {
    /// UserDefaults へ保存する際のキー
    private static let storageKey = StorageKey.UserDefaults.campaignProgress
    /// デバッグ用全解放フラグを保存するキー
    private static let debugUnlockStorageKey = StorageKey.UserDefaults.campaignDebugUnlock
    /// 永続化先
    private let userDefaults: UserDefaults

    /// ステージごとの進捗マップ
    @Published private(set) var progressMap: [CampaignStageID: CampaignStageProgress]

    /// デバッグ用パスコードで全ステージ解放を行うフラグ
    /// - Note: 6031 を設定画面で入力すると true になり、全ての解放判定をバイパスする
    @Published private(set) var isDebugUnlockEnabled: Bool

    /// 合計スター数
    var totalStars: Int {
        progressMap.values.reduce(0) { $0 + $1.earnedStars }
    }

    /// 指定したステージの進捗を取得
    /// - Parameter stageID: 参照したいステージ ID
    /// - Returns: 保存済みの進捗があればその値
    func progress(for stageID: CampaignStageID) -> CampaignStageProgress? {
        progressMap[stageID]
    }

    /// 初期化
    /// - Parameter userDefaults: 保存に利用する `UserDefaults`
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.progressMap = [:]
        // デバッグ用パスコード入力状態を先に復元し、View 側が即座に表示を更新できるようにする
        self.isDebugUnlockEnabled = userDefaults.bool(forKey: Self.debugUnlockStorageKey)
        self.progressMap = loadProgress()
    }

    /// ステージが解放済みか判定する
    /// - Parameter stage: 対象ステージ
    /// - Returns: 解放済みであれば true
    func isStageUnlocked(_ stage: CampaignStage) -> Bool {
        // デバッグ用パスコードが有効になっている場合は全ステージを即座に解放する
        if isDebugUnlockEnabled {
            return true
        }
        switch stage.unlockRequirement {
        case .always:
            return true
        case .totalStars(let minimum):
            return totalStars >= minimum
        case .chapterTotalStars(let chapter, let minimum):
            // MARK: 章単位のスター数を合計し、条件を満たしているか評価する
            return minimum <= 0 || totalStars(inChapter: chapter) >= minimum
        case .stageClear(let requiredID):
            let earned = progressMap[requiredID]?.earnedStars ?? 0
            return earned > 0
        }
    }

    /// 指定章で獲得済みのスター数を合算する
    /// - Parameter chapter: 集計対象の章番号
    /// - Returns: 対象章で得たスター数の合計
    func totalStars(inChapter chapter: Int) -> Int {
        // MARK: progressMap はステージ ID をキーに保持しているため、章番号が一致するもののみ抽出して加算する
        progressMap.reduce(into: 0) { partialResult, element in
            if element.key.chapter == chapter {
                partialResult += element.value.earnedStars
            }
        }
    }

    /// クリア結果を登録し、獲得スターやベスト記録を更新する
    /// - Parameters:
    ///   - stage: 対象ステージ
    ///   - metrics: クリア時の統計値
    /// - Returns: 更新後の記録と評価
    @discardableResult
    func registerClear(for stage: CampaignStage, metrics: CampaignStageClearMetrics) -> CampaignStageClearRecord {
        let evaluation = stage.evaluateClear(with: metrics)
        let previous = progressMap[stage.id] ?? CampaignStageProgress()
        var current = previous

        current.earnedStars = max(current.earnedStars, evaluation.earnedStars)
        if evaluation.achievedSecondaryObjective {
            current.achievedSecondaryObjective = true
        }
        if evaluation.achievedScoreGoal {
            current.achievedScoreGoal = true
        }
        if evaluation.achievedTwoStarScoreGoal {
            current.achievedTwoStarScoreGoal = true
        }
        if evaluation.achievedThreeStarScoreGoal {
            current.achievedThreeStarScoreGoal = true
        }

        current.updateBestCampaignScore(metrics.score)
        current.bestMoveCount = CampaignProgressStore.minValue(current.bestMoveCount, newValue: metrics.moveCount)
        current.bestTotalMoveCount = CampaignProgressStore.minValue(current.bestTotalMoveCount, newValue: metrics.totalMoveCount)
        current.bestPenaltyCount = CampaignProgressStore.minValue(current.bestPenaltyCount, newValue: metrics.penaltyCount)
        current.bestFocusCount = CampaignProgressStore.minValue(current.bestFocusCount, newValue: metrics.focusCount)
        current.bestElapsedSeconds = CampaignProgressStore.minValue(current.bestElapsedSeconds, newValue: metrics.elapsedSeconds)

        progressMap[stage.id] = current
        persistProgress()

        debugLog("CampaignProgressStore: ステージ \(stage.id.displayCode) を更新 スター=\(current.earnedStars)")

        return CampaignStageClearRecord(
            stage: stage,
            evaluation: evaluation,
            previousProgress: previous,
            progress: current
        )
    }

    /// デバッグ用パスコードによる全ステージ解放を有効化する
    /// - Note: すでに有効化済みの場合は重複保存を避ける
    func enableDebugUnlock() {
        guard !isDebugUnlockEnabled else { return }
        isDebugUnlockEnabled = true
        userDefaults.set(true, forKey: Self.debugUnlockStorageKey)
        debugLog("CampaignProgressStore: デバッグ用全ステージ解放フラグを有効化しました")
    }

    /// デバッグ用パスコードによる全ステージ解放を無効化する
    /// - Note: 解除操作時はフラグを false へ戻し、永続化内容も同時に更新する
    func disableDebugUnlock() {
        // 既に無効化済みであれば追加処理は不要なので早期リターンする
        guard isDebugUnlockEnabled else { return }
        isDebugUnlockEnabled = false
        userDefaults.set(false, forKey: Self.debugUnlockStorageKey)
        debugLog("CampaignProgressStore: デバッグ用全ステージ解放フラグを無効化しました")
    }

    /// 進捗データを読み出し
    private func loadProgress() -> [CampaignStageID: CampaignStageProgress] {
        guard let data = userDefaults.data(forKey: Self.storageKey) else { return [:] }
        do {
            let decoded = try JSONDecoder().decode([String: CampaignStageProgress].self, from: data)
            var map: [CampaignStageID: CampaignStageProgress] = [:]
            for (key, value) in decoded {
                guard let id = CampaignStageID(storageKey: key) else { continue }
                map[id] = value
            }
            return map
        } catch {
            // エラーの詳細を debugError で出力しつつ、発生箇所を分かりやすくメッセージ化する
            debugError(error, message: "CampaignProgressStore: 読み込みに失敗しました")
            return [:]
        }
    }

    /// 現在の進捗を保存
    private func persistProgress() {
        let encoder = JSONEncoder()
        let storageDictionary = progressMap.reduce(into: [String: CampaignStageProgress]()) { partialResult, element in
            partialResult[element.key.storageKey] = element.value
        }
        do {
            let data = try encoder.encode(storageDictionary)
            userDefaults.set(data, forKey: Self.storageKey)
        } catch {
            // 保存時に失敗した場合もエラー内容と原因箇所を記録する
            debugError(error, message: "CampaignProgressStore: 保存に失敗しました")
        }
    }

    /// ベスト値を更新する際の最小値計算
    private static func minValue(_ current: Int?, newValue: Int) -> Int {
        if let current {
            return min(current, newValue)
        } else {
            return newValue
        }
    }

}

/// ステージの進捗を表すモデル
struct CampaignStageProgress: Codable {
    /// 獲得済みスター数
    var earnedStars: Int
    /// 二つ目のスター条件を達成したことがあるか
    var achievedSecondaryObjective: Bool
    /// 三つ目のスター条件を達成したことがあるか
    var achievedScoreGoal: Bool
    /// 二つ目のスコアスター条件を達成したことがあるか
    var achievedTwoStarScoreGoal: Bool
    /// 三つ目のスコアスター条件を達成したことがあるか
    var achievedThreeStarScoreGoal: Bool
    /// ベストスコア（キャンペーン現行方式では高いほど良い）
    var bestScore: Int?
    /// ベストスコアを記録したスコア方式バージョン
    var bestScoreVersion: Int?
    /// ベストの移動回数
    var bestMoveCount: Int?
    /// ベストの合計手数
    var bestTotalMoveCount: Int?
    /// 最小ペナルティ手数
    var bestPenaltyCount: Int?
    /// 最小フォーカス回数
    var bestFocusCount: Int?
    /// 最短クリアタイム（秒）
    var bestElapsedSeconds: Int?

    init(
        earnedStars: Int = 0,
        achievedSecondaryObjective: Bool = false,
        achievedScoreGoal: Bool = false,
        achievedTwoStarScoreGoal: Bool = false,
        achievedThreeStarScoreGoal: Bool = false,
        bestScore: Int? = nil,
        bestScoreVersion: Int? = nil,
        bestMoveCount: Int? = nil,
        bestTotalMoveCount: Int? = nil,
        bestPenaltyCount: Int? = nil,
        bestFocusCount: Int? = nil,
        bestElapsedSeconds: Int? = nil
    ) {
        self.earnedStars = earnedStars
        self.achievedSecondaryObjective = achievedSecondaryObjective
        self.achievedScoreGoal = achievedScoreGoal
        self.achievedTwoStarScoreGoal = achievedTwoStarScoreGoal
        self.achievedThreeStarScoreGoal = achievedThreeStarScoreGoal
        self.bestScore = bestScore
        self.bestScoreVersion = bestScoreVersion
        self.bestMoveCount = bestMoveCount
        self.bestTotalMoveCount = bestTotalMoveCount
        self.bestPenaltyCount = bestPenaltyCount
        self.bestFocusCount = bestFocusCount
        self.bestElapsedSeconds = bestElapsedSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        earnedStars = try container.decodeIfPresent(Int.self, forKey: .earnedStars) ?? 0
        achievedSecondaryObjective = try container.decodeIfPresent(Bool.self, forKey: .achievedSecondaryObjective) ?? false
        achievedScoreGoal = try container.decodeIfPresent(Bool.self, forKey: .achievedScoreGoal) ?? false
        achievedTwoStarScoreGoal = try container.decodeIfPresent(Bool.self, forKey: .achievedTwoStarScoreGoal) ?? achievedSecondaryObjective
        achievedThreeStarScoreGoal = try container.decodeIfPresent(Bool.self, forKey: .achievedThreeStarScoreGoal) ?? achievedScoreGoal
        bestScore = try container.decodeIfPresent(Int.self, forKey: .bestScore)
        bestScoreVersion = try container.decodeIfPresent(Int.self, forKey: .bestScoreVersion)
        bestMoveCount = try container.decodeIfPresent(Int.self, forKey: .bestMoveCount)
        bestTotalMoveCount = try container.decodeIfPresent(Int.self, forKey: .bestTotalMoveCount)
        bestPenaltyCount = try container.decodeIfPresent(Int.self, forKey: .bestPenaltyCount)
        bestFocusCount = try container.decodeIfPresent(Int.self, forKey: .bestFocusCount)
        bestElapsedSeconds = try container.decodeIfPresent(Int.self, forKey: .bestElapsedSeconds)
    }

    mutating func updateBestCampaignScore(_ newScore: Int) {
        if bestScoreVersion != CampaignScoring.currentVersion {
            bestScore = newScore
            bestScoreVersion = CampaignScoring.currentVersion
        } else {
            bestScore = bestScore.map { max($0, newScore) } ?? newScore
        }
    }
}

/// クリア登録後のレスポンス
struct CampaignStageClearRecord {
    let stage: CampaignStage
    let evaluation: CampaignStageEvaluation
    /// クリア登録前の進捗（演出用に差分を知りたい場合に利用）
    let previousProgress: CampaignStageProgress
    let progress: CampaignStageProgress
}
