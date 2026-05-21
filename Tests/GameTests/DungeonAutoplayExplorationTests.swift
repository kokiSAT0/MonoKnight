import XCTest
@testable import Game
@testable import SharedSupport

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
final class DungeonAutoplayExplorationTests: XCTestCase {
    override func setUpWithError() throws {
        DebugLogConfiguration.shared.setStandardOutputLogging(enabled: false)
        DebugLogHistory.shared.setFrontEndViewerEnabled(true)
        DebugLogHistory.shared.clear()
    }

    override func tearDownWithError() throws {
        DebugLogConfiguration.shared.setStandardOutputLogging(enabled: false)
        DebugLogHistory.shared.setFrontEndViewerEnabled(true)
        DebugLogHistory.shared.clear()
    }

    func testGrowthTowerAutoplayExplorationFindsNoHardFailures() throws {
        let configuration = AutoplayConfiguration.fromEnvironment()
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))

        for runOffset in 0..<configuration.runCount {
            let seed = configuration.baseSeed &+ UInt64(runOffset)
            DebugLogHistory.shared.clear()
            var explorer = DungeonAutoplayExplorer(
                tower: tower,
                seed: seed,
                maxTurnsPerFloor: configuration.maxTurnsPerFloor,
                startFloorIndex: configuration.startFloorIndex,
                floorCount: configuration.floorCount
            )

            do {
                try explorer.run()
            } catch {
                XCTFail(explorer.failureReport(error: error))
            }
        }
    }

    func testAutoplayConfigurationCanTargetLateGrowthTowerFloors() {
        let configuration = AutoplayConfiguration.fromEnvironment([
            "MONOKNIGHT_AUTOPLAY_RUNS": "12",
            "MONOKNIGHT_AUTOPLAY_SEED": "424242",
            "MONOKNIGHT_AUTOPLAY_MAX_TURNS": "240",
            "MONOKNIGHT_AUTOPLAY_START_FLOOR": "41",
            "MONOKNIGHT_AUTOPLAY_FLOOR_COUNT": "10"
        ])

        XCTAssertEqual(configuration.runCount, 12)
        XCTAssertEqual(configuration.baseSeed, 424_242)
        XCTAssertEqual(configuration.maxTurnsPerFloor, 240)
        XCTAssertEqual(configuration.startFloorIndex, 40)
        XCTAssertEqual(configuration.floorCount, 10)
    }
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
private struct DungeonAutoplayExplorer {
    enum Failure: Error, CustomStringConvertible {
        case missingStartFloorMode(floor: Int)
        case missingRunState(floor: Int)
        case missingNextFloorMode(floor: Int)
        case invalidCurrentPoint(floor: Int, turn: Int, point: GridPoint?)
        case invalidHP(floor: Int, turn: Int, hp: Int)
        case blockedWithoutChoice(floor: Int, turn: Int)
        case floorTurnLimitExceeded(floor: Int, turn: Int)
        case resumeSnapshotUnavailable(floor: Int, turn: Int)
        case resumeSnapshotRoundTripFailed(floor: Int, turn: Int)
        case restoreSnapshotFailed(floor: Int, turn: Int)
        case unresolvedPickupChoice(floor: Int, turn: Int)
        case unresolvedRelicChoice(floor: Int, turn: Int)

        var description: String {
            switch self {
            case .missingStartFloorMode(let floor):
                return "start floor mode could not be created for floor \(floor)"
            case .missingRunState(let floor):
                return "run state missing at floor \(floor)"
            case .missingNextFloorMode(let floor):
                return "next floor mode could not be created for floor \(floor)"
            case .invalidCurrentPoint(let floor, let turn, let point):
                return "invalid current point at floor \(floor), turn \(turn): \(String(describing: point))"
            case .invalidHP(let floor, let turn, let hp):
                return "invalid HP at floor \(floor), turn \(turn): \(hp)"
            case .blockedWithoutChoice(let floor, let turn):
                return "playing state has no legal action and no pending choice at floor \(floor), turn \(turn)"
            case .floorTurnLimitExceeded(let floor, let turn):
                return "floor turn limit exceeded at floor \(floor), turn \(turn)"
            case .resumeSnapshotUnavailable(let floor, let turn):
                return "resume snapshot unavailable at floor \(floor), turn \(turn)"
            case .resumeSnapshotRoundTripFailed(let floor, let turn):
                return "resume snapshot encode/decode failed at floor \(floor), turn \(turn)"
            case .restoreSnapshotFailed(let floor, let turn):
                return "resume snapshot restore failed at floor \(floor), turn \(turn)"
            case .unresolvedPickupChoice(let floor, let turn):
                return "pickup choice remained unresolved at floor \(floor), turn \(turn)"
            case .unresolvedRelicChoice(let floor, let turn):
                return "relic choice remained unresolved at floor \(floor), turn \(turn)"
            }
        }
    }

