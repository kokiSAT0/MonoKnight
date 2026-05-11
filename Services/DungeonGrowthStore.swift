import Foundation
import Game
import SharedSupport

enum DungeonGrowthUpgrade: String, Codable, CaseIterable, Identifiable {
    case toolPouch
    case climbingKit
    case rewardScout
    case cardPreservation
    case widerRewardRead
    case supportScout
    case footingRead
    case secondStep
    case enemyRead
    case meteorRead
    case shortcutKit
    case refillCharm

    var id: String { rawValue }

    var branch: DungeonGrowthBranch {
        switch self {
        case .toolPouch, .climbingKit, .shortcutKit, .refillCharm:
            return .preparation
        case .rewardScout, .cardPreservation, .widerRewardRead, .supportScout:
            return .reward
        case .footingRead, .secondStep, .enemyRead, .meteorRead:
            return .hazard
        }
    }

    var title: String {
        switch self {
        case .toolPouch:
            return "道具袋"
        case .climbingKit:
            return "登り支度"
        case .rewardScout:
            return "報酬の目利き"
        case .cardPreservation:
            return "カード温存"
        case .widerRewardRead:
            return "広い見立て"
        case .supportScout:
            return "補助の目利き"
        case .footingRead:
            return "足場読み"
        case .secondStep:
            return "踏み直し"
        case .enemyRead:
            return "警戒読み"
        case .meteorRead:
            return "着弾読み"
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
        case .rewardScout:
            return "報酬候補に既存候補を補完するカードを混ぜます"
        case .cardPreservation:
            return "追加した移動報酬カードを3回使えるようにします"
        case .widerRewardRead:
            return "移動報酬候補を最大4択に増やします"
        case .supportScout:
            return "11F以降の報酬候補に補助カードを1枚混ぜます"
        case .footingRead:
            return "区間ごとに最初の罠か床崩落ダメージを無効化します"
        case .secondStep:
            return "区間ごとに2回目まで罠か床崩落ダメージを無効化します"
        case .enemyRead:
            return "区間ごとに最初の敵ダメージを無効化します"
        case .meteorRead:
            return "区間ごとに最初のメテオ着弾ダメージを無効化します"
        case .shortcutKit:
            return "区間開始時に右上2を1回分持って始めます"
        case .refillCharm:
            return "区間開始時に補給を1回分持って始めます"
        }
    }

    var cost: Int { 1 }

    var requiredUpgrades: Set<DungeonGrowthUpgrade> {
        switch self {
        case .toolPouch, .rewardScout, .footingRead:
            return []
        case .climbingKit:
            return [.toolPouch]
        case .cardPreservation:
            return [.rewardScout]
        case .widerRewardRead:
            return [.cardPreservation]
        case .supportScout:
            return [.widerRewardRead]
        case .secondStep:
            return [.footingRead]
        case .enemyRead:
            return [.footingRead]
        case .meteorRead:
            return [.enemyRead]
        case .shortcutKit:
            return [.climbingKit]
        case .refillCharm:
            return [.shortcutKit]
        }
    }

    var requiredMilestoneFloor: Int? {
        switch self {
        case .toolPouch, .rewardScout, .footingRead:
            return nil
        case .climbingKit, .cardPreservation:
            return 10
        case .secondStep, .enemyRead, .widerRewardRead, .shortcutKit:
            return 15
        case .meteorRead, .supportScout, .refillCharm:
            return 20
        }
    }
}

enum DungeonGrowthBranch: String, CaseIterable, Identifiable {
    case preparation
    case reward
    case hazard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preparation:
            return "準備"
        case .reward:
            return "報酬"
        case .hazard:
            return "危険回避"
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
              let milestoneID = growthMilestoneID(for: dungeon, clearedFloorIndex: runState.currentFloorIndex),
              !snapshot.rewardedGrowthMilestoneIDs.contains(milestoneID)
        else { return nil }

        let floorNumber = runState.currentFloorIndex + 1
        snapshot.points += 1
        snapshot.rewardedGrowthMilestoneIDs.insert(milestoneID)
        if floorNumber == 10, dungeon.floors.indices.contains(10) {
            snapshot.unlockedGrowthCheckpointFloorNumbers.insert(11)
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
        ownedRelics: Set<DungeonRelicID> = []
    ) -> [DungeonRewardOffer] {
        let choiceCount = maxRewardChoiceCount(for: dungeon)
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
        dungeon.difficulty == .growth && isActive(.widerRewardRead) ? 4 : 3
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
        if isActive(.secondStep) {
            return 2
        }
        return isActive(.footingRead) ? 1 : 0
    }

    func startingEnemyDamageMitigations(for dungeon: DungeonDefinition) -> Int {
        dungeon.difficulty == .growth && isActive(.enemyRead) ? 1 : 0
    }

    func startingMarkerDamageMitigations(for dungeon: DungeonDefinition) -> Int {
        dungeon.difficulty == .growth && isActive(.meteorRead) ? 1 : 0
    }

    func hasRewardedGrowthMilestone(_ milestoneID: String) -> Bool {
        snapshot.rewardedGrowthMilestoneIDs.contains(milestoneID)
    }

    func growthMilestoneIDs(for dungeon: DungeonDefinition) -> [String] {
        guard dungeon.difficulty == .growth else { return [] }
        return [5, 10, 15, 20]
            .filter { dungeon.floors.indices.contains($0 - 1) }
            .map { growthMilestoneID(dungeonID: dungeon.id, floorNumber: $0) }
    }

    func growthMilestoneID(for dungeon: DungeonDefinition, clearedFloorIndex: Int) -> String? {
        let floorNumber = clearedFloorIndex + 1
        guard [5, 10, 15, 20].contains(floorNumber),
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
