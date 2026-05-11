import XCTest
@testable import Game

final class DungeonFatigueIndicatorStateTests: XCTestCase {
    func testDungeonFatigueIndicatorIsHiddenWhileTurnsRemain() throws {
        let core = GameCore(mode: .dungeonPlaceholder)
        let limit = try XCTUnwrap(core.effectiveDungeonTurnLimit)

        core.overrideMetricsForTesting(moveCount: limit - 1, penaltyCount: 0, elapsedSeconds: 0)

        XCTAssertNil(core.dungeonFatigueIndicatorState)
    }

    func testDungeonFatigueIndicatorShowsEmptyPipsWhenTurnsReachZero() throws {
        let core = GameCore(mode: .dungeonPlaceholder)
        let limit = try XCTUnwrap(core.effectiveDungeonTurnLimit)

        core.overrideMetricsForTesting(moveCount: limit, penaltyCount: 0, elapsedSeconds: 0)

        XCTAssertEqual(
            core.dungeonFatigueIndicatorState,
            DungeonFatigueIndicatorState(filledCount: 0, totalCount: 3, isDamageStep: false)
        )
    }

    func testDungeonFatigueIndicatorMarksFirstOvertimeTurnAsDamageStep() throws {
        let core = GameCore(mode: .dungeonPlaceholder)
        let limit = try XCTUnwrap(core.effectiveDungeonTurnLimit)

        core.overrideMetricsForTesting(moveCount: limit + 1, penaltyCount: 0, elapsedSeconds: 0)

        XCTAssertEqual(
            core.dungeonFatigueIndicatorState,
            DungeonFatigueIndicatorState(filledCount: 3, totalCount: 3, isDamageStep: true)
        )
    }

    func testDungeonFatigueIndicatorAdvancesBetweenDamageSteps() throws {
        let core = GameCore(mode: .dungeonPlaceholder)
        let limit = try XCTUnwrap(core.effectiveDungeonTurnLimit)

        core.overrideMetricsForTesting(moveCount: limit + 2, penaltyCount: 0, elapsedSeconds: 0)
        XCTAssertEqual(
            core.dungeonFatigueIndicatorState,
            DungeonFatigueIndicatorState(filledCount: 1, totalCount: 3, isDamageStep: false)
        )

        core.overrideMetricsForTesting(moveCount: limit + 3, penaltyCount: 0, elapsedSeconds: 0)
        XCTAssertEqual(
            core.dungeonFatigueIndicatorState,
            DungeonFatigueIndicatorState(filledCount: 2, totalCount: 3, isDamageStep: false)
        )
    }

    func testDungeonFatigueIndicatorMarksFourthOvertimeTurnAsDamageStep() throws {
        let core = GameCore(mode: .dungeonPlaceholder)
        let limit = try XCTUnwrap(core.effectiveDungeonTurnLimit)

        core.overrideMetricsForTesting(moveCount: limit + 4, penaltyCount: 0, elapsedSeconds: 0)

        XCTAssertEqual(
            core.dungeonFatigueIndicatorState,
            DungeonFatigueIndicatorState(filledCount: 3, totalCount: 3, isDamageStep: true)
        )
    }
}
