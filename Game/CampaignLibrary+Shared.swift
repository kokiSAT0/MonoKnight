import Foundation

extension CampaignLibrary {
    static let campaignBoardSize = 8

    static var targetModePenalties: GameMode.PenaltySettings {
        GameMode.PenaltySettings(
            deadlockPenaltyCost: 0,
            manualRedrawPenaltyCost: 0,
            manualDiscardPenaltyCost: 1,
            revisitPenaltyCost: 0
        )
    }

    static var unifiedMidCampaignPenalties: GameMode.PenaltySettings {
        GameMode.PenaltySettings(
            deadlockPenaltyCost: 3,
            manualRedrawPenaltyCost: 2,
            manualDiscardPenaltyCost: 1,
            revisitPenaltyCost: 0
        )
    }

    static var standardPenalties: GameMode.PenaltySettings {
        unifiedMidCampaignPenalties
    }

    static func fixedSpawn(_ boardSize: Int) -> GameMode.SpawnRule {
        .fixed(BoardGeometry.defaultSpawnPoint(for: boardSize))
    }

    static var fixedSpawn5: GameMode.SpawnRule {
        fixedSpawn(5)
    }

    static func targetStage(
        chapter: Int,
        index: Int,
        title: String,
        summary: String,
        boardSize: Int = campaignBoardSize,
        goalCount: Int,
        deckPreset: GameDeckPreset,
        spawnRule: GameMode.SpawnRule? = nil,
        secondaryObjective: CampaignStage.SecondaryObjective,
        scoreTarget: Int,
        scoreTargetComparison: CampaignStage.ScoreTargetComparison = .lessThanOrEqual,
        unlockRequirement: CampaignStageUnlockRequirement,
        impassableTilePoints: Set<GridPoint> = [],
        tileEffectOverrides: [GridPoint: TileEffect] = [:],
        warpTilePairs: [String: [GridPoint]] = [:],
        fixedWarpCardTargets: [MoveCard: [GridPoint]] = [:]
    ) -> CampaignStage {
        CampaignStage(
            id: CampaignStageID(chapter: chapter, index: index),
            title: title,
            summary: summary,
            regulation: GameMode.Regulation(
                boardSize: boardSize,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: deckPreset,
                spawnRule: spawnRule ?? fixedSpawn(boardSize),
                penalties: targetModePenalties,
                impassableTilePoints: impassableTilePoints,
                tileEffectOverrides: tileEffectOverrides,
                warpTilePairs: warpTilePairs,
                fixedWarpCardTargets: fixedWarpCardTargets,
                completionRule: .targetCollection(goalCount: goalCount)
            ),
            secondaryObjective: secondaryObjective,
            scoreTarget: scoreTarget,
            scoreTargetComparison: scoreTargetComparison,
            unlockRequirement: unlockRequirement
        )
    }
}
