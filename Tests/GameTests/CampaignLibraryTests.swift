import XCTest
@testable import Game

/// キャンペーン関連の定義を確認するテスト
final class CampaignLibraryTests: XCTestCase {
    func testChoiceDeckPresetConfigurationsRemainAvailable() {
        let kingAndKnightBaseSet = Set(MoveCard.standardSet.filter { $0.isKingType || $0.isKnightType })
        let presets: [(GameDeckPreset, Set<MoveCard>)] = [
            (.standardLight, Set(MoveCard.standardSet)),
            (.kingAndKnightBasic, kingAndKnightBaseSet),
            (.kingAndKnightWithOrthogonalChoices, kingAndKnightBaseSet.union([.kingUpOrDown, .kingLeftOrRight])),
            (.kingAndKnightWithDiagonalChoices, kingAndKnightBaseSet.union([
                .kingUpwardDiagonalChoice,
                .kingRightDiagonalChoice,
                .kingDownwardDiagonalChoice,
                .kingLeftDiagonalChoice
            ])),
            (.kingAndKnightWithKnightChoices, kingAndKnightBaseSet.union([
                .knightUpwardChoice,
                .knightRightwardChoice,
                .knightDownwardChoice,
                .knightLeftwardChoice
            ])),
            (.kingAndKnightWithAllChoices, kingAndKnightBaseSet.union([
                .kingUpOrDown,
                .kingLeftOrRight,
                .kingUpwardDiagonalChoice,
                .kingRightDiagonalChoice,
                .kingDownwardDiagonalChoice,
                .kingLeftDiagonalChoice,
                .knightUpwardChoice,
                .knightRightwardChoice,
                .knightDownwardChoice,
                .knightLeftwardChoice
            ])),
            (.kingPlusKnightOnly, [
                .kingUp,
                .kingRight,
                .kingDown,
                .kingLeft,
                .knightUp2Right1,
                .knightUp2Left1,
                .knightDown2Right1,
                .knightDown2Left1
            ]),
            (.directionChoice, Set(MoveCard.standardSet).union([.kingUpOrDown, .kingLeftOrRight])),
            (.directionalRayFocus, Set(MoveCard.directionalRayCards).union([
                .kingUp,
                .kingRight,
                .kingDown,
                .kingLeft
            ])),
            (.standardWithOrthogonalChoices, Set(MoveCard.standardSet).union([.kingUpOrDown, .kingLeftOrRight])),
            (.standardWithDiagonalChoices, Set(MoveCard.standardSet).union([
                .kingUpwardDiagonalChoice,
                .kingRightDiagonalChoice,
                .kingDownwardDiagonalChoice,
                .kingLeftDiagonalChoice
            ])),
            (.standardWithKnightChoices, Set(MoveCard.standardSet).union([
                .knightUpwardChoice,
                .knightRightwardChoice,
                .knightDownwardChoice,
                .knightLeftwardChoice
            ])),
            (.standardWithAllChoices, Set(MoveCard.standardSet).union([
                .kingUpOrDown,
                .kingLeftOrRight,
                .kingUpwardDiagonalChoice,
                .kingRightDiagonalChoice,
                .kingDownwardDiagonalChoice,
                .kingLeftDiagonalChoice,
                .knightUpwardChoice,
                .knightRightwardChoice,
                .knightDownwardChoice,
                .knightLeftwardChoice
            ])),
            (.fixedWarpSpecialized, [
                .kingUp,
                .kingRight,
                .kingDown,
                .kingLeft,
                .knightUp2Right1,
                .knightUp2Left1,
                .knightDown2Right1,
                .knightDown2Left1,
                .fixedWarp
            ]),
            (.superWarpHighFrequency, Set(MoveCard.standardSet).union([.superWarp])),
            (.standardWithWarpCards, Set(MoveCard.standardSet).union([.fixedWarp, .superWarp]))
        ]

        for (preset, expectedMoves) in presets {
            XCTAssertEqual(Set(preset.configuration.allowedMoves), expectedMoves, "\(preset.displayName) のカード構成が想定と異なります")
        }
    }

