import XCTest
@testable import Game

final class CampaignStagePresentationTests: XCTestCase {
    func testLegacyCampaignPresentationTypesStillFormatWithoutCrashing() {
        let regulation = GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standard,
            spawnRule: .fixed(GridPoint(x: 2, y: 2)),
            penalties: GameMode.PenaltySettings(
                deadlockPenaltyCost: 0,
                manualRedrawPenaltyCost: 0,
                manualDiscardPenaltyCost: 1,
                revisitPenaltyCost: 0
            ),
            completionRule: .targetCollection(goalCount: 4)
        )
        let stage = CampaignStage(
            id: CampaignStageID(chapter: 2, index: 3),
            title: "テストステージ",
            summary: "summary",
            regulation: regulation,
            secondaryObjective: .finishWithFocusAtMostAndWithinMoves(maxFocusCount: 2, maxMoves: 7),
            twoStarScoreTarget: 55,
            scoreTarget: 42,
            scoreTargetComparison: .lessThan,
            unlockRequirement: .chapterTotalStars(chapter: 2, minimum: 5)
        )
        let metrics = CampaignStageClearMetrics(
            moveCount: 4,
            penaltyCount: 1,
            focusCount: 1,
            elapsedSeconds: 25,
            totalMoveCount: 5,
            score: 370,
            hasRevisitedTile: false,
            capturedTargetCount: 4
        )

        XCTAssertEqual(stage.displayCode, "2-3")
        XCTAssertFalse(stage.secondaryObjectiveDescription?.isEmpty ?? true)
        XCTAssertFalse(stage.unlockDescription.isEmpty)
        XCTAssertEqual(stage.evaluateClear(with: metrics).earnedStars, 3)
    }
}
