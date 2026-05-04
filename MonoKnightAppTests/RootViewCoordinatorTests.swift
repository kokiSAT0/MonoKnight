import Testing
import Game
@testable import MonoKnightApp

@MainActor
private final class RootViewCoordinatorTestGameCenterService: GameCenterServiceProtocol {
    var isAuthenticated: Bool
    private(set) var authenticateCallCount: Int = 0

    init(isAuthenticated: Bool) {
        self.isAuthenticated = isAuthenticated
    }

    func authenticateLocalPlayer(completion: ((Bool) -> Void)?) {
        authenticateCallCount += 1
        completion?(isAuthenticated)
    }

    func submitScore(_ score: Int, for modeIdentifier: GameMode.Identifier) {}
    func showLeaderboard(for modeIdentifier: GameMode.Identifier) {}
}

struct RootViewCoordinatorTests {
    @MainActor
    @Test func initialAuthentication_runsOnlyOnce_andQueuesPromptOnFailure() async throws {
        let stateStore = RootViewStateStore(initialIsAuthenticated: false)
        let presenter = RootViewGameCenterPromptPresenter()
        let gameCenterService = RootViewCoordinatorTestGameCenterService(isAuthenticated: false)

        presenter.performInitialAuthenticationIfNeeded(
            stateStore: stateStore,
            gameCenterService: gameCenterService
        )
        presenter.performInitialAuthenticationIfNeeded(
            stateStore: stateStore,
            gameCenterService: gameCenterService
        )

        await Task.yield()

        #expect(gameCenterService.authenticateCallCount == 1)
        #expect(stateStore.isAuthenticated == false)
        #expect(stateStore.gameCenterSignInPrompt != nil)
        if let prompt = stateStore.gameCenterSignInPrompt {
            switch prompt.reason {
            case .initialAuthenticationFailed:
                break
            default:
                Issue.record("想定外の再サインイン理由が設定されました")
            }
        }
    }

    @MainActor
    @Test func returnToCampaignSelection_cancelsPendingPreparationAndPreservesNavigationTarget() async throws {
        let stateStore = RootViewStateStore(initialIsAuthenticated: true)
        let preparationCoordinator = RootViewPreparationCoordinator()
        let titleFlowCoordinator = RootViewTitleFlowCoordinator()

        preparationCoordinator.startPreparation(
            for: .standard,
            context: .campaignStageSelection,
            stateStore: stateStore
        )

        titleFlowCoordinator.handleReturnToCampaignStageSelectionRequest(
            stateStore: stateStore,
            preparationCoordinator: preparationCoordinator
        )

        try await Task.sleep(
            for: .seconds(RootView.RootLayoutMetrics.gamePreparationMinimumDelay + 0.15)
        )

        #expect(stateStore.pendingTitleNavigationTarget == .campaign)
        #expect(stateStore.isShowingTitleScreen == true)
        #expect(stateStore.isPreparingGame == false)
        #expect(stateStore.isGameReadyForManualStart == false)
    }

    @MainActor
    @Test func startPreparation_updatesTargetLabModeWhenExperimentSettingsChange() {
        let stateStore = RootViewStateStore(initialIsAuthenticated: true)
        let preparationCoordinator = RootViewPreparationCoordinator()
        let initialSettings = TargetLabExperimentSettings.default
        let updatedSettings = TargetLabExperimentSettings(
            enabledCardGroups: [.standard],
            enabledTileKinds: [.boost, .slow]
        )

        preparationCoordinator.startPreparation(
            for: .targetLab(settings: initialSettings),
            context: .highScoreSelection,
            stateStore: stateStore
        )
        preparationCoordinator.startPreparation(
            for: .targetLab(settings: updatedSettings),
            context: .highScoreSelection,
            stateStore: stateStore
        )

        #expect(stateStore.activeMode.regulationSnapshot.targetLabExperimentSettings == updatedSettings)
    }

    @MainActor
    @Test func startPreparation_updatesDungeonRewardModeAndSessionTogether() throws {
        let stateStore = RootViewStateStore(initialIsAuthenticated: true)
        let preparationCoordinator = RootViewPreparationCoordinator()
        let tower = try #require(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let initialMode = try #require(DungeonLibrary.shared.firstFloorMode(for: tower))
        let initialSessionID = stateStore.gameSessionID

        preparationCoordinator.startPreparation(
            for: initialMode,
            context: .campaignStageSelection,
            stateStore: stateStore
        )

        let firstPreparationSessionID = stateStore.gameSessionID
        let runState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 1,
            carriedHP: 2,
            totalMoveCount: 4,
            clearedFloorCount: 1,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .straightRight2, rewardUses: 3)]
        )
        let nextMode = tower.floors[1].makeGameMode(
            dungeonID: tower.id,
            carriedHP: runState.carriedHP,
            runState: runState
        )

        preparationCoordinator.startPreparation(
            for: nextMode,
            context: .campaignContinuation,
            stateStore: stateStore
        )

        #expect(firstPreparationSessionID != initialSessionID)
        #expect(stateStore.gameSessionID != firstPreparationSessionID)
        #expect(stateStore.activeMode == nextMode)
        #expect(stateStore.activeMode.dungeonMetadataSnapshot?.runState?.rewardInventoryEntries == runState.rewardInventoryEntries)

        let core = GameCore(mode: stateStore.activeMode)
        #expect(core.handStacks.contains { $0.representativeMove == .straightRight2 })
        #expect(core.dungeonInventoryEntries == runState.rewardInventoryEntries)
    }
}
