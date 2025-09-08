import Foundation
import GoogleMobileAds
import UIKit
import SwiftUI

/// インタースティシャル広告を管理するサービス
/// ゲーム終了時に ResultView から呼び出される
final class AdsService: NSObject, ObservableObject {
    /// シングルトンインスタンス
    static let shared = AdsService()
    
    /// ロード済みのインタースティシャル広告
    private var interstitial: GADInterstitialAd?

    /// 広告除去購入済みフラグ（UserDefaults と連携）
    @AppStorage("remove_ads") private var removeAds: Bool = false
    
    private override init() {
        super.init()
        // 購入済みでなければアプリ起動直後に広告をプリロードしておく
        if !removeAds {
            loadInterstitial()
        }
    }
    
    /// インタースティシャル広告を読み込む
    private func loadInterstitial() {
        // 広告除去購入済みであれば何もしない
        guard !removeAds else { return }

        let request = GADRequest()
        // テスト用広告ユニット ID（実装時に差し替え）
        GADInterstitialAd.load(withAdUnitID: "ca-app-pub-3940256099942544/4411468910", request: request) { [weak self] ad, error in
            if let error = error {
                // 読み込み失敗時はログを出力
                print("広告の読み込み失敗: \(error.localizedDescription)")
                return
            }
            // 正常に取得できたら保持
            self?.interstitial = ad
        }
    }
    
    /// 準備済みの広告があれば表示する
    func showInterstitial() {
        // 購入済みなら広告を表示しない
        guard !removeAds,
              let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController,
              let ad = interstitial else { return }

        // 現在のルートビューから広告を表示
        ad.present(fromRootViewController: root)
        // 表示後は破棄して次回に備えて再読み込み（未購入時のみ）
        interstitial = nil
        loadInterstitial()
    }

    /// 購入済みのときに既存広告を破棄し、以降読み込まないようにする
    func disableAds() {
        interstitial = nil
    }
}
