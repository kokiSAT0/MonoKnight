import XCTest
@testable import Game

final class GameModeIdentifierTests: XCTestCase {
    func testFrozenModesKeepMinimumScoreSubmissionCompatibility() {
        XCTAssertEqual(GameMode.Identifier.dailyFixed.scoreSubmissionIdentifier, .dailyFixedChallenge)
        XCTAssertEqual(GameMode.Identifier.dailyRandom.scoreSubmissionIdentifier, .dailyRandomChallenge)
        XCTAssertEqual(GameMode.Identifier.dailyFixedChallenge.playModeIdentifier, .dailyFixed)
        XCTAssertEqual(GameMode.Identifier.dailyRandomChallenge.playModeIdentifier, .dailyRandom)

        XCTAssertEqual(GameMode.Identifier.standard5x5.scoreSubmissionIdentifier, .standard5x5)
        XCTAssertEqual(GameMode.Identifier.classicalChallenge.scoreSubmissionIdentifier, .classicalChallenge)
        XCTAssertNil(GameMode.Identifier.freeCustom.scoreSubmissionIdentifier)
        XCTAssertNil(GameMode.Identifier.campaignStage.scoreSubmissionIdentifier)
        XCTAssertNil(GameMode.Identifier.targetLab.scoreSubmissionIdentifier)
    }

    func testTargetLabStillBuildsAsFrozenExperimentMode() {
        let mode = GameMode.targetLab

        XCTAssertEqual(mode.identifier, .targetLab)
        XCTAssertEqual(mode.boardSize, 8)
        XCTAssertTrue(mode.requiresSpawnSelection)
        XCTAssertTrue(mode.usesTargetCollection)
        XCTAssertFalse(mode.isLeaderboardEligible)
        XCTAssertFalse(mode.deckConfiguration.allowedMoves.isEmpty)
        XCTAssertFalse(mode.tileEffects.isEmpty)
    }

    func testTargetLabSettingsDecodeLegacyRemovedGroupsWithoutCrashing() throws {
        let json = """
        {
          "enabledCardGroups": ["targetAssist", "effectAssist", "unknown"],
          "enabledTileKinds": ["boost", "unknownTile"]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(TargetLabExperimentSettings.self, from: json)

        XCTAssertEqual(decoded.enabledCardGroups, TargetLabExperimentSettings.default.enabledCardGroups)
        XCTAssertEqual(decoded.enabledTileKinds, [.boost])
    }

    func testLegacyCampaignStageIdentifierStillBuildsNonLeaderboardMode() throws {
        let stage = try XCTUnwrap(CampaignLibrary.shared.allStages.first)
        let mode = stage.makeGameMode()

        XCTAssertEqual(mode.identifier, .campaignStage)
        XCTAssertEqual(mode.campaignMetadataSnapshot?.stageID, stage.id)
        XCTAssertFalse(mode.isLeaderboardEligible)
    }
}
