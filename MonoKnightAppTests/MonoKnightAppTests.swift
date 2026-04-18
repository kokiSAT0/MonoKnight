//
//  MonoKnightAppTests.swift
//  MonoKnightAppTests
//
//  Created by koki sato on 2025/09/10.
//

import SwiftUI
import Testing
import Game
import GameKit
import SharedSupport
@testable import MonoKnightApp

// MARK: - テスト用スタブ定義
/// GameCenterServiceProtocol を差し替えるためのスタブ
/// - Note: 認証状態を任意に切り替えられるようにし、RootView 初期化時の状態注入を検証する
private final class StubGameCenterService: GameCenterServiceProtocol {
    /// テストで参照する認証フラグ
    var isAuthenticated: Bool
    /// 認証メソッドの呼び出し回数を記録しておき、必要に応じて挙動確認できるようにする
    private(set) var authenticateCallCount: Int = 0
    /// スコア送信ログを保持し、後続のユニットテスト追加にも流用できるようにする
    private(set) var submittedScores: [(score: Int, mode: GameMode.Identifier)] = []
    /// ランキング表示要求の履歴を取っておき、UI との連携テストに備える
    private(set) var requestedLeaderboards: [GameMode.Identifier] = []

    init(isAuthenticated: Bool) {
        self.isAuthenticated = isAuthenticated
    }

    func authenticateLocalPlayer(completion: ((Bool) -> Void)?) {
        authenticateCallCount += 1
        completion?(isAuthenticated)
    }

    func submitScore(_ score: Int, for modeIdentifier: GameMode.Identifier) {
        submittedScores.append((score, modeIdentifier))
    }

    func showLeaderboard(for modeIdentifier: GameMode.Identifier) {
        requestedLeaderboards.append(modeIdentifier)
    }
}

/// 広告サービスの挙動を固定化するためのスタブ
/// - Important: AdsServiceProtocol は @MainActor 指定のため、スタブ側も同様にアノテーションを付与する
@MainActor
private final class StubAdsService: AdsServiceProtocol {
    /// インタースティシャル表示要求の回数
    private(set) var showInterstitialCallCount: Int = 0
    /// プレイ開始フラグのリセットが何度呼ばれたか
    private(set) var resetPlayFlagCallCount: Int = 0
    /// 広告無効化メソッドの呼び出し回数
    private(set) var disableAdsCallCount: Int = 0
    /// トラッキング許可ダイアログ要求の回数
    private(set) var trackingAuthorizationRequestCount: Int = 0
    /// 同意フォーム表示のための判定更新回数
    private(set) var consentRequestCount: Int = 0
    /// プライバシーオプション更新の回数
    private(set) var consentRefreshCount: Int = 0
    /// リワード広告要求の回数
    private(set) var showRewardedAdCallCount: Int = 0
    /// リワード広告を成功扱いにするかどうかのフラグ
    var rewardedAdShouldSucceed: Bool = true

    func showInterstitial() {
        showInterstitialCallCount += 1
    }

    func resetPlayFlag() {
        resetPlayFlagCallCount += 1
    }

    func disableAds() {
        disableAdsCallCount += 1
    }

    func requestTrackingAuthorization() async {
        trackingAuthorizationRequestCount += 1
    }

    func requestConsentIfNeeded() async {
        consentRequestCount += 1
    }

    func refreshConsentStatus() async {
        consentRefreshCount += 1
    }

    func showRewardedAd() async -> Bool {
        showRewardedAdCallCount += 1
        return rewardedAdShouldSucceed
    }
}

/// 日替わりチャレンジ回数ストアのスタブ
@MainActor
private final class StubDailyChallengeAttemptStore: ObservableObject, DailyChallengeAttemptStoreProtocol {
    var fixedRemainingAttempts: Int
    var randomRemainingAttempts: Int
    var fixedRewardedAttemptsGranted: Int
    var randomRewardedAttemptsGranted: Int
    let maximumRewardedAttempts: Int
    var isDebugUnlimitedEnabled: Bool

    init(
        fixedRemainingAttempts: Int = 1,
        randomRemainingAttempts: Int = 1,
        fixedRewardedAttemptsGranted: Int = 0,
        randomRewardedAttemptsGranted: Int = 0,
        maximumRewardedAttempts: Int = 3,
        isDebugUnlimitedEnabled: Bool = false
    ) {
        self.fixedRemainingAttempts = fixedRemainingAttempts
        self.randomRemainingAttempts = randomRemainingAttempts
        self.fixedRewardedAttemptsGranted = fixedRewardedAttemptsGranted
        self.randomRewardedAttemptsGranted = randomRewardedAttemptsGranted
        self.maximumRewardedAttempts = maximumRewardedAttempts
        self.isDebugUnlimitedEnabled = isDebugUnlimitedEnabled
    }

