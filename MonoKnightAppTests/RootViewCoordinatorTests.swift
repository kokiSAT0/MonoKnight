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
}
