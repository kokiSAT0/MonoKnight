import Foundation

public extension GameMode {
    /// RootView の初期状態やプレビューで使う、実プレイ前の塔フロア相当モード。
    static var dungeonPlaceholder: GameMode {
        GameMode(
            identifier: .dungeonFloor,
            displayName: "塔ダンジョン",
            regulation: Regulation(
                boardSize: BoardGeometry.standardSize,
                handSize: 10,
                nextPreviewCount: 0,
                allowsStacking: true,
                deckPreset: .standardLight,
                spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: BoardGeometry.standardSize)),
                penalties: PenaltySettings(
                    deadlockPenaltyCost: 0,
                    manualRedrawPenaltyCost: 0,
                    manualDiscardPenaltyCost: 1,
                    revisitPenaltyCost: 0
                ),
                completionRule: .dungeonExit(exitPoint: GridPoint(x: 4, y: 4)),
                dungeonRules: DungeonRules(
                    difficulty: .tutorial,
                    failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 20),
                    allowsBasicOrthogonalMove: true,
                    cardAcquisitionMode: .inventoryOnly
                )
            ),
            leaderboardEligible: false
        )
    }
}
