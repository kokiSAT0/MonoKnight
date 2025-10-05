#if canImport(UIKit)
import XCTest

/// カード選択フェーズの多段階フローを自動検証する UI テスト
/// - Important: `UITEST_MODE` と `UITEST_SELECTION_MODE` の環境変数を利用し、
///   デッキ構成を安定化させた状態でトースト表示とタップ遷移を確認する
final class GameCardSelectionUITests: XCTestCase {
    /// 指定した選択モードでアプリを起動し、スタンダードゲーム画面へ遷移する共通処理
    /// - Parameter mode: `UITEST_SELECTION_MODE` に適用するモード文字列（"multi" など）
    /// - Returns: 起動済みのアプリインスタンス
    @discardableResult
    private func launchGame(withSelectionMode mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_MODE"] = "1"
        app.launchEnvironment["UITEST_SELECTION_MODE"] = mode
        app.launch()

        let standardModeButton = app.buttons["mode_button_standard5x5"]
        XCTAssertTrue(standardModeButton.waitForExistence(timeout: 5), "タイトル画面でスタンダードモードを選択できること")
        standardModeButton.tap()

        let startButton = app.buttons["start_game_button"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5), "ゲーム開始ボタンが表示されること")
        XCTAssertTrue(startButton.isEnabled, "モード選択後はゲーム開始ボタンが有効になること")
        startButton.tap()

        let firstSlot = app.otherElements["hand_slot_0"]
        XCTAssertTrue(firstSlot.waitForExistence(timeout: 5), "ゲーム画面で手札スロットが描画されること")

        addTeardownBlock {
            app.terminate()
        }

        return app
    }

    /// 複数ベクトルカードで目的地選択トーストが表示され、タップ確定で閉じることを確認する
    func testMultiVectorCardTriggersSelectionToast() {
        let app = launchGame(withSelectionMode: "multi")
        let firstSlot = app.otherElements["hand_slot_0"]
        firstSlot.tap()

        let toast = app.otherElements["card_selection_phase_toast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3), "複数候補カード選択時にフェーズトーストが表示されること")
        XCTAssertEqual(toast.label, "ハイライトされたマスから移動先をタップしてください。", "複数候補カード用の文言が表示されること")

        // 盤面中央付近のタイルをタップし、選択確定でトーストが閉じることを検証する
        let window = app.windows.element(boundBy: 0)
        let targetCoordinate = window.coordinate(withNormalizedOffset: CGVector(dx: 0.68, dy: 0.42))
        targetCoordinate.tap()

        let dismissExpectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: toast)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissExpectation], timeout: 4), .completed, "目的地確定後にトーストが閉じること")
    }

    /// 盤面全体選択モードでトースト文言が切り替わることを確認する
    func testBoardWideSelectionShowsBoardWideMessage() {
        let app = launchGame(withSelectionMode: "board")
        let firstSlot = app.otherElements["hand_slot_0"]
        firstSlot.tap()

        let toast = app.otherElements["card_selection_phase_toast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3), "盤面全体選択時にフェーズトーストが表示されること")
        XCTAssertEqual(toast.label, "任意のマスをタップして移動先を決定してください。", "盤面全体選択向けの案内文が表示されること")

        // 任意座標をタップして選択を確定し、トーストが消えることを確認する
        let window = app.windows.element(boundBy: 0)
        let targetCoordinate = window.coordinate(withNormalizedOffset: CGVector(dx: 0.32, dy: 0.36))
        targetCoordinate.tap()

        let dismissExpectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: toast)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissExpectation], timeout: 4), .completed, "任意マス選択後にトーストが閉じること")
    }
}
#endif
