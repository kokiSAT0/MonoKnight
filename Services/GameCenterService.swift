import Foundation
import Game      // debugLog / debugError などゲームロジック側のデバッグユーティリティと GameMode 識別子を利用するために追加
import GameKit
import UIKit

/// Game Center で利用するリーダーボードの定義をまとめたカタログ構造体
/// - NOTE: `docs/game-center-leaderboards.md` に掲載している一覧と同期しやすいよう、
///         参照名・Leaderboard ID・対応モードをここで一元管理する
private struct GameCenterLeaderboardCatalog {
    /// 1 つのリーダーボードに関するメタ情報
    struct Entry {
        /// App Store Connect 上で設定するリファレンス名
        let referenceName: String
        /// Leaderboard ID（`Leaderboard ID` 欄で設定する文字列）
        let leaderboardID: String
        /// このリーダーボードへスコア送信するゲームモードの集合
        let supportedModes: Set<GameMode.Identifier>
    }

    /// テスト版スタンダードモード向けリーダーボード
    /// - Important: リファレンス名・ID はドキュメントと完全一致させる
    static let standardTest = Entry(
        referenceName: "[TEST] Standard Leaderboard",
        leaderboardID: "test_standard_moves_v1",
        supportedModes: [.standard5x5]
    )

    /// テスト版クラシカルチャレンジ向けリーダーボード
    static let classicalChallengeTest = Entry(
        referenceName: "[TEST] Classical Challenge Leaderboard",
        leaderboardID: "test_classical_moves_v1",
        supportedModes: [.classicalChallenge]
    )

    /// 定義済みのリーダーボード一覧
    static let allEntries: [Entry] = [standardTest, classicalChallengeTest]

    /// 指定したゲームモードに対応するリーダーボードを返す
    /// - Parameter identifier: 判定対象となるゲームモード識別子
    /// - Returns: マッチするリーダーボード定義。未定義の場合は `nil`
    static func entry(for identifier: GameMode.Identifier) -> Entry? {
        allEntries.first { $0.supportedModes.contains(identifier) }
    }
}

/// Game Center 操作に必要なインターフェースを定義するプロトコル
/// - NOTE: 認証やスコア送信をテストしやすくするために利用する
protocol GameCenterServiceProtocol: AnyObject {
    /// 現在認証済みであるかどうか
    var isAuthenticated: Bool { get }
    /// ローカルプレイヤーの認証を行う
    /// - Parameter completion: 認証結果を受け取るクロージャ
    func authenticateLocalPlayer(completion: ((Bool) -> Void)?)
    /// リーダーボードへスコア（ポイント）を送信する
    /// - Parameters:
    ///   - score: 送信するポイント値
    ///   - modeIdentifier: スコアを送信したゲームモードの識別子
    func submitScore(_ score: Int, for modeIdentifier: GameMode.Identifier)
    /// ランキング画面を表示する
    /// - Parameter modeIdentifier: 表示したいリーダーボードが紐付くゲームモード識別子
    func showLeaderboard(for modeIdentifier: GameMode.Identifier)
}

/// Game Center 関連の操作をまとめたサービス
/// 実際に Game Center と連携する実装
final class GameCenterService: NSObject, GKGameCenterControllerDelegate, GameCenterServiceProtocol {
    /// シングルトンインスタンス
    static let shared = GameCenterService()

    /// UserDefaults アクセスを司るインスタンス
    private let userDefaults = UserDefaults.standard
    /// 送信済みフラグを保存するためのキー
    private let hasSubmittedDictionaryKey = "gc_has_submitted_by_leaderboard"
    /// 送信済みスコアを保存するためのキー
    private let lastScoreDictionaryKey = "gc_last_score_by_leaderboard"

    private override init() {}

    /// Game Center へログイン済みかどうかを保持するフラグ
    /// - Note: 認証に失敗した場合は `false` のままとなる
    private(set) var isAuthenticated = false

    // MARK: - 送信状況の読み書きヘルパー

    /// 指定したリーダーボード ID の送信済みフラグを取得する
    private func hasSubmittedScore(for leaderboardID: String) -> Bool {
        let stored = userDefaults.dictionary(forKey: hasSubmittedDictionaryKey) as? [String: Bool]
        return stored?[leaderboardID] ?? false
    }

    /// 指定したリーダーボード ID の最終送信スコアを取得する
    private func lastSubmittedScore(for leaderboardID: String) -> Int {
        let stored = userDefaults.dictionary(forKey: lastScoreDictionaryKey) as? [String: Int]
        return stored?[leaderboardID] ?? .max
    }

    /// 指定したリーダーボードの送信状況を更新する
    private func updateSubmissionRecord(for leaderboardID: String, with score: Int) {
        var flagDictionary = (userDefaults.dictionary(forKey: hasSubmittedDictionaryKey) as? [String: Bool]) ?? [:]
        flagDictionary[leaderboardID] = true
        if flagDictionary.isEmpty {
            userDefaults.removeObject(forKey: hasSubmittedDictionaryKey)
        } else {
            userDefaults.set(flagDictionary, forKey: hasSubmittedDictionaryKey)
        }

        var scoreDictionary = (userDefaults.dictionary(forKey: lastScoreDictionaryKey) as? [String: Int]) ?? [:]
        let previousScore = scoreDictionary[leaderboardID] ?? .max
        scoreDictionary[leaderboardID] = min(score, previousScore)
        if scoreDictionary.isEmpty {
            userDefaults.removeObject(forKey: lastScoreDictionaryKey)
        } else {
            userDefaults.set(scoreDictionary, forKey: lastScoreDictionaryKey)
        }
    }

