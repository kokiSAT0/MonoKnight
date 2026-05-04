import SwiftUI
import Game
import SharedSupport

@MainActor
struct AppBootstrapDependencies {
    let gameCenterService: GameCenterServiceProtocol
    let adsService: AdsServiceProtocol
    let storeService: AnyStoreService
    let gameSettingsStore: GameSettingsStore
}

enum AppBootstrap {
    static let uiTestModeKey = "UITEST_MODE"
    static let diagnosticsMenuKey = "ENABLE_DIAGNOSTICS_MENU"
    static let uiTestSuiteName = "monoKnight_ui_test"

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
            let mockDefaults = UserDefaults(suiteName: uiTestSuiteName)
            mockDefaults?.removePersistentDomain(forName: uiTestSuiteName)

            return AppBootstrapDependencies(
                gameCenterService: MockGameCenterService(),
                adsService: MockAdsService(),
                storeService: AnyStoreService(base: MockStoreService()),
                gameSettingsStore: GameSettingsStore(userDefaults: mockDefaults ?? .standard)
            )
        }

        return AppBootstrapDependencies(
            gameCenterService: GameCenterService.shared,
            adsService: AdsService.shared,
            storeService: AnyStoreService(base: StoreService.shared),
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
    @ObservedObject var gameSettingsStore: GameSettingsStore

    var body: some View {
        Group {
            if hasCompletedConsentFlow {
                RootView(
                    gameCenterService: gameCenterService,
                    adsService: adsService,
                    gameSettingsStore: gameSettingsStore
                )
            } else {
                ConsentFlowView(adsService: adsService)
            }
        }
        .preferredColorScheme(gameSettingsStore.preferredColorScheme.preferredColorScheme)
        .environmentObject(storeService)
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

        CrashFeedbackCollector.shared.logSummary(label: "scenePhase active", latestCount: 3)
        _ = CrashFeedbackCollector.shared.markReviewCompletedIfNeeded(
            note: "scenePhase active で自動レビュー",
            reviewer: "自動チェック"
        )
    }
}
