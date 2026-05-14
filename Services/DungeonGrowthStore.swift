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
            return "区間開始前の基本支度に短い移動カードを出します"
        case .climbingKit:
            return "基本支度で縦横どちらの抜け道も選びやすくします"
        case .deepStartKit:
            return "21F以降の支度候補に防御補助を混ぜます"
        case .routeKit:
            return "31F以降の経路支度に長い移動カードを混ぜます"
        case .deepSupplyCraft:
            return "深層の支度候補に補給と報酬補助をまとめます"
        case .finalPreparation:
            return "41F以降の支度候補に踏破向けの強い対策を出します"
        case .rewardScout:
            return "報酬傾向に合う補完カードを候補へ混ぜます"
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
            return "床・罠が多い区間で防御支度を選びやすくします"
        case .secondStep:
            return "床・罠対策の支度を厚くし、踏み直しやすくします"
        case .enemyRead:
            return "敵が濃い区間で障壁支度を選びやすくします"
        case .meteorRead:
            return "メテオが出る区間で凍結支度を選びやすくします"
        case .lastStand:
            return "21F以降の危険区間で対策支度を増やします"
        case .enemyReadPlus:
            return "31F以降の敵対策支度をさらに強めます"
        case .fallInsurance:
            return "35F以降の落下・床割れ区間で復帰支度を出します"
        case .dangerForecast:
            return "索敵した危険に合わせた対策支度を優先します"
        case .finalGuard:
            return "50F帯の支度候補を踏破向けの完成形に近づけます"
        case .floorSense:
            return "次区間の床ギミック傾向を挑戦前に表示します"
        case .rewardSense:
            return "次区間の拾得カード・報酬・宝箱傾向を表示します"
        case .enemySense:
            return "次区間の敵種と危険の方向性を表示します"
        case .pathPreview:
            return "鍵・ワープ・寄り道など経路判断の見通しを表示します"
        case .deepForecast:
            return "31F以降の複合ギミック注意点を追加表示します"
        case .routeForecast:
            return "41F以降の危険・報酬・経路をまとめて表示します"
        case .retryPreparation:
            return "21F以降の再挑戦時に補給支度を優先します"
        case .sectionRecovery:
            return "31F以降の再挑戦で立て直し支度を選びやすくします"
        case .deepCheckpointRead:
            return "21F以降の再挑戦時に障壁支度を出します"
        case .checkpointExpansion:
            return "31F以降の再挑戦時に万能薬支度を出します"
        case .comebackRoute:
            return "41F以降の再挑戦時に経路支度を出します"
        case .finalRecovery:
            return "41F以降の再挑戦時に凍結支度を出します"
        case .shortcutKit:
            return "基本支度に斜めの抜け道を加えます"
        case .refillCharm:
            return "基本支度に補給を加えます"
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

enum DungeonGrowthPreparationChoiceCategory: String, Equatable, Identifiable {
    case basic
    case floor
    case reward
    case enemy
    case path
    case recovery

    var id: String { rawValue }
}

struct DungeonGrowthPreparationChoice: Equatable, Identifiable {
    let id: String
    let title: String
    let summary: String
    let iconSystemName: String
    let category: DungeonGrowthPreparationChoiceCategory
    let entries: [DungeonInventoryEntry]
}

struct DungeonGrowthSnapshot: Codable, Equatable {
    var points: Int
    var unlockedUpgrades: Set<DungeonGrowthUpgrade>
    var activeUpgrades: Set<DungeonGrowthUpgrade>
    var rewardedGrowthMilestoneIDs: Set<String>
    var unlockedGrowthCheckpointFloorNumbers: Set<Int>
    var isKnightMovementStyleUnlocked: Bool

    init(
        points: Int = 0,
        unlockedUpgrades: Set<DungeonGrowthUpgrade> = [],
        activeUpgrades: Set<DungeonGrowthUpgrade>? = nil,
        rewardedGrowthMilestoneIDs: Set<String> = [],
        unlockedGrowthCheckpointFloorNumbers: Set<Int> = [],
        isKnightMovementStyleUnlocked: Bool = false
    ) {
        self.points = max(points, 0)
        self.unlockedUpgrades = unlockedUpgrades
        self.activeUpgrades = activeUpgrades.map { $0.intersection(unlockedUpgrades) } ?? unlockedUpgrades
        self.rewardedGrowthMilestoneIDs = rewardedGrowthMilestoneIDs
        self.unlockedGrowthCheckpointFloorNumbers = unlockedGrowthCheckpointFloorNumbers
        self.isKnightMovementStyleUnlocked = isKnightMovementStyleUnlocked
    }

