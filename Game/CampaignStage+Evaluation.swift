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
        case .finishWithFocusAtMost(let maxFocusCount):
            return metrics.focusCount <= maxFocusCount
        case .finishWithFocusAtMostAndWithinMoves(let maxFocusCount, let maxMoves):
            return metrics.focusCount <= maxFocusCount && metrics.moveCount <= maxMoves
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
        let twoStarAchieved: Bool
        if let twoStarScoreTarget {
            twoStarAchieved = scoreTargetComparison.isSatisfied(score: metrics.score, target: twoStarScoreTarget)
        } else {
            twoStarAchieved = false
        }

        let threeStarAchieved: Bool
        if let scoreTarget {
            threeStarAchieved = scoreTargetComparison.isSatisfied(score: metrics.score, target: scoreTarget)
        } else {
            threeStarAchieved = false
        }

        var stars = 1
        if twoStarAchieved { stars += 1 }
        if threeStarAchieved { stars += 1 }

        return CampaignStageEvaluation(
            stageID: id,
            earnedStars: stars,
            achievedSecondaryObjective: twoStarAchieved,
            achievedScoreGoal: threeStarAchieved,
            achievedTwoStarScoreGoal: twoStarAchieved,
            achievedThreeStarScoreGoal: threeStarAchieved
        )
    }
}
