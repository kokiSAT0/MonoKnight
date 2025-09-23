//
//  MonoKnightAppUITests.swift
//  MonoKnightAppUITests
//
//  Created by koki sato on 2025/09/10.
//

import XCTest

final class MonoKnightAppUITests: XCTestCase {

    /// 各テストで再利用するアプリケーションインスタンス
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        // 1 テストで失敗したら即座に中断し、以降の操作が副作用を生まないようにする
        continueAfterFailure = false
        // テストごとにクリーンなアプリインスタンスを生成し、前テストの状態が残らないように初期化する
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        // 後続テストに前回のインスタンスが残らないよう明示的に破棄する
        app = nil
    }

    @MainActor
    func testExample() throws {
        // アプリを起動し、タイトル画面が最初に表示されることを前提とした基本状態を整える
        app.launch()

        // アプリタイトルのラベルが表示されているか検証し、起動直後にタイトル画面へ留まっていることを確かめる
        let titleLabel = app.staticTexts["MonoKnight"]
        XCTAssertTrue(titleLabel.waitForExistence(timeout: 5), "起動直後にタイトルラベルが表示されること")

        // ゲーム開始ボタンがタップ可能な状態で存在するか確認し、ユーザーがすぐに操作できる導線を担保する
        let startButton = app.buttons["title_start_button"]
        XCTAssertTrue(startButton.exists, "タイトル画面にゲーム開始ボタンが配置されていること")

        // 遊び方ボタンも同時に表示されているか確認し、ヘルプ導線の欠落を防ぐ
        let howToPlayButton = app.buttons["title_how_to_play_button"]
        XCTAssertTrue(howToPlayButton.waitForExistence(timeout: 5), "タイトル画面で遊び方ボタンにアクセスできること")
    }

    @MainActor
    func testHandSlotAccessibilityReflectsStackState() throws {
        // ゲーム画面を起動し、初期状態の手札スロットを取得する
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

    @MainActor
    func testTitleToGameTransitionDisplaysHandSlots() throws {
        // タイトル画面からゲーム開始までを自動操作し、基本的な遷移が成立するか検証する
        app.launch()

        // ゲーム開始ボタンが表示されるまで待機し、確実にタップできる状態を捉える
        let startButton = app.buttons["title_start_button"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5), "ゲーム開始ボタンが表示されること")

        // 開始ボタンをタップしてプレイ画面への遷移を進める
        startButton.tap()

        // ローディング解除後に手札スロットが表示されることを確認し、実際にゲーム画面へ移ったと判断する
        let firstHandSlot = app.otherElements["hand_slot_0"]
        XCTAssertTrue(firstHandSlot.waitForExistence(timeout: 5), "ゲーム画面で最初の手札スロットが表示されること")

        // タイトル用の開始ボタンが非表示になっていることを確認し、重ね表示による誤タップの可能性を排除する
        XCTAssertFalse(startButton.exists, "ゲーム遷移後はタイトルの開始ボタンが残っていないこと")
    }
}
