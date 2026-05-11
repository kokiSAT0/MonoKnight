import Foundation
import Game
import SharedSupport

enum DungeonGrowthUpgrade: String, Codable, CaseIterable, Identifiable {
    case toolPouch
    case climbingKit
    case deepStartKit
    case routeKit
    case deepSupplyCraft
    case finalPreparation
    case rewardScout
    case cardPreservation
    case widerRewardRead
    case supportScout
    case relicScout
    case rewardUpgradeScout
    case rewardRerollRead
    case supportMastery
    case rewardCompletion
    case footingRead
    case secondStep
    case enemyRead
    case meteorRead
    case lastStand
    case enemyReadPlus
    case fallInsurance
    case dangerForecast
    case finalGuard
    case floorSense
    case rewardSense
    case enemySense
    case pathPreview
    case deepForecast
    case routeForecast
    case retryPreparation
    case sectionRecovery
    case deepCheckpointRead
    case checkpointExpansion
    case comebackRoute
    case finalRecovery
    case shortcutKit
    case refillCharm

    var id: String { rawValue }

    var branch: DungeonGrowthBranch {
        switch self {
        case .toolPouch, .climbingKit, .shortcutKit, .refillCharm, .deepStartKit, .routeKit, .deepSupplyCraft, .finalPreparation:
            return .preparation
        case .rewardScout, .cardPreservation, .widerRewardRead, .supportScout, .relicScout, .rewardUpgradeScout, .rewardRerollRead, .supportMastery, .rewardCompletion:
            return .reward
        case .footingRead, .secondStep, .enemyRead, .meteorRead, .lastStand, .enemyReadPlus, .fallInsurance, .dangerForecast, .finalGuard:
            return .hazard
        case .floorSense, .rewardSense, .enemySense, .pathPreview, .deepForecast, .routeForecast:
            return .scouting
        case .retryPreparation, .sectionRecovery, .deepCheckpointRead, .checkpointExpansion, .comebackRoute, .finalRecovery:
            return .recovery
        }
    }

    var title: String {
        switch self {
        case .toolPouch:
            return "道具袋"
        case .climbingKit:
            return "登り支度"
        case .deepStartKit:
            return "深層支度"
        case .routeKit:
            return "経路支度"
        case .deepSupplyCraft:
            return "深層補給術"
        case .finalPreparation:
            return "踏破支度"
        case .rewardScout:
            return "報酬の目利き"
        case .cardPreservation:
            return "カード温存"
        case .widerRewardRead:
            return "広い見立て"
        case .supportScout:
            return "補助の目利き"
        case .relicScout:
            return "遺物の嗅覚"
        case .rewardUpgradeScout:
            return "強化の目利き"
        case .rewardRerollRead:
            return "不要札読み"
        case .supportMastery:
            return "補助熟達"
        case .rewardCompletion:
            return "報酬完成"
        case .footingRead:
            return "足場読み"
        case .secondStep:
            return "踏み直し"
        case .enemyRead:
            return "警戒読み"
        case .meteorRead:
            return "着弾読み"
        case .lastStand:
            return "踏破の保険"
        case .enemyReadPlus:
            return "警戒重ね"
        case .fallInsurance:
            return "落下受け"
        case .dangerForecast:
            return "危険予報"
        case .finalGuard:
            return "踏破防衛"
        case .floorSense:
            return "床読み"
        case .rewardSense:
            return "報酬予感"
        case .enemySense:
            return "敵影読み"
        case .pathPreview:
            return "経路予見"
        case .deepForecast:
            return "深層予報"
        case .routeForecast:
            return "踏破予報"
        case .retryPreparation:
            return "再挑戦支度"
        case .sectionRecovery:
            return "区間立て直し"
        case .deepCheckpointRead:
            return "深層の旗印"
        case .checkpointExpansion:
            return "旗印拡張"
        case .comebackRoute:
            return "復帰経路"
        case .finalRecovery:
            return "踏破復帰"
        case .shortcutKit:
            return "抜け道支度"
        case .refillCharm:
            return "補給札"
        }
    }

