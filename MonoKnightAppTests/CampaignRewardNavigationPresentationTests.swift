import XCTest
import Game
@testable import MonoKnightApp

final class CampaignRewardNavigationPresentationTests: XCTestCase {
    func testNextStagePresentationUsesSingleSequentialCallToAction() throws {
        let stage = try XCTUnwrap(CampaignLibrary.shared.stage(with: CampaignStageID(chapter: 2, index: 1)))

        let presentation = CampaignRewardNavigationPresentation(nextCampaignStage: stage)

        XCTAssertEqual(presentation.title, "次のステージ")
        XCTAssertEqual(presentation.buttonTitle, "次へ: 2-1")
        XCTAssertEqual(presentation.stage?.id, stage.id)
    }

    func testFinalStagePresentationOmitsNextStageButton() {
        let presentation = CampaignRewardNavigationPresentation(nextCampaignStage: nil)

        XCTAssertEqual(presentation.title, "キャンペーン完走")
        XCTAssertNil(presentation.buttonTitle)
        XCTAssertNil(presentation.stage)
    }
}
