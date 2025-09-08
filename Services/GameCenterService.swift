import Foundation
import GameKit
import UIKit

/// Game Center 関連の操作をまとめたサービス
final class GameCenterService: NSObject, GKGameCenterControllerDelegate {
    /// シングルトンインスタンス
    static let shared = GameCenterService()

    private override init() {}

    /// スコアを Game Center のリーダーボードへ送信する
    /// - Parameter score: 送信する手数（少ないほど高評価）
    func submitScore(_ score: Int) {
        GKLeaderboard.submitScore(
            score,
            context: 0,
            player: GKLocalPlayer.local,
            leaderboardIDs: ["kc_moves_5x5"]
        ) { error in
            // エラーが発生した場合はログ出力のみ行う
            if let error {
                print("Game Center スコア送信失敗: \(error.localizedDescription)")
            }
        }
    }

    /// ランキング画面を表示する
    func showLeaderboard() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        
        // リーダーボード用のコントローラを生成
        let vc = GKGameCenterViewController()
        vc.gameCenterDelegate = self
        vc.viewState = .leaderboards
        
        // ルートビューからモーダル表示
        root.present(vc, animated: true)
    }
    
    /// Game Center コントローラの閉じるボタンが押された際に呼ばれる
    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        gameCenterViewController.dismiss(animated: true)
    }
}
