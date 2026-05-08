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

    func testDungeonTurnProgressUsesRemainingOverLimit() {
        XCTAssertEqual(GameBoardControlRowView.dungeonTurnProgress(remaining: 12, limit: 18), 12.0 / 18.0)
    }

    func testDungeonTurnProgressIsZeroWhenNoTurnsRemain() {
        XCTAssertEqual(GameBoardControlRowView.dungeonTurnProgress(remaining: 0, limit: 18), 0)
    }

    func testDungeonTurnProgressIsNilWithoutLimit() {
        XCTAssertNil(GameBoardControlRowView.dungeonTurnProgress(remaining: nil, limit: nil))
        XCTAssertEqual(GameBoardControlRowView.dungeonTurnValueText(remaining: nil, limit: nil), "制限なし")
        XCTAssertEqual(GameBoardControlRowView.dungeonTurnAccessibilityValue(remaining: nil, limit: nil), "制限なし")
    }

    func testDungeonTurnAccessibilityIncludesLimitAndRemaining() {
        XCTAssertEqual(GameBoardControlRowView.dungeonTurnValueText(remaining: 12, limit: 18), "残り 12 / 18")
        XCTAssertEqual(GameBoardControlRowView.dungeonTurnAccessibilityValue(remaining: 12, limit: 18), "18手中12手残り")
    }

    func testDungeonTurnsBecomeCriticalAtQuarterRemaining() {
        XCTAssertFalse(GameBoardControlRowView.isCriticalDungeonTurns(remaining: 5, limit: 18))
        XCTAssertTrue(GameBoardControlRowView.isCriticalDungeonTurns(remaining: 4, limit: 18))
        XCTAssertTrue(GameBoardControlRowView.isCriticalDungeonTurns(remaining: 0, limit: 18))
    }
}
