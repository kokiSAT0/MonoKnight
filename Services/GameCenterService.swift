import Foundation
import Game
import GameKit
import SharedSupport
import UIKit

/// Game Center リーダーボード設定を Info.plist から解決した結果
private struct GameCenterServiceConfiguration {
    struct Entry {
        let referenceName: String
        let leaderboardID: String
        let supportedModes: Set<GameMode.Identifier>
    }

    private enum Definition: CaseIterable {
        case standard
        case classicalChallenge
        case dailyFixed
        case dailyRandom

        var supportedModes: Set<GameMode.Identifier> {
            switch self {
            case .standard:
                return [.standard5x5]
            case .classicalChallenge:
                return [.classicalChallenge]
            case .dailyFixed:
                return [.dailyFixedChallenge]
            case .dailyRandom:
                return [.dailyRandomChallenge]
            }
        }

        var referenceNameInfoPlistKey: String {
            switch self {
            case .standard:
                return "GameCenterLeaderboardStandardReferenceName"
            case .classicalChallenge:
                return "GameCenterLeaderboardClassicalReferenceName"
            case .dailyFixed:
                return "GameCenterLeaderboardDailyFixedReferenceName"
            case .dailyRandom:
                return "GameCenterLeaderboardDailyRandomReferenceName"
            }
        }

        var leaderboardIDInfoPlistKey: String {
            switch self {
            case .standard:
                return "GameCenterLeaderboardStandardID"
            case .classicalChallenge:
                return "GameCenterLeaderboardClassicalID"
            case .dailyFixed:
                return "GameCenterLeaderboardDailyFixedID"
            case .dailyRandom:
                return "GameCenterLeaderboardDailyRandomID"
            }
        }
    }

    let entries: [Entry]

    static func make(from bundle: Bundle = .main) -> GameCenterServiceConfiguration {
        make(infoDictionary: bundle.infoDictionary ?? [:])
    }

    static func make(infoDictionary: [String: Any]) -> GameCenterServiceConfiguration {
        let resolvedEntries = Definition.allCases.compactMap { definition -> Entry? in
            guard
                let referenceName = infoDictionary[definition.referenceNameInfoPlistKey] as? String,
                let leaderboardID = infoDictionary[definition.leaderboardIDInfoPlistKey] as? String
            else {
                debugLog(
                    "Game Center 設定不足: \(definition.referenceNameInfoPlistKey) または \(definition.leaderboardIDInfoPlistKey) が見つかりません"
                )
                return nil
            }

            let trimmedReferenceName = referenceName.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedLeaderboardID = leaderboardID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedReferenceName.isEmpty, !trimmedLeaderboardID.isEmpty else {
                debugLog(
                    "Game Center 設定不足: \(definition.referenceNameInfoPlistKey) または \(definition.leaderboardIDInfoPlistKey) が空文字です"
                )
                return nil
            }

            return Entry(
                referenceName: trimmedReferenceName,
                leaderboardID: trimmedLeaderboardID,
                supportedModes: definition.supportedModes
            )
        }

        return GameCenterServiceConfiguration(entries: resolvedEntries)
    }

