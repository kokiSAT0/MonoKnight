#if canImport(UIKit)
import XCTest

/// 日替わりチャレンジが通常タイトル導線から凍結されていることを確認する UI テスト
/// - Note: `UITEST_MODE` 環境変数でモックサービスを注入し、挑戦回数ストアや広告サービスの挙動を決定論的にする
final class DailyChallengeUITests: XCTestCase {
    func testDailyChallengeIsHiddenFromMainTitleFlow() {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_MODE"] = "1"
        app.launch()

        let campaignTile = app.otherElements["title_tile_campaign"]
        XCTAssertTrue(campaignTile.waitForExistence(timeout: 5), "タイトル画面に塔ダンジョンカードが表示されること")

        let dailyTile = app.otherElements["title_tile_daily_challenge"]
        XCTAssertFalse(dailyTile.exists, "日替わりチャレンジは通常タイトル導線から外すこと")

        let highScoreTile = app.otherElements["title_tile_high_score"]
        XCTAssertFalse(highScoreTile.exists, "ハイスコアは通常タイトル導線から外すこと")
    }
}
#endif
