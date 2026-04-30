import XCTest
import Game
@testable import MonoKnightApp

final class GamePreparationOverlayPresentationTests: XCTestCase {
    func testCampaignPreparationPrioritizesFeatureSpotlight() throws {
        let stage = try XCTUnwrap(CampaignLibrary.shared.stage(with: CampaignStageID(chapter: 1, index: 1)))
        let presentation = GamePreparationOverlayPresentation(
            mode: stage.makeGameMode(),
            campaignStage: stage
        )

        XCTAssertEqual(presentation.primaryObjectiveText, "目的地を 3 個取ればクリア")
        XCTAssertEqual(presentation.clearConditionText, "クリア: 目的地 3 個")
        XCTAssertEqual(
            presentation.shortRuleSummaryText,
            "スコア: 手数 + 時間 + フォーカス。スターはやり込み目標です。"
        )
        XCTAssertEqual(presentation.detailsTitle, "スター条件・記録を見る")
        XCTAssertTrue(presentation.prioritizesFeatureSpotlight)
        XCTAssertEqual(
            presentation.featuredChips.map(\.displayText),
            ["NEW 目的地集め", "NEW 王将カード"]
        )
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

    func testCampaignPreparationHighlightsNewEarlyChoiceCards() throws {
        let stage = try XCTUnwrap(CampaignLibrary.shared.stage(with: CampaignStageID(chapter: 2, index: 1)))
        let presentation = GamePreparationOverlayPresentation(
            mode: stage.makeGameMode(),
            campaignStage: stage
        )

        XCTAssertTrue(presentation.featureChips.contains(.init(label: "選択カード", isNew: true)))
        XCTAssertEqual(presentation.featuredChips.first, .init(label: "選択カード", isNew: true))
    }

    func testCampaignPreparationHighlightsNewFreeFocusTile() throws {
        let stage = try XCTUnwrap(CampaignLibrary.shared.stage(with: CampaignStageID(chapter: 2, index: 2)))
        let presentation = GamePreparationOverlayPresentation(
            mode: stage.makeGameMode(),
            campaignStage: stage
        )

        XCTAssertTrue(presentation.featureChips.contains(.init(label: "開始位置選び", isNew: false)))
        XCTAssertTrue(presentation.featureChips.contains(.init(label: "無料フォーカス", isNew: true)))
        XCTAssertEqual(presentation.featuredChips.first, .init(label: "無料フォーカス", isNew: true))
    }

    func testCampaignPreparationKeepsFeatureSpotlightWithoutNewElements() throws {
        let stage = try XCTUnwrap(CampaignLibrary.shared.stage(with: CampaignStageID(chapter: 2, index: 6)))
        let presentation = GamePreparationOverlayPresentation(
            mode: stage.makeGameMode(),
            campaignStage: stage
        )

        XCTAssertTrue(presentation.prioritizesFeatureSpotlight)
        XCTAssertFalse(presentation.featuredChips.isEmpty)
        XCTAssertFalse(presentation.featuredChips.contains { $0.isNew })
    }
}
