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

        // 選択中モードの概要カードが描画されているか検証し、新しい開始導線が表示されていることを確認する
        let summaryCard = app.otherElements["selected_mode_summary_card"]
        XCTAssertTrue(summaryCard.waitForExistence(timeout: 5), "タイトル画面にモード概要カードが表示されていること")

        // スタンダードモードのカードがタップ可能な状態で存在するか確認し、まずモード選択の導線が確保されていることをチェックする
        let standardModeButton = app.buttons["mode_button_standard5x5"]
        XCTAssertTrue(standardModeButton.exists, "スタンダードモードのカードをタップできること")

        // 新設された「ゲーム開始」ボタンが表示され、通常モードではすぐに押下できることを確認する
        let startButton = app.buttons["start_game_button"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5), "タイトル画面にゲーム開始ボタンが表示されること")
        XCTAssertTrue(startButton.isEnabled, "ステージ選択不要なモードではゲーム開始ボタンが有効になっていること")

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

        // スタンダードモードのカードをタップし、モード選択が更新されることを検証する
        let standardModeButton = app.buttons["mode_button_standard5x5"]
        XCTAssertTrue(standardModeButton.waitForExistence(timeout: 5), "スタンダードモードのカードが表示されること")
        standardModeButton.tap()

        // モード選択後にゲーム開始ボタンが有効であることを確認し、手動開始フローへ遷移できる準備が整ったと判断する
        let startButton = app.buttons["start_game_button"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5), "ゲーム開始ボタンが表示されること")
        XCTAssertTrue(startButton.isEnabled, "選択済みモードに対して開始ボタンが有効になること")
        startButton.tap()

        // ローディング解除後に手札スロットが表示されることを確認し、実際にゲーム画面へ移ったと判断する
        let firstHandSlot = app.otherElements["hand_slot_0"]
        XCTAssertTrue(firstHandSlot.waitForExistence(timeout: 5), "ゲーム画面で最初の手札スロットが表示されること")

        // タイトル用のモードカードが非表示になっていることを確認し、重ね表示による誤タップの可能性を排除する
        XCTAssertFalse(standardModeButton.exists, "ゲーム遷移後はタイトルのモードカードが残っていないこと")
    }

    @MainActor
    func testPauseMenuDisplaysPenaltyRows() throws {
        // ゲーム画面まで遷移した上でポーズメニューを開き、新設されたペナルティ一覧が表示されることを確認する
        app.launch()

        // スタンダードモードを選択し、ポーズボタンへアクセスできる状態まで進める
        let standardModeButton = app.buttons["mode_button_standard5x5"]
        XCTAssertTrue(standardModeButton.waitForExistence(timeout: 5), "スタンダードモードのカードが表示されること")
        standardModeButton.tap()

        let startButton = app.buttons["start_game_button"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5), "ゲーム開始ボタンが表示されること")
        XCTAssertTrue(startButton.isEnabled, "選択後は開始ボタンが有効になること")
        startButton.tap()

        // ゲーム画面の要素を待機してからポーズメニューを開く
        let firstHandSlot = app.otherElements["hand_slot_0"]
        XCTAssertTrue(firstHandSlot.waitForExistence(timeout: 5), "ゲーム画面で手札スロットが表示されること")

        let pauseButton = app.buttons["pause_menu_button"]
        XCTAssertTrue(pauseButton.waitForExistence(timeout: 5), "ポーズボタンが表示されること")
        pauseButton.tap()

        // ペナルティセクションと各行の文言が RootView の案内と一致することを検証する
        let penaltyHeader = app.staticTexts["ペナルティ"]
        XCTAssertTrue(penaltyHeader.waitForExistence(timeout: 5), "ポーズメニューにペナルティ見出しが表示されること")

        XCTAssertTrue(app.staticTexts["手詰まり +3 手"].waitForExistence(timeout: 5), "手詰まりペナルティの行が表示されること")
        XCTAssertTrue(app.staticTexts["引き直し +2 手"].exists, "引き直しペナルティの行が表示されること")
        XCTAssertTrue(app.staticTexts["捨て札 +1 手"].exists, "捨て札ペナルティの行が表示されること")
        XCTAssertTrue(app.staticTexts["再訪ペナルティなし"].exists, "再訪ペナルティなしの行が表示されること")
    }

    @MainActor
    func testCampaignStageSelectionEnablesManualStartAfterPreparation() throws {
        // キャンペーンセレクターからステージを選択し、ローディング解除までの流れを自動検証する
        app.launch()

        // キャンペーンへの導線が表示されていることを確認し、NavigationLink の有効性を担保する
        let campaignSelector = app.otherElements["campaign_stage_selector_link"]
        XCTAssertTrue(campaignSelector.waitForExistence(timeout: 5), "タイトル画面にキャンペーンセレクターが表示されていること")
        campaignSelector.tap()

        // Chapter3-1 のステージボタンを探し、解放済みであればタップできることを確認する
        let stageButton = app.buttons["campaign_stage_button_3-1"]
        XCTAssertTrue(stageButton.waitForExistence(timeout: 5), "キャンペーン 3-1 のステージ行が表示されること")
        stageButton.tap()

        // ステージ確定後はタイトルへ戻り、概要カードの「ゲーム開始」ボタンが有効になることを確認する
        let summaryStartButton = app.buttons["start_game_button"]
        XCTAssertTrue(summaryStartButton.waitForExistence(timeout: 5), "ステージ選択後にゲーム開始ボタンへアクセスできること")
        XCTAssertTrue(summaryStartButton.isEnabled, "ステージ確定後はゲーム開始ボタンが有効になること")

        // タイトルから開始ボタンを押してゲーム準備フローを進める
        summaryStartButton.tap()

        // 開始直後にローディングオーバーレイが表示されることを確認し、遷移が開始されたと判断する
        let overlay = app.otherElements["game_preparation_overlay"]
        XCTAssertTrue(overlay.waitForExistence(timeout: 5), "ゲーム準備用のオーバーレイが表示されること")

        // ローディング中テキストが描画されることで、初期化待ち状態へ遷移していることを担保する
        let preparingLabel = app.staticTexts["初期化中…"]
        XCTAssertTrue(preparingLabel.waitForExistence(timeout: 3), "キャンペーンステージ初期化中のラベルが一時的に表示されること")

        // 開始ボタンが最終的に有効化されるまで待機し、非同期準備が確実に完了することを検証する
        let startButton = app.buttons["ステージを開始"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5), "ゲーム開始ボタンが表示されること")
        let enableExpectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: startButton)
        let enableResult = XCTWaiter.wait(for: [enableExpectation], timeout: 5)
        XCTAssertEqual(enableResult, .completed, "ステージ準備完了後に開始ボタンが有効化されること")

        // 実際に開始ボタンをタップし、ローディングが閉じることとゲーム画面へ遷移できることを確認する
        startButton.tap()
        let overlayDismissExpectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: overlay)
        let overlayDismissResult = XCTWaiter.wait(for: [overlayDismissExpectation], timeout: 5)
        XCTAssertEqual(overlayDismissResult, .completed, "開始操作後にローディングオーバーレイが閉じること")

        // ハンドスロットが表示されることで、ローディング解除後にゲーム画面へ進めたと判断する
        let firstHandSlot = app.otherElements["hand_slot_0"]
        XCTAssertTrue(firstHandSlot.waitForExistence(timeout: 5), "ステージ開始後に手札スロットが表示されること")
    }

    @MainActor
    func testCampaignPreparationReturnButtonRestoresStageSelection() throws {
        // キャンペーンのステージ選択から準備画面へ遷移し、ローディング中に戻るボタンで即座にステージ選択へ復帰できることを検証する
        app.launch()

        // タイトル画面からキャンペーンセレクターを開く
        let campaignSelector = app.otherElements["campaign_stage_selector_link"]
        XCTAssertTrue(campaignSelector.waitForExistence(timeout: 5), "キャンペーンセレクターが表示されていること")
        campaignSelector.tap()

        // 任意の解放済みステージ（ここでは 3-1）を選択して準備対象に設定する
        let stageButton = app.buttons["campaign_stage_button_3-1"]
        XCTAssertTrue(stageButton.waitForExistence(timeout: 5), "キャンペーン 3-1 のステージが表示されること")
        stageButton.tap()

        // タイトルへ戻ったらゲーム開始ボタンを押して準備画面を開く
        let startButton = app.buttons["start_game_button"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5), "ステージ選択後にゲーム開始ボタンへアクセスできること")
        startButton.tap()

        // ローディングオーバーレイが表示された段階で戻るボタンを探す
        let overlay = app.otherElements["game_preparation_overlay"]
        XCTAssertTrue(overlay.waitForExistence(timeout: 5), "ローディングオーバーレイが表示されること")

        let returnButton = app.buttons["game_preparation_return_button"]
        XCTAssertTrue(returnButton.waitForExistence(timeout: 2), "ローディング中でも戻るボタンが操作可能であること")
        returnButton.tap()

        // 戻る操作後はオーバーレイが閉じることを確認する
        let overlayDismissExpectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: overlay)
        let overlayDismissResult = XCTWaiter.wait(for: [overlayDismissExpectation], timeout: 5)
        XCTAssertEqual(overlayDismissResult, .completed, "戻る操作でローディングオーバーレイが閉じること")

        // キャンペーンステージ一覧が即座に再表示され、同じステージを再度選択できる状態へ戻ることを検証する
        XCTAssertTrue(stageButton.waitForExistence(timeout: 5), "戻った直後にステージ選択画面へ復帰できること")
    }
}
