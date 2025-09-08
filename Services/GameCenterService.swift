import Foundation
import GameKit
import UIKit
import SwiftUI // @AppStorage を利用するために追加

/// Game Center 操作に必要なインターフェースを定義するプロトコル
/// - NOTE: 認証やスコア送信をテストしやすくするために利用する
protocol GameCenterServiceProtocol: AnyObject {
    /// 現在認証済みであるかどうか
    var isAuthenticated: Bool { get }
    /// ローカルプレイヤーの認証を行う
    /// - Parameter completion: 認証結果を受け取るクロージャ
    func authenticateLocalPlayer(completion: ((Bool) -> Void)?)
    /// リーダーボードへスコアを送信する
    /// - Parameter score: 送信する手数
    func submitScore(_ score: Int)
    /// ランキング画面を表示する
    func showLeaderboard()
}

/// Game Center 関連の操作をまとめたサービス
/// 実際に Game Center と連携する実装
final class GameCenterService: NSObject, GKGameCenterControllerDelegate, GameCenterServiceProtocol {
    /// シングルトンインスタンス
    static let shared = GameCenterService()

    private override init() {}

    // MARK: - 永続フラグ

    /// Game Center へ初回スコア送信済みかどうかを保持するフラグ
    /// @AppStorage を利用して UserDefaults へ自動保存する
    /// - Note: 設定画面やデバッグからリセットできるよう公開メソッドを用意する
    @AppStorage("has_submitted_gc") private var hasSubmittedGC: Bool = false

    /// Game Center へログイン済みかどうかを保持するフラグ
    /// - Note: 認証に失敗した場合は `false` のままとなる
    private(set) var isAuthenticated = false

    /// ローカルプレイヤーを Game Center で認証する
    /// - Parameters:
    ///   - completion: 認証結果を受け取るクロージャ（省略可能）
    /// - Note: UI から呼び出し、完了後に状態を更新する想定
    func authenticateLocalPlayer(completion: ((Bool) -> Void)? = nil) {
        // --- テストモード判定 ---
        // 環境変数 "GC_TEST_ACCOUNT" に値が入っている場合は
        // ダミー認証を行い、GameKit の UI を全てスキップする
        if let testAccount = ProcessInfo.processInfo.environment["GC_TEST_ACCOUNT"],
           !testAccount.isEmpty {
            // テスト用ダミー認証: 即座に認証済みフラグを立てる
            // 実際の Game Center には接続しない
            isAuthenticated = true
            print("GC_TEST_ACCOUNT=\(testAccount) によるダミー認証を実行")
            completion?(true) // 呼び出し元へ成功を通知して終了
            return
        }

        // --- 通常モードの認証フロー ---
        // ローカルプレイヤーの取得
        let player = GKLocalPlayer.local

        // GameKit が提供する認証ハンドラを設定
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
                // 認証成功: フラグを更新しログ出力
                self?.isAuthenticated = true
                print("Game Center 認証成功")
                completion?(true) // 呼び出し元へ成功を通知
            } else {
                // 認証失敗: エラーメッセージをログ出力
                self?.isAuthenticated = false
                let message = error?.localizedDescription ?? "不明なエラー"
                print("Game Center 認証失敗: \(message)")
                completion?(false) // 呼び出し元へ失敗を通知
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

        // 既に送信済みの場合は再送信を避ける
        guard !hasSubmittedGC else {
            // デバッグ時に重複送信されないようログを残す
            print("Game Center スコアは既に送信済みのためスキップ")
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
                // 成功した場合は再送信を防ぐためフラグを更新
                self.hasSubmittedGC = true
            }
        }
    }

    // MARK: - デバッグ／設定用ユーティリティ

    /// スコア送信済みフラグをリセットする
    /// - Note: 設定画面やテスト時に初期状態へ戻したい場合に利用する
    func resetSubmittedFlag() {
        // フラグを false に戻すことで再送信が可能になる
        hasSubmittedGC = false
        print("Game Center スコア送信フラグをリセットしました")
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