    func remainingAttempts(for variant: DailyChallengeDefinition.Variant) -> Int {
        switch variant {
        case .fixed:
            return fixedRemainingAttempts
        case .random:
            return randomRemainingAttempts
        }
    }

    func rewardedAttemptsGranted(for variant: DailyChallengeDefinition.Variant) -> Int {
        switch variant {
        case .fixed:
            return fixedRewardedAttemptsGranted
        case .random:
            return randomRewardedAttemptsGranted
        }
    }

    func refreshForCurrentDate() {}

    @discardableResult
    func consumeAttempt(for variant: DailyChallengeDefinition.Variant) -> Bool {
        switch variant {
        case .fixed:
            fixedRemainingAttempts = max(0, fixedRemainingAttempts - 1)
        case .random:
            randomRemainingAttempts = max(0, randomRemainingAttempts - 1)
        }
        return true
    }

    @discardableResult
    func grantRewardedAttempt(for variant: DailyChallengeDefinition.Variant) -> Bool {
        switch variant {
        case .fixed:
            fixedRewardedAttemptsGranted += 1
            fixedRemainingAttempts += 1
        case .random:
            randomRewardedAttemptsGranted += 1
            randomRemainingAttempts += 1
        }
        return true
    }

    func enableDebugUnlimited() {
        // スタブではフラグの状態遷移だけ管理し、UI 連携の検証に利用する
        isDebugUnlimitedEnabled = true
    }

    func disableDebugUnlimited() {
        // 解除時は false へ戻し、再入力テストでも利用できるようにする
        isDebugUnlimitedEnabled = false
    }
}

@MainActor
private func makeBinding<Value>(
    get: @escaping () -> Value,
    set: @escaping (Value) -> Void
) -> Binding<Value> {
    Binding(get: get, set: set)
}

struct MonoKnightAppTests {

    /// AppBootstrap が通常起動時に live 依存を組み立てることを確認する
    @MainActor
    @Test func appBootstrap_liveEnvironment_buildsLiveDependencies() throws {
        let dependencies = AppBootstrap.makeDependencies(environment: [:])

        #expect(dependencies.gameCenterService as AnyObject === GameCenterService.shared)
        #expect(dependencies.adsService as AnyObject === AdsService.shared)
        #expect(dependencies.gameSettingsStore.preferredColorScheme == .system)
    }

    /// AppBootstrap が UI テスト時に mock 依存と専用 suite を使うことを確認する
    @MainActor
    @Test func appBootstrap_uiTestEnvironment_buildsMockDependencies() throws {
        let suiteName = AppBootstrap.uiTestDailyChallengeSuiteName
        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.set(
            ThemePreference.dark.rawValue,
            forKey: StorageKey.AppStorage.preferredColorScheme
        )

        let dependencies = AppBootstrap.makeDependencies(
            environment: [AppBootstrap.uiTestModeKey: "1"]
        )

        #expect(dependencies.gameCenterService is MockGameCenterService)
        #expect(dependencies.adsService is MockAdsService)
        #expect(dependencies.gameSettingsStore.preferredColorScheme == .system)
    }

    /// AppLifecycleCoordinator が active 復帰時だけ Game Center 再認証を要求することを確認する
    @MainActor
    @Test func appLifecycleCoordinator_onlyAuthenticatesOnActiveScenePhase() throws {
        let service = StubGameCenterService(isAuthenticated: false)

        AppLifecycleCoordinator.handleScenePhaseChange(.inactive, gameCenterService: service)
        AppLifecycleCoordinator.handleScenePhaseChange(.background, gameCenterService: service)
        #expect(service.authenticateCallCount == 0)

        AppLifecycleCoordinator.handleScenePhaseChange(.active, gameCenterService: service)
        #expect(service.authenticateCallCount == 1)
    }

