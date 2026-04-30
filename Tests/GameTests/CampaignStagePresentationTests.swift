import XCTest
@testable import Game

final class CampaignStagePresentationTests: XCTestCase {
    func testPresentationStringsRemainStableAfterExtraction() {
        let regulation = GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standard,
            spawnRule: .fixed(GridPoint(x: 2, y: 2)),
            penalties: GameMode.PenaltySettings(
                deadlockPenaltyCost: 3,
                manualRedrawPenaltyCost: 2,
                manualDiscardPenaltyCost: 1,
                revisitPenaltyCost: 0
            )
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

        XCTAssertEqual(stage.displayCode, "2-3")
        XCTAssertEqual(stage.secondaryObjectiveDescription, "フォーカス 2 回以内かつ 7 手以内でクリア")
        XCTAssertEqual(stage.twoStarScoreTargetDescription, "スコア 55 pt 未満でクリア")
        XCTAssertEqual(stage.scoreTargetDescription, "スコア 42 pt 未満でクリア")
        XCTAssertEqual(stage.unlockDescription, "第2章でスターを合計 5 個集める")
    }

    func testScoreEvaluationUsesTwoScoreLines() {
        let regulation = GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standard,
            spawnRule: .fixed(GridPoint(x: 2, y: 2)),
            penalties: GameMode.PenaltySettings(
                deadlockPenaltyCost: 3,
                manualRedrawPenaltyCost: 2,
                manualDiscardPenaltyCost: 1,
                revisitPenaltyCost: 0
            )
        )
        let stage = CampaignStage(
            id: CampaignStageID(chapter: 1, index: 1),
            title: "評価テスト",
            summary: "summary",
            regulation: regulation,
            secondaryObjective: .finishWithFocusAtMostAndWithinMoves(maxFocusCount: 1, maxMoves: 5),
            twoStarScoreTarget: 40,
            scoreTarget: 30,
            scoreTargetComparison: .lessThanOrEqual,
            unlockRequirement: .always
        )
        let oneStarMetrics = CampaignStageClearMetrics(
            moveCount: 4,
            penaltyCount: 1,
            focusCount: 0,
            elapsedSeconds: 60,
            totalMoveCount: 5,
            score: 41,
            hasRevisitedTile: false,
            capturedTargetCount: 4
        )
        let twoStarMetrics = CampaignStageClearMetrics(
            moveCount: 4,
            penaltyCount: 1,
            focusCount: 1,
            elapsedSeconds: 25,
            totalMoveCount: 5,
            score: 40,
            hasRevisitedTile: false,
            capturedTargetCount: 4
        )
        let threeStarMetrics = CampaignStageClearMetrics(
            moveCount: 4,
            penaltyCount: 1,
            focusCount: 1,
            elapsedSeconds: 25,
            totalMoveCount: 5,
            score: 30,
            hasRevisitedTile: false,
            capturedTargetCount: 4
        )

        let oneStarEvaluation = stage.evaluateClear(with: oneStarMetrics)
        let twoStarEvaluation = stage.evaluateClear(with: twoStarMetrics)
        let threeStarEvaluation = stage.evaluateClear(with: threeStarMetrics)

        XCTAssertEqual(oneStarEvaluation.earnedStars, 1)
        XCTAssertFalse(oneStarEvaluation.achievedTwoStarScoreGoal)
        XCTAssertFalse(oneStarEvaluation.achievedThreeStarScoreGoal)

        XCTAssertEqual(twoStarEvaluation.earnedStars, 2)
        XCTAssertTrue(twoStarEvaluation.achievedTwoStarScoreGoal)
        XCTAssertFalse(twoStarEvaluation.achievedThreeStarScoreGoal)

        XCTAssertEqual(threeStarEvaluation.earnedStars, 3)
        XCTAssertTrue(threeStarEvaluation.achievedTwoStarScoreGoal)
        XCTAssertTrue(threeStarEvaluation.achievedThreeStarScoreGoal)
    }
}
