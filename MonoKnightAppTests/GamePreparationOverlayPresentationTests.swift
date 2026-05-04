import XCTest
import Game
@testable import MonoKnightApp

final class GamePreparationOverlayPresentationTests: XCTestCase {
    func testDungeonPreparationUsesExitHPAndTurnLimit() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let floor = try XCTUnwrap(tower.floors.first)
        let presentation = GamePreparationOverlayPresentation(
            mode: floor.makeGameMode(dungeonID: tower.id)
        )

        XCTAssertEqual(presentation.primaryObjectiveText, "出口へ到達すればクリア")
        XCTAssertEqual(presentation.clearConditionText, "クリア: 出口 (3,4)")
        XCTAssertTrue(presentation.shortRuleSummaryText.contains("HP 3"))
        XCTAssertTrue(presentation.shortRuleSummaryText.contains("残り手数 7"))
        XCTAssertTrue(presentation.shortRuleSummaryText.contains("床のカードは1回使い切り"))
        XCTAssertTrue(presentation.shortRuleSummaryText.contains("報酬カードは持ち越せます"))
        XCTAssertEqual(presentation.detailsTitle, "塔のルールを見る")
        XCTAssertTrue(
            presentation.featureChips.contains(
                GamePreparationOverlayPresentation.FeatureChip(label: "出口到達", isNew: true)
            )
        )
        XCTAssertTrue(
            presentation.featureChips.contains(
                GamePreparationOverlayPresentation.FeatureChip(label: "基本移動", isNew: true)
            )
        )
    }
}
