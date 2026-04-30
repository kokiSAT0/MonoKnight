import Foundation

extension CampaignStage.SecondaryObjective {
    /// UI 表示向け説明文
    var description: String {
        switch self {
        case .finishWithinMoves(let maxMoves):
            return "移動 \(maxMoves) 手以内でクリア"
        case .finishWithinSeconds(let maxSeconds):
            return "\(maxSeconds) 秒以内でクリア"
        case .finishWithPenaltyAtMost(let maxPenaltyCount):
            return "ペナルティ合計 \(maxPenaltyCount) 以下でクリア"
        case .avoidRevisitingTiles:
            return "同じマスを 2 回踏まずにクリア"
        case .finishWithPenaltyAtMostAndWithinMoves(let maxPenaltyCount, let maxMoves):
            return "ペナルティ合計 \(maxPenaltyCount) 以下かつ \(maxMoves) 手以内でクリア"
        case .finishWithFocusAtMost(let maxFocusCount):
            return "フォーカス \(maxFocusCount) 回以内でクリア"
        case .finishWithFocusAtMostAndWithinMoves(let maxFocusCount, let maxMoves):
            return "フォーカス \(maxFocusCount) 回以内かつ \(maxMoves) 手以内でクリア"
        }
    }
}

public extension CampaignStage {
    /// UI で表示する際のコード表記
    var displayCode: String { id.displayCode }

    /// 二つ目のスター条件説明
    var secondaryObjectiveDescription: String? {
        secondaryObjective?.description
    }

    /// 二つ目のスター条件説明
    var twoStarScoreTargetDescription: String? {
        guard let twoStarPointThreshold else { return nil }
        return "\(twoStarPointThreshold) pt 到達"
    }

    /// 三つ目のスター条件説明
    var scoreTargetDescription: String? {
        guard let threeStarPointThreshold else { return nil }
        return "\(threeStarPointThreshold) pt 到達"
    }

    /// ステージ解放条件の説明
    var unlockDescription: String {
        switch unlockRequirement {
        case .always:
            return "最初から解放済み"
        case .totalStars(let minimum) where minimum <= 0:
            return "最初から解放済み"
        case .totalStars(let minimum):
            return "スターを合計 \(minimum) 個集める"
        case .chapterTotalStars(_, let minimum) where minimum <= 0:
            return "最初から解放済み"
        case .chapterTotalStars(let chapter, let minimum):
            return "第\(chapter)章でスターを合計 \(minimum) 個集める"
        case .stageClear(let requiredID):
            return "\(requiredID.displayCode) をクリア"
        }
    }
}