    var summary: String {
        switch self {
        case .toolPouch:
            return "区間開始時に右2を1回分持って始めます"
        case .climbingKit:
            return "区間開始時に右2と上2を各1回分持って始めます"
        case .deepStartKit:
            return "21F以降の区間開始時に防御補助を1回分持って始めます"
        case .routeKit:
            return "31F以降の区間開始時に経路を広げる移動カードを1回分追加します"
        case .deepSupplyCraft:
            return "深層の開始支度に補給と報酬補正を組み合わせます"
        case .finalPreparation:
            return "41F以降の区間開始時に踏破向けカードをまとめて持ちます"
        case .rewardScout:
            return "報酬候補に既存候補を補完するカードを混ぜます"
        case .cardPreservation:
            return "追加した移動報酬カードを3回使えるようにします"
        case .widerRewardRead:
            return "移動報酬候補を最大4択に増やします"
        case .supportScout:
            return "11F以降の報酬候補に補助カードを1枚混ぜます"
        case .relicScout:
            return "21F以降の報酬候補に未所持遺物を混ぜやすくします"
        case .rewardUpgradeScout:
            return "31F以降の報酬候補に強化向きカードを混ぜます"
        case .rewardRerollRead:
            return "35F以降の報酬候補で重複しにくい候補を優先します"
        case .supportMastery:
            return "40F以降の報酬候補に強い補助カードを混ぜます"
        case .rewardCompletion:
            return "50F帯の報酬候補を4択の完成形に近づけます"
        case .footingRead:
            return "区間ごとに最初の罠か床崩落ダメージを無効化します"
        case .secondStep:
            return "区間ごとに2回目まで罠か床崩落ダメージを無効化します"
        case .enemyRead:
            return "区間ごとに最初の敵ダメージを無効化します"
        case .meteorRead:
            return "区間ごとに最初のメテオ着弾ダメージを無効化します"
        case .lastStand:
            return "21F以降の区間で危険回避の保険を1回分増やします"
        case .enemyReadPlus:
            return "31F以降の区間で敵ダメージ無効化回数を増やします"
        case .fallInsurance:
            return "35F以降の区間で床崩落・落下への保険を増やします"
        case .dangerForecast:
            return "索敵と危険回避を組み合わせ、危険保険をさらに増やします"
        case .finalGuard:
            return "50F帯の踏破向けに各種ダメージ保険を完成させます"
        case .floorSense:
            return "次の階層帯の床ギミック傾向を読みやすくします"
        case .rewardSense:
            return "次の階層帯の報酬傾向を読みやすくします"
        case .enemySense:
            return "次の階層帯の敵傾向を読みやすくします"
        case .pathPreview:
            return "35F以降で安全経路を組み立てるための予見を得ます"
        case .deepForecast:
            return "40F以降の深層傾向をまとめて読みやすくします"
        case .routeForecast:
            return "50F帯の危険と報酬の見通しを完成させます"
        case .retryPreparation:
            return "21F以降の区間再挑戦に向けた支度を整えます"
        case .sectionRecovery:
            return "31F以降の区間開始時に立て直し用補助を持ちます"
        case .deepCheckpointRead:
            return "深層チェックポイント解放に備える復帰系スキルです"
        case .checkpointExpansion:
            return "将来の21F/31F/41F開始解放を扱う土台になります"
        case .comebackRoute:
            return "45F帯の復帰時に経路を作り直しやすくします"
        case .finalRecovery:
            return "50F帯の踏破失敗後に再挑戦しやすくします"
        case .shortcutKit:
            return "区間開始時に右上2を1回分持って始めます"
        case .refillCharm:
            return "区間開始時に補給を1回分持って始めます"
        }
    }

    var cost: Int { 1 }

