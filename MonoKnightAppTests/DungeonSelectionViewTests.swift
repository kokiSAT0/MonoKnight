import Game
import SwiftUI
import UIKit
import XCTest
@testable import MonoKnightApp

@MainActor
final class DungeonSelectionViewTests: XCTestCase {
    func testDungeonSelectionCanListAndStartTrapTower() throws {
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
            ["tutorial-tower", "patrol-tower", "key-door-tower", "warp-tower", "trap-tower"]
        )
        let trapTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "trap-tower"))
        let firstMode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: trapTower))

        XCTAssertEqual(firstMode.dungeonMetadataSnapshot?.dungeonID, trapTower.id)
        XCTAssertEqual(firstMode.dungeonMetadataSnapshot?.floorID, "trap-1")
        XCTAssertEqual(firstMode.dungeonMetadataSnapshot?.runState?.currentFloorIndex, 0)
        XCTAssertEqual(firstMode.boardSize, 9)
        XCTAssertNil(startedDungeon)
    }

    func testDungeonSelectionShowsGrowthRewardStatusForGrowthTowers() throws {
        let suiteName = "DungeonSelectionViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let growthStore = DungeonGrowthStore(userDefaults: defaults)
        let tutorialTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let patrolTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "patrol-tower"))
        let warpTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "warp-tower"))
        let trapTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "trap-tower"))
        _ = growthStore.registerDungeonClear(dungeon: tutorialTower, hasNextFloor: false)

        let tutorialStatus = try XCTUnwrap(
            DungeonGrowthRewardStatusPresentation.make(
                dungeon: tutorialTower,
                hasRewardedDungeon: growthStore.hasRewardedDungeon(tutorialTower.id)
            )
        )
        let patrolStatus = try XCTUnwrap(
            DungeonGrowthRewardStatusPresentation.make(
                dungeon: patrolTower,
                hasRewardedDungeon: growthStore.hasRewardedDungeon(patrolTower.id)
            )
        )
        let warpStatus = try XCTUnwrap(
            DungeonGrowthRewardStatusPresentation.make(
                dungeon: warpTower,
                hasRewardedDungeon: growthStore.hasRewardedDungeon(warpTower.id)
            )
        )
        let trapStatus = try XCTUnwrap(
            DungeonGrowthRewardStatusPresentation.make(
                dungeon: trapTower,
                hasRewardedDungeon: growthStore.hasRewardedDungeon(trapTower.id)
            )
        )

        XCTAssertEqual(tutorialStatus.text, "成長ポイント 獲得済")
        XCTAssertTrue(tutorialStatus.isRewarded)
        XCTAssertEqual(tutorialStatus.accessibilityIdentifier, "dungeon_growth_reward_status_\(tutorialTower.id)")
        XCTAssertEqual(patrolStatus.text, "成長ポイント 未獲得")
        XCTAssertFalse(patrolStatus.isRewarded)
        XCTAssertEqual(patrolStatus.accessibilityIdentifier, "dungeon_growth_reward_status_\(patrolTower.id)")
        XCTAssertEqual(warpStatus.text, "成長ポイント 未獲得")
        XCTAssertFalse(warpStatus.isRewarded)
        XCTAssertEqual(warpStatus.accessibilityIdentifier, "dungeon_growth_reward_status_\(warpTower.id)")
        XCTAssertEqual(trapStatus.text, "成長ポイント 未獲得")
        XCTAssertFalse(trapStatus.isRewarded)
        XCTAssertEqual(trapStatus.accessibilityIdentifier, "dungeon_growth_reward_status_\(trapTower.id)")
    }
}
