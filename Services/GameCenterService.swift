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

    // MARK: - GKAccessPoint 設定

    /// Game Center アクセスポイントを表示する
    /// - Note: 認証成功後に呼び出し、画面右上に常駐させる
    private func activateAccessPoint() {
        let accessPoint = GKAccessPoint.shared
        accessPoint.location = .topTrailing // 画面右上に表示
        accessPoint.isActive = true         // アクセスポイントを有効化
    }

    /// Game Center アクセスポイントを非表示にする
    /// - Note: ランキング表示中など不要な場面で利用する
    private func deactivateAccessPoint() {
        GKAccessPoint.shared.isActive = false
    }

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
            // テスト用認証を実行したことをデバッグログに残す
            debugLog("GC_TEST_ACCOUNT=\(testAccount) によるダミー認証を実行")
            // テスト環境でもアクセスポイントの有効化を試みる
            activateAccessPoint()
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
                debugLog("Game Center 認証成功")
                // 認証が完了したのでアクセスポイントを表示
                self?.activateAccessPoint()
                completion?(true) // 呼び出し元へ成功を通知
            } else {
                // 認証失敗: エラー内容をログへ出力
                self?.isAuthenticated = false
                if let error {
                    // エラーオブジェクトが存在する場合は詳細を出力
                    debugError(error, message: "Game Center 認証失敗")
                } else {
                    // それ以外はメッセージのみ出力
                    let message = "不明なエラー"
                    debugLog("Game Center 認証失敗: \(message)")
                }
                completion?(false) // 呼び出し元へ失敗を通知
            }
        }
    }

    /// スコアを Game Center のリーダーボードへ送信する
    /// - Parameter score: 送信する手数（少ないほど高評価）
    func submitScore(_ score: Int) {
        // 未認証の場合はスコア送信を行わない
        guard isAuthenticated else {
            // 未認証状態で呼ばれた際の注意をログ出力
            debugLog("Game Center 未認証のためスコア送信を中止")
            return
        }

        // 既に送信済みの場合は再送信を避ける
        guard !hasSubmittedGC else {
            // デバッグ時に重複送信されないようログを残す
            debugLog("Game Center スコアは既に送信済みのためスキップ")
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
                // 送信失敗時は詳細なエラーログを出力
                debugError(error, message: "Game Center スコア送信失敗")
            } else {
                // 成功時はスコアをログ出力
                debugLog("Game Center スコア送信成功: \(score)")
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
        // リセットしたことをデバッグログに出力
        debugLog("Game Center スコア送信フラグをリセットしました")
    }

    /// ランキング画面を表示する
    func showLeaderboard() {
        // 未認証の場合はランキングを表示しない
        guard isAuthenticated else {
            // 未認証のままランキング表示を要求された場合のログ
            debugLog("Game Center 未認証のためランキング表示不可")
            return
        }

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }

        // リーダーボード用のコントローラを生成
        // - Note: iOS17 以降で推奨される最新の初期化メソッドを使用する
        let vc = GKGameCenterViewController(state: .leaderboards)
        vc.gameCenterDelegate = self
        // 表示するリーダーボード ID を明示することで従来と同じ画面を開く
        vc.leaderboardIdentifier = "kc_moves_5x5"
        // タイムスコープも従来の仕様（通算ランキング）に合わせて設定
        vc.leaderboardTimeScope = .allTime

        // ランキング表示中はアクセスポイントが不要なので非表示にする
        deactivateAccessPoint()

        // ルートビューからモーダル表示
        root.present(vc, animated: true)
    }

    /// Game Center コントローラの閉じるボタンが押された際に呼ばれる
    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        gameCenterViewController.dismiss(animated: true)
        // ランキングを閉じたらアクセスポイントを再表示
        activateAccessPoint()
    }
}