    private enum CodingKeys: String, CodingKey {
        case points
        case unlockedUpgrades
        case activeUpgrades
        case rewardedGrowthMilestoneIDs
        case unlockedGrowthCheckpointFloorNumbers
        case isKnightMovementStyleUnlocked
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        points = max(try container.decodeIfPresent(Int.self, forKey: .points) ?? 0, 0)
        unlockedUpgrades = try container.decodeIfPresent(Set<DungeonGrowthUpgrade>.self, forKey: .unlockedUpgrades) ?? []
        activeUpgrades = try container.decodeIfPresent(Set<DungeonGrowthUpgrade>.self, forKey: .activeUpgrades) ?? unlockedUpgrades
        activeUpgrades = activeUpgrades.intersection(unlockedUpgrades)
        rewardedGrowthMilestoneIDs = try container.decodeIfPresent(Set<String>.self, forKey: .rewardedGrowthMilestoneIDs) ?? []
        unlockedGrowthCheckpointFloorNumbers = try container.decodeIfPresent(Set<Int>.self, forKey: .unlockedGrowthCheckpointFloorNumbers) ?? []
        isKnightMovementStyleUnlocked = try container.decodeIfPresent(Bool.self, forKey: .isKnightMovementStyleUnlocked) ?? false
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
    var isKnightMovementStyleUnlocked: Bool { snapshot.isKnightMovementStyleUnlocked }

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
        return upgrade.requiredUpgrades.isSubset(of: snapshot.unlockedUpgrades)
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
        let didUnlockKnightMovementStyle = floorNumber == dungeon.floors.count && !snapshot.isKnightMovementStyleUnlocked
        if snapshot.rewardedGrowthMilestoneIDs.contains(milestoneID) {
            guard isRepeatGrowthAwardFloor(floorNumber) || didUnlockKnightMovementStyle else { return nil }
            if didUnlockKnightMovementStyle {
                snapshot.isKnightMovementStyleUnlocked = true
            }
            let points = isRepeatGrowthAwardFloor(floorNumber) ? 1 : 0
            snapshot.points += points
            persist()
            if didUnlockKnightMovementStyle {
                debugLog("DungeonGrowthStore: 跳躍騎士を解放")
            }
            guard points > 0 else { return nil }
            debugLog("DungeonGrowthStore: \(milestoneID) 周回報酬として成長ポイント +1")
            return DungeonGrowthAward(dungeonID: dungeon.id, milestoneID: milestoneID, points: 1)
        }

        snapshot.points += 1
        snapshot.rewardedGrowthMilestoneIDs.insert(milestoneID)
        if didUnlockKnightMovementStyle {
            snapshot.isKnightMovementStyleUnlocked = true
        }
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