    private let tower: DungeonDefinition
    private let seed: UInt64
    private let maxTurnsPerFloor: Int
    private let startFloorIndex: Int
    private let floorCount: Int
    private var random: AutoplayRandom
    private var trace: [String] = []
    private var latestRunLogEntries: [DungeonRunLogEntry] = []
    private var latestStatus = "not started"

    init(
        tower: DungeonDefinition,
        seed: UInt64,
        maxTurnsPerFloor: Int,
        startFloorIndex: Int,
        floorCount: Int
    ) {
        self.tower = tower
        self.seed = seed
        self.maxTurnsPerFloor = max(maxTurnsPerFloor, 1)
        self.startFloorIndex = min(max(startFloorIndex, 0), max(tower.floors.count - 1, 0))
        self.floorCount = max(floorCount, 1)
        self.random = AutoplayRandom(seed: seed)
    }

    mutating func run() throws {
        let firstMode = try unwrap(
            DungeonLibrary.shared.floorMode(
                for: tower,
                floorIndex: startFloorIndex,
                cardVariationSeed: seed
            ),
            or: Failure.missingStartFloorMode(floor: startFloorIndex + 1)
        )
        var core = GameCore(mode: firstMode)
        var runState = try unwrap(
            firstMode.dungeonMetadataSnapshot?.runState,
            or: Failure.missingRunState(floor: startFloorIndex + 1)
        )
        let floorLimit = min(tower.floors.count, startFloorIndex + floorCount)

        while runState.currentFloorIndex < floorLimit {
            let floorNumber = runState.currentFloorIndex + 1
            try runFloor(core: core, floorNumber: floorNumber)

            guard core.progress == .cleared else {
                trace.append("run ended on floor \(floorNumber) with progress=\(core.progress)")
                return
            }
            guard tower.canAdvanceWithinRun(afterFloorIndex: runState.currentFloorIndex),
                  runState.currentFloorIndex + 1 < floorLimit
            else {
                return
            }

            let nextRunState = runState.advancedToNextFloor(
                carryoverHP: core.dungeonHP,
                currentFloorMoveCount: core.moveCount,
                rewardSelection: nil,
                currentInventoryEntries: core.dungeonInventoryEntries,
                currentRelicEntries: core.dungeonRelicEntries,
                currentCurseEntries: core.dungeonCurseEntries,
                collectedDungeonSpecialPickupIDs: core.collectedDungeonSpecialPickupIDs,
                collectedDungeonRelicPickupIDs: core.collectedDungeonRelicPickupIDs,
                areDungeonRelicAndCurseEffectsEnabled: core.areDungeonRelicAndCurseEffectsEnabled,
                completedWithinHalfTurnLimit: core.moveCount <= max((core.effectiveDungeonTurnLimit ?? maxTurnsPerFloor) / 2, 1),
                startedFloorWithEnemies: core.didStartCurrentFloorWithEnemies,
                currentFloorDefeatedEnemyCount: core.currentFloorDefeatedEnemyCount,
                hazardDamageMitigationsRemaining: core.hazardDamageMitigationsRemaining,
                enemyDamageMitigationsRemaining: core.enemyDamageMitigationsRemaining,
                markerDamageMitigationsRemaining: core.markerDamageMitigationsRemaining,
                currentRunLogEntries: core.dungeonRunLogEntries
            )
            let nextMode = try unwrap(
                DungeonLibrary.shared.floorMode(
                    for: tower,
                    floorIndex: nextRunState.currentFloorIndex,
                    startingRewardEntries: nextRunState.rewardInventoryEntries,
                    startingRelicEntries: nextRunState.relicEntries,
                    startingHazardDamageMitigations: nextRunState.hazardDamageMitigationsRemaining,
                    startingEnemyDamageMitigations: nextRunState.enemyDamageMitigationsRemaining,
                    startingMarkerDamageMitigations: nextRunState.markerDamageMitigationsRemaining,
                    movementStyle: nextRunState.movementStyle,
                    dungeonInventoryKindLimit: nextRunState.dungeonInventoryKindLimit,
                    cardVariationSeed: nextRunState.cardVariationSeed
                ),
                or: Failure.missingNextFloorMode(floor: nextRunState.currentFloorIndex + 1)
            )

            core = GameCore(mode: nextMode)
            runState = nextRunState
        }
    }