    var requiredUpgrades: Set<DungeonGrowthUpgrade> {
        switch self {
        case .toolPouch, .rewardScout, .footingRead, .floorSense, .retryPreparation:
            return []
        case .climbingKit:
            return [.toolPouch]
        case .deepStartKit:
            return [.refillCharm]
        case .routeKit:
            return [.deepStartKit, .pathPreview]
        case .deepSupplyCraft:
            return [.deepStartKit, .relicScout]
        case .finalPreparation:
            return [.routeKit, .deepSupplyCraft]
        case .cardPreservation:
            return [.rewardScout]
        case .widerRewardRead:
            return [.cardPreservation]
        case .supportScout:
            return [.widerRewardRead]
        case .relicScout:
            return [.supportScout]
        case .rewardUpgradeScout:
            return [.relicScout]
        case .rewardRerollRead:
            return [.rewardUpgradeScout]
        case .supportMastery:
            return [.supportScout, .sectionRecovery]
        case .rewardCompletion:
            return [.rewardRerollRead, .supportMastery]
        case .secondStep:
            return [.footingRead]
        case .enemyRead:
            return [.footingRead]
        case .meteorRead:
            return [.enemyRead]
        case .lastStand:
            return [.meteorRead]
        case .enemyReadPlus:
            return [.lastStand]
        case .fallInsurance:
            return [.secondStep, .lastStand]
        case .dangerForecast:
            return [.enemySense, .fallInsurance]
        case .finalGuard:
            return [.dangerForecast, .finalRecovery]
        case .rewardSense:
            return [.floorSense]
        case .enemySense:
            return [.floorSense]
        case .pathPreview:
            return [.rewardSense, .enemySense]
        case .deepForecast:
            return [.pathPreview]
        case .routeForecast:
            return [.deepForecast, .dangerForecast]
        case .sectionRecovery:
            return [.retryPreparation]
        case .deepCheckpointRead:
            return [.sectionRecovery]
        case .checkpointExpansion:
            return [.deepCheckpointRead]
        case .comebackRoute:
            return [.checkpointExpansion, .routeKit]
        case .finalRecovery:
            return [.comebackRoute]
        case .shortcutKit:
            return [.climbingKit]
        case .refillCharm:
            return [.shortcutKit]
        }
    }

    var requiredMilestoneFloor: Int? {
        tierFloor
    }

    var tierFloor: Int? {
        switch self {
        case .toolPouch, .rewardScout, .footingRead, .floorSense, .retryPreparation:
            return nil
        case .climbingKit, .cardPreservation, .rewardSense:
            return 10
        case .secondStep, .enemyRead, .widerRewardRead, .shortcutKit, .enemySense, .deepCheckpointRead:
            return 15
        case .meteorRead, .supportScout, .refillCharm, .pathPreview:
            return 20
        case .deepStartKit, .relicScout, .lastStand:
            return 25
        case .rewardUpgradeScout, .enemyReadPlus, .sectionRecovery:
            return 30
        case .routeKit, .rewardRerollRead, .fallInsurance, .deepForecast:
            return 35
        case .supportMastery, .checkpointExpansion:
            return 40
        case .deepSupplyCraft, .dangerForecast, .comebackRoute:
            return 45
        case .finalPreparation, .rewardCompletion, .finalGuard, .routeForecast, .finalRecovery:
            return 50
        }
    }
}

enum DungeonGrowthBranch: String, CaseIterable, Identifiable {
    case preparation
    case reward
    case hazard
    case scouting
    case recovery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preparation:
            return "準備"
        case .reward:
            return "報酬"
        case .hazard:
            return "危険回避"
        case .scouting:
            return "索敵"
        case .recovery:
            return "復帰"
        }
    }
}

struct DungeonGrowthAward: Equatable {
    let dungeonID: String
    let milestoneID: String
    let points: Int

    var milestoneFloorNumber: Int? {
        guard let suffix = milestoneID.split(separator: "-").last,
              suffix.hasSuffix("f")
        else { return nil }
        return Int(suffix.dropLast())
    }
}

struct DungeonGrowthSnapshot: Codable, Equatable {
    var points: Int
    var unlockedUpgrades: Set<DungeonGrowthUpgrade>
    var activeUpgrades: Set<DungeonGrowthUpgrade>
    var rewardedGrowthMilestoneIDs: Set<String>
    var unlockedGrowthCheckpointFloorNumbers: Set<Int>

    init(
        points: Int = 0,
        unlockedUpgrades: Set<DungeonGrowthUpgrade> = [],
        activeUpgrades: Set<DungeonGrowthUpgrade>? = nil,
        rewardedGrowthMilestoneIDs: Set<String> = [],
        unlockedGrowthCheckpointFloorNumbers: Set<Int> = []
    ) {
        self.points = max(points, 0)
        self.unlockedUpgrades = unlockedUpgrades
        self.activeUpgrades = activeUpgrades.map { $0.intersection(unlockedUpgrades) } ?? unlockedUpgrades
        self.rewardedGrowthMilestoneIDs = rewardedGrowthMilestoneIDs
        self.unlockedGrowthCheckpointFloorNumbers = unlockedGrowthCheckpointFloorNumbers
    }