    /// RootView の依存注入と、初期状態ストアの標準値が期待通りかを確認する
    @MainActor
    @Test func rootView_initialState_reflectsInjectedServices() throws {
        // MARK: 前提準備
        // Game Center 側は認証済みシナリオを想定し、true を渡したスタブを生成
        let gameCenterStub = StubGameCenterService(isAuthenticated: true)
        // 広告サービスは特に状態を持たないが、依存注入が差し替えられることを確認するために専用スタブを用意
        let adsServiceStub = StubAdsService()

        // MARK: テスト対象の生成
        let dailyStoreStub = StubDailyChallengeAttemptStore()
        let anyDailyStore = AnyDailyChallengeAttemptStore(base: dailyStoreStub)

        let view = RootView(
            gameCenterService: gameCenterStub,
            adsService: adsServiceStub,
            dailyChallengeAttemptStore: anyDailyStore
        )
        let mirror = Mirror(reflecting: view)

        // MARK: 依存サービスの保持を検証
        let mirroredGameCenter = mirror.children.first { $0.label == "gameCenterService" }?.value as? StubGameCenterService
        #expect(mirroredGameCenter === gameCenterStub)

        let mirroredAdsService = mirror.children.first { $0.label == "adsService" }?.value as? StubAdsService
        #expect(mirroredAdsService === adsServiceStub)

        let mirroredDailyStore = mirror.children.first { $0.label == "dailyChallengeAttemptStore" }?.value as? AnyDailyChallengeAttemptStore
        #expect(mirroredDailyStore === anyDailyStore)

        // MARK: RootViewStateStore の標準初期値を検証
        let stateStore = RootViewStateStore(initialIsAuthenticated: true)
        #expect(stateStore.isAuthenticated == true)
        #expect(stateStore.isShowingTitleScreen == true)
        #expect(stateStore.isPreparingGame == false)
        #expect(stateStore.isGameReadyForManualStart == false)
        #expect(stateStore.pendingTitleNavigationTarget == nil)
        #expect(stateStore.lastPreparationContext == nil)
    }

    /// 日替わりモード用リーダーボード ID が Info.plist 相当の設定値から解決されることを検証する
    @MainActor
    @Test func leaderboardIdentifier_dailyModes_useResolvedConfiguration() throws {
        let service = GameCenterService(
            userDefaults: UserDefaults(suiteName: "MonoKnightAppTests.GameCenterService") ?? .standard,
            infoDictionary: [
                "GameCenterLeaderboardStandardReferenceName": "[TEST] Standard Leaderboard",
                "GameCenterLeaderboardStandardID": "test_standard_moves_v1",
                "GameCenterLeaderboardClassicalReferenceName": "[TEST] Classical Challenge Leaderboard",
                "GameCenterLeaderboardClassicalID": "test_classical_moves_v1",
                "GameCenterLeaderboardDailyFixedReferenceName": "[TEST] Daily Fixed Leaderboard",
                "GameCenterLeaderboardDailyFixedID": "test_daily_fixed_v1",
                "GameCenterLeaderboardDailyRandomReferenceName": "[TEST] Daily Random Leaderboard",
                "GameCenterLeaderboardDailyRandomID": "test_daily_random_v1",
            ]
        )

        #expect(service.leaderboardIdentifier(for: .dailyFixedChallenge) == "test_daily_fixed_v1")
        #expect(service.leaderboardIdentifier(for: .dailyRandomChallenge) == "test_daily_random_v1")
    }

    /// 設定不足のモードは leaderboard ID を解決せず nil を返すことを確認する
    @MainActor
    @Test func leaderboardIdentifier_missingConfiguration_returnsNilForUnsupportedMode() throws {
        let service = GameCenterService(
            userDefaults: UserDefaults(suiteName: "MonoKnightAppTests.GameCenterService.MissingConfig") ?? .standard,
            infoDictionary: [
                "GameCenterLeaderboardStandardReferenceName": "[TEST] Standard Leaderboard",
                "GameCenterLeaderboardStandardID": "test_standard_moves_v1",
                "GameCenterLeaderboardClassicalReferenceName": "[TEST] Classical Challenge Leaderboard",
                "GameCenterLeaderboardClassicalID": "test_classical_moves_v1",
            ]
        )

        #expect(service.leaderboardIdentifier(for: .standard5x5) == "test_standard_moves_v1")
        #expect(service.leaderboardIdentifier(for: .dailyFixedChallenge) == nil)
        #expect(service.leaderboardIdentifier(for: .dailyRandomChallenge) == nil)
    }

