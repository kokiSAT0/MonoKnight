#if canImport(UIKit)
import XCTest

/// Game Center 認証フローとインタースティシャル広告表示を確認する UI テスト
/// 
/// - 注意: iOS シミュレーター上でのみ動作を想定し、
///         ダミーアカウントとテスト用広告ユニット ID を利用する。
final class GameCenterAdsUITests: XCTestCase {
    /// テスト用 Game Center アカウント名
    private let dummyGameCenterAccount = "GCTestUser1"
    
    /// Google 提供のテスト用インタースティシャル広告ユニット ID
    /// 実機配信では必ず差し替えること
    private let dummyInterstitialID = "ca-app-pub-3940256099942544/4411468910"
    
    /// Game Center へのサインインと広告表示の流れを検証
    func testGameCenterAuthAndInterstitialAd() {
        // テスト対象アプリを生成
        let app = XCUIApplication()
        
        // --- 環境変数の設定 ---
        // ダミー Game Center アカウントとダミー広告ユニット ID を渡す
        app.launchEnvironment["GC_TEST_ACCOUNT"] = dummyGameCenterAccount
        app.launchEnvironment["GAD_INTERSTITIAL_ID"] = dummyInterstitialID
        
        // アプリを起動
        app.launch()
        
        // --- Game Center ダミー認証の確認 ---
        // テストモードではアプリ起動直後に認証済みラベルが表示される
        let authedLabel = app.staticTexts["gc_authenticated"]
        XCTAssertTrue(authedLabel.waitForExistence(timeout: 5),
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
