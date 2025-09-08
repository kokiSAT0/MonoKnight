import Foundation

/// UI テストで利用する Game Center のダミーサービス
/// 認証を即時成功扱いとし、UI 表示は行わない
final class GameCenterServiceMock: GameCenterServiceProtocol {
    /// 認証状態を保持するフラグ
    private(set) var isAuthenticated: Bool = false
    /// ローカルプレイヤーを即時認証済みにする
    func authenticateLocalPlayer() {
        isAuthenticated = true
    }
    /// スコア送信はテストでは不要なので空実装
    func submitScore(_ score: Int) {}
    /// ランキング画面も表示しない
    func showLeaderboard() {}
}
