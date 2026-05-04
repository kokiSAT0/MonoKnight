import Foundation
import Game
import GameKit
import SharedSupport
import UIKit

typealias GameCenterAuthenticationHandlerInstaller = (@escaping (UIViewController?, Bool, Error?) -> Void) -> Void
typealias GameCenterScoreSubmitter = (_ score: Int, _ leaderboardID: String, _ completion: @escaping @Sendable (Error?) -> Void) -> Void

struct GameCenterServiceTestHooks {
    var currentAuthenticationStateProvider: (() -> Bool)?
    var testAccountProvider: (() -> String?)?
    var authenticateHandlerInstaller: GameCenterAuthenticationHandlerInstaller?
    var scoreSubmitter: GameCenterScoreSubmitter?
    var mainAsync: ((@escaping @MainActor @Sendable () -> Void) -> Void)?

    static let live = GameCenterServiceTestHooks()
}

/// Game Center リーダーボード設定を Info.plist から解決した結果
private struct GameCenterServiceConfiguration {
    struct Entry {
        let referenceName: String
        let leaderboardID: String
        let supportedModes: Set<GameMode.Identifier>
    }

    let entries: [Entry]

    static func make(from bundle: Bundle = .main) -> GameCenterServiceConfiguration {
        make(infoDictionary: bundle.infoDictionary ?? [:])
    }

    static func make(infoDictionary: [String: Any]) -> GameCenterServiceConfiguration {
        GameCenterServiceConfiguration(entries: [])
    }

    func entry(for identifier: GameMode.Identifier) -> Entry? {
        entries.first { $0.supportedModes.contains(identifier) }
    }
}

/// リーダーボードごとの送信済み状態を UserDefaults に永続化する小さなストア
private final class GameCenterSubmissionRecordStore {
    private let userDefaults: UserDefaults
    private let hasSubmittedDictionaryKey = StorageKey.UserDefaults.gameCenterHasSubmittedByLeaderboard
    private let lastScoreDictionaryKey = StorageKey.UserDefaults.gameCenterLastScoreByLeaderboard

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    func hasSubmittedScore(for leaderboardID: String) -> Bool {
        let stored = userDefaults.dictionary(forKey: hasSubmittedDictionaryKey) as? [String: Bool]
        return stored?[leaderboardID] ?? false
    }

    func lastSubmittedScore(for leaderboardID: String) -> Int {
        let stored = userDefaults.dictionary(forKey: lastScoreDictionaryKey) as? [String: Int]
        return stored?[leaderboardID] ?? .max
    }

    func shouldSubmitScore(_ score: Int, for leaderboardID: String) -> Bool {
        let hasSubmitted = hasSubmittedScore(for: leaderboardID)
        let previousScore = lastSubmittedScore(for: leaderboardID)
        return (!hasSubmitted) || (score < previousScore)
    }

