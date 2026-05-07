import XCTest
@testable import Game

final class DungeonModeTests: XCTestCase {
    func testDungeonExitClearsWithoutTargetCollection() throws {
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 1, y: 0),
            turnLimit: 4
        )
        let core = makeCore(
            mode: mode,
            cards: [.kingRight, .kingUp, .kingLeft, .kingDown, .straightRight2]
        )

        XCTAssertTrue(mode.usesDungeonExit)
        XCTAssertFalse(mode.usesTargetCollection)
        playMove(to: GridPoint(x: 1, y: 0), in: core)

        XCTAssertEqual(core.progress, .cleared)
        XCTAssertEqual(core.capturedTargetCount, 0)
    }

    func testDungeonTurnLimitFailsRunAfterNonExitMove() throws {
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            turnLimit: 1
        )
        let core = makeCore(
            mode: mode,
            cards: [.kingRight, .kingUp, .kingLeft, .kingDown, .straightRight2]
        )

        playMove(to: GridPoint(x: 1, y: 0), in: core)

        XCTAssertEqual(core.progress, .failed)
        XCTAssertEqual(core.remainingDungeonTurns, 0)
    }

    func testWatcherDangerDamagesPlayerAfterMove() throws {
        let watcher = EnemyDefinition(
            id: "watcher",
            name: "見張り",
            position: GridPoint(x: 1, y: 0),
            behavior: .watcher(direction: MoveVector(dx: 0, dy: 1), range: 3)
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 1),
            exit: GridPoint(x: 4, y: 4),
            hp: 2,
            turnLimit: 4,
            enemies: [watcher]
        )
        let core = makeCore(
            mode: mode,
            cards: [.kingRight, .kingUp, .kingLeft, .kingDown, .straightRight2]
        )

        XCTAssertTrue(core.enemyDangerPoints.contains(GridPoint(x: 1, y: 1)))
        playMove(to: GridPoint(x: 1, y: 1), in: core)

        XCTAssertEqual(core.dungeonHP, 1)
        XCTAssertEqual(core.progress, .playing)
    }

    func testRotatingWatcherUsesCurrentDirectionAndPreviewsNextDirection() throws {
        let rotatingWatcher = EnemyDefinition(
            id: "rotating-watcher",
            name: "回転見張り",
            position: GridPoint(x: 2, y: 1),
            behavior: .rotatingWatcher(
                directions: [
                    MoveVector(dx: 1, dy: 0),
                    MoveVector(dx: 0, dy: 1)
                ],
                range: 2
            )
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 4,
            enemies: [rotatingWatcher],
            allowsBasicOrthogonalMove: true
        )
        let core = makeCore(mode: mode)

        XCTAssertTrue(core.enemyDangerPoints.contains(GridPoint(x: 3, y: 1)))
        XCTAssertFalse(core.enemyDangerPoints.contains(GridPoint(x: 2, y: 2)))
        XCTAssertEqual(
            core.enemyRotatingWatcherDirectionPreviews,
            [
                EnemyRotatingWatcherDirectionPreview(
                    enemyID: "rotating-watcher",
                    current: GridPoint(x: 2, y: 1),
                    vector: MoveVector(dx: 0, dy: 1)
                )
            ]
        )

        playBasicMove(to: GridPoint(x: 0, y: 1), in: core)

        XCTAssertTrue(core.enemyDangerPoints.contains(GridPoint(x: 2, y: 2)))
        XCTAssertFalse(core.enemyDangerPoints.contains(GridPoint(x: 3, y: 1)))
    }

    func testRotatingWatcherDamagesAfterTurning() throws {
        let rotatingWatcher = EnemyDefinition(
            id: "rotating-watcher",
            name: "回転見張り",
            position: GridPoint(x: 2, y: 1),
            behavior: .rotatingWatcher(
                directions: [
                    MoveVector(dx: 1, dy: 0),
                    MoveVector(dx: 0, dy: 1)
                ],
                range: 2
            )
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 1, y: 1),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 4,
            enemies: [rotatingWatcher]
        )
        let core = makeCore(
            mode: mode,
            cards: [.kingUpRight, .kingRight, .kingUp, .kingLeft, .kingDown]
        )

        playMove(to: GridPoint(x: 2, y: 2), in: core)

        XCTAssertEqual(core.dungeonHP, 2)
        XCTAssertEqual(core.progress, .playing)
    }

    func testDungeonEnemyTurnEventCapturesEnemyStateTransitions() throws {
        let patrol = EnemyDefinition(
            id: "patrol",
            name: "巡回兵",
            position: GridPoint(x: 2, y: 1),
            behavior: .patrol(path: [
                GridPoint(x: 2, y: 1),
                GridPoint(x: 3, y: 1)
            ])
        )
        let rotatingWatcher = EnemyDefinition(
            id: "rotating-watcher",
            name: "回転見張り",
            position: GridPoint(x: 1, y: 4),
            behavior: .rotatingWatcher(
                directions: [
                    MoveVector(dx: 1, dy: 0),
                    MoveVector(dx: 0, dy: -1)
                ],
                range: 2
            )
        )
        let chaser = EnemyDefinition(
            id: "chaser",
            name: "追跡兵",
            position: GridPoint(x: 4, y: 4),
            behavior: .chaser
        )
        let marker = EnemyDefinition(
            id: "marker",
            name: "予告兵",
            position: GridPoint(x: 4, y: 0),
            behavior: .marker(
                directions: [
                    MoveVector(dx: 0, dy: 1),
                    MoveVector(dx: -1, dy: 0)
                ],
                range: 2
            )
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 2),
            hp: 3,
            turnLimit: 4,
            enemies: [patrol, rotatingWatcher, chaser, marker],
            allowsBasicOrthogonalMove: true
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: GridPoint(x: 0, y: 1), in: core)

        let event = try XCTUnwrap(core.dungeonEnemyTurnEvent)
        XCTAssertFalse(event.attackedPlayer)
        XCTAssertEqual(event.hpBefore, 3)
        XCTAssertEqual(event.hpAfter, 3)
        XCTAssertEqual(Set(event.transitions.map(\.enemyID)), ["patrol", "rotating-watcher", "chaser", "marker"])

        let transitions = Dictionary(uniqueKeysWithValues: event.transitions.map { ($0.enemyID, $0) })
        XCTAssertEqual(transitions["patrol"]?.before.position, GridPoint(x: 2, y: 1))
        XCTAssertEqual(transitions["patrol"]?.after.position, GridPoint(x: 3, y: 1))
        XCTAssertEqual(transitions["chaser"]?.before.position, GridPoint(x: 4, y: 4))
        XCTAssertEqual(transitions["chaser"]?.after.position, core.enemyStates.first(where: { $0.id == "chaser" })?.position)
        XCTAssertTrue(transitions["rotating-watcher"]?.didRotate == true)
        XCTAssertTrue(transitions["marker"]?.didRotate == true)
    }

    func testDungeonEnemyTurnEventCapturesAttackDamage() throws {
        let rotatingWatcher = EnemyDefinition(
            id: "rotating-watcher",
            name: "回転見張り",
            position: GridPoint(x: 2, y: 1),
            behavior: .rotatingWatcher(
                directions: [
                    MoveVector(dx: 1, dy: 0),
                    MoveVector(dx: 0, dy: 1)
                ],
                range: 2
            )
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 1, y: 1),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 4,
            enemies: [rotatingWatcher]
        )
        let core = makeCore(
            mode: mode,
            cards: [.kingUpRight, .kingRight, .kingUp, .kingLeft, .kingDown]
        )

        playMove(to: GridPoint(x: 2, y: 2), in: core)

        let event = try XCTUnwrap(core.dungeonEnemyTurnEvent)
        XCTAssertTrue(event.attackedPlayer)
        XCTAssertEqual(event.hpBefore, 3)
        XCTAssertEqual(event.hpAfter, 2)
        XCTAssertEqual(event.transitions.first?.enemyID, "rotating-watcher")
        XCTAssertTrue(event.transitions.first?.didRotate == true)
    }

    func testRotatingWatcherDangerStopsAtImpassableTile() throws {
        let rotatingWatcher = EnemyDefinition(
            id: "rotating-watcher",
            name: "回転見張り",
            position: GridPoint(x: 1, y: 1),
            behavior: .rotatingWatcher(
                directions: [MoveVector(dx: 1, dy: 0)],
                range: 3
            )
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 4,
            enemies: [rotatingWatcher],
            impassableTilePoints: [GridPoint(x: 3, y: 1)]
        )
        let core = makeCore(mode: mode)

        XCTAssertTrue(core.enemyDangerPoints.contains(GridPoint(x: 2, y: 1)))
        XCTAssertFalse(core.enemyDangerPoints.contains(GridPoint(x: 3, y: 1)))
        XCTAssertFalse(core.enemyDangerPoints.contains(GridPoint(x: 4, y: 1)))
    }

    func testMarkerEnemyWarnsNextTurnDamagePointsAndDamagesAfterPlayerMove() throws {
        let marker = EnemyDefinition(
            id: "marker",
            name: "予告兵",
            position: GridPoint(x: 3, y: 1),
            behavior: .marker(
                directions: [MoveVector(dx: -1, dy: 0)],
                range: 2
            )
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 1, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 4,
            enemies: [marker],
            allowsBasicOrthogonalMove: true
        )
        let core = makeCore(mode: mode)

        XCTAssertEqual(
            core.enemyWarningPoints,
            [
                GridPoint(x: 2, y: 1),
                GridPoint(x: 1, y: 1)
            ]
        )
        XCTAssertFalse(core.enemyDangerPoints.contains(GridPoint(x: 1, y: 1)))

        playBasicMove(to: GridPoint(x: 1, y: 1), in: core)

        XCTAssertEqual(core.dungeonHP, 2)
        XCTAssertEqual(core.progress, .playing)
    }

    func testMarkerEnemyWarningStopsAtImpassableTiles() throws {
        let marker = EnemyDefinition(
            id: "marker",
            name: "予告兵",
            position: GridPoint(x: 4, y: 1),
            behavior: .marker(
                directions: [MoveVector(dx: -1, dy: 0)],
                range: 4
            )
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 4,
            enemies: [marker],
            impassableTilePoints: [GridPoint(x: 2, y: 1)],
            allowsBasicOrthogonalMove: true
        )
        let core = makeCore(mode: mode)

        XCTAssertEqual(core.enemyWarningPoints, [GridPoint(x: 3, y: 1)])
    }

    func testMarkerEnemyWarningCyclesAfterEnemyTurn() throws {
        let marker = EnemyDefinition(
            id: "marker",
            name: "予告兵",
            position: GridPoint(x: 3, y: 1),
            behavior: .marker(
                directions: [
                    MoveVector(dx: -1, dy: 0),
                    MoveVector(dx: 0, dy: 1)
                ],
                range: 2
            )
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 4,
            enemies: [marker],
            allowsBasicOrthogonalMove: true
        )
        let core = makeCore(mode: mode)

        XCTAssertEqual(
            core.enemyWarningPoints,
            [
                GridPoint(x: 2, y: 1),
                GridPoint(x: 1, y: 1)
            ]
        )

        playBasicMove(to: GridPoint(x: 0, y: 1), in: core)

        XCTAssertEqual(
            core.enemyWarningPoints,
            [
                GridPoint(x: 3, y: 2),
                GridPoint(x: 3, y: 3)
            ]
        )
        XCTAssertEqual(core.dungeonHP, 3)
    }

    func testMarkerEnemyBehaviorCodableRoundTrip() throws {
        let behavior = EnemyBehavior.marker(
            directions: [
                MoveVector(dx: -1, dy: 0),
                MoveVector(dx: 0, dy: 1)
            ],
            range: 3
        )

        let encoded = try JSONEncoder().encode(behavior)
        let decoded = try JSONDecoder().decode(EnemyBehavior.self, from: encoded)

        XCTAssertEqual(decoded, behavior)
    }

    func testChaserMovesOneStepTowardPlayerWithStableHorizontalPreference() throws {
        let chaser = EnemyDefinition(
            id: "chaser",
            name: "追跡兵",
            position: GridPoint(x: 3, y: 3),
            behavior: .chaser
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            enemies: [chaser],
            allowsBasicOrthogonalMove: true
        )
        let core = makeCore(mode: mode)

        XCTAssertEqual(
            core.enemyChaserMovementPreviews,
            [
                EnemyPatrolMovementPreview(
                    enemyID: "chaser",
                    current: GridPoint(x: 3, y: 3),
                    next: GridPoint(x: 2, y: 3),
                    vector: MoveVector(dx: -1, dy: 0)
                )
            ],
            "同じ距離で詰められる場合は横方向を先に選びます"
        )

        playBasicMove(to: GridPoint(x: 1, y: 0), in: core)

        XCTAssertEqual(core.enemyStates.first?.position, GridPoint(x: 2, y: 3))
    }

    func testChaserRoutesAroundImpassableAndCollapsedFloorsAndStaysWhenUnreachable() throws {
        let chaser = EnemyDefinition(
            id: "chaser",
            name: "追跡兵",
            position: GridPoint(x: 4, y: 0),
            behavior: .chaser
        )
        let detourMode = makeDungeonMode(
            spawn: GridPoint(x: 1, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            enemies: [chaser],
            impassableTilePoints: [GridPoint(x: 3, y: 0)],
            allowsBasicOrthogonalMove: true
        )
        let detourCore = makeCore(mode: detourMode)

        XCTAssertEqual(detourCore.enemyChaserMovementPreviews.first?.next, GridPoint(x: 4, y: 1))
        playBasicMove(to: GridPoint(x: 1, y: 1), in: detourCore)
        XCTAssertEqual(detourCore.enemyStates.first?.position, GridPoint(x: 4, y: 1))

        let collapsedMode = makeDungeonMode(
            spawn: GridPoint(x: 1, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            enemies: [chaser],
            allowsBasicOrthogonalMove: true
        )
        let collapsedCore = makeCore(mode: collapsedMode)
        collapsedCore.overrideDungeonFloorStateForTesting(
            cracked: [],
            collapsed: [GridPoint(x: 3, y: 0)]
        )

        XCTAssertEqual(collapsedCore.enemyChaserMovementPreviews.first?.next, GridPoint(x: 4, y: 1))

        let trappedChaser = EnemyDefinition(
            id: "trapped-chaser",
            name: "追跡兵",
            position: GridPoint(x: 4, y: 4),
            behavior: .chaser
        )
        let unreachableMode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 0, y: 4),
            hp: 3,
            turnLimit: 8,
            enemies: [trappedChaser],
            impassableTilePoints: [
                GridPoint(x: 3, y: 4),
                GridPoint(x: 4, y: 3)
            ],
            allowsBasicOrthogonalMove: true
        )
        let unreachableCore = makeCore(mode: unreachableMode)

        XCTAssertTrue(unreachableCore.enemyChaserMovementPreviews.isEmpty)
        playBasicMove(to: GridPoint(x: 1, y: 0), in: unreachableCore)
        XCTAssertEqual(unreachableCore.enemyStates.first?.position, GridPoint(x: 4, y: 4))
    }

    func testChaserDangerAndDamageUseAdjacentPressureAfterMoving() throws {
        let chaser = EnemyDefinition(
            id: "chaser",
            name: "追跡兵",
            position: GridPoint(x: 3, y: 0),
            behavior: .chaser
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            enemies: [chaser],
            allowsBasicOrthogonalMove: true
        )
        let core = makeCore(mode: mode)

        XCTAssertTrue(core.enemyDangerPoints.contains(GridPoint(x: 3, y: 0)))
        XCTAssertTrue(core.enemyDangerPoints.contains(GridPoint(x: 2, y: 0)))
        XCTAssertTrue(core.enemyDangerPoints.contains(GridPoint(x: 3, y: 1)))
        XCTAssertFalse(core.enemyDangerPoints.contains(GridPoint(x: 2, y: 1)))

        playBasicMove(to: GridPoint(x: 1, y: 0), in: core)

        XCTAssertEqual(core.enemyStates.first?.position, GridPoint(x: 2, y: 0))
        XCTAssertEqual(core.dungeonHP, 2)
        XCTAssertEqual(core.progress, .playing)
    }

    func testPatrolEnemyAdvancesAfterPlayerMove() throws {
        let patrol = EnemyDefinition(
            id: "patrol",
            name: "巡回兵",
            position: GridPoint(x: 1, y: 1),
            behavior: .patrol(path: [
                GridPoint(x: 1, y: 1),
                GridPoint(x: 2, y: 1)
            ])
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 4,
            enemies: [patrol]
        )
        let core = makeCore(
            mode: mode,
            cards: [.kingUp, .kingRight, .kingLeft, .kingDown, .straightRight2]
        )

        playMove(to: GridPoint(x: 0, y: 1), in: core)

        XCTAssertEqual(core.enemyStates.first?.position, GridPoint(x: 2, y: 1))
    }

    func testPatrolMovementPreviewFollowsNextPatrolStep() throws {
        let patrol = EnemyDefinition(
            id: "patrol",
            name: "巡回兵",
            position: GridPoint(x: 1, y: 1),
            behavior: .patrol(path: [
                GridPoint(x: 1, y: 1),
                GridPoint(x: 2, y: 1),
                GridPoint(x: 3, y: 1)
            ])
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 4,
            enemies: [patrol]
        )
        let core = makeCore(
            mode: mode,
            cards: [.kingUp, .kingRight, .kingLeft, .kingDown, .straightRight2]
        )

        XCTAssertEqual(
            core.enemyPatrolMovementPreviews,
            [
                EnemyPatrolMovementPreview(
                    enemyID: "patrol",
                    current: GridPoint(x: 1, y: 1),
                    next: GridPoint(x: 2, y: 1),
                    vector: MoveVector(dx: 1, dy: 0)
                )
            ]
        )

        playMove(to: GridPoint(x: 0, y: 1), in: core)

        XCTAssertEqual(
            core.enemyPatrolMovementPreviews,
            [
                EnemyPatrolMovementPreview(
                    enemyID: "patrol",
                    current: GridPoint(x: 2, y: 1),
                    next: GridPoint(x: 3, y: 1),
                    vector: MoveVector(dx: 1, dy: 0)
                )
            ]
        )
    }

    func testPatrolMovementPreviewExcludesNonMovingEnemies() throws {
        let guardPost = EnemyDefinition(
            id: "guard",
            name: "番兵",
            position: GridPoint(x: 1, y: 1),
            behavior: .guardPost
        )
        let watcher = EnemyDefinition(
            id: "watcher",
            name: "見張り",
            position: GridPoint(x: 3, y: 0),
            behavior: .watcher(direction: MoveVector(dx: 0, dy: 1), range: 3)
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 4,
            enemies: [guardPost, watcher]
        )
        let core = makeCore(mode: mode)

        XCTAssertTrue(core.enemyPatrolMovementPreviews.isEmpty)
    }

    func testBrittleFloorCracksThenCollapsesOnSecondStep() throws {
        let brittlePoint = GridPoint(x: 1, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            hazards: [.brittleFloor(points: [brittlePoint])]
        )
        let core = makeCore(
            mode: mode,
            cards: [
                .kingRight, .kingLeft, .kingUp, .kingDown, .straightRight2,
                .kingLeft, .kingRight, .kingUp, .kingDown, .straightRight2,
                .kingRight, .kingUp, .kingLeft, .kingDown, .straightRight2
            ]
        )

        playMove(to: brittlePoint, in: core)
        XCTAssertTrue(core.crackedFloorPoints.contains(brittlePoint))
        XCTAssertFalse(core.collapsedFloorPoints.contains(brittlePoint))

        playMove(to: GridPoint(x: 0, y: 0), in: core)
        playMove(to: brittlePoint, in: core)

        XCTAssertFalse(core.crackedFloorPoints.contains(brittlePoint))
        XCTAssertTrue(core.collapsedFloorPoints.contains(brittlePoint))
        XCTAssertFalse(core.board.isTraversable(brittlePoint))
        XCTAssertEqual(core.dungeonHP, 2)
        XCTAssertEqual(core.dungeonFallEvent?.point, brittlePoint)
        XCTAssertEqual(core.dungeonFallEvent?.destinationFloorIndex, 1)
    }

    func testFallenLandingOnBrittleFloorCracksAndStops() throws {
        let landingPoint = GridPoint(x: 1, y: 0)
        let runState = DungeonRunState(
            dungeonID: "test-tower",
            currentFloorIndex: 1,
            carriedHP: 2,
            pendingFallLandingPoint: landingPoint
        )
        let mode = makeDungeonMode(
            spawn: landingPoint,
            exit: GridPoint(x: 4, y: 4),
            hp: 2,
            turnLimit: 8,
            hazards: [.brittleFloor(points: [landingPoint])],
            allowsBasicOrthogonalMove: true,
            runState: runState
        )
        let core = makeCore(mode: mode)

        core.resolvePendingDungeonFallLandingIfNeeded()

        XCTAssertTrue(core.crackedFloorPoints.contains(landingPoint))
        XCTAssertFalse(core.collapsedFloorPoints.contains(landingPoint))
        XCTAssertNil(core.dungeonFallEvent)
        XCTAssertEqual(core.dungeonHP, 2)
    }

    func testFallenLandingOnAlreadyCrackedFloorFallsAgain() throws {
        let landingPoint = GridPoint(x: 1, y: 0)
        let runState = DungeonRunState(
            dungeonID: "test-tower",
            currentFloorIndex: 1,
            carriedHP: 2,
            crackedFloorPointsByFloor: [1: [landingPoint]],
            pendingFallLandingPoint: landingPoint
        )
        let mode = makeDungeonMode(
            spawn: landingPoint,
            exit: GridPoint(x: 4, y: 4),
            hp: 2,
            turnLimit: 8,
            hazards: [.brittleFloor(points: [landingPoint])],
            allowsBasicOrthogonalMove: true,
            runState: runState
        )
        let core = makeCore(mode: mode)

        core.resolvePendingDungeonFallLandingIfNeeded()

        XCTAssertFalse(core.crackedFloorPoints.contains(landingPoint))
        XCTAssertTrue(core.collapsedFloorPoints.contains(landingPoint))
        XCTAssertEqual(core.dungeonHP, 1)
        XCTAssertEqual(core.dungeonFallEvent?.point, landingPoint)
        XCTAssertEqual(core.dungeonFallEvent?.sourceFloorIndex, 1)
        XCTAssertEqual(core.dungeonFallEvent?.destinationFloorIndex, 2)
    }

    func testBrittleFloorFallAtZeroHPFailsWithoutNextFloorEvent() throws {
        let brittlePoint = GridPoint(x: 1, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 1,
            turnLimit: 8,
            hazards: [.brittleFloor(points: [brittlePoint])]
        )
        let core = makeCore(
            mode: mode,
            cards: [.kingRight, .kingLeft, .kingRight, .kingUp, .kingDown]
        )

        playMove(to: brittlePoint, in: core)
        playMove(to: GridPoint(x: 0, y: 0), in: core)
        playMove(to: brittlePoint, in: core)

        XCTAssertEqual(core.dungeonHP, 0)
        XCTAssertEqual(core.progress, .failed)
        XCTAssertNil(core.dungeonFallEvent)
    }

    func testDamageTrapDamagesPlayerWhenSteppedOn() throws {
        let trapPoint = GridPoint(x: 1, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            hazards: [.damageTrap(points: [trapPoint], damage: 1)],
            allowsBasicOrthogonalMove: true
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: trapPoint, in: core)

        XCTAssertEqual(core.dungeonHP, 2)
        XCTAssertEqual(core.progress, .playing)
        XCTAssertEqual(core.damageTrapPoints, [trapPoint])
    }

    func testDamageTrapDamagesCardMoveIntermediatePoints() throws {
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            hazards: [
                .damageTrap(
                    points: [
                        GridPoint(x: 1, y: 0),
                        GridPoint(x: 2, y: 0)
                    ],
                    damage: 1
                )
            ]
        )
        let core = makeCore(mode: mode, cards: [.rayRight, .kingUp, .kingRight, .kingLeft, .kingDown])

        playMove(to: GridPoint(x: 4, y: 0), in: core)

        XCTAssertEqual(core.dungeonHP, 1, "レイ型カードの途中にある罠をどちらも踏む想定です")
        XCTAssertEqual(core.progress, .playing)
    }

    func testGrowthHazardMitigationNegatesFirstTrapDamage() throws {
        let trapPoint = GridPoint(x: 1, y: 0)
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            currentFloorIndex: 0,
            carriedHP: 3,
            hazardDamageMitigationsRemaining: 1
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            hazards: [.damageTrap(points: [trapPoint], damage: 1)],
            allowsBasicOrthogonalMove: true,
            runState: runState
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: trapPoint, in: core)

        XCTAssertEqual(core.dungeonHP, 3)
        XCTAssertEqual(core.hazardDamageMitigationsRemaining, 0)
        XCTAssertEqual(core.progress, .playing)
    }

    func testGrowthHazardMitigationOnlyCoversAvailableTrapDamageEvents() throws {
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            currentFloorIndex: 0,
            carriedHP: 3,
            hazardDamageMitigationsRemaining: 1
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            hazards: [
                .damageTrap(
                    points: [
                        GridPoint(x: 1, y: 0),
                        GridPoint(x: 2, y: 0)
                    ],
                    damage: 1
                )
            ],
            runState: runState
        )
        let core = makeCore(mode: mode, cards: [.rayRight, .kingUp, .kingRight, .kingLeft, .kingDown])

        playMove(to: GridPoint(x: 4, y: 0), in: core)

        XCTAssertEqual(core.dungeonHP, 2)
        XCTAssertEqual(core.hazardDamageMitigationsRemaining, 0)
        XCTAssertEqual(core.progress, .playing)
    }

    func testGrowthHazardMitigationPreventsBrittleFallDamageButStillFalls() throws {
        let brittlePoint = GridPoint(x: 1, y: 0)
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            currentFloorIndex: 0,
            carriedHP: 1,
            hazardDamageMitigationsRemaining: 1
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 1,
            turnLimit: 8,
            hazards: [.brittleFloor(points: [brittlePoint])],
            allowsBasicOrthogonalMove: true,
            runState: runState
        )
        let core = makeCore(
            mode: mode,
            cards: [.kingRight, .kingLeft, .kingRight, .kingUp, .kingDown]
        )

        playBasicMove(to: brittlePoint, in: core)
        playBasicMove(to: GridPoint(x: 0, y: 0), in: core)
        playBasicMove(to: brittlePoint, in: core)

        XCTAssertEqual(core.dungeonHP, 1)
        XCTAssertEqual(core.hazardDamageMitigationsRemaining, 0)
        XCTAssertEqual(core.progress, .playing)
        XCTAssertEqual(core.dungeonFallEvent?.hpAfterDamage, 1)
    }

    func testGrowthHazardMitigationCarriesWithinRunAndResetsAtSectionStart() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let firstMode = try XCTUnwrap(
            DungeonLibrary.shared.firstFloorMode(
                for: tower,
                startingHazardDamageMitigations: 2,
                cardVariationSeed: 123
            )
        )
        let firstRunState = try XCTUnwrap(firstMode.dungeonMetadataSnapshot?.runState)

        let nextRunState = firstRunState.advancedToNextFloor(
            carryoverHP: 3,
            currentFloorMoveCount: 2,
            hazardDamageMitigationsRemaining: 1
        )
        let sectionStartMode = try XCTUnwrap(
            DungeonLibrary.shared.floorMode(
                for: tower,
                floorIndex: 10,
                startingHazardDamageMitigations: 2,
                cardVariationSeed: 123
            )
        )

        XCTAssertEqual(firstRunState.hazardDamageMitigationsRemaining, 2)
        XCTAssertEqual(nextRunState.hazardDamageMitigationsRemaining, 1)
        XCTAssertEqual(sectionStartMode.dungeonMetadataSnapshot?.runState?.hazardDamageMitigationsRemaining, 2)
    }

    func testDirectionalRayStopsAtDungeonExitWhenExitIsTraversed() throws {
        let exit = GridPoint(x: 2, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: exit,
            hp: 3,
            turnLimit: 8
        )
        let core = makeCore(mode: mode, cards: [.rayRight, .kingUp, .kingRight, .kingLeft, .kingDown])

        playMove(to: GridPoint(x: 4, y: 0), in: core)

        XCTAssertEqual(core.progress, .cleared)
        XCTAssertEqual(core.current, exit)
        XCTAssertEqual(core.lastMovementResolution?.finalPosition, exit)
        XCTAssertEqual(
            core.lastMovementResolution?.path,
            [
                GridPoint(x: 1, y: 0),
                exit
            ]
        )
    }

    func testDirectionalRayDoesNotClearWhenLockedExitIsTraversedWithoutKey() throws {
        let exit = GridPoint(x: 2, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: exit,
            hp: 3,
            turnLimit: 8,
            exitLock: DungeonExitLock(unlockPoint: GridPoint(x: 4, y: 4))
        )
        let core = makeCore(mode: mode, cards: [.rayRight, .kingUp, .kingRight, .kingLeft, .kingDown])

        playMove(to: GridPoint(x: 4, y: 0), in: core)

        XCTAssertEqual(core.progress, .playing)
        XCTAssertFalse(core.isDungeonExitUnlocked)
        XCTAssertEqual(core.current, GridPoint(x: 4, y: 0))
        XCTAssertEqual(core.lastMovementResolution?.finalPosition, GridPoint(x: 4, y: 0))
    }

    func testDirectionalRayUnlocksKeyThenClearsExitInSameMove() throws {
        let exit = GridPoint(x: 3, y: 0)
        let unlockPoint = GridPoint(x: 1, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: exit,
            hp: 3,
            turnLimit: 8,
            exitLock: DungeonExitLock(unlockPoint: unlockPoint)
        )
        let core = makeCore(mode: mode, cards: [.rayRight, .kingUp, .kingRight, .kingLeft, .kingDown])

        XCTAssertEqual(core.dungeonKeyPoints, [unlockPoint])

        playMove(to: GridPoint(x: 4, y: 0), in: core)

        XCTAssertEqual(core.progress, .cleared)
        XCTAssertTrue(core.isDungeonExitUnlocked)
        XCTAssertTrue(core.dungeonKeyPoints.isEmpty)
        XCTAssertEqual(core.dungeonExitUnlockEvent?.unlockPoint, unlockPoint)
        XCTAssertEqual(core.current, exit)
        XCTAssertEqual(
            core.lastMovementResolution?.path,
            [
                unlockPoint,
                GridPoint(x: 2, y: 0),
                exit
            ]
        )
    }

    func testDirectionalRayStopsAtExitBeforeDamageTrapBeyondExit() throws {
        let exit = GridPoint(x: 2, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: exit,
            hp: 3,
            turnLimit: 8,
            hazards: [.damageTrap(points: [GridPoint(x: 3, y: 0)], damage: 1)]
        )
        let core = makeCore(mode: mode, cards: [.rayRight, .kingUp, .kingRight, .kingLeft, .kingDown])

        playMove(to: GridPoint(x: 4, y: 0), in: core)

        XCTAssertEqual(core.progress, .cleared)
        XCTAssertEqual(core.current, exit)
        XCTAssertEqual(core.dungeonHP, 3)
        XCTAssertEqual(core.lastMovementResolution?.path, [GridPoint(x: 1, y: 0), exit])
    }

    func testTutorialTowerProvidesThreePlayableFloors() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))

        XCTAssertEqual(tower.floors.count, 3)
        XCTAssertEqual(tower.difficulty, .tutorial)

        for floor in tower.floors {
            let mode = floor.makeGameMode(dungeonID: tower.id)
            XCTAssertTrue(mode.usesDungeonExit)
            XCTAssertFalse(mode.usesTargetCollection)
            XCTAssertEqual(mode.dungeonExitPoint, floor.exitPoint)
            XCTAssertEqual(mode.dungeonRules?.failureRule, floor.failureRule)
            XCTAssertEqual(mode.dungeonMetadataSnapshot?.dungeonID, tower.id)
            XCTAssertEqual(mode.dungeonMetadataSnapshot?.floorID, floor.id)
        }
    }

    func testDungeonLibraryProvidesThreeVisibleTowers() throws {
        let library = DungeonLibrary.shared

        XCTAssertNotNil(library.dungeon(with: "tutorial-tower"))
        XCTAssertNotNil(library.dungeon(with: "growth-tower"))
        XCTAssertNotNil(library.dungeon(with: "rogue-tower"))
        XCTAssertEqual(
            library.dungeons.map(\.id),
            ["tutorial-tower", "growth-tower", "rogue-tower"]
        )
    }

    func testPatrolTowerProvidesThreePlayableInventoryFloors() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "patrol-tower"))

        XCTAssertEqual(tower.title, "巡回塔")
        XCTAssertEqual(tower.difficulty, .growth)
        XCTAssertEqual(tower.floors.count, 3)
        XCTAssertEqual(tower.floors.map(\.title), ["巡回の間", "すれ違い", "巡回網"])
        XCTAssertEqual(tower.floors[0].rewardMoveCardsAfterClear, [
            .straightUp2,
            .straightRight2,
            .knightRightwardChoice
        ])
        XCTAssertEqual(tower.floors[1].rewardMoveCardsAfterClear, [
            .rayRight,
            .straightUp2,
            .knightRightwardChoice
        ])
        XCTAssertTrue(tower.floors[2].rewardMoveCardsAfterClear.isEmpty)

        for floor in tower.floors {
            let mode = floor.makeGameMode(dungeonID: tower.id)
            XCTAssertTrue(mode.usesDungeonExit)
            XCTAssertFalse(mode.usesTargetCollection)
            XCTAssertEqual(mode.dungeonExitPoint, floor.exitPoint)
            XCTAssertEqual(mode.dungeonRules?.allowsBasicOrthogonalMove, true)
            XCTAssertEqual(mode.dungeonRules?.cardAcquisitionMode, .inventoryOnly)
            XCTAssertEqual(mode.dungeonMetadataSnapshot?.dungeonID, tower.id)
            XCTAssertEqual(mode.dungeonMetadataSnapshot?.floorID, floor.id)
            XCTAssertFalse(floor.enemies.isEmpty)
            XCTAssertFalse(floor.cardPickups.isEmpty)
        }
    }

    func testDungeonTowerBoardSizesFollowTutorialAndStandardPolicy() throws {
        let tutorialTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let growthTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let rogueTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))

        XCTAssertEqual(tutorialTower.floors.map(\.boardSize), [5, 5, 5])
        XCTAssertEqual(growthTower.floors.map(\.boardSize), Array(repeating: 9, count: 20))
        XCTAssertEqual(rogueTower.floors.map(\.boardSize), [9, 9, 9])
    }

    func testGrowthTowerIntegratesTwentyProgressiveFloors() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))

        XCTAssertEqual(tower.title, "成長塔")
        XCTAssertEqual(tower.difficulty, .growth)
        XCTAssertEqual(tower.floors.count, 20)
        XCTAssertEqual(tower.floors.map(\.title), [
            "巡回の間",
            "鍵の小部屋",
            "見える罠",
            "転移の入口",
            "すれ違い",
            "転移の抜け道",
            "扉の見張り",
            "罠と見張り",
            "総合演習",
            "第一関門",
            "二合目の巡回路",
            "鍵と罠列",
            "転移と見張り",
            "ひび割れの迂回路",
            "中間演習",
            "挟み撃ちの廊下",
            "鍵の遠回り",
            "罠と転移の選択",
            "最終前哨",
            "第二関門"
        ])
        for floorIndex in 0..<9 {
            XCTAssertFalse(
                tower.floors[floorIndex].rewardMoveCardsAfterClear.isEmpty,
                "\(tower.floors[floorIndex].title) は次階へ向けた報酬候補を出す必要があります"
            )
        }
        for floorIndex in 10..<19 {
            XCTAssertFalse(
                tower.floors[floorIndex].rewardMoveCardsAfterClear.isEmpty,
                "\(tower.floors[floorIndex].title) は区間内の次階へ向けた報酬候補を出す必要があります"
            )
        }
        XCTAssertEqual(tower.floors[6].rewardMoveCardsAfterClear, [
            .straightUp2,
            .rayUp,
            .knightUpwardChoice
        ])
        XCTAssertEqual(tower.floors[7].rewardMoveCardsAfterClear, [
            .straightRight2,
            .diagonalUpRight2,
            .rayRight
        ])
        XCTAssertFalse(tower.floors[8].rewardMoveCardsAfterClear.isEmpty)
        XCTAssertEqual(tower.floors[9].rewardMoveCardsAfterClear, [])
        XCTAssertEqual(tower.floors[19].rewardMoveCardsAfterClear, [])
        XCTAssertFalse(tower.canAdvanceWithinRun(afterFloorIndex: 9))
        XCTAssertTrue(tower.canAdvanceWithinRun(afterFloorIndex: 10))
    }

    func testGrowthTowerEarlyFloorsUseDensePickupCardsForLowDifficulty() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let runState = DungeonRunState(
            dungeonID: tower.id,
            carriedHP: 3,
            cardVariationSeed: 321
        )
        let basicOneStepCards: Set<MoveCard> = [.kingUp, .kingDown, .kingLeft, .kingRight]

        for floorIndex in 0..<8 {
            let floor = tower.floors[floorIndex]
            let resolvedFloor = try XCTUnwrap(tower.resolvedFloor(at: floorIndex, runState: runState))

            XCTAssertEqual(
                floor.cardPickups.count,
                5,
                "\(floorIndex + 1)F はギミック追加より拾得カード密度で易しくする想定です"
            )
            XCTAssertEqual(
                resolvedFloor.cardPickups.count,
                5,
                "\(floorIndex + 1)F は seed 解決後も拾得カード数を保つ想定です"
            )
            XCTAssertTrue(
                resolvedFloor.cardPickups.allSatisfy { $0.point.isInside(boardSize: resolvedFloor.boardSize) },
                "\(floorIndex + 1)F の拾得カードは盤面内へ置く必要があります"
            )
            XCTAssertTrue(resolvedFloor.cardPickups.allSatisfy { !basicOneStepCards.contains($0.card) })
            XCTAssertFalse(resolvedFloor.cardPickups.contains { $0.card == .fixedWarp })
        }
    }

    func testGrowthTowerEarlyPickupCardsCanBeCollectedAsExtraOptions() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))

        let firstCore = makeCore(mode: tower.floors[0].makeGameMode(dungeonID: tower.id))
        playBasicMove(to: GridPoint(x: 1, y: 0), in: firstCore)
        playBasicMove(to: GridPoint(x: 2, y: 0), in: firstCore)
        playBasicMove(to: GridPoint(x: 3, y: 0), in: firstCore)
        XCTAssertTrue(
            firstCore.dungeonInventoryEntries.contains { $0.card == .diagonalUpRight2 && $0.pickupUses == 1 },
            "1F の追加拾得カードは序盤から寄り道/短縮用の選択肢として拾える想定です"
        )

        let secondCore = makeCore(mode: tower.floors[1].makeGameMode(dungeonID: tower.id))
        playBasicMove(to: GridPoint(x: 7, y: 8), in: secondCore)
        playBasicMove(to: GridPoint(x: 6, y: 8), in: secondCore)
        XCTAssertTrue(
            secondCore.dungeonInventoryEntries.contains { $0.card == .straightLeft2 && $0.pickupUses == 1 },
            "2F の追加拾得カードは鍵フロアの横移動を楽にする選択肢として拾える想定です"
        )
    }

    func testGrowthTowerStairsBecomeNextFloorStartWithinRunSections() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let firstSectionIndexes = 0..<9
        let secondSectionIndexes = 10..<19

        for index in firstSectionIndexes {
            XCTAssertEqual(
                tower.floors[index + 1].spawnPoint,
                tower.floors[index].exitPoint,
                "\(index + 1)F の階段位置から \(index + 2)F が始まる必要があります"
            )
        }
        for index in secondSectionIndexes {
            XCTAssertEqual(
                tower.floors[index + 1].spawnPoint,
                tower.floors[index].exitPoint,
                "\(index + 1)F の階段位置から \(index + 2)F が始まる必要があります"
            )
        }
        XCTAssertNotEqual(
            tower.floors[10].spawnPoint,
            tower.floors[9].exitPoint,
            "11F はチェックポイント開始なので 10F 階段からの連続開始にはしません"
        )
    }

    func testGrowthTowerUsesVariedStairPositions() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let uniqueExitPoints = Set(tower.floors.map(\.exitPoint))

        XCTAssertGreaterThanOrEqual(
            uniqueExitPoints.count,
            8,
            "成長塔は周回時の固定感を減らすため、階段位置を複数パターンに分散します"
        )
        for floor in tower.floors {
            XCTAssertNotEqual(
                floor.spawnPoint,
                floor.exitPoint,
                "\(floor.title) は開始直後に同じマスの階段でクリアしない配置にします"
            )
        }
    }

    func testGrowthTowerUsesWarpTilesWithoutFixedWarpCards() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        var hasWarpTile = false

        for floor in tower.floors {
            hasWarpTile = hasWarpTile || !floor.warpTilePairs.isEmpty
            XCTAssertTrue(
                floor.fixedWarpCardTargets.isEmpty,
                "\(floor.title) は成長塔では固定ワープカード目的地を持たない想定です"
            )
            XCTAssertFalse(
                floor.cardPickups.contains { $0.card == .fixedWarp },
                "\(floor.title) の拾得カードに固定ワープを混ぜない想定です"
            )
            XCTAssertFalse(
                floor.rewardMoveCardsAfterClear.contains(.fixedWarp),
                "\(floor.title) の報酬候補に固定ワープを混ぜない想定です"
            )
        }

        XCTAssertTrue(hasWarpTile, "成長塔のワープ要素は床ギミックとして残します")
    }

    func testGrowthTowerLateRewardsFeedIntoCombinedFloors() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))

        let eighthRunState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 7,
            carriedHP: 3,
            clearedFloorCount: 7,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .diagonalUpRight2, rewardUses: 3)]
        )
        let eighthCore = makeCore(
            mode: tower.floors[7].makeGameMode(
                dungeonID: tower.id,
                difficulty: tower.difficulty,
                runState: eighthRunState
            )
        )
        XCTAssertTrue(
            eighthCore.availableMoves().contains { $0.moveCard == .diagonalUpRight2 && $0.destination == GridPoint(x: 2, y: 2) },
            "7F報酬の右上2は8Fで罠列をまたぐ候補になる想定です"
        )

        let ninthRunState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 8,
            carriedHP: 3,
            clearedFloorCount: 8,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .straightRight2, rewardUses: 3)]
        )
        let ninthCore = makeCore(
            mode: tower.floors[8].makeGameMode(
                dungeonID: tower.id,
                difficulty: tower.difficulty,
                runState: ninthRunState
            )
        )
        XCTAssertTrue(
            ninthCore.availableMoves().contains { $0.moveCard == .straightRight2 && $0.destination == GridPoint(x: 2, y: 2) },
            "8F報酬の右2は9Fで鍵側へ寄る最初の短縮候補になる想定です"
        )

        let lateRewardCases: [(floorIndex: Int, card: MoveCard, destination: GridPoint, message: String)] = [
            (10, .straightDown2, GridPoint(x: 8, y: 6), "11F報酬の下2は12Fの下り導線へ入る候補になる想定です"),
            (11, .rayLeft, GridPoint(x: 0, y: 2), "12F報酬の左連続は13Fの横移動を大きく短縮する想定です"),
            (12, .straightRight2, GridPoint(x: 2, y: 6), "13F報酬の右2は14Fの直線ルートを刻む候補になる想定です"),
            (13, .diagonalDownLeft2, GridPoint(x: 6, y: 4), "14F報酬の左下2は15Fの鍵側へ寄る候補になる想定です"),
            (15, .diagonalUpLeft2, GridPoint(x: 6, y: 6), "16F報酬の左上2は17Fの遠回りを短縮する想定です"),
            (17, .diagonalDownLeft2, GridPoint(x: 6, y: 6), "18F報酬の左下2は19Fの罠側を避ける候補になる想定です"),
            (18, .straightRight2, GridPoint(x: 2, y: 2), "19F報酬の右2は20Fの鍵ルートへ寄る候補になる想定です")
        ]

        for rewardCase in lateRewardCases {
            let runState = DungeonRunState(
                dungeonID: tower.id,
                currentFloorIndex: rewardCase.floorIndex + 1,
                carriedHP: 3,
                clearedFloorCount: rewardCase.floorIndex + 1,
                rewardInventoryEntries: [DungeonInventoryEntry(card: rewardCase.card, rewardUses: 3)]
            )
            let core = makeCore(
                mode: tower.floors[rewardCase.floorIndex + 1].makeGameMode(
                    dungeonID: tower.id,
                    difficulty: tower.difficulty,
                    runState: runState
                )
            )
            XCTAssertTrue(
                core.availableMoves().contains {
                    $0.moveCard == rewardCase.card && $0.destination == rewardCase.destination
                },
                rewardCase.message
            )
        }
    }

    func testGrowthTowerDefinitionsStayInsideBoardAndExposeCombinedGimmicks() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        var hasPatrol = false
        var hasChaser = false
        var hasMarker = false
        var hasExitLock = false
        var hasDamageTrap = false
        var hasWarp = false
        var hasBrittleFloor = false
        var hasImpassable = false

        for floor in tower.floors {
            var points: [GridPoint] = [floor.spawnPoint, floor.exitPoint]
            points.append(contentsOf: floor.cardPickups.map(\.point))
            points.append(contentsOf: floor.enemies.map(\.position))
            points.append(contentsOf: floor.impassableTilePoints)
            hasImpassable = hasImpassable || !floor.impassableTilePoints.isEmpty
            points.append(contentsOf: floor.tileEffectOverrides.keys)
            for enemy in floor.enemies {
                switch enemy.behavior {
                case .patrol(let path):
                    hasPatrol = true
                    points.append(contentsOf: path)
                case .chaser:
                    hasChaser = true
                case .marker:
                    hasMarker = true
                case .guardPost, .watcher, .rotatingWatcher:
                    break
                }
            }
            for hazard in floor.hazards {
                switch hazard {
                case .damageTrap(let trapPoints, _):
                    hasDamageTrap = true
                    points.append(contentsOf: trapPoints)
                case .brittleFloor(let brittlePoints):
                    hasBrittleFloor = true
                    points.append(contentsOf: brittlePoints)
                }
            }
            for warpPoints in floor.warpTilePairs.values {
                hasWarp = true
                points.append(contentsOf: warpPoints)
            }
            for targets in floor.fixedWarpCardTargets.values {
                points.append(contentsOf: targets)
            }
            if let exitLock = floor.exitLock {
                hasExitLock = true
                points.append(exitLock.unlockPoint)
            }

            XCTAssertTrue(
                points.allSatisfy { $0.isInside(boardSize: floor.boardSize) },
                "\(floor.title) の配置はすべて 9×9 盤面内に収める必要があります"
            )
        }

        XCTAssertTrue(hasPatrol)
        XCTAssertTrue(hasChaser)
        XCTAssertTrue(hasMarker)
        XCTAssertTrue(hasExitLock)
        XCTAssertTrue(hasDamageTrap)
        XCTAssertTrue(hasWarp)
        XCTAssertTrue(hasBrittleFloor)
        XCTAssertTrue(hasImpassable)
    }

    func testGrowthTowerFixedRocksStaySparseAndDoNotOverlapGimmicks() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))

        for floor in tower.floors {
            XCTAssertTrue(
                (2...4).contains(floor.impassableTilePoints.count),
                "\(floor.title) の固定障害物は 1 フロア 2〜4 個の少量に留めます"
            )

            let disallowedPoints = disallowedGrowthTowerImpassablePoints(for: floor)
            XCTAssertTrue(
                floor.impassableTilePoints.isDisjoint(with: disallowedPoints),
                "\(floor.title) の固定障害物は開始/階段/鍵/拾得カード/敵/罠/ひび割れ/ワープと重ねません"
            )
        }
    }

    func testGrowthTowerFixedRocksLeaveRepresentativeRoutesOpen() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))

        for floor in tower.floors {
            XCTAssertTrue(
                hasOrthogonalPath(from: floor.spawnPoint, to: floor.exitPoint, in: floor),
                "\(floor.title) は固定障害物を足しても開始地点から階段までの代表導線を残します"
            )
        }
    }

    func testGrowthTowerFixedRocksStopRayCardsAndWatcherSight() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let floor = tower.floors[15]
        let core = makeCore(
            mode: floor.makeGameMode(dungeonID: tower.id, difficulty: tower.difficulty),
            cards: [.rayRight, .kingUp, .kingRight, .kingLeft, .kingDown]
        )

        XCTAssertTrue(core.enemyDangerPoints.contains(GridPoint(x: 4, y: 2)))
        XCTAssertFalse(core.enemyDangerPoints.contains(GridPoint(x: 4, y: 3)))
        XCTAssertFalse(core.enemyDangerPoints.contains(GridPoint(x: 4, y: 4)))
        XCTAssertTrue(core.addDungeonInventoryCardForTesting(.rayRight, rewardUses: 1))
        XCTAssertTrue(
            core.availableMoves().contains {
                $0.moveCard == .rayRight && $0.destination == GridPoint(x: 3, y: 0)
            },
            "16F の固定障害物はレイ型カードを手前で止める想定です"
        )
        XCTAssertFalse(
            core.availableMoves().contains {
                $0.moveCard == .rayRight && $0.destination == GridPoint(x: 8, y: 0)
            },
            "16F の固定障害物をレイ型カードが通過してはいけません"
        )
    }

    func testGrowthTowerChaserPunishesLooseDetoursWithoutBlockingClearRoute() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let floor = tower.floors[6]

        XCTAssertTrue(
            hasOrthogonalPath(from: floor.spawnPoint, to: floor.exitPoint, in: floor),
            "追跡兵を足しても 7F の代表クリアルートは残します"
        )

        let core = makeCore(mode: floor.makeGameMode(dungeonID: tower.id, difficulty: tower.difficulty))
        XCTAssertEqual(core.dungeonHP, 3)

        playBasicMove(to: GridPoint(x: 5, y: 0), in: core)

        XCTAssertLessThan(
            core.dungeonHP,
            3,
            "追跡兵側へ雑に寄り道すると敵ターン後に被弾しうる想定です"
        )
    }

    func testGrowthTowerPatrolRoutesExpandFromMidgameWithoutOverlaps() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let expectedExpandedFloorIndices: Set<Int> = [8, 9, 10, 14, 16, 18, 19]
        var expandedFloorIndices: Set<Int> = []

        for (index, floor) in tower.floors.enumerated() {
            for enemy in floor.enemies {
                guard case .patrol(let path) = enemy.behavior else { continue }

                XCTAssertEqual(
                    enemy.position,
                    path.first,
                    "\(floor.title) の巡回兵は初期位置を巡回パス先頭に揃えます"
                )
                XCTAssertTrue(
                    path.allSatisfy { $0.isInside(boardSize: floor.boardSize) },
                    "\(floor.title) の巡回パスはすべて盤面内に置きます"
                )
                for (current, next) in zip(path, path.dropFirst()) {
                    XCTAssertEqual(
                        manhattanDistance(from: current, to: next),
                        1,
                        "\(floor.title) の巡回パスは上下左右1マスずつ連続させます"
                    )
                }
                XCTAssertTrue(
                    Set(path).isDisjoint(with: disallowedGrowthTowerPatrolPoints(for: floor, excludingEnemyID: enemy.id)),
                    "\(floor.title) の巡回パスは開始/階段/拾得カード/ワープ/岩柱/罠/他敵と重ねません"
                )

                if index >= 8 {
                    XCTAssertGreaterThanOrEqual(
                        path.count,
                        6,
                        "\(floor.title) の中盤以降の巡回兵は6マス以上の巡回圧を持たせます"
                    )
                    expandedFloorIndices.insert(index)
                }
            }
        }

        XCTAssertTrue(
            expectedExpandedFloorIndices.isSubset(of: expandedFloorIndices),
            "成長塔9F/10F/11F/15F/17F/19F/20Fで巡回範囲を段階拡大します"
        )
    }

    func testExpandedGrowthTowerPatrolCanPunishLooseCentralEntry() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let floor = tower.floors[14]
        let patrol = try XCTUnwrap(
            floor.enemies.first { enemy in
                if case .patrol = enemy.behavior { return true }
                return false
            }
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 2, y: 4),
            exit: GridPoint(x: 8, y: 8),
            hp: 3,
            turnLimit: 6,
            enemies: [patrol],
            allowsBasicOrthogonalMove: true
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: GridPoint(x: 3, y: 4), in: core)

        XCTAssertEqual(
            core.dungeonHP,
            2,
            "15F以降の拡大巡回では、中央帯へ雑に入ると敵ターン後に被弾しうる想定です"
        )
    }

    func testGrowthTowerBrittleFloorsOnlyAppearBeforeFallableNextFloor() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))

        for (index, floor) in tower.floors.enumerated() {
            let hasBrittleFloor = floor.hazards.contains { hazard in
                if case .brittleFloor(let points) = hazard {
                    return !points.isEmpty
                }
                return false
            }

            if hasBrittleFloor {
                XCTAssertTrue(
                    tower.canAdvanceWithinRun(afterFloorIndex: index),
                    "\(floor.title) のひび割れ床は落下先として通常遷移できる次階がある場合だけ配置します"
                )
            }
        }
    }

    func testGrowthTowerKeysUnlockStairsWithoutOpenGateDoors() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let lockedFloors = tower.floors.filter { $0.exitLock != nil }

        XCTAssertFalse(lockedFloors.isEmpty)

        for floor in lockedFloors {
            let unlockPoint = try XCTUnwrap(floor.exitLock?.unlockPoint)
            XCTAssertNil(
                floor.tileEffectOverrides[unlockPoint],
                "\(floor.title) の鍵マスは openGate ではなく階段ロックの鍵として扱います"
            )
            XCTAssertFalse(
                floor.tileEffectOverrides.values.contains { effect in
                    if case .openGate = effect { return true }
                    return false
                },
                "\(floor.title) では序盤の鍵学習用に障害物扉を使いません"
            )

            let core = makeCore(mode: floor.makeGameMode(dungeonID: tower.id))
            XCTAssertFalse(core.isDungeonExitUnlocked)
            XCTAssertEqual(core.dungeonKeyPoints, [unlockPoint])
        }
    }

    func testGrowthTowerFinalFloorRepresentativeRouteCanClearCombinedGimmicks() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let runState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 8,
            carriedHP: 3,
            clearedFloorCount: 8
        )
        let core = makeCore(
            mode: tower.floors[8].makeGameMode(
                dungeonID: tower.id,
                difficulty: tower.difficulty,
                runState: runState
            )
        )

        playBasicMove(to: GridPoint(x: 0, y: 1), in: core)
        playMove(to: GridPoint(x: 2, y: 1), in: core)
        for destination in [
            GridPoint(x: 3, y: 1),
            GridPoint(x: 4, y: 1),
            GridPoint(x: 5, y: 1),
            GridPoint(x: 6, y: 1),
            GridPoint(x: 7, y: 1),
            GridPoint(x: 8, y: 1),
            GridPoint(x: 8, y: 2),
            GridPoint(x: 8, y: 3),
            GridPoint(x: 8, y: 4),
            GridPoint(x: 8, y: 5),
            GridPoint(x: 8, y: 6),
            GridPoint(x: 8, y: 7),
            GridPoint(x: 8, y: 8)
        ] {
            playBasicMove(to: destination, in: core)
        }

        XCTAssertEqual(core.progress, .cleared)
        XCTAssertEqual(core.dungeonHP, 3)
    }

    func testPatrolTowerNineByNineDefinitionsStayInsideBoard() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "patrol-tower"))

        for floor in tower.floors {
            var points: [GridPoint] = [floor.spawnPoint, floor.exitPoint]
            points.append(contentsOf: floor.cardPickups.map(\.point))
            points.append(contentsOf: floor.enemies.map(\.position))
            for enemy in floor.enemies {
                if case .patrol(let path) = enemy.behavior {
                    points.append(contentsOf: path)
                }
            }
            for hazard in floor.hazards {
                if case .brittleFloor(let brittlePoints) = hazard {
                    points.append(contentsOf: brittlePoints)
                } else if case .damageTrap(let trapPoints, _) = hazard {
                    points.append(contentsOf: trapPoints)
                }
            }

            XCTAssertTrue(
                points.allSatisfy { $0.isInside(boardSize: floor.boardSize) },
                "\(floor.title) の配置はすべて 9×9 盤面内に収める必要があります"
            )
        }
    }

    func testKeyDoorTowerProvidesThreePlayableInventoryFloors() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "key-door-tower"))

        XCTAssertEqual(tower.title, "鍵扉塔")
        XCTAssertEqual(tower.difficulty, .growth)
        XCTAssertEqual(tower.floors.count, 3)
        XCTAssertEqual(tower.floors.map(\.title), ["鍵の小部屋", "上の鍵道", "扉の見張り"])
        XCTAssertEqual(tower.floors[0].rewardMoveCardsAfterClear, [
            .straightRight2,
            .straightUp2,
            .knightRightwardChoice
        ])
        XCTAssertEqual(tower.floors[1].rewardMoveCardsAfterClear, [
            .straightUp2,
            .straightRight2,
            .diagonalUpRight2
        ])
        XCTAssertTrue(tower.floors[2].rewardMoveCardsAfterClear.isEmpty)

        for floor in tower.floors {
            let mode = floor.makeGameMode(dungeonID: tower.id)
            XCTAssertTrue(mode.usesDungeonExit)
            XCTAssertFalse(mode.usesTargetCollection)
            XCTAssertEqual(mode.dungeonExitPoint, floor.exitPoint)
            XCTAssertEqual(mode.dungeonRules?.allowsBasicOrthogonalMove, true)
            XCTAssertEqual(mode.dungeonRules?.cardAcquisitionMode, .inventoryOnly)
            XCTAssertEqual(mode.dungeonMetadataSnapshot?.dungeonID, tower.id)
            XCTAssertEqual(mode.dungeonMetadataSnapshot?.floorID, floor.id)
            XCTAssertFalse(floor.impassableTilePoints.isEmpty)
            XCTAssertFalse(floor.tileEffectOverrides.isEmpty)
            XCTAssertFalse(floor.cardPickups.isEmpty)
        }
    }

    func testKeyDoorTowerDefinitionsStayInsideBoardAndOpenGateTargetsAreDoors() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "key-door-tower"))

        for floor in tower.floors {
            var points: [GridPoint] = [floor.spawnPoint, floor.exitPoint]
            points.append(contentsOf: floor.cardPickups.map(\.point))
            points.append(contentsOf: floor.enemies.map(\.position))
            points.append(contentsOf: floor.impassableTilePoints)
            points.append(contentsOf: floor.tileEffectOverrides.keys)
            for enemy in floor.enemies {
                if case .patrol(let path) = enemy.behavior {
                    points.append(contentsOf: path)
                }
            }
            for effect in floor.tileEffectOverrides.values {
                if case .openGate(let target) = effect {
                    points.append(target)
                    XCTAssertTrue(
                        floor.impassableTilePoints.contains(target),
                        "\(floor.title) の開門先は初期扉として障害物配置する必要があります"
                    )
                }
            }

            XCTAssertTrue(
                points.allSatisfy { $0.isInside(boardSize: floor.boardSize) },
                "\(floor.title) の鍵/扉配置はすべて 9×9 盤面内に収める必要があります"
            )
        }
    }

    func testWarpTowerProvidesThreePlayableInventoryFloors() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "warp-tower"))

        XCTAssertEqual(tower.title, "ワープ塔")
        XCTAssertEqual(tower.difficulty, .growth)
        XCTAssertEqual(tower.floors.count, 3)
        XCTAssertEqual(tower.floors.map(\.title), ["転移の入口", "固定ワープの間", "危険な転移先"])
        XCTAssertEqual(tower.floors[0].rewardMoveCardsAfterClear, [
            .fixedWarp,
            .straightUp2,
            .rayRight
        ])
        XCTAssertEqual(tower.floors[1].rewardMoveCardsAfterClear, [
            .fixedWarp,
            .rayRight,
            .diagonalUpRight2
        ])
        XCTAssertTrue(tower.floors[2].rewardMoveCardsAfterClear.isEmpty)

        for floor in tower.floors {
            let mode = floor.makeGameMode(dungeonID: tower.id)
            XCTAssertTrue(mode.usesDungeonExit)
            XCTAssertFalse(mode.usesTargetCollection)
            XCTAssertEqual(mode.dungeonExitPoint, floor.exitPoint)
            XCTAssertEqual(mode.dungeonRules?.allowsBasicOrthogonalMove, true)
            XCTAssertEqual(mode.dungeonRules?.cardAcquisitionMode, .inventoryOnly)
            XCTAssertEqual(mode.dungeonMetadataSnapshot?.dungeonID, tower.id)
            XCTAssertEqual(mode.dungeonMetadataSnapshot?.floorID, floor.id)
            XCTAssertFalse(floor.cardPickups.isEmpty)
        }

        XCTAssertFalse(tower.floors[0].warpTilePairs.isEmpty)
        XCTAssertFalse(tower.floors[1].fixedWarpCardTargets.isEmpty)
        XCTAssertFalse(tower.floors[2].warpTilePairs.isEmpty)
        XCTAssertFalse(tower.floors[2].fixedWarpCardTargets.isEmpty)
    }

    func testWarpTowerDefinitionsStayInsideBoardAndWarpLinksResolve() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "warp-tower"))

        for floor in tower.floors {
            var points: [GridPoint] = [floor.spawnPoint, floor.exitPoint]
            points.append(contentsOf: floor.cardPickups.map(\.point))
            points.append(contentsOf: floor.enemies.map(\.position))
            points.append(contentsOf: floor.impassableTilePoints)
            points.append(contentsOf: floor.tileEffectOverrides.keys)
            for enemy in floor.enemies {
                if case .patrol(let path) = enemy.behavior {
                    points.append(contentsOf: path)
                }
            }
            for warpPoints in floor.warpTilePairs.values {
                XCTAssertGreaterThanOrEqual(warpPoints.count, 2)
                points.append(contentsOf: warpPoints)
            }
            for targets in floor.fixedWarpCardTargets.values {
                XCTAssertFalse(targets.isEmpty)
                points.append(contentsOf: targets)
            }

            XCTAssertTrue(
                points.allSatisfy { $0.isInside(boardSize: floor.boardSize) },
                "\(floor.title) のワープ配置はすべて 9×9 盤面内に収める必要があります"
            )

            let mode = floor.makeGameMode(dungeonID: tower.id)
            for warpPoints in floor.warpTilePairs.values {
                for point in warpPoints {
                    guard case .warp = mode.tileEffects[point] else {
                        XCTFail("\(floor.title) の \(point) はワープ床として解決される必要があります")
                        continue
                    }
                }
            }
            XCTAssertEqual(mode.fixedWarpCardTargets, floor.fixedWarpCardTargets)
        }
    }

    func testWarpTowerWarpRoutesShortenRepresentativeBasicRoutes() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "warp-tower"))

        let firstCore = makeCore(mode: tower.floors[0].makeGameMode(dungeonID: tower.id))
        for destination in [
            GridPoint(x: 1, y: 0),
            GridPoint(x: 2, y: 0),
            GridPoint(x: 2, y: 1),
            GridPoint(x: 7, y: 6),
            GridPoint(x: 8, y: 6),
            GridPoint(x: 8, y: 7),
            GridPoint(x: 8, y: 8)
        ] {
            playBasicMove(to: destination, in: firstCore)
        }
        XCTAssertEqual(firstCore.progress, .cleared)
        XCTAssertLessThan(firstCore.moveCount, 16)

        let secondRunState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 1,
            carriedHP: 3,
            clearedFloorCount: 1,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .fixedWarp, rewardUses: 3)]
        )
        let secondCore = makeCore(
            mode: tower.floors[1].makeGameMode(dungeonID: tower.id, runState: secondRunState)
        )
        playMove(to: GridPoint(x: 6, y: 4), in: secondCore)
        playBasicMove(to: GridPoint(x: 7, y: 4), in: secondCore)
        playBasicMove(to: GridPoint(x: 8, y: 4), in: secondCore)
        XCTAssertEqual(secondCore.progress, .cleared)
        XCTAssertLessThan(secondCore.moveCount, 8)

        let thirdCore = makeCore(mode: tower.floors[2].makeGameMode(dungeonID: tower.id))
        for destination in [
            GridPoint(x: 0, y: 1),
            GridPoint(x: 1, y: 1),
            GridPoint(x: 6, y: 7),
            GridPoint(x: 6, y: 8),
            GridPoint(x: 7, y: 8),
            GridPoint(x: 8, y: 8)
        ] {
            playBasicMove(to: destination, in: thirdCore)
        }
        XCTAssertEqual(thirdCore.progress, .cleared)
        XCTAssertEqual(thirdCore.dungeonHP, 2, "危険な転移先は近道だが見張りの危険範囲で HP を 1 失う想定です")
        XCTAssertLessThan(thirdCore.moveCount, 16)
    }

    func testWarpTowerRewardCardsAreUsableOnNextFloorStart() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "warp-tower"))
        let secondRunState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 1,
            carriedHP: 3,
            clearedFloorCount: 1,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .fixedWarp, rewardUses: 3)]
        )
        let secondCore = makeCore(mode: tower.floors[1].makeGameMode(dungeonID: tower.id, runState: secondRunState))

        XCTAssertTrue(
            secondCore.availableMoves().contains { $0.moveCard == .fixedWarp && $0.destination == GridPoint(x: 6, y: 4) },
            "ワープ塔 1F 報酬の固定ワープは 2F 初手で出口側へ短縮できる必要があります"
        )

        let thirdRunState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 2,
            carriedHP: 3,
            clearedFloorCount: 2,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .fixedWarp, rewardUses: 3)]
        )
        let thirdCore = makeCore(mode: tower.floors[2].makeGameMode(dungeonID: tower.id, runState: thirdRunState))

        XCTAssertTrue(
            thirdCore.availableMoves().contains { $0.moveCard == .fixedWarp && $0.destination == GridPoint(x: 6, y: 6) },
            "ワープ塔 2F 報酬の固定ワープは 3F の危険な転移先を読む候補になる想定です"
        )
    }

    func testTrapTowerProvidesThreePlayableInventoryFloors() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "trap-tower"))

        XCTAssertEqual(tower.title, "罠塔")
        XCTAssertEqual(tower.difficulty, .growth)
        XCTAssertEqual(tower.floors.count, 3)
        XCTAssertEqual(tower.floors.map(\.title), ["見える罠", "罠列の抜け道", "罠と見張り"])
        XCTAssertEqual(tower.floors[0].rewardMoveCardsAfterClear, [
            .straightRight2,
            .straightUp2,
            .diagonalUpRight2
        ])
        XCTAssertEqual(tower.floors[1].rewardMoveCardsAfterClear, [
            .rayRight,
            .diagonalUpRight2,
            .straightUp2
        ])
        XCTAssertTrue(tower.floors[2].rewardMoveCardsAfterClear.isEmpty)

        for floor in tower.floors {
            let mode = floor.makeGameMode(dungeonID: tower.id)
            XCTAssertTrue(mode.usesDungeonExit)
            XCTAssertFalse(mode.usesTargetCollection)
            XCTAssertEqual(mode.dungeonExitPoint, floor.exitPoint)
            XCTAssertEqual(mode.dungeonRules?.allowsBasicOrthogonalMove, true)
            XCTAssertEqual(mode.dungeonRules?.cardAcquisitionMode, .inventoryOnly)
            XCTAssertEqual(mode.dungeonMetadataSnapshot?.dungeonID, tower.id)
            XCTAssertEqual(mode.dungeonMetadataSnapshot?.floorID, floor.id)
            XCTAssertFalse(floor.hazards.isEmpty)
            XCTAssertFalse(floor.cardPickups.isEmpty)
        }
    }

    func testTrapTowerDefinitionsStayInsideBoardAndExposeDamageTrapPoints() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "trap-tower"))

        for floor in tower.floors {
            var points: [GridPoint] = [floor.spawnPoint, floor.exitPoint]
            points.append(contentsOf: floor.cardPickups.map(\.point))
            points.append(contentsOf: floor.enemies.map(\.position))
            for enemy in floor.enemies {
                if case .patrol(let path) = enemy.behavior {
                    points.append(contentsOf: path)
                }
            }

            var expectedTrapPoints: Set<GridPoint> = []
            for hazard in floor.hazards {
                switch hazard {
                case .damageTrap(let trapPoints, let damage):
                    XCTAssertEqual(damage, 1)
                    XCTAssertFalse(trapPoints.isEmpty)
                    expectedTrapPoints.formUnion(trapPoints)
                    points.append(contentsOf: trapPoints)
                case .brittleFloor(let brittlePoints):
                    points.append(contentsOf: brittlePoints)
                }
            }

            XCTAssertTrue(
                points.allSatisfy { $0.isInside(boardSize: floor.boardSize) },
                "\(floor.title) の罠配置はすべて 9×9 盤面内に収める必要があります"
            )
            let core = makeCore(mode: floor.makeGameMode(dungeonID: tower.id))
            XCTAssertEqual(core.damageTrapPoints, expectedTrapPoints)
        }
    }

    func testTrapTowerRepresentativeRoutesCanClearWithVisibleTrapTradeoffs() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "trap-tower"))

        let firstCore = makeCore(mode: tower.floors[0].makeGameMode(dungeonID: tower.id))
        for destination in [
            GridPoint(x: 1, y: 0),
            GridPoint(x: 2, y: 0),
            GridPoint(x: 3, y: 0),
            GridPoint(x: 4, y: 0),
            GridPoint(x: 5, y: 0),
            GridPoint(x: 6, y: 0),
            GridPoint(x: 7, y: 0),
            GridPoint(x: 8, y: 0),
            GridPoint(x: 8, y: 1),
            GridPoint(x: 8, y: 2),
            GridPoint(x: 8, y: 3),
            GridPoint(x: 8, y: 4),
            GridPoint(x: 8, y: 5),
            GridPoint(x: 8, y: 6),
            GridPoint(x: 8, y: 7),
            GridPoint(x: 8, y: 8)
        ] {
            playBasicMove(to: destination, in: firstCore)
        }
        XCTAssertEqual(firstCore.progress, .cleared)
        XCTAssertEqual(firstCore.dungeonHP, 3, "1F は罠を避ける遠回りでノーダメージ突破できる想定です")

        let secondCore = makeCore(mode: tower.floors[1].makeGameMode(dungeonID: tower.id))
        playBasicMove(to: GridPoint(x: 1, y: 4), in: secondCore)
        playMove(to: GridPoint(x: 8, y: 4), in: secondCore)
        XCTAssertEqual(secondCore.progress, .cleared)
        XCTAssertEqual(secondCore.dungeonHP, 1, "罠列は近道になるが、途中の罠2枚ぶんHPを支払う想定です")

        let thirdCore = makeCore(mode: tower.floors[2].makeGameMode(dungeonID: tower.id))
        for destination in [
            GridPoint(x: 1, y: 0),
            GridPoint(x: 2, y: 0),
            GridPoint(x: 3, y: 0),
            GridPoint(x: 4, y: 0),
            GridPoint(x: 5, y: 0),
            GridPoint(x: 6, y: 0),
            GridPoint(x: 7, y: 0),
            GridPoint(x: 8, y: 0),
            GridPoint(x: 8, y: 1),
            GridPoint(x: 8, y: 2),
            GridPoint(x: 8, y: 3),
            GridPoint(x: 8, y: 4),
            GridPoint(x: 8, y: 5),
            GridPoint(x: 8, y: 6),
            GridPoint(x: 8, y: 7),
            GridPoint(x: 8, y: 8)
        ] {
            playBasicMove(to: destination, in: thirdCore)
        }
        XCTAssertEqual(thirdCore.progress, .cleared)
        XCTAssertEqual(thirdCore.dungeonHP, 3)
    }

    func testRoguelikeTowerProvidesThreePlayableInventoryFloorsWithoutGrowthDifficulty() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))

        XCTAssertEqual(tower.title, "試練塔")
        XCTAssertEqual(tower.difficulty, .roguelike)
        XCTAssertEqual(tower.floors.count, 3)
        XCTAssertEqual(tower.floors.map(\.title), ["試練の入口", "罠列と短縮路", "混成試練"])
        XCTAssertEqual(tower.floors[0].rewardMoveCardsAfterClear, [
            .rayRight,
            .fixedWarp,
            .diagonalUpRight2
        ])
        XCTAssertEqual(tower.floors[1].rewardMoveCardsAfterClear, [
            .fixedWarp,
            .rayUp,
            .straightRight2
        ])
        XCTAssertTrue(tower.floors[2].rewardMoveCardsAfterClear.isEmpty)

        let firstMode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower))
        XCTAssertEqual(firstMode.dungeonRules?.difficulty, .roguelike)
        XCTAssertEqual(firstMode.dungeonRules?.allowsBasicOrthogonalMove, true)
        XCTAssertEqual(firstMode.dungeonRules?.cardAcquisitionMode, .inventoryOnly)

        for floor in tower.floors {
            let mode = floor.makeGameMode(dungeonID: tower.id, difficulty: tower.difficulty)
            XCTAssertTrue(mode.usesDungeonExit)
            XCTAssertFalse(mode.usesTargetCollection)
            XCTAssertEqual(mode.dungeonExitPoint, floor.exitPoint)
            XCTAssertEqual(mode.dungeonRules?.difficulty, .roguelike)
            XCTAssertFalse(floor.hazards.isEmpty)
            XCTAssertFalse(floor.cardPickups.isEmpty)
        }
    }

    func testRoguelikeTowerDefinitionsStayInsideBoardAndExposeMixedGimmicks() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))
        var hasWarp = false
        var hasFixedWarpTarget = false
        var hasBrittleFloor = false
        var hasDamageTrap = false

        for floor in tower.floors {
            var points: [GridPoint] = [floor.spawnPoint, floor.exitPoint]
            points.append(contentsOf: floor.cardPickups.map(\.point))
            points.append(contentsOf: floor.enemies.map(\.position))
            points.append(contentsOf: floor.impassableTilePoints)
            points.append(contentsOf: floor.tileEffectOverrides.keys)
            for enemy in floor.enemies {
                if case .patrol(let path) = enemy.behavior {
                    points.append(contentsOf: path)
                }
            }
            for hazard in floor.hazards {
                switch hazard {
                case .damageTrap(let trapPoints, let damage):
                    hasDamageTrap = true
                    XCTAssertEqual(damage, 1)
                    points.append(contentsOf: trapPoints)
                case .brittleFloor(let brittlePoints):
                    hasBrittleFloor = true
                    points.append(contentsOf: brittlePoints)
                }
            }
            for warpPoints in floor.warpTilePairs.values {
                hasWarp = true
                XCTAssertGreaterThanOrEqual(warpPoints.count, 2)
                points.append(contentsOf: warpPoints)
            }
            for targets in floor.fixedWarpCardTargets.values {
                hasFixedWarpTarget = true
                XCTAssertFalse(targets.isEmpty)
                points.append(contentsOf: targets)
            }

            XCTAssertTrue(
                points.allSatisfy { $0.isInside(boardSize: floor.boardSize) },
                "\(floor.title) の配置はすべて 9×9 盤面内に収める必要があります"
            )
        }

        XCTAssertTrue(hasWarp)
        XCTAssertTrue(hasFixedWarpTarget)
        XCTAssertTrue(hasBrittleFloor)
        XCTAssertTrue(hasDamageTrap)
    }

    func testRoguelikeTowerRepresentativeRoutesCanClearWithTemporaryCards() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))

        let firstCore = makeCore(mode: try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower)))
        for destination in [
            GridPoint(x: 1, y: 0),
            GridPoint(x: 3, y: 0),
            GridPoint(x: 4, y: 0),
            GridPoint(x: 5, y: 0),
            GridPoint(x: 6, y: 0),
            GridPoint(x: 7, y: 0),
            GridPoint(x: 8, y: 0),
            GridPoint(x: 8, y: 1),
            GridPoint(x: 8, y: 3),
            GridPoint(x: 8, y: 4),
            GridPoint(x: 8, y: 5),
            GridPoint(x: 8, y: 6),
            GridPoint(x: 8, y: 7),
            GridPoint(x: 8, y: 8)
        ] {
            playMoveOrBasicMove(to: destination, in: firstCore)
        }
        XCTAssertEqual(firstCore.progress, .cleared)
        XCTAssertEqual(firstCore.moveCount, 14)

        let secondRunState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 1,
            carriedHP: 3,
            clearedFloorCount: 1,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .fixedWarp, rewardUses: 3)]
        )
        let secondCore = makeCore(
            mode: tower.floors[1].makeGameMode(
                dungeonID: tower.id,
                difficulty: tower.difficulty,
                runState: secondRunState
            )
        )
        playBasicMove(to: GridPoint(x: 1, y: 4), in: secondCore)
        playMove(to: GridPoint(x: 6, y: 4), in: secondCore)
        playMove(to: GridPoint(x: 8, y: 4), in: secondCore)
        XCTAssertEqual(secondCore.progress, .cleared)
        XCTAssertEqual(secondCore.dungeonHP, 3)

        let thirdRunState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 2,
            carriedHP: 3,
            clearedFloorCount: 2,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .fixedWarp, rewardUses: 3)]
        )
        let thirdCore = makeCore(
            mode: tower.floors[2].makeGameMode(
                dungeonID: tower.id,
                difficulty: tower.difficulty,
                runState: thirdRunState
            )
        )
        playBasicMove(to: GridPoint(x: 1, y: 0), in: thirdCore)
        playBasicMove(to: GridPoint(x: 2, y: 0), in: thirdCore)
        playMove(to: GridPoint(x: 8, y: 6), in: thirdCore)
        playBasicMove(to: GridPoint(x: 8, y: 7), in: thirdCore)
        playBasicMove(to: GridPoint(x: 8, y: 8), in: thirdCore)
        XCTAssertEqual(thirdCore.progress, .cleared)
    }

    func testTrapTowerRewardCardsAreUsableOnNextFloorStart() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "trap-tower"))
        let secondRunState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 1,
            carriedHP: 3,
            clearedFloorCount: 1,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .diagonalUpRight2, rewardUses: 3)]
        )
        let secondCore = makeCore(mode: tower.floors[1].makeGameMode(dungeonID: tower.id, runState: secondRunState))

        XCTAssertTrue(
            secondCore.availableMoves().contains { $0.moveCard == .diagonalUpRight2 && $0.destination == GridPoint(x: 2, y: 6) },
            "罠塔 1F 報酬の斜め移動は 2F の上側迂回へ使える必要があります"
        )
    }

    func testTutorialTowerInitialRunStartsAtFirstFloor() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let mode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower))
        let runState = try XCTUnwrap(mode.dungeonMetadataSnapshot?.runState)

        XCTAssertEqual(mode.dungeonMetadataSnapshot?.floorID, tower.floors[0].id)
        XCTAssertEqual(runState.dungeonID, tower.id)
        XCTAssertEqual(runState.currentFloorIndex, 0)
        XCTAssertEqual(runState.clearedFloorCount, 0)
        XCTAssertEqual(runState.totalMoveCount, 0)
        XCTAssertTrue(runState.rewardInventoryEntries.isEmpty)
        XCTAssertEqual(mode.dungeonRules?.cardAcquisitionMode, .inventoryOnly)
        XCTAssertEqual(mode.handSize, 10)
        XCTAssertEqual(mode.nextPreviewCount, 0)
        XCTAssertEqual(mode.dungeonRules?.failureRule.initialHP, tower.floors[0].failureRule.initialHP)
        XCTAssertFalse(tower.floors[0].cardPickups.isEmpty)
        XCTAssertFalse(tower.floors[1].cardPickups.isEmpty)
        XCTAssertFalse(tower.floors[2].cardPickups.isEmpty)
        XCTAssertEqual(tower.floors[0].rewardMoveCardsAfterClear.count, 3)
        XCTAssertEqual(tower.floors[1].rewardMoveCardsAfterClear.count, 3)
        XCTAssertTrue(tower.floors[2].rewardMoveCardsAfterClear.isEmpty)

        let core = makeCore(mode: mode)
        XCTAssertTrue(core.handStacks.isEmpty)
        XCTAssertTrue(core.nextCards.isEmpty)
        XCTAssertTrue(core.dungeonInventoryEntries.isEmpty)
    }

    func testGrowthTowerCardVariationIsStableForSameSeed() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let firstMode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower, cardVariationSeed: 42))
        let secondMode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower, cardVariationSeed: 42))
        let firstRunState = try XCTUnwrap(firstMode.dungeonMetadataSnapshot?.runState)
        let secondRunState = try XCTUnwrap(secondMode.dungeonMetadataSnapshot?.runState)

        let firstFloor = try XCTUnwrap(tower.resolvedFloor(at: 0, runState: firstRunState))
        let secondFloor = try XCTUnwrap(tower.resolvedFloor(at: 0, runState: secondRunState))

        XCTAssertEqual(firstRunState.cardVariationSeed, 42)
        XCTAssertEqual(secondRunState.cardVariationSeed, 42)
        XCTAssertEqual(firstFloor.cardPickups, secondFloor.cardPickups)
        XCTAssertEqual(firstFloor.rewardMoveCardsAfterClear, secondFloor.rewardMoveCardsAfterClear)
        XCTAssertEqual(firstMode.dungeonRules?.cardPickups, firstFloor.cardPickups)

        let core = makeCore(mode: firstMode)
        XCTAssertEqual(core.activeDungeonCardPickups, firstFloor.cardPickups)
    }

    func testGrowthTowerCardVariationChangesAcrossSeedsAndKeepsSafeCells() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let firstRunState = DungeonRunState(
            dungeonID: tower.id,
            carriedHP: 3,
            cardVariationSeed: 100
        )
        let secondRunState = DungeonRunState(
            dungeonID: tower.id,
            carriedHP: 3,
            cardVariationSeed: 200
        )

        let firstFloors = try (0..<8).map { floorIndex in
            try XCTUnwrap(tower.resolvedFloor(at: floorIndex, runState: firstRunState))
        }
        let secondFloors = try (0..<8).map { floorIndex in
            try XCTUnwrap(tower.resolvedFloor(at: floorIndex, runState: secondRunState))
        }

        XCTAssertNotEqual(
            firstFloors.flatMap(\.cardPickups),
            secondFloors.flatMap(\.cardPickups)
        )
        XCTAssertNotEqual(
            firstFloors.flatMap(\.rewardMoveCardsAfterClear),
            secondFloors.flatMap(\.rewardMoveCardsAfterClear)
        )

        for floor in firstFloors {
            let blocked = blockedGrowthTowerPickupPoints(for: floor)
            XCTAssertTrue(floor.cardPickups.allSatisfy { !blocked.contains($0.point) })
        }
    }

    func testGrowthTowerCardVariationSeedCarriesToNextFloor() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let mode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower, cardVariationSeed: 999))
        let runState = try XCTUnwrap(mode.dungeonMetadataSnapshot?.runState)

        let advanced = runState.advancedToNextFloor(
            carryoverHP: 2,
            currentFloorMoveCount: 6,
            rewardMoveCard: .straightRight2
        )
        let nextFloor = try XCTUnwrap(tower.resolvedFloor(at: 1, runState: advanced))
        let repeatedNextFloor = try XCTUnwrap(tower.resolvedFloor(at: 1, runState: advanced))

        XCTAssertEqual(advanced.cardVariationSeed, 999)
        XCTAssertEqual(nextFloor, repeatedNextFloor)
    }

    func testGrowthTowerResolvedCardsExcludeBasicAndFixedWarp() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let runState = DungeonRunState(
            dungeonID: tower.id,
            carriedHP: 3,
            cardVariationSeed: 777
        )
        let basicOneStepCards: Set<MoveCard> = [.kingUp, .kingDown, .kingLeft, .kingRight]

        for floorIndex in tower.floors.indices {
            let floor = try XCTUnwrap(tower.resolvedFloor(at: floorIndex, runState: runState))
            XCTAssertTrue(floor.cardPickups.allSatisfy { !basicOneStepCards.contains($0.card) })
            XCTAssertTrue(floor.rewardMoveCardsAfterClear.allSatisfy { !basicOneStepCards.contains($0) })
            XCTAssertFalse(floor.cardPickups.contains { $0.card == .fixedWarp })
            XCTAssertFalse(floor.rewardMoveCardsAfterClear.contains(.fixedWarp))
        }
    }

    func testNonGrowthTowersDoNotResolveCardVariation() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let runState = DungeonRunState(
            dungeonID: tower.id,
            carriedHP: 3,
            cardVariationSeed: 123
        )
        let resolvedFloor = try XCTUnwrap(tower.resolvedFloor(at: 0, runState: runState))
        let mode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower, cardVariationSeed: 456))

        XCTAssertEqual(resolvedFloor, tower.floors[0])
        XCTAssertNil(mode.dungeonMetadataSnapshot?.runState?.cardVariationSeed)
        XCTAssertEqual(mode.dungeonRules?.cardPickups, tower.floors[0].cardPickups)
    }

    func testDungeonCardPickupAddsSingleUseAndConsumptionRemovesIt() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let mode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower))
        let core = makeCore(mode: mode)

        playBasicMove(to: GridPoint(x: 1, y: 1), in: core)

        XCTAssertEqual(
            core.dungeonInventoryEntries,
            [DungeonInventoryEntry(card: .straightUp2, rewardUses: 0, pickupUses: 1)]
        )
        XCTAssertFalse(core.activeDungeonCardPickups.contains { $0.point == GridPoint(x: 1, y: 1) })

        playMove(to: GridPoint(x: 1, y: 3), in: core)

        XCTAssertFalse(core.dungeonInventoryEntries.contains { $0.card == .straightUp2 })
        XCTAssertTrue(core.dungeonInventoryEntries.contains { $0.card == .straightRight2 && $0.pickupUses == 1 })
    }

    func testDungeonResumeSnapshotRestoresCurrentFloorState() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let mode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower))
        let core = makeCore(mode: mode)

        playBasicMove(to: GridPoint(x: 1, y: 1), in: core)

        let snapshot = try XCTUnwrap(core.makeDungeonResumeSnapshot())
        let resumeMode = try XCTUnwrap(DungeonLibrary.shared.resumeMode(from: snapshot))
        let restoredCore = makeCore(mode: resumeMode)

        XCTAssertTrue(restoredCore.restoreDungeonResumeSnapshot(snapshot))
        XCTAssertEqual(restoredCore.current, core.current)
        XCTAssertEqual(restoredCore.moveCount, core.moveCount)
        XCTAssertEqual(restoredCore.dungeonHP, core.dungeonHP)
        XCTAssertEqual(restoredCore.remainingDungeonTurns, core.remainingDungeonTurns)
        XCTAssertEqual(restoredCore.dungeonInventoryEntries, core.dungeonInventoryEntries)
        XCTAssertEqual(restoredCore.collectedDungeonCardPickupIDs, core.collectedDungeonCardPickupIDs)
        XCTAssertEqual(Set(restoredCore.activeDungeonCardPickups.map(\.id)), Set(core.activeDungeonCardPickups.map(\.id)))
    }

    func testDungeonResumeSnapshotRestoresKeyEnemiesAndFloorDamageState() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "key-door-tower"))
        let mode = try XCTUnwrap(DungeonLibrary.shared.floorMode(for: tower, floorIndex: 0))
        let core = makeCore(mode: mode)

        for destination in [
            GridPoint(x: 1, y: 4),
            GridPoint(x: 2, y: 4),
            GridPoint(x: 2, y: 5),
            GridPoint(x: 2, y: 6)
        ] {
            playBasicMove(to: destination, in: core)
        }

        let snapshot = try XCTUnwrap(core.makeDungeonResumeSnapshot())
        let restoredCore = makeCore(mode: try XCTUnwrap(DungeonLibrary.shared.resumeMode(from: snapshot)))

        XCTAssertTrue(restoredCore.restoreDungeonResumeSnapshot(snapshot))
        XCTAssertEqual(restoredCore.current, core.current)
        XCTAssertEqual(restoredCore.enemyStates, core.enemyStates)
        XCTAssertEqual(restoredCore.isDungeonExitUnlocked, core.isDungeonExitUnlocked)
        XCTAssertEqual(restoredCore.crackedFloorPoints, core.crackedFloorPoints)
        XCTAssertEqual(restoredCore.collapsedFloorPoints, core.collapsedFloorPoints)
        XCTAssertEqual(restoredCore.hazardDamageMitigationsRemaining, core.hazardDamageMitigationsRemaining)
        XCTAssertEqual(restoredCore.dungeonHP, core.dungeonHP)
    }

    func testGrowthTowerResumeSnapshotKeepsCardVariationSeedStable() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let mode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower, cardVariationSeed: 999))
        let core = makeCore(mode: mode)

        let basicMove = try XCTUnwrap(core.availableBasicOrthogonalMoves().first)
        core.playBasicOrthogonalMove(using: basicMove)

        let snapshot = try XCTUnwrap(core.makeDungeonResumeSnapshot())
        let resumedMode = try XCTUnwrap(DungeonLibrary.shared.resumeMode(from: snapshot))
        let originalFloor = try XCTUnwrap(tower.resolvedFloor(at: 0, runState: snapshot.runState))
        let resumedFloor = try XCTUnwrap(tower.resolvedFloor(at: 0, runState: resumedMode.dungeonMetadataSnapshot?.runState))

        XCTAssertEqual(snapshot.runState.cardVariationSeed, 999)
        XCTAssertEqual(resumedMode.dungeonMetadataSnapshot?.runState?.cardVariationSeed, 999)
        XCTAssertEqual(resumedFloor.cardPickups, originalFloor.cardPickups)
        XCTAssertEqual(resumedFloor.rewardMoveCardsAfterClear, originalFloor.rewardMoveCardsAfterClear)
    }

    func testDungeonInventoryCarriesOnlyRewardUsesBetweenFloors() {
        let runState = DungeonRunState(
            dungeonID: "tutorial-tower",
            currentFloorIndex: 0,
            carriedHP: 3,
            totalMoveCount: 0,
            clearedFloorCount: 0
        )

        let advanced = runState.advancedToNextFloor(
            carryoverHP: 2,
            currentFloorMoveCount: 5,
            currentInventoryEntries: [
                DungeonInventoryEntry(card: .straightRight2, rewardUses: 2, pickupUses: 4),
                DungeonInventoryEntry(card: .straightUp2, rewardUses: 0, pickupUses: 1)
            ]
        )

        XCTAssertEqual(
            advanced.rewardInventoryEntries,
            [DungeonInventoryEntry(card: .straightRight2, rewardUses: 2, pickupUses: 0)]
        )
    }

    func testDungeonRewardSelectionCanAddUpgradeAndRemoveCarriedRewardCards() {
        let runState = DungeonRunState(
            dungeonID: "tutorial-tower",
            currentFloorIndex: 0,
            carriedHP: 3,
            totalMoveCount: 0,
            clearedFloorCount: 0,
            rewardInventoryEntries: [
                DungeonInventoryEntry(card: .straightRight2, rewardUses: 2),
                DungeonInventoryEntry(card: .straightUp2, rewardUses: 1)
            ]
        )

        let added = runState.advancedToNextFloor(
            carryoverHP: 2,
            currentFloorMoveCount: 5,
            rewardSelection: .add(.rayRight)
        )
        let upgraded = runState.advancedToNextFloor(
            carryoverHP: 2,
            currentFloorMoveCount: 5,
            rewardSelection: .upgrade(.straightRight2)
        )
        let removed = runState.advancedToNextFloor(
            carryoverHP: 2,
            currentFloorMoveCount: 5,
            rewardSelection: .remove(.straightUp2)
        )

        XCTAssertEqual(
            added.rewardInventoryEntries,
            [
                DungeonInventoryEntry(card: .straightRight2, rewardUses: 2),
                DungeonInventoryEntry(card: .straightUp2, rewardUses: 1),
                DungeonInventoryEntry(card: .rayRight, rewardUses: 3)
            ]
        )
        XCTAssertEqual(
            upgraded.rewardInventoryEntries,
            [
                DungeonInventoryEntry(card: .straightRight2, rewardUses: 3),
                DungeonInventoryEntry(card: .straightUp2, rewardUses: 1)
            ]
        )
        XCTAssertEqual(
            removed.rewardInventoryEntries,
            [DungeonInventoryEntry(card: .straightRight2, rewardUses: 2)]
        )
    }

    func testDungeonRewardSelectionCanCarryOverUnusedPickupCard() {
        let runState = DungeonRunState(
            dungeonID: "tutorial-tower",
            currentFloorIndex: 0,
            carriedHP: 3,
            totalMoveCount: 0,
            clearedFloorCount: 0,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .straightRight2, rewardUses: 2)]
        )

        let carriedPickup = runState.advancedToNextFloor(
            carryoverHP: 2,
            currentFloorMoveCount: 5,
            rewardSelection: .carryOverPickup(.straightUp2),
            currentInventoryEntries: [
                DungeonInventoryEntry(card: .straightRight2, rewardUses: 2),
                DungeonInventoryEntry(card: .straightUp2, pickupUses: 1)
            ],
            rewardAddUses: 4
        )
        let ignoredUsedPickup = runState.advancedToNextFloor(
            carryoverHP: 2,
            currentFloorMoveCount: 5,
            rewardSelection: .carryOverPickup(.straightUp2),
            currentInventoryEntries: [
                DungeonInventoryEntry(card: .straightRight2, rewardUses: 2),
                DungeonInventoryEntry(card: .straightUp2, pickupUses: 0)
            ],
            rewardAddUses: 4
        )
        let mergedExistingReward = runState.advancedToNextFloor(
            carryoverHP: 2,
            currentFloorMoveCount: 5,
            rewardSelection: .carryOverPickup(.straightRight2),
            currentInventoryEntries: [
                DungeonInventoryEntry(card: .straightRight2, rewardUses: 2, pickupUses: 1)
            ],
            rewardAddUses: 3
        )

        XCTAssertEqual(
            carriedPickup.rewardInventoryEntries,
            [
                DungeonInventoryEntry(card: .straightRight2, rewardUses: 2),
                DungeonInventoryEntry(card: .straightUp2, rewardUses: 4)
            ]
        )
        XCTAssertEqual(
            ignoredUsedPickup.rewardInventoryEntries,
            [DungeonInventoryEntry(card: .straightRight2, rewardUses: 2)]
        )
        XCTAssertEqual(
            mergedExistingReward.rewardInventoryEntries,
            [DungeonInventoryEntry(card: .straightRight2, rewardUses: 5)]
        )
    }

    func testDungeonRewardCardConsumptionReducesUsesAndRemovesEmptyHandStack() {
        let runState = DungeonRunState(
            dungeonID: "test-tower",
            currentFloorIndex: 1,
            carriedHP: 3,
            clearedFloorCount: 1,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .straightRight2, rewardUses: 3)]
        )
        let mode = GameMode(
            identifier: .dungeonFloor,
            displayName: "報酬消費テスト",
            regulation: GameMode.Regulation(
                boardSize: 8,
                handSize: 10,
                nextPreviewCount: 0,
                allowsStacking: true,
                deckPreset: .standard,
                spawnRule: .fixed(GridPoint(x: 0, y: 0)),
                penalties: GameMode.PenaltySettings(
                    deadlockPenaltyCost: 0,
                    manualRedrawPenaltyCost: 0,
                    manualDiscardPenaltyCost: 1,
                    revisitPenaltyCost: 0
                ),
                completionRule: .dungeonExit(exitPoint: GridPoint(x: 7, y: 7)),
                dungeonRules: DungeonRules(
                    difficulty: .growth,
                    failureRule: DungeonFailureRule(initialHP: 3, turnLimit: nil),
                    allowsBasicOrthogonalMove: true,
                    cardAcquisitionMode: .inventoryOnly
                )
            ),
            leaderboardEligible: false,
            dungeonMetadata: .init(
                dungeonID: runState.dungeonID,
                floorID: "reward-consumption",
                runState: runState
            )
        )
        let core = GameCore(mode: mode)

        XCTAssertEqual(core.dungeonInventoryEntries, runState.rewardInventoryEntries)
        XCTAssertEqual(core.handStacks.first { $0.representativeMove == .straightRight2 }?.count, 3)

        playMove(to: GridPoint(x: 2, y: 0), in: core)
        XCTAssertEqual(core.dungeonInventoryEntries, [DungeonInventoryEntry(card: .straightRight2, rewardUses: 2)])
        XCTAssertEqual(core.handStacks.first { $0.representativeMove == .straightRight2 }?.count, 2)

        playBasicMove(to: GridPoint(x: 1, y: 0), in: core)
        playMove(to: GridPoint(x: 3, y: 0), in: core)
        XCTAssertEqual(core.dungeonInventoryEntries, [DungeonInventoryEntry(card: .straightRight2, rewardUses: 1)])
        XCTAssertEqual(core.handStacks.first { $0.representativeMove == .straightRight2 }?.count, 1)

        playBasicMove(to: GridPoint(x: 2, y: 0), in: core)
        playMove(to: GridPoint(x: 4, y: 0), in: core)
        XCTAssertTrue(core.dungeonInventoryEntries.isEmpty)
        XCTAssertFalse(core.handStacks.contains { $0.representativeMove == .straightRight2 })
    }

    func testDungeonRewardInventoryRemovalOnlyDropsRewardUses() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let mode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower))
        let core = makeCore(mode: mode)

        XCTAssertTrue(core.addDungeonInventoryCardForTesting(.straightRight2, pickupUses: 1, rewardUses: 2))
        XCTAssertTrue(core.removeDungeonRewardInventoryCard(.straightRight2))

        XCTAssertEqual(core.dungeonInventoryEntries, [DungeonInventoryEntry(card: .straightRight2, pickupUses: 1)])
        XCTAssertEqual(core.handStacks.first { $0.representativeMove == .straightRight2 }?.count, 1)
        XCTAssertFalse(core.removeDungeonRewardInventoryCard(.straightRight2))
    }

    func testDungeonInventoryStacksDuplicateCardsAndRejectsNewCardAtNineKindsWhenBasicMoveUsesTenthSlot() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let mode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower))
        let core = makeCore(mode: mode)
        let nineCards = Array(MoveCard.allCases.prefix(9))
        let tenth = try XCTUnwrap(MoveCard.allCases.dropFirst(9).first)

        for card in nineCards {
            XCTAssertTrue(core.addDungeonInventoryCardForTesting(card, pickupUses: 1))
        }

        XCTAssertEqual(core.dungeonInventoryEntries.count, 9)
        XCTAssertFalse(core.addDungeonInventoryCardForTesting(tenth, pickupUses: 1))
        XCTAssertEqual(core.dungeonInventoryEntries.count, 9)
        XCTAssertTrue(core.addDungeonInventoryCardForTesting(nineCards[0], pickupUses: 1))
        XCTAssertEqual(core.dungeonInventoryEntries.count, 9)
        XCTAssertEqual(core.dungeonInventoryEntries.first { $0.card == nineCards[0] }?.pickupUses, 2)
    }

    func testDungeonInventorySyncPreservesStackIDForSameCard() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let runState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 1,
            carriedHP: 2,
            totalMoveCount: 4,
            clearedFloorCount: 1,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .straightRight2, rewardUses: 3)]
        )
        let mode = tower.floors[1].makeGameMode(
            dungeonID: tower.id,
            carriedHP: runState.carriedHP,
            runState: runState
        )
        let core = makeCore(mode: mode)
        let initialStackID = try XCTUnwrap(core.handStacks.first { $0.representativeMove == .straightRight2 }?.id)

        XCTAssertTrue(core.addDungeonInventoryCardForTesting(.straightRight2, pickupUses: 1))

        XCTAssertEqual(core.handStacks.first { $0.representativeMove == .straightRight2 }?.id, initialStackID)
        XCTAssertEqual(core.handStacks.first { $0.representativeMove == .straightRight2 }?.count, 4)
    }

    func testTutorialTowerBasicMoveRoutesFitAdjustedTurnLimits() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let basicRoutes: [[GridPoint]] = [
            [
                GridPoint(x: 1, y: 1),
                GridPoint(x: 1, y: 2),
                GridPoint(x: 1, y: 3),
                GridPoint(x: 1, y: 4),
                GridPoint(x: 2, y: 4),
                GridPoint(x: 3, y: 4)
            ],
            [
                GridPoint(x: 1, y: 0),
                GridPoint(x: 2, y: 0),
                GridPoint(x: 3, y: 0),
                GridPoint(x: 4, y: 0),
                GridPoint(x: 4, y: 1),
                GridPoint(x: 4, y: 2),
                GridPoint(x: 4, y: 3),
                GridPoint(x: 4, y: 4)
            ],
            [
                GridPoint(x: 0, y: 1),
                GridPoint(x: 1, y: 1),
                GridPoint(x: 2, y: 1),
                GridPoint(x: 3, y: 1),
                GridPoint(x: 4, y: 1),
                GridPoint(x: 4, y: 2)
            ]
        ]

        for (floor, route) in zip(tower.floors, basicRoutes) {
            let mode = floor.makeGameMode(dungeonID: tower.id)
            let core = makeCore(mode: mode, cards: [.kingUp, .kingRight, .kingDown, .kingLeft, .straightRight2])

            for destination in route {
                playBasicMove(to: destination, in: core)
            }

            XCTAssertEqual(core.progress, .cleared, "\(floor.title) は基本移動だけでも出口へ届く必要があります")
            XCTAssertLessThanOrEqual(core.moveCount, floor.failureRule.turnLimit ?? .max)
        }
    }

    func testTutorialTowerCardRoutesShortenRepresentativeBasicRoutes() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))

        let firstFloorMode = tower.floors[0].makeGameMode(dungeonID: tower.id)
        let firstCore = makeCore(mode: firstFloorMode)
        playBasicMove(to: GridPoint(x: 1, y: 1), in: firstCore)
        XCTAssertTrue(firstCore.dungeonInventoryEntries.contains { $0.card == .straightUp2 && $0.pickupUses == 1 })
        playMove(to: GridPoint(x: 1, y: 3), in: firstCore)
        XCTAssertTrue(firstCore.dungeonInventoryEntries.contains { $0.card == .straightRight2 && $0.pickupUses == 1 })
        playMove(to: GridPoint(x: 3, y: 3), in: firstCore)
        playBasicMove(to: GridPoint(x: 3, y: 4), in: firstCore)
        XCTAssertEqual(firstCore.progress, .cleared)
        XCTAssertLessThan(firstCore.moveCount, 6)

        let secondRunState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 1,
            carriedHP: 3,
            clearedFloorCount: 1,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .straightRight2, rewardUses: 3)]
        )
        let secondFloorMode = tower.floors[1].makeGameMode(
            dungeonID: tower.id,
            carriedHP: secondRunState.carriedHP,
            runState: secondRunState
        )
        let secondCore = makeCore(mode: secondFloorMode)
        playMove(to: GridPoint(x: 2, y: 0), in: secondCore)
        playMove(to: GridPoint(x: 4, y: 0), in: secondCore)
        for destination in [
            GridPoint(x: 4, y: 1),
            GridPoint(x: 4, y: 2),
            GridPoint(x: 4, y: 3),
            GridPoint(x: 4, y: 4)
        ] {
            playBasicMove(to: destination, in: secondCore)
        }
        XCTAssertEqual(secondCore.progress, .cleared)
        XCTAssertLessThan(secondCore.moveCount, 8)

        let thirdRunState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 2,
            carriedHP: 3,
            clearedFloorCount: 2,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .rayRight, rewardUses: 3)]
        )
        let thirdFloorMode = tower.floors[2].makeGameMode(
            dungeonID: tower.id,
            carriedHP: thirdRunState.carriedHP,
            runState: thirdRunState
        )
        let thirdCore = makeCore(mode: thirdFloorMode)
        playMove(to: GridPoint(x: 4, y: 2), in: thirdCore)
        XCTAssertEqual(thirdCore.progress, .cleared)
        XCTAssertLessThan(thirdCore.moveCount, 6)
    }

    func testTutorialTowerRewardCardsCreateUsefulNextFloorMoves() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))

        XCTAssertEqual(tower.floors[0].rewardMoveCardsAfterClear, [
            .straightRight2,
            .straightUp2,
            .knightRightwardChoice
        ])
        XCTAssertEqual(tower.floors[1].rewardMoveCardsAfterClear, [
            .rayRight,
            .straightRight2,
            .knightRightwardChoice
        ])

        let secondRunState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 1,
            carriedHP: 3,
            clearedFloorCount: 1,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .straightRight2, rewardUses: 3)]
        )
        let secondMode = tower.floors[1].makeGameMode(dungeonID: tower.id, runState: secondRunState)
        let secondCore = makeCore(mode: secondMode)
        XCTAssertTrue(
            secondCore.availableMoves().contains { $0.moveCard == .straightRight2 && $0.destination == GridPoint(x: 2, y: 0) },
            "1F 報酬の右2は 2F の見張り射線下を抜ける短縮手になる想定です"
        )

        let thirdRunState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 2,
            carriedHP: 3,
            clearedFloorCount: 2,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .rayRight, rewardUses: 3)]
        )
        let thirdMode = tower.floors[2].makeGameMode(dungeonID: tower.id, runState: thirdRunState)
        let thirdCore = makeCore(mode: thirdMode)
        XCTAssertTrue(
            thirdCore.availableMoves().contains { $0.moveCard == .rayRight && $0.destination == GridPoint(x: 4, y: 2) },
            "2F 報酬の右連続は 3F のひび割れ床列を一気に抜ける手になる想定です"
        )
    }

    func testTutorialTowerExcludesBasicOneStepCardsFromPickupsAndRewards() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let basicOneStepCards: Set<MoveCard> = [
            .kingUp,
            .kingRight,
            .kingDown,
            .kingLeft
        ]

        for floor in tower.floors {
            XCTAssertTrue(
                floor.cardPickups.allSatisfy { !basicOneStepCards.contains($0.card) },
                "\(floor.title) の床落ちカードに基本移動と同じ上下左右1マスカードを入れない"
            )
            XCTAssertTrue(
                floor.rewardMoveCardsAfterClear.allSatisfy { !basicOneStepCards.contains($0) },
                "\(floor.title) の報酬候補に基本移動と同じ上下左右1マスカードを入れない"
            )
        }
    }

    func testTutorialTowerThirdFloorDirectBrittleRouteCostsHP() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let thirdFloorMode = tower.floors[2].makeGameMode(dungeonID: tower.id)
        let core = makeCore(mode: thirdFloorMode)

        for destination in [
            GridPoint(x: 1, y: 2),
            GridPoint(x: 2, y: 2),
            GridPoint(x: 3, y: 2),
            GridPoint(x: 4, y: 2)
        ] {
            playBasicMove(to: destination, in: core)
        }

        XCTAssertEqual(core.progress, .cleared)
        XCTAssertEqual(core.moveCount, 4)
        XCTAssertEqual(core.dungeonHP, 2, "ひび割れ床列を雑に直進すると番兵の危険範囲で HP を失う想定です")
        XCTAssertTrue(core.crackedFloorPoints.contains(GridPoint(x: 1, y: 2)))
        XCTAssertTrue(core.crackedFloorPoints.contains(GridPoint(x: 2, y: 2)))
        XCTAssertTrue(core.crackedFloorPoints.contains(GridPoint(x: 3, y: 2)))
    }

    func testPatrolTowerBasicMoveRoutesFitTurnLimits() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "patrol-tower"))
        let basicRoutes: [[GridPoint]] = [
            [
                GridPoint(x: 1, y: 0),
                GridPoint(x: 2, y: 0),
                GridPoint(x: 3, y: 0),
                GridPoint(x: 4, y: 0),
                GridPoint(x: 5, y: 0),
                GridPoint(x: 6, y: 0),
                GridPoint(x: 7, y: 0),
                GridPoint(x: 8, y: 0),
                GridPoint(x: 8, y: 1),
                GridPoint(x: 8, y: 2),
                GridPoint(x: 8, y: 3),
                GridPoint(x: 8, y: 4),
                GridPoint(x: 8, y: 5),
                GridPoint(x: 8, y: 6),
                GridPoint(x: 8, y: 7),
                GridPoint(x: 8, y: 8)
            ],
            [
                GridPoint(x: 0, y: 3),
                GridPoint(x: 0, y: 2),
                GridPoint(x: 0, y: 1),
                GridPoint(x: 0, y: 0),
                GridPoint(x: 1, y: 0),
                GridPoint(x: 2, y: 0),
                GridPoint(x: 3, y: 0),
                GridPoint(x: 4, y: 0),
                GridPoint(x: 5, y: 0),
                GridPoint(x: 6, y: 0),
                GridPoint(x: 7, y: 0),
                GridPoint(x: 8, y: 0),
                GridPoint(x: 8, y: 1),
                GridPoint(x: 8, y: 2),
                GridPoint(x: 8, y: 3),
                GridPoint(x: 8, y: 4)
            ],
            [
                GridPoint(x: 1, y: 0),
                GridPoint(x: 2, y: 0),
                GridPoint(x: 3, y: 0),
                GridPoint(x: 4, y: 0),
                GridPoint(x: 5, y: 0),
                GridPoint(x: 6, y: 0),
                GridPoint(x: 7, y: 0),
                GridPoint(x: 8, y: 0),
                GridPoint(x: 8, y: 1),
                GridPoint(x: 8, y: 2),
                GridPoint(x: 8, y: 3),
                GridPoint(x: 8, y: 4),
                GridPoint(x: 8, y: 5),
                GridPoint(x: 8, y: 6),
                GridPoint(x: 8, y: 7),
                GridPoint(x: 8, y: 8)
            ]
        ]

        for (floor, route) in zip(tower.floors, basicRoutes) {
            let mode = floor.makeGameMode(dungeonID: tower.id)
            let core = makeCore(mode: mode)

            for destination in route {
                playBasicMove(to: destination, in: core)
            }

            XCTAssertEqual(core.progress, .cleared, "\(floor.title) は基本移動だけでも出口へ届く必要があります")
            XCTAssertLessThanOrEqual(core.moveCount, floor.failureRule.turnLimit ?? .max)
        }
    }

    func testPatrolTowerCardRoutesShortenRepresentativeBasicRoutes() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "patrol-tower"))

        let firstCore = makeCore(mode: tower.floors[0].makeGameMode(dungeonID: tower.id))
        playBasicMove(to: GridPoint(x: 1, y: 0), in: firstCore)
        playBasicMove(to: GridPoint(x: 2, y: 0), in: firstCore)
        playMove(to: GridPoint(x: 4, y: 0), in: firstCore)
        playBasicMove(to: GridPoint(x: 5, y: 0), in: firstCore)
        playBasicMove(to: GridPoint(x: 6, y: 0), in: firstCore)
        playMove(to: GridPoint(x: 6, y: 2), in: firstCore)
        playBasicMove(to: GridPoint(x: 7, y: 2), in: firstCore)
        playBasicMove(to: GridPoint(x: 8, y: 2), in: firstCore)
        playBasicMove(to: GridPoint(x: 8, y: 3), in: firstCore)
        for destination in [
            GridPoint(x: 8, y: 4),
            GridPoint(x: 8, y: 5),
            GridPoint(x: 8, y: 6),
            GridPoint(x: 8, y: 7),
            GridPoint(x: 8, y: 8)
        ] {
            playBasicMove(to: destination, in: firstCore)
        }
        XCTAssertEqual(firstCore.progress, .cleared)
        XCTAssertLessThan(firstCore.moveCount, 16)

        let secondRunState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 1,
            carriedHP: 3,
            clearedFloorCount: 1,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .straightUp2, rewardUses: 3)]
        )
        let secondCore = makeCore(
            mode: tower.floors[1].makeGameMode(dungeonID: tower.id, runState: secondRunState)
        )
        playMove(to: GridPoint(x: 0, y: 6), in: secondCore)
        playBasicMove(to: GridPoint(x: 1, y: 6), in: secondCore)
        playMove(to: GridPoint(x: 8, y: 6), in: secondCore)
        playBasicMove(to: GridPoint(x: 8, y: 5), in: secondCore)
        playBasicMove(to: GridPoint(x: 8, y: 4), in: secondCore)
        XCTAssertEqual(secondCore.progress, .cleared)
        XCTAssertLessThan(secondCore.moveCount, 16)

        let thirdRunState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 2,
            carriedHP: 3,
            clearedFloorCount: 2,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .rayRight, rewardUses: 3)]
        )
        let thirdCore = makeCore(
            mode: tower.floors[2].makeGameMode(dungeonID: tower.id, runState: thirdRunState)
        )
        playMove(to: GridPoint(x: 8, y: 0), in: thirdCore)
        for destination in [
            GridPoint(x: 8, y: 1),
            GridPoint(x: 8, y: 2),
            GridPoint(x: 8, y: 3),
            GridPoint(x: 8, y: 4),
            GridPoint(x: 8, y: 5),
            GridPoint(x: 8, y: 6),
            GridPoint(x: 8, y: 7),
            GridPoint(x: 8, y: 8)
        ] {
            playBasicMove(to: destination, in: thirdCore)
        }
        XCTAssertEqual(thirdCore.progress, .cleared)
        XCTAssertLessThan(thirdCore.moveCount, 16)
    }

    func testPatrolTowerRewardCardsAreUsableOnNextFloorStart() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "patrol-tower"))
        let secondRunState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 1,
            carriedHP: 3,
            clearedFloorCount: 1,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .straightUp2, rewardUses: 3)]
        )
        let secondCore = makeCore(mode: tower.floors[1].makeGameMode(dungeonID: tower.id, runState: secondRunState))

        XCTAssertTrue(
            secondCore.availableMoves().contains { $0.moveCard == .straightUp2 && $0.destination == GridPoint(x: 0, y: 6) },
            "巡回塔 1F 報酬の上2は 2F 初手で上側ルートへ入る候補になる想定です"
        )

        let thirdRunState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 2,
            carriedHP: 3,
            clearedFloorCount: 2,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .rayRight, rewardUses: 3)]
        )
        let thirdCore = makeCore(mode: tower.floors[2].makeGameMode(dungeonID: tower.id, runState: thirdRunState))

        XCTAssertTrue(
            thirdCore.availableMoves().contains { $0.moveCard == .rayRight && $0.destination == GridPoint(x: 8, y: 0) },
            "巡回塔 2F 報酬の右連続は 3F 初手で巡回網の下側を抜ける候補になる想定です"
        )
    }

    func testPatrolTowerExcludesBasicOneStepCardsFromPickupsAndRewards() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "patrol-tower"))
        let basicOneStepCards: Set<MoveCard> = [
            .kingUp,
            .kingRight,
            .kingDown,
            .kingLeft
        ]

        for floor in tower.floors {
            XCTAssertTrue(floor.cardPickups.allSatisfy { !basicOneStepCards.contains($0.card) })
            XCTAssertTrue(floor.rewardMoveCardsAfterClear.allSatisfy { !basicOneStepCards.contains($0) })
        }
    }

    func testPatrolTowerThirdFloorBrittleTilesCollapseAndBlockCandidates() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "patrol-tower"))
        let mode = tower.floors[2].makeGameMode(dungeonID: tower.id)
        let core = makeCore(mode: mode, cards: [.kingRight, .kingLeft, .straightRight2])
        let brittlePoint = GridPoint(x: 4, y: 3)

        for destination in [
            GridPoint(x: 1, y: 0),
            GridPoint(x: 2, y: 0),
            GridPoint(x: 3, y: 0),
            GridPoint(x: 4, y: 0),
            GridPoint(x: 4, y: 1),
            GridPoint(x: 4, y: 2),
            GridPoint(x: 4, y: 3),
            GridPoint(x: 4, y: 2),
            GridPoint(x: 4, y: 3)
        ] {
            playBasicMove(to: destination, in: core)
        }

        XCTAssertTrue(core.collapsedFloorPoints.contains(brittlePoint))
        XCTAssertFalse(core.board.isTraversable(brittlePoint))
        XCTAssertFalse(core.availableBasicOrthogonalMoves().contains { $0.destination == brittlePoint })
        XCTAssertFalse(core.availableMoves().contains { $0.destination == brittlePoint })
    }

    func testPatrolTowerPatrolDangerMatchesDamageAfterEnemyTurn() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "patrol-tower"))
        let core = makeCore(mode: tower.floors[0].makeGameMode(dungeonID: tower.id))

        playBasicMove(to: GridPoint(x: 1, y: 0), in: core)
        playBasicMove(to: GridPoint(x: 2, y: 0), in: core)
        playBasicMove(to: GridPoint(x: 3, y: 0), in: core)
        playBasicMove(to: GridPoint(x: 4, y: 0), in: core)
        playBasicMove(to: GridPoint(x: 4, y: 1), in: core)
        playBasicMove(to: GridPoint(x: 4, y: 2), in: core)
        playBasicMove(to: GridPoint(x: 4, y: 3), in: core)

        XCTAssertEqual(core.dungeonHP, 2)
        XCTAssertTrue(core.enemyDangerPoints.contains(GridPoint(x: 4, y: 3)))
    }

    func testKeyDoorTowerOpenGateUnlocksDoorAndCandidates() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "key-door-tower"))
        let floor = tower.floors[0]
        let doorPoint = GridPoint(x: 4, y: 4)
        let core = makeCore(mode: floor.makeGameMode(dungeonID: tower.id))

        XCTAssertTrue(core.board.isImpassable(doorPoint))
        XCTAssertFalse(core.isDungeonExitUnlocked)

        for destination in [
            GridPoint(x: 1, y: 4),
            GridPoint(x: 2, y: 4),
            GridPoint(x: 2, y: 5),
            GridPoint(x: 2, y: 6)
        ] {
            playBasicMove(to: destination, in: core)
        }

        XCTAssertFalse(core.board.isImpassable(doorPoint))
        XCTAssertTrue(core.board.isTraversable(doorPoint))
        XCTAssertTrue(core.isDungeonExitUnlocked)
        XCTAssertEqual(core.dungeonExitUnlockEvent?.exitPoint, floor.exitPoint)

        playMove(to: GridPoint(x: 4, y: 6), in: core)
        playBasicMove(to: GridPoint(x: 4, y: 5), in: core)

        XCTAssertTrue(
            core.availableBasicOrthogonalMoves().contains { $0.destination == doorPoint },
            "鍵マスで開門した扉は、その後の基本移動候補へ反映される必要があります"
        )
    }

    func testKeyDoorTowerExitStaysLockedWhenKeyIsSkipped() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "key-door-tower"))
        let routesSkippingKey: [[GridPoint]] = [
            [
                GridPoint(x: 0, y: 3),
                GridPoint(x: 0, y: 2),
                GridPoint(x: 0, y: 1),
                GridPoint(x: 0, y: 0),
                GridPoint(x: 1, y: 0),
                GridPoint(x: 2, y: 0),
                GridPoint(x: 3, y: 0),
                GridPoint(x: 4, y: 0),
                GridPoint(x: 5, y: 0),
                GridPoint(x: 6, y: 0),
                GridPoint(x: 7, y: 0),
                GridPoint(x: 8, y: 0),
                GridPoint(x: 8, y: 1),
                GridPoint(x: 8, y: 2),
                GridPoint(x: 8, y: 3),
                GridPoint(x: 8, y: 4)
            ],
            [
                GridPoint(x: 0, y: 3),
                GridPoint(x: 0, y: 2),
                GridPoint(x: 0, y: 1),
                GridPoint(x: 0, y: 0),
                GridPoint(x: 1, y: 0),
                GridPoint(x: 2, y: 0),
                GridPoint(x: 3, y: 0),
                GridPoint(x: 4, y: 0),
                GridPoint(x: 5, y: 0),
                GridPoint(x: 6, y: 0),
                GridPoint(x: 7, y: 0),
                GridPoint(x: 8, y: 0),
                GridPoint(x: 8, y: 1),
                GridPoint(x: 8, y: 2),
                GridPoint(x: 8, y: 3),
                GridPoint(x: 8, y: 4)
            ],
            [
                GridPoint(x: 1, y: 0),
                GridPoint(x: 2, y: 0),
                GridPoint(x: 3, y: 0),
                GridPoint(x: 4, y: 0),
                GridPoint(x: 5, y: 0),
                GridPoint(x: 6, y: 0),
                GridPoint(x: 7, y: 0),
                GridPoint(x: 8, y: 0),
                GridPoint(x: 8, y: 1),
                GridPoint(x: 8, y: 2),
                GridPoint(x: 8, y: 3),
                GridPoint(x: 8, y: 4),
                GridPoint(x: 8, y: 5),
                GridPoint(x: 8, y: 6),
                GridPoint(x: 8, y: 7),
                GridPoint(x: 8, y: 8)
            ]
        ]

        for (floor, route) in zip(tower.floors, routesSkippingKey) {
            let core = makeCore(mode: floor.makeGameMode(dungeonID: tower.id))

            for destination in route {
                playBasicMove(to: destination, in: core)
            }

            XCTAssertEqual(core.current, floor.exitPoint)
            XCTAssertFalse(core.isDungeonExitUnlocked)
            XCTAssertEqual(core.progress, .playing, "\(floor.title) は鍵を取るまで出口へ到達してもクリアしない必要があります")
            XCTAssertLessThanOrEqual(core.moveCount, floor.failureRule.turnLimit ?? .max)
        }
    }

    func testKeyDoorTowerKeyAndCardRoutesShortenRepresentativeBasicRoutes() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "key-door-tower"))

        let firstCore = makeCore(mode: tower.floors[0].makeGameMode(dungeonID: tower.id))
        for destination in [
            GridPoint(x: 1, y: 4),
            GridPoint(x: 2, y: 4),
            GridPoint(x: 2, y: 5),
            GridPoint(x: 2, y: 6)
        ] {
            playBasicMove(to: destination, in: firstCore)
        }
        playMove(to: GridPoint(x: 4, y: 6), in: firstCore)
        for destination in [
            GridPoint(x: 4, y: 5),
            GridPoint(x: 4, y: 4),
            GridPoint(x: 5, y: 4),
            GridPoint(x: 6, y: 4),
            GridPoint(x: 7, y: 4),
            GridPoint(x: 8, y: 4)
        ] {
            playBasicMove(to: destination, in: firstCore)
        }
        XCTAssertEqual(firstCore.progress, .cleared)
        XCTAssertLessThan(firstCore.moveCount, 16)

        let secondRunState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 1,
            carriedHP: 3,
            clearedFloorCount: 1,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .straightUp2, rewardUses: 3)]
        )
        let secondCore = makeCore(
            mode: tower.floors[1].makeGameMode(dungeonID: tower.id, runState: secondRunState)
        )
        playMove(to: GridPoint(x: 0, y: 6), in: secondCore)
        for destination in [
            GridPoint(x: 1, y: 6),
            GridPoint(x: 2, y: 6),
            GridPoint(x: 2, y: 7)
        ] {
            playBasicMove(to: destination, in: secondCore)
        }
        playMove(to: GridPoint(x: 4, y: 7), in: secondCore)
        for destination in [
            GridPoint(x: 4, y: 6),
            GridPoint(x: 4, y: 5),
            GridPoint(x: 4, y: 4),
            GridPoint(x: 5, y: 4),
            GridPoint(x: 6, y: 4),
            GridPoint(x: 7, y: 4),
            GridPoint(x: 8, y: 4)
        ] {
            playBasicMove(to: destination, in: secondCore)
        }
        XCTAssertEqual(secondCore.progress, .cleared)
        XCTAssertLessThan(secondCore.moveCount, 16)

        let thirdRunState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 2,
            carriedHP: 3,
            clearedFloorCount: 2,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .straightRight2, rewardUses: 3)]
        )
        let thirdCore = makeCore(
            mode: tower.floors[2].makeGameMode(dungeonID: tower.id, runState: thirdRunState)
        )
        for destination in [
            GridPoint(x: 1, y: 0),
            GridPoint(x: 2, y: 0),
            GridPoint(x: 2, y: 1),
            GridPoint(x: 2, y: 2),
            GridPoint(x: 2, y: 3),
            GridPoint(x: 2, y: 4)
        ] {
            playBasicMove(to: destination, in: thirdCore)
        }
        playMove(to: GridPoint(x: 4, y: 4), in: thirdCore)
        for destination in [
            GridPoint(x: 5, y: 4),
            GridPoint(x: 6, y: 4),
            GridPoint(x: 7, y: 4),
            GridPoint(x: 8, y: 4),
            GridPoint(x: 8, y: 5),
            GridPoint(x: 8, y: 6),
            GridPoint(x: 8, y: 7),
            GridPoint(x: 8, y: 8)
        ] {
            playBasicMove(to: destination, in: thirdCore)
        }
        XCTAssertEqual(thirdCore.progress, .cleared)
        XCTAssertLessThan(thirdCore.moveCount, 16)
    }

    func testKeyDoorTowerRewardCardsAreUsableOnNextFloorStart() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "key-door-tower"))
        let secondRunState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 1,
            carriedHP: 3,
            clearedFloorCount: 1,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .straightUp2, rewardUses: 3)]
        )
        let secondCore = makeCore(mode: tower.floors[1].makeGameMode(dungeonID: tower.id, runState: secondRunState))

        XCTAssertTrue(
            secondCore.availableMoves().contains { $0.moveCard == .straightUp2 && $0.destination == GridPoint(x: 0, y: 6) },
            "鍵扉塔 1F 報酬の上2は 2F 初手で鍵道へ入る候補になる想定です"
        )

        let thirdRunState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 2,
            carriedHP: 3,
            clearedFloorCount: 2,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .straightRight2, rewardUses: 3)]
        )
        let thirdCore = makeCore(mode: tower.floors[2].makeGameMode(dungeonID: tower.id, runState: thirdRunState))

        XCTAssertTrue(
            thirdCore.availableMoves().contains { $0.moveCard == .straightRight2 && $0.destination == GridPoint(x: 2, y: 0) },
            "鍵扉塔 2F 報酬の右2は 3F 初手で鍵側へ寄る候補になる想定です"
        )
    }

    func testDungeonRunStateAdvancesWithCarryoverHPMoveCountAndRewardCard() {
        let runState = DungeonRunState(
            dungeonID: "tutorial-tower",
            currentFloorIndex: 0,
            carriedHP: 3,
            totalMoveCount: 4,
            clearedFloorCount: 0
        )

        let advanced = runState.advancedToNextFloor(
            carryoverHP: 2,
            currentFloorMoveCount: 6,
            rewardMoveCard: .kingLeftOrRight
        )

        XCTAssertEqual(advanced.currentFloorIndex, 1)
        XCTAssertEqual(advanced.floorNumber, 2)
        XCTAssertEqual(advanced.carriedHP, 2)
        XCTAssertEqual(advanced.totalMoveCount, 10)
        XCTAssertEqual(advanced.clearedFloorCount, 1)
        XCTAssertEqual(advanced.rewardInventoryEntries, [DungeonInventoryEntry(card: .kingLeftOrRight, rewardUses: 3)])
    }

    func testRewardCardsApplyToNextFloorInventoryWithoutDeckBonus() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let runState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 1,
            carriedHP: 2,
            totalMoveCount: 5,
            clearedFloorCount: 1,
            rewardInventoryEntries: [
                DungeonInventoryEntry(card: .straightRight2, rewardUses: 3),
                DungeonInventoryEntry(card: .straightUp2, rewardUses: 1)
            ]
        )

        let mode = tower.floors[1].makeGameMode(
            dungeonID: tower.id,
            carriedHP: runState.carriedHP,
            runState: runState
        )

        XCTAssertTrue(mode.bonusMoveCards.isEmpty)
        let core = makeCore(mode: mode)
        XCTAssertTrue(core.nextCards.isEmpty)
        XCTAssertEqual(core.dungeonInventoryEntries, runState.rewardInventoryEntries)
        XCTAssertTrue(core.availableMoves().contains { $0.moveCard == .straightRight2 && $0.destination == GridPoint(x: 2, y: 0) })
        XCTAssertEqual(core.handStacks.first { $0.representativeMove == .straightRight2 }?.count, 3)
    }

    func testBasicOrthogonalMoveIsAvailableOnlyWhenDungeonRuleAllowsIt() {
        let enabledMode = makeDungeonMode(
            spawn: GridPoint(x: 2, y: 2),
            exit: GridPoint(x: 4, y: 4),
            turnLimit: 8,
            allowsBasicOrthogonalMove: true
        )
        let enabledCore = makeCore(
            mode: enabledMode,
            cards: [.straightRight2, .straightLeft2, .diagonalUpRight2, .diagonalDownLeft2, .rayUp]
        )

        XCTAssertEqual(Set(enabledCore.availableBasicOrthogonalMoves().map(\.destination)), [
            GridPoint(x: 2, y: 3),
            GridPoint(x: 3, y: 2),
            GridPoint(x: 2, y: 1),
            GridPoint(x: 1, y: 2)
        ])

        let disabledMode = makeDungeonMode(
            spawn: GridPoint(x: 2, y: 2),
            exit: GridPoint(x: 4, y: 4),
            turnLimit: 8
        )
        let disabledCore = makeCore(
            mode: disabledMode,
            cards: [.straightRight2, .straightLeft2, .diagonalUpRight2, .diagonalDownLeft2, .rayUp]
        )

        XCTAssertTrue(disabledCore.availableBasicOrthogonalMoves().isEmpty)

    }

    func testBasicOrthogonalMoveConsumesTurnButNoCard() {
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            turnLimit: 3,
            allowsBasicOrthogonalMove: true
        )
        let core = makeCore(
            mode: mode,
            cards: [.straightRight2, .straightLeft2, .diagonalUpRight2, .diagonalDownLeft2, .rayUp]
        )
        let handBefore = core.handStacks
        let nextBefore = core.nextCards

        playBasicMove(to: GridPoint(x: 0, y: 1), in: core)

        XCTAssertEqual(core.current, GridPoint(x: 0, y: 1))
        XCTAssertEqual(core.moveCount, 1)
        XCTAssertEqual(core.remainingDungeonTurns, 2)
        XCTAssertEqual(core.handStacks, handBefore)
        XCTAssertEqual(core.nextCards, nextBefore)
    }

    func testBasicOrthogonalMoveCanClearExitAndTriggerDungeonFailureRules() {
        let clearMode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 0, y: 1),
            turnLimit: 1,
            allowsBasicOrthogonalMove: true
        )
        let clearCore = makeCore(mode: clearMode, cards: [.straightRight2, .straightLeft2, .rayRight])
        playBasicMove(to: GridPoint(x: 0, y: 1), in: clearCore)
        XCTAssertEqual(clearCore.progress, .cleared)

        let failMode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            turnLimit: 1,
            allowsBasicOrthogonalMove: true
        )
        let failCore = makeCore(mode: failMode, cards: [.straightRight2, .straightLeft2, .rayRight])
        playBasicMove(to: GridPoint(x: 0, y: 1), in: failCore)
        XCTAssertEqual(failCore.progress, .failed)
    }

    func testBasicOrthogonalMoveTriggersEnemyDamageAndBrittleFloor() {
        let brittlePoint = GridPoint(x: 0, y: 1)
        let watcher = EnemyDefinition(
            id: "watcher",
            name: "見張り",
            position: GridPoint(x: 1, y: 1),
            behavior: .watcher(direction: MoveVector(dx: -1, dy: 0), range: 2)
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            enemies: [watcher],
            hazards: [.brittleFloor(points: [brittlePoint])],
            allowsBasicOrthogonalMove: true
        )
        let core = makeCore(mode: mode, cards: [.straightRight2, .straightLeft2, .rayRight])

        playBasicMove(to: brittlePoint, in: core)

        XCTAssertTrue(core.crackedFloorPoints.contains(brittlePoint))
        XCTAssertEqual(core.dungeonHP, 2)
    }

    private func makeDungeonMode(
        spawn: GridPoint,
        exit: GridPoint,
        hp: Int = 3,
        turnLimit: Int?,
        enemies: [EnemyDefinition] = [],
        hazards: [HazardDefinition] = [],
        impassableTilePoints: Set<GridPoint> = [],
        exitLock: DungeonExitLock? = nil,
        allowsBasicOrthogonalMove: Bool = false,
        runState: DungeonRunState? = nil
    ) -> GameMode {
        GameMode(
            identifier: .dungeonFloor,
            displayName: "塔テスト",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standard,
                spawnRule: .fixed(spawn),
                penalties: GameMode.PenaltySettings(
                    deadlockPenaltyCost: 0,
                    manualRedrawPenaltyCost: 0,
                    manualDiscardPenaltyCost: 1,
                    revisitPenaltyCost: 0
                ),
                impassableTilePoints: impassableTilePoints,
                completionRule: .dungeonExit(exitPoint: exit),
                dungeonRules: DungeonRules(
                    difficulty: .growth,
                    failureRule: DungeonFailureRule(initialHP: hp, turnLimit: turnLimit),
                    enemies: enemies,
                    hazards: hazards,
                    exitLock: exitLock,
                    allowsBasicOrthogonalMove: allowsBasicOrthogonalMove
                )
            ),
            leaderboardEligible: false,
            dungeonMetadata: runState.map {
                GameMode.DungeonMetadata(
                    dungeonID: $0.dungeonID,
                    floorID: "test-floor-\($0.currentFloorIndex + 1)",
                    runState: $0
                )
            }
        )
    }

    private func blockedGrowthTowerPickupPoints(for floor: DungeonFloorDefinition) -> Set<GridPoint> {
        var blocked: Set<GridPoint> = [
            floor.spawnPoint,
            floor.exitPoint
        ]
        blocked.formUnion(floor.impassableTilePoints)
        blocked.formUnion(floor.enemies.map(\.position))
        blocked.formUnion(floor.warpTilePairs.values.flatMap { $0 })
        if let unlockPoint = floor.exitLock?.unlockPoint {
            blocked.insert(unlockPoint)
        }
        for hazard in floor.hazards {
            switch hazard {
            case .brittleFloor(let points):
                blocked.formUnion(points)
            case .damageTrap(let points, _):
                blocked.formUnion(points)
            }
        }
        return blocked
    }

    private func disallowedGrowthTowerImpassablePoints(for floor: DungeonFloorDefinition) -> Set<GridPoint> {
        var blocked: Set<GridPoint> = [
            floor.spawnPoint,
            floor.exitPoint
        ]
        blocked.formUnion(floor.cardPickups.map(\.point))
        blocked.formUnion(floor.enemies.map(\.position))
        for enemy in floor.enemies {
            if case .patrol(let path) = enemy.behavior {
                blocked.formUnion(path)
            }
        }
        blocked.formUnion(floor.tileEffectOverrides.keys)
        blocked.formUnion(floor.warpTilePairs.values.flatMap { $0 })
        blocked.formUnion(floor.fixedWarpCardTargets.values.flatMap { $0 })
        if let unlockPoint = floor.exitLock?.unlockPoint {
            blocked.insert(unlockPoint)
        }
        for hazard in floor.hazards {
            switch hazard {
            case .brittleFloor(let points):
                blocked.formUnion(points)
            case .damageTrap(let points, _):
                blocked.formUnion(points)
            }
        }
        return blocked
    }

    private func disallowedGrowthTowerPatrolPoints(
        for floor: DungeonFloorDefinition,
        excludingEnemyID enemyID: String
    ) -> Set<GridPoint> {
        var blocked: Set<GridPoint> = [
            floor.spawnPoint,
            floor.exitPoint
        ]
        blocked.formUnion(floor.cardPickups.map(\.point))
        blocked.formUnion(floor.impassableTilePoints)
        blocked.formUnion(floor.tileEffectOverrides.keys)
        blocked.formUnion(floor.warpTilePairs.values.flatMap { $0 })
        blocked.formUnion(floor.fixedWarpCardTargets.values.flatMap { $0 })
        blocked.formUnion(floor.enemies.compactMap { enemy in
            enemy.id == enemyID ? nil : enemy.position
        })
        if let unlockPoint = floor.exitLock?.unlockPoint {
            blocked.insert(unlockPoint)
        }
        for hazard in floor.hazards {
            switch hazard {
            case .brittleFloor(let points):
                blocked.formUnion(points)
            case .damageTrap(let points, _):
                blocked.formUnion(points)
            }
        }
        return blocked
    }

    private func manhattanDistance(from a: GridPoint, to b: GridPoint) -> Int {
        abs(a.x - b.x) + abs(a.y - b.y)
    }

    private func hasOrthogonalPath(
        from start: GridPoint,
        to goal: GridPoint,
        in floor: DungeonFloorDefinition
    ) -> Bool {
        guard start.isInside(boardSize: floor.boardSize), goal.isInside(boardSize: floor.boardSize) else {
            return false
        }
        var queue: [GridPoint] = [start]
        var visited: Set<GridPoint> = [start]
        let directions = [
            MoveVector(dx: 1, dy: 0),
            MoveVector(dx: -1, dy: 0),
            MoveVector(dx: 0, dy: 1),
            MoveVector(dx: 0, dy: -1)
        ]

        while !queue.isEmpty {
            let point = queue.removeFirst()
            if point == goal { return true }

            for direction in directions {
                let next = GridPoint(x: point.x + direction.dx, y: point.y + direction.dy)
                guard next.isInside(boardSize: floor.boardSize),
                      !floor.impassableTilePoints.contains(next),
                      !visited.contains(next)
                else {
                    continue
                }
                visited.insert(next)
                queue.append(next)
            }
        }

        return false
    }

    private func makeCore(
        mode: GameMode,
        cards: [MoveCard] = [.straightRight2, .straightUp2, .rayRight, .kingUp, .kingRight]
    ) -> GameCore {
        GameCore.makeTestInstance(
            deck: Deck.makeTestDeck(cards: cards, configuration: mode.deckConfiguration),
            current: mode.initialSpawnPoint,
            mode: mode
        )
    }

    private func playMove(to destination: GridPoint, in core: GameCore, file: StaticString = #filePath, line: UInt = #line) {
        guard let move = core.availableMoves().first(where: { $0.destination == destination }) else {
            XCTFail("移動候補が見つかりません: \(destination)", file: file, line: line)
            return
        }
        core.playCard(using: move)
    }

    private func playMoveOrBasicMove(to destination: GridPoint, in core: GameCore, file: StaticString = #filePath, line: UInt = #line) {
        if let move = core.availableMoves().first(where: { $0.destination == destination }) {
            core.playCard(using: move)
            return
        }
        playBasicMove(to: destination, in: core, file: file, line: line)
    }

    private func playBasicMove(to destination: GridPoint, in core: GameCore, file: StaticString = #filePath, line: UInt = #line) {
        guard let move = core.availableBasicOrthogonalMoves().first(where: { $0.destination == destination }) else {
            XCTFail("基本移動候補が見つかりません: \(destination)", file: file, line: line)
            return
        }
        core.playBasicOrthogonalMove(using: move)
    }
}
