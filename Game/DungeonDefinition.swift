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
public enum DungeonRewardSelection: Equatable {
    /// 新しい移動報酬カードを追加する
    case add(MoveCard)
    /// 新しい補助報酬カードを追加する
    case addSupport(SupportCard)
    /// 新しい遺物を追加する
    case addRelic(DungeonRelicID)
    /// 旧互換用: フロア内で拾って未使用分が残っているカードを報酬カードとして持ち越す
    case carryOverPickup(MoveCard)
    /// 既存の持ち越し報酬カードの使用回数を1増やす
    case upgrade(MoveCard)
    /// 既存の持ち越し補助報酬カードの使用回数を1増やす
    case upgradeSupport(SupportCard)
    /// 既存の持ち越し報酬カードをランから外す
    case remove(MoveCard)
    /// 既存の持ち越し補助報酬カードをランから外す
    case removeSupport(SupportCard)
}

/// フロア内に配置する拾得カード
public struct DungeonCardPickupDefinition: Codable, Equatable, Identifiable {
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

/// クリア後に同じ候補枠へ提示する報酬
public enum DungeonRewardOffer: Equatable, Hashable {
    case playable(PlayableCard)
    case relic(DungeonRelicID)

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

    public var displayName: String {
        switch self {
        case .playable(let playable):
            return playable.displayName
        case .relic(let relic):
            return relic.displayName
        }
    }
}

/// 所持枠が満杯のときに床落ちカード取得の解決を待つ状態
public struct PendingDungeonPickupChoice: Codable, Equatable {
    /// 拾おうとしている床落ちカード
    public let pickup: DungeonCardPickupDefinition
    /// 代わりに捨てられる現在の所持カード候補
    public let discardCandidates: [DungeonInventoryEntry]

    public init(pickup: DungeonCardPickupDefinition, discardCandidates: [DungeonInventoryEntry]) {
        self.pickup = pickup
        self.discardCandidates = discardCandidates.filter(\.hasUsesRemaining)
    }
}

/// 塔攻略中だけ有効な遺物の種類
public enum DungeonRelicID: String, Codable, CaseIterable, Equatable, Identifiable {
    case crackedShield
    case heavyCrown
    case glowingHeart
    case oldMap
    case blackFeather
    case chippedHourglass

    public var id: String { rawValue }

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
        }
    }

    public var effectDescription: String {
        switch self {
        case .crackedShield:
            return "次に受けるダメージを1回だけ1軽減する。"
        case .heavyCrown:
            return "新しく得る報酬カードの使用回数が+1される。"
        case .glowingHeart:
            return "取得時にHPが2増える。"
        case .oldMap:
            return "未取得の拾得カードを盤面で見つけやすくする。"
        case .blackFeather:
            return "崩落穴による落下を1回だけ無効化する。"
        case .chippedHourglass:
            return "各フロアの手数上限が+3される。"
        }
    }

    public var drawbackDescription: String {
        switch self {
        case .crackedShield:
            return "取得時にHPが1減る。HPは1未満にならない。"
        case .heavyCrown:
            return "各フロアの手数上限が-2される。"
        case .glowingHeart:
            return "次フロア開始時にHPが1減る。HPは1未満にならない。"
        case .oldMap:
            return "次フロア開始時の手数上限が-1される。"
        case .blackFeather:
            return "落下を無効化した時にHPが1減る。HPは1未満にならない。"
        case .chippedHourglass:
            return "報酬カード強化の増加量は変わらない。"
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
        }
    }

    public var startingUses: Int {
        switch self {
        case .crackedShield, .blackFeather:
            return 1
        case .heavyCrown, .glowingHeart, .oldMap, .chippedHourglass:
            return 0
        }
    }
}

/// ヘルプ内の遺物辞典で表示する 1 件分の情報
public struct DungeonRelicEncyclopediaEntry: Identifiable, Equatable {
    public let relicID: DungeonRelicID

    public var id: String { relicID.id }
    public var displayName: String { relicID.displayName }
    public var effectDescription: String { relicID.effectDescription }
    public var drawbackDescription: String { relicID.drawbackDescription }
    public var symbolName: String { relicID.symbolName }
    public var encyclopediaDiscoveryID: EncyclopediaDiscoveryID { relicID.encyclopediaDiscoveryID }

    public init(relicID: DungeonRelicID) {
        self.relicID = relicID
    }

    public static let allEntries: [DungeonRelicEncyclopediaEntry] = DungeonRelicID.allCases.map {
        DungeonRelicEncyclopediaEntry(relicID: $0)
    }
}

/// 塔攻略中だけ有効な呪い遺物の種類
public enum DungeonCurseID: String, Codable, CaseIterable, Equatable, Identifiable {
    case rustyChain
    case thornMark
    case bloodPact

    public var id: String { rawValue }

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
        }
    }

    public var effectDescription: String {
        switch self {
        case .rustyChain:
            return "各フロアの手数上限が-2される。"
        case .thornMark:
            return "次に受けるダメージが1増える。"
        case .bloodPact:
            return "次に新しく得る報酬カードの使用回数が1減る。"
        }
    }

    public var releaseDescription: String {
        switch self {
        case .rustyChain:
            return "この挑戦中ずっと残る。"
        case .thornMark:
            return "1回発動すると消える。"
        case .bloodPact:
            return "次の報酬カード取得で消える。最低1回は残る。"
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
        }
    }

    public var startingUses: Int {
        switch self {
        case .thornMark, .bloodPact:
            return 1
        case .rustyChain:
            return 0
        }
    }
}

/// ヘルプ内の呪い辞典で表示する 1 件分の情報
public struct DungeonCurseEncyclopediaEntry: Identifiable, Equatable {
    public let curseID: DungeonCurseID

    public var id: String { curseID.id }
    public var displayName: String { curseID.displayName }
    public var effectDescription: String { curseID.effectDescription }
    public var releaseDescription: String { curseID.releaseDescription }
    public var symbolName: String { curseID.symbolName }
    public var encyclopediaDiscoveryID: EncyclopediaDiscoveryID { curseID.encyclopediaDiscoveryID }

