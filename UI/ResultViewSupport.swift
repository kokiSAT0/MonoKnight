import Foundation
import Game
import SwiftUI

/// リザルト画面で利用する表示用の派生値をまとめたプレゼンテーション
struct ResultSummaryPresentation {
    let moveCount: Int
    let penaltyCount: Int
    let usesDungeonExit: Bool
    let isFailed: Bool
    let failureReason: String?
    let dungeonHP: Int?
    let remainingDungeonTurns: Int?
    let dungeonRunFloorText: String?
    let rogueTowerRecordText: String?
    let dungeonRunTotalMoveCount: Int?
    let dungeonRewardMoveCards: [MoveCard]
    let dungeonInventoryEntries: [DungeonInventoryEntry]
    let dungeonGrowthAward: DungeonGrowthAward?
    let hasNextDungeonFloor: Bool
    let elapsedSeconds: Int

    var totalMoves: Int {
        return moveCount + penaltyCount
    }

    var movePoints: Int {
        return moveCount * 10
    }

    var timePoints: Int {
        return elapsedSeconds
    }

    var points: Int {
        return movePoints + timePoints
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
        return penaltyCount == 0 ? "ペナルティなし" : "ペナルティ合計 \(penaltyCount)"
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
            .compactMap { $0.carryingAllUsesAsReward() }
    }

    var dungeonPickupInventoryEntries: [DungeonInventoryEntry] {
        []
    }

    var dungeonRewardInventoryText: String {
        dungeonRewardInventoryEntries
            .map { "\($0.playable.displayName)×\($0.totalUses)" }
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
        return "MonoKnight \(modeDisplayName) クリア！ポイント \(points)（移動 \(moveCount) 手 / \(penaltySummaryText) / 所要 \(formattedElapsedTime)）"
    }
}

/// リザルト画面の一時状態をまとめる
struct ResultViewState {
    var isNewBest = false
}
