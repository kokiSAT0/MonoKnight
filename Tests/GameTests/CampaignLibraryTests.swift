import XCTest
@testable import Game

/// キャンペーン関連の定義を確認するテスト
final class CampaignLibraryTests: XCTestCase {
    /// ステージ検証用の期待値定義
    /// - Note: 必要なパラメータを網羅しつつ、不要な項目は既定値で省略できるようにする
    private struct StageExpectation {
        let title: String
        let boardSize: Int
        let deck: GameDeckPreset
        let spawn: GameMode.SpawnRule
        let penalties: GameMode.PenaltySettings
        let additional: [GridPoint: Int]
        let toggles: Set<GridPoint>
        let impassable: Set<GridPoint>
        let secondary: CampaignStage.SecondaryObjective
        let scoreTarget: Int
        let comparison: CampaignStage.ScoreTargetComparison
        let unlock: CampaignStageUnlockRequirement

        init(
            title: String,
            boardSize: Int,
            deck: GameDeckPreset,
            spawn: GameMode.SpawnRule,
            penalties: GameMode.PenaltySettings,
            secondary: CampaignStage.SecondaryObjective,
            scoreTarget: Int,
            comparison: CampaignStage.ScoreTargetComparison = .lessThanOrEqual,
            unlock: CampaignStageUnlockRequirement,
            additional: [GridPoint: Int] = [:],
            toggles: Set<GridPoint> = [],
            impassable: Set<GridPoint> = []
        ) {
            self.title = title
            self.boardSize = boardSize
            self.deck = deck
            self.spawn = spawn
            self.penalties = penalties
            self.additional = additional
            self.toggles = toggles
            self.impassable = impassable
            self.secondary = secondary
            self.scoreTarget = scoreTarget
            self.comparison = comparison
            self.unlock = unlock
        }
    }

