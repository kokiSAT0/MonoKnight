import UIKit

/// UI テストで利用するダミー広告サービス
/// 実際の広告 SDK を使わず、簡易ビューを表示する
final class AdsServiceMock: AdsServiceProtocol {
    /// 準備済みの広告を表示する
    func showInterstitial() {
        // ルート VC を取得して半透明のダミービューをモーダル表示
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        let vc = UIViewController()
        vc.view.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        // UI テストが識別できるようアクセシビリティ ID を付与
        vc.view.accessibilityIdentifier = "dummy_interstitial_ad"
        root.present(vc, animated: false) {
            // 少し待ってから自動的に閉じる
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                vc.dismiss(animated: false)
            }
        }
    }
    /// テストではフラグリセットの必要がないため空実装
    func resetPlayFlag() {}
    /// 広告をそもそも読み込まないため空実装
    func disableAds() {}
}
