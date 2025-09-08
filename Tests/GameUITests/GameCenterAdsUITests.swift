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
        // サインインボタンが表示されるまで待機
        // アクセシビリティ識別子 "gc_sign_in_button" を対象
        let signInButton = app.buttons["gc_sign_in_button"]
        XCTAssertTrue(signInButton.waitForExistence(timeout: 5),
                      "Game Center のサインインボタンが表示されません")
        
        // ボタンをタップしてサインインを実行
        signInButton.tap()
        
        // サインイン完了を示すラベルが表示されるかを確認
        let authedLabel = app.staticTexts["gc_authenticated"]
        XCTAssertTrue(authedLabel.waitForExistence(timeout: 10),
                      "Game Center 認証が完了しません")
        
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
