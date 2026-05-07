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

    func testDungeonGrowthStoreStartsFreshFromV3StorageKey() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let oldData = try JSONEncoder().encode(
            DungeonGrowthSnapshot(
                points: 4,
                unlockedUpgrades: [.toolPouch],
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

        let store = DungeonGrowthStore(userDefaults: defaults)
        XCTAssertFalse(store.unlock(.toolPouch))

        let dungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let fifthFloor = DungeonRunState(dungeonID: dungeon.id, currentFloorIndex: 4, carriedHP: 3, clearedFloorCount: 4)
        _ = store.registerDungeonClear(dungeon: dungeon, runState: fifthFloor, hasNextFloor: true)

        XCTAssertFalse(store.canUnlock(.climbingKit))
        XCTAssertEqual(store.lockReason(for: .climbingKit), "前提: 道具袋")
        XCTAssertTrue(store.unlock(.toolPouch))
        XCTAssertFalse(store.unlock(.toolPouch))
        XCTAssertFalse(store.canUnlock(.climbingKit))
        XCTAssertEqual(store.lockReason(for: .climbingKit), "10F到達後")
    }

    func testDungeonGrowthStoreLocksStrongNodesBehindMilestones() throws {
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

    func testHazardGrowthBranchCanReachSecondStepWithFifteenthFloorMilestone() throws {
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
}
