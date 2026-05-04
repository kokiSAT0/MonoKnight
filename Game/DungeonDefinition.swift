import Foundation

/// 塔ダンジョンの難度と成長持ち込み方針
public enum DungeonDifficulty: String, Codable, Equatable {
    /// 操作と基本ルールを学ぶチュートリアル塔
    case tutorial
    /// 永続強化を持ち込める低難度ダンジョン
    case growth
    /// 一時報酬だけで進む中難度ダンジョン
    case tactical
    /// 毎回初期状態から始める高難度ローグライク
    case roguelike
}

/// 塔ダンジョンでカードを獲得・補充する方式
public enum DungeonCardAcquisitionMode: String, Codable, Equatable {
    /// 既存の山札/NEXT/手札補充を使う
    case deck
    /// フロア拾得と報酬だけでカードを所持する
    case inventoryOnly
}

/// 塔ラン中に所持しているカードと残り使用回数
public struct DungeonInventoryEntry: Codable, Equatable, Identifiable {
    public let card: MoveCard
    /// フロアをまたいで持ち越せる報酬由来の残り使用回数
    public var rewardUses: Int
    /// 現在フロア限りの拾得由来の残り使用回数
    public var pickupUses: Int

    public init(card: MoveCard, rewardUses: Int = 0, pickupUses: Int = 0) {
        self.card = card
        self.rewardUses = max(rewardUses, 0)
        self.pickupUses = max(pickupUses, 0)
    }

    public var id: MoveCard { card }
    public var totalUses: Int { rewardUses + pickupUses }
    public var hasUsesRemaining: Bool { totalUses > 0 }

    public func carryingRewardUsesOnly() -> DungeonInventoryEntry? {
        guard rewardUses > 0 else { return nil }
        return DungeonInventoryEntry(card: card, rewardUses: rewardUses, pickupUses: 0)
    }
}

/// フロアクリア後に選ぶ塔報酬
public enum DungeonRewardSelection: Equatable {
    /// 新しい報酬カードを3回分追加する
    case add(MoveCard)
    /// フロア内で拾って未使用分が残っているカードを報酬カードとして持ち越す
    case carryOverPickup(MoveCard)
    /// 既存の持ち越し報酬カードの使用回数を1増やす
    case upgrade(MoveCard)
    /// 既存の持ち越し報酬カードをランから外す
    case remove(MoveCard)
}

/// フロア内に配置する拾得カード
public struct DungeonCardPickupDefinition: Codable, Equatable, Identifiable {
    public let id: String
    public let point: GridPoint
    public let card: MoveCard
    public let uses: Int

    public init(id: String, point: GridPoint, card: MoveCard, uses: Int = 1) {
        self.id = id
        self.point = point
        self.card = card
        self.uses = max(uses, 1)
    }
}

/// 1 回の塔挑戦でフロア間に引き継ぐ最小状態
public struct DungeonRunState: Codable, Equatable {
    public let dungeonID: String
    /// 0 始まりの現在フロア番号
    public let currentFloorIndex: Int
    /// 次フロアへ持ち越す HP
    public let carriedHP: Int
    /// これまでに完了したフロアの移動手数合計
    public let totalMoveCount: Int
    /// クリア済みフロア数
    public let clearedFloorCount: Int
    /// フロアをまたいで持ち越す報酬カードと残り使用回数
    public let rewardInventoryEntries: [DungeonInventoryEntry]
    /// 成長塔の拾得/報酬カード変化に使うラン単位の seed
    public let cardVariationSeed: UInt64?
    /// フロアごとのひび割れ床状態
    public let crackedFloorPointsByFloor: [Int: Set<GridPoint>]
    /// フロアごとの崩落床状態
    public let collapsedFloorPointsByFloor: [Int: Set<GridPoint>]
    /// 落下で次フロアへ入る場合の着地点
    public let pendingFallLandingPoint: GridPoint?
    /// 成長塔の区間内で罠/床崩落ダメージを無効化できる残り回数
    public let hazardDamageMitigationsRemaining: Int

    public init(
        dungeonID: String,
        currentFloorIndex: Int = 0,
        carriedHP: Int,
        totalMoveCount: Int = 0,
        clearedFloorCount: Int = 0,
        rewardInventoryEntries: [DungeonInventoryEntry] = [],
        cardVariationSeed: UInt64? = nil,
        crackedFloorPointsByFloor: [Int: Set<GridPoint>] = [:],
        collapsedFloorPointsByFloor: [Int: Set<GridPoint>] = [:],
        pendingFallLandingPoint: GridPoint? = nil,
        hazardDamageMitigationsRemaining: Int = 0
    ) {
        self.dungeonID = dungeonID
        self.currentFloorIndex = max(currentFloorIndex, 0)
        self.carriedHP = max(carriedHP, 1)
        self.totalMoveCount = max(totalMoveCount, 0)
        self.clearedFloorCount = max(clearedFloorCount, 0)
        self.rewardInventoryEntries = DungeonRunState.mergedRewardEntries(rewardInventoryEntries)
        self.cardVariationSeed = cardVariationSeed
        self.crackedFloorPointsByFloor = crackedFloorPointsByFloor.filter { !$0.value.isEmpty }
        self.collapsedFloorPointsByFloor = collapsedFloorPointsByFloor.filter { !$0.value.isEmpty }
        self.pendingFallLandingPoint = pendingFallLandingPoint
        self.hazardDamageMitigationsRemaining = max(hazardDamageMitigationsRemaining, 0)
    }

    public var floorNumber: Int {
        currentFloorIndex + 1
    }

    public func advancedToNextFloor(
        carryoverHP: Int,
        currentFloorMoveCount: Int,
        rewardMoveCard: MoveCard? = nil,
        rewardSelection: DungeonRewardSelection? = nil,
        currentInventoryEntries: [DungeonInventoryEntry]? = nil,
        rewardAddUses: Int = 3,
        hazardDamageMitigationsRemaining: Int? = nil
    ) -> DungeonRunState {
        let sourceEntries = currentInventoryEntries ?? rewardInventoryEntries
        let carriedEntries = sourceEntries.compactMap { $0.carryingRewardUsesOnly() }
        let selection = rewardSelection ?? rewardMoveCard.map { DungeonRewardSelection.add($0) }
        let updatedRewardInventoryEntries = DungeonRunState.applying(
            selection,
            to: carriedEntries,
            sourceEntries: sourceEntries,
            rewardAddUses: rewardAddUses
        )
        return DungeonRunState(
            dungeonID: dungeonID,
            currentFloorIndex: currentFloorIndex + 1,
            carriedHP: carryoverHP,
            totalMoveCount: totalMoveCount + max(currentFloorMoveCount, 0),
            clearedFloorCount: clearedFloorCount + 1,
            rewardInventoryEntries: updatedRewardInventoryEntries.compactMap { $0.carryingRewardUsesOnly() },
            cardVariationSeed: cardVariationSeed,
            crackedFloorPointsByFloor: crackedFloorPointsByFloor,
            collapsedFloorPointsByFloor: collapsedFloorPointsByFloor,
            hazardDamageMitigationsRemaining: hazardDamageMitigationsRemaining ?? self.hazardDamageMitigationsRemaining
        )
    }

    public func fallenToNextFloor(
        carryoverHP: Int,
        currentFloorMoveCount: Int,
        currentInventoryEntries: [DungeonInventoryEntry],
        landingPoint: GridPoint,
        currentFloorCrackedPoints: Set<GridPoint>,
        currentFloorCollapsedPoints: Set<GridPoint>,
        hazardDamageMitigationsRemaining: Int? = nil
    ) -> DungeonRunState {
        let recordedState = recordingFloorState(
            floorIndex: currentFloorIndex,
            cracked: currentFloorCrackedPoints,
            collapsed: currentFloorCollapsedPoints
        )
        return DungeonRunState(
            dungeonID: dungeonID,
            currentFloorIndex: currentFloorIndex + 1,
            carriedHP: carryoverHP,
            totalMoveCount: totalMoveCount + max(currentFloorMoveCount, 0),
            clearedFloorCount: clearedFloorCount,
            rewardInventoryEntries: currentInventoryEntries.compactMap { $0.carryingRewardUsesOnly() },
            cardVariationSeed: cardVariationSeed,
            crackedFloorPointsByFloor: recordedState.crackedFloorPointsByFloor,
            collapsedFloorPointsByFloor: recordedState.collapsedFloorPointsByFloor,
            pendingFallLandingPoint: landingPoint,
            hazardDamageMitigationsRemaining: hazardDamageMitigationsRemaining ?? self.hazardDamageMitigationsRemaining
        )
    }

    public func totalMoveCountIncludingCurrentFloor(_ currentFloorMoveCount: Int) -> Int {
        totalMoveCount + max(currentFloorMoveCount, 0)
    }

    public func crackedFloorPoints(for floorIndex: Int) -> Set<GridPoint> {
        crackedFloorPointsByFloor[floorIndex] ?? []
    }

    public func collapsedFloorPoints(for floorIndex: Int) -> Set<GridPoint> {
        collapsedFloorPointsByFloor[floorIndex] ?? []
    }

    public func recordingFloorState(
        floorIndex: Int,
        cracked: Set<GridPoint>,
        collapsed: Set<GridPoint>
    ) -> DungeonRunState {
        var crackedByFloor = crackedFloorPointsByFloor
        var collapsedByFloor = collapsedFloorPointsByFloor
        if cracked.isEmpty {
            crackedByFloor.removeValue(forKey: floorIndex)
        } else {
            crackedByFloor[floorIndex] = cracked
        }
        if collapsed.isEmpty {
            collapsedByFloor.removeValue(forKey: floorIndex)
        } else {
            collapsedByFloor[floorIndex] = collapsed
        }
        return DungeonRunState(
            dungeonID: dungeonID,
            currentFloorIndex: currentFloorIndex,
            carriedHP: carriedHP,
            totalMoveCount: totalMoveCount,
            clearedFloorCount: clearedFloorCount,
            rewardInventoryEntries: rewardInventoryEntries,
            cardVariationSeed: cardVariationSeed,
            crackedFloorPointsByFloor: crackedByFloor,
            collapsedFloorPointsByFloor: collapsedByFloor,
            pendingFallLandingPoint: pendingFallLandingPoint,
            hazardDamageMitigationsRemaining: hazardDamageMitigationsRemaining
        )
    }

    private static func mergedRewardEntries(_ entries: [DungeonInventoryEntry]) -> [DungeonInventoryEntry] {
        var result: [DungeonInventoryEntry] = []
        for entry in entries where entry.rewardUses > 0 {
            if let index = result.firstIndex(where: { $0.card == entry.card }) {
                result[index].rewardUses += entry.rewardUses
            } else {
                result.append(
                    DungeonInventoryEntry(card: entry.card, rewardUses: entry.rewardUses, pickupUses: 0)
                )
            }
        }
        return result
    }

    private static func applying(
        _ selection: DungeonRewardSelection?,
        to entries: [DungeonInventoryEntry],
        sourceEntries: [DungeonInventoryEntry],
        rewardAddUses: Int = 3
    ) -> [DungeonInventoryEntry] {
        var result = entries
        switch selection {
        case .add(let card):
            result.append(DungeonInventoryEntry(card: card, rewardUses: max(rewardAddUses, 1), pickupUses: 0))
        case .carryOverPickup(let card):
            guard sourceEntries.contains(where: { $0.card == card && $0.pickupUses > 0 }) else { break }
            result.append(DungeonInventoryEntry(card: card, rewardUses: max(rewardAddUses, 1), pickupUses: 0))
        case .upgrade(let card):
            guard let index = result.firstIndex(where: { $0.card == card && $0.rewardUses > 0 }) else { break }
            result[index].rewardUses += 1
        case .remove(let card):
            result.removeAll { $0.card == card }
        case .none:
            break
        }
        return result
    }
}

/// ダンジョン失敗条件
public struct DungeonFailureRule: Codable, Equatable {
    /// 初期 HP。0 以下は 1 として扱う
    public var initialHP: Int
    /// フロア内の最大移動手数。nil の場合は手数失敗なし
    public var turnLimit: Int?

    public init(initialHP: Int, turnLimit: Int? = nil) {
        self.initialHP = max(initialHP, 1)
        self.turnLimit = turnLimit.map { max($0, 1) }
    }
}

/// ダンジョン出口を開けるために踏む必要がある鍵マス
public struct DungeonExitLock: Codable, Equatable {
    public let unlockPoint: GridPoint

    public init(unlockPoint: GridPoint) {
        self.unlockPoint = unlockPoint
    }
}

/// 敵の行動パターン
public enum EnemyBehavior: Codable, Equatable {
    /// その場から動かず、隣接マスを警戒する
    case guardPost
    /// 指定経路を順に巡回する
    case patrol(path: [GridPoint])
    /// 指定方向の直線を見張る
    case watcher(direction: MoveVector, range: Int)
    /// 指定方向を順に向き直す見張り
    case rotatingWatcher(directions: [MoveVector], range: Int)
    /// プレイヤーへ1マスずつ近づく
    case chaser

    private enum CodingKeys: String, CodingKey {
        case type
        case path
        case direction
        case directions
        case range
    }

