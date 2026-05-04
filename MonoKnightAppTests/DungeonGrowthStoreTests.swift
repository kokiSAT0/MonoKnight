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
        let runState = DungeonRunState(dungeonID: dungeon.id, currentFloorIndex: 2, carriedHP: 3, clearedFloorCount: 2)

        XCTAssertNotNil(store.registerDungeonClear(dungeon: dungeon, runState: runState, hasNextFloor: true))
        XCTAssertTrue(store.unlock(.initialHPBoost))

        let reloadedStore = DungeonGrowthStore(userDefaults: defaults)
        XCTAssertTrue(reloadedStore.isUnlocked(.initialHPBoost))
        XCTAssertEqual(reloadedStore.points, 0)
        XCTAssertTrue(reloadedStore.hasRewardedGrowthMilestone("growth-tower-3f"))
    }

    func testDungeonGrowthStoreRejectsDuplicateUnlockAndInsufficientPoints() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let store = DungeonGrowthStore(userDefaults: defaults)
        XCTAssertFalse(store.unlock(.initialHPBoost))

        let dungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let runState = DungeonRunState(dungeonID: dungeon.id, currentFloorIndex: 2, carriedHP: 3, clearedFloorCount: 2)
        _ = store.registerDungeonClear(dungeon: dungeon, runState: runState, hasNextFloor: true)

        XCTAssertTrue(store.unlock(.initialHPBoost))
        XCTAssertFalse(store.unlock(.initialHPBoost))
    }

    func testDungeonGrowthAwardIsGrantedOnlyForGrowthTowerMilestonesOnce() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let store = DungeonGrowthStore(userDefaults: defaults)
        let dungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let secondFloor = DungeonRunState(dungeonID: dungeon.id, currentFloorIndex: 1, carriedHP: 3, clearedFloorCount: 1)
        let thirdFloor = DungeonRunState(dungeonID: dungeon.id, currentFloorIndex: 2, carriedHP: 3, clearedFloorCount: 2)
        let sixthFloor = DungeonRunState(dungeonID: dungeon.id, currentFloorIndex: 5, carriedHP: 3, clearedFloorCount: 5)

        XCTAssertNil(store.registerDungeonClear(dungeon: dungeon, runState: secondFloor, hasNextFloor: true))
        XCTAssertEqual(store.points, 0)

        XCTAssertEqual(store.registerDungeonClear(dungeon: dungeon, runState: thirdFloor, hasNextFloor: true)?.milestoneID, "growth-tower-3f")
        XCTAssertEqual(store.points, 1)
        XCTAssertNil(store.registerDungeonClear(dungeon: dungeon, runState: thirdFloor, hasNextFloor: true))
        XCTAssertEqual(store.points, 1)
        XCTAssertEqual(store.registerDungeonClear(dungeon: dungeon, runState: sixthFloor, hasNextFloor: true)?.milestoneID, "growth-tower-6f")
        XCTAssertEqual(store.points, 2)
    }

    func testDungeonGrowthAwardExposesMilestoneFloorNumber() {
        let award = DungeonGrowthAward(
            dungeonID: "growth-tower",
            milestoneID: "growth-tower-6f",
            points: 1
        )

        XCTAssertEqual(award.milestoneFloorNumber, 6)
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

        let runState = DungeonRunState(dungeonID: dungeon.id, currentFloorIndex: 2, carriedHP: 3, clearedFloorCount: 2)
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
        let runState = DungeonRunState(dungeonID: growthTower.id, currentFloorIndex: 2, carriedHP: 3, clearedFloorCount: 2)
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
        let runState = DungeonRunState(dungeonID: dungeon.id, currentFloorIndex: 2, carriedHP: 3, clearedFloorCount: 2)
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

    func testGrowthEffectsDoNotApplyToRoguelikeTower() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let store = DungeonGrowthStore(userDefaults: defaults)
        let growthDungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let rogueDungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))
        let runState = DungeonRunState(dungeonID: growthDungeon.id, currentFloorIndex: 2, carriedHP: 3, clearedFloorCount: 2)
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
