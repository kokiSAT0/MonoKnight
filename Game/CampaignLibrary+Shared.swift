import Foundation

extension CampaignLibrary {
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
}