    private enum CodingKeys: String, CodingKey {
        case points
        case unlockedUpgrades
        case activeUpgrades
        case rewardedGrowthMilestoneIDs
        case unlockedGrowthCheckpointFloorNumbers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        points = max(try container.decodeIfPresent(Int.self, forKey: .points) ?? 0, 0)
        unlockedUpgrades = try container.decodeIfPresent(Set<DungeonGrowthUpgrade>.self, forKey: .unlockedUpgrades) ?? []
        activeUpgrades = try container.decodeIfPresent(Set<DungeonGrowthUpgrade>.self, forKey: .activeUpgrades) ?? unlockedUpgrades
        activeUpgrades = activeUpgrades.intersection(unlockedUpgrades)
        rewardedGrowthMilestoneIDs = try container.decodeIfPresent(Set<String>.self, forKey: .rewardedGrowthMilestoneIDs) ?? []
        unlockedGrowthCheckpointFloorNumbers = try container.decodeIfPresent(Set<Int>.self, forKey: .unlockedGrowthCheckpointFloorNumbers) ?? []
    }
}

@MainActor
final class DungeonGrowthStore: ObservableObject {
    private static let storageKey = StorageKey.UserDefaults.dungeonGrowth
    private let userDefaults: UserDefaults

    @Published private(set) var snapshot: DungeonGrowthSnapshot

