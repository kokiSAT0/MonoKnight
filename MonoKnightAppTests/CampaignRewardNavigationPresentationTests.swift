import XCTest
import Game
@testable import MonoKnightApp

/// 旧目的地制キャンペーンの結果導線は凍結中のため、表示モデルが壊れない最低限だけ確認する。
final class CampaignRewardNavigationPresentationTests: XCTestCase {
    func testLegacyCampaignRewardNavigationPresentationStillFormats() throws {
        let stage = try XCTUnwrap(CampaignLibrary.shared.allStages.first)
        let presentation = CampaignRewardNavigationPresentation(nextCampaignStage: stage)
        let finalPresentation = CampaignRewardNavigationPresentation(nextCampaignStage: nil)

        XCTAssertFalse(presentation.title.isEmpty)
        XCTAssertNotNil(presentation.buttonTitle)
        XCTAssertEqual(presentation.stage?.id, stage.id)
        XCTAssertFalse(finalPresentation.title.isEmpty)
        XCTAssertNil(finalPresentation.buttonTitle)
    }
}