    /// resetSubmittedFlag(for:) が単一モードの送信記録だけを消せることを確認する
    @MainActor
    @Test func gameCenterService_resetSubmittedFlag_forSingleMode_removesOnlyTargetRecord() async throws {
        let suiteName = "MonoKnightAppTests.GameCenterService.ResetSingle"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)

        var submittedLeaderboards: [String] = []
        let service = GameCenterService(
            userDefaults: defaults,
            infoDictionary: [
                "GameCenterLeaderboardStandardReferenceName": "[TEST] Standard Leaderboard",
                "GameCenterLeaderboardStandardID": "test_standard_moves_v1",
                "GameCenterLeaderboardClassicalReferenceName": "[TEST] Classical Challenge Leaderboard",
                "GameCenterLeaderboardClassicalID": "test_classical_moves_v1",
            ],
            testHooks: GameCenterServiceTestHooks(
                currentAuthenticationStateProvider: { true },
                scoreSubmitter: { _, leaderboardID, completion in
                    submittedLeaderboards.append(leaderboardID)
                    completion(nil)
                },
                mainAsync: { $0() }
            )
        )

        service.submitScore(10, for: .standard5x5)
        await Task.yield()
        service.submitScore(12, for: .classicalChallenge)
        await Task.yield()
        service.submitScore(20, for: .standard5x5)
        await Task.yield()

        #expect(submittedLeaderboards == ["test_standard_moves_v1", "test_classical_moves_v1"])

        service.resetSubmittedFlag(for: .standard5x5)
        service.submitScore(20, for: .standard5x5)
        await Task.yield()
        service.submitScore(18, for: .classicalChallenge)
        await Task.yield()

