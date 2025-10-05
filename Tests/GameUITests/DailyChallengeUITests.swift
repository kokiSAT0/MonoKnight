#if canImport(UIKit)
import XCTest

/// 日替わりチャレンジ画面の UI を自動検証するテスト
/// - Note: `UITEST_MODE` 環境変数でモックサービスを注入し、挑戦回数ストアや広告サービスの挙動を決定論的にする
final class DailyChallengeUITests: XCTestCase {
    func testDailyChallengeConsumesAndRewardsAttempts() {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_MODE"] = "1"
        app.launch()

        let dailyTile = app.otherElements["title_tile_daily_challenge"]
        XCTAssertTrue(dailyTile.waitForExistence(timeout: 5), "タイトル画面に日替わりカードが表示されること")
        dailyTile.tap()

        let dailyView = app.otherElements["daily_challenge_view"]
        XCTAssertTrue(dailyView.waitForExistence(timeout: 5), "日替わりチャレンジ画面へ遷移できること")

        let fixedCard = app.otherElements["daily_challenge_stage_card_fixed"]
        XCTAssertTrue(fixedCard.waitForExistence(timeout: 5), "固定レギュレーション用カードが表示されること")

        let randomCard = app.otherElements["daily_challenge_stage_card_random"]
        XCTAssertTrue(randomCard.waitForExistence(timeout: 5), "ランダムレギュレーション用カードが表示されること")

        let remainingLabel = app.staticTexts["daily_challenge_remaining_label"]
        XCTAssertTrue(remainingLabel.waitForExistence(timeout: 5), "残り挑戦回数ラベルが表示されること")
        XCTAssertTrue(remainingLabel.label.contains("残り 1 回"), "初回は無料挑戦が 1 回残っている想定")

        let fixedStartButton = app.buttons["daily_challenge_start_button_fixed"]
        XCTAssertTrue(fixedStartButton.waitForExistence(timeout: 5), "固定モード用の挑戦ボタンが存在すること")
        XCTAssertTrue(fixedStartButton.isEnabled, "挑戦回数が残っている場合は固定モードの開始ボタンが有効であること")
        fixedStartButton.tap()

        let overlay = app.otherElements["game_preparation_overlay"]
        XCTAssertTrue(overlay.waitForExistence(timeout: 5), "挑戦開始後に準備オーバーレイが表示されること")
        let returnButton = app.buttons["game_preparation_return_button"]
        XCTAssertTrue(returnButton.waitForExistence(timeout: 5), "準備オーバーレイに戻るボタンが用意されていること")
        returnButton.tap()

        XCTAssertTrue(dailyTile.waitForExistence(timeout: 5), "タイトルへ戻った後も日替わりカードが再表示されること")
        dailyTile.tap()
        XCTAssertTrue(dailyView.waitForExistence(timeout: 5), "再度日替わり画面を開けること")

        let remainingAfterStart = app.staticTexts["daily_challenge_remaining_label"]
        XCTAssertTrue(remainingAfterStart.waitForExistence(timeout: 5), "残り挑戦回数ラベルが再表示されること")
        XCTAssertTrue(remainingAfterStart.label.contains("残り 0 回"), "挑戦開始後は残り回数が 0 回になること")

        let rewardButton = app.buttons["daily_challenge_reward_button"]
        XCTAssertTrue(rewardButton.waitForExistence(timeout: 5), "広告視聴ボタンが表示されること")
        rewardButton.tap()

        let rewardStatus = app.staticTexts["daily_challenge_reward_status"]
        let rewardExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS '1 / 3'"),
            object: rewardStatus
        )
        let remainingExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS '残り 1 回'"),
            object: remainingAfterStart
        )
        XCTAssertEqual(XCTWaiter.wait(for: [rewardExpectation, remainingExpectation], timeout: 5), .completed, "広告視聴後に挑戦回数が 1 回ぶん回復し、付与済み回数が更新されること")

        let randomStartButton = app.buttons["daily_challenge_start_button_random"]
        XCTAssertTrue(randomStartButton.waitForExistence(timeout: 5), "ランダムモード用の挑戦ボタンが存在すること")
        let startEnabledExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isEnabled == true"),
            object: randomStartButton
        )
        XCTAssertEqual(XCTWaiter.wait(for: [startEnabledExpectation], timeout: 5), .completed, "広告視聴後にランダムモードの開始ボタンが有効化されること")
        randomStartButton.tap()

        XCTAssertTrue(overlay.waitForExistence(timeout: 5), "ランダムモード開始後にも準備オーバーレイが表示されること")
        XCTAssertTrue(returnButton.waitForExistence(timeout: 5), "ランダム挑戦後も戻るボタンが表示されること")
        returnButton.tap()

        let closeButton = app.buttons["daily_challenge_back_button"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 3), "日替わり画面へ戻るボタンが表示されること")
        closeButton.tap()
    }
}
#endif
