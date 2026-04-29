import XCTest
@testable import Game

final class GameModeIdentifierTests: XCTestCase {
    func testScoreSubmissionIdentifierMapsDailyPlayModesToLeaderboardModes() {
        XCTAssertEqual(GameMode.Identifier.dailyFixed.scoreSubmissionIdentifier, .dailyFixedChallenge)
        XCTAssertEqual(GameMode.Identifier.dailyRandom.scoreSubmissionIdentifier, .dailyRandomChallenge)
    }

    func testScoreSubmissionIdentifierPreservesExistingLeaderboardModes() {
        XCTAssertEqual(GameMode.Identifier.standard5x5.scoreSubmissionIdentifier, .standard5x5)
        XCTAssertEqual(GameMode.Identifier.classicalChallenge.scoreSubmissionIdentifier, .classicalChallenge)
        XCTAssertEqual(GameMode.Identifier.dailyFixedChallenge.scoreSubmissionIdentifier, .dailyFixedChallenge)
        XCTAssertEqual(GameMode.Identifier.dailyRandomChallenge.scoreSubmissionIdentifier, .dailyRandomChallenge)
        XCTAssertNil(GameMode.Identifier.freeCustom.scoreSubmissionIdentifier)
        XCTAssertNil(GameMode.Identifier.campaignStage.scoreSubmissionIdentifier)
        XCTAssertNil(GameMode.Identifier.targetLab.scoreSubmissionIdentifier)
    }

    func testPlayModeIdentifierNormalizesLeaderboardIdentifiersBackToPlayableModes() {
        XCTAssertEqual(GameMode.Identifier.dailyFixedChallenge.playModeIdentifier, .dailyFixed)
        XCTAssertEqual(GameMode.Identifier.dailyRandomChallenge.playModeIdentifier, .dailyRandom)
        XCTAssertEqual(GameMode.Identifier.standard5x5.playModeIdentifier, .standard5x5)
        XCTAssertEqual(GameMode.Identifier.targetLab.playModeIdentifier, .targetLab)
    }

    func testTargetLabModeUsesExperimentRulesWithoutLeaderboard() {
        let mode = GameMode.targetLab

        XCTAssertEqual(mode.identifier, .targetLab)
        XCTAssertEqual(mode.boardSize, 5)
        XCTAssertTrue(mode.requiresSpawnSelection)
        XCTAssertTrue(mode.usesTargetCollection)
        XCTAssertEqual(mode.targetGoalCount, 12)
        XCTAssertEqual(mode.deckPreset, .targetLabAllIn)
        XCTAssertFalse(mode.isLeaderboardEligible)
        XCTAssertFalse(mode.isCampaignStage)
    }

    func testCampaignLibraryStageLookupReturnsStageForEveryRegisteredID() {
        let library = CampaignLibrary.shared
        for stage in library.allStages {
            let lookedUpStage = library.stage(with: stage.id)
            XCTAssertEqual(lookedUpStage, stage, "ステージ \(stage.id.displayCode) を再取得できません")
        }
    }

    func testCampaignStageMakeGameModePreservesCampaignMetadataAndRegulation() {
        guard let stage = CampaignLibrary.shared.stage(with: CampaignStageID(chapter: 1, index: 1)) else {
            return XCTFail("検証対象ステージが見つかりません")
        }

        let mode = stage.makeGameMode()

        XCTAssertEqual(mode.identifier, .campaignStage)
        XCTAssertEqual(mode.campaignMetadataSnapshot?.stageID, stage.id)
        XCTAssertEqual(mode.regulationSnapshot, stage.regulation)
        XCTAssertFalse(mode.isLeaderboardEligible)
    }
}