    /// 選択カード系プリセットが期待通りの構成を返すことを確認する
    func testChoiceDeckPresetConfigurations() {
        let presets: [(GameDeckPreset, String, String, Set<MoveCard>)] = [
            (.standardLight, "スタンダード軽量構成", "長距離カード抑制型標準デッキ", Set(MoveCard.standardSet)),
            (
                .kingAndKnightBasic,
                "キング＋ナイト基礎構成",
                "キングと桂馬の基礎デッキ",
                Set(MoveCard.standardSet.filter { $0.isKingType || $0.isKnightType })
            ),
            (
                .kingPlusKnightOnly,
                "キング＋ナイト限定構成",
                "キングと桂馬の限定デッキ",
                Set([
                    .kingUp,
                    .kingRight,
                    .kingDown,
                    .kingLeft,
                    .knightUp2Right1,
                    .knightUp2Left1,
                    .knightDown2Right1,
                    .knightDown2Left1
                ])
            ),
            (.directionChoice, "選択式キング構成", "選択式キングカード入り", [.kingUpOrDown, .kingLeftOrRight]),
            (.standardWithOrthogonalChoices, "標準＋縦横選択キング構成", "標準＋上下左右選択キング", Set(MoveCard.standardSet).union([.kingUpOrDown, .kingLeftOrRight])),
            (.standardWithDiagonalChoices, "標準＋斜め選択キング構成", "標準＋斜め選択キング", Set(MoveCard.standardSet).union([
                .kingUpwardDiagonalChoice,
                .kingRightDiagonalChoice,
                .kingDownwardDiagonalChoice,
                .kingLeftDiagonalChoice
            ])),
            (.standardWithKnightChoices, "標準＋桂馬選択構成", "標準＋桂馬選択カード", Set(MoveCard.standardSet).union([
                .knightUpwardChoice,
                .knightRightwardChoice,
                .knightDownwardChoice,
                .knightLeftwardChoice
            ])),
            (.standardWithAllChoices, "標準＋全選択カード構成", "標準＋全選択カード", Set(MoveCard.standardSet).union([
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
            (.kingOrthogonalChoiceOnly, "上下左右選択キング構成", "上下左右の選択キング限定", [.kingUpOrDown, .kingLeftOrRight]),
            (.kingDiagonalChoiceOnly, "斜め選択キング構成", "斜め選択キング限定", [
                .kingUpwardDiagonalChoice,
                .kingRightDiagonalChoice,
                .kingDownwardDiagonalChoice,
                .kingLeftDiagonalChoice
            ]),
            (.knightChoiceOnly, "桂馬選択構成", "桂馬選択カード限定", [
                .knightUpwardChoice,
                .knightRightwardChoice,
                .knightDownwardChoice,
                .knightLeftwardChoice
            ]),
            (.allChoiceMixed, "選択カード総合構成", "選択カード総合ミックス", [
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
            ])
        ]

        for (preset, expectedName, expectedSummary, expectedMoves) in presets {
            XCTAssertEqual(preset.displayName, expectedName, "\(preset) の表示名が仕様と異なります")
            XCTAssertEqual(preset.summaryText, expectedSummary, "\(preset) の要約テキストが仕様と異なります")

            let configuration = preset.configuration
            let allowedMoves = Set(configuration.allowedMoves)
            XCTAssertTrue(expectedMoves.isSubset(of: allowedMoves), "\(preset) に必要なカードが含まれていません")

            // MARK: 標準セットを内包するプリセットは全カードを含んでいるか検証する
            let presetsRequiringStandard: Set<GameDeckPreset> = [
                .standardLight,
                .directionChoice,
                .standardWithOrthogonalChoices,
                .standardWithDiagonalChoices,
                .standardWithKnightChoices,
                .standardWithAllChoices
            ]
            if presetsRequiringStandard.contains(preset) {
                let standardMoves = Set(MoveCard.standardSet)
                XCTAssertTrue(standardMoves.isSubset(of: allowedMoves), "標準カードが欠落しています: \(preset)")
            }
        }
    }

    /// 第 1 章の 8 ステージがドキュメント記載の仕様へ更新されているか検証する
    func testCampaignStage1Definitions() {
        let library = CampaignLibrary.shared

        // MARK: 章 1 の取得とステージ数確認
        guard let chapter1 = library.chapters.first(where: { $0.id == 1 }) else {
            XCTFail("第1章の定義が見つかりません")
            return
        }
        XCTAssertEqual(chapter1.stages.count, 8, "第1章のステージ数が 8 に拡張されていません")

        // MARK: 期待値テーブル（スポーン・ペナルティ・スター条件など）
        let fixedSpawn3 = GameMode.SpawnRule.fixed(BoardGeometry.defaultSpawnPoint(for: 3))
        let fixedSpawn4 = GameMode.SpawnRule.fixed(BoardGeometry.defaultSpawnPoint(for: 4))
        let fixedSpawn5 = GameMode.SpawnRule.fixed(BoardGeometry.defaultSpawnPoint(for: 5))

        let expectations: [Int: (
            title: String,
            board: Int,
            deck: GameDeckPreset,
            spawn: GameMode.SpawnRule,
            penalties: GameMode.PenaltySettings,
            secondary: CampaignStage.SecondaryObjective,
            scoreTarget: Int,
            unlock: CampaignStageUnlockRequirement
        )] = [
            1: (
                title: "王将訓練",
                board: 3,
                deck: .kingOnly,
                spawn: fixedSpawn3,
                penalties: GameMode.PenaltySettings(deadlockPenaltyCost: 2, manualRedrawPenaltyCost: 2, manualDiscardPenaltyCost: 1, revisitPenaltyCost: 1),
                secondary: .finishWithinSeconds(maxSeconds: 60),
                scoreTarget: 300,
                unlock: .always
            ),
            2: (
                title: "ナイト初見",
                board: 3,
                deck: .kingPlusKnightOnly,
                spawn: fixedSpawn3,
                penalties: GameMode.PenaltySettings(deadlockPenaltyCost: 2, manualRedrawPenaltyCost: 2, manualDiscardPenaltyCost: 1, revisitPenaltyCost: 0),
                secondary: .finishWithPenaltyAtMost(maxPenaltyCount: 3),
                scoreTarget: 300,
                unlock: .stageClear(CampaignStageID(chapter: 1, index: 1))
            ),
            3: (
                title: "4×4基礎",
                board: 4,
                deck: .kingAndKnightBasic,
                spawn: fixedSpawn4,
                penalties: GameMode.PenaltySettings(deadlockPenaltyCost: 3, manualRedrawPenaltyCost: 1, manualDiscardPenaltyCost: 1, revisitPenaltyCost: 0),
                secondary: .finishWithinSeconds(maxSeconds: 60),
                scoreTarget: 400,
                unlock: .stageClear(CampaignStageID(chapter: 1, index: 2))
            ),
            4: (
                title: "4×4応用",
                board: 4,
                deck: .kingAndKnightBasic,
                spawn: .chooseAnyAfterPreview,
                penalties: GameMode.PenaltySettings(deadlockPenaltyCost: 3, manualRedrawPenaltyCost: 1, manualDiscardPenaltyCost: 1, revisitPenaltyCost: 0),
                secondary: .finishWithPenaltyAtMost(maxPenaltyCount: 5),
                scoreTarget: 400,
                unlock: .stageClear(CampaignStageID(chapter: 1, index: 3))
            ),
            5: (
                title: "4×4持久",
                board: 4,
                deck: .standardLight,
                spawn: fixedSpawn4,
                penalties: GameMode.PenaltySettings(deadlockPenaltyCost: 3, manualRedrawPenaltyCost: 2, manualDiscardPenaltyCost: 1, revisitPenaltyCost: 0),
                secondary: .finishWithinMoves(maxMoves: 30),
                scoreTarget: 400,
                unlock: .stageClear(CampaignStageID(chapter: 1, index: 4))
            ),
            6: (
                title: "4×4戦略",
                board: 4,
                deck: .kingAndKnightBasic,
                spawn: .chooseAnyAfterPreview,
                penalties: GameMode.PenaltySettings(deadlockPenaltyCost: 3, manualRedrawPenaltyCost: 2, manualDiscardPenaltyCost: 1, revisitPenaltyCost: 0),
                secondary: .finishWithPenaltyAtMost(maxPenaltyCount: 3),
                scoreTarget: 400,
                unlock: .stageClear(CampaignStageID(chapter: 1, index: 5))
            ),
            7: (
                title: "5×5導入",
                board: 5,
                deck: .standardLight,
                spawn: fixedSpawn5,
                penalties: GameMode.PenaltySettings(deadlockPenaltyCost: 3, manualRedrawPenaltyCost: 2, manualDiscardPenaltyCost: 1, revisitPenaltyCost: 0),
                secondary: .finishWithinMoves(maxMoves: 40),
                scoreTarget: 460,
                unlock: .stageClear(CampaignStageID(chapter: 1, index: 6))
            ),
            8: (
                title: "総合演習",
                board: 5,
                deck: .standardLight,
                spawn: .chooseAnyAfterPreview,
                penalties: GameMode.PenaltySettings(deadlockPenaltyCost: 3, manualRedrawPenaltyCost: 2, manualDiscardPenaltyCost: 1, revisitPenaltyCost: 0),
                secondary: .finishWithinMoves(maxMoves: 35),
                scoreTarget: 440,
                unlock: .stageClear(CampaignStageID(chapter: 1, index: 7))
            )
        ]

        for stage in chapter1.stages {
            guard let expectation = expectations[stage.id.index] else {
                XCTFail("第1章に想定外のステージ index=\(stage.id.index) が含まれています")
                continue
            }

            // MARK: タイトル・盤面サイズ・山札プリセットの検証
            XCTAssertEqual(stage.title, expectation.title, "1-\(stage.id.index) のタイトルが仕様と一致しません")
            XCTAssertEqual(stage.regulation.boardSize, expectation.board, "1-\(stage.id.index) の盤面サイズが仕様と一致しません")
            XCTAssertEqual(stage.regulation.deckPreset, expectation.deck, "1-\(stage.id.index) の山札プリセットが仕様と一致しません")

            // MARK: 共通レギュレーション（手札 5 / 先読み 3 / スタック可）
            XCTAssertEqual(stage.regulation.handSize, 5)
            XCTAssertEqual(stage.regulation.nextPreviewCount, 3)
            XCTAssertTrue(stage.regulation.allowsStacking)

            // MARK: スポーン方式・ペナルティ・スター条件・アンロック条件
            XCTAssertEqual(stage.regulation.spawnRule, expectation.spawn, "1-\(stage.id.index) のスポーン方式が仕様と一致しません")
            XCTAssertEqual(stage.regulation.penalties, expectation.penalties, "1-\(stage.id.index) のペナルティ設定が仕様と一致しません")
            XCTAssertEqual(stage.secondaryObjective, expectation.secondary, "1-\(stage.id.index) のセカンダリ条件が仕様と一致しません")
            XCTAssertEqual(stage.scoreTarget, expectation.scoreTarget, "1-\(stage.id.index) のスコア上限が仕様と一致しません")
            XCTAssertEqual(stage.scoreTargetComparison, .lessThan, "1-\(stage.id.index) のスコア比較方式は未満（lessThan）であるべきです")
            XCTAssertEqual(stage.unlockRequirement, expectation.unlock, "1-\(stage.id.index) のアンロック条件が仕様と一致しません")
        }
    }

    /// 第2章の 8 ステージが多重踏破仕様に沿っているか検証する
    func testCampaignStage2Definitions() {
        let library = CampaignLibrary.shared
        guard let chapter2 = library.chapters.first(where: { $0.id == 2 }) else {
            XCTFail("第2章の定義が見つかりません")
            return
        }

        XCTAssertEqual(chapter2.stages.count, 8, "第2章は 8 ステージ構成の想定です")

        // MARK: スポーン方式・ペナルティなどの共通パラメータを事前に用意
        let fixedSpawn4 = GameMode.SpawnRule.fixed(BoardGeometry.defaultSpawnPoint(for: 4))
        let chooseAny = GameMode.SpawnRule.chooseAnyAfterPreview
        let penalties = GameMode.PenaltySettings(deadlockPenaltyCost: 3, manualRedrawPenaltyCost: 1, manualDiscardPenaltyCost: 1, revisitPenaltyCost: 0)

        let expectations: [Int: StageExpectation] = [
            1: StageExpectation(
                title: "重踏チュートリアル",
                boardSize: 4,
                deck: .kingAndKnightBasic,
                spawn: fixedSpawn4,
                penalties: penalties,
                secondary: .finishWithPenaltyAtMost(maxPenaltyCount: 5),
                scoreTarget: 620,
                unlock: .chapterTotalStars(chapter: 1, minimum: 16),
                additional: [GridPoint(x: 1, y: 1): 2, GridPoint(x: 2, y: 2): 2]
            ),
            2: StageExpectation(
                title: "基礎演習",
                boardSize: 5,
                deck: .kingAndKnightBasic,
                spawn: chooseAny,
                penalties: penalties,
                secondary: .finishWithinMoves(maxMoves: 45),
                scoreTarget: 600,
                unlock: .stageClear(CampaignStageID(chapter: 2, index: 1)),
                additional: [GridPoint(x: 1, y: 1): 2, GridPoint(x: 3, y: 3): 2]
            ),
            3: StageExpectation(
                title: "三重踏み入門",
                boardSize: 5,
                deck: .kingAndKnightBasic,
                spawn: chooseAny,
                penalties: penalties,
                secondary: .finishWithinMoves(maxMoves: 42),
                scoreTarget: 590,
                unlock: .stageClear(CampaignStageID(chapter: 2, index: 2)),
                additional: [GridPoint(x: 2, y: 2): 3]
            ),
            4: StageExpectation(
                title: "複数三重踏み",
                boardSize: 5,
                deck: .kingAndKnightBasic,
                spawn: chooseAny,
                penalties: penalties,
                secondary: .finishWithPenaltyAtMost(maxPenaltyCount: 3),
                scoreTarget: 580,
                unlock: .stageClear(CampaignStageID(chapter: 2, index: 3)),
                additional: [GridPoint(x: 1, y: 1): 3, GridPoint(x: 3, y: 3): 3]
            ),
            5: StageExpectation(
                title: "中央集中",
                boardSize: 5,
                deck: .kingAndKnightBasic,
                spawn: chooseAny,
                penalties: penalties,
                secondary: .finishWithinMoves(maxMoves: 40),
                scoreTarget: 570,
                unlock: .stageClear(CampaignStageID(chapter: 2, index: 4)),
                additional: [GridPoint(x: 2, y: 2): 4]
            ),
            6: StageExpectation(
                title: "四重踏み分散",
                boardSize: 5,
                deck: .kingAndKnightBasic,
                spawn: chooseAny,
                penalties: penalties,
                secondary: .finishWithinSeconds(maxSeconds: 130),
                scoreTarget: 560,
                unlock: .stageClear(CampaignStageID(chapter: 2, index: 5)),
                additional: [GridPoint(x: 1, y: 1): 4, GridPoint(x: 3, y: 3): 4]
            ),
            7: StageExpectation(
                title: "複合課題",
                boardSize: 5,
                deck: .kingAndKnightBasic,
                spawn: chooseAny,
                penalties: penalties,
                secondary: .finishWithinMoves(maxMoves: 36),
                scoreTarget: 550,
                unlock: .stageClear(CampaignStageID(chapter: 2, index: 6)),
                additional: [GridPoint(x: 0, y: 0): 2, GridPoint(x: 2, y: 2): 3, GridPoint(x: 4, y: 4): 4]
            ),
            8: StageExpectation(
                title: "総合演習",
                boardSize: 5,
                deck: .kingAndKnightBasic,
                spawn: chooseAny,
                penalties: penalties,
                secondary: .finishWithinMoves(maxMoves: 34),
                scoreTarget: 540,
                unlock: .stageClear(CampaignStageID(chapter: 2, index: 7)),
                additional: [
                    GridPoint(x: 0, y: 0): 3,
                    GridPoint(x: 4, y: 0): 3,
                    GridPoint(x: 0, y: 4): 3,
                    GridPoint(x: 4, y: 4): 3
                ]
            )
        ]

        for stage in chapter2.stages {
            guard let expectation = expectations[stage.id.index] else {
                XCTFail("第2章に想定外のステージ index=\(stage.id.index) が含まれています")
                continue
            }

            XCTAssertEqual(stage.title, expectation.title)
            XCTAssertEqual(stage.regulation.boardSize, expectation.boardSize)
            XCTAssertEqual(stage.regulation.deckPreset, expectation.deck)
            XCTAssertEqual(stage.regulation.spawnRule, expectation.spawn)
            XCTAssertEqual(stage.regulation.penalties, expectation.penalties)
            XCTAssertEqual(stage.regulation.additionalVisitRequirements, expectation.additional)
            XCTAssertTrue(stage.regulation.toggleTilePoints.isEmpty, "第2章ではトグルマスを使用しません")
            XCTAssertTrue(stage.regulation.impassableTilePoints.isEmpty, "第2章では障害物を使用しません")
            XCTAssertEqual(stage.secondaryObjective, expectation.secondary)
            XCTAssertEqual(stage.scoreTarget, expectation.scoreTarget)
            XCTAssertEqual(stage.scoreTargetComparison, expectation.comparison)
            XCTAssertEqual(stage.unlockRequirement, expectation.unlock)
        }
    }

    /// 第3章の 8 ステージが選択カード＋複数踏破の仕様通りか検証する
    func testCampaignStage3Definitions() {
        let library = CampaignLibrary.shared
        guard let chapter3 = library.chapters.first(where: { $0.id == 3 }) else {
            XCTFail("第3章の定義が見つかりません")
            return
        }

        XCTAssertEqual(chapter3.stages.count, 8, "第3章は 8 ステージ構成の想定です")

        let fixedSpawn4 = GameMode.SpawnRule.fixed(BoardGeometry.defaultSpawnPoint(for: 4))
        let fixedSpawn5 = GameMode.SpawnRule.fixed(BoardGeometry.defaultSpawnPoint(for: 5))
        let chooseAny = GameMode.SpawnRule.chooseAnyAfterPreview
        let standardPenalties = GameMode.PenaltySettings(deadlockPenaltyCost: 5, manualRedrawPenaltyCost: 5, manualDiscardPenaltyCost: 1, revisitPenaltyCost: 0)
        let noPenalty = GameMode.PenaltySettings(deadlockPenaltyCost: 0, manualRedrawPenaltyCost: 0, manualDiscardPenaltyCost: 1, revisitPenaltyCost: 0)

        let expectations: [Int: StageExpectation] = [
            1: StageExpectation(
                title: "縦横選択チュートリアル",
                boardSize: 4,
                deck: .standardWithOrthogonalChoices,
                spawn: fixedSpawn4,
                penalties: noPenalty,
                secondary: .finishWithoutPenalty,
                scoreTarget: 600,
                unlock: .chapterTotalStars(chapter: 2, minimum: 16)
            ),
            2: StageExpectation(
                title: "縦横基礎",
                boardSize: 5,
                deck: .standardWithOrthogonalChoices,
                spawn: fixedSpawn5,
                penalties: standardPenalties,
                secondary: .finishWithinMoves(maxMoves: 40),
                scoreTarget: 590,
                unlock: .stageClear(CampaignStageID(chapter: 3, index: 1))
            ),
            3: StageExpectation(
                title: "斜め選択入門",
                boardSize: 5,
                deck: .standardWithDiagonalChoices,
                spawn: fixedSpawn5,
                penalties: standardPenalties,
                secondary: .finishWithPenaltyAtMost(maxPenaltyCount: 2),
                scoreTarget: 580,
                unlock: .stageClear(CampaignStageID(chapter: 3, index: 2))
            ),
            4: StageExpectation(
                title: "桂馬選択入門",
                boardSize: 5,
                deck: .standardWithKnightChoices,
                spawn: fixedSpawn5,
                penalties: standardPenalties,
                secondary: .finishWithinMoves(maxMoves: 38),
                scoreTarget: 570,
                unlock: .stageClear(CampaignStageID(chapter: 3, index: 3))
            ),
            5: StageExpectation(
                title: "選択＋二度踏み",
                boardSize: 5,
                deck: .standardWithOrthogonalChoices,
                spawn: chooseAny,
                penalties: standardPenalties,
                secondary: .finishWithinMoves(maxMoves: 36),
                scoreTarget: 560,
                unlock: .stageClear(CampaignStageID(chapter: 3, index: 4)),
                additional: [GridPoint(x: 1, y: 1): 2, GridPoint(x: 3, y: 3): 2]
            ),
            6: StageExpectation(
                title: "全選択＋三重踏み",
                boardSize: 5,
                deck: .standardWithAllChoices,
                spawn: fixedSpawn5,
                penalties: standardPenalties,
                secondary: .finishWithPenaltyAtMost(maxPenaltyCount: 1),
                scoreTarget: 550,
                unlock: .stageClear(CampaignStageID(chapter: 3, index: 5)),
                additional: [GridPoint(x: 2, y: 2): 3, GridPoint(x: 3, y: 1): 3]
            ),
            7: StageExpectation(
                title: "全選択＋四重踏み",
                boardSize: 5,
                deck: .standardWithAllChoices,
                spawn: chooseAny,
                penalties: standardPenalties,
                secondary: .finishWithinMoves(maxMoves: 34),
                scoreTarget: 540,
                unlock: .stageClear(CampaignStageID(chapter: 3, index: 6)),
                additional: [GridPoint(x: 0, y: 0): 4, GridPoint(x: 4, y: 4): 4]
            ),
            8: StageExpectation(
                title: "総合演習",
                boardSize: 5,
                deck: .standardWithAllChoices,
                spawn: fixedSpawn5,
                penalties: noPenalty,
                secondary: .finishWithoutPenaltyAndWithinMoves(maxMoves: 32),
                scoreTarget: 530,
                unlock: .stageClear(CampaignStageID(chapter: 3, index: 7)),
                additional: [GridPoint(x: 0, y: 0): 2, GridPoint(x: 2, y: 2): 3, GridPoint(x: 4, y: 4): 4]
            )
        ]

        for stage in chapter3.stages {
            guard let expectation = expectations[stage.id.index] else {
                XCTFail("第3章に想定外のステージ index=\(stage.id.index) が含まれています")
                continue
            }

            XCTAssertEqual(stage.title, expectation.title)
            XCTAssertEqual(stage.regulation.deckPreset, expectation.deck)
            XCTAssertEqual(stage.regulation.spawnRule, expectation.spawn)
            XCTAssertEqual(stage.regulation.additionalVisitRequirements, expectation.additional)
            XCTAssertEqual(stage.secondaryObjective, expectation.secondary)
            XCTAssertEqual(stage.scoreTarget, expectation.scoreTarget)
            XCTAssertEqual(stage.scoreTargetComparison, expectation.comparison)
            XCTAssertEqual(stage.unlockRequirement, expectation.unlock)
        }
    }

    /// 第4章のトグル＋複数踏破構成を検証する
    func testCampaignStage4Definitions() {
        let library = CampaignLibrary.shared
        guard let chapter4 = library.chapters.first(where: { $0.id == 4 }) else {
            XCTFail("第4章の定義が見つかりません")
            return
        }

        XCTAssertEqual(chapter4.stages.count, 8, "第4章は 8 ステージ構成の想定です")

        let fixedSpawn5 = GameMode.SpawnRule.fixed(BoardGeometry.defaultSpawnPoint(for: 5))
        let chooseAny = GameMode.SpawnRule.chooseAnyAfterPreview
        let penalties = GameMode.PenaltySettings(deadlockPenaltyCost: 5, manualRedrawPenaltyCost: 5, manualDiscardPenaltyCost: 1, revisitPenaltyCost: 0)
        let noPenalty = GameMode.PenaltySettings(deadlockPenaltyCost: 0, manualRedrawPenaltyCost: 0, manualDiscardPenaltyCost: 1, revisitPenaltyCost: 0)

        let expectations: [Int: StageExpectation] = [
            1: StageExpectation(
                title: "トグル基礎",
                boardSize: 5,
                deck: .standardLight,
                spawn: fixedSpawn5,
                penalties: penalties,
                secondary: .finishWithinMoves(maxMoves: 30),
                scoreTarget: 520,
                unlock: .chapterTotalStars(chapter: 3, minimum: 16),
                toggles: [GridPoint(x: 1, y: 1), GridPoint(x: 3, y: 3)]
            ),
            2: StageExpectation(
                title: "トグル応用",
                boardSize: 5,
                deck: .standardLight,
                spawn: fixedSpawn5,
                penalties: penalties,
                secondary: .finishWithPenaltyAtMost(maxPenaltyCount: 2),
                scoreTarget: 510,
                unlock: .stageClear(CampaignStageID(chapter: 4, index: 1)),
                toggles: [GridPoint(x: 2, y: 2), GridPoint(x: 1, y: 3), GridPoint(x: 3, y: 1)]
            ),
            3: StageExpectation(
                title: "トグル＋二度踏み",
                boardSize: 5,
                deck: .standardLight,
                spawn: fixedSpawn5,
                penalties: penalties,
                secondary: .finishWithinMoves(maxMoves: 40),
                scoreTarget: 500,
                unlock: .stageClear(CampaignStageID(chapter: 4, index: 2)),
                additional: [GridPoint(x: 0, y: 2): 2, GridPoint(x: 4, y: 2): 2],
                toggles: [GridPoint(x: 1, y: 1), GridPoint(x: 3, y: 3)]
            ),
            4: StageExpectation(
                title: "トグル＋三重踏み",
                boardSize: 5,
                deck: .standardWithAllChoices,
                spawn: fixedSpawn5,
                penalties: penalties,
                secondary: .finishWithPenaltyAtMost(maxPenaltyCount: 1),
                scoreTarget: 490,
                unlock: .stageClear(CampaignStageID(chapter: 4, index: 3)),
                additional: [GridPoint(x: 2, y: 2): 3],
                toggles: [GridPoint(x: 1, y: 1), GridPoint(x: 3, y: 3)]
            ),
            5: StageExpectation(
                title: "トグル集中制御",
                boardSize: 5,
                deck: .standardWithAllChoices,
                spawn: chooseAny,
                penalties: penalties,
                secondary: .finishWithinMoves(maxMoves: 38),
                scoreTarget: 480,
                unlock: .stageClear(CampaignStageID(chapter: 4, index: 4)),
                toggles: [
                    GridPoint(x: 0, y: 0),
                    GridPoint(x: 4, y: 0),
                    GridPoint(x: 0, y: 4),
                    GridPoint(x: 4, y: 4)
                ]
            ),
            6: StageExpectation(
                title: "トグル＋四重踏み",
                boardSize: 5,
                deck: .standardWithAllChoices,
                spawn: chooseAny,
                penalties: penalties,
                secondary: .finishWithinMoves(maxMoves: 36),
                scoreTarget: 470,
                unlock: .stageClear(CampaignStageID(chapter: 4, index: 5)),
                additional: [GridPoint(x: 2, y: 2): 4],
                toggles: [GridPoint(x: 1, y: 1), GridPoint(x: 3, y: 3)]
            ),
            7: StageExpectation(
                title: "トグル＋複合踏破",
                boardSize: 5,
                deck: .standardWithAllChoices,
                spawn: chooseAny,
                penalties: noPenalty,
                secondary: .finishWithoutPenalty,
                scoreTarget: 460,
                unlock: .stageClear(CampaignStageID(chapter: 4, index: 6)),
                additional: [GridPoint(x: 0, y: 2): 2, GridPoint(x: 4, y: 2): 2, GridPoint(x: 2, y: 2): 3],
                toggles: [GridPoint(x: 1, y: 1), GridPoint(x: 3, y: 3)]
            ),
            8: StageExpectation(
                title: "総合演習",
                boardSize: 5,
                deck: .standardWithAllChoices,
                spawn: fixedSpawn5,
                penalties: noPenalty,
                secondary: .finishWithoutPenaltyAndWithinMoves(maxMoves: 34),
                scoreTarget: 450,
                unlock: .stageClear(CampaignStageID(chapter: 4, index: 7)),
                additional: [GridPoint(x: 0, y: 0): 2, GridPoint(x: 4, y: 0): 3, GridPoint(x: 2, y: 2): 4],
                toggles: [GridPoint(x: 1, y: 1), GridPoint(x: 3, y: 3), GridPoint(x: 2, y: 4)]
            )
        ]

        for stage in chapter4.stages {
            guard let expectation = expectations[stage.id.index] else {
                XCTFail("第4章に想定外のステージ index=\(stage.id.index) が含まれています")
                continue
            }

            XCTAssertEqual(stage.title, expectation.title)
            XCTAssertEqual(stage.regulation.toggleTilePoints, expectation.toggles)
            XCTAssertEqual(stage.secondaryObjective, expectation.secondary)
            XCTAssertEqual(stage.unlockRequirement, expectation.unlock)
        }
    }

    /// 第5章の障害物＋複合ギミック構成を検証する
    func testCampaignStage5Definitions() {
        let library = CampaignLibrary.shared
        guard let chapter5 = library.chapters.first(where: { $0.id == 5 }) else {
            XCTFail("第5章の定義が見つかりません")
            return
        }

        XCTAssertEqual(chapter5.stages.count, 8, "第5章は 8 ステージ構成の想定です")

        let fixedSpawn5 = GameMode.SpawnRule.fixed(BoardGeometry.defaultSpawnPoint(for: 5))
        let chooseAny = GameMode.SpawnRule.chooseAnyAfterPreview
        let penalties = GameMode.PenaltySettings(deadlockPenaltyCost: 5, manualRedrawPenaltyCost: 5, manualDiscardPenaltyCost: 1, revisitPenaltyCost: 0)
        let noPenalty = GameMode.PenaltySettings(deadlockPenaltyCost: 0, manualRedrawPenaltyCost: 0, manualDiscardPenaltyCost: 1, revisitPenaltyCost: 0)

        let expectations: [Int: StageExpectation] = [
            1: StageExpectation(
                title: "障害物基礎",
                boardSize: 5,
                deck: .standardWithAllChoices,
                spawn: fixedSpawn5,
                penalties: penalties,
                secondary: .finishWithinMoves(maxMoves: 30),
                scoreTarget: 500,
                unlock: .chapterTotalStars(chapter: 4, minimum: 16),
                impassable: [GridPoint(x: 1, y: 1), GridPoint(x: 3, y: 3)]
            ),
            2: StageExpectation(
                title: "障害物応用",
                boardSize: 5,
                deck: .standardWithAllChoices,
                spawn: chooseAny,
                penalties: penalties,
                secondary: .finishWithPenaltyAtMost(maxPenaltyCount: 2),
                scoreTarget: 490,
                unlock: .stageClear(CampaignStageID(chapter: 5, index: 1)),
                impassable: [GridPoint(x: 1, y: 1), GridPoint(x: 3, y: 3), GridPoint(x: 2, y: 2)]
            ),
            3: StageExpectation(
                title: "障害物＋二度踏み",
                boardSize: 5,
                deck: .standardWithAllChoices,
                spawn: fixedSpawn5,
                penalties: penalties,
                secondary: .finishWithinMoves(maxMoves: 40),
                scoreTarget: 480,
                unlock: .stageClear(CampaignStageID(chapter: 5, index: 2)),
                additional: [GridPoint(x: 1, y: 3): 2, GridPoint(x: 3, y: 1): 2],
                impassable: [GridPoint(x: 0, y: 1), GridPoint(x: 4, y: 3)]
            ),
            4: StageExpectation(
                title: "障害物＋三重踏み",
                boardSize: 5,
                deck: .standardWithAllChoices,
                spawn: chooseAny,
                penalties: penalties,
                secondary: .finishWithPenaltyAtMost(maxPenaltyCount: 1),
                scoreTarget: 470,
                unlock: .stageClear(CampaignStageID(chapter: 5, index: 3)),
                additional: [GridPoint(x: 2, y: 2): 3],
                impassable: [GridPoint(x: 0, y: 2), GridPoint(x: 4, y: 2)]
            ),
            5: StageExpectation(
                title: "障害物＋トグル",
                boardSize: 5,
                deck: .standardWithAllChoices,
                spawn: fixedSpawn5,
                penalties: penalties,
                secondary: .finishWithinMoves(maxMoves: 38),
                scoreTarget: 460,
                unlock: .stageClear(CampaignStageID(chapter: 5, index: 4)),
                toggles: [GridPoint(x: 2, y: 1), GridPoint(x: 2, y: 3)],
                impassable: [GridPoint(x: 1, y: 1), GridPoint(x: 3, y: 3)]
            ),
            6: StageExpectation(
                title: "複合 (四重踏み含む)",
                boardSize: 5,
                deck: .standardWithAllChoices,
                spawn: chooseAny,
                penalties: penalties,
                secondary: .finishWithinMoves(maxMoves: 36),
                scoreTarget: 450,
                unlock: .stageClear(CampaignStageID(chapter: 5, index: 5)),
                additional: [GridPoint(x: 2, y: 2): 4],
                toggles: [GridPoint(x: 0, y: 4)],
                impassable: [GridPoint(x: 1, y: 1), GridPoint(x: 3, y: 3)]
            ),
            7: StageExpectation(
                title: "複合 (多要素)",
                boardSize: 5,
                deck: .standardWithAllChoices,
                spawn: chooseAny,
                penalties: noPenalty,
                secondary: .finishWithoutPenalty,
                scoreTarget: 440,
                unlock: .stageClear(CampaignStageID(chapter: 5, index: 6)),
                additional: [GridPoint(x: 0, y: 0): 2, GridPoint(x: 4, y: 4): 3],
                toggles: [GridPoint(x: 2, y: 2)],
                impassable: [GridPoint(x: 1, y: 1), GridPoint(x: 3, y: 3), GridPoint(x: 2, y: 4)]
            ),
            8: StageExpectation(
                title: "最終試験",
                boardSize: 5,
                deck: .standardWithAllChoices,
                spawn: chooseAny,
                penalties: noPenalty,
                secondary: .finishWithoutPenaltyAndWithinMoves(maxMoves: 34),
                scoreTarget: 430,
                unlock: .stageClear(CampaignStageID(chapter: 5, index: 7)),
                additional: [GridPoint(x: 0, y: 4): 2, GridPoint(x: 4, y: 0): 3, GridPoint(x: 2, y: 4): 4],
                toggles: [GridPoint(x: 1, y: 3), GridPoint(x: 3, y: 1)],
                impassable: [GridPoint(x: 1, y: 1), GridPoint(x: 3, y: 3), GridPoint(x: 2, y: 2)]
            )
        ]

        for stage in chapter5.stages {
            guard let expectation = expectations[stage.id.index] else {
                XCTFail("第5章に想定外のステージ index=\(stage.id.index) が含まれています")
                continue
            }

            XCTAssertEqual(stage.title, expectation.title)
            XCTAssertEqual(stage.regulation.impassableTilePoints, expectation.impassable)
            XCTAssertEqual(stage.regulation.toggleTilePoints, expectation.toggles)
            XCTAssertEqual(stage.regulation.additionalVisitRequirements, expectation.additional)
            XCTAssertEqual(stage.secondaryObjective, expectation.secondary)
            XCTAssertEqual(stage.unlockRequirement, expectation.unlock)
        }
    }

    /// 全ステージの固定スポーンが障害物と重なっていないかを網羅的に検証する
    /// - Important: 任意スポーンはプレイヤーが安全マスを選べるため検証対象外とし、固定スポーンのみ `impassableTilePoints` との矛盾をチェックする
    func testFixedSpawnDoesNotOverlapImpassableTiles() {
        let library = CampaignLibrary.shared

        for chapter in library.chapters {
            for stage in chapter.stages {
                switch stage.regulation.spawnRule {
                case .fixed(let spawnPoint):
                    // 障害物と固定スポーンが衝突すると開幕で移動できないため、定義ミスを検知する
                    XCTAssertFalse(
                        stage.regulation.impassableTilePoints.contains(spawnPoint),
                        "ステージ \(stage.displayCode) の固定スポーンが障害物マスと重なっています"
                    )
                case .chooseAnyAfterPreview:
                    // 任意スポーンはプレイヤーが配置を調整できるため、ここでの追加検証は不要
                    continue
                }
            }
        }
    }
}
