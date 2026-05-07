import Foundation

/// 塔攻略をアプリ再起動後に再開するための保存用スナップショット。
/// - Note: `DungeonRunState` はフロア間状態、こちらは現在フロア内の生きた状態を保持する。
public struct DungeonRunResumeSnapshot: Codable, Equatable {
    public static let currentVersion = 1

    public let version: Int
    public let dungeonID: String
    public let floorIndex: Int
    public let runState: DungeonRunState
    public let currentPoint: GridPoint
    public let visitedPoints: Set<GridPoint>
    public let moveCount: Int
    public let elapsedSeconds: Int
    public let dungeonHP: Int
    public let hazardDamageMitigationsRemaining: Int
    public let enemyStates: [EnemyState]
    public let crackedFloorPoints: Set<GridPoint>
    public let collapsedFloorPoints: Set<GridPoint>
    public let dungeonInventoryEntries: [DungeonInventoryEntry]
    public let collectedDungeonCardPickupIDs: Set<String>
    public let isDungeonExitUnlocked: Bool

    public init(
        version: Int = Self.currentVersion,
        dungeonID: String,
        floorIndex: Int,
        runState: DungeonRunState,
        currentPoint: GridPoint,
        visitedPoints: Set<GridPoint>,
        moveCount: Int,
        elapsedSeconds: Int,
        dungeonHP: Int,
        hazardDamageMitigationsRemaining: Int,
        enemyStates: [EnemyState],
        crackedFloorPoints: Set<GridPoint>,
        collapsedFloorPoints: Set<GridPoint>,
        dungeonInventoryEntries: [DungeonInventoryEntry],
        collectedDungeonCardPickupIDs: Set<String>,
        isDungeonExitUnlocked: Bool
    ) {
        self.version = version
        self.dungeonID = dungeonID
        self.floorIndex = max(floorIndex, 0)
        self.runState = runState
        self.currentPoint = currentPoint
        self.visitedPoints = visitedPoints
        self.moveCount = max(moveCount, 0)
        self.elapsedSeconds = max(elapsedSeconds, 0)
        self.dungeonHP = max(dungeonHP, 0)
        self.hazardDamageMitigationsRemaining = max(hazardDamageMitigationsRemaining, 0)
        self.enemyStates = enemyStates
        self.crackedFloorPoints = crackedFloorPoints
        self.collapsedFloorPoints = collapsedFloorPoints
        self.dungeonInventoryEntries = dungeonInventoryEntries.filter(\.hasUsesRemaining)
        self.collectedDungeonCardPickupIDs = collectedDungeonCardPickupIDs
        self.isDungeonExitUnlocked = isDungeonExitUnlocked
    }
}
