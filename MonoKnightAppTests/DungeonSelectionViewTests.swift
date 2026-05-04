import Game
import SwiftUI
import UIKit
import XCTest
@testable import MonoKnightApp

final class DungeonSelectionViewTests: XCTestCase {
    func testDungeonSelectionCanListAndStartPatrolTower() throws {
        var startedDungeon: DungeonDefinition?
        let view = NavigationStack {
            DungeonSelectionView(
                dungeonLibrary: .shared,
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

        XCTAssertEqual(DungeonLibrary.shared.dungeons.map(\.id), ["tutorial-tower", "patrol-tower"])
        let patrolTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "patrol-tower"))
        let firstMode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: patrolTower))

        XCTAssertEqual(firstMode.dungeonMetadataSnapshot?.dungeonID, patrolTower.id)
        XCTAssertEqual(firstMode.dungeonMetadataSnapshot?.floorID, "patrol-1")
        XCTAssertEqual(firstMode.dungeonMetadataSnapshot?.runState?.currentFloorIndex, 0)
        XCTAssertEqual(firstMode.boardSize, 9)
        XCTAssertNil(startedDungeon)
    }
}
