import XCTest
@testable import MonoKnightApp

final class GameBoardControlRowViewTests: XCTestCase {
    func testDungeonHPAccessibilityIncludesCriticalStateAtOneHP() {
        XCTAssertTrue(GameBoardControlRowView.isCriticalDungeonHP(1))
        XCTAssertEqual(GameBoardControlRowView.dungeonHPAccessibilityValue(for: 1), "1、瀕死")
    }

    func testDungeonHPAccessibilityIncludesCriticalStateAtZeroHP() {
        XCTAssertTrue(GameBoardControlRowView.isCriticalDungeonHP(0))
        XCTAssertEqual(GameBoardControlRowView.dungeonHPAccessibilityValue(for: 0), "0、瀕死")
    }

    func testDungeonHPAccessibilityStaysNormalAboveOneHP() {
        XCTAssertFalse(GameBoardControlRowView.isCriticalDungeonHP(2))
        XCTAssertEqual(GameBoardControlRowView.dungeonHPAccessibilityValue(for: 2), "2")
    }
}
