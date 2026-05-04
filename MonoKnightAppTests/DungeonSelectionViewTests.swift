import Game
import SwiftUI
import UIKit
import XCTest
@testable import MonoKnightApp

@MainActor
final class DungeonSelectionViewTests: XCTestCase {
    func testDungeonSelectionCanListAndStartGrowthTower() throws {
        let suiteName = "DungeonSelectionViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var startedDungeon: DungeonDefinition?
        let view = NavigationStack {
            DungeonSelectionView(
                dungeonLibrary: .shared,
                dungeonGrowthStore: DungeonGrowthStore(userDefaults: defaults),
                onClose: {},
                onStartDungeon: { startedDungeon = $0 }
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
    }

    func testDungeonSelectionShowsGrowthRewardStatusForGrowthTowers() throws {
        let suiteName = "DungeonSelectionViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let growthStore = DungeonGrowthStore(userDefaults: defaults)
        let growthTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let rogueTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))
        let thirdFloor = DungeonRunState(dungeonID: growthTower.id, currentFloorIndex: 2, carriedHP: 3, clearedFloorCount: 2)
        _ = growthStore.registerDungeonClear(dungeon: growthTower, runState: thirdFloor, hasNextFloor: true)

        let growthStatuses = DungeonGrowthRewardStatusPresentation.make(dungeon: growthTower, growthStore: growthStore)

        XCTAssertEqual(growthStatuses.map(\.text), ["3F 獲得済", "6F 未獲得", "9F 未獲得"])
        XCTAssertEqual(growthStatuses.map(\.isRewarded), [true, false, false])
        XCTAssertEqual(growthStatuses.map(\.accessibilityIdentifier), [
            "dungeon_growth_reward_status_growth-tower-3f",
            "dungeon_growth_reward_status_growth-tower-6f",
            "dungeon_growth_reward_status_growth-tower-9f"
        ])
        XCTAssertTrue(DungeonGrowthRewardStatusPresentation.make(dungeon: rogueTower, growthStore: growthStore).isEmpty)
    }
}
