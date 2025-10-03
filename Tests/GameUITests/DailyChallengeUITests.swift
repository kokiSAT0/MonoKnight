#if canImport(UIKit)
import XCTest

/// デイリーチャレンジ画面の基本的な UI 挙動を確認する UI テスト
final class DailyChallengeUITests: XCTestCase {
    func testDailyChallengeStartAndRewardFlow() {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_MODE"] = "1"
        app.launch()

        let tileAttemptsLabel = app.staticTexts["daily_challenge_tile_attempts"]
        XCTAssertTrue(tileAttemptsLabel.waitForExistence(timeout: 5), "タイトル画面にデイリーチャレンジの回数表示が見つかりません")

        app.buttons["title_tile_daily_challenge"].tap()

        let attemptsValue = app.staticTexts["daily_challenge_attempts_value"]
        XCTAssertTrue(attemptsValue.waitForExistence(timeout: 5), "デイリーチャレンジ詳細の回数表示が見つかりません")

        let initialCompact = attemptsValue.label
        let components = initialCompact.split(separator: "/")
        XCTAssertEqual(components.count, 2, "挑戦回数の表示形式が想定外です: \(initialCompact)")
        let initialRemaining = Int(components[0]) ?? 0
        let maximumAttempts = Int(components[1]) ?? 0
        XCTAssertGreaterThan(initialRemaining, 0, "初期挑戦回数が 0 以下です")

        app.buttons["daily_challenge_start_button"].tap()

        let startAlert = app.alerts.firstMatch
        XCTAssertTrue(startAlert.waitForExistence(timeout: 2), "挑戦開始後の確認アラートが表示されません")
        startAlert.buttons["OK"].tap()

        let expectedAfterStart = "\(initialRemaining - 1)/\(maximumAttempts)"
        XCTAssertTrue(attemptsValue.waitForExistence(timeout: 2))
        XCTAssertEqual(attemptsValue.label, expectedAfterStart, "挑戦開始後の回数表示が減少していません")

        app.buttons["daily_challenge_close_button"].tap()
        XCTAssertTrue(tileAttemptsLabel.waitForExistence(timeout: 2))
        XCTAssertTrue(tileAttemptsLabel.label.contains("\(initialRemaining - 1)/\(maximumAttempts)"), "タイトル側の回数表示が更新されていません")

        app.buttons["title_tile_daily_challenge"].tap()
        XCTAssertTrue(attemptsValue.waitForExistence(timeout: 2))

        app.buttons["daily_challenge_watch_ad_button"].tap()
        let rewardAlert = app.alerts.firstMatch
        XCTAssertTrue(rewardAlert.waitForExistence(timeout: 2), "広告視聴後の確認アラートが表示されません")
        rewardAlert.buttons["OK"].tap()

        let expectedAfterReward = "\(initialRemaining)/\(maximumAttempts)"
        XCTAssertEqual(attemptsValue.label, expectedAfterReward, "広告視聴後の回数補充が反映されていません")

        app.buttons["daily_challenge_close_button"].tap()
        XCTAssertTrue(tileAttemptsLabel.waitForExistence(timeout: 2))
        XCTAssertTrue(tileAttemptsLabel.label.contains("\(initialRemaining)/\(maximumAttempts)"), "広告視聴後の回数がタイトルへ反映されていません")
    }
}
#endif