    func failureReport(error: Error) -> String {
        let logSummary = traceSuffix(coreLogEntries: latestRunLogEntries)
        return """
        Growth Tower autoplay exploration failed
        seed: \(seed)
        status: \(latestStatus)
        error: \(error)
        \(logSummary)
        """
    }

    private mutating func runFloor(core: GameCore, floorNumber: Int) throws {
        var turn = 0
        var idleTurnCount = 0

        while core.progress == .playing || core.progress == .deadlock {
            latestRunLogEntries = core.dungeonRunLogEntries
            latestStatus = statusText(core: core, floorNumber: floorNumber, turn: turn)
            if turn > maxTurnsPerFloor {
                throw Failure.floorTurnLimitExceeded(floor: floorNumber, turn: turn)
            }

            try resolveDeferredEvents(in: core, floorNumber: floorNumber, turn: turn)
            try assertCoreInvariants(core, floorNumber: floorNumber, turn: turn)
            try assertResumeSnapshotRoundTrips(core, floorNumber: floorNumber, turn: turn)

            if core.progress == .deadlock {
                trace.append("floor \(floorNumber) turn \(turn): penalty redraw")
                core.applyManualPenaltyRedraw()
                turn += 1
                continue
            }

            if try resolvePendingChoices(in: core, floorNumber: floorNumber, turn: turn) {
                turn += 1
                idleTurnCount = 0
                continue
            }

            if playSeededAction(in: core, floorNumber: floorNumber, turn: turn) {
                turn += 1
                idleTurnCount = 0
            } else {
                idleTurnCount += 1
                if idleTurnCount >= 2 {
                    throw Failure.blockedWithoutChoice(floor: floorNumber, turn: turn)
                }
                turn += 1
            }
        }
    }

    private mutating func resolveDeferredEvents(in core: GameCore, floorNumber: Int, turn: Int) throws {
        if core.dungeonFallEvent != nil {
            trace.append("floor \(floorNumber) turn \(turn): resolve fall landing")
            core.resolvePendingDungeonFallLandingIfNeeded()
        }
        if let event = core.dungeonLockedExitReachEvent {
            trace.append("floor \(floorNumber) turn \(turn): clear locked exit notice")
            core.clearDungeonLockedExitReachEvent(event.id)
        }
        if let event = core.dungeonRewindReviveEvent {
            trace.append("floor \(floorNumber) turn \(turn): clear rewind revive notice")
            core.clearDungeonRewindReviveEvent(event.id)
        }
        if let event = core.dungeonFallEvent {
            core.clearDungeonFallEvent(event.id)
        }
        if core.pendingDungeonPickupChoice != nil {
            try resolvePickupChoice(in: core, floorNumber: floorNumber, turn: turn)
        }
        if core.pendingDungeonRelicPickupChoice != nil {
            try resolveRelicChoice(in: core, floorNumber: floorNumber, turn: turn)
        }
    }

    private mutating func resolvePendingChoices(in core: GameCore, floorNumber: Int, turn: Int) throws -> Bool {
        if core.pendingDungeonPickupChoice != nil {
            try resolvePickupChoice(in: core, floorNumber: floorNumber, turn: turn)
            return true
        }
        if core.pendingDungeonRelicPickupChoice != nil {
            try resolveRelicChoice(in: core, floorNumber: floorNumber, turn: turn)
            return true
        }
        return false
    }