    public init(curseID: DungeonCurseID) {
        self.curseID = curseID
    }

    public static let allEntries: [DungeonCurseEncyclopediaEntry] = DungeonCurseID.allCases.map {
        DungeonCurseEncyclopediaEntry(curseID: $0)
    }
}

/// 塔ラン中に所持している遺物
public struct DungeonRelicEntry: Codable, Equatable, Identifiable {
    public let relicID: DungeonRelicID
    public var remainingUses: Int

    public var id: DungeonRelicID { relicID }
    public var displayName: String { relicID.displayName }
    public var effectDescription: String { relicID.effectDescription }
    public var drawbackDescription: String { relicID.drawbackDescription }
    public var symbolName: String { relicID.symbolName }
    public var hasLimitedUses: Bool { relicID.startingUses > 0 }

    public init(relicID: DungeonRelicID, remainingUses: Int? = nil) {
        self.relicID = relicID
        self.remainingUses = max(remainingUses ?? relicID.startingUses, 0)
    }
}

/// 塔ラン中に所持している呪い遺物
public struct DungeonCurseEntry: Codable, Equatable, Identifiable {
    public let curseID: DungeonCurseID
    public var remainingUses: Int

    public var id: DungeonCurseID { curseID }
    public var displayName: String { curseID.displayName }
    public var effectDescription: String { curseID.effectDescription }
    public var releaseDescription: String { curseID.releaseDescription }
    public var symbolName: String { curseID.symbolName }
    public var hasLimitedUses: Bool { curseID.startingUses > 0 }

    public init(curseID: DungeonCurseID, remainingUses: Int? = nil) {
        self.curseID = curseID
        self.remainingUses = max(remainingUses ?? curseID.startingUses, 0)
    }
}

/// 宝箱から発生する結果
public enum DungeonRelicPickupOutcome: Codable, Equatable {
    case relic
    case curse
    case mimic
    case pandora
}

/// 遊び方辞典で扱う塔イベントの分類
public enum DungeonEventEncyclopediaKind: String, CaseIterable, Equatable, Identifiable {
    case safeChest
    case suspiciousLightChest
    case suspiciousDeepChest
    case relicReward
    case curseOutcome
    case mimicOutcome
    case pandoraOutcome
    case floorFall

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
        }
    }

    public var description: String {
        switch self {
        case .safeChest:
            return "踏むと遺物を取得する安全な宝箱です。カード所持枠は使いません。"
        case .suspiciousLightChest:
            return "遺物以外の結果も起きることがある、少し怪しい宝箱です。"
        case .suspiciousDeepChest:
            return "強い遺物も狙えますが、危険な結果の割合も高い宝箱です。"
        case .relicReward:
            return "フロアクリア後の報酬候補に遺物が並ぶことがあります。既に持つ遺物は候補から外れます。"
        case .curseOutcome:
            return "怪しい宝箱から不利な効果を持つ呪いを受けることがあります。"
        case .mimicOutcome:
            return "宝箱がミミック化し、開けた瞬間にダメージを受けます。"
        case .pandoraOutcome:
            return "遺物と呪いを同時に受け取る大きな賭けです。"
        case .floorFall:
            return "崩落穴に落ちると HP を失い、条件を満たす場合は前の階へ落下します。"
        }
    }
}

/// ヘルプ内のイベント辞典で表示する 1 件分の情報
public struct DungeonEventEncyclopediaEntry: Identifiable, Equatable {
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
public enum DungeonRelicPickupKind: String, Codable, Equatable {
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
}

/// フロア内に配置する宝箱。踏むとランダムな遺物を取得する。
public struct DungeonRelicPickupDefinition: Codable, Equatable, Identifiable {
    public let id: String
    public let point: GridPoint
    public let kind: DungeonRelicPickupKind
    public let candidateRelics: [DungeonRelicID]
    public let candidateCurses: [DungeonCurseID]

