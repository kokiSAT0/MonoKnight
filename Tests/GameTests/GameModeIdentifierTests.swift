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
        XCTAssertEqual(mode.boardSize, 8)
        XCTAssertTrue(mode.requiresSpawnSelection)
        XCTAssertTrue(mode.usesTargetCollection)
        XCTAssertEqual(mode.targetGoalCount, 20)
        XCTAssertEqual(mode.deckPreset, .targetLabAllIn)
        XCTAssertFalse(mode.isLeaderboardEligible)
        XCTAssertFalse(mode.isCampaignStage)
        XCTAssertEqual(mode.tileEffects[GridPoint(x: 0, y: 0)], .warp(pairID: "lab_warp", destination: GridPoint(x: 7, y: 7)))
        XCTAssertEqual(mode.tileEffects[GridPoint(x: 7, y: 7)], .warp(pairID: "lab_warp", destination: GridPoint(x: 0, y: 0)))
        XCTAssertEqual(mode.tileEffects[GridPoint(x: 2, y: 5)], .shuffleHand)
        XCTAssertEqual(mode.tileEffects[GridPoint(x: 5, y: 2)], .boost)
        XCTAssertEqual(mode.tileEffects[GridPoint(x: 2, y: 2)], .slow)
        XCTAssertEqual(mode.tileEffects[GridPoint(x: 0, y: 7)], .nextRefresh)
        XCTAssertEqual(mode.tileEffects[GridPoint(x: 7, y: 0)], .freeFocus)
        XCTAssertEqual(mode.tileEffects[GridPoint(x: 3, y: 0)], .preserveCard)
        XCTAssertEqual(mode.tileEffects[GridPoint(x: 4, y: 4)], .draft)
        XCTAssertEqual(mode.tileEffects[GridPoint(x: 5, y: 5)], .overload)
        XCTAssertEqual(mode.tileEffects[GridPoint(x: 1, y: 6)], .targetSwap)
        XCTAssertEqual(mode.tileEffects[GridPoint(x: 6, y: 1)], .openGate(target: GridPoint(x: 6, y: 4)))
        XCTAssertTrue(mode.impassableTilePoints.contains(GridPoint(x: 6, y: 4)))
        XCTAssertEqual(
            mode.fixedWarpCardTargets[.fixedWarp],
            [
                GridPoint(x: 0, y: 0),
                GridPoint(x: 3, y: 0),
                GridPoint(x: 7, y: 0),
                GridPoint(x: 0, y: 3),
                GridPoint(x: 7, y: 3),
                GridPoint(x: 0, y: 7),
                GridPoint(x: 3, y: 7),
                GridPoint(x: 7, y: 7),
            ]
        )
    }

    func testTargetLabDefaultExperimentSettingsEnableAllGroupsAndTiles() {
        let settings = TargetLabExperimentSettings.default

        XCTAssertEqual(settings.enabledCardGroups, Set(TargetLabCardGroup.allCases))
        XCTAssertEqual(settings.enabledTileKinds, Set(TargetLabTileKind.allCases))
        XCTAssertTrue(settings.hasPlayableCards)
    }

    func testTargetLabModeFiltersDeckByEnabledCardGroups() {
        let settings = TargetLabExperimentSettings(
            enabledCardGroups: [.standard, .warp],
            enabledTileKinds: Set(TargetLabTileKind.allCases)
        )
        let mode = GameMode.targetLab(settings: settings)
        let allowedMoves = Set(mode.deckConfiguration.allowedMoves)

        XCTAssertTrue(Set(TargetLabCardGroup.standard.cards).isSubset(of: allowedMoves))
        XCTAssertTrue(Set(TargetLabCardGroup.warp.cards).isSubset(of: allowedMoves))
        XCTAssertFalse(allowedMoves.contains(.kingUpOrDown))
        XCTAssertFalse(allowedMoves.contains(.rayRight))
    }

    func testTargetLabModeRemovesWarpCardsAndFixedWarpTargetsWhenWarpGroupDisabled() {
        let settings = TargetLabExperimentSettings(
            enabledCardGroups: [.standard],
            enabledTileKinds: Set(TargetLabTileKind.allCases)
        )
        let mode = GameMode.targetLab(settings: settings)
        let allowedMoves = Set(mode.deckConfiguration.allowedMoves)

        XCTAssertFalse(allowedMoves.contains(.fixedWarp))
        XCTAssertFalse(allowedMoves.contains(.superWarp))
        XCTAssertEqual(mode.fixedWarpCardTargets[.fixedWarp], nil)
    }

    func testTargetLabModeFiltersTileKinds() {
        let settings = TargetLabExperimentSettings(
            enabledCardGroups: Set(TargetLabCardGroup.allCases),
            enabledTileKinds: [.boost, .slow]
        )
        let mode = GameMode.targetLab(settings: settings)

        XCTAssertEqual(mode.tileEffects[GridPoint(x: 5, y: 2)], .boost)
        XCTAssertEqual(mode.tileEffects[GridPoint(x: 2, y: 2)], .slow)
        XCTAssertNil(mode.tileEffects[GridPoint(x: 0, y: 0)])
        XCTAssertNil(mode.tileEffects[GridPoint(x: 7, y: 7)])
        XCTAssertNil(mode.tileEffects[GridPoint(x: 2, y: 5)])
        XCTAssertNil(mode.tileEffects[GridPoint(x: 0, y: 7)])
        XCTAssertNil(mode.tileEffects[GridPoint(x: 4, y: 4)])
        XCTAssertNil(mode.tileEffects[GridPoint(x: 1, y: 6)])
        XCTAssertNil(mode.tileEffects[GridPoint(x: 6, y: 1)])
    }

    func testTargetLabModeRemovesDraftTileWhenDraftDisabled() {
        var enabledTileKinds = Set(TargetLabTileKind.allCases)
        enabledTileKinds.remove(.draft)
        let settings = TargetLabExperimentSettings(
            enabledCardGroups: Set(TargetLabCardGroup.allCases),
            enabledTileKinds: enabledTileKinds
        )
        let mode = GameMode.targetLab(settings: settings)

        XCTAssertNil(mode.tileEffects[GridPoint(x: 4, y: 4)])
        XCTAssertEqual(mode.tileEffects[GridPoint(x: 5, y: 2)], .boost)
    }

    func testTargetLabModeRemovesOverloadTileWhenOverloadDisabled() {
        var enabledTileKinds = Set(TargetLabTileKind.allCases)
        enabledTileKinds.remove(.overload)
        let settings = TargetLabExperimentSettings(
            enabledCardGroups: Set(TargetLabCardGroup.allCases),
            enabledTileKinds: enabledTileKinds
        )
        let mode = GameMode.targetLab(settings: settings)

        XCTAssertNil(mode.tileEffects[GridPoint(x: 5, y: 5)])
        XCTAssertEqual(mode.tileEffects[GridPoint(x: 4, y: 4)], .draft)
    }

    func testTargetLabModeRemovesTargetSwapTileWhenTargetSwapDisabled() {
        var enabledTileKinds = Set(TargetLabTileKind.allCases)
        enabledTileKinds.remove(.targetSwap)
        let settings = TargetLabExperimentSettings(
            enabledCardGroups: Set(TargetLabCardGroup.allCases),
            enabledTileKinds: enabledTileKinds
        )
        let mode = GameMode.targetLab(settings: settings)

        XCTAssertNil(mode.tileEffects[GridPoint(x: 1, y: 6)])
        XCTAssertEqual(mode.tileEffects[GridPoint(x: 5, y: 5)], .overload)
    }

    func testTargetLabModeRemovesOpenGateTileAndObstacleWhenOpenGateDisabled() {
        var enabledTileKinds = Set(TargetLabTileKind.allCases)
        enabledTileKinds.remove(.openGate)
        let settings = TargetLabExperimentSettings(
            enabledCardGroups: Set(TargetLabCardGroup.allCases),
            enabledTileKinds: enabledTileKinds
        )
        let mode = GameMode.targetLab(settings: settings)

        XCTAssertNil(mode.tileEffects[GridPoint(x: 6, y: 1)])
        XCTAssertFalse(mode.impassableTilePoints.contains(GridPoint(x: 6, y: 4)))
        XCTAssertEqual(mode.tileEffects[GridPoint(x: 1, y: 6)], .targetSwap)
    }

    func testTargetLabExperimentSettingsCodingIgnoresUnknownValuesAndRecoversEmptyCards() throws {
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
