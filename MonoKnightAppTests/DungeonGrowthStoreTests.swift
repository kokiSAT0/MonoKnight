import Game
import XCTest
@testable import MonoKnightApp

@MainActor
final class DungeonGrowthStoreTests: XCTestCase {
    func testDungeonGrowthStorePersistsPointsAndUnlockedTreeUpgrades() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let store = DungeonGrowthStore(userDefaults: defaults)
        let dungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let runState = DungeonRunState(dungeonID: dungeon.id, currentFloorIndex: 4, carriedHP: 3, clearedFloorCount: 4)

        XCTAssertNotNil(store.registerDungeonClear(dungeon: dungeon, runState: runState, hasNextFloor: true))
        XCTAssertTrue(store.unlock(.toolPouch))

        let reloadedStore = DungeonGrowthStore(userDefaults: defaults)
        XCTAssertTrue(reloadedStore.isUnlocked(.toolPouch))
        XCTAssertEqual(reloadedStore.points, 0)
        XCTAssertTrue(reloadedStore.hasRewardedGrowthMilestone("growth-tower-5f"))
    }

    func testDungeonGrowthStorePersistsActiveTreeTogglesAndDefaultsOldSnapshotsToActive() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        struct LegacyGrowthSnapshot: Codable {
            let points: Int
            let unlockedUpgrades: Set<DungeonGrowthUpgrade>
            let rewardedGrowthMilestoneIDs: Set<String>
            let unlockedGrowthCheckpointFloorNumbers: Set<Int>
        }

        let oldData = try JSONEncoder().encode(
            LegacyGrowthSnapshot(
                points: 0,
                unlockedUpgrades: Set<DungeonGrowthUpgrade>([.toolPouch, .rewardScout]),
                rewardedGrowthMilestoneIDs: ["growth-tower-5f"],
                unlockedGrowthCheckpointFloorNumbers: []
            )
        )
        defaults.set(oldData, forKey: StorageKey.UserDefaults.dungeonGrowth)

        let migratedStore = DungeonGrowthStore(userDefaults: defaults)
        XCTAssertTrue(migratedStore.isActive(.toolPouch))
        XCTAssertTrue(migratedStore.isActive(.rewardScout))

        XCTAssertTrue(migratedStore.setActive(.toolPouch, isActive: false))
        XCTAssertFalse(migratedStore.isActive(.toolPouch))
        XCTAssertFalse(migratedStore.setActive(.climbingKit, isActive: true))

        let reloadedStore = DungeonGrowthStore(userDefaults: defaults)
        XCTAssertFalse(reloadedStore.isActive(.toolPouch))
        XCTAssertTrue(reloadedStore.isActive(.rewardScout))
    }

    func testDungeonGrowthStoreStartsFreshFromV3StorageKey() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let oldData = try JSONEncoder().encode(
            DungeonGrowthSnapshot(
                points: 4,
                unlockedUpgrades: Set<DungeonGrowthUpgrade>([.toolPouch]),
                rewardedGrowthMilestoneIDs: ["growth-tower-5f"],
                unlockedGrowthCheckpointFloorNumbers: [11]
            )
        )
        defaults.set(oldData, forKey: "dungeon_growth_v2")

        let store = DungeonGrowthStore(userDefaults: defaults)

        XCTAssertEqual(store.points, 0)
        XCTAssertFalse(store.isUnlocked(.toolPouch))
        XCTAssertFalse(store.hasRewardedGrowthMilestone("growth-tower-5f"))
        XCTAssertEqual(store.availableGrowthStartFloorNumbers(for: try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))), [1])
    }

    func testDungeonGrowthStoreRejectsLockedDuplicateAndInsufficientUnlocks() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let store = makeStore(
            defaults: defaults,
            points: 2,
            unlocked: [],
            active: []
        )

        XCTAssertFalse(store.canUnlock(.climbingKit))
        XCTAssertEqual(store.lockReason(for: .climbingKit), "前提: 道具袋")
        XCTAssertTrue(store.unlock(.toolPouch))
        XCTAssertFalse(store.unlock(.toolPouch))
        XCTAssertTrue(store.canUnlock(.climbingKit))
        XCTAssertNil(store.lockReason(for: .climbingKit))
    }

    func testDungeonGrowthStoreLocksStrongNodesBehindPrerequisites() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let store = DungeonGrowthStore(userDefaults: defaults)
        let dungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        for floorIndex in [4, 9, 14] {
            let runState = DungeonRunState(
                dungeonID: dungeon.id,
                currentFloorIndex: floorIndex,
                carriedHP: 3,
                clearedFloorCount: floorIndex
            )
            _ = store.registerDungeonClear(dungeon: dungeon, runState: runState, hasNextFloor: true)
        }

        XCTAssertEqual(store.lockReason(for: .secondStep), "前提: 足場読み")
        XCTAssertTrue(store.unlock(.footingRead))
        XCTAssertTrue(store.canUnlock(.secondStep))
        XCTAssertTrue(store.unlock(.toolPouch))
        XCTAssertTrue(store.canUnlock(.climbingKit))
    }

    func testDungeonGrowthAwardIsGrantedOnlyForGrowthTowerMilestonesOnce() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let store = DungeonGrowthStore(userDefaults: defaults)
        let dungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let fourthFloor = DungeonRunState(dungeonID: dungeon.id, currentFloorIndex: 3, carriedHP: 3, clearedFloorCount: 3)
        let fifthFloor = DungeonRunState(dungeonID: dungeon.id, currentFloorIndex: 4, carriedHP: 3, clearedFloorCount: 4)
        let tenthFloor = DungeonRunState(dungeonID: dungeon.id, currentFloorIndex: 9, carriedHP: 3, clearedFloorCount: 9)
        let fifteenthFloor = DungeonRunState(dungeonID: dungeon.id, currentFloorIndex: 14, carriedHP: 3, clearedFloorCount: 14)
        let twentiethFloor = DungeonRunState(dungeonID: dungeon.id, currentFloorIndex: 19, carriedHP: 3, clearedFloorCount: 19)

        XCTAssertNil(store.registerDungeonClear(dungeon: dungeon, runState: fourthFloor, hasNextFloor: true))
        XCTAssertEqual(store.points, 0)

        XCTAssertEqual(store.registerDungeonClear(dungeon: dungeon, runState: fifthFloor, hasNextFloor: true)?.milestoneID, "growth-tower-5f")
        XCTAssertEqual(store.points, 1)
        XCTAssertNil(store.registerDungeonClear(dungeon: dungeon, runState: fifthFloor, hasNextFloor: true))
        XCTAssertEqual(store.points, 1)
        XCTAssertEqual(store.registerDungeonClear(dungeon: dungeon, runState: tenthFloor, hasNextFloor: true)?.milestoneID, "growth-tower-10f")
        XCTAssertEqual(store.points, 2)
        XCTAssertEqual(store.availableGrowthStartFloorNumbers(for: dungeon), [1, 11])
        XCTAssertEqual(store.registerDungeonClear(dungeon: dungeon, runState: fifteenthFloor, hasNextFloor: true)?.milestoneID, "growth-tower-15f")
        XCTAssertEqual(store.registerDungeonClear(dungeon: dungeon, runState: twentiethFloor, hasNextFloor: false)?.milestoneID, "growth-tower-20f")
        XCTAssertEqual(store.points, 4)
    }

    func testDungeonGrowthMilestonesScaleWithDungeonFloorCount() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let store = DungeonGrowthStore(userDefaults: defaults)
        let fiftyFloorDungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let twentyFloorDungeon = makeGrowthDungeon(floorCount: 20)

        XCTAssertEqual(
            store.growthMilestoneIDs(for: twentyFloorDungeon).compactMap { store.growthMilestoneFloorNumber(for: $0) },
            [5, 10, 15, 20]
        )
        XCTAssertEqual(
            store.growthMilestoneIDs(for: fiftyFloorDungeon).compactMap { store.growthMilestoneFloorNumber(for: $0) },
            [5, 10, 15, 20, 25, 30, 35, 40, 45, 50]
        )
    }

    func testDungeonGrowthRepeatAwardsComeFromSectionEnds() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let store = DungeonGrowthStore(userDefaults: defaults)
        let dungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let fifthFloor = DungeonRunState(dungeonID: dungeon.id, currentFloorIndex: 4, carriedHP: 3, clearedFloorCount: 4)
        let tenthFloor = DungeonRunState(dungeonID: dungeon.id, currentFloorIndex: 9, carriedHP: 3, clearedFloorCount: 9)
        let twentiethFloor = DungeonRunState(dungeonID: dungeon.id, currentFloorIndex: 19, carriedHP: 3, clearedFloorCount: 19)

        XCTAssertNotNil(store.registerDungeonClear(dungeon: dungeon, runState: fifthFloor, hasNextFloor: true))
        XCTAssertNil(store.registerDungeonClear(dungeon: dungeon, runState: fifthFloor, hasNextFloor: true))
        XCTAssertEqual(store.points, 1)

        XCTAssertNotNil(store.registerDungeonClear(dungeon: dungeon, runState: tenthFloor, hasNextFloor: true))
        XCTAssertNotNil(store.registerDungeonClear(dungeon: dungeon, runState: tenthFloor, hasNextFloor: true))
        XCTAssertEqual(store.points, 3)

        XCTAssertNotNil(store.registerDungeonClear(dungeon: dungeon, runState: twentiethFloor, hasNextFloor: false))
        XCTAssertNotNil(store.registerDungeonClear(dungeon: dungeon, runState: twentiethFloor, hasNextFloor: false))
        XCTAssertEqual(store.points, 5)
    }

    func testDungeonGrowthRepeatAwardsCanEventuallyUnlockAllSkills() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let store = DungeonGrowthStore(userDefaults: defaults)
        let dungeon = makeGrowthDungeon(floorCount: 50)

        for floorIndex in stride(from: 4, through: 49, by: 5) {
            let runState = DungeonRunState(dungeonID: dungeon.id, currentFloorIndex: floorIndex, carriedHP: 3, clearedFloorCount: floorIndex)
            _ = store.registerDungeonClear(dungeon: dungeon, runState: runState, hasNextFloor: floorIndex < 49)
        }
        let repeatFloors = [9, 19, 29, 39, 49]
        var repeatIndex = 0
        while store.points < DungeonGrowthUpgrade.allCases.count {
            let floorIndex = repeatFloors[repeatIndex % repeatFloors.count]
            repeatIndex += 1
            let runState = DungeonRunState(dungeonID: dungeon.id, currentFloorIndex: floorIndex, carriedHP: 3, clearedFloorCount: floorIndex)
            _ = store.registerDungeonClear(dungeon: dungeon, runState: runState, hasNextFloor: floorIndex < 49)
        }

        var passCount = 0
        while store.unlockedUpgrades.count < DungeonGrowthUpgrade.allCases.count && passCount < DungeonGrowthUpgrade.allCases.count {
            passCount += 1
            for upgrade in DungeonGrowthUpgrade.allCases {
                _ = store.unlock(upgrade)
            }
        }

        XCTAssertEqual(store.unlockedUpgrades, Set(DungeonGrowthUpgrade.allCases))
        XCTAssertEqual(store.activeUpgrades, Set(DungeonGrowthUpgrade.allCases))
    }

    func testDungeonGrowthCrossPrerequisitesUseUnlockedNotActiveParents() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let store = DungeonGrowthStore(userDefaults: defaults)
        let dungeon = makeGrowthDungeon(floorCount: 50)
        for floorIndex in stride(from: 4, through: 49, by: 5) {
            let runState = DungeonRunState(dungeonID: dungeon.id, currentFloorIndex: floorIndex, carriedHP: 3, clearedFloorCount: floorIndex)
            _ = store.registerDungeonClear(dungeon: dungeon, runState: runState, hasNextFloor: floorIndex < 49)
        }
        while store.points < 20 {
            let runState = DungeonRunState(dungeonID: dungeon.id, currentFloorIndex: 49, carriedHP: 3, clearedFloorCount: 49)
            _ = store.registerDungeonClear(dungeon: dungeon, runState: runState, hasNextFloor: false)
        }

        for upgrade in [
            .rewardScout, .cardPreservation, .widerRewardRead, .supportScout, .relicScout,
            .toolPouch, .climbingKit, .shortcutKit, .refillCharm, .deepStartKit
        ] as [DungeonGrowthUpgrade] {
            XCTAssertTrue(store.unlock(upgrade), "\(upgrade.rawValue) should unlock")
        }
        XCTAssertTrue(store.canUnlock(.deepSupplyCraft))
        XCTAssertTrue(store.unlock(.deepSupplyCraft))

        XCTAssertTrue(store.setActive(.deepStartKit, isActive: false))
        XCTAssertTrue(store.setActive(.relicScout, isActive: false))
        XCTAssertTrue(store.isActive(.deepSupplyCraft))
    }

    func testDungeonGrowthAwardExposesMilestoneFloorNumber() {
        let award = DungeonGrowthAward(
            dungeonID: "growth-tower",
            milestoneID: "growth-tower-15f",
            points: 1
        )

        XCTAssertEqual(award.milestoneFloorNumber, 15)
    }

    func testGrowthEffectsApplyOnlyWhenUnlocked() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let store = DungeonGrowthStore(userDefaults: defaults)
        let dungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let firstFloor = try XCTUnwrap(dungeon.floors.first)
        let baseCards = firstFloor.rewardMoveCardsAfterClear

        XCTAssertEqual(store.initialHPBonus(for: dungeon), 0)
        XCTAssertEqual(store.startingRewardEntries(for: dungeon, startingFloorIndex: 0), [])
        XCTAssertEqual(store.startingHazardDamageMitigations(for: dungeon), 0)
        XCTAssertEqual(store.rewardMoveCards(for: baseCards, dungeon: dungeon), baseCards)

        let runState = DungeonRunState(dungeonID: dungeon.id, currentFloorIndex: 4, carriedHP: 3, clearedFloorCount: 4)
        _ = store.registerDungeonClear(dungeon: dungeon, runState: runState, hasNextFloor: true)
        XCTAssertTrue(store.unlock(.rewardScout))

        let boostedCards = store.rewardMoveCards(for: baseCards, dungeon: dungeon)
        XCTAssertEqual(boostedCards.count, 3)
        XCTAssertEqual(boostedCards.prefix(2), baseCards.prefix(2))
        XCTAssertNotEqual(boostedCards, baseCards)
    }

    func testExpandedGrowthTreeUnlocksBranchDepthAndUsesActiveEffectsOnly() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let store = DungeonGrowthStore(userDefaults: defaults)
        let dungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        for floorIndex in [4, 9, 14, 19] {
            let runState = DungeonRunState(
                dungeonID: dungeon.id,
                currentFloorIndex: floorIndex,
                carriedHP: 3,
                clearedFloorCount: floorIndex
            )
            _ = store.registerDungeonClear(dungeon: dungeon, runState: runState, hasNextFloor: floorIndex < 19)
        }

        XCTAssertTrue(store.unlock(.rewardScout))
        XCTAssertTrue(store.unlock(.cardPreservation))
        XCTAssertTrue(store.unlock(.widerRewardRead))
        XCTAssertTrue(store.unlock(.supportScout))
        XCTAssertTrue(store.isActive(.supportScout))

        let baseMoveCards = Array(dungeon.floors[10].rewardMoveCardsAfterClear.prefix(4))
        XCTAssertEqual(store.maxRewardChoiceCount(for: dungeon), 4)
        XCTAssertEqual(store.rewardMoveCards(for: baseMoveCards, dungeon: dungeon).count, 4)
        XCTAssertEqual(
            store.rewardSupportCards(for: [], dungeon: dungeon, floorIndex: 10),
            [.refillEmptySlots]
        )

        XCTAssertTrue(store.setActive(.widerRewardRead, isActive: false))
        XCTAssertTrue(store.setActive(.supportScout, isActive: false))
        XCTAssertEqual(store.maxRewardChoiceCount(for: dungeon), 3)
        XCTAssertEqual(store.rewardSupportCards(for: [], dungeon: dungeon, floorIndex: 10), [])
    }

    func testPreparationAndDangerBranchNewEffectsApplyOnlyWhenActive() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let store = DungeonGrowthStore(userDefaults: defaults)
        let dungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        for floorIndex in [4, 9, 14, 19] {
            let runState = DungeonRunState(
                dungeonID: dungeon.id,
                currentFloorIndex: floorIndex,
                carriedHP: 3,
                clearedFloorCount: floorIndex
            )
            _ = store.registerDungeonClear(dungeon: dungeon, runState: runState, hasNextFloor: floorIndex < 19)
        }

        XCTAssertTrue(store.unlock(.toolPouch))
        XCTAssertTrue(store.unlock(.climbingKit))
        XCTAssertTrue(store.unlock(.shortcutKit))
        XCTAssertTrue(store.unlock(.refillCharm))

        XCTAssertEqual(
            store.startingRewardEntries(for: dungeon, startingFloorIndex: 10),
            [
                DungeonInventoryEntry(card: .straightRight2, rewardUses: 1),
                DungeonInventoryEntry(card: .straightUp2, rewardUses: 1),
                DungeonInventoryEntry(card: .diagonalUpRight2, rewardUses: 1),
                DungeonInventoryEntry(support: .refillEmptySlots, rewardUses: 1)
            ]
        )

        XCTAssertTrue(store.setActive(.climbingKit, isActive: false))
        XCTAssertEqual(
            store.startingRewardEntries(for: dungeon, startingFloorIndex: 10),
            [
                DungeonInventoryEntry(card: .straightRight2, rewardUses: 1),
                DungeonInventoryEntry(card: .diagonalUpRight2, rewardUses: 1),
                DungeonInventoryEntry(support: .refillEmptySlots, rewardUses: 1)
            ]
        )

        let (dangerDefaults, dangerSuiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: dangerSuiteName) }
        let dangerStore = DungeonGrowthStore(userDefaults: dangerDefaults)
        for floorIndex in [4, 9, 14, 19] {
            let runState = DungeonRunState(
                dungeonID: dungeon.id,
                currentFloorIndex: floorIndex,
                carriedHP: 3,
                clearedFloorCount: floorIndex
            )
            _ = dangerStore.registerDungeonClear(dungeon: dungeon, runState: runState, hasNextFloor: floorIndex < 19)
        }
        XCTAssertTrue(dangerStore.unlock(.footingRead))
        XCTAssertTrue(dangerStore.unlock(.enemyRead))
        XCTAssertTrue(dangerStore.unlock(.meteorRead))
        XCTAssertEqual(dangerStore.startingEnemyDamageMitigations(for: dungeon), 1)
        XCTAssertEqual(dangerStore.startingMarkerDamageMitigations(for: dungeon), 1)
        XCTAssertTrue(dangerStore.setActive(.enemyRead, isActive: false))
        XCTAssertEqual(dangerStore.startingEnemyDamageMitigations(for: dungeon), 0)
        XCTAssertEqual(dangerStore.startingMarkerDamageMitigations(for: dungeon), 1)
    }

    func testRewardCandidateBoostVariesByExistingRewardShape() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let store = DungeonGrowthStore(userDefaults: defaults)
        let tutorialTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let growthTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let runState = DungeonRunState(dungeonID: growthTower.id, currentFloorIndex: 4, carriedHP: 3, clearedFloorCount: 4)
        _ = store.registerDungeonClear(dungeon: growthTower, runState: runState, hasNextFloor: true)
        XCTAssertTrue(store.unlock(.rewardScout))

        let tutorialFirst = store.rewardMoveCards(
            for: tutorialTower.floors[0].rewardMoveCardsAfterClear,
            dungeon: tutorialTower
        )
        let tutorialSecond = store.rewardMoveCards(
            for: tutorialTower.floors[1].rewardMoveCardsAfterClear,
            dungeon: tutorialTower
        )
        let growthFirst = store.rewardMoveCards(
            for: growthTower.floors[0].rewardMoveCardsAfterClear,
            dungeon: growthTower
        )
        let growthSecond = store.rewardMoveCards(
            for: growthTower.floors[1].rewardMoveCardsAfterClear,
            dungeon: growthTower
        )

        XCTAssertEqual(tutorialFirst, [.straightRight2, .straightUp2, .knightRightwardChoice])
        XCTAssertEqual(tutorialSecond, [.rayRight, .straightRight2, .knightRightwardChoice])
        XCTAssertEqual(growthFirst.count, 3)
        XCTAssertEqual(growthSecond.count, 3)
        XCTAssertEqual(growthFirst.prefix(2), growthTower.floors[0].rewardMoveCardsAfterClear.prefix(2))
        XCTAssertEqual(growthSecond.prefix(2), growthTower.floors[1].rewardMoveCardsAfterClear.prefix(2))
        XCTAssertNotEqual(growthFirst, Array(growthTower.floors[0].rewardMoveCardsAfterClear.prefix(3)))
        XCTAssertNotEqual(growthSecond, Array(growthTower.floors[1].rewardMoveCardsAfterClear.prefix(3)))
    }

    func testTreeGrowthUpgradesAffectOnlyGrowthTowerStartsAndRewards() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let store = DungeonGrowthStore(userDefaults: defaults)
        let dungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        for floorIndex in [4, 9, 14, 19] {
            let runState = DungeonRunState(
                dungeonID: dungeon.id,
                currentFloorIndex: floorIndex,
                carriedHP: 3,
                clearedFloorCount: floorIndex
            )
            _ = store.registerDungeonClear(dungeon: dungeon, runState: runState, hasNextFloor: floorIndex < 19)
        }

        XCTAssertTrue(store.unlock(.toolPouch))
        XCTAssertTrue(store.unlock(.climbingKit))
        XCTAssertTrue(store.unlock(.rewardScout))
        XCTAssertTrue(store.unlock(.cardPreservation))

        XCTAssertEqual(store.initialHPBonus(for: dungeon, startingFloorIndex: 0), 0)
        XCTAssertEqual(store.initialHPBonus(for: dungeon, startingFloorIndex: 10), 0)
        XCTAssertEqual(
            store.startingRewardEntries(for: dungeon, startingFloorIndex: 10),
            [
                DungeonInventoryEntry(card: .straightRight2, rewardUses: 1),
                DungeonInventoryEntry(card: .straightUp2, rewardUses: 1)
            ]
        )
        XCTAssertEqual(store.rewardAddUses(for: dungeon), 3)
        XCTAssertEqual(store.startingHazardDamageMitigations(for: dungeon), 0)
    }

    func testHazardGrowthBranchCanReachSecondStepWithoutMilestoneGate() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let store = DungeonGrowthStore(userDefaults: defaults)
        let dungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        for floorIndex in [4, 9, 14] {
            let runState = DungeonRunState(
                dungeonID: dungeon.id,
                currentFloorIndex: floorIndex,
                carriedHP: 3,
                clearedFloorCount: floorIndex
            )
            _ = store.registerDungeonClear(dungeon: dungeon, runState: runState, hasNextFloor: true)
        }

        XCTAssertTrue(store.unlock(.footingRead))
        XCTAssertTrue(store.unlock(.secondStep))

        XCTAssertEqual(store.startingHazardDamageMitigations(for: dungeon), 2)
    }

    func testRetryRecoveryEntriesApplyOnlyWhenActiveAndDeepEnough() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let dungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let store = makeStore(
            defaults: defaults,
            unlocked: [.retryPreparation, .deepCheckpointRead, .checkpointExpansion, .comebackRoute, .finalRecovery],
            active: [.retryPreparation, .deepCheckpointRead, .checkpointExpansion, .comebackRoute, .finalRecovery]
        )

        XCTAssertEqual(store.retryRewardEntries(for: dungeon, startingFloorIndex: 10), [])
        XCTAssertEqual(
            store.retryRewardEntries(for: dungeon, startingFloorIndex: 20),
            [
                DungeonInventoryEntry(support: .refillEmptySlots, rewardUses: 1),
                DungeonInventoryEntry(support: .barrierSpell, rewardUses: 1)
            ]
        )
        XCTAssertEqual(
            store.retryRewardEntries(for: dungeon, startingFloorIndex: 30),
            [
                DungeonInventoryEntry(support: .refillEmptySlots, rewardUses: 1),
                DungeonInventoryEntry(support: .barrierSpell, rewardUses: 1),
                DungeonInventoryEntry(support: .panacea, rewardUses: 1)
            ]
        )
        XCTAssertEqual(
            store.retryRewardEntries(for: dungeon, startingFloorIndex: 40),
            [
                DungeonInventoryEntry(support: .refillEmptySlots, rewardUses: 1),
                DungeonInventoryEntry(support: .barrierSpell, rewardUses: 1),
                DungeonInventoryEntry(support: .panacea, rewardUses: 1),
                DungeonInventoryEntry(card: .rayUpRight, rewardUses: 1),
                DungeonInventoryEntry(support: .freezeSpell, rewardUses: 1)
            ]
        )

        XCTAssertTrue(store.setActive(.deepCheckpointRead, isActive: false))
        XCTAssertFalse(
            store.retryRewardEntries(for: dungeon, startingFloorIndex: 40)
                .contains(DungeonInventoryEntry(support: .barrierSpell, rewardUses: 1))
        )
    }

    func testRetryRecoveryEntriesDoNotApplyToNonGrowthTowersOrNormalStarts() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let growthDungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let rogueDungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))
        let store = makeStore(
            defaults: defaults,
            unlocked: [.retryPreparation, .deepCheckpointRead],
            active: [.retryPreparation, .deepCheckpointRead]
        )

        XCTAssertEqual(store.retryRewardEntries(for: rogueDungeon, startingFloorIndex: 20), [])
        XCTAssertEqual(store.startingRewardEntries(for: growthDungeon, startingFloorIndex: 20), [])
        XCTAssertEqual(
            store.retryRewardEntries(for: growthDungeon, startingFloorIndex: 20),
            [
                DungeonInventoryEntry(support: .refillEmptySlots, rewardUses: 1),
                DungeonInventoryEntry(support: .barrierSpell, rewardUses: 1)
            ]
        )
    }

    func testGrowthEffectsDoNotApplyToRoguelikeTower() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let store = DungeonGrowthStore(userDefaults: defaults)
        let growthDungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let rogueDungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))
        let runState = DungeonRunState(dungeonID: growthDungeon.id, currentFloorIndex: 4, carriedHP: 3, clearedFloorCount: 4)
        _ = store.registerDungeonClear(dungeon: growthDungeon, runState: runState, hasNextFloor: true)
        XCTAssertTrue(store.unlock(.toolPouch))

        let rogueRunState = DungeonRunState(dungeonID: rogueDungeon.id, currentFloorIndex: 2, carriedHP: 3, clearedFloorCount: 2)
        XCTAssertNil(store.registerDungeonClear(dungeon: rogueDungeon, runState: rogueRunState, hasNextFloor: false))
        XCTAssertEqual(store.initialHPBonus(for: rogueDungeon), 0)
        XCTAssertTrue(store.startingRewardEntries(for: rogueDungeon, startingFloorIndex: 0).isEmpty)
        XCTAssertEqual(store.startingHazardDamageMitigations(for: rogueDungeon), 0)
        XCTAssertEqual(
            store.rewardMoveCards(for: rogueDungeon.floors[0].rewardMoveCardsAfterClear, dungeon: rogueDungeon),
            Array(rogueDungeon.floors[0].rewardMoveCardsAfterClear.prefix(3))
        )

        let firstMode = try XCTUnwrap(
            DungeonLibrary.shared.firstFloorMode(for: rogueDungeon, initialHPBonus: 99, startingHazardDamageMitigations: 99)
        )
        XCTAssertEqual(firstMode.dungeonRules?.failureRule.initialHP, rogueDungeon.floors[0].failureRule.initialHP)
        XCTAssertEqual(firstMode.dungeonMetadataSnapshot?.runState?.hazardDamageMitigationsRemaining, 0)
    }

    private func makeIsolatedDefaults() throws -> (UserDefaults, String) {
        let suiteName = "DungeonGrowthStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("UserDefaults を生成できませんでした")
            throw NSError(domain: "DungeonGrowthStoreTests", code: -1)
        }
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private func makeStore(
        defaults: UserDefaults,
        points: Int = 0,
        unlocked: Set<DungeonGrowthUpgrade>,
        active: Set<DungeonGrowthUpgrade>
    ) -> DungeonGrowthStore {
        let snapshot = DungeonGrowthSnapshot(
            points: points,
            unlockedUpgrades: unlocked,
            activeUpgrades: active
        )
        let data = try? JSONEncoder().encode(snapshot)
        defaults.set(data, forKey: StorageKey.UserDefaults.dungeonGrowth)
        return DungeonGrowthStore(userDefaults: defaults)
    }

    private func makeGrowthDungeon(floorCount: Int) -> DungeonDefinition {
        let baseFloor = DungeonLibrary.shared.dungeon(with: "growth-tower")!.floors[0]
        let floors = (0..<floorCount).map { index in
            DungeonFloorDefinition(
                id: "growth-test-\(index + 1)",
                title: "\(index + 1)F",
                boardSize: baseFloor.boardSize,
                spawnPoint: baseFloor.spawnPoint,
                exitPoint: baseFloor.exitPoint,
                deckPreset: baseFloor.deckPreset,
                failureRule: baseFloor.failureRule,
                enemies: baseFloor.enemies,
                hazards: baseFloor.hazards,
                impassableTilePoints: baseFloor.impassableTilePoints,
                tileEffectOverrides: baseFloor.tileEffectOverrides,
                warpTilePairs: baseFloor.warpTilePairs,
                exitLock: baseFloor.exitLock,
                cardPickups: baseFloor.cardPickups,
                relicPickups: baseFloor.relicPickups,
                rewardMoveCardsAfterClear: baseFloor.rewardMoveCardsAfterClear,
                rewardSupportCardsAfterClear: baseFloor.rewardSupportCardsAfterClear
            )
        }
        return DungeonDefinition(
            id: "growth-test-\(floorCount)",
            title: "成長塔テスト",
            summary: "テスト用",
            difficulty: .growth,
            floors: floors
        )
    }
}
