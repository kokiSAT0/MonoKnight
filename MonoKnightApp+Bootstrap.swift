import SwiftUI
import Game
import SharedSupport

@MainActor
struct AppBootstrapDependencies {
    let gameCenterService: GameCenterServiceProtocol
    let adsService: AdsServiceProtocol
    let storeService: AnyStoreService
    let dailyChallengeAttemptStore: AnyDailyChallengeAttemptStore
    let dailyChallengeDefinitionService: DailyChallengeDefinitionService
    let gameSettingsStore: GameSettingsStore
}

enum AppBootstrap {
    static let uiTestModeKey = "UITEST_MODE"
    static let diagnosticsMenuKey = "ENABLE_DIAGNOSTICS_MENU"
    static let uiTestDailyChallengeSuiteName = "monoKnight_ui_test_daily_challenge"

    @MainActor
    static func configureDiagnosticsViewer(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
#if DEBUG
        DebugLogHistory.shared.setFrontEndViewerEnabled(true)
#else
        let diagnosticsEnabled = environment[diagnosticsMenuKey] == "1"
        DebugLogHistory.shared.setFrontEndViewerEnabled(diagnosticsEnabled)
#endif
    }

    @MainActor
    static func makeDependencies(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppBootstrapDependencies {
        if environment[uiTestModeKey] != nil {
            let mockDefaults = UserDefaults(suiteName: uiTestDailyChallengeSuiteName)
            mockDefaults?.removePersistentDomain(forName: uiTestDailyChallengeSuiteName)

            return AppBootstrapDependencies(
                gameCenterService: MockGameCenterService(),
                adsService: MockAdsService(),
                storeService: AnyStoreService(base: MockStoreService()),
                dailyChallengeAttemptStore: AnyDailyChallengeAttemptStore(
                    base: DailyChallengeAttemptStore(userDefaults: mockDefaults ?? .standard)
                ),
                dailyChallengeDefinitionService: DailyChallengeDefinitionService(),
                gameSettingsStore: GameSettingsStore(userDefaults: mockDefaults ?? .standard)
            )
        }

        return AppBootstrapDependencies(
            gameCenterService: GameCenterService.shared,
            adsService: AdsService.shared,
            storeService: AnyStoreService(base: StoreService.shared),
            dailyChallengeAttemptStore: AnyDailyChallengeAttemptStore(base: DailyChallengeAttemptStore()),
            dailyChallengeDefinitionService: DailyChallengeDefinitionService(),
            gameSettingsStore: GameSettingsStore()
        )
    }
}

@MainActor
struct RootAppContent: View {
    let hasCompletedConsentFlow: Bool
    let gameCenterService: GameCenterServiceProtocol
    let adsService: AdsServiceProtocol
    @ObservedObject var storeService: AnyStoreService
    @ObservedObject var dailyChallengeAttemptStore: AnyDailyChallengeAttemptStore
    let dailyChallengeDefinitionService: DailyChallengeDefinitionService
    @ObservedObject var gameSettingsStore: GameSettingsStore

    var body: some View {
        Group {
            if hasCompletedConsentFlow {
                RootView(
                    gameCenterService: gameCenterService,
                    adsService: adsService,
                    dailyChallengeAttemptStore: dailyChallengeAttemptStore,
                    dailyChallengeDefinitionService: dailyChallengeDefinitionService,
                    gameSettingsStore: gameSettingsStore
                )
            } else {
                ConsentFlowView(adsService: adsService)
            }
        }
        .preferredColorScheme(gameSettingsStore.preferredColorScheme.preferredColorScheme)
        .environmentObject(storeService)
        .environmentObject(dailyChallengeAttemptStore)
        .environmentObject(gameSettingsStore)
    }
}

enum AppLifecycleCoordinator {
    @MainActor
    static func handleScenePhaseChange(
        _ newPhase: ScenePhase,
        gameCenterService: GameCenterServiceProtocol
    ) {
        guard newPhase == .active else { return }

        debugLog("MonoKnightApp: scenePhase が active へ遷移したため Game Center 認証を再試行します")
        gameCenterService.authenticateLocalPlayer(completion: nil)
        CrashFeedbackCollector.shared.logSummary(label: "scenePhase active", latestCount: 3)
        _ = CrashFeedbackCollector.shared.markReviewCompletedIfNeeded(
            note: "scenePhase active で自動レビュー",
            reviewer: "自動チェック"
        )
    }
}
