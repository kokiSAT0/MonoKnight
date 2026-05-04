import Game
import XCTest
@testable import MonoKnightApp

@MainActor
final class DungeonGrowthStoreTests: XCTestCase {
    func testDungeonGrowthStorePersistsPointsAndUnlockedUpgrades() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let store = DungeonGrowthStore(userDefaults: defaults)
        let dungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let runState = DungeonRunState(dungeonID: dungeon.id, currentFloorIndex: 4, carriedHP: 3, clearedFloorCount: 4)

        XCTAssertNotNil(store.registerDungeonClear(dungeon: dungeon, runState: runState, hasNextFloor: true))
        XCTAssertTrue(store.unlock(.initialHPBoost))

        let reloadedStore = DungeonGrowthStore(userDefaults: defaults)
        XCTAssertTrue(reloadedStore.isUnlocked(.initialHPBoost))
        XCTAssertEqual(reloadedStore.points, 0)
        XCTAssertTrue(reloadedStore.hasRewardedGrowthMilestone("growth-tower-5f"))
    }

    func testDungeonGrowthStoreRejectsDuplicateUnlockAndInsufficientPoints() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let store = DungeonGrowthStore(userDefaults: defaults)
        XCTAssertFalse(store.unlock(.initialHPBoost))

        let dungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let runState = DungeonRunState(dungeonID: dungeon.id, currentFloorIndex: 4, carriedHP: 3, clearedFloorCount: 4)
        _ = store.registerDungeonClear(dungeon: dungeon, runState: runState, hasNextFloor: true)

        XCTAssertTrue(store.unlock(.initialHPBoost))
        XCTAssertFalse(store.unlock(.initialHPBoost))
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
        XCTAssertEqual(store.rewardMoveCards(for: baseCards, dungeon: dungeon), baseCards)

        let runState = DungeonRunState(dungeonID: dungeon.id, currentFloorIndex: 4, carriedHP: 3, clearedFloorCount: 4)
        _ = store.registerDungeonClear(dungeon: dungeon, runState: runState, hasNextFloor: true)
        XCTAssertTrue(store.unlock(.rewardCandidateBoost))

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
        XCTAssertTrue(store.unlock(.rewardCandidateBoost))

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
        XCTAssertEqual(growthFirst, [.straightUp2, .straightRight2, .rayRight])
        XCTAssertEqual(growthSecond, [.straightRight2, .straightUp2, .rayUp])
    }

    func testInitialHPBoostIsAppliedWhenStartingFirstFloor() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let store = DungeonGrowthStore(userDefaults: defaults)
        let dungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let runState = DungeonRunState(dungeonID: dungeon.id, currentFloorIndex: 4, carriedHP: 3, clearedFloorCount: 4)
        _ = store.registerDungeonClear(dungeon: dungeon, runState: runState, hasNextFloor: true)
        XCTAssertTrue(store.unlock(.initialHPBoost))

        let mode = try XCTUnwrap(
            DungeonLibrary.shared.firstFloorMode(
                for: dungeon,
                initialHPBonus: store.initialHPBonus(for: dungeon)
            )
        )

        XCTAssertEqual(mode.dungeonRules?.failureRule.initialHP, 4)
        XCTAssertEqual(mode.dungeonMetadataSnapshot?.runState?.carriedHP, 4)
    }

    func testExpandedGrowthUpgradesAffectOnlyGrowthTowerStartsAndRewards() throws {
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

        XCTAssertTrue(store.unlock(.initialHPBoost2))
        XCTAssertTrue(store.unlock(.starterCard))
        XCTAssertTrue(store.unlock(.sectionStartHPBoost))
        XCTAssertTrue(store.unlock(.rewardUsesBoost))

        XCTAssertEqual(store.initialHPBonus(for: dungeon, startingFloorIndex: 0), 2)
        XCTAssertEqual(store.initialHPBonus(for: dungeon, startingFloorIndex: 10), 1)
        XCTAssertEqual(
            store.startingRewardEntries(for: dungeon, startingFloorIndex: 10),
            [DungeonInventoryEntry(card: .straightRight2, rewardUses: 2)]
        )
        XCTAssertEqual(store.rewardAddUses(for: dungeon), 4)
    }

    func testGrowthEffectsDoNotApplyToRoguelikeTower() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let store = DungeonGrowthStore(userDefaults: defaults)
        let growthDungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let rogueDungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))
        let runState = DungeonRunState(dungeonID: growthDungeon.id, currentFloorIndex: 4, carriedHP: 3, clearedFloorCount: 4)
        _ = store.registerDungeonClear(dungeon: growthDungeon, runState: runState, hasNextFloor: true)
        XCTAssertTrue(store.unlock(.initialHPBoost))

        let rogueRunState = DungeonRunState(dungeonID: rogueDungeon.id, currentFloorIndex: 2, carriedHP: 3, clearedFloorCount: 2)
        XCTAssertNil(store.registerDungeonClear(dungeon: rogueDungeon, runState: rogueRunState, hasNextFloor: false))
        XCTAssertEqual(store.initialHPBonus(for: rogueDungeon), 0)
        XCTAssertEqual(
            store.rewardMoveCards(for: rogueDungeon.floors[0].rewardMoveCardsAfterClear, dungeon: rogueDungeon),
            Array(rogueDungeon.floors[0].rewardMoveCardsAfterClear.prefix(3))
        )

        let firstMode = try XCTUnwrap(
            DungeonLibrary.shared.firstFloorMode(for: rogueDungeon, initialHPBonus: 99)
        )
        XCTAssertEqual(firstMode.dungeonRules?.failureRule.initialHP, rogueDungeon.floors[0].failureRule.initialHP)
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
