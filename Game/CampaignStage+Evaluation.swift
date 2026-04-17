import Foundation

extension CampaignStage.SecondaryObjective {
    /// 条件をプレイ結果に照らし合わせて判定
    /// - Parameter metrics: クリア時の統計値
    /// - Returns: 条件を満たしていれば true
    func isSatisfied(by metrics: CampaignStageClearMetrics) -> Bool {
        switch self {
        case .finishWithinMoves(let maxMoves):
            return metrics.moveCount <= maxMoves
        case .finishWithinSeconds(let maxSeconds):
            return metrics.elapsedSeconds <= maxSeconds
        case .finishWithPenaltyAtMost(let maxPenaltyCount):
            return metrics.penaltyCount <= maxPenaltyCount
        case .avoidRevisitingTiles:
            return !metrics.hasRevisitedTile
        case .finishWithPenaltyAtMostAndWithinMoves(let maxPenaltyCount, let maxMoves):
            return metrics.penaltyCount <= maxPenaltyCount && metrics.moveCount <= maxMoves
        }
    }
}

extension CampaignStage.ScoreTargetComparison {
    /// 条件を満たしているか判定する
    /// - Parameters:
    ///   - score: 実際のスコア
    ///   - target: 目標値
    /// - Returns: 達成していれば true
    func isSatisfied(score: Int, target: Int) -> Bool {
        switch self {
        case .lessThanOrEqual:
            return score <= target
        case .lessThan:
            return score < target
        }
    }
}

public extension CampaignStage {
    /// クリア時の成績から獲得スター数を判定
    /// - Parameter metrics: クリア時の統計値
    /// - Returns: 達成状況の評価結果
    func evaluateClear(with metrics: CampaignStageClearMetrics) -> CampaignStageEvaluation {
        let objectiveAchieved = secondaryObjective?.isSatisfied(by: metrics) ?? false
        let scoreAchieved: Bool
        if let scoreTarget {
            scoreAchieved = scoreTargetComparison.isSatisfied(score: metrics.score, target: scoreTarget)
        } else {
            scoreAchieved = false
        }

        var stars = 1
        if objectiveAchieved { stars += 1 }
        if scoreAchieved { stars += 1 }

        return CampaignStageEvaluation(
            stageID: id,
            earnedStars: stars,
            achievedSecondaryObjective: objectiveAchieved,
            achievedScoreGoal: scoreAchieved
        )
    }

    /// ゲームプレイ用の `GameMode` を生成
    /// - Returns: ステージに対応するモード
    func makeGameMode() -> GameMode {
        GameMode(
            identifier: .campaignStage,
            displayName: "\(displayCode) \(title)",
            regulation: regulation,
            leaderboardEligible: false,
            campaignMetadata: .init(stageID: id)
        )
    }
}
