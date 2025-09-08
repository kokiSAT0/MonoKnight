import Foundation
import GameKit
import UIKit

/// Game Center 関連の操作をまとめたサービス
final class GameCenterService: NSObject, GKGameCenterControllerDelegate {
    /// シングルトンインスタンス
    static let shared = GameCenterService()
    
    private override init() {}
    
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