    func testCampaignIsFullyConvertedToTargetCollection() {
        let library = CampaignLibrary.shared

        XCTAssertEqual(library.chapters.count, 8)
        XCTAssertEqual(library.allStages.count, 64)

        let expectedGoalRanges: [Int: ClosedRange<Int>] = [
            1: 3...6,
            2: 6...9,
            3: 8...11,
            4: 8...11,
            5: 10...13,
            6: 10...14,
            7: 10...14,
            8: 10...14
        ]

        for chapter in library.chapters {
            XCTAssertEqual(chapter.stages.count, 8, "第\(chapter.id)章は8ステージ構成を維持します")
            guard let range = expectedGoalRanges[chapter.id] else {
                XCTFail("想定外の章 \(chapter.id) が含まれています")
                continue
            }

            for stage in chapter.stages {
                XCTAssertTrue(stage.regulation.handSize == 5)
                XCTAssertTrue(stage.regulation.nextPreviewCount == 3)
                XCTAssertTrue(stage.regulation.allowsStacking)
                XCTAssertTrue(stage.regulation.toggleTilePoints.isEmpty, "\(stage.displayCode) では旧トグルギミックを使いません")
                XCTAssertTrue(stage.regulation.additionalVisitRequirements.isEmpty, "\(stage.displayCode) では全踏破用の追加踏破条件を使いません")
                XCTAssertEqual(stage.regulation.penalties.manualRedrawPenaltyCost, 0)
                XCTAssertEqual(stage.regulation.penalties.deadlockPenaltyCost, 0)

                guard case .targetCollection(let goalCount) = stage.regulation.completionRule else {
                    XCTFail("\(stage.displayCode) が目的地制に変換されていません")
                    continue
                }
                XCTAssertTrue(range.contains(goalCount), "\(stage.displayCode) の目的地数 \(goalCount) が章の難度範囲外です")
            }
        }
    }

    func testCampaignUnlockFlowRemainsSequentialByChapter() {
        let library = CampaignLibrary.shared

        for chapter in library.chapters {
            for stage in chapter.stages {
                if chapter.id == 1 && stage.id.index == 1 {
                    XCTAssertEqual(stage.unlockRequirement, .always)
                } else if stage.id.index == 1 {
                    XCTAssertEqual(stage.unlockRequirement, .chapterTotalStars(chapter: chapter.id - 1, minimum: 12))
                } else {
                    XCTAssertEqual(
                        stage.unlockRequirement,
                        .stageClear(CampaignStageID(chapter: chapter.id, index: stage.id.index - 1))
                    )
                }
            }
        }
    }

    func testCampaignUsesFocusObjectivesInsteadOfPenaltyObjectives() {
        let stages = CampaignLibrary.shared.allStages

        XCTAssertTrue(stages.contains { stage in
            if case .finishWithFocusAtMost = stage.secondaryObjective { return true }
            return false
        })
        XCTAssertTrue(stages.contains { stage in
            if case .finishWithFocusAtMostAndWithinMoves = stage.secondaryObjective { return true }
            return false
        })
        XCTAssertFalse(stages.contains { stage in
            switch stage.secondaryObjective {
            case .finishWithPenaltyAtMost, .finishWithPenaltyAtMostAndWithinMoves:
                return true
            default:
                return false
            }
        })
    }

    func testLateCampaignKeepsObstacleAndWarpLearningBeats() {
        let library = CampaignLibrary.shared
        let chapter5 = library.chapters.first { $0.id == 5 }?.stages ?? []
        let chapter7 = library.chapters.first { $0.id == 7 }?.stages ?? []
        let chapter8 = library.chapters.first { $0.id == 8 }?.stages ?? []

        XCTAssertTrue(chapter5.allSatisfy { !$0.regulation.impassableTilePoints.isEmpty })
        XCTAssertTrue(chapter7.contains { !$0.regulation.warpTilePairs.isEmpty })
        XCTAssertTrue(chapter8.contains { !$0.regulation.fixedWarpCardTargets.isEmpty })
        XCTAssertTrue(chapter8.contains { $0.regulation.deckPreset == .superWarpHighFrequency })
        XCTAssertTrue(chapter8.contains { $0.regulation.deckPreset == .standardWithWarpCards })
    }

    func testFixedSpawnDoesNotOverlapImpassableTiles() {
        for stage in CampaignLibrary.shared.allStages {
            switch stage.regulation.spawnRule {
            case .fixed(let spawnPoint):
                XCTAssertFalse(
                    stage.regulation.impassableTilePoints.contains(spawnPoint),
                    "ステージ \(stage.displayCode) の固定スポーンが障害物マスと重なっています"
                )
            case .chooseAnyAfterPreview:
                continue
            }
        }
    }
}