    func entry(for identifier: GameMode.Identifier) -> Entry? {
        guard let resolvedIdentifier = identifier.scoreSubmissionIdentifier else { return nil }
        return entries.first { $0.supportedModes.contains(resolvedIdentifier) }
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

/// Game Center 関連の操作をまとめたサービス
@MainActor
final class GameCenterService: NSObject, GameCenterServiceProtocol {
    static let shared = GameCenterService()

    private let configuration: GameCenterServiceConfiguration
    private let submissionRecordStore: GameCenterSubmissionRecordStore
    private let presentationCoordinator: GameCenterPresentationCoordinator

    private(set) var isAuthenticated = false

    private init(
        userDefaults: UserDefaults = .standard,
        configuration: GameCenterServiceConfiguration = .make(),
        presentationCoordinator: GameCenterPresentationCoordinator = GameCenterPresentationCoordinator()
    ) {
        self.configuration = configuration
        self.submissionRecordStore = GameCenterSubmissionRecordStore(userDefaults: userDefaults)
        self.presentationCoordinator = presentationCoordinator
        super.init()

        isAuthenticated = GKLocalPlayer.local.isAuthenticated
        self.presentationCoordinator.refreshAccessPointVisibility()
    }

    convenience override init() {
        self.init(userDefaults: .standard, configuration: .make())
    }

    convenience init(userDefaults: UserDefaults = .standard, infoDictionary: [String: Any]) {
        self.init(
            userDefaults: userDefaults,
            configuration: .make(infoDictionary: infoDictionary)
        )
    }

    func authenticateLocalPlayer(completion: ((Bool) -> Void)? = nil) {
        if GKLocalPlayer.local.isAuthenticated {
            isAuthenticated = true
            presentationCoordinator.refreshAccessPointVisibility()
            completion?(true)
            return
        }

        if let testAccount = ProcessInfo.processInfo.environment["GC_TEST_ACCOUNT"],
           !testAccount.isEmpty {
            isAuthenticated = true
            debugLog("GC_TEST_ACCOUNT=\(testAccount) によるダミー認証を実行")
            presentationCoordinator.refreshAccessPointVisibility()
            completion?(true)
            return
        }

        let player = GKLocalPlayer.local
        player.authenticateHandler = { [weak self] vc, error in
            guard let self else { return }

            let statusDescription = error.map { "error=\($0.localizedDescription)" } ?? "error=nil"
            debugLog(
                "Game Center 認証ハンドラ呼び出し: presentingVC=\(vc != nil), isAuthenticated=\(player.isAuthenticated), \(statusDescription)"
            )

            if let vc {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    guard let root = self.presentationCoordinator.presentableRootViewController() else {
                        debugLog("Game Center 認証 UI のルート取得に失敗したため再試行が必要")
                        self.isAuthenticated = false
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

            if player.isAuthenticated {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.isAuthenticated = true
                    debugLog("Game Center 認証成功")
                    self.presentationCoordinator.refreshAccessPointVisibility()
                    completion?(true)
                }
            } else {
                let authError = error
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.isAuthenticated = false
                    self.presentationCoordinator.refreshAccessPointVisibility()
                    self.logAuthenticationFailure(authError, player: player)
                    completion?(false)
                }
            }
        }
    }

    func submitScore(_ score: Int, for modeIdentifier: GameMode.Identifier) {
        guard isAuthenticated else {
            debugLog("Game Center 未認証のためスコア送信を中止")
            return
        }

        guard let entry = configuration.entry(for: modeIdentifier) else {
            debugLog("Game Center: モード \(modeIdentifier.rawValue) に対応するリーダーボードが未定義のため送信をスキップ")
            return
        }

        let hasSubmitted = submissionRecordStore.hasSubmittedScore(for: entry.leaderboardID)
        let previousScore = submissionRecordStore.lastSubmittedScore(for: entry.leaderboardID)
        let shouldSubmit = (!hasSubmitted) || (score < previousScore)
        guard shouldSubmit else {
            debugLog("Game Center \(entry.referenceName) は既存スコア (\(previousScore)) 以下のため送信をスキップ: \(score)")
            return
        }

        GKLeaderboard.submitScore(
            score,
            context: 0,
            player: GKLocalPlayer.local,
            leaderboardIDs: [entry.leaderboardID]
        ) { [weak self] error in
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
        guard isAuthenticated else {
            debugLog("Game Center 未認証のためランキング表示不可")
            return
        }

        let entry = configuration.entry(for: modeIdentifier) ?? configuration.entries.first
        guard let targetEntry = entry else {
            debugLog("Game Center: 表示可能なリーダーボードが定義されていないためランキングを開けません")
            return
        }

        let vc = GKGameCenterViewController(
            leaderboardID: targetEntry.leaderboardID,
            playerScope: .global,
            timeScope: .allTime
        )
        vc.gameCenterDelegate = self

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.presentationCoordinator.refreshAccessPointVisibility()
            guard let root = self.presentationCoordinator.presentableRootViewController() else {
                debugLog("Game Center ランキング表示用のルート取得に失敗したため表示を中止")
                return
            }
            debugLog("Game Center ランキングを表示します: \(targetEntry.referenceName)")
            root.present(vc, animated: true)
        }
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
    func logAuthenticationFailure(_ error: Error?, player: GKLocalPlayer) {
        if let error, shouldDowngradeAuthenticationError(error) {
            let nsError = error as NSError
            debugLog("Game Center 認証が利用者操作により完了しませんでした (code=\(nsError.code), description=\(nsError.localizedDescription))")
            return
        }

        if let error {
            debugError(error, message: "Game Center 認証失敗")
        } else {
            debugLog("Game Center 認証失敗: 不明なエラー")
            debugLog("Game Center 認証失敗: GKLocalPlayer.isAuthenticated=\(player.isAuthenticated)")
        }
    }

    func shouldDowngradeAuthenticationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == GKErrorDomain else { return false }

        if let code = GKError.Code(rawValue: nsError.code) {
            return code == .cancelled || code == .notAuthenticated
        }
        return false
    }
}
