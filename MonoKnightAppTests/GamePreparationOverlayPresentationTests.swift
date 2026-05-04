import XCTest
import Game
@testable import MonoKnightApp

final class GamePreparationOverlayPresentationTests: XCTestCase {
    func testLegacyCampaignPreparationStillFormats() throws {
        let stage = try XCTUnwrap(CampaignLibrary.shared.allStages.first)
        let presentation = GamePreparationOverlayPresentation(
            mode: stage.makeGameMode(),
            campaignStage: stage
        )

        XCTAssertFalse(presentation.primaryObjectiveText.isEmpty)
        XCTAssertFalse(presentation.clearConditionText.isEmpty)
        XCTAssertFalse(presentation.shortRuleSummaryText.isEmpty)
        XCTAssertFalse(presentation.detailsTitle.isEmpty)
    }

    func testNonCampaignPreparationUsesRuleDetailDisclosure() {
        let presentation = GamePreparationOverlayPresentation(
            mode: .classicalChallenge,
            campaignStage: nil
        )

        XCTAssertEqual(presentation.primaryObjectiveText, "盤面の必要マスを踏破すればクリア")
        XCTAssertEqual(presentation.clearConditionText, "クリア: 必要マスを踏破")
        XCTAssertEqual(
            presentation.shortRuleSummaryText,
            "ペナルティを抑えながら、使えるカードで盤面を埋めましょう。"
        )
        XCTAssertEqual(presentation.detailsTitle, "ルール詳細を見る")
        XCTAssertFalse(presentation.prioritizesFeatureSpotlight)
        XCTAssertTrue(presentation.featureChips.isEmpty)
    }

    func testDungeonPreparationUsesExitHPAndTurnLimitWithoutCampaignStars() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let floor = try XCTUnwrap(tower.floors.first)
        let presentation = GamePreparationOverlayPresentation(
            mode: floor.makeGameMode(dungeonID: tower.id),
            campaignStage: nil
        )

        XCTAssertEqual(presentation.primaryObjectiveText, "出口へ到達すればクリア")
        XCTAssertEqual(presentation.clearConditionText, "クリア: 出口 (3,4)")
        XCTAssertTrue(presentation.shortRuleSummaryText.contains("HP 3"))
        XCTAssertTrue(presentation.shortRuleSummaryText.contains("残り手数 7"))
        XCTAssertTrue(presentation.shortRuleSummaryText.contains("最初は基本移動のみ"))
        XCTAssertTrue(presentation.shortRuleSummaryText.contains("床のカードは1回使い切り"))
        XCTAssertTrue(presentation.shortRuleSummaryText.contains("報酬カードは3回使えて持ち越せます"))
        XCTAssertEqual(presentation.detailsTitle, "塔のルールを見る")
        XCTAssertTrue(presentation.featureChips.contains(.init(label: "出口到達", isNew: true)))
        XCTAssertTrue(presentation.featureChips.contains(.init(label: "基本移動", isNew: true)))
        XCTAssertFalse(presentation.detailsTitle.contains("スター"))
    }

}
