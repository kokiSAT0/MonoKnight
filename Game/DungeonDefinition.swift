import Foundation

private let minimumRailPatrolUniquePointCount = 4
private let minimumRailPatrolPathLength = 6
private let minimumLoopRailPatrolUniquePointCount = 6

private func expandedRailPatrolPath(from points: [GridPoint], pathLength: Int) -> [GridPoint] {
    guard points.count > 1 else { return points }
    let bounce = points + points.dropLast().dropFirst().reversed()
    var path: [GridPoint] = []
    while path.count < pathLength {
        path.append(contentsOf: bounce)
    }
    return Array(path.prefix(pathLength))
}

private func isClosedRailPatrolLoop(_ path: [GridPoint]) -> Bool {
    guard path.count >= minimumRailPatrolUniquePointCount,
          Set(path).count == path.count,
          let first = path.first,
          let last = path.last
    else { return false }
    return abs(first.x - last.x) + abs(first.y - last.y) == 1
}

/// 塔ダンジョンの難度と成長持ち込み方針
public enum DungeonDifficulty: String, Codable, Equatable, Sendable {
    /// 操作と基本ルールを学ぶチュートリアル塔
    case tutorial
    /// 永続強化を持ち込める低難度ダンジョン
    case growth
    /// 一時報酬だけで進む中難度ダンジョン
    case tactical
    /// 毎回初期状態から始める高難度ローグライク
    case roguelike
}

/// 塔ラン中に固定される基本移動スタイル
public enum DungeonMovementStyle: String, Codable, CaseIterable, Equatable, Identifiable, Sendable {
    case orthogonal
    case knight

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .orthogonal:
            return "標準騎士"
        case .knight:
            return "跳躍騎士"
        }
    }

    public var summary: String {
        switch self {
        case .orthogonal:
            return "基本移動は上下左右1マス。ナイト系カードで大きく跳ぶ。"
        case .knight:
            return "基本移動はナイト跳び。上下左右1マスカードで位置を整える。"
        }
    }

    public var basicMoveVectors: [MoveVector] {
        switch self {
        case .orthogonal:
            return [
                MoveVector(dx: 0, dy: 1),
                MoveVector(dx: 1, dy: 0),
                MoveVector(dx: 0, dy: -1),
                MoveVector(dx: -1, dy: 0)
            ]
        case .knight:
            return [
                MoveVector(dx: 1, dy: 2),
                MoveVector(dx: -1, dy: 2),
                MoveVector(dx: 2, dy: 1),
                MoveVector(dx: -2, dy: 1),
                MoveVector(dx: 2, dy: -1),
                MoveVector(dx: -2, dy: -1),
                MoveVector(dx: 1, dy: -2),
                MoveVector(dx: -1, dy: -2)
            ]
        }
    }
}

/// 塔ダンジョンでカードを獲得・補充する方式
public enum DungeonCardAcquisitionMode: String, Codable, Equatable, Sendable {
    /// 既存の山札/NEXT/手札補充を使う
    case deck
    /// フロア拾得と報酬だけでカードを所持する
    case inventoryOnly
}

/// 塔ラン中に所持しているカードと残り使用回数
public struct DungeonInventoryEntry: Codable, Equatable, Identifiable, Sendable {
    public let playable: PlayableCard
    /// 残り使用回数。旧保存データの拾得回数もここへ畳み込む。
    public var rewardUses: Int
    /// 旧保存データ互換用。現行ルールでは新規状態を 0 に正規化する。
    public var pickupUses: Int

    public var card: MoveCard {
        guard let move = playable.move else {
            preconditionFailure("補助カードには MoveCard がありません")
        }
        return move
    }

    public var moveCard: MoveCard? { playable.move }
    public var supportCard: SupportCard? { playable.support }

    public init(card: MoveCard, rewardUses: Int = 0, pickupUses: Int = 0) {
        self.playable = .move(card)
        self.rewardUses = Self.normalizedTotalUses(rewardUses: rewardUses, pickupUses: pickupUses)
        self.pickupUses = 0
    }

    public init(support: SupportCard, rewardUses: Int = 0, pickupUses: Int = 0) {
        self.playable = .support(support)
        self.rewardUses = Self.normalizedTotalUses(rewardUses: rewardUses, pickupUses: pickupUses)
        self.pickupUses = 0
    }

    public init(playable: PlayableCard, rewardUses: Int = 0, pickupUses: Int = 0) {
        self.playable = playable
        self.rewardUses = Self.normalizedTotalUses(rewardUses: rewardUses, pickupUses: pickupUses)
        self.pickupUses = 0
    }

    public var id: String { playable.identityText }
    public var totalUses: Int { rewardUses + pickupUses }
    public var hasUsesRemaining: Bool { totalUses > 0 }

    public func carryingRewardUsesOnly() -> DungeonInventoryEntry? {
        carryingAllUsesAsReward()
    }

    public func carryingAllUsesAsReward() -> DungeonInventoryEntry? {
        guard totalUses > 0 else { return nil }
        return DungeonInventoryEntry(playable: playable, rewardUses: totalUses, pickupUses: 0)
    }

    private static func normalizedTotalUses(rewardUses: Int, pickupUses: Int) -> Int {
        max(rewardUses, 0) + max(pickupUses, 0)
    }

    private enum CodingKeys: String, CodingKey {
        case playable
        case card
        case rewardUses
        case pickupUses
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let playable = try container.decodeIfPresent(PlayableCard.self, forKey: .playable) {
            self.playable = playable
        } else {
            self.playable = .move(try container.decode(MoveCard.self, forKey: .card))
        }
        rewardUses = Self.normalizedTotalUses(
            rewardUses: try container.decodeIfPresent(Int.self, forKey: .rewardUses) ?? 0,
            pickupUses: try container.decodeIfPresent(Int.self, forKey: .pickupUses) ?? 0
        )
        pickupUses = 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(playable, forKey: .playable)
        if let move = playable.move {
            try container.encode(move, forKey: .card)
        }
        try container.encode(rewardUses, forKey: .rewardUses)
        try container.encode(pickupUses, forKey: .pickupUses)
    }
}

/// フロアクリア後に選ぶ塔報酬
public enum DungeonRewardSelection: Codable, Equatable, Hashable, Sendable {
    /// 新しい移動報酬カードを追加する
    case add(MoveCard)
    /// 新しい補助報酬カードを追加する
    case addSupport(SupportCard)
    /// 新しい遺物を追加する
    case addRelic(DungeonRelicID)
    /// 試練塔専用。通常カード所持枠をラン中だけ 1 つ増やす。
    case handExpansion
    /// 旧互換用: フロア内で拾って未使用分が残っているカードを報酬カードとして持ち越す
    case carryOverPickup(MoveCard)
    /// 既存の持ち越し報酬カードをランから外す
    case remove(MoveCard)
    /// 既存の持ち越し補助報酬カードをランから外す
    case removeSupport(SupportCard)
}

/// フロア内に配置する拾得カード
public struct DungeonCardPickupDefinition: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let point: GridPoint
    public let playable: PlayableCard
    public let uses: Int

    public init(id: String, point: GridPoint, card: MoveCard, uses: Int = 1) {
        self.init(id: id, point: point, playable: .move(card), uses: uses)
    }

    public init(id: String, point: GridPoint, support: SupportCard, uses: Int = 1) {
        self.init(id: id, point: point, playable: .support(support), uses: uses)
    }

    public init(id: String, point: GridPoint, playable: PlayableCard, uses: Int = 1) {
        self.id = id
        self.point = point
        self.playable = playable
        self.uses = max(uses, 1)
    }

    public var card: MoveCard {
        guard let move = playable.move else {
            preconditionFailure("補助カードには MoveCard がありません")
        }
        return move
    }

    public var moveCard: MoveCard? { playable.move }
    public var supportCard: SupportCard? { playable.support }

    private enum CodingKeys: String, CodingKey {
        case id
        case point
        case playable
        case card
        case uses
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        point = try container.decode(GridPoint.self, forKey: .point)
        if let playable = try container.decodeIfPresent(PlayableCard.self, forKey: .playable) {
            self.playable = playable
        } else {
            self.playable = .move(try container.decode(MoveCard.self, forKey: .card))
        }
        uses = max(try container.decodeIfPresent(Int.self, forKey: .uses) ?? 1, 1)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(point, forKey: .point)
        try container.encode(playable, forKey: .playable)
        if let move = playable.move {
            try container.encode(move, forKey: .card)
        }
        try container.encode(uses, forKey: .uses)
    }
}

/// フロア内に配置する塔専用の非カード拾得アイテム。
public enum DungeonSpecialPickupKind: String, Codable, Equatable, Sendable {
    /// 試練塔専用。通常カード所持枠をラン中だけ 1 つ増やす。
    case handExpansion

    public var displayName: String {
        switch self {
        case .handExpansion:
            return "手札拡張"
        }
    }
}

/// 試練塔の手札拡張がその階でどちらに出るか。
public enum DungeonHandExpansionSpawnSurface: String, Codable, Equatable, Sendable {
    case floorPickup
    case clearReward
}

public struct DungeonSpecialPickupDefinition: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let point: GridPoint
    public let kind: DungeonSpecialPickupKind

    public init(id: String, point: GridPoint, kind: DungeonSpecialPickupKind) {
        self.id = id
        self.point = point
        self.kind = kind
    }
}

/// クリア後に同じ候補枠へ提示する報酬
public enum DungeonRewardOffer: Codable, Equatable, Hashable, Sendable {
    case playable(PlayableCard)
    case relic(DungeonRelicID)
    case handExpansion

    public var playable: PlayableCard? {
        if case .playable(let playable) = self { return playable }
        return nil
    }

    public var move: MoveCard? { playable?.move }
    public var support: SupportCard? { playable?.support }
    public var relic: DungeonRelicID? {
        if case .relic(let relic) = self { return relic }
        return nil
    }
    public var isHandExpansion: Bool {
        if case .handExpansion = self { return true }
        return false
    }

    public var displayName: String {
        switch self {
        case .playable(let playable):
            return playable.displayName
        case .relic(let relic):
            return relic.displayName
        case .handExpansion:
            return DungeonSpecialPickupKind.handExpansion.displayName
        }
    }
}

/// クリア済みフロアへ落下で戻るときに復元する盤面消費状態
public struct DungeonClearedFloorState: Codable, Equatable, Sendable {
    public let visitedPoints: Set<GridPoint>
    public let crackedFloorPoints: Set<GridPoint>
    public let collapsedFloorPoints: Set<GridPoint>
    public let consumedHealingTilePoints: Set<GridPoint>
    public let consumedDamageTrapPoints: Set<GridPoint>
    public let collectedDungeonCardPickupIDs: Set<String>
    public let collectedDungeonSpecialPickupIDs: Set<String>
    public let collectedDungeonRelicPickupIDs: Set<String>
    public let enemyStates: [EnemyState]
    public let isDungeonExitUnlocked: Bool
    public let rewardOffers: [DungeonRewardOffer]
    public let selectedRewardOffers: Set<DungeonRewardOffer>

    public init(
        visitedPoints: Set<GridPoint> = [],
        crackedFloorPoints: Set<GridPoint> = [],
        collapsedFloorPoints: Set<GridPoint> = [],
        consumedHealingTilePoints: Set<GridPoint> = [],
        consumedDamageTrapPoints: Set<GridPoint> = [],
        collectedDungeonCardPickupIDs: Set<String> = [],
        collectedDungeonSpecialPickupIDs: Set<String> = [],
        collectedDungeonRelicPickupIDs: Set<String> = [],
        enemyStates: [EnemyState] = [],
        isDungeonExitUnlocked: Bool = true,
        rewardOffers: [DungeonRewardOffer] = [],
        selectedRewardOffers: Set<DungeonRewardOffer> = []
    ) {
        self.visitedPoints = visitedPoints
        self.crackedFloorPoints = crackedFloorPoints
        self.collapsedFloorPoints = collapsedFloorPoints
        self.consumedHealingTilePoints = consumedHealingTilePoints
        self.consumedDamageTrapPoints = consumedDamageTrapPoints
        self.collectedDungeonCardPickupIDs = collectedDungeonCardPickupIDs
        self.collectedDungeonSpecialPickupIDs = collectedDungeonSpecialPickupIDs
        self.collectedDungeonRelicPickupIDs = collectedDungeonRelicPickupIDs
        self.enemyStates = enemyStates
        self.isDungeonExitUnlocked = isDungeonExitUnlocked
        self.rewardOffers = rewardOffers
        self.selectedRewardOffers = selectedRewardOffers
    }

    public func recordingRewardSelection(
        _ selection: DungeonRewardSelection?,
        currentRewardOffers: [DungeonRewardOffer]
    ) -> DungeonClearedFloorState {
        let offers = rewardOffers.isEmpty ? currentRewardOffers : rewardOffers
        var selectedOffers = selectedRewardOffers
        if let offer = selection?.rewardOffer {
            selectedOffers.insert(offer)
        }
        return DungeonClearedFloorState(
            visitedPoints: visitedPoints,
            crackedFloorPoints: crackedFloorPoints,
            collapsedFloorPoints: collapsedFloorPoints,
            consumedHealingTilePoints: consumedHealingTilePoints,
            consumedDamageTrapPoints: consumedDamageTrapPoints,
            collectedDungeonCardPickupIDs: collectedDungeonCardPickupIDs,
            collectedDungeonSpecialPickupIDs: collectedDungeonSpecialPickupIDs,
            collectedDungeonRelicPickupIDs: collectedDungeonRelicPickupIDs,
            enemyStates: enemyStates,
            isDungeonExitUnlocked: isDungeonExitUnlocked,
            rewardOffers: offers,
            selectedRewardOffers: selectedOffers
        )
    }

    private enum CodingKeys: String, CodingKey {
        case visitedPoints
        case crackedFloorPoints
        case collapsedFloorPoints
        case consumedHealingTilePoints
        case consumedDamageTrapPoints
        case collectedDungeonCardPickupIDs
        case collectedDungeonSpecialPickupIDs
        case collectedDungeonRelicPickupIDs
        case enemyStates
        case isDungeonExitUnlocked
        case rewardOffers
        case selectedRewardOffers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        visitedPoints = try container.decodeIfPresent(Set<GridPoint>.self, forKey: .visitedPoints) ?? []
        crackedFloorPoints = try container.decodeIfPresent(Set<GridPoint>.self, forKey: .crackedFloorPoints) ?? []
        collapsedFloorPoints = try container.decodeIfPresent(Set<GridPoint>.self, forKey: .collapsedFloorPoints) ?? []
        consumedHealingTilePoints = try container.decodeIfPresent(Set<GridPoint>.self, forKey: .consumedHealingTilePoints) ?? []
        consumedDamageTrapPoints = try container.decodeIfPresent(Set<GridPoint>.self, forKey: .consumedDamageTrapPoints) ?? []
        collectedDungeonCardPickupIDs = try container.decodeIfPresent(Set<String>.self, forKey: .collectedDungeonCardPickupIDs) ?? []
        collectedDungeonSpecialPickupIDs = try container.decodeIfPresent(Set<String>.self, forKey: .collectedDungeonSpecialPickupIDs) ?? []
        collectedDungeonRelicPickupIDs = try container.decodeIfPresent(Set<String>.self, forKey: .collectedDungeonRelicPickupIDs) ?? []
        enemyStates = try container.decodeIfPresent([EnemyState].self, forKey: .enemyStates) ?? []
        isDungeonExitUnlocked = try container.decodeIfPresent(Bool.self, forKey: .isDungeonExitUnlocked) ?? true
        rewardOffers = try container.decodeIfPresent([DungeonRewardOffer].self, forKey: .rewardOffers) ?? []
        selectedRewardOffers = try container.decodeIfPresent(Set<DungeonRewardOffer>.self, forKey: .selectedRewardOffers) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(visitedPoints, forKey: .visitedPoints)
        try container.encode(crackedFloorPoints, forKey: .crackedFloorPoints)
        try container.encode(collapsedFloorPoints, forKey: .collapsedFloorPoints)
        try container.encode(consumedHealingTilePoints, forKey: .consumedHealingTilePoints)
        try container.encode(consumedDamageTrapPoints, forKey: .consumedDamageTrapPoints)
        try container.encode(collectedDungeonCardPickupIDs, forKey: .collectedDungeonCardPickupIDs)
        try container.encode(collectedDungeonSpecialPickupIDs, forKey: .collectedDungeonSpecialPickupIDs)
        try container.encode(collectedDungeonRelicPickupIDs, forKey: .collectedDungeonRelicPickupIDs)
        try container.encode(enemyStates, forKey: .enemyStates)
        try container.encode(isDungeonExitUnlocked, forKey: .isDungeonExitUnlocked)
        try container.encode(rewardOffers, forKey: .rewardOffers)
        try container.encode(selectedRewardOffers, forKey: .selectedRewardOffers)
    }
}

extension DungeonRewardSelection {
    public var rewardOffer: DungeonRewardOffer? {
        switch self {
        case .add(let card):
            return .playable(.move(card))
        case .addSupport(let support):
            return .playable(.support(support))
        case .addRelic(let relic):
            return .relic(relic)
        case .handExpansion:
            return .handExpansion
        case .carryOverPickup, .remove, .removeSupport:
            return nil
        }
    }
}

/// 所持枠が満杯のときに床落ちカード取得の解決を待つ状態
public struct PendingDungeonPickupChoice: Codable, Equatable, Sendable {
    /// 拾おうとしている床落ちカード
    public let pickup: DungeonCardPickupDefinition
    /// 実際に追加される使用回数
    public let pickupUses: Int
    /// 代わりに捨てられる現在の所持カード候補
    public let discardCandidates: [DungeonInventoryEntry]

    public init(pickup: DungeonCardPickupDefinition, pickupUses: Int? = nil, discardCandidates: [DungeonInventoryEntry]) {
        self.pickup = pickup
        self.pickupUses = max(pickupUses ?? pickup.uses, 1)
        self.discardCandidates = discardCandidates.filter(\.hasUsesRemaining)
    }

    private enum CodingKeys: String, CodingKey {
        case pickup
        case pickupUses
        case discardCandidates
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let pickup = try container.decode(DungeonCardPickupDefinition.self, forKey: .pickup)
        self.pickup = pickup
        self.pickupUses = max(try container.decodeIfPresent(Int.self, forKey: .pickupUses) ?? pickup.uses, 1)
        self.discardCandidates = try container.decode([DungeonInventoryEntry].self, forKey: .discardCandidates).filter(\.hasUsesRemaining)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pickup, forKey: .pickup)
        try container.encode(pickupUses, forKey: .pickupUses)
        try container.encode(discardCandidates, forKey: .discardCandidates)
    }
}

/// 満杯拾得カードの選択で一時停止している移動の残り処理
public struct PendingDungeonMovementContinuation: Codable, Equatable, Sendable {
    public enum InputKind: String, Codable, Equatable, Sendable {
        case card
        case basic
    }

    public let inputKind: InputKind
    public let playedMoveCard: MoveCard?
    public let remainingPath: [GridPoint]
    public let traversedPath: [GridPoint]
    public let encounteredRevisit: Bool
    public let detectedEffects: [MovementResolution.AppliedEffect]
    public let postMoveTileEffect: TileEffect?
    public let preservesPlayedCard: Bool
    public let initialMarkerDamagePoints: Set<GridPoint>
    public let paralysisTrapPoint: GridPoint?
    public let triggeredPoisonTrap: Bool
    public let previousMoveCount: Int
    public let stopsAtMovementStoppingTiles: Bool

    public init(
        inputKind: InputKind,
        playedMoveCard: MoveCard? = nil,
        remainingPath: [GridPoint],
        traversedPath: [GridPoint],
        encounteredRevisit: Bool,
        detectedEffects: [MovementResolution.AppliedEffect],
        postMoveTileEffect: TileEffect? = nil,
        preservesPlayedCard: Bool,
        initialMarkerDamagePoints: Set<GridPoint>,
        paralysisTrapPoint: GridPoint? = nil,
        triggeredPoisonTrap: Bool,
        previousMoveCount: Int,
        stopsAtMovementStoppingTiles: Bool = true
    ) {
        self.inputKind = inputKind
        self.playedMoveCard = playedMoveCard
        self.remainingPath = remainingPath
        self.traversedPath = traversedPath
        self.encounteredRevisit = encounteredRevisit
        self.detectedEffects = detectedEffects
        self.postMoveTileEffect = postMoveTileEffect
        self.preservesPlayedCard = preservesPlayedCard
        self.initialMarkerDamagePoints = initialMarkerDamagePoints
        self.paralysisTrapPoint = paralysisTrapPoint
        self.triggeredPoisonTrap = triggeredPoisonTrap
        self.previousMoveCount = max(previousMoveCount, 0)
        self.stopsAtMovementStoppingTiles = stopsAtMovementStoppingTiles
    }

    private enum CodingKeys: String, CodingKey {
        case inputKind
        case playedMoveCard
        case remainingPath
        case traversedPath
        case encounteredRevisit
        case detectedEffects
        case postMoveTileEffect
        case preservesPlayedCard
        case initialMarkerDamagePoints
        case paralysisTrapPoint
        case triggeredPoisonTrap
        case previousMoveCount
        case stopsAtMovementStoppingTiles
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputKind = try container.decode(InputKind.self, forKey: .inputKind)
        playedMoveCard = try container.decodeIfPresent(MoveCard.self, forKey: .playedMoveCard)
        remainingPath = try container.decode([GridPoint].self, forKey: .remainingPath)
        traversedPath = try container.decode([GridPoint].self, forKey: .traversedPath)
        encounteredRevisit = try container.decode(Bool.self, forKey: .encounteredRevisit)
        detectedEffects = try container.decode([MovementResolution.AppliedEffect].self, forKey: .detectedEffects)
        postMoveTileEffect = try container.decodeIfPresent(TileEffect.self, forKey: .postMoveTileEffect)
        preservesPlayedCard = try container.decode(Bool.self, forKey: .preservesPlayedCard)
        initialMarkerDamagePoints = try container.decode(Set<GridPoint>.self, forKey: .initialMarkerDamagePoints)
        paralysisTrapPoint = try container.decodeIfPresent(GridPoint.self, forKey: .paralysisTrapPoint)
        triggeredPoisonTrap = try container.decode(Bool.self, forKey: .triggeredPoisonTrap)
        previousMoveCount = max(try container.decode(Int.self, forKey: .previousMoveCount), 0)
        stopsAtMovementStoppingTiles = try container.decodeIfPresent(
            Bool.self,
            forKey: .stopsAtMovementStoppingTiles
        ) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(inputKind, forKey: .inputKind)
        try container.encodeIfPresent(playedMoveCard, forKey: .playedMoveCard)
        try container.encode(remainingPath, forKey: .remainingPath)
        try container.encode(traversedPath, forKey: .traversedPath)
        try container.encode(encounteredRevisit, forKey: .encounteredRevisit)
        try container.encode(detectedEffects, forKey: .detectedEffects)
        try container.encodeIfPresent(postMoveTileEffect, forKey: .postMoveTileEffect)
        try container.encode(preservesPlayedCard, forKey: .preservesPlayedCard)
        try container.encode(initialMarkerDamagePoints, forKey: .initialMarkerDamagePoints)
        try container.encodeIfPresent(paralysisTrapPoint, forKey: .paralysisTrapPoint)
        try container.encode(triggeredPoisonTrap, forKey: .triggeredPoisonTrap)
        try container.encode(previousMoveCount, forKey: .previousMoveCount)
        try container.encode(stopsAtMovementStoppingTiles, forKey: .stopsAtMovementStoppingTiles)
    }
}

/// 怪しい宝箱で提示する選択肢
public struct PendingDungeonRelicPickupChoice: Codable, Equatable, Sendable {
    public enum OptionKind: String, Codable, Equatable, Sendable {
        case stableRelic
        case curseRelic
        case riskyRelicWithDamage
    }

    public struct Option: Codable, Equatable, Identifiable, Sendable {
        public let id: String
        public let title: String
        public let kind: OptionKind
        public let relicID: DungeonRelicID?
        public let curseID: DungeonCurseID?
        public let hpPenalty: Int

        public init(
            id: String,
            title: String,
            kind: OptionKind,
            relicID: DungeonRelicID? = nil,
            curseID: DungeonCurseID? = nil,
            hpPenalty: Int = 0
        ) {
            self.id = id
            self.title = title
            self.kind = kind
            self.relicID = relicID
            self.curseID = curseID
            self.hpPenalty = max(hpPenalty, 0)
        }

        public var previewItems: [DungeonRelicAcquisitionPresentation.Item] {
            var items: [DungeonRelicAcquisitionPresentation.Item] = []
            if let relicID {
                items.append(.relic(DungeonRelicEntry(relicID: relicID)))
            }
            if let curseID {
                items.append(.curse(DungeonCurseEntry(curseID: curseID)))
            }
            if hpPenalty > 0 {
                items.append(.hpPenalty(hpPenalty))
            }
            return items
        }
    }

    public let pickup: DungeonRelicPickupDefinition
    public let options: [Option]

    public init(pickup: DungeonRelicPickupDefinition, options: [Option]) {
        self.pickup = pickup
        self.options = options
    }
}

/// 遺物の希少度。強さと排出率の大枠として扱う。
public enum DungeonRelicRarity: String, Codable, CaseIterable, Equatable, Identifiable, Sendable {
    case common
    case rare
    case legendary

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .common:
            return "コモン"
        case .rare:
            return "レア"
        case .legendary:
            return "レジェンド"
        }
    }

    public var badgeText: String {
        switch self {
        case .common:
            return "C"
        case .rare:
            return "R"
        case .legendary:
            return "L"
        }
    }
}

/// 塔攻略中だけ有効な遺物の種類
public enum DungeonRelicID: String, Codable, CaseIterable, Equatable, Identifiable, Sendable {
    case crackedShield
    case heavyCrown
    case glowingHeart
    case oldMap
    case blackFeather
    case chippedHourglass
    case travelerBoots
    case silverNeedle
    case starCup
    case distantStarCup
    case crackedStarCup
    case explorerBag
    case moonMirror
    case victoryBanner
    case windcutFeather
    case guardianIncense
    case trapperGloves
    case whiteChalk
    case spareTorch
    case oldRope
    case twinPouch
    case gamblerCoin
    case royalCrown
    case immortalHeart
    case guardianAegis
    case stargazerHourglass
    case woodenAmulet
    case copperHourglass
    case travelerRation
    case travelerCanteen
    case moonDewCanteen
    case smallLantern
    case dullNeedle
    case patchedRope
    case fieldMedkit
    case scoutCompass
    case quickSheath
    case purifyingCharm
    case greatPurifyingCharm
    case phoenixFeather
    case sageCodex
    case lavaCharm
    case lavaLantern
    case watcherMask
    case railWedge
    case railSign
    case smokeDecoy
    case chaserWhistle
    case starVeil
    case trapSole
    case emberCloak
    case watcherMonocle
    case railCharm
    case chaserDecoy
    case antidoteStone
    case greaterAntidoteStone
    case starUmbrella
    case guardianCloak
    case fallAnchor
    case foldingMap
    case phantomTicket
    case campfireCoal
    case merchantsScale
    case barrierCharm
    case barrierTalisman
    case frostBell
    case rewindingHourglass
    case slayerPouch
    case hunterBanner
    case intimidationHorn
    case slayerMedal
    case nightCardLens
    case thornScoutLens
    case magmaScoutLens
    case trapScoutLens
    case enemyScoutLens

    public var id: String { rawValue }

    public static let allCases: [DungeonRelicID] = [
        .crackedShield, .heavyCrown, .glowingHeart,
        .blackFeather, .chippedHourglass, .travelerBoots, .silverNeedle,
        .starCup, .distantStarCup, .crackedStarCup, .explorerBag, .moonMirror, .victoryBanner,
        .windcutFeather, .guardianIncense, .trapperGloves, .spareTorch, .oldRope,
        .twinPouch, .gamblerCoin, .royalCrown, .immortalHeart, .guardianAegis,
        .stargazerHourglass, .woodenAmulet, .copperHourglass, .travelerRation,
        .travelerCanteen, .moonDewCanteen, .smallLantern, .dullNeedle, .patchedRope,
        .fieldMedkit, .scoutCompass, .quickSheath, .purifyingCharm, .greatPurifyingCharm, .phoenixFeather,
        .sageCodex, .lavaCharm, .lavaLantern, .watcherMask, .railWedge, .railSign,
        .smokeDecoy, .chaserWhistle, .starVeil, .trapSole, .emberCloak,
        .watcherMonocle, .railCharm, .chaserDecoy, .antidoteStone, .greaterAntidoteStone, .starUmbrella,
        .guardianCloak,
        .fallAnchor, .campfireCoal, .merchantsScale,
        .barrierCharm, .barrierTalisman, .frostBell, .rewindingHourglass,
        .slayerPouch, .hunterBanner, .intimidationHorn, .slayerMedal,
        .nightCardLens, .thornScoutLens, .magmaScoutLens, .trapScoutLens, .enemyScoutLens
    ]

    public static var newAcquisitionCases: [DungeonRelicID] {
        allCases.filter(\.isAvailableForNewAcquisition)
    }

    public var isAvailableForNewAcquisition: Bool {
        switch self {
        case .oldMap, .whiteChalk, .windcutFeather, .quickSheath:
            return false
        default:
            return true
        }
    }

    var isRemovedFromCurrentRules: Bool {
        switch self {
        case .foldingMap, .phantomTicket:
            return true
        default:
            return false
        }
    }

    public var encyclopediaDiscoveryID: EncyclopediaDiscoveryID {
        EncyclopediaDiscoveryID(category: .relic, itemID: rawValue)
    }

    public var displayName: String {
        switch self {
        case .crackedShield:
            return "割れた盾"
        case .heavyCrown:
            return "重い王冠"
        case .glowingHeart:
            return "灯る心臓"
        case .oldMap:
            return "古い地図"
        case .blackFeather:
            return "黒い羽根"
        case .chippedHourglass:
            return "欠けた砂時計"
        case .travelerBoots:
            return "旅人の靴"
        case .silverNeedle:
            return "銀の針"
        case .starCup:
            return "星の杯"
        case .distantStarCup:
            return "遠星の杯"
        case .crackedStarCup:
            return "欠け星の杯"
        case .explorerBag:
            return "探索者の袋"
        case .moonMirror:
            return "月の鏡"
        case .victoryBanner:
            return "勝利の旗"
        case .windcutFeather:
            return "風切りの羽根"
        case .guardianIncense:
            return "守りの香炉"
        case .trapperGloves:
            return "罠師の手袋"
        case .whiteChalk:
            return "白いチョーク"
        case .spareTorch:
            return "予備のたいまつ"
        case .oldRope:
            return "古びたロープ"
        case .twinPouch:
            return "双子の小袋"
        case .gamblerCoin:
            return "勝負師のコイン"
        case .royalCrown:
            return "王家の宝冠"
        case .immortalHeart:
            return "不滅の心臓"
        case .guardianAegis:
            return "守護者の大盾"
        case .stargazerHourglass:
            return "星詠みの砂時計"
        case .woodenAmulet:
            return "木彫りの護符"
        case .copperHourglass:
            return "銅の砂時計"
        case .travelerRation:
            return "旅の保存食"
        case .travelerCanteen:
            return "旅の水筒"
        case .moonDewCanteen:
            return "月露の水筒"
        case .smallLantern:
            return "小さなランタン"
        case .dullNeedle:
            return "鈍い針"
        case .patchedRope:
            return "継ぎ接ぎロープ"
        case .fieldMedkit:
            return "野戦医療箱"
        case .scoutCompass:
            return "斥候の羅針盤"
        case .quickSheath:
            return "早業の鞘"
        case .purifyingCharm:
            return "清めの護符"
        case .greatPurifyingCharm:
            return "清めの大護符"
        case .phoenixFeather:
            return "不死鳥の羽根"
        case .sageCodex:
            return "賢者の写本"
        case .lavaCharm:
            return "火消しの札"
        case .lavaLantern:
            return "耐火ランタン"
        case .watcherMask:
            return "見張り除けの面"
        case .railWedge:
            return "レール止めの楔"
        case .railSign:
            return "レール守りの標識"
        case .smokeDecoy:
            return "追跡避けの煙玉"
        case .chaserWhistle:
            return "追跡封じの笛"
        case .starVeil:
            return "星隠しの布"
        case .trapSole:
            return "罠踏みの靴底"
        case .emberCloak:
            return "残り火の外套"
        case .watcherMonocle:
            return "見張りの単眼鏡"
        case .railCharm:
            return "レール守りの護符"
        case .chaserDecoy:
            return "追跡避けの囮"
        case .antidoteStone:
            return "解毒石"
        case .greaterAntidoteStone:
            return "解毒の霊石"
        case .starUmbrella:
            return "星除けの傘"
        case .guardianCloak:
            return "守護者の外套"
        case .fallAnchor:
            return "落下止めの錨"
        case .foldingMap, .phantomTicket:
            return "削除済みレリック"
        case .campfireCoal:
            return "焚き火の熾火"
        case .merchantsScale:
            return "商人の天秤"
        case .barrierCharm:
            return "護りの小札"
        case .barrierTalisman:
            return "護りの札"
        case .frostBell:
            return "霜の鈴"
        case .rewindingHourglass:
            return "逆巻きの砂時計"
        case .slayerPouch:
            return "討伐の小袋"
        case .hunterBanner:
            return "狩人の旗"
        case .intimidationHorn:
            return "威圧の角笛"
        case .slayerMedal:
            return "討伐者の勲章"
        case .nightCardLens:
            return "拾い火のレンズ"
        case .thornScoutLens:
            return "撒菱読みのレンズ"
        case .magmaScoutLens:
            return "溶岩読みのレンズ"
        case .trapScoutLens:
            return "罠読みのレンズ"
        case .enemyScoutLens:
            return "影読みのレンズ"
        }
    }

    public var effectDescription: String {
        switch self {
        case .crackedShield:
            return "次に受けるダメージを1回だけ1軽減する。"
        case .heavyCrown:
            return "移動報酬カードを新しく得る時、使用回数が+1される。"
        case .glowingHeart:
            return "取得時にHPが2増える。"
        case .oldMap:
            return "未取得の拾得カードを盤面で見つけやすくする。"
        case .blackFeather:
            return "次に受ける落下HP減少を1回だけ無効化する。"
        case .chippedHourglass:
            return "各フロアの手数上限が+3される。"
        case .travelerBoots:
            return "各フロアの手数上限が+1される。"
        case .silverNeedle:
            return "次に受ける罠ダメージを1回だけ無効化する。"
        case .starCup:
            return "取得後から2フロアごとのフロア開始時にHPが1増える。"
        case .distantStarCup:
            return "取得後から3フロアごとのフロア開始時にHPが1増える。"
        case .crackedStarCup:
            return "取得後から5フロアごとのフロア開始時にHPが1増える。"
        case .explorerBag:
            return "拾得カードの取得時使用回数が+1される。"
        case .moonMirror:
            return "次に呪い遺物を得る時、1回だけ無効化して通常遺物に変える。"
        case .victoryBanner:
            return "クリア報酬のレリック出現率が2pt上がる。"
        case .windcutFeather:
            return "旧効果のレリック。現在は新しく出現せず、使用回数補正も発生しない。"
        case .guardianIncense:
            return "各フロアで最初に受ける見張り・回転見張りダメージを1回だけ無効化する。"
        case .trapperGloves:
            return "罠でダメージまたは状態異常を受けた時、次のクリア報酬の補助カード出現率が5pt上がる。"
        case .whiteChalk:
            return "暗闇フロアで、未取得の拾得カードを1枚だけ見つけやすくする。"
        case .spareTorch:
            return "暗闇フロアで見える範囲が周囲2マスに広がる。"
        case .oldRope:
            return "落下で前の階へ戻る時、HP減少を1回だけ無効化する。"
        case .twinPouch:
            return "補助報酬カードを新しく得る時、使用回数が+1される。"
        case .gamblerCoin:
            return "手数上限の半分以内にクリアすると、クリア報酬のレリック出現率が2pt上がる。"
        case .royalCrown:
            return "クリア報酬のレリック出現率が2pt上がり、新しく得る報酬カードの使用回数が+1される。"
        case .immortalHeart:
            return "各フロア開始時にHPが1増える。"
        case .guardianAegis:
            return "各フロアで最初に受けるメテオ兵ダメージを1回だけ無効化する。"
        case .stargazerHourglass:
            return "各フロアの手数上限が+5される。"
        case .woodenAmulet:
            return "取得時にHPが1増える。"
        case .copperHourglass:
            return "各フロアの手数上限が+2される。"
        case .travelerRation:
            return "各フロア開始時、HPが2以下ならHPが1増える。"
        case .travelerCanteen:
            return "次の3フロア開始時にHPが1増える。"
        case .moonDewCanteen:
            return "次の5フロア開始時にHPが1増える。"
        case .smallLantern:
            return "暗闇フロアで見える範囲が少し広がる。"
        case .dullNeedle:
            return "各フロアで最初に受ける罠ダメージを1回だけ無効化する。"
        case .patchedRope:
            return "各フロアで最初に受ける落下HP減少を1回だけ無効化する。"
        case .fieldMedkit:
            return "回復マスの回復量が+1される。"
        case .scoutCompass:
            return "70%以内にクリアすると、クリア報酬の補助カード出現率が5pt上がる。"
        case .quickSheath:
            return "旧効果のレリック。現在は新しく出現せず、使用回数補正も発生しない。"
        case .purifyingCharm:
            return "次に受ける状態異常を1回だけ無効化する。"
        case .greatPurifyingCharm:
            return "次に受ける状態異常を2回まで無効化する。"
        case .phoenixFeather:
            return "HPが0になるダメージを1回だけHP1で耐える。"
        case .sageCodex:
            return "新しく得る拾得カード、移動報酬カード、補助報酬カードの使用回数が+1される。"
        case .lavaCharm:
            return "次に受ける溶岩ダメージを1回だけ無効化する。"
        case .lavaLantern:
            return "各フロアで最初に受ける溶岩ダメージを1回だけ無効化する。"
        case .watcherMask:
            return "次に受ける見張り・回転見張りダメージを1回だけ無効化する。"
        case .railWedge:
            return "次に受ける巡回兵ダメージを1回だけ無効化する。"
        case .railSign:
            return "各フロアで最初に受ける巡回兵ダメージを1回だけ無効化する。"
        case .smokeDecoy:
            return "次に受ける追跡兵ダメージを1回だけ無効化する。"
        case .chaserWhistle:
            return "各フロアで最初に受ける追跡兵ダメージを1回だけ無効化する。"
        case .starVeil:
            return "次に受けるメテオ兵ダメージを1回だけ無効化する。"
        case .trapSole:
            return "撒菱から受けるHPダメージを常に1軽減する。"
        case .emberCloak:
            return "溶岩から受けるHPダメージを常に1軽減する。"
        case .watcherMonocle:
            return "見張りと回転見張りから受けるHPダメージを1軽減する。"
        case .railCharm:
            return "巡回兵から受けるHPダメージを1軽減する。"
        case .chaserDecoy:
            return "追跡兵から受けるHPダメージを1軽減する。"
        case .antidoteStone:
            return "毒罠の毒ダメージ回数を1減らす。最低1回。"
        case .greaterAntidoteStone:
            return "毒罠の毒ダメージ回数を2減らす。最低1回。"
        case .starUmbrella:
            return "メテオと標的警告から受けるHPダメージを1軽減する。"
        case .guardianCloak:
            return "敵とメテオから受けるHPダメージを1軽減する。同じダメージ源では他の軽減レリックと重複しない。"
        case .fallAnchor:
            return "崩落穴で受ける落下HP減少を常に1軽減する。"
        case .foldingMap, .phantomTicket:
            return "現在は削除済みのレリックです。"
        case .campfireCoal:
            return "回復マスを踏んだ時、毒、足枷、幻惑を解除する。"
        case .merchantsScale:
            return "クリア報酬でレリックを選んだ時、次階開始HPが1増える。"
        case .barrierCharm:
            return "各フロア開始時、次の1行動後処理までHPダメージを無効化する。"
        case .barrierTalisman:
            return "各フロア開始時、次の2行動後処理までHPダメージを無効化する。"
        case .frostBell:
            return "各フロア開始時、最初の敵ターンを1回停止する。"
        case .rewindingHourglass:
            return "HPが0になる時、1回だけ過去のランダムな階層でHP1から復活する。"
        case .slayerPouch:
            return "その階で敵を1体倒すたび、クリア報酬の補助カード出現率が3pt上がる。"
        case .hunterBanner:
            return "その階で敵を1体倒すたび、クリア報酬のレリック出現率が1pt上がる。"
        case .intimidationHorn:
            return "敵を倒した行動後、敵が残っていれば敵ターンを1回停止する。"
        case .slayerMedal:
            return "取得後、敵を10体倒すごとに未所持のコモンレリックを1つ得る。"
        case .nightCardLens:
            return "暗闇フロアで未取得の拾得カードが常に見える。"
        case .thornScoutLens:
            return "暗闇フロアで撒菱が常に見える。"
        case .magmaScoutLens:
            return "暗闇フロアで溶岩が常に見える。"
        case .trapScoutLens:
            return "暗闇フロアで隠し罠が常に見える。"
        case .enemyScoutLens:
            return "暗闇フロアで全ての敵が常に見える。"
        }
    }

    public var noteDescription: String? {
        switch self {
        case .crackedShield, .heavyCrown, .glowingHeart, .oldMap, .blackFeather,
             .travelerBoots, .silverNeedle, .starCup, .distantStarCup, .crackedStarCup,
             .explorerBag, .moonMirror, .victoryBanner,
             .windcutFeather, .guardianIncense, .trapperGloves, .whiteChalk, .spareTorch,
             .oldRope, .twinPouch, .gamblerCoin, .royalCrown, .immortalHeart, .guardianAegis,
             .woodenAmulet, .travelerRation, .travelerCanteen, .moonDewCanteen,
             .smallLantern, .dullNeedle, .patchedRope,
             .fieldMedkit, .scoutCompass, .quickSheath, .phoenixFeather, .sageCodex,
             .lavaCharm, .lavaLantern, .watcherMask, .railWedge, .railSign, .smokeDecoy,
             .chaserWhistle, .starVeil,
             .trapSole, .emberCloak, .watcherMonocle, .railCharm, .chaserDecoy,
             .antidoteStone, .greaterAntidoteStone, .starUmbrella, .guardianCloak, .fallAnchor, .foldingMap, .phantomTicket,
             .campfireCoal, .merchantsScale,
             .barrierCharm, .barrierTalisman, .frostBell, .rewindingHourglass,
             .slayerPouch, .hunterBanner, .intimidationHorn, .slayerMedal,
             .nightCardLens, .thornScoutLens, .magmaScoutLens, .trapScoutLens, .enemyScoutLens:
            return nil
        case .chippedHourglass, .stargazerHourglass, .copperHourglass:
            return "新規報酬カードの使用回数補正は通常どおり。"
        case .purifyingCharm, .greatPurifyingCharm:
            return "毒、麻痺、足枷、幻惑、手札喪失系の罠に反応する。"
        }
    }

    public var rarity: DungeonRelicRarity {
        switch self {
        case .crackedShield, .heavyCrown, .glowingHeart, .oldMap, .travelerBoots, .silverNeedle, .whiteChalk, .oldRope,
             .woodenAmulet, .copperHourglass, .travelerRation, .travelerCanteen,
             .crackedStarCup, .smallLantern, .dullNeedle, .patchedRope,
             .lavaCharm, .lavaLantern, .trapSole, .emberCloak, .campfireCoal,
             .slayerPouch, .nightCardLens, .thornScoutLens, .magmaScoutLens,
             .purifyingCharm, .antidoteStone:
            return .common
        case .blackFeather, .chippedHourglass, .starCup, .distantStarCup, .explorerBag,
             .windcutFeather, .guardianIncense, .trapperGloves, .spareTorch,
             .fieldMedkit, .scoutCompass, .quickSheath, .greatPurifyingCharm, .moonDewCanteen,
             .watcherMask, .railWedge, .railSign, .smokeDecoy, .chaserWhistle,
             .watcherMonocle, .railCharm, .chaserDecoy, .greaterAntidoteStone, .starUmbrella,
             .foldingMap, .phantomTicket, .barrierCharm, .frostBell, .hunterBanner, .intimidationHorn, .slayerMedal,
             .trapScoutLens, .enemyScoutLens:
            return .rare
        case .moonMirror, .victoryBanner, .royalCrown, .immortalHeart, .guardianAegis, .stargazerHourglass,
             .twinPouch, .gamblerCoin, .phoenixFeather, .sageCodex, .starVeil, .guardianCloak, .fallAnchor, .merchantsScale,
             .barrierTalisman, .rewindingHourglass:
            return .legendary
        }
    }

    public var symbolName: String {
        switch self {
        case .crackedShield:
            return "shield.lefthalf.filled"
        case .heavyCrown:
            return "crown.fill"
        case .glowingHeart:
            return "heart.fill"
        case .oldMap:
            return "map.fill"
        case .blackFeather:
            return "leaf.fill"
        case .chippedHourglass:
            return "hourglass"
        case .travelerBoots:
            return "shoeprints.fill"
        case .silverNeedle:
            return "pin.fill"
        case .starCup:
            return "star.fill"
        case .distantStarCup:
            return "sparkles"
        case .crackedStarCup:
            return "star"
        case .explorerBag:
            return "bag.fill"
        case .moonMirror:
            return "moon.fill"
        case .victoryBanner:
            return "flag.fill"
        case .windcutFeather:
            return "wind"
        case .guardianIncense:
            return "smoke.fill"
        case .trapperGloves:
            return "hand.raised.fill"
        case .whiteChalk:
            return "pencil.and.scribble"
        case .spareTorch:
            return "flame.fill"
        case .oldRope:
            return "point.3.connected.trianglepath.dotted"
        case .twinPouch:
            return "shippingbox.fill"
        case .gamblerCoin:
            return "circle.lefthalf.filled"
        case .royalCrown:
            return "crown.fill"
        case .immortalHeart:
            return "heart.circle.fill"
        case .guardianAegis:
            return "shield.fill"
        case .stargazerHourglass:
            return "hourglass.badge.plus"
        case .woodenAmulet:
            return "leaf.circle.fill"
        case .copperHourglass:
            return "hourglass"
        case .travelerRation:
            return "takeoutbag.and.cup.and.straw.fill"
        case .travelerCanteen:
            return "drop.fill"
        case .moonDewCanteen:
            return "drop.circle.fill"
        case .smallLantern:
            return "lightbulb.fill"
        case .dullNeedle:
            return "pin"
        case .patchedRope:
            return "point.3.connected.trianglepath.dotted"
        case .fieldMedkit:
            return "cross.case.fill"
        case .scoutCompass:
            return "safari.fill"
        case .quickSheath:
            return "bolt.fill"
        case .purifyingCharm:
            return "sparkles"
        case .greatPurifyingCharm:
            return "sparkles"
        case .phoenixFeather:
            return "flame.circle.fill"
        case .sageCodex:
            return "book.closed.fill"
        case .lavaCharm:
            return "flame.slash.fill"
        case .lavaLantern:
            return "lamp.desk.fill"
        case .watcherMask:
            return "theatermasks.fill"
        case .railWedge:
            return "wrench.adjustable.fill"
        case .railSign:
            return "signpost.right.fill"
        case .smokeDecoy:
            return "smoke.fill"
        case .chaserWhistle:
            return "speaker.wave.2.fill"
        case .starVeil:
            return "sparkle.magnifyingglass"
        case .trapSole:
            return "shoeprints.fill"
        case .emberCloak:
            return "flame.fill"
        case .watcherMonocle:
            return "eyeglasses"
        case .railCharm:
            return "tram.fill"
        case .chaserDecoy:
            return "figure.walk.motion"
        case .antidoteStone:
            return "pills.fill"
        case .greaterAntidoteStone:
            return "pills.fill"
        case .starUmbrella:
            return "umbrella.fill"
        case .guardianCloak:
            return "shield.checkered"
        case .fallAnchor:
            return "anchor"
        case .foldingMap, .phantomTicket:
            return "xmark.circle"
        case .campfireCoal:
            return "flame.circle"
        case .merchantsScale:
            return "scale.3d"
        case .barrierCharm:
            return "shield"
        case .barrierTalisman:
            return "shield.righthalf.filled"
        case .frostBell:
            return "bell.fill"
        case .rewindingHourglass:
            return "hourglass.circle.fill"
        case .slayerPouch:
            return "bag.fill"
        case .hunterBanner:
            return "flag.checkered"
        case .intimidationHorn:
            return "megaphone.fill"
        case .slayerMedal:
            return "medal.fill"
        case .nightCardLens:
            return "doc.text.magnifyingglass"
        case .thornScoutLens:
            return "exclamationmark.triangle.fill"
        case .magmaScoutLens:
            return "flame.fill"
        case .trapScoutLens:
            return "scope"
        case .enemyScoutLens:
            return "eye.fill"
        }
    }

    public var startingUses: Int {
        switch self {
        case .crackedShield, .blackFeather, .silverNeedle, .moonMirror, .guardianIncense, .oldRope, .guardianAegis,
             .dullNeedle, .patchedRope, .purifyingCharm, .phoenixFeather,
             .lavaCharm, .lavaLantern, .watcherMask, .railWedge, .railSign, .smokeDecoy, .chaserWhistle, .starVeil,
             .rewindingHourglass:
            return 1
        case .trapperGloves, .greatPurifyingCharm:
            return 2
        case .travelerCanteen:
            return 3
        case .moonDewCanteen:
            return 5
        case .heavyCrown, .glowingHeart, .oldMap, .chippedHourglass,
             .travelerBoots, .starCup, .distantStarCup, .crackedStarCup, .explorerBag, .victoryBanner,
             .windcutFeather, .whiteChalk, .spareTorch, .twinPouch, .gamblerCoin,
             .royalCrown, .immortalHeart, .stargazerHourglass,
             .woodenAmulet, .copperHourglass, .travelerRation, .smallLantern,
             .fieldMedkit, .scoutCompass, .quickSheath, .sageCodex,
             .trapSole, .emberCloak, .watcherMonocle, .railCharm, .chaserDecoy,
             .antidoteStone, .greaterAntidoteStone, .starUmbrella, .guardianCloak, .fallAnchor, .foldingMap, .phantomTicket,
             .campfireCoal, .merchantsScale, .barrierCharm, .barrierTalisman, .frostBell,
             .slayerPouch, .hunterBanner, .intimidationHorn, .slayerMedal,
             .nightCardLens, .thornScoutLens, .magmaScoutLens, .trapScoutLens, .enemyScoutLens:
            return 0
        }
    }

    public var floorStartDamageBarrierTurns: Int {
        switch self {
        case .barrierCharm:
            return 1
        case .barrierTalisman:
            return 2
        default:
            return 0
        }
    }

    public var floorStartEnemyFreezeTurns: Int {
        switch self {
        case .frostBell:
            return 1
        default:
            return 0
        }
    }

    public var floorStartHealingInterval: Int? {
        switch self {
        case .starCup:
            return 2
        case .distantStarCup:
            return 3
        case .crackedStarCup:
            return 5
        default:
            return nil
        }
    }

    public var healsAtFloorStartForLimitedUses: Bool {
        switch self {
        case .travelerCanteen, .moonDewCanteen:
            return true
        default:
            return false
        }
    }

    public var refillsUseAtFloorStart: Bool {
        switch self {
        case .dullNeedle, .lavaLantern, .patchedRope, .guardianIncense, .railSign, .chaserWhistle, .guardianAegis:
            return true
        default:
            return false
        }
    }

    public var displayKind: DungeonRelicDisplayKind {
        startingUses > 0 ? .temporary : .persistent
    }
}

public enum DungeonRelicDisplayKind: Equatable, Sendable {
    case temporary
    case persistent
}

/// ヘルプ内の遺物辞典で表示する 1 件分の情報
public struct DungeonRelicEncyclopediaEntry: Identifiable, Equatable, Sendable {
    public let relicID: DungeonRelicID

    public var id: String { relicID.id }
    public var displayName: String { relicID.displayName }
    public var effectDescription: String { relicID.effectDescription }
    public var noteDescription: String? { relicID.noteDescription }
    public var symbolName: String { relicID.symbolName }
    public var displayKind: DungeonRelicDisplayKind { relicID.displayKind }
    public var rarity: DungeonRelicRarity { relicID.rarity }
    public var encyclopediaDiscoveryID: EncyclopediaDiscoveryID { relicID.encyclopediaDiscoveryID }

    public init(relicID: DungeonRelicID) {
        self.relicID = relicID
    }

    public static let allEntries: [DungeonRelicEncyclopediaEntry] = DungeonRelicID.allCases.map {
        DungeonRelicEncyclopediaEntry(relicID: $0)
    }
}

/// 塔攻略中だけ有効な呪い遺物の種類
public enum DungeonCurseID: String, Codable, CaseIterable, Equatable, Identifiable, Sendable {
    case rustyChain
    case thornMark
    case bloodPact
    case cursedCrown
    case obsidianHeart
    case warpedHourglass
    case redChalice
    case greedyBag
    case crackedCompass
    case heavyBell
    case cloudedMirror
    case crackedShoes
    case watchersBrand
    case patrolBell
    case chaserScent
    case meteorRod
    case trapMagnet
    case oilSoakedBoots
    case glassAnklet
    case poisonVial
    case ironShackle
    case foolsMask
    case frayedMemory
    case wetTinder
    case laughingDoor
    case upsideDownKey
    case taxCollector
    case flickeringCampfire
    case contractCodex
    case royalIou
    case bottomlessPack
    case relicHunterBrand
    case supportOath
    case ashHeart
    case hasteArmor
    case scorchedCloak
    case lastStandShield
    case firewalkingTalisman
    case tinkersToolbox
    case expressTicket
    case ploverContract
    case quartermasterBell
    case sleepingWarDrum
    case swarmcallingTalisman
    case gildedSeal

    public var id: String { rawValue }

    public static let newAcquisitionCases: [DungeonCurseID] = [
        .chaserScent, .firewalkingTalisman, .flickeringCampfire, .tinkersToolbox,
        .expressTicket, .ploverContract, .redChalice, .warpedHourglass,
        .contractCodex, .royalIou, .lastStandShield, .quartermasterBell,
        .sleepingWarDrum, .swarmcallingTalisman, .gildedSeal
    ]

    public var encyclopediaDiscoveryID: EncyclopediaDiscoveryID {
        EncyclopediaDiscoveryID(category: .curse, itemID: rawValue)
    }

    public var displayName: String {
        switch self {
        case .rustyChain:
            return "錆びた鎖"
        case .thornMark:
            return "棘の印"
        case .bloodPact:
            return "血の契約"
        case .cursedCrown:
            return "呪われた王冠"
        case .obsidianHeart:
            return "黒曜の心臓"
        case .warpedHourglass:
            return "歪んだ砂時計"
        case .redChalice:
            return "赤い杯"
        case .greedyBag:
            return "欲深い袋"
        case .crackedCompass:
            return "割れた羅針盤"
        case .heavyBell:
            return "重い鐘"
        case .cloudedMirror:
            return "曇った鏡"
        case .crackedShoes:
            return "割れた靴"
        case .watchersBrand:
            return "見張りの焼印"
        case .patrolBell:
            return "巡回の鈴"
        case .chaserScent:
            return "追跡の匂い袋"
        case .meteorRod:
            return "流星の避雷針"
        case .trapMagnet:
            return "罠寄せの磁石"
        case .oilSoakedBoots:
            return "油染みの靴"
        case .glassAnklet:
            return "硝子の足環"
        case .poisonVial:
            return "毒見の小瓶"
        case .ironShackle:
            return "鉄の足枷飾り"
        case .foolsMask:
            return "愚者の仮面"
        case .frayedMemory:
            return "ほつれた記憶"
        case .wetTinder:
            return "湿った火口"
        case .laughingDoor:
            return "笑う扉"
        case .upsideDownKey:
            return "逆さ鍵"
        case .taxCollector:
            return "取り立て人"
        case .flickeringCampfire:
            return "揺らぐ焚き火"
        case .contractCodex:
            return "契約の写本"
        case .royalIou:
            return "王家の借用書"
        case .bottomlessPack:
            return "底なしの背嚢"
        case .relicHunterBrand:
            return "遺物狩りの焼印"
        case .supportOath:
            return "支援の誓約"
        case .ashHeart:
            return "灰の心臓"
        case .hasteArmor:
            return "駆け足の鎧"
        case .scorchedCloak:
            return "焦げた外套"
        case .lastStandShield:
            return "背水の大盾"
        case .firewalkingTalisman:
            return "火渡りの札"
        case .tinkersToolbox:
            return "細工師の工具箱"
        case .expressTicket:
            return "急行切符"
        case .ploverContract:
            return "千鳥の契約"
        case .quartermasterBell:
            return "補給係の鈴"
        case .sleepingWarDrum:
            return "眠りの軍太鼓"
        case .swarmcallingTalisman:
            return "群れ呼びの護符"
        case .gildedSeal:
            return "黄金の封蝋"
        }
    }

    public var upsideDescription: String {
        switch self {
        case .rustyChain:
            return "取得時にHPが1増える。"
        case .thornMark:
            return "取得時にHPが1増える。"
        case .bloodPact:
            return "取得時にHPが2増える。"
        case .cursedCrown:
            return "新しく得る報酬カードの使用回数が+3される。"
        case .obsidianHeart:
            return "取得時にHPが6増える。"
        case .warpedHourglass:
            return "クリア報酬に補助カードが必ず1つ以上出現する。"
        case .redChalice:
            return "取得時にHPが8増える。"
        case .greedyBag:
            return "拾得カードの取得時使用回数が+4される。"
        case .crackedCompass:
            return "クリア報酬の補助カード出現率が5pt上がる。"
        case .heavyBell:
            return "取得時にHPが2増える。"
        case .cloudedMirror:
            return "クリア報酬の補助カード出現率が5pt上がる。"
        case .crackedShoes:
            return "取得時にHPが3増える。"
        case .watchersBrand:
            return "取得時にHPが2増える。"
        case .patrolBell:
            return "クリア報酬の補助カード出現率が5pt上がる。"
        case .chaserScent:
            return "追跡兵がいる階では、床に落ちているカードの配置数が3倍になる。"
        case .meteorRod:
            return "取得時にHPが3増える。"
        case .trapMagnet:
            return "新しく得る報酬カードの使用回数が+2される。"
        case .oilSoakedBoots:
            return "各フロアの手数上限が+3される。"
        case .glassAnklet:
            return "取得時にHPが2増える。"
        case .poisonVial:
            return "拾得カードの取得時使用回数が+2される。"
        case .ironShackle:
            return "取得時にHPが3増える。"
        case .foolsMask:
            return "クリア報酬の補助カード出現率が5pt上がる。"
        case .frayedMemory:
            return "補助報酬カードの使用回数が+1される。"
        case .wetTinder:
            return "取得時にHPが2増える。"
        case .laughingDoor:
            return "クリア報酬の補助カード出現率が5pt上がる。"
        case .upsideDownKey:
            return "鍵を拾って出口を開けると、クリア報酬の補助カード出現率が5pt上がる。"
        case .taxCollector:
            return "クリア報酬の補助カード出現率が5pt上がる。"
        case .flickeringCampfire:
            return "回復マスの回復量が+3される。"
        case .contractCodex:
            return "新しく得る拾得カード、移動報酬カード、補助報酬カードの使用回数が+3される。"
        case .royalIou:
            return "クリア報酬の補助カード出現率が10pt上がり、新しく得る報酬カードの使用回数が+2される。"
        case .bottomlessPack:
            return "拾得カードの取得時使用回数が+5される。"
        case .relicHunterBrand:
            return "手数上限の半分以内にクリアすると、クリア報酬のレリック出現率が5pt上がる。"
        case .supportOath:
            return "補助報酬カードを新しく得る時、使用回数が+3される。"
        case .ashHeart:
            return "各フロア開始時にHPが2増える。"
        case .hasteArmor:
            return "敵とメテオから受けるHPダメージが1減る。"
        case .scorchedCloak:
            return "罠、溶岩、崩落穴から受けるHPダメージが1減る。"
        case .lastStandShield:
            return "各フロア最初に受けるHPダメージが3減る。"
        case .firewalkingTalisman:
            return "その階で溶岩を踏んでクリアすると、クリア報酬の補助カード出現率が10pt上がる。"
        case .tinkersToolbox:
            return "既に所持している移動/補助カードが、クリア報酬に出やすくなる。"
        case .expressTicket:
            return "手数上限の半分以内でクリアすると、次階開始時にHPが3増える。"
        case .ploverContract:
            return "手札スロットが1つ増える。最大10枠。"
        case .quartermasterBell:
            return "フロア開始時、空き手札枠へ補充カードと同じ移動カード補給を行う。"
        case .sleepingWarDrum:
            return "敵ターンが2ターンに1回だけ進む。"
        case .swarmcallingTalisman:
            return "フロア開始時に3ターン分の障壁を得る。"
        case .gildedSeal:
            return "レリック報酬と宝箱の通常遺物候補がレア以上になる。"
        }
    }

    public var downsideDescription: String {
        switch self {
        case .rustyChain:
            return "各フロアの手数上限が-2される。"
        case .thornMark:
            return "次に受けるダメージが1増える。"
        case .bloodPact:
            return "次に新しく得る報酬カードの使用回数が1減る。"
        case .cursedCrown:
            return "各フロアの手数上限が-5される。"
        case .obsidianHeart:
            return "各フロア開始時にHPが1減る。HPは1未満にならない。"
        case .warpedHourglass:
            return "手数上限の半分を超えてクリアすると、次階開始HPが1減る。最低1。"
        case .redChalice:
            return "以後、受けるダメージが1増える。"
        case .greedyBag:
            return "新しく得る報酬カードの使用回数が2減る。最低1回は残る。"
        case .crackedCompass:
            return "各フロアの手数上限が-3される。"
        case .heavyBell:
            return "各フロア最初の行動が2手分になる。"
        case .cloudedMirror:
            return "レリック報酬候補に手早いクリアによる品質補正がかからない。"
        case .crackedShoes:
            return "レイ型移動カードを新しく得る時、使用回数が1減る。最低1回は残る。"
        case .watchersBrand:
            return "見張りと回転見張りから受けるダメージが1増える。"
        case .patrolBell:
            return "巡回兵から受けるダメージが1増える。"
        case .chaserScent:
            return "追跡兵から受けるダメージが1増える。"
        case .meteorRod:
            return "メテオと標的警告から受けるダメージが1増える。"
        case .trapMagnet:
            return "互換用の呪いです。現在は撒菱ダメージを増やしません。"
        case .oilSoakedBoots:
            return "溶岩から受けるダメージが1増える。"
        case .glassAnklet:
            return "崩落穴で受ける落下ダメージが1増える。"
        case .poisonVial:
            return "毒罠の毒ダメージ回数が1増える。"
        case .ironShackle:
            return "足枷中の敵ターンが3回進む。"
        case .foolsMask:
            return "幻惑罠を踏むと、追加で手札を1つ失う。"
        case .frayedMemory:
            return "手札喪失系の罠で、通常効果後に追加で手札を1つ失う。"
        case .wetTinder:
            return "暗闇フロアの視界半径が1狭くなる。最低1。"
        case .laughingDoor:
            return "ワープマスで移動した時、手札を1つ失う。"
        case .upsideDownKey:
            return "鍵を拾って出口を開けた階では、その階の手数上限が-2される。"
        case .taxCollector:
            return "クリア報酬を選ぶと、次階開始HPが1減る。最低1。"
        case .flickeringCampfire:
            return "回復マスを踏むと幻惑を受ける。"
        case .contractCodex:
            return "各フロアの手数上限が-5される。"
        case .royalIou:
            return "クリア報酬を選ぶと、次階開始HPが2減る。最低1。"
        case .bottomlessPack:
            return "クリア後の報酬候補が1減る。最低2択。"
        case .relicHunterBrand:
            return "新しく得るカードの使用回数が1減る。最低1回は残る。"
        case .supportOath:
            return "新しく得る拾得カードと移動報酬カードの使用回数が1減る。最低1回は残る。"
        case .ashHeart:
            return "クリア後の報酬候補が1減る。最低2択。"
        case .hasteArmor:
            return "疲労ダメージが1増える。"
        case .scorchedCloak:
            return "疲労ダメージが1増える。"
        case .lastStandShield:
            return "各フロアの手数上限が-4される。"
        case .firewalkingTalisman:
            return "溶岩上で移動しない行動をすると、溶岩滞在ダメージが1増える。"
        case .tinkersToolbox:
            return "同じカードに寄りやすくなり、新しい種類を広げにくくなる。"
        case .expressTicket:
            return "疲労ダメージが1増える。"
        case .ploverContract:
            return "基本移動が使えなくなる。"
        case .quartermasterBell:
            return "敵がいる階で敵を1体も倒さずにクリアすると、次階開始HPが1減る。最低1。"
        case .sleepingWarDrum:
            return "敵由来のHPダメージが3倍になる。"
        case .swarmcallingTalisman:
            return "解決済みフロアで敵数が2倍になる。置ける範囲まで。"
        case .gildedSeal:
            return "取得中は現在HP、回復、次階開始HPが2を超えない。"
        }
    }

    public var effectDescription: String {
        "\(upsideDescription) \(downsideDescription)"
    }

    public var releaseDescription: String {
        switch self {
        case .rustyChain:
            return "この挑戦中ずっと残る。"
        case .thornMark:
            return "1回発動すると消える。"
        case .bloodPact:
            return "次の報酬カード取得で消える。最低1回は残る。"
        case .cursedCrown:
            return "この挑戦中ずっと残る。"
        case .obsidianHeart:
            return "この挑戦中ずっと残る。"
        case .warpedHourglass, .redChalice, .greedyBag, .crackedCompass, .heavyBell, .cloudedMirror, .crackedShoes:
            return "この挑戦中ずっと残る。"
        case .watchersBrand, .patrolBell, .chaserScent, .meteorRod, .trapMagnet, .oilSoakedBoots,
             .glassAnklet, .poisonVial, .ironShackle, .foolsMask, .frayedMemory, .wetTinder,
             .laughingDoor, .upsideDownKey, .taxCollector, .flickeringCampfire,
             .contractCodex, .royalIou, .bottomlessPack, .relicHunterBrand, .supportOath, .ashHeart,
             .hasteArmor, .scorchedCloak, .lastStandShield, .firewalkingTalisman, .tinkersToolbox,
             .expressTicket, .ploverContract, .quartermasterBell, .sleepingWarDrum,
             .swarmcallingTalisman, .gildedSeal:
            return "この挑戦中ずっと残る。"
        }
    }

    public var symbolName: String {
        switch self {
        case .rustyChain:
            return "link"
        case .thornMark:
            return "exclamationmark.triangle.fill"
        case .bloodPact:
            return "drop.fill"
        case .cursedCrown:
            return "crown.fill"
        case .obsidianHeart:
            return "heart.fill"
        case .warpedHourglass:
            return "hourglass"
        case .redChalice:
            return "drop.circle.fill"
        case .greedyBag:
            return "bag.fill"
        case .crackedCompass:
            return "safari.fill"
        case .heavyBell:
            return "bell.fill"
        case .cloudedMirror:
            return "mirror.side.left"
        case .crackedShoes:
            return "shoeprints.fill"
        case .watchersBrand:
            return "eye.trianglebadge.exclamationmark.fill"
        case .patrolBell:
            return "bell.and.waves.left.and.right.fill"
        case .chaserScent:
            return "wind"
        case .meteorRod:
            return "bolt.fill"
        case .trapMagnet:
            return "magnet.fill"
        case .oilSoakedBoots:
            return "flame.fill"
        case .glassAnklet:
            return "circle.hexagongrid.fill"
        case .poisonVial:
            return "cross.vial.fill"
        case .ironShackle:
            return "lock.fill"
        case .foolsMask:
            return "theatermasks.fill"
        case .frayedMemory:
            return "brain.head.profile"
        case .wetTinder:
            return "drop.triangle.fill"
        case .laughingDoor:
            return "door.left.hand.open"
        case .upsideDownKey:
            return "key.radiowaves.forward.fill"
        case .taxCollector:
            return "banknote.fill"
        case .flickeringCampfire:
            return "flame.trianglebadge.exclamationmark"
        case .contractCodex:
            return "book.closed.fill"
        case .royalIou:
            return "scroll.fill"
        case .bottomlessPack:
            return "bag.badge.plus"
        case .relicHunterBrand:
            return "scope"
        case .supportOath:
            return "hands.sparkles.fill"
        case .ashHeart:
            return "heart.text.square.fill"
        case .hasteArmor:
            return "figure.run.square.stack.fill"
        case .scorchedCloak:
            return "flame.dashed"
        case .lastStandShield:
            return "shield.lefthalf.filled"
        case .firewalkingTalisman:
            return "flame.circle.fill"
        case .tinkersToolbox:
            return "wrench.and.screwdriver.fill"
        case .expressTicket:
            return "ticket.fill"
        case .ploverContract:
            return "arrow.triangle.branch"
        case .quartermasterBell:
            return "bell.fill"
        case .sleepingWarDrum:
            return "moon.zzz.fill"
        case .swarmcallingTalisman:
            return "person.3.fill"
        case .gildedSeal:
            return "seal.fill"
        }
    }

    public var startingUses: Int {
        switch self {
        case .thornMark, .bloodPact:
            return 1
        case .rustyChain, .cursedCrown, .obsidianHeart, .warpedHourglass,
             .redChalice, .greedyBag, .crackedCompass, .heavyBell, .cloudedMirror, .crackedShoes:
            return 0
        case .watchersBrand, .patrolBell, .chaserScent, .meteorRod, .trapMagnet, .oilSoakedBoots,
             .glassAnklet, .poisonVial, .ironShackle, .foolsMask, .frayedMemory, .wetTinder,
             .laughingDoor, .upsideDownKey, .taxCollector, .flickeringCampfire,
             .contractCodex, .royalIou, .bottomlessPack, .relicHunterBrand, .supportOath, .ashHeart,
             .hasteArmor, .scorchedCloak, .firewalkingTalisman, .tinkersToolbox, .expressTicket,
             .ploverContract, .quartermasterBell, .sleepingWarDrum, .swarmcallingTalisman, .gildedSeal:
            return 0
        case .lastStandShield:
            return 1
        }
    }

    public var displayKind: DungeonCurseDisplayKind {
        if self == .lastStandShield {
            return .persistent
        }
        return startingUses > 0 ? .temporary : .persistent
    }
}

public enum DungeonCurseDisplayKind: Equatable, Sendable {
    case temporary
    case persistent

    public var displayName: String {
        switch self {
        case .temporary:
            return "一時呪い"
        case .persistent:
            return "永続呪い"
        }
    }

    public var badgeText: String {
        switch self {
        case .temporary:
            return "一"
        case .persistent:
            return "永"
        }
    }
}

/// ヘルプ内の呪い辞典で表示する 1 件分の情報
public struct DungeonCurseEncyclopediaEntry: Identifiable, Equatable, Sendable {
    public let curseID: DungeonCurseID

    public var id: String { curseID.id }
    public var displayName: String { curseID.displayName }
    public var effectDescription: String { curseID.effectDescription }
    public var upsideDescription: String { curseID.upsideDescription }
    public var downsideDescription: String { curseID.downsideDescription }
    public var releaseDescription: String { curseID.releaseDescription }
    public var symbolName: String { curseID.symbolName }
    public var displayKind: DungeonCurseDisplayKind { curseID.displayKind }
    public var encyclopediaDiscoveryID: EncyclopediaDiscoveryID { curseID.encyclopediaDiscoveryID }

    public init(curseID: DungeonCurseID) {
        self.curseID = curseID
    }

    public static let allEntries: [DungeonCurseEncyclopediaEntry] = DungeonCurseID.allCases.map {
        DungeonCurseEncyclopediaEntry(curseID: $0)
    }
}

/// 塔ラン中に所持している遺物
public struct DungeonRelicEntry: Codable, Equatable, Identifiable, Sendable {
    public let relicID: DungeonRelicID
    public var remainingUses: Int
    public var floorStartCharge: Int?
    public var enemyDefeatProgress: Int

    public var id: DungeonRelicID { relicID }
    public var displayName: String { relicID.displayName }
    public var effectDescription: String { relicID.effectDescription }
    public var noteDescription: String? { relicID.noteDescription }
    public var symbolName: String { relicID.symbolName }
    public var hasLimitedUses: Bool { relicID.startingUses > 0 }
    public var displayKind: DungeonRelicDisplayKind { relicID.displayKind }
    public var rarity: DungeonRelicRarity { relicID.rarity }

    public init(
        relicID: DungeonRelicID,
        remainingUses: Int? = nil,
        floorStartCharge: Int? = nil,
        enemyDefeatProgress: Int = 0
    ) {
        self.relicID = relicID
        self.remainingUses = max(remainingUses ?? relicID.startingUses, 0)
        self.floorStartCharge = floorStartCharge.map { max($0, 0) }
        self.enemyDefeatProgress = max(enemyDefeatProgress, 0)
    }

    private enum CodingKeys: String, CodingKey {
        case relicID
        case remainingUses
        case floorStartCharge
        case enemyDefeatProgress
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let relicID = try container.decode(DungeonRelicID.self, forKey: .relicID)
        guard !relicID.isRemovedFromCurrentRules else {
            throw DecodingError.dataCorruptedError(
                forKey: .relicID,
                in: container,
                debugDescription: "Removed dungeon relic is ignored."
            )
        }
        self.init(
            relicID: relicID,
            remainingUses: try container.decodeIfPresent(Int.self, forKey: .remainingUses),
            floorStartCharge: try container.decodeIfPresent(Int.self, forKey: .floorStartCharge),
            enemyDefeatProgress: try container.decodeIfPresent(Int.self, forKey: .enemyDefeatProgress) ?? 0
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(relicID, forKey: .relicID)
        try container.encode(remainingUses, forKey: .remainingUses)
        try container.encodeIfPresent(floorStartCharge, forKey: .floorStartCharge)
        try container.encode(enemyDefeatProgress, forKey: .enemyDefeatProgress)
    }
}

struct LossyDungeonRelicEntry: Decodable {
    let value: DungeonRelicEntry?

    init(from decoder: Decoder) throws {
        value = try? DungeonRelicEntry(from: decoder)
    }
}

/// 塔ラン中に所持している呪い遺物
public struct DungeonCurseEntry: Codable, Equatable, Identifiable, Sendable {
    public let curseID: DungeonCurseID
    public var remainingUses: Int

    public var id: DungeonCurseID { curseID }
    public var displayName: String { curseID.displayName }
    public var effectDescription: String { curseID.effectDescription }
    public var upsideDescription: String { curseID.upsideDescription }
    public var downsideDescription: String { curseID.downsideDescription }
    public var releaseDescription: String { curseID.releaseDescription }
    public var symbolName: String { curseID.symbolName }
    public var hasLimitedUses: Bool { curseID.startingUses > 0 }
    public var displayKind: DungeonCurseDisplayKind { curseID.displayKind }

    public init(curseID: DungeonCurseID, remainingUses: Int? = nil) {
        self.curseID = curseID
        self.remainingUses = max(remainingUses ?? curseID.startingUses, 0)
    }
}

/// 宝箱から発生する結果
public enum DungeonRelicPickupOutcome: Codable, Equatable, Sendable {
    case relic
    case curse
    case mimic
    case pandora
}

/// UI へ渡す遺物取得結果の表示用イベント
public struct DungeonRelicAcquisitionPresentation: Equatable, Identifiable, Sendable {
    public enum Source: Equatable, Sendable {
        case pickup
        case reward
    }

    public enum Item: Equatable, Identifiable, Sendable {
        case relic(DungeonRelicEntry)
        case curse(DungeonCurseEntry)
        case mimicDamage(Int)
        case hpCompensation(Int)
        case hpPenalty(Int)

        public var id: String {
            switch self {
            case .relic(let relic):
                return "relic-\(relic.relicID.rawValue)"
            case .curse(let curse):
                return "curse-\(curse.curseID.rawValue)"
            case .mimicDamage(let damage):
                return "mimic-\(damage)"
            case .hpCompensation(let amount):
                return "hp-\(amount)"
            case .hpPenalty(let amount):
                return "hp-penalty-\(amount)"
            }
        }

        public var displayName: String {
            switch self {
            case .relic(let relic):
                return relic.displayName
            case .curse(let curse):
                return curse.displayName
            case .mimicDamage:
                return "ミミック"
            case .hpCompensation:
                return "小さな補填"
            case .hpPenalty:
                return "代償"
            }
        }

        public var symbolName: String {
            switch self {
            case .relic(let relic):
                return relic.symbolName
            case .curse(let curse):
                return curse.symbolName
            case .mimicDamage:
                return "exclamationmark.triangle.fill"
            case .hpCompensation:
                return "heart.fill"
            case .hpPenalty:
                return "heart.slash.fill"
            }
        }

        public var primaryDescription: String {
            switch self {
            case .relic(let relic):
                return relic.effectDescription
            case .curse(let curse):
                return "\(curse.displayKind.displayName) / 利点: \(curse.upsideDescription)"
            case .mimicDamage(let damage):
                return "宝箱がミミック化し、HPを \(damage) 失いました。"
            case .hpCompensation(let amount):
                return "未所持の遺物候補がなかったため、HPが \(amount) 回復しました。"
            case .hpPenalty(let amount):
                return "代償として HP を \(amount) 失います。"
            }
        }

        public var secondaryDescriptions: [String] {
            switch self {
            case .relic(let relic):
                var descriptions: [String] = []
                if let note = relic.noteDescription {
                    descriptions.append(note)
                }
                if relic.hasLimitedUses {
                    descriptions.append("残り \(relic.remainingUses) 回")
                }
                return descriptions
            case .curse(let curse):
                var descriptions = [
                    "代償: \(curse.downsideDescription)",
                    "解除: \(curse.releaseDescription)"
                ]
                if curse.hasLimitedUses {
                    descriptions.append("残り \(curse.remainingUses) 回")
                }
                return descriptions
            case .mimicDamage, .hpCompensation, .hpPenalty:
                return []
            }
        }
    }

    public let id: UUID
    public let source: Source
    public let outcome: DungeonRelicPickupOutcome?
    public let items: [Item]

    public init(
        id: UUID = UUID(),
        source: Source,
        outcome: DungeonRelicPickupOutcome?,
        items: [Item]
    ) {
        self.id = id
        self.source = source
        self.outcome = outcome
        self.items = items
    }

    public static func rewardRelic(_ relic: DungeonRelicID) -> DungeonRelicAcquisitionPresentation {
        DungeonRelicAcquisitionPresentation(
            source: .reward,
            outcome: .relic,
            items: [.relic(DungeonRelicEntry(relicID: relic))]
        )
    }

    public var title: String {
        switch source {
        case .reward:
            return "遺物を獲得"
        case .pickup:
            switch outcome {
            case .relic:
                return "宝箱から遺物"
            case .curse:
                return "呪い遺物を受けた"
            case .mimic:
                return "ミミックが出現"
            case .pandora:
                return "パンドラ箱が開いた"
            case .none:
                return "宝箱の結果"
            }
        }
    }

    public var confirmationTitle: String {
        source == .reward ? "次の階へ" : "冒険を続ける"
    }
}

/// 遊び方辞典で扱う塔イベントの分類
public enum DungeonEventEncyclopediaKind: String, CaseIterable, Equatable, Identifiable, Sendable {
    case safeChest
    case suspiciousLightChest
    case suspiciousDeepChest
    case relicReward
    case curseOutcome
    case mimicOutcome
    case pandoraOutcome
    case floorFall
    case handExpansion

    public var id: String { rawValue }

    public var encyclopediaDiscoveryID: EncyclopediaDiscoveryID {
        EncyclopediaDiscoveryID(category: .event, itemID: rawValue)
    }

    public var displayName: String {
        switch self {
        case .safeChest:
            return "宝箱"
        case .suspiciousLightChest:
            return "怪しい宝箱"
        case .suspiciousDeepChest:
            return "深く怪しい宝箱"
        case .relicReward:
            return "遺物報酬"
        case .curseOutcome:
            return "呪い"
        case .mimicOutcome:
            return "ミミック"
        case .pandoraOutcome:
            return "パンドラ箱"
        case .floorFall:
            return "床崩落"
        case .handExpansion:
            return "手札拡張"
        }
    }

    public var description: String {
        switch self {
        case .safeChest:
            return "踏むと通常遺物を取得する宝箱です。カード所持枠は使いません。"
        case .suspiciousLightChest:
            return "通常遺物と呪い遺物から選ぶ、少し怪しい宝箱です。"
        case .suspiciousDeepChest:
            return "通常遺物と呪い遺物から選ぶ、深層の怪しい宝箱です。通常遺物は高希少度が出やすくなります。"
        case .relicReward:
            return "フロアクリア後の報酬候補に遺物が並ぶことがあります。既に持つ遺物は候補から外れます。"
        case .curseOutcome:
            return "怪しい宝箱から不利な効果を持つ呪いを受けることがあります。"
        case .mimicOutcome:
            return "旧仕様の怪しい宝箱で使われていた危険結果です。現行の怪しい宝箱は選択式です。"
        case .pandoraOutcome:
            return "旧仕様の怪しい宝箱で使われていた複合結果です。現行の怪しい宝箱は選択式です。"
        case .floorFall:
            return "崩落穴に落ちると HP を失い、条件を満たす場合は前の階へ落下します。"
        case .handExpansion:
            return "試練塔のラン中だけ通常カードの手札枠を1つ増やすアイテムです。最大9枠まで増えます。"
        }
    }
}

/// ヘルプ内のイベント辞典で表示する 1 件分の情報
public struct DungeonEventEncyclopediaEntry: Identifiable, Equatable, Sendable {
    public let kind: DungeonEventEncyclopediaKind

    public var id: String { kind.id }
    public var displayName: String { kind.displayName }
    public var description: String { kind.description }
    public var encyclopediaDiscoveryID: EncyclopediaDiscoveryID { kind.encyclopediaDiscoveryID }

    public init(kind: DungeonEventEncyclopediaKind) {
        self.kind = kind
    }

    public static let allEntries: [DungeonEventEncyclopediaEntry] = DungeonEventEncyclopediaKind.allCases.map {
        DungeonEventEncyclopediaEntry(kind: $0)
    }
}

/// 宝箱の危険度
public enum DungeonRelicPickupKind: String, Codable, Equatable, Sendable {
    case safe
    case suspiciousLight
    case suspiciousDeep

    public var isSuspicious: Bool {
        switch self {
        case .safe:
            return false
        case .suspiciousLight, .suspiciousDeep:
            return true
        }
    }

    public var encyclopediaEventKind: DungeonEventEncyclopediaKind {
        switch self {
        case .safe:
            return .safeChest
        case .suspiciousLight:
            return .suspiciousLightChest
        case .suspiciousDeep:
            return .suspiciousDeepChest
        }
    }

    public var outcomeWeights: [(DungeonRelicPickupOutcome, Int)] {
        switch self {
        case .safe:
            return [(.relic, 100)]
        case .suspiciousLight:
            return [(.relic, 75), (.curse, 15), (.mimic, 7), (.pandora, 3)]
        case .suspiciousDeep:
            return [(.relic, 60), (.curse, 25), (.mimic, 10), (.pandora, 5)]
        }
    }

    public var relicRarityWeights: [(DungeonRelicRarity, Int)] {
        switch self {
        case .safe:
            return [(.common, 75), (.rare, 22), (.legendary, 3)]
        case .suspiciousLight:
            return [(.common, 55), (.rare, 35), (.legendary, 10)]
        case .suspiciousDeep:
            return [(.common, 40), (.rare, 42), (.legendary, 18)]
        }
    }
}

/// フロア内に配置する宝箱。踏むとランダムな遺物を取得する。
public struct DungeonRelicPickupDefinition: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let point: GridPoint
    public let kind: DungeonRelicPickupKind
    public let candidateRelics: [DungeonRelicID]
    public let candidateCurses: [DungeonCurseID]

    public init(
        id: String,
        point: GridPoint,
        kind: DungeonRelicPickupKind = .safe,
        candidateRelics: [DungeonRelicID] = DungeonRelicID.newAcquisitionCases,
        candidateCurses: [DungeonCurseID] = DungeonCurseID.newAcquisitionCases
    ) {
        self.id = id
        self.point = point
        self.kind = kind
        self.candidateRelics = candidateRelics.isEmpty ? DungeonRelicID.newAcquisitionCases : candidateRelics
        self.candidateCurses = candidateCurses.isEmpty ? DungeonCurseID.newAcquisitionCases : candidateCurses
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case point
        case kind
        case candidateRelics
        case candidateCurses
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            point: try container.decode(GridPoint.self, forKey: .point),
            kind: try container.decodeIfPresent(DungeonRelicPickupKind.self, forKey: .kind) ?? .safe,
            candidateRelics: try container.decodeIfPresent([DungeonRelicID].self, forKey: .candidateRelics) ?? DungeonRelicID.newAcquisitionCases,
            candidateCurses: try container.decodeIfPresent([DungeonCurseID].self, forKey: .candidateCurses) ?? DungeonCurseID.newAcquisitionCases
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(point, forKey: .point)
        try container.encode(kind, forKey: .kind)
        try container.encode(candidateRelics, forKey: .candidateRelics)
        try container.encode(candidateCurses, forKey: .candidateCurses)
    }
}

/// 成長塔の階層別排出テーブルに載せる候補種別
public enum DungeonWeightedRewardPoolItem: Equatable, Sendable {
    case move(MoveCard)
    case support(SupportCard)
    case relic(DungeonRelicID)

    public var playable: PlayableCard? {
        switch self {
        case .move(let card):
            return .move(card)
        case .support(let support):
            return .support(support)
        case .relic:
            return nil
        }
    }

    public var offer: DungeonRewardOffer? {
        switch self {
        case .move(let card):
            return .playable(.move(card))
        case .support(let support):
            return .playable(.support(support))
        case .relic(let relic):
            return .relic(relic)
        }
    }

    fileprivate var category: DungeonWeightedRewardPoolCategory {
        switch self {
        case .move:
            return .move
        case .support:
            return .support
        case .relic:
            return .relic
        }
    }
}

/// 成長塔の重み付き排出候補。weight 0 はテーブル上の予約枠として扱い、抽選には出ない。
public struct DungeonWeightedRewardPoolEntry: Equatable, Sendable {
    public let item: DungeonWeightedRewardPoolItem
    public let weight: Int

    public init(item: DungeonWeightedRewardPoolItem, weight: Int) {
        self.item = item
        self.weight = max(weight, 0)
    }
}

/// 成長塔の排出テーブル種別
public enum DungeonWeightedRewardPoolContext: Equatable, Sendable {
    case floorPickup
    case clearReward
}

private enum DungeonWeightedRewardPoolCategory: CaseIterable {
    case move
    case support
    case relic
}

public struct DungeonRewardDrawTuning: Equatable, Sendable {
    public let clearMoveCount: Int?
    public let turnLimit: Int?
    public let suppressRelicQualityBonus: Bool
    public let supportCategoryBonusPoints: Int
    public let relicCategoryBonusPoints: Int
    public let preferredPlayables: Set<PlayableCard>
    public let forcesRareOrBetterRelics: Bool

    public init(
        clearMoveCount: Int? = nil,
        turnLimit: Int? = nil,
        suppressRelicQualityBonus: Bool = false,
        supportCategoryBonusPoints: Int = 0,
        relicCategoryBonusPoints: Int = 0,
        preferredPlayables: Set<PlayableCard> = [],
        forcesRareOrBetterRelics: Bool = false
    ) {
        self.clearMoveCount = clearMoveCount
        self.turnLimit = turnLimit
        self.suppressRelicQualityBonus = suppressRelicQualityBonus
        self.supportCategoryBonusPoints = max(supportCategoryBonusPoints, 0)
        self.relicCategoryBonusPoints = max(relicCategoryBonusPoints, 0)
        self.preferredPlayables = preferredPlayables
        self.forcesRareOrBetterRelics = forcesRareOrBetterRelics
    }
}

private struct DungeonWeightedRewardCategoryWeights {
    let move: Int
    let support: Int
    let relic: Int

    func weight(for category: DungeonWeightedRewardPoolCategory) -> Int {
        switch category {
        case .move:
            return move
        case .support:
            return support
        case .relic:
            return relic
        }
    }
}

/// 成長塔の階層別・重み付き排出テーブル
public enum DungeonWeightedRewardPools {
    public static func entries(
        floorIndex: Int,
        context: DungeonWeightedRewardPoolContext,
        movementStyle: DungeonMovementStyle = .orthogonal,
        countering nextFloor: DungeonFloorDefinition? = nil
    ) -> [DungeonWeightedRewardPoolEntry] {
        let baseEntries: [DungeonWeightedRewardPoolEntry]
        switch (band(for: floorIndex), context) {
        case (.floors1To5, .floorPickup):
            baseEntries = weightedMoves([
                (.straightRight2, 8), (.straightUp2, 8), (.straightLeft2, 5), (.straightDown2, 5),
                (.diagonalUpRight2, 6), (.diagonalUpLeft2, 5), (.diagonalDownRight2, 4), (.diagonalDownLeft2, 4),
                (.rayRight, 3), (.rayUp, 3)
            ]) + weightedSupports([(.refillEmptySlots, 1), (.singleAnnihilationSpell, 1)])
        case (.floors1To5, .clearReward):
            baseEntries = weightedMoves([
                (.straightRight2, 9), (.straightUp2, 9), (.diagonalUpRight2, 7),
                (.rayRight, 5), (.rayUp, 4), (.knightRightwardChoice, 3), (.knightUpwardChoice, 3)
            ]) + weightedSupports([(.refillEmptySlots, 1), (.singleAnnihilationSpell, 1)]) + weightedRelics()
        case (.floors6To10, .floorPickup):
            baseEntries = weightedMoves([
                (.straightRight2, 8), (.straightUp2, 8), (.straightLeft2, 7), (.straightDown2, 7),
                (.diagonalUpRight2, 7), (.diagonalUpLeft2, 6), (.diagonalDownRight2, 6), (.diagonalDownLeft2, 6),
                (.rayRight, 5), (.rayUp, 5), (.rayLeft, 4), (.rayDown, 4),
                (.knightRightwardChoice, 3), (.knightUpwardChoice, 3), (.knightLeftwardChoice, 2), (.knightDownwardChoice, 2)
            ]) + weightedSupports([(.refillEmptySlots, 2), (.singleAnnihilationSpell, 1), (.panacea, 1)])
        case (.floors6To10, .clearReward):
            baseEntries = weightedMoves([
                (.rayRight, 7), (.rayUp, 7), (.rayLeft, 5), (.rayDown, 5),
                (.straightRight2, 6), (.straightUp2, 6), (.diagonalUpRight2, 6), (.diagonalDownRight2, 4),
                (.knightRightwardChoice, 5), (.knightUpwardChoice, 4), (.knightLeftwardChoice, 3)
            ]) + weightedSupports([(.refillEmptySlots, 2), (.singleAnnihilationSpell, 1), (.panacea, 1)]) + weightedRelics()
        case (.floors11To15, .floorPickup):
            baseEntries = weightedMoves([
                (.straightRight2, 7), (.straightUp2, 7), (.straightLeft2, 7), (.straightDown2, 7),
                (.diagonalUpRight2, 7), (.diagonalUpLeft2, 7), (.diagonalDownRight2, 6), (.diagonalDownLeft2, 6),
                (.rayRight, 6), (.rayUp, 6), (.rayLeft, 6), (.rayDown, 6),
                (.rayUpRight, 3), (.rayUpLeft, 3), (.rayDownRight, 3), (.rayDownLeft, 3),
                (.knightRightwardChoice, 4), (.knightUpwardChoice, 4), (.knightLeftwardChoice, 4), (.knightDownwardChoice, 3)
            ]) + weightedSupports([
                (.refillEmptySlots, 3),
                (.singleAnnihilationSpell, 1),
                (.annihilationSpell, 1),
                (.darknessSpell, 2),
                (.railBreakSpell, 2),
                (.panacea, 4)
            ])
        case (.floors11To15, .clearReward):
            baseEntries = weightedMoves([
                (.rayRight, 7), (.rayUp, 7), (.rayLeft, 7), (.rayDown, 7),
                (.rayUpRight, 4), (.rayUpLeft, 4), (.rayDownRight, 3), (.rayDownLeft, 3),
                (.diagonalUpRight2, 5), (.diagonalUpLeft2, 5), (.diagonalDownLeft2, 4),
                (.knightRightwardChoice, 5), (.knightUpwardChoice, 5), (.knightLeftwardChoice, 4)
            ]) + weightedSupports([
                (.refillEmptySlots, 3),
                (.singleAnnihilationSpell, 1),
                (.annihilationSpell, 1),
                (.darknessSpell, 2),
                (.railBreakSpell, 2),
                (.panacea, 4)
            ]) + weightedRelics()
        case (.floors16To20, .floorPickup):
            baseEntries = weightedMoves([
                (.rayRight, 8), (.rayUp, 8), (.rayLeft, 8), (.rayDown, 8),
                (.rayUpRight, 5), (.rayUpLeft, 5), (.rayDownRight, 5), (.rayDownLeft, 5),
                (.knightRightwardChoice, 6), (.knightUpwardChoice, 6), (.knightLeftwardChoice, 5), (.knightDownwardChoice, 5),
                (.straightRight2, 5), (.straightUp2, 5), (.diagonalUpRight2, 5), (.diagonalDownLeft2, 5)
            ]) + weightedSupports([
                (.refillEmptySlots, 2),
                (.singleAnnihilationSpell, 1),
                (.annihilationSpell, 1),
                (.darknessSpell, 3),
                (.railBreakSpell, 3),
                (.panacea, 4)
            ])
        case (.floors16To20, .clearReward):
            baseEntries = weightedMoves([
                (.rayRight, 9), (.rayUp, 9), (.rayLeft, 9), (.rayDown, 8),
                (.rayUpRight, 6), (.rayUpLeft, 6), (.rayDownRight, 5), (.rayDownLeft, 5),
                (.knightRightwardChoice, 7), (.knightUpwardChoice, 7), (.knightLeftwardChoice, 6), (.knightDownwardChoice, 6),
                (.diagonalUpRight2, 4), (.diagonalUpLeft2, 4), (.diagonalDownLeft2, 4)
            ]) + weightedSupports([
                (.refillEmptySlots, 2),
                (.singleAnnihilationSpell, 1),
                (.annihilationSpell, 1),
                (.darknessSpell, 3),
                (.railBreakSpell, 3),
                (.freezeSpell, 3),
                (.barrierSpell, 3),
                (.panacea, 4)
            ]) + weightedRelics()
        case (.floors21To30, .floorPickup):
            baseEntries = weightedMoves([
                (.rayRight, 8), (.rayUp, 8), (.rayLeft, 8), (.rayDown, 8),
                (.rayUpRight, 5), (.rayUpLeft, 5), (.rayDownRight, 5), (.rayDownLeft, 5),
                (.knightRightwardChoice, 6), (.knightUpwardChoice, 6), (.knightLeftwardChoice, 6), (.knightDownwardChoice, 6),
                (.straightRight2, 5), (.straightUp2, 5), (.straightLeft2, 5), (.straightDown2, 5),
                (.diagonalUpRight2, 5), (.diagonalUpLeft2, 5), (.diagonalDownRight2, 5), (.diagonalDownLeft2, 5)
            ]) + weightedSupports([
                (.refillEmptySlots, 3),
                (.singleAnnihilationSpell, 1),
                (.annihilationSpell, 1),
                (.darknessSpell, 2),
                (.railBreakSpell, 2),
                (.flySpell, 3),
                (.panacea, 6)
            ])
        case (.floors21To30, .clearReward):
            baseEntries = weightedMoves([
                (.rayRight, 8), (.rayUp, 8), (.rayLeft, 8), (.rayDown, 8),
                (.rayUpRight, 7), (.rayUpLeft, 7), (.rayDownRight, 6), (.rayDownLeft, 6),
                (.knightRightwardChoice, 7), (.knightUpwardChoice, 7), (.knightLeftwardChoice, 7), (.knightDownwardChoice, 7),
                (.diagonalUpRight2, 5), (.diagonalUpLeft2, 5), (.diagonalDownRight2, 5), (.diagonalDownLeft2, 5)
            ]) + weightedSupports([
                (.refillEmptySlots, 3),
                (.singleAnnihilationSpell, 1),
                (.annihilationSpell, 1),
                (.darknessSpell, 3),
                (.railBreakSpell, 3),
                (.freezeSpell, 3),
                (.barrierSpell, 3),
                (.flySpell, 3),
                (.panacea, 6)
            ]) + weightedRelics()
        case (.floors31To40, .floorPickup):
            baseEntries = weightedMoves([
                (.rayRight, 7), (.rayUp, 7), (.rayLeft, 7), (.rayDown, 7),
                (.rayUpRight, 7), (.rayUpLeft, 7), (.rayDownRight, 7), (.rayDownLeft, 7),
                (.knightRightwardChoice, 7), (.knightUpwardChoice, 7), (.knightLeftwardChoice, 7), (.knightDownwardChoice, 7),
                (.straightRight2, 4), (.straightUp2, 4), (.straightLeft2, 4), (.straightDown2, 4),
                (.diagonalUpRight2, 5), (.diagonalUpLeft2, 5), (.diagonalDownRight2, 5), (.diagonalDownLeft2, 5)
            ]) + weightedSupports([
                (.refillEmptySlots, 2),
                (.singleAnnihilationSpell, 1),
                (.annihilationSpell, 1),
                (.darknessSpell, 3),
                (.railBreakSpell, 3),
                (.freezeSpell, 2),
                (.barrierSpell, 3),
                (.flySpell, 3),
                (.panacea, 7)
            ])
        case (.floors31To40, .clearReward):
            baseEntries = weightedMoves([
                (.rayRight, 8), (.rayUp, 8), (.rayLeft, 8), (.rayDown, 8),
                (.rayUpRight, 8), (.rayUpLeft, 8), (.rayDownRight, 7), (.rayDownLeft, 7),
                (.knightRightwardChoice, 8), (.knightUpwardChoice, 8), (.knightLeftwardChoice, 8), (.knightDownwardChoice, 8),
                (.diagonalUpRight2, 5), (.diagonalUpLeft2, 5), (.diagonalDownRight2, 5), (.diagonalDownLeft2, 5)
            ]) + weightedSupports([
                (.refillEmptySlots, 2),
                (.singleAnnihilationSpell, 1),
                (.annihilationSpell, 1),
                (.darknessSpell, 4),
                (.railBreakSpell, 4),
                (.freezeSpell, 4),
                (.barrierSpell, 4),
                (.flySpell, 3),
                (.panacea, 7)
            ]) + weightedRelics()
        case (.floors41To50, .floorPickup):
            baseEntries = weightedMoves([
                (.rayRight, 8), (.rayUp, 8), (.rayLeft, 8), (.rayDown, 8),
                (.rayUpRight, 8), (.rayUpLeft, 8), (.rayDownRight, 8), (.rayDownLeft, 8),
                (.knightRightwardChoice, 8), (.knightUpwardChoice, 8), (.knightLeftwardChoice, 8), (.knightDownwardChoice, 8),
                (.diagonalUpRight2, 6), (.diagonalUpLeft2, 6), (.diagonalDownRight2, 6), (.diagonalDownLeft2, 6)
            ]) + weightedSupports([
                (.refillEmptySlots, 2),
                (.singleAnnihilationSpell, 1),
                (.annihilationSpell, 1),
                (.darknessSpell, 4),
                (.railBreakSpell, 4),
                (.freezeSpell, 3),
                (.barrierSpell, 4),
                (.flySpell, 3),
                (.panacea, 6)
            ])
        case (.floors41To50, .clearReward):
            baseEntries = weightedMoves([
                (.rayRight, 9), (.rayUp, 9), (.rayLeft, 9), (.rayDown, 9),
                (.rayUpRight, 9), (.rayUpLeft, 9), (.rayDownRight, 9), (.rayDownLeft, 9),
                (.knightRightwardChoice, 9), (.knightUpwardChoice, 9), (.knightLeftwardChoice, 9), (.knightDownwardChoice, 9),
                (.diagonalUpRight2, 6), (.diagonalUpLeft2, 6), (.diagonalDownRight2, 6), (.diagonalDownLeft2, 6)
            ]) + weightedSupports([
                (.refillEmptySlots, 2),
                (.singleAnnihilationSpell, 1),
                (.annihilationSpell, 1),
                (.darknessSpell, 5),
                (.railBreakSpell, 5),
                (.freezeSpell, 5),
                (.barrierSpell, 5),
                (.flySpell, 4),
                (.panacea, 7)
            ]) + weightedRelics()
        }
        let movementAdjustedEntries = adjustedEntries(baseEntries, movementStyle: movementStyle)
        guard context == .clearReward, let nextFloor else {
            return movementAdjustedEntries
        }
        return entries(
            movementAdjustedEntries,
            addingSupportBiases: counterSupportBiases(for: nextFloor)
        )
    }

    public static func drawUniquePlayables(
        from entries: [DungeonWeightedRewardPoolEntry],
        count: Int,
        seed: UInt64,
        floorIndex: Int,
        salt: UInt64,
        excluding excluded: Set<PlayableCard> = []
    ) -> [PlayableCard] {
        drawUniqueOffers(
            from: entries,
            context: .clearReward,
            count: count,
            seed: seed,
            floorIndex: floorIndex,
            salt: salt,
            excludingPlayables: excluded
        )
        .compactMap(\.playable)
    }

    public static func drawUniqueOffers(
        from entries: [DungeonWeightedRewardPoolEntry],
        context: DungeonWeightedRewardPoolContext,
        count: Int,
        seed: UInt64,
        floorIndex: Int,
        salt: UInt64,
        tuning: DungeonRewardDrawTuning = DungeonRewardDrawTuning(),
        excludingPlayables excludedPlayables: Set<PlayableCard> = [],
        excludingRelics excludedRelics: Set<DungeonRelicID> = []
    ) -> [DungeonRewardOffer] {
        var randomizer = DungeonCardVariationRandomizer(seed: seed, floorIndex: floorIndex, salt: salt)
        var candidates = entries
            .filter { $0.weight > 0 }
            .compactMap { entry -> (offer: DungeonRewardOffer, category: DungeonWeightedRewardPoolCategory, weight: Int)? in
                guard let offer = entry.item.offer else { return nil }
                switch offer {
                case .playable(let playable) where excludedPlayables.contains(playable):
                    return nil
                case .playable(let playable):
                    return (offer, entry.item.category, rewardPlayableWeight(entry.weight, playable: playable, tuning: tuning))
                case .relic(let relic) where excludedRelics.contains(relic):
                    return nil
                case .relic(let relic):
                    return (offer, entry.item.category, entry.weight * rewardRelicWeight(for: relic.rarity, tuning: tuning))
                case .handExpansion:
                    return (offer, entry.item.category, entry.weight)
                }
            }
        var result: [DungeonRewardOffer] = []
        let categoryWeights = categoryWeights(context: context, tuning: tuning)
        while result.count < count, !candidates.isEmpty {
            let availableCategories = DungeonWeightedRewardPoolCategory.allCases.compactMap { category -> (DungeonWeightedRewardPoolCategory, Int)? in
                guard candidates.contains(where: { $0.category == category }) else { return nil }
                let weight = categoryWeights.weight(for: category)
                return weight > 0 ? (category, weight) : nil
            }
            guard let selectedCategory = drawCategory(availableCategories, randomizer: &randomizer) else { break }
            let categoryCandidateIndices = candidates.indices.filter { candidates[$0].category == selectedCategory }
            let totalWeight = categoryCandidateIndices.reduce(0) { $0 + candidates[$1].weight }
            guard totalWeight > 0 else { break }
            var roll = randomizer.nextIndex(upperBound: totalWeight)
            let selectedIndex = categoryCandidateIndices.first { index in
                if roll < candidates[index].weight { return true }
                roll -= candidates[index].weight
                return false
            } ?? categoryCandidateIndices[0]
            result.append(candidates.remove(at: selectedIndex).offer)
        }
        PlayDiagnosticLog.emit(
            event: "reward_draw",
            fields: [
                ("dungeon", "growth-tower"),
                ("floor", String(floorIndex + 1)),
                ("turn", "nil"),
                ("hp", "nil"),
                ("pos", "nil"),
                ("progress", "reward"),
                ("hand", "nil"),
                ("relics", excludedRelics.map(\.rawValue).sorted().joined(separator: ",")),
                ("curses", "nil"),
                ("context", String(describing: context)),
                ("requested", String(count)),
                ("seed", String(seed)),
                ("salt", String(salt)),
                ("baseCount", String(entries.count)),
                ("excludedPlayables", excludedPlayables.map(\.displayName).sorted().joined(separator: ",")),
                ("result", result.map(\.displayName).joined(separator: ","))
            ]
        )
        return result
    }

    public static func rewardPlayableWeight(
        _ baseWeight: Int,
        playable: PlayableCard,
        tuning: DungeonRewardDrawTuning
    ) -> Int {
        guard tuning.preferredPlayables.contains(playable) else { return baseWeight }
        return baseWeight + 12
    }

    private enum FloorBand {
        case floors1To5
        case floors6To10
        case floors11To15
        case floors16To20
        case floors21To30
        case floors31To40
        case floors41To50
    }

    private static func band(for floorIndex: Int) -> FloorBand {
        switch floorIndex {
        case 0..<5:
            return .floors1To5
        case 5..<10:
            return .floors6To10
        case 10..<15:
            return .floors11To15
        case 15..<20:
            return .floors16To20
        case 20..<30:
            return .floors21To30
        case 30..<40:
            return .floors31To40
        default:
            return .floors41To50
        }
    }

    private static func weightedMoves(_ cards: [(MoveCard, Int)]) -> [DungeonWeightedRewardPoolEntry] {
        cards.map { DungeonWeightedRewardPoolEntry(item: .move($0.0), weight: $0.1) }
    }

    private static func weightedSupports(_ cards: [(SupportCard, Int)]) -> [DungeonWeightedRewardPoolEntry] {
        cards.map { DungeonWeightedRewardPoolEntry(item: .support($0.0), weight: $0.1) }
    }

    private static func weightedRelics() -> [DungeonWeightedRewardPoolEntry] {
        DungeonRelicID.newAcquisitionCases.map { DungeonWeightedRewardPoolEntry(item: .relic($0), weight: 1) }
    }

    private static func adjustedEntries(
        _ entries: [DungeonWeightedRewardPoolEntry],
        movementStyle: DungeonMovementStyle
    ) -> [DungeonWeightedRewardPoolEntry] {
        guard movementStyle == .knight else { return entries }
        return entries.map { entry in
            guard case .move(let card) = entry.item else { return entry }
            return DungeonWeightedRewardPoolEntry(
                item: .move(card.cardForKnightMovementStyle),
                weight: entry.weight
            )
        }
    }

    private static func entries(
        _ entries: [DungeonWeightedRewardPoolEntry],
        addingSupportBiases biases: [(SupportCard, Int)]
    ) -> [DungeonWeightedRewardPoolEntry] {
        guard !biases.isEmpty else { return entries }
        let biasBySupport = Dictionary(uniqueKeysWithValues: biases)
        var includedSupports: Set<SupportCard> = []
        var result = entries.map { entry in
            guard case .support(let support) = entry.item else { return entry }
            includedSupports.insert(support)
            return DungeonWeightedRewardPoolEntry(
                item: entry.item,
                weight: entry.weight + (biasBySupport[support] ?? 0)
            )
        }
        for (support, weight) in biases where weight > 0 && !includedSupports.contains(support) {
            result.append(DungeonWeightedRewardPoolEntry(item: .support(support), weight: weight))
        }
        return result
    }

    private static func counterSupportBiases(for floor: DungeonFloorDefinition) -> [(SupportCard, Int)] {
        var weights: [SupportCard: Int] = [:]
        func add(_ support: SupportCard, _ weight: Int) {
            weights[support, default: 0] += weight
        }

        if floor.isDarknessEnabled {
            add(.darknessSpell, 10)
        }

        for enemy in floor.enemies {
            switch enemy.behavior {
            case .patrol:
                add(.railBreakSpell, 9)
            case .chaser, .marker, .targetedMarker:
                add(.freezeSpell, 6)
            case .watcher, .rotatingWatcher:
                add(.darknessSpell, 4)
            case .guardPost:
                break
            }
        }

        var hasStatusTrap = false
        var hasHandLossTrap = false
        for effect in floor.tileEffectOverrides.values {
            switch effect {
            case .poisonTrap:
                hasStatusTrap = true
            case .shackleTrap, .illusionTrap, .staggerTrap, .relicBreakTrap:
                hasStatusTrap = true
            case .discardRandomHand, .discardAllMoveCards, .discardAllSupportCards, .discardAllHands:
                hasStatusTrap = true
                hasHandLossTrap = true
            case .warp, .returnWarp, .shuffleHand, .blast, .slow, .swamp, .preserveCard:
                break
            }
        }
        if hasStatusTrap {
            add(.panacea, 9)
        }
        if hasHandLossTrap {
            add(.refillEmptySlots, 8)
        }

        let hasDangerFloor = floor.hazards.contains { hazard in
            switch hazard {
            case .brittleFloor, .damageTrap, .hpHalvingTrap, .lavaTile:
                return true
            case .healingTile:
                return false
            }
        }
        if hasDangerFloor {
            add(.barrierSpell, 7)
            add(.flySpell, 6)
        }

        let order: [SupportCard] = [
            .darknessSpell,
            .railBreakSpell,
            .panacea,
            .flySpell,
            .barrierSpell,
            .freezeSpell,
            .refillEmptySlots
        ]
        return order.compactMap { support in
            guard let weight = weights[support], weight > 0 else { return nil }
            return (support, weight)
        }
    }

    private static func rewardRelicWeight(
        for rarity: DungeonRelicRarity,
        tuning: DungeonRewardDrawTuning
    ) -> Int {
        if tuning.forcesRareOrBetterRelics, rarity == .common {
            return 0
        }
        guard let moveCount = tuning.clearMoveCount,
              let turnLimit = tuning.turnLimit,
              turnLimit > 0,
              !tuning.suppressRelicQualityBonus
        else {
            return normalRewardRelicWeight(for: rarity)
        }
        if moveCount * 2 <= turnLimit {
            return weight(for: rarity, common: 45, rare: 40, legendary: 15)
        }
        if moveCount * 10 <= turnLimit * 7 {
            return weight(for: rarity, common: 60, rare: 32, legendary: 8)
        }
        return normalRewardRelicWeight(for: rarity)
    }

    private static func normalRewardRelicWeight(for rarity: DungeonRelicRarity) -> Int {
        weight(for: rarity, common: 70, rare: 25, legendary: 5)
    }

    private static func weight(
        for rarity: DungeonRelicRarity,
        common: Int,
        rare: Int,
        legendary: Int
    ) -> Int {
        switch rarity {
        case .common:
            return common
        case .rare:
            return rare
        case .legendary:
            return legendary
        }
    }

    private static func categoryWeights(
        context: DungeonWeightedRewardPoolContext,
        tuning: DungeonRewardDrawTuning
    ) -> DungeonWeightedRewardCategoryWeights {
        switch context {
        case .floorPickup:
            return DungeonWeightedRewardCategoryWeights(move: 90, support: 10, relic: 0)
        case .clearReward:
            func adjusted(move: Int, support: Int, relic: Int) -> DungeonWeightedRewardCategoryWeights {
                let adjustedSupport = support + tuning.supportCategoryBonusPoints
                let adjustedRelic = relic + tuning.relicCategoryBonusPoints
                return DungeonWeightedRewardCategoryWeights(
                    move: max(move - tuning.supportCategoryBonusPoints - tuning.relicCategoryBonusPoints, 0),
                    support: adjustedSupport,
                    relic: adjustedRelic
                )
            }
            guard let moveCount = tuning.clearMoveCount,
                  let turnLimit = tuning.turnLimit,
                  turnLimit > 0
            else {
                return adjusted(move: 89, support: 10, relic: 1)
            }
            if moveCount * 2 <= turnLimit {
                if tuning.suppressRelicQualityBonus {
                    return adjusted(move: 69, support: 30, relic: 1)
                }
                return adjusted(move: 65, support: 30, relic: 5)
            }
            if moveCount * 10 <= turnLimit * 7 {
                if tuning.suppressRelicQualityBonus {
                    return adjusted(move: 79, support: 20, relic: 1)
                }
                return adjusted(move: 77, support: 20, relic: 3)
            }
            return adjusted(move: 89, support: 10, relic: 1)
        }
    }

    private static func drawCategory(
        _ categories: [(DungeonWeightedRewardPoolCategory, Int)],
        randomizer: inout DungeonCardVariationRandomizer
    ) -> DungeonWeightedRewardPoolCategory? {
        let totalWeight = categories.reduce(0) { $0 + $1.1 }
        guard totalWeight > 0 else { return nil }
        var roll = randomizer.nextIndex(upperBound: totalWeight)
        return categories.first { category in
            if roll < category.1 { return true }
            roll -= category.1
            return false
        }?.0
    }
}

/// 1 回の塔挑戦でフロア間に引き継ぐ最小状態
public struct DungeonRunState: Codable, Equatable, Sendable {
    public let dungeonID: String
    /// 0 始まりの現在フロア番号
    public let currentFloorIndex: Int
    /// 次フロアへ持ち越す HP
    public let carriedHP: Int
    /// これまでに完了したフロアの移動手数合計
    public let totalMoveCount: Int
    /// これまでに遷移したフロアの所要時間合計
    public let totalElapsedSeconds: Int
    /// クリア済みフロア数
    public let clearedFloorCount: Int
    /// フロアをまたいで持ち越す所持カードと残り使用回数
    public let rewardInventoryEntries: [DungeonInventoryEntry]
    /// ラン中だけ有効な遺物
    public let relicEntries: [DungeonRelicEntry]
    /// ラン中だけ有効な呪い遺物
    public let curseEntries: [DungeonCurseEntry]
    /// ラン中に取得済みの宝箱 ID
    public let collectedDungeonRelicPickupIDs: Set<String>
    /// 成長塔の拾得/報酬カード変化に使うラン単位の seed
    public let cardVariationSeed: UInt64?
    /// ラン中に固定される基本移動スタイル
    public let movementStyle: DungeonMovementStyle
    /// 基本移動固定枠を除いた、塔ラン中の通常カード所持上限
    public let dungeonInventoryKindLimit: Int
    /// 試練塔の手札拡張が次に出る確率段階。0 が 2%、1 が 4%。
    public let rogueHandExpansionChanceStep: Int
    /// 試練塔のフロア生成に使うラン単位の seed
    public let rogueTowerSeed: UInt64?
    /// フロアごとのひび割れ床状態
    public let crackedFloorPointsByFloor: [Int: Set<GridPoint>]
    /// フロアごとの崩落床状態
    public let collapsedFloorPointsByFloor: [Int: Set<GridPoint>]
    /// クリア済みフロアへ落下で戻るときに使うフロア別盤面状態
    public let clearedFloorStatesByFloor: [Int: DungeonClearedFloorState]
    /// 落下で次フロアへ入る場合の着地点
    public let pendingFallLandingPoint: GridPoint?
    /// 成長塔の区間内で罠/床崩落ダメージを無効化できる残り回数
    public let hazardDamageMitigationsRemaining: Int
    /// 成長塔の区間内で敵ダメージを無効化できる残り回数
    public let enemyDamageMitigationsRemaining: Int
    /// 成長塔の区間内でメテオ着弾ダメージを無効化できる残り回数
    public let markerDamageMitigationsRemaining: Int
    /// プレイヤーがラン中に振り返るための時系列履歴
    public let runLogEntries: [DungeonRunLogEntry]

    public init(
        dungeonID: String,
        currentFloorIndex: Int = 0,
        carriedHP: Int,
        totalMoveCount: Int = 0,
        totalElapsedSeconds: Int = 0,
        clearedFloorCount: Int = 0,
        rewardInventoryEntries: [DungeonInventoryEntry] = [],
        relicEntries: [DungeonRelicEntry] = [],
        curseEntries: [DungeonCurseEntry] = [],
        collectedDungeonRelicPickupIDs: Set<String> = [],
        cardVariationSeed: UInt64? = nil,
        movementStyle: DungeonMovementStyle = .orthogonal,
        dungeonInventoryKindLimit: Int = 9,
        rogueHandExpansionChanceStep: Int = 0,
        rogueTowerSeed: UInt64? = nil,
        crackedFloorPointsByFloor: [Int: Set<GridPoint>] = [:],
        collapsedFloorPointsByFloor: [Int: Set<GridPoint>] = [:],
        clearedFloorStatesByFloor: [Int: DungeonClearedFloorState] = [:],
        pendingFallLandingPoint: GridPoint? = nil,
        hazardDamageMitigationsRemaining: Int = 0,
        enemyDamageMitigationsRemaining: Int = 0,
        markerDamageMitigationsRemaining: Int = 0,
        runLogEntries: [DungeonRunLogEntry] = []
    ) {
        self.dungeonID = dungeonID
        self.currentFloorIndex = max(currentFloorIndex, 0)
        self.carriedHP = max(carriedHP, 1)
        self.totalMoveCount = max(totalMoveCount, 0)
        self.totalElapsedSeconds = max(totalElapsedSeconds, 0)
        self.clearedFloorCount = max(clearedFloorCount, 0)
        self.rewardInventoryEntries = DungeonRunState.mergedRewardEntries(rewardInventoryEntries)
        self.relicEntries = DungeonRunState.mergedRelicEntries(relicEntries)
        self.curseEntries = DungeonRunState.mergedCurseEntries(curseEntries)
        self.collectedDungeonRelicPickupIDs = collectedDungeonRelicPickupIDs
        self.cardVariationSeed = cardVariationSeed
        self.movementStyle = movementStyle
        self.dungeonInventoryKindLimit = min(max(dungeonInventoryKindLimit, 1), 9)
        self.rogueHandExpansionChanceStep = max(rogueHandExpansionChanceStep, 0)
        self.rogueTowerSeed = rogueTowerSeed
        self.crackedFloorPointsByFloor = crackedFloorPointsByFloor.filter { !$0.value.isEmpty }
        self.collapsedFloorPointsByFloor = collapsedFloorPointsByFloor.filter { !$0.value.isEmpty }
        self.clearedFloorStatesByFloor = clearedFloorStatesByFloor
        self.pendingFallLandingPoint = pendingFallLandingPoint
        self.hazardDamageMitigationsRemaining = max(hazardDamageMitigationsRemaining, 0)
        self.enemyDamageMitigationsRemaining = max(enemyDamageMitigationsRemaining, 0)
        self.markerDamageMitigationsRemaining = max(markerDamageMitigationsRemaining, 0)
        self.runLogEntries = DungeonRunLogEntry.trimmed(runLogEntries)
    }

    public var floorNumber: Int {
        currentFloorIndex + 1
    }

    public var rogueHandExpansionChancePercent: Int {
        min(max(rogueHandExpansionChanceStep + 1, 1) * 2, 100)
    }

    public func rogueHandExpansionSpawnSurface(
        floorIndex: Int,
        seed: UInt64
    ) -> DungeonHandExpansionSpawnSurface? {
        guard dungeonInventoryKindLimit < 9 else { return nil }
        var randomizer = DungeonCardVariationRandomizer(
            seed: seed,
            floorIndex: max(floorIndex, 0),
            salt: 0x48_61_6E_64
        )
        guard randomizer.nextIndex(upperBound: 100) < rogueHandExpansionChancePercent else {
            return nil
        }
        return randomizer.nextIndex(upperBound: 2) == 0 ? .floorPickup : .clearReward
    }

    public func advancedToNextFloor(
        carryoverHP: Int,
        currentFloorMoveCount: Int,
        currentFloorElapsedSeconds: Int = 0,
        rewardMoveCard: MoveCard? = nil,
        rewardSelection: DungeonRewardSelection? = nil,
        currentInventoryEntries: [DungeonInventoryEntry]? = nil,
        currentRelicEntries: [DungeonRelicEntry]? = nil,
        currentCurseEntries: [DungeonCurseEntry]? = nil,
        collectedDungeonSpecialPickupIDs: Set<String> = [],
        collectedDungeonRelicPickupIDs: Set<String>? = nil,
        rewardAddUses: Int = 2,
        supportRewardAddUses: Int = 1,
        areDungeonRelicAndCurseEffectsEnabled: Bool = true,
        completedWithinHalfTurnLimit: Bool = false,
        startedFloorWithEnemies: Bool = false,
        currentFloorDefeatedEnemyCount: Int = 0,
        hazardDamageMitigationsRemaining: Int? = nil,
        enemyDamageMitigationsRemaining: Int? = nil,
        markerDamageMitigationsRemaining: Int? = nil,
        currentRunLogEntries: [DungeonRunLogEntry]? = nil,
        currentFloorVisitedPoints: Set<GridPoint> = [],
        currentFloorCrackedPoints: Set<GridPoint> = [],
        currentFloorCollapsedPoints: Set<GridPoint> = [],
        currentFloorConsumedHealingTilePoints: Set<GridPoint> = [],
        currentFloorConsumedDamageTrapPoints: Set<GridPoint> = [],
        currentFloorCollectedDungeonCardPickupIDs: Set<String> = [],
        currentFloorCollectedDungeonSpecialPickupIDs: Set<String> = [],
        currentFloorEnemyStates: [EnemyState] = [],
        isCurrentFloorDungeonExitUnlocked: Bool = true,
        currentRewardOffers: [DungeonRewardOffer] = []
    ) -> DungeonRunState {
        let sourceEntries = currentInventoryEntries ?? rewardInventoryEntries
        let carriedEntries = sourceEntries.compactMap { $0.carryingAllUsesAsReward() }
        let selection = rewardSelection ?? rewardMoveCard.map { DungeonRewardSelection.add($0) }
        let currentEffectRelicEntries = areDungeonRelicAndCurseEffectsEnabled ? (currentRelicEntries ?? relicEntries) : []
        let currentEffectCurseEntries = areDungeonRelicAndCurseEffectsEnabled ? (currentCurseEntries ?? curseEntries) : []
        let updatedRewardInventoryEntries = DungeonRunState.applying(
            selection,
            to: carriedEntries,
            sourceEntries: sourceEntries,
            relicEntries: currentEffectRelicEntries,
            curseEntries: currentEffectCurseEntries,
            rewardAddUses: rewardAddUses,
            supportRewardAddUses: supportRewardAddUses
        )
        let selectedRelicEntries = DungeonRunState.applyingRelicReward(
            selection,
            to: currentRelicEntries ?? relicEntries
        )
        let selectedCurseEntries = DungeonRunState.curseEntriesAfterRewardSelection(
            areDungeonRelicAndCurseEffectsEnabled ? selection : nil,
            entries: currentCurseEntries ?? curseEntries
        )
        let floorStartRelicResult = areDungeonRelicAndCurseEffectsEnabled
            ? DungeonRunState.applyingFloorStartRelicHealing(to: selectedRelicEntries)
            : (entries: selectedRelicEntries, hpBonus: 0)
        let carriedRelics = DungeonRunState.relicEntriesForNextFloor(floorStartRelicResult.entries)
        let carriedCurses = DungeonRunState.curseEntriesForNextFloor(selectedCurseEntries)
        let effectRelicEntries = areDungeonRelicAndCurseEffectsEnabled ? floorStartRelicResult.entries : []
        let effectCurseEntries = areDungeonRelicAndCurseEffectsEnabled ? selectedCurseEntries : []
        let effectSelection = areDungeonRelicAndCurseEffectsEnabled ? selection : nil
        let rewardRelicAdjustedHP = DungeonRunState.carryoverHP(
            carryoverHP,
            afterSelectingRelicReward: effectSelection,
            relicEntries: effectRelicEntries,
            curseEntries: effectCurseEntries
        )
        let obsidianHeartPenalty = effectCurseEntries.contains { $0.curseID == .obsidianHeart } ? 1 : 0
        let hasSlowWarpedHourglassClear = !completedWithinHalfTurnLimit && effectCurseEntries.contains {
            $0.curseID == .warpedHourglass
        }
        let warpedHourglassPenalty = hasSlowWarpedHourglassClear ? 1 : 0
        let quartermasterPenalty = startedFloorWithEnemies
            && currentFloorDefeatedEnemyCount == 0
            && effectCurseEntries.contains { $0.curseID == .quartermasterBell }
            ? 1
            : 0
        let adjustedCarryoverHP = max(
            rewardRelicAdjustedHP - obsidianHeartPenalty - warpedHourglassPenalty - quartermasterPenalty,
            1
        )
        var floorStartHP = adjustedCarryoverHP
            + floorStartRelicResult.hpBonus
            + (effectRelicEntries.contains { $0.relicID == .immortalHeart } ? 1 : 0)
            + (effectCurseEntries.contains { $0.curseID == .ashHeart } ? 2 : 0)
            + (completedWithinHalfTurnLimit && effectCurseEntries.contains { $0.curseID == .expressTicket } ? 3 : 0)
        if floorStartHP <= 2, effectRelicEntries.contains(where: { $0.relicID == .travelerRation }) {
            floorStartHP += 1
        }
        if effectCurseEntries.contains(where: { $0.curseID == .gildedSeal }) {
            floorStartHP = min(floorStartHP, 2)
        }
        var updatedRunLogEntries = currentRunLogEntries ?? runLogEntries
        if case .addRelic(let relicID) = selection {
            let nextSequence = (updatedRunLogEntries.last?.sequence ?? -1) + 1
            updatedRunLogEntries.append(
                DungeonRunLogEntry(
                    sequence: nextSequence,
                    floorNumber: floorNumber,
                    turn: currentFloorMoveCount,
                    point: nil,
                    kind: .acquisition,
                    message: "報酬レリック「\(relicID.displayName)」を取得"
                )
            )
            if rewardRelicAdjustedHP != carryoverHP {
                let delta = rewardRelicAdjustedHP - carryoverHP
                let sign = delta > 0 ? "+" : ""
                updatedRunLogEntries.append(
                    DungeonRunLogEntry(
                        sequence: nextSequence + 1,
                        floorNumber: floorNumber,
                        turn: currentFloorMoveCount,
                        point: nil,
                        kind: delta > 0 ? .healing : .damage,
                        hpBefore: carryoverHP,
                        hpAfter: rewardRelicAdjustedHP,
                        message: "\(relicID.displayName)でHP \(sign)\(delta)（HP \(carryoverHP)→\(rewardRelicAdjustedHP)）"
                    )
                )
            }
        }
        let didCollectHandExpansion = collectedDungeonSpecialPickupIDs.contains { id in
            id.contains("-hand-expansion")
        } || selection == .handExpansion
        let nextInventoryKindLimit = didCollectHandExpansion
            ? min(dungeonInventoryKindLimit + 1, 9)
            : dungeonInventoryKindLimit
        if selection == .handExpansion {
            let nextSequence = (updatedRunLogEntries.last?.sequence ?? -1) + 1
            updatedRunLogEntries.append(
                DungeonRunLogEntry(
                    sequence: nextSequence,
                    floorNumber: floorNumber,
                    turn: currentFloorMoveCount,
                    point: nil,
                    kind: .acquisition,
                    message: "報酬で手札拡張を取得（所持枠 \(dungeonInventoryKindLimit)→\(nextInventoryKindLimit)）"
                )
            )
        }
        let recordedClearState = DungeonClearedFloorState(
            visitedPoints: currentFloorVisitedPoints,
            crackedFloorPoints: currentFloorCrackedPoints,
            collapsedFloorPoints: currentFloorCollapsedPoints,
            consumedHealingTilePoints: currentFloorConsumedHealingTilePoints,
            consumedDamageTrapPoints: currentFloorConsumedDamageTrapPoints,
            collectedDungeonCardPickupIDs: currentFloorCollectedDungeonCardPickupIDs,
            collectedDungeonSpecialPickupIDs: currentFloorCollectedDungeonSpecialPickupIDs,
            collectedDungeonRelicPickupIDs: collectedDungeonRelicPickupIDs ?? [],
            enemyStates: currentFloorEnemyStates,
            isDungeonExitUnlocked: isCurrentFloorDungeonExitUnlocked,
            rewardOffers: currentRewardOffers
        )
        var clearedStates = clearedFloorStatesByFloor
        clearedStates[currentFloorIndex] = (clearedStates[currentFloorIndex] ?? recordedClearState)
            .recordingRewardSelection(selection, currentRewardOffers: currentRewardOffers)
        return DungeonRunState(
            dungeonID: dungeonID,
            currentFloorIndex: currentFloorIndex + 1,
            carriedHP: floorStartHP,
            totalMoveCount: totalMoveCount + max(currentFloorMoveCount, 0),
            totalElapsedSeconds: totalElapsedSeconds + max(currentFloorElapsedSeconds, 0),
            clearedFloorCount: clearedFloorCount + 1,
            rewardInventoryEntries: updatedRewardInventoryEntries.compactMap { $0.carryingRewardUsesOnly() },
            relicEntries: carriedRelics,
            curseEntries: carriedCurses,
            collectedDungeonRelicPickupIDs: self.collectedDungeonRelicPickupIDs.union(collectedDungeonRelicPickupIDs ?? []),
            cardVariationSeed: cardVariationSeed,
            movementStyle: movementStyle,
            dungeonInventoryKindLimit: nextInventoryKindLimit,
            rogueHandExpansionChanceStep: didCollectHandExpansion ? 0 : rogueHandExpansionChanceStep + 1,
            rogueTowerSeed: rogueTowerSeed,
            crackedFloorPointsByFloor: crackedFloorPointsByFloor,
            collapsedFloorPointsByFloor: collapsedFloorPointsByFloor,
            clearedFloorStatesByFloor: clearedStates,
            hazardDamageMitigationsRemaining: hazardDamageMitigationsRemaining ?? self.hazardDamageMitigationsRemaining,
            enemyDamageMitigationsRemaining: enemyDamageMitigationsRemaining ?? self.enemyDamageMitigationsRemaining,
            markerDamageMitigationsRemaining: markerDamageMitigationsRemaining ?? self.markerDamageMitigationsRemaining,
            runLogEntries: updatedRunLogEntries
        )
    }

    public func fallenToPreviousFloor(
        carryoverHP: Int,
        currentFloorMoveCount: Int,
        currentFloorElapsedSeconds: Int = 0,
        currentInventoryEntries: [DungeonInventoryEntry],
        currentRelicEntries: [DungeonRelicEntry]? = nil,
        currentCurseEntries: [DungeonCurseEntry]? = nil,
        collectedDungeonSpecialPickupIDs: Set<String> = [],
        collectedDungeonRelicPickupIDs: Set<String> = [],
        landingPoint: GridPoint,
        currentFloorCrackedPoints: Set<GridPoint>,
        currentFloorCollapsedPoints: Set<GridPoint>,
        hazardDamageMitigationsRemaining: Int? = nil,
        enemyDamageMitigationsRemaining: Int? = nil,
        markerDamageMitigationsRemaining: Int? = nil,
        currentRunLogEntries: [DungeonRunLogEntry]? = nil
    ) -> DungeonRunState {
        let recordedState = recordingFloorState(
            floorIndex: currentFloorIndex,
            cracked: currentFloorCrackedPoints,
            collapsed: currentFloorCollapsedPoints
        )
        let currentInventoryKindLimit = collectedDungeonSpecialPickupIDs.contains { $0.contains("-hand-expansion") }
            ? min(dungeonInventoryKindLimit + 1, 9)
            : dungeonInventoryKindLimit
        return DungeonRunState(
            dungeonID: dungeonID,
            currentFloorIndex: max(currentFloorIndex - 1, 0),
            carriedHP: carryoverHP,
            totalMoveCount: totalMoveCount + max(currentFloorMoveCount, 0),
            totalElapsedSeconds: totalElapsedSeconds + max(currentFloorElapsedSeconds, 0),
            clearedFloorCount: clearedFloorCount,
            rewardInventoryEntries: currentInventoryEntries.compactMap { $0.carryingRewardUsesOnly() },
            relicEntries: currentRelicEntries ?? relicEntries,
            curseEntries: currentCurseEntries ?? curseEntries,
            collectedDungeonRelicPickupIDs: self.collectedDungeonRelicPickupIDs.union(collectedDungeonRelicPickupIDs),
            cardVariationSeed: cardVariationSeed,
            movementStyle: movementStyle,
            dungeonInventoryKindLimit: currentInventoryKindLimit,
            rogueHandExpansionChanceStep: rogueHandExpansionChanceStep,
            rogueTowerSeed: rogueTowerSeed,
            crackedFloorPointsByFloor: recordedState.crackedFloorPointsByFloor,
            collapsedFloorPointsByFloor: recordedState.collapsedFloorPointsByFloor,
            clearedFloorStatesByFloor: recordedState.clearedFloorStatesByFloor,
            pendingFallLandingPoint: landingPoint,
            hazardDamageMitigationsRemaining: hazardDamageMitigationsRemaining ?? self.hazardDamageMitigationsRemaining,
            enemyDamageMitigationsRemaining: enemyDamageMitigationsRemaining ?? self.enemyDamageMitigationsRemaining,
            markerDamageMitigationsRemaining: markerDamageMitigationsRemaining ?? self.markerDamageMitigationsRemaining,
            runLogEntries: currentRunLogEntries ?? runLogEntries
        )
    }

    public func revivedAtPreviousFloor(
        floorIndex destinationFloorIndex: Int,
        currentFloorMoveCount: Int,
        currentFloorElapsedSeconds: Int = 0,
        currentInventoryEntries: [DungeonInventoryEntry],
        currentRelicEntries: [DungeonRelicEntry],
        currentCurseEntries: [DungeonCurseEntry],
        collectedDungeonSpecialPickupIDs: Set<String> = [],
        collectedDungeonRelicPickupIDs: Set<String>,
        hazardDamageMitigationsRemaining: Int,
        enemyDamageMitigationsRemaining: Int,
        markerDamageMitigationsRemaining: Int,
        currentRunLogEntries: [DungeonRunLogEntry]
    ) -> DungeonRunState {
        let normalizedDestination = max(destinationFloorIndex, 0)
        var crackedByFloor = crackedFloorPointsByFloor
        var collapsedByFloor = collapsedFloorPointsByFloor
        crackedByFloor.removeValue(forKey: normalizedDestination)
        collapsedByFloor.removeValue(forKey: normalizedDestination)
        let currentInventoryKindLimit = collectedDungeonSpecialPickupIDs.contains { $0.contains("-hand-expansion") }
            ? min(dungeonInventoryKindLimit + 1, 9)
            : dungeonInventoryKindLimit

        return DungeonRunState(
            dungeonID: dungeonID,
            currentFloorIndex: normalizedDestination,
            carriedHP: 1,
            totalMoveCount: totalMoveCount + max(currentFloorMoveCount, 0),
            totalElapsedSeconds: totalElapsedSeconds + max(currentFloorElapsedSeconds, 0),
            clearedFloorCount: clearedFloorCount,
            rewardInventoryEntries: currentInventoryEntries.compactMap { $0.carryingRewardUsesOnly() },
            relicEntries: currentRelicEntries,
            curseEntries: currentCurseEntries,
            collectedDungeonRelicPickupIDs: self.collectedDungeonRelicPickupIDs.union(collectedDungeonRelicPickupIDs),
            cardVariationSeed: cardVariationSeed,
            movementStyle: movementStyle,
            dungeonInventoryKindLimit: currentInventoryKindLimit,
            rogueHandExpansionChanceStep: rogueHandExpansionChanceStep,
            rogueTowerSeed: rogueTowerSeed,
            crackedFloorPointsByFloor: crackedByFloor,
            collapsedFloorPointsByFloor: collapsedByFloor,
            clearedFloorStatesByFloor: clearedFloorStatesByFloor,
            hazardDamageMitigationsRemaining: hazardDamageMitigationsRemaining,
            enemyDamageMitigationsRemaining: enemyDamageMitigationsRemaining,
            markerDamageMitigationsRemaining: markerDamageMitigationsRemaining,
            runLogEntries: currentRunLogEntries
        )
    }

    public func totalMoveCountIncludingCurrentFloor(_ currentFloorMoveCount: Int) -> Int {
        totalMoveCount + max(currentFloorMoveCount, 0)
    }

    public func totalElapsedSecondsIncludingCurrentFloor(_ currentFloorElapsedSeconds: Int) -> Int {
        totalElapsedSeconds + max(currentFloorElapsedSeconds, 0)
    }

    public func crackedFloorPoints(for floorIndex: Int) -> Set<GridPoint> {
        crackedFloorPointsByFloor[floorIndex] ?? []
    }

    public func collapsedFloorPoints(for floorIndex: Int) -> Set<GridPoint> {
        collapsedFloorPointsByFloor[floorIndex] ?? []
    }

    public func clearedFloorState(for floorIndex: Int) -> DungeonClearedFloorState? {
        clearedFloorStatesByFloor[floorIndex]
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
            totalElapsedSeconds: totalElapsedSeconds,
            clearedFloorCount: clearedFloorCount,
            rewardInventoryEntries: rewardInventoryEntries,
            relicEntries: relicEntries,
            curseEntries: curseEntries,
            collectedDungeonRelicPickupIDs: collectedDungeonRelicPickupIDs,
            cardVariationSeed: cardVariationSeed,
            movementStyle: movementStyle,
            dungeonInventoryKindLimit: dungeonInventoryKindLimit,
            rogueHandExpansionChanceStep: rogueHandExpansionChanceStep,
            rogueTowerSeed: rogueTowerSeed,
            crackedFloorPointsByFloor: crackedByFloor,
            collapsedFloorPointsByFloor: collapsedByFloor,
            clearedFloorStatesByFloor: clearedFloorStatesByFloor,
            pendingFallLandingPoint: pendingFallLandingPoint,
            hazardDamageMitigationsRemaining: hazardDamageMitigationsRemaining,
            enemyDamageMitigationsRemaining: enemyDamageMitigationsRemaining,
            markerDamageMitigationsRemaining: markerDamageMitigationsRemaining,
            runLogEntries: runLogEntries
        )
    }

    private enum CodingKeys: String, CodingKey {
        case dungeonID
        case currentFloorIndex
        case carriedHP
        case totalMoveCount
        case totalElapsedSeconds
        case clearedFloorCount
        case rewardInventoryEntries
        case relicEntries
        case curseEntries
        case collectedDungeonRelicPickupIDs
        case cardVariationSeed
        case movementStyle
        case dungeonInventoryKindLimit
        case rogueHandExpansionChanceStep
        case rogueTowerSeed
        case crackedFloorPointsByFloor
        case collapsedFloorPointsByFloor
        case clearedFloorStatesByFloor
        case pendingFallLandingPoint
        case hazardDamageMitigationsRemaining
        case enemyDamageMitigationsRemaining
        case markerDamageMitigationsRemaining
        case runLogEntries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            dungeonID: try container.decode(String.self, forKey: .dungeonID),
            currentFloorIndex: try container.decodeIfPresent(Int.self, forKey: .currentFloorIndex) ?? 0,
            carriedHP: try container.decode(Int.self, forKey: .carriedHP),
            totalMoveCount: try container.decodeIfPresent(Int.self, forKey: .totalMoveCount) ?? 0,
            totalElapsedSeconds: try container.decodeIfPresent(Int.self, forKey: .totalElapsedSeconds) ?? 0,
            clearedFloorCount: try container.decodeIfPresent(Int.self, forKey: .clearedFloorCount) ?? 0,
            rewardInventoryEntries: try container.decodeIfPresent([DungeonInventoryEntry].self, forKey: .rewardInventoryEntries) ?? [],
            relicEntries: try container.decodeIfPresent([LossyDungeonRelicEntry].self, forKey: .relicEntries)?
                .compactMap(\.value) ?? [],
            curseEntries: try container.decodeIfPresent([DungeonCurseEntry].self, forKey: .curseEntries) ?? [],
            collectedDungeonRelicPickupIDs: try container.decodeIfPresent(Set<String>.self, forKey: .collectedDungeonRelicPickupIDs) ?? [],
            cardVariationSeed: try container.decodeIfPresent(UInt64.self, forKey: .cardVariationSeed),
            movementStyle: try container.decodeIfPresent(DungeonMovementStyle.self, forKey: .movementStyle) ?? .orthogonal,
            dungeonInventoryKindLimit: try container.decodeIfPresent(Int.self, forKey: .dungeonInventoryKindLimit) ?? 9,
            rogueHandExpansionChanceStep: try container.decodeIfPresent(Int.self, forKey: .rogueHandExpansionChanceStep) ?? 0,
            rogueTowerSeed: try container.decodeIfPresent(UInt64.self, forKey: .rogueTowerSeed),
            crackedFloorPointsByFloor: try container.decodeIfPresent([Int: Set<GridPoint>].self, forKey: .crackedFloorPointsByFloor) ?? [:],
            collapsedFloorPointsByFloor: try container.decodeIfPresent([Int: Set<GridPoint>].self, forKey: .collapsedFloorPointsByFloor) ?? [:],
            clearedFloorStatesByFloor: try container.decodeIfPresent([Int: DungeonClearedFloorState].self, forKey: .clearedFloorStatesByFloor) ?? [:],
            pendingFallLandingPoint: try container.decodeIfPresent(GridPoint.self, forKey: .pendingFallLandingPoint),
            hazardDamageMitigationsRemaining: try container.decodeIfPresent(Int.self, forKey: .hazardDamageMitigationsRemaining) ?? 0,
            enemyDamageMitigationsRemaining: try container.decodeIfPresent(Int.self, forKey: .enemyDamageMitigationsRemaining) ?? 0,
            markerDamageMitigationsRemaining: try container.decodeIfPresent(Int.self, forKey: .markerDamageMitigationsRemaining) ?? 0,
            runLogEntries: try container.decodeIfPresent([DungeonRunLogEntry].self, forKey: .runLogEntries) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dungeonID, forKey: .dungeonID)
        try container.encode(currentFloorIndex, forKey: .currentFloorIndex)
        try container.encode(carriedHP, forKey: .carriedHP)
        try container.encode(totalMoveCount, forKey: .totalMoveCount)
        try container.encode(totalElapsedSeconds, forKey: .totalElapsedSeconds)
        try container.encode(clearedFloorCount, forKey: .clearedFloorCount)
        try container.encode(rewardInventoryEntries, forKey: .rewardInventoryEntries)
        try container.encode(relicEntries, forKey: .relicEntries)
        try container.encode(curseEntries, forKey: .curseEntries)
        try container.encode(collectedDungeonRelicPickupIDs, forKey: .collectedDungeonRelicPickupIDs)
        try container.encodeIfPresent(cardVariationSeed, forKey: .cardVariationSeed)
        try container.encode(movementStyle, forKey: .movementStyle)
        try container.encode(dungeonInventoryKindLimit, forKey: .dungeonInventoryKindLimit)
        try container.encode(rogueHandExpansionChanceStep, forKey: .rogueHandExpansionChanceStep)
        try container.encodeIfPresent(rogueTowerSeed, forKey: .rogueTowerSeed)
        try container.encode(crackedFloorPointsByFloor, forKey: .crackedFloorPointsByFloor)
        try container.encode(collapsedFloorPointsByFloor, forKey: .collapsedFloorPointsByFloor)
        try container.encode(clearedFloorStatesByFloor, forKey: .clearedFloorStatesByFloor)
        try container.encodeIfPresent(pendingFallLandingPoint, forKey: .pendingFallLandingPoint)
        try container.encode(hazardDamageMitigationsRemaining, forKey: .hazardDamageMitigationsRemaining)
        try container.encode(enemyDamageMitigationsRemaining, forKey: .enemyDamageMitigationsRemaining)
        try container.encode(markerDamageMitigationsRemaining, forKey: .markerDamageMitigationsRemaining)
        try container.encode(runLogEntries, forKey: .runLogEntries)
    }

    private static func mergedRewardEntries(_ entries: [DungeonInventoryEntry]) -> [DungeonInventoryEntry] {
        var result: [DungeonInventoryEntry] = []
        for entry in entries where entry.rewardUses > 0 {
            if let index = result.firstIndex(where: { $0.playable == entry.playable }) {
                result[index].rewardUses += entry.rewardUses
            } else {
                result.append(
                    DungeonInventoryEntry(playable: entry.playable, rewardUses: entry.rewardUses, pickupUses: 0)
                )
            }
        }
        return result
    }

    private static func mergedRelicEntries(_ entries: [DungeonRelicEntry]) -> [DungeonRelicEntry] {
        var result: [DungeonRelicEntry] = []
        for entry in entries {
            if let index = result.firstIndex(where: { $0.relicID == entry.relicID }) {
                result[index].remainingUses = max(result[index].remainingUses, entry.remainingUses)
                result[index].floorStartCharge = max(result[index].floorStartCharge ?? 0, entry.floorStartCharge ?? 0)
                result[index].enemyDefeatProgress = max(result[index].enemyDefeatProgress, entry.enemyDefeatProgress)
            } else {
                result.append(entry)
            }
        }
        return result
    }

    private static func mergedCurseEntries(_ entries: [DungeonCurseEntry]) -> [DungeonCurseEntry] {
        var result: [DungeonCurseEntry] = []
        for entry in entries {
            if let index = result.firstIndex(where: { $0.curseID == entry.curseID }) {
                result[index].remainingUses = max(result[index].remainingUses, entry.remainingUses)
            } else {
                result.append(entry)
            }
        }
        return result
    }

    private static func relicEntriesForNextFloor(_ entries: [DungeonRelicEntry]) -> [DungeonRelicEntry] {
        entries.compactMap { entry in
            switch entry.relicID {
            case _ where entry.relicID.refillsUseAtFloorStart:
                return DungeonRelicEntry(relicID: entry.relicID)
            case .trapperGloves where entry.remainingUses == 1:
                return DungeonRelicEntry(relicID: .trapperGloves, remainingUses: 0)
            case .travelerCanteen where entry.remainingUses <= 0,
                 .moonDewCanteen where entry.remainingUses <= 0:
                return nil
            case .glowingHeart:
                return entry
            default:
                return entry
            }
        }
    }

    private static func applyingFloorStartRelicHealing(
        to entries: [DungeonRelicEntry]
    ) -> (entries: [DungeonRelicEntry], hpBonus: Int) {
        var updatedEntries: [DungeonRelicEntry] = []
        var hpBonus = 0

        for var entry in entries {
            if let interval = entry.relicID.floorStartHealingInterval {
                let nextCharge = (entry.floorStartCharge ?? 0) + 1
                if nextCharge >= interval {
                    hpBonus += 1
                    entry.floorStartCharge = 0
                } else {
                    entry.floorStartCharge = nextCharge
                }
            }

            if entry.relicID.healsAtFloorStartForLimitedUses, entry.remainingUses > 0 {
                hpBonus += 1
                entry.remainingUses -= 1
            }

            updatedEntries.append(entry)
        }

        return (updatedEntries, hpBonus)
    }

    private static func curseEntriesForNextFloor(_ entries: [DungeonCurseEntry]) -> [DungeonCurseEntry] {
        entries.map { entry in
            switch entry.curseID {
            case .lastStandShield:
                return DungeonCurseEntry(curseID: .lastStandShield)
            default:
                return entry
            }
        }
    }

    private static func applying(
        _ selection: DungeonRewardSelection?,
        to entries: [DungeonInventoryEntry],
        sourceEntries: [DungeonInventoryEntry],
        relicEntries: [DungeonRelicEntry],
        curseEntries: [DungeonCurseEntry],
        rewardAddUses: Int = 2,
        supportRewardAddUses: Int = 1
    ) -> [DungeonInventoryEntry] {
        var result = entries
        switch selection {
        case .add(let card):
            let isExistingRewardCard = sourceEntries.contains {
                $0.moveCard == card && $0.hasUsesRemaining
            }
            result.append(
                DungeonInventoryEntry(
                    card: card,
                    rewardUses: adjustedRewardAddUses(
                        rewardAddUses,
                        for: card,
                        relicEntries: relicEntries,
                        curseEntries: curseEntries,
                        isExistingRewardCard: isExistingRewardCard
                    ),
                    pickupUses: 0
                )
            )
        case .addSupport(let support):
            result.append(
                DungeonInventoryEntry(
                    support: support,
                    rewardUses: max(supportRewardAddUses, 1),
                    pickupUses: 0
                )
            )
        case .addRelic:
            break
        case .handExpansion:
            break
        case .carryOverPickup(let card):
            guard sourceEntries.contains(where: { $0.moveCard == card && $0.hasUsesRemaining }) else { break }
            break
        case .remove(let card):
            result.removeAll { $0.moveCard == card }
        case .removeSupport(let support):
            result.removeAll { $0.supportCard == support }
        case .none:
            break
        }
        return result
    }

    public static func adjustedRewardAddUses(
        _ baseUses: Int,
        for card: MoveCard,
        relicEntries: [DungeonRelicEntry],
        curseEntries: [DungeonCurseEntry]
    ) -> Int {
        adjustedRewardAddUses(
            baseUses,
            for: card,
            relicEntries: relicEntries,
            curseEntries: curseEntries,
            isExistingRewardCard: false
        )
    }

    public static func adjustedRewardAddUses(
        _ baseUses: Int,
        for card: MoveCard,
        relicEntries: [DungeonRelicEntry],
        curseEntries: [DungeonCurseEntry],
        isExistingRewardCard: Bool
    ) -> Int {
        var adjustment = 0
        if MoveCard.directionalRayCards.contains(card),
           curseEntries.contains(where: { $0.curseID == .crackedShoes }) {
            adjustment -= 1
        }
        if curseEntries.contains(where: { $0.curseID == .relicHunterBrand }) {
            adjustment -= 1
        }
        return max(baseUses + adjustment, 1)
    }

    public static func adjustedMoveRewardBaseUses(
        _ baseUses: Int,
        relicEntries: [DungeonRelicEntry],
        curseEntries: [DungeonCurseEntry]
    ) -> Int {
        let heavyCrownBonus = relicEntries.contains { $0.relicID == .heavyCrown } ? 1 : 0
        let royalCrownBonus = relicEntries.contains { $0.relicID == .royalCrown } ? 1 : 0
        let sageCodexBonus = relicEntries.contains { $0.relicID == .sageCodex } ? 1 : 0
        let cursedCrownBonus = curseEntries.contains { $0.curseID == .cursedCrown } ? 3 : 0
        let trapMagnetBonus = curseEntries.contains { $0.curseID == .trapMagnet } ? 2 : 0
        let contractCodexBonus = curseEntries.contains { $0.curseID == .contractCodex } ? 3 : 0
        let royalIouBonus = curseEntries.contains { $0.curseID == .royalIou } ? 2 : 0
        let cursePenalty = curseEntries.contains { $0.curseID == .bloodPact && $0.remainingUses > 0 } ? 1 : 0
        let greedyBagPenalty = curseEntries.contains { $0.curseID == .greedyBag } ? 2 : 0
        let relicHunterPenalty = curseEntries.contains { $0.curseID == .relicHunterBrand } ? 1 : 0
        let supportOathPenalty = curseEntries.contains { $0.curseID == .supportOath } ? 1 : 0
        return max(
            baseUses + heavyCrownBonus + royalCrownBonus + sageCodexBonus + cursedCrownBonus + trapMagnetBonus
                + contractCodexBonus + royalIouBonus
                - cursePenalty - greedyBagPenalty - relicHunterPenalty - supportOathPenalty,
            1
        )
    }

    public static func adjustedSupportRewardUses(
        _ baseUses: Int,
        relicEntries: [DungeonRelicEntry],
        curseEntries: [DungeonCurseEntry]
    ) -> Int {
        let twinPouchBonus = relicEntries.contains { $0.relicID == .twinPouch } ? 1 : 0
        let royalCrownBonus = relicEntries.contains { $0.relicID == .royalCrown } ? 1 : 0
        let sageCodexBonus = relicEntries.contains { $0.relicID == .sageCodex } ? 1 : 0
        let frayedMemoryBonus = curseEntries.contains { $0.curseID == .frayedMemory } ? 1 : 0
        let trapMagnetBonus = curseEntries.contains { $0.curseID == .trapMagnet } ? 2 : 0
        let contractCodexBonus = curseEntries.contains { $0.curseID == .contractCodex } ? 3 : 0
        let royalIouBonus = curseEntries.contains { $0.curseID == .royalIou } ? 2 : 0
        let supportOathBonus = curseEntries.contains { $0.curseID == .supportOath } ? 3 : 0
        let relicHunterPenalty = curseEntries.contains { $0.curseID == .relicHunterBrand } ? 1 : 0
        return max(
            baseUses + twinPouchBonus + royalCrownBonus + sageCodexBonus + trapMagnetBonus + frayedMemoryBonus
                + contractCodexBonus + royalIouBonus + supportOathBonus - relicHunterPenalty,
            1
        )
    }

    private static func applyingRelicReward(
        _ selection: DungeonRewardSelection?,
        to entries: [DungeonRelicEntry]
    ) -> [DungeonRelicEntry] {
        guard case .addRelic(let relicID) = selection,
              !entries.contains(where: { $0.relicID == relicID })
        else { return entries }
        return entries + [DungeonRelicEntry(relicID: relicID)]
    }

    private static func curseEntriesAfterRewardSelection(
        _ selection: DungeonRewardSelection?,
        entries: [DungeonCurseEntry]
    ) -> [DungeonCurseEntry] {
        guard case .add = selection else { return entries }
        var result = entries
        guard let index = result.firstIndex(where: { $0.curseID == .bloodPact && $0.remainingUses > 0 }) else {
            return result
        }
        result[index].remainingUses -= 1
        return result
    }

    private static func carryoverHP(
        _ hp: Int,
        afterSelectingRelicReward selection: DungeonRewardSelection?,
        relicEntries: [DungeonRelicEntry] = [],
        curseEntries: [DungeonCurseEntry] = []
    ) -> Int {
        let taxCollectorPenalty = selection != nil && curseEntries.contains(where: { $0.curseID == .taxCollector }) ? 1 : 0
        let royalIouPenalty = selection != nil && curseEntries.contains(where: { $0.curseID == .royalIou }) ? 2 : 0
        let merchantsScaleBonus = {
            guard case .addRelic = selection,
                  relicEntries.contains(where: { $0.relicID == .merchantsScale })
            else { return 0 }
            return 1
        }()
        let baseHP = max(hp + merchantsScaleBonus - taxCollectorPenalty - royalIouPenalty, 1)
        guard case .addRelic(let relicID) = selection else { return baseHP }
        switch relicID {
        case .crackedShield:
            return baseHP
        case .glowingHeart:
            return baseHP + 2
        case .woodenAmulet:
            return baseHP + 1
        case .heavyCrown, .oldMap, .blackFeather, .chippedHourglass,
             .travelerBoots, .silverNeedle, .starCup, .distantStarCup, .crackedStarCup,
             .explorerBag, .moonMirror, .victoryBanner,
             .windcutFeather, .guardianIncense, .trapperGloves, .whiteChalk, .spareTorch,
             .oldRope, .twinPouch, .gamblerCoin, .royalCrown, .immortalHeart, .guardianAegis,
             .stargazerHourglass, .copperHourglass, .travelerRation, .travelerCanteen, .moonDewCanteen,
             .smallLantern, .dullNeedle,
             .patchedRope, .fieldMedkit, .scoutCompass, .quickSheath, .purifyingCharm, .greatPurifyingCharm,
             .phoenixFeather, .sageCodex, .lavaCharm, .lavaLantern, .watcherMask, .railWedge,
             .railSign, .smokeDecoy, .chaserWhistle, .starVeil,
             .trapSole, .emberCloak, .watcherMonocle, .railCharm,
             .chaserDecoy, .antidoteStone, .greaterAntidoteStone, .starUmbrella, .guardianCloak,
             .fallAnchor, .foldingMap, .phantomTicket,
             .campfireCoal, .merchantsScale, .barrierCharm, .barrierTalisman, .frostBell, .rewindingHourglass,
             .slayerPouch, .hunterBanner, .intimidationHorn, .slayerMedal,
             .nightCardLens, .thornScoutLens, .magmaScoutLens, .trapScoutLens, .enemyScoutLens:
            return baseHP
        }
    }

    public static func rewardUses(for support: SupportCard) -> Int {
        switch support {
        case .refillEmptySlots, .singleAnnihilationSpell, .annihilationSpell, .freezeSpell, .barrierSpell, .darknessSpell, .railBreakSpell, .flySpell, .antidote, .panacea:
            return 1
        }
    }
}

/// ダンジョン失敗条件
public struct DungeonFailureRule: Codable, Equatable, Sendable {
    /// 初期 HP。0 以下は 1 として扱う
    public var initialHP: Int
    /// フロア内の疲労開始手数。nil の場合は疲労ダメージなし
    public var turnLimit: Int?

    public init(initialHP: Int, turnLimit: Int? = nil) {
        self.initialHP = max(initialHP, 1)
        self.turnLimit = turnLimit.map { max($0, 1) }
    }
}

/// ダンジョン出口を開けるために踏む必要がある鍵マス
public struct DungeonExitLock: Codable, Equatable, Sendable {
    public let unlockPoint: GridPoint

    public init(unlockPoint: GridPoint) {
        self.unlockPoint = unlockPoint
    }
}

/// 上階の崩落穴からだけ入れる宝箱小部屋の定義
public struct DungeonFallSecretDefinition: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let sourceFloorIndex: Int
    public let entrancePoint: GridPoint
    public let destinationFloorIndex: Int
    public let landingPoint: GridPoint
    public let treasurePickup: DungeonRelicPickupDefinition
    public let returnWarpPoint: GridPoint
    public let returnDestination: GridPoint
    public let chamberWallPoints: Set<GridPoint>

    public init(
        id: String,
        sourceFloorIndex: Int,
        entrancePoint: GridPoint,
        destinationFloorIndex: Int,
        landingPoint: GridPoint,
        treasurePickup: DungeonRelicPickupDefinition,
        returnWarpPoint: GridPoint,
        returnDestination: GridPoint,
        chamberWallPoints: Set<GridPoint>
    ) {
        self.id = id
        self.sourceFloorIndex = sourceFloorIndex
        self.entrancePoint = entrancePoint
        self.destinationFloorIndex = destinationFloorIndex
        self.landingPoint = landingPoint
        self.treasurePickup = treasurePickup
        self.returnWarpPoint = returnWarpPoint
        self.returnDestination = returnDestination
        self.chamberWallPoints = chamberWallPoints
    }

    public var sourceReservedPoints: Set<GridPoint> {
        [entrancePoint]
    }

    public var destinationReservedPoints: Set<GridPoint> {
        Set([landingPoint, treasurePickup.point, returnWarpPoint, returnDestination]).union(chamberWallPoints)
    }
}

/// 回転見張りの回転方向
public enum RotatingWatcherDirection: String, Codable, Equatable, Sendable {
    case clockwise
    case counterclockwise
}

/// 敵の行動パターン
public enum EnemyBehavior: Codable, Equatable, Sendable {
    /// その場から動かず、隣接マスを警戒する
    case guardPost
    /// 指定経路を順に巡回する
    case patrol(path: [GridPoint])
    /// 指定方向の直線を見張る
    case watcher(direction: MoveVector, range: Int)
    /// 4方向を右回りまたは左回りに向き直す見張り
    case rotatingWatcher(initialDirection: MoveVector, rotationDirection: RotatingWatcherDirection, range: Int)
    /// プレイヤーへ1マスずつ近づく
    case chaser
    /// 次ターンにメテオが着弾するマスを予告する
    /// - Note: 旧保存データとの互換のため `directions` を保持するが、現行ルールでは `range` を予告数として扱う。
    case marker(directions: [MoveVector], range: Int)
    /// ランダムな着弾予告に加えて、現在のプレイヤー位置も予告する上級メテオ兵
    /// - Note: `directions` は通常メテオ兵と同じ保存互換用で、現行ルールでは `range` をランダム予告数として扱う。
    case targetedMarker(directions: [MoveVector], range: Int)

    private enum CodingKeys: String, CodingKey {
        case type
        case path
        case direction
        case initialDirection
        case rotationDirection
        case directions
        case range
    }

    private enum Kind: String, Codable, Sendable {
        case guardPost
        case patrol
        case watcher
        case rotatingWatcher
        case chaser
        case marker
        case targetedMarker
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
            let legacyDirections = try container.decodeIfPresent([MoveVector].self, forKey: .directions) ?? []
            let initialDirection = try container.decodeIfPresent(MoveVector.self, forKey: .initialDirection)
                ?? legacyDirections.first
                ?? MoveVector(dx: 0, dy: 1)
            let rotationDirection = try container.decodeIfPresent(
                RotatingWatcherDirection.self,
                forKey: .rotationDirection
            ) ?? Self.inferredRotationDirection(from: legacyDirections)
            self = .rotatingWatcher(
                initialDirection: initialDirection,
                rotationDirection: rotationDirection,
                range: try container.decodeIfPresent(Int.self, forKey: .range) ?? 1
            )
        case .chaser:
            self = .chaser
        case .marker:
            self = .marker(
                directions: try container.decodeIfPresent([MoveVector].self, forKey: .directions) ?? [],
                range: try container.decodeIfPresent(Int.self, forKey: .range) ?? 1
            )
        case .targetedMarker:
            self = .targetedMarker(
                directions: try container.decodeIfPresent([MoveVector].self, forKey: .directions) ?? [],
                range: try container.decodeIfPresent(Int.self, forKey: .range) ?? 1
            )
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
        case .rotatingWatcher(let initialDirection, let rotationDirection, let range):
            try container.encode(Kind.rotatingWatcher, forKey: .type)
            try container.encode(initialDirection, forKey: .initialDirection)
            try container.encode(rotationDirection, forKey: .rotationDirection)
            try container.encode(range, forKey: .range)
        case .chaser:
            try container.encode(Kind.chaser, forKey: .type)
        case .marker(let directions, let range):
            try container.encode(Kind.marker, forKey: .type)
            try container.encode(directions, forKey: .directions)
            try container.encode(range, forKey: .range)
        case .targetedMarker(let directions, let range):
            try container.encode(Kind.targetedMarker, forKey: .type)
            try container.encode(directions, forKey: .directions)
            try container.encode(range, forKey: .range)
        }
    }

    private static func inferredRotationDirection(from directions: [MoveVector]) -> RotatingWatcherDirection {
        let normalized = directions.compactMap(normalizedOrthogonalDirection)
        guard normalized.count >= 2,
              let firstIndex = rotatingWatcherClockwiseDirections.firstIndex(of: normalized[0]),
              let secondIndex = rotatingWatcherClockwiseDirections.firstIndex(of: normalized[1])
        else {
            return .clockwise
        }

        let clockwiseIndex = (firstIndex + 1) % rotatingWatcherClockwiseDirections.count
        let counterclockwiseIndex = (
            firstIndex + rotatingWatcherClockwiseDirections.count - 1
        ) % rotatingWatcherClockwiseDirections.count
        if secondIndex == counterclockwiseIndex {
            return .counterclockwise
        }
        if secondIndex == clockwiseIndex {
            return .clockwise
        }
        return .clockwise
    }

    static func normalizedOrthogonalDirection(_ direction: MoveVector) -> MoveVector? {
        let dx = direction.dx == 0 ? 0 : (direction.dx > 0 ? 1 : -1)
        let dy = direction.dy == 0 ? 0 : (direction.dy > 0 ? 1 : -1)
        guard abs(dx) + abs(dy) == 1 else { return nil }
        return MoveVector(dx: dx, dy: dy)
    }

    static let rotatingWatcherClockwiseDirections: [MoveVector] = [
        MoveVector(dx: 0, dy: 1),
        MoveVector(dx: 1, dy: 0),
        MoveVector(dx: 0, dy: -1),
        MoveVector(dx: -1, dy: 0)
    ]
}

/// フロア開始時に配置する敵
public struct EnemyDefinition: Codable, Equatable, Identifiable, Sendable {
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
public struct EnemyState: Codable, Equatable, Identifiable, Sendable {
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
        patrolIndex = Self.initialPatrolIndex(position: definition.position, behavior: definition.behavior)
        rotationIndex = 0
    }

    private static func initialPatrolIndex(position: GridPoint, behavior: EnemyBehavior) -> Int {
        guard case .patrol(let path) = behavior else { return 0 }
        return path.firstIndex(of: position) ?? 0
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

/// 敵ターン中に各敵がどの状態からどの状態へ進んだかを UI へ伝える差分
public struct DungeonEnemyTurnTransition: Equatable, Identifiable, Sendable {
    public let enemyID: String
    public let name: String
    public let before: EnemyState
    public let after: EnemyState
    public let warpPoint: GridPoint?

    public var id: String { enemyID }
    public var didMove: Bool { before.position != after.position || warpPoint != nil }
    public var didRotate: Bool { before.rotationIndex != after.rotationIndex }

    public init(
        enemyID: String,
        name: String,
        before: EnemyState,
        after: EnemyState,
        warpPoint: GridPoint? = nil
    ) {
        self.enemyID = enemyID
        self.name = name
        self.before = before
        self.after = after
        self.warpPoint = warpPoint
    }
}

/// プレイヤー行動後に発生した敵ターンの可視化用イベント
public struct DungeonEnemyTurnPhase: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let transitions: [DungeonEnemyTurnTransition]
    public let attackedPlayer: Bool
    public let hpBefore: Int
    public let hpAfter: Int

    public init(
        id: UUID = UUID(),
        transitions: [DungeonEnemyTurnTransition],
        attackedPlayer: Bool,
        hpBefore: Int,
        hpAfter: Int
    ) {
        self.id = id
        self.transitions = transitions
        self.attackedPlayer = attackedPlayer
        self.hpBefore = max(hpBefore, 0)
        self.hpAfter = max(hpAfter, 0)
    }
}

public struct DungeonEnemyTurnEvent: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let phases: [DungeonEnemyTurnPhase]
    public let isParalysisRest: Bool
    public let paralysisTrapPoint: GridPoint?

    public var transitions: [DungeonEnemyTurnTransition] {
        phases.flatMap(\.transitions)
    }

    public var attackedPlayer: Bool {
        phases.contains { $0.attackedPlayer }
    }

    public var hpBefore: Int {
        phases.first?.hpBefore ?? 0
    }

    public var hpAfter: Int {
        phases.last?.hpAfter ?? hpBefore
    }

    public init(
        id: UUID = UUID(),
        transitions: [DungeonEnemyTurnTransition],
        attackedPlayer: Bool,
        hpBefore: Int,
        hpAfter: Int,
        isParalysisRest: Bool = false,
        paralysisTrapPoint: GridPoint? = nil
    ) {
        self.init(
            id: id,
            phases: [
                DungeonEnemyTurnPhase(
                    transitions: transitions,
                    attackedPlayer: attackedPlayer,
                    hpBefore: hpBefore,
                    hpAfter: hpAfter
                )
            ],
            isParalysisRest: isParalysisRest,
            paralysisTrapPoint: paralysisTrapPoint
        )
    }

    public init(
        id: UUID = UUID(),
        phases: [DungeonEnemyTurnPhase],
        isParalysisRest: Bool = false,
        paralysisTrapPoint: GridPoint? = nil
    ) {
        self.id = id
        self.phases = phases
        self.isParalysisRest = isParalysisRest
        self.paralysisTrapPoint = paralysisTrapPoint
    }
}

/// 割れる床の初期状態
public enum BrittleFloorInitialState: String, Codable, Equatable, Sendable {
    /// 見た目は通常床。踏むと崩落穴になるが、その踏みでは落下しない
    case hiddenWeak
    /// 目視できるヒビ床。踏むと崩落穴になるが、その踏みでは落下しない
    case cracked
    /// 最初から崩落している穴。入ると落下する
    case collapsed
}

/// 床や罠など、敵以外のフロアギミック
public enum HazardDefinition: Codable, Equatable, Sendable {
    /// 初期状態に応じて、隠し脆い床、ヒビ床、崩落穴として始まる床
    case brittleFloor(points: Set<GridPoint>, initialState: BrittleFloorInitialState = .cracked)
    /// 見えている撒菱。踏むと1ダメージを受け、そのフロア中は消費済みになる
    case damageTrap(points: Set<GridPoint>, damage: Int)
    /// 見えている衰弱罠。踏むと現在 HP に応じた罠ダメージを受ける
    case hpHalvingTrap(points: Set<GridPoint>)
    /// 見えている溶岩床。踏み込みと滞在で2ダメージを受ける
    case lavaTile(points: Set<GridPoint>, damage: Int)
    /// 見えている回復床。1 回踏むと指定量だけ HP が増え、そのフロア中は消費済みになる
    case healingTile(points: Set<GridPoint>, amount: Int)

    private enum CodingKeys: String, CodingKey {
        case type
        case points
        case damage
        case amount
        case initialState
    }

    private enum Kind: String, Codable, Sendable {
        case brittleFloor
        case damageTrap
        case hpHalvingTrap
        case lavaTile
        case healingTile
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        switch kind {
        case .brittleFloor:
            self = .brittleFloor(
                points: try container.decode(Set<GridPoint>.self, forKey: .points),
                initialState: try container.decodeIfPresent(BrittleFloorInitialState.self, forKey: .initialState) ?? .cracked
            )
        case .damageTrap:
            self = .damageTrap(
                points: try container.decode(Set<GridPoint>.self, forKey: .points),
                damage: try container.decodeIfPresent(Int.self, forKey: .damage) ?? 1
            )
        case .hpHalvingTrap:
            self = .hpHalvingTrap(
                points: try container.decode(Set<GridPoint>.self, forKey: .points)
            )
        case .lavaTile:
            self = .lavaTile(
                points: try container.decode(Set<GridPoint>.self, forKey: .points),
                damage: try container.decodeIfPresent(Int.self, forKey: .damage) ?? 1
            )
        case .healingTile:
            self = .healingTile(
                points: try container.decode(Set<GridPoint>.self, forKey: .points),
                amount: try container.decodeIfPresent(Int.self, forKey: .amount) ?? 1
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .brittleFloor(let points, let initialState):
            try container.encode(Kind.brittleFloor, forKey: .type)
            try container.encode(points, forKey: .points)
            if initialState != .cracked {
                try container.encode(initialState, forKey: .initialState)
            }
        case .damageTrap(let points, let damage):
            try container.encode(Kind.damageTrap, forKey: .type)
            try container.encode(points, forKey: .points)
            try container.encode(max(damage, 1), forKey: .damage)
        case .hpHalvingTrap(let points):
            try container.encode(Kind.hpHalvingTrap, forKey: .type)
            try container.encode(points, forKey: .points)
        case .lavaTile(let points, let damage):
            try container.encode(Kind.lavaTile, forKey: .type)
            try container.encode(points, forKey: .points)
            try container.encode(max(damage, 1), forKey: .damage)
        case .healingTile(let points, let amount):
            try container.encode(Kind.healingTile, forKey: .type)
            try container.encode(points, forKey: .points)
            try container.encode(max(amount, 1), forKey: .amount)
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
    public let exitLock: DungeonExitLock?
    public let cardPickups: [DungeonCardPickupDefinition]
    public let specialPickups: [DungeonSpecialPickupDefinition]
    public let relicPickups: [DungeonRelicPickupDefinition]
    public let fallSecrets: [DungeonFallSecretDefinition]
    public let rewardMoveCardsAfterClear: [MoveCard]
    public let rewardSupportCardsAfterClear: [SupportCard]
    public let isDarknessEnabled: Bool

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
        exitLock: DungeonExitLock? = nil,
        cardPickups: [DungeonCardPickupDefinition] = [],
        specialPickups: [DungeonSpecialPickupDefinition] = [],
        relicPickups: [DungeonRelicPickupDefinition] = [],
        fallSecrets: [DungeonFallSecretDefinition] = [],
        rewardMoveCardsAfterClear: [MoveCard] = [],
        rewardSupportCardsAfterClear: [SupportCard] = [],
        isDarknessEnabled: Bool = false
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
        self.exitLock = exitLock
        self.cardPickups = cardPickups
        self.specialPickups = specialPickups
        self.relicPickups = relicPickups
        self.fallSecrets = fallSecrets
        self.isDarknessEnabled = isDarknessEnabled
        var uniqueRewardMoveCards: [MoveCard] = []
        for card in rewardMoveCardsAfterClear where !uniqueRewardMoveCards.contains(card) {
            uniqueRewardMoveCards.append(card)
        }
        self.rewardMoveCardsAfterClear = uniqueRewardMoveCards
        var uniqueRewardSupportCards: [SupportCard] = []
        for card in rewardSupportCardsAfterClear where !uniqueRewardSupportCards.contains(card) {
            uniqueRewardSupportCards.append(card)
        }
        self.rewardSupportCardsAfterClear = uniqueRewardSupportCards
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case boardSize
        case spawnPoint
        case exitPoint
        case deckPreset
        case failureRule
        case enemies
        case hazards
        case impassableTilePoints
        case tileEffectOverrides
        case warpTilePairs
        case exitLock
        case cardPickups
        case specialPickups
        case relicPickups
        case fallSecrets
        case rewardMoveCardsAfterClear
        case rewardSupportCardsAfterClear
        case isDarknessEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            title: try container.decode(String.self, forKey: .title),
            boardSize: try container.decode(Int.self, forKey: .boardSize),
            spawnPoint: try container.decode(GridPoint.self, forKey: .spawnPoint),
            exitPoint: try container.decode(GridPoint.self, forKey: .exitPoint),
            deckPreset: try container.decode(GameDeckPreset.self, forKey: .deckPreset),
            failureRule: try container.decode(DungeonFailureRule.self, forKey: .failureRule),
            enemies: try container.decodeIfPresent([EnemyDefinition].self, forKey: .enemies) ?? [],
            hazards: try container.decodeIfPresent([HazardDefinition].self, forKey: .hazards) ?? [],
            impassableTilePoints: try container.decodeIfPresent(Set<GridPoint>.self, forKey: .impassableTilePoints) ?? [],
            tileEffectOverrides: try container.decodeIfPresent([GridPoint: TileEffect].self, forKey: .tileEffectOverrides) ?? [:],
            warpTilePairs: try container.decodeIfPresent([String: [GridPoint]].self, forKey: .warpTilePairs) ?? [:],
            exitLock: try container.decodeIfPresent(DungeonExitLock.self, forKey: .exitLock),
            cardPickups: try container.decodeIfPresent([DungeonCardPickupDefinition].self, forKey: .cardPickups) ?? [],
            specialPickups: try container.decodeIfPresent([DungeonSpecialPickupDefinition].self, forKey: .specialPickups) ?? [],
            relicPickups: try container.decodeIfPresent([DungeonRelicPickupDefinition].self, forKey: .relicPickups) ?? [],
            fallSecrets: try container.decodeIfPresent([DungeonFallSecretDefinition].self, forKey: .fallSecrets) ?? [],
            rewardMoveCardsAfterClear: try container.decodeIfPresent([MoveCard].self, forKey: .rewardMoveCardsAfterClear) ?? [],
            rewardSupportCardsAfterClear: try container.decodeIfPresent([SupportCard].self, forKey: .rewardSupportCardsAfterClear) ?? [],
            isDarknessEnabled: try container.decodeIfPresent(Bool.self, forKey: .isDarknessEnabled) ?? false
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(boardSize, forKey: .boardSize)
        try container.encode(spawnPoint, forKey: .spawnPoint)
        try container.encode(exitPoint, forKey: .exitPoint)
        try container.encode(deckPreset, forKey: .deckPreset)
        try container.encode(failureRule, forKey: .failureRule)
        try container.encode(enemies, forKey: .enemies)
        try container.encode(hazards, forKey: .hazards)
        try container.encode(impassableTilePoints, forKey: .impassableTilePoints)
        try container.encode(tileEffectOverrides, forKey: .tileEffectOverrides)
        try container.encode(warpTilePairs, forKey: .warpTilePairs)
        try container.encodeIfPresent(exitLock, forKey: .exitLock)
        try container.encode(cardPickups, forKey: .cardPickups)
        try container.encode(specialPickups, forKey: .specialPickups)
        try container.encode(relicPickups, forKey: .relicPickups)
        try container.encode(fallSecrets, forKey: .fallSecrets)
        try container.encode(rewardMoveCardsAfterClear, forKey: .rewardMoveCardsAfterClear)
        try container.encode(rewardSupportCardsAfterClear, forKey: .rewardSupportCardsAfterClear)
        try container.encode(isDarknessEnabled, forKey: .isDarknessEnabled)
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
            identifier: .dungeonFloor,
            displayName: title,
            regulation: GameMode.Regulation(
                boardSize: boardSize,
                handSize: 10,
                nextPreviewCount: 0,
                allowsStacking: true,
                deckPreset: deckPreset,
                bonusMoveCards: [],
                spawnRule: .fixed(resolvedSpawnPoint),
                penalties: GameMode.PenaltySettings(
                    deadlockPenaltyCost: 0,
                    manualRedrawPenaltyCost: 0,
                    manualDiscardPenaltyCost: 1,
                    revisitPenaltyCost: 0
                ),
                impassableTilePoints: impassableTilePoints,
                tileEffectOverrides: tileEffectOverrides,
                warpTilePairs: warpTilePairs,
                completionRule: .dungeonExit(exitPoint: exitPoint),
                dungeonRules: DungeonRules(
                    difficulty: difficulty,
                    failureRule: resolvedFailureRule,
                    enemies: enemies,
                    hazards: hazards,
                    exitLock: exitLock,
                    allowsBasicOrthogonalMove: true,
                    movementStyle: runState?.movementStyle ?? .orthogonal,
                    cardAcquisitionMode: .inventoryOnly,
                    cardPickups: cardPickups,
                    specialPickups: specialPickups,
                    relicPickups: relicPickups,
                    isDarknessEnabled: isDarknessEnabled
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
            exitLock: exitLock,
            cardPickups: cardPickups,
            specialPickups: specialPickups,
            relicPickups: relicPickups,
            fallSecrets: fallSecrets,
            rewardMoveCardsAfterClear: rewardMoveCardsAfterClear,
            rewardSupportCardsAfterClear: rewardSupportCardsAfterClear,
            isDarknessEnabled: isDarknessEnabled
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
            exitLock: exitLock,
            cardPickups: cardPickups + additionalCardPickups,
            specialPickups: specialPickups,
            relicPickups: relicPickups,
            fallSecrets: fallSecrets,
            rewardMoveCardsAfterClear: rewardMoveCardsAfterClear,
            rewardSupportCardsAfterClear: rewardSupportCardsAfterClear,
            isDarknessEnabled: isDarknessEnabled
        )
    }

    public func withAdditionalRelicPickups(_ additionalRelicPickups: [DungeonRelicPickupDefinition]) -> DungeonFloorDefinition {
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
            exitLock: exitLock,
            cardPickups: cardPickups,
            specialPickups: specialPickups,
            relicPickups: relicPickups + additionalRelicPickups,
            fallSecrets: fallSecrets,
            rewardMoveCardsAfterClear: rewardMoveCardsAfterClear,
            rewardSupportCardsAfterClear: rewardSupportCardsAfterClear,
            isDarknessEnabled: isDarknessEnabled
        )
    }

    public func withAdditionalHazards(_ additionalHazards: [HazardDefinition]) -> DungeonFloorDefinition {
        DungeonFloorDefinition(
            id: id,
            title: title,
            boardSize: boardSize,
            spawnPoint: spawnPoint,
            exitPoint: exitPoint,
            deckPreset: deckPreset,
            failureRule: failureRule,
            enemies: enemies,
            hazards: hazards + additionalHazards,
            impassableTilePoints: impassableTilePoints,
            tileEffectOverrides: tileEffectOverrides,
            warpTilePairs: warpTilePairs,
            exitLock: exitLock,
            cardPickups: cardPickups,
            specialPickups: specialPickups,
            relicPickups: relicPickups,
            fallSecrets: fallSecrets,
            rewardMoveCardsAfterClear: rewardMoveCardsAfterClear,
            rewardSupportCardsAfterClear: rewardSupportCardsAfterClear,
            isDarknessEnabled: isDarknessEnabled
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
            exitLock: exitLock,
            cardPickups: cardPickups,
            specialPickups: specialPickups,
            relicPickups: relicPickups,
            fallSecrets: fallSecrets,
            rewardMoveCardsAfterClear: rewardMoveCardsAfterClear,
            rewardSupportCardsAfterClear: rewardSupportCardsAfterClear,
            isDarknessEnabled: isDarknessEnabled
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
            exitLock: exitLock,
            cardPickups: cardPickups,
            specialPickups: specialPickups,
            relicPickups: relicPickups,
            fallSecrets: fallSecrets,
            rewardMoveCardsAfterClear: rewardMoveCardsAfterClear,
            rewardSupportCardsAfterClear: rewardSupportCardsAfterClear,
            isDarknessEnabled: isDarknessEnabled
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
            exitLock: exitLock,
            cardPickups: cardPickups,
            specialPickups: specialPickups,
            relicPickups: relicPickups,
            fallSecrets: fallSecrets,
            rewardMoveCardsAfterClear: rewardMoveCardsAfterClear,
            rewardSupportCardsAfterClear: rewardSupportCardsAfterClear,
            isDarknessEnabled: isDarknessEnabled
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

    public var supportsInfiniteFloors: Bool {
        id == "rogue-tower" && difficulty == .roguelike
    }

    public func canAdvanceWithinRun(afterFloorIndex floorIndex: Int) -> Bool {
        if supportsInfiniteFloors { return true }
        return floors.indices.contains(floorIndex + 1)
    }

    public func resolvedFloor(at floorIndex: Int, runState: DungeonRunState?) -> DungeonFloorDefinition? {
        if supportsInfiniteFloors {
            guard let seed = runState?.rogueTowerSeed else { return nil }
            return RogueTowerFloorGenerator.resolve(
                floorIndex: max(floorIndex, 0),
                seed: seed,
                runState: runState
            )
        }
        guard floors.indices.contains(floorIndex) else { return nil }
        let floor = floors[floorIndex]
        guard id == "growth-tower",
              difficulty == .growth,
              let seed = runState?.cardVariationSeed
        else { return floor }
        let spawnPoint = DungeonCardVariationResolver.resolvedStitchedSpawnPoint(
            floors: floors,
            floorIndex: floorIndex,
            seed: seed
        )
        let fallLandingBlockedPoints = DungeonCardVariationResolver.resolvedFallLandingBlockedPoints(
            floors: floors,
            floorIndex: floorIndex,
            seed: seed,
            curseEntries: runState?.curseEntries ?? []
        )
        return DungeonCardVariationResolver.resolve(
            floor: floor,
            floorIndex: floorIndex,
            seed: seed,
            forcedSpawnPoint: spawnPoint,
            fallLandingBlockedPoints: fallLandingBlockedPoints,
            movementStyle: runState?.movementStyle ?? .orthogonal,
            curseEntries: runState?.curseEntries ?? []
        )
    }
}

private enum RogueTowerFloorGenerator {
    private static let boardSize = 9

    private enum DeepFloorTheme {
        case trapCache
        case enemyPressure
        case warpVault
        case darkRoute
        case balanced
    }

    private enum DeepFloorRole {
        case normal
        case preparation
        case pressure
        case recovery
    }

    static func resolve(floorIndex: Int, seed: UInt64, runState: DungeonRunState?) -> DungeonFloorDefinition {
        let floorIndex = max(floorIndex, 0)
        var randomizer = DungeonCardVariationRandomizer(seed: seed, floorIndex: floorIndex, salt: 0x52_6F_67_75_65)
        let theme = deepFloorTheme(floorIndex: floorIndex, seed: seed)
        let role = deepFloorRole(floorIndex: floorIndex)
        let spawnPoint = resolvedSpawnPoint(floorIndex: floorIndex, seed: seed)
        let exitPoint = randomEdgePoint(avoiding: spawnPoint, randomizer: &randomizer)
        let safePath = representativePath(from: spawnPoint, to: exitPoint, randomizer: &randomizer)
        var reserved: Set<GridPoint> = [spawnPoint, exitPoint]

        var impassableTilePoints = impassableTiles(
            floorIndex: floorIndex,
            safePath: safePath,
            reserved: &reserved,
            randomizer: &randomizer
        )
        impassableTilePoints = validatedImpassableTiles(
            impassableTilePoints,
            spawnPoint: spawnPoint,
            exitPoint: exitPoint,
            safePath: safePath
        )
        let relicPickups = relicPickups(
            floorIndex: floorIndex,
            seed: seed,
            spawnPoint: spawnPoint,
            exitPoint: exitPoint,
            safePath: safePath,
            impassableTilePoints: impassableTilePoints,
            theme: theme,
            role: role,
            reserved: &reserved,
            randomizer: &randomizer
        )
        let pressureFocusPoints = [exitPoint] + relicPickups.map(\.point)
        let warpTilePairs = warpPairs(
            floorIndex: floorIndex,
            theme: theme,
            role: role,
            focusPoints: pressureFocusPoints,
            reserved: &reserved,
            randomizer: &randomizer
        )
        let hazards = hazards(
            floorIndex: floorIndex,
            theme: theme,
            role: role,
            focusPoints: pressureFocusPoints,
            reserved: &reserved,
            randomizer: &randomizer
        )
        let tileEffectOverrides = tileEffects(
            floorIndex: floorIndex,
            theme: theme,
            role: role,
            focusPoints: pressureFocusPoints,
            reserved: &reserved,
            randomizer: &randomizer
        )
        let baseEnemies = enemies(
            floorIndex: floorIndex,
            safePath: safePath,
            impassableTilePoints: impassableTilePoints,
            hazards: hazards,
            theme: theme,
            role: role,
            focusPoints: pressureFocusPoints,
            reserved: &reserved,
            randomizer: &randomizer
        )
        let cardPickups = cardPickups(
            floorIndex: floorIndex,
            seed: seed,
            role: role,
            focusPoints: pressureFocusPoints,
            reserved: &reserved,
            randomizer: &randomizer
        )
        let specialPickups = specialPickups(
            floorIndex: floorIndex,
            runState: runState,
            reserved: &reserved,
            randomizer: &randomizer
        )
        let rewardCards = rewardCards(floorIndex: floorIndex, seed: seed, randomizer: &randomizer)
        let darknessEnabled = isDarknessEnabled(
            floorIndex: floorIndex,
            theme: theme,
            role: role,
            randomizer: &randomizer
        )
        let baseFloor = DungeonFloorDefinition(
            id: "rogue-\(floorIndex + 1)",
            title: "試練 \(floorIndex + 1)F",
            boardSize: boardSize,
            spawnPoint: spawnPoint,
            exitPoint: exitPoint,
            deckPreset: .standardLight,
            failureRule: DungeonFailureRule(
                initialHP: 3,
                turnLimit: turnLimit(floorIndex: floorIndex, safePathLength: safePath.count)
            ),
            enemies: baseEnemies,
            hazards: hazards,
            impassableTilePoints: impassableTilePoints,
            tileEffectOverrides: tileEffectOverrides,
            warpTilePairs: warpTilePairs,
            cardPickups: cardPickups,
            specialPickups: specialPickups,
            relicPickups: relicPickups,
            rewardMoveCardsAfterClear: rewardCards.compactMap(\.move),
            rewardSupportCardsAfterClear: rewardCards.compactMap(\.support),
            isDarknessEnabled: darknessEnabled
        )
        let adjustedEnemies = DungeonCardVariationResolver.adjustedEnemies(
            baseEnemies,
            for: baseFloor,
            floorIndex: floorIndex,
            seed: seed,
            curseEntries: runState?.curseEntries ?? [],
            additionalReservedPoints: reserved
        )

        return DungeonFloorDefinition(
            id: "rogue-\(floorIndex + 1)",
            title: "試練 \(floorIndex + 1)F",
            boardSize: boardSize,
            spawnPoint: spawnPoint,
            exitPoint: exitPoint,
            deckPreset: .standardLight,
            failureRule: DungeonFailureRule(
                initialHP: 3,
                turnLimit: turnLimit(floorIndex: floorIndex, safePathLength: safePath.count)
            ),
            enemies: adjustedEnemies,
            hazards: hazards,
            impassableTilePoints: impassableTilePoints,
            tileEffectOverrides: tileEffectOverrides,
            warpTilePairs: warpTilePairs,
            cardPickups: cardPickups,
            specialPickups: specialPickups,
            relicPickups: relicPickups,
            rewardMoveCardsAfterClear: rewardCards.compactMap(\.move),
            rewardSupportCardsAfterClear: rewardCards.compactMap(\.support),
            isDarknessEnabled: darknessEnabled
        )
    }

    private static func resolvedSpawnPoint(floorIndex: Int, seed: UInt64) -> GridPoint {
        guard floorIndex > 0 else {
            var randomizer = DungeonCardVariationRandomizer(seed: seed, floorIndex: 0, salt: 0x52_6F_67_75_65)
            return randomEdgePoint(randomizer: &randomizer)
        }
        return resolvedExitPoint(floorIndex: floorIndex - 1, seed: seed)
    }

    private static func resolvedExitPoint(floorIndex: Int, seed: UInt64) -> GridPoint {
        let floorIndex = max(floorIndex, 0)
        var randomizer = DungeonCardVariationRandomizer(seed: seed, floorIndex: floorIndex, salt: 0x52_6F_67_75_65)
        let spawnPoint = resolvedSpawnPoint(floorIndex: floorIndex, seed: seed)
        return randomEdgePoint(avoiding: spawnPoint, randomizer: &randomizer)
    }

    private static func turnLimit(floorIndex: Int, safePathLength: Int) -> Int {
        max(9, safePathLength + 4 - min(floorIndex / 8, 5))
    }

    private static func deepFloorTheme(floorIndex: Int, seed: UInt64) -> DeepFloorTheme {
        guard floorIndex >= 50 else { return .balanced }
        let role = deepFloorRole(floorIndex: floorIndex)
        let candidates: [DeepFloorTheme]
        switch role {
        case .preparation:
            candidates = [.trapCache, .warpVault, .balanced, .darkRoute, .trapCache]
        case .pressure:
            candidates = [.enemyPressure, .trapCache, .darkRoute, .enemyPressure, .warpVault]
        case .recovery:
            candidates = [.balanced, .warpVault, .darkRoute, .trapCache, .balanced]
        case .normal:
            candidates = [.balanced]
        }
        var randomizer = DungeonCardVariationRandomizer(seed: seed, floorIndex: floorIndex, salt: 0x44_65_65_70)
        return candidates[randomizer.nextIndex(upperBound: candidates.count)]
    }

    private static func deepFloorRole(floorIndex: Int) -> DeepFloorRole {
        guard floorIndex >= 50 else { return .normal }
        switch (floorIndex - 50) % 3 {
        case 0:
            return .preparation
        case 1:
            return .pressure
        default:
            return .recovery
        }
    }

    private static func randomEdgePoint(avoiding avoided: GridPoint? = nil, randomizer: inout DungeonCardVariationRandomizer) -> GridPoint {
        let candidates = edgePoints.filter { point in
            guard let avoided else { return true }
            return point != avoided && manhattanDistance(point, avoided) >= 8
        }
        return candidates[randomizer.nextIndex(upperBound: candidates.count)]
    }

    private static func representativePath(
        from start: GridPoint,
        to goal: GridPoint,
        randomizer: inout DungeonCardVariationRandomizer
    ) -> [GridPoint] {
        let bend = randomizer.nextIndex(upperBound: 2) == 0
            ? GridPoint(x: goal.x, y: start.y)
            : GridPoint(x: start.x, y: goal.y)
        return linePath(from: start, to: bend) + linePath(from: bend, to: goal).dropFirst()
    }

    private static func linePath(from start: GridPoint, to goal: GridPoint) -> [GridPoint] {
        var result = [start]
        var current = start
        while current.x != goal.x {
            current = GridPoint(x: current.x + (goal.x > current.x ? 1 : -1), y: current.y)
            result.append(current)
        }
        while current.y != goal.y {
            current = GridPoint(x: current.x, y: current.y + (goal.y > current.y ? 1 : -1))
            result.append(current)
        }
        return result
    }

    private static func impassableTiles(
        floorIndex: Int,
        safePath: [GridPoint],
        reserved: inout Set<GridPoint>,
        randomizer: inout DungeonCardVariationRandomizer
    ) -> Set<GridPoint> {
        let count = min(2 + floorIndex / 6, 7)
        let blockedPath = Set(safePath)
        let points = drawPoints(count: count, reserved: reserved.union(blockedPath), randomizer: &randomizer)
        reserved.formUnion(points)
        return Set(points)
    }

    private static func validatedImpassableTiles(
        _ points: Set<GridPoint>,
        spawnPoint: GridPoint,
        exitPoint: GridPoint,
        safePath: [GridPoint]
    ) -> Set<GridPoint> {
        var result = points
        result.remove(spawnPoint)
        result.remove(exitPoint)
        result.subtract(safePath)
        guard !hasOrthogonalPath(from: spawnPoint, to: exitPoint, blocked: result) else {
            return result
        }

        for point in result.sorted(by: { lhs, rhs in
            lhs.y == rhs.y ? lhs.x < rhs.x : lhs.y < rhs.y
        }) {
            result.remove(point)
            if hasOrthogonalPath(from: spawnPoint, to: exitPoint, blocked: result) {
                return result
            }
        }
        return []
    }

    private static func hasOrthogonalPath(
        from start: GridPoint,
        to goal: GridPoint,
        blocked: Set<GridPoint>
    ) -> Bool {
        guard start.isInside(boardSize: boardSize),
              goal.isInside(boardSize: boardSize),
              !blocked.contains(start),
              !blocked.contains(goal)
        else {
            return false
        }

        var queue: [GridPoint] = [start]
        var visited: Set<GridPoint> = [start]
        while !queue.isEmpty {
            let point = queue.removeFirst()
            if point == goal { return true }

            for next in neighbors(of: point) {
                guard next.isInside(boardSize: boardSize),
                      !blocked.contains(next),
                      !visited.contains(next)
                else {
                    continue
                }
                visited.insert(next)
                queue.append(next)
            }
        }
        return false
    }

    private static func warpPairs(
        floorIndex: Int,
        theme: DeepFloorTheme,
        role: DeepFloorRole,
        focusPoints: [GridPoint],
        reserved: inout Set<GridPoint>,
        randomizer: inout DungeonCardVariationRandomizer
    ) -> [String: [GridPoint]] {
        guard floorIndex >= 4 else { return [:] }
        let pairCount = floorIndex >= 18 ? 2 : 1
        var result: [String: [GridPoint]] = [:]
        let warpFocusPoints = theme == .warpVault || role == .preparation ? focusPoints : []
        for index in 0..<pairCount {
            let points = drawWarpPairPoints(
                count: 2,
                reserved: reserved,
                focusPoints: warpFocusPoints,
                randomizer: &randomizer
            )
            guard points.count == 2 else { continue }
            reserved.formUnion(points)
            result["rogue-\(floorIndex + 1)-warp-\(index + 1)"] = points
        }
        return result
    }

    private static func drawWarpPairPoints(
        count: Int,
        reserved: Set<GridPoint>,
        focusPoints: [GridPoint] = [],
        randomizer: inout DungeonCardVariationRandomizer
    ) -> [GridPoint] {
        var candidates = focusedCandidates(reserved: reserved, focusPoints: focusPoints)
        var result: [GridPoint] = []
        while !candidates.isEmpty && result.count < count {
            let index = randomizer.nextIndex(upperBound: candidates.count)
            let candidate = candidates.remove(at: index)
            guard !result.contains(where: { isOrthogonallyAdjacent(candidate, $0) }) else {
                continue
            }
            result.append(candidate)
        }
        if result.count < count {
            var fallback = allPoints.filter { point in
                !reserved.contains(point) && !result.contains(point)
            }
            while !fallback.isEmpty && result.count < count {
                let index = randomizer.nextIndex(upperBound: fallback.count)
                let candidate = fallback.remove(at: index)
                guard !result.contains(where: { isOrthogonallyAdjacent(candidate, $0) }) else {
                    continue
                }
                result.append(candidate)
            }
        }
        return result
    }

    private static func hazards(
        floorIndex: Int,
        theme: DeepFloorTheme,
        role: DeepFloorRole,
        focusPoints: [GridPoint],
        reserved: inout Set<GridPoint>,
        randomizer: inout DungeonCardVariationRandomizer
    ) -> [HazardDefinition] {
        var result: [HazardDefinition] = []
        let trapCount = min(2 + floorIndex / 3, floorIndex >= 40 ? 9 : 14)
        let pressureFocusPoints = hazardFocusPoints(theme: theme, role: role, focusPoints: focusPoints)
        let trapPoints = drawPoints(
            count: trapCount,
            reserved: reserved,
            focusPoints: pressureFocusPoints,
            randomizer: &randomizer
        )
        if !trapPoints.isEmpty {
            reserved.formUnion(trapPoints)
            result.append(.damageTrap(
                points: Set(trapPoints),
                damage: damageTrapDamage(forFloorNumber: floorIndex + 1)
            ))
        }

        if floorIndex >= 2 {
            let brittleCount = min(1 + floorIndex / 5, 8)
            let brittleFocusPoints = theme == .trapCache ? pressureFocusPoints : []
            let brittlePoints = drawPoints(
                count: brittleCount,
                reserved: reserved,
                focusPoints: brittleFocusPoints,
                randomizer: &randomizer
            )
            if !brittlePoints.isEmpty {
                reserved.formUnion(brittlePoints)
                let initialState: BrittleFloorInitialState
                if floorIndex >= 25 {
                    initialState = .hiddenWeak
                } else if floorIndex >= 10 {
                    initialState = .collapsed
                } else {
                    initialState = .cracked
                }
                result.append(.brittleFloor(points: Set(brittlePoints), initialState: initialState))
            }
        }

        if floorIndex >= 10 {
            let lavaCount = floorIndex >= 40
                ? min(4 + floorIndex / 30, 6)
                : min(1 + floorIndex / 12, 4)
            let lavaFocusPoints = role == .pressure ? pressureFocusPoints : []
            let lavaPoints = drawLavaClusterPoints(
                count: lavaCount,
                reserved: reserved,
                focusPoints: lavaFocusPoints,
                randomizer: &randomizer
            )
            if !lavaPoints.isEmpty {
                reserved.formUnion(lavaPoints)
                result.append(.lavaTile(
                    points: Set(lavaPoints),
                    damage: lavaTileDamage(forFloorNumber: floorIndex + 1)
                ))
            }
        }

        let guaranteesRecoveryHeal = role == .recovery && floorIndex >= 50
        if floorIndex >= 8 && (guaranteesRecoveryHeal || randomizer.nextIndex(upperBound: 3) == 0) {
            let healPoints = drawPoints(count: 1, reserved: reserved, randomizer: &randomizer)
            if !healPoints.isEmpty {
                reserved.formUnion(healPoints)
                result.append(.healingTile(points: Set(healPoints), amount: 1))
            }
        }
        return result
    }

    private static func drawLavaClusterPoints(
        count: Int,
        reserved: Set<GridPoint>,
        focusPoints: [GridPoint] = [],
        randomizer: inout DungeonCardVariationRandomizer
    ) -> [GridPoint] {
        guard count > 0 else { return [] }
        let shapes: [[MoveVector]] = [
            [MoveVector(dx: 0, dy: 0), MoveVector(dx: 1, dy: 0), MoveVector(dx: 0, dy: 1), MoveVector(dx: 1, dy: 1), MoveVector(dx: 0, dy: 2), MoveVector(dx: 1, dy: 2)],
            [MoveVector(dx: 0, dy: 0), MoveVector(dx: 1, dy: 0), MoveVector(dx: 2, dy: 0), MoveVector(dx: 0, dy: 1), MoveVector(dx: 1, dy: 1), MoveVector(dx: 2, dy: 1)],
            [MoveVector(dx: 0, dy: 0), MoveVector(dx: 1, dy: 0), MoveVector(dx: 0, dy: 1), MoveVector(dx: 1, dy: 1)],
            [MoveVector(dx: 0, dy: 0), MoveVector(dx: 1, dy: 0)],
            [MoveVector(dx: 0, dy: 0), MoveVector(dx: 0, dy: 1)],
            [MoveVector(dx: 0, dy: 0)]
        ]
        var anchors = focusedCandidates(reserved: reserved, focusPoints: focusPoints)
        while !anchors.isEmpty {
            let anchorIndex = randomizer.nextIndex(upperBound: anchors.count)
            let anchor = anchors.remove(at: anchorIndex)
            var shapeOrder = shapes
            while !shapeOrder.isEmpty {
                let shapeIndex = randomizer.nextIndex(upperBound: shapeOrder.count)
                let selectedShape = shapeOrder.remove(at: shapeIndex)
                guard selectedShape.count >= count else { continue }
                let shape = Array(selectedShape.prefix(count))
                let points = shape.map { anchor.offset(dx: $0.dx, dy: $0.dy) }
                guard points.allSatisfy({ $0.isInside(boardSize: boardSize) && !reserved.contains($0) })
                else {
                    continue
                }
                return points
            }
        }
        return drawConnectedPoints(
            count: count,
            reserved: reserved,
            focusPoints: focusPoints,
            randomizer: &randomizer
        )
    }

    private static func drawConnectedPoints(
        count: Int,
        reserved: Set<GridPoint>,
        focusPoints: [GridPoint] = [],
        randomizer: inout DungeonCardVariationRandomizer
    ) -> [GridPoint] {
        var anchors = focusedCandidates(reserved: reserved, focusPoints: focusPoints)
        var bestResult: [GridPoint] = []
        while !anchors.isEmpty {
            let anchorIndex = randomizer.nextIndex(upperBound: anchors.count)
            let anchor = anchors.remove(at: anchorIndex)
            var result: [GridPoint] = [anchor]
            var frontier: [GridPoint] = [anchor]
            while result.count < count, !frontier.isEmpty {
                let frontierIndex = randomizer.nextIndex(upperBound: frontier.count)
                let point = frontier.remove(at: frontierIndex)
                var directions = rotatedDirections(randomizer: &randomizer)
                while result.count < count, !directions.isEmpty {
                    let direction = directions.removeFirst()
                    let candidate = point.offset(dx: direction.dx, dy: direction.dy)
                    guard candidate.isInside(boardSize: boardSize),
                          !reserved.contains(candidate),
                          !result.contains(candidate)
                    else { continue }
                    result.append(candidate)
                    frontier.append(candidate)
                }
            }
            if result.count == count {
                return result
            }
            if result.count > bestResult.count {
                bestResult = result
            }
        }
        if !bestResult.isEmpty {
            return bestResult
        }
        return drawPoints(count: count, reserved: reserved, focusPoints: focusPoints, randomizer: &randomizer)
    }

    private static func hazardFocusPoints(
        theme: DeepFloorTheme,
        role: DeepFloorRole,
        focusPoints: [GridPoint]
    ) -> [GridPoint] {
        guard role == .pressure || theme == .trapCache || theme == .enemyPressure else {
            return []
        }
        return focusPoints
    }

    private static func tileEffects(
        floorIndex: Int,
        theme: DeepFloorTheme,
        role: DeepFloorRole,
        focusPoints: [GridPoint],
        reserved: inout Set<GridPoint>,
        randomizer: inout DungeonCardVariationRandomizer
    ) -> [GridPoint: TileEffect] {
        guard floorIndex >= 5 else { return [:] }
        var candidates: [TileEffect] = [
            .poisonTrap,
            .shackleTrap,
            .illusionTrap,
            .swamp,
            .discardRandomHand
        ]
        if floorIndex >= 50 {
            switch theme {
            case .trapCache:
                candidates += [.poisonTrap, .shackleTrap, .relicBreakTrap, .discardRandomHand]
            case .enemyPressure:
                candidates += [.shackleTrap, .swamp]
            case .warpVault:
                candidates += [.illusionTrap, .swamp]
            case .darkRoute:
                candidates += [.illusionTrap, .discardRandomHand]
            case .balanced:
                break
            }
            if role == .pressure {
                candidates += [.relicBreakTrap, .discardRandomHand]
            }
        }
        let effectCandidates = floorIndex >= 12 ? candidates + [.relicBreakTrap] : candidates
        let count = min(1 + floorIndex / 10, 4)
        let points = drawPoints(
            count: count,
            reserved: reserved,
            focusPoints: role == .pressure || theme == .trapCache ? focusPoints : [],
            randomizer: &randomizer
        )
        reserved.formUnion(points)
        return Dictionary(uniqueKeysWithValues: points.enumerated().map { index, point in
            (point, effectCandidates[(index + randomizer.nextIndex(upperBound: effectCandidates.count)) % effectCandidates.count])
        })
    }

    private static func enemies(
        floorIndex: Int,
        safePath: [GridPoint],
        impassableTilePoints: Set<GridPoint>,
        hazards: [HazardDefinition],
        theme: DeepFloorTheme,
        role: DeepFloorRole,
        focusPoints: [GridPoint],
        reserved: inout Set<GridPoint>,
        randomizer: inout DungeonCardVariationRandomizer
    ) -> [EnemyDefinition] {
        let enemyCount = enemyCount(for: floorIndex)
        var enemies: [EnemyDefinition] = []
        var didPlaceChaser = false
        var enemyReserved = reserved.union(Set(safePath))
        for index in 0..<enemyCount {
            let preferredBehaviorKind = enemyBehaviorKind(
                floorIndex: floorIndex,
                didPlaceChaser: didPlaceChaser,
                theme: theme,
                role: role,
                randomizer: &randomizer
            )
            let enemyFocusPoints = role == .pressure || theme == .enemyPressure ? focusPoints : []
            let point = drawPoints(
                count: 1,
                reserved: enemyReserved,
                focusPoints: enemyFocusPoints,
                randomizer: &randomizer
            ).first
                ?? drawPoints(count: 1, reserved: reserved, randomizer: &randomizer).first
            guard let point else { continue }
            var behavior: EnemyBehavior?
            var name: String?
            for behaviorKind in enemyBehaviorKinds(
                floorIndex: floorIndex,
                didPlaceChaser: didPlaceChaser,
                theme: theme,
                role: role,
                preferred: preferredBehaviorKind
            ) {
                switch behaviorKind {
                case 0:
                    behavior = .guardPost
                    name = "番兵"
                case 1:
                    behavior = .watcher(
                        direction: DungeonWatcherDirectionSelector.bestDirection(
                            from: point,
                            boardSize: boardSize,
                            impassableTilePoints: impassableTilePoints,
                            randomizer: &randomizer
                        ),
                        range: min(3 + floorIndex / 8, 6)
                    )
                    name = "見張り"
                case 2:
                    let path = patrolPath(from: point, avoiding: enemyReserved, randomizer: &randomizer)
                    guard DungeonPatrolRouteValidator.isValidPatrolPath(
                        path,
                        boardSize: boardSize,
                        impassableTilePoints: impassableTilePoints,
                        hazards: hazards
                    ) else {
                        continue
                    }
                    behavior = .patrol(path: path)
                    name = "巡回兵"
                case 3:
                    behavior = .chaser
                    name = "追跡兵"
                    didPlaceChaser = true
                default:
                    behavior = .marker(directions: [], range: min(2 + floorIndex / 8, 5))
                    name = "メテオ兵"
                }
                break
            }
            guard let behavior, let name else { continue }
            let occupied: Set<GridPoint>
            if case .patrol(let path) = behavior {
                occupied = Set(path)
            } else {
                occupied = [point]
            }
            enemyReserved.formUnion(occupied)
            reserved.formUnion(occupied)
            enemies.append(
                EnemyDefinition(
                    id: "rogue-\(floorIndex + 1)-enemy-\(index + 1)",
                    name: name,
                    position: point,
                    behavior: behavior,
                    damage: enemyDamage(forFloorNumber: floorIndex + 1)
                )
            )
        }
        return enemies
    }

    private static func enemyCount(for floorIndex: Int) -> Int {
        switch floorIndex {
        case ..<3:
            return 0
        case 3..<5:
            return 1
        case 5..<10:
            return 2
        case 10..<15:
            return 3
        case 15..<29:
            return 4
        case 29..<39:
            return 5
        default:
            return 7
        }
    }

    private static func enemyBehaviorKind(
        floorIndex: Int,
        didPlaceChaser: Bool,
        theme: DeepFloorTheme,
        role: DeepFloorRole,
        randomizer: inout DungeonCardVariationRandomizer
    ) -> Int {
        let candidates = enemyBehaviorKindCandidates(
            floorIndex: floorIndex,
            didPlaceChaser: didPlaceChaser,
            theme: theme,
            role: role
        )
        return candidates[randomizer.nextIndex(upperBound: candidates.count)]
    }

    private static func enemyBehaviorKinds(
        floorIndex: Int,
        didPlaceChaser: Bool,
        theme: DeepFloorTheme,
        role: DeepFloorRole,
        preferred: Int
    ) -> [Int] {
        let candidates = enemyBehaviorKindCandidates(
            floorIndex: floorIndex,
            didPlaceChaser: didPlaceChaser,
            theme: theme,
            role: role
        )
        return [preferred] + candidates.filter { $0 != preferred }
    }

    private static func enemyBehaviorKindCandidates(
        floorIndex: Int,
        didPlaceChaser: Bool,
        theme: DeepFloorTheme,
        role: DeepFloorRole
    ) -> [Int] {
        if floorIndex >= 50 {
            switch theme {
            case .enemyPressure:
                return role == .pressure ? [3, 4, 1, 2, 3, 4, 0] : [1, 2, 3, 4, 0]
            case .trapCache:
                return role == .pressure ? [1, 2, 4, 3, 0] : [0, 1, 2, 4]
            case .warpVault:
                return [1, 3, 4, 0, 2]
            case .darkRoute:
                return [1, 4, 2, 0, 3]
            case .balanced:
                return role == .pressure ? [1, 2, 3, 4, 0] : [0, 1, 2, 3, 4]
            }
        }
        switch floorIndex {
        case ..<5:
            return [0, 1]
        case 5..<10:
            return [0, 1, 2]
        case 10..<15:
            return didPlaceChaser ? [0, 1, 2] : [0, 1, 2, 3]
        default:
            return [0, 1, 2, 3, 4]
        }
    }

    private static func enemyDamage(forFloorNumber floorNumber: Int) -> Int {
        if floorNumber >= 41 { return 3 }
        if floorNumber >= 21 { return 2 }
        return 1
    }

    private static func damageTrapDamage(forFloorNumber floorNumber: Int) -> Int {
        1
    }

    private static func lavaTileDamage(forFloorNumber floorNumber: Int) -> Int {
        2
    }

    private static func patrolPath(
        from start: GridPoint,
        avoiding blocked: Set<GridPoint>,
        randomizer: inout DungeonCardVariationRandomizer
    ) -> [GridPoint] {
        let orderedDirections = rotatedDirections(randomizer: &randomizer)
        let loopPaths = patrolLoopPaths(from: start, directions: orderedDirections, avoiding: blocked)
        if !loopPaths.isEmpty,
           randomizer.nextIndex(upperBound: 3) == 0 {
            return loopPaths[randomizer.nextIndex(upperBound: loopPaths.count)]
        }
        if let line = orderedDirections
            .map({ patrolLine(from: start, direction: $0, avoiding: blocked) })
            .first(where: { $0.count >= minimumRailPatrolUniquePointCount }) {
            return expandedRailPatrolPath(from: line, pathLength: minimumRailPatrolPathLength)
        }
        if let turn = patrolTurnPath(from: start, directions: orderedDirections, avoiding: blocked) {
            return expandedRailPatrolPath(from: turn, pathLength: minimumRailPatrolPathLength)
        }
        if !loopPaths.isEmpty {
            return loopPaths[randomizer.nextIndex(upperBound: loopPaths.count)]
        }
        return []
    }

    private static func patrolLine(
        from start: GridPoint,
        direction: MoveVector,
        avoiding blocked: Set<GridPoint>
    ) -> [GridPoint] {
        var result: [GridPoint] = [start]
        for step in 1..<4 {
            let point = GridPoint(x: start.x + direction.dx * step, y: start.y + direction.dy * step)
            guard point.isInside(boardSize: boardSize), !blocked.contains(point) else {
                break
            }
            result.append(point)
        }
        return result
    }

    private static func patrolTurnPath(
        from start: GridPoint,
        directions: [MoveVector],
        avoiding blocked: Set<GridPoint>
    ) -> [GridPoint]? {
        for firstDirection in directions {
            let firstLeg = patrolLine(from: start, direction: firstDirection, avoiding: blocked)
            guard firstLeg.count >= 2 else { continue }

            for turnIndex in 1..<firstLeg.count {
                let turn = firstLeg[turnIndex]
                for secondDirection in directions where secondDirection != firstDirection {
                    var path = Array(firstLeg.prefix(through: turnIndex))
                    for step in 1...minimumRailPatrolUniquePointCount {
                        let point = GridPoint(x: turn.x + secondDirection.dx * step, y: turn.y + secondDirection.dy * step)
                        guard point.isInside(boardSize: boardSize), !blocked.contains(point), !path.contains(point) else {
                            break
                        }
                        path.append(point)
                        if path.count >= minimumRailPatrolUniquePointCount {
                            return path
                        }
                    }
                }
            }
        }
        return nil
    }

    private static func patrolLoopPaths(
        from start: GridPoint,
        directions: [MoveVector],
        avoiding blocked: Set<GridPoint>
    ) -> [[GridPoint]] {
        let loopSizes = [(width: 3, height: 2), (width: 2, height: 3), (width: 3, height: 3)]
        var candidates: [[GridPoint]] = []
        for horizontalDirection in directions {
            for verticalDirection in directions where isPerpendicular(horizontalDirection, verticalDirection) {
                for size in loopSizes {
                    let path = rectangleLoopPath(
                        from: start,
                        horizontalDirection: horizontalDirection,
                        verticalDirection: verticalDirection,
                        width: size.width,
                        height: size.height
                    )
                    guard path.count >= minimumLoopRailPatrolUniquePointCount,
                          path.allSatisfy({ $0.isInside(boardSize: boardSize) && !blocked.contains($0) }),
                          isClosedRailPatrolLoop(path)
                    else { continue }
                    candidates.append(path)
                }
            }
        }
        return candidates
    }

    private static func rectangleLoopPath(
        from start: GridPoint,
        horizontalDirection: MoveVector,
        verticalDirection: MoveVector,
        width: Int,
        height: Int
    ) -> [GridPoint] {
        var path: [GridPoint] = []
        for offset in 0..<width {
            path.append(GridPoint(
                x: start.x + horizontalDirection.dx * offset,
                y: start.y + horizontalDirection.dy * offset
            ))
        }
        let topRight = path[path.count - 1]
        if height > 1 {
            for offset in 1..<height {
                path.append(GridPoint(
                    x: topRight.x + verticalDirection.dx * offset,
                    y: topRight.y + verticalDirection.dy * offset
                ))
            }
        }
        let bottomRight = path[path.count - 1]
        if width > 1 {
            for offset in 1..<width {
                path.append(GridPoint(
                    x: bottomRight.x - horizontalDirection.dx * offset,
                    y: bottomRight.y - horizontalDirection.dy * offset
                ))
            }
        }
        let bottomLeft = path[path.count - 1]
        if height > 2 {
            for offset in 1..<(height - 1) {
                path.append(GridPoint(
                    x: bottomLeft.x - verticalDirection.dx * offset,
                    y: bottomLeft.y - verticalDirection.dy * offset
                ))
            }
        }
        return path
    }

    private static func isPerpendicular(_ lhs: MoveVector, _ rhs: MoveVector) -> Bool {
        lhs.dx * rhs.dx + lhs.dy * rhs.dy == 0
    }

    private static func rotatedDirections(randomizer: inout DungeonCardVariationRandomizer) -> [MoveVector] {
        let offset = randomizer.nextIndex(upperBound: directions.count)
        return directions.indices.map { directions[($0 + offset) % directions.count] }
    }

    private static func cardPickups(
        floorIndex: Int,
        seed: UInt64,
        role: DeepFloorRole,
        focusPoints: [GridPoint],
        reserved: inout Set<GridPoint>,
        randomizer: inout DungeonCardVariationRandomizer
    ) -> [DungeonCardPickupDefinition] {
        let count: Int
        if floorIndex < 5 {
            count = 4
        } else if floorIndex < 10 {
            count = 5
        } else {
            count = min(3 + floorIndex / 7, 5)
        }
        let points = drawPoints(
            count: count,
            reserved: reserved,
            focusPoints: role == .preparation || role == .recovery ? focusPoints : [],
            randomizer: &randomizer
        )
        reserved.formUnion(points)
        let cards = paddedPlayableCards(
            floorIndex: floorIndex,
            seed: seed,
            count: points.count,
            salt: 0xC4D1
        )
        return points.enumerated().map { index, point in
            DungeonCardPickupDefinition(
                id: "rogue-\(floorIndex + 1)-pickup-\(index + 1)",
                point: point,
                playable: cards[index],
                uses: 1
            )
        }
    }

    private static func specialPickups(
        floorIndex: Int,
        runState: DungeonRunState?,
        reserved: inout Set<GridPoint>,
        randomizer: inout DungeonCardVariationRandomizer
    ) -> [DungeonSpecialPickupDefinition] {
        guard let runState,
              let seed = runState.rogueTowerSeed,
              runState.rogueHandExpansionSpawnSurface(floorIndex: floorIndex, seed: seed) == .floorPickup,
              let point = drawPoints(count: 1, reserved: reserved, randomizer: &randomizer).first
        else { return [] }
        reserved.insert(point)
        return [
            DungeonSpecialPickupDefinition(
                id: "rogue-\(floorIndex + 1)-hand-expansion",
                point: point,
                kind: .handExpansion
            )
        ]
    }

    private static func relicPickups(
        floorIndex: Int,
        seed: UInt64,
        spawnPoint: GridPoint,
        exitPoint: GridPoint,
        safePath: [GridPoint],
        impassableTilePoints: Set<GridPoint>,
        theme: DeepFloorTheme,
        role: DeepFloorRole,
        reserved: inout Set<GridPoint>,
        randomizer: inout DungeonCardVariationRandomizer
    ) -> [DungeonRelicPickupDefinition] {
        guard floorIndex >= 1 else { return [] }
        let earlyGuaranteedKind = earlyGuaranteedRelicPickupKind(floorIndex: floorIndex, seed: seed)
        let isGuaranteed = earlyGuaranteedKind != nil || isGuaranteedRelicPickupFloor(floorIndex: floorIndex, role: role)
        let divisor: Int
        if floorIndex >= 30 {
            divisor = 3
        } else if floorIndex >= 12 {
            divisor = 4
        } else {
            divisor = 5
        }
        guard isGuaranteed || randomizer.nextIndex(upperBound: divisor) == 0,
              let point = drawRelicPickupPoint(
                spawnPoint: spawnPoint,
                exitPoint: exitPoint,
                safePath: safePath,
                impassableTilePoints: impassableTilePoints,
                reserved: reserved,
                preferredNearExit: floorIndex >= 30 || role == .preparation || theme == .warpVault || earlyGuaranteedKind != nil,
                randomizer: &randomizer
              )
        else { return [] }
        reserved.insert(point)
        let kind: DungeonRelicPickupKind
        if let earlyGuaranteedKind {
            kind = earlyGuaranteedKind
        } else if floorIndex < 12 {
            kind = randomizer.nextIndex(upperBound: 2) == 0 ? .safe : .suspiciousLight
        } else if floorIndex >= 30 || (floorIndex >= 24 && (isGuaranteed || randomizer.nextIndex(upperBound: 2) == 0)) {
            kind = .suspiciousDeep
        } else if floorIndex >= 8 && randomizer.nextIndex(upperBound: 2) == 0 {
            kind = .suspiciousLight
        } else {
            kind = .safe
        }
        return [
            DungeonRelicPickupDefinition(
                id: "rogue-\(floorIndex + 1)-relic-1",
                point: point,
                kind: kind
            )
        ]
    }

    private static func earlyGuaranteedRelicPickupKind(floorIndex: Int, seed: UInt64) -> DungeonRelicPickupKind? {
        guard let window = earlyRelicPickupWindow(containing: floorIndex) else { return nil }
        let guaranteedFloorIndex = earlyGuaranteedRelicPickupFloor(in: window.range, seed: seed)
        guard floorIndex == guaranteedFloorIndex else { return nil }
        if window.index == earlyRequiredSuspiciousRelicWindow(seed: seed) {
            return .suspiciousLight
        }
        var randomizer = DungeonCardVariationRandomizer(
            seed: seed,
            floorIndex: window.index,
            salt: 0x45_61_72_6C_79_52_65_6C
        )
        return randomizer.nextIndex(upperBound: 2) == 0 ? .safe : .suspiciousLight
    }

    private static func earlyRelicPickupWindow(containing floorIndex: Int) -> (index: Int, range: Range<Int>)? {
        switch floorIndex {
        case 1..<4:
            return (0, 1..<4)
        case 4..<8:
            return (1, 4..<8)
        case 8..<12:
            return (2, 8..<12)
        default:
            return nil
        }
    }

    private static func earlyGuaranteedRelicPickupFloor(in range: Range<Int>, seed: UInt64) -> Int {
        var randomizer = DungeonCardVariationRandomizer(
            seed: seed,
            floorIndex: range.lowerBound,
            salt: 0x52_6F_67_75_65_45_61_72
        )
        return range.lowerBound + randomizer.nextIndex(upperBound: range.count)
    }

    private static func earlyRequiredSuspiciousRelicWindow(seed: UInt64) -> Int {
        var randomizer = DungeonCardVariationRandomizer(
            seed: seed,
            floorIndex: 0,
            salt: 0x53_75_73_70_52_65_6C_69
        )
        return randomizer.nextIndex(upperBound: 3)
    }

    private static func isGuaranteedRelicPickupFloor(floorIndex: Int, role: DeepFloorRole) -> Bool {
        if floorIndex >= 50 {
            return role == .preparation
        }
        if floorIndex >= 30 {
            return (floorIndex - 30) % 4 == 0
        }
        return false
    }

    private static func drawRelicPickupPoint(
        spawnPoint: GridPoint,
        exitPoint: GridPoint,
        safePath: [GridPoint],
        impassableTilePoints: Set<GridPoint>,
        reserved: Set<GridPoint>,
        preferredNearExit: Bool,
        randomizer: inout DungeonCardVariationRandomizer
    ) -> GridPoint? {
        let safePathSet = Set(safePath)
        let reachableCandidates = allPoints.filter { point in
            guard !reserved.contains(point),
                  !impassableTilePoints.contains(point),
                  hasOrthogonalPath(from: spawnPoint, to: point, blocked: impassableTilePoints),
                  hasOrthogonalPath(from: point, to: exitPoint, blocked: impassableTilePoints)
            else { return false }
            return true
        }
        let offRouteCandidates = reachableCandidates.filter { point in
            !safePathSet.contains(point) && nearestDistance(from: point, to: safePath) >= 2
        }
        let nearExitCandidates = offRouteCandidates.filter { point in
            let distance = manhattanDistance(point, exitPoint)
            return distance >= 2 && distance <= 4
        }
        let candidates: [GridPoint]
        if preferredNearExit, !nearExitCandidates.isEmpty {
            candidates = nearExitCandidates
        } else if !offRouteCandidates.isEmpty {
            candidates = offRouteCandidates
        } else {
            candidates = reachableCandidates
        }
        guard !candidates.isEmpty else { return nil }
        return candidates[randomizer.nextIndex(upperBound: candidates.count)]
    }

    private static func rewardCards(
        floorIndex: Int,
        seed: UInt64,
        randomizer: inout DungeonCardVariationRandomizer
    ) -> [PlayableCard] {
        paddedPlayableCards(floorIndex: floorIndex, seed: seed, count: 3, salt: 0xA11D)
    }

    private static func paddedPlayableCards(
        floorIndex: Int,
        seed: UInt64,
        count: Int,
        salt: UInt64
    ) -> [PlayableCard] {
        let cards = drawPlayableCards(floorIndex: floorIndex, seed: seed, count: count, salt: salt)
        if cards.count >= count { return Array(cards.prefix(count)) }
        let fallback: [PlayableCard] = [
            .move(.straightRight2),
            .move(.straightUp2),
            .move(.diagonalUpRight2),
            .move(.rayRight),
            .support(.refillEmptySlots),
            .support(.barrierSpell)
        ]
        var result = cards
        for card in fallback where result.count < count && !result.contains(card) {
            result.append(card)
        }
        return result
    }

    private static func drawPlayableCards(floorIndex: Int, seed: UInt64, count: Int, salt: UInt64) -> [PlayableCard] {
        DungeonWeightedRewardPools.drawUniqueOffers(
            from: DungeonWeightedRewardPools.entries(floorIndex: floorIndex, context: .clearReward),
            context: .clearReward,
            count: count,
            seed: seed,
            floorIndex: floorIndex,
            salt: salt
        )
        .compactMap(\.playable)
    }

    private static func isDarknessEnabled(
        floorIndex: Int,
        theme: DeepFloorTheme,
        role: DeepFloorRole,
        randomizer: inout DungeonCardVariationRandomizer
    ) -> Bool {
        guard floorIndex >= 14 else { return false }
        if floorIndex >= 50 {
            if theme == .darkRoute { return true }
            if role == .pressure {
                return randomizer.nextIndex(upperBound: 2) == 0
            }
        }
        return randomizer.nextIndex(upperBound: 4) == 0
    }

    private static func drawPoints(
        count: Int,
        reserved: Set<GridPoint>,
        focusPoints: [GridPoint] = [],
        randomizer: inout DungeonCardVariationRandomizer
    ) -> [GridPoint] {
        var candidates = focusedCandidates(reserved: reserved, focusPoints: focusPoints)
        var result: [GridPoint] = []
        while !candidates.isEmpty && result.count < count {
            let index = randomizer.nextIndex(upperBound: candidates.count)
            let point = candidates.remove(at: index)
            result.append(point)
        }
        if result.count < count {
            var fallback = allPoints.filter { point in
                !reserved.contains(point) && !result.contains(point)
            }
            while !fallback.isEmpty && result.count < count {
                let index = randomizer.nextIndex(upperBound: fallback.count)
                result.append(fallback.remove(at: index))
            }
        }
        return result
    }

    private static func focusedCandidates(
        reserved: Set<GridPoint>,
        focusPoints: [GridPoint]
    ) -> [GridPoint] {
        let candidates = allPoints.filter { !reserved.contains($0) }
        guard !focusPoints.isEmpty else { return candidates }
        let focused = candidates.filter { point in
            focusPoints.contains { focus in
                let distance = manhattanDistance(point, focus)
                return distance >= 1 && distance <= 3
            }
        }
        return focused.isEmpty ? candidates : focused
    }

    private static func nearestDistance(from point: GridPoint, to path: [GridPoint]) -> Int {
        path.map { manhattanDistance(point, $0) }.min() ?? Int.max
    }

    private static func randomDirection(randomizer: inout DungeonCardVariationRandomizer) -> MoveVector {
        directions[randomizer.nextIndex(upperBound: directions.count)]
    }

    private static func neighbors(of point: GridPoint) -> [GridPoint] {
        directions.compactMap { direction in
            let next = GridPoint(x: point.x + direction.dx, y: point.y + direction.dy)
            return next.isInside(boardSize: boardSize) ? next : nil
        }
    }

    private static func manhattanDistance(_ lhs: GridPoint, _ rhs: GridPoint) -> Int {
        abs(lhs.x - rhs.x) + abs(lhs.y - rhs.y)
    }

    private static func isOrthogonallyAdjacent(_ lhs: GridPoint, _ rhs: GridPoint) -> Bool {
        manhattanDistance(lhs, rhs) == 1
    }

    private static let directions = [
        MoveVector(dx: 1, dy: 0),
        MoveVector(dx: -1, dy: 0),
        MoveVector(dx: 0, dy: 1),
        MoveVector(dx: 0, dy: -1)
    ]

    private static let allPoints: [GridPoint] = (0..<boardSize).flatMap { y in
        (0..<boardSize).map { x in GridPoint(x: x, y: y) }
    }

    private static let edgePoints: [GridPoint] = allPoints.filter { point in
        point.x == 0 || point.y == 0 || point.x == boardSize - 1 || point.y == boardSize - 1
    }
}

private enum DungeonWatcherDirectionSelector {
    static func bestDirection(
        from origin: GridPoint,
        boardSize: Int,
        impassableTilePoints: Set<GridPoint>,
        randomizer: inout DungeonCardVariationRandomizer
    ) -> MoveVector {
        let orderedDirections = randomOrderedDirections(randomizer: &randomizer)
        let scoredDirections = orderedDirections.map { direction in
            (direction: direction, length: lineOfSightLength(
                from: origin,
                direction: direction,
                boardSize: boardSize,
                impassableTilePoints: impassableTilePoints
            ))
        }
        guard let best = scoredDirections.max(by: { lhs, rhs in lhs.length < rhs.length }),
              best.length > 0
        else {
            return orderedDirections[0]
        }
        return best.direction
    }

    private static func lineOfSightLength(
        from origin: GridPoint,
        direction: MoveVector,
        boardSize: Int,
        impassableTilePoints: Set<GridPoint>
    ) -> Int {
        var length = 0
        var point = origin.offset(dx: direction.dx, dy: direction.dy)
        while point.isInside(boardSize: boardSize), !impassableTilePoints.contains(point) {
            length += 1
            point = point.offset(dx: direction.dx, dy: direction.dy)
        }
        return length
    }

    private static func randomOrderedDirections(
        randomizer: inout DungeonCardVariationRandomizer
    ) -> [MoveVector] {
        let offset = randomizer.nextIndex(upperBound: orthogonalDirections.count)
        return orthogonalDirections.indices.map { index in
            orthogonalDirections[(index + offset) % orthogonalDirections.count]
        }
    }

    private static let orthogonalDirections = [
        MoveVector(dx: 1, dy: 0),
        MoveVector(dx: -1, dy: 0),
        MoveVector(dx: 0, dy: 1),
        MoveVector(dx: 0, dy: -1)
    ]
}

private enum DungeonCardVariationResolver {
    static func resolvedStitchedSpawnPoint(
        floors: [DungeonFloorDefinition],
        floorIndex: Int,
        seed: UInt64
    ) -> GridPoint? {
        guard floors.indices.contains(floorIndex) else { return nil }
        var previousExitPoint: GridPoint?
        for index in 0...floorIndex {
            let floor = floors[index]
            let spawnPoint = previousExitPoint ?? resolvedSpawnPoint(for: floor, floorIndex: index, seed: seed)
            if index == floorIndex {
                return spawnPoint
            }
            previousExitPoint = resolvedExitPoint(
                for: floor,
                floorIndex: index,
                seed: seed,
                avoiding: spawnPoint
            )
        }
        return nil
    }

    static func resolvedFallLandingBlockedPoints(
        floors: [DungeonFloorDefinition],
        floorIndex: Int,
        seed: UInt64,
        curseEntries: [DungeonCurseEntry]
    ) -> Set<GridPoint> {
        guard floorIndex > 0 else { return [] }
        var previousExitPoint: GridPoint?
        var previousImpassableTilePoints: Set<GridPoint> = []

        for index in 0..<floorIndex {
            let floor = floors[index]
            let spawnPoint = previousExitPoint ?? resolvedSpawnPoint(for: floor, floorIndex: index, seed: seed)
            let exitPoint = resolvedExitPoint(for: floor, floorIndex: index, seed: seed, avoiding: spawnPoint)
            let endpointFloor = floorVariant(floor, spawnPoint: spawnPoint, exitPoint: exitPoint)
            let enemies = resolvedEnemies(
                for: endpointFloor,
                floorIndex: index,
                seed: seed
            )
            let curseAdjustedEnemies = adjustedEnemies(
                enemies,
                for: endpointFloor,
                floorIndex: index,
                seed: seed,
                curseEntries: curseEntries
            )
            let enemyFloor = floorVariant(endpointFloor, enemies: curseAdjustedEnemies)
            let exitLock = resolvedExitLock(
                for: enemyFloor,
                floorIndex: index,
                seed: seed
            )
            let lockedFloor = floorVariant(enemyFloor, exitLock: exitLock)
            let warpTilePairs = resolvedWarpTilePairs(
                for: lockedFloor,
                floorIndex: index,
                seed: seed
            )
            let warpFloor = floorVariant(lockedFloor, warpTilePairs: warpTilePairs)
            let hazards = resolvedHazards(
                for: warpFloor,
                floorIndex: index,
                seed: seed,
                fallLandingBlockedPoints: previousImpassableTilePoints
            )
            previousImpassableTilePoints = resolvedImpassableTilePoints(
                for: warpFloor,
                floorIndex: index,
                seed: seed,
                hazards: hazards
            )
            previousExitPoint = exitPoint
        }

        return previousImpassableTilePoints
    }

    static func resolve(
        floor: DungeonFloorDefinition,
        floorIndex: Int,
        seed: UInt64,
        forcedSpawnPoint: GridPoint? = nil,
        fallLandingBlockedPoints: Set<GridPoint> = [],
        movementStyle: DungeonMovementStyle = .orthogonal,
        curseEntries: [DungeonCurseEntry] = []
    ) -> DungeonFloorDefinition {
        let spawnPoint = forcedSpawnPoint ?? resolvedSpawnPoint(for: floor, floorIndex: floorIndex, seed: seed)
        let exitPoint = resolvedExitPoint(for: floor, floorIndex: floorIndex, seed: seed, avoiding: spawnPoint)
        let endpointFloor = floorVariant(floor, spawnPoint: spawnPoint, exitPoint: exitPoint)
        let enemies = resolvedEnemies(
            for: endpointFloor,
            floorIndex: floorIndex,
            seed: seed
        )
        let curseAdjustedEnemies = adjustedEnemies(
            enemies,
            for: endpointFloor,
            floorIndex: floorIndex,
            seed: seed,
            curseEntries: curseEntries
        )
        let enemyFloor = floorVariant(endpointFloor, enemies: curseAdjustedEnemies)
        let exitLock = resolvedExitLock(
            for: enemyFloor,
            floorIndex: floorIndex,
            seed: seed
        )
        let lockedFloor = floorVariant(enemyFloor, exitLock: exitLock)
        let warpTilePairs = resolvedWarpTilePairs(
            for: lockedFloor,
            floorIndex: floorIndex,
            seed: seed
        )
        let warpFloor = floorVariant(lockedFloor, warpTilePairs: warpTilePairs)
        let hazards = resolvedHazards(
            for: warpFloor,
            floorIndex: floorIndex,
            seed: seed,
            fallLandingBlockedPoints: fallLandingBlockedPoints
        )
        let impassableTilePoints = resolvedImpassableTilePoints(
            for: warpFloor,
            floorIndex: floorIndex,
            seed: seed,
            hazards: hazards
        )
        let tileEffectOverrides = resolvedTileEffectOverrides(
            for: warpFloor,
            floorIndex: floorIndex,
            seed: seed,
            hazards: hazards,
            impassableTilePoints: impassableTilePoints
        )
        let tileEffectFloor = floorVariant(
            warpFloor,
            tileEffectOverrides: tileEffectOverrides
        )
        let relicPickups = resolvedRelicPickups(
            for: tileEffectFloor,
            floorIndex: floorIndex,
            seed: seed,
            hazards: hazards,
            impassableTilePoints: impassableTilePoints
        )
        let cardPickups = resolvedPickups(
            for: tileEffectFloor,
            floorIndex: floorIndex,
            seed: seed,
            movementStyle: movementStyle,
            hazards: hazards,
            impassableTilePoints: impassableTilePoints,
            relicPickups: relicPickups,
            curseEntries: curseEntries
        )
        let rewardCards = resolvedRewardCards(
            for: floor,
            floorIndex: floorIndex,
            seed: seed,
            movementStyle: movementStyle
        )
        let watcherResolvedEnemies = resolvedWatcherDirections(
            for: curseAdjustedEnemies,
            floorIndex: floorIndex,
            seed: seed,
            boardSize: floor.boardSize,
            impassableTilePoints: impassableTilePoints
        )
        let finalEnemies = resolvedValidPatrolRoutes(
            for: watcherResolvedEnemies,
            floor: tileEffectFloor,
            floorIndex: floorIndex,
            seed: seed,
            hazards: hazards,
            impassableTilePoints: impassableTilePoints,
            warpTilePairs: warpTilePairs,
            exitLock: exitLock,
            cardPickups: cardPickups,
            relicPickups: relicPickups
        )
        return DungeonFloorDefinition(
            id: floor.id,
            title: floor.title,
            boardSize: floor.boardSize,
            spawnPoint: spawnPoint,
            exitPoint: exitPoint,
            deckPreset: floor.deckPreset,
            failureRule: floor.failureRule,
            enemies: finalEnemies,
            hazards: hazards,
            impassableTilePoints: impassableTilePoints,
            tileEffectOverrides: tileEffectOverrides,
            warpTilePairs: warpTilePairs,
            exitLock: exitLock,
            cardPickups: cardPickups,
            specialPickups: floor.specialPickups,
            relicPickups: relicPickups,
            fallSecrets: floor.fallSecrets,
            rewardMoveCardsAfterClear: rewardCards.compactMap(\.move),
            rewardSupportCardsAfterClear: rewardCards.compactMap(\.support),
            isDarknessEnabled: floor.isDarknessEnabled
        )
    }

    private static func resolvedValidPatrolRoutes(
        for enemies: [EnemyDefinition],
        floor: DungeonFloorDefinition,
        floorIndex: Int,
        seed: UInt64,
        hazards: [HazardDefinition],
        impassableTilePoints: Set<GridPoint>,
        warpTilePairs: [String: [GridPoint]],
        exitLock: DungeonExitLock?,
        cardPickups: [DungeonCardPickupDefinition],
        relicPickups: [DungeonRelicPickupDefinition]
    ) -> [EnemyDefinition] {
        var reserved = patrolRouteReservedPoints(
            floor: floor,
            floorIndex: floorIndex,
            hazards: hazards,
            impassableTilePoints: impassableTilePoints,
            warpTilePairs: warpTilePairs,
            exitLock: exitLock,
            cardPickups: cardPickups,
            relicPickups: relicPickups
        )
        for enemy in enemies {
            if case .patrol = enemy.behavior {
                continue
            }
            reserved.insert(enemy.position)
        }

        return enemies.enumerated().compactMap { index, enemy in
            guard case .patrol(let path) = enemy.behavior else { return enemy }

            let pathPoints = Set(path)
            if pathPoints.count >= minimumRailPatrolUniquePointCount,
               path.count >= minimumRailPatrolPathLength,
               pathPoints.isDisjoint(with: reserved),
               DungeonPatrolRouteValidator.isValidPatrolPath(
                path,
                boardSize: floor.boardSize,
                impassableTilePoints: impassableTilePoints,
                hazards: hazards
               ) {
                reserved.formUnion(pathPoints)
                return enemy
            }

            let uniqueCount = max(minimumRailPatrolUniquePointCount, min(Set(path).count, 5))
            let candidates = candidatePatrolPaths(
                boardSize: floor.boardSize,
                uniqueCount: uniqueCount,
                pathLength: max(max(path.count, uniqueCount), minimumRailPatrolPathLength),
                reserved: reserved
            ).filter {
                DungeonPatrolRouteValidator.isValidPatrolPath(
                    $0,
                    boardSize: floor.boardSize,
                    impassableTilePoints: impassableTilePoints,
                    hazards: hazards
                )
            }
            guard !candidates.isEmpty else { return nil }

            var randomizer = DungeonCardVariationRandomizer(
                seed: seed,
                floorIndex: floorIndex,
                salt: 0x7A71 + UInt64(index)
            )
            let resolvedPath = candidates[randomizer.nextIndex(upperBound: candidates.count)]
            reserved.formUnion(resolvedPath)
            return EnemyDefinition(
                id: enemy.id,
                name: enemy.name,
                position: resolvedPath.first ?? enemy.position,
                behavior: .patrol(path: resolvedPath),
                damage: enemy.damage
            )
        }
    }

    private static func patrolRouteReservedPoints(
        floor: DungeonFloorDefinition,
        floorIndex: Int,
        hazards: [HazardDefinition],
        impassableTilePoints: Set<GridPoint>,
        warpTilePairs: [String: [GridPoint]],
        exitLock: DungeonExitLock?,
        cardPickups: [DungeonCardPickupDefinition],
        relicPickups: [DungeonRelicPickupDefinition]
    ) -> Set<GridPoint> {
        var reserved: Set<GridPoint> = [floor.spawnPoint, floor.exitPoint]
        reserved.formUnion(floor.tileEffectOverrides.keys)
        reserved.formUnion(warpTilePairs.values.flatMap { $0 })
        reserved.formUnion(impassableTilePoints)
        reserved.formUnion(DungeonPatrolRouteValidator.initialCollapsedFloorPoints(in: hazards))
        reserved.formUnion(floor.specialPickups.map(\.point))
        reserved.formUnion(cardPickups.map(\.point))
        reserved.formUnion(relicPickups.map(\.point))
        if let unlockPoint = exitLock?.unlockPoint {
            reserved.insert(unlockPoint)
        }
        reserved.formUnion(secretReservedPoints(for: floor, floorIndex: floorIndex))
        return reserved
    }

    private static func floorVariant(
        _ floor: DungeonFloorDefinition,
        spawnPoint: GridPoint? = nil,
        exitPoint: GridPoint? = nil,
        enemies: [EnemyDefinition]? = nil,
        hazards: [HazardDefinition]? = nil,
        impassableTilePoints: Set<GridPoint>? = nil,
        tileEffectOverrides: [GridPoint: TileEffect]? = nil,
        warpTilePairs: [String: [GridPoint]]? = nil,
        exitLock: DungeonExitLock? = nil,
        preservesExitLock: Bool = true
    ) -> DungeonFloorDefinition {
        DungeonFloorDefinition(
            id: floor.id,
            title: floor.title,
            boardSize: floor.boardSize,
            spawnPoint: spawnPoint ?? floor.spawnPoint,
            exitPoint: exitPoint ?? floor.exitPoint,
            deckPreset: floor.deckPreset,
            failureRule: floor.failureRule,
            enemies: enemies ?? floor.enemies,
            hazards: hazards ?? floor.hazards,
            impassableTilePoints: impassableTilePoints ?? floor.impassableTilePoints,
            tileEffectOverrides: tileEffectOverrides ?? floor.tileEffectOverrides,
            warpTilePairs: warpTilePairs ?? floor.warpTilePairs,
            exitLock: preservesExitLock ? (exitLock ?? floor.exitLock) : exitLock,
            cardPickups: floor.cardPickups,
            specialPickups: floor.specialPickups,
            relicPickups: floor.relicPickups,
            fallSecrets: floor.fallSecrets,
            rewardMoveCardsAfterClear: floor.rewardMoveCardsAfterClear,
            rewardSupportCardsAfterClear: floor.rewardSupportCardsAfterClear,
            isDarknessEnabled: floor.isDarknessEnabled
        )
    }

    private static func resolvedSpawnPoint(
        for floor: DungeonFloorDefinition,
        floorIndex: Int,
        seed: UInt64
    ) -> GridPoint {
        guard floorIndex > 0 else { return floor.spawnPoint }
        return variedEndpoint(
            around: floor.spawnPoint,
            floorIndex: floorIndex - 1,
            seed: seed,
            boardSize: floor.boardSize,
            avoiding: floor.exitPoint
        )
    }

    private static func resolvedExitPoint(
        for floor: DungeonFloorDefinition,
        floorIndex: Int,
        seed: UInt64,
        avoiding pointToAvoid: GridPoint
    ) -> GridPoint {
        variedEndpoint(
            around: floor.exitPoint,
            floorIndex: floorIndex,
            seed: seed,
            boardSize: floor.boardSize,
            avoiding: pointToAvoid
        )
    }

    private static func variedEndpoint(
        around basePoint: GridPoint,
        floorIndex: Int,
        seed: UInt64,
        boardSize: Int,
        avoiding pointToAvoid: GridPoint
    ) -> GridPoint {
        var randomizer = DungeonCardVariationRandomizer(seed: seed, floorIndex: max(floorIndex, 0), salt: 0xE117)
        let candidates = ([basePoint] + orthogonalNeighbors(of: basePoint, boardSize: boardSize))
            .filter { $0 != pointToAvoid }
        guard !candidates.isEmpty else { return basePoint }
        return candidates[randomizer.nextIndex(upperBound: candidates.count)]
    }

    private static func resolvedEnemies(
        for floor: DungeonFloorDefinition,
        floorIndex: Int,
        seed: UInt64
    ) -> [EnemyDefinition] {
        var reserved = coreReservedPoints(
            for: floor,
            includesEnemies: false,
            includesExitLock: false,
            includesWarpTiles: false
        )
        return floor.enemies.enumerated().map { index, enemy in
            var randomizer = DungeonCardVariationRandomizer(
                seed: seed,
                floorIndex: floorIndex,
                salt: 0xE000 + UInt64(index)
            )
            let behavior = resolvedEnemyBehavior(
                enemy.behavior,
                floor: floor,
                enemyIndex: index,
                reserved: reserved,
                randomizer: &randomizer
            )
            let position: GridPoint
            if case .patrol(let path) = behavior, let first = path.first {
                position = first
                reserved.formUnion(path)
            } else {
                position = drawPoints(
                    for: floor,
                    count: 1,
                    reserved: reserved,
                    randomizer: &randomizer
                ).first ?? enemy.position
                reserved.insert(position)
            }
            return EnemyDefinition(
                id: enemy.id,
                name: enemy.name,
                position: position,
                behavior: behavior,
                damage: enemy.damage
            )
        }
    }

    static func adjustedEnemies(
        _ enemies: [EnemyDefinition],
        for floor: DungeonFloorDefinition,
        floorIndex: Int,
        seed: UInt64,
        curseEntries: [DungeonCurseEntry],
        additionalReservedPoints: Set<GridPoint> = []
    ) -> [EnemyDefinition] {
        guard curseEntries.contains(where: { $0.curseID == .swarmcallingTalisman }),
              !enemies.isEmpty
        else { return enemies }

        var result = enemies
        var reserved = coreReservedPoints(
            for: floor,
            includesEnemies: false,
            includesExitLock: false,
            includesWarpTiles: false
        )
        reserved.formUnion(additionalReservedPoints)
        for enemy in enemies {
            switch enemy.behavior {
            case .patrol(let path):
                reserved.formUnion(path)
            case .guardPost, .watcher, .rotatingWatcher, .chaser, .marker, .targetedMarker:
                reserved.insert(enemy.position)
            }
        }

        for (index, enemy) in enemies.enumerated() {
            var randomizer = DungeonCardVariationRandomizer(
                seed: seed,
                floorIndex: floorIndex,
                salt: 0x5A6D + UInt64(index)
            )
            let behavior: EnemyBehavior
            let position: GridPoint
            switch enemy.behavior {
            case .patrol(let path):
                let uniqueCount = max(minimumRailPatrolUniquePointCount, min(Set(path).count, 5))
                let candidates = candidatePatrolPaths(
                    boardSize: floor.boardSize,
                    uniqueCount: uniqueCount,
                    pathLength: max(max(path.count, uniqueCount), minimumRailPatrolPathLength),
                    reserved: reserved
                )
                guard !candidates.isEmpty else { continue }
                let copiedPath = candidates[randomizer.nextIndex(upperBound: candidates.count)]
                behavior = .patrol(path: copiedPath)
                position = copiedPath.first ?? enemy.position
                reserved.formUnion(copiedPath)
            case .guardPost, .watcher, .rotatingWatcher, .chaser, .marker, .targetedMarker:
                guard let copiedPosition = drawPoints(
                    for: floor,
                    count: 1,
                    reserved: reserved,
                    randomizer: &randomizer
                ).first else { continue }
                behavior = enemy.behavior
                position = copiedPosition
                reserved.insert(copiedPosition)
            }
            result.append(
                EnemyDefinition(
                    id: "\(enemy.id)-swarm-\(index + 1)",
                    name: enemy.name,
                    position: position,
                    behavior: behavior,
                    damage: enemy.damage
                )
            )
        }
        return result
    }

    private static func resolvedEnemyBehavior(
        _ behavior: EnemyBehavior,
        floor: DungeonFloorDefinition,
        enemyIndex: Int,
        reserved: Set<GridPoint>,
        randomizer: inout DungeonCardVariationRandomizer
    ) -> EnemyBehavior {
        switch behavior {
        case .guardPost, .chaser:
            return behavior
        case .marker(_, let range):
            return .marker(directions: [], range: range)
        case .targetedMarker(_, let range):
            return .targetedMarker(directions: [], range: range)
        case .watcher(_, let range):
            return .watcher(
                direction: randomOrthogonalDirection(randomizer: &randomizer),
                range: range
            )
        case .rotatingWatcher(_, _, let range):
            return .rotatingWatcher(
                initialDirection: randomOrthogonalDirection(randomizer: &randomizer),
                rotationDirection: randomizer.nextIndex(upperBound: 2) == 0 ? .clockwise : .counterclockwise,
                range: range
            )
        case .patrol(let path):
            let uniqueCount = max(minimumRailPatrolUniquePointCount, min(Set(path).count, minimumLoopRailPatrolUniquePointCount))
            let candidates = candidatePatrolPaths(
                boardSize: floor.boardSize,
                uniqueCount: uniqueCount,
                pathLength: max(max(path.count, uniqueCount), minimumRailPatrolPathLength),
                reserved: reserved
            )
            guard !candidates.isEmpty else { return behavior }
            return .patrol(path: candidates[randomizer.nextIndex(upperBound: candidates.count)])
        }
    }

    private static func resolvedWatcherDirections(
        for enemies: [EnemyDefinition],
        floorIndex: Int,
        seed: UInt64,
        boardSize: Int,
        impassableTilePoints: Set<GridPoint>
    ) -> [EnemyDefinition] {
        enemies.enumerated().map { index, enemy in
            let behavior: EnemyBehavior
            switch enemy.behavior {
            case .watcher(_, let range):
                var randomizer = DungeonCardVariationRandomizer(
                    seed: seed,
                    floorIndex: floorIndex,
                    salt: 0xF4C1 + UInt64(index)
                )
                behavior = .watcher(
                    direction: DungeonWatcherDirectionSelector.bestDirection(
                        from: enemy.position,
                        boardSize: boardSize,
                        impassableTilePoints: impassableTilePoints,
                        randomizer: &randomizer
                    ),
                    range: range
                )
            case .rotatingWatcher(_, let rotationDirection, let range):
                var randomizer = DungeonCardVariationRandomizer(
                    seed: seed,
                    floorIndex: floorIndex,
                    salt: 0xF4C1 + UInt64(index)
                )
                behavior = .rotatingWatcher(
                    initialDirection: DungeonWatcherDirectionSelector.bestDirection(
                        from: enemy.position,
                        boardSize: boardSize,
                        impassableTilePoints: impassableTilePoints,
                        randomizer: &randomizer
                    ),
                    rotationDirection: rotationDirection,
                    range: range
                )
            case .guardPost, .patrol, .chaser, .marker, .targetedMarker:
                behavior = enemy.behavior
            }
            return EnemyDefinition(
                id: enemy.id,
                name: enemy.name,
                position: enemy.position,
                behavior: behavior,
                damage: enemy.damage
            )
        }
    }

    private static func resolvedExitLock(
        for floor: DungeonFloorDefinition,
        floorIndex: Int,
        seed: UInt64
    ) -> DungeonExitLock? {
        guard floor.exitLock != nil else { return nil }
        var randomizer = DungeonCardVariationRandomizer(seed: seed, floorIndex: floorIndex, salt: 0x10CC)
        let reserved = coreReservedPoints(
            for: floor,
            includesExitLock: false,
            includesWarpTiles: false
        )
        let candidates = candidatePoints(for: floor, excluding: reserved).filter { point in
            hasOrthogonalPath(from: floor.spawnPoint, to: point, boardSize: floor.boardSize, blocked: Set<GridPoint>())
                && hasOrthogonalPath(from: point, to: floor.exitPoint, boardSize: floor.boardSize, blocked: Set<GridPoint>())
        }
        guard !candidates.isEmpty else { return floor.exitLock }
        return DungeonExitLock(unlockPoint: candidates[randomizer.nextIndex(upperBound: candidates.count)])
    }

    private static func resolvedWarpTilePairs(
        for floor: DungeonFloorDefinition,
        floorIndex: Int,
        seed: UInt64
    ) -> [String: [GridPoint]] {
        guard !floor.warpTilePairs.isEmpty else { return [:] }
        var reserved = coreReservedPoints(
            for: floor,
            includesWarpTiles: false
        )
        var resolved: [String: [GridPoint]] = [:]
        for key in floor.warpTilePairs.keys.sorted() {
            guard let basePoints = floor.warpTilePairs[key], basePoints.count >= 2 else { continue }
            var randomizer = DungeonCardVariationRandomizer(
                seed: seed,
                floorIndex: floorIndex,
                salt: 0xA9A0 + UInt64(resolved.count)
            )
            let points = drawWarpPairPoints(
                for: floor,
                count: basePoints.count,
                reserved: reserved,
                randomizer: &randomizer
            )
            if points.count == basePoints.count {
                resolved[key] = points
                reserved.formUnion(points)
            } else {
                resolved[key] = basePoints
                reserved.formUnion(basePoints)
            }
        }
        return resolved
    }

    private static func drawWarpPairPoints(
        for floor: DungeonFloorDefinition,
        count: Int,
        reserved: Set<GridPoint>,
        randomizer: inout DungeonCardVariationRandomizer
    ) -> [GridPoint] {
        var candidates = candidatePoints(for: floor, excluding: reserved)
        var result: [GridPoint] = []
        while !candidates.isEmpty && result.count < count {
            let index = randomizer.nextIndex(upperBound: candidates.count)
            let candidate = candidates.remove(at: index)
            guard !result.contains(where: { isOrthogonallyAdjacent(candidate, $0) }) else {
                continue
            }
            result.append(candidate)
        }
        return result
    }

    private static func resolvedPickups(
        for floor: DungeonFloorDefinition,
        floorIndex: Int,
        seed: UInt64,
        movementStyle: DungeonMovementStyle,
        hazards: [HazardDefinition],
        impassableTilePoints: Set<GridPoint>,
        relicPickups: [DungeonRelicPickupDefinition],
        curseEntries: [DungeonCurseEntry]
    ) -> [DungeonCardPickupDefinition] {
        guard !floor.cardPickups.isEmpty else { return [] }
        let basePickupCount = resolvedPickupCount(for: floor, floorIndex: floorIndex, seed: seed)
        let pickupCount = adjustedPickupCount(
            basePickupCount,
            for: floor,
            curseEntries: curseEntries
        )
        var cards = drawPlayableCards(
            floorIndex: floorIndex,
            context: .floorPickup,
            count: pickupCount,
            seed: seed,
            movementStyle: movementStyle,
            salt: 0xC4D1
        )
        if cards.count < pickupCount {
            cards += floor.cardPickups.dropFirst(cards.count).map(\.playable)
        }
        let fallbackPlayables = floor.cardPickups.map(\.playable)
        while cards.count < pickupCount, !fallbackPlayables.isEmpty {
            cards.append(fallbackPlayables[cards.count % fallbackPlayables.count])
        }

        var randomizer = DungeonCardVariationRandomizer(seed: seed, floorIndex: floorIndex, salt: 0xC4D1)
        var positions = pickupPositions(
            for: floor,
            count: pickupCount,
            hazards: hazards,
            impassableTilePoints: impassableTilePoints,
            relicPickups: relicPickups,
            randomizer: &randomizer
        )
        if positions.count < pickupCount {
            positions += floor.cardPickups.dropFirst(positions.count).map(\.point)
        }

        return (0..<min(pickupCount, cards.count, positions.count)).map { index in
            let basePickup = floor.cardPickups[index % floor.cardPickups.count]
            return DungeonCardPickupDefinition(
                id: index < floor.cardPickups.count ? basePickup.id : "\(floor.id)-variant-pickup-\(index + 1)",
                point: positions[index],
                playable: cards[index],
                uses: basePickup.uses
            )
        }
    }

    private static func resolvedHazards(
        for floor: DungeonFloorDefinition,
        floorIndex: Int,
        seed: UInt64,
        fallLandingBlockedPoints: Set<GridPoint>
    ) -> [HazardDefinition] {
        var reserved = coreReservedPoints(for: floor)
        let resolved: [HazardDefinition] = floor.hazards.enumerated().compactMap { index, hazard -> HazardDefinition? in
            if case .healingTile = hazard,
               floorIndex >= 20,
               !keepsDeepGrowthHealingTile(floorIndex: floorIndex) {
                return nil
            }
            let fixedBrittlePoints = secretEntrancePoints(for: floor, floorIndex: floorIndex)
            var randomizer = DungeonCardVariationRandomizer(
                seed: seed,
                floorIndex: floorIndex,
                salt: 0xD00D + UInt64(index)
            )
            let count: Int
            if case .healingTile = hazard {
                count = hazard.points.count
            } else {
                count = variedCount(
                    base: hazard.points.count,
                    minimum: hazard.points.isEmpty ? 0 : 1,
                    maximum: max(hazard.points.count + 1, 1),
                    randomizer: &randomizer
                )
            }
            let randomCount: Int
            let pointReserved: Set<GridPoint>
            if case .brittleFloor = hazard {
                randomCount = max(count - fixedBrittlePoints.count, 0)
                pointReserved = reserved.union(fallLandingBlockedPoints)
            } else {
                randomCount = count
                pointReserved = reserved
            }
            let points = drawPoints(
                for: floor,
                count: randomCount,
                reserved: pointReserved,
                randomizer: &randomizer
            )
            guard !points.isEmpty || (!fixedBrittlePoints.isEmpty && {
                if case .brittleFloor = hazard { return true }
                return false
            }()) else { return nil }
            reserved.formUnion(points)
            reserved.formUnion(fixedBrittlePoints)
            switch hazard {
            case .brittleFloor(_, let initialState):
                return .brittleFloor(
                    points: Set(points).union(fixedBrittlePoints),
                    initialState: initialState
                )
            case .damageTrap:
                return .damageTrap(
                    points: Set(points),
                    damage: damageTrapDamage(forFloorNumber: floorIndex + 1)
                )
            case .hpHalvingTrap:
                return .hpHalvingTrap(points: Set(points))
            case .lavaTile:
                return .lavaTile(
                    points: Set(points),
                    damage: lavaTileDamage(forFloorNumber: floorIndex + 1)
                )
            case .healingTile(_, let amount):
                return .healingTile(points: Set(points), amount: amount)
            }
        }
        return resolved + additionalGrowthHazards(
            for: floor,
            floorIndex: floorIndex,
            seed: seed,
            existingHazards: resolved,
            fallLandingBlockedPoints: fallLandingBlockedPoints
        )
    }

    private static func additionalGrowthHazards(
        for floor: DungeonFloorDefinition,
        floorIndex: Int,
        seed: UInt64,
        existingHazards: [HazardDefinition],
        fallLandingBlockedPoints: Set<GridPoint>
    ) -> [HazardDefinition] {
        guard let targetCount = targetGrowthDamageHazardPointCount(floorIndex: floorIndex) else { return [] }
        let existingCount = damagePressurePointCount(in: existingHazards)
        let requiredVisibleBrittleCount = targetGrowthVisibleBrittlePointCount(floorIndex: floorIndex)
        let existingVisibleBrittleCount = visibleBrittlePointCount(in: existingHazards)
        let missingCount = max(
            targetCount - existingCount,
            requiredVisibleBrittleCount - existingVisibleBrittleCount
        )
        guard missingCount > 0 else { return [] }

        var reserved = coreReservedPoints(for: floor)
        reserved.formUnion(existingHazards.flatMap(\.points))
        reserved.formUnion(fallLandingBlockedPoints)
        var randomizer = DungeonCardVariationRandomizer(seed: seed, floorIndex: floorIndex, salt: 0xDA94)
        let points = drawPoints(
            for: floor,
            count: missingCount,
            reserved: reserved,
            randomizer: &randomizer
        )
        guard !points.isEmpty else { return [] }

        if floorIndex == 49 {
            let lavaCount = min(max(points.count / 4, 1), 2)
            let lavaPoints = Set(points.prefix(lavaCount))
            let trapPoints = Set(points.dropFirst(lavaCount))
            var hazards: [HazardDefinition] = []
            if !trapPoints.isEmpty {
                hazards.append(.damageTrap(
                    points: trapPoints,
                    damage: damageTrapDamage(forFloorNumber: floorIndex + 1)
                ))
            }
            if !lavaPoints.isEmpty {
                hazards.append(.lavaTile(
                    points: lavaPoints,
                    damage: lavaTileDamage(forFloorNumber: floorIndex + 1)
                ))
            }
            return hazards
        }

        if floorIndex >= 40 {
            let lavaCount = min(max(points.count / 4, 1), 2)
            let visibleBrittleCount = min(
                max(requiredVisibleBrittleCount - existingVisibleBrittleCount, max(points.count / 4, 1)),
                max(points.count - lavaCount, 0)
            )
            let hiddenBrittleCount = points.count >= 6 && points.count > lavaCount + visibleBrittleCount ? 1 : 0
            let lavaPoints = Set(points.prefix(lavaCount))
            let visibleBrittlePoints = Set(points.dropFirst(lavaCount).prefix(visibleBrittleCount))
            let hiddenBrittlePoints = Set(points.dropFirst(lavaCount + visibleBrittleCount).prefix(hiddenBrittleCount))
            let trapPoints = Set(points.dropFirst(lavaCount + visibleBrittleCount + hiddenBrittleCount))
            var hazards: [HazardDefinition] = []
            if !trapPoints.isEmpty {
                hazards.append(.damageTrap(
                    points: trapPoints,
                    damage: damageTrapDamage(forFloorNumber: floorIndex + 1)
                ))
            }
            if !lavaPoints.isEmpty {
                hazards.append(.lavaTile(
                    points: lavaPoints,
                    damage: lavaTileDamage(forFloorNumber: floorIndex + 1)
                ))
            }
            if !visibleBrittlePoints.isEmpty {
                hazards.append(.brittleFloor(points: visibleBrittlePoints))
            }
            if !hiddenBrittlePoints.isEmpty {
                hazards.append(.brittleFloor(points: hiddenBrittlePoints, initialState: .hiddenWeak))
            }
            return hazards
        }

        if floorIndex >= 30, points.count >= 3 {
            let lavaPoints = Set(points.prefix(1))
            let brittleCount = min(
                max(requiredVisibleBrittleCount - existingVisibleBrittleCount, points.count >= 5 ? 2 : 1),
                points.count - 1
            )
            let brittlePoints = Set(points.dropFirst(1).prefix(brittleCount))
            let trapPoints = Set(points.dropFirst(1 + brittleCount))
            return [
                .damageTrap(
                    points: trapPoints,
                    damage: damageTrapDamage(forFloorNumber: floorIndex + 1)
                ),
                .lavaTile(
                    points: lavaPoints,
                    damage: lavaTileDamage(forFloorNumber: floorIndex + 1)
                ),
                .brittleFloor(points: brittlePoints)
            ].filter { !$0.points.isEmpty }
        }

        if floorIndex >= 20, points.count >= 3 {
            let brittleCount = min(
                max(requiredVisibleBrittleCount - existingVisibleBrittleCount, points.count >= 5 ? 2 : 1),
                points.count
            )
            let brittlePoints = Set(points.prefix(brittleCount))
            let trapPoints = Set(points.dropFirst(brittleCount))
            return [
                .damageTrap(
                    points: trapPoints,
                    damage: damageTrapDamage(forFloorNumber: floorIndex + 1)
                ),
                .brittleFloor(points: brittlePoints)
            ].filter { !$0.points.isEmpty }
        }

        if floorIndex >= 10 {
            let brittleCount = min(max(requiredVisibleBrittleCount - existingVisibleBrittleCount, 1), points.count)
            let brittlePoints = Set(points.prefix(brittleCount))
            let trapPoints = Set(points.dropFirst(brittleCount))
            return [
                .damageTrap(
                    points: trapPoints,
                    damage: damageTrapDamage(forFloorNumber: floorIndex + 1)
                ),
                .brittleFloor(points: brittlePoints)
            ].filter { !$0.points.isEmpty }
        }

        return [.damageTrap(
            points: Set(points),
            damage: damageTrapDamage(forFloorNumber: floorIndex + 1)
        )]
    }

    private static func resolvedTileEffectOverrides(
        for floor: DungeonFloorDefinition,
        floorIndex: Int,
        seed: UInt64,
        hazards: [HazardDefinition],
        impassableTilePoints: Set<GridPoint>
    ) -> [GridPoint: TileEffect] {
        guard let targetCount = targetGrowthStatusTrapPointCount(floorIndex: floorIndex) else {
            return floor.tileEffectOverrides
        }
        let existingCount = statusTrapPointCount(in: floor.tileEffectOverrides)
        let missingCount = max(targetCount - existingCount, 0)
        guard missingCount > 0 else { return floor.tileEffectOverrides }

        var reserved = coreReservedPoints(for: floor)
        reserved.formUnion(hazards.flatMap(\.points))
        reserved.formUnion(impassableTilePoints)
        var randomizer = DungeonCardVariationRandomizer(seed: seed, floorIndex: floorIndex, salt: 0x575A)
        let points = drawPoints(
            for: floor,
            count: missingCount,
            reserved: reserved,
            randomizer: &randomizer
        )
        guard !points.isEmpty else { return floor.tileEffectOverrides }

        var result = floor.tileEffectOverrides
        for (offset, point) in points.enumerated() {
            result[point] = growthStatusTrapEffect(
                floorIndex: floorIndex,
                offset: offset,
                randomizer: &randomizer
            )
        }
        return result
    }

    private static func targetGrowthDamageHazardPointCount(floorIndex: Int) -> Int? {
        switch floorIndex {
        case 0..<10:
            return nil
        case 10..<15:
            return 4
        case 15..<20:
            return 5
        case 20..<30:
            return 7
        case 30..<40:
            return 9
        case 40...:
            return 11
        default:
            return nil
        }
    }

    private static func damageTrapDamage(forFloorNumber floorNumber: Int) -> Int {
        1
    }

    private static func lavaTileDamage(forFloorNumber floorNumber: Int) -> Int {
        2
    }

    private static func targetGrowthStatusTrapPointCount(floorIndex: Int) -> Int? {
        switch floorIndex {
        case 20..<25:
            return 1
        case 25..<30:
            return 2
        case 30..<35:
            return 2
        case 35..<40:
            return 3
        case 40...:
            return 3
        default:
            return nil
        }
    }

    private static func damagePressurePointCount(in hazards: [HazardDefinition]) -> Int {
        hazards.reduce(0) { total, hazard in
            switch hazard {
            case .damageTrap(let points, _), .hpHalvingTrap(let points), .lavaTile(let points, _), .brittleFloor(let points, _):
                return total + points.count
            case .healingTile:
                return total
            }
        }
    }

    private static func visibleBrittlePointCount(in hazards: [HazardDefinition]) -> Int {
        hazards.reduce(0) { total, hazard in
            guard case .brittleFloor(let points, .cracked) = hazard else { return total }
            return total + points.count
        }
    }

    private static func targetGrowthVisibleBrittlePointCount(floorIndex: Int) -> Int {
        switch floorIndex {
        case 10..<30:
            return 1
        case 30..<49:
            return 2
        default:
            return 0
        }
    }

    private static func statusTrapPointCount(in tileEffects: [GridPoint: TileEffect]) -> Int {
        tileEffects.values.reduce(0) { total, effect in
            isGrowthStatusTrap(effect) ? total + 1 : total
        }
    }

    private static func isGrowthStatusTrap(_ effect: TileEffect) -> Bool {
        switch effect {
        case .poisonTrap, .shackleTrap, .illusionTrap, .staggerTrap, .relicBreakTrap,
             .discardRandomHand, .discardAllMoveCards, .discardAllSupportCards, .discardAllHands:
            return true
        case .warp, .returnWarp, .shuffleHand, .blast, .slow, .swamp, .preserveCard:
            return false
        }
    }

    private static func growthStatusTrapEffect(
        floorIndex: Int,
        offset: Int,
        randomizer: inout DungeonCardVariationRandomizer
    ) -> TileEffect {
        let candidates: [TileEffect]
        if floorIndex >= 40 {
            candidates = [.poisonTrap, .shackleTrap, .illusionTrap, .discardRandomHand, .discardAllMoveCards, .discardAllHands]
        } else if floorIndex >= 30 {
            candidates = [.poisonTrap, .shackleTrap, .illusionTrap, .discardRandomHand, .discardAllMoveCards]
        } else {
            candidates = [.poisonTrap, .shackleTrap, .illusionTrap, .discardRandomHand]
        }
        return candidates[(offset + randomizer.nextIndex(upperBound: candidates.count)) % candidates.count]
    }

    private static func keepsDeepGrowthHealingTile(floorIndex: Int) -> Bool {
        [29, 39, 49].contains(floorIndex)
    }

    private static func resolvedImpassableTilePoints(
        for floor: DungeonFloorDefinition,
        floorIndex: Int,
        seed: UInt64,
        hazards: [HazardDefinition]
    ) -> Set<GridPoint> {
        guard !floor.impassableTilePoints.isEmpty else { return [] }
        var randomizer = DungeonCardVariationRandomizer(seed: seed, floorIndex: floorIndex, salt: 0xB10C)
        let fixedWallPoints = secretChamberWallPoints(for: floor, floorIndex: floorIndex)
        let maximum = floorIndex >= 10 ? 5 : 4
        let count = variedCount(
            base: floor.impassableTilePoints.count,
            minimum: 2,
            maximum: maximum,
            randomizer: &randomizer
        )
        var reserved = coreReservedPoints(for: floor)
        reserved.formUnion(hazards.flatMap(\.points))
        reserved.formUnion(fixedWallPoints)
        var candidates = candidatePoints(for: floor, excluding: reserved)
        var result = fixedWallPoints
        while !candidates.isEmpty && result.count < count {
            let index = randomizer.nextIndex(upperBound: candidates.count)
            let point = candidates.remove(at: index)
            let nextResult = result.union([point])
            if preservesRepresentativeRoutes(in: floor, blocked: nextResult) {
                result.insert(point)
            }
        }
        return result
    }

    private static func resolvedRelicPickups(
        for floor: DungeonFloorDefinition,
        floorIndex: Int,
        seed: UInt64,
        hazards: [HazardDefinition],
        impassableTilePoints: Set<GridPoint>
    ) -> [DungeonRelicPickupDefinition] {
        guard !floor.relicPickups.isEmpty else { return [] }
        let fixedSecretPickups = secretTreasurePickups(for: floor, floorIndex: floorIndex)
        let movablePickups = floor.relicPickups.filter { pickup in
            !fixedSecretPickups.contains { $0.id == pickup.id }
        }
        guard !movablePickups.isEmpty else { return fixedSecretPickups }
        var reserved = coreReservedPoints(for: floor)
        reserved.formUnion(hazards.flatMap(\.points))
        reserved.formUnion(impassableTilePoints)
        reserved.formUnion(fixedSecretPickups.map(\.point))
        var randomizer = DungeonCardVariationRandomizer(seed: seed, floorIndex: floorIndex, salt: 0x7E11C)
        let positions = drawPoints(
            for: floor,
            count: movablePickups.count,
            reserved: reserved,
            randomizer: &randomizer
        )
        guard positions.count == movablePickups.count else { return floor.relicPickups }
        let randomized = movablePickups.enumerated().map { index, pickup in
            DungeonRelicPickupDefinition(
                id: pickup.id,
                point: positions[index],
                kind: pickup.kind,
                candidateRelics: pickup.candidateRelics,
                candidateCurses: pickup.candidateCurses
            )
        }
        return fixedSecretPickups + randomized
    }

    private static func resolvedRewardCards(
        for floor: DungeonFloorDefinition,
        floorIndex: Int,
        seed: UInt64,
        movementStyle: DungeonMovementStyle
    ) -> [PlayableCard] {
        let rewardCount = floor.rewardMoveCardsAfterClear.count + floor.rewardSupportCardsAfterClear.count
        guard rewardCount > 0 else { return [] }
        let cards = DungeonWeightedRewardPools.drawUniquePlayables(
            from: DungeonWeightedRewardPools.entries(
                floorIndex: floorIndex,
                context: .clearReward,
                movementStyle: movementStyle
            ),
            count: rewardCount,
            seed: seed,
            floorIndex: floorIndex,
            salt: 0xA11D
        )
        if cards.count >= rewardCount {
            return cards
        }
        let fallbackMoveCards = movementStyle == .knight
            ? floor.rewardMoveCardsAfterClear.map(\.cardForKnightMovementStyle)
            : floor.rewardMoveCardsAfterClear
        let fallback = fallbackMoveCards.map(PlayableCard.move)
            + floor.rewardSupportCardsAfterClear.map(PlayableCard.support)
        return cards + fallback.filter { !cards.contains($0) }.prefix(rewardCount - cards.count)
    }

    private static func drawPlayableCards(
        floorIndex: Int,
        context: DungeonWeightedRewardPoolContext,
        count: Int,
        seed: UInt64,
        movementStyle: DungeonMovementStyle,
        salt: UInt64
    ) -> [PlayableCard] {
        DungeonWeightedRewardPools.drawUniqueOffers(
            from: DungeonWeightedRewardPools.entries(
                floorIndex: floorIndex,
                context: context,
                movementStyle: movementStyle
            ),
            context: context,
            count: count,
            seed: seed,
            floorIndex: floorIndex,
            salt: salt
        )
        .compactMap(\.playable)
    }

    private static func pickupPositions(
        for floor: DungeonFloorDefinition,
        count: Int,
        hazards: [HazardDefinition],
        impassableTilePoints: Set<GridPoint>,
        relicPickups: [DungeonRelicPickupDefinition],
        randomizer: inout DungeonCardVariationRandomizer
    ) -> [GridPoint] {
        var reserved = coreReservedPoints(for: floor)
        reserved.formUnion(hazards.flatMap(\.points))
        reserved.formUnion(impassableTilePoints)
        reserved.formUnion(relicPickups.map(\.point))
        return drawPoints(
            for: floor,
            count: count,
            reserved: reserved,
            randomizer: &randomizer
        )
    }

    private static func resolvedPickupCount(
        for floor: DungeonFloorDefinition,
        floorIndex: Int,
        seed: UInt64
    ) -> Int {
        var randomizer = DungeonCardVariationRandomizer(seed: seed, floorIndex: floorIndex, salt: 0xC0A7)
        let minimum = floorIndex < 8 ? 4 : 3
        return variedCount(
            base: floor.cardPickups.count,
            minimum: minimum,
            maximum: floor.cardPickups.count + 1,
            randomizer: &randomizer
        )
    }

    private static func adjustedPickupCount(
        _ baseCount: Int,
        for floor: DungeonFloorDefinition,
        curseEntries: [DungeonCurseEntry]
    ) -> Int {
        guard baseCount > 0,
              curseEntries.contains(where: { $0.curseID == .chaserScent }),
              floor.enemies.contains(where: { enemy in
                  if case .chaser = enemy.behavior { return true }
                  return false
              })
        else { return baseCount }
        return baseCount * 3
    }

    private static func variedCount(
        base: Int,
        minimum: Int,
        maximum: Int,
        randomizer: inout DungeonCardVariationRandomizer
    ) -> Int {
        guard base > 0 else { return 0 }
        let delta = randomizer.nextIndex(upperBound: 3) - 1
        return min(max(base + delta, minimum), max(minimum, maximum))
    }

    private static func drawPoints(
        for floor: DungeonFloorDefinition,
        count: Int,
        reserved: Set<GridPoint>,
        randomizer: inout DungeonCardVariationRandomizer
    ) -> [GridPoint] {
        var candidates = candidatePoints(for: floor, excluding: reserved)
        var result: [GridPoint] = []
        while !candidates.isEmpty && result.count < count {
            let index = randomizer.nextIndex(upperBound: candidates.count)
            result.append(candidates.remove(at: index))
        }
        return result
    }

    private static func candidatePoints(
        for floor: DungeonFloorDefinition,
        excluding reserved: Set<GridPoint>
    ) -> [GridPoint] {
        var points: [GridPoint] = []
        for y in 0..<floor.boardSize {
            for x in 0..<floor.boardSize {
                let point = GridPoint(x: x, y: y)
                if !reserved.contains(point) {
                    points.append(point)
                }
            }
        }
        return points
    }

    private static func randomOrthogonalDirection(
        randomizer: inout DungeonCardVariationRandomizer
    ) -> MoveVector {
        orthogonalDirections[randomizer.nextIndex(upperBound: orthogonalDirections.count)]
    }

    private static func orthogonalNeighbors(of point: GridPoint, boardSize: Int) -> [GridPoint] {
        orthogonalDirections.compactMap { direction in
            let next = GridPoint(x: point.x + direction.dx, y: point.y + direction.dy)
            return next.isInside(boardSize: boardSize) ? next : nil
        }
    }

    private static func isOrthogonallyAdjacent(_ lhs: GridPoint, _ rhs: GridPoint) -> Bool {
        abs(lhs.x - rhs.x) + abs(lhs.y - rhs.y) == 1
    }

    private static func candidatePatrolPaths(
        boardSize: Int,
        uniqueCount: Int,
        pathLength: Int,
        reserved: Set<GridPoint>
    ) -> [[GridPoint]] {
        var candidates: [[GridPoint]] = []
        for y in 0..<boardSize {
            for x in 0..<boardSize {
                let start = GridPoint(x: x, y: y)
                for direction in orthogonalDirections {
                    let line = (0..<uniqueCount).map {
                        GridPoint(x: start.x + direction.dx * $0, y: start.y + direction.dy * $0)
                    }
                    if line.allSatisfy({ $0.isInside(boardSize: boardSize) && !reserved.contains($0) }) {
                        candidates.append(expandedPatrolPath(from: line, pathLength: pathLength))
                    }
                }
                if uniqueCount >= 4 {
                    for firstDirection in orthogonalDirections {
                        for secondDirection in orthogonalDirections where secondDirection != firstDirection {
                            let firstLegCount = max(2, uniqueCount / 2)
                            let firstLeg = (0..<firstLegCount).map {
                                GridPoint(x: start.x + firstDirection.dx * $0, y: start.y + firstDirection.dy * $0)
                            }
                            guard let turn = firstLeg.last else { continue }
                            let secondLeg = (1...(uniqueCount - firstLegCount)).map {
                                GridPoint(x: turn.x + secondDirection.dx * $0, y: turn.y + secondDirection.dy * $0)
                            }
                            let points = firstLeg + secondLeg
                            if Set(points).count == uniqueCount,
                               points.allSatisfy({ $0.isInside(boardSize: boardSize) && !reserved.contains($0) }) {
                                candidates.append(expandedPatrolPath(from: points, pathLength: pathLength))
                            }
                        }
                    }
                }
                candidates.append(contentsOf: candidateLoopPatrolPaths(
                    from: start,
                    boardSize: boardSize,
                    reserved: reserved
                ))
            }
        }
        return candidates
    }

    private static func candidateLoopPatrolPaths(
        from start: GridPoint,
        boardSize: Int,
        reserved: Set<GridPoint>
    ) -> [[GridPoint]] {
        let loopSizes = [(width: 3, height: 2), (width: 2, height: 3)]
        var candidates: [[GridPoint]] = []
        for horizontalDirection in orthogonalDirections {
            for verticalDirection in orthogonalDirections where isPerpendicular(horizontalDirection, verticalDirection) {
                for size in loopSizes {
                    let path = rectangleLoopPath(
                        from: start,
                        horizontalDirection: horizontalDirection,
                        verticalDirection: verticalDirection,
                        width: size.width,
                        height: size.height
                    )
                    guard path.allSatisfy({ $0.isInside(boardSize: boardSize) && !reserved.contains($0) }),
                          isClosedRailPatrolLoop(path)
                    else { continue }
                    candidates.append(path)
                }
            }
        }
        return candidates
    }

    private static func rectangleLoopPath(
        from start: GridPoint,
        horizontalDirection: MoveVector,
        verticalDirection: MoveVector,
        width: Int,
        height: Int
    ) -> [GridPoint] {
        var path: [GridPoint] = []
        for offset in 0..<width {
            path.append(GridPoint(
                x: start.x + horizontalDirection.dx * offset,
                y: start.y + horizontalDirection.dy * offset
            ))
        }
        let topRight = path[path.count - 1]
        if height > 1 {
            for offset in 1..<height {
                path.append(GridPoint(
                    x: topRight.x + verticalDirection.dx * offset,
                    y: topRight.y + verticalDirection.dy * offset
                ))
            }
        }
        let bottomRight = path[path.count - 1]
        if width > 1 {
            for offset in 1..<width {
                path.append(GridPoint(
                    x: bottomRight.x - horizontalDirection.dx * offset,
                    y: bottomRight.y - horizontalDirection.dy * offset
                ))
            }
        }
        let bottomLeft = path[path.count - 1]
        if height > 2 {
            for offset in 1..<(height - 1) {
                path.append(GridPoint(
                    x: bottomLeft.x - verticalDirection.dx * offset,
                    y: bottomLeft.y - verticalDirection.dy * offset
                ))
            }
        }
        return path
    }

    private static func isPerpendicular(_ lhs: MoveVector, _ rhs: MoveVector) -> Bool {
        lhs.dx * rhs.dx + lhs.dy * rhs.dy == 0
    }

    private static func expandedPatrolPath(from points: [GridPoint], pathLength: Int) -> [GridPoint] {
        guard points.count > 1 else { return points }
        let bounce = points + points.dropLast().dropFirst().reversed()
        var path: [GridPoint] = []
        while path.count < pathLength {
            path.append(contentsOf: bounce)
        }
        return Array(path.prefix(pathLength))
    }

    private static let orthogonalDirections = [
        MoveVector(dx: 1, dy: 0),
        MoveVector(dx: -1, dy: 0),
        MoveVector(dx: 0, dy: 1),
        MoveVector(dx: 0, dy: -1)
    ]

    private static func secretEntrancePoints(for floor: DungeonFloorDefinition, floorIndex: Int) -> Set<GridPoint> {
        Set(floor.fallSecrets.filter { $0.sourceFloorIndex == floorIndex }.map(\.entrancePoint))
    }

    private static func secretTreasurePickups(
        for floor: DungeonFloorDefinition,
        floorIndex: Int
    ) -> [DungeonRelicPickupDefinition] {
        floor.fallSecrets
            .filter { $0.destinationFloorIndex == floorIndex }
            .map(\.treasurePickup)
    }

    private static func secretChamberWallPoints(
        for floor: DungeonFloorDefinition,
        floorIndex: Int
    ) -> Set<GridPoint> {
        floor.fallSecrets
            .filter { $0.destinationFloorIndex == floorIndex }
            .reduce(into: Set<GridPoint>()) { result, secret in
                result.formUnion(secret.chamberWallPoints)
            }
    }

    private static func secretReservedPoints(for floor: DungeonFloorDefinition, floorIndex: Int?) -> Set<GridPoint> {
        floor.fallSecrets.reduce(into: Set<GridPoint>()) { result, secret in
            if floorIndex == nil || secret.sourceFloorIndex == floorIndex {
                result.formUnion(secret.sourceReservedPoints)
            }
            if floorIndex == nil || secret.destinationFloorIndex == floorIndex {
                result.formUnion(secret.destinationReservedPoints)
            }
        }
    }

    private static func coreReservedPoints(
        for floor: DungeonFloorDefinition,
        includesEnemies: Bool = true,
        includesExitLock: Bool = true,
        includesWarpTiles: Bool = true
    ) -> Set<GridPoint> {
        var blocked: Set<GridPoint> = [
            floor.spawnPoint,
            floor.exitPoint
        ]
        if includesEnemies {
            for enemy in floor.enemies {
                switch enemy.behavior {
                case .patrol(let path):
                    blocked.formUnion(path)
                case .guardPost, .watcher, .rotatingWatcher, .chaser, .marker, .targetedMarker:
                    blocked.insert(enemy.position)
                }
            }
        }
        blocked.formUnion(floor.tileEffectOverrides.keys)
        if includesWarpTiles {
            blocked.formUnion(floor.warpTilePairs.values.flatMap { $0 })
        }
        if includesExitLock, let unlockPoint = floor.exitLock?.unlockPoint {
            blocked.insert(unlockPoint)
        }
        blocked.formUnion(secretReservedPoints(for: floor, floorIndex: nil))
        return blocked
    }

    private static func hasOrthogonalPath(
        from start: GridPoint,
        to goal: GridPoint,
        boardSize: Int,
        blocked: Set<GridPoint>
    ) -> Bool {
        guard start.isInside(boardSize: boardSize), goal.isInside(boardSize: boardSize) else {
            return false
        }
        var queue: [GridPoint] = [start]
        var visited: Set<GridPoint> = [start]
        let directions = [
            MoveVector(dx: 1, dy: 0),
            MoveVector(dx: -1, dy: 0),
            MoveVector(dx: 0, dy: 1),
            MoveVector(dx: 0, dy: -1)
        ]
        while !queue.isEmpty {
            let point = queue.removeFirst()
            if point == goal { return true }
            for direction in directions {
                let next = GridPoint(x: point.x + direction.dx, y: point.y + direction.dy)
                guard next.isInside(boardSize: boardSize),
                      !blocked.contains(next),
                      !visited.contains(next)
                else {
                    continue
                }
                visited.insert(next)
                queue.append(next)
            }
        }
        return false
    }

    private static func preservesRepresentativeRoutes(
        in floor: DungeonFloorDefinition,
        blocked: Set<GridPoint>
    ) -> Bool {
        if let unlockPoint = floor.exitLock?.unlockPoint {
            return hasOrthogonalPath(from: floor.spawnPoint, to: unlockPoint, boardSize: floor.boardSize, blocked: blocked)
                && hasOrthogonalPath(from: unlockPoint, to: floor.exitPoint, boardSize: floor.boardSize, blocked: blocked)
        }
        return hasOrthogonalPath(from: floor.spawnPoint, to: floor.exitPoint, boardSize: floor.boardSize, blocked: blocked)
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
        case .brittleFloor(let points, _):
            return points
        case .damageTrap(let points, _):
            return points
        case .hpHalvingTrap(let points):
            return points
        case .lavaTile(let points, _):
            return points
        case .healingTile(let points, _):
            return points
        }
    }
}

private enum DungeonPatrolRouteValidator {
    static func isValidPatrolPath(
        _ path: [GridPoint],
        boardSize: Int,
        impassableTilePoints: Set<GridPoint>,
        hazards: [HazardDefinition]
    ) -> Bool {
        guard Set(path).count >= 2 else { return false }
        let collapsedFloorPoints = initialCollapsedFloorPoints(in: hazards)
        guard path.allSatisfy({
            $0.isInside(boardSize: boardSize)
                && !impassableTilePoints.contains($0)
                && !collapsedFloorPoints.contains($0)
        }) else {
            return false
        }
        return zip(path, path.dropFirst()).allSatisfy { before, after in
            abs(before.x - after.x) + abs(before.y - after.y) == 1
        }
    }

    static func initialCollapsedFloorPoints(in hazards: [HazardDefinition]) -> Set<GridPoint> {
        var points: Set<GridPoint> = []
        for hazard in hazards {
            if case .brittleFloor(let hazardPoints, .collapsed) = hazard {
                points.formUnion(hazardPoints)
            }
        }
        return points
    }
}

/// `GameMode.Regulation` に埋め込むダンジョン追加ルール
public struct DungeonRules: Codable, Equatable, Sendable {
    public var difficulty: DungeonDifficulty
    public var failureRule: DungeonFailureRule
    public var enemies: [EnemyDefinition]
    public var hazards: [HazardDefinition]
    /// 指定がある場合、鍵マスを踏むまで出口到達ではクリアしない
    public var exitLock: DungeonExitLock?
    /// カードを消費しない上下左右 1 マス移動を許可するか
    public var allowsBasicOrthogonalMove: Bool
    /// 基本移動の形
    public var movementStyle: DungeonMovementStyle
    /// 塔内でのカード獲得・補充方式
    public var cardAcquisitionMode: DungeonCardAcquisitionMode
    /// この GameMode で解決済みの拾得カード配置
    public var cardPickups: [DungeonCardPickupDefinition]
    /// この GameMode で解決済みの塔専用拾得アイテム配置
    public var specialPickups: [DungeonSpecialPickupDefinition]
    /// この GameMode で解決済みの宝箱配置
    public var relicPickups: [DungeonRelicPickupDefinition]
    /// 暗闇フロアとして、盤面情報の表示を現在地周辺と常時可視要素へ制限するか
    public var isDarknessEnabled: Bool

    public init(
        difficulty: DungeonDifficulty,
        failureRule: DungeonFailureRule,
        enemies: [EnemyDefinition] = [],
        hazards: [HazardDefinition] = [],
        exitLock: DungeonExitLock? = nil,
        allowsBasicOrthogonalMove: Bool = false,
        movementStyle: DungeonMovementStyle = .orthogonal,
        cardAcquisitionMode: DungeonCardAcquisitionMode = .deck,
        cardPickups: [DungeonCardPickupDefinition] = [],
        specialPickups: [DungeonSpecialPickupDefinition] = [],
        relicPickups: [DungeonRelicPickupDefinition] = [],
        isDarknessEnabled: Bool = false
    ) {
        self.difficulty = difficulty
        self.failureRule = failureRule
        self.enemies = enemies
        self.hazards = hazards
        self.exitLock = exitLock
        self.allowsBasicOrthogonalMove = allowsBasicOrthogonalMove
        self.movementStyle = movementStyle
        self.cardAcquisitionMode = cardAcquisitionMode
        self.cardPickups = cardPickups
        self.specialPickups = specialPickups
        self.relicPickups = relicPickups
        self.isDarknessEnabled = isDarknessEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case difficulty
        case failureRule
        case enemies
        case hazards
        case exitLock
        case allowsBasicOrthogonalMove
        case movementStyle
        case cardAcquisitionMode
        case cardPickups
        case specialPickups
        case relicPickups
        case isDarknessEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        difficulty = try container.decode(DungeonDifficulty.self, forKey: .difficulty)
        failureRule = try container.decode(DungeonFailureRule.self, forKey: .failureRule)
        enemies = try container.decodeIfPresent([EnemyDefinition].self, forKey: .enemies) ?? []
        hazards = try container.decodeIfPresent([HazardDefinition].self, forKey: .hazards) ?? []
        exitLock = try container.decodeIfPresent(DungeonExitLock.self, forKey: .exitLock)
        allowsBasicOrthogonalMove = try container.decodeIfPresent(Bool.self, forKey: .allowsBasicOrthogonalMove) ?? false
        movementStyle = try container.decodeIfPresent(DungeonMovementStyle.self, forKey: .movementStyle) ?? .orthogonal
        cardAcquisitionMode = try container.decodeIfPresent(DungeonCardAcquisitionMode.self, forKey: .cardAcquisitionMode) ?? .deck
        cardPickups = try container.decodeIfPresent([DungeonCardPickupDefinition].self, forKey: .cardPickups) ?? []
        specialPickups = try container.decodeIfPresent([DungeonSpecialPickupDefinition].self, forKey: .specialPickups) ?? []
        relicPickups = try container.decodeIfPresent([DungeonRelicPickupDefinition].self, forKey: .relicPickups) ?? []
        isDarknessEnabled = try container.decodeIfPresent(Bool.self, forKey: .isDarknessEnabled) ?? false
    }
}

/// 塔ダンジョン定義の入口
public struct DungeonLibrary {
    public static let shared = DungeonLibrary()

    private static let tutorialTowerBoardSize = 9
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
        dungeons.first(where: { $0.id == id })
    }

    public func firstFloorMode(
        for dungeon: DungeonDefinition,
        initialHPBonus: Int = 0,
        startingHazardDamageMitigations: Int = 0,
        startingEnemyDamageMitigations: Int = 0,
        startingMarkerDamageMitigations: Int = 0,
        movementStyle: DungeonMovementStyle = .orthogonal,
        dungeonInventoryKindLimit: Int = 9,
        cardVariationSeed: UInt64? = nil
    ) -> GameMode? {
        floorMode(
            for: dungeon,
            floorIndex: 0,
            initialHPBonus: initialHPBonus,
            startingHazardDamageMitigations: startingHazardDamageMitigations,
            startingEnemyDamageMitigations: startingEnemyDamageMitigations,
            startingMarkerDamageMitigations: startingMarkerDamageMitigations,
            movementStyle: movementStyle,
            dungeonInventoryKindLimit: dungeonInventoryKindLimit,
            cardVariationSeed: cardVariationSeed
        )
    }

    public func floorMode(
        for dungeon: DungeonDefinition,
        floorIndex: Int,
        initialHPBonus: Int = 0,
        startingRewardEntries: [DungeonInventoryEntry] = [],
        startingRelicEntries: [DungeonRelicEntry] = [],
        startingHazardDamageMitigations: Int = 0,
        startingEnemyDamageMitigations: Int = 0,
        startingMarkerDamageMitigations: Int = 0,
        movementStyle: DungeonMovementStyle = .orthogonal,
        dungeonInventoryKindLimit: Int = 9,
        cardVariationSeed: UInt64? = nil
    ) -> GameMode? {
        guard dungeon.supportsInfiniteFloors || dungeon.floors.indices.contains(floorIndex) else { return nil }
        let baseFloor = dungeon.floors[min(max(floorIndex, 0), dungeon.floors.count - 1)]
        let resolvedInitialHPBonus = dungeon.difficulty == .growth ? max(initialHPBonus, 0) : 0
        let resolvedCardVariationSeed = dungeon.id == "growth-tower"
            ? cardVariationSeed ?? Self.makeCardVariationSeed()
            : nil
        let resolvedRogueTowerSeed = dungeon.supportsInfiniteFloors
            ? cardVariationSeed ?? Self.makeCardVariationSeed()
            : nil
        let resolvedMovementStyle: DungeonMovementStyle = (dungeon.difficulty == .growth || dungeon.supportsInfiniteFloors)
            ? movementStyle
            : .orthogonal
        let resolvedInventoryKindLimit: Int
        if dungeon.supportsInfiniteFloors {
            resolvedInventoryKindLimit = 5
        } else if dungeon.difficulty == .growth {
            resolvedInventoryKindLimit = dungeonInventoryKindLimit
        } else {
            resolvedInventoryKindLimit = 9
        }
        let runState = DungeonRunState(
            dungeonID: dungeon.id,
            currentFloorIndex: floorIndex,
            carriedHP: baseFloor.failureRule.initialHP + resolvedInitialHPBonus,
            clearedFloorCount: floorIndex,
            rewardInventoryEntries: startingRewardEntries,
            relicEntries: dungeon.difficulty == .growth ? startingRelicEntries : [],
            cardVariationSeed: resolvedCardVariationSeed,
            movementStyle: resolvedMovementStyle,
            dungeonInventoryKindLimit: resolvedInventoryKindLimit,
            rogueTowerSeed: resolvedRogueTowerSeed,
            hazardDamageMitigationsRemaining: dungeon.difficulty == .growth ? startingHazardDamageMitigations : 0,
            enemyDamageMitigationsRemaining: dungeon.difficulty == .growth ? startingEnemyDamageMitigations : 0,
            markerDamageMitigationsRemaining: dungeon.difficulty == .growth ? startingMarkerDamageMitigations : 0
        )
        let floor = dungeon.resolvedFloor(at: floorIndex, runState: runState) ?? baseFloor
        return floor.makeGameMode(
            dungeonID: dungeon.id,
            difficulty: dungeon.difficulty,
            carriedHP: runState.carriedHP,
            runState: runState
        )
    }

    public func resumeMode(from snapshot: DungeonRunResumeSnapshot) -> GameMode? {
        guard snapshot.version == DungeonRunResumeSnapshot.currentVersion,
              let dungeon = dungeon(with: snapshot.dungeonID),
              (dungeon.supportsInfiniteFloors || dungeon.floors.indices.contains(snapshot.floorIndex)),
              snapshot.runState.dungeonID == dungeon.id,
              snapshot.runState.currentFloorIndex == snapshot.floorIndex
        else { return nil }

        let floor = dungeon.resolvedFloor(at: snapshot.floorIndex, runState: snapshot.runState)
            ?? dungeon.floors[min(snapshot.floorIndex, dungeon.floors.count - 1)]
        return floor.makeGameMode(
            dungeonID: dungeon.id,
            difficulty: dungeon.difficulty,
            carriedHP: max(snapshot.dungeonHP, 1),
            runState: snapshot.runState
        )
    }

    private static func makeCardVariationSeed() -> UInt64 {
        var seed = UInt64.random(in: 1...UInt64.max)
        seed ^= UInt64(Date().timeIntervalSinceReferenceDate * 1000)
        return seed == 0 ? 1 : seed
    }

    private static func buildTutorialTower() -> DungeonDefinition {
        let floors = stitchDungeonFloors([
            DungeonFloorDefinition(
                id: "tutorial-1",
                title: "塔の入口",
                boardSize: tutorialTowerBoardSize,
                spawnPoint: GridPoint(x: 0, y: 0),
                exitPoint: GridPoint(x: 4, y: 4),
                deckPreset: .kingAndKnightBasic,
                failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 12),
                cardPickups: [
                    DungeonCardPickupDefinition(
                        id: "tutorial-1-up2",
                        point: GridPoint(x: 0, y: 1),
                        card: .straightUp2
                    ),
                    DungeonCardPickupDefinition(
                        id: "tutorial-1-right2",
                        point: GridPoint(x: 0, y: 3),
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
                exitPoint: GridPoint(x: 8, y: 4),
                deckPreset: .kingAndKnightBasic,
                failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 15),
                enemies: [
                    EnemyDefinition(
                        id: "watcher-1",
                        name: "見張り",
                        position: GridPoint(x: 4, y: 2),
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
                        point: GridPoint(x: 8, y: 1),
                        card: .straightUp2
                    ),
                    DungeonCardPickupDefinition(
                        id: "tutorial-2-knight",
                        point: GridPoint(x: 3, y: 0),
                        card: .knightRightwardChoice
                    )
                ],
                rewardMoveCardsAfterClear: [
                    .rayLeft,
                    .straightRight2,
                    .knightRightwardChoice,
                ]
            ),
            DungeonFloorDefinition(
                id: "tutorial-3",
                title: "ひび割れ床",
                boardSize: tutorialTowerBoardSize,
                spawnPoint: GridPoint(x: 0, y: 4),
                exitPoint: GridPoint(x: 0, y: 4),
                deckPreset: .standardLight,
                failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 15),
                enemies: [
                    EnemyDefinition(
                        id: "guard-1",
                        name: "番兵",
                        position: GridPoint(x: 5, y: 5),
                        behavior: .guardPost
                    )
                ],
                hazards: [
                    .brittleFloor(points: [
                        GridPoint(x: 3, y: 4),
                        GridPoint(x: 4, y: 4),
                        GridPoint(x: 5, y: 4),
                        GridPoint(x: 6, y: 4)
                    ])
                ],
                cardPickups: [
                    DungeonCardPickupDefinition(
                        id: "tutorial-3-ray-right",
                        point: GridPoint(x: 0, y: 3),
                        card: .rayRight
                    ),
                    DungeonCardPickupDefinition(
                        id: "tutorial-3-up2",
                        point: GridPoint(x: 2, y: 3),
                        card: .straightUp2
                    ),
                    DungeonCardPickupDefinition(
                        id: "tutorial-3-knight",
                        point: GridPoint(x: 1, y: 5),
                        card: .knightRightwardChoice
                    )
                ],
                rewardMoveCardsAfterClear: [
                    .rayRight,
                    .straightUp2,
                    .diagonalUpRight2
                ]
            ),
            DungeonFloorDefinition(
                id: "tutorial-4",
                title: "鍵の小部屋",
                boardSize: tutorialTowerBoardSize,
                spawnPoint: GridPoint(x: 0, y: 4),
                exitPoint: GridPoint(x: 8, y: 4),
                deckPreset: .kingAndKnightBasic,
                failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 18),
                impassableTilePoints: [
                    GridPoint(x: 4, y: 4)
                ],
                exitLock: DungeonExitLock(unlockPoint: GridPoint(x: 2, y: 6)),
                cardPickups: [
                    DungeonCardPickupDefinition(
                        id: "tutorial-4-right2",
                        point: GridPoint(x: 1, y: 4),
                        card: .straightRight2
                    ),
                    DungeonCardPickupDefinition(
                        id: "tutorial-4-up2",
                        point: GridPoint(x: 2, y: 5),
                        card: .straightUp2
                    ),
                    DungeonCardPickupDefinition(
                        id: "tutorial-4-knight",
                        point: GridPoint(x: 5, y: 6),
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
                id: "tutorial-5",
                title: "見える罠",
                boardSize: tutorialTowerBoardSize,
                spawnPoint: GridPoint(x: 0, y: 4),
                exitPoint: GridPoint(x: 0, y: 4),
                deckPreset: .standardLight,
                failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 16),
                hazards: [
                    .damageTrap(
                        points: [
                            GridPoint(x: 3, y: 4),
                            GridPoint(x: 5, y: 4)
                        ],
                        damage: 1
                    )
                ],
                cardPickups: [
                    DungeonCardPickupDefinition(
                        id: "tutorial-5-ray-right",
                        point: GridPoint(x: 1, y: 2),
                        card: .rayRight
                    ),
                    DungeonCardPickupDefinition(
                        id: "tutorial-5-up2",
                        point: GridPoint(x: 2, y: 6),
                        card: .straightUp2
                    ),
                    DungeonCardPickupDefinition(
                        id: "tutorial-5-diagonal-up-right",
                        point: GridPoint(x: 4, y: 2),
                        card: .diagonalUpRight2
                    )
                ],
                rewardMoveCardsAfterClear: [
                    .rayRight,
                    .straightRight2,
                    .knightRightwardChoice
                ]
            ),
            DungeonFloorDefinition(
                id: "tutorial-6",
                title: "転移と巡回",
                boardSize: tutorialTowerBoardSize,
                spawnPoint: GridPoint(x: 0, y: 0),
                exitPoint: GridPoint(x: 8, y: 8),
                deckPreset: .standardLight,
                failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 18),
                enemies: [
                    EnemyDefinition(
                        id: "tutorial-6-patrol",
                        name: "巡回兵",
                        position: GridPoint(x: 3, y: 4),
                        behavior: .patrol(path: [
                            GridPoint(x: 3, y: 4),
                            GridPoint(x: 4, y: 4),
                            GridPoint(x: 5, y: 4),
                            GridPoint(x: 6, y: 4),
                            GridPoint(x: 5, y: 4),
                            GridPoint(x: 4, y: 4)
                        ])
                    )
                ],
                warpTilePairs: [
                    "tutorial-6-shortcut": [
                        GridPoint(x: 2, y: 1),
                        GridPoint(x: 6, y: 6)
                    ]
                ],
                cardPickups: [
                    DungeonCardPickupDefinition(
                        id: "tutorial-6-right2",
                        point: GridPoint(x: 1, y: 0),
                        card: .straightRight2
                    ),
                    DungeonCardPickupDefinition(
                        id: "tutorial-6-up2",
                        point: GridPoint(x: 6, y: 7),
                        card: .straightUp2
                    ),
                    DungeonCardPickupDefinition(
                        id: "tutorial-6-knight",
                        point: GridPoint(x: 7, y: 6),
                        card: .knightRightwardChoice
                    )
                ]
            )
        ])

        return DungeonDefinition(
            id: "tutorial-tower",
            title: "基礎塔",
            summary: "出口、敵、床、鍵、罠、転移を順に学び、成長塔の入口へ備えるチュートリアル塔。",
            difficulty: .tutorial,
            floors: floors
        )
    }

    private static func buildGrowthTower() -> DungeonDefinition {
        let patrolFloors = buildGrowthPatrolBaseFloors()
        let keyDoorFloors = buildGrowthKeyBaseFloors()
        let warpFloors = buildGrowthWarpBaseFloors()
        let trapFloors = buildGrowthTrapBaseFloors()
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
            growthFloorWithRewardCards(
                warpFloors[0].withAdditionalCardPickups([
                    DungeonCardPickupDefinition(id: "growth-4-down2", point: GridPoint(x: 8, y: 2), card: .straightDown2),
                    DungeonCardPickupDefinition(id: "growth-4-ray-left", point: GridPoint(x: 4, y: 8), card: .rayLeft)
                ])
                .withAdditionalImpassableTilePoints([
                    GridPoint(x: 3, y: 3),
                    GridPoint(x: 6, y: 2)
                ])
                .withAdditionalRelicPickups([
                    DungeonRelicPickupDefinition(id: "growth-4-relic", point: GridPoint(x: 2, y: 6))
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
            growthFloorWithRewardCards(
                warpFloors[1].withAdditionalCardPickups([
                    DungeonCardPickupDefinition(id: "growth-6-left2", point: GridPoint(x: 8, y: 6), card: .straightLeft2),
                    DungeonCardPickupDefinition(id: "growth-6-diagonal-down-right", point: GridPoint(x: 2, y: 2), card: .diagonalDownRight2)
                ])
                .withAdditionalImpassableTilePoints([
                    GridPoint(x: 3, y: 5),
                    GridPoint(x: 6, y: 2)
                ])
                .withAdditionalHazards([
                    .healingTile(points: [GridPoint(x: 5, y: 3)], amount: 1)
                ]),
                title: "転移の抜け道",
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
                            initialDirection: MoveVector(dx: -1, dy: 0),
                            rotationDirection: .counterclockwise,
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
                .withAdditionalRelicPickups([
                    DungeonRelicPickupDefinition(id: "growth-8-relic", point: GridPoint(x: 5, y: 7))
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
        ] + buildGrowthTowerDeepFloors()
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
            19: GridPoint(x: 8, y: 8),
            20: GridPoint(x: 8, y: 4),
            21: GridPoint(x: 0, y: 6),
            22: GridPoint(x: 8, y: 2),
            23: GridPoint(x: 0, y: 0),
            24: GridPoint(x: 8, y: 4),
            25: GridPoint(x: 4, y: 8),
            26: GridPoint(x: 0, y: 2),
            27: GridPoint(x: 8, y: 6),
            28: GridPoint(x: 2, y: 8),
            29: GridPoint(x: 8, y: 8),
            30: GridPoint(x: 8, y: 4),
            31: GridPoint(x: 0, y: 6),
            32: GridPoint(x: 8, y: 2),
            33: GridPoint(x: 0, y: 0),
            34: GridPoint(x: 8, y: 6),
            35: GridPoint(x: 4, y: 8),
            36: GridPoint(x: 0, y: 2),
            37: GridPoint(x: 8, y: 6),
            38: GridPoint(x: 2, y: 8),
            39: GridPoint(x: 8, y: 8),
            40: GridPoint(x: 8, y: 4),
            41: GridPoint(x: 0, y: 6),
            42: GridPoint(x: 8, y: 2),
            43: GridPoint(x: 0, y: 0),
            44: GridPoint(x: 8, y: 4),
            45: GridPoint(x: 4, y: 8),
            46: GridPoint(x: 0, y: 2),
            47: GridPoint(x: 8, y: 6),
            48: GridPoint(x: 2, y: 8),
            49: GridPoint(x: 8, y: 8)
        ]
        var previousExitPoint: GridPoint?

        return floors.enumerated().map { index, floor in
            let spawnPoint = previousExitPoint ?? floor.spawnPoint
            let exitPoint = exitPointsByFloorIndex[index] ?? floor.exitPoint
            previousExitPoint = exitPoint
            return floor.withEndpoints(
                spawnPoint: spawnPoint,
                exitPoint: exitPoint
            )
        }
    }

    private static func stitchDungeonFloors(_ floors: [DungeonFloorDefinition]) -> [DungeonFloorDefinition] {
        var previousExitPoint: GridPoint?
        return floors.map { floor in
            let stitchedFloor = floor.withEndpoints(spawnPoint: previousExitPoint)
            previousExitPoint = stitchedFloor.exitPoint
            return stitchedFloor
        }
    }

    private static func stairKeyOnlyGrowthFloor(
        _ floor: DungeonFloorDefinition,
        rewardMoveCardsAfterClear: [MoveCard]? = nil
    ) -> DungeonFloorDefinition {
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
            exitLock: floor.exitLock,
            cardPickups: floor.cardPickups,
            specialPickups: floor.specialPickups,
            relicPickups: floor.relicPickups,
            rewardMoveCardsAfterClear: rewardMoveCardsAfterClear ?? floor.rewardMoveCardsAfterClear,
            rewardSupportCardsAfterClear: floor.rewardSupportCardsAfterClear,
            isDarknessEnabled: floor.isDarknessEnabled
        )
    }

    private static func growthFloorWithRewardCards(
        _ floor: DungeonFloorDefinition,
        title: String? = nil,
        rewardMoveCardsAfterClear: [MoveCard]? = nil
    ) -> DungeonFloorDefinition {
        let cardPickups = floor.cardPickups

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
            exitLock: floor.exitLock,
            cardPickups: cardPickups,
            specialPickups: floor.specialPickups,
            relicPickups: floor.relicPickups,
            rewardMoveCardsAfterClear: rewardMoveCardsAfterClear ?? floor.rewardMoveCardsAfterClear,
            rewardSupportCardsAfterClear: floor.rewardSupportCardsAfterClear,
            isDarknessEnabled: floor.isDarknessEnabled
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
                    position: GridPoint(x: 4, y: 5),
                    behavior: .patrol(path: [
                        GridPoint(x: 4, y: 5),
                        GridPoint(x: 5, y: 5),
                        GridPoint(x: 6, y: 5),
                        GridPoint(x: 7, y: 5),
                        GridPoint(x: 6, y: 5),
                        GridPoint(x: 5, y: 5)
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
                    GridPoint(x: 7, y: 7)
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
                    point: GridPoint(x: 1, y: 1),
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
                    position: GridPoint(x: 4, y: 4),
                    behavior: .patrol(path: [
                        GridPoint(x: 4, y: 4),
                        GridPoint(x: 5, y: 4),
                        GridPoint(x: 6, y: 4),
                        GridPoint(x: 7, y: 4),
                        GridPoint(x: 6, y: 4),
                        GridPoint(x: 5, y: 4)
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
                DungeonCardPickupDefinition(id: "growth-10-diagonal", point: GridPoint(x: 2, y: 0), card: .diagonalUpRight2),
                DungeonCardPickupDefinition(id: "growth-10-up2", point: GridPoint(x: 8, y: 6), card: .straightUp2)
            ],
            rewardMoveCardsAfterClear: [
                .straightRight2,
                .straightUp2,
                .diagonalUpRight2
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
                    position: GridPoint(x: 2, y: 3),
                    behavior: .patrol(path: [
                        GridPoint(x: 2, y: 3),
                        GridPoint(x: 3, y: 3),
                        GridPoint(x: 4, y: 3),
                        GridPoint(x: 5, y: 3),
                        GridPoint(x: 6, y: 3),
                        GridPoint(x: 5, y: 3),
                        GridPoint(x: 4, y: 3),
                        GridPoint(x: 3, y: 3)
                    ])
                ),
                EnemyDefinition(
                    id: "growth-11-patrol-b",
                    name: "巡回兵",
                    position: GridPoint(x: 6, y: 4),
                    behavior: .patrol(path: [
                        GridPoint(x: 6, y: 4),
                        GridPoint(x: 6, y: 5),
                        GridPoint(x: 6, y: 6),
                        GridPoint(x: 6, y: 7),
                        GridPoint(x: 6, y: 8),
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
            rewardMoveCardsAfterClear: [.rayDown, .straightDown2],
            rewardSupportCardsAfterClear: [.refillEmptySlots]
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
                        initialDirection: MoveVector(dx: -1, dy: 0),
                        rotationDirection: .clockwise,
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
                ], damage: 1),
                .healingTile(points: [GridPoint(x: 6, y: 4)], amount: 1)
            ],
            impassableTilePoints: [
                GridPoint(x: 1, y: 5),
                GridPoint(x: 5, y: 2),
                GridPoint(x: 7, y: 6)
            ],
            tileEffectOverrides: [
                GridPoint(x: 5, y: 7): .swamp,
                GridPoint(x: 6, y: 6): .swamp,
                GridPoint(x: 6, y: 7): .swamp
            ],
            exitLock: DungeonExitLock(unlockPoint: GridPoint(x: 2, y: 2)),
            cardPickups: [
                DungeonCardPickupDefinition(id: "growth-12-key-up2", point: GridPoint(x: 1, y: 2), card: .straightUp2),
                DungeonCardPickupDefinition(id: "growth-12-right2", point: GridPoint(x: 0, y: 1), card: .straightRight2),
                DungeonCardPickupDefinition(id: "growth-12-ray-right", point: GridPoint(x: 4, y: 5), card: .rayRight)
            ],
            relicPickups: [
                DungeonRelicPickupDefinition(id: "growth-12-relic", point: GridPoint(x: 3, y: 6), kind: .suspiciousLight)
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
                        initialDirection: MoveVector(dx: 0, dy: 1),
                        rotationDirection: .counterclockwise,
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
                    GridPoint(x: 6, y: 4)
                ],
                "growth-13-safe": [
                    GridPoint(x: 2, y: 2),
                    GridPoint(x: 7, y: 5)
                ]
            ],
            cardPickups: [
                DungeonCardPickupDefinition(id: "growth-13-ray-right", point: GridPoint(x: 0, y: 3), card: .rayRight),
                DungeonCardPickupDefinition(id: "growth-13-up2", point: GridPoint(x: 3, y: 2), card: .straightUp2),
                DungeonCardPickupDefinition(id: "growth-13-right2", point: GridPoint(x: 7, y: 4), card: .straightRight2)
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
                DungeonCardPickupDefinition(id: "growth-14-diagonal", point: GridPoint(x: 6, y: 3), card: .diagonalUpRight2)
            ],
            rewardMoveCardsAfterClear: [.diagonalDownLeft2, .rayLeft, .straightDown2]
        )
    }

    private static func buildGrowthTowerFifteenthFloor() -> DungeonFloorDefinition {
        DungeonFloorDefinition(
            id: "growth-15",
            title: "第二関門・宝箱警戒",
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
                        initialDirection: MoveVector(dx: -1, dy: 0),
                        rotationDirection: .clockwise,
                        range: 4
                    )
                ),
                EnemyDefinition(id: "growth-15-patrol", name: "巡回兵", position: GridPoint(x: 3, y: 4), behavior: .patrol(path: [GridPoint(x: 3, y: 4), GridPoint(x: 4, y: 4), GridPoint(x: 5, y: 4), GridPoint(x: 6, y: 4), GridPoint(x: 5, y: 4), GridPoint(x: 4, y: 4)])),
                EnemyDefinition(
                    id: "growth-15-chaser",
                    name: "追跡兵",
                    position: GridPoint(x: 3, y: 7),
                    behavior: .chaser
                )
            ],
            hazards: [
                .damageTrap(points: [GridPoint(x: 2, y: 2), GridPoint(x: 5, y: 5), GridPoint(x: 7, y: 6)], damage: 1)
            ],
            impassableTilePoints: [
                GridPoint(x: 1, y: 6),
                GridPoint(x: 3, y: 3),
                GridPoint(x: 5, y: 1),
                GridPoint(x: 7, y: 2)
            ],
            tileEffectOverrides: [
                GridPoint(x: 8, y: 4): .discardAllMoveCards,
                GridPoint(x: 4, y: 6): .swamp,
                GridPoint(x: 4, y: 7): .swamp,
                GridPoint(x: 5, y: 6): .swamp,
                GridPoint(x: 5, y: 7): .swamp
            ],
            warpTilePairs: ["growth-15-warp": [GridPoint(x: 1, y: 2), GridPoint(x: 6, y: 6)]],
            exitLock: DungeonExitLock(unlockPoint: GridPoint(x: 2, y: 1)),
            cardPickups: [
                DungeonCardPickupDefinition(id: "growth-15-right2", point: GridPoint(x: 0, y: 1), card: .straightRight2),
                DungeonCardPickupDefinition(id: "growth-15-key-diagonal", point: GridPoint(x: 2, y: 0), card: .diagonalUpRight2),
                DungeonCardPickupDefinition(id: "growth-15-up2", point: GridPoint(x: 6, y: 7), card: .straightUp2)
            ],
            relicPickups: [
                DungeonRelicPickupDefinition(id: "growth-15-relic", point: GridPoint(x: 7, y: 1), kind: .suspiciousLight)
            ],
            rewardMoveCardsAfterClear: [.rayRight, .diagonalUpRight2],
            rewardSupportCardsAfterClear: [.refillEmptySlots]
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
                        initialDirection: MoveVector(dx: 0, dy: 1),
                        rotationDirection: .clockwise,
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
            hazards: [
                .damageTrap(points: [GridPoint(x: 3, y: 4), GridPoint(x: 5, y: 4)], damage: 1),
                .healingTile(points: [GridPoint(x: 2, y: 4)], amount: 1)
            ],
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
            relicPickups: [
                DungeonRelicPickupDefinition(id: "growth-16-relic", point: GridPoint(x: 5, y: 1), kind: .suspiciousDeep)
            ],
            rewardMoveCardsAfterClear: [.diagonalUpLeft2, .rayLeft],
            rewardSupportCardsAfterClear: [.singleAnnihilationSpell]
        )
    }

    private static func buildGrowthTowerSeventeenthFloor() -> DungeonFloorDefinition {
        DungeonFloorDefinition(
            id: "growth-17",
            title: "暗闇の遠回り",
            boardSize: standardTowerBoardSize,
            spawnPoint: GridPoint(x: 0, y: 0),
            exitPoint: GridPoint(x: 8, y: 8),
            deckPreset: .standardLight,
            failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 17),
            enemies: [
                EnemyDefinition(id: "growth-17-patrol", name: "巡回兵", position: GridPoint(x: 3, y: 5), behavior: .patrol(path: [GridPoint(x: 3, y: 5), GridPoint(x: 4, y: 5), GridPoint(x: 5, y: 5), GridPoint(x: 6, y: 5), GridPoint(x: 5, y: 5), GridPoint(x: 4, y: 5)])),
                EnemyDefinition(
                    id: "growth-17-marker",
                    name: "メテオ兵",
                    position: GridPoint(x: 7, y: 4),
                    behavior: .marker(
                        directions: [],
                        range: 3
                    )
                )
            ],
            hazards: [.brittleFloor(points: [GridPoint(x: 3, y: 1), GridPoint(x: 3, y: 2), GridPoint(x: 3, y: 3)])],
            impassableTilePoints: [
                GridPoint(x: 2, y: 4),
                GridPoint(x: 4, y: 6),
                GridPoint(x: 7, y: 1)
            ],
            exitLock: DungeonExitLock(unlockPoint: GridPoint(x: 1, y: 5)),
            cardPickups: [
                DungeonCardPickupDefinition(id: "growth-17-up2", point: GridPoint(x: 1, y: 4), card: .straightUp2),
                DungeonCardPickupDefinition(id: "growth-17-ray-right", point: GridPoint(x: 2, y: 0), card: .rayRight),
                DungeonCardPickupDefinition(id: "growth-17-diagonal", point: GridPoint(x: 6, y: 6), card: .diagonalUpRight2)
            ],
            rewardMoveCardsAfterClear: [.straightRight2, .knightRightwardChoice],
            rewardSupportCardsAfterClear: [.annihilationSpell],
            isDarknessEnabled: true
        )
    }

    private static func buildGrowthTowerEighteenthFloor() -> DungeonFloorDefinition {
        DungeonFloorDefinition(
            id: "growth-18",
            title: "暗闇の射線",
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
                        initialDirection: MoveVector(dx: -1, dy: 0),
                        rotationDirection: .counterclockwise,
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
            hazards: [
                .damageTrap(points: [GridPoint(x: 1, y: 1), GridPoint(x: 2, y: 2), GridPoint(x: 3, y: 3), GridPoint(x: 6, y: 5)], damage: 1),
                .lavaTile(points: [GridPoint(x: 7, y: 4)], damage: 1)
            ],
            impassableTilePoints: [
                GridPoint(x: 3, y: 7),
                GridPoint(x: 4, y: 2),
                GridPoint(x: 5, y: 5),
                GridPoint(x: 7, y: 3)
            ],
            tileEffectOverrides: [
                GridPoint(x: 7, y: 2): .discardAllSupportCards,
                GridPoint(x: 2, y: 4): .poisonTrap,
                GridPoint(x: 4, y: 4): .swamp,
                GridPoint(x: 4, y: 5): .swamp,
                GridPoint(x: 5, y: 4): .swamp,
                GridPoint(x: 6, y: 4): .swamp
            ],
            warpTilePairs: ["growth-18-choice": [GridPoint(x: 1, y: 0), GridPoint(x: 6, y: 6)]],
            cardPickups: [
                DungeonCardPickupDefinition(id: "growth-18-ray-right", point: GridPoint(x: 0, y: 1), card: .rayRight),
                DungeonCardPickupDefinition(id: "growth-18-right2", point: GridPoint(x: 2, y: 1), card: .straightRight2),
                DungeonCardPickupDefinition(id: "growth-18-up2", point: GridPoint(x: 8, y: 6), card: .straightUp2)
            ],
            rewardMoveCardsAfterClear: [.diagonalDownLeft2, .rayLeft],
            rewardSupportCardsAfterClear: [.freezeSpell],
            isDarknessEnabled: true
        )
    }

    private static func buildGrowthTowerNineteenthFloor() -> DungeonFloorDefinition {
        DungeonFloorDefinition(
            id: "growth-19",
            title: "暗闇の前哨",
            boardSize: standardTowerBoardSize,
            spawnPoint: GridPoint(x: 0, y: 2),
            exitPoint: GridPoint(x: 8, y: 8),
            deckPreset: .standardLight,
            failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 15),
            enemies: [
                EnemyDefinition(id: "growth-19-patrol-a", name: "巡回兵", position: GridPoint(x: 4, y: 4), behavior: .patrol(path: [GridPoint(x: 4, y: 4), GridPoint(x: 5, y: 4), GridPoint(x: 5, y: 5), GridPoint(x: 4, y: 5), GridPoint(x: 3, y: 5), GridPoint(x: 4, y: 5), GridPoint(x: 5, y: 5), GridPoint(x: 5, y: 4)])),
                EnemyDefinition(id: "growth-19-watcher", name: "見張り", position: GridPoint(x: 7, y: 5), behavior: .watcher(direction: MoveVector(dx: -1, dy: 0), range: 5))
            ],
            hazards: [
                .brittleFloor(points: [GridPoint(x: 2, y: 2), GridPoint(x: 3, y: 2)]),
                .lavaTile(points: [GridPoint(x: 6, y: 4)], damage: 1),
                .damageTrap(points: [GridPoint(x: 5, y: 6), GridPoint(x: 6, y: 7)], damage: 1),
                .healingTile(points: [GridPoint(x: 2, y: 5)], amount: 1)
            ],
            impassableTilePoints: [
                GridPoint(x: 1, y: 4),
                GridPoint(x: 3, y: 6),
                GridPoint(x: 6, y: 3),
                GridPoint(x: 7, y: 1)
            ],
            tileEffectOverrides: [
                GridPoint(x: 3, y: 3): .poisonTrap,
                GridPoint(x: 6, y: 2): .illusionTrap,
                GridPoint(x: 8, y: 4): .shackleTrap
            ],
            cardPickups: [
                DungeonCardPickupDefinition(id: "growth-19-ray-right", point: GridPoint(x: 0, y: 1), card: .rayRight),
                DungeonCardPickupDefinition(id: "growth-19-diagonal", point: GridPoint(x: 4, y: 3), card: .diagonalUpRight2),
                DungeonCardPickupDefinition(id: "growth-19-up2", point: GridPoint(x: 8, y: 6), card: .straightUp2)
            ],
            relicPickups: [
                DungeonRelicPickupDefinition(id: "growth-19-relic", point: GridPoint(x: 6, y: 1), kind: .suspiciousDeep)
            ],
            rewardMoveCardsAfterClear: [.straightRight2, .diagonalUpRight2],
            rewardSupportCardsAfterClear: [.barrierSpell],
            isDarknessEnabled: true
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
                        initialDirection: MoveVector(dx: -1, dy: 0),
                        rotationDirection: .counterclockwise,
                        range: 4
                    )
                ),
                EnemyDefinition(id: "growth-20-patrol", name: "巡回兵", position: GridPoint(x: 4, y: 5), behavior: .patrol(path: [GridPoint(x: 4, y: 5), GridPoint(x: 5, y: 5), GridPoint(x: 6, y: 5), GridPoint(x: 7, y: 5), GridPoint(x: 6, y: 5), GridPoint(x: 5, y: 5)])),
                EnemyDefinition(
                    id: "growth-20-chaser",
                    name: "追跡兵",
                    position: GridPoint(x: 7, y: 7),
                    behavior: .chaser
                )
            ],
            hazards: [
                .damageTrap(points: [GridPoint(x: 2, y: 2), GridPoint(x: 3, y: 3), GridPoint(x: 5, y: 6)], damage: 1)
            ],
            impassableTilePoints: [
                GridPoint(x: 1, y: 5),
                GridPoint(x: 3, y: 6),
                GridPoint(x: 6, y: 2),
                GridPoint(x: 7, y: 4)
            ],
            tileEffectOverrides: [
                GridPoint(x: 8, y: 3): .discardAllHands
            ],
            warpTilePairs: ["growth-20-risk": [GridPoint(x: 1, y: 2), GridPoint(x: 6, y: 6)]],
            exitLock: DungeonExitLock(unlockPoint: GridPoint(x: 2, y: 1)),
            cardPickups: [
                DungeonCardPickupDefinition(id: "growth-20-right2", point: GridPoint(x: 0, y: 1), card: .straightRight2),
                DungeonCardPickupDefinition(id: "growth-20-key-diagonal", point: GridPoint(x: 2, y: 0), card: .diagonalUpRight2),
                DungeonCardPickupDefinition(id: "growth-20-up2", point: GridPoint(x: 8, y: 6), card: .straightUp2)
            ],
            rewardMoveCardsAfterClear: [.rayRight, .diagonalUpRight2],
            rewardSupportCardsAfterClear: [.barrierSpell]
        )
    }

    private static func buildGrowthTowerDeepFloors() -> [DungeonFloorDefinition] {
        let fallSecret24 = growthFallSecret(
            id: "growth-fall-secret-24-to-23",
            sourceFloorNumber: 24,
            entrance: (8, 8),
            landing: (8, 8),
            treasure: (7, 8),
            treasureKind: .safe,
            returnWarp: (8, 7),
            returnDestination: (5, 4),
            chamberWalls: [(6, 8), (7, 7), (8, 6)]
        )
        return [
            makeGrowthTowerDeepFloor(
                number: 21,
                title: "寄り道の分岐",
                turnLimit: 17,
                enemies: [
                    growthPatrol("growth-21-patrol", [(3, 3), (4, 3), (5, 3), (6, 3), (5, 3), (4, 3)]),
                    growthWatcher("growth-21-watcher", position: (6, 6), direction: (-1, 0), range: 4)
                ],
                hazards: [.damageTrap(points: gridSet([(2, 2), (6, 5)]), damage: 1)],
                impassableTilePoints: gridSet([(2, 5), (4, 6), (7, 3)]),
                warpTilePairs: ["growth-21-shortcut": gridPoints([(1, 2), (7, 7)])],
                exitLock: DungeonExitLock(unlockPoint: GridPoint(x: 2, y: 1)),
                cardPickups: growthCards(21, [((1, 1), .straightRight2), ((3, 1), .diagonalUpRight2), ((6, 7), .rayLeft)]),
                relicPickups: [growthRelic(21, at: (5, 5), kind: .safe)],
                exitPoint: GridPoint(x: 8, y: 4),
                rewardMoveCardsAfterClear: [.rayUpRight, .straightLeft2, .knightRightwardChoice],
                rewardSupportCardsAfterClear: [.refillEmptySlots]
            ),
            makeGrowthTowerDeepFloor(
                number: 22,
                title: "宝箱の門番",
                turnLimit: 16,
                enemies: [
                    growthRotatingWatcher("growth-22-rotating", position: (5, 5), direction: (0, -1), rotation: .clockwise, range: 4),
                    growthChaser("growth-22-chaser", position: (6, 1))
                ],
                hazards: [
                    .damageTrap(points: gridSet([(3, 2), (5, 4)]), damage: 1),
                    .healingTile(points: gridSet([(2, 4)]), amount: 1)
                ],
                impassableTilePoints: gridSet([(2, 6), (4, 2), (7, 5)]),
                tileEffectOverrides: gridEffects([((6, 4), .swamp), ((6, 5), .swamp)]),
                cardPickups: growthCards(22, [((2, 1), .rayRight), ((4, 1), .straightUp2), ((5, 6), .diagonalUpLeft2)]),
                relicPickups: [growthRelic(22, at: (3, 6), kind: .suspiciousLight)],
                rewardMoveCardsAfterClear: [.rayDownLeft, .diagonalDownLeft2, .knightUpwardChoice],
                rewardSupportCardsAfterClear: [.singleAnnihilationSpell]
            ),
            makeGrowthTowerDeepFloor(
                number: 23,
                title: "転移待ち",
                turnLimit: 15,
                enemies: [
                    growthPatrol("growth-23-patrol", [(2, 5), (3, 5), (4, 5), (5, 5), (4, 5), (3, 5), (2, 5), (3, 5)]),
                    growthRotatingWatcher("growth-23-rotating", position: (6, 2), direction: (-1, 0), rotation: .counterclockwise, range: 3)
                ],
                hazards: [.brittleFloor(points: gridSet([(3, 2), (5, 2)]))],
                impassableTilePoints: fallSecret24.chamberWallPoints,
                tileEffectOverrides: gridEffects([((8, 7), .returnWarp(destination: GridPoint(x: 5, y: 4)))]),
                warpTilePairs: [
                    "growth-23-risk": gridPoints([(1, 5), (7, 2)]),
                    "growth-23-safe": gridPoints([(2, 1), (4, 6)])
                ],
                cardPickups: growthCards(23, [((1, 4), .straightUp2), ((3, 1), .rayUp), ((6, 4), .straightLeft2)]),
                relicPickups: [fallSecret24.treasurePickup],
                fallSecrets: [fallSecret24],
                exitPoint: GridPoint(x: 8, y: 4),
                rewardMoveCardsAfterClear: [.rayLeft, .diagonalUpLeft2, .knightLeftwardChoice],
                rewardSupportCardsAfterClear: [.railBreakSpell]
            ),
            makeGrowthTowerDeepFloor(
                number: 24,
                title: "鍵の遠回り",
                turnLimit: 17,
                enemies: [
                    growthChaser("growth-24-chaser", position: (6, 6)),
                    growthWatcher("growth-24-watcher", position: (5, 2), direction: (0, 1), range: 4)
                ],
                hazards: [
                    .lavaTile(points: gridSet([(4, 4)]), damage: 1),
                    .healingTile(points: gridSet([(2, 5)]), amount: 1),
                    .brittleFloor(points: gridSet([(8, 8)]), initialState: .collapsed)
                ],
                impassableTilePoints: gridSet([(3, 3), (5, 5), (7, 1)]),
                tileEffectOverrides: gridEffects([((6, 3), .discardRandomHand)]),
                exitLock: DungeonExitLock(unlockPoint: GridPoint(x: 2, y: 6)),
                cardPickups: growthCards(24, [((1, 5), .straightUp2), ((3, 6), .diagonalDownRight2), ((6, 2), .rayLeft)]),
                fallSecrets: [fallSecret24],
                rewardMoveCardsAfterClear: [.rayDown, .straightDown2, .diagonalDownRight2],
                rewardSupportCardsAfterClear: [.barrierSpell]
            ),
            makeGrowthTowerDeepFloor(
                number: 25,
                title: "第三関門・鍵と追跡",
                turnLimit: 16,
                enemies: [
                    growthPatrol("growth-25-patrol", [(3, 4), (4, 4), (5, 4), (6, 4), (5, 4), (4, 4)]),
                    growthWatcher("growth-25-watcher", position: (6, 6), direction: (-1, 0), range: 5),
                    growthChaser("growth-25-chaser", position: (2, 6))
                ],
                hazards: [
                    .damageTrap(points: gridSet([(2, 2), (5, 6)]), damage: 1),
                    .brittleFloor(points: gridSet([(4, 2), (5, 2)]), initialState: .collapsed)
                ],
                impassableTilePoints: gridSet([(2, 5), (4, 7), (7, 3), (7, 6)]),
                warpTilePairs: ["growth-25-chest": gridPoints([(1, 3), (6, 7)])],
                exitLock: DungeonExitLock(unlockPoint: GridPoint(x: 2, y: 1)),
                cardPickups: growthCards(25, [((1, 1), .straightRight2), ((3, 1), .diagonalUpRight2), ((6, 5), .rayUpLeft)]),
                relicPickups: [growthRelic(25, at: (7, 7), kind: .suspiciousDeep)],
                rewardMoveCardsAfterClear: [.rayUpLeft, .knightDownwardChoice, .diagonalDownLeft2],
                rewardSupportCardsAfterClear: [.freezeSpell]
            ),
            makeGrowthTowerDeepFloor(
                number: 26,
                title: "回復を挟む廊下",
                turnLimit: 15,
                enemies: [
                    growthRotatingWatcher("growth-26-rotating", position: (5, 3), direction: (0, 1), rotation: .clockwise, range: 5),
                    growthChaser("growth-26-chaser", position: (7, 5))
                ],
                hazards: [
                    .damageTrap(points: gridSet([(3, 4), (6, 6)]), damage: 1),
                    .healingTile(points: gridSet([(4, 5)]), amount: 1)
                ],
                impassableTilePoints: gridSet([(2, 2), (4, 6), (7, 2)]),
                tileEffectOverrides: gridEffects([((5, 6), .swamp), ((6, 5), .swamp)]),
                cardPickups: growthCards(26, [((2, 1), .rayRight), ((5, 1), .straightUp2), ((6, 4), .diagonalUpLeft2)]),
                rewardMoveCardsAfterClear: [.rayRight, .rayUp, .knightRightwardChoice],
                rewardSupportCardsAfterClear: [.panacea]
            ),
            makeGrowthTowerDeepFloor(
                number: 27,
                title: "巡回の鍵束",
                turnLimit: 16,
                enemies: [
                    growthPatrol("growth-27-patrol-a", [(2, 3), (3, 3), (4, 3), (5, 3), (6, 3), (5, 3), (4, 3), (3, 3)]),
                    growthPatrol("growth-27-patrol-b", [(6, 5), (6, 6), (6, 7), (5, 7), (4, 7), (5, 7), (6, 7), (6, 6)])
                ],
                hazards: [.damageTrap(points: gridSet([(2, 5), (5, 5)]), damage: 1)],
                impassableTilePoints: gridSet([(2, 7), (4, 5), (7, 1)]),
                exitLock: DungeonExitLock(unlockPoint: GridPoint(x: 1, y: 4)),
                cardPickups: growthCards(27, [((1, 3), .straightUp2), ((3, 4), .diagonalUpRight2), ((7, 4), .rayLeft)]),
                relicPickups: [growthRelic(27, at: (5, 6), kind: .safe)],
                rewardMoveCardsAfterClear: [.rayDownRight, .straightRight2, .diagonalUpRight2],
                rewardSupportCardsAfterClear: [.railBreakSpell]
            ),
            makeGrowthTowerDeepFloor(
                number: 28,
                title: "追跡と抜け道",
                turnLimit: 14,
                enemies: [
                    growthChaser("growth-28-chaser-a", position: (5, 6)),
                    growthChaser("growth-28-chaser-b", position: (7, 3)),
                    growthWatcher("growth-28-watcher", position: (4, 2), direction: (1, 0), range: 3)
                ],
                hazards: [
                    .lavaTile(points: gridSet([(3, 5)]), damage: 1),
                    .healingTile(points: gridSet([(2, 3)]), amount: 1)
                ],
                impassableTilePoints: gridSet([(3, 2), (5, 4), (6, 6)]),
                warpTilePairs: ["growth-28-detour": gridPoints([(1, 1), (6, 7)])],
                cardPickups: growthCards(28, [((2, 2), .straightRight2), ((4, 1), .rayUp), ((6, 5), .diagonalDownLeft2)]),
                rewardMoveCardsAfterClear: [.rayLeft, .rayDown, .knightLeftwardChoice],
                rewardSupportCardsAfterClear: [.singleAnnihilationSpell]
            ),
            makeGrowthTowerDeepFloor(
                number: 29,
                title: "宝箱の近道",
                turnLimit: 15,
                enemies: [
                    growthRotatingWatcher("growth-29-rotating", position: (6, 4), direction: (-1, 0), rotation: .clockwise, range: 4),
                    growthPatrol("growth-29-patrol", [(2, 6), (3, 6), (4, 6), (5, 6), (6, 6), (5, 6), (4, 6), (3, 6)])
                ],
                hazards: [
                    .brittleFloor(points: gridSet([(3, 3), (4, 3)]), initialState: .hiddenWeak),
                    .damageTrap(points: gridSet([(5, 2), (6, 3)]), damage: 1)
                ],
                impassableTilePoints: gridSet([(2, 4), (4, 2), (7, 5)]),
                tileEffectOverrides: gridEffects([((5, 5), .discardAllSupportCards)]),
                cardPickups: growthCards(29, [((1, 5), .straightRight2), ((3, 5), .diagonalDownRight2), ((7, 6), .rayLeft)]),
                relicPickups: [growthRelic(29, at: (6, 1), kind: .suspiciousDeep)],
                rewardMoveCardsAfterClear: [.rayUpRight, .rayDownLeft, .knightUpwardChoice],
                rewardSupportCardsAfterClear: [.barrierSpell]
            ),
            makeGrowthTowerDeepFloor(
                number: 30,
                title: "第三関門・総合",
                turnLimit: 16,
                enemies: [
                    growthPatrol("growth-30-patrol", [(3, 4), (4, 4), (5, 4), (6, 4), (7, 4), (6, 4), (5, 4), (4, 4)]),
                    growthRotatingWatcher("growth-30-rotating", position: (6, 6), direction: (-1, 0), rotation: .counterclockwise, range: 5),
                    growthChaser("growth-30-chaser", position: (2, 6))
                ],
                hazards: [
                    .damageTrap(points: gridSet([(2, 2), (3, 5), (6, 5)]), damage: 1),
                    .lavaTile(points: gridSet([(5, 2)]), damage: 1)
                ],
                impassableTilePoints: gridSet([(2, 4), (4, 7), (7, 2), (7, 6)]),
                tileEffectOverrides: gridEffects([((5, 6), .discardAllMoveCards)]),
                warpTilePairs: ["growth-30-risk": gridPoints([(1, 2), (6, 7)])],
                exitLock: DungeonExitLock(unlockPoint: GridPoint(x: 2, y: 1)),
                cardPickups: growthCards(30, [((1, 1), .straightRight2), ((3, 1), .diagonalUpRight2), ((7, 5), .rayLeft)]),
                relicPickups: [growthRelic(30, at: (4, 6), kind: .suspiciousLight)],
                rewardMoveCardsAfterClear: [.rayRight, .rayUpRight, .knightRightwardChoice],
                rewardSupportCardsAfterClear: [.freezeSpell]
            )
        ] + buildGrowthTowerLateDeepFloors()
    }

    private static func buildGrowthTowerLateDeepFloors() -> [DungeonFloorDefinition] {
        let fallSecret36 = growthFallSecret(
            id: "growth-fall-secret-36-to-35",
            sourceFloorNumber: 36,
            entrance: (8, 0),
            landing: (8, 0),
            treasure: (7, 0),
            treasureKind: .suspiciousLight,
            returnWarp: (8, 1),
            returnDestination: (5, 3),
            chamberWalls: [(6, 0), (7, 1), (8, 2)]
        )
        return [
            makeGrowthTowerDeepFloor(number: 31, title: "毒の見取り図", turnLimit: 16, enemies: [growthWatcher("growth-31-watcher", position: (6, 5), direction: (-1, 0), range: 4), growthChaser("growth-31-chaser", position: (5, 2))], hazards: [.damageTrap(points: gridSet([(3, 3)]), damage: 1), .healingTile(points: gridSet([(2, 5)]), amount: 1)], impassableTilePoints: gridSet([(2, 2), (4, 6), (7, 3)]), tileEffectOverrides: gridEffects([((4, 4), .poisonTrap)]), cardPickups: growthCards(31, [((1, 1), .straightRight2), ((3, 1), .rayRight), ((6, 4), .diagonalUpLeft2)]), exitPoint: GridPoint(x: 8, y: 4), rewardMoveCardsAfterClear: [.rayDownRight, .diagonalDownRight2, .knightDownwardChoice], rewardSupportCardsAfterClear: [.panacea, .barrierSpell]),
            makeGrowthTowerDeepFloor(number: 32, title: "足枷の迂回", turnLimit: 17, enemies: [growthPatrol("growth-32-patrol", [(3, 5), (4, 5), (5, 5), (6, 5), (5, 5), (4, 5)]), growthRotatingWatcher("growth-32-rotating", position: (6, 2), direction: (0, 1), rotation: .clockwise, range: 4)], hazards: [.damageTrap(points: gridSet([(2, 3), (5, 3)]), damage: 1)], impassableTilePoints: gridSet([(2, 6), (4, 2), (7, 5)]), tileEffectOverrides: gridEffects([((3, 4), .shackleTrap)]), exitLock: DungeonExitLock(unlockPoint: GridPoint(x: 1, y: 5)), cardPickups: growthCards(32, [((1, 4), .straightUp2), ((3, 6), .diagonalDownRight2), ((6, 4), .rayLeft)]), relicPickups: [growthRelic(32, at: (5, 6), kind: .suspiciousLight)], rewardMoveCardsAfterClear: [.rayUp, .rayLeft, .knightUpwardChoice], rewardSupportCardsAfterClear: [.panacea]),
            makeGrowthTowerDeepFloor(number: 33, title: "幻惑の小部屋", turnLimit: 15, enemies: [growthChaser("growth-33-chaser", position: (6, 6)), growthWatcher("growth-33-watcher", position: (5, 2), direction: (0, 1), range: 4)], hazards: [.healingTile(points: gridSet([(2, 4)]), amount: 1)], impassableTilePoints: gridSet([(3, 3), (5, 5), (7, 2)]), tileEffectOverrides: gridEffects([((4, 4), .illusionTrap), ((6, 4), .swamp)]), warpTilePairs: ["growth-33-safe": gridPoints([(1, 2), (6, 7)])], cardPickups: growthCards(33, [((2, 1), .straightRight2), ((4, 1), .rayUp), ((6, 5), .diagonalDownLeft2)]), rewardMoveCardsAfterClear: [.rayUpLeft, .straightLeft2, .knightLeftwardChoice], rewardSupportCardsAfterClear: [.panacea]),
            makeGrowthTowerDeepFloor(number: 34, title: "暗闇の薬棚", turnLimit: 16, enemies: [growthRotatingWatcher("growth-34-rotating", position: (6, 3), direction: (-1, 0), rotation: .counterclockwise, range: 4), growthChaser("growth-34-chaser", position: (5, 6))], hazards: [.damageTrap(points: gridSet([(2, 2), (6, 5)]), damage: 1), .healingTile(points: gridSet([(3, 5)]), amount: 1)], impassableTilePoints: gridSet([(2, 6), (4, 2), (7, 4)]), tileEffectOverrides: gridEffects([((5, 4), .poisonTrap)]), cardPickups: growthCards(34, [((1, 5), .straightUp2), ((3, 6), .diagonalDownRight2), ((6, 2), .rayLeft)]), rewardMoveCardsAfterClear: [.rayRight, .diagonalUpRight2, .knightRightwardChoice], rewardSupportCardsAfterClear: [.darknessSpell, .panacea], isDarknessEnabled: true),
            makeGrowthTowerDeepFloor(number: 35, title: "第四関門・暗闇巡回", turnLimit: 16, enemies: [growthPatrol("growth-35-patrol", [(2, 4), (3, 4), (4, 4), (5, 4), (6, 4), (7, 4), (6, 4), (5, 4)]), growthMarker("growth-35-marker", position: (6, 6), range: 3), growthChaser("growth-35-chaser", position: (2, 6))], hazards: [.damageTrap(points: gridSet([(3, 2), (5, 6)]), damage: 1), .brittleFloor(points: gridSet([(3, 3), (4, 3)]), initialState: .hiddenWeak)], impassableTilePoints: fallSecret36.chamberWallPoints, tileEffectOverrides: gridEffects([((4, 6), .shackleTrap), ((3, 6), .discardRandomHand), ((8, 1), .returnWarp(destination: GridPoint(x: 5, y: 3)))]), exitLock: DungeonExitLock(unlockPoint: GridPoint(x: 2, y: 1)), cardPickups: growthCards(35, [((1, 1), .straightRight2), ((3, 1), .diagonalUpRight2), ((7, 5), .rayLeft)]), relicPickups: [growthRelic(35, at: (5, 5), kind: .suspiciousDeep), fallSecret36.treasurePickup], fallSecrets: [fallSecret36], rewardMoveCardsAfterClear: [.rayDownLeft, .rayUpRight, .knightDownwardChoice], rewardSupportCardsAfterClear: [.freezeSpell], isDarknessEnabled: true),
            makeGrowthTowerDeepFloor(number: 36, title: "万能薬の遠回り", turnLimit: 15, enemies: [growthPatrol("growth-36-patrol", [(3, 3), (4, 3), (5, 3), (6, 3), (5, 3), (4, 3)]), growthWatcher("growth-36-watcher", position: (6, 6), direction: (-1, 0), range: 5)], hazards: [.lavaTile(points: gridSet([(4, 5)]), damage: 1), .healingTile(points: gridSet([(2, 5)]), amount: 1), .brittleFloor(points: gridSet([(8, 0)]), initialState: .collapsed)], impassableTilePoints: gridSet([(2, 2), (4, 6), (7, 3)]), tileEffectOverrides: gridEffects([((3, 5), .poisonTrap), ((6, 4), .swamp)]), cardPickups: growthCards(36, [((2, 1), .straightRight2), ((4, 1), .rayUp), ((6, 5), .diagonalDownLeft2)]), fallSecrets: [fallSecret36], rewardMoveCardsAfterClear: [.rayLeft, .rayDownLeft, .knightLeftwardChoice], rewardSupportCardsAfterClear: [.panacea, .barrierSpell]),
            makeGrowthTowerDeepFloor(number: 37, title: "見えない巡回路", turnLimit: 16, enemies: [growthPatrol("growth-37-patrol-a", [(2, 4), (3, 4), (4, 4), (5, 4), (5, 5), (4, 5), (3, 5), (2, 5)]), growthPatrol("growth-37-patrol-b", [(2, 4), (3, 4), (4, 4), (5, 4), (5, 5), (4, 5), (3, 5), (2, 5)], position: (5, 5))], hazards: [.damageTrap(points: gridSet([(2, 2), (5, 6)]), damage: 1)], impassableTilePoints: gridSet([(2, 7), (4, 2), (7, 5)]), warpTilePairs: ["growth-37-scout": gridPoints([(1, 3), (6, 7)])], cardPickups: growthCards(37, [((1, 2), .straightUp2), ((3, 6), .diagonalDownRight2), ((7, 4), .rayLeft)]), relicPickups: [growthRelic(37, at: (5, 7), kind: .safe)], rewardMoveCardsAfterClear: [.rayRight, .rayDownRight, .knightRightwardChoice], rewardSupportCardsAfterClear: [.railBreakSpell], isDarknessEnabled: true),
            makeGrowthTowerDeepFloor(number: 38, title: "幻惑と転移", turnLimit: 14, enemies: [growthChaser("growth-38-chaser", position: (7, 5)), growthRotatingWatcher("growth-38-rotating", position: (5, 2), direction: (0, 1), rotation: .clockwise, range: 4)], hazards: [.damageTrap(points: gridSet([(3, 3), (6, 5)]), damage: 1), .healingTile(points: gridSet([(2, 6)]), amount: 1)], impassableTilePoints: gridSet([(2, 4), (4, 6), (7, 2)]), tileEffectOverrides: gridEffects([((4, 4), .illusionTrap), ((5, 5), .shackleTrap)]), warpTilePairs: ["growth-38-risk": gridPoints([(1, 1), (6, 6)])], cardPickups: growthCards(38, [((2, 1), .rayRight), ((4, 1), .straightUp2), ((6, 4), .diagonalUpLeft2)]), rewardMoveCardsAfterClear: [.rayUpLeft, .rayDownRight, .knightUpwardChoice], rewardSupportCardsAfterClear: [.panacea]),
            makeGrowthTowerDeepFloor(number: 39, title: "暗闇の補給線", turnLimit: 15, enemies: [growthMarker("growth-39-marker", position: (6, 6), range: 3), growthWatcher("growth-39-watcher", position: (7, 4), direction: (-1, 0), range: 5), growthChaser("growth-39-chaser", position: (3, 6))], hazards: [.brittleFloor(points: gridSet([(3, 2), (4, 2)]), initialState: .hiddenWeak), .lavaTile(points: gridSet([(5, 5)]), damage: 1)], impassableTilePoints: gridSet([(2, 5), (4, 6), (7, 2)]), tileEffectOverrides: gridEffects([((6, 3), .discardAllSupportCards)]), cardPickups: growthCards(39, [((1, 5), .straightRight2), ((3, 5), .diagonalDownRight2), ((7, 6), .rayLeft)]), relicPickups: [growthRelic(39, at: (6, 1), kind: .suspiciousDeep)], rewardMoveCardsAfterClear: [.rayDown, .rayUpRight, .knightDownwardChoice], rewardSupportCardsAfterClear: [.refillEmptySlots, .barrierSpell], isDarknessEnabled: true),
            makeGrowthTowerDeepFloor(number: 40, title: "第四関門・総合", turnLimit: 16, enemies: [growthPatrol("growth-40-patrol", [(3, 4), (4, 4), (5, 4), (6, 4), (7, 4), (6, 4), (5, 4), (4, 4)]), growthMarker("growth-40-marker", position: (6, 6), range: 4), growthRotatingWatcher("growth-40-rotating", position: (5, 2), direction: (0, 1), rotation: .counterclockwise, range: 5)], hazards: [.damageTrap(points: gridSet([(2, 2), (3, 5), (6, 5)]), damage: 1), .healingTile(points: gridSet([(2, 6)]), amount: 1)], impassableTilePoints: gridSet([(2, 4), (4, 7), (7, 2), (7, 6)]), tileEffectOverrides: gridEffects([((5, 5), .illusionTrap), ((6, 3), .discardAllMoveCards)]), warpTilePairs: ["growth-40-risk": gridPoints([(1, 2), (6, 7)])], exitLock: DungeonExitLock(unlockPoint: GridPoint(x: 2, y: 1)), cardPickups: growthCards(40, [((1, 1), .straightRight2), ((3, 1), .diagonalUpRight2), ((7, 5), .rayLeft)]), relicPickups: [growthRelic(40, at: (4, 6), kind: .suspiciousDeep)], rewardMoveCardsAfterClear: [.rayRight, .rayUpLeft, .knightRightwardChoice], rewardSupportCardsAfterClear: [.freezeSpell, .panacea], isDarknessEnabled: true)
        ] + buildGrowthTowerFinalFloors()
    }

    private static func buildGrowthTowerFinalFloors() -> [DungeonFloorDefinition] {
        let fallSecret46 = growthFallSecret(
            id: "growth-fall-secret-46-to-45",
            sourceFloorNumber: 46,
            entrance: (0, 8),
            landing: (0, 8),
            treasure: (1, 8),
            treasureKind: .suspiciousDeep,
            returnWarp: (0, 7),
            returnDestination: (3, 3),
            chamberWalls: [(0, 6), (1, 7), (2, 8)]
        )
        return [
            makeGrowthTowerDeepFloor(number: 41, title: "踏破への入口", turnLimit: 16, enemies: [growthPatrol("growth-41-patrol", [(2, 3), (3, 3), (4, 3), (5, 3), (6, 3), (7, 3), (6, 3), (5, 3)]), growthRotatingWatcher("growth-41-rotating", position: (6, 6), direction: (-1, 0), rotation: .clockwise, range: 5)], hazards: [.damageTrap(points: gridSet([(3, 5), (6, 5)]), damage: 1), .healingTile(points: gridSet([(2, 5)]), amount: 1)], impassableTilePoints: gridSet([(2, 2), (4, 6), (7, 4)]), warpTilePairs: ["growth-41-build": gridPoints([(1, 2), (6, 7)])], cardPickups: growthCards(41, [((1, 1), .straightRight2), ((3, 1), .rayRight), ((6, 4), .diagonalUpLeft2)]), relicPickups: [growthRelic(41, at: (5, 5), kind: .suspiciousLight)], exitPoint: GridPoint(x: 8, y: 4), rewardMoveCardsAfterClear: [.rayUpRight, .rayDownLeft, .knightRightwardChoice], rewardSupportCardsAfterClear: [.barrierSpell]),
            makeGrowthTowerDeepFloor(number: 42, title: "呪い箱の岐路", turnLimit: 15, enemies: [growthChaser("growth-42-chaser", position: (7, 5)), growthWatcher("growth-42-watcher", position: (5, 2), direction: (0, 1), range: 5), growthStarReader("growth-42-star-reader", position: (6, 6), range: 3)], hazards: [.lavaTile(points: gridSet([(4, 4)]), damage: 1), .hpHalvingTrap(points: gridSet([(2, 3)]))], impassableTilePoints: gridSet([(2, 6), (4, 2), (7, 3)]), tileEffectOverrides: gridEffects([((3, 5), .poisonTrap), ((6, 4), .swamp), ((4, 6), .relicBreakTrap)]), cardPickups: growthCards(42, [((1, 5), .straightUp2), ((3, 6), .diagonalDownRight2), ((6, 2), .rayLeft)]), relicPickups: [growthRelic(42, at: (5, 6), kind: .suspiciousDeep)], rewardMoveCardsAfterClear: [.rayLeft, .rayDownRight, .knightLeftwardChoice], rewardSupportCardsAfterClear: [.panacea, .darknessSpell], isDarknessEnabled: true),
            makeGrowthTowerDeepFloor(number: 43, title: "落下を読む橋", turnLimit: 16, enemies: [growthPatrol("growth-43-patrol", [(2, 5), (3, 5), (4, 5), (5, 5), (6, 5), (5, 5), (4, 5), (3, 5)]), growthRotatingWatcher("growth-43-rotating", position: (6, 2), direction: (0, 1), rotation: .counterclockwise, range: 5)], hazards: [.brittleFloor(points: gridSet([(3, 3), (4, 3), (5, 3)]), initialState: .hiddenWeak), .damageTrap(points: gridSet([(6, 6)]), damage: 1), .hpHalvingTrap(points: gridSet([(5, 6)]))], impassableTilePoints: gridSet([(2, 2), (4, 6), (7, 5)]), warpTilePairs: ["growth-43-fall": gridPoints([(1, 4), (6, 7)])], cardPickups: growthCards(43, [((2, 1), .straightRight2), ((4, 1), .rayUp), ((6, 4), .diagonalUpLeft2)]), rewardMoveCardsAfterClear: [.rayUp, .rayUpLeft, .knightUpwardChoice], rewardSupportCardsAfterClear: [.flySpell]),
            makeGrowthTowerDeepFloor(number: 44, title: "追跡の薬路", turnLimit: 15, enemies: [growthChaser("growth-44-chaser-a", position: (5, 6)), growthChaser("growth-44-chaser-b", position: (7, 3)), growthMarker("growth-44-marker", position: (6, 5), range: 3)], hazards: [.damageTrap(points: gridSet([(3, 2), (5, 5)]), damage: 1), .healingTile(points: gridSet([(2, 4)]), amount: 1)], impassableTilePoints: gridSet([(3, 3), (5, 2), (7, 6)]), tileEffectOverrides: gridEffects([((4, 5), .shackleTrap), ((6, 4), .discardRandomHand)]), exitLock: DungeonExitLock(unlockPoint: GridPoint(x: 2, y: 6)), cardPickups: growthCards(44, [((1, 5), .straightUp2), ((3, 6), .diagonalDownRight2), ((6, 2), .rayLeft)]), rewardMoveCardsAfterClear: [.rayDown, .rayDownLeft, .knightDownwardChoice], rewardSupportCardsAfterClear: [.panacea, .singleAnnihilationSpell]),
            makeGrowthTowerDeepFloor(number: 45, title: "第五関門・呪いと崩落", turnLimit: 16, enemies: [growthPatrol("growth-45-patrol", [(3, 4), (4, 4), (5, 4), (6, 4), (7, 4), (6, 4), (5, 4), (4, 4)]), growthRotatingWatcher("growth-45-rotating", position: (6, 6), direction: (-1, 0), rotation: .clockwise, range: 5), growthMarker("growth-45-marker", position: (3, 5), range: 4)], hazards: [.damageTrap(points: gridSet([(2, 2), (5, 6)]), damage: 1), .hpHalvingTrap(points: gridSet([(6, 1)])), .brittleFloor(points: gridSet([(4, 2), (6, 2)]), initialState: .collapsed)], impassableTilePoints: fallSecret46.chamberWallPoints, tileEffectOverrides: gridEffects([((0, 7), .returnWarp(destination: GridPoint(x: 3, y: 3))), ((5, 5), .illusionTrap), ((6, 3), .discardAllSupportCards)]), warpTilePairs: ["growth-45-risk": gridPoints([(1, 2), (6, 7)])], exitLock: DungeonExitLock(unlockPoint: GridPoint(x: 2, y: 1)), cardPickups: growthCards(45, [((1, 1), .straightRight2), ((3, 1), .diagonalUpRight2), ((7, 5), .rayLeft)]), relicPickups: [growthRelic(45, at: (4, 6), kind: .suspiciousDeep), fallSecret46.treasurePickup], fallSecrets: [fallSecret46], rewardMoveCardsAfterClear: [.rayUpRight, .rayDownRight, .knightRightwardChoice], rewardSupportCardsAfterClear: [.freezeSpell, .railBreakSpell], isDarknessEnabled: true),
            makeGrowthTowerDeepFloor(number: 46, title: "暗闇の総力戦", turnLimit: 15, enemies: [growthWatcher("growth-46-watcher", position: (7, 5), direction: (-1, 0), range: 5), growthStarReader("growth-46-star-reader", position: (6, 6), range: 4), growthChaser("growth-46-chaser", position: (3, 6))], hazards: [.lavaTile(points: gridSet([(5, 4)]), damage: 1), .healingTile(points: gridSet([(2, 5)]), amount: 1), .brittleFloor(points: gridSet([(0, 8)]), initialState: .collapsed)], impassableTilePoints: gridSet([(2, 2), (4, 6), (7, 3)]), tileEffectOverrides: gridEffects([((3, 5), .poisonTrap), ((6, 4), .swamp)]), cardPickups: growthCards(46, [((2, 1), .straightRight2), ((4, 1), .rayUp), ((6, 5), .diagonalDownLeft2)]), fallSecrets: [fallSecret46], rewardMoveCardsAfterClear: [.rayLeft, .rayUpLeft, .knightLeftwardChoice], rewardSupportCardsAfterClear: [.darknessSpell, .panacea], isDarknessEnabled: true),
            makeGrowthTowerDeepFloor(number: 47, title: "巡回の包囲網", turnLimit: 16, enemies: [growthPatrol("growth-47-patrol-a", [(2, 3), (3, 3), (4, 3), (5, 3), (6, 3), (7, 3), (6, 3), (5, 3)]), growthPatrol("growth-47-patrol-b", [(6, 5), (6, 6), (6, 7), (5, 7), (4, 7), (5, 7), (6, 7), (6, 6)]), growthRotatingWatcher("growth-47-rotating", position: (5, 5), direction: (0, -1), rotation: .counterclockwise, range: 4)], hazards: [.damageTrap(points: gridSet([(2, 5), (5, 6)]), damage: 1)], impassableTilePoints: gridSet([(2, 7), (4, 5), (7, 1)]), exitLock: DungeonExitLock(unlockPoint: GridPoint(x: 1, y: 4)), cardPickups: growthCards(47, [((1, 3), .straightUp2), ((3, 4), .diagonalUpRight2), ((7, 4), .rayLeft)]), relicPickups: [growthRelic(47, at: (3, 6), kind: .suspiciousLight)], rewardMoveCardsAfterClear: [.rayRight, .rayDownRight, .knightUpwardChoice], rewardSupportCardsAfterClear: [.railBreakSpell, .barrierSpell]),
            makeGrowthTowerDeepFloor(number: 48, title: "幻惑の最短路", turnLimit: 14, enemies: [growthChaser("growth-48-chaser", position: (7, 5)), growthMarker("growth-48-marker", position: (6, 6), range: 4), growthRotatingWatcher("growth-48-rotating", position: (5, 2), direction: (0, 1), rotation: .clockwise, range: 5)], hazards: [.damageTrap(points: gridSet([(3, 3), (6, 5)]), damage: 1), .healingTile(points: gridSet([(2, 6)]), amount: 1)], impassableTilePoints: gridSet([(2, 4), (4, 6), (7, 2)]), tileEffectOverrides: gridEffects([((4, 4), .illusionTrap), ((5, 5), .shackleTrap), ((6, 3), .discardAllMoveCards), ((2, 5), .relicBreakTrap)]), warpTilePairs: ["growth-48-risk": gridPoints([(1, 1), (6, 7)])], cardPickups: growthCards(48, [((2, 1), .rayRight), ((4, 1), .straightUp2), ((6, 4), .diagonalUpLeft2)]), rewardMoveCardsAfterClear: [.rayUpLeft, .rayDownLeft, .knightDownwardChoice], rewardSupportCardsAfterClear: [.panacea, .freezeSpell], isDarknessEnabled: true),
            makeGrowthTowerDeepFloor(number: 49, title: "踏破前夜", turnLimit: 15, enemies: [growthPatrol("growth-49-patrol", [(2, 5), (3, 5), (4, 5), (5, 5), (6, 5), (7, 5), (6, 5), (5, 5)]), growthWatcher("growth-49-watcher", position: (7, 3), direction: (-1, 0), range: 5), growthStarReader("growth-49-star-reader", position: (6, 6), range: 4)], hazards: [.brittleFloor(points: gridSet([(3, 2), (4, 2), (5, 2)]), initialState: .hiddenWeak), .lavaTile(points: gridSet([(5, 6)]), damage: 1)], impassableTilePoints: gridSet([(2, 4), (4, 6), (7, 1)]), tileEffectOverrides: gridEffects([((6, 4), .discardAllHands)]), cardPickups: growthCards(49, [((1, 4), .straightRight2), ((3, 4), .diagonalDownRight2), ((7, 6), .rayLeft)]), relicPickups: [growthRelic(49, at: (6, 2), kind: .suspiciousDeep)], rewardMoveCardsAfterClear: [.rayRight, .rayUpRight, .knightRightwardChoice], rewardSupportCardsAfterClear: [.refillEmptySlots, .flySpell], isDarknessEnabled: true),
            makeGrowthTowerDeepFloor(number: 50, title: "最上階", turnLimit: 16, enemies: [growthPatrol("growth-50-patrol", [(3, 4), (4, 4), (5, 4), (6, 4), (7, 4), (6, 4), (5, 4), (4, 4)]), growthRotatingWatcher("growth-50-rotating", position: (6, 6), direction: (-1, 0), rotation: .counterclockwise, range: 5), growthMarker("growth-50-marker", position: (2, 6), range: 4), growthChaser("growth-50-chaser", position: (7, 2))], hazards: [.damageTrap(points: gridSet([(2, 2), (3, 5), (6, 5)]), damage: 1), .lavaTile(points: gridSet([(5, 2)]), damage: 1), .healingTile(points: gridSet([(2, 5)]), amount: 1)], impassableTilePoints: gridSet([(2, 4), (4, 7), (7, 3), (7, 6)]), tileEffectOverrides: gridEffects([((5, 5), .illusionTrap), ((6, 3), .discardAllHands), ((3, 3), .relicBreakTrap)]), warpTilePairs: ["growth-50-risk": gridPoints([(1, 2), (6, 7)])], exitLock: DungeonExitLock(unlockPoint: GridPoint(x: 2, y: 1)), cardPickups: growthCards(50, [((1, 1), .straightRight2), ((3, 1), .diagonalUpRight2), ((7, 5), .rayLeft)]), relicPickups: [growthRelic(50, at: (4, 6), kind: .suspiciousDeep)], rewardMoveCardsAfterClear: [], rewardSupportCardsAfterClear: [], isDarknessEnabled: true)
        ]
    }

    private static func makeGrowthTowerDeepFloor(
        number: Int,
        title: String,
        turnLimit: Int,
        enemies: [EnemyDefinition],
        hazards: [HazardDefinition],
        impassableTilePoints: Set<GridPoint>,
        tileEffectOverrides: [GridPoint: TileEffect] = [:],
        warpTilePairs: [String: [GridPoint]] = [:],
        exitLock: DungeonExitLock? = nil,
        cardPickups: [DungeonCardPickupDefinition],
        relicPickups: [DungeonRelicPickupDefinition] = [],
        fallSecrets: [DungeonFallSecretDefinition] = [],
        exitPoint: GridPoint = GridPoint(x: 8, y: 8),
        rewardMoveCardsAfterClear: [MoveCard],
        rewardSupportCardsAfterClear: [SupportCard] = [],
        isDarknessEnabled: Bool = false
    ) -> DungeonFloorDefinition {
        DungeonFloorDefinition(
            id: "growth-\(number)",
            title: title,
            boardSize: standardTowerBoardSize,
            spawnPoint: GridPoint(x: 0, y: 0),
            exitPoint: exitPoint,
            deckPreset: .standardLight,
            failureRule: DungeonFailureRule(initialHP: 3, turnLimit: turnLimit),
            enemies: enemies.map { enemy in
                EnemyDefinition(
                    id: enemy.id,
                    name: enemy.name,
                    position: enemy.position,
                    behavior: enemy.behavior,
                    damage: enemyDamage(forFloorNumber: number)
                )
            },
            hazards: hazards.map { hazardWithFloorDamage($0, floorNumber: number) },
            impassableTilePoints: impassableTilePoints,
            tileEffectOverrides: tileEffectOverrides,
            warpTilePairs: warpTilePairs,
            exitLock: exitLock,
            cardPickups: cardPickups,
            relicPickups: relicPickups,
            fallSecrets: fallSecrets,
            rewardMoveCardsAfterClear: rewardMoveCardsAfterClear,
            rewardSupportCardsAfterClear: rewardSupportCardsAfterClear,
            isDarknessEnabled: isDarknessEnabled
        )
    }

    private static func gridPoint(_ point: (Int, Int)) -> GridPoint {
        GridPoint(x: point.0, y: point.1)
    }

    private static func gridPoints(_ points: [(Int, Int)]) -> [GridPoint] {
        points.map(gridPoint)
    }

    private static func gridSet(_ points: [(Int, Int)]) -> Set<GridPoint> {
        Set(gridPoints(points))
    }

    private static func gridEffects(_ effects: [((Int, Int), TileEffect)]) -> [GridPoint: TileEffect] {
        Dictionary(uniqueKeysWithValues: effects.map { (gridPoint($0.0), $0.1) })
    }

    private static func enemyDamage(forFloorNumber floorNumber: Int) -> Int {
        if floorNumber >= 41 { return 3 }
        if floorNumber >= 21 { return 2 }
        return 1
    }

    private static func hazardWithFloorDamage(
        _ hazard: HazardDefinition,
        floorNumber: Int
    ) -> HazardDefinition {
        switch hazard {
        case .damageTrap(let points, _):
            return .damageTrap(points: points, damage: damageTrapDamage(forFloorNumber: floorNumber))
        case .lavaTile(let points, _):
            return .lavaTile(points: points, damage: lavaTileDamage(forFloorNumber: floorNumber))
        case .brittleFloor, .hpHalvingTrap, .healingTile:
            return hazard
        }
    }

    private static func damageTrapDamage(forFloorNumber floorNumber: Int) -> Int {
        1
    }

    private static func lavaTileDamage(forFloorNumber floorNumber: Int) -> Int {
        2
    }

    private static func growthCards(_ floorNumber: Int, _ cards: [((Int, Int), MoveCard)]) -> [DungeonCardPickupDefinition] {
        cards.enumerated().map { index, entry in
            DungeonCardPickupDefinition(
                id: "growth-\(floorNumber)-pickup-\(index + 1)",
                point: gridPoint(entry.0),
                card: entry.1
            )
        }
    }

    private static func growthRelic(
        _ floorNumber: Int,
        at point: (Int, Int),
        kind: DungeonRelicPickupKind
    ) -> DungeonRelicPickupDefinition {
        DungeonRelicPickupDefinition(
            id: "growth-\(floorNumber)-relic",
            point: gridPoint(point),
            kind: kind
        )
    }

    private static func growthFallSecret(
        id: String,
        sourceFloorNumber: Int,
        entrance: (Int, Int),
        landing: (Int, Int),
        treasure: (Int, Int),
        treasureKind: DungeonRelicPickupKind,
        returnWarp: (Int, Int),
        returnDestination: (Int, Int),
        chamberWalls: [(Int, Int)]
    ) -> DungeonFallSecretDefinition {
        let destinationFloorNumber = sourceFloorNumber - 1
        return DungeonFallSecretDefinition(
            id: id,
            sourceFloorIndex: sourceFloorNumber - 1,
            entrancePoint: gridPoint(entrance),
            destinationFloorIndex: destinationFloorNumber - 1,
            landingPoint: gridPoint(landing),
            treasurePickup: DungeonRelicPickupDefinition(
                id: "\(id)-relic",
                point: gridPoint(treasure),
                kind: treasureKind
            ),
            returnWarpPoint: gridPoint(returnWarp),
            returnDestination: gridPoint(returnDestination),
            chamberWallPoints: reinforcedFallSecretChamberWalls(
                landing: gridPoint(landing),
                treasure: gridPoint(treasure),
                returnWarp: gridPoint(returnWarp),
                baseWalls: gridSet(chamberWalls)
            )
        )
    }

    private static func reinforcedFallSecretChamberWalls(
        landing: GridPoint,
        treasure: GridPoint,
        returnWarp: GridPoint,
        baseWalls: Set<GridPoint>
    ) -> Set<GridPoint> {
        let chamberPoints: Set<GridPoint> = [landing, treasure, returnWarp]
        let approachVectors = Set(
            MoveCard.allCases.flatMap(\.movementVectors)
                + DungeonMovementStyle.orthogonal.basicMoveVectors
                + DungeonMovementStyle.knight.basicMoveVectors
        )
        var walls = baseWalls

        for chamberPoint in chamberPoints {
            for vector in approachVectors {
                let approach = chamberPoint.offset(dx: -vector.dx, dy: -vector.dy)
                guard approach.isInside(boardSize: standardTowerBoardSize),
                      !chamberPoints.contains(approach)
                else { continue }
                walls.insert(approach)
            }
        }

        return walls
    }

    private static func growthPatrol(
        _ id: String,
        _ points: [(Int, Int)],
        position: (Int, Int)? = nil
    ) -> EnemyDefinition {
        let path = gridPoints(points)
        return EnemyDefinition(
            id: id,
            name: "巡回兵",
            position: position.map(gridPoint) ?? path.first ?? GridPoint(x: 4, y: 4),
            behavior: .patrol(path: path)
        )
    }

    private static func growthWatcher(
        _ id: String,
        position: (Int, Int),
        direction: (Int, Int),
        range: Int
    ) -> EnemyDefinition {
        EnemyDefinition(
            id: id,
            name: "見張り",
            position: gridPoint(position),
            behavior: .watcher(direction: MoveVector(dx: direction.0, dy: direction.1), range: range)
        )
    }

    private static func growthRotatingWatcher(
        _ id: String,
        position: (Int, Int),
        direction: (Int, Int),
        rotation: RotatingWatcherDirection,
        range: Int
    ) -> EnemyDefinition {
        EnemyDefinition(
            id: id,
            name: "回転見張り",
            position: gridPoint(position),
            behavior: .rotatingWatcher(
                initialDirection: MoveVector(dx: direction.0, dy: direction.1),
                rotationDirection: rotation,
                range: range
            )
        )
    }

    private static func growthChaser(_ id: String, position: (Int, Int)) -> EnemyDefinition {
        EnemyDefinition(id: id, name: "追跡兵", position: gridPoint(position), behavior: .chaser)
    }

    private static func growthMarker(_ id: String, position: (Int, Int), range: Int) -> EnemyDefinition {
        EnemyDefinition(
            id: id,
            name: "メテオ兵",
            position: gridPoint(position),
            behavior: .marker(directions: [], range: range)
        )
    }

    private static func growthStarReader(_ id: String, position: (Int, Int), range: Int) -> EnemyDefinition {
        EnemyDefinition(
            id: id,
            name: "星詠み兵",
            position: gridPoint(position),
            behavior: .targetedMarker(directions: [], range: range)
        )
    }

    private static func buildGrowthPatrolBaseFloors() -> [DungeonFloorDefinition] {
        [
            DungeonFloorDefinition(
                id: "patrol-1",
                title: "巡回の間",
                boardSize: standardTowerBoardSize,
                spawnPoint: GridPoint(x: 0, y: 0),
                exitPoint: GridPoint(x: 8, y: 8),
                deckPreset: .kingAndKnightBasic,
                failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 19),
                enemies: [
                    EnemyDefinition(
                        id: "patrol-1-guard",
                        name: "巡回兵",
                        position: GridPoint(x: 3, y: 4),
                        behavior: .patrol(path: [
                            GridPoint(x: 3, y: 4),
                            GridPoint(x: 4, y: 4),
                            GridPoint(x: 5, y: 4),
                            GridPoint(x: 6, y: 4),
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
                failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 19),
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
                            GridPoint(x: 8, y: 7),
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
                failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 19),
                enemies: [
                    EnemyDefinition(
                        id: "patrol-3-horizontal",
                        name: "巡回兵A",
                        position: GridPoint(x: 1, y: 4),
                        behavior: .patrol(path: [
                            GridPoint(x: 1, y: 4),
                            GridPoint(x: 2, y: 4),
                            GridPoint(x: 3, y: 4),
                            GridPoint(x: 3, y: 5),
                            GridPoint(x: 3, y: 4),
                            GridPoint(x: 2, y: 4)
                        ])
                    ),
                    EnemyDefinition(
                        id: "patrol-3-vertical",
                        name: "巡回兵B",
                        position: GridPoint(x: 5, y: 2),
                        behavior: .patrol(path: [
                            GridPoint(x: 5, y: 2),
                            GridPoint(x: 5, y: 3),
                            GridPoint(x: 5, y: 4),
                            GridPoint(x: 5, y: 5),
                            GridPoint(x: 5, y: 4),
                            GridPoint(x: 5, y: 3)
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
    }

    private static func buildGrowthKeyBaseFloors() -> [DungeonFloorDefinition] {
        [
            DungeonFloorDefinition(
                id: "key-door-1",
                title: "鍵の小部屋",
                boardSize: standardTowerBoardSize,
                spawnPoint: GridPoint(x: 0, y: 4),
                exitPoint: GridPoint(x: 8, y: 4),
                deckPreset: .kingAndKnightBasic,
                failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 19),
                impassableTilePoints: [
                    GridPoint(x: 4, y: 4)
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
                failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 19),
                impassableTilePoints: [
                    GridPoint(x: 4, y: 4)
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
                failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 19),
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
                exitLock: DungeonExitLock(unlockPoint: GridPoint(x: 2, y: 3)),
                cardPickups: [
                    DungeonCardPickupDefinition(
                        id: "key-door-3-right2",
                        point: GridPoint(x: 3, y: 0),
                        card: .straightRight2
                    ),
                    DungeonCardPickupDefinition(
                        id: "key-door-3-up2",
                        point: GridPoint(x: 2, y: 4),
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
    }

    private static func buildGrowthWarpBaseFloors() -> [DungeonFloorDefinition] {
        [
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
                        point: GridPoint(x: 6, y: 5),
                        card: .straightUp2
                    ),
                    DungeonCardPickupDefinition(
                        id: "warp-1-knight",
                        point: GridPoint(x: 7, y: 6),
                        card: .knightRightwardChoice
                    )
                ],
                rewardMoveCardsAfterClear: [
                    .rayRight,
                    .straightUp2,
                    .rayRight
                ]
            ),
            DungeonFloorDefinition(
                id: "warp-2",
                title: "転移床の間",
                boardSize: standardTowerBoardSize,
                spawnPoint: GridPoint(x: 0, y: 4),
                exitPoint: GridPoint(x: 8, y: 4),
                deckPreset: .standardLight,
                failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 13),
                cardPickups: [
                    DungeonCardPickupDefinition(
                        id: "warp-2-ray-right",
                        point: GridPoint(x: 1, y: 4),
                        card: .rayRight
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
                    .straightRight2,
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
                cardPickups: [
                    DungeonCardPickupDefinition(
                        id: "warp-3-ray-right",
                        point: GridPoint(x: 0, y: 1),
                        card: .rayRight
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
    }

    private static func buildGrowthTrapBaseFloors() -> [DungeonFloorDefinition] {
        [
            DungeonFloorDefinition(
                id: "trap-1",
                title: "見える罠",
                boardSize: standardTowerBoardSize,
                spawnPoint: GridPoint(x: 0, y: 0),
                exitPoint: GridPoint(x: 8, y: 8),
                deckPreset: .kingAndKnightBasic,
                failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 19),
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
                failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 19),
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
                            GridPoint(x: 6, y: 4),
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
                        point: GridPoint(x: 1, y: 2),
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
    }

    private static func buildRoguelikeTower() -> DungeonDefinition {
        let floors = [
            DungeonFloorDefinition(
                id: "rogue-template",
                title: "試練",
                boardSize: standardTowerBoardSize,
                spawnPoint: GridPoint(x: 0, y: 0),
                exitPoint: GridPoint(x: 8, y: 8),
                deckPreset: .standardLight,
                failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 14)
            )
        ]

        return DungeonDefinition(
            id: "rogue-tower",
            title: "試練塔",
            summary: "永続成長を持ち込まず、毎回生成される無限階を拾得カードと報酬ビルドで登るローグライク塔。",
            difficulty: .roguelike,
            floors: floors
        )
    }
}
