import Foundation

/// Game Center 関連機能の共通インターフェース
/// 認証・スコア送信・ランキング表示を抽象化する
protocol GameCenterServiceProtocol {
    /// 認証済みかどうかの状態
    var isAuthenticated: Bool { get }
    /// ローカルプレイヤーを認証する
    func authenticateLocalPlayer()
    /// スコアをリーダーボードへ送信する
    func submitScore(_ score: Int)
    /// ランキング画面を表示する
    func showLeaderboard()
}