    func startingRewardEntries(
        for dungeon: DungeonDefinition,
        startingFloorIndex: Int,
        preparationChoice: DungeonGrowthPreparationChoice? = nil,
        movementStyle: DungeonMovementStyle = .orthogonal
    ) -> [DungeonInventoryEntry] {
        guard dungeon.difficulty == .growth else { return [] }
        var entries: [DungeonInventoryEntry] = []
        if let preparationChoice {
            entries.append(contentsOf: adjustedEntries(preparationChoice.entries, movementStyle: movementStyle))
        } else if isActive(.climbingKit) {
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

    func preparationChoices(
        for dungeon: DungeonDefinition,
        startingFloorIndex: Int,
        isRetry: Bool = false,
        movementStyle: DungeonMovementStyle = .orthogonal
    ) -> [DungeonGrowthPreparationChoice] {
        guard dungeon.difficulty == .growth else { return [] }

        let sectionEndFloorIndex = min(((startingFloorIndex / 10) + 1) * 10, dungeon.floors.count) - 1
        let floors = (startingFloorIndex...max(startingFloorIndex, sectionEndFloorIndex)).compactMap { index in
            dungeon.floors.indices.contains(index) ? dungeon.floors[index] : nil
        }
        let facts = DungeonGrowthPreparationFacts(floors: floors)
        var choices: [DungeonGrowthPreparationChoice] = []

        if let basic = basicPreparationChoice(startingFloorIndex: startingFloorIndex) {
            choices.append(basic)
        }
        if isActive(.floorSense), let floorChoice = floorPreparationChoice(from: facts, startingFloorIndex: startingFloorIndex) {
            choices.append(floorChoice)
        }
        if (isActive(.enemySense) || isActive(.enemyRead) || isActive(.meteorRead)),
           let enemyChoice = enemyPreparationChoice(from: facts, startingFloorIndex: startingFloorIndex) {
            choices.append(enemyChoice)
        }
        if isActive(.pathPreview), let pathChoice = pathPreparationChoice(from: facts, startingFloorIndex: startingFloorIndex) {
            choices.append(pathChoice)
        }
        if isActive(.rewardSense), let rewardChoice = rewardPreparationChoice(from: facts, startingFloorIndex: startingFloorIndex) {
            choices.append(rewardChoice)
        }
        if isRetry, let recoveryChoice = recoveryPreparationChoice(startingFloorIndex: startingFloorIndex) {
            choices.insert(recoveryChoice, at: 0)
        }

        return Array(uniquePreparationChoices(choices).prefix(3)).map {
            adjustedPreparationChoice($0, movementStyle: movementStyle)
        }
    }

    func retryRewardEntries(for dungeon: DungeonDefinition, startingFloorIndex: Int) -> [DungeonInventoryEntry] {
        guard dungeon.difficulty == .growth else { return [] }
        var entries: [DungeonInventoryEntry] = []
        if startingFloorIndex >= 20, isActive(.retryPreparation) {
            entries.append(DungeonInventoryEntry(support: .refillEmptySlots, rewardUses: 1))
        }
        if startingFloorIndex >= 20, isActive(.deepCheckpointRead) {
            entries.append(DungeonInventoryEntry(support: .barrierSpell, rewardUses: 1))
        }
        if startingFloorIndex >= 30, isActive(.checkpointExpansion) {
            entries.append(DungeonInventoryEntry(support: .panacea, rewardUses: 1))
        }
        if startingFloorIndex >= 40, isActive(.comebackRoute) {
            entries.append(DungeonInventoryEntry(card: .rayUpRight, rewardUses: 1))
        }
        if startingFloorIndex >= 40, isActive(.finalRecovery) {
            entries.append(DungeonInventoryEntry(support: .freezeSpell, rewardUses: 1))
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
        minimumChoiceCount: Int? = nil,
        movementStyle: DungeonMovementStyle = .orthogonal
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
                from: DungeonWeightedRewardPools.entries(
                    floorIndex: floorIndex,
                    context: .clearReward,
                    movementStyle: movementStyle
                ),
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
                from: DungeonWeightedRewardPools.entries(
                    floorIndex: floorIndex,
                    context: .clearReward,
                    movementStyle: movementStyle
                ),
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
            let candidate = movementStyle == .knight
                ? MoveCard.knightRightwardChoice.cardForKnightMovementStyle
                : .knightRightwardChoice
            appendRewardCandidate(.playable(.move(candidate)), to: &result, choiceCount: choiceCount)
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

    private func basicPreparationChoice(startingFloorIndex: Int) -> DungeonGrowthPreparationChoice? {
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
        if entries.isEmpty { return nil }
        return DungeonGrowthPreparationChoice(
            id: "basic-\(startingFloorIndex)",
            title: "登り支度",
            summary: "短い移動と補給で区間の初動を安定させる",
            iconSystemName: "bag.fill",
            category: .basic,
            entries: entries
        )
    }

    private func floorPreparationChoice(
        from facts: DungeonGrowthPreparationFacts,
        startingFloorIndex: Int
    ) -> DungeonGrowthPreparationChoice? {
        if facts.hasStatusFloor || facts.hasDarkness {
            return DungeonGrowthPreparationChoice(
                id: "floor-status-\(startingFloorIndex)",
                title: "状態対策",
                summary: "毒・足枷・暗闇を見て万能薬を持ち込む",
                iconSystemName: "cross.case.fill",
                category: .floor,
                entries: [DungeonInventoryEntry(support: .panacea, rewardUses: 1)]
            )
        }
        if facts.hasBrittleOrTrap {
            return DungeonGrowthPreparationChoice(
                id: "floor-guard-\(startingFloorIndex)",
                title: "足場対策",
                summary: "罠や床割れを見て障壁を持ち込む",
                iconSystemName: "shield.lefthalf.filled",
                category: .floor,
                entries: [DungeonInventoryEntry(support: .barrierSpell, rewardUses: 1)]
            )
        }
        return nil
    }

    private func enemyPreparationChoice(
        from facts: DungeonGrowthPreparationFacts,
        startingFloorIndex: Int
    ) -> DungeonGrowthPreparationChoice? {
        guard facts.hasEnemyPressure else { return nil }
        if facts.hasMeteor || facts.hasManyEnemies {
            return DungeonGrowthPreparationChoice(
                id: "enemy-freeze-\(startingFloorIndex)",
                title: "敵影対策",
                summary: "敵やメテオが濃い区間に凍結を持ち込む",
                iconSystemName: "snowflake",
                category: .enemy,
                entries: [DungeonInventoryEntry(support: .freezeSpell, rewardUses: 1)]
            )
        }
        return DungeonGrowthPreparationChoice(
            id: "enemy-barrier-\(startingFloorIndex)",
            title: "警戒対策",
            summary: "見張りや追跡の圧に障壁で備える",
            iconSystemName: "exclamationmark.shield.fill",
            category: .enemy,
            entries: [DungeonInventoryEntry(support: .barrierSpell, rewardUses: 1)]
        )
    }

    private func pathPreparationChoice(
        from facts: DungeonGrowthPreparationFacts,
        startingFloorIndex: Int
    ) -> DungeonGrowthPreparationChoice? {
        guard facts.hasPathBranch else { return nil }
        let card: MoveCard = startingFloorIndex >= 30 ? .rayRight : .diagonalUpRight2
        return DungeonGrowthPreparationChoice(
            id: "path-\(startingFloorIndex)",
            title: "経路支度",
            summary: "鍵・ワープ・寄り道に備えて抜け道を持つ",
            iconSystemName: "point.forward.to.point.capsulepath.fill",
            category: .path,
            entries: [DungeonInventoryEntry(card: card, rewardUses: 1)]
        )
    }

    private func rewardPreparationChoice(
        from facts: DungeonGrowthPreparationFacts,
        startingFloorIndex: Int
    ) -> DungeonGrowthPreparationChoice? {
        guard facts.hasRewardOpportunity else { return nil }
        return DungeonGrowthPreparationChoice(
            id: "reward-\(startingFloorIndex)",
            title: "報酬支度",
            summary: "宝箱や拾得カードに寄るため補給を持ち込む",
            iconSystemName: "gift.fill",
            category: .reward,
            entries: [DungeonInventoryEntry(support: .refillEmptySlots, rewardUses: 1)]
        )
    }

    private func recoveryPreparationChoice(startingFloorIndex: Int) -> DungeonGrowthPreparationChoice? {
        var entries: [DungeonInventoryEntry] = []
        if startingFloorIndex >= 40, isActive(.finalRecovery) {
            entries.append(DungeonInventoryEntry(support: .freezeSpell, rewardUses: 1))
        } else if startingFloorIndex >= 30, isActive(.checkpointExpansion) {
            entries.append(DungeonInventoryEntry(support: .panacea, rewardUses: 1))
        } else if startingFloorIndex >= 20, isActive(.deepCheckpointRead) {
            entries.append(DungeonInventoryEntry(support: .barrierSpell, rewardUses: 1))
        } else if startingFloorIndex >= 20, isActive(.retryPreparation) {
            entries.append(DungeonInventoryEntry(support: .refillEmptySlots, rewardUses: 1))
        }
        guard !entries.isEmpty else { return nil }
        return DungeonGrowthPreparationChoice(
            id: "recovery-\(startingFloorIndex)",
            title: "再挑戦支度",
            summary: "失敗した区間を立て直す補助を優先する",
            iconSystemName: "arrow.clockwise.circle.fill",
            category: .recovery,
            entries: entries
        )
    }

    private func uniquePreparationChoices(_ choices: [DungeonGrowthPreparationChoice]) -> [DungeonGrowthPreparationChoice] {
        var result: [DungeonGrowthPreparationChoice] = []
        for choice in choices where !result.contains(where: { $0.id == choice.id || $0.entries == choice.entries }) {
            result.append(choice)
        }
        return result
    }

    private func adjustedPreparationChoice(
        _ choice: DungeonGrowthPreparationChoice,
        movementStyle: DungeonMovementStyle
    ) -> DungeonGrowthPreparationChoice {
        DungeonGrowthPreparationChoice(
            id: choice.id,
            title: choice.title,
            summary: choice.summary,
            iconSystemName: choice.iconSystemName,
            category: choice.category,
            entries: adjustedEntries(choice.entries, movementStyle: movementStyle)
        )
    }

    private func adjustedEntries(
        _ entries: [DungeonInventoryEntry],
        movementStyle: DungeonMovementStyle
    ) -> [DungeonInventoryEntry] {
        guard movementStyle == .knight else { return entries }
        return entries.map { entry in
            guard let card = entry.moveCard else { return entry }
            return DungeonInventoryEntry(
                card: card.cardForKnightMovementStyle,
                rewardUses: entry.rewardUses,
                pickupUses: entry.pickupUses
            )
        }
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

private struct DungeonGrowthPreparationFacts {
    let hasStatusFloor: Bool
    let hasDarkness: Bool
    let hasBrittleOrTrap: Bool
    let hasEnemyPressure: Bool
    let hasMeteor: Bool
    let hasManyEnemies: Bool
    let hasPathBranch: Bool
    let hasRewardOpportunity: Bool

    init(floors: [DungeonFloorDefinition]) {
        hasStatusFloor = floors.contains { floor in
            floor.tileEffectOverrides.values.contains { effect in
                switch effect {
                case .poisonTrap, .illusionTrap, .shackleTrap, .swamp:
                    return true
                case .warp, .returnWarp, .shuffleHand, .blast, .slow, .preserveCard,
                     .discardRandomHand, .discardAllMoveCards, .discardAllSupportCards, .discardAllHands:
                    return false
                }
            }
        }
        hasDarkness = floors.contains(where: \.isDarknessEnabled)
        hasBrittleOrTrap = floors.contains { floor in
            floor.hazards.contains { hazard in
                switch hazard {
                case .brittleFloor, .damageTrap, .lavaTile:
                    return true
                case .healingTile:
                    return false
                }
            }
        }
        hasEnemyPressure = floors.contains { !$0.enemies.isEmpty }
        hasMeteor = floors.contains { floor in
            floor.enemies.contains { enemy in
                if case .marker = enemy.behavior {
                    return true
                }
                return false
            }
        }
        hasManyEnemies = floors.contains { $0.enemies.count >= 3 }
        hasPathBranch = floors.contains { floor in
            floor.exitLock != nil
                || !floor.warpTilePairs.isEmpty
                || !floor.relicPickups.isEmpty
                || !floor.fallSecrets.isEmpty
        }
        hasRewardOpportunity = floors.contains { floor in
            !floor.cardPickups.isEmpty
                || !floor.rewardMoveCardsAfterClear.isEmpty
                || !floor.rewardSupportCardsAfterClear.isEmpty
                || !floor.relicPickups.isEmpty
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
final class TutorialTowerProgressStore: ObservableObject {
    private static let storageKey = StorageKey.UserDefaults.tutorialTowerProgress
    private let userDefaults: UserDefaults

    @Published private(set) var hasCompletedTutorialTower: Bool {
        didSet { save() }
    }
    @Published private(set) var hasSeenGrowthTowerIntroPrompt: Bool {
        didSet { save() }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let snapshot = Self.loadSnapshot(from: userDefaults)
        hasCompletedTutorialTower = snapshot.hasCompletedTutorialTower
        hasSeenGrowthTowerIntroPrompt = snapshot.hasSeenGrowthTowerIntroPrompt
    }

    func registerTutorialTowerClear(dungeon: DungeonDefinition, runState: DungeonRunState) {
        guard dungeon.id == "tutorial-tower",
              runState.currentFloorIndex == dungeon.floors.count - 1
        else { return }
        hasCompletedTutorialTower = true
    }

    func markGrowthTowerIntroPromptSeen() {
        hasSeenGrowthTowerIntroPrompt = true
    }

    func shouldPresentGrowthTowerIntroPrompt(for dungeon: DungeonDefinition) -> Bool {
        dungeon.id == "growth-tower"
            && !hasCompletedTutorialTower
            && !hasSeenGrowthTowerIntroPrompt
    }

    private func save() {
        let snapshot = TutorialTowerProgressSnapshot(
            hasCompletedTutorialTower: hasCompletedTutorialTower,
            hasSeenGrowthTowerIntroPrompt: hasSeenGrowthTowerIntroPrompt
        )
        do {
            let data = try JSONEncoder().encode(snapshot)
            userDefaults.set(data, forKey: Self.storageKey)
        } catch {
            debugError(error, message: "TutorialTowerProgressStore: 保存に失敗しました")
        }
    }

    private static func loadSnapshot(from userDefaults: UserDefaults) -> TutorialTowerProgressSnapshot {
        guard let data = userDefaults.data(forKey: storageKey) else {
            return TutorialTowerProgressSnapshot()
        }
        do {
            return try JSONDecoder().decode(TutorialTowerProgressSnapshot.self, from: data)
        } catch {
            debugError(error, message: "TutorialTowerProgressStore: 読み込みに失敗しました")
            return TutorialTowerProgressSnapshot()
        }
    }
}

private struct TutorialTowerProgressSnapshot: Codable {
    var hasCompletedTutorialTower = false
    var hasSeenGrowthTowerIntroPrompt = false
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
