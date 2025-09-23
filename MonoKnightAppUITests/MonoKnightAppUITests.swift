//
//  MonoKnightAppUITests.swift
//  MonoKnightAppUITests
//
//  Created by koki sato on 2025/09/10.
//

import XCTest

final class MonoKnightAppUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testHandSlotAccessibilityReflectsStackState() throws {
        // ゲーム画面を起動し、初期状態の手札スロットを取得する
        let app = XCUIApplication()
        app.launch()

        let firstSlot = app.otherElements["hand_slot_0"]
        XCTAssertTrue(firstSlot.waitForExistence(timeout: 5), "手札スロットが VoiceOver から参照できることを確認")

        // ラベルには「方向＋残枚数」が含まれている想定
        XCTAssertTrue(firstSlot.label.contains("残り"), "ラベルに残枚数の読み上げが含まれていること")
        XCTAssertTrue(firstSlot.label.contains("枚"), "ラベルに枚数単位が含まれていること")

        // KVC でヒント文を取得し、スタック仕様が案内されているか検証する
        let hintText = firstSlot.value(forKey: "hint") as? String
        XCTAssertNotNil(hintText, "ヒント文が設定されていること")
        if let hintText {
            XCTAssertTrue(hintText.contains("スタック"), "ヒントにスタック挙動の説明が含まれていること")
        }
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