    private mutating func resolvePickupChoice(in core: GameCore, floorNumber: Int, turn: Int) throws {
        guard let choice = core.pendingDungeonPickupChoice else { return }
        if choice.discardCandidates.isEmpty || random.nextBool() {
            trace.append("floor \(floorNumber) turn \(turn): discard pickup \(choice.pickup.playable.displayName)")
            guard core.discardPendingDungeonPickupCard() else {
                throw Failure.unresolvedPickupChoice(floor: floorNumber, turn: turn)
            }
            return
        }

        let candidate = choice.discardCandidates[random.index(in: choice.discardCandidates)]
        trace.append(
            "floor \(floorNumber) turn \(turn): pickup \(choice.pickup.playable.displayName), discard \(candidate.playable.displayName)"
        )
        guard core.replaceDungeonInventoryEntryForPendingPickup(discarding: candidate.playable) else {
            throw Failure.unresolvedPickupChoice(floor: floorNumber, turn: turn)
        }
    }

    private mutating func resolveRelicChoice(in core: GameCore, floorNumber: Int, turn: Int) throws {
        guard let choice = core.pendingDungeonRelicPickupChoice,
              !choice.options.isEmpty
        else { return }
        let option = choice.options[random.index(in: choice.options)]
        trace.append("floor \(floorNumber) turn \(turn): relic choice \(option.id)")
        guard core.selectPendingDungeonRelicPickupOption(id: option.id) else {
            throw Failure.unresolvedRelicChoice(floor: floorNumber, turn: turn)
        }
    }

    private mutating func playSeededAction(in core: GameCore, floorNumber: Int, turn: Int) -> Bool {
        let moveCandidates = core.availableMoves()
        if !moveCandidates.isEmpty {
            let move = moveCandidates[random.index(in: moveCandidates)]
            trace.append(
                "floor \(floorNumber) turn \(turn): card \(move.card.displayName) -> \(pointText(move.destination))"
            )
            core.playCard(using: move)
            return true
        }

        if let supportIndex = seededUsableSupportIndex(in: core) {
            let support = core.handStacks[supportIndex].topCard?.supportCard
            trace.append("floor \(floorNumber) turn \(turn): support \(support?.displayName ?? "unknown")")
            if support?.requiresEnemyTargetSelection == true {
                guard core.beginTargetedSupportCardSelection(at: supportIndex),
                      let target = core.targetedSupportCardTargetPoints.sortedForAutoplay().first
                else { return false }
                return core.playTargetedSupportCard(at: target)
            }
            core.playSupportCard(at: supportIndex)
            return true
        }

        let basicMoves = core.availableBasicOrthogonalMoves()
        if !basicMoves.isEmpty {
            let move = basicMoves[random.index(in: basicMoves)]
            trace.append("floor \(floorNumber) turn \(turn): basic -> \(pointText(move.destination))")
            core.playBasicOrthogonalMove(using: move)
            return true
        }

        return false
    }

    private mutating func seededUsableSupportIndex(in core: GameCore) -> Int? {
        let indices = core.handStacks.indices.filter { core.isSupportCardUsable(in: core.handStacks[$0]) }
        guard !indices.isEmpty else { return nil }
        return indices[random.index(in: indices)]
    }

    private func assertCoreInvariants(_ core: GameCore, floorNumber: Int, turn: Int) throws {
        guard let current = core.current,
              core.board.contains(current),
              core.board.isTraversable(current)
        else {
            throw Failure.invalidCurrentPoint(floor: floorNumber, turn: turn, point: core.current)
        }
        guard (1...99).contains(core.dungeonHP) || core.progress == .failed else {
            throw Failure.invalidHP(floor: floorNumber, turn: turn, hp: core.dungeonHP)
        }
    }

