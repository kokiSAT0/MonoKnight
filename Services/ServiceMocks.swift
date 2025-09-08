#if canImport(UIKit)
import UIKit
import SwiftUI

/// Game Center の動作を即時成功させる UI テスト用モック
final class MockGameCenterService: GameCenterServiceProtocol {
    /// 認証状態を保持するプロパティ
    var isAuthenticated: Bool = false

    /// 即座に認証成功とし、コールバックを呼び出す
    func authenticateLocalPlayer(completion: ((Bool) -> Void)?) {
        isAuthenticated = true
        completion?(true)
    }

    /// スコア送信は行わないダミー実装
    func submitScore(_ score: Int) {}

    /// ランキング表示も行わないダミー実装
    func showLeaderboard() {}
}

/// インタースティシャル広告をダミー表示する UI テスト用モック
final class MockAdsService: AdsServiceProtocol {
    /// ダミー広告を全画面で表示する
    func showInterstitial() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        // モック用の簡易ビューを作成して表示
        let vc = UIHostingController(rootView: MockAdView())
        vc.modalPresentationStyle = .fullScreen
        root.present(vc, animated: true)
    }

    /// フラグ操作は不要なので空実装
    func resetPlayFlag() {}

    /// 広告読み込み停止も不要なので空実装
    func disableAds() {}

    /// ATT 許可ダイアログは表示しないダミー実装
    func requestTrackingAuthorization() async {}

    /// UMP 同意フォームも表示しないダミー実装
    func requestConsentIfNeeded() async {}

    /// ダミー広告ビュー
    private struct MockAdView: View {
        @Environment(\.dismiss) private var dismiss
        var body: some View {
            ZStack {
                Color.black
                Text("Test Ad")
                    .foregroundColor(.white)
            }
            .ignoresSafeArea()
            .accessibilityIdentifier("dummy_interstitial_ad")
            .onTapGesture { dismiss() }
        }
    }
}
#endif
