#if canImport(UIKit)
import XCTest

/// Game Center 認証フローとインタースティシャル広告表示を確認する UI テスト
///
/// - 注意: iOS シミュレーター上でのみ動作を想定し、
///         モックサービスを利用して動作を簡略化する。
final class GameCenterAdsUITests: XCTestCase {
    /// Game Center へのサインインと広告表示の流れを検証
    func testGameCenterAuthAndInterstitialAd() {
        // テスト対象アプリを生成
        let app = XCUIApplication()
        // UI テスト用モックを利用するためのフラグを設定
        app.launchEnvironment["UITEST_MODE"] = "1"
        
        // アプリを起動
        app.launch()
        
        // --- Game Center 認証フローの確認 ---
        // タイトル画面右上の設定ボタンを開き、設定画面経由でサインインを実施する
        let settingsButton = app.buttons["設定"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5),
                      "タイトル画面の設定ボタンが見つかりません")
        settingsButton.tap()

        let gcSettingsButton = app.buttons["settings_gc_sign_in_button"]
        XCTAssertTrue(gcSettingsButton.waitForExistence(timeout: 5),
                      "設定画面の Game Center サインインボタンが表示されません")
        gcSettingsButton.tap()

        // 認証成功時のアラートが表示されるか確認し、閉じる
        let gcAlert = app.alerts["Game Center"]
        XCTAssertTrue(gcAlert.waitForExistence(timeout: 5),
                      "Game Center 認証結果のアラートが表示されません")
        gcAlert.buttons["OK"].tap()

        // ステータスラベルがサインイン済みの状態になっていることを確認
        let statusLabel = app.staticTexts["settings_gc_status_label"]
        XCTAssertTrue(statusLabel.waitForExistence(timeout: 5),
                      "Game Center 認証状態ラベルが更新されません")

        // 設定画面を閉じてゲーム画面へ戻る
        let closeSettingsButton = app.buttons["設定画面を閉じる"]
        XCTAssertTrue(closeSettingsButton.waitForExistence(timeout: 2),
                      "設定画面を閉じるボタンが見つかりません")
        closeSettingsButton.tap()

        // --- インタースティシャル広告表示の確認 ---
        // 結果画面へ遷移するボタンをタップし、広告表示トリガーとする
        // アクセシビリティ識別子 "show_result" を想定
        app.buttons["show_result"].tap()
        
        // ダミー広告ビューが表示されるか検証
        // "dummy_interstitial_ad" は AdsService 側でテスト用に設定する識別子
        let adView = app.otherElements["dummy_interstitial_ad"]
        XCTAssertTrue(adView.waitForExistence(timeout: 5),
                      "インタースティシャル広告が表示されません")
    }
}
#endif
