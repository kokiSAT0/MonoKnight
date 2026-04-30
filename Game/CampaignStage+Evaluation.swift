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

public extension CampaignStage {
    /// 目的地をすべて取った場合のキャンペーン最大ポイント
    var maxCampaignScore: Int {
        guard case .targetCollection(let goalCount) = regulation.completionRule else { return 0 }
        return goalCount * CampaignScoring.targetCapturePoints
    }

    /// 旧コストラインを加点式の 2 スター閾値へ変換した値
    var twoStarPointThreshold: Int? {
        guard let twoStarScoreTarget else { return nil }
        return max(maxCampaignScore - twoStarScoreTarget, 0)
    }

    /// 旧コストラインを加点式の 3 スター閾値へ変換した値
    var threeStarPointThreshold: Int? {
        guard let scoreTarget else { return nil }
        return max(maxCampaignScore - scoreTarget, 0)
    }

    /// クリア時の成績から獲得スター数を判定
    /// - Parameter metrics: クリア時の統計値
    /// - Returns: 達成状況の評価結果
    func evaluateClear(with metrics: CampaignStageClearMetrics) -> CampaignStageEvaluation {
        let twoStarAchieved: Bool
        if let twoStarPointThreshold {
            twoStarAchieved = metrics.score >= twoStarPointThreshold
        } else {
            twoStarAchieved = false
        }

        let threeStarAchieved: Bool
        if let threeStarPointThreshold {
            threeStarAchieved = metrics.score >= threeStarPointThreshold
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