    private enum Kind: String, Codable {
        case guardPost
        case patrol
        case watcher
        case rotatingWatcher
        case chaser
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawKind = try container.decodeIfPresent(String.self, forKey: .type)
        let kind = rawKind.flatMap(Kind.init(rawValue:)) ?? .guardPost
        switch kind {
        case .guardPost:
            self = .guardPost
        case .patrol:
            self = .patrol(path: try container.decodeIfPresent([GridPoint].self, forKey: .path) ?? [])
        case .watcher:
            self = .watcher(
                direction: try container.decodeIfPresent(MoveVector.self, forKey: .direction) ?? MoveVector(dx: 1, dy: 0),
                range: try container.decodeIfPresent(Int.self, forKey: .range) ?? 1
            )
        case .rotatingWatcher:
            self = .rotatingWatcher(
                directions: try container.decodeIfPresent([MoveVector].self, forKey: .directions) ?? [],
                range: try container.decodeIfPresent(Int.self, forKey: .range) ?? 1
            )
        case .chaser:
            self = .chaser
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .guardPost:
            try container.encode(Kind.guardPost, forKey: .type)
        case .patrol(let path):
            try container.encode(Kind.patrol, forKey: .type)
            try container.encode(path, forKey: .path)
        case .watcher(let direction, let range):
            try container.encode(Kind.watcher, forKey: .type)
            try container.encode(direction, forKey: .direction)
            try container.encode(range, forKey: .range)
        case .rotatingWatcher(let directions, let range):
            try container.encode(Kind.rotatingWatcher, forKey: .type)
            try container.encode(directions, forKey: .directions)
            try container.encode(range, forKey: .range)
        case .chaser:
            try container.encode(Kind.chaser, forKey: .type)
        }
    }
}

/// フロア開始時に配置する敵
public struct EnemyDefinition: Codable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let position: GridPoint
    public let behavior: EnemyBehavior
    public let damage: Int

    public init(
        id: String,
        name: String,
        position: GridPoint,
        behavior: EnemyBehavior,
        damage: Int = 1
    ) {
        self.id = id
        self.name = name
        self.position = position
        self.behavior = behavior
        self.damage = max(damage, 1)
    }
}

/// 進行中の敵状態
public struct EnemyState: Codable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public var position: GridPoint
    public let behavior: EnemyBehavior
    public let damage: Int
    public var patrolIndex: Int
    public var rotationIndex: Int

    public init(definition: EnemyDefinition) {
        id = definition.id
        name = definition.name
        position = definition.position
        behavior = definition.behavior
        damage = definition.damage
        patrolIndex = 0
        rotationIndex = 0
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case position
        case behavior
        case damage
        case patrolIndex
        case rotationIndex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        position = try container.decode(GridPoint.self, forKey: .position)
        behavior = try container.decode(EnemyBehavior.self, forKey: .behavior)
        damage = max(try container.decodeIfPresent(Int.self, forKey: .damage) ?? 1, 1)
        patrolIndex = max(try container.decodeIfPresent(Int.self, forKey: .patrolIndex) ?? 0, 0)
        rotationIndex = max(try container.decodeIfPresent(Int.self, forKey: .rotationIndex) ?? 0, 0)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(position, forKey: .position)
        try container.encode(behavior, forKey: .behavior)
        try container.encode(damage, forKey: .damage)
        try container.encode(patrolIndex, forKey: .patrolIndex)
        try container.encode(rotationIndex, forKey: .rotationIndex)
    }
}

/// 床や罠など、敵以外のフロアギミック
public enum HazardDefinition: Codable, Equatable {
    /// 1 回踏むとひび割れ、2 回目で崩落して通行不可になる床
    case brittleFloor(points: Set<GridPoint>)
    /// 見えている罠床。踏むたびに指定ダメージを受ける
    case damageTrap(points: Set<GridPoint>, damage: Int)

    private enum CodingKeys: String, CodingKey {
        case type
        case points
        case damage
    }

    private enum Kind: String, Codable {
        case brittleFloor
        case damageTrap
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        switch kind {
        case .brittleFloor:
            self = .brittleFloor(points: try container.decode(Set<GridPoint>.self, forKey: .points))
        case .damageTrap:
            self = .damageTrap(
                points: try container.decode(Set<GridPoint>.self, forKey: .points),
                damage: try container.decodeIfPresent(Int.self, forKey: .damage) ?? 1
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .brittleFloor(let points):
            try container.encode(Kind.brittleFloor, forKey: .type)
            try container.encode(points, forKey: .points)
        case .damageTrap(let points, let damage):
            try container.encode(Kind.damageTrap, forKey: .type)
            try container.encode(points, forKey: .points)
            try container.encode(max(damage, 1), forKey: .damage)
        }
    }
}

/// 1 フロア分の塔ダンジョン定義
public struct DungeonFloorDefinition: Codable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let boardSize: Int
    public let spawnPoint: GridPoint
    public let exitPoint: GridPoint
    public let deckPreset: GameDeckPreset
    public let failureRule: DungeonFailureRule
    public let enemies: [EnemyDefinition]
    public let hazards: [HazardDefinition]
    public let impassableTilePoints: Set<GridPoint>
    public let tileEffectOverrides: [GridPoint: TileEffect]
    public let warpTilePairs: [String: [GridPoint]]
    public let fixedWarpCardTargets: [MoveCard: [GridPoint]]
    public let exitLock: DungeonExitLock?
    public let cardPickups: [DungeonCardPickupDefinition]
    public let rewardMoveCardsAfterClear: [MoveCard]

    public init(
        id: String,
        title: String,
        boardSize: Int,
        spawnPoint: GridPoint,
        exitPoint: GridPoint,
        deckPreset: GameDeckPreset,
        failureRule: DungeonFailureRule,
        enemies: [EnemyDefinition] = [],
        hazards: [HazardDefinition] = [],
        impassableTilePoints: Set<GridPoint> = [],
        tileEffectOverrides: [GridPoint: TileEffect] = [:],
        warpTilePairs: [String: [GridPoint]] = [:],
        fixedWarpCardTargets: [MoveCard: [GridPoint]] = [:],
        exitLock: DungeonExitLock? = nil,
        cardPickups: [DungeonCardPickupDefinition] = [],
        rewardMoveCardsAfterClear: [MoveCard] = []
    ) {
        self.id = id
        self.title = title
        self.boardSize = boardSize
        self.spawnPoint = spawnPoint
        self.exitPoint = exitPoint
        self.deckPreset = deckPreset
        self.failureRule = failureRule
        self.enemies = enemies
        self.hazards = hazards
        self.impassableTilePoints = impassableTilePoints
        self.tileEffectOverrides = tileEffectOverrides
        self.warpTilePairs = warpTilePairs
        self.fixedWarpCardTargets = fixedWarpCardTargets
        self.exitLock = exitLock
        self.cardPickups = cardPickups
        var uniqueRewardMoveCards: [MoveCard] = []
        for card in rewardMoveCardsAfterClear where !uniqueRewardMoveCards.contains(card) {
            uniqueRewardMoveCards.append(card)
        }
        self.rewardMoveCardsAfterClear = uniqueRewardMoveCards
    }

    public func makeGameMode(
        dungeonID: String = "tutorial-tower",
        difficulty: DungeonDifficulty = .growth,
        carriedHP: Int? = nil,
        runState: DungeonRunState? = nil
    ) -> GameMode {
        let resolvedFailureRule = DungeonFailureRule(
            initialHP: carriedHP ?? runState?.carriedHP ?? failureRule.initialHP,
            turnLimit: failureRule.turnLimit
        )
        let resolvedSpawnPoint = runState?.pendingFallLandingPoint ?? spawnPoint
        return GameMode(
            identifier: .campaignStage,
            displayName: title,
            regulation: GameMode.Regulation(
                boardSize: boardSize,
                handSize: 10,
                nextPreviewCount: 0,
                allowsStacking: true,
                deckPreset: deckPreset,
                bonusMoveCards: [],
                spawnRule: .fixed(resolvedSpawnPoint),
                penalties: CampaignLibrary.targetModePenalties,
                impassableTilePoints: impassableTilePoints,
                tileEffectOverrides: tileEffectOverrides,
                warpTilePairs: warpTilePairs,
                fixedWarpCardTargets: fixedWarpCardTargets,
                completionRule: .dungeonExit(exitPoint: exitPoint),
                dungeonRules: DungeonRules(
                    difficulty: difficulty,
                    failureRule: resolvedFailureRule,
                    enemies: enemies,
                    hazards: hazards,
                    exitLock: exitLock,
                    allowsBasicOrthogonalMove: true,
                    cardAcquisitionMode: .inventoryOnly,
                    cardPickups: cardPickups
                )
            ),
            leaderboardEligible: false,
            dungeonMetadata: GameMode.DungeonMetadata(
                dungeonID: dungeonID,
                floorID: id,
                runState: runState
            )
        )
    }

    public func withRewardMoveCardsAfterClear(_ rewardMoveCardsAfterClear: [MoveCard]) -> DungeonFloorDefinition {
        DungeonFloorDefinition(
            id: id,
            title: title,
            boardSize: boardSize,
            spawnPoint: spawnPoint,
            exitPoint: exitPoint,
            deckPreset: deckPreset,
            failureRule: failureRule,
            enemies: enemies,
            hazards: hazards,
            impassableTilePoints: impassableTilePoints,
            tileEffectOverrides: tileEffectOverrides,
            warpTilePairs: warpTilePairs,
            fixedWarpCardTargets: fixedWarpCardTargets,
            exitLock: exitLock,
            cardPickups: cardPickups,
            rewardMoveCardsAfterClear: rewardMoveCardsAfterClear
        )
    }

    public func withAdditionalCardPickups(_ additionalCardPickups: [DungeonCardPickupDefinition]) -> DungeonFloorDefinition {
        DungeonFloorDefinition(
            id: id,
            title: title,
            boardSize: boardSize,
            spawnPoint: spawnPoint,
            exitPoint: exitPoint,
            deckPreset: deckPreset,
            failureRule: failureRule,
            enemies: enemies,
            hazards: hazards,
            impassableTilePoints: impassableTilePoints,
            tileEffectOverrides: tileEffectOverrides,
            warpTilePairs: warpTilePairs,
            fixedWarpCardTargets: fixedWarpCardTargets,
            exitLock: exitLock,
            cardPickups: cardPickups + additionalCardPickups,
            rewardMoveCardsAfterClear: rewardMoveCardsAfterClear
        )
    }

    public func withEnemies(_ enemies: [EnemyDefinition]) -> DungeonFloorDefinition {
        DungeonFloorDefinition(
            id: id,
            title: title,
            boardSize: boardSize,
            spawnPoint: spawnPoint,
            exitPoint: exitPoint,
            deckPreset: deckPreset,
            failureRule: failureRule,
            enemies: enemies,
            hazards: hazards,
            impassableTilePoints: impassableTilePoints,
            tileEffectOverrides: tileEffectOverrides,
            warpTilePairs: warpTilePairs,
            fixedWarpCardTargets: fixedWarpCardTargets,
            exitLock: exitLock,
            cardPickups: cardPickups,
            rewardMoveCardsAfterClear: rewardMoveCardsAfterClear
        )
    }

    public func withImpassableTilePoints(_ impassableTilePoints: Set<GridPoint>) -> DungeonFloorDefinition {
        DungeonFloorDefinition(
            id: id,
            title: title,
            boardSize: boardSize,
            spawnPoint: spawnPoint,
            exitPoint: exitPoint,
            deckPreset: deckPreset,
            failureRule: failureRule,
            enemies: enemies,
            hazards: hazards,
            impassableTilePoints: impassableTilePoints,
            tileEffectOverrides: tileEffectOverrides,
            warpTilePairs: warpTilePairs,
            fixedWarpCardTargets: fixedWarpCardTargets,
            exitLock: exitLock,
            cardPickups: cardPickups,
            rewardMoveCardsAfterClear: rewardMoveCardsAfterClear
        )
    }

    public func withAdditionalImpassableTilePoints(_ additionalPoints: Set<GridPoint>) -> DungeonFloorDefinition {
        withImpassableTilePoints(impassableTilePoints.union(additionalPoints))
    }

    public func withEndpoints(
        spawnPoint: GridPoint? = nil,
        exitPoint: GridPoint? = nil
    ) -> DungeonFloorDefinition {
        DungeonFloorDefinition(
            id: id,
            title: title,
            boardSize: boardSize,
            spawnPoint: spawnPoint ?? self.spawnPoint,
            exitPoint: exitPoint ?? self.exitPoint,
            deckPreset: deckPreset,
            failureRule: failureRule,
            enemies: enemies,
            hazards: hazards,
            impassableTilePoints: impassableTilePoints,
            tileEffectOverrides: tileEffectOverrides,
            warpTilePairs: warpTilePairs,
            fixedWarpCardTargets: fixedWarpCardTargets,
            exitLock: exitLock,
            cardPickups: cardPickups,
            rewardMoveCardsAfterClear: rewardMoveCardsAfterClear
        )
    }
}

/// ダンジョン単位の定義
public struct DungeonDefinition: Codable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let summary: String
    public let difficulty: DungeonDifficulty
    public let floors: [DungeonFloorDefinition]

    public init(
        id: String,
        title: String,
        summary: String,
        difficulty: DungeonDifficulty,
        floors: [DungeonFloorDefinition]
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.difficulty = difficulty
        self.floors = floors
    }

    public func canAdvanceWithinRun(afterFloorIndex floorIndex: Int) -> Bool {
        guard floors.indices.contains(floorIndex + 1) else { return false }
        if difficulty == .growth, (floorIndex + 1).isMultiple(of: 10) {
            return false
        }
        return true
    }

    public func resolvedFloor(at floorIndex: Int, runState: DungeonRunState?) -> DungeonFloorDefinition? {
        guard floors.indices.contains(floorIndex) else { return nil }
        let floor = floors[floorIndex]
        guard id == "growth-tower",
              difficulty == .growth,
              let seed = runState?.cardVariationSeed
        else { return floor }
        return DungeonCardVariationResolver.resolve(
            floor: floor,
            floorIndex: floorIndex,
            seed: seed
        )
    }
}

