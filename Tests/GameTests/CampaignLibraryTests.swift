import XCTest
@testable import Game

/// キャンペーン関連の定義を確認するテスト
final class CampaignLibraryTests: XCTestCase {
    /// directionChoice プリセットが新カードを含む設定を返すことを確認する
    func testDirectionChoicePresetConfiguration() {
        let preset = GameDeckPreset.directionChoice
        let config = preset.configuration

        // 表示名と要約テキストが期待通りか確認
        XCTAssertEqual(preset.displayName, "選択式キング構成", "表示名が想定外です")
        XCTAssertEqual(preset.summaryText, "選択式キングカード入り", "サマリーテキストが想定外です")

        // 設定に新カードが含まれているか検証
        XCTAssertTrue(config.allowedMoves.contains(.kingUpOrDown), "上下選択カードがプリセット設定に含まれていません")
        XCTAssertTrue(config.allowedMoves.contains(.kingLeftOrRight), "左右選択カードがプリセット設定に含まれていません")
    }

    /// 3-1 ステージが directionChoice デッキを使用し、仕様通りの条件を持つことを確認する
    func testCampaignStage31Definition() {
        let library = CampaignLibrary.shared
        let stageID = CampaignStageID(chapter: 3, index: 1)
        guard let stage = library.stage(with: stageID) else {
            XCTFail("3-1 ステージが CampaignLibrary に見つかりません")
            return
        }

        XCTAssertEqual(stage.title, "選択訓練", "ステージ名が仕様と一致していません")
        XCTAssertEqual(stage.regulation.boardSize, 5, "盤面サイズが 5×5 ではありません")
        XCTAssertEqual(stage.regulation.deckPreset, .directionChoice, "使用デッキが directionChoice ではありません")
        XCTAssertEqual(stage.secondaryObjective, .finishWithoutPenalty, "二つ目のスター条件が想定外です")
        XCTAssertEqual(stage.scoreTarget, 600, "スコアターゲットが想定外です")

        // アンロック条件が 2-1 のクリアであることを確認
        let expectedUnlock = CampaignStageUnlockRequirement.stageClear(CampaignStageID(chapter: 2, index: 1))
        XCTAssertEqual(stage.unlockRequirement, expectedUnlock, "アンロック条件が 2-1 クリアになっていません")
    }
}
