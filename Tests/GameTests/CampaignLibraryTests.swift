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
                XCTAssertEqual(stage.regulation.boardSize, 8, "\(stage.displayCode) はキャンペーン共通の 8×8 盤を使います")
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
                assertCampaignCoordinatesAreInsideBoard(stage)
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
                    XCTAssertEqual(
                        stage.unlockRequirement,
                        .stageClear(CampaignStageID(chapter: chapter.id - 1, index: 8))
                    )
                } else {
                    XCTAssertEqual(
                        stage.unlockRequirement,
                        .stageClear(CampaignStageID(chapter: chapter.id, index: stage.id.index - 1))
                    )
                }
            }
        }
    }

    func testCampaignLibraryResolvesNextStageInDefinitionOrder() throws {
        let library = CampaignLibrary.shared

        let stage12 = try XCTUnwrap(library.nextStage(after: CampaignStageID(chapter: 1, index: 1)))
        let stage21 = try XCTUnwrap(library.nextStage(after: CampaignStageID(chapter: 1, index: 8)))
        let finalNext = library.nextStage(after: CampaignStageID(chapter: 8, index: 8))

        XCTAssertEqual(stage12.id, CampaignStageID(chapter: 1, index: 2))
        XCTAssertEqual(stage21.id, CampaignStageID(chapter: 2, index: 1))
        XCTAssertNil(finalNext)
    }

    func testCampaignDoesNotUseStarGateUnlocks() {
        for stage in CampaignLibrary.shared.allStages {
            switch stage.unlockRequirement {
            case .chapterTotalStars, .totalStars:
                XCTFail("\(stage.displayCode) はスターゲートではなくクリア進行で解放します")
            case .always, .stageClear:
                continue
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

    func testEarlyCampaignIntroducesVisibleNewElementsByStage22() {
        let library = CampaignLibrary.shared
        let stage21 = library.stage(with: CampaignStageID(chapter: 2, index: 1))
        let stage22 = library.stage(with: CampaignStageID(chapter: 2, index: 2))

        XCTAssertEqual(stage21?.regulation.deckPreset, .standardWithOrthogonalChoices)
        XCTAssertTrue(
            stage22?.regulation.tileEffectOverrides.values.containsEffect(.freeFocus) == true,
            "2-2 までに視覚的に分かる補助要素を出し、新要素の実感を作ります"
        )
        XCTAssertEqual(stage22?.regulation.spawnRule, .chooseAnyAfterPreview)
    }

    private func assertCampaignCoordinatesAreInsideBoard(
        _ stage: CampaignStage,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let boardSize = stage.regulation.boardSize
        for point in stage.regulation.impassableTilePoints {
            XCTAssertTrue(point.isInside(boardSize: boardSize), "\(stage.displayCode) の障害物 \(point) が盤外です", file: file, line: line)
        }
        for (point, effect) in stage.regulation.tileEffectOverrides {
            XCTAssertTrue(point.isInside(boardSize: boardSize), "\(stage.displayCode) の特殊マス \(point) が盤外です", file: file, line: line)
            if case .openGate(let target) = effect {
                XCTAssertTrue(target.isInside(boardSize: boardSize), "\(stage.displayCode) の開門先 \(target) が盤外です", file: file, line: line)
                XCTAssertTrue(stage.regulation.impassableTilePoints.contains(target), "\(stage.displayCode) の開門先 \(target) は障害物として配置されている必要があります", file: file, line: line)
            }
        }
        for points in stage.regulation.warpTilePairs.values {
            for point in points {
                XCTAssertTrue(point.isInside(boardSize: boardSize), "\(stage.displayCode) のワープ \(point) が盤外です", file: file, line: line)
            }
        }
        for points in stage.regulation.fixedWarpCardTargets.values {
            for point in points {
                XCTAssertTrue(point.isInside(boardSize: boardSize), "\(stage.displayCode) の固定ワープ先 \(point) が盤外です", file: file, line: line)
            }
        }
    }

    func testChapter2ExpandsChoiceCardsBeforeChapter3Applications() {
        let chapter2Presets = CampaignLibrary.shared.chapters.first { $0.id == 2 }?.stages.map(\.regulation.deckPreset) ?? []
        let chapter3 = CampaignLibrary.shared.chapters.first { $0.id == 3 }

        XCTAssertTrue(chapter2Presets.contains(.standardWithOrthogonalChoices))
        XCTAssertTrue(chapter2Presets.contains(.standardWithDiagonalChoices))
        XCTAssertTrue(chapter2Presets.contains(.standardWithKnightChoices))
        XCTAssertTrue(chapter2Presets.contains(.standardWithAllChoices))
        XCTAssertEqual(chapter3?.title, "選択カード応用")
    }

    func testCampaignCoversTargetLabCardGroupsAndTileEffects() {
        let stages = CampaignLibrary.shared.allStages
        let allowedMovesByStage = stages.map { $0.regulation.deckPreset.configuration.allowedMoves }
        let allAllowedMoves = Set(allowedMovesByStage.flatMap { $0 })

        XCTAssertFalse(allAllowedMoves.intersection(MoveCard.standardSet).isEmpty)
        XCTAssertTrue(allAllowedMoves.contains(.kingUpOrDown) || allAllowedMoves.contains(.kingLeftOrRight))
        XCTAssertFalse(allAllowedMoves.intersection(MoveCard.directionalRayCards).isEmpty)
        XCTAssertTrue(allAllowedMoves.contains(.fixedWarp) || allAllowedMoves.contains(.superWarp))
        XCTAssertFalse(allAllowedMoves.intersection(MoveCard.targetAssistCards).isEmpty)
        XCTAssertFalse(allAllowedMoves.intersection(MoveCard.effectAssistCards).isEmpty)

        let allEffects = stages.flatMap { Array($0.regulation.resolvedTileEffects.values) }
        XCTAssertTrue(allEffects.containsEffect(.warp))
        XCTAssertTrue(allEffects.containsEffect(.shuffleHand))
        XCTAssertTrue(allEffects.containsEffect(.boost))
        XCTAssertTrue(allEffects.containsEffect(.slow))
        XCTAssertTrue(allEffects.containsEffect(.nextRefresh))
        XCTAssertTrue(allEffects.containsEffect(.freeFocus))
        XCTAssertTrue(allEffects.containsEffect(.preserveCard))
        XCTAssertTrue(allEffects.containsEffect(.draft))
        XCTAssertTrue(allEffects.containsEffect(.overload))
        XCTAssertTrue(allEffects.containsEffect(.targetSwap))
        XCTAssertTrue(allEffects.containsEffect(.openGate))
    }

    func testLateCampaignKeepsObstacleAndWarpLearningBeats() {
        let library = CampaignLibrary.shared
        let chapter5 = library.chapters.first { $0.id == 5 }?.stages ?? []
        let chapter6 = library.chapters.first { $0.id == 6 }?.stages ?? []
        let chapter7 = library.chapters.first { $0.id == 7 }?.stages ?? []
        let chapter8 = library.chapters.first { $0.id == 8 }?.stages ?? []

        XCTAssertTrue(chapter5.allSatisfy { !$0.regulation.impassableTilePoints.isEmpty })
        XCTAssertTrue(chapter5.contains { stage in
            stage.regulation.tileEffectOverrides.values.containsEffect(.openGate)
        })
        XCTAssertTrue(chapter6.contains { stage in
            stage.regulation.tileEffectOverrides.values.containsEffect(.boost)
        })
        XCTAssertTrue(chapter6.contains { stage in
            stage.regulation.tileEffectOverrides.values.containsEffect(.slow)
        })
        XCTAssertTrue(chapter6.contains { stage in
            stage.regulation.tileEffectOverrides.values.containsEffect(.overload)
        })
        XCTAssertTrue(chapter7.contains { !$0.regulation.warpTilePairs.isEmpty })
        XCTAssertTrue(chapter7.contains { stage in
            stage.regulation.tileEffectOverrides.values.containsEffect(.targetSwap)
        })
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

private enum TileEffectKind {
    case warp
    case shuffleHand
    case boost
    case slow
    case nextRefresh
    case freeFocus
    case preserveCard
    case draft
    case overload
    case targetSwap
    case openGate
}

private extension Sequence where Element == TileEffect {
    func containsEffect(_ kind: TileEffectKind) -> Bool {
        contains { effect in
            switch (kind, effect) {
            case (.warp, .warp(_, _)),
                 (.shuffleHand, .shuffleHand),
                 (.boost, .boost),
                 (.slow, .slow),
                 (.nextRefresh, .nextRefresh),
                 (.freeFocus, .freeFocus),
                 (.preserveCard, .preserveCard),
                 (.draft, .draft),
                 (.overload, .overload),
                 (.targetSwap, .targetSwap),
                 (.openGate, .openGate(_)):
                return true
            default:
                return false
            }
        }
    }
}
