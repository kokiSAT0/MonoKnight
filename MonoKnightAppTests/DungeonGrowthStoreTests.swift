import Game
import XCTest
@testable import MonoKnightApp

@MainActor
final class DungeonGrowthStoreTests: XCTestCase {
    func testDungeonGrowthStorePersistsPointsAndUnlockedUpgrades() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let store = DungeonGrowthStore(userDefaults: defaults)
        let dungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))

        XCTAssertNotNil(store.registerDungeonClear(dungeon: dungeon, hasNextFloor: false))
        XCTAssertTrue(store.unlock(.initialHPBoost))

        let reloadedStore = DungeonGrowthStore(userDefaults: defaults)
        XCTAssertTrue(reloadedStore.isUnlocked(.initialHPBoost))
        XCTAssertEqual(reloadedStore.points, 0)
        XCTAssertTrue(reloadedStore.hasRewardedDungeon(dungeon.id))
    }

    func testDungeonGrowthStoreRejectsDuplicateUnlockAndInsufficientPoints() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let store = DungeonGrowthStore(userDefaults: defaults)
        XCTAssertFalse(store.unlock(.initialHPBoost))

        let dungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        _ = store.registerDungeonClear(dungeon: dungeon, hasNextFloor: false)

        XCTAssertTrue(store.unlock(.initialHPBoost))
        XCTAssertFalse(store.unlock(.initialHPBoost))
    }

    func testDungeonGrowthAwardIsOnlyGrantedForFinalGrowthTowerClearOnce() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let store = DungeonGrowthStore(userDefaults: defaults)
        let dungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))

        XCTAssertNil(store.registerDungeonClear(dungeon: dungeon, hasNextFloor: true))
        XCTAssertEqual(store.points, 0)

        XCTAssertEqual(store.registerDungeonClear(dungeon: dungeon, hasNextFloor: false)?.points, 1)
        XCTAssertEqual(store.points, 1)
        XCTAssertNil(store.registerDungeonClear(dungeon: dungeon, hasNextFloor: false))
        XCTAssertEqual(store.points, 1)
    }

    func testGrowthEffectsApplyOnlyWhenUnlocked() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let store = DungeonGrowthStore(userDefaults: defaults)
        let dungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let firstFloor = try XCTUnwrap(dungeon.floors.first)
        let baseCards = firstFloor.rewardMoveCardsAfterClear

        XCTAssertEqual(store.initialHPBonus(for: dungeon), 0)
        XCTAssertEqual(store.rewardMoveCards(for: baseCards, dungeon: dungeon), baseCards)

        _ = store.registerDungeonClear(dungeon: dungeon, hasNextFloor: false)
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
        let patrolTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "patrol-tower"))
        let keyDoorTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "key-door-tower"))
        _ = store.registerDungeonClear(dungeon: tutorialTower, hasNextFloor: false)
        XCTAssertTrue(store.unlock(.rewardCandidateBoost))

        let tutorialFirst = store.rewardMoveCards(
            for: tutorialTower.floors[0].rewardMoveCardsAfterClear,
            dungeon: tutorialTower
        )
        let tutorialSecond = store.rewardMoveCards(
            for: tutorialTower.floors[1].rewardMoveCardsAfterClear,
            dungeon: tutorialTower
        )
        let patrolFirst = store.rewardMoveCards(
            for: patrolTower.floors[0].rewardMoveCardsAfterClear,
            dungeon: patrolTower
        )
        let keyDoorSecond = store.rewardMoveCards(
            for: keyDoorTower.floors[1].rewardMoveCardsAfterClear,
            dungeon: keyDoorTower
        )

        XCTAssertEqual(tutorialFirst, [.straightRight2, .straightUp2, .rayUp])
        XCTAssertEqual(tutorialSecond, [.rayRight, .straightRight2, .diagonalUpRight2])
        XCTAssertEqual(patrolFirst, [.straightUp2, .straightRight2, .rayRight])
        XCTAssertEqual(keyDoorSecond, [.straightUp2, .straightRight2, .rayUp])
    }

    func testInitialHPBoostIsAppliedWhenStartingFirstFloor() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let store = DungeonGrowthStore(userDefaults: defaults)
        let dungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        _ = store.registerDungeonClear(dungeon: dungeon, hasNextFloor: false)
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
