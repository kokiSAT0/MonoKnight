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
            guard let self else { return }

            // 認証のための ViewController が渡された場合は表示を行う
            if let vc {
                // UI 提示系の処理は必ずメインスレッドでまとめて実行する
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    // 最前面のシーンとキーウィンドウから提示用の ViewController を取得
                    guard let root = self.presentableRootViewController() else {
                        // ルート取得に失敗した場合はログを出力し、未認証扱いで完了を通知
                        debugLog("Game Center 認証 UI のルート取得に失敗したため再試行が必要")
                        self.isAuthenticated = false
                        completion?(false)
                        return
                    }
                    root.present(vc, animated: true)
                }
                return
            }

            // 認証結果を判定
            if player.isAuthenticated {
                // 認証成功時の処理をメインスレッドで反映
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.isAuthenticated = true
                    debugLog("Game Center 認証成功")
                    // 認証が完了したのでアクセスポイントを表示
                    self.activateAccessPoint()
                    completion?(true) // 呼び出し元へ成功を通知
                }
            } else {
                let authError = error
                // 認証失敗時もメインスレッドで状態更新と通知を行う
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.isAuthenticated = false
                    if let authError {
                        // エラーオブジェクトが存在する場合は詳細を出力
                        debugError(authError, message: "Game Center 認証失敗")
                    } else {
                        // それ以外はメッセージのみ出力
                        let message = "不明なエラー"
                        debugLog("Game Center 認証失敗: \(message)")
                    }
                    completion?(false) // 呼び出し元へ失敗を通知
                }
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
        // UI 操作をメインスレッドでまとめて実行する
        DispatchQueue.main.async { [weak self] in
            self?.deactivateAccessPoint()
            // ルートビューからモーダル表示
            guard let root = self?.presentableRootViewController() else {
                // ルート取得に失敗した場合はログのみ出力し、UI は表示しない
                debugLog("Game Center ランキング表示用のルート取得に失敗したため表示を中止")
                return
            }
            root.present(vc, animated: true)
        }
    }

    // MARK: - 表示用ヘルパー

    /// Game Center の UI を提示するための最前面 ViewController を取得する
    /// - Note: AdsService と同様にシーン/ウィンドウ階層を考慮して探索する
    private func presentableRootViewController() -> UIViewController? {
        // --- アクティブな UIWindowScene を順番に探索して最前面の VC を探す ---
        // Game Center の UI は表示中のシーンに重ねる必要があるため、
        // foregroundActive → foregroundInactive → その他 の順で候補を評価する。
        let orderedScenes: [UIWindowScene] = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .sorted { lhs, rhs in
                // activationState.rawValue へ依存すると将来の OS 変更に弱いため、
                // 明示的な優先度マップを用意して安定したソート順を維持する。
                let priority: (UIWindowScene.ActivationState) -> Int = { state in
                    switch state {
                    case .foregroundActive:
                        return 0
                    case .foregroundInactive:
                        return 1
                    case .background:
                        return 2
                    case .unattached:
                        return 3
                    @unknown default:
                        return 4
                    }
                }
                return priority(lhs.activationState) < priority(rhs.activationState)
            }

        for scene in orderedScenes {
            // 表示中の UIWindow を抽出（非表示ウィンドウやサイズ 0 のダミーは除外）
            if let window = activeWindow(in: scene),
               let root = window.rootViewController,
               let topMost = topMostViewController(from: root) {
                return topMost
            }
        }

        // ここまでで取得できなければ nil を返し、呼び出し元でリトライする。
        return nil
    }

    /// 指定したシーン内で表示中の UIWindow を返す
    /// - Parameter scene: 探索対象の UIWindowScene
    /// - Returns: 表示中の UIWindow（見つからない場合は nil）
    private func activeWindow(in scene: UIWindowScene) -> UIWindow? {
        // isKeyWindow を最優先にしつつ、非表示ウィンドウやオーバーレイ用の 0 サイズウィンドウを除外して探索する
        let visibleWindows = scene.windows.filter { window in
            // 完全に隠れているウィンドウや画面外にあるウィンドウはプレゼンテーションに使えないため除外
            let isVisible = !window.isHidden && window.alpha > 0 && window.bounds != .zero
            return isVisible
        }

        if let keyWindow = visibleWindows.first(where: { $0.isKeyWindow }) {
            return keyWindow
        }

        // キーウィンドウが取得できない場合でも、先頭の可視ウィンドウを返して最前面 VC を辿れるようにする
        return visibleWindows.first
    }

    /// モーダル/ナビゲーション/タブ構成を考慮して最前面の ViewController を探索する
    private func topMostViewController(from controller: UIViewController?) -> UIViewController? {
        guard let controller else { return nil }

        // モーダル表示中であれば更に提示中の画面を優先する
        if let presented = controller.presentedViewController {
            return topMostViewController(from: presented)
        }

        // ナビゲーションコントローラは可視 VC（無ければトップ）を辿る
        if let navigation = controller as? UINavigationController {
            return topMostViewController(from: navigation.visibleViewController ?? navigation.topViewController)
        }

        // タブバーコントローラは選択中のタブ配下を探索
        if let tab = controller as? UITabBarController {
            return topMostViewController(from: tab.selectedViewController)
        }

        // SplitViewController は最後尾（詳細側）を辿って提示中の画面を取得
        if let split = controller as? UISplitViewController {
            return topMostViewController(from: split.viewControllers.last)
        }

        // 上記に該当しない場合は現在のコントローラが最前面
        return controller
    }

    /// Game Center コントローラの閉じるボタンが押された際に呼ばれる
    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        gameCenterViewController.dismiss(animated: true)
        // ランキングを閉じたらアクセスポイントを再表示
        activateAccessPoint()
    }
}
