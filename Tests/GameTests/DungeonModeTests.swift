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

        playMove(to: GridPoint(x: 4, y: 0), in: core)

        XCTAssertEqual(core.progress, .cleared)
        XCTAssertTrue(core.isDungeonExitUnlocked)
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
        XCTAssertEqual(growthTower.floors.map(\.boardSize), Array(repeating: 9, count: 9))
        XCTAssertEqual(rogueTower.floors.map(\.boardSize), [9, 9, 9])
    }

    func testGrowthTowerIntegratesNineProgressiveFloors() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))

        XCTAssertEqual(tower.title, "成長塔")
        XCTAssertEqual(tower.difficulty, .growth)
        XCTAssertEqual(tower.floors.count, 9)
        XCTAssertEqual(tower.floors.map(\.title), [
            "巡回の間",
            "鍵の小部屋",
            "見える罠",
            "転移の入口",
            "すれ違い",
            "固定ワープの間",
            "扉の見張り",
            "罠と見張り",
            "総合演習"
        ])
        for floorIndex in 0..<8 {
            XCTAssertFalse(
                tower.floors[floorIndex].rewardMoveCardsAfterClear.isEmpty,
                "\(tower.floors[floorIndex].title) は次階へ向けた報酬候補を出す必要があります"
            )
        }
        XCTAssertEqual(tower.floors[6].rewardMoveCardsAfterClear, [
            .diagonalUpRight2,
            .rayRight,
            .straightUp2
        ])
        XCTAssertEqual(tower.floors[7].rewardMoveCardsAfterClear, [
            .straightRight2,
            .fixedWarp,
            .straightUp2
        ])
        XCTAssertEqual(tower.floors[8].rewardMoveCardsAfterClear, [])
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
            ninthCore.availableMoves().contains { $0.moveCard == .straightRight2 && $0.destination == GridPoint(x: 2, y: 0) },
            "8F報酬の右2は9Fで鍵側へ寄る最初の短縮候補になる想定です"
        )
    }

    func testGrowthTowerDefinitionsStayInsideBoardAndExposeCombinedGimmicks() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        var hasPatrol = false
        var hasExitLock = false
        var hasDamageTrap = false
        var hasWarp = false
        var hasBrittleFloor = false

        for floor in tower.floors {
            var points: [GridPoint] = [floor.spawnPoint, floor.exitPoint]
            points.append(contentsOf: floor.cardPickups.map(\.point))
            points.append(contentsOf: floor.enemies.map(\.position))
            points.append(contentsOf: floor.impassableTilePoints)
            points.append(contentsOf: floor.tileEffectOverrides.keys)
            for enemy in floor.enemies {
                if case .patrol(let path) = enemy.behavior {
                    hasPatrol = true
                    points.append(contentsOf: path)
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
        XCTAssertTrue(hasExitLock)
        XCTAssertTrue(hasDamageTrap)
        XCTAssertTrue(hasWarp)
        XCTAssertTrue(hasBrittleFloor)
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
        playMove(to: GridPoint(x: 8, y: 6), in: core)
        playMove(to: GridPoint(x: 8, y: 8), in: core)

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

    func testDungeonRewardCardConsumptionReducesUsesAndRemovesEmptyHandStack() {
        let runState = DungeonRunState(
            dungeonID: "test-tower",
            currentFloorIndex: 1,
            carriedHP: 3,
            clearedFloorCount: 1,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .straightRight2, rewardUses: 3)]
        )
        let mode = GameMode(
            identifier: .campaignStage,
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

    func testDungeonInventoryStacksDuplicateCardsAndRejectsNewCardAtTenKinds() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let mode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower))
        let core = makeCore(mode: mode)
        let tenCards = Array(MoveCard.allCases.prefix(10))
        let eleventh = try XCTUnwrap(MoveCard.allCases.dropFirst(10).first)

        for card in tenCards {
            XCTAssertTrue(core.addDungeonInventoryCardForTesting(card, pickupUses: 1))
        }

        XCTAssertEqual(core.dungeonInventoryEntries.count, 10)
        XCTAssertFalse(core.addDungeonInventoryCardForTesting(eleventh, pickupUses: 1))
        XCTAssertEqual(core.dungeonInventoryEntries.count, 10)
        XCTAssertTrue(core.addDungeonInventoryCardForTesting(tenCards[0], pickupUses: 1))
        XCTAssertEqual(core.dungeonInventoryEntries.count, 10)
        XCTAssertEqual(core.dungeonInventoryEntries.first { $0.card == tenCards[0] }?.pickupUses, 2)
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

        let standardCore = makeCore(
            mode: .standard,
            cards: [.straightRight2, .straightLeft2, .diagonalUpRight2, .diagonalDownLeft2, .rayUp]
        )
        XCTAssertTrue(standardCore.availableBasicOrthogonalMoves().isEmpty)
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
        exitLock: DungeonExitLock? = nil,
        allowsBasicOrthogonalMove: Bool = false
    ) -> GameMode {
        GameMode(
            identifier: .campaignStage,
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
            leaderboardEligible: false
        )
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