private enum DungeonCardVariationResolver {
    static func resolve(
        floor: DungeonFloorDefinition,
        floorIndex: Int,
        seed: UInt64
    ) -> DungeonFloorDefinition {
        let cardPickups = resolvedPickups(
            for: floor,
            floorIndex: floorIndex,
            seed: seed
        )
        let rewardMoveCards = resolvedRewardCards(
            for: floor,
            floorIndex: floorIndex,
            seed: seed
        )
        return DungeonFloorDefinition(
            id: floor.id,
            title: floor.title,
            boardSize: floor.boardSize,
            spawnPoint: floor.spawnPoint,
            exitPoint: floor.exitPoint,
            deckPreset: floor.deckPreset,
            failureRule: floor.failureRule,
            enemies: floor.enemies,
            hazards: floor.hazards,
            impassableTilePoints: floor.impassableTilePoints,
            tileEffectOverrides: floor.tileEffectOverrides,
            warpTilePairs: floor.warpTilePairs,
            fixedWarpCardTargets: floor.fixedWarpCardTargets,
            exitLock: floor.exitLock,
            cardPickups: cardPickups,
            rewardMoveCardsAfterClear: rewardMoveCards
        )
    }

    private static func resolvedPickups(
        for floor: DungeonFloorDefinition,
        floorIndex: Int,
        seed: UInt64
    ) -> [DungeonCardPickupDefinition] {
        guard !floor.cardPickups.isEmpty else { return [] }
        var randomizer = DungeonCardVariationRandomizer(seed: seed, floorIndex: floorIndex, salt: 0xC4D1)
        var cards = variedCards(
            from: floor.cardPickups.map(\.card),
            randomizer: &randomizer
        )
        if cards.count < floor.cardPickups.count {
            cards += floor.cardPickups.dropFirst(cards.count).map(\.card)
        }

        var positions = pickupPositions(
            for: floor,
            count: floor.cardPickups.count,
            randomizer: &randomizer
        )
        if positions.count < floor.cardPickups.count {
            positions += floor.cardPickups.dropFirst(positions.count).map(\.point)
        }

        return floor.cardPickups.enumerated().map { index, basePickup in
            DungeonCardPickupDefinition(
                id: basePickup.id,
                point: positions[index],
                card: cards[index],
                uses: basePickup.uses
            )
        }
    }

    private static func resolvedRewardCards(
        for floor: DungeonFloorDefinition,
        floorIndex: Int,
        seed: UInt64
    ) -> [MoveCard] {
        guard !floor.rewardMoveCardsAfterClear.isEmpty else { return [] }
        var randomizer = DungeonCardVariationRandomizer(seed: seed, floorIndex: floorIndex, salt: 0xA11D)
        return variedCards(from: floor.rewardMoveCardsAfterClear, randomizer: &randomizer)
    }

    private static func variedCards(
        from baseCards: [MoveCard],
        randomizer: inout DungeonCardVariationRandomizer
    ) -> [MoveCard] {
        var result: [MoveCard] = []
        for baseCard in baseCards {
            let alternatives = cardAlternatives(for: baseCard)
            let startIndex = randomizer.nextIndex(upperBound: alternatives.count)
            let selected = (0..<alternatives.count)
                .map { alternatives[(startIndex + $0) % alternatives.count] }
                .first { !result.contains($0) }
                ?? baseCard
            result.append(selected)
        }
        return result
    }

    private static func cardAlternatives(for card: MoveCard) -> [MoveCard] {
        switch card {
        case .straightRight2:
            return [.straightRight2, .rayRight, .knightRightwardChoice]
        case .straightLeft2:
            return [.straightLeft2, .rayLeft, .knightLeftwardChoice]
        case .straightUp2:
            return [.straightUp2, .rayUp, .knightUpwardChoice]
        case .straightDown2:
            return [.straightDown2, .rayDown, .knightDownwardChoice]
        case .diagonalUpRight2:
            return [.diagonalUpRight2, .rayUpRight, .knightRightwardChoice]
        case .diagonalUpLeft2:
            return [.diagonalUpLeft2, .rayUpLeft, .knightLeftwardChoice]
        case .diagonalDownRight2:
            return [.diagonalDownRight2, .rayDownRight, .knightRightwardChoice]
        case .diagonalDownLeft2:
            return [.diagonalDownLeft2, .rayDownLeft, .knightLeftwardChoice]
        case .rayRight:
            return [.rayRight, .straightRight2, .knightRightwardChoice]
        case .rayLeft:
            return [.rayLeft, .straightLeft2, .knightLeftwardChoice]
        case .rayUp:
            return [.rayUp, .straightUp2, .knightUpwardChoice]
        case .rayDown:
            return [.rayDown, .straightDown2, .knightDownwardChoice]
        case .rayUpRight:
            return [.rayUpRight, .diagonalUpRight2, .knightUpwardChoice]
        case .rayUpLeft:
            return [.rayUpLeft, .diagonalUpLeft2, .knightUpwardChoice]
        case .rayDownRight:
            return [.rayDownRight, .diagonalDownRight2, .knightDownwardChoice]
        case .rayDownLeft:
            return [.rayDownLeft, .diagonalDownLeft2, .knightDownwardChoice]
        case .knightRightwardChoice:
            return [.knightRightwardChoice, .straightRight2, .diagonalUpRight2]
        case .knightLeftwardChoice:
            return [.knightLeftwardChoice, .straightLeft2, .diagonalUpLeft2]
        case .knightUpwardChoice:
            return [.knightUpwardChoice, .straightUp2, .diagonalUpRight2]
        case .knightDownwardChoice:
            return [.knightDownwardChoice, .straightDown2, .diagonalDownRight2]
        default:
            return [card]
        }
    }

    private static func pickupPositions(
        for floor: DungeonFloorDefinition,
        count: Int,
        randomizer: inout DungeonCardVariationRandomizer
    ) -> [GridPoint] {
        var candidates = safePickupPoints(for: floor)
        var result: [GridPoint] = []
        while !candidates.isEmpty && result.count < count {
            let index = randomizer.nextIndex(upperBound: candidates.count)
            result.append(candidates.remove(at: index))
        }
        return result
    }

    private static func safePickupPoints(for floor: DungeonFloorDefinition) -> [GridPoint] {
        var blocked: Set<GridPoint> = [
            floor.spawnPoint,
            floor.exitPoint
        ]
        blocked.formUnion(floor.impassableTilePoints)
        blocked.formUnion(floor.enemies.map(\.position))
        blocked.formUnion(floor.hazards.flatMap(\.points))
        blocked.formUnion(floor.warpTilePairs.values.flatMap { $0 })
        if let unlockPoint = floor.exitLock?.unlockPoint {
            blocked.insert(unlockPoint)
        }

        var points: [GridPoint] = []
        for y in 0..<floor.boardSize {
            for x in 0..<floor.boardSize {
                let point = GridPoint(x: x, y: y)
                if !blocked.contains(point) {
                    points.append(point)
                }
            }
        }
        return points
    }
}

private struct DungeonCardVariationRandomizer {
    private var state: UInt64

    init(seed: UInt64, floorIndex: Int, salt: UInt64) {
        state = seed
            ^ UInt64(floorIndex + 1).multipliedReportingOverflow(by: 0x9E37_79B9_7F4A_7C15).partialValue
            ^ salt
        advance()
    }

    mutating func nextIndex(upperBound: Int) -> Int {
        guard upperBound > 1 else { return 0 }
        return Int(advance() % UInt64(upperBound))
    }

    @discardableResult
    private mutating func advance() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        var value = state
        value ^= value >> 30
        value &*= 0xBF58_476D_1CE4_E5B9
        value ^= value >> 27
        value &*= 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return value
    }
}

private extension HazardDefinition {
    var points: Set<GridPoint> {
        switch self {
        case .brittleFloor(let points):
            return points
        case .damageTrap(let points, _):
            return points
        }
    }
}

/// `GameMode.Regulation` に埋め込むダンジョン追加ルール
public struct DungeonRules: Codable, Equatable {
    public var difficulty: DungeonDifficulty
    public var failureRule: DungeonFailureRule
    public var enemies: [EnemyDefinition]
    public var hazards: [HazardDefinition]
    /// 指定がある場合、鍵マスを踏むまで出口到達ではクリアしない
    public var exitLock: DungeonExitLock?
    /// カードを消費しない上下左右 1 マス移動を許可するか
    public var allowsBasicOrthogonalMove: Bool
    /// 塔内でのカード獲得・補充方式
    public var cardAcquisitionMode: DungeonCardAcquisitionMode
    /// この GameMode で解決済みの拾得カード配置
    public var cardPickups: [DungeonCardPickupDefinition]

    public init(
        difficulty: DungeonDifficulty,
        failureRule: DungeonFailureRule,
        enemies: [EnemyDefinition] = [],
        hazards: [HazardDefinition] = [],
        exitLock: DungeonExitLock? = nil,
        allowsBasicOrthogonalMove: Bool = false,
        cardAcquisitionMode: DungeonCardAcquisitionMode = .deck,
        cardPickups: [DungeonCardPickupDefinition] = []
    ) {
        self.difficulty = difficulty
        self.failureRule = failureRule
        self.enemies = enemies
        self.hazards = hazards
        self.exitLock = exitLock
        self.allowsBasicOrthogonalMove = allowsBasicOrthogonalMove
        self.cardAcquisitionMode = cardAcquisitionMode
        self.cardPickups = cardPickups
    }

    private enum CodingKeys: String, CodingKey {
        case difficulty
        case failureRule
        case enemies
        case hazards
        case exitLock
        case allowsBasicOrthogonalMove
        case cardAcquisitionMode
        case cardPickups
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        difficulty = try container.decode(DungeonDifficulty.self, forKey: .difficulty)
        failureRule = try container.decode(DungeonFailureRule.self, forKey: .failureRule)
        enemies = try container.decodeIfPresent([EnemyDefinition].self, forKey: .enemies) ?? []
        hazards = try container.decodeIfPresent([HazardDefinition].self, forKey: .hazards) ?? []
        exitLock = try container.decodeIfPresent(DungeonExitLock.self, forKey: .exitLock)
        allowsBasicOrthogonalMove = try container.decodeIfPresent(Bool.self, forKey: .allowsBasicOrthogonalMove) ?? false
        cardAcquisitionMode = try container.decodeIfPresent(DungeonCardAcquisitionMode.self, forKey: .cardAcquisitionMode) ?? .deck
        cardPickups = try container.decodeIfPresent([DungeonCardPickupDefinition].self, forKey: .cardPickups) ?? []
    }
}

/// 塔ダンジョン定義の入口
public struct DungeonLibrary {
    public static let shared = DungeonLibrary()

    private static let tutorialTowerBoardSize = 5
    private static let standardTowerBoardSize = 9

    public let dungeons: [DungeonDefinition]

    public init() {
        dungeons = [
            DungeonLibrary.buildTutorialTower(),
            DungeonLibrary.buildGrowthTower(),
            DungeonLibrary.buildRoguelikeTower()
        ]
    }

    public var allFloors: [DungeonFloorDefinition] {
        dungeons.flatMap(\.floors)
    }

    public func dungeon(with id: String) -> DungeonDefinition? {
        if let visibleDungeon = dungeons.first(where: { $0.id == id }) {
            return visibleDungeon
        }
        return legacyDungeon(with: id)
    }

    private func legacyDungeon(with id: String) -> DungeonDefinition? {
        switch id {
        case "patrol-tower":
            return DungeonLibrary.buildPatrolTower()
        case "key-door-tower":
            return DungeonLibrary.buildKeyDoorTower()
        case "warp-tower":
            return DungeonLibrary.buildWarpTower()
        case "trap-tower":
            return DungeonLibrary.buildTrapTower()
        default:
            return nil
        }
    }

    public func firstFloorMode(
        for dungeon: DungeonDefinition,
        initialHPBonus: Int = 0,
        startingHazardDamageMitigations: Int = 0,
        cardVariationSeed: UInt64? = nil
    ) -> GameMode? {
        floorMode(
            for: dungeon,
            floorIndex: 0,
            initialHPBonus: initialHPBonus,
            startingHazardDamageMitigations: startingHazardDamageMitigations,
            cardVariationSeed: cardVariationSeed
        )
    }

    public func floorMode(
        for dungeon: DungeonDefinition,
        floorIndex: Int,
        initialHPBonus: Int = 0,
        startingRewardEntries: [DungeonInventoryEntry] = [],
        startingHazardDamageMitigations: Int = 0,
        cardVariationSeed: UInt64? = nil
    ) -> GameMode? {
        guard dungeon.floors.indices.contains(floorIndex) else { return nil }
        let baseFloor = dungeon.floors[floorIndex]
        let resolvedInitialHPBonus = dungeon.difficulty == .growth ? max(initialHPBonus, 0) : 0
        let resolvedCardVariationSeed = dungeon.id == "growth-tower"
            ? cardVariationSeed ?? Self.makeCardVariationSeed()
            : nil
        let runState = DungeonRunState(
            dungeonID: dungeon.id,
            currentFloorIndex: floorIndex,
            carriedHP: baseFloor.failureRule.initialHP + resolvedInitialHPBonus,
            clearedFloorCount: floorIndex,
            rewardInventoryEntries: startingRewardEntries,
            cardVariationSeed: resolvedCardVariationSeed,
            hazardDamageMitigationsRemaining: dungeon.difficulty == .growth ? startingHazardDamageMitigations : 0
        )
        let floor = dungeon.resolvedFloor(at: floorIndex, runState: runState) ?? baseFloor
        return floor.makeGameMode(
            dungeonID: dungeon.id,
            difficulty: dungeon.difficulty,
            carriedHP: runState.carriedHP,
            runState: runState
        )
    }

