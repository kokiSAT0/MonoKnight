import Foundation

/// インタースティシャル広告サービスの共通インターフェース
/// これにより本番用サービスとテスト用モックを切り替えられる
protocol AdsServiceProtocol {
    /// 準備済みの広告を表示する
    func showInterstitial()
    /// 新しいプレイ開始時に 1 プレイ 1 回制限フラグをリセットする
    func resetPlayFlag()
    /// 広告除去購入時に広告を無効化する
    func disableAds()
}
