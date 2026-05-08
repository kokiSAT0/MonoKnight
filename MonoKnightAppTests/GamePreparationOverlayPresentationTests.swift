import XCTest
import Game
@testable import MonoKnightApp

final class GamePreparationOverlayPresentationTests: XCTestCase {
    func testDungeonPreparationShowsOnlyTowerAndFloor() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let floor = try XCTUnwrap(tower.floors.first)
        let presentation = GamePreparationOverlayPresentation(
            mode: floor.makeGameMode(dungeonID: tower.id)
        )

        XCTAssertEqual(presentation.titleText, "基礎塔 1F")
        XCTAssertEqual(presentation.subtitleText, "Floor 1")
    }

    func testDungeonPreparationUsesRunStateFloorNumber() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let runState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 6,
            carriedHP: 3,
            clearedFloorCount: 6
        )
        let mode = tower.floors[6].makeGameMode(
            dungeonID: tower.id,
            difficulty: tower.difficulty,
            carriedHP: runState.carriedHP,
            runState: runState
        )
        let presentation = GamePreparationOverlayPresentation(mode: mode)

        XCTAssertEqual(presentation.titleText, "成長塔 7F")
        XCTAssertEqual(presentation.subtitleText, "Floor 7")
    }
}
