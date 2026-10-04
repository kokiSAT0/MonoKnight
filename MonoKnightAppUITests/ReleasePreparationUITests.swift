import XCTest

final class ReleasePreparationUITests: XCTestCase {
    @MainActor
    func testSoundSettingsAndTowerEntry() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_MODE"] = "1"
        app.launch()
        let continueButton = app.buttons["続行"]
        if continueButton.waitForExistence(timeout: 3) { continueButton.tap() }
        let settingsButton = app.buttons["設定"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
        attach(app, name: "タイトル")
        settingsButton.tap()
        let music = app.switches["audio.musicEnabled"]
        let sound = app.switches["audio.soundEnabled"]
        XCTAssertTrue(music.waitForExistence(timeout: 5))
        XCTAssertTrue(sound.exists)
        attach(app, name: "サウンド設定")
        tapSwitchControl(music)
        XCTAssertEqual(music.value as? String, "0")
        XCTAssertEqual(sound.value as? String, "1")
        XCTAssertFalse(app.sliders["audio.musicVolume"].isEnabled)
        app.buttons["設定画面を閉じる"].tap()
        settingsButton.tap()
        XCTAssertTrue(music.waitForExistence(timeout: 5))
        XCTAssertEqual(music.value as? String, "0")
        tapSwitchControl(music)
        app.buttons["効果音を試す"].tap()
        app.buttons["設定画面を閉じる"].tap()
        app.buttons["title_tile_dungeon"].tap()
        let start = app.buttons.matching(identifier: "dungeon_card_tutorial-tower").matching(NSPredicate(format: "label == %@", "開始")).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        attach(app, name: "塔選択")
        start.tap()
        let pause = app.buttons["pause_menu_button"]
        XCTAssertTrue(pause.waitForExistence(timeout: 15))
        let intro = app.otherElements["game_preparation_overlay"]
        let introFinished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: intro)
        XCTAssertEqual(XCTWaiter.wait(for: [introFinished], timeout: 10), .completed)
        attach(app, name: "基礎塔の盤面")
        pause.tap()
        let resume = app.buttons["pause_resume_button"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        attach(app, name: "ポーズ")
        app.buttons["pause_settings_disclosure"].tap()
        attach(app, name: "ポーズ中の設定")
        resume.tap()
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
    }

    @MainActor
    func testPrivacyInformationCanBeOpenedFromSettings() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_MODE"] = "1"
        app.launch()
        let continueButton = app.buttons["続行"]
        if continueButton.waitForExistence(timeout: 3) { continueButton.tap() }
        let settings = app.buttons["設定"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let privacy = app.buttons["プライバシーについて"]
        for _ in 0..<5 {
            if privacy.exists && privacy.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(privacy.waitForExistence(timeout: 5))
        privacy.tap()
        XCTAssertTrue(app.staticTexts["端末内に保存する情報"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Googleのプライバシーポリシー"].exists)
        attach(app, name: "プライバシー説明")
    }

    @MainActor
    private func tapSwitchControl(_ element: XCUIElement) {
        // iPadでは行が広くなるため、行全体の中心ではなく右端の実スイッチを押す。
        element.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: element.frame.width - 30, dy: element.frame.height / 2))
            .tap()
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