    func updateSubmissionRecord(for leaderboardID: String, with score: Int) {
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

    func resetSubmissionRecord(for leaderboardID: String) {
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
}

/// Game Center UI の提示先解決と access point 制御をまとめるヘルパー
private struct GameCenterPresentationCoordinator {
    func refreshAccessPointVisibility() {
        let accessPoint = GKAccessPoint.shared
        accessPoint.location = .topTrailing
        accessPoint.isActive = false
        accessPoint.showHighlights = false
    }

    func presentableRootViewController() -> UIViewController? {
        let orderedScenes: [UIWindowScene] = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .sorted { lhs, rhs in
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
            if let window = activeWindow(in: scene),
               let root = window.rootViewController,
               let topMost = topMostViewController(from: root) {
                return topMost
            }
        }

        return nil
    }

    private func activeWindow(in scene: UIWindowScene) -> UIWindow? {
        let visibleWindows = scene.windows.filter { window in
            !window.isHidden && window.alpha > 0 && window.bounds != .zero
        }

        if let keyWindow = visibleWindows.first(where: { $0.isKeyWindow }) {
            return keyWindow
        }
        return visibleWindows.first
    }

    private func topMostViewController(from controller: UIViewController?) -> UIViewController? {
        guard let controller else { return nil }

        if let presented = controller.presentedViewController {
            return topMostViewController(from: presented)
        }
        if let navigation = controller as? UINavigationController {
            return topMostViewController(from: navigation.visibleViewController ?? navigation.topViewController)
        }
        if let tab = controller as? UITabBarController {
            return topMostViewController(from: tab.selectedViewController)
        }
        if let split = controller as? UISplitViewController {
            return topMostViewController(from: split.viewControllers.last)
        }
        return controller
    }
}

/// Game Center 認証フローだけを担当する協調オブジェクト
@MainActor
private final class GameCenterAuthenticationCoordinator {
    private let presentationCoordinator: GameCenterPresentationCoordinator
    private let currentAuthenticationStateProvider: () -> Bool
    private let testAccountProvider: () -> String?
    private let authenticateHandlerInstaller: GameCenterAuthenticationHandlerInstaller
    private let mainAsync: (@escaping @MainActor @Sendable () -> Void) -> Void

    var currentAuthenticationState: Bool {
        currentAuthenticationStateProvider()
    }

    init(
        presentationCoordinator: GameCenterPresentationCoordinator,
        currentAuthenticationStateProvider: @escaping () -> Bool,
        testAccountProvider: @escaping () -> String?,
        authenticateHandlerInstaller: @escaping GameCenterAuthenticationHandlerInstaller,
        mainAsync: @escaping (@escaping @MainActor @Sendable () -> Void) -> Void
    ) {
        self.presentationCoordinator = presentationCoordinator
        self.currentAuthenticationStateProvider = currentAuthenticationStateProvider
        self.testAccountProvider = testAccountProvider
        self.authenticateHandlerInstaller = authenticateHandlerInstaller
        self.mainAsync = mainAsync
    }

    func authenticate(
        stateDidChange: @escaping (Bool) -> Void,
        completion: ((Bool) -> Void)?
    ) {
        if currentAuthenticationState {
            stateDidChange(true)
            presentationCoordinator.refreshAccessPointVisibility()
            completion?(true)
            return
        }

        if let testAccount = testAccountProvider()?.trimmingCharacters(in: .whitespacesAndNewlines),
           !testAccount.isEmpty {
            stateDidChange(true)
            debugLog("GC_TEST_ACCOUNT=\(testAccount) によるダミー認証を実行")
            presentationCoordinator.refreshAccessPointVisibility()
            completion?(true)
            return
        }

        authenticateHandlerInstaller { [weak self] vc, isAuthenticated, error in
            guard let self else { return }

            let statusDescription = error.map { "error=\($0.localizedDescription)" } ?? "error=nil"
            debugLog(
                "Game Center 認証ハンドラ呼び出し: presentingVC=\(vc != nil), isAuthenticated=\(isAuthenticated), \(statusDescription)"
            )

            if let vc {
                self.mainAsync { [weak self] in
                    guard let self else { return }
                    guard let root = self.presentationCoordinator.presentableRootViewController() else {
                        debugLog("Game Center 認証 UI のルート取得に失敗したため再試行が必要")
                        stateDidChange(false)
                        self.presentationCoordinator.refreshAccessPointVisibility()
                        completion?(false)
                        return
                    }

                    debugLog("Game Center 認証 UI を提示します: root=\(type(of: root))")
                    self.presentationCoordinator.refreshAccessPointVisibility()
                    root.present(vc, animated: true)
                }
                return
            }

            self.mainAsync { [weak self] in
                guard let self else { return }
                stateDidChange(isAuthenticated)
                self.presentationCoordinator.refreshAccessPointVisibility()

                if isAuthenticated {
                    debugLog("Game Center 認証成功")
                    completion?(true)
                } else {
                    self.logAuthenticationFailure(error, isPlayerAuthenticated: isAuthenticated)
                    completion?(false)
                }
            }
        }
    }

    private func logAuthenticationFailure(_ error: Error?, isPlayerAuthenticated: Bool) {
        if let error, shouldDowngradeAuthenticationError(error) {
            let nsError = error as NSError
            debugLog("Game Center 認証が利用者操作により完了しませんでした (code=\(nsError.code), description=\(nsError.localizedDescription))")
            return
        }

        if let error {
            debugError(error, message: "Game Center 認証失敗")
        } else {
            debugLog("Game Center 認証失敗: 不明なエラー")
            debugLog("Game Center 認証失敗: GKLocalPlayer.isAuthenticated=\(isPlayerAuthenticated)")
        }
    }

    private func shouldDowngradeAuthenticationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == GKErrorDomain else { return false }

        if let code = GKError.Code(rawValue: nsError.code) {
            return code == .cancelled || code == .notAuthenticated
        }
        return false
    }
}

/// スコア送信の判定と送信後の永続化更新を担当する協調オブジェクト
@MainActor
private final class GameCenterScoreSubmissionCoordinator {
    private let submissionRecordStore: GameCenterSubmissionRecordStore
    private let submitter: GameCenterScoreSubmitter

