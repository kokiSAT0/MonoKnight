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
    public let enemyDamageMitigationsRemaining: Int
    public let markerDamageMitigationsRemaining: Int
    public let enemyStates: [EnemyState]
    public let crackedFloorPoints: Set<GridPoint>
    public let collapsedFloorPoints: Set<GridPoint>
    public let consumedHealingTilePoints: Set<GridPoint>
    public let dungeonInventoryEntries: [DungeonInventoryEntry]
    public let collectedDungeonCardPickupIDs: Set<String>
    public let dungeonRelicEntries: [DungeonRelicEntry]
    public let dungeonCurseEntries: [DungeonCurseEntry]
    public let collectedDungeonRelicPickupIDs: Set<String>
    public let isDungeonExitUnlocked: Bool
    public let pendingDungeonPickupChoice: PendingDungeonPickupChoice?

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
        enemyDamageMitigationsRemaining: Int = 0,
        markerDamageMitigationsRemaining: Int = 0,
        enemyStates: [EnemyState],
        crackedFloorPoints: Set<GridPoint>,
        collapsedFloorPoints: Set<GridPoint>,
        consumedHealingTilePoints: Set<GridPoint> = [],
        dungeonInventoryEntries: [DungeonInventoryEntry],
        collectedDungeonCardPickupIDs: Set<String>,
        dungeonRelicEntries: [DungeonRelicEntry] = [],
        dungeonCurseEntries: [DungeonCurseEntry] = [],
        collectedDungeonRelicPickupIDs: Set<String> = [],
        isDungeonExitUnlocked: Bool,
        pendingDungeonPickupChoice: PendingDungeonPickupChoice? = nil
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
        self.enemyDamageMitigationsRemaining = max(enemyDamageMitigationsRemaining, 0)
        self.markerDamageMitigationsRemaining = max(markerDamageMitigationsRemaining, 0)
        self.enemyStates = enemyStates
        self.crackedFloorPoints = crackedFloorPoints
        self.collapsedFloorPoints = collapsedFloorPoints
        self.consumedHealingTilePoints = consumedHealingTilePoints
        self.dungeonInventoryEntries = dungeonInventoryEntries.filter(\.hasUsesRemaining)
        self.collectedDungeonCardPickupIDs = collectedDungeonCardPickupIDs
        self.dungeonRelicEntries = dungeonRelicEntries
        self.dungeonCurseEntries = dungeonCurseEntries
        self.collectedDungeonRelicPickupIDs = collectedDungeonRelicPickupIDs
        self.isDungeonExitUnlocked = isDungeonExitUnlocked
        self.pendingDungeonPickupChoice = pendingDungeonPickupChoice
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case dungeonID
        case floorIndex
        case runState
        case currentPoint
        case visitedPoints
        case moveCount
        case elapsedSeconds
        case dungeonHP
        case hazardDamageMitigationsRemaining
        case enemyDamageMitigationsRemaining
        case markerDamageMitigationsRemaining
        case enemyStates
        case crackedFloorPoints
        case collapsedFloorPoints
        case consumedHealingTilePoints
        case dungeonInventoryEntries
        case collectedDungeonCardPickupIDs
        case dungeonRelicEntries
        case dungeonCurseEntries
        case collectedDungeonRelicPickupIDs
        case isDungeonExitUnlocked
        case pendingDungeonPickupChoice
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            version: try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion,
            dungeonID: try container.decode(String.self, forKey: .dungeonID),
            floorIndex: try container.decode(Int.self, forKey: .floorIndex),
            runState: try container.decode(DungeonRunState.self, forKey: .runState),
            currentPoint: try container.decode(GridPoint.self, forKey: .currentPoint),
            visitedPoints: try container.decode(Set<GridPoint>.self, forKey: .visitedPoints),
            moveCount: try container.decode(Int.self, forKey: .moveCount),
            elapsedSeconds: try container.decode(Int.self, forKey: .elapsedSeconds),
            dungeonHP: try container.decode(Int.self, forKey: .dungeonHP),
            hazardDamageMitigationsRemaining: try container.decodeIfPresent(Int.self, forKey: .hazardDamageMitigationsRemaining) ?? 0,
            enemyDamageMitigationsRemaining: try container.decodeIfPresent(Int.self, forKey: .enemyDamageMitigationsRemaining) ?? 0,
            markerDamageMitigationsRemaining: try container.decodeIfPresent(Int.self, forKey: .markerDamageMitigationsRemaining) ?? 0,
            enemyStates: try container.decodeIfPresent([EnemyState].self, forKey: .enemyStates) ?? [],
            crackedFloorPoints: try container.decodeIfPresent(Set<GridPoint>.self, forKey: .crackedFloorPoints) ?? [],
            collapsedFloorPoints: try container.decodeIfPresent(Set<GridPoint>.self, forKey: .collapsedFloorPoints) ?? [],
            consumedHealingTilePoints: try container.decodeIfPresent(Set<GridPoint>.self, forKey: .consumedHealingTilePoints) ?? [],
            dungeonInventoryEntries: try container.decodeIfPresent([DungeonInventoryEntry].self, forKey: .dungeonInventoryEntries) ?? [],
            collectedDungeonCardPickupIDs: try container.decodeIfPresent(Set<String>.self, forKey: .collectedDungeonCardPickupIDs) ?? [],
            dungeonRelicEntries: try container.decodeIfPresent([DungeonRelicEntry].self, forKey: .dungeonRelicEntries) ?? [],
            dungeonCurseEntries: try container.decodeIfPresent([DungeonCurseEntry].self, forKey: .dungeonCurseEntries) ?? [],
            collectedDungeonRelicPickupIDs: try container.decodeIfPresent(Set<String>.self, forKey: .collectedDungeonRelicPickupIDs) ?? [],
            isDungeonExitUnlocked: try container.decodeIfPresent(Bool.self, forKey: .isDungeonExitUnlocked) ?? true,
            pendingDungeonPickupChoice: try container.decodeIfPresent(PendingDungeonPickupChoice.self, forKey: .pendingDungeonPickupChoice)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(dungeonID, forKey: .dungeonID)
        try container.encode(floorIndex, forKey: .floorIndex)
        try container.encode(runState, forKey: .runState)
        try container.encode(currentPoint, forKey: .currentPoint)
        try container.encode(visitedPoints, forKey: .visitedPoints)
        try container.encode(moveCount, forKey: .moveCount)
        try container.encode(elapsedSeconds, forKey: .elapsedSeconds)
        try container.encode(dungeonHP, forKey: .dungeonHP)
        try container.encode(hazardDamageMitigationsRemaining, forKey: .hazardDamageMitigationsRemaining)
        try container.encode(enemyDamageMitigationsRemaining, forKey: .enemyDamageMitigationsRemaining)
        try container.encode(markerDamageMitigationsRemaining, forKey: .markerDamageMitigationsRemaining)
        try container.encode(enemyStates, forKey: .enemyStates)
        try container.encode(crackedFloorPoints, forKey: .crackedFloorPoints)
        try container.encode(collapsedFloorPoints, forKey: .collapsedFloorPoints)
        try container.encode(consumedHealingTilePoints, forKey: .consumedHealingTilePoints)
        try container.encode(dungeonInventoryEntries, forKey: .dungeonInventoryEntries)
        try container.encode(collectedDungeonCardPickupIDs, forKey: .collectedDungeonCardPickupIDs)
        try container.encode(dungeonRelicEntries, forKey: .dungeonRelicEntries)
        try container.encode(dungeonCurseEntries, forKey: .dungeonCurseEntries)
        try container.encode(collectedDungeonRelicPickupIDs, forKey: .collectedDungeonRelicPickupIDs)
        try container.encode(isDungeonExitUnlocked, forKey: .isDungeonExitUnlocked)
        try container.encodeIfPresent(pendingDungeonPickupChoice, forKey: .pendingDungeonPickupChoice)
    }
}
