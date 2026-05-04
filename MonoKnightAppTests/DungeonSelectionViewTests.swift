import Game
import SwiftUI
import UIKit
import XCTest
@testable import MonoKnightApp

@MainActor
final class DungeonSelectionViewTests: XCTestCase {
    func testDungeonSelectionCanShowThreeTowerCardsAndStartGrowthTower() throws {
        let suiteName = "DungeonSelectionViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var startedDungeon: DungeonDefinition?
        var startedFloorIndex: Int?
        let view = NavigationStack {
            DungeonSelectionView(
                dungeonLibrary: .shared,
                dungeonGrowthStore: DungeonGrowthStore(userDefaults: defaults),
                onClose: {},
                onStartDungeon: {
                    startedDungeon = $0
                    startedFloorIndex = $1
                }
            )
        }
        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let window = UIWindow(frame: controller.view.frame)
        window.rootViewController = controller
        window.makeKeyAndVisible()

        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        XCTAssertEqual(
            DungeonLibrary.shared.dungeons.map(\.id),
            ["tutorial-tower", "growth-tower", "rogue-tower"]
        )
        let growthTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let firstMode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: growthTower))

        XCTAssertEqual(firstMode.dungeonMetadataSnapshot?.dungeonID, growthTower.id)
        XCTAssertEqual(firstMode.dungeonMetadataSnapshot?.floorID, "patrol-1")
        XCTAssertEqual(firstMode.dungeonMetadataSnapshot?.runState?.currentFloorIndex, 0)
        XCTAssertEqual(firstMode.boardSize, 9)
        XCTAssertNil(startedDungeon)
        XCTAssertNil(startedFloorIndex)
    }

    func testDungeonSelectionShowsOnlyTowerCardsWithoutFloorInfoRows() throws {
        XCTAssertEqual(
            DungeonLibrary.shared.dungeons.map { "dungeon_card_\($0.id)" },
            [
                "dungeon_card_tutorial-tower",
                "dungeon_card_growth-tower",
                "dungeon_card_rogue-tower"
            ]
        )
        XCTAssertFalse(
            DungeonLibrary.shared.allFloors
                .map { "dungeon_floor_info_\($0.id)" }
                .contains("dungeon_card_growth-tower")
        )
    }

    func testDungeonSelectionShowsGrowthRewardStatusForGrowthTowers() throws {
        let suiteName = "DungeonSelectionViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let growthStore = DungeonGrowthStore(userDefaults: defaults)
        let growthTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let rogueTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))
        let fifthFloor = DungeonRunState(dungeonID: growthTower.id, currentFloorIndex: 4, carriedHP: 3, clearedFloorCount: 4)
        _ = growthStore.registerDungeonClear(dungeon: growthTower, runState: fifthFloor, hasNextFloor: true)

        let growthStatuses = DungeonGrowthRewardStatusPresentation.make(dungeon: growthTower, growthStore: growthStore)

        XCTAssertEqual(growthStatuses.map(\.text), ["5F 獲得済", "10F 未獲得", "15F 未獲得", "20F 未獲得"])
        XCTAssertEqual(growthStatuses.map(\.isRewarded), [true, false, false, false])
        XCTAssertEqual(growthStatuses.map(\.accessibilityIdentifier), [
            "dungeon_growth_reward_status_growth-tower-5f",
            "dungeon_growth_reward_status_growth-tower-10f",
            "dungeon_growth_reward_status_growth-tower-15f",
            "dungeon_growth_reward_status_growth-tower-20f"
        ])
        XCTAssertTrue(DungeonGrowthRewardStatusPresentation.make(dungeon: rogueTower, growthStore: growthStore).isEmpty)
    }

    func testDungeonSelectionExposesSecondSectionAfterCheckpointUnlock() throws {
        let suiteName = "DungeonSelectionViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let growthStore = DungeonGrowthStore(userDefaults: defaults)
        let growthTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let tenthFloor = DungeonRunState(dungeonID: growthTower.id, currentFloorIndex: 9, carriedHP: 3, clearedFloorCount: 9)

        XCTAssertEqual(growthStore.availableGrowthStartFloorNumbers(for: growthTower), [1])
        _ = growthStore.registerDungeonClear(dungeon: growthTower, runState: tenthFloor, hasNextFloor: true)

        XCTAssertEqual(growthStore.availableGrowthStartFloorNumbers(for: growthTower), [1, 11])
    }

    func testDungeonSelectionStartButtonsStayAvailableForUnlockedFloors() throws {
        let suiteName = "DungeonSelectionViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let growthStore = DungeonGrowthStore(userDefaults: defaults)
        let growthTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let tenthFloor = DungeonRunState(dungeonID: growthTower.id, currentFloorIndex: 9, carriedHP: 3, clearedFloorCount: 9)

        XCTAssertEqual(
            growthStore.availableGrowthStartFloorNumbers(for: growthTower)
                .map { "dungeon_start_button_\(growthTower.id)_\($0)f" },
            ["dungeon_start_button_growth-tower_1f"]
        )

        _ = growthStore.registerDungeonClear(dungeon: growthTower, runState: tenthFloor, hasNextFloor: true)

        XCTAssertEqual(
            growthStore.availableGrowthStartFloorNumbers(for: growthTower)
                .map { "dungeon_start_button_\(growthTower.id)_\($0)f" },
            [
                "dungeon_start_button_growth-tower_1f",
                "dungeon_start_button_growth-tower_11f"
            ]
        )
    }

    func testDungeonSelectionGrowthTreeLockStateChangesAfterMilestones() throws {
        let suiteName = "DungeonSelectionViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let growthStore = DungeonGrowthStore(userDefaults: defaults)
        let growthTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let fifthFloor = DungeonRunState(dungeonID: growthTower.id, currentFloorIndex: 4, carriedHP: 3, clearedFloorCount: 4)
        let tenthFloor = DungeonRunState(dungeonID: growthTower.id, currentFloorIndex: 9, carriedHP: 3, clearedFloorCount: 9)

        _ = growthStore.registerDungeonClear(dungeon: growthTower, runState: fifthFloor, hasNextFloor: true)

        XCTAssertTrue(growthStore.canUnlock(.toolPouch))
        XCTAssertEqual(growthStore.lockReason(for: .climbingKit), "前提: 道具袋")
        XCTAssertTrue(growthStore.unlock(.toolPouch))
        XCTAssertEqual(growthStore.lockReason(for: .climbingKit), "10F到達後")

        _ = growthStore.registerDungeonClear(dungeon: growthTower, runState: tenthFloor, hasNextFloor: true)

        XCTAssertTrue(growthStore.canUnlock(.climbingKit))
    }
}
