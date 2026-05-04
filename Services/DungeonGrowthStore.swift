import Foundation
import Game
import SharedSupport

enum DungeonGrowthUpgrade: String, Codable, CaseIterable, Identifiable {
    case initialHPBoost
    case rewardCandidateBoost

    var id: String { rawValue }

    var title: String {
        switch self {
        case .initialHPBoost:
            return "初期HP +1"
        case .rewardCandidateBoost:
            return "報酬候補強化"
        }
    }

    var summary: String {
        switch self {
        case .initialHPBoost:
            return "低難度塔の1F開始時にHPを1増やします"
        case .rewardCandidateBoost:
            return "1F/2F後の報酬候補に強めの移動カードを混ぜます"
        }
    }

    var cost: Int { 1 }
}

struct DungeonGrowthAward: Equatable {
    let dungeonID: String
    let points: Int
}

struct DungeonGrowthSnapshot: Codable, Equatable {
    var points: Int
    var unlockedUpgrades: Set<DungeonGrowthUpgrade>
    var rewardedDungeonIDs: Set<String>

    init(
        points: Int = 0,
        unlockedUpgrades: Set<DungeonGrowthUpgrade> = [],
        rewardedDungeonIDs: Set<String> = []
    ) {
        self.points = max(points, 0)
        self.unlockedUpgrades = unlockedUpgrades
        self.rewardedDungeonIDs = rewardedDungeonIDs
    }
}

@MainActor
final class DungeonGrowthStore: ObservableObject {
    private static let storageKey = StorageKey.UserDefaults.dungeonGrowth
    private let userDefaults: UserDefaults

    @Published private(set) var snapshot: DungeonGrowthSnapshot

    var points: Int { snapshot.points }
    var unlockedUpgrades: Set<DungeonGrowthUpgrade> { snapshot.unlockedUpgrades }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.snapshot = Self.loadSnapshot(from: userDefaults)
    }

    func isUnlocked(_ upgrade: DungeonGrowthUpgrade) -> Bool {
        snapshot.unlockedUpgrades.contains(upgrade)
    }

    @discardableResult
    func unlock(_ upgrade: DungeonGrowthUpgrade) -> Bool {
        guard !isUnlocked(upgrade), snapshot.points >= upgrade.cost else {
            return false
        }

        snapshot.points -= upgrade.cost
        snapshot.unlockedUpgrades.insert(upgrade)
        persist()
        return true
    }

    @discardableResult
    func registerDungeonClear(dungeon: DungeonDefinition, hasNextFloor: Bool) -> DungeonGrowthAward? {
        guard dungeon.difficulty == .growth,
              !hasNextFloor,
              !snapshot.rewardedDungeonIDs.contains(dungeon.id)
        else { return nil }

        snapshot.points += 1
        snapshot.rewardedDungeonIDs.insert(dungeon.id)
        persist()
        debugLog("DungeonGrowthStore: \(dungeon.id) クリア報酬として成長ポイント +1")
        return DungeonGrowthAward(dungeonID: dungeon.id, points: 1)
    }

    func initialHPBonus(for dungeon: DungeonDefinition) -> Int {
        dungeon.difficulty == .growth && isUnlocked(.initialHPBoost) ? 1 : 0
    }

    func rewardMoveCards(for baseCards: [MoveCard], dungeon: DungeonDefinition) -> [MoveCard] {
        guard dungeon.difficulty == .growth, isUnlocked(.rewardCandidateBoost) else {
            return Array(baseCards.prefix(3))
        }

        let boostedCandidate = [
            MoveCard.rayRight,
            .diagonalUpRight2,
            .rayUp,
            .knightRightwardChoice
        ].first { !baseCards.contains($0) }

        guard let boostedCandidate else {
            return Array(baseCards.prefix(3))
        }

        var result = Array(baseCards.prefix(2))
        result.append(boostedCandidate)
        return result
    }

    func hasRewardedDungeon(_ dungeonID: String) -> Bool {
        snapshot.rewardedDungeonIDs.contains(dungeonID)
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