    public init(
        id: String,
        point: GridPoint,
        kind: DungeonRelicPickupKind = .safe,
        candidateRelics: [DungeonRelicID] = DungeonRelicID.allCases,
        candidateCurses: [DungeonCurseID] = DungeonCurseID.allCases
    ) {
        self.id = id
        self.point = point
        self.kind = kind
        self.candidateRelics = candidateRelics.isEmpty ? DungeonRelicID.allCases : candidateRelics
        self.candidateCurses = candidateCurses.isEmpty ? DungeonCurseID.allCases : candidateCurses
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
            candidateRelics: try container.decodeIfPresent([DungeonRelicID].self, forKey: .candidateRelics) ?? DungeonRelicID.allCases,
            candidateCurses: try container.decodeIfPresent([DungeonCurseID].self, forKey: .candidateCurses) ?? DungeonCurseID.allCases
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
public enum DungeonWeightedRewardPoolItem: Equatable {
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
public struct DungeonWeightedRewardPoolEntry: Equatable {
    public let item: DungeonWeightedRewardPoolItem
    public let weight: Int

    public init(item: DungeonWeightedRewardPoolItem, weight: Int) {
        self.item = item
        self.weight = max(weight, 0)
    }
}

/// 成長塔の排出テーブル種別
public enum DungeonWeightedRewardPoolContext: Equatable {
    case floorPickup
    case clearReward
}

private enum DungeonWeightedRewardPoolCategory: CaseIterable {
    case move
    case support
    case relic
}

public struct DungeonRewardDrawTuning: Equatable {
    public let clearMoveCount: Int?
    public let turnLimit: Int?

    public init(clearMoveCount: Int? = nil, turnLimit: Int? = nil) {
        self.clearMoveCount = clearMoveCount
        self.turnLimit = turnLimit
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
        context: DungeonWeightedRewardPoolContext
    ) -> [DungeonWeightedRewardPoolEntry] {
        switch (band(for: floorIndex), context) {
        case (.floors1To5, .floorPickup):
            return weightedMoves([
                (.straightRight2, 8), (.straightUp2, 8), (.straightLeft2, 5), (.straightDown2, 5),
                (.diagonalUpRight2, 6), (.diagonalUpLeft2, 5), (.diagonalDownRight2, 4), (.diagonalDownLeft2, 4),
                (.rayRight, 3), (.rayUp, 3)
            ]) + weightedSupports([(.refillEmptySlots, 1)])
        case (.floors1To5, .clearReward):
            return weightedMoves([
                (.straightRight2, 9), (.straightUp2, 9), (.diagonalUpRight2, 7),
                (.rayRight, 5), (.rayUp, 4), (.knightRightwardChoice, 3), (.knightUpwardChoice, 3)
            ]) + weightedSupports([(.refillEmptySlots, 1)]) + weightedRelics()
        case (.floors6To10, .floorPickup):
            return weightedMoves([
                (.straightRight2, 8), (.straightUp2, 8), (.straightLeft2, 7), (.straightDown2, 7),
                (.diagonalUpRight2, 7), (.diagonalUpLeft2, 6), (.diagonalDownRight2, 6), (.diagonalDownLeft2, 6),
                (.rayRight, 5), (.rayUp, 5), (.rayLeft, 4), (.rayDown, 4),
                (.knightRightwardChoice, 3), (.knightUpwardChoice, 3), (.knightLeftwardChoice, 2), (.knightDownwardChoice, 2)
            ]) + weightedSupports([(.refillEmptySlots, 2), (.singleAnnihilationSpell, 1)])
        case (.floors6To10, .clearReward):
            return weightedMoves([
                (.rayRight, 7), (.rayUp, 7), (.rayLeft, 5), (.rayDown, 5),
                (.straightRight2, 6), (.straightUp2, 6), (.diagonalUpRight2, 6), (.diagonalDownRight2, 4),
                (.knightRightwardChoice, 5), (.knightUpwardChoice, 4), (.knightLeftwardChoice, 3)
            ]) + weightedSupports([(.refillEmptySlots, 2), (.singleAnnihilationSpell, 1)]) + weightedRelics()
        case (.floors11To15, .floorPickup):
            return weightedMoves([
                (.straightRight2, 7), (.straightUp2, 7), (.straightLeft2, 7), (.straightDown2, 7),
                (.diagonalUpRight2, 7), (.diagonalUpLeft2, 7), (.diagonalDownRight2, 6), (.diagonalDownLeft2, 6),
                (.rayRight, 6), (.rayUp, 6), (.rayLeft, 6), (.rayDown, 6),
                (.rayUpRight, 3), (.rayUpLeft, 3), (.rayDownRight, 3), (.rayDownLeft, 3),
                (.knightRightwardChoice, 4), (.knightUpwardChoice, 4), (.knightLeftwardChoice, 4), (.knightDownwardChoice, 3)
            ]) + weightedSupports([(.refillEmptySlots, 3), (.singleAnnihilationSpell, 2), (.annihilationSpell, 1)])
        case (.floors11To15, .clearReward):
            return weightedMoves([
                (.rayRight, 7), (.rayUp, 7), (.rayLeft, 7), (.rayDown, 7),
                (.rayUpRight, 4), (.rayUpLeft, 4), (.rayDownRight, 3), (.rayDownLeft, 3),
                (.diagonalUpRight2, 5), (.diagonalUpLeft2, 5), (.diagonalDownLeft2, 4),
                (.knightRightwardChoice, 5), (.knightUpwardChoice, 5), (.knightLeftwardChoice, 4)
            ]) + weightedSupports([(.refillEmptySlots, 3), (.singleAnnihilationSpell, 2), (.annihilationSpell, 1)]) + weightedRelics()
        case (.floors16To20, .floorPickup):
            return weightedMoves([
                (.rayRight, 8), (.rayUp, 8), (.rayLeft, 8), (.rayDown, 8),
                (.rayUpRight, 5), (.rayUpLeft, 5), (.rayDownRight, 5), (.rayDownLeft, 5),
                (.knightRightwardChoice, 6), (.knightUpwardChoice, 6), (.knightLeftwardChoice, 5), (.knightDownwardChoice, 5),
                (.straightRight2, 5), (.straightUp2, 5), (.diagonalUpRight2, 5), (.diagonalDownLeft2, 5)
            ]) + weightedSupports([(.refillEmptySlots, 2), (.singleAnnihilationSpell, 3), (.annihilationSpell, 2)])
        case (.floors16To20, .clearReward):
            return weightedMoves([
                (.rayRight, 9), (.rayUp, 9), (.rayLeft, 9), (.rayDown, 8),
                (.rayUpRight, 6), (.rayUpLeft, 6), (.rayDownRight, 5), (.rayDownLeft, 5),
                (.knightRightwardChoice, 7), (.knightUpwardChoice, 7), (.knightLeftwardChoice, 6), (.knightDownwardChoice, 6),
                (.diagonalUpRight2, 4), (.diagonalUpLeft2, 4), (.diagonalDownLeft2, 4)
            ]) + weightedSupports([(.refillEmptySlots, 2), (.singleAnnihilationSpell, 3), (.annihilationSpell, 2)]) + weightedRelics()
        }
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
                case .relic(let relic) where excludedRelics.contains(relic):
                    return nil
                default:
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
        return result
    }

    private enum FloorBand {
        case floors1To5
        case floors6To10
        case floors11To15
        case floors16To20
    }

    private static func band(for floorIndex: Int) -> FloorBand {
        switch floorIndex {
        case 0..<5:
            return .floors1To5
        case 5..<10:
            return .floors6To10
        case 10..<15:
            return .floors11To15
        default:
            return .floors16To20
        }
    }

    private static func weightedMoves(_ cards: [(MoveCard, Int)]) -> [DungeonWeightedRewardPoolEntry] {
        cards.map { DungeonWeightedRewardPoolEntry(item: .move($0.0), weight: $0.1) }
    }

    private static func weightedSupports(_ cards: [(SupportCard, Int)]) -> [DungeonWeightedRewardPoolEntry] {
        cards.map { DungeonWeightedRewardPoolEntry(item: .support($0.0), weight: $0.1) }
    }

    private static func weightedRelics() -> [DungeonWeightedRewardPoolEntry] {
        DungeonRelicID.allCases.map { DungeonWeightedRewardPoolEntry(item: .relic($0), weight: 1) }
    }

    private static func categoryWeights(
        context: DungeonWeightedRewardPoolContext,
        tuning: DungeonRewardDrawTuning
    ) -> DungeonWeightedRewardCategoryWeights {
        switch context {
        case .floorPickup:
            return DungeonWeightedRewardCategoryWeights(move: 90, support: 10, relic: 0)
        case .clearReward:
            guard let moveCount = tuning.clearMoveCount,
                  let turnLimit = tuning.turnLimit,
                  turnLimit > 0
            else {
                return DungeonWeightedRewardCategoryWeights(move: 89, support: 10, relic: 1)
            }
            if moveCount * 2 <= turnLimit {
                return DungeonWeightedRewardCategoryWeights(move: 65, support: 30, relic: 5)
            }
            if moveCount * 10 <= turnLimit * 7 {
                return DungeonWeightedRewardCategoryWeights(move: 77, support: 20, relic: 3)
            }
            return DungeonWeightedRewardCategoryWeights(move: 89, support: 10, relic: 1)
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
    /// フロアごとのひび割れ床状態
    public let crackedFloorPointsByFloor: [Int: Set<GridPoint>]
    /// フロアごとの崩落床状態
    public let collapsedFloorPointsByFloor: [Int: Set<GridPoint>]
    /// 落下で次フロアへ入る場合の着地点
    public let pendingFallLandingPoint: GridPoint?
    /// 成長塔の区間内で罠/床崩落ダメージを無効化できる残り回数
    public let hazardDamageMitigationsRemaining: Int
    /// 成長塔の区間内で敵ダメージを無効化できる残り回数
    public let enemyDamageMitigationsRemaining: Int
    /// 成長塔の区間内でメテオ着弾ダメージを無効化できる残り回数
    public let markerDamageMitigationsRemaining: Int

    public init(
        dungeonID: String,
        currentFloorIndex: Int = 0,
        carriedHP: Int,
        totalMoveCount: Int = 0,
        clearedFloorCount: Int = 0,
        rewardInventoryEntries: [DungeonInventoryEntry] = [],
        relicEntries: [DungeonRelicEntry] = [],
        curseEntries: [DungeonCurseEntry] = [],
        collectedDungeonRelicPickupIDs: Set<String> = [],
        cardVariationSeed: UInt64? = nil,
        crackedFloorPointsByFloor: [Int: Set<GridPoint>] = [:],
        collapsedFloorPointsByFloor: [Int: Set<GridPoint>] = [:],
        pendingFallLandingPoint: GridPoint? = nil,
        hazardDamageMitigationsRemaining: Int = 0,
        enemyDamageMitigationsRemaining: Int = 0,
        markerDamageMitigationsRemaining: Int = 0
    ) {
        self.dungeonID = dungeonID
        self.currentFloorIndex = max(currentFloorIndex, 0)
        self.carriedHP = max(carriedHP, 1)
        self.totalMoveCount = max(totalMoveCount, 0)
        self.clearedFloorCount = max(clearedFloorCount, 0)
        self.rewardInventoryEntries = DungeonRunState.mergedRewardEntries(rewardInventoryEntries)
        self.relicEntries = DungeonRunState.mergedRelicEntries(relicEntries)
        self.curseEntries = DungeonRunState.mergedCurseEntries(curseEntries)
        self.collectedDungeonRelicPickupIDs = collectedDungeonRelicPickupIDs
        self.cardVariationSeed = cardVariationSeed
        self.crackedFloorPointsByFloor = crackedFloorPointsByFloor.filter { !$0.value.isEmpty }
        self.collapsedFloorPointsByFloor = collapsedFloorPointsByFloor.filter { !$0.value.isEmpty }
        self.pendingFallLandingPoint = pendingFallLandingPoint
        self.hazardDamageMitigationsRemaining = max(hazardDamageMitigationsRemaining, 0)
        self.enemyDamageMitigationsRemaining = max(enemyDamageMitigationsRemaining, 0)
        self.markerDamageMitigationsRemaining = max(markerDamageMitigationsRemaining, 0)
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
        currentRelicEntries: [DungeonRelicEntry]? = nil,
        currentCurseEntries: [DungeonCurseEntry]? = nil,
        collectedDungeonRelicPickupIDs: Set<String>? = nil,
        rewardAddUses: Int = 2,
        hazardDamageMitigationsRemaining: Int? = nil,
        enemyDamageMitigationsRemaining: Int? = nil,
        markerDamageMitigationsRemaining: Int? = nil
    ) -> DungeonRunState {
        let sourceEntries = currentInventoryEntries ?? rewardInventoryEntries
        let carriedEntries = sourceEntries.compactMap { $0.carryingAllUsesAsReward() }
        let selection = rewardSelection ?? rewardMoveCard.map { DungeonRewardSelection.add($0) }
        let updatedRewardInventoryEntries = DungeonRunState.applying(
            selection,
            to: carriedEntries,
            sourceEntries: sourceEntries,
            rewardAddUses: rewardAddUses
        )
        let selectedRelicEntries = DungeonRunState.applyingRelicReward(
            selection,
            to: currentRelicEntries ?? relicEntries
        )
        let selectedCurseEntries = DungeonRunState.curseEntriesAfterRewardSelection(
            selection,
            entries: currentCurseEntries ?? curseEntries
        )
        let carriedRelics = DungeonRunState.relicEntriesForNextFloor(selectedRelicEntries)
        let rewardRelicAdjustedHP = DungeonRunState.carryoverHP(
            carryoverHP,
            afterSelectingRelicReward: selection
        )
        let adjustedCarryoverHP = carriedRelics.contains { $0.relicID == .glowingHeart }
            ? max(rewardRelicAdjustedHP - 1, 1)
            : rewardRelicAdjustedHP
        return DungeonRunState(
            dungeonID: dungeonID,
            currentFloorIndex: currentFloorIndex + 1,
            carriedHP: adjustedCarryoverHP,
            totalMoveCount: totalMoveCount + max(currentFloorMoveCount, 0),
            clearedFloorCount: clearedFloorCount + 1,
            rewardInventoryEntries: updatedRewardInventoryEntries.compactMap { $0.carryingRewardUsesOnly() },
            relicEntries: carriedRelics,
            curseEntries: selectedCurseEntries,
            collectedDungeonRelicPickupIDs: self.collectedDungeonRelicPickupIDs.union(collectedDungeonRelicPickupIDs ?? []),
            cardVariationSeed: cardVariationSeed,
            crackedFloorPointsByFloor: crackedFloorPointsByFloor,
            collapsedFloorPointsByFloor: collapsedFloorPointsByFloor,
            hazardDamageMitigationsRemaining: hazardDamageMitigationsRemaining ?? self.hazardDamageMitigationsRemaining,
            enemyDamageMitigationsRemaining: enemyDamageMitigationsRemaining ?? self.enemyDamageMitigationsRemaining,
            markerDamageMitigationsRemaining: markerDamageMitigationsRemaining ?? self.markerDamageMitigationsRemaining
        )
    }

    public func fallenToPreviousFloor(
        carryoverHP: Int,
        currentFloorMoveCount: Int,
        currentInventoryEntries: [DungeonInventoryEntry],
        currentRelicEntries: [DungeonRelicEntry]? = nil,
        currentCurseEntries: [DungeonCurseEntry]? = nil,
        collectedDungeonRelicPickupIDs: Set<String> = [],
        landingPoint: GridPoint,
        currentFloorCrackedPoints: Set<GridPoint>,
        currentFloorCollapsedPoints: Set<GridPoint>,
        hazardDamageMitigationsRemaining: Int? = nil,
        enemyDamageMitigationsRemaining: Int? = nil,
        markerDamageMitigationsRemaining: Int? = nil
    ) -> DungeonRunState {
        let recordedState = recordingFloorState(
            floorIndex: currentFloorIndex,
            cracked: currentFloorCrackedPoints,
            collapsed: currentFloorCollapsedPoints
        )
        return DungeonRunState(
            dungeonID: dungeonID,
            currentFloorIndex: max(currentFloorIndex - 1, 0),
            carriedHP: carryoverHP,
            totalMoveCount: totalMoveCount + max(currentFloorMoveCount, 0),
            clearedFloorCount: clearedFloorCount,
            rewardInventoryEntries: currentInventoryEntries.compactMap { $0.carryingRewardUsesOnly() },
            relicEntries: currentRelicEntries ?? relicEntries,
            curseEntries: currentCurseEntries ?? curseEntries,
            collectedDungeonRelicPickupIDs: self.collectedDungeonRelicPickupIDs.union(collectedDungeonRelicPickupIDs),
            cardVariationSeed: cardVariationSeed,
            crackedFloorPointsByFloor: recordedState.crackedFloorPointsByFloor,
            collapsedFloorPointsByFloor: recordedState.collapsedFloorPointsByFloor,
            pendingFallLandingPoint: landingPoint,
            hazardDamageMitigationsRemaining: hazardDamageMitigationsRemaining ?? self.hazardDamageMitigationsRemaining,
            enemyDamageMitigationsRemaining: enemyDamageMitigationsRemaining ?? self.enemyDamageMitigationsRemaining,
            markerDamageMitigationsRemaining: markerDamageMitigationsRemaining ?? self.markerDamageMitigationsRemaining
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
            relicEntries: relicEntries,
            curseEntries: curseEntries,
            collectedDungeonRelicPickupIDs: collectedDungeonRelicPickupIDs,
            cardVariationSeed: cardVariationSeed,
            crackedFloorPointsByFloor: crackedByFloor,
            collapsedFloorPointsByFloor: collapsedByFloor,
            pendingFallLandingPoint: pendingFallLandingPoint,
            hazardDamageMitigationsRemaining: hazardDamageMitigationsRemaining,
            enemyDamageMitigationsRemaining: enemyDamageMitigationsRemaining,
            markerDamageMitigationsRemaining: markerDamageMitigationsRemaining
        )
    }

    private enum CodingKeys: String, CodingKey {
        case dungeonID
        case currentFloorIndex
        case carriedHP
        case totalMoveCount
        case clearedFloorCount
        case rewardInventoryEntries
        case relicEntries
        case curseEntries
        case collectedDungeonRelicPickupIDs
        case cardVariationSeed
        case crackedFloorPointsByFloor
        case collapsedFloorPointsByFloor
        case pendingFallLandingPoint
        case hazardDamageMitigationsRemaining
        case enemyDamageMitigationsRemaining
        case markerDamageMitigationsRemaining
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            dungeonID: try container.decode(String.self, forKey: .dungeonID),
            currentFloorIndex: try container.decodeIfPresent(Int.self, forKey: .currentFloorIndex) ?? 0,
            carriedHP: try container.decode(Int.self, forKey: .carriedHP),
            totalMoveCount: try container.decodeIfPresent(Int.self, forKey: .totalMoveCount) ?? 0,
            clearedFloorCount: try container.decodeIfPresent(Int.self, forKey: .clearedFloorCount) ?? 0,
            rewardInventoryEntries: try container.decodeIfPresent([DungeonInventoryEntry].self, forKey: .rewardInventoryEntries) ?? [],
            relicEntries: try container.decodeIfPresent([DungeonRelicEntry].self, forKey: .relicEntries) ?? [],
            curseEntries: try container.decodeIfPresent([DungeonCurseEntry].self, forKey: .curseEntries) ?? [],
            collectedDungeonRelicPickupIDs: try container.decodeIfPresent(Set<String>.self, forKey: .collectedDungeonRelicPickupIDs) ?? [],
            cardVariationSeed: try container.decodeIfPresent(UInt64.self, forKey: .cardVariationSeed),
            crackedFloorPointsByFloor: try container.decodeIfPresent([Int: Set<GridPoint>].self, forKey: .crackedFloorPointsByFloor) ?? [:],
            collapsedFloorPointsByFloor: try container.decodeIfPresent([Int: Set<GridPoint>].self, forKey: .collapsedFloorPointsByFloor) ?? [:],
            pendingFallLandingPoint: try container.decodeIfPresent(GridPoint.self, forKey: .pendingFallLandingPoint),
            hazardDamageMitigationsRemaining: try container.decodeIfPresent(Int.self, forKey: .hazardDamageMitigationsRemaining) ?? 0,
            enemyDamageMitigationsRemaining: try container.decodeIfPresent(Int.self, forKey: .enemyDamageMitigationsRemaining) ?? 0,
            markerDamageMitigationsRemaining: try container.decodeIfPresent(Int.self, forKey: .markerDamageMitigationsRemaining) ?? 0
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dungeonID, forKey: .dungeonID)
        try container.encode(currentFloorIndex, forKey: .currentFloorIndex)
        try container.encode(carriedHP, forKey: .carriedHP)
        try container.encode(totalMoveCount, forKey: .totalMoveCount)
        try container.encode(clearedFloorCount, forKey: .clearedFloorCount)
        try container.encode(rewardInventoryEntries, forKey: .rewardInventoryEntries)
        try container.encode(relicEntries, forKey: .relicEntries)
        try container.encode(curseEntries, forKey: .curseEntries)
        try container.encode(collectedDungeonRelicPickupIDs, forKey: .collectedDungeonRelicPickupIDs)
        try container.encodeIfPresent(cardVariationSeed, forKey: .cardVariationSeed)
        try container.encode(crackedFloorPointsByFloor, forKey: .crackedFloorPointsByFloor)
        try container.encode(collapsedFloorPointsByFloor, forKey: .collapsedFloorPointsByFloor)
        try container.encodeIfPresent(pendingFallLandingPoint, forKey: .pendingFallLandingPoint)
        try container.encode(hazardDamageMitigationsRemaining, forKey: .hazardDamageMitigationsRemaining)
        try container.encode(enemyDamageMitigationsRemaining, forKey: .enemyDamageMitigationsRemaining)
        try container.encode(markerDamageMitigationsRemaining, forKey: .markerDamageMitigationsRemaining)
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
        entries.map { entry in
            guard entry.relicID == .glowingHeart else { return entry }
            return entry
        }
    }

    private static func applying(
        _ selection: DungeonRewardSelection?,
        to entries: [DungeonInventoryEntry],
        sourceEntries: [DungeonInventoryEntry],
        rewardAddUses: Int = 2
    ) -> [DungeonInventoryEntry] {
        var result = entries
        switch selection {
        case .add(let card):
            result.append(DungeonInventoryEntry(card: card, rewardUses: max(rewardAddUses, 1), pickupUses: 0))
        case .addSupport(let support):
            result.append(DungeonInventoryEntry(support: support, rewardUses: DungeonRunState.rewardUses(for: support), pickupUses: 0))
        case .addRelic:
            break
        case .carryOverPickup(let card):
            guard sourceEntries.contains(where: { $0.moveCard == card && $0.hasUsesRemaining }) else { break }
            break
        case .upgrade(let card):
            guard let index = result.firstIndex(where: { $0.moveCard == card && $0.hasUsesRemaining }) else { break }
            result[index].rewardUses += 1
        case .upgradeSupport(let support):
            guard let index = result.firstIndex(where: { $0.supportCard == support && $0.hasUsesRemaining }) else { break }
            result[index].rewardUses += 1
        case .remove(let card):
            result.removeAll { $0.moveCard == card }
        case .removeSupport(let support):
            result.removeAll { $0.supportCard == support }
        case .none:
            break
        }
        return result
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
        afterSelectingRelicReward selection: DungeonRewardSelection?
    ) -> Int {
        guard case .addRelic(let relicID) = selection else { return hp }
        switch relicID {
        case .crackedShield:
            return max(hp - 1, 1)
        case .glowingHeart:
            return hp + 2
        case .heavyCrown, .oldMap, .blackFeather, .chippedHourglass:
            return hp
        }
    }

    public static func rewardUses(for support: SupportCard) -> Int {
        switch support {
        case .refillEmptySlots, .singleAnnihilationSpell, .annihilationSpell:
            return 1
        }
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

/// 回転見張りの回転方向
public enum RotatingWatcherDirection: String, Codable, Equatable {
    case clockwise
    case counterclockwise
}

/// 敵の行動パターン
public enum EnemyBehavior: Codable, Equatable {
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

    private enum CodingKeys: String, CodingKey {
        case type
        case path
        case direction
        case initialDirection
        case rotationDirection
        case directions
        case range
    }

    private enum Kind: String, Codable {
        case guardPost
        case patrol
        case watcher
        case rotatingWatcher
        case chaser
        case marker
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

/// 敵ターン中に各敵がどの状態からどの状態へ進んだかを UI へ伝える差分
public struct DungeonEnemyTurnTransition: Equatable, Identifiable {
    public let enemyID: String
    public let name: String
    public let before: EnemyState
    public let after: EnemyState

    public var id: String { enemyID }
    public var didMove: Bool { before.position != after.position }
    public var didRotate: Bool { before.rotationIndex != after.rotationIndex }

    public init(enemyID: String, name: String, before: EnemyState, after: EnemyState) {
        self.enemyID = enemyID
        self.name = name
        self.before = before
        self.after = after
    }
}

/// プレイヤー行動後に発生した敵ターンの可視化用イベント
public struct DungeonEnemyTurnPhase: Equatable, Identifiable {
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

public struct DungeonEnemyTurnEvent: Equatable, Identifiable {
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

/// 床や罠など、敵以外のフロアギミック
public enum HazardDefinition: Codable, Equatable {
    /// 1 回踏むとひび割れ、2 回目以降は崩落穴として落下する床
    case brittleFloor(points: Set<GridPoint>)
    /// 見えている罠床。踏むたびに指定ダメージを受ける
    case damageTrap(points: Set<GridPoint>, damage: Int)
    /// 見えている回復床。1 回踏むと指定量だけ HP が増え、そのフロア中は消費済みになる
    case healingTile(points: Set<GridPoint>, amount: Int)

    private enum CodingKeys: String, CodingKey {
        case type
        case points
        case damage
        case amount
    }

    private enum Kind: String, Codable {
        case brittleFloor
        case damageTrap
        case healingTile
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
        case .brittleFloor(let points):
            try container.encode(Kind.brittleFloor, forKey: .type)
            try container.encode(points, forKey: .points)
        case .damageTrap(let points, let damage):
            try container.encode(Kind.damageTrap, forKey: .type)
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
    public let relicPickups: [DungeonRelicPickupDefinition]
    public let rewardMoveCardsAfterClear: [MoveCard]
    public let rewardSupportCardsAfterClear: [SupportCard]

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
        relicPickups: [DungeonRelicPickupDefinition] = [],
        rewardMoveCardsAfterClear: [MoveCard] = [],
        rewardSupportCardsAfterClear: [SupportCard] = []
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
        self.relicPickups = relicPickups
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
        case relicPickups
        case rewardMoveCardsAfterClear
        case rewardSupportCardsAfterClear
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
            relicPickups: try container.decodeIfPresent([DungeonRelicPickupDefinition].self, forKey: .relicPickups) ?? [],
            rewardMoveCardsAfterClear: try container.decodeIfPresent([MoveCard].self, forKey: .rewardMoveCardsAfterClear) ?? [],
            rewardSupportCardsAfterClear: try container.decodeIfPresent([SupportCard].self, forKey: .rewardSupportCardsAfterClear) ?? []
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
        try container.encode(relicPickups, forKey: .relicPickups)
        try container.encode(rewardMoveCardsAfterClear, forKey: .rewardMoveCardsAfterClear)
        try container.encode(rewardSupportCardsAfterClear, forKey: .rewardSupportCardsAfterClear)
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
                    cardAcquisitionMode: .inventoryOnly,
                    cardPickups: cardPickups,
                    relicPickups: relicPickups
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
            relicPickups: relicPickups,
            rewardMoveCardsAfterClear: rewardMoveCardsAfterClear,
            rewardSupportCardsAfterClear: rewardSupportCardsAfterClear
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
            relicPickups: relicPickups,
            rewardMoveCardsAfterClear: rewardMoveCardsAfterClear,
            rewardSupportCardsAfterClear: rewardSupportCardsAfterClear
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
            relicPickups: relicPickups + additionalRelicPickups,
            rewardMoveCardsAfterClear: rewardMoveCardsAfterClear,
            rewardSupportCardsAfterClear: rewardSupportCardsAfterClear
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
            relicPickups: relicPickups,
            rewardMoveCardsAfterClear: rewardMoveCardsAfterClear,
            rewardSupportCardsAfterClear: rewardSupportCardsAfterClear
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
            relicPickups: relicPickups,
            rewardMoveCardsAfterClear: rewardMoveCardsAfterClear,
            rewardSupportCardsAfterClear: rewardSupportCardsAfterClear
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
            relicPickups: relicPickups,
            rewardMoveCardsAfterClear: rewardMoveCardsAfterClear,
            rewardSupportCardsAfterClear: rewardSupportCardsAfterClear
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
            relicPickups: relicPickups,
            rewardMoveCardsAfterClear: rewardMoveCardsAfterClear,
            rewardSupportCardsAfterClear: rewardSupportCardsAfterClear
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
        floors.indices.contains(floorIndex + 1)
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
        let rewardCards = resolvedRewardCards(
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
            exitLock: floor.exitLock,
            cardPickups: cardPickups,
            relicPickups: floor.relicPickups,
            rewardMoveCardsAfterClear: rewardCards.compactMap(\.move),
            rewardSupportCardsAfterClear: rewardCards.compactMap(\.support)
        )
    }

    private static func resolvedPickups(
        for floor: DungeonFloorDefinition,
        floorIndex: Int,
        seed: UInt64
    ) -> [DungeonCardPickupDefinition] {
        guard !floor.cardPickups.isEmpty else { return [] }
        var cards = drawPlayableCards(
            floorIndex: floorIndex,
            context: .floorPickup,
            count: floor.cardPickups.count,
            seed: seed,
            salt: 0xC4D1
        )
        if cards.count < floor.cardPickups.count {
            cards += floor.cardPickups.dropFirst(cards.count).map(\.playable)
        }

        var randomizer = DungeonCardVariationRandomizer(seed: seed, floorIndex: floorIndex, salt: 0xC4D1)
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
                playable: cards[index],
                uses: basePickup.uses
            )
        }
    }

    private static func resolvedRewardCards(
        for floor: DungeonFloorDefinition,
        floorIndex: Int,
        seed: UInt64
    ) -> [PlayableCard] {
        let rewardCount = floor.rewardMoveCardsAfterClear.count + floor.rewardSupportCardsAfterClear.count
        guard rewardCount > 0 else { return [] }
        let cards = DungeonWeightedRewardPools.drawUniquePlayables(
            from: DungeonWeightedRewardPools.entries(floorIndex: floorIndex, context: .clearReward),
            count: rewardCount,
            seed: seed,
            floorIndex: floorIndex,
            salt: 0xA11D
        )
        if cards.count >= rewardCount {
            return cards
        }
        let fallback = floor.rewardMoveCardsAfterClear.map(PlayableCard.move)
            + floor.rewardSupportCardsAfterClear.map(PlayableCard.support)
        return cards + fallback.filter { !cards.contains($0) }.prefix(rewardCount - cards.count)
    }

    private static func drawPlayableCards(
        floorIndex: Int,
        context: DungeonWeightedRewardPoolContext,
        count: Int,
        seed: UInt64,
        salt: UInt64
    ) -> [PlayableCard] {
        DungeonWeightedRewardPools.drawUniqueOffers(
            from: DungeonWeightedRewardPools.entries(floorIndex: floorIndex, context: context),
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
        blocked.formUnion(floor.relicPickups.map(\.point))
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
        case .healingTile(let points, _):
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
    /// この GameMode で解決済みの宝箱配置
    public var relicPickups: [DungeonRelicPickupDefinition]

    public init(
        difficulty: DungeonDifficulty,
        failureRule: DungeonFailureRule,
        enemies: [EnemyDefinition] = [],
        hazards: [HazardDefinition] = [],
        exitLock: DungeonExitLock? = nil,
        allowsBasicOrthogonalMove: Bool = false,
        cardAcquisitionMode: DungeonCardAcquisitionMode = .deck,
        cardPickups: [DungeonCardPickupDefinition] = [],
        relicPickups: [DungeonRelicPickupDefinition] = []
    ) {
        self.difficulty = difficulty
        self.failureRule = failureRule
        self.enemies = enemies
        self.hazards = hazards
        self.exitLock = exitLock
        self.allowsBasicOrthogonalMove = allowsBasicOrthogonalMove
        self.cardAcquisitionMode = cardAcquisitionMode
        self.cardPickups = cardPickups
        self.relicPickups = relicPickups
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
        case relicPickups
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
        relicPickups = try container.decodeIfPresent([DungeonRelicPickupDefinition].self, forKey: .relicPickups) ?? []
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
        dungeons.first(where: { $0.id == id })
    }

    public func firstFloorMode(
        for dungeon: DungeonDefinition,
        initialHPBonus: Int = 0,
        startingHazardDamageMitigations: Int = 0,
        startingEnemyDamageMitigations: Int = 0,
        startingMarkerDamageMitigations: Int = 0,
        cardVariationSeed: UInt64? = nil
    ) -> GameMode? {
        floorMode(
            for: dungeon,
            floorIndex: 0,
            initialHPBonus: initialHPBonus,
            startingHazardDamageMitigations: startingHazardDamageMitigations,
            startingEnemyDamageMitigations: startingEnemyDamageMitigations,
            startingMarkerDamageMitigations: startingMarkerDamageMitigations,
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
            relicEntries: dungeon.difficulty == .growth ? startingRelicEntries : [],
            cardVariationSeed: resolvedCardVariationSeed,
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
              dungeon.floors.indices.contains(snapshot.floorIndex),
              snapshot.runState.dungeonID == dungeon.id,
              snapshot.runState.currentFloorIndex == snapshot.floorIndex
        else { return nil }

        let floor = dungeon.resolvedFloor(at: snapshot.floorIndex, runState: snapshot.runState)
            ?? dungeon.floors[snapshot.floorIndex]
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
        let floors = [
            DungeonFloorDefinition(
                id: "tutorial-1",
                title: "塔の入口",
                boardSize: tutorialTowerBoardSize,
                spawnPoint: GridPoint(x: 1, y: 0),
                exitPoint: GridPoint(x: 3, y: 4),
                deckPreset: .kingAndKnightBasic,
                failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 9),
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
                failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 11),
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
                failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 9),
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
            relicPickups: floor.relicPickups,
            rewardMoveCardsAfterClear: rewardMoveCardsAfterClear ?? floor.rewardMoveCardsAfterClear,
            rewardSupportCardsAfterClear: floor.rewardSupportCardsAfterClear
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
            relicPickups: floor.relicPickups,
            rewardMoveCardsAfterClear: rewardMoveCardsAfterClear ?? floor.rewardMoveCardsAfterClear,
            rewardSupportCardsAfterClear: floor.rewardSupportCardsAfterClear
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
            title: "鍵の遠回り",
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
            rewardSupportCardsAfterClear: [.annihilationSpell]
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
            hazards: [.damageTrap(points: [GridPoint(x: 1, y: 1), GridPoint(x: 2, y: 2), GridPoint(x: 3, y: 3), GridPoint(x: 6, y: 5)], damage: 1)],
            impassableTilePoints: [
                GridPoint(x: 3, y: 7),
                GridPoint(x: 4, y: 2),
                GridPoint(x: 5, y: 5),
                GridPoint(x: 7, y: 3)
            ],
            tileEffectOverrides: [
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
                EnemyDefinition(id: "growth-19-patrol-a", name: "巡回兵", position: GridPoint(x: 4, y: 4), behavior: .patrol(path: [GridPoint(x: 4, y: 4), GridPoint(x: 5, y: 4), GridPoint(x: 5, y: 5), GridPoint(x: 4, y: 5), GridPoint(x: 3, y: 5), GridPoint(x: 4, y: 5), GridPoint(x: 5, y: 5), GridPoint(x: 5, y: 4)])),
                EnemyDefinition(id: "growth-19-watcher", name: "見張り", position: GridPoint(x: 7, y: 5), behavior: .watcher(direction: MoveVector(dx: -1, dy: 0), range: 5))
            ],
            hazards: [
                .brittleFloor(points: [GridPoint(x: 2, y: 2), GridPoint(x: 3, y: 2)]),
                .damageTrap(points: [GridPoint(x: 5, y: 6), GridPoint(x: 6, y: 7)], damage: 1),
                .healingTile(points: [GridPoint(x: 2, y: 5)], amount: 1)
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
            relicPickups: [
                DungeonRelicPickupDefinition(id: "growth-19-relic", point: GridPoint(x: 6, y: 1), kind: .suspiciousDeep)
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
            warpTilePairs: ["growth-20-risk": [GridPoint(x: 1, y: 2), GridPoint(x: 6, y: 6)]],
            exitLock: DungeonExitLock(unlockPoint: GridPoint(x: 2, y: 1)),
            cardPickups: [
                DungeonCardPickupDefinition(id: "growth-20-right2", point: GridPoint(x: 0, y: 1), card: .straightRight2),
                DungeonCardPickupDefinition(id: "growth-20-key-diagonal", point: GridPoint(x: 2, y: 0), card: .diagonalUpRight2),
                DungeonCardPickupDefinition(id: "growth-20-up2", point: GridPoint(x: 8, y: 6), card: .straightUp2)
            ]
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
                    .straightRight2,
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
                cardPickups: [
                    DungeonCardPickupDefinition(
                        id: "rogue-2-ray-right",
                        point: GridPoint(x: 1, y: 4),
                        card: .rayRight
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
                    .straightRight2,
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
                cardPickups: [
                    DungeonCardPickupDefinition(
                        id: "rogue-3-ray-right",
                        point: GridPoint(x: 0, y: 1),
                        card: .rayRight
                    ),
                    DungeonCardPickupDefinition(
                        id: "rogue-3-diagonal-up-right",
                        point: GridPoint(x: 2, y: 0),
                        card: .diagonalUpRight2
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