    var points: Int { snapshot.points }
    var unlockedUpgrades: Set<DungeonGrowthUpgrade> { snapshot.unlockedUpgrades }
    var activeUpgrades: Set<DungeonGrowthUpgrade> { snapshot.activeUpgrades }
    var unlockedGrowthCheckpointFloorNumbers: Set<Int> { snapshot.unlockedGrowthCheckpointFloorNumbers }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.snapshot = Self.loadSnapshot(from: userDefaults)
    }

    func isUnlocked(_ upgrade: DungeonGrowthUpgrade) -> Bool {
        snapshot.unlockedUpgrades.contains(upgrade)
    }

    func isActive(_ upgrade: DungeonGrowthUpgrade) -> Bool {
        isUnlocked(upgrade) && snapshot.activeUpgrades.contains(upgrade)
    }

    func canUnlock(_ upgrade: DungeonGrowthUpgrade) -> Bool {
        guard !isUnlocked(upgrade), snapshot.points >= upgrade.cost else {
            return false
        }
        guard upgrade.requiredUpgrades.isSubset(of: snapshot.unlockedUpgrades) else {
            return false
        }
        guard let requiredMilestoneFloor = upgrade.requiredMilestoneFloor else {
            return true
        }
        return hasRewardedGrowthMilestoneFloor(requiredMilestoneFloor)
    }

    func lockReason(for upgrade: DungeonGrowthUpgrade) -> String? {
        if isUnlocked(upgrade) {
            return nil
        }
        let missingPrerequisites = upgrade.requiredUpgrades
            .filter { !isUnlocked($0) }
            .map(\.title)
        if !missingPrerequisites.isEmpty {
            return "前提: \(missingPrerequisites.joined(separator: "、"))"
        }
        if let requiredMilestoneFloor = upgrade.requiredMilestoneFloor,
           !hasRewardedGrowthMilestoneFloor(requiredMilestoneFloor) {
            return "\(requiredMilestoneFloor)F到達後"
        }
        if snapshot.points < upgrade.cost {
            return "ポイント不足"
        }
        return nil
    }

    @discardableResult
    func unlock(_ upgrade: DungeonGrowthUpgrade) -> Bool {
        guard canUnlock(upgrade) else {
            return false
        }

        snapshot.points -= upgrade.cost
        snapshot.unlockedUpgrades.insert(upgrade)
        snapshot.activeUpgrades.insert(upgrade)
        persist()
        return true
    }

    @discardableResult
    func setActive(_ upgrade: DungeonGrowthUpgrade, isActive: Bool) -> Bool {
        guard isUnlocked(upgrade) else { return false }
        if isActive {
            snapshot.activeUpgrades.insert(upgrade)
        } else {
            snapshot.activeUpgrades.remove(upgrade)
        }
        persist()
        return true
    }

    @discardableResult
    func toggleActive(_ upgrade: DungeonGrowthUpgrade) -> Bool {
        setActive(upgrade, isActive: !isActive(upgrade))
    }

    @discardableResult
    func registerDungeonClear(dungeon: DungeonDefinition, runState: DungeonRunState, hasNextFloor: Bool) -> DungeonGrowthAward? {
        guard dungeon.difficulty == .growth,
              let milestoneID = growthMilestoneID(for: dungeon, clearedFloorIndex: runState.currentFloorIndex)
        else { return nil }

        let floorNumber = runState.currentFloorIndex + 1
        if snapshot.rewardedGrowthMilestoneIDs.contains(milestoneID) {
            guard isRepeatGrowthAwardFloor(floorNumber) else { return nil }
            snapshot.points += 1
            persist()
            debugLog("DungeonGrowthStore: \(milestoneID) 周回報酬として成長ポイント +1")
            return DungeonGrowthAward(dungeonID: dungeon.id, milestoneID: milestoneID, points: 1)
        }

        snapshot.points += 1
        snapshot.rewardedGrowthMilestoneIDs.insert(milestoneID)
        if isRepeatGrowthAwardFloor(floorNumber),
           dungeon.floors.indices.contains(floorNumber) {
            snapshot.unlockedGrowthCheckpointFloorNumbers.insert(floorNumber + 1)
        }
        persist()
        debugLog("DungeonGrowthStore: \(milestoneID) クリア報酬として成長ポイント +1")
        return DungeonGrowthAward(dungeonID: dungeon.id, milestoneID: milestoneID, points: 1)
    }

    func initialHPBonus(for dungeon: DungeonDefinition) -> Int {
        initialHPBonus(for: dungeon, startingFloorIndex: 0)
    }

    func initialHPBonus(for dungeon: DungeonDefinition, startingFloorIndex: Int) -> Int {
        0
    }

    func startingRewardEntries(for dungeon: DungeonDefinition, startingFloorIndex: Int) -> [DungeonInventoryEntry] {
        guard dungeon.difficulty == .growth else { return [] }
        var entries: [DungeonInventoryEntry] = []
        if isActive(.climbingKit) {
            entries.append(DungeonInventoryEntry(card: .straightRight2, rewardUses: 1))
            entries.append(DungeonInventoryEntry(card: .straightUp2, rewardUses: 1))
        } else if isActive(.toolPouch) {
            entries.append(DungeonInventoryEntry(card: .straightRight2, rewardUses: 1))
        }
        if isActive(.shortcutKit) {
            entries.append(DungeonInventoryEntry(card: .diagonalUpRight2, rewardUses: 1))
        }
        if isActive(.refillCharm) {
            entries.append(DungeonInventoryEntry(support: .refillEmptySlots, rewardUses: 1))
        }
        if startingFloorIndex >= 20, isActive(.deepStartKit) {
            entries.append(DungeonInventoryEntry(support: .barrierSpell, rewardUses: 1))
        }
        if startingFloorIndex >= 30, isActive(.routeKit) {
            entries.append(DungeonInventoryEntry(card: .rayRight, rewardUses: 1))
        }
        if startingFloorIndex >= 40, isActive(.deepSupplyCraft) {
            entries.append(DungeonInventoryEntry(support: .refillEmptySlots, rewardUses: 1))
        }
        if startingFloorIndex >= 40, isActive(.finalPreparation) {
            entries.append(DungeonInventoryEntry(card: .rayUp, rewardUses: 1))
            entries.append(DungeonInventoryEntry(support: .freezeSpell, rewardUses: 1))
        }
        if startingFloorIndex >= 30, isActive(.sectionRecovery) {
            entries.append(DungeonInventoryEntry(support: .barrierSpell, rewardUses: 1))
        }
        return entries
    }

    func rewardAddUses(for dungeon: DungeonDefinition) -> Int {
        dungeon.difficulty == .growth && isActive(.cardPreservation) ? 3 : 2
    }

    func rewardOffers(
        for baseOffers: [DungeonRewardOffer],
        dungeon: DungeonDefinition,
        floorIndex: Int,
        seed: UInt64?,
        tuning: DungeonRewardDrawTuning = DungeonRewardDrawTuning(),
        ownedRelics: Set<DungeonRelicID> = [],
        minimumChoiceCount: Int? = nil
    ) -> [DungeonRewardOffer] {
        let choiceCount = min(max(maxRewardChoiceCount(for: dungeon), minimumChoiceCount ?? 0), 4)
        guard dungeon.difficulty == .growth else {
            return Array(baseOffers.prefix(choiceCount))
        }

        var result = Array(baseOffers.prefix(choiceCount))
        if isActive(.rewardScout) {
            let keptCount = result.count >= choiceCount ? max(choiceCount - 1, 0) : result.count
            result = Array(result.prefix(keptCount))
            let excludedPlayables = Set(baseOffers.compactMap(\.playable))
            let excludedRelics = ownedRelics.union(baseOffers.compactMap(\.relic))
            let supplemental = DungeonWeightedRewardPools.drawUniqueOffers(
                from: DungeonWeightedRewardPools.entries(floorIndex: floorIndex, context: .clearReward),
                context: .clearReward,
                count: max(choiceCount - result.count, 1),
                seed: seed ?? UInt64(floorIndex + 1),
                floorIndex: floorIndex,
                salt: 0x5C07,
                tuning: tuning,
                excludingPlayables: excludedPlayables,
                excludingRelics: excludedRelics
            )
            result.append(contentsOf: supplemental)
        }

        if floorIndex >= 10, isActive(.supportScout) {
            let weightedSupportCandidate = DungeonWeightedRewardPools.drawUniqueOffers(
                from: DungeonWeightedRewardPools.entries(floorIndex: floorIndex, context: .clearReward),
                context: .clearReward,
                count: choiceCount,
                seed: seed ?? UInt64(floorIndex + 1),
                floorIndex: floorIndex,
                salt: 0x5119,
                tuning: tuning,
                excludingPlayables: Set(result.compactMap(\.playable)),
                excludingRelics: ownedRelics.union(result.compactMap(\.relic))
            )
            .first { $0.support != nil }
            let fallbackSupportCandidate = [
                DungeonRewardOffer.playable(.support(.refillEmptySlots)),
                .playable(.support(.singleAnnihilationSpell)),
                .playable(.support(.annihilationSpell))
            ].first { !result.contains($0) }
            let supportCandidate = weightedSupportCandidate ?? fallbackSupportCandidate
            if let supportCandidate {
                if result.count >= choiceCount {
                    if let replaceIndex = result.lastIndex(where: { $0.relic == nil }) {
                        result.remove(at: replaceIndex)
                    } else {
                        result.removeLast()
                    }
                }
                result.append(supportCandidate)
            }
        }

        if floorIndex >= 20, isActive(.relicScout),
           let relicCandidate = DungeonRelicID.allCases
            .first(where: { !ownedRelics.contains($0) && !result.contains(.relic($0)) }) {
            appendRewardCandidate(.relic(relicCandidate), to: &result, choiceCount: choiceCount)
        }

        if floorIndex >= 30, isActive(.rewardUpgradeScout) {
            appendRewardCandidate(.playable(.move(.knightRightwardChoice)), to: &result, choiceCount: choiceCount)
        }

        if floorIndex >= 35, isActive(.rewardRerollRead) {
            result = uniqueRewardOffers(result)
        }

        if floorIndex >= 40, isActive(.supportMastery) {
            appendRewardCandidate(.playable(.support(.barrierSpell)), to: &result, choiceCount: choiceCount)
        }

        if floorIndex >= 49, isActive(.rewardCompletion) {
            appendRewardCandidate(.playable(.support(.freezeSpell)), to: &result, choiceCount: max(choiceCount, 4))
        }

        return Array(result.prefix(choiceCount))
    }

    func rewardCards(
        for baseCards: [PlayableCard],
        dungeon: DungeonDefinition,
        floorIndex: Int,
        seed: UInt64?
    ) -> [PlayableCard] {
        rewardOffers(
            for: baseCards.map(DungeonRewardOffer.playable),
            dungeon: dungeon,
            floorIndex: floorIndex,
            seed: seed
        )
        .compactMap(\.playable)
    }

    func rewardMoveCards(for baseCards: [MoveCard], dungeon: DungeonDefinition) -> [MoveCard] {
        let choiceCount = maxRewardChoiceCount(for: dungeon)
        guard dungeon.difficulty == .growth, isActive(.rewardScout) else {
            return Array(baseCards.prefix(choiceCount))
        }

        var result = Array(baseCards.prefix(max(choiceCount - 1, 0)))
        for candidate in boostedRewardCandidates(for: baseCards) where result.count < choiceCount && !result.contains(candidate) {
            result.append(candidate)
        }
        return result
    }

    func rewardSupportCards(for baseCards: [SupportCard], dungeon: DungeonDefinition, floorIndex: Int) -> [SupportCard] {
        guard dungeon.difficulty == .growth,
              floorIndex >= 10,
              isActive(.supportScout)
        else { return baseCards }
        var result = baseCards
        if let supplemental = [SupportCard.refillEmptySlots, .annihilationSpell].first(where: { !result.contains($0) }) {
            result.append(supplemental)
        }
        return result
    }

    func maxRewardChoiceCount(for dungeon: DungeonDefinition) -> Int {
        dungeon.difficulty == .growth && (isActive(.widerRewardRead) || isActive(.rewardCompletion)) ? 4 : 3
    }

    private func boostedRewardCandidates(for baseCards: [MoveCard]) -> [MoveCard] {
        let candidates: [MoveCard]
        if baseCards.contains(.rayRight) {
            candidates = [.diagonalUpRight2, .rayUp, .knightRightwardChoice]
        } else if baseCards.contains(.diagonalUpRight2) {
            candidates = [.rayUp, .rayRight, .knightRightwardChoice]
        } else if baseCards.first == .straightRight2 {
            candidates = [.rayUp, .rayRight, .diagonalUpRight2, .knightRightwardChoice]
        } else {
            candidates = [.rayRight, .diagonalUpRight2, .rayUp, .knightRightwardChoice]
        }

        return candidates.filter { !baseCards.contains($0) }
    }

    func startingHazardDamageMitigations(for dungeon: DungeonDefinition) -> Int {
        guard dungeon.difficulty == .growth else { return 0 }
        var mitigations = 0
        if isActive(.secondStep) {
            mitigations = 2
        } else if isActive(.footingRead) {
            mitigations = 1
        }
        if isActive(.lastStand) {
            mitigations += 1
        }
        if isActive(.fallInsurance) {
            mitigations += 1
        }
        if isActive(.dangerForecast) {
            mitigations += 1
        }
        if isActive(.finalGuard) {
            mitigations += 1
        }
        return mitigations
    }

    func startingEnemyDamageMitigations(for dungeon: DungeonDefinition) -> Int {
        guard dungeon.difficulty == .growth else { return 0 }
        var mitigations = isActive(.enemyRead) ? 1 : 0
        if isActive(.enemyReadPlus) {
            mitigations += 1
        }
        if isActive(.finalGuard) {
            mitigations += 1
        }
        return mitigations
    }

    func startingMarkerDamageMitigations(for dungeon: DungeonDefinition) -> Int {
        guard dungeon.difficulty == .growth else { return 0 }
        var mitigations = isActive(.meteorRead) ? 1 : 0
        if isActive(.dangerForecast) {
            mitigations += 1
        }
        if isActive(.finalGuard) {
            mitigations += 1
        }
        return mitigations
    }

    func hasRewardedGrowthMilestone(_ milestoneID: String) -> Bool {
        snapshot.rewardedGrowthMilestoneIDs.contains(milestoneID)
    }

    func growthMilestoneIDs(for dungeon: DungeonDefinition) -> [String] {
        guard dungeon.difficulty == .growth else { return [] }
        return growthMilestoneFloors(for: dungeon)
            .map { growthMilestoneID(dungeonID: dungeon.id, floorNumber: $0) }
    }

    func growthMilestoneID(for dungeon: DungeonDefinition, clearedFloorIndex: Int) -> String? {
        let floorNumber = clearedFloorIndex + 1
        guard floorNumber % 5 == 0,
              dungeon.floors.indices.contains(clearedFloorIndex)
        else { return nil }
        return growthMilestoneID(dungeonID: dungeon.id, floorNumber: floorNumber)
    }

    func availableGrowthStartFloorNumbers(for dungeon: DungeonDefinition) -> [Int] {
        guard dungeon.difficulty == .growth else { return [1] }
        let unlocked = snapshot.unlockedGrowthCheckpointFloorNumbers
            .filter { $0 > 1 && dungeon.floors.indices.contains($0 - 1) }
            .sorted()
        return [1] + unlocked
    }

    func isGrowthCheckpointStartUnlocked(floorNumber: Int) -> Bool {
        floorNumber == 1 || snapshot.unlockedGrowthCheckpointFloorNumbers.contains(floorNumber)
    }

    func growthMilestoneFloorNumber(for milestoneID: String) -> Int? {
        guard let suffix = milestoneID.split(separator: "-").last,
              suffix.hasSuffix("f"),
              let number = Int(suffix.dropLast())
        else { return nil }
        return number
    }

    private func hasRewardedGrowthMilestoneFloor(_ floorNumber: Int) -> Bool {
        snapshot.rewardedGrowthMilestoneIDs.contains { milestoneID in
            growthMilestoneFloorNumber(for: milestoneID) == floorNumber
        }
    }

    private func growthMilestoneID(dungeonID: String, floorNumber: Int) -> String {
        "\(dungeonID)-\(floorNumber)f"
    }

    private func growthMilestoneFloors(for dungeon: DungeonDefinition) -> [Int] {
        stride(from: 5, through: dungeon.floors.count, by: 5).map { $0 }
    }

    private func isRepeatGrowthAwardFloor(_ floorNumber: Int) -> Bool {
        floorNumber > 0 && floorNumber % 10 == 0
    }

    private func appendRewardCandidate(
        _ candidate: DungeonRewardOffer,
        to result: inout [DungeonRewardOffer],
        choiceCount: Int
    ) {
        guard !result.contains(candidate) else { return }
        if result.count >= choiceCount {
            if let replaceIndex = result.lastIndex(where: { $0.relic == nil }) {
                result.remove(at: replaceIndex)
            } else {
                result.removeLast()
            }
        }
        result.append(candidate)
    }

    private func uniqueRewardOffers(_ offers: [DungeonRewardOffer]) -> [DungeonRewardOffer] {
        var result: [DungeonRewardOffer] = []
        for offer in offers where !result.contains(offer) {
            result.append(offer)
        }
        return result
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(snapshot)
            userDefaults.set(data, forKey: Self.storageKey)
        } catch {
            debugError(error, message: "DungeonGrowthStore: 保存に失敗しました")
        }
    }

    private static func loadSnapshot(from userDefaults: UserDefaults) -> DungeonGrowthSnapshot {
        guard let data = userDefaults.data(forKey: storageKey) else {
            return DungeonGrowthSnapshot()
        }

        do {
            return try JSONDecoder().decode(DungeonGrowthSnapshot.self, from: data)
        } catch {
            debugError(error, message: "DungeonGrowthStore: 読み込みに失敗しました")
            return DungeonGrowthSnapshot()
        }
    }
}

