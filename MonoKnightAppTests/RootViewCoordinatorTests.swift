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
    @Test func startPreparation_updatesDungeonRewardModeAndSessionTogether() throws {
        let stateStore = RootViewStateStore(initialIsAuthenticated: true)
        let preparationCoordinator = RootViewPreparationCoordinator()
        let tower = try #require(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let initialMode = try #require(DungeonLibrary.shared.firstFloorMode(for: tower))
        let initialSessionID = stateStore.gameSessionID

        preparationCoordinator.startPreparation(
            for: initialMode,
            context: .dungeonSelection,
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
            context: .dungeonContinuation,
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

    @MainActor
    @Test func finishPreparationBeforeReadyDoesNotStartGame() throws {
        let stateStore = RootViewStateStore(initialIsAuthenticated: true)
        let preparationCoordinator = RootViewPreparationCoordinator()
        let tower = try #require(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let mode = try #require(DungeonLibrary.shared.firstFloorMode(for: tower))

        preparationCoordinator.startPreparation(
            for: mode,
            context: .dungeonSelection,
            stateStore: stateStore
        )
        preparationCoordinator.finishPreparationAndStart(stateStore: stateStore)

        #expect(stateStore.isPreparingGame == true)
        #expect(stateStore.isGameReadyForManualStart == false)
    }

    @MainActor
    @Test func startPreparationAutomaticallyStartsAfterChapterDisplay() async throws {
        let stateStore = RootViewStateStore(initialIsAuthenticated: true)
        let preparationCoordinator = RootViewPreparationCoordinator()
        let tower = try #require(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let mode = try #require(DungeonLibrary.shared.firstFloorMode(for: tower))

        preparationCoordinator.startPreparation(
            for: mode,
            context: .dungeonSelection,
            stateStore: stateStore
        )

        #expect(stateStore.isPreparingGame == true)

        try await Task.sleep(nanoseconds: 1_500_000_000)

        #expect(stateStore.isPreparingGame == false)
        #expect(stateStore.isGameReadyForManualStart == false)
        #expect(stateStore.isShowingTitleScreen == false)
    }

    @MainActor
    @Test func startImmediatelyForFallLanding_skipsPreparationOverlayAndUpdatesSession() throws {
        let stateStore = RootViewStateStore(initialIsAuthenticated: true)
        let preparationCoordinator = RootViewPreparationCoordinator()
        let tower = try #require(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let initialSessionID = stateStore.gameSessionID
        let landingPoint = GridPoint(x: 3, y: 4)
        let runState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 14,
            carriedHP: 1,
            totalMoveCount: 7,
            clearedFloorCount: 13,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .straightRight2, rewardUses: 2)],
            pendingFallLandingPoint: landingPoint
        )
        let fallMode = tower.floors[14].makeGameMode(
            dungeonID: tower.id,
            difficulty: tower.difficulty,
            carriedHP: runState.carriedHP,
            runState: runState
        )

        preparationCoordinator.startImmediately(
            for: fallMode,
            context: .dungeonContinuation,
            stateStore: stateStore
        )

        #expect(stateStore.gameSessionID != initialSessionID)
        #expect(stateStore.activeMode == fallMode)
        #expect(stateStore.lastPreparationContext == .dungeonContinuation)
        #expect(stateStore.isShowingTitleScreen == false)
        #expect(stateStore.isPreparingGame == false)
        #expect(stateStore.isGameReadyForManualStart == false)
        #expect(stateStore.activeMode.initialSpawnPoint == landingPoint)
        #expect(stateStore.activeMode.dungeonMetadataSnapshot?.runState?.pendingFallLandingPoint == landingPoint)
    }
}
