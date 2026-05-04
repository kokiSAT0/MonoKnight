import Foundation
import Game
import SwiftUI

/// リザルト画面で利用する表示用の派生値をまとめたプレゼンテーション
struct ResultSummaryPresentation {
    let moveCount: Int
    let penaltyCount: Int
    let focusCount: Int
    let usesTargetCollection: Bool
    let usesDungeonExit: Bool
    let isFailed: Bool
    let failureReason: String?
    let dungeonHP: Int?
    let remainingDungeonTurns: Int?
    let dungeonRunFloorText: String?
    let dungeonRunTotalMoveCount: Int?
    let dungeonRewardMoveCards: [MoveCard]
    let dungeonInventoryEntries: [DungeonInventoryEntry]
    let hasNextDungeonFloor: Bool
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

    var resultTitle: String {
        if isFailed {
            return usesDungeonExit ? "塔に失敗" : "失敗"
        }
        if usesDungeonExit {
            return hasNextDungeonFloor ? "フロアクリア" : "\(dungeonTitleText)クリア"
        }
        return "総合ポイント: \(points)"
    }

    private var dungeonTitleText: String {
        guard let dungeonRunFloorText,
              let title = dungeonRunFloorText.split(separator: " ").first,
              !title.isEmpty
        else {
            return "塔"
        }
        return String(title)
    }

    var resultSubtitle: String? {
        if isFailed {
            return failureReason ?? "攻略に失敗しました"
        }
        if usesDungeonExit {
            if let dungeonRunFloorText {
                return "\(dungeonRunFloorText) を突破しました"
            }
            return "出口へ到達しました"
        }
        return nil
    }

    var dungeonRewardInventoryEntries: [DungeonInventoryEntry] {
        dungeonInventoryEntries
            .filter { $0.rewardUses > 0 }
            .map { DungeonInventoryEntry(card: $0.card, rewardUses: $0.rewardUses) }
    }

    var dungeonPickupInventoryEntries: [DungeonInventoryEntry] {
        dungeonInventoryEntries
            .filter { $0.pickupUses > 0 }
            .map { DungeonInventoryEntry(card: $0.card, pickupUses: $0.pickupUses) }
    }

    var dungeonRewardInventoryText: String {
        dungeonRewardInventoryEntries
            .map { "\($0.card.displayName)×\($0.rewardUses)" }
            .joined(separator: "、")
    }

    var dungeonPickupInventoryText: String {
        dungeonPickupInventoryEntries
            .map { "\($0.card.displayName)×\($0.pickupUses)" }
            .joined(separator: "、")
    }

    func shareMessage(modeDisplayName: String) -> String {
        if isFailed {
            return "MonoKnight \(modeDisplayName) 挑戦失敗（移動 \(moveCount) 手 / \(penaltySummaryText) / 所要 \(formattedElapsedTime)）"
        }
        if usesDungeonExit {
            return "MonoKnight \(modeDisplayName) フロアクリア！（移動 \(moveCount) 手 / 残HP \(dungeonHP ?? 0) / 所要 \(formattedElapsedTime)）"
        }
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