    private static func makeCardVariationSeed() -> UInt64 {
        var seed = UInt64.random(in: 1...UInt64.max)
        seed ^= UInt64(Date().timeIntervalSinceReferenceDate * 1000)
        return seed == 0 ? 1 : seed
    }

    private static func buildTutorialTower() -> DungeonDefinition {
        let floors = [
            DungeonFloorDefinition(
                id: "tutorial-1",
                title: "塔の入口",
                boardSize: tutorialTowerBoardSize,
                spawnPoint: GridPoint(x: 1, y: 0),
                exitPoint: GridPoint(x: 3, y: 4),
                deckPreset: .kingAndKnightBasic,
                failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 7),
                cardPickups: [
                    DungeonCardPickupDefinition(
                        id: "tutorial-1-up2",
                        point: GridPoint(x: 1, y: 1),
                        card: .straightUp2
                    ),
                    DungeonCardPickupDefinition(
                        id: "tutorial-1-right2",
                        point: GridPoint(x: 1, y: 3),
                        card: .straightRight2
                    )
                ],
                rewardMoveCardsAfterClear: [
                    .straightRight2,
                    .straightUp2,
                    .knightRightwardChoice
                ]
            ),
            DungeonFloorDefinition(
                id: "tutorial-2",
                title: "見張りの間",
                boardSize: tutorialTowerBoardSize,
                spawnPoint: GridPoint(x: 0, y: 0),
                exitPoint: GridPoint(x: 4, y: 4),
                deckPreset: .kingAndKnightBasic,
                failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 9),
                enemies: [
                    EnemyDefinition(
                        id: "watcher-1",
                        name: "見張り",
                        position: GridPoint(x: 2, y: 1),
                        behavior: .watcher(direction: MoveVector(dx: 0, dy: 1), range: 3)
                    )
                ],
                cardPickups: [
                    DungeonCardPickupDefinition(
                        id: "tutorial-2-right2",
                        point: GridPoint(x: 1, y: 0),
                        card: .straightRight2
                    ),
                    DungeonCardPickupDefinition(
                        id: "tutorial-2-up2",
                        point: GridPoint(x: 4, y: 1),
                        card: .straightUp2
                    ),
                    DungeonCardPickupDefinition(
                        id: "tutorial-2-knight",
                        point: GridPoint(x: 3, y: 0),
                        card: .knightRightwardChoice
                    )
                ],
                rewardMoveCardsAfterClear: [
                    .rayRight,
                    .straightRight2,
                    .knightRightwardChoice,
                ]
            ),
            DungeonFloorDefinition(
                id: "tutorial-3",
                title: "ひび割れ床",
                boardSize: tutorialTowerBoardSize,
                spawnPoint: GridPoint(x: 0, y: 2),
                exitPoint: GridPoint(x: 4, y: 2),
                deckPreset: .standardLight,
                failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 6),
                enemies: [
                    EnemyDefinition(
                        id: "guard-1",
                        name: "番兵",
                        position: GridPoint(x: 3, y: 3),
                        behavior: .guardPost
                    )
                ],
                hazards: [
                    .brittleFloor(points: [
                        GridPoint(x: 1, y: 2),
                        GridPoint(x: 2, y: 2),
                        GridPoint(x: 3, y: 2)
                    ])
                ],
                cardPickups: [
                    DungeonCardPickupDefinition(
                        id: "tutorial-3-ray-right",
                        point: GridPoint(x: 0, y: 1),
                        card: .rayRight
                    ),
                    DungeonCardPickupDefinition(
                        id: "tutorial-3-up2",
                        point: GridPoint(x: 2, y: 1),
                        card: .straightUp2
                    ),
                    DungeonCardPickupDefinition(
                        id: "tutorial-3-knight",
                        point: GridPoint(x: 1, y: 3),
                        card: .knightRightwardChoice
                    )
                ]
            )
        ]

        return DungeonDefinition(
            id: "tutorial-tower",
            title: "基礎塔",
            summary: "出口到達、敵の警戒範囲、ひび割れ床を順に学ぶチュートリアル塔。",
            difficulty: .tutorial,
            floors: floors
        )
    }

    private static func buildGrowthTower() -> DungeonDefinition {
        let patrolFloors = buildPatrolTower().floors
        let keyDoorFloors = buildKeyDoorTower().floors
        let warpFloors = buildWarpTower().floors
        let trapFloors = buildTrapTower().floors
        let baseFloors = [
            patrolFloors[0]
                .withAdditionalCardPickups([
                    DungeonCardPickupDefinition(id: "growth-1-diagonal-up-right", point: GridPoint(x: 3, y: 0), card: .diagonalUpRight2),
                    DungeonCardPickupDefinition(id: "growth-1-ray-right", point: GridPoint(x: 0, y: 2), card: .rayRight)
                ])
                .withAdditionalImpassableTilePoints([
                    GridPoint(x: 1, y: 2),
                    GridPoint(x: 6, y: 6)
                ])
                .withRewardMoveCardsAfterClear([
                    .rayLeft,
                    .diagonalDownLeft2,
                    .straightDown2
                ]),
            stairKeyOnlyGrowthFloor(
                keyDoorFloors[0].withAdditionalCardPickups([
                    DungeonCardPickupDefinition(id: "growth-2-left2", point: GridPoint(x: 6, y: 8), card: .straightLeft2),
                    DungeonCardPickupDefinition(id: "growth-2-diagonal-down-left", point: GridPoint(x: 3, y: 6), card: .diagonalDownLeft2)
                ])
                .withAdditionalImpassableTilePoints([
                    GridPoint(x: 5, y: 6),
                    GridPoint(x: 7, y: 6)
                ]),
                rewardMoveCardsAfterClear: [
                    .rayRight,
                    .diagonalDownRight2,
                    .straightDown2
                ]
            ),
            trapFloors[0]
                .withAdditionalCardPickups([
                    DungeonCardPickupDefinition(id: "growth-3-ray-right", point: GridPoint(x: 0, y: 3), card: .rayRight),
                    DungeonCardPickupDefinition(id: "growth-3-diagonal-up-left", point: GridPoint(x: 8, y: 2), card: .diagonalUpLeft2)
                ])
                .withAdditionalImpassableTilePoints([
                    GridPoint(x: 1, y: 5),
                    GridPoint(x: 5, y: 1)
                ])
                .withRewardMoveCardsAfterClear([
                    .rayLeft,
                    .diagonalUpLeft2,
                    .straightUp2
                ]),
            growthFloorWithoutFixedWarp(
                warpFloors[0].withAdditionalCardPickups([
                    DungeonCardPickupDefinition(id: "growth-4-down2", point: GridPoint(x: 8, y: 2), card: .straightDown2),
                    DungeonCardPickupDefinition(id: "growth-4-ray-left", point: GridPoint(x: 4, y: 8), card: .rayLeft)
                ])
                .withAdditionalImpassableTilePoints([
                    GridPoint(x: 3, y: 3),
                    GridPoint(x: 6, y: 2)
                ]),
                rewardMoveCardsAfterClear: [
                    .rayRight,
                    .diagonalDownRight2,
                    .straightDown2
                ]
            ),
            patrolFloors[1]
                .withAdditionalCardPickups([
                    DungeonCardPickupDefinition(id: "growth-5-right2", point: GridPoint(x: 0, y: 6), card: .straightRight2),
                    DungeonCardPickupDefinition(id: "growth-5-diagonal-up-right", point: GridPoint(x: 6, y: 1), card: .diagonalUpRight2)
                ])
                .withAdditionalImpassableTilePoints([
                    GridPoint(x: 2, y: 2),
                    GridPoint(x: 6, y: 6)
                ])
                .withRewardMoveCardsAfterClear([
                    .diagonalDownLeft2,
                    .straightLeft2,
                    .straightDown2
                ]),
            growthFloorWithoutFixedWarp(
                warpFloors[1].withAdditionalCardPickups([
                    DungeonCardPickupDefinition(id: "growth-6-left2", point: GridPoint(x: 8, y: 6), card: .straightLeft2),
                    DungeonCardPickupDefinition(id: "growth-6-diagonal-down-right", point: GridPoint(x: 2, y: 2), card: .diagonalDownRight2)
                ])
                .withAdditionalImpassableTilePoints([
                    GridPoint(x: 3, y: 5),
                    GridPoint(x: 6, y: 2)
                ]),
                title: "転移の抜け道",
                replacementForFixedWarpPickups: .rayRight,
                rewardMoveCardsAfterClear: [
                    .rayLeft,
                    .straightLeft2,
                    .knightLeftwardChoice
                ]
            ),
            stairKeyOnlyGrowthFloor(
                keyDoorFloors[2].withAdditionalCardPickups([
                    DungeonCardPickupDefinition(id: "growth-7-ray-right", point: GridPoint(x: 0, y: 2), card: .rayRight),
                    DungeonCardPickupDefinition(id: "growth-7-diagonal-up-right", point: GridPoint(x: 2, y: 5), card: .diagonalUpRight2)
                ])
                .withImpassableTilePoints([
                    GridPoint(x: 4, y: 2),
                    GridPoint(x: 4, y: 6),
                    GridPoint(x: 7, y: 2)
                ])
                .withEnemies([
                    EnemyDefinition(
                        id: "growth-7-rotating-watcher",
                        name: "回転見張り",
                        position: GridPoint(x: 6, y: 5),
                        behavior: .rotatingWatcher(
                            directions: [
                                MoveVector(dx: -1, dy: 0),
                                MoveVector(dx: 0, dy: -1),
                                MoveVector(dx: -1, dy: 0),
                                MoveVector(dx: 0, dy: 1)
                            ],
                            range: 2
                        )
                    ),
                    EnemyDefinition(
                        id: "growth-7-chaser",
                        name: "追跡兵",
                        position: GridPoint(x: 6, y: 1),
                        behavior: .chaser
                    )
                ]),
                rewardMoveCardsAfterClear: [
                    .straightUp2,
                    .rayUp,
                    .knightUpwardChoice
                ]
            ),
            trapFloors[2]
                .withAdditionalCardPickups([
                    DungeonCardPickupDefinition(id: "growth-8-right2", point: GridPoint(x: 0, y: 1), card: .straightRight2),
                    DungeonCardPickupDefinition(id: "growth-8-up2", point: GridPoint(x: 3, y: 0), card: .straightUp2)
                ])
                .withAdditionalImpassableTilePoints([
                    GridPoint(x: 1, y: 5),
                    GridPoint(x: 4, y: 1),
                    GridPoint(x: 7, y: 3)
                ])
                .withRewardMoveCardsAfterClear([
                    .straightRight2,
                    .diagonalUpRight2,
                    .rayRight
                ]),
            buildGrowthTowerNinthFloor(),
            buildGrowthTowerTenthFloor(),
            buildGrowthTowerEleventhFloor(),
            buildGrowthTowerTwelfthFloor(),
            buildGrowthTowerThirteenthFloor(),
            buildGrowthTowerFourteenthFloor(),
            buildGrowthTowerFifteenthFloor(),
            buildGrowthTowerSixteenthFloor(),
            buildGrowthTowerSeventeenthFloor(),
            buildGrowthTowerEighteenthFloor(),
            buildGrowthTowerNineteenthFloor(),
            buildGrowthTowerTwentiethFloor()
        ]
        let floors = buildStitchedGrowthTowerFloors(from: baseFloors)

        return DungeonDefinition(
            id: "growth-tower",
            title: "成長塔",
            summary: "巡回、鍵、罠、ワープを階ごとに重ね、周回成長で攻略方針を広げる標準塔。",
            difficulty: .growth,
            floors: floors
        )
    }

    private static func buildStitchedGrowthTowerFloors(
        from floors: [DungeonFloorDefinition]
    ) -> [DungeonFloorDefinition] {
        let exitPointsByFloorIndex: [Int: GridPoint] = [
            0: GridPoint(x: 8, y: 8),
            1: GridPoint(x: 0, y: 4),
            2: GridPoint(x: 8, y: 0),
            3: GridPoint(x: 0, y: 8),
            4: GridPoint(x: 8, y: 4),
            5: GridPoint(x: 4, y: 0),
            6: GridPoint(x: 0, y: 0),
            7: GridPoint(x: 0, y: 2),
            8: GridPoint(x: 8, y: 8),
            9: GridPoint(x: 0, y: 8),
            10: GridPoint(x: 8, y: 8),
            11: GridPoint(x: 8, y: 2),
            12: GridPoint(x: 0, y: 6),
            13: GridPoint(x: 8, y: 6),
            14: GridPoint(x: 0, y: 0),
            15: GridPoint(x: 8, y: 4),
            16: GridPoint(x: 2, y: 8),
            17: GridPoint(x: 8, y: 8),
            18: GridPoint(x: 0, y: 2),
            19: GridPoint(x: 8, y: 8)
        ]
        let sectionStartIndexes: Set<Int> = [0, 10]
        var previousExitPoint: GridPoint?

        return floors.enumerated().map { index, floor in
            let spawnPoint = sectionStartIndexes.contains(index) ? floor.spawnPoint : previousExitPoint
            let exitPoint = exitPointsByFloorIndex[index] ?? floor.exitPoint
            previousExitPoint = exitPoint
            return floor.withEndpoints(
                spawnPoint: spawnPoint,
                exitPoint: exitPoint
            )
        }
    }

    private static func stairKeyOnlyGrowthFloor(
        _ floor: DungeonFloorDefinition,
        rewardMoveCardsAfterClear: [MoveCard]? = nil
    ) -> DungeonFloorDefinition {
        var openGateTargets: Set<GridPoint> = []
        let retainedEffects = floor.tileEffectOverrides.filter { _, effect in
            if case .openGate(let target) = effect {
                openGateTargets.insert(target)
                return false
            }
            return true
        }

        return DungeonFloorDefinition(
            id: floor.id,
            title: floor.title,
            boardSize: floor.boardSize,
            spawnPoint: floor.spawnPoint,
            exitPoint: floor.exitPoint,
            deckPreset: floor.deckPreset,
            failureRule: floor.failureRule,
            enemies: floor.enemies,
            hazards: floor.hazards,
            impassableTilePoints: floor.impassableTilePoints.subtracting(openGateTargets),
            tileEffectOverrides: retainedEffects,
            warpTilePairs: floor.warpTilePairs,
            fixedWarpCardTargets: floor.fixedWarpCardTargets,
            exitLock: floor.exitLock,
            cardPickups: floor.cardPickups,
            rewardMoveCardsAfterClear: rewardMoveCardsAfterClear ?? floor.rewardMoveCardsAfterClear
        )
    }

    private static func growthFloorWithoutFixedWarp(
        _ floor: DungeonFloorDefinition,
        title: String? = nil,
        replacementForFixedWarpPickups: MoveCard = .straightRight2,
        rewardMoveCardsAfterClear: [MoveCard]? = nil
    ) -> DungeonFloorDefinition {
        let cardPickups = floor.cardPickups.map { pickup in
            guard pickup.card == .fixedWarp else { return pickup }
            return DungeonCardPickupDefinition(
                id: pickup.id,
                point: pickup.point,
                card: replacementForFixedWarpPickups
            )
        }

        return DungeonFloorDefinition(
            id: floor.id,
            title: title ?? floor.title,
            boardSize: floor.boardSize,
            spawnPoint: floor.spawnPoint,
            exitPoint: floor.exitPoint,
            deckPreset: floor.deckPreset,
            failureRule: floor.failureRule,
            enemies: floor.enemies,
            hazards: floor.hazards,
            impassableTilePoints: floor.impassableTilePoints,
            tileEffectOverrides: floor.tileEffectOverrides,
            warpTilePairs: floor.warpTilePairs,
            fixedWarpCardTargets: [:],
            exitLock: floor.exitLock,
            cardPickups: cardPickups,
            rewardMoveCardsAfterClear: rewardMoveCardsAfterClear ?? floor.rewardMoveCardsAfterClear
        )
    }

    private static func buildGrowthTowerNinthFloor() -> DungeonFloorDefinition {
        DungeonFloorDefinition(
            id: "growth-9",
            title: "総合演習",
            boardSize: standardTowerBoardSize,
            spawnPoint: GridPoint(x: 0, y: 0),
            exitPoint: GridPoint(x: 8, y: 8),
            deckPreset: .standardLight,
            failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 18),
            enemies: [
                EnemyDefinition(
                    id: "growth-9-watcher",
                    name: "見張り",
                    position: GridPoint(x: 7, y: 6),
                    behavior: .watcher(direction: MoveVector(dx: -1, dy: 0), range: 3)
                ),
                EnemyDefinition(
                    id: "growth-9-patrol",
                    name: "巡回兵",
                    position: GridPoint(x: 4, y: 4),
                    behavior: .patrol(path: [
                        GridPoint(x: 4, y: 4),
                        GridPoint(x: 5, y: 4),
                        GridPoint(x: 5, y: 5),
                        GridPoint(x: 4, y: 5)
                    ])
                )
            ],
            hazards: [
                .damageTrap(
                    points: [
                        GridPoint(x: 2, y: 2),
                        GridPoint(x: 4, y: 4),
                        GridPoint(x: 6, y: 6)
                    ],
                    damage: 1
                ),
                .brittleFloor(points: [
                    GridPoint(x: 3, y: 2),
                    GridPoint(x: 3, y: 3),
                    GridPoint(x: 3, y: 4)
                ])
            ],
            impassableTilePoints: [
                GridPoint(x: 3, y: 6),
                GridPoint(x: 5, y: 2),
                GridPoint(x: 7, y: 3)
            ],
            warpTilePairs: [
                "growth-9-risk": [
                    GridPoint(x: 1, y: 2),
                    GridPoint(x: 6, y: 6)
                ]
            ],
            exitLock: DungeonExitLock(unlockPoint: GridPoint(x: 2, y: 1)),
            cardPickups: [
                DungeonCardPickupDefinition(
                    id: "growth-9-key-route-right2",
                    point: GridPoint(x: 0, y: 1),
                    card: .straightRight2
                ),
                DungeonCardPickupDefinition(
                    id: "growth-9-key-diagonal",
                    point: GridPoint(x: 2, y: 1),
                    card: .diagonalUpRight2
                ),
                DungeonCardPickupDefinition(
                    id: "growth-9-up2",
                    point: GridPoint(x: 8, y: 6),
                    card: .straightUp2
                )
            ],
            rewardMoveCardsAfterClear: [
                .diagonalUpRight2,
                .rayRight,
                .straightUp2
            ]
        )
    }

    private static func buildGrowthTowerTenthFloor() -> DungeonFloorDefinition {
        DungeonFloorDefinition(
            id: "growth-10",
            title: "第一関門",
            boardSize: standardTowerBoardSize,
            spawnPoint: GridPoint(x: 0, y: 0),
            exitPoint: GridPoint(x: 8, y: 8),
            deckPreset: .standardLight,
            failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 16),
            enemies: [
                EnemyDefinition(
                    id: "growth-10-patrol",
                    name: "巡回兵",
                    position: GridPoint(x: 4, y: 3),
                    behavior: .patrol(path: [
                        GridPoint(x: 4, y: 3),
                        GridPoint(x: 5, y: 3),
                        GridPoint(x: 5, y: 4),
                        GridPoint(x: 4, y: 4)
                    ])
                ),
                EnemyDefinition(
                    id: "growth-10-watcher",
                    name: "見張り",
                    position: GridPoint(x: 6, y: 6),
                    behavior: .watcher(direction: MoveVector(dx: -1, dy: 0), range: 3)
                )
            ],
            hazards: [
                .damageTrap(points: [
                    GridPoint(x: 2, y: 2),
                    GridPoint(x: 3, y: 3),
                    GridPoint(x: 6, y: 5)
                ], damage: 1)
            ],
            impassableTilePoints: [
                GridPoint(x: 2, y: 5),
                GridPoint(x: 4, y: 7),
                GridPoint(x: 7, y: 2)
            ],
            warpTilePairs: [
                "growth-10-shortcut": [
                    GridPoint(x: 1, y: 1),
                    GridPoint(x: 7, y: 6)
                ]
            ],
            cardPickups: [
                DungeonCardPickupDefinition(id: "growth-10-right2", point: GridPoint(x: 1, y: 0), card: .straightRight2),
                DungeonCardPickupDefinition(id: "growth-10-diagonal", point: GridPoint(x: 1, y: 1), card: .diagonalUpRight2),
                DungeonCardPickupDefinition(id: "growth-10-up2", point: GridPoint(x: 7, y: 6), card: .straightUp2)
            ]
        )
    }

    private static func buildGrowthTowerEleventhFloor() -> DungeonFloorDefinition {
        DungeonFloorDefinition(
            id: "growth-11",
            title: "二合目の巡回路",
            boardSize: standardTowerBoardSize,
            spawnPoint: GridPoint(x: 0, y: 0),
            exitPoint: GridPoint(x: 8, y: 8),
            deckPreset: .kingAndKnightBasic,
            failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 15),
            enemies: [
                EnemyDefinition(
                    id: "growth-11-patrol-a",
                    name: "巡回兵",
                    position: GridPoint(x: 3, y: 3),
                    behavior: .patrol(path: [
                        GridPoint(x: 3, y: 3),
                        GridPoint(x: 4, y: 3),
                        GridPoint(x: 5, y: 3),
                        GridPoint(x: 4, y: 3)
                    ])
                ),
                EnemyDefinition(
                    id: "growth-11-patrol-b",
                    name: "巡回兵",
                    position: GridPoint(x: 6, y: 5),
                    behavior: .patrol(path: [
                        GridPoint(x: 6, y: 5),
                        GridPoint(x: 6, y: 6),
                        GridPoint(x: 6, y: 7),
                        GridPoint(x: 6, y: 6)
                    ])
                )
            ],
            impassableTilePoints: [
                GridPoint(x: 1, y: 3),
                GridPoint(x: 3, y: 6),
                GridPoint(x: 7, y: 2)
            ],
            cardPickups: [
                DungeonCardPickupDefinition(id: "growth-11-right2", point: GridPoint(x: 2, y: 0), card: .straightRight2),
                DungeonCardPickupDefinition(id: "growth-11-up2", point: GridPoint(x: 4, y: 2), card: .straightUp2),
                DungeonCardPickupDefinition(id: "growth-11-knight", point: GridPoint(x: 7, y: 5), card: .knightRightwardChoice)
            ],
            rewardMoveCardsAfterClear: [.rayDown, .straightDown2, .knightDownwardChoice]
        )
    }

    private static func buildGrowthTowerTwelfthFloor() -> DungeonFloorDefinition {
        DungeonFloorDefinition(
            id: "growth-12",
            title: "鍵と罠列",
            boardSize: standardTowerBoardSize,
            spawnPoint: GridPoint(x: 0, y: 0),
            exitPoint: GridPoint(x: 8, y: 8),
            deckPreset: .standardLight,
            failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 16),
            enemies: [
                EnemyDefinition(
                    id: "growth-12-rotating-watcher",
                    name: "回転見張り",
                    position: GridPoint(x: 5, y: 3),
                    behavior: .rotatingWatcher(
                        directions: [
                            MoveVector(dx: -1, dy: 0),
                            MoveVector(dx: 0, dy: 1),
                            MoveVector(dx: 1, dy: 0)
                        ],
                        range: 3
                    )
                ),
                EnemyDefinition(
                    id: "growth-12-chaser",
                    name: "追跡兵",
                    position: GridPoint(x: 7, y: 1),
                    behavior: .chaser
                )
            ],
            hazards: [
                .damageTrap(points: [
                    GridPoint(x: 2, y: 1),
                    GridPoint(x: 3, y: 2),
                    GridPoint(x: 4, y: 3),
                    GridPoint(x: 5, y: 4)
                ], damage: 1)
            ],
            impassableTilePoints: [
                GridPoint(x: 1, y: 5),
                GridPoint(x: 5, y: 2),
                GridPoint(x: 7, y: 6)
            ],
            exitLock: DungeonExitLock(unlockPoint: GridPoint(x: 2, y: 2)),
            cardPickups: [
                DungeonCardPickupDefinition(id: "growth-12-key-up2", point: GridPoint(x: 2, y: 2), card: .straightUp2),
                DungeonCardPickupDefinition(id: "growth-12-right2", point: GridPoint(x: 0, y: 1), card: .straightRight2),
                DungeonCardPickupDefinition(id: "growth-12-ray-right", point: GridPoint(x: 4, y: 5), card: .rayRight)
            ],
            rewardMoveCardsAfterClear: [.rayLeft, .diagonalUpLeft2, .straightUp2]
        )
    }

    private static func buildGrowthTowerThirteenthFloor() -> DungeonFloorDefinition {
        DungeonFloorDefinition(
            id: "growth-13",
            title: "転移と見張り",
            boardSize: standardTowerBoardSize,
            spawnPoint: GridPoint(x: 0, y: 4),
            exitPoint: GridPoint(x: 8, y: 4),
            deckPreset: .standardLight,
            failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 13),
            enemies: [
                EnemyDefinition(
                    id: "growth-13-watcher",
                    name: "回転見張り",
                    position: GridPoint(x: 6, y: 3),
                    behavior: .rotatingWatcher(
                        directions: [
                            MoveVector(dx: 0, dy: 1),
                            MoveVector(dx: -1, dy: 0),
                            MoveVector(dx: 0, dy: 1),
                            MoveVector(dx: 1, dy: 0)
                        ],
                        range: 4
                    )
                )
            ],
            impassableTilePoints: [
                GridPoint(x: 3, y: 4),
                GridPoint(x: 5, y: 1),
                GridPoint(x: 7, y: 7)
            ],
            warpTilePairs: [
                "growth-13-risk": [
                    GridPoint(x: 1, y: 4),
                    GridPoint(x: 6, y: 3)
                ],
                "growth-13-safe": [
                    GridPoint(x: 2, y: 2),
                    GridPoint(x: 7, y: 5)
                ]
            ],
            cardPickups: [
                DungeonCardPickupDefinition(id: "growth-13-ray-right", point: GridPoint(x: 0, y: 3), card: .rayRight),
                DungeonCardPickupDefinition(id: "growth-13-up2", point: GridPoint(x: 2, y: 2), card: .straightUp2),
                DungeonCardPickupDefinition(id: "growth-13-right2", point: GridPoint(x: 7, y: 5), card: .straightRight2)
            ],
            rewardMoveCardsAfterClear: [.straightRight2, .knightRightwardChoice, .diagonalUpRight2]
        )
    }

    private static func buildGrowthTowerFourteenthFloor() -> DungeonFloorDefinition {
        DungeonFloorDefinition(
            id: "growth-14",
            title: "ひび割れの迂回路",
            boardSize: standardTowerBoardSize,
            spawnPoint: GridPoint(x: 0, y: 2),
            exitPoint: GridPoint(x: 8, y: 6),
            deckPreset: .standardLight,
            failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 15),
            enemies: [
                EnemyDefinition(id: "growth-14-guard", name: "番兵", position: GridPoint(x: 4, y: 5), behavior: .guardPost)
            ],
            hazards: [
                .brittleFloor(points: [
                    GridPoint(x: 2, y: 2),
                    GridPoint(x: 3, y: 2),
                    GridPoint(x: 4, y: 2),
                    GridPoint(x: 5, y: 2)
                ]),
                .damageTrap(points: [GridPoint(x: 6, y: 4), GridPoint(x: 7, y: 5)], damage: 1)
            ],
            impassableTilePoints: [
                GridPoint(x: 1, y: 4),
                GridPoint(x: 3, y: 6),
                GridPoint(x: 6, y: 1),
                GridPoint(x: 7, y: 3)
            ],
            cardPickups: [
                DungeonCardPickupDefinition(id: "growth-14-ray-right", point: GridPoint(x: 0, y: 1), card: .rayRight),
                DungeonCardPickupDefinition(id: "growth-14-up2", point: GridPoint(x: 5, y: 3), card: .straightUp2),
                DungeonCardPickupDefinition(id: "growth-14-diagonal", point: GridPoint(x: 6, y: 4), card: .diagonalUpRight2)
            ],
            rewardMoveCardsAfterClear: [.diagonalDownLeft2, .rayLeft, .straightDown2]
        )
    }

    private static func buildGrowthTowerFifteenthFloor() -> DungeonFloorDefinition {
        DungeonFloorDefinition(
            id: "growth-15",
            title: "中間演習",
            boardSize: standardTowerBoardSize,
            spawnPoint: GridPoint(x: 0, y: 0),
            exitPoint: GridPoint(x: 8, y: 8),
            deckPreset: .standardLight,
            failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 15),
            enemies: [
                EnemyDefinition(
                    id: "growth-15-watcher",
                    name: "回転見張り",
                    position: GridPoint(x: 7, y: 4),
                    behavior: .rotatingWatcher(
                        directions: [
                            MoveVector(dx: -1, dy: 0),
                            MoveVector(dx: 0, dy: 1),
                            MoveVector(dx: -1, dy: 0),
                            MoveVector(dx: 0, dy: -1)
                        ],
                        range: 4
                    )
                ),
                EnemyDefinition(id: "growth-15-patrol", name: "巡回兵", position: GridPoint(x: 4, y: 4), behavior: .patrol(path: [GridPoint(x: 4, y: 4), GridPoint(x: 5, y: 4), GridPoint(x: 5, y: 5), GridPoint(x: 4, y: 5)]))
                ,
                EnemyDefinition(
                    id: "growth-15-chaser",
                    name: "追跡兵",
                    position: GridPoint(x: 3, y: 7),
                    behavior: .chaser
                )
            ],
            hazards: [
                .damageTrap(points: [GridPoint(x: 2, y: 1), GridPoint(x: 5, y: 5), GridPoint(x: 7, y: 6)], damage: 1)
            ],
            impassableTilePoints: [
                GridPoint(x: 1, y: 6),
                GridPoint(x: 3, y: 3),
                GridPoint(x: 5, y: 1),
                GridPoint(x: 7, y: 2)
            ],
            warpTilePairs: ["growth-15-warp": [GridPoint(x: 1, y: 2), GridPoint(x: 6, y: 6)]],
            exitLock: DungeonExitLock(unlockPoint: GridPoint(x: 2, y: 1)),
            cardPickups: [
                DungeonCardPickupDefinition(id: "growth-15-right2", point: GridPoint(x: 0, y: 1), card: .straightRight2),
                DungeonCardPickupDefinition(id: "growth-15-key-diagonal", point: GridPoint(x: 2, y: 1), card: .diagonalUpRight2),
                DungeonCardPickupDefinition(id: "growth-15-up2", point: GridPoint(x: 6, y: 6), card: .straightUp2)
            ],
            rewardMoveCardsAfterClear: [.rayRight, .diagonalUpRight2, .straightRight2]
        )
    }

    private static func buildGrowthTowerSixteenthFloor() -> DungeonFloorDefinition {
        DungeonFloorDefinition(
            id: "growth-16",
            title: "挟み撃ちの廊下",
            boardSize: standardTowerBoardSize,
            spawnPoint: GridPoint(x: 0, y: 4),
            exitPoint: GridPoint(x: 8, y: 4),
            deckPreset: .standardLight,
            failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 12),
            enemies: [
                EnemyDefinition(
                    id: "growth-16-watch-up",
                    name: "回転見張り",
                    position: GridPoint(x: 4, y: 1),
                    behavior: .rotatingWatcher(
                        directions: [
                            MoveVector(dx: 0, dy: 1),
                            MoveVector(dx: 1, dy: 0),
                            MoveVector(dx: 0, dy: 1),
                            MoveVector(dx: -1, dy: 0)
                        ],
                        range: 5
                    )
                ),
                EnemyDefinition(id: "growth-16-watch-down", name: "見張り", position: GridPoint(x: 6, y: 7), behavior: .watcher(direction: MoveVector(dx: 0, dy: -1), range: 5)),
                EnemyDefinition(
                    id: "growth-16-chaser",
                    name: "追跡兵",
                    position: GridPoint(x: 7, y: 7),
                    behavior: .chaser
                )
            ],
            hazards: [.damageTrap(points: [GridPoint(x: 3, y: 4), GridPoint(x: 5, y: 4)], damage: 1)],
            impassableTilePoints: [
                GridPoint(x: 2, y: 6),
                GridPoint(x: 4, y: 0),
                GridPoint(x: 4, y: 3),
                GridPoint(x: 7, y: 2)
            ],
            cardPickups: [
                DungeonCardPickupDefinition(id: "growth-16-ray-right", point: GridPoint(x: 1, y: 4), card: .rayRight),
                DungeonCardPickupDefinition(id: "growth-16-diagonal", point: GridPoint(x: 3, y: 2), card: .diagonalUpRight2),
                DungeonCardPickupDefinition(id: "growth-16-up2", point: GridPoint(x: 6, y: 5), card: .straightUp2)
            ],
            rewardMoveCardsAfterClear: [.diagonalUpLeft2, .rayLeft, .straightUp2]
        )
    }

    private static func buildGrowthTowerSeventeenthFloor() -> DungeonFloorDefinition {
        DungeonFloorDefinition(
            id: "growth-17",
            title: "鍵の遠回り",
            boardSize: standardTowerBoardSize,
            spawnPoint: GridPoint(x: 0, y: 0),
            exitPoint: GridPoint(x: 8, y: 8),
            deckPreset: .standardLight,
            failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 17),
            enemies: [
                EnemyDefinition(id: "growth-17-patrol", name: "巡回兵", position: GridPoint(x: 5, y: 2), behavior: .patrol(path: [GridPoint(x: 5, y: 2), GridPoint(x: 5, y: 3), GridPoint(x: 6, y: 3), GridPoint(x: 6, y: 2)]))
            ],
            hazards: [.brittleFloor(points: [GridPoint(x: 3, y: 1), GridPoint(x: 3, y: 2), GridPoint(x: 3, y: 3)])],
            impassableTilePoints: [
                GridPoint(x: 2, y: 4),
                GridPoint(x: 4, y: 6),
                GridPoint(x: 7, y: 1)
            ],
            exitLock: DungeonExitLock(unlockPoint: GridPoint(x: 1, y: 5)),
            cardPickups: [
                DungeonCardPickupDefinition(id: "growth-17-up2", point: GridPoint(x: 1, y: 5), card: .straightUp2),
                DungeonCardPickupDefinition(id: "growth-17-ray-right", point: GridPoint(x: 2, y: 0), card: .rayRight),
                DungeonCardPickupDefinition(id: "growth-17-diagonal", point: GridPoint(x: 6, y: 6), card: .diagonalUpRight2)
            ],
            rewardMoveCardsAfterClear: [.straightRight2, .knightRightwardChoice, .diagonalDownRight2]
        )
    }

    private static func buildGrowthTowerEighteenthFloor() -> DungeonFloorDefinition {
        DungeonFloorDefinition(
            id: "growth-18",
            title: "罠と転移の選択",
            boardSize: standardTowerBoardSize,
            spawnPoint: GridPoint(x: 0, y: 0),
            exitPoint: GridPoint(x: 8, y: 8),
            deckPreset: .standardLight,
            failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 14),
            enemies: [
                EnemyDefinition(
                    id: "growth-18-watcher",
                    name: "回転見張り",
                    position: GridPoint(x: 7, y: 6),
                    behavior: .rotatingWatcher(
                        directions: [
                            MoveVector(dx: -1, dy: 0),
                            MoveVector(dx: 0, dy: -1),
                            MoveVector(dx: -1, dy: 0),
                            MoveVector(dx: 0, dy: 1)
                        ],
                        range: 4
                    )
                ),
                EnemyDefinition(
                    id: "growth-18-chaser",
                    name: "追跡兵",
                    position: GridPoint(x: 5, y: 7),
                    behavior: .chaser
                )
            ],
            hazards: [.damageTrap(points: [GridPoint(x: 1, y: 1), GridPoint(x: 2, y: 2), GridPoint(x: 3, y: 3), GridPoint(x: 6, y: 6)], damage: 1)],
            impassableTilePoints: [
                GridPoint(x: 3, y: 7),
                GridPoint(x: 4, y: 2),
                GridPoint(x: 5, y: 5),
                GridPoint(x: 7, y: 3)
            ],
            warpTilePairs: ["growth-18-choice": [GridPoint(x: 1, y: 0), GridPoint(x: 6, y: 6)]],
            cardPickups: [
                DungeonCardPickupDefinition(id: "growth-18-ray-right", point: GridPoint(x: 1, y: 0), card: .rayRight),
                DungeonCardPickupDefinition(id: "growth-18-right2", point: GridPoint(x: 2, y: 1), card: .straightRight2),
                DungeonCardPickupDefinition(id: "growth-18-up2", point: GridPoint(x: 8, y: 6), card: .straightUp2)
            ],
            rewardMoveCardsAfterClear: [.diagonalDownLeft2, .rayLeft, .straightDown2]
        )
    }

    private static func buildGrowthTowerNineteenthFloor() -> DungeonFloorDefinition {
        DungeonFloorDefinition(
            id: "growth-19",
            title: "最終前哨",
            boardSize: standardTowerBoardSize,
            spawnPoint: GridPoint(x: 0, y: 2),
            exitPoint: GridPoint(x: 8, y: 8),
            deckPreset: .standardLight,
            failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 15),
            enemies: [
                EnemyDefinition(id: "growth-19-patrol-a", name: "巡回兵", position: GridPoint(x: 4, y: 4), behavior: .patrol(path: [GridPoint(x: 4, y: 4), GridPoint(x: 5, y: 4), GridPoint(x: 5, y: 5), GridPoint(x: 4, y: 5)])),
                EnemyDefinition(id: "growth-19-watcher", name: "見張り", position: GridPoint(x: 7, y: 5), behavior: .watcher(direction: MoveVector(dx: -1, dy: 0), range: 5))
            ],
            hazards: [
                .brittleFloor(points: [GridPoint(x: 2, y: 2), GridPoint(x: 3, y: 2)]),
                .damageTrap(points: [GridPoint(x: 5, y: 6), GridPoint(x: 6, y: 7)], damage: 1)
            ],
            impassableTilePoints: [
                GridPoint(x: 1, y: 4),
                GridPoint(x: 3, y: 6),
                GridPoint(x: 6, y: 3),
                GridPoint(x: 7, y: 1)
            ],
            cardPickups: [
                DungeonCardPickupDefinition(id: "growth-19-ray-right", point: GridPoint(x: 0, y: 1), card: .rayRight),
                DungeonCardPickupDefinition(id: "growth-19-diagonal", point: GridPoint(x: 4, y: 3), card: .diagonalUpRight2),
                DungeonCardPickupDefinition(id: "growth-19-up2", point: GridPoint(x: 8, y: 6), card: .straightUp2)
            ],
            rewardMoveCardsAfterClear: [.straightRight2, .diagonalUpRight2, .rayRight]
        )
    }

    private static func buildGrowthTowerTwentiethFloor() -> DungeonFloorDefinition {
        DungeonFloorDefinition(
            id: "growth-20",
            title: "第二関門",
            boardSize: standardTowerBoardSize,
            spawnPoint: GridPoint(x: 0, y: 0),
            exitPoint: GridPoint(x: 8, y: 8),
            deckPreset: .standardLight,
            failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 16),
            enemies: [
                EnemyDefinition(
                    id: "growth-20-watcher",
                    name: "回転見張り",
                    position: GridPoint(x: 7, y: 6),
                    behavior: .rotatingWatcher(
                        directions: [
                            MoveVector(dx: -1, dy: 0),
                            MoveVector(dx: 0, dy: -1),
                            MoveVector(dx: -1, dy: 0),
                            MoveVector(dx: 0, dy: 1)
                        ],
                        range: 4
                    )
                ),
                EnemyDefinition(id: "growth-20-patrol", name: "巡回兵", position: GridPoint(x: 4, y: 4), behavior: .patrol(path: [GridPoint(x: 4, y: 4), GridPoint(x: 5, y: 4), GridPoint(x: 5, y: 5), GridPoint(x: 4, y: 5)])),
                EnemyDefinition(
                    id: "growth-20-chaser",
                    name: "追跡兵",
                    position: GridPoint(x: 7, y: 7),
                    behavior: .chaser
                )
            ],
            hazards: [
                .damageTrap(points: [GridPoint(x: 2, y: 1), GridPoint(x: 3, y: 3), GridPoint(x: 6, y: 6)], damage: 1)
            ],
            impassableTilePoints: [
                GridPoint(x: 1, y: 5),
                GridPoint(x: 3, y: 6),
                GridPoint(x: 6, y: 2),
                GridPoint(x: 7, y: 4)
            ],
            warpTilePairs: ["growth-20-risk": [GridPoint(x: 1, y: 2), GridPoint(x: 6, y: 6)]],
            exitLock: DungeonExitLock(unlockPoint: GridPoint(x: 2, y: 1)),
            cardPickups: [
                DungeonCardPickupDefinition(id: "growth-20-right2", point: GridPoint(x: 0, y: 1), card: .straightRight2),
                DungeonCardPickupDefinition(id: "growth-20-key-diagonal", point: GridPoint(x: 2, y: 1), card: .diagonalUpRight2),
                DungeonCardPickupDefinition(id: "growth-20-up2", point: GridPoint(x: 8, y: 6), card: .straightUp2)
            ]
        )
    }

    private static func buildPatrolTower() -> DungeonDefinition {
        let floors = [
            DungeonFloorDefinition(
                id: "patrol-1",
                title: "巡回の間",
                boardSize: standardTowerBoardSize,
                spawnPoint: GridPoint(x: 0, y: 0),
                exitPoint: GridPoint(x: 8, y: 8),
                deckPreset: .kingAndKnightBasic,
                failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 17),
                enemies: [
                    EnemyDefinition(
                        id: "patrol-1-guard",
                        name: "巡回兵",
                        position: GridPoint(x: 3, y: 4),
                        behavior: .patrol(path: [
                            GridPoint(x: 3, y: 4),
                            GridPoint(x: 4, y: 4),
                            GridPoint(x: 5, y: 4),
                            GridPoint(x: 4, y: 4)
                        ])
                    )
                ],
                cardPickups: [
                    DungeonCardPickupDefinition(
                        id: "patrol-1-right2",
                        point: GridPoint(x: 2, y: 0),
                        card: .straightRight2
                    ),
                    DungeonCardPickupDefinition(
                        id: "patrol-1-up2",
                        point: GridPoint(x: 6, y: 0),
                        card: .straightUp2
                    ),
                    DungeonCardPickupDefinition(
                        id: "patrol-1-knight",
                        point: GridPoint(x: 8, y: 3),
                        card: .knightRightwardChoice
                    )
                ],
                rewardMoveCardsAfterClear: [
                    .straightUp2,
                    .straightRight2,
                    .knightRightwardChoice
                ]
            ),
            DungeonFloorDefinition(
                id: "patrol-2",
                title: "すれ違い",
                boardSize: standardTowerBoardSize,
                spawnPoint: GridPoint(x: 0, y: 4),
                exitPoint: GridPoint(x: 8, y: 4),
                deckPreset: .kingAndKnightBasic,
                failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 17),
                enemies: [
                    EnemyDefinition(
                        id: "patrol-2-vertical",
                        name: "巡回兵A",
                        position: GridPoint(x: 4, y: 2),
                        behavior: .patrol(path: [
                            GridPoint(x: 4, y: 2),
                            GridPoint(x: 4, y: 3),
                            GridPoint(x: 4, y: 4),
                            GridPoint(x: 4, y: 5),
                            GridPoint(x: 4, y: 6),
                            GridPoint(x: 4, y: 5),
                            GridPoint(x: 4, y: 4),
                            GridPoint(x: 4, y: 3)
                        ])
                    ),
                    EnemyDefinition(
                        id: "patrol-2-horizontal",
                        name: "巡回兵B",
                        position: GridPoint(x: 5, y: 7),
                        behavior: .patrol(path: [
                            GridPoint(x: 5, y: 7),
                            GridPoint(x: 6, y: 7),
                            GridPoint(x: 7, y: 7),
                            GridPoint(x: 6, y: 7)
                        ])
                    )
                ],
                cardPickups: [
                    DungeonCardPickupDefinition(
                        id: "patrol-2-right2",
                        point: GridPoint(x: 1, y: 0),
                        card: .straightRight2
                    ),
                    DungeonCardPickupDefinition(
                        id: "patrol-2-up2",
                        point: GridPoint(x: 7, y: 2),
                        card: .straightUp2
                    ),
                    DungeonCardPickupDefinition(
                        id: "patrol-2-ray-right",
                        point: GridPoint(x: 1, y: 6),
                        card: .rayRight
                    )
                ],
                rewardMoveCardsAfterClear: [
                    .rayRight,
                    .straightUp2,
                    .knightRightwardChoice
                ]
            ),
            DungeonFloorDefinition(
                id: "patrol-3",
                title: "巡回網",
                boardSize: standardTowerBoardSize,
                spawnPoint: GridPoint(x: 0, y: 0),
                exitPoint: GridPoint(x: 8, y: 8),
                deckPreset: .standardLight,
                failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 17),
                enemies: [
                    EnemyDefinition(
                        id: "patrol-3-horizontal",
                        name: "巡回兵A",
                        position: GridPoint(x: 3, y: 4),
                        behavior: .patrol(path: [
                            GridPoint(x: 3, y: 4),
                            GridPoint(x: 4, y: 4),
                            GridPoint(x: 5, y: 4),
                            GridPoint(x: 4, y: 4)
                        ])
                    ),
                    EnemyDefinition(
                        id: "patrol-3-vertical",
                        name: "巡回兵B",
                        position: GridPoint(x: 5, y: 3),
                        behavior: .patrol(path: [
                            GridPoint(x: 5, y: 3),
                            GridPoint(x: 5, y: 4),
                            GridPoint(x: 5, y: 5),
                            GridPoint(x: 5, y: 4)
                        ])
                    )
                ],
                hazards: [
                    .brittleFloor(points: [
                        GridPoint(x: 4, y: 3),
                        GridPoint(x: 4, y: 4),
                        GridPoint(x: 4, y: 5)
                    ])
                ],
                cardPickups: [
                    DungeonCardPickupDefinition(
                        id: "patrol-3-ray-right",
                        point: GridPoint(x: 0, y: 1),
                        card: .rayRight
                    ),
                    DungeonCardPickupDefinition(
                        id: "patrol-3-up2",
                        point: GridPoint(x: 8, y: 1),
                        card: .straightUp2
                    ),
                    DungeonCardPickupDefinition(
                        id: "patrol-3-diagonal-up-right",
                        point: GridPoint(x: 4, y: 0),
                        card: .diagonalUpRight2
                    )
                ]
            )
        ]

        return DungeonDefinition(
            id: "patrol-tower",
            title: "巡回塔",
            summary: "巡回兵の移動ルートを読み、すれ違うタイミングを作る低難度の塔。",
            difficulty: .growth,
            floors: floors
        )
    }

    private static func buildKeyDoorTower() -> DungeonDefinition {
        let floors = [
            DungeonFloorDefinition(
                id: "key-door-1",
                title: "鍵の小部屋",
                boardSize: standardTowerBoardSize,
                spawnPoint: GridPoint(x: 0, y: 4),
                exitPoint: GridPoint(x: 8, y: 4),
                deckPreset: .kingAndKnightBasic,
                failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 18),
                impassableTilePoints: [
                    GridPoint(x: 4, y: 4)
                ],
                tileEffectOverrides: [
                    GridPoint(x: 2, y: 6): .openGate(target: GridPoint(x: 4, y: 4))
                ],
                exitLock: DungeonExitLock(unlockPoint: GridPoint(x: 2, y: 6)),
                cardPickups: [
                    DungeonCardPickupDefinition(
                        id: "key-door-1-right2",
                        point: GridPoint(x: 1, y: 4),
                        card: .straightRight2
                    ),
                    DungeonCardPickupDefinition(
                        id: "key-door-1-up2",
                        point: GridPoint(x: 2, y: 5),
                        card: .straightUp2
                    ),
                    DungeonCardPickupDefinition(
                        id: "key-door-1-knight",
                        point: GridPoint(x: 5, y: 4),
                        card: .knightRightwardChoice
                    )
                ],
                rewardMoveCardsAfterClear: [
                    .straightRight2,
                    .straightUp2,
                    .knightRightwardChoice
                ]
            ),
            DungeonFloorDefinition(
                id: "key-door-2",
                title: "上の鍵道",
                boardSize: standardTowerBoardSize,
                spawnPoint: GridPoint(x: 0, y: 4),
                exitPoint: GridPoint(x: 8, y: 4),
                deckPreset: .kingAndKnightBasic,
                failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 18),
                impassableTilePoints: [
                    GridPoint(x: 4, y: 4)
                ],
                tileEffectOverrides: [
                    GridPoint(x: 2, y: 7): .openGate(target: GridPoint(x: 4, y: 4))
                ],
                exitLock: DungeonExitLock(unlockPoint: GridPoint(x: 2, y: 7)),
                cardPickups: [
                    DungeonCardPickupDefinition(
                        id: "key-door-2-ray-right",
                        point: GridPoint(x: 0, y: 6),
                        card: .rayRight
                    ),
                    DungeonCardPickupDefinition(
                        id: "key-door-2-right2",
                        point: GridPoint(x: 2, y: 7),
                        card: .straightRight2
                    ),
                    DungeonCardPickupDefinition(
                        id: "key-door-2-up2",
                        point: GridPoint(x: 7, y: 2),
                        card: .straightUp2
                    )
                ],
                rewardMoveCardsAfterClear: [
                    .straightUp2,
                    .straightRight2,
                    .diagonalUpRight2
                ]
            ),
            DungeonFloorDefinition(
                id: "key-door-3",
                title: "扉の見張り",
                boardSize: standardTowerBoardSize,
                spawnPoint: GridPoint(x: 0, y: 0),
                exitPoint: GridPoint(x: 8, y: 8),
                deckPreset: .standardLight,
                failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 18),
                enemies: [
                    EnemyDefinition(
                        id: "key-door-3-watcher",
                        name: "見張り",
                        position: GridPoint(x: 6, y: 5),
                        behavior: .watcher(direction: MoveVector(dx: -1, dy: 0), range: 2)
                    )
                ],
                impassableTilePoints: [
                    GridPoint(x: 4, y: 1),
                    GridPoint(x: 4, y: 2),
                    GridPoint(x: 4, y: 3),
                    GridPoint(x: 4, y: 4),
                    GridPoint(x: 4, y: 5),
                    GridPoint(x: 4, y: 6),
                    GridPoint(x: 4, y: 7),
                    GridPoint(x: 4, y: 8)
                ],
                tileEffectOverrides: [
                    GridPoint(x: 2, y: 3): .openGate(target: GridPoint(x: 4, y: 4))
                ],
                exitLock: DungeonExitLock(unlockPoint: GridPoint(x: 2, y: 3)),
                cardPickups: [
                    DungeonCardPickupDefinition(
                        id: "key-door-3-right2",
                        point: GridPoint(x: 3, y: 0),
                        card: .straightRight2
                    ),
                    DungeonCardPickupDefinition(
                        id: "key-door-3-up2",
                        point: GridPoint(x: 2, y: 3),
                        card: .straightUp2
                    ),
                    DungeonCardPickupDefinition(
                        id: "key-door-3-diagonal-up-right",
                        point: GridPoint(x: 1, y: 1),
                        card: .diagonalUpRight2
                    )
                ]
            )
        ]

        return DungeonDefinition(
            id: "key-door-tower",
            title: "鍵扉塔",
            summary: "鍵マスで扉を開き、寄り道と出口直行の手数差を読む低難度の塔。",
            difficulty: .growth,
            floors: floors
        )
    }

    private static func buildWarpTower() -> DungeonDefinition {
        let floors = [
            DungeonFloorDefinition(
                id: "warp-1",
                title: "転移の入口",
                boardSize: standardTowerBoardSize,
                spawnPoint: GridPoint(x: 0, y: 0),
                exitPoint: GridPoint(x: 8, y: 8),
                deckPreset: .standardLight,
                failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 18),
                warpTilePairs: [
                    "warp-1-shortcut": [
                        GridPoint(x: 2, y: 1),
                        GridPoint(x: 6, y: 6)
                    ]
                ],
                cardPickups: [
                    DungeonCardPickupDefinition(
                        id: "warp-1-right2",
                        point: GridPoint(x: 1, y: 0),
                        card: .straightRight2
                    ),
                    DungeonCardPickupDefinition(
                        id: "warp-1-up2",
                        point: GridPoint(x: 6, y: 6),
                        card: .straightUp2
                    ),
                    DungeonCardPickupDefinition(
                        id: "warp-1-knight",
                        point: GridPoint(x: 7, y: 6),
                        card: .knightRightwardChoice
                    )
                ],
                rewardMoveCardsAfterClear: [
                    .fixedWarp,
                    .straightUp2,
                    .rayRight
                ]
            ),
            DungeonFloorDefinition(
                id: "warp-2",
                title: "固定ワープの間",
                boardSize: standardTowerBoardSize,
                spawnPoint: GridPoint(x: 0, y: 4),
                exitPoint: GridPoint(x: 8, y: 4),
                deckPreset: .standardLight,
                failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 13),
                fixedWarpCardTargets: [
                    .fixedWarp: [
                        GridPoint(x: 6, y: 4),
                        GridPoint(x: 7, y: 6)
                    ]
                ],
                cardPickups: [
                    DungeonCardPickupDefinition(
                        id: "warp-2-fixed-warp",
                        point: GridPoint(x: 1, y: 4),
                        card: .fixedWarp
                    ),
                    DungeonCardPickupDefinition(
                        id: "warp-2-right2",
                        point: GridPoint(x: 6, y: 4),
                        card: .straightRight2
                    ),
                    DungeonCardPickupDefinition(
                        id: "warp-2-up2",
                        point: GridPoint(x: 7, y: 4),
                        card: .straightUp2
                    )
                ],
                rewardMoveCardsAfterClear: [
                    .fixedWarp,
                    .rayRight,
                    .diagonalUpRight2
                ]
            ),
            DungeonFloorDefinition(
                id: "warp-3",
                title: "危険な転移先",
                boardSize: standardTowerBoardSize,
                spawnPoint: GridPoint(x: 0, y: 0),
                exitPoint: GridPoint(x: 8, y: 8),
                deckPreset: .standardLight,
                failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 18),
                enemies: [
                    EnemyDefinition(
                        id: "warp-3-watcher",
                        name: "見張り",
                        position: GridPoint(x: 7, y: 6),
                        behavior: .watcher(direction: MoveVector(dx: -1, dy: 0), range: 2)
                    )
                ],
                warpTilePairs: [
                    "warp-3-risk": [
                        GridPoint(x: 1, y: 1),
                        GridPoint(x: 6, y: 6)
                    ]
                ],
                fixedWarpCardTargets: [
                    .fixedWarp: [
                        GridPoint(x: 6, y: 6),
                        GridPoint(x: 8, y: 6)
                    ]
                ],
                cardPickups: [
                    DungeonCardPickupDefinition(
                        id: "warp-3-fixed-warp",
                        point: GridPoint(x: 0, y: 1),
                        card: .fixedWarp
                    ),
                    DungeonCardPickupDefinition(
                        id: "warp-3-up2",
                        point: GridPoint(x: 6, y: 6),
                        card: .straightUp2
                    ),
                    DungeonCardPickupDefinition(
                        id: "warp-3-diagonal-up-right",
                        point: GridPoint(x: 6, y: 7),
                        card: .diagonalUpRight2
                    )
                ]
            )
        ]

        return DungeonDefinition(
            id: "warp-tower",
            title: "ワープ塔",
            summary: "ワープ床と固定ワープカードを読み、遠回りと近道を切り替える低難度の塔。",
            difficulty: .growth,
            floors: floors
        )
    }

    private static func buildTrapTower() -> DungeonDefinition {
        let floors = [
            DungeonFloorDefinition(
                id: "trap-1",
                title: "見える罠",
                boardSize: standardTowerBoardSize,
                spawnPoint: GridPoint(x: 0, y: 0),
                exitPoint: GridPoint(x: 8, y: 8),
                deckPreset: .kingAndKnightBasic,
                failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 18),
                hazards: [
                    .damageTrap(
                        points: [
                            GridPoint(x: 2, y: 2),
                            GridPoint(x: 3, y: 3),
                            GridPoint(x: 4, y: 4),
                            GridPoint(x: 5, y: 5),
                            GridPoint(x: 6, y: 6)
                        ],
                        damage: 1
                    )
                ],
                cardPickups: [
                    DungeonCardPickupDefinition(
                        id: "trap-1-right2",
                        point: GridPoint(x: 1, y: 0),
                        card: .straightRight2
                    ),
                    DungeonCardPickupDefinition(
                        id: "trap-1-up2",
                        point: GridPoint(x: 7, y: 1),
                        card: .straightUp2
                    ),
                    DungeonCardPickupDefinition(
                        id: "trap-1-knight",
                        point: GridPoint(x: 8, y: 3),
                        card: .knightRightwardChoice
                    )
                ],
                rewardMoveCardsAfterClear: [
                    .straightRight2,
                    .straightUp2,
                    .diagonalUpRight2
                ]
            ),
            DungeonFloorDefinition(
                id: "trap-2",
                title: "罠列の抜け道",
                boardSize: standardTowerBoardSize,
                spawnPoint: GridPoint(x: 0, y: 4),
                exitPoint: GridPoint(x: 8, y: 4),
                deckPreset: .standardLight,
                failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 15),
                hazards: [
                    .damageTrap(
                        points: [
                            GridPoint(x: 3, y: 3),
                            GridPoint(x: 3, y: 4),
                            GridPoint(x: 3, y: 5),
                            GridPoint(x: 5, y: 3),
                            GridPoint(x: 5, y: 4),
                            GridPoint(x: 5, y: 5)
                        ],
                        damage: 1
                    )
                ],
                cardPickups: [
                    DungeonCardPickupDefinition(
                        id: "trap-2-ray-right",
                        point: GridPoint(x: 1, y: 4),
                        card: .rayRight
                    ),
                    DungeonCardPickupDefinition(
                        id: "trap-2-up2",
                        point: GridPoint(x: 2, y: 6),
                        card: .straightUp2
                    ),
                    DungeonCardPickupDefinition(
                        id: "trap-2-diagonal-up-right",
                        point: GridPoint(x: 4, y: 2),
                        card: .diagonalUpRight2
                    )
                ],
                rewardMoveCardsAfterClear: [
                    .rayRight,
                    .diagonalUpRight2,
                    .straightUp2
                ]
            ),
            DungeonFloorDefinition(
                id: "trap-3",
                title: "罠と見張り",
                boardSize: standardTowerBoardSize,
                spawnPoint: GridPoint(x: 0, y: 0),
                exitPoint: GridPoint(x: 8, y: 8),
                deckPreset: .standardLight,
                failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 18),
                enemies: [
                    EnemyDefinition(
                        id: "trap-3-watcher",
                        name: "見張り",
                        position: GridPoint(x: 6, y: 5),
                        behavior: .watcher(direction: MoveVector(dx: -1, dy: 0), range: 3)
                    )
                ],
                hazards: [
                    .damageTrap(
                        points: [
                            GridPoint(x: 2, y: 1),
                            GridPoint(x: 3, y: 2),
                            GridPoint(x: 4, y: 3),
                            GridPoint(x: 5, y: 4),
                            GridPoint(x: 6, y: 5),
                            GridPoint(x: 7, y: 6)
                        ],
                        damage: 1
                    )
                ],
                cardPickups: [
                    DungeonCardPickupDefinition(
                        id: "trap-3-right2",
                        point: GridPoint(x: 2, y: 0),
                        card: .straightRight2
                    ),
                    DungeonCardPickupDefinition(
                        id: "trap-3-ray-right",
                        point: GridPoint(x: 0, y: 2),
                        card: .rayRight
                    ),
                    DungeonCardPickupDefinition(
                        id: "trap-3-diagonal-up-right",
                        point: GridPoint(x: 5, y: 6),
                        card: .diagonalUpRight2
                    )
                ]
            )
        ]

        return DungeonDefinition(
            id: "trap-tower",
            title: "罠塔",
            summary: "見えている罠を避けるか、HPを支払って近道するかを読む低難度の塔。",
            difficulty: .growth,
            floors: floors
        )
    }

    private static func buildRoguelikeTower() -> DungeonDefinition {
        let floors = [
            DungeonFloorDefinition(
                id: "rogue-1",
                title: "試練の入口",
                boardSize: standardTowerBoardSize,
                spawnPoint: GridPoint(x: 0, y: 0),
                exitPoint: GridPoint(x: 8, y: 8),
                deckPreset: .standardLight,
                failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 14),
                enemies: [
                    EnemyDefinition(
                        id: "rogue-1-watcher",
                        name: "見張り",
                        position: GridPoint(x: 5, y: 5),
                        behavior: .watcher(direction: MoveVector(dx: -1, dy: 0), range: 3)
                    )
                ],
                hazards: [
                    .damageTrap(
                        points: [
                            GridPoint(x: 3, y: 3),
                            GridPoint(x: 4, y: 4),
                            GridPoint(x: 5, y: 5)
                        ],
                        damage: 1
                    )
                ],
                cardPickups: [
                    DungeonCardPickupDefinition(
                        id: "rogue-1-right2",
                        point: GridPoint(x: 1, y: 0),
                        card: .straightRight2
                    ),
                    DungeonCardPickupDefinition(
                        id: "rogue-1-diagonal-up-right",
                        point: GridPoint(x: 4, y: 0),
                        card: .diagonalUpRight2
                    ),
                    DungeonCardPickupDefinition(
                        id: "rogue-1-up2",
                        point: GridPoint(x: 8, y: 1),
                        card: .straightUp2
                    )
                ],
                rewardMoveCardsAfterClear: [
                    .rayRight,
                    .fixedWarp,
                    .diagonalUpRight2
                ]
            ),
            DungeonFloorDefinition(
                id: "rogue-2",
                title: "罠列と短縮路",
                boardSize: standardTowerBoardSize,
                spawnPoint: GridPoint(x: 0, y: 4),
                exitPoint: GridPoint(x: 8, y: 4),
                deckPreset: .standardLight,
                failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 12),
                enemies: [
                    EnemyDefinition(
                        id: "rogue-2-patrol",
                        name: "巡回兵",
                        position: GridPoint(x: 4, y: 2),
                        behavior: .patrol(path: [
                            GridPoint(x: 4, y: 2),
                            GridPoint(x: 4, y: 3),
                            GridPoint(x: 4, y: 4),
                            GridPoint(x: 4, y: 5),
                            GridPoint(x: 4, y: 4),
                            GridPoint(x: 4, y: 3)
                        ])
                    )
                ],
                hazards: [
                    .damageTrap(
                        points: [
                            GridPoint(x: 3, y: 4),
                            GridPoint(x: 5, y: 4)
                        ],
                        damage: 1
                    ),
                    .brittleFloor(points: [
                        GridPoint(x: 2, y: 5),
                        GridPoint(x: 6, y: 5)
                    ])
                ],
                fixedWarpCardTargets: [
                    .fixedWarp: [
                        GridPoint(x: 6, y: 4),
                        GridPoint(x: 7, y: 6)
                    ]
                ],
                cardPickups: [
                    DungeonCardPickupDefinition(
                        id: "rogue-2-fixed-warp",
                        point: GridPoint(x: 1, y: 4),
                        card: .fixedWarp
                    ),
                    DungeonCardPickupDefinition(
                        id: "rogue-2-right2",
                        point: GridPoint(x: 6, y: 4),
                        card: .straightRight2
                    ),
                    DungeonCardPickupDefinition(
                        id: "rogue-2-up2",
                        point: GridPoint(x: 7, y: 4),
                        card: .straightUp2
                    )
                ],
                rewardMoveCardsAfterClear: [
                    .fixedWarp,
                    .rayUp,
                    .straightRight2
                ]
            ),
            DungeonFloorDefinition(
                id: "rogue-3",
                title: "混成試練",
                boardSize: standardTowerBoardSize,
                spawnPoint: GridPoint(x: 0, y: 0),
                exitPoint: GridPoint(x: 8, y: 8),
                deckPreset: .standardLight,
                failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 16),
                enemies: [
                    EnemyDefinition(
                        id: "rogue-3-watcher",
                        name: "見張り",
                        position: GridPoint(x: 7, y: 6),
                        behavior: .watcher(direction: MoveVector(dx: -1, dy: 0), range: 3)
                    ),
                    EnemyDefinition(
                        id: "rogue-3-patrol",
                        name: "巡回兵",
                        position: GridPoint(x: 3, y: 4),
                        behavior: .patrol(path: [
                            GridPoint(x: 3, y: 4),
                            GridPoint(x: 4, y: 4),
                            GridPoint(x: 5, y: 4),
                            GridPoint(x: 4, y: 4)
                        ])
                    )
                ],
                hazards: [
                    .damageTrap(
                        points: [
                            GridPoint(x: 2, y: 2),
                            GridPoint(x: 4, y: 4),
                            GridPoint(x: 6, y: 6)
                        ],
                        damage: 1
                    ),
                    .brittleFloor(points: [
                        GridPoint(x: 1, y: 2),
                        GridPoint(x: 2, y: 3),
                        GridPoint(x: 3, y: 4)
                    ])
                ],
                warpTilePairs: [
                    "rogue-3-risk": [
                        GridPoint(x: 1, y: 1),
                        GridPoint(x: 6, y: 6)
                    ]
                ],
                fixedWarpCardTargets: [
                    .fixedWarp: [
                        GridPoint(x: 8, y: 6),
                        GridPoint(x: 6, y: 6)
                    ]
                ],
                cardPickups: [
                    DungeonCardPickupDefinition(
                        id: "rogue-3-ray-right",
                        point: GridPoint(x: 0, y: 1),
                        card: .rayRight
                    ),
                    DungeonCardPickupDefinition(
                        id: "rogue-3-fixed-warp",
                        point: GridPoint(x: 2, y: 0),
                        card: .fixedWarp
                    ),
                    DungeonCardPickupDefinition(
                        id: "rogue-3-up2",
                        point: GridPoint(x: 6, y: 6),
                        card: .straightUp2
                    )
                ]
            )
        ]

        return DungeonDefinition(
            id: "rogue-tower",
            title: "試練塔",
            summary: "永続成長を持ち込まず、拾得カードと報酬ビルドだけで罠・敵・ワープを読む高難度プロトタイプ。",
            difficulty: .roguelike,
            floors: floors
        )
    }
}
