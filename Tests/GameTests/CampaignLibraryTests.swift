import XCTest
@testable import Game

/// キャンペーン関連の定義を確認するテスト
final class CampaignLibraryTests: XCTestCase {
    /// 選択カード系プリセットが期待通りの構成を返すことを確認する
    func testChoiceDeckPresetConfigurations() {
        let presets: [(GameDeckPreset, String, String, Set<MoveCard>)] = [
            (.directionChoice, "選択式キング構成", "選択式キングカード入り", [.kingUpOrDown, .kingLeftOrRight]),
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

            let allowedMoves = Set(preset.configuration.allowedMoves)
            XCTAssertTrue(expectedMoves.isSubset(of: allowedMoves), "\(preset) に必要なカードが含まれていません")
        }
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
        XCTAssertEqual(stage31.regulation.deckPreset, .kingOrthogonalChoiceOnly)
        XCTAssertEqual(stage31.secondaryObjective, .finishWithoutPenalty)
        XCTAssertEqual(stage31.scoreTarget, 600)
        XCTAssertEqual(stage31.unlockRequirement, .stageClear(CampaignStageID(chapter: 2, index: 1)))

        XCTAssertEqual(stage32.title, "斜め選択応用")
        XCTAssertEqual(stage32.regulation.deckPreset, .kingDiagonalChoiceOnly)
        XCTAssertEqual(stage32.secondaryObjective, .finishWithinMoves(maxMoves: 32))
        XCTAssertEqual(stage32.scoreTarget, 580)
        XCTAssertEqual(stage32.unlockRequirement, .stageClear(stage31ID))

        XCTAssertEqual(stage33.title, "桂馬選択攻略")
        XCTAssertEqual(stage33.regulation.deckPreset, .knightChoiceOnly)
        XCTAssertEqual(stage33.secondaryObjective, .finishWithinMoves(maxMoves: 30))
        XCTAssertEqual(stage33.scoreTarget, 560)
        XCTAssertEqual(stage33.unlockRequirement, .stageClear(stage32ID))

        XCTAssertEqual(stage34.title, "総合選択演習")
        XCTAssertEqual(stage34.regulation.deckPreset, .allChoiceMixed)
        XCTAssertEqual(stage34.secondaryObjective, .finishWithinMoves(maxMoves: 28))
        XCTAssertEqual(stage34.scoreTarget, 540)
        XCTAssertEqual(stage34.scoreTargetComparison, .lessThan)
        XCTAssertEqual(stage34.unlockRequirement, .stageClear(stage33ID))
    }

    /// 4 章のトグルギミック導入ステージが仕様通りに組み込まれているかを確認する
    func testCampaignStage4Definitions() {
        let library = CampaignLibrary.shared
        let stage41ID = CampaignStageID(chapter: 4, index: 1)

        // MARK: 章配列が 4 章まで拡張されているか明示的に確認する
        XCTAssertEqual(library.chapters.count, 4, "キャンペーンの章数が 4 章構成になっていません")
        XCTAssertEqual(library.chapters.last?.id, 4, "最終章の ID が 4 になっていません")

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
}
