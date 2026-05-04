import Foundation
import Game
import SharedSupport

enum DungeonGrowthUpgrade: String, Codable, CaseIterable, Identifiable {
    case toolPouch
    case climbingKit
    case rewardScout
    case cardPreservation
    case footingRead
    case secondStep

    var id: String { rawValue }

    var branch: DungeonGrowthBranch {
        switch self {
        case .toolPouch, .climbingKit:
            return .preparation
        case .rewardScout, .cardPreservation:
            return .reward
        case .footingRead, .secondStep:
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
        case .footingRead:
            return "足場読み"
        case .secondStep:
            return "踏み直し"
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
            return "追加した報酬カードを4回使えるようにします"
        case .footingRead:
            return "区間ごとに最初の罠か床崩落ダメージを無効化します"
        case .secondStep:
            return "区間ごとに2回目まで罠か床崩落ダメージを無効化します"
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
        case .secondStep:
            return [.footingRead]
        }
    }

    var requiredMilestoneFloor: Int? {
        switch self {
        case .toolPouch, .rewardScout, .footingRead:
            return nil
        case .climbingKit, .cardPreservation:
            return 10
        case .secondStep:
            return 15
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
    var rewardedGrowthMilestoneIDs: Set<String>
    var unlockedGrowthCheckpointFloorNumbers: Set<Int>

    init(
        points: Int = 0,
        unlockedUpgrades: Set<DungeonGrowthUpgrade> = [],
        rewardedGrowthMilestoneIDs: Set<String> = [],
        unlockedGrowthCheckpointFloorNumbers: Set<Int> = []
    ) {
        self.points = max(points, 0)
        self.unlockedUpgrades = unlockedUpgrades
        self.rewardedGrowthMilestoneIDs = rewardedGrowthMilestoneIDs
        self.unlockedGrowthCheckpointFloorNumbers = unlockedGrowthCheckpointFloorNumbers
    }

    private enum CodingKeys: String, CodingKey {
        case points
        case unlockedUpgrades
        case rewardedGrowthMilestoneIDs
        case unlockedGrowthCheckpointFloorNumbers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        points = max(try container.decodeIfPresent(Int.self, forKey: .points) ?? 0, 0)
        unlockedUpgrades = try container.decodeIfPresent(Set<DungeonGrowthUpgrade>.self, forKey: .unlockedUpgrades) ?? []
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
    var unlockedGrowthCheckpointFloorNumbers: Set<Int> { snapshot.unlockedGrowthCheckpointFloorNumbers }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.snapshot = Self.loadSnapshot(from: userDefaults)
    }

    func isUnlocked(_ upgrade: DungeonGrowthUpgrade) -> Bool {
        snapshot.unlockedUpgrades.contains(upgrade)
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
        persist()
        return true
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
        if isUnlocked(.climbingKit) {
            return [
                DungeonInventoryEntry(card: .straightRight2, rewardUses: 1),
                DungeonInventoryEntry(card: .straightUp2, rewardUses: 1)
            ]
        }
        if isUnlocked(.toolPouch) {
            return [DungeonInventoryEntry(card: .straightRight2, rewardUses: 1)]
        }
        return []
    }

    func rewardAddUses(for dungeon: DungeonDefinition) -> Int {
        dungeon.difficulty == .growth && isUnlocked(.cardPreservation) ? 4 : 3
    }

    func rewardMoveCards(for baseCards: [MoveCard], dungeon: DungeonDefinition) -> [MoveCard] {
        guard dungeon.difficulty == .growth, isUnlocked(.rewardScout) else {
            return Array(baseCards.prefix(3))
        }

        let boostedCandidate = boostedRewardCandidate(for: baseCards)

        guard let boostedCandidate else {
            return Array(baseCards.prefix(3))
        }

        var result = Array(baseCards.prefix(2))
        result.append(boostedCandidate)
        return result
    }

    private func boostedRewardCandidate(for baseCards: [MoveCard]) -> MoveCard? {
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

        return candidates.first { !baseCards.contains($0) }
    }

    func startingHazardDamageMitigations(for dungeon: DungeonDefinition) -> Int {
        guard dungeon.difficulty == .growth else { return 0 }
        if isUnlocked(.secondStep) {
            return 2
        }
        return isUnlocked(.footingRead) ? 1 : 0
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