    init(
        submissionRecordStore: GameCenterSubmissionRecordStore,
        submitter: @escaping GameCenterScoreSubmitter
    ) {
        self.submissionRecordStore = submissionRecordStore
        self.submitter = submitter
    }

    func submitScore(
        _ score: Int,
        for modeIdentifier: GameMode.Identifier,
        isAuthenticated: Bool,
        configuration: GameCenterServiceConfiguration
    ) {
        guard isAuthenticated else {
            debugLog("Game Center 未認証のためスコア送信を中止")
            return
        }

        guard let entry = configuration.entry(for: modeIdentifier) else {
            debugLog("Game Center: モード \(modeIdentifier.rawValue) に対応するリーダーボードが未定義のため送信をスキップ")
            return
        }

        let previousScore = submissionRecordStore.lastSubmittedScore(for: entry.leaderboardID)
        guard submissionRecordStore.shouldSubmitScore(score, for: entry.leaderboardID) else {
            debugLog("Game Center \(entry.referenceName) は既存スコア (\(previousScore)) 以下のため送信をスキップ: \(score)")
            return
        }

        submitter(score, entry.leaderboardID) { [weak self] error in
            if let error {
                debugError(error, message: "Game Center スコア送信失敗")
                return
            }

            debugLog("Game Center スコア送信成功: \(entry.referenceName) score=\(score)")
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.submissionRecordStore.updateSubmissionRecord(for: entry.leaderboardID, with: score)
            }
        }
    }
}

/// leaderboard 画面の組み立てと提示を担当する協調オブジェクト
@MainActor
private struct GameCenterLeaderboardPresenter {
    let presentationCoordinator: GameCenterPresentationCoordinator

    func showLeaderboard(
        for modeIdentifier: GameMode.Identifier,
        isAuthenticated: Bool,
        configuration: GameCenterServiceConfiguration,
        delegate: GKGameCenterControllerDelegate
    ) {
        guard isAuthenticated else {
            debugLog("Game Center 未認証のためランキング表示不可")
            return
        }

        let entry = configuration.entry(for: modeIdentifier) ?? configuration.entries.first
        guard let targetEntry = entry else {
            debugLog("Game Center: 表示可能なリーダーボードが定義されていないためランキングを開けません")
            return
        }

        let viewController = GKGameCenterViewController(
            leaderboardID: targetEntry.leaderboardID,
            playerScope: .global,
            timeScope: .allTime
        )
        viewController.gameCenterDelegate = delegate

        DispatchQueue.main.async {
            presentationCoordinator.refreshAccessPointVisibility()
            guard let root = presentationCoordinator.presentableRootViewController() else {
                debugLog("Game Center ランキング表示用のルート取得に失敗したため表示を中止")
                return
            }

            debugLog("Game Center ランキングを表示します: \(targetEntry.referenceName)")
            root.present(viewController, animated: true)
        }
    }
}

/// Game Center 関連の操作をまとめたサービス
@MainActor
final class GameCenterService: NSObject, GameCenterServiceProtocol {
    static let shared = GameCenterService()

    private let configuration: GameCenterServiceConfiguration
    private let submissionRecordStore: GameCenterSubmissionRecordStore
    private let presentationCoordinator: GameCenterPresentationCoordinator
    private let authenticationCoordinator: GameCenterAuthenticationCoordinator
    private let scoreSubmissionCoordinator: GameCenterScoreSubmissionCoordinator
    private let leaderboardPresenter: GameCenterLeaderboardPresenter

    private(set) var isAuthenticated = false