        #expect(submittedLeaderboards == [
            "test_standard_moves_v1",
            "test_classical_moves_v1",
            "test_standard_moves_v1",
        ])
    }

    /// 全モードの送信記録リセット後は各 leaderboard が再送信可能になることを確認する
    @MainActor
    @Test func gameCenterService_resetSubmittedFlag_forAllModes_clearsAllRecords() async throws {
        let suiteName = "MonoKnightAppTests.GameCenterService.ResetAll"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)

        var submittedLeaderboards: [String] = []
        let service = GameCenterService(
            userDefaults: defaults,
            infoDictionary: [
                "GameCenterLeaderboardStandardReferenceName": "[TEST] Standard Leaderboard",
                "GameCenterLeaderboardStandardID": "test_standard_moves_v1",
                "GameCenterLeaderboardClassicalReferenceName": "[TEST] Classical Challenge Leaderboard",
                "GameCenterLeaderboardClassicalID": "test_classical_moves_v1",
            ],
            testHooks: GameCenterServiceTestHooks(
                currentAuthenticationStateProvider: { true },
                scoreSubmitter: { _, leaderboardID, completion in
                    submittedLeaderboards.append(leaderboardID)
                    completion(nil)
                },
                mainAsync: { $0() }
            )
        )

        service.submitScore(10, for: .standard5x5)
        await Task.yield()
        service.submitScore(12, for: .classicalChallenge)
        await Task.yield()
        service.resetSubmittedFlag()
        service.submitScore(20, for: .standard5x5)
        await Task.yield()
        service.submitScore(18, for: .classicalChallenge)
        await Task.yield()

        #expect(submittedLeaderboards == [
            "test_standard_moves_v1",
            "test_classical_moves_v1",
            "test_standard_moves_v1",
            "test_classical_moves_v1",
        ])
    }

    /// 既送信より悪いスコアは再送信されないことを確認する
    @MainActor
    @Test func gameCenterService_submitScore_skipsWorseScoresAfterBestRecord() async throws {
        let suiteName = "MonoKnightAppTests.GameCenterService.WorseScore"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)

        var submittedScores: [(String, Int)] = []
        let service = GameCenterService(
            userDefaults: defaults,
            infoDictionary: [
                "GameCenterLeaderboardStandardReferenceName": "[TEST] Standard Leaderboard",
                "GameCenterLeaderboardStandardID": "test_standard_moves_v1",
            ],
            testHooks: GameCenterServiceTestHooks(
                currentAuthenticationStateProvider: { true },
                scoreSubmitter: { score, leaderboardID, completion in
                    submittedScores.append((leaderboardID, score))
                    completion(nil)
                },
                mainAsync: { $0() }
            )
        )

        service.submitScore(10, for: .standard5x5)
        await Task.yield()
        service.submitScore(20, for: .standard5x5)
        await Task.yield()
        service.submitScore(8, for: .standard5x5)
        await Task.yield()

        #expect(submittedScores.count == 2)
        #expect(submittedScores.map(\.0) == ["test_standard_moves_v1", "test_standard_moves_v1"])
        #expect(submittedScores.map(\.1) == [10, 8])
    }

    /// 認証キャンセル系のエラーは downgrade ログのみを残すことを確認する
    @MainActor
    @Test func gameCenterService_authenticationCancellation_logsDowngradedMessage() async throws {
        DebugLogHistory.shared.clear()

        let cancellationError = NSError(
            domain: GKErrorDomain,
            code: GKError.Code.cancelled.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "cancelled in test"]
        )
        let service = GameCenterService(
            userDefaults: UserDefaults(suiteName: "MonoKnightAppTests.GameCenterService.Auth") ?? .standard,
            infoDictionary: [:],
            testHooks: GameCenterServiceTestHooks(
                currentAuthenticationStateProvider: { false },
                authenticateHandlerInstaller: { callback in
                    callback(nil, false, cancellationError)
                },
                mainAsync: { $0() }
            )
        )

        var completionResult: Bool?
        service.authenticateLocalPlayer { success in
            completionResult = success
        }
        await Task.yield()

        let messages = DebugLogHistory.shared.snapshot().map(\.message)
        #expect(completionResult == false)
        #expect(messages.contains(where: { $0.contains("Game Center 認証が利用者操作により完了しませんでした") }))
        #expect(messages.allSatisfy { !$0.contains("Game Center 認証失敗") })
    }

    /// SettingsActionCoordinator が Game Center 認証状態と alert を既存どおり更新することを確認する
    @MainActor
    @Test func settingsActionCoordinator_authenticateGameCenter_updatesBindingAndAlert() async throws {
        let service = StubGameCenterService(isAuthenticated: true)
        var presentationState = SettingsPresentationState()
        var isAuthenticated = false

        SettingsActionCoordinator.authenticateGameCenter(
            presentationState: makeBinding(
                get: { presentationState },
                set: { presentationState = $0 }
            ),
            isGameCenterAuthenticated: makeBinding(
                get: { isAuthenticated },
                set: { isAuthenticated = $0 }
            ),
            gameCenterService: service
        )

        await Task.yield()

        #expect(service.authenticateCallCount == 1)
        #expect(isAuthenticated == true)
        #expect(presentationState.isGameCenterAuthenticationInProgress == false)
        #expect(presentationState.gameCenterAlert == .success)
    }

    /// SettingsDebugUnlockCoordinator が入力整形と debug override 有効化を既存どおり行うことを確認する
    @MainActor
    @Test func settingsDebugUnlockCoordinator_sanitizesInputAndEnablesOverrides() throws {
        let campaignProgressStore = CampaignProgressStore()
        let dailyStore = StubDailyChallengeAttemptStore()
        let anyDailyStore = AnyDailyChallengeAttemptStore(base: dailyStore)
        var debugState = SettingsDebugUnlockState()
        var presentationState = SettingsPresentationState()

        SettingsDebugUnlockCoordinator.handleDebugUnlockInputChange(
            "1a2",
            debugState: makeBinding(
                get: { debugState },
                set: { debugState = $0 }
            ),
            presentationState: makeBinding(
                get: { presentationState },
                set: { presentationState = $0 }
            ),
            campaignProgressStore: campaignProgressStore,
            dailyChallengeAttemptStore: anyDailyStore
        )

        #expect(debugState.debugUnlockInput == "12")
        #expect(campaignProgressStore.isDebugUnlockEnabled == false)
        #expect(dailyStore.isDebugUnlimitedEnabled == false)

        SettingsDebugUnlockCoordinator.handleDebugUnlockInputChange(
            "6031",
            debugState: makeBinding(
                get: { debugState },
                set: { debugState = $0 }
            ),
            presentationState: makeBinding(
                get: { presentationState },
                set: { presentationState = $0 }
            ),
            campaignProgressStore: campaignProgressStore,
            dailyChallengeAttemptStore: anyDailyStore
        )

        #expect(debugState.debugUnlockInput.isEmpty)
        #expect(campaignProgressStore.isDebugUnlockEnabled == true)
        #expect(dailyStore.isDebugUnlimitedEnabled == true)
        #expect(presentationState.isDebugUnlockSuccessAlertPresented == true)
    }
}