    /// 指定したリーダーボードの送信状況をリセットする
    private func resetSubmissionRecord(for leaderboardID: String) {
        var flagDictionary = (userDefaults.dictionary(forKey: hasSubmittedDictionaryKey) as? [String: Bool]) ?? [:]
        flagDictionary.removeValue(forKey: leaderboardID)
        if flagDictionary.isEmpty {
            userDefaults.removeObject(forKey: hasSubmittedDictionaryKey)
        } else {
            userDefaults.set(flagDictionary, forKey: hasSubmittedDictionaryKey)
        }

        var scoreDictionary = (userDefaults.dictionary(forKey: lastScoreDictionaryKey) as? [String: Int]) ?? [:]
        scoreDictionary.removeValue(forKey: leaderboardID)
        if scoreDictionary.isEmpty {
            userDefaults.removeObject(forKey: lastScoreDictionaryKey)
        } else {
            userDefaults.set(scoreDictionary, forKey: lastScoreDictionaryKey)
        }
    }

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
    /// - Parameter score: 送信するポイント（少ないほど高評価）
    func submitScore(_ score: Int, for modeIdentifier: GameMode.Identifier) {
        // 未認証の場合はスコア送信を行わない
        guard isAuthenticated else {
            // 未認証状態で呼ばれた際の注意をログ出力
            debugLog("Game Center 未認証のためスコア送信を中止")
            return
        }

        // 指定モードに対応するリーダーボードが存在するか確認
        guard let entry = GameCenterLeaderboardCatalog.entry(for: modeIdentifier) else {
            // まだリーダーボード未整備のモードでは送信しない
            debugLog("Game Center: モード \(modeIdentifier.rawValue) に対応するテスト用リーダーボードが未定義のため送信をスキップ")
            return
        }

        // 送信要否を判定。未送信またはベスト更新時のみ送る
        let hasSubmitted = hasSubmittedScore(for: entry.leaderboardID)
        let previousScore = lastSubmittedScore(for: entry.leaderboardID)
        let shouldSubmit = (!hasSubmitted) || (score < previousScore)

        guard shouldSubmit else {
            // 送信済みスコアより悪化している場合はリーダーボード更新を行わない
            debugLog("Game Center 既存スコア (\(previousScore)) 以下のため送信をスキップ: \(score)")
            return
        }

        GKLeaderboard.submitScore(
            score,
            context: 0,
            player: GKLocalPlayer.local,
            leaderboardIDs: [entry.leaderboardID]
        ) { [weak self] error in
            // エラーが発生した場合はログ出力のみ行う
            if let error {
                // 送信失敗時は詳細なエラーログを出力
                debugError(error, message: "Game Center スコア送信失敗")
            } else {
                // 成功時はスコアをログ出力
                debugLog("Game Center スコア送信成功: \(score)")
                // 成功した場合は再送信を防ぐためフラグを更新
                guard let self else { return }
                self.updateSubmissionRecord(for: entry.leaderboardID, with: score)
            }
        }
    }

    // MARK: - デバッグ／設定用ユーティリティ

    /// スコア送信済みフラグをリセットする
    /// - Note: 設定画面やテスト時に初期状態へ戻したい場合に利用する
    /// - Parameter modeIdentifier: リセット対象のモード。`nil` の場合は全モードを対象とする
    func resetSubmittedFlag(for modeIdentifier: GameMode.Identifier? = nil) {
        if let identifier = modeIdentifier {
            guard let entry = GameCenterLeaderboardCatalog.entry(for: identifier) else {
                debugLog("Game Center リセット要求: モード \(identifier.rawValue) に対応するリーダーボードが未定義のため処理を中断")
                return
            }
            resetSubmissionRecord(for: entry.leaderboardID)
            debugLog("Game Center スコア送信フラグをリセットしました (対象モード: \(identifier.rawValue))")
        } else {
            for entry in GameCenterLeaderboardCatalog.allEntries {
                resetSubmissionRecord(for: entry.leaderboardID)
            }
            debugLog("Game Center スコア送信フラグを全モード分リセットしました")
        }
    }

    /// ランキング画面を表示する
    func showLeaderboard(for modeIdentifier: GameMode.Identifier) {
        // 未認証の場合はランキングを表示しない
        guard isAuthenticated else {
            // 未認証のままランキング表示を要求された場合のログ
            debugLog("Game Center 未認証のためランキング表示不可")
            return
        }

        // リーダーボードの表示対象を決定。モード未定義の場合は先頭のテストボードを利用
        let entry = GameCenterLeaderboardCatalog.entry(for: modeIdentifier) ?? GameCenterLeaderboardCatalog.allEntries.first

        guard let targetEntry = entry else {
            debugLog("Game Center: 表示可能なリーダーボードが定義されていないためランキングを開けません")
            return
        }

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }

        // リーダーボード用のコントローラを生成
        // - Note: iOS14 以降で推奨される `leaderboardID` 指定の初期化メソッドを利用する
        //         これによりデプリケーション警告を解消しつつ、従来と同じ ID／スコープを適用できる
        let vc = GKGameCenterViewController(
            leaderboardID: targetEntry.leaderboardID,     // モードに応じたテスト用リーダーボード ID を明示
            playerScope: .global,              // これまで通り全世界ランキングを参照
            timeScope: .allTime                // 通算ランキング表示（過去の挙動を維持）
        )
        // 初期化時に ID・スコープを渡しているため、deprecated なプロパティ再設定は不要
        // - 補足: iOS14 で `leaderboardIdentifier` が廃止されたため、二重指定は避ける
        // デリゲート設定は従来通り維持し、閉じる操作のハンドリングを可能にする
        vc.gameCenterDelegate = self

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
