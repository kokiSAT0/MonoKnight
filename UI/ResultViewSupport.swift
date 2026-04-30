import Foundation
import SwiftUI

/// リザルト画面で利用する表示用の派生値をまとめたプレゼンテーション
struct ResultSummaryPresentation {
    let moveCount: Int
    let penaltyCount: Int
    let focusCount: Int
    let usesTargetCollection: Bool
    let elapsedSeconds: Int
    let bestPoints: Int
    let isNewBest: Bool
    let previousBest: Int?

    var totalMoves: Int {
        if usesTargetCollection {
            return moveCount
        }
        return moveCount + penaltyCount
    }

    var movePoints: Int {
        return moveCount * 10
    }

    var focusPoints: Int {
        return usesTargetCollection ? focusCount * 15 : 0
    }

    var timePoints: Int {
        return elapsedSeconds
    }

    var points: Int {
        return movePoints + timePoints + focusPoints
    }

    var formattedElapsedTime: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        if minutes > 0 {
            return "\(minutes)分\(seconds)秒"
        } else {
            return "\(seconds)秒"
        }
    }

    var penaltySummaryText: String {
        if usesTargetCollection {
            return focusCount == 0 ? "フォーカスなし" : "フォーカス \(focusCount) 回"
        }
        return penaltyCount == 0 ? "ペナルティなし" : "ペナルティ合計 \(penaltyCount)"
    }

    var bestPointsText: String {
        return bestPoints == .max ? "-" : String(bestPoints)
    }

    var bestComparisonDescription: String? {
        guard isNewBest else { return nil }

        if let previousBest {
            let diff = previousBest - points
            return "これまでのベスト \(previousBest) pt → 今回 \(points) pt（\(diff) pt 更新）"
        } else {
            return "初めてのベストポイントが登録されました"
        }
    }

    func shareMessage(modeDisplayName: String) -> String {
        if usesTargetCollection {
            return "MonoKnight \(modeDisplayName) クリア！ポイント \(points)（移動 \(moveCount) 手 / \(penaltySummaryText) / 所要 \(formattedElapsedTime)）"
        }
        return "MonoKnight \(modeDisplayName) クリア！ポイント \(points)（移動 \(moveCount) 手 / \(penaltySummaryText) / 所要 \(formattedElapsedTime)）"
    }
}

/// リザルト画面の一時状態をまとめる
struct ResultViewState {
    var isNewBest = false
    var previousBest: Int?

    @MainActor
    mutating func updateBest(points: Int, settingsStore: GameSettingsStore) -> Bool {
        previousBest = settingsStore.updateBestPointsIfNeeded(points)
        let isImproved = previousBest == nil || points < (previousBest ?? .max)
        isNewBest = isImproved
        return isImproved
    }
}

/// キャンペーンリワード表示用の派生値
struct CampaignRewardPresentation {
    let record: CampaignStageClearRecord

    var starGain: Int {
        max(0, record.progress.earnedStars - record.previousProgress.earnedStars)
    }

    var conditions: [(title: String, description: String, isAchieved: Bool)] {
        var items: [(title: String, description: String, isAchieved: Bool)] = [
            (
                title: "★1",
                description: "ステージをクリア",
                isAchieved: true
            )
        ]

        if let twoStarTarget = record.stage.twoStarScoreTargetDescription {
            items.append((
                title: "★2",
                description: twoStarTarget,
                isAchieved: record.progress.achievedTwoStarScoreGoal
            ))
        }

        if let scoreTarget = record.stage.scoreTargetDescription {
            items.append((
                title: "★3",
                description: scoreTarget,
                isAchieved: record.progress.achievedThreeStarScoreGoal
            ))
        }

        return items
    }
}