final class DungeonRunResumeStore: ObservableObject {
    private static let storageKey = StorageKey.UserDefaults.dungeonRunResume
    private let userDefaults: UserDefaults

    @Published private(set) var snapshot: DungeonRunResumeSnapshot?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.snapshot = Self.loadSnapshot(from: userDefaults)
    }

    func save(_ snapshot: DungeonRunResumeSnapshot) {
        guard snapshot.version == DungeonRunResumeSnapshot.currentVersion else {
            clear()
            return
        }
        do {
            let data = try JSONEncoder().encode(snapshot)
            userDefaults.set(data, forKey: Self.storageKey)
            self.snapshot = snapshot
        } catch {
            debugError(error, message: "DungeonRunResumeStore: 保存に失敗しました")
        }
    }

    func clear() {
        userDefaults.removeObject(forKey: Self.storageKey)
        snapshot = nil
    }

    private static func loadSnapshot(from userDefaults: UserDefaults) -> DungeonRunResumeSnapshot? {
        guard let data = userDefaults.data(forKey: storageKey) else { return nil }
        do {
            let snapshot = try JSONDecoder().decode(DungeonRunResumeSnapshot.self, from: data)
            guard snapshot.version == DungeonRunResumeSnapshot.currentVersion else { return nil }
            return snapshot
        } catch {
            debugError(error, message: "DungeonRunResumeStore: 読み込みに失敗しました")
            return nil
        }
    }
}

@MainActor
final class RogueTowerRecordStore: ObservableObject {
    private static let storageKey = StorageKey.UserDefaults.rogueTowerRecord
    private let userDefaults: UserDefaults

    @Published private(set) var highestFloorNumber: Int

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.highestFloorNumber = max(userDefaults.integer(forKey: Self.storageKey), 0)
    }

    @discardableResult
    func registerReachedFloor(_ floorNumber: Int, for dungeon: DungeonDefinition) -> Bool {
        guard dungeon.supportsInfiniteFloors else { return false }
        let normalizedFloor = max(floorNumber, 1)
        guard normalizedFloor > highestFloorNumber else { return false }
        highestFloorNumber = normalizedFloor
        userDefaults.set(normalizedFloor, forKey: Self.storageKey)
        return true
    }

    func highestFloorText(for dungeon: DungeonDefinition) -> String? {
        guard dungeon.supportsInfiniteFloors, highestFloorNumber > 0 else { return nil }
        return "最高到達 \(highestFloorNumber)F"
    }
}
