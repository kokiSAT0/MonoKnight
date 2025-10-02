import XCTest
@testable import Game

/// キャンペーン関連の定義を確認するテスト
final class CampaignLibraryTests: XCTestCase {
    /// 選択カード系プリセットが期待通りの構成を返すことを確認する
    func testChoiceDeckPresetConfigurations() {
        let presets: [(GameDeckPreset, String, String, Set<MoveCard>)] = [
            (.kingOnly, "王将構成", "王将カードのみ", Set(MoveCard.standardSet.filter { $0.isKingType })),
            (.kingPlusKnightOnly, "王将＋桂馬構成", "王将4種＋桂馬4種", Set([
                .kingUp,
                .kingRight,
                .kingDown,
                .kingLeft,
                .knightUp2Right1,
                .knightUp2Left1,
                .knightDown2Right1,
                .knightDown2Left1
            ])),
            (.kingAndKnightBasic, "キング＆桂馬基本構成", "キング8種＋桂馬8種", Set(MoveCard.standardSet.filter { $0.isKingType || $0.isKnightType })),
            (.directionChoice, "選択式キング構成", "選択式キングカード入り", [.kingUpOrDown, .kingLeftOrRight]),
            (.standardLight, "標準ライト構成", "標準（長距離減衰）", Set(MoveCard.standardSet)),
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
                .directionChoice,
                .standardLight,
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

    /// 第1章のステージ構成が最新レギュレーションと一致するかを検証する
    func testCampaignStage1Definitions() {
        let library = CampaignLibrary.shared

        guard let chapter1 = library.chapters.first(where: { $0.id == 1 }) else {
            XCTFail("第1章の定義が見つかりません")
            return
        }

        XCTAssertEqual(chapter1.stages.count, 8, "第1章は 8 ステージ構成である必要があります")

        // MARK: スポーン設定とペナルティ設定を事前に用意しておき、比較を簡潔にする
        let spawn3 = GameMode.SpawnRule.fixed(BoardGeometry.defaultSpawnPoint(for: 3))
        let spawn4 = GameMode.SpawnRule.fixed(BoardGeometry.defaultSpawnPoint(for: 4))
        let spawn5 = GameMode.SpawnRule.fixed(BoardGeometry.defaultSpawnPoint(for: 5))
        let chooseAny = GameMode.SpawnRule.chooseAnyAfterPreview

        let penaltyStage11 = GameMode.PenaltySettings(deadlockPenaltyCost: 2, manualRedrawPenaltyCost: 2, manualDiscardPenaltyCost: 1, revisitPenaltyCost: 1)
        let penaltyStage12 = GameMode.PenaltySettings(deadlockPenaltyCost: 2, manualRedrawPenaltyCost: 2, manualDiscardPenaltyCost: 1, revisitPenaltyCost: 0)
        let penaltyStage13to14 = GameMode.PenaltySettings(deadlockPenaltyCost: 3, manualRedrawPenaltyCost: 1, manualDiscardPenaltyCost: 1, revisitPenaltyCost: 0)
        let penaltyStage15onward = GameMode.PenaltySettings(deadlockPenaltyCost: 3, manualRedrawPenaltyCost: 2, manualDiscardPenaltyCost: 1, revisitPenaltyCost: 0)

        let expectations: [(CampaignStageID, String, GameDeckPreset, Int, GameMode.SpawnRule, GameMode.PenaltySettings, CampaignStage.SecondaryObjective?, Int, CampaignStage.ScoreTargetComparison, CampaignStageUnlockRequirement)] = [
            (CampaignStageID(chapter: 1, index: 1), "王将訓練", .kingOnly, 3, spawn3, penaltyStage11, .finishWithinSeconds(maxSeconds: 120), 900, .lessThan, .always),
            (CampaignStageID(chapter: 1, index: 2), "ナイト初見", .kingPlusKnightOnly, 3, spawn3, penaltyStage12, .finishWithPenaltyAtMost(maxPenaltyCount: 5), 800, .lessThan, .stageClear(CampaignStageID(chapter: 1, index: 1))),
            (CampaignStageID(chapter: 1, index: 3), "4×4基礎", .kingAndKnightBasic, 4, spawn4, penaltyStage13to14, .finishWithinSeconds(maxSeconds: 60), 600, .lessThan, .stageClear(CampaignStageID(chapter: 1, index: 2))),
            (CampaignStageID(chapter: 1, index: 4), "4×4応用", .kingAndKnightBasic, 4, chooseAny, penaltyStage13to14, .finishWithPenaltyAtMost(maxPenaltyCount: 3), 550, .lessThan, .stageClear(CampaignStageID(chapter: 1, index: 3))),
            (CampaignStageID(chapter: 1, index: 5), "4×4持久", .standardLight, 4, spawn4, penaltyStage15onward, .finishWithinMoves(maxMoves: 30), 500, .lessThan, .stageClear(CampaignStageID(chapter: 1, index: 4))),
            (CampaignStageID(chapter: 1, index: 6), "4×4戦略", .kingAndKnightBasic, 4, chooseAny, penaltyStage15onward, .finishWithPenaltyAtMost(maxPenaltyCount: 2), 480, .lessThan, .stageClear(CampaignStageID(chapter: 1, index: 5))),
            (CampaignStageID(chapter: 1, index: 7), "5×5導入", .standardLight, 5, spawn5, penaltyStage15onward, .finishWithinMoves(maxMoves: 40), 460, .lessThan, .stageClear(CampaignStageID(chapter: 1, index: 6))),
            (CampaignStageID(chapter: 1, index: 8), "総合演習", .standardLight, 5, chooseAny, penaltyStage15onward, .finishWithinMoves(maxMoves: 35), 440, .lessThan, .stageClear(CampaignStageID(chapter: 1, index: 7)))
        ]

        for (index, expectation) in expectations.enumerated() {
            let stage = chapter1.stages[index]
            XCTAssertEqual(stage.id, expectation.0)
            XCTAssertEqual(stage.title, expectation.1)
            XCTAssertEqual(stage.regulation.deckPreset, expectation.2)
            XCTAssertEqual(stage.regulation.boardSize, expectation.3)
            XCTAssertEqual(stage.regulation.spawnRule, expectation.4)
            XCTAssertEqual(stage.regulation.penalties, expectation.5)
            XCTAssertEqual(stage.secondaryObjective, expectation.6)
            XCTAssertEqual(stage.scoreTarget, expectation.7)
            XCTAssertEqual(stage.scoreTargetComparison, expectation.8)
            XCTAssertEqual(stage.unlockRequirement, expectation.9)
        }

        // MARK: ステージ順序が ID の昇順になっているか確認する
        XCTAssertEqual(chapter1.stages.map(\.id.index), Array(1...8), "第1章のステージ順序が連番になっていません")
    }

    /// 3 章のステージが段階的に難度を増しているかをまとめて検証する
    func testCampaignStage3Definitions() {
        let library = CampaignLibrary.shared
        let stage31ID = CampaignStageID(chapter: 3, index: 1)
        let stage32ID = CampaignStageID(chapter: 3, index: 2)
        let stage33ID = CampaignStageID(chapter: 3, index: 3)
        let stage34ID = CampaignStageID(chapter: 3, index: 4)

        guard
            let stage31 = library.stage(with: stage31ID),
            let stage32 = library.stage(with: stage32ID),
            let stage33 = library.stage(with: stage33ID),
            let stage34 = library.stage(with: stage34ID)
        else {
            XCTFail("第3章のステージ定義に不足があります")
            return
        }

        XCTAssertEqual(stage31.title, "縦横選択訓練")
        XCTAssertEqual(stage31.regulation.deckPreset, .standardWithOrthogonalChoices)
        XCTAssertEqual(stage31.secondaryObjective, .finishWithoutPenalty)
        XCTAssertEqual(stage31.scoreTarget, 600)
        XCTAssertEqual(stage31.unlockRequirement, .stageClear(CampaignStageID(chapter: 2, index: 1)))

        XCTAssertEqual(stage32.title, "斜め選択応用")
        XCTAssertEqual(stage32.regulation.deckPreset, .standardWithDiagonalChoices)
        XCTAssertEqual(stage32.secondaryObjective, .finishWithinMoves(maxMoves: 32))
        XCTAssertEqual(stage32.scoreTarget, 580)
        XCTAssertEqual(stage32.unlockRequirement, .stageClear(stage31ID))

        XCTAssertEqual(stage33.title, "桂馬選択攻略")
        XCTAssertEqual(stage33.regulation.deckPreset, .standardWithKnightChoices)
        XCTAssertEqual(stage33.secondaryObjective, .finishWithinMoves(maxMoves: 30))
        XCTAssertEqual(stage33.scoreTarget, 560)
        XCTAssertEqual(stage33.unlockRequirement, .stageClear(stage32ID))

        XCTAssertEqual(stage34.title, "総合選択演習")
        XCTAssertEqual(stage34.regulation.deckPreset, .standardWithAllChoices)
        XCTAssertEqual(stage34.secondaryObjective, .finishWithinMoves(maxMoves: 28))
        XCTAssertEqual(stage34.scoreTarget, 540)
        XCTAssertEqual(stage34.scoreTargetComparison, .lessThan)
        XCTAssertEqual(stage34.unlockRequirement, .stageClear(stage33ID))
    }

    /// 4 章のトグルギミック導入ステージが仕様通りに組み込まれているかを確認する
    func testCampaignStage4Definitions() {
        let library = CampaignLibrary.shared
        let stage41ID = CampaignStageID(chapter: 4, index: 1)

        // MARK: 章配列へ 4 章が含まれているかを確認する（最終章は別テストで検証）
        XCTAssertGreaterThanOrEqual(library.chapters.count, 4, "キャンペーン定義に 4 章目が存在しません")
        XCTAssertNotNil(library.chapters.first(where: { $0.id == 4 }), "章 ID 4 の定義が欠落しています")

        guard let stage41 = library.stage(with: stage41ID) else {
            XCTFail("第4章 4-1 の定義が見つかりません")
            return
        }

        // MARK: 基本情報（タイトル・サマリー・盤面サイズ）が仕様通りかを検証
        XCTAssertEqual(stage41.title, "反転制御訓練")
        XCTAssertTrue(stage41.summary.contains("トグルマス"), "サマリーにトグルギミックへの言及がありません")
        XCTAssertEqual(stage41.regulation.boardSize, 5)

        // MARK: トグルマス座標が 0 始まりで (0,1) と (2,3) に設定されているかをチェック
        let expectedTogglePoints: Set<GridPoint> = [
            GridPoint(x: 0, y: 1),
            GridPoint(x: 2, y: 3)
        ]
        XCTAssertEqual(stage41.regulation.toggleTilePoints, expectedTogglePoints)

        // MARK: スター条件（手数制限・スコア上限）が定義通りかを確認
        XCTAssertEqual(stage41.secondaryObjective, .finishWithinMoves(maxMoves: 30))
        XCTAssertEqual(stage41.scoreTarget, 520)

        // MARK: アンロック条件が 3-4 クリアに紐付いているかを確認
        let prerequisiteID = CampaignStageID(chapter: 3, index: 4)
        XCTAssertEqual(stage41.unlockRequirement, .stageClear(prerequisiteID))
    }

    /// 5 章の障害物ステージが仕様通りに構築されているかを確認する
    func testCampaignStage5Definitions() {
        let library = CampaignLibrary.shared
        let stage51ID = CampaignStageID(chapter: 5, index: 1)
        let prerequisiteStageID = CampaignStageID(chapter: 4, index: 1)

        // MARK: 章数が 5 章構成へ拡張され、最終章の ID が 5 になっているか確認
        XCTAssertEqual(library.chapters.count, 5, "キャンペーンの章数が 5 章構成になっていません")
        XCTAssertEqual(library.chapters.last?.id, 5, "最終章の ID が 5 になっていません")

        guard let stage51 = library.stage(with: stage51ID) else {
            XCTFail("第5章 5-1 の定義が見つかりません")
            return
        }

        // MARK: 基本情報（タイトル・サマリー）で移動不可マスへの言及があるか確認
        XCTAssertEqual(stage51.title, "障害物突破演習")
        XCTAssertTrue(stage51.summary.contains("移動不可"), "サマリーに移動不可マスへの言及がありません")

        // MARK: 移動不可マスが (0,1) と (2,3) に設定されているかを検証
        let expectedImpassablePoints: Set<GridPoint> = [
            GridPoint(x: 0, y: 1),
            GridPoint(x: 2, y: 3)
        ]
        XCTAssertEqual(stage51.regulation.impassableTilePoints, expectedImpassablePoints, "移動不可マスの設定が仕様と一致しません")

        // MARK: スター条件が移動不可マスを意識した手数・スコアになっているか確認
        XCTAssertEqual(stage51.secondaryObjective, .finishWithinMoves(maxMoves: 27))
        XCTAssertEqual(stage51.scoreTarget, 500)
        XCTAssertEqual(stage51.scoreTargetComparison, .lessThan)

        // MARK: アンロック条件が 4-1 クリアに紐付いているかを確認
        XCTAssertEqual(stage51.unlockRequirement, .stageClear(prerequisiteStageID))
    }
}
