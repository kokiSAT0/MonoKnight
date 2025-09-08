import Foundation
import GameKit
import UIKit

/// Game Center 関連の操作をまとめたサービス
final class GameCenterService: NSObject, GKGameCenterControllerDelegate {
    /// シングルトンインスタンス
    static let shared = GameCenterService()

    private override init() {}

    /// Game Center へログイン済みかどうかを保持するフラグ
    /// - Note: 認証に失敗した場合は `false` のままとなる
    private(set) var isAuthenticated = false

    /// ローカルプレイヤーを Game Center で認証する
    /// - Note: アプリ起動時に一度だけ呼び出すことを想定
    func authenticateLocalPlayer() {
        // ローカルプレイヤーの取得
        let player = GKLocalPlayer.local

        // 認証ハンドラを設定
        player.authenticateHandler = { [weak self] vc, error in
            // 認証のための ViewController が渡された場合は表示を行う
            if let vc {
                // 最前面の ViewController を取得してモーダル表示
                guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                      let root = scene.windows.first?.rootViewController else { return }
                root.present(vc, animated: true)
                return
            }

            // 認証結果を判定
            if player.isAuthenticated {
                // 認証成功
                self?.isAuthenticated = true
                print("Game Center 認証成功")
            } else {
                // 認証失敗: エラーメッセージをログ出力
                self?.isAuthenticated = false
                let message = error?.localizedDescription ?? "不明なエラー"
                print("Game Center 認証失敗: \(message)")
            }
        }
    }

    /// スコアを Game Center のリーダーボードへ送信する
    /// - Parameter score: 送信する手数（少ないほど高評価）
    func submitScore(_ score: Int) {
        // 未認証の場合はスコア送信を行わない
        guard isAuthenticated else {
            print("Game Center 未認証のためスコア送信を中止")
            return
        }

        GKLeaderboard.submitScore(
            score,
            context: 0,
            player: GKLocalPlayer.local,
            leaderboardIDs: ["kc_moves_5x5"]
        ) { error in
            // エラーが発生した場合はログ出力のみ行う
            if let error {
                print("Game Center スコア送信失敗: \(error.localizedDescription)")
            } else {
                print("Game Center スコア送信成功: \(score)")
            }
        }
    }

    /// ランキング画面を表示する
    func showLeaderboard() {
        // 未認証の場合はランキングを表示しない
        guard isAuthenticated else {
            print("Game Center 未認証のためランキング表示不可")
            return
        }

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