    private func assertResumeSnapshotRoundTrips(_ core: GameCore, floorNumber: Int, turn: Int) throws {
        guard core.progress == .playing,
              core.dungeonFallEvent == nil
        else { return }
        let snapshot = try unwrap(
            core.makeDungeonResumeSnapshot(),
            or: Failure.resumeSnapshotUnavailable(floor: floorNumber, turn: turn)
        )
        let data: Data
        let decoded: DungeonRunResumeSnapshot
        do {
            data = try JSONEncoder().encode(snapshot)
            decoded = try JSONDecoder().decode(DungeonRunResumeSnapshot.self, from: data)
        } catch {
            throw Failure.resumeSnapshotRoundTripFailed(floor: floorNumber, turn: turn)
        }
        let mode = try unwrap(
            DungeonLibrary.shared.resumeMode(from: decoded),
            or: Failure.restoreSnapshotFailed(floor: floorNumber, turn: turn)
        )
        let restoredCore = GameCore(mode: mode)
        guard restoredCore.restoreDungeonResumeSnapshot(decoded) else {
            throw Failure.restoreSnapshotFailed(floor: floorNumber, turn: turn)
        }
    }

    private func traceSuffix(coreLogEntries: [DungeonRunLogEntry]) -> String {
        let traceText = trace.suffix(20).joined(separator: "\n")
        let runLogText = coreLogEntries.suffix(20)
            .map { "\($0.headerText): \($0.message)" }
            .joined(separator: "\n")
        return """
        last actions:
        \(traceText.isEmpty ? "(none)" : traceText)
        dungeonRunLog:
        \(runLogText.isEmpty ? "(none captured in failure report)" : runLogText)
        """
    }

    private func pointText(_ point: GridPoint) -> String {
        "(\(point.x),\(point.y))"
    }

    private func statusText(core: GameCore, floorNumber: Int, turn: Int) -> String {
        let current = core.current.map(pointText) ?? "nil"
        let pendingChoice: String
        if let choice = core.pendingDungeonPickupChoice {
            pendingChoice = "pickup=\(choice.pickup.playable.displayName)"
        } else if let choice = core.pendingDungeonRelicPickupChoice {
            pendingChoice = "relic=\(choice.pickup.id)"
        } else {
            pendingChoice = "none"
        }
        return "floor=\(floorNumber) turn=\(turn) progress=\(core.progress) current=\(current) hp=\(core.dungeonHP) pendingChoice=\(pendingChoice)"
    }

    private func unwrap<T>(_ value: T?, or failure: Failure) throws -> T {
        guard let value else { throw failure }
        return value
    }
}

private struct AutoplayConfiguration {
    let runCount: Int
    let baseSeed: UInt64
    let maxTurnsPerFloor: Int
    let startFloorIndex: Int
    let floorCount: Int

    static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Self {
        let startFloor = environment.positiveInt(for: "MONOKNIGHT_AUTOPLAY_START_FLOOR") ?? 1
        return AutoplayConfiguration(
            runCount: environment.positiveInt(for: "MONOKNIGHT_AUTOPLAY_RUNS") ?? 20,
            baseSeed: environment.positiveUInt64(for: "MONOKNIGHT_AUTOPLAY_SEED") ?? 0x5EED_2026,
            maxTurnsPerFloor: environment.positiveInt(for: "MONOKNIGHT_AUTOPLAY_MAX_TURNS") ?? 100,
            startFloorIndex: max(startFloor - 1, 0),
            floorCount: environment.positiveInt(for: "MONOKNIGHT_AUTOPLAY_FLOOR_COUNT") ?? 3
        )
    }
}

private struct AutoplayRandom {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    mutating func index<C: Collection>(in collection: C) -> C.Index where C.Index == Int {
        collection.startIndex + Int(next() % UInt64(collection.count))
    }

    mutating func nextBool() -> Bool {
        next().isMultiple(of: 2)
    }
}

private extension Dictionary where Key == String, Value == String {
    func positiveInt(for key: String) -> Int? {
        guard let value = self[key],
              let parsed = Int(value),
              parsed > 0
        else { return nil }
        return parsed
    }

    func positiveUInt64(for key: String) -> UInt64? {
        guard let value = self[key],
              let parsed = UInt64(value),
              parsed > 0
        else { return nil }
        return parsed
    }
}

private extension Set where Element == GridPoint {
    func sortedForAutoplay() -> [GridPoint] {
        sorted {
            if $0.y == $1.y {
                return $0.x < $1.x
            }
            return $0.y < $1.y
        }
    }
}