    private init(
        userDefaults: UserDefaults = .standard,
        configuration: GameCenterServiceConfiguration = .make(),
        presentationCoordinator: GameCenterPresentationCoordinator = GameCenterPresentationCoordinator(),
        testHooks: GameCenterServiceTestHooks = .live
    ) {
        self.configuration = configuration
        let submissionRecordStore = GameCenterSubmissionRecordStore(userDefaults: userDefaults)
        self.submissionRecordStore = submissionRecordStore
        self.presentationCoordinator = presentationCoordinator
        self.authenticationCoordinator = GameCenterAuthenticationCoordinator(
            presentationCoordinator: presentationCoordinator,
            currentAuthenticationStateProvider: testHooks.currentAuthenticationStateProvider ?? { GKLocalPlayer.local.isAuthenticated },
            testAccountProvider: testHooks.testAccountProvider ?? { ProcessInfo.processInfo.environment["GC_TEST_ACCOUNT"] },
            authenticateHandlerInstaller: testHooks.authenticateHandlerInstaller ?? Self.makeLiveAuthenticateHandlerInstaller(),
            mainAsync: testHooks.mainAsync ?? { operation in
                Task { @MainActor in
                    operation()
                }
            }
        )
        self.scoreSubmissionCoordinator = GameCenterScoreSubmissionCoordinator(
            submissionRecordStore: submissionRecordStore,
            submitter: testHooks.scoreSubmitter ?? Self.liveScoreSubmitter
        )
        self.leaderboardPresenter = GameCenterLeaderboardPresenter(
            presentationCoordinator: presentationCoordinator
        )
        super.init()

        isAuthenticated = authenticationCoordinator.currentAuthenticationState
        self.presentationCoordinator.refreshAccessPointVisibility()
    }

    convenience override init() {
        self.init(userDefaults: .standard, configuration: .make())
    }

    convenience init(
        userDefaults: UserDefaults = .standard,
        infoDictionary: [String: Any],
        testHooks: GameCenterServiceTestHooks = .live
    ) {
        self.init(
            userDefaults: userDefaults,
            configuration: .make(infoDictionary: infoDictionary),
            testHooks: testHooks
        )
    }

    func authenticateLocalPlayer(completion: ((Bool) -> Void)? = nil) {
        authenticationCoordinator.authenticate(
            stateDidChange: { [weak self] authenticated in
                self?.isAuthenticated = authenticated
            },
            completion: completion
        )
    }

    func submitScore(_ score: Int, for modeIdentifier: GameMode.Identifier) {
        scoreSubmissionCoordinator.submitScore(
            score,
            for: modeIdentifier,
            isAuthenticated: isAuthenticated,
            configuration: configuration
        )
    }

    func resetSubmittedFlag(for modeIdentifier: GameMode.Identifier? = nil) {
        if let identifier = modeIdentifier {
            guard let entry = configuration.entry(for: identifier) else {
                debugLog("Game Center リセット要求: モード \(identifier.rawValue) に対応するリーダーボードが未定義のため処理を中断")
                return
            }
            submissionRecordStore.resetSubmissionRecord(for: entry.leaderboardID)
            debugLog("Game Center スコア送信フラグをリセットしました (対象モード: \(identifier.rawValue))")
            return
        }

        for entry in configuration.entries {
            submissionRecordStore.resetSubmissionRecord(for: entry.leaderboardID)
        }
        debugLog("Game Center スコア送信フラグを全モード分リセットしました")
    }

    func showLeaderboard(for modeIdentifier: GameMode.Identifier) {
        leaderboardPresenter.showLeaderboard(
            for: modeIdentifier,
            isAuthenticated: isAuthenticated,
            configuration: configuration,
            delegate: self
        )
    }

    /// 指定モードに対応するリーダーボード ID を取得するユーティリティ
    func leaderboardIdentifier(for modeIdentifier: GameMode.Identifier) -> String? {
        configuration.entry(for: modeIdentifier)?.leaderboardID
    }

}

extension GameCenterService: GKGameCenterControllerDelegate {
    nonisolated func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        Task { @MainActor [weak self] in
            gameCenterViewController.dismiss(animated: true)
            self?.presentationCoordinator.refreshAccessPointVisibility()
        }
    }
}

private extension GameCenterService {
    static func makeLiveAuthenticateHandlerInstaller() -> GameCenterAuthenticationHandlerInstaller {
        { callback in
            let player = GKLocalPlayer.local
            player.authenticateHandler = { viewController, error in
                callback(viewController, player.isAuthenticated, error)
            }
        }
    }

    static let liveScoreSubmitter: GameCenterScoreSubmitter = { score, leaderboardID, completion in
        GKLeaderboard.submitScore(
            score,
            context: 0,
            player: GKLocalPlayer.local,
            leaderboardIDs: [leaderboardID],
            completionHandler: completion
        )
    }
}
