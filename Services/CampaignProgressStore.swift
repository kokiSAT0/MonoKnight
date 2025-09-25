import Foundation
import Game
import SharedSupport

/// キャンペーンの進捗（獲得スターやベストスコア）を管理するストア
/// - Note: `UserDefaults` へ JSON で保存し、アプリ再起動後も進捗を復元できるようにする
@MainActor
final class CampaignProgressStore: ObservableObject {
    /// UserDefaults へ保存する際のキー
    private let storageKey = "campaign_progress_v1"
    /// 永続化先
    private let userDefaults: UserDefaults

    /// ステージごとの進捗マップ
    @Published private(set) var progressMap: [CampaignStageID: CampaignStageProgress]

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
        self.progressMap = loadProgress()
    }

    /// ステージが解放済みか判定する
    /// - Parameter stage: 対象ステージ
    /// - Returns: 解放済みであれば true
    func isStageUnlocked(_ stage: CampaignStage) -> Bool {
        switch stage.unlockRequirement {
        case .always:
            return true
        case .totalStars(let minimum):
            return totalStars >= minimum
        case .stageClear(let requiredID):
            let earned = progressMap[requiredID]?.earnedStars ?? 0
            return earned > 0
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
        var current = progressMap[stage.id] ?? CampaignStageProgress()

        current.earnedStars = max(current.earnedStars, evaluation.earnedStars)
        if evaluation.achievedSecondaryObjective {
            current.achievedSecondaryObjective = true
        }
        if evaluation.achievedScoreGoal {
            current.achievedScoreGoal = true
        }

        current.bestScore = CampaignProgressStore.minValue(current.bestScore, newValue: metrics.score)
        current.bestMoveCount = CampaignProgressStore.minValue(current.bestMoveCount, newValue: metrics.moveCount)
        current.bestTotalMoveCount = CampaignProgressStore.minValue(current.bestTotalMoveCount, newValue: metrics.totalMoveCount)
        current.bestPenaltyCount = CampaignProgressStore.minValue(current.bestPenaltyCount, newValue: metrics.penaltyCount)
        current.bestElapsedSeconds = CampaignProgressStore.minValue(current.bestElapsedSeconds, newValue: metrics.elapsedSeconds)

        progressMap[stage.id] = current
        saveProgress()

        debugLog("CampaignProgressStore: ステージ \(stage.id.displayCode) を更新 スター=\(current.earnedStars)")

        return CampaignStageClearRecord(stage: stage, evaluation: evaluation, progress: current)
    }

    /// 進捗データを読み出し
    private func loadProgress() -> [CampaignStageID: CampaignStageProgress] {
        guard let data = userDefaults.data(forKey: storageKey) else { return [:] }
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
    private func saveProgress() {
        let encoder = JSONEncoder()
        let storageDictionary = progressMap.reduce(into: [String: CampaignStageProgress]()) { partialResult, element in
            partialResult[element.key.storageKey] = element.value
        }
        do {
            let data = try encoder.encode(storageDictionary)
            userDefaults.set(data, forKey: storageKey)
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
    var earnedStars: Int = 0
    /// 二つ目のスター条件を達成したことがあるか
    var achievedSecondaryObjective: Bool = false
    /// 三つ目のスター条件を達成したことがあるか
    var achievedScoreGoal: Bool = false
    /// ベストスコア（低いほど良い）
    var bestScore: Int?
    /// ベストの移動回数
    var bestMoveCount: Int?
    /// ベストの合計手数
    var bestTotalMoveCount: Int?
    /// 最小ペナルティ手数
    var bestPenaltyCount: Int?
    /// 最短クリアタイム（秒）
    var bestElapsedSeconds: Int?
}

/// クリア登録後のレスポンス
struct CampaignStageClearRecord {
    let stage: CampaignStage
    let evaluation: CampaignStageEvaluation
    let progress: CampaignStageProgress
}
