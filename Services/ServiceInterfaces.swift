import Combine
import Foundation
import Game

// MARK: - プラットフォームサービス共通プロトコル
/// Game Center / AdMob / StoreKit を横断して依存注入しやすくするための共通インターフェース定義。
/// UI テストやプレビューで実装を差し替えることを想定し、サービスごとに最小限の機能を公開する。

// MARK: Game Center
@MainActor
protocol GameCenterServiceProtocol: AnyObject {
    /// 現在 Game Center へ認証済みかどうかを確認する。
    var isAuthenticated: Bool { get }
    /// ローカルプレイヤーの認証を試みる。
    /// - Parameter completion: 認証完了後に呼び出されるクロージャ（省略可能）。
    func authenticateLocalPlayer(completion: ((Bool) -> Void)?)
    /// 指定したモード用リーダーボードへスコアを送信する。
    /// - Parameters:
    ///   - score: 投稿するスコア値。
    ///   - modeIdentifier: 対象モードの識別子。
    func submitScore(_ score: Int, for modeIdentifier: GameMode.Identifier)
    /// 指定モードのリーダーボードを表示する。
    /// - Parameter modeIdentifier: 表示対象モードの識別子。
    func showLeaderboard(for modeIdentifier: GameMode.Identifier)
}

// MARK: AdMob
@MainActor
protocol AdsServiceProtocol: AnyObject {
    /// インタースティシャル広告を表示する。
    func showInterstitial()
    /// プレイ開始フラグをリセットし、広告表示条件を初期化する。
    func resetPlayFlag()
    /// 広告読み込みを完全に停止する（IAP 購入時などに利用）。
    func disableAds()
    /// ATT（アプリトラッキング許可）をリクエストする。
    func requestTrackingAuthorization() async
    /// UMP（ユーザー同意）を必要に応じて提示する。
    func requestConsentIfNeeded() async
    /// 同意状態を最新化する。
    func refreshConsentStatus() async
}

// MARK: StoreKit
@MainActor
protocol StoreServiceProtocol: ObservableObject, AnyObject {
    /// 広告除去オプションが購入済みかどうかを公開する。
    var isRemoveAdsPurchased: Bool { get }
    /// 表示用の価格テキスト。商品情報取得前は `nil`。
    var removeAdsPriceText: String? { get }
    /// 商品情報の取得や再取得を行う。
    func refreshProducts() async
    /// 広告除去商品の購入フローを開始する。
    func purchaseRemoveAds() async
    /// App Store と同期して購入履歴を復元する。
    /// - Returns: 復元処理が成功したかどうか。
    func restorePurchases() async -> Bool
}
