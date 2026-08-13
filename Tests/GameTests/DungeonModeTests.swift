import XCTest
@testable import Game
@testable import SharedSupport

final class DungeonModeTests: XCTestCase {
    override func tearDownWithError() throws {
        DebugLogHistory.shared.setFrontEndViewerEnabled(true)
        DebugLogHistory.shared.clear()
    }

    func testDungeonExitClearsWithoutTargetCollection() throws {
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 1, y: 0),
            turnLimit: 4
        )
        let core = makeCore(
            mode: mode,
            cards: [.straightRight2, .kingUpRight, .straightLeft2, .straightDown2, .straightRight2]
        )

        XCTAssertTrue(mode.usesDungeonExit)
        playMove(to: GridPoint(x: 1, y: 0), in: core)

        XCTAssertEqual(core.progress, .cleared)
    }

    func testDungeonPlayDiagnosticsCaptureBasicTrapAndEnemyEvents() throws {
        DebugLogHistory.shared.setFrontEndViewerEnabled(true)
        DebugLogHistory.shared.clear()
        let trapPoint = GridPoint(x: 0, y: 1)
        let patrol = EnemyDefinition(
            id: "diagnostic-patrol",
            name: "巡回兵",
            position: GridPoint(x: 3, y: 3),
            behavior: .patrol(path: [
                GridPoint(x: 3, y: 3),
                GridPoint(x: 4, y: 3)
            ])
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            turnLimit: 6,
            enemies: [patrol],
            hazards: [.damageTrap(points: [trapPoint], damage: 1)],
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            runState: DungeonRunState(dungeonID: "growth-tower", carriedHP: 3)
        )
        let core = makeCore(mode: mode)

        DebugLogHistory.shared.clear()
        playBasicMove(to: trapPoint, in: core)
        let messages = playDiagnosticMessages()

        XCTAssertTrue(messages.contains { $0.contains("event=move_start") && $0.contains("input=basic") })
        XCTAssertTrue(messages.contains { $0.contains("event=move_resolved") && $0.contains("input=basic") })
        XCTAssertTrue(messages.contains { $0.contains("event=damage_applied") && $0.contains("source=撒菱") })
        XCTAssertTrue(messages.contains { $0.contains("event=enemy_turn") && $0.contains("diagnostic-patrol") })
    }

    func testDungeonPlayDiagnosticsCaptureCardMoveAndRewardDrawEvents() throws {
        DebugLogHistory.shared.setFrontEndViewerEnabled(true)
        DebugLogHistory.shared.clear()
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            turnLimit: 6,
            allowsBasicOrthogonalMove: true,
            runState: DungeonRunState(dungeonID: "growth-tower", carriedHP: 3)
        )
        let core = makeCore(mode: mode, cards: [.straightRight2, .straightUp2, .rayRight])

        DebugLogHistory.shared.clear()
        let cardMove = try XCTUnwrap(core.availableMoves().first { $0.destination == GridPoint(x: 2, y: 0) })
        core.playCard(using: cardMove)
        _ = DungeonWeightedRewardPools.drawUniqueOffers(
            from: DungeonWeightedRewardPools.entries(floorIndex: 0, context: .clearReward),
            context: .clearReward,
            count: 2,
            seed: 123,
            floorIndex: 0,
            salt: 456
        )
        let messages = playDiagnosticMessages()

        XCTAssertTrue(messages.contains { $0.contains("event=move_start") && $0.contains("input=card") })
        XCTAssertTrue(messages.contains { $0.contains("event=move_resolved") && $0.contains("input=card") })
        XCTAssertTrue(messages.contains { $0.contains("event=reward_draw") && $0.contains("seed=123") })
    }

    func testGrowthTowerReportedFreezeSeedKeepsLegalActionsOnThirdFloor() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let seed: UInt64 = 4_514_531_392_004_290_882
        let inventoryEntries: [DungeonInventoryEntry] = [
            DungeonInventoryEntry(card: .knightUpwardChoice, rewardUses: 1),
            DungeonInventoryEntry(card: .rayUp, rewardUses: 2),
            DungeonInventoryEntry(card: .diagonalDownRight2, rewardUses: 1),
            DungeonInventoryEntry(support: .refillEmptySlots, rewardUses: 1),
            DungeonInventoryEntry(support: .barrierSpell, rewardUses: 1)
        ]
        let runState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 2,
            carriedHP: 3,
            totalMoveCount: 29,
            totalElapsedSeconds: 25,
            clearedFloorCount: 2,
            rewardInventoryEntries: inventoryEntries,
            cardVariationSeed: seed,
            movementStyle: .orthogonal,
            dungeonInventoryKindLimit: 5,
            rogueHandExpansionChanceStep: 2
        )
        let mode = try XCTUnwrap(
            tower.resolvedFloor(at: 2, runState: runState)?.makeGameMode(
                dungeonID: tower.id,
                difficulty: tower.difficulty,
                carriedHP: 3,
                runState: runState
            )
        )
        let core = GameCore(mode: mode)
        let snapshot = DungeonRunResumeSnapshot(
            dungeonID: tower.id,
            floorIndex: 2,
            runState: runState,
            currentPoint: GridPoint(x: 2, y: 1),
            visitedPoints: [
                GridPoint(x: 1, y: 1),
                GridPoint(x: 0, y: 4),
                GridPoint(x: 2, y: 1),
                GridPoint(x: 0, y: 3),
                GridPoint(x: 0, y: 1),
                GridPoint(x: 0, y: 2)
            ],
            moveCount: 5,
            elapsedSeconds: 14,
            dungeonHP: 3,
            hazardDamageMitigationsRemaining: 0,
            enemyStates: [],
            crackedFloorPoints: [],
            collapsedFloorPoints: [],
            dungeonInventoryEntries: inventoryEntries,
            collectedDungeonCardPickupIDs: ["growth-3-diagonal-up-left"],
            isDungeonExitUnlocked: true
        )

        XCTAssertTrue(core.restoreDungeonResumeSnapshot(snapshot))
        XCTAssertEqual(core.progress, .playing)
        XCTAssertEqual(core.current, GridPoint(x: 2, y: 1))
        XCTAssertFalse(core.availableMoves().isEmpty)
        XCTAssertFalse(core.availableBasicOrthogonalMoves().isEmpty)
    }

    func testDeveloperRelicEffectToggleDisablesRelicAndCurseTurnLimitEffects() throws {
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            turnLimit: 8,
            runState: DungeonRunState(
                dungeonID: "growth-tower",
                carriedHP: 3,
                relicEntries: [DungeonRelicEntry(relicID: .copperHourglass)],
                curseEntries: [DungeonCurseEntry(curseID: .crackedCompass)]
            )
        )
        let core = makeCore(mode: mode)

        XCTAssertEqual(core.effectiveDungeonTurnLimit, 7)

        core.updateDungeonRelicAndCurseEffects(enabled: false)

        XCTAssertEqual(core.effectiveDungeonTurnLimit, 8)
        XCTAssertEqual(core.dungeonRelicEntries.map(\.relicID), [.copperHourglass])
        XCTAssertEqual(core.dungeonCurseEntries.map(\.curseID), [.crackedCompass])
    }

    func testDeveloperRelicEffectToggleDoesNotConsumeLimitedRelicOrCurseUses() throws {
        let trapPoint = GridPoint(x: 1, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 5,
            turnLimit: 8,
            hazards: [.damageTrap(points: [trapPoint], damage: 2)],
            allowsBasicOrthogonalMove: true,
            runState: DungeonRunState(
                dungeonID: "growth-tower",
                carriedHP: 5,
                relicEntries: [DungeonRelicEntry(relicID: .silverNeedle)],
                curseEntries: [DungeonCurseEntry(curseID: .thornMark)]
            )
        )
        let core = makeCore(mode: mode)
        core.updateDungeonRelicAndCurseEffects(enabled: false)

        playBasicMove(to: trapPoint, in: core)

        XCTAssertEqual(core.dungeonHP, 4)
        XCTAssertEqual(core.dungeonRelicEntries.first { $0.relicID == .silverNeedle }?.remainingUses, 1)
        XCTAssertEqual(core.dungeonCurseEntries.first { $0.curseID == .thornMark }?.remainingUses, 1)
        XCTAssertNil(core.dungeonRelicActivationEvent)
    }

    func testDeveloperRelicEffectToggleKeepsPickupOwnershipWithoutImmediateEffects() throws {
        let pickupPoint = GridPoint(x: 1, y: 0)
        let pickup = DungeonRelicPickupDefinition(
            id: "developer-toggle-relic",
            point: pickupPoint,
            kind: .safe,
            candidateRelics: [.glowingHeart]
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            allowsBasicOrthogonalMove: true,
            relicPickups: [pickup],
            runState: DungeonRunState(dungeonID: "growth-tower", carriedHP: 3)
        )
        let core = makeCore(mode: mode)
        core.updateDungeonRelicAndCurseEffects(enabled: false)

        playBasicMove(to: pickupPoint, in: core)

        XCTAssertEqual(core.dungeonHP, 3)
        XCTAssertEqual(core.dungeonRelicEntries.map(\.relicID), [.glowingHeart])
        XCTAssertEqual(core.collectedDungeonRelicPickupIDs, ["developer-toggle-relic"])
    }

    func testDeveloperRelicEffectToggleKeepsCarryoverOwnershipButDisablesNextFloorEffects() throws {
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 2,
            relicEntries: [
                DungeonRelicEntry(relicID: .starCup),
                DungeonRelicEntry(relicID: .heavyCrown)
            ],
            curseEntries: [
                DungeonCurseEntry(curseID: .obsidianHeart),
                DungeonCurseEntry(curseID: .bloodPact)
            ]
        )

        let nextState = runState.advancedToNextFloor(
            carryoverHP: 2,
            currentFloorMoveCount: 1,
            rewardSelection: .add(.straightRight2),
            rewardAddUses: 2,
            areDungeonRelicAndCurseEffectsEnabled: false
        )

        XCTAssertEqual(nextState.carriedHP, 2)
        XCTAssertEqual(nextState.relicEntries.map(\.relicID), [.starCup, .heavyCrown])
        XCTAssertEqual(nextState.curseEntries.map(\.curseID), [.obsidianHeart, .bloodPact])
        XCTAssertEqual(nextState.curseEntries.first { $0.curseID == .bloodPact }?.remainingUses, 1)
        XCTAssertEqual(nextState.rewardInventoryEntries.first?.rewardUses, 2)
    }

    func testDungeonTurnLimitStartsFatigueAfterNonExitMove() throws {
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            turnLimit: 1
        )
        let core = makeCore(
            mode: mode,
            cards: [.straightRight2, .kingUpRight, .straightLeft2, .straightDown2, .straightRight2]
        )

        playMove(to: GridPoint(x: 1, y: 0), in: core)

        XCTAssertEqual(core.progress, .playing)
        XCTAssertEqual(core.remainingDungeonTurns, 0)

        playMove(to: GridPoint(x: 2, y: 0), in: core)

        XCTAssertEqual(core.progress, .playing)
        XCTAssertEqual(core.dungeonHP, 2)
    }

    func testDungeonRelicPickupGrantsRunRelicAndDoesNotUseCardSlot() throws {
        let pickup = DungeonRelicPickupDefinition(
            id: "test-relic",
            point: GridPoint(x: 0, y: 1),
            candidateRelics: [.glowingHeart]
        )
        let runState = DungeonRunState(dungeonID: "growth-tower", carriedHP: 2)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 2,
            turnLimit: 6,
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            relicPickups: [pickup],
            runState: runState
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: pickup.point, in: core)

        XCTAssertEqual(core.dungeonRelicEntries.map(\.relicID), [.glowingHeart])
        XCTAssertEqual(core.dungeonHP, 4)
        XCTAssertTrue(core.collectedDungeonRelicPickupIDs.contains(pickup.id))
        XCTAssertTrue(core.dungeonInventoryEntries.isEmpty)
        XCTAssertTrue(core.activeDungeonRelicPickups.isEmpty)
        XCTAssertEqual(core.dungeonRelicAcquisitionPresentations.count, 1)
        XCTAssertEqual(core.dungeonRelicAcquisitionPresentations.first?.outcome, .relic)
        XCTAssertEqual(core.dungeonRelicAcquisitionPresentations.first?.items, [.relic(DungeonRelicEntry(relicID: .glowingHeart))])
        XCTAssertTrue(core.dungeonRunLogEntries.contains { $0.kind == .acquisition && $0.message.contains("レリック「\(DungeonRelicID.glowingHeart.displayName)」") })
        XCTAssertTrue(core.dungeonRunLogEntries.contains { $0.kind == .healing && $0.message.contains("\(DungeonRelicID.glowingHeart.displayName)でHP +2") })
    }

    func testRoguelikeTowerRelicPickupGrantsRunRelic() throws {
        let pickup = DungeonRelicPickupDefinition(
            id: "rogue-test-relic",
            point: GridPoint(x: 0, y: 1),
            candidateRelics: [.glowingHeart]
        )
        let runState = DungeonRunState(dungeonID: "rogue-tower", carriedHP: 2)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 2,
            turnLimit: 6,
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            relicPickups: [pickup],
            difficulty: .roguelike,
            runState: runState
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: pickup.point, in: core)

        XCTAssertEqual(core.dungeonRelicEntries.map(\.relicID), [.glowingHeart])
        XCTAssertEqual(core.dungeonHP, 4)
        XCTAssertTrue(core.collectedDungeonRelicPickupIDs.contains(pickup.id))
        XCTAssertTrue(core.activeDungeonRelicPickups.isEmpty)
        XCTAssertEqual(core.dungeonRelicAcquisitionPresentations.count, 1)
        XCTAssertEqual(core.dungeonRelicAcquisitionPresentations.first?.outcome, .relic)
        XCTAssertTrue(core.dungeonRunLogEntries.contains { $0.kind == .acquisition && $0.message.contains("レリック「\(DungeonRelicID.glowingHeart.displayName)」") })
    }

    func testSafeRelicPickupDoesNotDuplicateAndCompensatesWhenCandidatesAreExhausted() throws {
        let pickup = DungeonRelicPickupDefinition(
            id: "test-empty-safe",
            point: GridPoint(x: 0, y: 1),
            candidateRelics: [.glowingHeart]
        )
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 3,
            relicEntries: [DungeonRelicEntry(relicID: .glowingHeart)]
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 6,
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            relicPickups: [pickup],
            runState: runState
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: pickup.point, in: core)

        XCTAssertEqual(core.dungeonRelicEntries.map(\.relicID), [.glowingHeart])
        XCTAssertEqual(core.dungeonHP, 4)
        XCTAssertTrue(core.collectedDungeonRelicPickupIDs.contains(pickup.id))
        XCTAssertEqual(core.dungeonRelicAcquisitionPresentations.first?.items, [.hpCompensation(1)])
    }

    func testDungeonRelicEffectsAdjustDamageRewardsAndTurns() throws {
        let trapPoint = GridPoint(x: 0, y: 1)
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 3,
            relicEntries: [
                DungeonRelicEntry(relicID: .crackedShield),
                DungeonRelicEntry(relicID: .heavyCrown),
                DungeonRelicEntry(relicID: .chippedHourglass)
            ]
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 6,
            hazards: [.damageTrap(points: [trapPoint], damage: 2)],
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            runState: runState
        )
        let core = makeCore(mode: mode)

        XCTAssertEqual(core.effectiveDungeonTurnLimit, 9)
        playBasicMove(to: trapPoint, in: core)

        XCTAssertEqual(core.dungeonHP, 3)
        XCTAssertEqual(core.dungeonRelicEntries.first { $0.relicID == .crackedShield }?.remainingUses, 0)
        XCTAssertEqual(core.remainingDungeonTurns, 8)

        let advanced = runState.advancedToNextFloor(
            carryoverHP: core.dungeonHP,
            currentFloorMoveCount: core.moveCount,
            rewardSelection: .add(.straightRight2),
            currentInventoryEntries: core.dungeonInventoryEntries,
            currentRelicEntries: core.dungeonRelicEntries,
            rewardAddUses: 3
        )
        XCTAssertEqual(advanced.rewardInventoryEntries.first?.rewardUses, 3)
        XCTAssertTrue(advanced.relicEntries.contains { $0.relicID == .heavyCrown })
    }

    func testLegendaryRelicsAddStrongerRunShapingEffects() throws {
        let trapPoint = GridPoint(x: 0, y: 1)
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 3,
            relicEntries: [
                DungeonRelicEntry(relicID: .guardianAegis),
                DungeonRelicEntry(relicID: .immortalHeart),
                DungeonRelicEntry(relicID: .stargazerHourglass)
            ]
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 6,
            hazards: [.damageTrap(points: [trapPoint], damage: 2)],
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            runState: runState
        )
        let core = makeCore(mode: mode)

        XCTAssertEqual(core.effectiveDungeonTurnLimit, 11)
        playBasicMove(to: trapPoint, in: core)

        XCTAssertEqual(core.dungeonHP, 3)
        XCTAssertEqual(core.dungeonRelicEntries.first { $0.relicID == .guardianAegis }?.remainingUses, 0)

        let advanced = runState.advancedToNextFloor(
            carryoverHP: core.dungeonHP,
            currentFloorMoveCount: core.moveCount,
            currentInventoryEntries: core.dungeonInventoryEntries,
            currentRelicEntries: core.dungeonRelicEntries
        )
        XCTAssertEqual(advanced.carriedHP, 4)
        XCTAssertEqual(advanced.relicEntries.first { $0.relicID == .guardianAegis }?.remainingUses, 1)
    }

    func testFloorStartBarrierCharmBlocksOneActionPostDamageOnly() throws {
        let trapPoint = GridPoint(x: 1, y: 0)
        let lavaPoint = GridPoint(x: 2, y: 0)
        let patrol = EnemyDefinition(
            id: "patrol",
            name: "巡回兵",
            position: GridPoint(x: 4, y: 1),
            behavior: .patrol(path: [
                GridPoint(x: 4, y: 1),
                GridPoint(x: 4, y: 2)
            ])
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            enemies: [patrol],
            hazards: [
                .damageTrap(points: [trapPoint], damage: 1),
                .lavaTile(points: [lavaPoint], damage: 1)
            ],
            runState: DungeonRunState(
                dungeonID: "growth-tower",
                carriedHP: 3,
                relicEntries: [DungeonRelicEntry(relicID: .barrierCharm)]
            )
        )
        let core = makeCore(mode: mode)

        XCTAssertEqual(core.dungeonRelicActivationEvent?.relicID, .barrierCharm)
        XCTAssertEqual(core.damageBarrierTurnsRemaining, 1)

        playBasicMove(to: trapPoint, in: core)

        XCTAssertEqual(core.dungeonHP, 3)
        XCTAssertEqual(core.damageBarrierTurnsRemaining, 0)
        XCTAssertEqual(core.enemyStates.first?.position, GridPoint(x: 4, y: 2))

        playBasicMove(to: lavaPoint, in: core)

        XCTAssertEqual(core.dungeonHP, 1)
    }

    func testFloorStartBarrierTalismanUsesMaximumBarrierTurns() throws {
        let firstTrapPoint = GridPoint(x: 1, y: 0)
        let secondTrapPoint = GridPoint(x: 2, y: 0)
        let thirdTrapPoint = GridPoint(x: 3, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 4,
            turnLimit: 8,
            hazards: [.damageTrap(points: [firstTrapPoint, secondTrapPoint, thirdTrapPoint], damage: 1)],
            runState: DungeonRunState(
                dungeonID: "growth-tower",
                carriedHP: 4,
                relicEntries: [
                    DungeonRelicEntry(relicID: .barrierCharm),
                    DungeonRelicEntry(relicID: .barrierTalisman)
                ]
            )
        )
        let core = makeCore(mode: mode)

        XCTAssertEqual(core.damageBarrierTurnsRemaining, 2)

        playBasicMove(to: firstTrapPoint, in: core)
        XCTAssertEqual(core.dungeonHP, 4)
        XCTAssertEqual(core.damageBarrierTurnsRemaining, 1)

        playBasicMove(to: secondTrapPoint, in: core)
        XCTAssertEqual(core.dungeonHP, 4)
        XCTAssertEqual(core.damageBarrierTurnsRemaining, 0)

        playBasicMove(to: thirdTrapPoint, in: core)
        XCTAssertEqual(core.dungeonHP, 3)
    }

    func testFloorStartFrostBellSkipsOnlyFirstEnemyTurn() throws {
        let patrol = EnemyDefinition(
            id: "patrol",
            name: "巡回兵",
            position: GridPoint(x: 4, y: 1),
            behavior: .patrol(path: [
                GridPoint(x: 4, y: 1),
                GridPoint(x: 4, y: 2)
            ])
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            enemies: [patrol],
            runState: DungeonRunState(
                dungeonID: "growth-tower",
                carriedHP: 3,
                relicEntries: [DungeonRelicEntry(relicID: .frostBell)]
            )
        )
        let core = makeCore(mode: mode)

        XCTAssertEqual(core.enemyFreezeTurnsRemaining, 1)
        XCTAssertTrue(core.enemyDangerPoints.isEmpty)

        playBasicMove(to: GridPoint(x: 1, y: 0), in: core)

        XCTAssertEqual(core.enemyFreezeTurnsRemaining, 0)
        XCTAssertEqual(core.enemyStates.first?.position, GridPoint(x: 4, y: 1))
        XCTAssertFalse(core.enemyDangerPoints.isEmpty)

        playBasicMove(to: GridPoint(x: 2, y: 0), in: core)

        XCTAssertEqual(core.enemyStates.first?.position, GridPoint(x: 4, y: 2))
    }

    func testDeveloperRelicEffectToggleDisablesFloorStartBarrierAndFreeze() throws {
        let trapPoint = GridPoint(x: 1, y: 0)
        let patrol = EnemyDefinition(
            id: "patrol",
            name: "巡回兵",
            position: GridPoint(x: 4, y: 1),
            behavior: .patrol(path: [
                GridPoint(x: 4, y: 1),
                GridPoint(x: 4, y: 2)
            ])
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            enemies: [patrol],
            hazards: [.damageTrap(points: [trapPoint], damage: 1)],
            runState: DungeonRunState(
                dungeonID: "growth-tower",
                carriedHP: 3,
                relicEntries: [
                    DungeonRelicEntry(relicID: .barrierCharm),
                    DungeonRelicEntry(relicID: .barrierTalisman),
                    DungeonRelicEntry(relicID: .frostBell)
                ]
            )
        )
        let core = makeCore(mode: mode)

        XCTAssertEqual(core.damageBarrierTurnsRemaining, 2)
        XCTAssertEqual(core.enemyFreezeTurnsRemaining, 1)

        core.updateDungeonRelicAndCurseEffects(enabled: false)

        XCTAssertEqual(core.damageBarrierTurnsRemaining, 0)
        XCTAssertEqual(core.enemyFreezeTurnsRemaining, 0)

        playBasicMove(to: trapPoint, in: core)

        XCTAssertEqual(core.dungeonHP, 2)
        XCTAssertEqual(core.enemyStates.first?.position, GridPoint(x: 4, y: 2))
        XCTAssertEqual(core.dungeonRelicEntries.map(\.relicID), [.barrierCharm, .barrierTalisman, .frostBell])
    }

    func testSuspiciousLightRelicPickupWaitsForChoiceAndCanGrantCurse() throws {
        let pickup = DungeonRelicPickupDefinition(
            id: "test-light-choice",
            point: GridPoint(x: 0, y: 1),
            kind: .suspiciousLight,
            candidateRelics: [.glowingHeart],
            candidateCurses: [.rustyChain]
        )
        let runState = DungeonRunState(dungeonID: "growth-tower", carriedHP: 3)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            relicPickups: [pickup],
            runState: runState
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: pickup.point, in: core)

        let choice = try XCTUnwrap(core.pendingDungeonRelicPickupChoice)
        XCTAssertFalse(core.collectedDungeonRelicPickupIDs.contains(pickup.id))
        XCTAssertEqual(choice.options.map(\.kind), [.stableRelic, .curseRelic])
        XCTAssertEqual(choice.options.map(\.title), ["通常遺物", "呪い遺物"])
        let curseOption = try XCTUnwrap(choice.options.first { $0.kind == .curseRelic })
        XCTAssertTrue(core.selectPendingDungeonRelicPickupOption(id: curseOption.id))

        XCTAssertEqual(core.dungeonCurseEntries.map(\.curseID), [.rustyChain])
        XCTAssertEqual(core.dungeonHP, 4)
        XCTAssertEqual(core.effectiveDungeonTurnLimit, 6)
        XCTAssertTrue(core.collectedDungeonRelicPickupIDs.contains(pickup.id))
        XCTAssertEqual(core.dungeonRelicAcquisitionPresentations.first?.outcome, .curse)
        XCTAssertEqual(core.dungeonRelicAcquisitionPresentations.first?.items, [.curse(DungeonCurseEntry(curseID: .rustyChain))])
        XCTAssertTrue(core.dungeonRunLogEntries.contains { $0.kind == .acquisition && $0.message.contains("呪い「\(DungeonCurseID.rustyChain.displayName)」") })
    }

    func testSuspiciousDeepRelicPickupOffersCurseWithoutHpPenalty() throws {
        let pickup = DungeonRelicPickupDefinition(
            id: "test-deep-choice",
            point: GridPoint(x: 0, y: 1),
            kind: .suspiciousDeep,
            candidateRelics: [.blackFeather, .travelerBoots],
            candidateCurses: [.bloodPact]
        )
        let runState = DungeonRunState(dungeonID: "growth-tower", carriedHP: 3)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            relicPickups: [pickup],
            runState: runState
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: pickup.point, in: core)

        let choice = try XCTUnwrap(core.pendingDungeonRelicPickupChoice)
        XCTAssertEqual(choice.options.map(\.kind), [.stableRelic, .curseRelic])
        XCTAssertEqual(choice.options.map(\.title), ["通常遺物", "呪い遺物"])
        let curseOption = try XCTUnwrap(choice.options.first { $0.kind == .curseRelic })
        XCTAssertEqual(curseOption.hpPenalty, 0)
        XCTAssertTrue(core.selectPendingDungeonRelicPickupOption(id: curseOption.id))

        XCTAssertEqual(core.dungeonHP, 5)
        XCTAssertEqual(core.progress, .playing)
        XCTAssertTrue(core.collectedDungeonRelicPickupIDs.contains(pickup.id))
        XCTAssertTrue(core.dungeonRelicEntries.isEmpty)
        XCTAssertEqual(core.dungeonCurseEntries.map(\.curseID), [.bloodPact])
        XCTAssertEqual(core.dungeonRelicAcquisitionPresentations.first?.outcome, .curse)
        XCTAssertEqual(core.dungeonRelicAcquisitionPresentations.first?.items, [.curse(DungeonCurseEntry(curseID: .bloodPact))])
    }

    func testSuspiciousDeepRelicPickupFallsBackToCompensationWhenChoiceCannotBeBuilt() throws {
        let pickup = DungeonRelicPickupDefinition(
            id: "test-deep-empty",
            point: GridPoint(x: 0, y: 1),
            kind: .suspiciousDeep,
            candidateRelics: [.glowingHeart]
        )
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 2,
            relicEntries: [DungeonRelicEntry(relicID: .glowingHeart)]
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 2,
            turnLimit: 8,
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            relicPickups: [pickup],
            runState: runState
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: pickup.point, in: core)

        XCTAssertNil(core.pendingDungeonRelicPickupChoice)
        XCTAssertEqual(core.dungeonHP, 3)
        XCTAssertEqual(core.progress, .playing)
        XCTAssertTrue(core.collectedDungeonRelicPickupIDs.contains(pickup.id))
        XCTAssertEqual(core.dungeonRelicAcquisitionPresentations.first?.items, [.hpCompensation(1)])
    }

    func testSuspiciousLightStableChoiceGrantsShownRelic() throws {
        let pickup = DungeonRelicPickupDefinition(
            id: "test-light-stable",
            point: GridPoint(x: 0, y: 1),
            kind: .suspiciousLight,
            candidateRelics: [.blackFeather],
            candidateCurses: [.bloodPact]
        )
        let runState = DungeonRunState(dungeonID: "growth-tower", carriedHP: 3)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            relicPickups: [pickup],
            runState: runState
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: pickup.point, in: core)

        let choice = try XCTUnwrap(core.pendingDungeonRelicPickupChoice)
        let stableOption = try XCTUnwrap(choice.options.first { $0.kind == .stableRelic })
        XCTAssertEqual(stableOption.relicID, .blackFeather)
        XCTAssertTrue(core.selectPendingDungeonRelicPickupOption(id: stableOption.id))

        XCTAssertEqual(core.dungeonRelicEntries.map(\.relicID), [.blackFeather])
        XCTAssertTrue(core.dungeonCurseEntries.isEmpty)
        XCTAssertEqual(core.dungeonRelicAcquisitionPresentations.first?.items, [.relic(DungeonRelicEntry(relicID: .blackFeather))])
    }

    func testSuspiciousChoiceExcludesOwnedRelicsAndCurses() throws {
        let deepPickup = DungeonRelicPickupDefinition(
            id: "test-deep-owned",
            point: GridPoint(x: 0, y: 1),
            kind: .suspiciousDeep,
            candidateRelics: [.blackFeather, .travelerBoots, .glowingHeart],
            candidateCurses: [.bloodPact]
        )
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 3,
            relicEntries: [DungeonRelicEntry(relicID: .blackFeather)]
        )
        let pandoraMode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            relicPickups: [deepPickup],
            runState: runState
        )
        let deepCore = makeCore(mode: pandoraMode)

        playBasicMove(to: deepPickup.point, in: deepCore)

        let deepChoice = try XCTUnwrap(deepCore.pendingDungeonRelicPickupChoice)
        XCTAssertFalse(deepChoice.options.contains { $0.relicID == .blackFeather })

        let curseFilteredPickup = DungeonRelicPickupDefinition(
            id: "test-light-owned-curse",
            point: GridPoint(x: 0, y: 1),
            kind: .suspiciousLight,
            candidateRelics: [.travelerBoots],
            candidateCurses: [.rustyChain]
        )
        let curseFilteredRunState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 3,
            curseEntries: [DungeonCurseEntry(curseID: .rustyChain)]
        )
        let curseFilteredMode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            relicPickups: [curseFilteredPickup],
            runState: curseFilteredRunState
        )
        let curseFilteredCore = makeCore(mode: curseFilteredMode)

        playBasicMove(to: curseFilteredPickup.point, in: curseFilteredCore)

        XCTAssertNil(curseFilteredCore.pendingDungeonRelicPickupChoice)
        XCTAssertEqual(curseFilteredCore.dungeonCurseEntries.filter { $0.curseID == .rustyChain }.count, 1)
        XCTAssertEqual(curseFilteredCore.dungeonRelicAcquisitionPresentations.first?.items, [.hpCompensation(1)])
    }

    func testDungeonCurseEffectsAdjustDamageAndRewardUses() throws {
        let trapPoint = GridPoint(x: 0, y: 1)
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 4,
            curseEntries: [
                DungeonCurseEntry(curseID: .thornMark),
                DungeonCurseEntry(curseID: .bloodPact)
            ]
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 4,
            turnLimit: 8,
            hazards: [.damageTrap(points: [trapPoint], damage: 1)],
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            runState: runState
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: trapPoint, in: core)

        XCTAssertEqual(core.dungeonHP, 2)
        XCTAssertEqual(core.dungeonCurseEntries.first { $0.curseID == .thornMark }?.remainingUses, 0)

        let advanced = runState.advancedToNextFloor(
            carryoverHP: core.dungeonHP,
            currentFloorMoveCount: core.moveCount,
            rewardSelection: .add(.straightRight2),
            currentInventoryEntries: core.dungeonInventoryEntries,
            currentRelicEntries: core.dungeonRelicEntries,
            currentCurseEntries: core.dungeonCurseEntries,
            rewardAddUses: 1
        )
        XCTAssertEqual(advanced.rewardInventoryEntries.first?.rewardUses, 1)
        XCTAssertEqual(advanced.curseEntries.first { $0.curseID == .bloodPact }?.remainingUses, 0)
    }

    func testDungeonCursePickupAddsSmallUpside() throws {
        let pickup = DungeonRelicPickupDefinition(
            id: "test-deep-0",
            point: GridPoint(x: 0, y: 1),
            kind: .suspiciousLight,
            candidateRelics: [.glowingHeart],
            candidateCurses: [.bloodPact]
        )
        let runState = DungeonRunState(dungeonID: "growth-tower", carriedHP: 2)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 2,
            turnLimit: 8,
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            relicPickups: [pickup],
            runState: runState
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: pickup.point, in: core)
        let choice = try XCTUnwrap(core.pendingDungeonRelicPickupChoice)
        let curseOption = try XCTUnwrap(choice.options.first { $0.kind == .curseRelic })
        XCTAssertTrue(core.selectPendingDungeonRelicPickupOption(id: curseOption.id))

        XCTAssertEqual(core.dungeonCurseEntries.map(\.curseID), [.bloodPact])
        XCTAssertEqual(core.dungeonHP, 4)
    }

    func testPeakyDungeonCurseEffectsAdjustTurnsAndCarryoverHP() throws {
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 5,
            curseEntries: [
                DungeonCurseEntry(curseID: .cursedCrown),
                DungeonCurseEntry(curseID: .obsidianHeart),
                DungeonCurseEntry(curseID: .warpedHourglass)
            ]
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 5,
            turnLimit: 10,
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            runState: runState
        )
        let core = makeCore(mode: mode)

        XCTAssertEqual(core.effectiveDungeonTurnLimit, 5)

        let advanced = runState.advancedToNextFloor(
            carryoverHP: 5,
            currentFloorMoveCount: 0,
            currentInventoryEntries: core.dungeonInventoryEntries,
            currentCurseEntries: core.dungeonCurseEntries,
            completedWithinHalfTurnLimit: true
        )

        XCTAssertEqual(advanced.carriedHP, 4)
        XCTAssertEqual(advanced.curseEntries.map(\.curseID), [.cursedCrown, .obsidianHeart, .warpedHourglass])
    }

    func testAddedRelicsAdjustTurnsPickupsFloorStartAndCurseConversion() throws {
        let pickup = DungeonRelicPickupDefinition(
            id: "test-deep-0",
            point: GridPoint(x: 0, y: 1),
            kind: .suspiciousLight,
            candidateRelics: [.victoryBanner],
            candidateCurses: [.bloodPact]
        )
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 3,
            relicEntries: [
                DungeonRelicEntry(relicID: .travelerBoots),
                DungeonRelicEntry(relicID: .explorerBag),
                DungeonRelicEntry(relicID: .moonMirror),
                DungeonRelicEntry(relicID: .starCup, floorStartCharge: 1)
            ]
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 6,
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            cardPickups: [
                DungeonCardPickupDefinition(
                    id: "pickup",
                    point: GridPoint(x: 1, y: 1),
                    card: .straightRight2,
                    uses: 1
                )
            ],
            relicPickups: [pickup],
            runState: runState
        )
        let core = makeCore(mode: mode)

        XCTAssertEqual(core.effectiveDungeonTurnLimit, 7)
        playBasicMove(to: pickup.point, in: core)
        let choice = try XCTUnwrap(core.pendingDungeonRelicPickupChoice)
        let curseOption = try XCTUnwrap(choice.options.first { $0.kind == .curseRelic })
        XCTAssertTrue(core.selectPendingDungeonRelicPickupOption(id: curseOption.id))
        XCTAssertFalse(core.dungeonCurseEntries.contains { $0.curseID == .bloodPact })
        XCTAssertTrue(core.dungeonRelicEntries.contains { $0.relicID == .victoryBanner })
        XCTAssertEqual(core.dungeonRelicEntries.first { $0.relicID == .moonMirror }?.remainingUses, 0)
        playBasicMove(to: GridPoint(x: 1, y: 1), in: core)
        XCTAssertEqual(core.dungeonInventoryEntries.first?.rewardUses, 2)

        let advanced = runState.advancedToNextFloor(
            carryoverHP: core.dungeonHP,
            currentFloorMoveCount: core.moveCount,
            currentInventoryEntries: core.dungeonInventoryEntries,
            currentRelicEntries: core.dungeonRelicEntries
        )
        XCTAssertEqual(advanced.carriedHP, core.dungeonHP + 1)
    }

    func testSilverNeedlePreventsTrapDamageOnce() throws {
        let trapPoint = GridPoint(x: 0, y: 1)
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 3,
            relicEntries: [DungeonRelicEntry(relicID: .silverNeedle)]
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            hazards: [.damageTrap(points: [trapPoint], damage: 2)],
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            runState: runState
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: trapPoint, in: core)
        XCTAssertEqual(core.dungeonRelicActivationEvent?.relicID, .silverNeedle)
        playBasicMove(to: GridPoint(x: 0, y: 0), in: core)
        playBasicMove(to: trapPoint, in: core)

        XCTAssertEqual(core.dungeonHP, 3)
        XCTAssertEqual(core.dungeonRelicEntries.first { $0.relicID == DungeonRelicID.silverNeedle }?.remainingUses, 0)
    }

    func testPersistentDamageReductionRelicPublishesActivationEvent() throws {
        let trapPoint = GridPoint(x: 0, y: 1)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            hazards: [.damageTrap(points: [trapPoint], damage: 2)],
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            runState: DungeonRunState(
                dungeonID: "growth-tower",
                carriedHP: 3,
                relicEntries: [DungeonRelicEntry(relicID: .trapSole)]
            )
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: trapPoint, in: core)

        XCTAssertEqual(core.dungeonHP, 3)
        XCTAssertEqual(core.dungeonRelicActivationEvent?.relicID, .trapSole)
    }

    func testAddedCursesAdjustDamagePickupsRewardsAndTurns() throws {
        let trapPoint = GridPoint(x: 1, y: 1)
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 9,
            curseEntries: [
                DungeonCurseEntry(curseID: .redChalice),
                DungeonCurseEntry(curseID: .greedyBag),
                DungeonCurseEntry(curseID: .crackedCompass)
            ]
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 9,
            turnLimit: 8,
            hazards: [.damageTrap(points: [trapPoint], damage: 1)],
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            cardPickups: [
                DungeonCardPickupDefinition(
                    id: "pickup",
                    point: GridPoint(x: 1, y: 0),
                    card: .straightRight2,
                    uses: 1
                )
            ],
            runState: runState
        )
        let core = makeCore(mode: mode)

        XCTAssertEqual(core.effectiveDungeonTurnLimit, 5)
        playBasicMove(to: GridPoint(x: 1, y: 0), in: core)
        XCTAssertEqual(core.dungeonInventoryEntries.first?.rewardUses, 5)

        playBasicMove(to: trapPoint, in: core)
        XCTAssertEqual(core.dungeonHP, 7)

        let advanced = runState.advancedToNextFloor(
            carryoverHP: core.dungeonHP,
            currentFloorMoveCount: core.moveCount,
            rewardSelection: .add(.straightUp2),
            currentInventoryEntries: core.dungeonInventoryEntries,
            currentCurseEntries: core.dungeonCurseEntries,
            rewardAddUses: 1
        )
        XCTAssertEqual(advanced.rewardInventoryEntries.first { $0.moveCard == .straightUp2 }?.rewardUses, 1)
    }

    func testBlackFeatherPreventsFirstBrittleFloorFall() throws {
        let brittlePoint = GridPoint(x: 0, y: 1)
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            currentFloorIndex: 1,
            carriedHP: 2,
            relicEntries: [DungeonRelicEntry(relicID: .blackFeather)]
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 2,
            turnLimit: 8,
            hazards: [.brittleFloor(points: [brittlePoint])],
            allowsBasicOrthogonalMove: true,
            runState: runState
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: brittlePoint, in: core)
        playBasicMove(to: GridPoint(x: 0, y: 0), in: core)
        playBasicMove(to: brittlePoint, in: core)

        XCTAssertNotNil(core.dungeonFallEvent)
        XCTAssertEqual(core.dungeonHP, 2)
        XCTAssertEqual(core.dungeonRelicEntries.first { $0.relicID == .blackFeather }?.remainingUses, 0)
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
        let core = makeCore(mode: mode)

        XCTAssertFalse(core.enemyDangerPoints.contains(watcher.position))
        XCTAssertTrue(core.enemyDangerPoints.contains(GridPoint(x: 1, y: 1)))
        playBasicMove(to: GridPoint(x: 1, y: 1), in: core)

        XCTAssertEqual(core.dungeonHP, 1)
        XCTAssertEqual(core.progress, .playing)
        XCTAssertTrue(core.dungeonRunLogEntries.contains { $0.kind == .damage && $0.message.contains("シロフクロウの攻撃でHP -1") })
    }

    func testDungeonRunLogRecordsTrapDamageHealingAndFatigueDamage() throws {
        let trapPoint = GridPoint(x: 1, y: 0)
        let healingPoint = GridPoint(x: 2, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 1,
            hazards: [
                .damageTrap(points: [trapPoint], damage: 1),
                .healingTile(points: [healingPoint], amount: 1)
            ]
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: trapPoint, in: core)
        playBasicMove(to: healingPoint, in: core)

        XCTAssertTrue(core.dungeonRunLogEntries.contains { $0.kind == .damage && $0.message.contains("撒菱でHP -1") })
        XCTAssertTrue(core.dungeonRunLogEntries.contains { $0.kind == .healing && $0.message.contains("回復マスでHP +1") })
        XCTAssertTrue(core.dungeonRunLogEntries.contains { $0.kind == .damage && $0.message.contains("疲労でHP -1") })
    }

    func testGrowthEnemyDamageMitigationNegatesFirstEnemyDamage() throws {
        let watcher = EnemyDefinition(
            id: "watcher",
            name: "見張り",
            position: GridPoint(x: 1, y: 0),
            behavior: .watcher(direction: MoveVector(dx: 0, dy: 1), range: 3)
        )
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 2,
            enemyDamageMitigationsRemaining: 1
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 1),
            exit: GridPoint(x: 4, y: 4),
            hp: 2,
            turnLimit: 4,
            enemies: [watcher],
            allowsBasicOrthogonalMove: true,
            runState: runState
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: GridPoint(x: 1, y: 1), in: core)

        XCTAssertEqual(core.dungeonHP, 2)
        XCTAssertEqual(core.enemyDamageMitigationsRemaining, 0)
        XCTAssertEqual(core.progress, .playing)
    }

    func testWatcherDangerExtendsToBoardEdgeIgnoringLegacyRange() throws {
        let watcher = EnemyDefinition(
            id: "watcher",
            name: "見張り",
            position: GridPoint(x: 1, y: 0),
            behavior: .watcher(direction: MoveVector(dx: 0, dy: 1), range: 1)
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 4,
            enemies: [watcher]
        )
        let core = makeCore(mode: mode)

        XCTAssertFalse(core.enemyDangerPoints.contains(watcher.position))
        XCTAssertTrue(core.enemyDangerPoints.contains(GridPoint(x: 1, y: 1)))
        XCTAssertTrue(core.enemyDangerPoints.contains(GridPoint(x: 1, y: 2)))
        XCTAssertTrue(core.enemyDangerPoints.contains(GridPoint(x: 1, y: 3)))
        XCTAssertTrue(core.enemyDangerPoints.contains(GridPoint(x: 1, y: 4)))
    }

    func testWatcherDangerStopsAtImpassableTile() throws {
        let watcher = EnemyDefinition(
            id: "watcher",
            name: "見張り",
            position: GridPoint(x: 1, y: 0),
            behavior: .watcher(direction: MoveVector(dx: 0, dy: 1), range: 99)
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 4,
            enemies: [watcher],
            impassableTilePoints: [GridPoint(x: 1, y: 3)]
        )
        let core = makeCore(mode: mode)

        XCTAssertTrue(core.enemyDangerPoints.contains(GridPoint(x: 1, y: 1)))
        XCTAssertTrue(core.enemyDangerPoints.contains(GridPoint(x: 1, y: 2)))
        XCTAssertFalse(core.enemyDangerPoints.contains(GridPoint(x: 1, y: 3)))
        XCTAssertFalse(core.enemyDangerPoints.contains(GridPoint(x: 1, y: 4)))
    }

    func testClockwiseRotatingWatcherTurnsThroughFourFixedDirections() throws {
        let rotatingWatcher = EnemyDefinition(
            id: "rotating-watcher",
            name: "回転見張り",
            position: GridPoint(x: 2, y: 1),
            behavior: .rotatingWatcher(
                initialDirection: MoveVector(dx: 0, dy: 1),
                rotationDirection: .clockwise,
                range: 1
            )
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 4,
            enemies: [rotatingWatcher]
        )
        let core = makeCore(mode: mode)

        XCTAssertFalse(core.enemyDangerPoints.contains(rotatingWatcher.position))
        XCTAssertTrue(core.enemyDangerPoints.contains(GridPoint(x: 2, y: 2)))
        XCTAssertTrue(core.enemyDangerPoints.contains(GridPoint(x: 2, y: 3)))
        XCTAssertFalse(core.enemyDangerPoints.contains(GridPoint(x: 3, y: 1)))

        playBasicMove(to: GridPoint(x: 0, y: 1), in: core)

        XCTAssertTrue(core.enemyDangerPoints.contains(GridPoint(x: 3, y: 1)))
        XCTAssertTrue(core.enemyDangerPoints.contains(GridPoint(x: 4, y: 1)))
        XCTAssertFalse(core.enemyDangerPoints.contains(GridPoint(x: 2, y: 2)))
    }

    func testRotatingWatcherDisplayDangerShowsCurrentLine() throws {
        let rotatingWatcher = EnemyDefinition(
            id: "rotating-watcher",
            name: "回転見張り",
            position: GridPoint(x: 2, y: 1),
            behavior: .rotatingWatcher(
                initialDirection: MoveVector(dx: 0, dy: 1),
                rotationDirection: .clockwise,
                range: 1
            )
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 4,
            enemies: [rotatingWatcher],
            impassableTilePoints: [GridPoint(x: 4, y: 1)]
        )
        let core = makeCore(mode: mode)

        XCTAssertTrue(core.enemyDangerPoints.contains(GridPoint(x: 2, y: 2)))
        XCTAssertFalse(core.enemyDangerPoints.contains(GridPoint(x: 3, y: 1)))
        XCTAssertFalse(core.enemyDangerDisplayPoints.contains(rotatingWatcher.position))
        XCTAssertFalse(core.enemyDangerDisplayPoints.contains(GridPoint(x: 3, y: 1)))
        XCTAssertFalse(core.enemyDangerDisplayPoints.contains(GridPoint(x: 4, y: 1)))
        XCTAssertTrue(core.enemyDangerDisplayPoints.contains(GridPoint(x: 2, y: 2)))
    }

    func testEnemyFreezeHidesRotatingWatcherDisplayDanger() throws {
        let rotatingWatcher = EnemyDefinition(
            id: "rotating-watcher",
            name: "回転見張り",
            position: GridPoint(x: 2, y: 1),
            behavior: .rotatingWatcher(
                initialDirection: MoveVector(dx: 0, dy: 1),
                rotationDirection: .clockwise,
                range: 1
            )
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 4,
            enemies: [rotatingWatcher]
        )
        let core = makeCore(mode: mode)
        core.overrideEnemyFreezeTurnsRemainingForTesting(2)

        XCTAssertTrue(core.enemyDangerDisplayPoints.isEmpty)
    }

    func testCounterclockwiseRotatingWatcherTurnsThroughFourFixedDirections() throws {
        let rotatingWatcher = EnemyDefinition(
            id: "rotating-watcher",
            name: "回転見張り",
            position: GridPoint(x: 2, y: 1),
            behavior: .rotatingWatcher(
                initialDirection: MoveVector(dx: 0, dy: 1),
                rotationDirection: .counterclockwise,
                range: 1
            )
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 4,
            enemies: [rotatingWatcher]
        )
        let core = makeCore(mode: mode)

        XCTAssertTrue(core.enemyDangerPoints.contains(GridPoint(x: 2, y: 2)))
        XCTAssertFalse(core.enemyDangerPoints.contains(GridPoint(x: 1, y: 1)))

        playBasicMove(to: GridPoint(x: 0, y: 1), in: core)

        XCTAssertTrue(core.enemyDangerPoints.contains(GridPoint(x: 1, y: 1)))
        XCTAssertTrue(core.enemyDangerPoints.contains(GridPoint(x: 0, y: 1)))
        XCTAssertFalse(core.enemyDangerPoints.contains(GridPoint(x: 3, y: 1)))
    }

    func testRotatingWatcherDamagesAfterTurning() throws {
        let rotatingWatcher = EnemyDefinition(
            id: "rotating-watcher",
            name: "回転見張り",
            position: GridPoint(x: 2, y: 1),
            behavior: .rotatingWatcher(
                initialDirection: MoveVector(dx: 1, dy: 0),
                rotationDirection: .counterclockwise,
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
            cards: [.kingUpRight, .straightRight2, .kingUpRight, .straightLeft2, .straightDown2]
        )

        playMove(to: GridPoint(x: 2, y: 2), in: core)

        XCTAssertEqual(core.dungeonHP, 2)
        XCTAssertEqual(core.progress, .playing)
        XCTAssertEqual(core.enemyStates.first?.rotationIndex, 1)
        XCTAssertTrue(core.dungeonEnemyTurnEvent?.transitions.first?.didRotate == true)
    }

    func testRotatingWatcherAttacksCurrentLineWithoutTurning() throws {
        let rotatingWatcher = EnemyDefinition(
            id: "rotating-watcher",
            name: "回転見張り",
            position: GridPoint(x: 2, y: 1),
            behavior: .rotatingWatcher(
                initialDirection: MoveVector(dx: -1, dy: 0),
                rotationDirection: .clockwise,
                range: 2
            )
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 1),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 4,
            enemies: [rotatingWatcher],
            cardAcquisitionMode: .inventoryOnly
        )
        let core = makeCore(mode: mode)
        XCTAssertTrue(core.addDungeonInventorySupportCardForTesting(.refillEmptySlots, rewardUses: 1))
        let supportIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.topCard?.supportCard == .refillEmptySlots })

        core.playSupportCard(at: supportIndex)

        XCTAssertEqual(core.dungeonHP, 2)
        XCTAssertEqual(core.enemyStates.first?.rotationIndex, 0)
        XCTAssertTrue(core.dungeonEnemyTurnEvent?.attackedPlayer == true)
        XCTAssertTrue(core.dungeonEnemyTurnEvent?.transitions.first?.didRotate == false)
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
                initialDirection: MoveVector(dx: 1, dy: 0),
                rotationDirection: .clockwise,
                range: 2
            )
        )
        let chaser = EnemyDefinition(
            id: "chaser",
            name: "追跡兵",
            position: GridPoint(x: 4, y: 3),
            behavior: .chaser
        )
        let marker = EnemyDefinition(
            id: "marker",
            name: "メテオ兵",
            position: GridPoint(x: 4, y: 0),
            behavior: .marker(directions: [], range: 2)
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 2),
            hp: 3,
            turnLimit: 4,
            enemies: [patrol, rotatingWatcher, chaser, marker]
        )
        let core = makeCore(mode: mode)

        let safeBasicMove = try XCTUnwrap(
            core.availableBasicOrthogonalMoves().first {
                !core.enemyWarningPoints.contains($0.destination)
                    && !core.enemyDangerPoints.contains($0.destination)
            }
        )
        playBasicMove(to: safeBasicMove.destination, in: core)

        let event = try XCTUnwrap(core.dungeonEnemyTurnEvent)
        XCTAssertEqual(event.hpBefore, 3)
        XCTAssertLessThanOrEqual(event.hpAfter, event.hpBefore)
        XCTAssertEqual(Set(event.transitions.map(\.enemyID)), ["patrol", "rotating-watcher", "chaser", "marker"])

        let transitions = Dictionary(uniqueKeysWithValues: event.transitions.map { ($0.enemyID, $0) })
        XCTAssertEqual(transitions["patrol"]?.before.position, GridPoint(x: 2, y: 1))
        XCTAssertEqual(transitions["patrol"]?.after.position, GridPoint(x: 3, y: 1))
        XCTAssertEqual(transitions["chaser"]?.before.position, GridPoint(x: 4, y: 3))
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
                initialDirection: MoveVector(dx: 1, dy: 0),
                rotationDirection: .counterclockwise,
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
            cards: [.kingUpRight, .straightRight2, .kingUpRight, .straightLeft2, .straightDown2]
        )

        playMove(to: GridPoint(x: 2, y: 2), in: core)

        let event = try XCTUnwrap(core.dungeonEnemyTurnEvent)
        XCTAssertTrue(event.attackedPlayer)
        XCTAssertEqual(event.hpBefore, 3)
        XCTAssertEqual(event.hpAfter, 2)
        XCTAssertEqual(event.transitions.first?.enemyID, "rotating-watcher")
        XCTAssertTrue(event.transitions.first?.didRotate == true)
        XCTAssertTrue(core.dungeonRunLogEntries.contains { $0.kind == .damage && $0.message.contains("オーロラフクロウの攻撃でHP -1") })
    }

    func testRotatingWatcherDangerStopsAtImpassableTile() throws {
        let rotatingWatcher = EnemyDefinition(
            id: "rotating-watcher",
            name: "回転見張り",
            position: GridPoint(x: 1, y: 1),
            behavior: .rotatingWatcher(
                initialDirection: MoveVector(dx: 1, dy: 0),
                rotationDirection: .clockwise,
                range: 1
            )
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 4,
            enemies: [rotatingWatcher],
            impassableTilePoints: [GridPoint(x: 4, y: 1)]
        )
        let core = makeCore(mode: mode)

        XCTAssertTrue(core.enemyDangerPoints.contains(GridPoint(x: 2, y: 1)))
        XCTAssertTrue(core.enemyDangerPoints.contains(GridPoint(x: 3, y: 1)))
        XCTAssertFalse(core.enemyDangerPoints.contains(GridPoint(x: 4, y: 1)))
    }

    func testRotatingWatcherDecodesLegacyDirectionsAsInitialDirectionAndRotation() throws {
        let json = """
        {
          "type": "rotatingWatcher",
          "directions": [
            { "dx": 0, "dy": 1 },
            { "dx": -1, "dy": 0 }
          ],
          "range": 3
        }
        """.data(using: .utf8)!

        let behavior = try JSONDecoder().decode(EnemyBehavior.self, from: json)

        XCTAssertEqual(
            behavior,
            .rotatingWatcher(
                initialDirection: MoveVector(dx: 0, dy: 1),
                rotationDirection: .counterclockwise,
                range: 3
            )
        )
    }

    func testMarkerEnemyWarnsMeteorLandingPointsAndDamagesAfterPlayerMove() throws {
        let marker = EnemyDefinition(
            id: "marker",
            name: "メテオ兵",
            position: GridPoint(x: 3, y: 1),
            behavior: .marker(directions: [], range: 99)
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 1, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 4,
            enemies: [marker]
        )
        let core = makeCore(mode: mode)

        let warnedBasicMove = try XCTUnwrap(
            core.availableBasicOrthogonalMoves().first { core.enemyWarningPoints.contains($0.destination) }
        )
        XCTAssertFalse(core.enemyWarningPoints.contains(GridPoint(x: 1, y: 0)))
        XCTAssertFalse(core.enemyDangerPoints.contains(warnedBasicMove.destination))

        playBasicMove(to: warnedBasicMove.destination, in: core)

        XCTAssertEqual(core.dungeonHP, 2)
        XCTAssertEqual(core.progress, .playing)
        XCTAssertTrue(core.dungeonRunLogEntries.contains { $0.kind == .damage && $0.message.contains("氷下のシャチの急襲でHP -1") })
    }

    func testGrowthMarkerDamageMitigationNegatesFirstMeteorDamage() throws {
        let marker = EnemyDefinition(
            id: "marker",
            name: "メテオ兵",
            position: GridPoint(x: 3, y: 1),
            behavior: .marker(directions: [], range: 99)
        )
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 3,
            markerDamageMitigationsRemaining: 1
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 1, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 4,
            enemies: [marker],
            allowsBasicOrthogonalMove: true,
            runState: runState
        )
        let core = makeCore(mode: mode)

        let warnedBasicMove = try XCTUnwrap(
            core.availableBasicOrthogonalMoves().first { core.enemyWarningPoints.contains($0.destination) }
        )
        playBasicMove(to: warnedBasicMove.destination, in: core)

        XCTAssertEqual(core.dungeonHP, 3)
        XCTAssertEqual(core.markerDamageMitigationsRemaining, 0)
        XCTAssertEqual(core.progress, .playing)
    }

    func testMarkerEnemyWarningExcludesBlockedAndEnemyTiles() throws {
        let marker = EnemyDefinition(
            id: "marker",
            name: "メテオ兵",
            position: GridPoint(x: 4, y: 1),
            behavior: .marker(directions: [], range: 20)
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 4,
            enemies: [marker],
            impassableTilePoints: [GridPoint(x: 2, y: 1)]
        )
        let core = makeCore(mode: mode)

        XCTAssertFalse(core.enemyWarningPoints.contains(GridPoint(x: 2, y: 1)))
        XCTAssertFalse(core.enemyWarningPoints.contains(GridPoint(x: 4, y: 1)))
        XCTAssertTrue(core.enemyWarningPoints.allSatisfy { core.board.isTraversable($0) })
    }

    func testMarkerEnemyWarningIsDeterministicAndChangesAfterEnemyTurn() throws {
        let marker = EnemyDefinition(
            id: "marker",
            name: "メテオ兵",
            position: GridPoint(x: 3, y: 1),
            behavior: .marker(directions: [], range: 2)
        )
        let runState = DungeonRunState(
            dungeonID: "test-dungeon",
            carriedHP: 3,
            cardVariationSeed: 123
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 4,
            enemies: [marker],
            allowsBasicOrthogonalMove: true,
            runState: runState
        )
        let core = makeCore(mode: mode)
        let repeatedCore = makeCore(mode: mode)

        let initialWarnings = core.enemyWarningPoints
        XCTAssertEqual(initialWarnings, repeatedCore.enemyWarningPoints)
        XCTAssertEqual(initialWarnings.count, 2)

        playBasicMove(to: GridPoint(x: 0, y: 1), in: core)

        XCTAssertNotEqual(core.enemyWarningPoints, initialWarnings)
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
            enemies: [chaser]
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
            impassableTilePoints: [GridPoint(x: 3, y: 0)]
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
            enemies: [chaser]
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
            ]
        )
        let unreachableCore = makeCore(mode: unreachableMode)

        XCTAssertTrue(unreachableCore.enemyChaserMovementPreviews.isEmpty)
        playBasicMove(to: GridPoint(x: 1, y: 0), in: unreachableCore)
        XCTAssertEqual(unreachableCore.enemyStates.first?.position, GridPoint(x: 4, y: 4))
    }

    func testChaserRoutesAroundDamageTrapWhenSafeRouteExists() throws {
        let chaser = EnemyDefinition(
            id: "chaser",
            name: "追跡兵",
            position: GridPoint(x: 4, y: 0),
            behavior: .chaser
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 1, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            enemies: [chaser],
            hazards: [.damageTrap(points: [GridPoint(x: 3, y: 0)], damage: 1)]
        )
        let core = makeCore(mode: mode)

        XCTAssertEqual(
            core.enemyChaserMovementPreviews,
            [
                EnemyPatrolMovementPreview(
                    enemyID: "chaser",
                    current: GridPoint(x: 4, y: 0),
                    next: GridPoint(x: 4, y: 1),
                    vector: MoveVector(dx: 0, dy: 1)
                )
            ]
        )

        playBasicMove(to: GridPoint(x: 1, y: 1), in: core)

        XCTAssertEqual(core.enemyStates.first?.position, GridPoint(x: 4, y: 1))
    }

    func testChaserWarpsAfterSteppingOnWarpTileAndUpdatesDanger() throws {
        let warpSource = GridPoint(x: 3, y: 0)
        let warpDestination = GridPoint(x: 1, y: 2)
        let chaser = EnemyDefinition(
            id: "chaser",
            name: "追跡兵",
            position: GridPoint(x: 4, y: 0),
            behavior: .chaser
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 4,
            enemies: [chaser],
            warpTilePairs: ["enemy-warp": [warpSource, warpDestination]]
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: GridPoint(x: 0, y: 1), in: core)

        XCTAssertEqual(core.enemyStates.first { $0.id == "chaser" }?.position, warpDestination)
        XCTAssertTrue(core.enemyDangerPoints.contains(GridPoint(x: 1, y: 1)))
        XCTAssertFalse(core.enemyDangerPoints.contains(GridPoint(x: 4, y: 0)))
        XCTAssertEqual(
            core.dungeonEnemyTurnEvent?.transitions.first { $0.enemyID == "chaser" }?.warpPoint,
            warpSource
        )
    }

    func testEnemyWarpStopsOnWarpTileWhenDestinationIsOccupied() throws {
        let warpSource = GridPoint(x: 3, y: 0)
        let warpDestination = GridPoint(x: 1, y: 2)
        let guardPost = EnemyDefinition(
            id: "guard",
            name: "番兵",
            position: warpDestination,
            behavior: .guardPost
        )
        let chaser = EnemyDefinition(
            id: "chaser",
            name: "追跡兵",
            position: GridPoint(x: 4, y: 0),
            behavior: .chaser
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 4,
            enemies: [guardPost, chaser],
            warpTilePairs: ["enemy-warp": [warpSource, warpDestination]]
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: GridPoint(x: 0, y: 1), in: core)

        XCTAssertEqual(core.enemyStates.first { $0.id == "guard" }?.position, warpDestination)
        XCTAssertEqual(core.enemyStates.first { $0.id == "chaser" }?.position, warpSource)
        XCTAssertEqual(Set(core.enemyStates.map(\.position)).count, core.enemyStates.count)
        XCTAssertNil(core.dungeonEnemyTurnEvent?.transitions.first { $0.enemyID == "chaser" }?.warpPoint)
    }

    func testEnemyWarpStopsOnWarpTileWhenDestinationIsCollapsed() throws {
        let warpSource = GridPoint(x: 3, y: 0)
        let warpDestination = GridPoint(x: 1, y: 2)
        let chaser = EnemyDefinition(
            id: "chaser",
            name: "追跡兵",
            position: GridPoint(x: 4, y: 0),
            behavior: .chaser
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 4,
            enemies: [chaser],
            warpTilePairs: ["enemy-warp": [warpSource, warpDestination]]
        )
        let core = makeCore(mode: mode)
        core.overrideDungeonFloorStateForTesting(cracked: [], collapsed: [warpDestination])

        playBasicMove(to: GridPoint(x: 0, y: 1), in: core)

        XCTAssertEqual(core.enemyStates.first { $0.id == "chaser" }?.position, warpSource)
        XCTAssertNil(core.dungeonEnemyTurnEvent?.transitions.first { $0.enemyID == "chaser" }?.warpPoint)
    }

    func testChaserStepsOntoLavaAndDefeatsItselfWhenNoSafeRouteExists() throws {
        let lavaPoint = GridPoint(x: 1, y: 0)
        let chaser = EnemyDefinition(
            id: "chaser",
            name: "追跡兵",
            position: GridPoint(x: 2, y: 0),
            behavior: .chaser
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            enemies: [chaser],
            hazards: [.lavaTile(points: [lavaPoint], damage: 1)],
            impassableTilePoints: [
                GridPoint(x: 1, y: 1),
                GridPoint(x: 2, y: 1),
                GridPoint(x: 3, y: 0)
            ]
        )
        let core = makeCore(mode: mode)

        XCTAssertEqual(core.enemyChaserMovementPreviews.first?.next, lavaPoint)

        playBasicMove(to: GridPoint(x: 0, y: 1), in: core)

        XCTAssertTrue(core.enemyStates.isEmpty)
        XCTAssertTrue(core.enemyChaserMovementPreviews.isEmpty)
    }

    func testChaserConsumesDamageTrapWhenForcedOntoIt() throws {
        let trapPoint = GridPoint(x: 1, y: 0)
        let chaser = EnemyDefinition(
            id: "chaser",
            name: "追跡兵",
            position: GridPoint(x: 2, y: 0),
            behavior: .chaser
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            enemies: [chaser],
            hazards: [.damageTrap(points: [trapPoint], damage: 1)],
            impassableTilePoints: [
                GridPoint(x: 1, y: 1),
                GridPoint(x: 2, y: 1),
                GridPoint(x: 3, y: 0)
            ]
        )
        let core = makeCore(mode: mode)

        XCTAssertEqual(core.enemyChaserMovementPreviews.first?.next, trapPoint)

        playBasicMove(to: GridPoint(x: 0, y: 1), in: core)

        XCTAssertTrue(core.enemyStates.isEmpty)
        XCTAssertTrue(core.damageTrapPoints.isEmpty)
        XCTAssertEqual(core.consumedDamageTrapPoints, [trapPoint])
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
            enemies: [chaser]
        )
        let core = makeCore(mode: mode)

        XCTAssertFalse(core.enemyDangerPoints.contains(GridPoint(x: 3, y: 0)))
        XCTAssertTrue(core.enemyDangerPoints.contains(GridPoint(x: 2, y: 0)))
        XCTAssertTrue(core.enemyDangerPoints.contains(GridPoint(x: 3, y: 1)))
        XCTAssertFalse(core.enemyDangerPoints.contains(GridPoint(x: 2, y: 1)))

        playBasicMove(to: GridPoint(x: 1, y: 0), in: core)

        XCTAssertEqual(core.enemyStates.first?.position, GridPoint(x: 2, y: 0))
        XCTAssertEqual(core.dungeonHP, 2)
        XCTAssertEqual(core.progress, .playing)
    }

    func testChaserAttacksWithoutMovingWhenPlayerEntersCurrentDanger() throws {
        let chaser = EnemyDefinition(
            id: "chaser",
            name: "追跡兵",
            position: GridPoint(x: 2, y: 0),
            behavior: .chaser
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            enemies: [chaser]
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: GridPoint(x: 1, y: 0), in: core)

        XCTAssertEqual(core.enemyStates.first?.position, GridPoint(x: 2, y: 0))
        XCTAssertEqual(core.dungeonHP, 2)
        XCTAssertEqual(core.progress, .playing)
        XCTAssertEqual(core.dungeonEnemyTurnEvent?.attackedPlayer, true)
    }

    func testChaserIsDefeatedWhenMovingIntoWatcherLaser() throws {
        let watcher = EnemyDefinition(
            id: "watcher",
            name: "見張り",
            position: GridPoint(x: 2, y: 0),
            behavior: .watcher(direction: MoveVector(dx: 0, dy: 1), range: 4)
        )
        let chaser = EnemyDefinition(
            id: "chaser",
            name: "追跡兵",
            position: GridPoint(x: 3, y: 1),
            behavior: .chaser
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            enemies: [watcher, chaser]
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: GridPoint(x: 0, y: 1), in: core)

        XCTAssertEqual(core.enemyStates.map(\.id), ["watcher"])
        XCTAssertFalse(core.enemyChaserMovementPreviews.contains { $0.enemyID == "chaser" })
    }

    func testPatrolIsDefeatedWhenMovingIntoWatcherLaser() throws {
        let watcher = EnemyDefinition(
            id: "watcher",
            name: "見張り",
            position: GridPoint(x: 2, y: 0),
            behavior: .watcher(direction: MoveVector(dx: 0, dy: 1), range: 4)
        )
        let patrol = EnemyDefinition(
            id: "patrol",
            name: "巡回兵",
            position: GridPoint(x: 3, y: 1),
            behavior: .patrol(path: [
                GridPoint(x: 3, y: 1),
                GridPoint(x: 2, y: 1)
            ])
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            enemies: [watcher, patrol]
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: GridPoint(x: 0, y: 1), in: core)

        XCTAssertEqual(core.enemyStates.map(\.id), ["watcher"])
        XCTAssertFalse(core.enemyPatrolMovementPreviews.contains { $0.enemyID == "patrol" })
    }

    func testMovingEnemyIsDefeatedByRotatingWatcherFinalLaser() throws {
        let rotatingWatcher = EnemyDefinition(
            id: "rotating-watcher",
            name: "回転見張り",
            position: GridPoint(x: 1, y: 1),
            behavior: .rotatingWatcher(
                initialDirection: MoveVector(dx: 0, dy: 1),
                rotationDirection: .clockwise,
                range: 4
            )
        )
        let chaser = EnemyDefinition(
            id: "chaser",
            name: "追跡兵",
            position: GridPoint(x: 3, y: 2),
            behavior: .chaser
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 4, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            enemies: [rotatingWatcher, chaser]
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: GridPoint(x: 3, y: 0), in: core)

        XCTAssertEqual(core.enemyStates.map(\.id), ["rotating-watcher"])
        XCTAssertEqual(core.enemyStates.first?.rotationIndex, 1)
        XCTAssertTrue(core.enemyDangerPoints.contains(GridPoint(x: 3, y: 1)))
    }

    func testDarknessSpellSuppressesMovingEnemyLaserDefeat() throws {
        let watcher = EnemyDefinition(
            id: "watcher",
            name: "見張り",
            position: GridPoint(x: 2, y: 0),
            behavior: .watcher(direction: MoveVector(dx: 0, dy: 1), range: 4)
        )
        let chaser = EnemyDefinition(
            id: "chaser",
            name: "追跡兵",
            position: GridPoint(x: 3, y: 1),
            behavior: .chaser
        )
        let runState = DungeonRunState(
            dungeonID: "darkness-laser-test",
            carriedHP: 3,
            rewardInventoryEntries: [DungeonInventoryEntry(support: .darknessSpell, rewardUses: 1)]
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            enemies: [watcher, chaser],
            cardAcquisitionMode: .inventoryOnly,
            runState: runState
        )
        let core = makeCore(mode: mode)
        let supportIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.topCard?.supportCard == .darknessSpell })

        core.playSupportCard(at: supportIndex)

        XCTAssertEqual(core.enemyStates.map(\.id), ["watcher", "chaser"])
        XCTAssertEqual(core.enemyStates.first { $0.id == "chaser" }?.position, GridPoint(x: 2, y: 1))
        XCTAssertTrue(core.isDarknessSpellActive)
    }

    func testBasicMoveStompsEveryEnemyBehaviorWithoutTakingDamageFromThatEnemy() throws {
        let enemyCases: [(id: String, name: String, behavior: EnemyBehavior)] = [
            ("guard", "番兵", .guardPost),
            ("patrol", "巡回兵", .patrol(path: [GridPoint(x: 1, y: 0), GridPoint(x: 2, y: 0)])),
            ("watcher", "見張り", .watcher(direction: MoveVector(dx: 0, dy: 1), range: 2)),
            (
                "rotating-watcher",
                "回転見張り",
                .rotatingWatcher(
                    initialDirection: MoveVector(dx: 0, dy: 1),
                    rotationDirection: .clockwise,
                    range: 2
                )
            ),
            ("chaser", "追跡兵", .chaser),
            ("marker", "メテオ兵", .marker(directions: [], range: 2))
        ]

        for enemyCase in enemyCases {
            let enemy = EnemyDefinition(
                id: enemyCase.id,
                name: enemyCase.name,
                position: GridPoint(x: 1, y: 0),
                behavior: enemyCase.behavior
            )
            let mode = makeDungeonMode(
                spawn: GridPoint(x: 0, y: 0),
                exit: GridPoint(x: 4, y: 4),
                hp: 3,
                turnLimit: 8,
                enemies: [enemy],
                allowsBasicOrthogonalMove: true
            )
            let core = makeCore(mode: mode)

            playBasicMove(to: GridPoint(x: 1, y: 0), in: core)

            XCTAssertTrue(core.enemyStates.isEmpty, "\(enemyCase.name)を踏んだら倒れる想定です")
            XCTAssertEqual(core.dungeonHP, 3, "\(enemyCase.name)を踏んだ手はその敵から被弾しません")
            XCTAssertFalse(core.enemyDangerPoints.contains(GridPoint(x: 1, y: 0)))
            XCTAssertNil(core.dungeonEnemyTurnEvent)
        }
    }

    func testRayMoveStompsEnemiesOnIntermediatePath() throws {
        let enemies = [
            EnemyDefinition(
                id: "guard",
                name: "番兵",
                position: GridPoint(x: 1, y: 0),
                behavior: .guardPost
            ),
            EnemyDefinition(
                id: "watcher",
                name: "見張り",
                position: GridPoint(x: 2, y: 0),
                behavior: .watcher(direction: MoveVector(dx: 0, dy: 1), range: 2)
            ),
            EnemyDefinition(
                id: "marker",
                name: "メテオ兵",
                position: GridPoint(x: 3, y: 0),
                behavior: .marker(directions: [], range: 2)
            )
        ]
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            enemies: enemies
        )
        let core = makeCore(mode: mode, cards: [.rayRight])

        playMove(to: GridPoint(x: 4, y: 0), in: core)

        XCTAssertTrue(core.enemyStates.isEmpty)
        XCTAssertEqual(core.dungeonHP, 3)
        XCTAssertEqual(core.lastMovementResolution?.path, [
            GridPoint(x: 1, y: 0),
            GridPoint(x: 2, y: 0),
            GridPoint(x: 3, y: 0),
            GridPoint(x: 4, y: 0)
        ])
        XCTAssertNil(core.dungeonEnemyTurnEvent)
    }

    func testRayMoveTakesChaserDangerDamageBeforeStompingChaser() throws {
        let chaser = EnemyDefinition(
            id: "chaser",
            name: "追跡兵",
            position: GridPoint(x: 2, y: 0),
            behavior: .chaser
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            enemies: [chaser]
        )
        let core = makeCore(mode: mode, cards: [.rayRight])

        playMove(to: GridPoint(x: 4, y: 0), in: core)

        XCTAssertTrue(core.enemyStates.isEmpty, "追跡兵本体を踏んだら倒れる想定です")
        XCTAssertEqual(core.dungeonHP, 2, "追跡兵の攻撃範囲に入った時点で先にダメージを受ける想定です")
        XCTAssertEqual(core.progress, .playing)
        XCTAssertEqual(core.lastMovementResolution?.presentationSteps.map(\.hpAfter), [2, 2, 2, 2])
        XCTAssertNil(core.dungeonEnemyTurnEvent)
    }

    func testRayMoveChaserDangerDamageUsesEnemyDamageMitigationBeforeStomping() throws {
        let chaser = EnemyDefinition(
            id: "chaser",
            name: "追跡兵",
            position: GridPoint(x: 2, y: 0),
            behavior: .chaser
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            enemies: [chaser],
            runState: DungeonRunState(
                dungeonID: "growth-tower",
                carriedHP: 3,
                enemyDamageMitigationsRemaining: 1
            )
        )
        let core = makeCore(mode: mode, cards: [.rayRight])

        playMove(to: GridPoint(x: 4, y: 0), in: core)

        XCTAssertTrue(core.enemyStates.isEmpty)
        XCTAssertEqual(core.dungeonHP, 3)
        XCTAssertEqual(core.enemyDamageMitigationsRemaining, 0)
        XCTAssertEqual(core.lastMovementResolution?.presentationSteps.map(\.hpAfter), [3, 3, 3, 3])
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
            cards: [.kingUpRight, .straightRight2, .straightLeft2, .straightDown2, .straightRight2]
        )

        playMove(to: GridPoint(x: 2, y: 0), in: core)

        XCTAssertEqual(core.enemyStates.first?.position, GridPoint(x: 2, y: 1))
    }

    func testPatrolEnemyWarpsAfterSteppingOnWarpTile() throws {
        let warpSource = GridPoint(x: 3, y: 2)
        let warpDestination = GridPoint(x: 4, y: 0)
        let patrol = EnemyDefinition(
            id: "patrol",
            name: "巡回兵",
            position: GridPoint(x: 3, y: 3),
            behavior: .patrol(path: [
                GridPoint(x: 3, y: 3),
                warpSource,
                GridPoint(x: 3, y: 1)
            ])
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 0, y: 4),
            hp: 3,
            turnLimit: 4,
            enemies: [patrol],
            warpTilePairs: ["enemy-warp": [warpSource, warpDestination]]
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: GridPoint(x: 1, y: 0), in: core)

        let patrolState = try XCTUnwrap(core.enemyStates.first { $0.id == "patrol" })
        XCTAssertEqual(patrolState.position, warpDestination)
        XCTAssertEqual(patrolState.patrolIndex, 1)
        XCTAssertEqual(core.dungeonEnemyTurnEvent?.transitions.first?.warpPoint, warpSource)
    }

    func testPatrolEnemyStaysWhenNextStepIsOccupiedByAnotherEnemy() throws {
        let patrol = EnemyDefinition(
            id: "patrol",
            name: "巡回兵",
            position: GridPoint(x: 1, y: 1),
            behavior: .patrol(path: [
                GridPoint(x: 1, y: 1),
                GridPoint(x: 2, y: 1)
            ])
        )
        let guardPost = EnemyDefinition(
            id: "guard",
            name: "番兵",
            position: GridPoint(x: 2, y: 1),
            behavior: .guardPost
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 4,
            enemies: [patrol, guardPost]
        )
        let core = makeCore(
            mode: mode,
            cards: [.kingUpRight, .straightRight2, .straightLeft2, .straightDown2, .straightRight2]
        )

        XCTAssertTrue(core.enemyPatrolMovementPreviews.isEmpty)

        playMove(to: GridPoint(x: 2, y: 0), in: core)

        let patrolState = try XCTUnwrap(core.enemyStates.first { $0.id == "patrol" })
        XCTAssertEqual(patrolState.position, GridPoint(x: 1, y: 1))
        XCTAssertEqual(patrolState.patrolIndex, 0)
        XCTAssertEqual(
            Set(core.enemyStates.map(\.position)),
            [GridPoint(x: 1, y: 1), GridPoint(x: 2, y: 1)]
        )
    }

    func testPatrolAttacksWithoutAdvancingWhenPlayerEntersCurrentDanger() throws {
        let patrol = EnemyDefinition(
            id: "patrol",
            name: "巡回兵",
            position: GridPoint(x: 2, y: 1),
            behavior: .patrol(path: [
                GridPoint(x: 2, y: 1),
                GridPoint(x: 3, y: 1)
            ])
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 1),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            enemies: [patrol]
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: GridPoint(x: 1, y: 1), in: core)

        XCTAssertEqual(core.enemyStates.first?.position, GridPoint(x: 2, y: 1))
        XCTAssertEqual(core.enemyStates.first?.patrolIndex, 0)
        XCTAssertEqual(core.dungeonHP, 2)
        XCTAssertEqual(core.progress, .playing)
        XCTAssertEqual(core.dungeonEnemyTurnEvent?.attackedPlayer, true)
    }

    func testPatrolMovesThenAttacksWhenPlayerEntersPostMoveDanger() throws {
        let patrol = EnemyDefinition(
            id: "patrol",
            name: "巡回兵",
            position: GridPoint(x: 3, y: 1),
            behavior: .patrol(path: [
                GridPoint(x: 3, y: 1),
                GridPoint(x: 2, y: 1)
            ])
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 1),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            enemies: [patrol]
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: GridPoint(x: 1, y: 1), in: core)

        XCTAssertEqual(core.enemyStates.first?.position, GridPoint(x: 2, y: 1))
        XCTAssertEqual(core.enemyStates.first?.patrolIndex, 1)
        XCTAssertEqual(core.dungeonHP, 2)
        XCTAssertEqual(core.progress, .playing)
        XCTAssertEqual(core.dungeonEnemyTurnEvent?.attackedPlayer, true)
    }

    func testLaterChaserRoutesAroundEarlierEnemyReservedDestination() throws {
        let patrol = EnemyDefinition(
            id: "patrol",
            name: "巡回兵",
            position: GridPoint(x: 1, y: 1),
            behavior: .patrol(path: [
                GridPoint(x: 1, y: 1),
                GridPoint(x: 2, y: 1)
            ])
        )
        let chaser = EnemyDefinition(
            id: "chaser",
            name: "追跡兵",
            position: GridPoint(x: 3, y: 1),
            behavior: .chaser
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 4,
            enemies: [patrol, chaser]
        )
        let core = makeCore(
            mode: mode,
            cards: [.kingUpRight, .straightRight2, .straightLeft2, .straightDown2, .straightRight2]
        )

        XCTAssertEqual(core.enemyPatrolMovementPreviews.map(\.enemyID), ["patrol"])
        XCTAssertEqual(
            core.enemyChaserMovementPreviews,
            [
                EnemyPatrolMovementPreview(
                    enemyID: "chaser",
                    current: GridPoint(x: 3, y: 1),
                    next: GridPoint(x: 3, y: 0),
                    vector: MoveVector(dx: 0, dy: -1)
                )
            ]
        )

        playMove(to: GridPoint(x: 2, y: 0), in: core)

        let patrolState = try XCTUnwrap(core.enemyStates.first { $0.id == "patrol" })
        let chaserState = try XCTUnwrap(core.enemyStates.first { $0.id == "chaser" })
        XCTAssertEqual(patrolState.position, GridPoint(x: 2, y: 1))
        XCTAssertEqual(patrolState.patrolIndex, 1)
        XCTAssertEqual(chaserState.position, GridPoint(x: 3, y: 0))
        XCTAssertEqual(
            Set(core.enemyStates.map(\.position)),
            [GridPoint(x: 2, y: 1), GridPoint(x: 3, y: 0)]
        )
    }

    func testChaserRoutesAroundOccupiedEnemyDestination() throws {
        let guardPost = EnemyDefinition(
            id: "guard",
            name: "番兵",
            position: GridPoint(x: 2, y: 1),
            behavior: .guardPost
        )
        let chaser = EnemyDefinition(
            id: "chaser",
            name: "追跡兵",
            position: GridPoint(x: 3, y: 1),
            behavior: .chaser
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 4,
            enemies: [guardPost, chaser]
        )
        let core = makeCore(
            mode: mode,
            cards: [.kingUpRight, .straightRight2, .straightLeft2, .straightDown2, .straightRight2]
        )

        XCTAssertEqual(
            core.enemyChaserMovementPreviews,
            [
                EnemyPatrolMovementPreview(
                    enemyID: "chaser",
                    current: GridPoint(x: 3, y: 1),
                    next: GridPoint(x: 3, y: 0),
                    vector: MoveVector(dx: 0, dy: -1)
                )
            ]
        )

        playMove(to: GridPoint(x: 2, y: 0), in: core)

        let guardState = try XCTUnwrap(core.enemyStates.first { $0.id == "guard" })
        let chaserState = try XCTUnwrap(core.enemyStates.first { $0.id == "chaser" })
        XCTAssertEqual(guardState.position, GridPoint(x: 2, y: 1))
        XCTAssertEqual(chaserState.position, GridPoint(x: 3, y: 0))
        XCTAssertEqual(
            Set(core.enemyStates.map(\.position)),
            [GridPoint(x: 2, y: 1), GridPoint(x: 3, y: 0)]
        )
    }

    func testChaserStaysWhenEnemiesAndObstaclesLeaveNoReachableRoute() throws {
        let guardPost = EnemyDefinition(
            id: "guard",
            name: "番兵",
            position: GridPoint(x: 2, y: 1),
            behavior: .guardPost
        )
        let chaser = EnemyDefinition(
            id: "chaser",
            name: "追跡兵",
            position: GridPoint(x: 3, y: 1),
            behavior: .chaser
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 4,
            enemies: [guardPost, chaser],
            impassableTilePoints: [
                GridPoint(x: 3, y: 0),
                GridPoint(x: 3, y: 2),
                GridPoint(x: 4, y: 1)
            ]
        )
        let core = makeCore(
            mode: mode,
            cards: [.kingUpRight, .straightRight2, .straightLeft2, .straightDown2, .straightRight2]
        )

        XCTAssertTrue(core.enemyChaserMovementPreviews.isEmpty)

        playMove(to: GridPoint(x: 2, y: 0), in: core)

        XCTAssertEqual(core.enemyStates.first { $0.id == "chaser" }?.position, GridPoint(x: 3, y: 1))
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
            cards: [.kingUpRight, .straightRight2, .straightLeft2, .straightDown2, .straightRight2]
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

        playMove(to: GridPoint(x: 2, y: 0), in: core)

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

    func testLoopPatrolMovesFromLastPointBackToFirstPoint() throws {
        let loopPath = [
            GridPoint(x: 1, y: 2),
            GridPoint(x: 2, y: 2),
            GridPoint(x: 3, y: 2),
            GridPoint(x: 3, y: 3),
            GridPoint(x: 2, y: 3),
            GridPoint(x: 1, y: 3)
        ]
        let patrol = EnemyDefinition(
            id: "patrol",
            name: "巡回兵",
            position: GridPoint(x: 1, y: 3),
            behavior: .patrol(path: loopPath)
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
            cards: [.straightRight2, .kingUpRight, .straightLeft2, .straightDown2, .straightRight2]
        )

        XCTAssertEqual(core.enemyPatrolMovementPreviews.first?.next, GridPoint(x: 1, y: 2))

        playMove(to: GridPoint(x: 2, y: 0), in: core)

        XCTAssertEqual(core.enemyStates.first { $0.id == "patrol" }?.position, GridPoint(x: 1, y: 2))
    }

    func testPatrolStartingFromMiddleOfPathMovesImmediatelyToNextPoint() throws {
        let loopPath = [
            GridPoint(x: 1, y: 2),
            GridPoint(x: 2, y: 2),
            GridPoint(x: 3, y: 2),
            GridPoint(x: 3, y: 3),
            GridPoint(x: 2, y: 3),
            GridPoint(x: 1, y: 3)
        ]
        let patrol = EnemyDefinition(
            id: "patrol",
            name: "巡回兵",
            position: GridPoint(x: 3, y: 3),
            behavior: .patrol(path: loopPath)
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
            cards: [.straightRight2, .kingUpRight, .straightLeft2, .straightDown2, .straightRight2]
        )

        XCTAssertEqual(core.enemyPatrolMovementPreviews.first?.next, GridPoint(x: 2, y: 3))

        playMove(to: GridPoint(x: 2, y: 0), in: core)

        XCTAssertEqual(core.enemyStates.first { $0.id == "patrol" }?.position, GridPoint(x: 2, y: 3))
    }

    func testTwoPatrolsCanShareLoopWhenOffset() throws {
        let loopPath = [
            GridPoint(x: 1, y: 2),
            GridPoint(x: 2, y: 2),
            GridPoint(x: 3, y: 2),
            GridPoint(x: 3, y: 3),
            GridPoint(x: 2, y: 3),
            GridPoint(x: 1, y: 3)
        ]
        let first = EnemyDefinition(
            id: "patrol-a",
            name: "巡回兵",
            position: GridPoint(x: 1, y: 2),
            behavior: .patrol(path: loopPath)
        )
        let second = EnemyDefinition(
            id: "patrol-b",
            name: "巡回兵",
            position: GridPoint(x: 3, y: 3),
            behavior: .patrol(path: loopPath)
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 4,
            enemies: [first, second]
        )
        let core = makeCore(
            mode: mode,
            cards: [.straightRight2, .kingUpRight, .straightLeft2, .straightDown2, .straightRight2]
        )

        XCTAssertEqual(core.enemyPatrolMovementPreviews.map(\.next), [
            GridPoint(x: 2, y: 2),
            GridPoint(x: 2, y: 3)
        ])

        playMove(to: GridPoint(x: 2, y: 0), in: core)

        XCTAssertEqual(core.enemyStates.first { $0.id == "patrol-a" }?.position, GridPoint(x: 2, y: 2))
        XCTAssertEqual(core.enemyStates.first { $0.id == "patrol-b" }?.position, GridPoint(x: 2, y: 3))
    }

    func testPatrolRailPreviewExposesFullValidPatrolPath() throws {
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
        let core = makeCore(mode: mode)

        XCTAssertEqual(
            core.enemyPatrolRailPreviews,
            [
                EnemyPatrolRailPreview(
                    enemyID: "patrol",
                    path: [
                        GridPoint(x: 1, y: 1),
                        GridPoint(x: 2, y: 1),
                        GridPoint(x: 3, y: 1)
                    ]
                )
            ]
        )
    }

    func testPatrolRailPreviewFiltersInvalidTilesAndRequiresCurrentPathPosition() throws {
        let patrol = EnemyDefinition(
            id: "patrol",
            name: "巡回兵",
            position: GridPoint(x: 1, y: 1),
            behavior: .patrol(path: [
                GridPoint(x: 1, y: 1),
                GridPoint(x: 2, y: 1),
                GridPoint(x: 3, y: 1),
                GridPoint(x: 6, y: 1)
            ])
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 4,
            enemies: [patrol],
            impassableTilePoints: [GridPoint(x: 3, y: 1)]
        )
        let core = makeCore(mode: mode)

        XCTAssertEqual(
            core.enemyPatrolRailPreviews,
            [
                EnemyPatrolRailPreview(
                    enemyID: "patrol",
                    path: [
                        GridPoint(x: 1, y: 1),
                        GridPoint(x: 2, y: 1)
                    ]
                )
            ]
        )

        playMove(to: GridPoint(x: 0, y: 1), in: core)

        XCTAssertEqual(
            core.enemyPatrolRailPreviews,
            [
                EnemyPatrolRailPreview(
                    enemyID: "patrol",
                    path: [
                        GridPoint(x: 1, y: 1),
                        GridPoint(x: 2, y: 1)
                    ]
                )
            ]
        )
    }

    func testPatrolRailPreviewStaysVisibleWhenPatrolRecoversFromOffPathPosition() throws {
        let patrol = EnemyDefinition(
            id: "patrol",
            name: "巡回兵",
            position: GridPoint(x: 4, y: 1),
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
        let core = makeCore(mode: mode)

        XCTAssertEqual(
            core.enemyPatrolRailPreviews,
            [
                EnemyPatrolRailPreview(
                    enemyID: "patrol",
                    path: [
                        GridPoint(x: 1, y: 1),
                        GridPoint(x: 2, y: 1),
                        GridPoint(x: 3, y: 1)
                    ]
                )
            ]
        )
        XCTAssertEqual(core.enemyPatrolMovementPreviews.first?.next, GridPoint(x: 3, y: 1))
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
        XCTAssertTrue(core.enemyPatrolRailPreviews.isEmpty)
    }

    func testCrackedBrittleFloorCollapsesThenFallsOnReentry() throws {
        let brittlePoint = GridPoint(x: 1, y: 0)
        let runState = DungeonRunState(
            dungeonID: "test-tower",
            currentFloorIndex: 1,
            carriedHP: 3
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            hazards: [.brittleFloor(points: [brittlePoint])],
            runState: runState
        )
        let core = makeCore(
            mode: mode,
            cards: [
                .straightRight2, .straightLeft2, .kingUpRight, .straightDown2, .straightRight2,
                .straightLeft2, .straightRight2, .kingUpRight, .straightDown2, .straightRight2,
                .straightRight2, .kingUpRight, .straightLeft2, .straightDown2, .straightRight2
            ]
        )

        XCTAssertTrue(core.crackedFloorPoints.contains(brittlePoint))
        XCTAssertFalse(core.collapsedFloorPoints.contains(brittlePoint))

        playMove(to: brittlePoint, in: core)

        XCTAssertFalse(core.crackedFloorPoints.contains(brittlePoint))
        XCTAssertTrue(core.collapsedFloorPoints.contains(brittlePoint))
        XCTAssertEqual(core.dungeonHP, 3)
        XCTAssertNil(core.dungeonFallEvent)

        playMove(to: GridPoint(x: 0, y: 0), in: core)
        playMove(to: brittlePoint, in: core)

        XCTAssertEqual(core.dungeonHP, 2)
        XCTAssertEqual(core.dungeonFallEvent?.point, brittlePoint)
        XCTAssertEqual(core.dungeonFallEvent?.sourceFloorIndex, 1)
        XCTAssertEqual(core.dungeonFallEvent?.destinationFloorIndex, 0)
    }

    func testHiddenWeakFloorCollapsesWithoutImmediateFall() throws {
        let hiddenPoint = GridPoint(x: 1, y: 0)
        let runState = DungeonRunState(
            dungeonID: "test-tower",
            currentFloorIndex: 1,
            carriedHP: 3
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            hazards: [.brittleFloor(points: [hiddenPoint], initialState: .hiddenWeak)],
            allowsBasicOrthogonalMove: true,
            runState: runState
        )
        let core = makeCore(mode: mode)

        XCTAssertFalse(core.crackedFloorPoints.contains(hiddenPoint))
        XCTAssertFalse(core.collapsedFloorPoints.contains(hiddenPoint))

        playBasicMove(to: hiddenPoint, in: core)

        XCTAssertFalse(core.crackedFloorPoints.contains(hiddenPoint))
        XCTAssertTrue(core.collapsedFloorPoints.contains(hiddenPoint))
        XCTAssertEqual(core.dungeonHP, 3)
        XCTAssertNil(core.dungeonFallEvent)
    }

    func testInitialCollapsedFloorFallsImmediately() throws {
        let collapsedPoint = GridPoint(x: 1, y: 0)
        let runState = DungeonRunState(
            dungeonID: "test-tower",
            currentFloorIndex: 1,
            carriedHP: 3
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            hazards: [.brittleFloor(points: [collapsedPoint], initialState: .collapsed)],
            allowsBasicOrthogonalMove: true,
            runState: runState
        )
        let core = makeCore(mode: mode)

        XCTAssertTrue(core.collapsedFloorPoints.contains(collapsedPoint))

        playBasicMove(to: collapsedPoint, in: core)

        XCTAssertEqual(core.dungeonHP, 2)
        XCTAssertEqual(core.dungeonFallEvent?.point, collapsedPoint)
        XCTAssertEqual(core.dungeonFallEvent?.sourceFloorIndex, 1)
        XCTAssertEqual(core.dungeonFallEvent?.destinationFloorIndex, 0)
    }

    func testFallenLandingOnCrackedBrittleFloorCollapsesAndStops() throws {
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

        XCTAssertFalse(core.crackedFloorPoints.contains(landingPoint))
        XCTAssertTrue(core.collapsedFloorPoints.contains(landingPoint))
        XCTAssertNil(core.dungeonFallEvent)
        XCTAssertEqual(core.dungeonHP, 2)
    }

    func testFallenLandingOnEnemyDangerOnlyAppliesFallDamage() throws {
        let landingPoint = GridPoint(x: 1, y: 1)
        let watcher = EnemyDefinition(
            id: "watcher",
            name: "見張り",
            position: GridPoint(x: 1, y: 0),
            behavior: .watcher(direction: MoveVector(dx: 0, dy: 1), range: 3)
        )
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
            enemies: [watcher],
            hazards: [.brittleFloor(points: [landingPoint])],
            allowsBasicOrthogonalMove: true,
            runState: runState
        )
        let core = makeCore(mode: mode)

        XCTAssertTrue(core.enemyDangerPoints.contains(landingPoint))

        core.resolvePendingDungeonFallLandingIfNeeded()

        XCTAssertFalse(core.crackedFloorPoints.contains(landingPoint))
        XCTAssertTrue(core.collapsedFloorPoints.contains(landingPoint))
        XCTAssertNil(core.dungeonFallEvent)
        XCTAssertEqual(core.dungeonHP, 2)
        XCTAssertEqual(core.progress, .playing)
    }

    func testFallenLandingOnAlreadyCollapsedFloorFallsAgain() throws {
        let landingPoint = GridPoint(x: 1, y: 0)
        let runState = DungeonRunState(
            dungeonID: "test-tower",
            currentFloorIndex: 1,
            carriedHP: 2,
            collapsedFloorPointsByFloor: [1: [landingPoint]],
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
        XCTAssertEqual(core.dungeonFallEvent?.destinationFloorIndex, 0)
    }

    func testBrittleFloorFallOnFirstFloorFailsWithoutPreviousFloorEvent() throws {
        let brittlePoint = GridPoint(x: 1, y: 0)
        let runState = DungeonRunState(
            dungeonID: "test-tower",
            currentFloorIndex: 0,
            carriedHP: 2
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 2,
            turnLimit: 8,
            hazards: [.brittleFloor(points: [brittlePoint])],
            allowsBasicOrthogonalMove: true,
            runState: runState
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: brittlePoint, in: core)
        playBasicMove(to: GridPoint(x: 0, y: 0), in: core)
        playBasicMove(to: brittlePoint, in: core)

        XCTAssertEqual(core.dungeonHP, 1)
        XCTAssertEqual(core.progress, .failed)
        XCTAssertNil(core.dungeonFallEvent)
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
            cards: [.straightRight2, .straightLeft2, .straightRight2, .kingUpRight, .straightDown2]
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
            hazards: [.damageTrap(points: [trapPoint], damage: 1)]
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: trapPoint, in: core)

        XCTAssertEqual(core.dungeonHP, 2)
        XCTAssertEqual(core.progress, .playing)
        XCTAssertTrue(core.damageTrapPoints.isEmpty)
        XCTAssertEqual(core.consumedDamageTrapPoints, [trapPoint])

        playBasicMove(to: GridPoint(x: 0, y: 0), in: core)
        playBasicMove(to: trapPoint, in: core)

        XCTAssertEqual(core.dungeonHP, 2)
    }

    func testDamageTrapIsConsumedWhenBarrierBlocksDamage() throws {
        let trapPoint = GridPoint(x: 1, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            hazards: [.damageTrap(points: [trapPoint], damage: 2)]
        )
        let core = makeCore(mode: mode)
        core.overrideDamageBarrierTurnsRemainingForTesting(1)

        playBasicMove(to: trapPoint, in: core)

        XCTAssertEqual(core.dungeonHP, 3)
        XCTAssertTrue(core.damageTrapPoints.isEmpty)
        XCTAssertEqual(core.consumedDamageTrapPoints, [trapPoint])
    }

    func testHpHalvingTrapReducesHighHPWithoutImmediateFailure() throws {
        let trapPoint = GridPoint(x: 1, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 10,
            turnLimit: 8,
            hazards: [.hpHalvingTrap(points: [trapPoint])]
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: trapPoint, in: core)

        XCTAssertEqual(core.dungeonHP, 5)
        XCTAssertEqual(core.progress, .playing)
        XCTAssertEqual(core.hpHalvingTrapPoints, [trapPoint])
    }

    func testHpHalvingTrapLeavesLowHPPlayable() throws {
        let trapPoint = GridPoint(x: 1, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            hazards: [.hpHalvingTrap(points: [trapPoint])]
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: trapPoint, in: core)

        XCTAssertEqual(core.dungeonHP, 2)
        XCTAssertEqual(core.progress, .playing)

        let oneHPMode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 1,
            turnLimit: 8,
            hazards: [.hpHalvingTrap(points: [trapPoint])]
        )
        let oneHPCore = makeCore(mode: oneHPMode)

        playBasicMove(to: trapPoint, in: oneHPCore)

        XCTAssertEqual(oneHPCore.dungeonHP, 1)
        XCTAssertEqual(oneHPCore.progress, .playing)
    }

    func testHpHalvingTrapUsesTrapDamageMitigation() throws {
        let trapPoint = GridPoint(x: 1, y: 0)
        let silverNeedleMode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 10,
            turnLimit: 8,
            hazards: [.hpHalvingTrap(points: [trapPoint])],
            allowsBasicOrthogonalMove: true,
            runState: DungeonRunState(
                dungeonID: "growth-tower",
                carriedHP: 10,
                relicEntries: [DungeonRelicEntry(relicID: .silverNeedle)]
            )
        )
        let silverNeedleCore = makeCore(mode: silverNeedleMode)

        playBasicMove(to: trapPoint, in: silverNeedleCore)

        XCTAssertEqual(silverNeedleCore.dungeonHP, 10)
        XCTAssertEqual(silverNeedleCore.dungeonRelicEntries.first { $0.relicID == DungeonRelicID.silverNeedle }?.remainingUses, 0)

        let trapSoleMode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 10,
            turnLimit: 8,
            hazards: [.hpHalvingTrap(points: [trapPoint])],
            allowsBasicOrthogonalMove: true,
            runState: DungeonRunState(
                dungeonID: "growth-tower",
                carriedHP: 10,
                relicEntries: [DungeonRelicEntry(relicID: .trapSole)]
            )
        )
        let trapSoleCore = makeCore(mode: trapSoleMode)

        playBasicMove(to: trapPoint, in: trapSoleCore)

        XCTAssertEqual(trapSoleCore.dungeonHP, 6)
    }

    func testHpHalvingTrapDamageIsBlockedByBarrier() throws {
        let trapPoint = GridPoint(x: 1, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 10,
            turnLimit: 8,
            hazards: [.hpHalvingTrap(points: [trapPoint])]
        )
        let core = makeCore(mode: mode)
        core.overrideDamageBarrierTurnsRemainingForTesting(1)

        playBasicMove(to: trapPoint, in: core)

        XCTAssertEqual(core.dungeonHP, 10)
        XCTAssertEqual(core.progress, .playing)
    }

    func testRayMoveContinuesAfterHpHalvingTrap() throws {
        let trapPoint = GridPoint(x: 1, y: 0)
        let laterPoint = GridPoint(x: 2, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 10,
            turnLimit: 8,
            hazards: [.hpHalvingTrap(points: [trapPoint])]
        )
        let core = makeCore(mode: mode, cards: [.rayRight, .kingUpRight, .straightRight2, .straightLeft2, .straightDown2])

        playMove(to: GridPoint(x: 4, y: 0), in: core)

        XCTAssertEqual(core.progress, .playing)
        XCTAssertEqual(core.dungeonHP, 5)
        XCTAssertEqual(core.current, GridPoint(x: 4, y: 0))
        XCTAssertTrue(core.board.isVisited(laterPoint))
        XCTAssertEqual(core.lastMovementResolution?.presentationSteps.first?.hpAfter, 5)
        XCTAssertEqual(core.lastMovementResolution?.presentationSteps.first?.tookDamage, true)
    }

    func testLavaTileDamagesPlayerWhenSteppedOn() throws {
        let lavaPoint = GridPoint(x: 1, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            hazards: [.lavaTile(points: [lavaPoint], damage: 1)]
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: lavaPoint, in: core)

        XCTAssertEqual(core.dungeonHP, 1)
        XCTAssertEqual(core.progress, .playing)
        XCTAssertEqual(core.lavaTilePoints, [lavaPoint])
    }

    func testLavaTileHazardCodingRoundTrip() throws {
        let hazard = HazardDefinition.lavaTile(points: [GridPoint(x: 1, y: 2)], damage: 2)
        let data = try JSONEncoder().encode(hazard)
        let decoded = try JSONDecoder().decode(HazardDefinition.self, from: data)

        XCTAssertEqual(decoded, hazard)
    }

    func testDiscardRandomHandTrapRemovesOneHandSlotWithoutRefill() throws {
        let trapPoint = GridPoint(x: 1, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            tileEffectOverrides: [trapPoint: .discardRandomHand]
        )
        let core = makeCore(mode: mode)
        let initialHandCount = core.handStacks.count
        let initialNextCards = core.nextCards

        playBasicMove(to: trapPoint, in: core)

        XCTAssertEqual(core.handStacks.count, initialHandCount - 1)
        XCTAssertEqual(core.nextCards, initialNextCards)
        XCTAssertEqual(core.progress, .playing)
        XCTAssertTrue(core.lastMovementResolution?.appliedEffects.contains { $0.point == trapPoint && $0.effect == .discardRandomHand } == true)
    }

    func testDiscardAllHandsTrapClearsHandWithoutChangingNextCards() throws {
        let trapPoint = GridPoint(x: 1, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            tileEffectOverrides: [trapPoint: .discardAllHands]
        )
        let core = makeCore(mode: mode)
        let initialNextCards = core.nextCards

        playBasicMove(to: trapPoint, in: core)

        XCTAssertTrue(core.handStacks.isEmpty)
        XCTAssertEqual(core.nextCards, initialNextCards)
        XCTAssertEqual(core.progress, .playing)
    }

    func testDiscardRandomHandTrapRemovesOneInventorySlot() throws {
        let trapPoint = GridPoint(x: 1, y: 0)
        let runState = DungeonRunState(
            dungeonID: "discard-random-test",
            carriedHP: 3,
            rewardInventoryEntries: [
                DungeonInventoryEntry(card: .straightRight2, rewardUses: 2),
                DungeonInventoryEntry(card: .straightUp2, rewardUses: 1),
                DungeonInventoryEntry(card: .rayRight, rewardUses: 1),
            ],
            cardVariationSeed: 42
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            tileEffectOverrides: [trapPoint: .discardRandomHand],
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            runState: runState
        )
        let core = makeCore(mode: mode)
        let initialInventoryCount = core.dungeonInventoryEntries.filter(\.hasUsesRemaining).count

        playBasicMove(to: trapPoint, in: core)

        XCTAssertEqual(core.dungeonInventoryEntries.filter(\.hasUsesRemaining).count, initialInventoryCount - 1)
        XCTAssertEqual(core.handStacks.count, initialInventoryCount - 1)
        XCTAssertEqual(core.nextCards, [])
        XCTAssertEqual(core.progress, .playing)
    }

    func testDiscardAllHandsTrapRemovesAllInventorySlots() throws {
        let trapPoint = GridPoint(x: 1, y: 0)
        let runState = DungeonRunState(
            dungeonID: "discard-all-test",
            carriedHP: 3,
            rewardInventoryEntries: [
                DungeonInventoryEntry(card: .straightRight2, rewardUses: 2),
                DungeonInventoryEntry(card: .straightUp2, rewardUses: 1),
            ],
            cardVariationSeed: 43
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            tileEffectOverrides: [trapPoint: .discardAllHands],
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            runState: runState
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: trapPoint, in: core)

        XCTAssertTrue(core.dungeonInventoryEntries.filter(\.hasUsesRemaining).isEmpty)
        XCTAssertTrue(core.handStacks.isEmpty)
        XCTAssertEqual(core.progress, .playing)
        XCTAssertFalse(core.availableBasicOrthogonalMoves().isEmpty)
    }

    func testDiscardAllMoveCardsTrapKeepsSupportInventorySlots() throws {
        let trapPoint = GridPoint(x: 1, y: 0)
        let runState = DungeonRunState(
            dungeonID: "discard-move-test",
            carriedHP: 3,
            rewardInventoryEntries: [
                DungeonInventoryEntry(card: .straightRight2, rewardUses: 2),
                DungeonInventoryEntry(card: .straightUp2, rewardUses: 1),
                DungeonInventoryEntry(support: .refillEmptySlots, rewardUses: 1),
            ],
            cardVariationSeed: 44
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            tileEffectOverrides: [trapPoint: .discardAllMoveCards],
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            runState: runState
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: trapPoint, in: core)

        XCTAssertFalse(core.dungeonInventoryEntries.contains { $0.moveCard != nil && $0.hasUsesRemaining })
        XCTAssertEqual(core.dungeonInventoryEntries.filter { $0.supportCard != nil && $0.hasUsesRemaining }, [
            DungeonInventoryEntry(support: .refillEmptySlots, rewardUses: 1)
        ])
        XCTAssertEqual(core.handStacks.compactMap(\.representativeSupport), [.refillEmptySlots])
        XCTAssertEqual(core.progress, .playing)
    }

    func testDiscardAllSupportCardsTrapKeepsMoveInventorySlots() throws {
        let trapPoint = GridPoint(x: 1, y: 0)
        let runState = DungeonRunState(
            dungeonID: "discard-support-test",
            carriedHP: 3,
            rewardInventoryEntries: [
                DungeonInventoryEntry(card: .straightRight2, rewardUses: 2),
                DungeonInventoryEntry(support: .refillEmptySlots, rewardUses: 1),
                DungeonInventoryEntry(support: .annihilationSpell, rewardUses: 1),
            ],
            cardVariationSeed: 45
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            tileEffectOverrides: [trapPoint: .discardAllSupportCards],
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            runState: runState
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: trapPoint, in: core)

        XCTAssertFalse(core.dungeonInventoryEntries.contains { $0.supportCard != nil && $0.hasUsesRemaining })
        XCTAssertEqual(core.dungeonInventoryEntries.filter { $0.moveCard != nil && $0.hasUsesRemaining }, [
            DungeonInventoryEntry(card: .straightRight2, rewardUses: 2)
        ])
        XCTAssertEqual(core.handStacks.compactMap(\.representativeMove), [.straightRight2])
        XCTAssertEqual(core.progress, .playing)
    }

    func testDiscardAllHandsTrapOverridesCategoryDiscardOnSameMove() throws {
        let moveTrapPoint = GridPoint(x: 1, y: 0)
        let allTrapPoint = GridPoint(x: 2, y: 0)
        let runState = DungeonRunState(
            dungeonID: "discard-priority-test",
            carriedHP: 3,
            rewardInventoryEntries: [
                DungeonInventoryEntry(card: .rayRight, rewardUses: 1),
                DungeonInventoryEntry(support: .refillEmptySlots, rewardUses: 1),
            ],
            cardVariationSeed: 46
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            tileEffectOverrides: [
                moveTrapPoint: .discardAllMoveCards,
                allTrapPoint: .discardAllHands,
            ],
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            runState: runState
        )
        let core = makeCore(mode: mode)

        playMove(to: GridPoint(x: 4, y: 0), in: core)

        XCTAssertTrue(core.dungeonInventoryEntries.filter(\.hasUsesRemaining).isEmpty)
        XCTAssertTrue(core.handStacks.isEmpty)
        XCTAssertTrue(core.lastMovementResolution?.appliedEffects.contains { $0.point == moveTrapPoint && $0.effect == .discardAllMoveCards } == true)
        XCTAssertTrue(core.lastMovementResolution?.appliedEffects.contains { $0.point == allTrapPoint && $0.effect == .discardAllHands } == true)
        XCTAssertEqual(core.progress, .playing)
    }

    func testMoveAndSupportDiscardTrapsCombineOnSameMove() throws {
        let moveTrapPoint = GridPoint(x: 1, y: 0)
        let supportTrapPoint = GridPoint(x: 2, y: 0)
        let runState = DungeonRunState(
            dungeonID: "discard-combine-test",
            carriedHP: 3,
            rewardInventoryEntries: [
                DungeonInventoryEntry(card: .rayRight, rewardUses: 1),
                DungeonInventoryEntry(support: .refillEmptySlots, rewardUses: 1),
            ],
            cardVariationSeed: 47
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            tileEffectOverrides: [
                moveTrapPoint: .discardAllMoveCards,
                supportTrapPoint: .discardAllSupportCards,
            ],
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            runState: runState
        )
        let core = makeCore(mode: mode)

        playMove(to: GridPoint(x: 4, y: 0), in: core)

        XCTAssertTrue(core.dungeonInventoryEntries.filter(\.hasUsesRemaining).isEmpty)
        XCTAssertTrue(core.handStacks.isEmpty)
        XCTAssertTrue(core.lastMovementResolution?.appliedEffects.contains { $0.point == moveTrapPoint && $0.effect == .discardAllMoveCards } == true)
        XCTAssertTrue(core.lastMovementResolution?.appliedEffects.contains { $0.point == supportTrapPoint && $0.effect == .discardAllSupportCards } == true)
        XCTAssertEqual(core.progress, .playing)
    }

    func testRelicBreakTrapRemovesOneRelicAndDoesNotCarryItToNextFloor() throws {
        let trapPoint = GridPoint(x: 1, y: 0)
        let runState = DungeonRunState(
            dungeonID: "relic-break-test",
            carriedHP: 3,
            relicEntries: [
                DungeonRelicEntry(relicID: .heavyCrown),
                DungeonRelicEntry(relicID: .starCup)
            ],
            cardVariationSeed: 101
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            tileEffectOverrides: [trapPoint: .relicBreakTrap],
            runState: runState
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: trapPoint, in: core)

        XCTAssertEqual(core.dungeonRelicEntries.count, 1)
        let removedRelics = Set(runState.relicEntries.map(\.relicID)).subtracting(core.dungeonRelicEntries.map(\.relicID))
        XCTAssertEqual(removedRelics.count, 1)

        let nextState = runState.advancedToNextFloor(
            carryoverHP: core.dungeonHP,
            currentFloorMoveCount: core.moveCount,
            currentRelicEntries: core.dungeonRelicEntries,
            currentCurseEntries: core.dungeonCurseEntries
        )
        XCTAssertTrue(nextState.relicEntries.map(\.relicID).allSatisfy { !removedRelics.contains($0) })
    }

    func testRelicBreakTrapCanRemoveCurseWhenOnlyCurseIsOwned() throws {
        let trapPoint = GridPoint(x: 1, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            tileEffectOverrides: [trapPoint: .relicBreakTrap],
            runState: DungeonRunState(
                dungeonID: "relic-break-curse-test",
                carriedHP: 3,
                curseEntries: [DungeonCurseEntry(curseID: .bloodPact)],
                cardVariationSeed: 102
            )
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: trapPoint, in: core)

        XCTAssertTrue(core.dungeonCurseEntries.isEmpty)
        XCTAssertEqual(core.progress, .playing)
        XCTAssertTrue(core.dungeonRunLogEntries.contains { $0.message.contains("呪い「血の契約」") })
    }

    func testRelicBreakTrapDestroysPurifyingCharmFirstAsDecoy() throws {
        let trapPoint = GridPoint(x: 1, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            tileEffectOverrides: [trapPoint: .relicBreakTrap],
            runState: DungeonRunState(
                dungeonID: "relic-break-charm-test",
                carriedHP: 3,
                relicEntries: [
                    DungeonRelicEntry(relicID: .heavyCrown),
                    DungeonRelicEntry(relicID: .purifyingCharm)
                ],
                curseEntries: [DungeonCurseEntry(curseID: .bloodPact)],
                cardVariationSeed: 103
            )
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: trapPoint, in: core)

        XCTAssertEqual(core.dungeonRelicEntries.map(\.relicID), [.heavyCrown])
        XCTAssertEqual(core.dungeonCurseEntries.map(\.curseID), [.bloodPact])
        XCTAssertTrue(core.dungeonRunLogEntries.contains { $0.message.contains("清めの護符が身代わり") })
    }

    func testRelicBreakTrapWithoutTargetsKeepsRunPlaying() throws {
        let trapPoint = GridPoint(x: 1, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            tileEffectOverrides: [trapPoint: .relicBreakTrap]
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: trapPoint, in: core)

        XCTAssertTrue(core.dungeonRelicEntries.isEmpty)
        XCTAssertTrue(core.dungeonCurseEntries.isEmpty)
        XCTAssertEqual(core.progress, .playing)
        XCTAssertTrue(core.dungeonRunLogEntries.contains { $0.message.contains("壊れるレリック/呪いなし") })
    }

    func testRayMoveTriggersRelicBreakTrapWithoutStopping() throws {
        let trapPoint = GridPoint(x: 1, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            tileEffectOverrides: [trapPoint: .relicBreakTrap],
            runState: DungeonRunState(
                dungeonID: "relic-break-ray-test",
                carriedHP: 3,
                relicEntries: [DungeonRelicEntry(relicID: .heavyCrown)],
                cardVariationSeed: 104
            )
        )
        let core = makeCore(mode: mode, cards: [.rayRight, .kingUpRight, .straightRight2, .straightLeft2, .straightDown2])

        playMove(to: GridPoint(x: 4, y: 0), in: core)

        XCTAssertEqual(core.current, GridPoint(x: 4, y: 0))
        XCTAssertTrue(core.dungeonRelicEntries.isEmpty)
        XCTAssertTrue(core.lastMovementResolution?.appliedEffects.contains { $0.point == trapPoint && $0.effect == .relicBreakTrap } == true)
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
        let core = makeCore(mode: mode, cards: [.rayRight, .kingUpRight, .straightRight2, .straightLeft2, .straightDown2])

        playMove(to: GridPoint(x: 4, y: 0), in: core)

        XCTAssertEqual(core.dungeonHP, 1, "レイ型カードの途中にある罠をどちらも踏む想定です")
        XCTAssertEqual(core.progress, .playing)
        let steps = try XCTUnwrap(core.lastMovementResolution?.presentationSteps)
        XCTAssertEqual(
            steps.map(\.hpAfter),
            [2, 1, 1, 1],
            "レイ型の表示ステップは通過マスごとの罠ダメージを順に保持します"
        )
        XCTAssertEqual(steps[0].boardAfter?.isVisited(GridPoint(x: 1, y: 0)), true)
        XCTAssertEqual(steps[0].boardAfter?.isVisited(GridPoint(x: 2, y: 0)), false)
        XCTAssertEqual(steps[1].boardAfter?.isVisited(GridPoint(x: 2, y: 0)), true)
        XCTAssertEqual(core.lastMovementResolution?.presentationInitialBoard?.isVisited(GridPoint(x: 1, y: 0)), false)
    }

    func testLavaTileDamagesCardMoveIntermediatePoints() throws {
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            hazards: [.lavaTile(points: [GridPoint(x: 1, y: 0), GridPoint(x: 2, y: 0)], damage: 1)]
        )
        let core = makeCore(mode: mode, cards: [.rayRight, .kingUpRight, .straightRight2, .straightLeft2, .straightDown2])

        playMove(to: GridPoint(x: 4, y: 0), in: core)

        XCTAssertEqual(core.dungeonHP, 0)
        XCTAssertEqual(core.progress, .failed)
        XCTAssertEqual(core.lastMovementResolution?.presentationSteps.map(\.hpAfter), [1, 0])
    }

    func testLeavingLavaDoesNotApplyExtraWaitDamage() throws {
        let lavaPoint = GridPoint(x: 0, y: 0)
        let mode = makeDungeonMode(
            spawn: lavaPoint,
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            hazards: [.lavaTile(points: [lavaPoint], damage: 1)]
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: GridPoint(x: 1, y: 0), in: core)

        XCTAssertEqual(core.dungeonHP, 3)
        XCTAssertEqual(core.progress, .playing)
    }

    func testRefillSupportOnLavaTakesWaitDamageAndAdvancesEnemyTurn() throws {
        let lavaPoint = GridPoint(x: 0, y: 0)
        let patrol = EnemyDefinition(
            id: "lava-patrol",
            name: "巡回兵",
            position: GridPoint(x: 4, y: 1),
            behavior: .patrol(path: [GridPoint(x: 4, y: 1), GridPoint(x: 4, y: 2)])
        )
        let runState = DungeonRunState(
            dungeonID: "lava-support-test",
            carriedHP: 3,
            rewardInventoryEntries: [DungeonInventoryEntry(support: .refillEmptySlots, rewardUses: 1)]
        )
        let mode = makeDungeonMode(
            spawn: lavaPoint,
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            enemies: [patrol],
            hazards: [.lavaTile(points: [lavaPoint], damage: 1)],
            cardAcquisitionMode: .inventoryOnly,
            runState: runState
        )
        let core = makeCore(mode: mode)
        let supportIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.topCard?.supportCard == .refillEmptySlots })

        core.playSupportCard(at: supportIndex)

        XCTAssertEqual(core.dungeonHP, 1)
        XCTAssertEqual(core.enemyStates.first?.position, GridPoint(x: 4, y: 2))
        XCTAssertEqual(core.moveCount, 1)
        XCTAssertEqual(core.progress, .playing)
    }

    func testTargetedSupportOnLavaResolvesEffectThenLavaAndEnemyTurn() throws {
        let lavaPoint = GridPoint(x: 0, y: 0)
        let target = EnemyDefinition(id: "target", name: "番兵", position: GridPoint(x: 1, y: 0), behavior: .guardPost)
        let patrol = EnemyDefinition(
            id: "patrol",
            name: "巡回兵",
            position: GridPoint(x: 4, y: 1),
            behavior: .patrol(path: [GridPoint(x: 4, y: 1), GridPoint(x: 4, y: 2)])
        )
        let runState = DungeonRunState(
            dungeonID: "lava-target-support-test",
            carriedHP: 3,
            rewardInventoryEntries: [DungeonInventoryEntry(support: .singleAnnihilationSpell, rewardUses: 1)]
        )
        let mode = makeDungeonMode(
            spawn: lavaPoint,
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            enemies: [target, patrol],
            hazards: [.lavaTile(points: [lavaPoint], damage: 1)],
            cardAcquisitionMode: .inventoryOnly,
            runState: runState
        )
        let core = makeCore(mode: mode)
        let supportIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.topCard?.supportCard == .singleAnnihilationSpell })

        XCTAssertTrue(core.beginTargetedSupportCardSelection(at: supportIndex))
        XCTAssertTrue(core.playTargetedSupportCard(at: target.position))

        XCTAssertEqual(core.dungeonHP, 1)
        XCTAssertEqual(core.enemyStates.map(\.id), ["patrol"])
        XCTAssertEqual(core.enemyStates.first?.position, GridPoint(x: 4, y: 2))
        XCTAssertEqual(core.progress, .playing)
    }

    func testAnnihilationSupportOnLavaCanFailBeforeEnemyTurn() throws {
        let lavaPoint = GridPoint(x: 0, y: 0)
        let enemy = EnemyDefinition(id: "guard", name: "番兵", position: GridPoint(x: 1, y: 0), behavior: .guardPost)
        let runState = DungeonRunState(
            dungeonID: "lava-fail-support-test",
            carriedHP: 1,
            rewardInventoryEntries: [DungeonInventoryEntry(support: .annihilationSpell, rewardUses: 1)]
        )
        let mode = makeDungeonMode(
            spawn: lavaPoint,
            exit: GridPoint(x: 4, y: 4),
            hp: 1,
            turnLimit: 8,
            enemies: [enemy],
            hazards: [.lavaTile(points: [lavaPoint], damage: 1)],
            cardAcquisitionMode: .inventoryOnly,
            runState: runState
        )
        let core = makeCore(mode: mode)
        let supportIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.topCard?.supportCard == .annihilationSpell })

        core.playSupportCard(at: supportIndex)

        XCTAssertTrue(core.enemyStates.isEmpty)
        XCTAssertEqual(core.dungeonHP, 0)
        XCTAssertEqual(core.progress, .failed)
        XCTAssertNil(core.dungeonEnemyTurnEvent)
    }

    func testHealingTileRestoresOneHPWhenSteppedOn() throws {
        let healingPoint = GridPoint(x: 1, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 2,
            turnLimit: 8,
            hazards: [.healingTile(points: [healingPoint], amount: 1)]
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: healingPoint, in: core)

        XCTAssertEqual(core.dungeonHP, 3)
        XCTAssertEqual(core.progress, .playing)
        XCTAssertTrue(core.healingTilePoints.isEmpty)
        XCTAssertEqual(core.consumedHealingTilePoints, [healingPoint])
    }

    func testHealingTileCanIncreaseHPBeyondInitialHPOnlyOnce() throws {
        let healingPoint = GridPoint(x: 1, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            hazards: [.healingTile(points: [healingPoint], amount: 1)]
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: healingPoint, in: core)

        XCTAssertEqual(core.dungeonHP, 4)
        playBasicMove(to: GridPoint(x: 0, y: 0), in: core)
        playBasicMove(to: healingPoint, in: core)

        XCTAssertEqual(core.dungeonHP, 4)
        XCTAssertTrue(core.healingTilePoints.isEmpty)
        XCTAssertEqual(core.progress, .playing)
    }

    func testConsumedHealingTileStateRestoresFromResumeSnapshot() throws {
        let healingPoint = GridPoint(x: 1, y: 0)
        let runState = DungeonRunState(dungeonID: "test-dungeon", carriedHP: 2)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 2,
            turnLimit: 8,
            hazards: [.healingTile(points: [healingPoint], amount: 1)],
            allowsBasicOrthogonalMove: true,
            runState: runState
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: healingPoint, in: core)
        let snapshot = try XCTUnwrap(core.makeDungeonResumeSnapshot())
        let restoredCore = makeCore(mode: makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 2,
            turnLimit: 8,
            hazards: [.healingTile(points: [healingPoint], amount: 1)],
            allowsBasicOrthogonalMove: true,
            runState: runState
        ))

        XCTAssertTrue(restoredCore.restoreDungeonResumeSnapshot(snapshot))
        XCTAssertEqual(restoredCore.dungeonHP, 3)
        XCTAssertEqual(restoredCore.consumedHealingTilePoints, [healingPoint])
        XCTAssertTrue(restoredCore.healingTilePoints.isEmpty)
    }

    func testHealingTileAppliesOnIntermediateCardMoveAndDoesNotStopMovement() throws {
        let healingPoint = GridPoint(x: 1, y: 0)
        let pickup = DungeonCardPickupDefinition(
            id: "post-heal-pickup",
            point: GridPoint(x: 2, y: 0),
            card: .rayLeft
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 2,
            turnLimit: 8,
            hazards: [.healingTile(points: [healingPoint], amount: 1)],
            cardAcquisitionMode: .inventoryOnly,
            cardPickups: [pickup]
        )
        let core = makeCore(mode: mode, cards: [.rayRight, .kingUpRight, .straightRight2, .straightLeft2, .straightDown2])
        XCTAssertTrue(core.addDungeonInventoryCardForTesting(.rayRight, pickupUses: 1))

        playMove(to: GridPoint(x: 4, y: 0), in: core)

        XCTAssertEqual(core.current, GridPoint(x: 4, y: 0))
        XCTAssertEqual(core.dungeonHP, 3)
        XCTAssertTrue(core.collectedDungeonCardPickupIDs.contains(pickup.id))
        XCTAssertEqual(core.progress, .playing)
    }

    func testRayMoveStopsAtIntermediateTrapWhenHPReachesZero() throws {
        let trapPoint = GridPoint(x: 1, y: 0)
        let laterPoint = GridPoint(x: 2, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 1,
            turnLimit: 8,
            hazards: [.damageTrap(points: [trapPoint, laterPoint], damage: 1)]
        )
        let core = makeCore(mode: mode, cards: [.rayRight, .kingUpRight, .straightRight2, .straightLeft2, .straightDown2])

        playMove(to: GridPoint(x: 4, y: 0), in: core)

        XCTAssertEqual(core.progress, .failed)
        XCTAssertEqual(core.dungeonHP, 0)
        XCTAssertEqual(core.current, trapPoint)
        XCTAssertEqual(core.lastMovementResolution?.path, [trapPoint])
        XCTAssertEqual(core.lastMovementResolution?.presentationSteps.map(\.point), [trapPoint])
        XCTAssertEqual(core.lastMovementResolution?.presentationSteps.first?.hpAfter, 0)
        XCTAssertEqual(core.lastMovementResolution?.presentationSteps.first?.tookDamage, true)
        XCTAssertEqual(core.lastMovementResolution?.presentationSteps.first?.stopReason, .failed)
        XCTAssertFalse(core.board.isVisited(laterPoint), "HP 0 になった後の経路は踏まない想定です")
    }

    func testRayMoveTakesDamageWhenPassingEnemyDangerPoint() throws {
        let watcher = EnemyDefinition(
            id: "watcher",
            name: "見張り",
            position: GridPoint(x: 2, y: 1),
            behavior: .watcher(direction: MoveVector(dx: 0, dy: -1), range: 3)
        )
        let dangerPoint = GridPoint(x: 2, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            enemies: [watcher]
        )
        let core = makeCore(mode: mode, cards: [.rayRight, .kingUpRight, .straightRight2, .straightLeft2, .straightDown2])

        XCTAssertTrue(core.enemyDangerPoints.contains(dangerPoint))

        playMove(to: GridPoint(x: 4, y: 0), in: core)

        let steps = try XCTUnwrap(core.lastMovementResolution?.presentationSteps)
        XCTAssertEqual(core.dungeonHP, 2)
        XCTAssertEqual(steps.map(\.point), [
            GridPoint(x: 1, y: 0),
            dangerPoint,
            GridPoint(x: 3, y: 0),
            GridPoint(x: 4, y: 0)
        ])
        XCTAssertEqual(steps[1].hpAfter, 2)
        XCTAssertTrue(steps[1].tookDamage)
        XCTAssertNil(steps[1].stopReason)
    }

    func testRayMoveTakesDamageFromRotatingWatcherDisplayedCurrentLine() throws {
        let rotatingWatcher = EnemyDefinition(
            id: "rotating-watcher",
            name: "回転見張り",
            position: GridPoint(x: 2, y: 1),
            behavior: .rotatingWatcher(
                initialDirection: MoveVector(dx: 0, dy: 1),
                rotationDirection: .clockwise,
                range: 3
            )
        )
        let currentDangerPoint = GridPoint(x: 2, y: 2)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 2),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            enemies: [rotatingWatcher]
        )
        let core = makeCore(mode: mode, cards: [.rayRight, .kingUpRight, .straightRight2, .straightLeft2, .straightDown2])

        XCTAssertTrue(core.enemyDangerPoints.contains(currentDangerPoint))
        XCTAssertTrue(core.enemyDangerDisplayPoints.contains(currentDangerPoint))

        playMove(to: GridPoint(x: 4, y: 2), in: core)

        let steps = try XCTUnwrap(core.lastMovementResolution?.presentationSteps)
        XCTAssertEqual(core.dungeonHP, 2)
        XCTAssertTrue(steps.contains(where: \.tookDamage))
        XCTAssertEqual(steps[1].point, currentDangerPoint)
        XCTAssertEqual(steps[1].hpAfter, 2)
    }

    func testRayMoveDoesNotTakeImmediateDamageFromRotatingWatcherNextLineOutsideDisplayedDanger() throws {
        let rotatingWatcher = EnemyDefinition(
            id: "rotating-watcher",
            name: "回転見張り",
            position: GridPoint(x: 2, y: 1),
            behavior: .rotatingWatcher(
                initialDirection: MoveVector(dx: 0, dy: 1),
                rotationDirection: .clockwise,
                range: 3
            )
        )
        let displayedDangerPoint = GridPoint(x: 3, y: 1)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 3, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            enemies: [rotatingWatcher]
        )
        let core = makeCore(mode: mode, cards: [.rayUp, .kingUpRight, .straightRight2, .straightLeft2, .straightDown2])

        XCTAssertFalse(core.enemyDangerPoints.contains(displayedDangerPoint))
        XCTAssertFalse(core.enemyDangerDisplayPoints.contains(displayedDangerPoint))

        playMove(to: GridPoint(x: 3, y: 4), in: core)

        let steps = try XCTUnwrap(core.lastMovementResolution?.presentationSteps)
        XCTAssertEqual(core.dungeonHP, 3)
        XCTAssertEqual(steps.map(\.point), [
            displayedDangerPoint,
            GridPoint(x: 3, y: 2),
            GridPoint(x: 3, y: 3),
            GridPoint(x: 3, y: 4)
        ])
        XCTAssertEqual(steps[0].hpAfter, 3)
        XCTAssertFalse(steps[0].tookDamage)
        XCTAssertNil(steps[0].stopReason)
    }

    func testRayMoveStopsAtEnemyDangerWhenHPReachesZero() throws {
        let watcher = EnemyDefinition(
            id: "watcher",
            name: "見張り",
            position: GridPoint(x: 2, y: 1),
            behavior: .watcher(direction: MoveVector(dx: 0, dy: -1), range: 3)
        )
        let dangerPoint = GridPoint(x: 2, y: 0)
        let laterPoint = GridPoint(x: 3, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 1,
            turnLimit: 8,
            enemies: [watcher]
        )
        let core = makeCore(mode: mode, cards: [.rayRight, .kingUpRight, .straightRight2, .straightLeft2, .straightDown2])

        playMove(to: GridPoint(x: 4, y: 0), in: core)

        XCTAssertEqual(core.progress, .failed)
        XCTAssertEqual(core.dungeonHP, 0)
        XCTAssertEqual(core.current, dangerPoint)
        XCTAssertEqual(core.lastMovementResolution?.path, [
            GridPoint(x: 1, y: 0),
            dangerPoint
        ])
        XCTAssertEqual(core.lastMovementResolution?.presentationSteps.map(\.point), [
            GridPoint(x: 1, y: 0),
            dangerPoint
        ])
        XCTAssertEqual(core.lastMovementResolution?.presentationSteps.last?.hpAfter, 0)
        XCTAssertEqual(core.lastMovementResolution?.presentationSteps.last?.tookDamage, true)
        XCTAssertEqual(core.lastMovementResolution?.presentationSteps.last?.stopReason, .failed)
        XCTAssertFalse(core.board.isVisited(laterPoint), "敵攻撃範囲で HP 0 になった後の経路は踏まない想定です")
    }

    func testRayMoveDoesNotTakeDangerDamageFromEnemyStompedEarlierInPath() throws {
        let guardPost = EnemyDefinition(
            id: "guard",
            name: "番兵",
            position: GridPoint(x: 1, y: 0),
            behavior: .guardPost
        )
        let formerDangerPoint = GridPoint(x: 2, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            enemies: [guardPost]
        )
        let core = makeCore(mode: mode, cards: [.rayRight, .kingUpRight, .straightRight2, .straightLeft2, .straightDown2])

        XCTAssertTrue(core.enemyDangerPoints.contains(formerDangerPoint))

        playMove(to: GridPoint(x: 4, y: 0), in: core)

        let steps = try XCTUnwrap(core.lastMovementResolution?.presentationSteps)
        XCTAssertEqual(core.dungeonHP, 3)
        XCTAssertEqual(core.enemyStates.map(\.id), [])
        XCTAssertFalse(steps.contains(where: \.tookDamage))
    }

    func testRayMovePresentationStepsKeepEnemyUntilStompedStep() throws {
        let enemyPoint = GridPoint(x: 2, y: 0)
        let guardPost = EnemyDefinition(
            id: "presentation-guard",
            name: "番兵",
            position: enemyPoint,
            behavior: .guardPost
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            enemies: [guardPost]
        )
        let core = makeCore(mode: mode, cards: [.rayRight, .kingUpRight, .straightRight2, .straightLeft2, .straightDown2])

        playMove(to: GridPoint(x: 4, y: 0), in: core)

        let resolution = try XCTUnwrap(core.lastMovementResolution)
        XCTAssertEqual(resolution.presentationInitialEnemyStates?.map(\.id), [guardPost.id])
        XCTAssertEqual(resolution.presentationSteps.map(\.point), [
            GridPoint(x: 1, y: 0),
            enemyPoint,
            GridPoint(x: 3, y: 0),
            GridPoint(x: 4, y: 0)
        ])
        XCTAssertEqual(resolution.presentationSteps[0].enemyStatesAfter.map(\.id), [guardPost.id])
        XCTAssertEqual(resolution.presentationSteps[1].enemyStatesAfter.map(\.id), [])
        XCTAssertEqual(core.enemyStates.map(\.id), [])
    }

    func testRayMoveStopsAtIntermediateCollapsedFloor() throws {
        let brittlePoint = GridPoint(x: 1, y: 0)
        let laterPoint = GridPoint(x: 2, y: 0)
        let runState = DungeonRunState(
            dungeonID: "test-tower",
            currentFloorIndex: 1,
            carriedHP: 3,
            collapsedFloorPointsByFloor: [1: [brittlePoint]]
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            hazards: [.brittleFloor(points: [brittlePoint], initialState: .collapsed)],
            runState: runState
        )
        let core = makeCore(mode: mode, cards: [.rayRight, .kingUpRight, .straightRight2, .straightLeft2, .straightDown2])

        playMove(to: GridPoint(x: 4, y: 0), in: core)

        XCTAssertEqual(core.current, brittlePoint)
        XCTAssertEqual(core.dungeonHP, 2)
        XCTAssertEqual(core.dungeonFallEvent?.point, brittlePoint)
        XCTAssertEqual(core.lastMovementResolution?.path, [brittlePoint])
        XCTAssertEqual(core.lastMovementResolution?.presentationSteps.map(\.point), [brittlePoint])
        XCTAssertEqual(core.lastMovementResolution?.presentationSteps.first?.hpAfter, 2)
        XCTAssertEqual(core.lastMovementResolution?.presentationSteps.first?.tookDamage, true)
        XCTAssertEqual(core.lastMovementResolution?.presentationSteps.first?.stopReason, .fall)
        XCTAssertEqual(core.lastMovementResolution?.presentationSteps.first?.collapsedFloorPointsAfter, [brittlePoint])
        XCTAssertFalse(core.board.isVisited(laterPoint), "崩落した後の経路は踏まない想定です")
    }

    func testRayMovePresentationStepsReflectIntermediatePickup() throws {
        let pickupPoint = GridPoint(x: 1, y: 0)
        let pickup = DungeonCardPickupDefinition(
            id: "pickup-ray-left",
            point: pickupPoint,
            card: .rayLeft,
            uses: 1
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            cardAcquisitionMode: .inventoryOnly,
            cardPickups: [pickup]
        )
        let core = makeCore(mode: mode, cards: [.rayRight, .kingUpRight, .straightRight2, .straightLeft2, .straightDown2])
        XCTAssertTrue(core.addDungeonInventoryCardForTesting(.rayRight, pickupUses: 1))

        playMove(to: GridPoint(x: 4, y: 0), in: core)

        let steps = try XCTUnwrap(core.lastMovementResolution?.presentationSteps)
        XCTAssertEqual(steps.map(\.point), [
            GridPoint(x: 1, y: 0),
            GridPoint(x: 2, y: 0),
            GridPoint(x: 3, y: 0),
            GridPoint(x: 4, y: 0)
        ])
        XCTAssertTrue(steps[0].collectedDungeonCardPickupIDsAfter.contains(pickup.id))
        XCTAssertTrue(steps[0].handStacksAfter.contains { $0.representativeMove == .rayLeft })
    }

    func testRayMovePresentationStepsIncludeWarpSourceBeforeDestination() throws {
        let warpSource = GridPoint(x: 2, y: 0)
        let warpDestination = GridPoint(x: 4, y: 4)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 0, y: 4),
            hp: 3,
            turnLimit: 8,
            warpTilePairs: ["test-warp": [warpSource, warpDestination]]
        )
        let core = makeCore(mode: mode, cards: [.rayRight, .kingUpRight, .straightRight2, .straightLeft2, .straightDown2])

        playMove(to: GridPoint(x: 4, y: 0), in: core)

        let resolution = try XCTUnwrap(core.lastMovementResolution)
        XCTAssertEqual(core.current, warpDestination)
        XCTAssertEqual(resolution.path, [
            GridPoint(x: 1, y: 0),
            warpSource,
            warpDestination
        ])
        XCTAssertEqual(resolution.presentationSteps.map(\.point), [
            GridPoint(x: 1, y: 0),
            warpSource,
            warpDestination
        ])
        XCTAssertNil(resolution.presentationSteps[1].stopReason)
        XCTAssertEqual(resolution.presentationSteps[2].stopReason, .warp)
        XCTAssertEqual(resolution.appliedEffects.map(\.point), [warpSource])
        XCTAssertTrue(resolution.presentationSteps[1].boardAfter?.isVisited(warpSource) == true)
        XCTAssertFalse(resolution.presentationSteps[1].boardAfter?.isVisited(warpDestination) == true)
        XCTAssertTrue(resolution.presentationSteps[2].boardAfter?.isVisited(warpDestination) == true)
    }

    func testWarpDestinationTakesEnemyDangerDamageBeforeContinuing() throws {
        let warpSource = GridPoint(x: 2, y: 0)
        let warpDestination = GridPoint(x: 4, y: 3)
        let watcher = EnemyDefinition(
            id: "watcher",
            name: "見張り",
            position: GridPoint(x: 4, y: 1),
            behavior: .watcher(direction: MoveVector(dx: 0, dy: 1), range: 3)
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: warpDestination,
            hp: 3,
            turnLimit: 8,
            enemies: [watcher],
            warpTilePairs: ["test-warp": [warpSource, warpDestination]]
        )
        let core = makeCore(mode: mode, cards: [.rayRight, .kingUpRight, .straightRight2, .straightLeft2, .straightDown2])

        XCTAssertTrue(core.enemyDangerPoints.contains(warpDestination))

        playMove(to: GridPoint(x: 4, y: 0), in: core)

        let resolution = try XCTUnwrap(core.lastMovementResolution)
        XCTAssertEqual(core.current, warpDestination)
        XCTAssertEqual(core.dungeonHP, 2)
        XCTAssertEqual(resolution.presentationSteps.map(\.point), [
            GridPoint(x: 1, y: 0),
            warpSource,
            warpDestination
        ])
        XCTAssertEqual(resolution.presentationSteps.last?.hpAfter, 2)
        XCTAssertEqual(resolution.presentationSteps.last?.tookDamage, true)
        XCTAssertEqual(resolution.presentationSteps.last?.stopReason, .warp)
    }

    func testWarpDestinationDangerDamageSuppressesSameWatcherEnemyTurnAttack() throws {
        let warpSource = GridPoint(x: 2, y: 0)
        let warpDestination = GridPoint(x: 4, y: 3)
        let watcher = EnemyDefinition(
            id: "watcher",
            name: "見張り",
            position: GridPoint(x: 4, y: 1),
            behavior: .watcher(direction: MoveVector(dx: 0, dy: 1), range: 3)
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 0, y: 4),
            hp: 3,
            turnLimit: 8,
            enemies: [watcher],
            warpTilePairs: ["test-warp": [warpSource, warpDestination]]
        )
        let core = makeCore(mode: mode, cards: [.rayRight, .kingUpRight, .straightRight2, .straightLeft2, .straightDown2])

        playMove(to: GridPoint(x: 4, y: 0), in: core)

        XCTAssertEqual(core.current, warpDestination)
        XCTAssertEqual(core.dungeonHP, 2)
        XCTAssertTrue(core.dungeonRunLogEntries.contains { $0.message.contains("シロフクロウの攻撃範囲通過でHP -1") })
        XCTAssertFalse(core.dungeonRunLogEntries.contains { $0.message.contains("シロフクロウの攻撃でHP") })
    }

    func testWarpDestinationDangerDamageOnlySuppressesResolvedEnemy() throws {
        let warpSource = GridPoint(x: 2, y: 0)
        let warpDestination = GridPoint(x: 4, y: 3)
        let watcher = EnemyDefinition(
            id: "watcher",
            name: "見張り",
            position: GridPoint(x: 4, y: 1),
            behavior: .watcher(direction: MoveVector(dx: 0, dy: 1), range: 3)
        )
        let chaser = EnemyDefinition(
            id: "chaser",
            name: "追跡兵",
            position: GridPoint(x: 2, y: 3),
            behavior: .chaser
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 0, y: 4),
            hp: 3,
            turnLimit: 8,
            enemies: [watcher, chaser],
            warpTilePairs: ["test-warp": [warpSource, warpDestination]]
        )
        let core = makeCore(mode: mode, cards: [.rayRight, .kingUpRight, .straightRight2, .straightLeft2, .straightDown2])

        playMove(to: GridPoint(x: 4, y: 0), in: core)

        XCTAssertEqual(core.current, warpDestination)
        XCTAssertEqual(core.enemyStates.first { $0.id == "chaser" }?.position, GridPoint(x: 3, y: 3))
        XCTAssertEqual(core.dungeonHP, 1)
        XCTAssertTrue(core.dungeonRunLogEntries.contains { $0.message.contains("シロフクロウの攻撃範囲通過でHP -1") })
        XCTAssertTrue(core.dungeonRunLogEntries.contains { $0.message.contains("ホッキョクギツネの攻撃でHP -1") })
        XCTAssertFalse(core.dungeonRunLogEntries.contains { $0.message.contains("シロフクロウの攻撃でHP") })
    }

    func testPendingPickupContinuationPreservesResolvedEnemyDamageSourceIDs() throws {
        let continuation = PendingDungeonMovementContinuation(
            inputKind: .card,
            playedMoveCard: .rayRight,
            remainingPath: [GridPoint(x: 2, y: 0)],
            traversedPath: [GridPoint(x: 1, y: 0)],
            encounteredRevisit: false,
            detectedEffects: [],
            preservesPlayedCard: false,
            initialMarkerDamagePoints: [],
            triggeredPoisonTrap: false,
            previousMoveCount: 0,
            resolvedEnemyDamageSourceIDs: ["watcher"]
        )

        let decoded = try JSONDecoder().decode(
            PendingDungeonMovementContinuation.self,
            from: JSONEncoder().encode(continuation)
        )

        XCTAssertEqual(decoded.resolvedEnemyDamageSourceIDs, ["watcher"])

        let legacyContinuation = PendingDungeonMovementContinuation(
            inputKind: .basic,
            remainingPath: [GridPoint(x: 2, y: 0)],
            traversedPath: [GridPoint(x: 1, y: 0)],
            encounteredRevisit: false,
            detectedEffects: [],
            preservesPlayedCard: false,
            initialMarkerDamagePoints: [],
            triggeredPoisonTrap: false,
            previousMoveCount: 0
        )
        let legacyDecoded = try JSONDecoder().decode(
            PendingDungeonMovementContinuation.self,
            from: JSONEncoder().encode(legacyContinuation)
        )

        XCTAssertTrue(legacyDecoded.resolvedEnemyDamageSourceIDs.isEmpty)
    }

    func testWarpDestinationEnemyDangerDamageStopsBeforePickupWhenHPReachesZero() throws {
        let warpSource = GridPoint(x: 2, y: 0)
        let warpDestination = GridPoint(x: 4, y: 3)
        let watcher = EnemyDefinition(
            id: "watcher",
            name: "見張り",
            position: GridPoint(x: 4, y: 1),
            behavior: .watcher(direction: MoveVector(dx: 0, dy: 1), range: 3)
        )
        let pickup = DungeonCardPickupDefinition(
            id: "danger-warp-pickup",
            point: warpDestination,
            card: .straightUp2
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 0, y: 4),
            hp: 1,
            turnLimit: 8,
            enemies: [watcher],
            warpTilePairs: ["test-warp": [warpSource, warpDestination]],
            cardPickups: [pickup]
        )
        let core = makeCore(mode: mode, cards: [.rayRight, .kingUpRight, .straightRight2, .straightLeft2, .straightDown2])

        playMove(to: GridPoint(x: 4, y: 0), in: core)

        let resolution = try XCTUnwrap(core.lastMovementResolution)
        XCTAssertEqual(core.progress, .failed)
        XCTAssertEqual(core.current, warpDestination)
        XCTAssertEqual(core.dungeonHP, 0)
        XCTAssertEqual(resolution.path, [
            GridPoint(x: 1, y: 0),
            warpSource,
            warpDestination
        ])
        XCTAssertEqual(resolution.presentationSteps.map(\.point), [
            GridPoint(x: 1, y: 0),
            warpSource,
            warpDestination
        ])
        XCTAssertEqual(resolution.presentationSteps.last?.hpAfter, 0)
        XCTAssertEqual(resolution.presentationSteps.last?.tookDamage, true)
        XCTAssertEqual(resolution.presentationSteps.last?.stopReason, .failed)
        XCTAssertFalse(core.collectedDungeonCardPickupIDs.contains(pickup.id))
    }

    func testRayMoveStopsAtParalysisTrapAndAdvancesEnemiesTwice() throws {
        let paralysisTrap = GridPoint(x: 1, y: 0)
        let laterPoint = GridPoint(x: 2, y: 0)
        let patrol = EnemyDefinition(
            id: "patrol",
            name: "巡回兵",
            position: GridPoint(x: 4, y: 1),
            behavior: .patrol(path: [
                GridPoint(x: 4, y: 1),
                GridPoint(x: 4, y: 2),
                GridPoint(x: 4, y: 3)
            ])
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            enemies: [patrol],
            tileEffectOverrides: [paralysisTrap: .slow]
        )
        let core = makeCore(mode: mode, cards: [.rayRight, .kingUpRight, .straightRight2, .straightLeft2, .straightDown2])

        playMove(to: paralysisTrap, in: core)

        XCTAssertEqual(core.current, paralysisTrap)
        XCTAssertEqual(core.lastMovementResolution?.path, [paralysisTrap])
        XCTAssertFalse(core.board.isVisited(laterPoint), "麻痺罠より先の経路は踏まない想定です")
        XCTAssertEqual(core.enemyStates.first?.position, GridPoint(x: 4, y: 3))
        XCTAssertEqual(core.dungeonEnemyTurnEvent?.isParalysisRest, true)
        XCTAssertEqual(core.dungeonEnemyTurnEvent?.paralysisTrapPoint, paralysisTrap)
        XCTAssertEqual(core.dungeonEnemyTurnEvent?.phases.count, 2)
        XCTAssertEqual(core.moveCount, 1)
    }

    func testParalysisTrapStopsSecondEnemyTurnWhenFirstTurnDefeatsPlayer() throws {
        let paralysisTrap = GridPoint(x: 1, y: 0)
        let guardEnemy = EnemyDefinition(
            id: "guard",
            name: "番兵",
            position: GridPoint(x: 2, y: 0),
            behavior: .guardPost
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 1,
            turnLimit: 8,
            enemies: [guardEnemy],
            tileEffectOverrides: [paralysisTrap: .slow]
        )
        let core = makeCore(mode: mode, cards: [.rayRight, .kingUpRight, .straightRight2, .straightLeft2, .straightDown2])

        playMove(to: paralysisTrap, in: core)

        XCTAssertEqual(core.progress, .failed)
        XCTAssertEqual(core.dungeonHP, 0)
        XCTAssertEqual(core.dungeonEnemyTurnEvent?.isParalysisRest, true)
        XCTAssertEqual(core.dungeonEnemyTurnEvent?.phases.count, 1)
    }

    func testShackleTrapUsesNormalTurnCostAndAdvancesEnemiesTwiceImmediately() throws {
        let shackleTrap = GridPoint(x: 1, y: 0)
        let patrol = EnemyDefinition(
            id: "patrol",
            name: "巡回兵",
            position: GridPoint(x: 4, y: 1),
            behavior: .patrol(path: [
                GridPoint(x: 4, y: 1),
                GridPoint(x: 4, y: 2),
                GridPoint(x: 4, y: 3)
            ])
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            enemies: [patrol],
            tileEffectOverrides: [shackleTrap: .shackleTrap]
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: shackleTrap, in: core)

        XCTAssertTrue(core.isShackled)
        XCTAssertEqual(core.moveCount, 1)
        XCTAssertEqual(core.enemyStates.first?.position, GridPoint(x: 4, y: 3))
        XCTAssertEqual(core.dungeonEnemyTurnEvent?.phases.count, 2)
    }

    func testRayMoveStopsAtShackleTrap() throws {
        let shackleTrap = GridPoint(x: 1, y: 0)
        let laterPoint = GridPoint(x: 2, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            tileEffectOverrides: [shackleTrap: .shackleTrap]
        )
        let core = makeCore(mode: mode, cards: [.rayRight, .kingUpRight, .straightRight2, .straightLeft2, .straightDown2])

        playMove(to: shackleTrap, in: core)

        XCTAssertEqual(core.current, shackleTrap)
        XCTAssertEqual(core.lastMovementResolution?.path, [shackleTrap])
        XCTAssertEqual(core.lastMovementResolution?.presentationSteps.last?.stopReason, .shackleTrap)
        XCTAssertFalse(core.board.isVisited(laterPoint))
        XCTAssertTrue(core.isShackled)
        XCTAssertEqual(core.moveCount, 1)
    }

    func testFixedTwoStepMoveSkipsIntermediateShackleTrap() throws {
        let shackleTrap = GridPoint(x: 3, y: 3)
        let destination = GridPoint(x: 2, y: 2)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 4, y: 4),
            exit: GridPoint(x: 0, y: 0),
            hp: 3,
            turnLimit: 8,
            tileEffectOverrides: [shackleTrap: .shackleTrap]
        )
        let core = makeCore(
            mode: mode,
            cards: [.diagonalDownLeft2, .rayRight, .kingUpRight, .straightRight2, .straightLeft2]
        )

        let move = try XCTUnwrap(core.availableMoves().first { $0.moveCard == .diagonalDownLeft2 })
        XCTAssertEqual(move.destination, destination)
        XCTAssertEqual(move.path, [destination])

        core.playCard(using: move)

        XCTAssertEqual(core.current, destination)
        XCTAssertFalse(core.board.isVisited(shackleTrap))
        XCTAssertTrue(core.board.isVisited(destination))
        XCTAssertFalse(core.isShackled)
        XCTAssertEqual(core.lastMovementResolution?.path, [destination])
        XCTAssertFalse(
            core.lastMovementResolution?.appliedEffects.contains {
                $0.point == shackleTrap && $0.effect == .shackleTrap
            } == true
        )
        XCTAssertEqual(core.lastMovementResolution?.presentationSteps.map(\.point), [destination])
        XCTAssertNil(core.lastMovementResolution?.presentationSteps.first?.stopReason)
        XCTAssertEqual(core.moveCount, 1)
    }

    func testShackleStateKeepsLaterBasicMoveCostOneAndAdvancesEnemiesTwice() throws {
        let shackleTrap = GridPoint(x: 1, y: 0)
        let patrol = EnemyDefinition(
            id: "patrol",
            name: "巡回兵",
            position: GridPoint(x: 4, y: 1),
            behavior: .patrol(path: [
                GridPoint(x: 4, y: 1),
                GridPoint(x: 4, y: 2),
                GridPoint(x: 4, y: 3)
            ])
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 10,
            enemies: [patrol],
            tileEffectOverrides: [shackleTrap: .shackleTrap]
        )
        let core = makeCore(mode: mode)
        playBasicMove(to: shackleTrap, in: core)

        playBasicMove(to: GridPoint(x: 1, y: 1), in: core)

        XCTAssertTrue(core.isShackled)
        XCTAssertEqual(core.moveCount, 2)
        XCTAssertEqual(core.dungeonEnemyTurnEvent?.phases.count, 2)
    }

    func testSupportCardOnShackleAndLavaCanFailBeforeEnemyTurns() throws {
        let shackleTrap = GridPoint(x: 1, y: 0)
        let patrol = EnemyDefinition(
            id: "patrol",
            name: "巡回兵",
            position: GridPoint(x: 4, y: 1),
            behavior: .patrol(path: [
                GridPoint(x: 4, y: 1),
                GridPoint(x: 4, y: 2),
                GridPoint(x: 4, y: 3)
            ])
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 10,
            enemies: [patrol],
            hazards: [.lavaTile(points: [shackleTrap], damage: 1)],
            tileEffectOverrides: [shackleTrap: .shackleTrap],
            cardAcquisitionMode: .inventoryOnly
        )
        let core = makeCore(mode: mode)
        XCTAssertTrue(core.addDungeonInventorySupportCardForTesting(.refillEmptySlots, rewardUses: 1))
        playBasicMove(to: shackleTrap, in: core)
        let supportIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.topCard?.supportCard == .refillEmptySlots })

        core.playSupportCard(at: supportIndex)

        XCTAssertTrue(core.isShackled)
        XCTAssertEqual(core.moveCount, 2)
        XCTAssertEqual(core.dungeonHP, 0)
        XCTAssertNil(core.dungeonEnemyTurnEvent)
    }

    func testLegacyAntidoteClearsPoisonBeforeSupportActionCanDealPoisonDamage() throws {
        let poisonTrap = GridPoint(x: 1, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 12,
            tileEffectOverrides: [poisonTrap: .poisonTrap],
            cardAcquisitionMode: .inventoryOnly
        )
        let core = makeCore(mode: mode)
        XCTAssertTrue(core.addDungeonInventorySupportCardForTesting(.antidote, rewardUses: 1))
        playBasicMove(to: poisonTrap, in: core)
        playBasicMove(to: GridPoint(x: 1, y: 1), in: core)
        playBasicMove(to: GridPoint(x: 0, y: 1), in: core)
        XCTAssertEqual(core.poisonActionsUntilNextDamage, 1)
        let supportIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.topCard?.supportCard == .panacea })

        core.playSupportCard(at: supportIndex)

        XCTAssertEqual(core.dungeonHP, 3)
        XCTAssertEqual(core.poisonDamageTicksRemaining, 0)
        XCTAssertEqual(core.poisonActionsUntilNextDamage, 0)
        XCTAssertEqual(core.moveCount, 4)
    }

    func testPanaceaOnShackleUsesNormalCostThenResolvesOneEnemyTurn() throws {
        let shackleTrap = GridPoint(x: 1, y: 0)
        let patrol = EnemyDefinition(
            id: "patrol",
            name: "巡回兵",
            position: GridPoint(x: 4, y: 1),
            behavior: .patrol(path: [
                GridPoint(x: 4, y: 1),
                GridPoint(x: 4, y: 2),
                GridPoint(x: 4, y: 3)
            ])
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 10,
            enemies: [patrol],
            tileEffectOverrides: [shackleTrap: .shackleTrap],
            cardAcquisitionMode: .inventoryOnly
        )
        let core = makeCore(mode: mode)
        XCTAssertTrue(core.addDungeonInventorySupportCardForTesting(.panacea, rewardUses: 1))
        playBasicMove(to: shackleTrap, in: core)
        let supportIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.topCard?.supportCard == .panacea })

        core.playSupportCard(at: supportIndex)

        XCTAssertFalse(core.isShackled)
        XCTAssertEqual(core.moveCount, 2)
        XCTAssertEqual(core.dungeonEnemyTurnEvent?.phases.count, 1)
    }

    func testIllusionTrapPersistsOnSameFloorResumeAndClearsOnNextFloor() throws {
        let illusionTrap = GridPoint(x: 1, y: 0)
        let runState = DungeonRunState(dungeonID: "growth-tower", currentFloorIndex: 0, carriedHP: 3)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            tileEffectOverrides: [illusionTrap: .illusionTrap],
            runState: runState
        )
        let core = makeCore(mode: mode)
        playBasicMove(to: illusionTrap, in: core)
        let snapshot = try XCTUnwrap(core.makeDungeonResumeSnapshot())
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(DungeonRunResumeSnapshot.self, from: data)

        let restoredCore = makeCore(mode: mode)
        XCTAssertTrue(restoredCore.restoreDungeonResumeSnapshot(decoded))
        XCTAssertTrue(restoredCore.isIlluded)

        let nextFloorMode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            runState: DungeonRunState(dungeonID: "growth-tower", currentFloorIndex: 1, carriedHP: 3)
        )
        XCTAssertFalse(makeCore(mode: nextFloorMode).isIlluded)
    }

    func testIllusionRandomMoveUsesOnlyCurrentlyLegalMoveCandidates() throws {
        let illusionTrap = GridPoint(x: 1, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            impassableTilePoints: [GridPoint(x: 3, y: 0)],
            tileEffectOverrides: [illusionTrap: .illusionTrap]
        )
        let core = makeCore(mode: mode, cards: [.straightRight2, .straightLeft2, .straightUp2])
        playBasicMove(to: illusionTrap, in: core)

        let randomMove = try XCTUnwrap(core.randomIllusionMove())

        XCTAssertTrue(core.isIlluded)
        XCTAssertTrue(core.availableMoves().contains(randomMove))
        XCTAssertNotEqual(randomMove.destination, GridPoint(x: 3, y: 0))
        XCTAssertNotEqual(randomMove.moveCard, .straightLeft2)
    }

    func testIllusionAllowsBasicMoveAndSupportButBlocksMoveCardsOnSwamp() throws {
        let illusionTrap = GridPoint(x: 1, y: 0)
        let swamp = GridPoint(x: 1, y: 1)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            enemies: [
                EnemyDefinition(id: "guard", name: "番兵", position: GridPoint(x: 4, y: 0), behavior: .guardPost)
            ],
            tileEffectOverrides: [
                illusionTrap: .illusionTrap,
                swamp: .swamp
            ],
            cardAcquisitionMode: .inventoryOnly
        )
        let core = makeCore(mode: mode)
        XCTAssertTrue(core.addDungeonInventoryCardForTesting(.straightRight2, pickupUses: 1))
        XCTAssertTrue(core.addDungeonInventorySupportCardForTesting(.singleAnnihilationSpell, rewardUses: 1))
        playBasicMove(to: illusionTrap, in: core)
        playBasicMove(to: swamp, in: core)
        let supportIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.topCard?.supportCard == .singleAnnihilationSpell })

        XCTAssertTrue(core.isIlluded)
        XCTAssertFalse(core.availableBasicOrthogonalMoves().isEmpty)
        XCTAssertTrue(core.isSupportCardUsable(in: core.handStacks[supportIndex]))
        XCTAssertNil(core.randomIllusionMove())
    }

    func testPanaceaClearsIllusionState() throws {
        let illusionTrap = GridPoint(x: 1, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            tileEffectOverrides: [illusionTrap: .illusionTrap],
            cardAcquisitionMode: .inventoryOnly
        )
        let core = makeCore(mode: mode)
        XCTAssertTrue(core.addDungeonInventorySupportCardForTesting(.panacea, rewardUses: 1))
        playBasicMove(to: illusionTrap, in: core)
        let supportIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.topCard?.supportCard == .panacea })

        XCTAssertTrue(core.isSupportCardUsable(in: core.handStacks[supportIndex]))
        core.playSupportCard(at: supportIndex)

        XCTAssertFalse(core.isIlluded)
        XCTAssertFalse(core.dungeonInventoryEntries.contains { $0.supportCard == .panacea })
    }

    func testShackleStopsSecondEnemyTurnWhenFirstTurnDefeatsPlayer() throws {
        let shackleTrap = GridPoint(x: 1, y: 0)
        let guardEnemy = EnemyDefinition(
            id: "guard",
            name: "番兵",
            position: GridPoint(x: 2, y: 0),
            behavior: .guardPost
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 1,
            turnLimit: 8,
            enemies: [guardEnemy],
            tileEffectOverrides: [shackleTrap: .shackleTrap]
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: shackleTrap, in: core)

        XCTAssertTrue(core.isShackled)
        XCTAssertEqual(core.progress, .failed)
        XCTAssertEqual(core.dungeonHP, 0)
        XCTAssertEqual(core.dungeonEnemyTurnEvent?.phases.count, 1)
    }

    func testShackleStateRestoresFromResumeSnapshotAndDoesNotCarryToNewFloor() throws {
        let shackleTrap = GridPoint(x: 1, y: 0)
        let runState = DungeonRunState(dungeonID: "growth-tower", currentFloorIndex: 0, carriedHP: 3)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            tileEffectOverrides: [shackleTrap: .shackleTrap],
            runState: runState
        )
        let core = makeCore(mode: mode)
        playBasicMove(to: shackleTrap, in: core)
        let snapshot = try XCTUnwrap(core.makeDungeonResumeSnapshot())
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(DungeonRunResumeSnapshot.self, from: data)

        let restoredCore = makeCore(mode: mode)
        XCTAssertTrue(restoredCore.restoreDungeonResumeSnapshot(decoded))
        XCTAssertTrue(restoredCore.isShackled)

        let nextFloorMode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            runState: DungeonRunState(dungeonID: "growth-tower", currentFloorIndex: 1, carriedHP: 3)
        )
        XCTAssertFalse(makeCore(mode: nextFloorMode).isShackled)
    }

    func testIronShackleCurseMakesShackledEnemyTurnsThreeWithoutExtraMoveCost() throws {
        let shackleTrap = GridPoint(x: 1, y: 0)
        let patrol = EnemyDefinition(
            id: "patrol",
            name: "巡回兵",
            position: GridPoint(x: 4, y: 0),
            behavior: .patrol(path: [
                GridPoint(x: 4, y: 0),
                GridPoint(x: 4, y: 1),
                GridPoint(x: 4, y: 2),
                GridPoint(x: 4, y: 3)
            ])
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            enemies: [patrol],
            tileEffectOverrides: [shackleTrap: .shackleTrap],
            runState: DungeonRunState(
                dungeonID: "growth-tower",
                carriedHP: 3,
                curseEntries: [DungeonCurseEntry(curseID: .ironShackle)]
            )
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: shackleTrap, in: core)

        XCTAssertTrue(core.isShackled)
        XCTAssertEqual(core.moveCount, 1)
        XCTAssertEqual(core.enemyStates.first?.position, GridPoint(x: 4, y: 3))
        XCTAssertEqual(core.dungeonEnemyTurnEvent?.phases.count, 3)
    }

    func testPoisonTrapStartsPoisonWithoutImmediateDamage() throws {
        let poisonTrap = GridPoint(x: 1, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 12,
            tileEffectOverrides: [poisonTrap: .poisonTrap]
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: poisonTrap, in: core)

        XCTAssertEqual(core.dungeonHP, 3)
        XCTAssertEqual(core.poisonDamageTicksRemaining, 3)
        XCTAssertEqual(core.poisonActionsUntilNextDamage, 3)
    }

    func testPoisonDealsDamageEveryThreeSuccessfulActionsAndThenExpires() throws {
        let poisonTrap = GridPoint(x: 1, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 4,
            turnLimit: 20,
            tileEffectOverrides: [poisonTrap: .poisonTrap]
        )
        let core = makeCore(mode: mode)
        playBasicMove(to: poisonTrap, in: core)

        playBasicMove(to: GridPoint(x: 1, y: 1), in: core)
        XCTAssertEqual(core.dungeonHP, 4)
        XCTAssertEqual(core.poisonActionsUntilNextDamage, 2)

        playBasicMove(to: GridPoint(x: 0, y: 1), in: core)
        XCTAssertEqual(core.dungeonHP, 4)
        XCTAssertEqual(core.poisonActionsUntilNextDamage, 1)

        playBasicMove(to: GridPoint(x: 1, y: 1), in: core)
        XCTAssertEqual(core.dungeonHP, 3)
        XCTAssertEqual(core.poisonDamageTicksRemaining, 2)
        XCTAssertEqual(core.poisonActionsUntilNextDamage, 3)
    }

    func testRayMovePassesThroughPoisonTrap() throws {
        let poisonTrap = GridPoint(x: 1, y: 0)
        let laterPoint = GridPoint(x: 2, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            tileEffectOverrides: [poisonTrap: .poisonTrap]
        )
        let core = makeCore(mode: mode, cards: [.rayRight, .kingUpRight, .straightRight2, .straightLeft2, .straightDown2])

        playMove(to: GridPoint(x: 4, y: 0), in: core)

        XCTAssertEqual(core.current, GridPoint(x: 4, y: 0))
        XCTAssertTrue(core.board.isVisited(poisonTrap))
        XCTAssertTrue(core.board.isVisited(laterPoint))
        XCTAssertTrue(core.lastMovementResolution?.appliedEffects.contains { $0.point == poisonTrap && $0.effect == .poisonTrap } == true)
        XCTAssertEqual(core.poisonDamageTicksRemaining, 3)
    }

    func testPoisonTicksOnceDuringShackledAction() throws {
        let poisonTrap = GridPoint(x: 1, y: 0)
        let shackleTrap = GridPoint(x: 1, y: 1)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 12,
            tileEffectOverrides: [
                poisonTrap: .poisonTrap,
                shackleTrap: .shackleTrap
            ]
        )
        let core = makeCore(mode: mode)
        playBasicMove(to: poisonTrap, in: core)

        playBasicMove(to: shackleTrap, in: core)

        XCTAssertTrue(core.isShackled)
        XCTAssertEqual(core.moveCount, 2)
        XCTAssertEqual(core.poisonDamageTicksRemaining, 3)
        XCTAssertEqual(core.poisonActionsUntilNextDamage, 2)
    }

    func testPoisonDamageFailsBeforeEnemyTurn() throws {
        let poisonTrap = GridPoint(x: 1, y: 0)
        let guardEnemy = EnemyDefinition(
            id: "guard",
            name: "番兵",
            position: GridPoint(x: 4, y: 0),
            behavior: .guardPost
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 1,
            turnLimit: 12,
            enemies: [guardEnemy],
            tileEffectOverrides: [poisonTrap: .poisonTrap]
        )
        let core = makeCore(mode: mode)
        playBasicMove(to: poisonTrap, in: core)
        playBasicMove(to: GridPoint(x: 1, y: 1), in: core)
        playBasicMove(to: GridPoint(x: 0, y: 1), in: core)

        playBasicMove(to: GridPoint(x: 1, y: 1), in: core)

        XCTAssertEqual(core.progress, .failed)
        XCTAssertEqual(core.dungeonHP, 0)
    }

    func testPoisonStateRestoresFromResumeSnapshotAndDoesNotCarryToNewFloor() throws {
        let poisonTrap = GridPoint(x: 1, y: 0)
        let runState = DungeonRunState(dungeonID: "growth-tower", currentFloorIndex: 0, carriedHP: 3)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            tileEffectOverrides: [poisonTrap: .poisonTrap],
            runState: runState
        )
        let core = makeCore(mode: mode)
        playBasicMove(to: poisonTrap, in: core)
        playBasicMove(to: GridPoint(x: 1, y: 1), in: core)
        let snapshot = try XCTUnwrap(core.makeDungeonResumeSnapshot())
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(DungeonRunResumeSnapshot.self, from: data)

        let restoredCore = makeCore(mode: mode)
        XCTAssertTrue(restoredCore.restoreDungeonResumeSnapshot(decoded))
        XCTAssertEqual(restoredCore.poisonDamageTicksRemaining, 3)
        XCTAssertEqual(restoredCore.poisonActionsUntilNextDamage, 2)

        let nextFloorMode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            runState: DungeonRunState(dungeonID: "growth-tower", currentFloorIndex: 1, carriedHP: 3)
        )
        XCTAssertEqual(makeCore(mode: nextFloorMode).poisonDamageTicksRemaining, 0)
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
        let core = makeCore(mode: mode, cards: [.rayRight, .kingUpRight, .straightRight2, .straightLeft2, .straightDown2])

        playMove(to: GridPoint(x: 4, y: 0), in: core)

        XCTAssertEqual(core.dungeonHP, 2)
        XCTAssertEqual(core.hazardDamageMitigationsRemaining, 0)
        XCTAssertEqual(core.progress, .playing)
    }

    func testGrowthHazardMitigationPreventsBrittleFallDamageButStillFalls() throws {
        let brittlePoint = GridPoint(x: 1, y: 0)
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            currentFloorIndex: 1,
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
            cards: [.straightRight2, .straightLeft2, .straightRight2, .kingUpRight, .straightDown2]
        )

        playBasicMove(to: brittlePoint, in: core)
        playBasicMove(to: GridPoint(x: 0, y: 0), in: core)
        playBasicMove(to: brittlePoint, in: core)

        XCTAssertEqual(core.dungeonHP, 1)
        XCTAssertEqual(core.hazardDamageMitigationsRemaining, 0)
        XCTAssertEqual(core.progress, .playing)
        XCTAssertEqual(core.dungeonFallEvent?.hpAfterDamage, 1)
        XCTAssertEqual(core.dungeonFallEvent?.destinationFloorIndex, 0)
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
            hazardDamageMitigationsRemaining: 1,
            enemyDamageMitigationsRemaining: 1,
            markerDamageMitigationsRemaining: 1
        )
        let sectionStartMode = try XCTUnwrap(
            DungeonLibrary.shared.floorMode(
                for: tower,
                floorIndex: 10,
                startingHazardDamageMitigations: 2,
                startingEnemyDamageMitigations: 1,
                startingMarkerDamageMitigations: 1,
                cardVariationSeed: 123
            )
        )

        XCTAssertEqual(firstRunState.hazardDamageMitigationsRemaining, 2)
        XCTAssertEqual(nextRunState.hazardDamageMitigationsRemaining, 1)
        XCTAssertEqual(nextRunState.enemyDamageMitigationsRemaining, 1)
        XCTAssertEqual(nextRunState.markerDamageMitigationsRemaining, 1)
        XCTAssertEqual(sectionStartMode.dungeonMetadataSnapshot?.runState?.hazardDamageMitigationsRemaining, 2)
        XCTAssertEqual(sectionStartMode.dungeonMetadataSnapshot?.runState?.enemyDamageMitigationsRemaining, 1)
        XCTAssertEqual(sectionStartMode.dungeonMetadataSnapshot?.runState?.markerDamageMitigationsRemaining, 1)
    }

    func testDirectionalRayStopsAtDungeonExitWhenExitIsTraversed() throws {
        let exit = GridPoint(x: 2, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: exit,
            hp: 3,
            turnLimit: 8
        )
        let core = makeCore(mode: mode, cards: [.rayRight, .kingUpRight, .straightRight2, .straightLeft2, .straightDown2])

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
        let core = makeCore(mode: mode, cards: [.rayRight, .kingUpRight, .straightRight2, .straightLeft2, .straightDown2])

        playMove(to: GridPoint(x: 4, y: 0), in: core)

        XCTAssertEqual(core.progress, .playing)
        XCTAssertFalse(core.isDungeonExitUnlocked)
        XCTAssertEqual(core.current, GridPoint(x: 4, y: 0))
        XCTAssertEqual(core.lastMovementResolution?.finalPosition, GridPoint(x: 4, y: 0))
        XCTAssertNil(core.dungeonLockedExitReachEvent)
        XCTAssertFalse(
            core.lastMovementResolution?.presentationSteps.contains {
                $0.dungeonLockedExitReachEvent != nil
            } ?? true
        )
    }

    func testLockedExitReachPublishesNoticeEventWithoutClearing() throws {
        let exit = GridPoint(x: 2, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: exit,
            hp: 3,
            turnLimit: 8,
            exitLock: DungeonExitLock(unlockPoint: GridPoint(x: 4, y: 4))
        )
        let core = makeCore(mode: mode, cards: [.straightRight2, .kingUpRight, .straightLeft2, .straightDown2, .rayRight])

        playMove(to: exit, in: core)

        XCTAssertEqual(core.progress, .playing)
        XCTAssertFalse(core.isDungeonExitUnlocked)
        XCTAssertEqual(core.current, exit)
        XCTAssertEqual(core.dungeonLockedExitReachEvent?.exitPoint, exit)
        XCTAssertEqual(core.lastMovementResolution?.presentationSteps.last?.dungeonLockedExitReachEvent?.exitPoint, exit)
    }

    func testDirectionalRayPublishesLockedExitReachOnFinalStepOnly() throws {
        let exit = GridPoint(x: 4, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: exit,
            hp: 3,
            turnLimit: 8,
            exitLock: DungeonExitLock(unlockPoint: GridPoint(x: 4, y: 4))
        )
        let core = makeCore(mode: mode, cards: [.rayRight, .kingUpRight, .straightRight2, .straightLeft2, .straightDown2])

        playMove(to: exit, in: core)

        XCTAssertEqual(core.progress, .playing)
        XCTAssertNil(core.dungeonLockedExitReachEvent)
        let steps = try XCTUnwrap(core.lastMovementResolution?.presentationSteps)
        XCTAssertEqual(steps.map(\.point), [
            GridPoint(x: 1, y: 0),
            GridPoint(x: 2, y: 0),
            GridPoint(x: 3, y: 0),
            exit
        ])
        XCTAssertTrue(steps.dropLast().allSatisfy { $0.dungeonLockedExitReachEvent == nil })
        XCTAssertEqual(steps.last?.dungeonLockedExitReachEvent?.exitPoint, exit)
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
        let core = makeCore(mode: mode, cards: [.rayRight, .kingUpRight, .straightRight2, .straightLeft2, .straightDown2])

        XCTAssertEqual(core.dungeonKeyPoints, [unlockPoint])

        playMove(to: GridPoint(x: 4, y: 0), in: core)

        XCTAssertEqual(core.progress, .cleared)
        XCTAssertTrue(core.isDungeonExitUnlocked)
        XCTAssertTrue(core.dungeonKeyPoints.isEmpty)
        XCTAssertNil(core.dungeonExitUnlockEvent)
        XCTAssertNil(core.dungeonLockedExitReachEvent)
        XCTAssertEqual(core.current, exit)
        XCTAssertEqual(
            core.lastMovementResolution?.path,
            [
                unlockPoint,
                GridPoint(x: 2, y: 0),
                exit
            ]
        )
        let steps = try XCTUnwrap(core.lastMovementResolution?.presentationSteps)
        XCTAssertEqual(steps.first?.dungeonExitUnlockEvent?.unlockPoint, unlockPoint)
        XCTAssertEqual(steps.first?.dungeonExitUnlockEvent?.exitPoint, exit)
        XCTAssertTrue(steps.dropFirst().allSatisfy { $0.dungeonExitUnlockEvent == nil })
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
        let core = makeCore(mode: mode, cards: [.rayRight, .kingUpRight, .straightRight2, .straightLeft2, .straightDown2])

        playMove(to: GridPoint(x: 4, y: 0), in: core)

        XCTAssertEqual(core.progress, .cleared)
        XCTAssertEqual(core.current, exit)
        XCTAssertEqual(core.dungeonHP, 3)
        XCTAssertEqual(core.lastMovementResolution?.path, [GridPoint(x: 1, y: 0), exit])
    }

    func testTutorialTowerProvidesSixPlayableFloors() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))

        XCTAssertEqual(tower.floors.count, 6)
        XCTAssertEqual(tower.difficulty, .tutorial)

        for floor in tower.floors {
            let mode = floor.makeGameMode(dungeonID: tower.id)
            XCTAssertTrue(mode.usesDungeonExit)
            XCTAssertEqual(mode.dungeonExitPoint, floor.exitPoint)
            XCTAssertEqual(mode.dungeonRules?.failureRule, floor.failureRule)
            XCTAssertEqual(mode.dungeonMetadataSnapshot?.dungeonID, tower.id)
            XCTAssertEqual(mode.dungeonMetadataSnapshot?.floorID, floor.id)
        }
    }

    func testTutorialTowerStairsBecomeNextFloorStart() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))

        for floorIndex in tower.floors.indices.dropLast() {
            XCTAssertEqual(
                tower.floors[floorIndex + 1].spawnPoint,
                tower.floors[floorIndex].exitPoint,
                "\(floorIndex + 1)F の階段位置から \(floorIndex + 2)F が始まる必要があります"
            )
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
        XCTAssertNil(library.dungeon(with: "patrol-tower"))
        XCTAssertNil(library.dungeon(with: "key-door-tower"))
        XCTAssertNil(library.dungeon(with: "warp-tower"))
        XCTAssertNil(library.dungeon(with: "trap-tower"))
    }


    func testDungeonTowerBoardSizesFollowTutorialAndStandardPolicy() throws {
        let tutorialTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let growthTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let rogueTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))

        XCTAssertEqual(tutorialTower.floors.map(\.boardSize), Array(repeating: 9, count: tutorialTower.floors.count))
        XCTAssertEqual(growthTower.floors.map(\.boardSize), Array(repeating: 9, count: 50))
        XCTAssertEqual(rogueTower.floors.map(\.boardSize), [9])
        XCTAssertEqual(
            rogueTower.resolvedFloor(
                at: 25,
                runState: DungeonRunState(dungeonID: rogueTower.id, carriedHP: 3, rogueTowerSeed: 1)
            )?.boardSize,
            9
        )
    }

    func testGrowthTowerIntegratesFiftyProgressiveFloors() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))

        XCTAssertEqual(tower.title, "成長塔")
        XCTAssertEqual(tower.difficulty, .growth)
        XCTAssertEqual(tower.floors.count, 50)
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
            "第二関門・宝箱警戒",
            "挟み撃ちの廊下",
            "暗闇の遠回り",
            "暗闇の射線",
            "暗闇の前哨",
            "第二関門",
            "寄り道の分岐",
            "宝箱の門番",
            "転移待ち",
            "鍵の遠回り",
            "第三関門・鍵と追跡",
            "回復を挟む廊下",
            "巡回の鍵束",
            "追跡と抜け道",
            "宝箱の近道",
            "第三関門・総合",
            "毒の見取り図",
            "足枷の迂回",
            "幻惑の小部屋",
            "暗闇の薬棚",
            "第四関門・暗闇巡回",
            "万能薬の遠回り",
            "見えない巡回路",
            "幻惑と転移",
            "暗闇の補給線",
            "第四関門・総合",
            "踏破への入口",
            "呪い箱の岐路",
            "落下を読む橋",
            "追跡の薬路",
            "第五関門・呪いと崩落",
            "暗闇の総力戦",
            "巡回の包囲網",
            "幻惑の最短路",
            "踏破前夜",
            "最上階"
        ])
        for floorIndex in 0..<49 {
            XCTAssertFalse(
                tower.floors[floorIndex].rewardMoveCardsAfterClear.isEmpty
                    && tower.floors[floorIndex].rewardSupportCardsAfterClear.isEmpty,
                "\(tower.floors[floorIndex].title) は次階へ向けた報酬候補を出す必要があります"
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
        XCTAssertEqual(tower.floors[9].rewardMoveCardsAfterClear, [
            .straightRight2,
            .straightUp2,
            .diagonalUpRight2
        ])
        XCTAssertEqual(tower.floors[10].rewardMoveCardsAfterClear, [
            .rayDown,
            .straightDown2
        ])
        XCTAssertEqual(tower.floors[10].rewardSupportCardsAfterClear, [.refillEmptySlots])
        XCTAssertEqual(
            tower.floors[10].rewardMoveCardsAfterClear.count + tower.floors[10].rewardSupportCardsAfterClear.count,
            3,
            "補給は4枚目ではなく報酬3択の1枠として出す想定です"
        )
        XCTAssertEqual(tower.floors[14].rewardMoveCardsAfterClear, [
            .rayRight,
            .diagonalUpRight2
        ])
        XCTAssertEqual(tower.floors[14].rewardSupportCardsAfterClear, [.refillEmptySlots])
        XCTAssertEqual(
            tower.floors[14].rewardMoveCardsAfterClear.count + tower.floors[14].rewardSupportCardsAfterClear.count,
            3,
            "補給ありフロアでも報酬候補の合計は3件に保つ必要があります"
        )
        XCTAssertEqual(tower.floors[15].rewardMoveCardsAfterClear, [
            .diagonalUpLeft2,
            .rayLeft
        ])
        XCTAssertEqual(tower.floors[15].rewardSupportCardsAfterClear, [.singleAnnihilationSpell])
        XCTAssertEqual(
            tower.floors[15].rewardMoveCardsAfterClear.count + tower.floors[15].rewardSupportCardsAfterClear.count,
            3,
            "消滅の呪文も報酬3択の1枠として出す想定です"
        )
        XCTAssertEqual(tower.floors[16].rewardMoveCardsAfterClear, [
            .straightRight2,
            .knightRightwardChoice
        ])
        XCTAssertEqual(tower.floors[16].rewardSupportCardsAfterClear, [.annihilationSpell])
        XCTAssertEqual(
            tower.floors[16].rewardMoveCardsAfterClear.count + tower.floors[16].rewardSupportCardsAfterClear.count,
            3,
            "全滅の呪文も報酬3択の1枠として出す想定です"
        )
        XCTAssertEqual(tower.floors[17].rewardMoveCardsAfterClear, [
            .diagonalDownLeft2,
            .rayLeft
        ])
        XCTAssertEqual(tower.floors[17].rewardSupportCardsAfterClear, [.freezeSpell])
        XCTAssertEqual(
            tower.floors[17].rewardMoveCardsAfterClear.count + tower.floors[17].rewardSupportCardsAfterClear.count,
            3,
            "凍結の呪文も報酬3択の1枠として出す想定です"
        )
        XCTAssertEqual(tower.floors[18].rewardMoveCardsAfterClear, [
            .straightRight2,
            .diagonalUpRight2
        ])
        XCTAssertEqual(tower.floors[18].rewardSupportCardsAfterClear, [.barrierSpell])
        XCTAssertEqual(
            tower.floors[18].rewardMoveCardsAfterClear.count + tower.floors[18].rewardSupportCardsAfterClear.count,
            3,
            "障壁の呪文も報酬3択の1枠として出す想定です"
        )
        XCTAssertEqual(
            tower.floors[19].rewardMoveCardsAfterClear.count + tower.floors[19].rewardSupportCardsAfterClear.count,
            3,
            "20Fは区間終端ですが、50F構成では21Fへ進む報酬を出します"
        )
        XCTAssertEqual(tower.floors[49].rewardMoveCardsAfterClear, [])
        XCTAssertEqual(tower.floors[49].rewardSupportCardsAfterClear, [])
        XCTAssertTrue(tower.canAdvanceWithinRun(afterFloorIndex: 9))
        XCTAssertTrue(tower.canAdvanceWithinRun(afterFloorIndex: 19))
        XCTAssertTrue(tower.canAdvanceWithinRun(afterFloorIndex: 39))
        XCTAssertFalse(tower.canAdvanceWithinRun(afterFloorIndex: 49))
    }

    func testGrowthTowerAddsDarknessAsLateInformationPressure() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let darknessFloorIDs = Set(tower.floors.filter(\.isDarknessEnabled).map(\.id))

        XCTAssertEqual(
            darknessFloorIDs,
            [
                "growth-17", "growth-18", "growth-19",
                "growth-34", "growth-35", "growth-37", "growth-39", "growth-40",
                "growth-42", "growth-45", "growth-46", "growth-48", "growth-49", "growth-50"
            ]
        )
        for floor in tower.floors where floor.isDarknessEnabled {
            let mode = floor.makeGameMode(dungeonID: tower.id, difficulty: tower.difficulty)
            XCTAssertEqual(mode.dungeonRules?.isDarknessEnabled, true)
            XCTAssertTrue(
                hasOrthogonalPath(from: floor.spawnPoint, to: floor.exitPoint, in: floor),
                "\(floor.title) は暗闇でも開始地点から階段までの代表導線を残します"
            )
            if let unlockPoint = floor.exitLock?.unlockPoint {
                XCTAssertTrue(
                    hasOrthogonalPath(from: floor.spawnPoint, to: unlockPoint, in: floor),
                    "\(floor.title) は暗闇でも開始地点から鍵までの代表導線を残します"
                )
                XCTAssertTrue(
                    hasOrthogonalPath(from: unlockPoint, to: floor.exitPoint, in: floor),
                    "\(floor.title) は暗闇でも鍵から階段までの代表導線を残します"
                )
            }
        }
    }

    func testGrowthTowerEarlyFloorsUseDensePickupCardsForLowDifficulty() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let runState = DungeonRunState(
            dungeonID: tower.id,
            carriedHP: 3,
            cardVariationSeed: 321
        )
        let currentMoveCards = Set(MoveCard.allCases)

        for floorIndex in 0..<8 {
            let floor = tower.floors[floorIndex]
            let resolvedFloor = try XCTUnwrap(tower.resolvedFloor(at: floorIndex, runState: runState))

            XCTAssertEqual(
                floor.cardPickups.count,
                5,
                "\(floorIndex + 1)F はギミック追加より拾得カード密度で易しくする想定です"
            )
            XCTAssertTrue(
                (4...6).contains(resolvedFloor.cardPickups.count),
                "\(floorIndex + 1)F は seed 解決後も拾得カード数を4〜6枚の範囲で軽く揺らす想定です"
            )
            XCTAssertTrue(
                resolvedFloor.cardPickups.allSatisfy { $0.point.isInside(boardSize: resolvedFloor.boardSize) },
                "\(floorIndex + 1)F の拾得カードは盤面内へ置く必要があります"
            )
            XCTAssertTrue(
                resolvedFloor.cardPickups.allSatisfy { pickup in
                    pickup.supportCard != nil || pickup.moveCard.map { currentMoveCards.contains($0) } == true
                }
            )
        }
    }

    func testGrowthTowerEarlyPickupCardsCanBeCollectedAsExtraOptions() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))

        let firstCore = makeCore(mode: tower.floors[0].makeGameMode(dungeonID: tower.id))
        playBasicMove(to: GridPoint(x: 1, y: 0), in: firstCore)
        playBasicMove(to: GridPoint(x: 2, y: 0), in: firstCore)
        playBasicMove(to: GridPoint(x: 3, y: 0), in: firstCore)
        XCTAssertTrue(
            firstCore.dungeonInventoryEntries.contains { $0.card == .diagonalUpRight2 && $0.rewardUses == 1 && $0.pickupUses == 0 },
            "1F の追加拾得カードは序盤から寄り道/短縮用の選択肢として拾える想定です"
        )

        let secondCore = makeCore(mode: tower.floors[1].makeGameMode(dungeonID: tower.id))
        playBasicMove(to: GridPoint(x: 7, y: 8), in: secondCore)
        playBasicMove(to: GridPoint(x: 6, y: 8), in: secondCore)
        XCTAssertTrue(
            secondCore.dungeonInventoryEntries.contains { $0.card == .straightLeft2 && $0.rewardUses == 1 && $0.pickupUses == 0 },
            "2F の追加拾得カードは鍵フロアの横移動を楽にする選択肢として拾える想定です"
        )
    }

    func testGrowthTowerStairsBecomeNextFloorStartAcrossAllFloors() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))

        for floorIndex in tower.floors.indices.dropLast() {
            XCTAssertEqual(
                tower.floors[floorIndex + 1].spawnPoint,
                tower.floors[floorIndex].exitPoint,
                "\(floorIndex + 1)F の階段位置から \(floorIndex + 2)F が始まる必要があります"
            )
        }
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
                floor.cardPickups.allSatisfy { $0.moveCard?.displayName != "固定ワープ" },
                "\(floor.title) の拾得カードに退役カードを混ぜない想定です"
            )
            XCTAssertTrue(
                floor.rewardMoveCardsAfterClear.allSatisfy { $0.displayName != "固定ワープ" },
                "\(floor.title) の報酬候補に退役カードを混ぜない想定です"
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
        var hasHealingTile = false
        var hasWarp = false
        var hasSwamp = false
        var hasBrittleFloor = false
        var hasImpassable = false

        for floor in tower.floors {
            var points: [GridPoint] = [floor.spawnPoint, floor.exitPoint]
            points.append(contentsOf: floor.cardPickups.map(\.point))
            points.append(contentsOf: floor.enemies.map(\.position))
            XCTAssertEqual(
                Set(floor.enemies.map(\.position)).count,
                floor.enemies.count,
                "\(floor.title) の敵初期位置は同じマスに重ねません"
            )
            points.append(contentsOf: floor.impassableTilePoints)
            hasImpassable = hasImpassable || !floor.impassableTilePoints.isEmpty
            points.append(contentsOf: floor.tileEffectOverrides.keys)
            hasSwamp = hasSwamp || floor.tileEffectOverrides.values.contains(.swamp)
            for enemy in floor.enemies {
                switch enemy.behavior {
                case .patrol(let path):
                    hasPatrol = true
                    points.append(contentsOf: path)
                    assertPatrolPathCanMove(
                        path,
                        in: floor,
                        context: "\(floor.title) / \(enemy.id)"
                    )
                case .chaser:
                    hasChaser = true
                case .marker, .targetedMarker:
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
                case .hpHalvingTrap(let trapPoints):
                    hasDamageTrap = true
                    points.append(contentsOf: trapPoints)
                case .lavaTile(let lavaPoints, _):
                    hasDamageTrap = true
                    points.append(contentsOf: lavaPoints)
                case .brittleFloor(let brittlePoints, _):
                    hasBrittleFloor = true
                    points.append(contentsOf: brittlePoints)
                case .healingTile(let healingPoints, _):
                    hasHealingTile = true
                    points.append(contentsOf: healingPoints)
                }
            }
            for warpPoints in floor.warpTilePairs.values {
                hasWarp = true
                points.append(contentsOf: warpPoints)
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
        XCTAssertTrue(hasHealingTile)
        XCTAssertTrue(hasWarp)
        XCTAssertTrue(hasSwamp)
        XCTAssertTrue(hasBrittleFloor)
        XCTAssertTrue(hasImpassable)
    }

    func testHealingTilesAppearOnlyInGrowthTowerAtSparseResolvedFloors() throws {
        let growthTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let runState = DungeonRunState(dungeonID: growthTower.id, carriedHP: 3, cardVariationSeed: 12_345)
        let allTowers = DungeonLibrary.shared.dungeons

        let healingFloors = try growthTower.floors.indices.compactMap { index -> (Int, Set<GridPoint>)? in
            let floor = try XCTUnwrap(growthTower.resolvedFloor(at: index, runState: runState))
            let points = floor.hazards.reduce(into: Set<GridPoint>()) { result, hazard in
                if case .healingTile(let healingPoints, let amount) = hazard {
                    XCTAssertEqual(amount, 1)
                    result.formUnion(healingPoints)
                }
            }
            return points.isEmpty ? nil : (index + 1, points)
        }

        XCTAssertEqual(
            healingFloors.map(\.0),
            [6, 12, 16, 19, 40, 50]
        )
        XCTAssertEqual(healingFloors.reduce(0) { $0 + $1.1.count }, 6)

        for tower in allTowers where tower.id != growthTower.id {
            let healingTileCount = tower.floors.reduce(0) { total, floor in
                total + floor.hazards.reduce(0) { floorTotal, hazard in
                    if case .healingTile(let points, _) = hazard {
                        return floorTotal + points.count
                    }
                    return floorTotal
                }
            }
            XCTAssertEqual(healingTileCount, 0, "\(tower.title) には回復マスを置かない想定です")
        }
    }

    func testGrowthTowerResolvedHazardPressureCreatesNoUpgradeWallFrom21F() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let seeds: [UInt64] = [1, 42, 999, 12_345]

        for seed in seeds {
            let runState = DungeonRunState(dungeonID: tower.id, carriedHP: 3, cardVariationSeed: seed)
            let resolvedFloors = try tower.floors.indices.map { floorIndex in
                try XCTUnwrap(tower.resolvedFloor(at: floorIndex, runState: runState))
            }
            let warningBand = resolvedFloors[10..<20]
            let wallBand = resolvedFloors[20..<30]
            let complexBand = resolvedFloors[30..<40]
            let finalBand = resolvedFloors[40..<50]

            XCTAssertTrue(warningBand.allSatisfy { growthTowerDamagePressurePointCount(for: $0) >= 4 })
            XCTAssertTrue(wallBand.allSatisfy { growthTowerDamagePressurePointCount(for: $0) >= 7 })
            XCTAssertTrue(complexBand.allSatisfy { growthTowerDamagePressurePointCount(for: $0) >= 9 })
            XCTAssertTrue(finalBand.allSatisfy { growthTowerDamagePressurePointCount(for: $0) >= 11 })

            XCTAssertTrue(wallBand.allSatisfy { growthTowerStatusTrapPointCount(for: $0) >= 1 })
            XCTAssertTrue(complexBand.allSatisfy { growthTowerStatusTrapPointCount(for: $0) >= 2 })
            XCTAssertTrue(finalBand.allSatisfy { growthTowerStatusTrapPointCount(for: $0) >= 3 })

            let earlyAverage = averageDamagePressure(in: resolvedFloors[0..<10])
            let warningAverage = averageDamagePressure(in: warningBand)
            let wallAverage = averageDamagePressure(in: wallBand)
            XCTAssertGreaterThan(warningAverage, earlyAverage)
            XCTAssertGreaterThan(wallAverage, warningAverage)
        }
    }

    func testGrowthTowerResolvedHazardPressureAddsVisibleBrittleFloorsFrom11F() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let seeds: [UInt64] = [1, 42, 999, 12_345]

        for seed in seeds {
            let runState = DungeonRunState(dungeonID: tower.id, carriedHP: 3, cardVariationSeed: seed)
            let resolvedFloors = try tower.floors.indices.map { floorIndex in
                try XCTUnwrap(tower.resolvedFloor(at: floorIndex, runState: runState))
            }

            XCTAssertTrue(
                resolvedFloors[10..<20].allSatisfy { growthTowerBrittleFloorPointCount(for: $0, initialState: .cracked) >= 1 },
                "seed \(seed) の11-20Fには見えるヒビ床を混ぜます"
            )
            XCTAssertTrue(
                resolvedFloors[20..<40].allSatisfy { growthTowerBrittleFloorPointCount(for: $0, initialState: .cracked) >= 1 },
                "seed \(seed) の21-40Fには見えるヒビ床を混ぜます"
            )
            XCTAssertTrue(
                resolvedFloors[40..<49].allSatisfy { growthTowerBrittleFloorPointCount(for: $0, initialState: .cracked) >= 1 },
                "seed \(seed) の41-49Fには見えるヒビ床を混ぜます"
            )
            XCTAssertEqual(
                growthTowerBrittleFloorPointCount(for: resolvedFloors[49], initialState: nil),
                0,
                "seed \(seed) の50Fには落下先がないため床割れを追加しません"
            )
        }
    }

    func testGrowthTowerResolvedHazardPressureAvoidsPickupsAndRouteBlockers() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let seeds: [UInt64] = [1, 42, 111, 222, 999, 12_345]

        for seed in seeds {
            let runState = DungeonRunState(dungeonID: tower.id, carriedHP: 3, cardVariationSeed: seed)
            for floorIndex in 20..<tower.floors.count {
                let floor = try XCTUnwrap(tower.resolvedFloor(at: floorIndex, runState: runState))
                let blocked = blockedGrowthTowerPickupPoints(for: floor)
                let statusTrapPoints = growthTowerStatusTrapPoints(for: floor)

                XCTAssertTrue(
                    floor.cardPickups.allSatisfy { !blocked.contains($0.point) && !statusTrapPoints.contains($0.point) },
                    "seed \(seed) / \(floorIndex + 1)F の拾得カードが危険マスと重なっています"
                )
                XCTAssertTrue(
                    floor.relicPickups.allSatisfy { !blocked.contains($0.point) && !statusTrapPoints.contains($0.point) },
                    "seed \(seed) / \(floorIndex + 1)F の宝箱が危険マスと重なっています"
                )
                XCTAssertTrue(
                    statusTrapPoints.isDisjoint(with: growthTowerHazardPoints(for: floor)),
                    "seed \(seed) / \(floorIndex + 1)F の状態罠が床罠と重なっています"
                )
                XCTAssertTrue(
                    statusTrapPoints.isDisjoint(with: floor.impassableTilePoints),
                    "seed \(seed) / \(floorIndex + 1)F の状態罠が岩柱と重なっています"
                )
                XCTAssertTrue(
                    hasOrthogonalPath(from: floor.spawnPoint, to: floor.exitPoint, in: floor),
                    "seed \(seed) / \(floorIndex + 1)F は開始地点から階段までの代表導線を残します"
                )
            }
        }
    }

    func testGrowthTowerFixedRocksStaySparseAndDoNotOverlapGimmicks() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))

        for (index, floor) in tower.floors.enumerated() {
            let expectedSecretChamberWalls = floor.fallSecrets
                .filter { $0.destinationFloorIndex == index }
                .reduce(into: Set<GridPoint>()) { result, secret in
                result.formUnion(secret.chamberWallPoints)
            }
            let secretChamberWalls = floor.impassableTilePoints.intersection(expectedSecretChamberWalls)
            let regularImpassablePoints = floor.impassableTilePoints.subtracting(secretChamberWalls)
            if secretChamberWalls.isEmpty {
                XCTAssertTrue(
                    (2...4).contains(regularImpassablePoints.count),
                    "\(floor.title) の固定障害物は 1 フロア 2〜4 個の少量に留めます"
                )
            } else {
                XCTAssertLessThanOrEqual(
                    regularImpassablePoints.count,
                    4,
                    "\(floor.title) の落下専用小部屋以外の固定障害物は少量に留めます"
                )
            }
            if !secretChamberWalls.isEmpty {
                XCTAssertTrue(
                    expectedSecretChamberWalls.isSubset(of: floor.impassableTilePoints),
                    "\(floor.title) の落下専用小部屋の外周壁は固定障害物として配置します"
                )
            }

            let disallowedPoints = disallowedGrowthTowerImpassablePoints(for: floor)
            XCTAssertTrue(
                floor.impassableTilePoints.isDisjoint(with: disallowedPoints),
                "\(floor.title) の固定障害物は開始/階段/鍵/拾得カード/宝箱/敵/罠/ひび割れ/ワープと重ねません"
            )
        }
    }

    func testGrowthTowerMajorGimmicksDoNotOverlap() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let runStates = [
            DungeonRunState(dungeonID: tower.id, carriedHP: 3, cardVariationSeed: 101),
            DungeonRunState(dungeonID: tower.id, carriedHP: 3, cardVariationSeed: 202)
        ]

        for floor in tower.floors {
            let overlaps = majorGrowthTowerGimmickOverlaps(for: floor)
            XCTAssertTrue(
                overlaps.isEmpty,
                "\(floor.title) の主要ギミックは開始/階段/鍵/拾得カード/宝箱/敵/巡回/障害物/罠/ひび割れ/ワープで重ねません: \(overlaps)"
            )
        }
        for runState in runStates {
            for floorIndex in tower.floors.indices {
                let floor = try XCTUnwrap(tower.resolvedFloor(at: floorIndex, runState: runState))
                let overlaps = majorGrowthTowerGimmickOverlaps(for: floor)
                XCTAssertTrue(
                    overlaps.isEmpty,
                    "\(floor.title) の seed 解決後も主要ギミックを重ねません: \(overlaps)"
                )
            }
        }
    }

    func testGrowthTowerFixedRocksLeaveRepresentativeRoutesOpen() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let runState = DungeonRunState(dungeonID: tower.id, carriedHP: 3, cardVariationSeed: 303)

        for floor in tower.floors {
            XCTAssertTrue(
                hasOrthogonalPath(from: floor.spawnPoint, to: floor.exitPoint, in: floor),
                "\(floor.title) は固定障害物を足しても開始地点から階段までの代表導線を残します"
            )
        }
        for floorIndex in tower.floors.indices {
            let floor = try XCTUnwrap(tower.resolvedFloor(at: floorIndex, runState: runState))
            XCTAssertTrue(
                hasOrthogonalPath(from: floor.spawnPoint, to: floor.exitPoint, in: floor),
                "\(floor.title) は seed 解決後の岩柱でも開始地点から階段までの代表導線を残します"
            )
        }
    }

    func testGrowthTowerFixedRocksStopRayCardsAndWatcherSight() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let floor = tower.floors[15]
        let core = makeCore(
            mode: floor.makeGameMode(dungeonID: tower.id, difficulty: tower.difficulty),
            cards: [.rayRight, .kingUpRight, .straightRight2, .straightLeft2, .straightDown2]
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

                XCTAssertTrue(
                    path.contains(enemy.position),
                    "\(floor.title) の巡回兵は初期位置を巡回パス上に置きます"
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
                    "\(floor.title) の巡回パスは開始/階段/拾得カード/ワープ/岩柱/罠/同一ループ以外の他敵と重ねません"
                )
                XCTAssertGreaterThanOrEqual(
                    Set(path).count,
                    4,
                    "\(floor.title) の巡回兵は4マス以上の実巡回路でレール感を持たせます"
                )
                XCTAssertGreaterThanOrEqual(
                    path.count,
                    6,
                    "\(floor.title) の巡回兵は往復込み6マス以上の巡回圧を持たせます"
                )
                if isClosedPatrolLoop(path) {
                    XCTAssertEqual(
                        manhattanDistance(from: path[path.count - 1], to: path[0]),
                        1,
                        "\(floor.title) のループ巡回パスは末尾から先頭へ上下左右1マスで戻れる必要があります"
                    )
                }

                if index >= 8 {
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
            spawn: GridPoint(x: 2, y: 3),
            exit: GridPoint(x: 8, y: 8),
            hp: 3,
            turnLimit: 6,
            enemies: [patrol]
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: GridPoint(x: 3, y: 3), in: core)

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
                if case .brittleFloor(let points, _) = hazard {
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

    func testGrowthTowerBrittleFloorsDoNotLandOnImpassableTiles() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let seeds: [UInt64?] = [nil, 1, 42, 111, 222, 999, 12_345]

        for seed in seeds {
            let runState = seed.map {
                DungeonRunState(dungeonID: tower.id, carriedHP: 3, cardVariationSeed: $0)
            }
            let floors = try tower.floors.indices.map { floorIndex in
                try XCTUnwrap(tower.resolvedFloor(at: floorIndex, runState: runState))
            }

            for floorIndex in floors.indices.dropFirst() {
                let sourceFloor = floors[floorIndex]
                let destinationFloor = floors[floorIndex - 1]
                let collidingPoints = growthTowerBrittleFloorPoints(for: sourceFloor)
                    .intersection(destinationFloor.impassableTilePoints)

                XCTAssertTrue(
                    collidingPoints.isEmpty,
                    "seed \(seed.map(String.init) ?? "base") / \(sourceFloor.title) の床割れは落下先の \(destinationFloor.title) で移動不能マスになってはいけません: \(collidingPoints)"
                )
            }
        }
    }

    func testGrowthTowerAddsOptionalFallTreasureRoomsWithReturnWarps() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let sourceRunState = DungeonRunState(dungeonID: tower.id, carriedHP: 3, cardVariationSeed: 404)
        let secretPairs = [
            (source: 23, destination: 22, secretID: "growth-fall-secret-24-to-23"),
            (source: 35, destination: 34, secretID: "growth-fall-secret-36-to-35"),
            (source: 45, destination: 44, secretID: "growth-fall-secret-46-to-45")
        ]

        for pair in secretPairs {
            let sourceFloor = try XCTUnwrap(tower.resolvedFloor(at: pair.source, runState: sourceRunState))
            let destinationFloor = try XCTUnwrap(tower.resolvedFloor(at: pair.destination, runState: sourceRunState))
            let secret = try XCTUnwrap(destinationFloor.fallSecrets.first { $0.id == pair.secretID })

            XCTAssertEqual(secret.sourceFloorIndex, pair.source)
            XCTAssertEqual(secret.destinationFloorIndex, pair.destination)
            XCTAssertTrue(sourceFloor.fallSecrets.contains(secret))
            XCTAssertTrue(
                sourceFloor.hazards.contains { hazard in
                    if case .brittleFloor(let points, _) = hazard {
                        return points.contains(secret.entrancePoint)
                    }
                    return false
                },
                "\(sourceFloor.title) には落下専用宝箱への崩落入口を固定します"
            )
            XCTAssertTrue(destinationFloor.relicPickups.contains(secret.treasurePickup))
            XCTAssertEqual(
                destinationFloor.tileEffectOverrides[secret.returnWarpPoint],
                .returnWarp(destination: secret.returnDestination)
            )
            XCTAssertTrue(secret.chamberWallPoints.isSubset(of: destinationFloor.impassableTilePoints))
            XCTAssertFalse(
                hasOrthogonalPath(from: destinationFloor.spawnPoint, to: secret.landingPoint, in: destinationFloor),
                "\(destinationFloor.title) の落下専用小部屋は通常移動だけでは入れない想定です"
            )
            assertFallSecretChamberCannotBeEnteredByNormalMovement(
                secret,
                in: destinationFloor,
                dungeonID: tower.id,
                floorIndex: pair.destination
            )
            assertFallSecretChamberRemainsUsableAfterFalling(
                secret,
                in: destinationFloor,
                dungeonID: tower.id,
                floorIndex: pair.destination
            )
            XCTAssertTrue(
                hasOrthogonalPath(from: secret.returnDestination, to: destinationFloor.exitPoint, in: destinationFloor),
                "\(destinationFloor.title) の帰還先から通常ルートへ戻れる必要があります"
            )
        }
    }

    func testGrowthTowerMilestoneFloorsExposeOptionalTreasureDecisions() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let milestoneExpectations: [(index: Int, title: String, relicKinds: Set<DungeonRelicPickupKind>)] = [
            (14, "第二関門・宝箱警戒", [.suspiciousLight]),
            (24, "第三関門・鍵と追跡", [.suspiciousDeep]),
            (34, "第四関門・暗闇巡回", [.suspiciousDeep, .suspiciousLight]),
            (44, "第五関門・呪いと崩落", [.suspiciousDeep])
        ]

        for expectation in milestoneExpectations {
            let floor = tower.floors[expectation.index]
            XCTAssertEqual(floor.title, expectation.title)
            XCTAssertEqual(Set(floor.relicPickups.map(\.kind)), expectation.relicKinds)
            XCTAssertTrue(hasOrthogonalPath(from: floor.spawnPoint, to: floor.exitPoint, in: floor))
            XCTAssertTrue(
                floor.relicPickups.allSatisfy { !blockedGrowthTowerPickupPoints(for: floor).contains($0.point) },
                "\(floor.title) の宝箱は通常ルートを塞がない任意目標として配置します"
            )
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
                "\(floor.title) の鍵マスは階段ロックの鍵として扱います"
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
        assertTurnLimitSlack(for: tower.floors[8], after: core)
    }



    func testRoguelikeTowerGeneratesInfiniteDeterministicFloors() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))
        let runState = DungeonRunState(dungeonID: tower.id, currentFloorIndex: 99, carriedHP: 3, rogueTowerSeed: 12345)

        let first = try XCTUnwrap(tower.resolvedFloor(at: 99, runState: runState))
        let second = try XCTUnwrap(tower.resolvedFloor(at: 99, runState: runState))
        let differentSeed = try XCTUnwrap(
            tower.resolvedFloor(
                at: 99,
                runState: DungeonRunState(dungeonID: tower.id, currentFloorIndex: 99, carriedHP: 3, rogueTowerSeed: 67890)
            )
        )

        XCTAssertTrue(tower.supportsInfiniteFloors)
        XCTAssertTrue(tower.canAdvanceWithinRun(afterFloorIndex: 99))
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, differentSeed)
        XCTAssertEqual(first.title, "試練 100F")
    }

    func testRoguelikeTowerStartsWithFiveInventorySlotsAndKeepsKnightStyle() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))
        let mode = try XCTUnwrap(
            DungeonLibrary.shared.firstFloorMode(
                for: tower,
                movementStyle: .knight,
                dungeonInventoryKindLimit: 9,
                cardVariationSeed: 123
            )
        )
        let runState = try XCTUnwrap(mode.dungeonMetadataSnapshot?.runState)

        XCTAssertEqual(runState.movementStyle, .knight)
        XCTAssertEqual(mode.dungeonRules?.movementStyle, .knight)
        XCTAssertEqual(runState.dungeonInventoryKindLimit, 5)
        XCTAssertEqual(makeCore(mode: mode).dungeonInventoryKindLimit, 5)
    }

    func testRoguelikeTowerHandExpansionIncreasesInventoryLimitAndResetsChance() throws {
        let floor = DungeonFloorDefinition(
            id: "rogue-hand-expansion-test",
            title: "手札拡張テスト",
            boardSize: 5,
            spawnPoint: GridPoint(x: 0, y: 0),
            exitPoint: GridPoint(x: 4, y: 4),
            deckPreset: .standardLight,
            failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 12),
            specialPickups: [
                DungeonSpecialPickupDefinition(
                    id: "rogue-1-hand-expansion",
                    point: GridPoint(x: 1, y: 0),
                    kind: .handExpansion
                )
            ]
        )
        let runState = DungeonRunState(
            dungeonID: "rogue-tower",
            carriedHP: 3,
            dungeonInventoryKindLimit: 5,
            rogueHandExpansionChanceStep: 4,
            rogueTowerSeed: 1
        )
        let mode = floor.makeGameMode(dungeonID: "rogue-tower", difficulty: .roguelike, runState: runState)
        let core = makeCore(mode: mode)

        XCTAssertEqual(core.dungeonInventoryKindLimit, 5)
        playBasicMove(to: GridPoint(x: 1, y: 0), in: core)

        XCTAssertEqual(core.dungeonInventoryKindLimit, 6)
        XCTAssertEqual(core.collectedDungeonSpecialPickupIDs, Set(["rogue-1-hand-expansion"]))

        let advanced = runState.advancedToNextFloor(
            carryoverHP: core.dungeonHP,
            currentFloorMoveCount: core.moveCount,
            currentInventoryEntries: core.dungeonInventoryEntries,
            collectedDungeonSpecialPickupIDs: core.collectedDungeonSpecialPickupIDs
        )
        XCTAssertEqual(advanced.dungeonInventoryKindLimit, 6)
        XCTAssertEqual(advanced.rogueHandExpansionChanceStep, 0)
    }

    func testRoguelikeTowerHandExpansionChanceRisesAndStopsAtNineSlots() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))
        let runState = DungeonRunState(
            dungeonID: tower.id,
            carriedHP: 3,
            dungeonInventoryKindLimit: 5,
            rogueHandExpansionChanceStep: 0,
            rogueTowerSeed: 222
        )
        let missed = runState.advancedToNextFloor(
            carryoverHP: 3,
            currentFloorMoveCount: 2,
            currentInventoryEntries: [],
            collectedDungeonSpecialPickupIDs: []
        )
        XCTAssertEqual(missed.rogueHandExpansionChanceStep, 1)

        let cappedRunState = DungeonRunState(
            dungeonID: tower.id,
            carriedHP: 3,
            dungeonInventoryKindLimit: 9,
            rogueHandExpansionChanceStep: 99,
            rogueTowerSeed: 222
        )
        let cappedFloor = try XCTUnwrap(tower.resolvedFloor(at: 8, runState: cappedRunState))
        XCTAssertTrue(cappedFloor.specialPickups.isEmpty)
    }

    func testRoguelikeTowerHandExpansionSharedRollTargetsEitherFloorOrReward() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))
        let floorSeed = try XCTUnwrap(rogueHandExpansionSeed(targeting: .floorPickup))
        let rewardSeed = try XCTUnwrap(rogueHandExpansionSeed(targeting: .clearReward))
        let floorRunState = DungeonRunState(
            dungeonID: tower.id,
            carriedHP: 3,
            dungeonInventoryKindLimit: 5,
            rogueHandExpansionChanceStep: 99,
            rogueTowerSeed: floorSeed
        )
        let rewardRunState = DungeonRunState(
            dungeonID: tower.id,
            carriedHP: 3,
            dungeonInventoryKindLimit: 5,
            rogueHandExpansionChanceStep: 99,
            rogueTowerSeed: rewardSeed
        )

        let floorPickupFloor = try XCTUnwrap(tower.resolvedFloor(at: 0, runState: floorRunState))
        let rewardFloor = try XCTUnwrap(tower.resolvedFloor(at: 0, runState: rewardRunState))

        XCTAssertEqual(floorPickupFloor.specialPickups.map(\.kind), [.handExpansion])
        XCTAssertTrue(rewardFloor.specialPickups.isEmpty)
        XCTAssertEqual(
            rewardRunState.rogueHandExpansionSpawnSurface(floorIndex: 0, seed: rewardSeed),
            .clearReward
        )
    }

    func testRoguelikeTowerHandExpansionRewardIncreasesInventoryLimitAndResetsChance() throws {
        let runState = DungeonRunState(
            dungeonID: "rogue-tower",
            carriedHP: 3,
            dungeonInventoryKindLimit: 5,
            rogueHandExpansionChanceStep: 4,
            rogueTowerSeed: 1
        )
        let advanced = runState.advancedToNextFloor(
            carryoverHP: 3,
            currentFloorMoveCount: 3,
            rewardSelection: .handExpansion,
            currentRewardOffers: [.handExpansion]
        )

        XCTAssertEqual(advanced.dungeonInventoryKindLimit, 6)
        XCTAssertEqual(advanced.rogueHandExpansionChanceStep, 0)
        XCTAssertEqual(
            advanced.clearedFloorState(for: 0)?.selectedRewardOffers,
            [.handExpansion]
        )
    }

    func testRoguelikeTowerEarlyFloorsPrioritizeTrapBuildResources() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))
        let seeds: [UInt64] = [1, 42, 999, 12_345, 67_890]

        for seed in seeds {
            let runState = DungeonRunState(dungeonID: tower.id, carriedHP: 3, rogueTowerSeed: seed)
            for floorIndex in 0..<10 {
                let floor = try XCTUnwrap(tower.resolvedFloor(at: floorIndex, runState: runState))
                let floorNumber = floorIndex + 1

                XCTAssertFalse(
                    floor.enemies.contains(where: isChaser),
                    "seed \(seed) / 試練塔 \(floorNumber)F は追跡兵を出さず、罠と拾得で序盤ビルドを作ります"
                )

                if floorIndex < 3 {
                    XCTAssertTrue(floor.enemies.isEmpty)
                } else if floorIndex < 5 {
                    XCTAssertLessThanOrEqual(floor.enemies.count, 1)
                    XCTAssertTrue(floor.enemies.allSatisfy { isGuardPost($0) || isWatcher($0) })
                } else {
                    XCTAssertLessThanOrEqual(floor.enemies.count, 2)
                    XCTAssertTrue(floor.enemies.allSatisfy { isGuardPost($0) || isWatcher($0) || isPatrol($0) })
                }

                XCTAssertEqual(floor.cardPickups.count, floorIndex < 5 ? 4 : 5)
                XCTAssertTrue(hasOrthogonalPath(from: floor.spawnPoint, to: floor.exitPoint, in: floor))
            }
        }
    }

    func testRoguelikeTowerEarlyRelicPickupsVaryBySeedAndIncludeSuspiciousLight() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))
        let seeds: [UInt64] = [1, 2, 3, 42, 777, 999, 12_345, 67_890]
        let earlyWindows = [1..<4, 4..<8, 8..<12]
        var signatures = Set<String>()

        for seed in seeds {
            let runState = DungeonRunState(dungeonID: tower.id, carriedHP: 3, rogueTowerSeed: seed)
            let floors = try (1..<12).map { floorIndex in
                try XCTUnwrap(tower.resolvedFloor(at: floorIndex, runState: runState))
            }
            let signature = floors.enumerated()
                .flatMap { offset, floor in
                    floor.relicPickups.map { "\(offset + 2):\($0.kind)" }
                }
                .joined(separator: "|")
            signatures.insert(signature)

            for window in earlyWindows {
                let windowFloors = try window.map { floorIndex in
                    try XCTUnwrap(tower.resolvedFloor(at: floorIndex, runState: runState))
                }
                XCTAssertTrue(
                    windowFloors.contains { !$0.relicPickups.isEmpty },
                    "seed \(seed) / 試練塔 \(window.lowerBound + 1)F-\(window.upperBound)F は宝箱寄り道を保証します"
                )
            }

            let earlyKinds = floors.flatMap { $0.relicPickups.map(\.kind) }
            XCTAssertTrue(
                earlyKinds.contains(.suspiciousLight),
                "seed \(seed) / 試練塔2-12Fには軽い怪しい宝箱を少なくとも1つ出します"
            )
            XCTAssertFalse(
                earlyKinds.contains(.suspiciousDeep),
                "seed \(seed) / 試練塔2-12Fでは深層の怪しい宝箱を出しません"
            )

            for (offset, floor) in floors.enumerated() {
                let floorIndex = offset + 1
                let blockedPickupPoints = floor.impassableTilePoints
                    .union(floor.tileEffectOverrides.keys)
                    .union(floor.warpTilePairs.values.flatMap { $0 })
                    .union(growthTowerHazardPoints(for: floor))
                    .union(floor.enemies.flatMap { enemy in
                        if case .patrol(let path) = enemy.behavior { return path }
                        return [enemy.position]
                    })
                    .union(floor.cardPickups.map(\.point))
                    .union(floor.specialPickups.map(\.point))
                    .union([floor.spawnPoint, floor.exitPoint])

                let repeatFloor = try XCTUnwrap(tower.resolvedFloor(at: floorIndex, runState: runState))
                XCTAssertEqual(floor, repeatFloor)

                for pickup in floor.relicPickups {
                    XCTAssertFalse(
                        blockedPickupPoints.contains(pickup.point),
                        "seed \(seed) / 試練塔 \(floorIndex + 1)F の序盤宝箱は他要素と重ねません"
                    )
                    XCTAssertTrue(
                        hasOrthogonalPath(from: floor.spawnPoint, to: pickup.point, in: floor),
                        "seed \(seed) / 試練塔 \(floorIndex + 1)F の序盤宝箱へ物理到達できる必要があります"
                    )
                    XCTAssertTrue(
                        hasOrthogonalPath(from: pickup.point, to: floor.exitPoint, in: floor),
                        "seed \(seed) / 試練塔 \(floorIndex + 1)F の序盤宝箱から階段へ戻れる必要があります"
                    )
                }
            }
        }

        XCTAssertGreaterThan(signatures.count, 1, "試練塔序盤の宝箱階や種別は seed によって揺れる必要があります")
    }

    func testRoguelikeTowerChasersStartAfterTenthFloor() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))
        let seeds: [UInt64] = [1, 2, 3, 42, 777, 999, 12_345, 67_890]
        var foundChaserAfterTenthFloor = false

        for seed in seeds {
            let runState = DungeonRunState(dungeonID: tower.id, carriedHP: 3, rogueTowerSeed: seed)
            for floorIndex in 10..<20 {
                let floor = try XCTUnwrap(tower.resolvedFloor(at: floorIndex, runState: runState))
                let chaserCount = floor.enemies.filter(isChaser).count
                if chaserCount > 0 {
                    foundChaserAfterTenthFloor = true
                }
                if floorIndex < 15 {
                    XCTAssertLessThanOrEqual(
                        chaserCount,
                        1,
                        "試練塔11-15Fの追跡兵は1フロア最大1体に抑えます"
                    )
                }
            }
        }

        XCTAssertTrue(foundChaserAfterTenthFloor, "試練塔11F以降では追跡兵が出現しうる必要があります")
    }

    func testRoguelikeTowerStairsBecomeNextFloorStart() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))

        for seed in [1, 42, 999, 12_345] as [UInt64] {
            let runState = DungeonRunState(dungeonID: tower.id, carriedHP: 3, rogueTowerSeed: seed)
            for floorIndex in [0, 1, 2, 7, 15, 30, 75] {
                let floor = try XCTUnwrap(tower.resolvedFloor(at: floorIndex, runState: runState))
                let nextFloor = try XCTUnwrap(tower.resolvedFloor(at: floorIndex + 1, runState: runState))

                XCTAssertEqual(
                    nextFloor.spawnPoint,
                    floor.exitPoint,
                    "seed \(seed) / \(floorIndex + 1)F の階段位置から \(floorIndex + 2)F が始まる必要があります"
                )
                XCTAssertTrue(hasOrthogonalPath(from: nextFloor.spawnPoint, to: nextFloor.exitPoint, in: nextFloor))
            }
        }
    }

    func testGrowthTowerResolvedWatchersFaceWidestOpenSightLine() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let seeds: [UInt64] = [101, 202, 303, 404, 505]
        var checkedWatcherCount = 0
        var checkedEdgeWatcherCount = 0

        for seed in seeds {
            let runState = DungeonRunState(dungeonID: tower.id, carriedHP: 3, cardVariationSeed: seed)
            for floorIndex in tower.floors.indices {
                let floor = try XCTUnwrap(tower.resolvedFloor(at: floorIndex, runState: runState))
                let result = assertWatchersFaceWidestOpenSightLine(
                    in: floor,
                    context: "seed \(seed) / 成長塔 \(floorIndex + 1)F"
                )
                checkedWatcherCount += result.watcherCount
                checkedEdgeWatcherCount += result.edgeWatcherCount
            }
        }

        XCTAssertGreaterThan(checkedWatcherCount, 0)
        XCTAssertGreaterThan(
            checkedEdgeWatcherCount,
            0,
            "壁際の見張りも、盤外方向ではなく有効な射線が広い方向を向く必要があります"
        )
    }

    func testRoguelikeTowerGeneratedWatchersFaceWidestOpenSightLineDeterministically() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))
        let seeds: [UInt64] = [1, 42, 999, 12_345]
        let floorIndexes = [0, 1, 5, 12, 30, 75]
        var checkedWatcherCount = 0
        var checkedEdgeWatcherCount = 0

        for seed in seeds {
            let runState = DungeonRunState(dungeonID: tower.id, carriedHP: 3, rogueTowerSeed: seed)
            for floorIndex in floorIndexes {
                let first = try XCTUnwrap(tower.resolvedFloor(at: floorIndex, runState: runState))
                let second = try XCTUnwrap(tower.resolvedFloor(at: floorIndex, runState: runState))
                XCTAssertEqual(first.enemies, second.enemies)

                let result = assertWatchersFaceWidestOpenSightLine(
                    in: first,
                    context: "seed \(seed) / 試練塔 \(floorIndex + 1)F"
                )
                checkedWatcherCount += result.watcherCount
                checkedEdgeWatcherCount += result.edgeWatcherCount
            }
        }

        XCTAssertGreaterThan(checkedWatcherCount, 0)
        XCTAssertGreaterThan(
            checkedEdgeWatcherCount,
            0,
            "試練塔の壁際見張りも、生成時に広い射線方向を選ぶ必要があります"
        )
    }

    func testRoguelikeTowerGeneratedFloorsStayInsideBoardAndKeepPhysicalRoute() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))
        let runState = DungeonRunState(dungeonID: tower.id, carriedHP: 3, rogueTowerSeed: 2468)

        for floorIndex in [0, 1, 7, 15, 30, 75] {
            let floor = try XCTUnwrap(tower.resolvedFloor(at: floorIndex, runState: runState))
            var points: [GridPoint] = [floor.spawnPoint, floor.exitPoint]
            points.append(contentsOf: floor.cardPickups.map(\.point))
            points.append(contentsOf: floor.specialPickups.map(\.point))
            points.append(contentsOf: floor.relicPickups.map(\.point))
            points.append(contentsOf: floor.enemies.map(\.position))
            points.append(contentsOf: floor.impassableTilePoints)
            points.append(contentsOf: floor.tileEffectOverrides.keys)
            points.append(contentsOf: floor.warpTilePairs.values.flatMap { $0 })
            points.append(contentsOf: growthTowerHazardPoints(for: floor))
            for enemy in floor.enemies {
                if case .patrol(let path) = enemy.behavior {
                    points.append(contentsOf: path)
                    assertPatrolPathCanMove(
                        path,
                        in: floor,
                        context: "seed 2468 / 試練塔 \(floorIndex + 1)F / \(enemy.id)"
                    )
                }
            }

            XCTAssertEqual(floor.boardSize, 9)
            XCTAssertTrue(points.allSatisfy { $0.isInside(boardSize: floor.boardSize) })
            let blockedPickupPoints = floor.impassableTilePoints
                .union(floor.tileEffectOverrides.keys)
                .union(floor.warpTilePairs.values.flatMap { $0 })
                .union(growthTowerHazardPoints(for: floor))
                .union(floor.enemies.flatMap { enemy in
                    if case .patrol(let path) = enemy.behavior { return path }
                    return [enemy.position]
                })
            XCTAssertTrue(floor.cardPickups.allSatisfy { !blockedPickupPoints.contains($0.point) })
            XCTAssertTrue(floor.specialPickups.allSatisfy { !blockedPickupPoints.contains($0.point) })
            XCTAssertTrue(floor.relicPickups.allSatisfy { !blockedPickupPoints.contains($0.point) })
            XCTAssertTrue(hasOrthogonalPath(from: floor.spawnPoint, to: floor.exitPoint, in: floor))
        }
    }

    func testRoguelikeTowerGeneratedPatrolsAlwaysHaveLiveRoutes() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))
        let seeds: [UInt64] = [1, 2, 3, 42, 777, 2_468, 12_345, 67_890]
        let floorIndexes = [5, 7, 12, 15, 30, 41, 75]
        var checkedPatrolCount = 0

        for seed in seeds {
            let runState = DungeonRunState(dungeonID: tower.id, carriedHP: 3, rogueTowerSeed: seed)
            for floorIndex in floorIndexes {
                let floor = try XCTUnwrap(tower.resolvedFloor(at: floorIndex, runState: runState))
                for enemy in floor.enemies {
                    guard case .patrol(let path) = enemy.behavior else { continue }
                    checkedPatrolCount += 1
                    assertPatrolPathCanMove(
                        path,
                        in: floor,
                        context: "seed \(seed) / 試練塔 \(floorIndex + 1)F / \(enemy.id)"
                    )
                }
            }
        }

        XCTAssertGreaterThan(checkedPatrolCount, 0)
    }

    func testRoguelikeTowerImpassableTilesNeverCreatePhysicalDeadEnds() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))
        let seeds: [UInt64] = [1, 2, 3, 777, 2_468, 12_345, 67_890]
        let floorIndexes = [0, 1, 5, 12, 30, 75]

        for seed in seeds {
            let runState = DungeonRunState(dungeonID: tower.id, carriedHP: 3, rogueTowerSeed: seed)
            for floorIndex in floorIndexes {
                let floor = try XCTUnwrap(tower.resolvedFloor(at: floorIndex, runState: runState))
                let disallowedImpassablePoints = disallowedGrowthTowerImpassablePoints(for: floor)

                XCTAssertTrue(
                    hasOrthogonalPath(from: floor.spawnPoint, to: floor.exitPoint, in: floor),
                    "seed \(seed) / \(floorIndex + 1)F は移動不能マスだけで出口経路を塞いではいけません"
                )
                XCTAssertTrue(
                    floor.impassableTilePoints.isDisjoint(with: disallowedImpassablePoints),
                    "seed \(seed) / \(floorIndex + 1)F の移動不能マスが他要素と重なっています"
                )
                assertWarpPairsAvoidOrthogonalAdjacency(
                    in: floor,
                    context: "seed \(seed) / \(floorIndex + 1)F"
                )
            }
        }
    }

    func testRoguelikeTowerDifficultyDensityIncreasesWithFloorIndex() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))
        let runState = DungeonRunState(dungeonID: tower.id, carriedHP: 3, rogueTowerSeed: 1357)
        let early = try XCTUnwrap(tower.resolvedFloor(at: 0, runState: runState))
        let deep = try XCTUnwrap(tower.resolvedFloor(at: 30, runState: runState))

        XCTAssertGreaterThan(deep.enemies.count, early.enemies.count)
        XCTAssertGreaterThan(growthTowerHazardPoints(for: deep).count, growthTowerHazardPoints(for: early).count)
        XCTAssertFalse(deep.tileEffectOverrides.isEmpty)
        XCTAssertFalse(deep.warpTilePairs.isEmpty)
    }

    func testRoguelikeTowerDeepFloorsCanGenerateConnectedLavaFields() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))
        let seeds: [UInt64] = [1, 42, 999, 12_345, 67_890]
        var foundConnectedLavaField = false

        for seed in seeds {
            let runState = DungeonRunState(dungeonID: tower.id, carriedHP: 3, rogueTowerSeed: seed)
            for floorIndex in [40, 50, 75] {
                let floor = try XCTUnwrap(tower.resolvedFloor(at: floorIndex, runState: runState))
                let lavaFields = lavaTileFields(in: floor)
                if lavaFields.contains(where: { $0.count >= 4 }) {
                    foundConnectedLavaField = true
                }
                for lavaPoints in lavaFields where lavaPoints.count >= 2 {
                    XCTAssertTrue(
                        isSingleOrthogonalComponent(lavaPoints),
                        "seed \(seed) / 試練塔 \(floorIndex + 1)F の溶岩塊はまとまった地形として読める必要があります"
                    )
                }
            }
        }

        XCTAssertTrue(foundConnectedLavaField, "試練塔深層では2x2以上の溶岩塊が生成されうる必要があります")
    }

    func testRoguelikeTowerDeepFloorsGuaranteeRelicPickupsWithinCadence() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))
        let seeds: [UInt64] = [1, 42, 999, 12_345, 67_890]

        for seed in seeds {
            let runState = DungeonRunState(dungeonID: tower.id, carriedHP: 3, rogueTowerSeed: seed)
            for windowStart in stride(from: 30, through: 46, by: 4) {
                let floors = try (windowStart..<(windowStart + 4)).map { floorIndex in
                    try XCTUnwrap(tower.resolvedFloor(at: floorIndex, runState: runState))
                }
                XCTAssertTrue(
                    floors.contains { !$0.relicPickups.isEmpty },
                    "seed \(seed) / 試練塔 \(windowStart + 1)F-\(windowStart + 4)F は宝箱寄り道を保証します"
                )
            }

            for windowStart in stride(from: 50, through: 65, by: 3) {
                let floors = try (windowStart..<(windowStart + 3)).map { floorIndex in
                    try XCTUnwrap(tower.resolvedFloor(at: floorIndex, runState: runState))
                }
                XCTAssertTrue(
                    floors.contains { !$0.relicPickups.isEmpty },
                    "seed \(seed) / 試練塔 \(windowStart + 1)F-\(windowStart + 3)F は深層宝箱寄り道を保証します"
                )
            }
        }
    }

    func testRoguelikeTowerDeepRelicPickupsStayReachableAndNonOverlapping() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))
        let seeds: [UInt64] = [1, 42, 999, 12_345]
        let floorIndexes = [30, 34, 38, 50, 53, 56, 65, 75]

        for seed in seeds {
            let runState = DungeonRunState(dungeonID: tower.id, carriedHP: 3, rogueTowerSeed: seed)
            for floorIndex in floorIndexes {
                let floor = try XCTUnwrap(tower.resolvedFloor(at: floorIndex, runState: runState))
                let blockedPickupPoints = floor.impassableTilePoints
                    .union(floor.tileEffectOverrides.keys)
                    .union(floor.warpTilePairs.values.flatMap { $0 })
                    .union(growthTowerHazardPoints(for: floor))
                    .union(floor.enemies.flatMap { enemy in
                        if case .patrol(let path) = enemy.behavior { return path }
                        return [enemy.position]
                    })
                    .union(floor.cardPickups.map(\.point))
                    .union(floor.specialPickups.map(\.point))

                XCTAssertTrue(hasOrthogonalPath(from: floor.spawnPoint, to: floor.exitPoint, in: floor))
                for pickup in floor.relicPickups {
                    XCTAssertFalse(
                        blockedPickupPoints.contains(pickup.point),
                        "seed \(seed) / 試練塔 \(floorIndex + 1)F の宝箱は他要素と重ねません"
                    )
                    XCTAssertTrue(
                        hasOrthogonalPath(from: floor.spawnPoint, to: pickup.point, in: floor),
                        "seed \(seed) / 試練塔 \(floorIndex + 1)F の宝箱へ物理到達できる必要があります"
                    )
                    XCTAssertTrue(
                        hasOrthogonalPath(from: pickup.point, to: floor.exitPoint, in: floor),
                        "seed \(seed) / 試練塔 \(floorIndex + 1)F の宝箱から階段へ戻れる必要があります"
                    )
                }
            }
        }
    }

    func testRoguelikeTowerDeepThemesRemainDeterministicAndRoutable() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))
        let seeds: [UInt64] = [1, 42, 999, 12_345]
        let floorIndexes = [50, 51, 52, 60, 75, 99]

        for seed in seeds {
            let runState = DungeonRunState(dungeonID: tower.id, carriedHP: 3, rogueTowerSeed: seed)
            for floorIndex in floorIndexes {
                let first = try XCTUnwrap(tower.resolvedFloor(at: floorIndex, runState: runState))
                let second = try XCTUnwrap(tower.resolvedFloor(at: floorIndex, runState: runState))

                XCTAssertEqual(first, second)
                XCTAssertTrue(
                    hasOrthogonalPath(from: first.spawnPoint, to: first.exitPoint, in: first),
                    "seed \(seed) / 試練塔 \(floorIndex + 1)F は深層テーマ後も物理導線を残します"
                )
            }
        }
    }

    func testRoguelikeTowerCanGenerateRelicBreakTrapsWithoutOverlaps() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))
        let seeds: [UInt64] = [1, 42, 999, 12_345, 67_890]
        let floorIndexes = [12, 18, 30, 75]
        var foundRelicBreakTrap = false

        for seed in seeds {
            let runState = DungeonRunState(dungeonID: tower.id, carriedHP: 3, rogueTowerSeed: seed)
            for floorIndex in floorIndexes {
                let floor = try XCTUnwrap(tower.resolvedFloor(at: floorIndex, runState: runState))
                let relicBreakPoints = Set(floor.tileEffectOverrides.compactMap { point, effect in
                    effect == .relicBreakTrap ? point : nil
                })
                guard !relicBreakPoints.isEmpty else { continue }

                foundRelicBreakTrap = true
                let disallowedPoints = disallowedGrowthTowerImpassablePoints(for: floor)
                XCTAssertTrue(
                    relicBreakPoints.isDisjoint(with: disallowedPoints.subtracting(relicBreakPoints)),
                    "seed \(seed) / \(floorIndex + 1)F のレリック破壊罠が他要素と重なっています"
                )
                XCTAssertTrue(hasOrthogonalPath(from: floor.spawnPoint, to: floor.exitPoint, in: floor))
            }
        }

        XCTAssertTrue(foundRelicBreakTrap)
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
        XCTAssertEqual(tower.floors.count, 6)
        XCTAssertTrue(tower.floors.allSatisfy { $0.boardSize == 9 })
        XCTAssertTrue(tower.floors.allSatisfy { !$0.cardPickups.isEmpty })
        XCTAssertEqual(tower.floors[0].rewardMoveCardsAfterClear.count, 3)
        XCTAssertEqual(tower.floors[1].rewardMoveCardsAfterClear.count, 3)
        XCTAssertEqual(tower.floors[2].rewardMoveCardsAfterClear.count, 3)
        XCTAssertEqual(tower.floors[3].rewardMoveCardsAfterClear.count, 3)
        XCTAssertEqual(tower.floors[4].rewardMoveCardsAfterClear.count, 3)
        XCTAssertTrue(tower.floors[5].rewardMoveCardsAfterClear.isEmpty)

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
        let firstFloors = try tower.floors.indices.map { floorIndex in
            try XCTUnwrap(tower.resolvedFloor(at: floorIndex, runState: firstRunState))
        }
        let secondFloors = try tower.floors.indices.map { floorIndex in
            try XCTUnwrap(tower.resolvedFloor(at: floorIndex, runState: secondRunState))
        }

        XCTAssertEqual(firstRunState.cardVariationSeed, 42)
        XCTAssertEqual(secondRunState.cardVariationSeed, 42)
        XCTAssertEqual(firstFloors, secondFloors)
        XCTAssertEqual(firstFloor.cardPickups, secondFloor.cardPickups)
        XCTAssertEqual(firstFloor.rewardMoveCardsAfterClear, secondFloor.rewardMoveCardsAfterClear)
        XCTAssertEqual(firstMode.dungeonRules?.cardPickups, firstFloor.cardPickups)

        let core = makeCore(mode: firstMode)
        XCTAssertEqual(core.activeDungeonCardPickups, firstFloor.cardPickups)
    }

    func testGrowthTowerVariationChangesAcrossSeedsAndKeepsSafeCells() throws {
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

        let firstFloors = try tower.floors.indices.map { floorIndex in
            try XCTUnwrap(tower.resolvedFloor(at: floorIndex, runState: firstRunState))
        }
        let secondFloors = try tower.floors.indices.map { floorIndex in
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
        XCTAssertNotEqual(
            firstFloors.map(\.impassableTilePoints) + firstFloors.map(growthTowerHazardPoints),
            secondFloors.map(\.impassableTilePoints) + secondFloors.map(growthTowerHazardPoints),
            "seed が違うランでは、カード以外の岩柱/床ギミック配置や個数も変わる想定です"
        )

        for floor in firstFloors {
            let blocked = blockedGrowthTowerPickupPoints(for: floor)
            XCTAssertTrue(floor.cardPickups.allSatisfy { !blocked.contains($0.point) })
            XCTAssertTrue(floor.relicPickups.allSatisfy { !blocked.contains($0.point) })
        }
    }

    func testGrowthTowerControlledVariationMovesEnemiesKeysWarpsAndStairs() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let firstRunState = DungeonRunState(dungeonID: tower.id, carriedHP: 3, cardVariationSeed: 111)
        let secondRunState = DungeonRunState(dungeonID: tower.id, carriedHP: 3, cardVariationSeed: 222)

        let firstFloors = try tower.floors.indices.map {
            try XCTUnwrap(tower.resolvedFloor(at: $0, runState: firstRunState))
        }
        let secondFloors = try tower.floors.indices.map {
            try XCTUnwrap(tower.resolvedFloor(at: $0, runState: secondRunState))
        }

        XCTAssertNotEqual(firstFloors.map(\.exitPoint), secondFloors.map(\.exitPoint))
        XCTAssertNotEqual(firstFloors.flatMap(\.enemies), secondFloors.flatMap(\.enemies))
        XCTAssertNotEqual(
            firstFloors.compactMap(\.exitLock?.unlockPoint),
            secondFloors.compactMap(\.exitLock?.unlockPoint)
        )
        XCTAssertNotEqual(
            firstFloors.flatMap { $0.warpTilePairs.values.flatMap { $0 } },
            secondFloors.flatMap { $0.warpTilePairs.values.flatMap { $0 } }
        )

        for seed in [1, 42, 111, 222, 999, 12_345] as [UInt64] {
            let runState = DungeonRunState(dungeonID: tower.id, carriedHP: 3, cardVariationSeed: seed)
            let resolvedFloors = try tower.floors.indices.map {
                try XCTUnwrap(tower.resolvedFloor(at: $0, runState: runState))
            }

            for (floorIndex, resolvedFloor) in resolvedFloors.enumerated() {
                let baseFloor = tower.floors[floorIndex]
                XCTAssertEqual(resolvedFloor.enemies.count, baseFloor.enemies.count)
                XCTAssertEqual(
                    resolvedFloor.enemies.map { enemyBehaviorKind($0.behavior) },
                    baseFloor.enemies.map { enemyBehaviorKind($0.behavior) },
                    "\(resolvedFloor.title) は敵種/敵数を維持したまま配置だけ揺らします"
                )
                XCTAssertEqual(resolvedFloor.exitLock != nil, baseFloor.exitLock != nil)
                XCTAssertEqual(resolvedFloor.warpTilePairs.mapValues(\.count), baseFloor.warpTilePairs.mapValues(\.count))
                assertWarpPairsAvoidOrthogonalAdjacency(
                    in: resolvedFloor,
                    context: "seed \(seed) / \(resolvedFloor.title)"
                )

                for enemy in resolvedFloor.enemies {
                    if case .patrol(let path) = enemy.behavior {
                        XCTAssertTrue(isOrthogonalStepPath(path), "\(resolvedFloor.title) の巡回路は上下左右1マス連続にします")
                        assertPatrolPathCanMove(
                            path,
                            in: resolvedFloor,
                            context: "seed \(seed) / \(resolvedFloor.title) / \(enemy.id)"
                        )
                    }
                }
                if let unlockPoint = resolvedFloor.exitLock?.unlockPoint {
                    XCTAssertTrue(
                        hasOrthogonalPath(from: resolvedFloor.spawnPoint, to: unlockPoint, in: resolvedFloor),
                        "\(resolvedFloor.title) は開始地点から鍵までの代表導線を残します"
                    )
                    XCTAssertTrue(
                        hasOrthogonalPath(from: unlockPoint, to: resolvedFloor.exitPoint, in: resolvedFloor),
                        "\(resolvedFloor.title) は鍵から階段までの代表導線を残します"
                    )
                }
            }

            XCTAssertEqual(resolvedFloors[0].spawnPoint, tower.floors[0].spawnPoint)
            for floorIndex in resolvedFloors.indices.dropLast() {
                XCTAssertEqual(
                    resolvedFloors[floorIndex].exitPoint,
                    resolvedFloors[floorIndex + 1].spawnPoint,
                    "\(floorIndex + 1)F の階段位置を次階の開始地点へ接続します"
                )
            }
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

    func testWeightedRewardPoolHonorsZeroWeightAndRelicReservation() {
        let entries = [
            DungeonWeightedRewardPoolEntry(item: .move(.straightRight2), weight: 0),
            DungeonWeightedRewardPoolEntry(item: .relic(.glowingHeart), weight: 100),
            DungeonWeightedRewardPoolEntry(item: .move(.rayRight), weight: 100)
        ]

        let drawn = DungeonWeightedRewardPools.drawUniquePlayables(
            from: entries,
            count: 3,
            seed: 1,
            floorIndex: 0,
            salt: 0xBEEF
        )

        XCTAssertEqual(drawn, [.move(.rayRight)])
    }

    func testFloorPickupPoolCanDrawSupportButNeverRelic() {
        let entries = [
            DungeonWeightedRewardPoolEntry(item: .move(.straightRight2), weight: 1),
            DungeonWeightedRewardPoolEntry(item: .support(.refillEmptySlots), weight: 1),
            DungeonWeightedRewardPoolEntry(item: .relic(.glowingHeart), weight: 1_000)
        ]
        let drawn = (1...120).flatMap { seed in
            DungeonWeightedRewardPools.drawUniqueOffers(
                from: entries,
                context: .floorPickup,
                count: 1,
                seed: UInt64(seed),
                floorIndex: 0,
                salt: 0xF100
            )
        }

        XCTAssertTrue(drawn.contains(.playable(.support(.refillEmptySlots))))
        XCTAssertFalse(drawn.contains { $0.relic != nil })
    }

    func testFastClearRewardBonusRaisesSupportAndRelicDraws() {
        let entries = [
            DungeonWeightedRewardPoolEntry(item: .move(.straightRight2), weight: 1),
            DungeonWeightedRewardPoolEntry(item: .support(.refillEmptySlots), weight: 1),
            DungeonWeightedRewardPoolEntry(item: .relic(.glowingHeart), weight: 1)
        ]
        let normalDraws = (1...300).map { seed in
            DungeonWeightedRewardPools.drawUniqueOffers(
                from: entries,
                context: .clearReward,
                count: 1,
                seed: UInt64(seed),
                floorIndex: 10,
                salt: 0xC1EA,
                tuning: DungeonRewardDrawTuning(clearMoveCount: 12, turnLimit: 12)
            ).first
        }
        let fastDraws = (1...300).map { seed in
            DungeonWeightedRewardPools.drawUniqueOffers(
                from: entries,
                context: .clearReward,
                count: 1,
                seed: UInt64(seed),
                floorIndex: 10,
                salt: 0xC1EA,
                tuning: DungeonRewardDrawTuning(clearMoveCount: 6, turnLimit: 12)
            ).first
        }
        let normalBonusCount = normalDraws.filter { $0?.move == nil }.count
        let fastBonusCount = fastDraws.filter { $0?.move == nil }.count

        XCTAssertGreaterThan(fastBonusCount, normalBonusCount)
    }

    func testRewardCategoryBonusPointsRaiseSupportAndRelicDraws() {
        let entries = [
            DungeonWeightedRewardPoolEntry(item: .move(.straightRight2), weight: 1),
            DungeonWeightedRewardPoolEntry(item: .support(.refillEmptySlots), weight: 1),
            DungeonWeightedRewardPoolEntry(item: .relic(.glowingHeart), weight: 1)
        ]
        func draws(tuning: DungeonRewardDrawTuning) -> [DungeonRewardOffer?] {
            (1...2_000).map { seed in
                DungeonWeightedRewardPools.drawUniqueOffers(
                    from: entries,
                    context: .clearReward,
                    count: 1,
                    seed: UInt64(seed),
                    floorIndex: 10,
                    salt: 0xC47E,
                    tuning: tuning
                ).first
            }
        }

        let normalDraws = draws(tuning: DungeonRewardDrawTuning(clearMoveCount: 12, turnLimit: 12))
        let supportBonusDraws = draws(
            tuning: DungeonRewardDrawTuning(
                clearMoveCount: 12,
                turnLimit: 12,
                supportCategoryBonusPoints: 5
            )
        )
        let relicBonusDraws = draws(
            tuning: DungeonRewardDrawTuning(
                clearMoveCount: 12,
                turnLimit: 12,
                relicCategoryBonusPoints: 2
            )
        )

        XCTAssertGreaterThan(
            supportBonusDraws.filter { $0?.support != nil }.count,
            normalDraws.filter { $0?.support != nil }.count
        )
        XCTAssertGreaterThan(
            relicBonusDraws.filter { $0?.relic != nil }.count,
            normalDraws.filter { $0?.relic != nil }.count
        )
    }

    func testDefeatingEnemiesTracksFloorRewardBonusCountAcrossMovementAndSpells() throws {
        let stompedEnemy = EnemyDefinition(
            id: "stomped",
            name: "番兵",
            position: GridPoint(x: 1, y: 0),
            behavior: .guardPost
        )
        let spellEnemy = EnemyDefinition(
            id: "spell",
            name: "追跡兵",
            position: GridPoint(x: 3, y: 3),
            behavior: .chaser
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            turnLimit: 8,
            enemies: [stompedEnemy, spellEnemy],
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            runState: DungeonRunState(
                dungeonID: "growth-tower",
                carriedHP: 3,
                rewardInventoryEntries: [DungeonInventoryEntry(card: .straightRight2, rewardUses: 1)],
                relicEntries: [
                    DungeonRelicEntry(relicID: .slayerPouch),
                    DungeonRelicEntry(relicID: .hunterBanner)
                ]
            )
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: stompedEnemy.position, in: core)

        XCTAssertEqual(core.currentFloorDefeatedEnemyCount, 1)
        XCTAssertEqual(core.enemyStates.map(\.id), [spellEnemy.id])

        XCTAssertTrue(core.addDungeonInventorySupportCardForTesting(.singleAnnihilationSpell, rewardUses: 1))
        let supportIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.topCard?.supportCard == .singleAnnihilationSpell })
        XCTAssertTrue(core.beginTargetedSupportCardSelection(at: supportIndex))
        XCTAssertTrue(core.playTargetedSupportCard(at: core.enemyStates[0].position))

        XCTAssertEqual(core.currentFloorDefeatedEnemyCount, 2)
        XCTAssertTrue(core.enemyStates.isEmpty)
    }

    func testAnnihilationSpellCountsEveryDefeatedEnemyForFloorRewardBonus() throws {
        let enemies = [
            EnemyDefinition(id: "a", name: "番兵", position: GridPoint(x: 2, y: 2), behavior: .guardPost),
            EnemyDefinition(id: "b", name: "番兵", position: GridPoint(x: 3, y: 3), behavior: .guardPost)
        ]
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            turnLimit: 8,
            enemies: enemies,
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            runState: DungeonRunState(dungeonID: "growth-tower", carriedHP: 3)
        )
        let core = makeCore(mode: mode)

        XCTAssertTrue(core.addDungeonInventorySupportCardForTesting(.annihilationSpell, rewardUses: 1))
        let supportIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.topCard?.supportCard == .annihilationSpell })
        core.playSupportCard(at: supportIndex)

        XCTAssertEqual(core.currentFloorDefeatedEnemyCount, 2)
        XCTAssertTrue(core.enemyStates.isEmpty)
    }

    func testIntimidationHornSkipsOnlyOneEnemyTurnAfterDefeatWithRemainingEnemy() throws {
        let stompedEnemy = EnemyDefinition(
            id: "stomped",
            name: "番兵",
            position: GridPoint(x: 1, y: 0),
            behavior: .guardPost
        )
        let patrol = EnemyDefinition(
            id: "patrol",
            name: "巡回兵",
            position: GridPoint(x: 3, y: 3),
            behavior: .patrol(path: [
                GridPoint(x: 3, y: 3),
                GridPoint(x: 4, y: 3)
            ])
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            turnLimit: 8,
            enemies: [stompedEnemy, patrol],
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            runState: DungeonRunState(
                dungeonID: "growth-tower",
                carriedHP: 3,
                relicEntries: [DungeonRelicEntry(relicID: .intimidationHorn)]
            )
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: stompedEnemy.position, in: core)

        let remainingPatrol = try XCTUnwrap(core.enemyStates.first { $0.id == patrol.id })
        XCTAssertEqual(remainingPatrol.position, GridPoint(x: 3, y: 3))
        XCTAssertEqual(core.currentFloorDefeatedEnemyCount, 1)

        playBasicMove(to: GridPoint(x: 1, y: 1), in: core)

        let movedPatrol = try XCTUnwrap(core.enemyStates.first { $0.id == patrol.id })
        XCTAssertEqual(movedPatrol.position, GridPoint(x: 4, y: 3))
    }

    func testSlayerMedalDoesNotGrantCommonRelicBeforeTenDefeats() throws {
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            turnLimit: 8,
            enemies: makeGuardEnemies(count: 9),
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            runState: DungeonRunState(
                dungeonID: "growth-tower",
                carriedHP: 3,
                relicEntries: [DungeonRelicEntry(relicID: .slayerMedal)]
            )
        )
        let core = makeCore(mode: mode)

        annihilateAllEnemies(in: core)

        XCTAssertEqual(core.currentFloorDefeatedEnemyCount, 9)
        XCTAssertEqual(core.dungeonRelicEntries.map(\.relicID), [.slayerMedal])
        XCTAssertEqual(core.dungeonRelicEntries.first?.enemyDefeatProgress, 9)
        XCTAssertTrue(core.dungeonRelicAcquisitionPresentations.isEmpty)
    }

    func testSlayerMedalGrantsCommonRelicOnTenthDefeat() throws {
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            turnLimit: 8,
            enemies: makeGuardEnemies(count: 10),
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            runState: DungeonRunState(
                dungeonID: "growth-tower",
                carriedHP: 3,
                relicEntries: [DungeonRelicEntry(relicID: .slayerMedal)]
            )
        )
        let core = makeCore(mode: mode)

        annihilateAllEnemies(in: core)

        XCTAssertEqual(core.currentFloorDefeatedEnemyCount, 10)
        XCTAssertEqual(core.dungeonRelicEntries.count, 2)
        let grantedRelic = try XCTUnwrap(core.dungeonRelicEntries.map(\.relicID).first { $0 != .slayerMedal })
        XCTAssertEqual(grantedRelic.rarity, .common)
        XCTAssertEqual(core.dungeonRelicEntries.first { $0.relicID == .slayerMedal }?.enemyDefeatProgress, 0)
        XCTAssertEqual(core.dungeonRelicAcquisitionPresentations.count, 1)
        XCTAssertEqual(core.dungeonRelicAcquisitionPresentations.first?.source, .reward)
        XCTAssertEqual(
            core.dungeonRelicAcquisitionPresentations.first?.items,
            [.relic(DungeonRelicEntry(relicID: grantedRelic))]
        )
    }

    func testSlayerMedalIgnoresDefeatsBeforeAcquisition() throws {
        let firstFloorState = DungeonRunState(dungeonID: "growth-tower", carriedHP: 3)
        let nextRunState = firstFloorState.advancedToNextFloor(
            carryoverHP: 3,
            currentFloorMoveCount: 1,
            rewardSelection: .addRelic(.slayerMedal),
            currentInventoryEntries: [],
            currentRelicEntries: [],
            currentCurseEntries: []
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            turnLimit: 8,
            enemies: makeGuardEnemies(count: 1),
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            runState: nextRunState
        )
        let core = makeCore(mode: mode)

        annihilateAllEnemies(in: core)

        XCTAssertEqual(core.currentFloorDefeatedEnemyCount, 1)
        XCTAssertEqual(core.dungeonRelicEntries.map(\.relicID), [.slayerMedal])
        XCTAssertEqual(core.dungeonRelicEntries.first?.enemyDefeatProgress, 1)
        XCTAssertTrue(core.dungeonRelicAcquisitionPresentations.isEmpty)
    }

    func testSlayerMedalCanGrantMultipleCommonRelicsFromOneMassDefeat() throws {
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            turnLimit: 8,
            enemies: makeGuardEnemies(count: 21),
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            runState: DungeonRunState(
                dungeonID: "growth-tower",
                carriedHP: 3,
                relicEntries: [DungeonRelicEntry(relicID: .slayerMedal, enemyDefeatProgress: 9)]
            )
        )
        let core = makeCore(mode: mode)

        annihilateAllEnemies(in: core)

        let grantedRelics = core.dungeonRelicEntries.map(\.relicID).filter { $0 != .slayerMedal }
        XCTAssertEqual(grantedRelics.count, 3)
        XCTAssertTrue(grantedRelics.allSatisfy { $0.rarity == .common })
        XCTAssertEqual(Set(grantedRelics).count, grantedRelics.count)
        XCTAssertEqual(core.dungeonRelicEntries.first { $0.relicID == .slayerMedal }?.enemyDefeatProgress, 0)
        XCTAssertEqual(core.dungeonRelicAcquisitionPresentations.first?.items.count, 3)
    }

    func testSlayerMedalExcludesOwnedCommonRelics() throws {
        let remainingRelic = DungeonRelicID.woodenAmulet
        let ownedCommonRelics = DungeonRelicID.newAcquisitionCases.filter {
            $0.rarity == .common && $0 != remainingRelic
        }
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            turnLimit: 8,
            enemies: makeGuardEnemies(count: 10),
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            runState: DungeonRunState(
                dungeonID: "growth-tower",
                carriedHP: 3,
                relicEntries: [DungeonRelicEntry(relicID: .slayerMedal)]
                    + ownedCommonRelics.map { DungeonRelicEntry(relicID: $0) }
            )
        )
        let core = makeCore(mode: mode)

        annihilateAllEnemies(in: core)

        XCTAssertTrue(core.dungeonRelicEntries.contains { $0.relicID == remainingRelic })
        XCTAssertEqual(core.dungeonRelicEntries.filter { $0.relicID == remainingRelic }.count, 1)
    }

    func testSlayerMedalConsumesProgressWithoutDuplicateWhenNoCommonRelicCandidatesRemain() throws {
        let allCommonRelics = DungeonRelicID.newAcquisitionCases.filter { $0.rarity == .common }
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            turnLimit: 8,
            enemies: makeGuardEnemies(count: 10),
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            runState: DungeonRunState(
                dungeonID: "growth-tower",
                carriedHP: 3,
                relicEntries: [DungeonRelicEntry(relicID: .slayerMedal)]
                    + allCommonRelics.map { DungeonRelicEntry(relicID: $0) }
            )
        )
        let core = makeCore(mode: mode)

        annihilateAllEnemies(in: core)

        XCTAssertEqual(core.dungeonRelicEntries.count, allCommonRelics.count + 1)
        XCTAssertEqual(core.dungeonRelicEntries.first { $0.relicID == .slayerMedal }?.enemyDefeatProgress, 0)
        XCTAssertTrue(core.dungeonRelicAcquisitionPresentations.isEmpty)
        XCTAssertTrue(core.dungeonRunLogEntries.contains { $0.message.contains("未所持のコモンレリック候補なし") })
    }

    func testSlayerMedalProgressPersistsAcrossFloorAdvance() throws {
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 3,
            relicEntries: [DungeonRelicEntry(relicID: .slayerMedal, enemyDefeatProgress: 7)]
        )

        let advanced = runState.advancedToNextFloor(
            carryoverHP: 3,
            currentFloorMoveCount: 1,
            currentInventoryEntries: [],
            currentRelicEntries: runState.relicEntries,
            currentCurseEntries: []
        )

        XCTAssertEqual(advanced.relicEntries.first { $0.relicID == .slayerMedal }?.enemyDefeatProgress, 7)
    }

    func testRelicRarityMetadataCoversAllRelics() {
        XCTAssertEqual(DungeonRelicID.allCases.count, 72)
        XCTAssertEqual(DungeonRelicID.crackedShield.rarity, .common)
        XCTAssertEqual(DungeonRelicID.heavyCrown.rarity, .common)
        XCTAssertEqual(DungeonRelicID.starCup.rarity, .rare)
        XCTAssertEqual(DungeonRelicID.distantStarCup.rarity, .rare)
        XCTAssertEqual(DungeonRelicID.crackedStarCup.rarity, .common)
        XCTAssertEqual(DungeonRelicID.travelerCanteen.rarity, .common)
        XCTAssertEqual(DungeonRelicID.moonDewCanteen.rarity, .rare)
        XCTAssertEqual(DungeonRelicID.moonMirror.rarity, .legendary)
        XCTAssertEqual(DungeonRelicID.gamblerCoin.rarity, .legendary)
        XCTAssertEqual(DungeonRelicID.royalCrown.rarity, .legendary)
        XCTAssertEqual(DungeonRelicID.immortalHeart.rarity, .legendary)
        XCTAssertEqual(DungeonRelicID.guardianAegis.rarity, .legendary)
        XCTAssertEqual(DungeonRelicID.stargazerHourglass.rarity, .legendary)
        XCTAssertEqual(DungeonRelicID.woodenAmulet.rarity, .common)
        XCTAssertEqual(DungeonRelicID.copperHourglass.rarity, .common)
        XCTAssertEqual(DungeonRelicID.fieldMedkit.rarity, .rare)
        XCTAssertEqual(DungeonRelicID.purifyingCharm.rarity, .common)
        XCTAssertEqual(DungeonRelicID.purifyingCharm.startingUses, 1)
        XCTAssertEqual(DungeonRelicID.greatPurifyingCharm.rarity, .rare)
        XCTAssertEqual(DungeonRelicID.greatPurifyingCharm.startingUses, 2)
        XCTAssertEqual(DungeonRelicID.greatPurifyingCharm.effectDescription, "次に受ける状態異常を2回まで無効化する。")
        XCTAssertEqual(DungeonRelicID.phoenixFeather.rarity, .legendary)
        XCTAssertEqual(DungeonRelicID.sageCodex.rarity, .legendary)
        XCTAssertEqual(DungeonRelicID.twinPouch.rarity, .legendary)
        XCTAssertEqual(DungeonRelicID.lavaCharm.rarity, .common)
        XCTAssertEqual(DungeonRelicID.lavaLantern.rarity, .common)
        XCTAssertEqual(DungeonRelicID.watcherMask.rarity, .rare)
        XCTAssertEqual(DungeonRelicID.railWedge.rarity, .rare)
        XCTAssertEqual(DungeonRelicID.railSign.rarity, .rare)
        XCTAssertEqual(DungeonRelicID.smokeDecoy.rarity, .rare)
        XCTAssertEqual(DungeonRelicID.chaserWhistle.rarity, .rare)
        XCTAssertEqual(DungeonRelicID.starVeil.rarity, .legendary)
        XCTAssertEqual(DungeonRelicID.trapSole.rarity, .common)
        XCTAssertEqual(DungeonRelicID.emberCloak.rarity, .common)
        XCTAssertEqual(DungeonRelicID.watcherMonocle.rarity, .rare)
        XCTAssertEqual(DungeonRelicID.railCharm.rarity, .rare)
        XCTAssertEqual(DungeonRelicID.chaserDecoy.rarity, .rare)
        XCTAssertEqual(DungeonRelicID.antidoteStone.rarity, .common)
        XCTAssertEqual(DungeonRelicID.greaterAntidoteStone.rarity, .rare)
        XCTAssertEqual(DungeonRelicID.greaterAntidoteStone.effectDescription, "毒罠の毒ダメージ回数を2減らす。最低1回。")
        XCTAssertEqual(DungeonRelicID.starUmbrella.rarity, .rare)
        XCTAssertEqual(DungeonRelicID.guardianCloak.rarity, .legendary)
        XCTAssertEqual(
            DungeonRelicID.guardianCloak.effectDescription,
            "敵とメテオから受けるHPダメージを1軽減する。同じダメージ源では他の軽減レリックと重複しない。"
        )
        XCTAssertEqual(DungeonRelicID.fallAnchor.rarity, .legendary)
        XCTAssertEqual(DungeonRelicID.campfireCoal.rarity, .common)
        XCTAssertEqual(DungeonRelicID.merchantsScale.rarity, .legendary)
        XCTAssertEqual(DungeonRelicID.barrierCharm.rarity, .rare)
        XCTAssertEqual(DungeonRelicID.barrierTalisman.rarity, .legendary)
        XCTAssertEqual(DungeonRelicID.frostBell.rarity, .rare)
        XCTAssertEqual(DungeonRelicID.rewindingHourglass.rarity, .legendary)
        XCTAssertEqual(DungeonRelicID.slayerPouch.rarity, .common)
        XCTAssertEqual(DungeonRelicID.hunterBanner.rarity, .rare)
        XCTAssertEqual(DungeonRelicID.intimidationHorn.rarity, .rare)
        XCTAssertEqual(DungeonRelicID.slayerMedal.rarity, .rare)
        XCTAssertEqual(DungeonRelicID.nightCardLens.rarity, .common)
        XCTAssertEqual(DungeonRelicID.thornScoutLens.rarity, .common)
        XCTAssertEqual(DungeonRelicID.magmaScoutLens.rarity, .common)
        XCTAssertEqual(DungeonRelicID.trapScoutLens.rarity, .rare)
        XCTAssertEqual(DungeonRelicID.enemyScoutLens.rarity, .rare)
        XCTAssertEqual(DungeonRelicID.slayerPouch.effectDescription, "その階で敵を1体倒すたび、クリア報酬の補助カード出現率が3pt上がる。")
        XCTAssertEqual(DungeonRelicID.hunterBanner.effectDescription, "その階で敵を1体倒すたび、クリア報酬のレリック出現率が1pt上がる。")
        XCTAssertEqual(DungeonRelicID.slayerMedal.effectDescription, "取得後、敵を10体倒すごとに未所持のコモンレリックを1つ得る。")
        XCTAssertEqual(DungeonRelicID.nightCardLens.effectDescription, "暗闇フロアで未取得の拾得カードが常に見える。")
        XCTAssertEqual(DungeonRelicID.trapScoutLens.effectDescription, "暗闇フロアで隠し罠が常に見える。")
        XCTAssertFalse(DungeonRelicID.oldMap.isAvailableForNewAcquisition)
        XCTAssertFalse(DungeonRelicID.whiteChalk.isAvailableForNewAcquisition)
        XCTAssertFalse(DungeonRelicID.windcutFeather.isAvailableForNewAcquisition)
        XCTAssertFalse(DungeonRelicID.quickSheath.isAvailableForNewAcquisition)
        XCTAssertFalse(DungeonRelicID.allCases.contains(.oldMap))
        XCTAssertFalse(DungeonRelicID.allCases.contains(.whiteChalk))
        XCTAssertFalse(DungeonRelicID.newAcquisitionCases.contains(.oldMap))
        XCTAssertFalse(DungeonRelicID.newAcquisitionCases.contains(.whiteChalk))
        XCTAssertFalse(DungeonRelicID.newAcquisitionCases.contains(.windcutFeather))
        XCTAssertFalse(DungeonRelicID.newAcquisitionCases.contains(.quickSheath))
        XCTAssertTrue(DungeonRelicID.allCases.allSatisfy { !$0.rarity.displayName.isEmpty })
        XCTAssertTrue(DungeonRelicID.allCases.allSatisfy { !$0.rarity.badgeText.isEmpty })
    }

    func testRemovedRelicsAreSkippedWhenDecodingLegacyRunStateAndResumeSnapshot() throws {
        let runStateJSON = """
        {
          "dungeonID": "growth-tower",
          "carriedHP": 3,
          "relicEntries": [
            { "relicID": "foldingMap", "remainingUses": 0 },
            { "relicID": "glowingHeart", "remainingUses": 0 },
            { "relicID": "phantomTicket", "remainingUses": 0 }
          ]
        }
        """
        let decodedRunState = try JSONDecoder().decode(DungeonRunState.self, from: Data(runStateJSON.utf8))

        XCTAssertEqual(decodedRunState.relicEntries.map(\.relicID), [.glowingHeart])

        let snapshotJSON = """
        {
          "version": 1,
          "dungeonID": "growth-tower",
          "floorIndex": 0,
          "runState": {
            "dungeonID": "growth-tower",
            "carriedHP": 3,
            "relicEntries": [
              { "relicID": "foldingMap", "remainingUses": 0 },
              { "relicID": "campfireCoal", "remainingUses": 0 }
            ]
          },
          "currentPoint": { "x": 0, "y": 0 },
          "visitedPoints": [{ "x": 0, "y": 0 }],
          "moveCount": 0,
          "elapsedSeconds": 0,
          "dungeonHP": 3,
          "dungeonInventoryEntries": [],
          "collectedDungeonCardPickupIDs": [],
          "dungeonRelicEntries": [
            { "relicID": "phantomTicket", "remainingUses": 0 },
            { "relicID": "merchantsScale", "remainingUses": 0 }
          ],
          "isDungeonExitUnlocked": true
        }
        """
        let decodedSnapshot = try JSONDecoder().decode(DungeonRunResumeSnapshot.self, from: Data(snapshotJSON.utf8))

        XCTAssertEqual(decodedSnapshot.runState.relicEntries.map(\.relicID), [.campfireCoal])
        XCTAssertEqual(decodedSnapshot.dungeonRelicEntries.map(\.relicID), [.merchantsScale])
    }

    func testDarknessScoutRelicsRevealOnlyTheirCategories() throws {
        let cardPickup = DungeonCardPickupDefinition(
            id: "dark-card",
            point: GridPoint(x: 4, y: 4),
            card: .straightRight2
        )
        let thornPoint = GridPoint(x: 3, y: 0)
        let strongThornPoint = GridPoint(x: 4, y: 0)
        let lavaPoint = GridPoint(x: 0, y: 3)
        let strongLavaPoint = GridPoint(x: 0, y: 4)
        let hpHalvingPoint = GridPoint(x: 2, y: 3)
        let poisonPoint = GridPoint(x: 3, y: 3)
        let swampPoint = GridPoint(x: 4, y: 3)
        let enemy = EnemyDefinition(
            id: "dark-enemy",
            name: "追跡兵",
            position: GridPoint(x: 4, y: 2),
            behavior: .chaser
        )
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 3,
            relicEntries: [
                DungeonRelicEntry(relicID: .nightCardLens),
                DungeonRelicEntry(relicID: .thornScoutLens),
                DungeonRelicEntry(relicID: .magmaScoutLens),
                DungeonRelicEntry(relicID: .trapScoutLens),
                DungeonRelicEntry(relicID: .enemyScoutLens)
            ]
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 1),
            turnLimit: 8,
            enemies: [enemy],
            hazards: [
                .damageTrap(points: [thornPoint], damage: 1),
                .damageTrap(points: [strongThornPoint], damage: 2),
                .lavaTile(points: [lavaPoint], damage: 1),
                .lavaTile(points: [strongLavaPoint], damage: 2),
                .hpHalvingTrap(points: [hpHalvingPoint])
            ],
            tileEffectOverrides: [
                poisonPoint: .poisonTrap,
                swampPoint: .swamp
            ],
            cardAcquisitionMode: .inventoryOnly,
            cardPickups: [cardPickup],
            runState: runState
        )
        let core = makeCore(mode: mode)

        XCTAssertEqual(core.darknessRevealedDungeonCardPickupPoints, [cardPickup.point])
        XCTAssertEqual(core.darknessRevealedThornTrapPoints, [thornPoint, strongThornPoint])
        XCTAssertEqual(core.darknessRevealedLavaTilePoints, [lavaPoint, strongLavaPoint])
        XCTAssertEqual(core.darknessRevealedHiddenTrapPoints, [hpHalvingPoint, poisonPoint])
        XCTAssertFalse(core.darknessRevealedHiddenTrapPoints.contains(swampPoint))
        XCTAssertEqual(core.darknessRevealedEnemyPoints, [enemy.position])
    }

    func testV11CommonRelicsAdjustHPTurnsDarknessTrapAndFall() {
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 3,
            relicEntries: [
                DungeonRelicEntry(relicID: .copperHourglass),
                DungeonRelicEntry(relicID: .smallLantern),
                DungeonRelicEntry(relicID: .spareTorch),
                DungeonRelicEntry(relicID: .dullNeedle),
                DungeonRelicEntry(relicID: .patchedRope)
            ]
        )
        let trapPoint = GridPoint(x: 1, y: 0)
        let brittlePoint = GridPoint(x: 2, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 5,
            hazards: [
                .damageTrap(points: [trapPoint], damage: 2),
                .brittleFloor(points: [brittlePoint])
            ],
            allowsBasicOrthogonalMove: true,
            runState: runState
        )
        let core = makeCore(mode: mode, cards: [.straightRight2, .straightLeft2, .rayRight])

        XCTAssertEqual(core.effectiveDungeonTurnLimit, 7)
        XCTAssertEqual(core.dungeonDarknessVisionRadius, 3)

        playBasicMove(to: trapPoint, in: core)
        XCTAssertEqual(core.dungeonHP, 3)
        XCTAssertEqual(core.dungeonRelicEntries.first { $0.relicID == .dullNeedle }?.remainingUses, 0)

        playBasicMove(to: brittlePoint, in: core)
        playBasicMove(to: GridPoint(x: 2, y: 1), in: core)
        playBasicMove(to: brittlePoint, in: core)
        XCTAssertEqual(core.dungeonHP, 3)
        XCTAssertEqual(core.dungeonRelicEntries.first { $0.relicID == .patchedRope }?.remainingUses, 0)

        let advanced = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 2,
            relicEntries: [DungeonRelicEntry(relicID: .travelerRation)]
        ).advancedToNextFloor(carryoverHP: 2, currentFloorMoveCount: 1)
        XCTAssertEqual(advanced.carriedHP, 3)
        XCTAssertEqual(
            DungeonRunState.adjustedMoveRewardBaseUses(
                2,
                relicEntries: [DungeonRelicEntry(relicID: .heavyCrown)],
                curseEntries: []
            ),
            3
        )
        XCTAssertEqual(
            DungeonRunState.adjustedSupportRewardUses(
                1,
                relicEntries: [DungeonRelicEntry(relicID: .heavyCrown)],
                curseEntries: []
            ),
            1
        )
    }

    func testStarCupHealsEverySecondFloorAfterPickup() {
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 3,
            relicEntries: [DungeonRelicEntry(relicID: .starCup)]
        )

        let first = runState.advancedToNextFloor(carryoverHP: 3, currentFloorMoveCount: 1)
        let second = first.advancedToNextFloor(carryoverHP: first.carriedHP, currentFloorMoveCount: 1)
        let third = second.advancedToNextFloor(carryoverHP: second.carriedHP, currentFloorMoveCount: 1)

        XCTAssertEqual(first.carriedHP, 3)
        XCTAssertEqual(first.relicEntries.first { $0.relicID == .starCup }?.floorStartCharge, 1)
        XCTAssertEqual(second.carriedHP, 4)
        XCTAssertEqual(second.relicEntries.first { $0.relicID == .starCup }?.floorStartCharge, 0)
        XCTAssertEqual(third.carriedHP, 4)
        XCTAssertEqual(third.relicEntries.first { $0.relicID == .starCup }?.floorStartCharge, 1)
    }

    func testDistantAndCrackedStarCupsUseTheirOwnHealingCadence() {
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 3,
            relicEntries: [
                DungeonRelicEntry(relicID: .distantStarCup),
                DungeonRelicEntry(relicID: .crackedStarCup)
            ]
        )

        let first = runState.advancedToNextFloor(carryoverHP: 3, currentFloorMoveCount: 1)
        let second = first.advancedToNextFloor(carryoverHP: first.carriedHP, currentFloorMoveCount: 1)
        let third = second.advancedToNextFloor(carryoverHP: second.carriedHP, currentFloorMoveCount: 1)
        let fourth = third.advancedToNextFloor(carryoverHP: third.carriedHP, currentFloorMoveCount: 1)
        let fifth = fourth.advancedToNextFloor(carryoverHP: fourth.carriedHP, currentFloorMoveCount: 1)

        XCTAssertEqual(first.carriedHP, 3)
        XCTAssertEqual(second.carriedHP, 3)
        XCTAssertEqual(third.carriedHP, 4)
        XCTAssertEqual(fourth.carriedHP, 4)
        XCTAssertEqual(fifth.carriedHP, 5)
        XCTAssertEqual(fifth.relicEntries.first { $0.relicID == .distantStarCup }?.floorStartCharge, 2)
        XCTAssertEqual(fifth.relicEntries.first { $0.relicID == .crackedStarCup }?.floorStartCharge, 0)
    }

    func testLimitedCanteenRelicsHealAtFloorStartAndExpire() {
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 3,
            relicEntries: [
                DungeonRelicEntry(relicID: .travelerCanteen),
                DungeonRelicEntry(relicID: .moonDewCanteen)
            ]
        )

        let first = runState.advancedToNextFloor(carryoverHP: 3, currentFloorMoveCount: 1)
        let second = first.advancedToNextFloor(carryoverHP: first.carriedHP, currentFloorMoveCount: 1)
        let third = second.advancedToNextFloor(carryoverHP: second.carriedHP, currentFloorMoveCount: 1)
        let fourth = third.advancedToNextFloor(carryoverHP: third.carriedHP, currentFloorMoveCount: 1)
        let fifth = fourth.advancedToNextFloor(carryoverHP: fourth.carriedHP, currentFloorMoveCount: 1)

        XCTAssertEqual(first.carriedHP, 5)
        XCTAssertEqual(first.relicEntries.first { $0.relicID == .travelerCanteen }?.remainingUses, 2)
        XCTAssertEqual(first.relicEntries.first { $0.relicID == .moonDewCanteen }?.remainingUses, 4)
        XCTAssertEqual(second.carriedHP, 7)
        XCTAssertEqual(third.carriedHP, 9)
        XCTAssertNil(third.relicEntries.first { $0.relicID == .travelerCanteen })
        XCTAssertEqual(third.relicEntries.first { $0.relicID == .moonDewCanteen }?.remainingUses, 2)
        XCTAssertEqual(fourth.carriedHP, 10)
        XCTAssertEqual(fifth.carriedHP, 11)
        XCTAssertNil(fifth.relicEntries.first { $0.relicID == .moonDewCanteen })
    }

    func testV11RareRelicsAdjustHealingRewardUsesAndStatusProtection() {
        let poisonPoint = GridPoint(x: 1, y: 0)
        let healPoint = GridPoint(x: 2, y: 0)
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 3,
            relicEntries: [
                DungeonRelicEntry(relicID: .fieldMedkit),
                DungeonRelicEntry(relicID: .purifyingCharm)
            ]
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            hazards: [.healingTile(points: [healPoint], amount: 1)],
            tileEffectOverrides: [poisonPoint: .poisonTrap],
            allowsBasicOrthogonalMove: true,
            runState: runState
        )
        let core = makeCore(mode: mode, cards: [.straightRight2, .straightLeft2, .rayRight])

        playBasicMove(to: poisonPoint, in: core)
        XCTAssertEqual(core.poisonDamageTicksRemaining, 0)
        XCTAssertEqual(core.dungeonRelicEntries.first { $0.relicID == .purifyingCharm }?.remainingUses, 0)

        playBasicMove(to: healPoint, in: core)
        XCTAssertEqual(core.dungeonHP, 5)

        let advanced = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 3,
            relicEntries: [DungeonRelicEntry(relicID: .quickSheath)]
        ).advancedToNextFloor(
            carryoverHP: 3,
            currentFloorMoveCount: 1,
            rewardSelection: .add(.straightRight2),
            rewardAddUses: 2
        )
        XCTAssertEqual(advanced.rewardInventoryEntries.first?.rewardUses, 2)
        XCTAssertEqual(
            DungeonRunState.adjustedRewardAddUses(
                2,
                for: .rayRight,
                relicEntries: [DungeonRelicEntry(relicID: .windcutFeather)],
                curseEntries: []
            ),
            2
        )
        XCTAssertEqual(
            DungeonRunState.adjustedRewardAddUses(
                2,
                for: .straightRight2,
                relicEntries: [DungeonRelicEntry(relicID: .quickSheath)],
                curseEntries: []
            ),
            2
        )
        XCTAssertEqual(
            DungeonRunState.adjustedMoveRewardBaseUses(
                2,
                relicEntries: [DungeonRelicEntry(relicID: .twinPouch)],
                curseEntries: []
            ),
            2
        )
        XCTAssertEqual(
            DungeonRunState.adjustedSupportRewardUses(
                1,
                relicEntries: [DungeonRelicEntry(relicID: .twinPouch)],
                curseEntries: []
            ),
            2
        )
    }

    func testGreaterPurifyingCharmBlocksTwoStatusTraps() {
        let poisonPoint = GridPoint(x: 1, y: 0)
        let shacklePoint = GridPoint(x: 2, y: 0)
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 3,
            relicEntries: [DungeonRelicEntry(relicID: .greatPurifyingCharm)]
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            tileEffectOverrides: [
                poisonPoint: .poisonTrap,
                shacklePoint: .shackleTrap
            ],
            allowsBasicOrthogonalMove: true,
            runState: runState
        )
        let core = makeCore(mode: mode, cards: [.straightRight2, .straightLeft2, .rayRight])

        playBasicMove(to: poisonPoint, in: core)
        XCTAssertEqual(core.poisonDamageTicksRemaining, 0)
        XCTAssertEqual(core.dungeonRelicEntries.first { $0.relicID == .greatPurifyingCharm }?.remainingUses, 1)

        playBasicMove(to: shacklePoint, in: core)
        XCTAssertFalse(core.isShackled)
        XCTAssertEqual(core.dungeonRelicEntries.first { $0.relicID == .greatPurifyingCharm }?.remainingUses, 0)
    }

    func testAntidoteRelicsReducePoisonTicksByStrength() {
        func poisonTicks(relics: [DungeonRelicEntry]) -> Int {
            let poisonPoint = GridPoint(x: 1, y: 0)
            let core = makeCore(
                mode: makeDungeonMode(
                    spawn: GridPoint(x: 0, y: 0),
                    exit: GridPoint(x: 4, y: 4),
                    hp: 3,
                    turnLimit: 8,
                    tileEffectOverrides: [poisonPoint: .poisonTrap],
                    allowsBasicOrthogonalMove: true,
                    runState: DungeonRunState(
                        dungeonID: "growth-tower",
                        carriedHP: 3,
                        relicEntries: relics
                    )
                )
            )
            playBasicMove(to: poisonPoint, in: core)
            return core.poisonDamageTicksRemaining
        }

        XCTAssertEqual(poisonTicks(relics: [DungeonRelicEntry(relicID: .antidoteStone)]), 2)
        XCTAssertEqual(poisonTicks(relics: [DungeonRelicEntry(relicID: .greaterAntidoteStone)]), 1)
        XCTAssertEqual(
            poisonTicks(relics: [
                DungeonRelicEntry(relicID: .antidoteStone),
                DungeonRelicEntry(relicID: .greaterAntidoteStone)
            ]),
            1
        )
    }

    func testV11LegendaryRelicsPreventFatalDamageAndBoostAllNewCardUses() {
        let trapPoint = GridPoint(x: 1, y: 0)
        let pickupPoint = GridPoint(x: 2, y: 0)
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 1,
            relicEntries: [
                DungeonRelicEntry(relicID: .phoenixFeather),
                DungeonRelicEntry(relicID: .sageCodex)
            ]
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 1,
            turnLimit: 8,
            hazards: [.damageTrap(points: [trapPoint], damage: 2)],
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            cardPickups: [
                DungeonCardPickupDefinition(id: "pickup", point: pickupPoint, playable: .move(.straightRight2), uses: 1)
            ],
            runState: runState
        )
        let core = makeCore(mode: mode, cards: [.straightRight2, .straightLeft2, .rayRight])

        playBasicMove(to: trapPoint, in: core)
        XCTAssertEqual(core.dungeonHP, 1)
        XCTAssertEqual(core.dungeonRelicEntries.first { $0.relicID == .phoenixFeather }?.remainingUses, 0)
        XCTAssertEqual(core.dungeonRelicActivationEvent?.relicID, .phoenixFeather)

        playBasicMove(to: pickupPoint, in: core)
        XCTAssertEqual(core.dungeonInventoryEntries.first { $0.moveCard == .straightRight2 }?.totalUses, 2)

        let advanced = runState.advancedToNextFloor(
            carryoverHP: 1,
            currentFloorMoveCount: 1,
            rewardSelection: .addSupport(.barrierSpell),
            currentRelicEntries: [DungeonRelicEntry(relicID: .sageCodex)],
            supportRewardAddUses: 2
        )
        XCTAssertEqual(advanced.rewardInventoryEntries.first?.rewardUses, 2)
        XCTAssertEqual(
            DungeonRunState.adjustedMoveRewardBaseUses(
                2,
                relicEntries: [DungeonRelicEntry(relicID: .royalCrown)],
                curseEntries: []
            ),
            3
        )
        XCTAssertEqual(
            DungeonRunState.adjustedSupportRewardUses(
                1,
                relicEntries: [DungeonRelicEntry(relicID: .royalCrown)],
                curseEntries: []
            ),
            2
        )
    }

    func testRewindingHourglassRevivesOnEarlierRandomFloorWithRunStateCarriedForward() throws {
        let trapPoint = GridPoint(x: 1, y: 0)
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            currentFloorIndex: 4,
            carriedHP: 1,
            totalMoveCount: 12,
            clearedFloorCount: 4,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .straightRight2, rewardUses: 2)],
            relicEntries: [
                DungeonRelicEntry(relicID: .rewindingHourglass),
                DungeonRelicEntry(relicID: .sageCodex)
            ],
            curseEntries: [DungeonCurseEntry(curseID: .rustyChain)],
            collectedDungeonRelicPickupIDs: ["chest-1"],
            cardVariationSeed: 4242,
            movementStyle: .orthogonal,
            dungeonInventoryKindLimit: 7,
            crackedFloorPointsByFloor: [2: [GridPoint(x: 2, y: 2)]],
            collapsedFloorPointsByFloor: [2: [GridPoint(x: 3, y: 3)]],
            hazardDamageMitigationsRemaining: 0,
            enemyDamageMitigationsRemaining: 2,
            markerDamageMitigationsRemaining: 3
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 1,
            turnLimit: 8,
            hazards: [.damageTrap(points: [trapPoint], damage: 2)],
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            runState: runState
        )
        let core = makeCore(mode: mode, cards: [.straightRight2, .straightLeft2, .rayRight])

        playBasicMove(to: trapPoint, in: core)

        let event = try XCTUnwrap(core.dungeonRewindReviveEvent)
        XCTAssertEqual(core.progress, .playing)
        XCTAssertEqual(core.dungeonHP, 1)
        XCTAssertEqual(event.sourceFloorIndex, 4)
        XCTAssertLessThan(event.destinationFloorIndex, 4)
        XCTAssertEqual(event.hpAfterRevive, 1)
        XCTAssertEqual(core.dungeonRelicEntries.first { $0.relicID == .rewindingHourglass }?.remainingUses, 0)
        XCTAssertTrue(core.dungeonRunLogEntries.contains { $0.message.contains("逆巻きの砂時計で\(event.destinationFloorIndex + 1)Fへ復活") })

        let revived = runState.revivedAtPreviousFloor(
            floorIndex: event.destinationFloorIndex,
            currentFloorMoveCount: core.moveCount,
            currentInventoryEntries: core.dungeonInventoryEntries,
            currentRelicEntries: core.dungeonRelicEntries,
            currentCurseEntries: core.dungeonCurseEntries,
            collectedDungeonRelicPickupIDs: core.collectedDungeonRelicPickupIDs,
            hazardDamageMitigationsRemaining: core.hazardDamageMitigationsRemaining,
            enemyDamageMitigationsRemaining: core.enemyDamageMitigationsRemaining,
            markerDamageMitigationsRemaining: core.markerDamageMitigationsRemaining,
            currentRunLogEntries: core.dungeonRunLogEntries
        )
        XCTAssertEqual(revived.currentFloorIndex, event.destinationFloorIndex)
        XCTAssertEqual(revived.carriedHP, 1)
        XCTAssertEqual(revived.rewardInventoryEntries.first?.rewardUses, 2)
        XCTAssertEqual(revived.relicEntries.first { $0.relicID == .rewindingHourglass }?.remainingUses, 0)
        XCTAssertEqual(revived.curseEntries.map(\.curseID), [.rustyChain])
        XCTAssertEqual(revived.collectedDungeonRelicPickupIDs, Set(["chest-1"]))
        XCTAssertEqual(revived.cardVariationSeed, 4242)
        XCTAssertEqual(revived.movementStyle, .orthogonal)
        XCTAssertEqual(revived.dungeonInventoryKindLimit, 7)
        XCTAssertEqual(revived.hazardDamageMitigationsRemaining, 0)
        XCTAssertEqual(revived.enemyDamageMitigationsRemaining, 2)
        XCTAssertEqual(revived.markerDamageMitigationsRemaining, 3)
        XCTAssertEqual(revived.crackedFloorPoints(for: event.destinationFloorIndex), [])
        XCTAssertEqual(revived.collapsedFloorPoints(for: event.destinationFloorIndex), [])
    }

    func testPhoenixFeatherTakesPrecedenceOverRewindingHourglass() {
        let trapPoint = GridPoint(x: 1, y: 0)
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            currentFloorIndex: 3,
            carriedHP: 1,
            relicEntries: [
                DungeonRelicEntry(relicID: .phoenixFeather),
                DungeonRelicEntry(relicID: .rewindingHourglass)
            ],
            cardVariationSeed: 99
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 1,
            turnLimit: 8,
            hazards: [.damageTrap(points: [trapPoint], damage: 2)],
            allowsBasicOrthogonalMove: true,
            runState: runState
        )
        let core = makeCore(mode: mode, cards: [.straightRight2, .straightLeft2, .rayRight])

        playBasicMove(to: trapPoint, in: core)

        XCTAssertNil(core.dungeonRewindReviveEvent)
        XCTAssertEqual(core.dungeonHP, 1)
        XCTAssertEqual(core.dungeonRelicEntries.first { $0.relicID == .phoenixFeather }?.remainingUses, 0)
        XCTAssertEqual(core.dungeonRelicEntries.first { $0.relicID == .rewindingHourglass }?.remainingUses, 1)
    }

    func testRewindingHourglassRevivesOnFirstFloorWhenThereIsNoEarlierFloor() throws {
        let trapPoint = GridPoint(x: 1, y: 0)
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            currentFloorIndex: 0,
            carriedHP: 1,
            relicEntries: [DungeonRelicEntry(relicID: .rewindingHourglass)],
            cardVariationSeed: 7
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 1,
            turnLimit: 8,
            hazards: [.damageTrap(points: [trapPoint], damage: 2)],
            allowsBasicOrthogonalMove: true,
            runState: runState
        )
        let core = makeCore(mode: mode, cards: [.straightRight2, .straightLeft2, .rayRight])

        playBasicMove(to: trapPoint, in: core)

        let event = try XCTUnwrap(core.dungeonRewindReviveEvent)
        XCTAssertEqual(event.sourceFloorIndex, 0)
        XCTAssertEqual(event.destinationFloorIndex, 0)
        XCTAssertEqual(core.dungeonHP, 1)
        XCTAssertEqual(core.progress, .playing)
        XCTAssertEqual(core.dungeonRelicEntries.first { $0.relicID == .rewindingHourglass }?.remainingUses, 0)
    }

    func testTargetedBuffRelicsReduceSpecificEnemyDamageAndOffsetCurses() {
        let enemyCases: [(DungeonRelicID, DungeonCurseID, EnemyDefinition, GridPoint)] = [
            (
                .watcherMonocle,
                .watchersBrand,
                EnemyDefinition(
                    id: "watcher",
                    name: "見張り",
                    position: GridPoint(x: 1, y: 1),
                    behavior: .watcher(direction: MoveVector(dx: -1, dy: 0), range: 2)
                ),
                GridPoint(x: 0, y: 1)
            ),
            (
                .railCharm,
                .patrolBell,
                EnemyDefinition(
                    id: "patrol",
                    name: "巡回兵",
                    position: GridPoint(x: 1, y: 1),
                    behavior: .patrol(path: [GridPoint(x: 1, y: 1), GridPoint(x: 2, y: 1)])
                ),
                GridPoint(x: 0, y: 1)
            ),
            (
                .chaserDecoy,
                .chaserScent,
                EnemyDefinition(
                    id: "chaser",
                    name: "追跡兵",
                    position: GridPoint(x: 1, y: 1),
                    behavior: .chaser
                ),
                GridPoint(x: 0, y: 1)
            )
        ]

        for (relic, curse, enemy, dangerPoint) in enemyCases {
            let relicCore = makeCore(
                mode: makeDungeonMode(
                    spawn: GridPoint(x: 0, y: 0),
                    exit: GridPoint(x: 4, y: 4),
                    hp: 4,
                    turnLimit: 8,
                    enemies: [enemy],
                    runState: DungeonRunState(
                        dungeonID: "growth-tower",
                        carriedHP: 4,
                        relicEntries: [DungeonRelicEntry(relicID: relic)]
                    )
                )
            )
            playBasicMove(to: dangerPoint, in: relicCore)
            XCTAssertEqual(relicCore.dungeonHP, 4, "\(relic.displayName) should fully cover base \(enemy.name) damage")

            let offsetCore = makeCore(
                mode: makeDungeonMode(
                    spawn: GridPoint(x: 0, y: 0),
                    exit: GridPoint(x: 4, y: 4),
                    hp: 4,
                    turnLimit: 8,
                    enemies: [enemy],
                    runState: DungeonRunState(
                        dungeonID: "growth-tower",
                        carriedHP: 4,
                        relicEntries: [DungeonRelicEntry(relicID: relic)],
                        curseEntries: [DungeonCurseEntry(curseID: curse)]
                    )
                )
            )
            playBasicMove(to: dangerPoint, in: offsetCore)
            XCTAssertEqual(offsetCore.dungeonHP, 3, "\(relic.displayName) should offset \(curse.displayName) back to base damage")
        }
    }

    func testTargetedOneTimeNullifyRelicsCoverHazardAndEnemyCategories() throws {
        let trapPoint = GridPoint(x: 1, y: 0)
        let trapCore = makeCore(
            mode: makeDungeonMode(
                spawn: GridPoint(x: 0, y: 0),
                exit: GridPoint(x: 4, y: 4),
                hp: 4,
                turnLimit: 8,
                hazards: [.damageTrap(points: [trapPoint], damage: 2)],
                runState: DungeonRunState(
                    dungeonID: "growth-tower",
                    carriedHP: 4,
                    relicEntries: [DungeonRelicEntry(relicID: .silverNeedle)]
                )
            )
        )
        playBasicMove(to: trapPoint, in: trapCore)
        XCTAssertEqual(trapCore.dungeonHP, 4)
        XCTAssertEqual(trapCore.dungeonRelicEntries.first { $0.relicID == .silverNeedle }?.remainingUses, 0)

        let lavaPoint = GridPoint(x: 1, y: 0)
        let lavaCore = makeCore(
            mode: makeDungeonMode(
                spawn: GridPoint(x: 0, y: 0),
                exit: GridPoint(x: 4, y: 4),
                hp: 4,
                turnLimit: 8,
                hazards: [.lavaTile(points: [lavaPoint], damage: 2)],
                runState: DungeonRunState(
                    dungeonID: "growth-tower",
                    carriedHP: 4,
                    relicEntries: [DungeonRelicEntry(relicID: .lavaCharm)]
                )
            )
        )
        playBasicMove(to: lavaPoint, in: lavaCore)
        XCTAssertEqual(lavaCore.dungeonHP, 4)
        XCTAssertEqual(lavaCore.dungeonRelicEntries.first { $0.relicID == .lavaCharm }?.remainingUses, 0)

        let enemyCases: [(DungeonRelicID, EnemyDefinition, GridPoint)] = [
            (
                .watcherMask,
                EnemyDefinition(
                    id: "watcher",
                    name: "見張り",
                    position: GridPoint(x: 1, y: 1),
                    behavior: .watcher(direction: MoveVector(dx: -1, dy: 0), range: 2),
                    damage: 2
                ),
                GridPoint(x: 0, y: 1)
            ),
            (
                .railWedge,
                EnemyDefinition(
                    id: "patrol",
                    name: "巡回兵",
                    position: GridPoint(x: 1, y: 1),
                    behavior: .patrol(path: [GridPoint(x: 1, y: 1), GridPoint(x: 2, y: 1)]),
                    damage: 2
                ),
                GridPoint(x: 0, y: 1)
            ),
            (
                .smokeDecoy,
                EnemyDefinition(
                    id: "chaser",
                    name: "追跡兵",
                    position: GridPoint(x: 1, y: 1),
                    behavior: .chaser,
                    damage: 2
                ),
                GridPoint(x: 0, y: 1)
            )
        ]

        for (relic, enemy, dangerPoint) in enemyCases {
            let core = makeCore(
                mode: makeDungeonMode(
                    spawn: GridPoint(x: 0, y: 0),
                    exit: GridPoint(x: 4, y: 4),
                    hp: 4,
                    turnLimit: 8,
                    enemies: [enemy],
                    runState: DungeonRunState(
                        dungeonID: "growth-tower",
                        carriedHP: 4,
                        relicEntries: [DungeonRelicEntry(relicID: relic)]
                    )
                )
            )
            playBasicMove(to: dangerPoint, in: core)
            XCTAssertEqual(core.dungeonHP, 4, "\(relic.displayName) should nullify \(enemy.name) damage")
            XCTAssertEqual(core.dungeonRelicEntries.first { $0.relicID == relic }?.remainingUses, 0)
        }

        let marker = EnemyDefinition(
            id: "marker",
            name: "メテオ兵",
            position: GridPoint(x: 3, y: 1),
            behavior: .marker(directions: [], range: 2),
            damage: 2
        )
        var selectedCore: GameCore?
        var selectedMove: BasicOrthogonalMove?
        for seed in 0..<200 {
            let core = makeCore(
                mode: makeDungeonMode(
                    spawn: GridPoint(x: 0, y: 0),
                    exit: GridPoint(x: 4, y: 4),
                    hp: 4,
                    turnLimit: 8,
                    enemies: [marker],
                    runState: DungeonRunState(
                        dungeonID: "growth-tower",
                        carriedHP: 4,
                        relicEntries: [DungeonRelicEntry(relicID: .starVeil)],
                        cardVariationSeed: UInt64(seed)
                    )
                )
            )
            if let warningMove = core.availableBasicOrthogonalMoves().first(where: {
                core.enemyWarningPoints.contains($0.destination)
            }) {
                selectedCore = core
                selectedMove = warningMove
                break
            }
        }
        let markerCore = try XCTUnwrap(selectedCore)
        let markerMove = try XCTUnwrap(selectedMove)
        playBasicMove(to: markerMove.destination, in: markerCore)
        XCTAssertEqual(markerCore.dungeonHP, 4)
        XCTAssertEqual(markerCore.dungeonRelicEntries.first { $0.relicID == .starVeil }?.remainingUses, 0)
    }

    func testPerFloorNullifyRelicsResetOnNextFloor() {
        let relics: [DungeonRelicID] = [
            .dullNeedle,
            .lavaLantern,
            .patchedRope,
            .guardianIncense,
            .railSign,
            .chaserWhistle,
            .guardianAegis
        ]
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 3,
            relicEntries: relics.map { DungeonRelicEntry(relicID: $0, remainingUses: 0) }
        )
        let advanced = runState.advancedToNextFloor(
            carryoverHP: 3,
            currentFloorMoveCount: 1,
            currentRelicEntries: runState.relicEntries
        )
        for relic in relics {
            XCTAssertEqual(advanced.relicEntries.first { $0.relicID == relic }?.remainingUses, 1, "\(relic.displayName) should refill")
        }
    }

    func testStrongerEnemyDamageStillUsesRelicReductionAfterBaseDamage() {
        let damageTwoWatcher = EnemyDefinition(
            id: "damage-two-watcher",
            name: "見張り",
            position: GridPoint(x: 1, y: 1),
            behavior: .watcher(direction: MoveVector(dx: -1, dy: 0), range: 2),
            damage: 2
        )
        let damageThreeWatcher = EnemyDefinition(
            id: "damage-three-watcher",
            name: "見張り",
            position: GridPoint(x: 1, y: 1),
            behavior: .watcher(direction: MoveVector(dx: -1, dy: 0), range: 2),
            damage: 3
        )

        for (enemy, expectedHP) in [(damageTwoWatcher, 4), (damageThreeWatcher, 3)] {
            let core = makeCore(
                mode: makeDungeonMode(
                    spawn: GridPoint(x: 0, y: 0),
                    exit: GridPoint(x: 4, y: 4),
                    hp: 5,
                    turnLimit: 8,
                    enemies: [enemy],
                    runState: DungeonRunState(
                        dungeonID: "growth-tower",
                        carriedHP: 5,
                        relicEntries: [DungeonRelicEntry(relicID: .watcherMonocle)]
                    )
                )
            )

            playBasicMove(to: GridPoint(x: 0, y: 1), in: core)

            XCTAssertEqual(core.dungeonHP, expectedHP)
        }
    }

    func testStrongerMeteorDamageUsesMarkerRelicReductionAfterBaseDamage() throws {
        let marker = EnemyDefinition(
            id: "damage-three-marker",
            name: "メテオ兵",
            position: GridPoint(x: 3, y: 1),
            behavior: .marker(directions: [], range: 2),
            damage: 3
        )
        var selectedCore: GameCore?
        var selectedMove: BasicOrthogonalMove?
        for seed in 0..<200 {
            let core = makeCore(
                mode: makeDungeonMode(
                    spawn: GridPoint(x: 0, y: 0),
                    exit: GridPoint(x: 4, y: 4),
                    hp: 6,
                    turnLimit: 8,
                    enemies: [marker],
                    runState: DungeonRunState(
                        dungeonID: "growth-tower",
                        carriedHP: 6,
                        relicEntries: [DungeonRelicEntry(relicID: .starUmbrella)],
                        cardVariationSeed: UInt64(seed)
                    )
                )
            )
            if let warningMove = core.availableBasicOrthogonalMoves().first(where: {
                core.enemyWarningPoints.contains($0.destination)
            }) {
                selectedCore = core
                selectedMove = warningMove
                break
            }
        }

        let core = try XCTUnwrap(selectedCore)
        let warningMove = try XCTUnwrap(selectedMove)
        playBasicMove(to: warningMove.destination, in: core)

        XCTAssertEqual(core.dungeonHP, 4)
    }

    func testGuardianCloakReducesAllEnemyDamageWithoutStackingWithTargetedRelics() throws {
        let enemyCases: [(EnemyDefinition, GridPoint)] = [
            (
                EnemyDefinition(
                    id: "watcher",
                    name: "見張り",
                    position: GridPoint(x: 1, y: 1),
                    behavior: .watcher(direction: MoveVector(dx: -1, dy: 0), range: 2),
                    damage: 2
                ),
                GridPoint(x: 0, y: 1)
            ),
            (
                EnemyDefinition(
                    id: "rotating-watcher",
                    name: "回転見張り",
                    position: GridPoint(x: 1, y: 1),
                    behavior: .rotatingWatcher(
                        initialDirection: MoveVector(dx: -1, dy: 0),
                        rotationDirection: .clockwise,
                        range: 2
                    ),
                    damage: 2
                ),
                GridPoint(x: 0, y: 1)
            ),
            (
                EnemyDefinition(
                    id: "patrol",
                    name: "巡回兵",
                    position: GridPoint(x: 1, y: 1),
                    behavior: .patrol(path: [GridPoint(x: 1, y: 1), GridPoint(x: 2, y: 1)]),
                    damage: 2
                ),
                GridPoint(x: 0, y: 1)
            ),
            (
                EnemyDefinition(
                    id: "chaser",
                    name: "追跡兵",
                    position: GridPoint(x: 1, y: 1),
                    behavior: .chaser,
                    damage: 2
                ),
                GridPoint(x: 0, y: 1)
            )
        ]

        for (enemy, dangerPoint) in enemyCases {
            let core = makeCore(
                mode: makeDungeonMode(
                    spawn: GridPoint(x: 0, y: 0),
                    exit: GridPoint(x: 4, y: 4),
                    hp: 5,
                    turnLimit: 8,
                    enemies: [enemy],
                    runState: DungeonRunState(
                        dungeonID: "growth-tower",
                        carriedHP: 5,
                        relicEntries: [DungeonRelicEntry(relicID: .guardianCloak)]
                    )
                )
            )

            playBasicMove(to: dangerPoint, in: core)

            XCTAssertEqual(core.dungeonHP, 4, "\(enemy.name) should be reduced by 1")
        }

        let weakWatcher = EnemyDefinition(
            id: "weak-watcher",
            name: "見張り",
            position: GridPoint(x: 1, y: 1),
            behavior: .watcher(direction: MoveVector(dx: -1, dy: 0), range: 2),
            damage: 1
        )
        let weakCore = makeCore(
            mode: makeDungeonMode(
                spawn: GridPoint(x: 0, y: 0),
                exit: GridPoint(x: 4, y: 4),
                hp: 5,
                turnLimit: 8,
                enemies: [weakWatcher],
                runState: DungeonRunState(
                    dungeonID: "growth-tower",
                    carriedHP: 5,
                    relicEntries: [DungeonRelicEntry(relicID: .guardianCloak)]
                )
            )
        )
        playBasicMove(to: GridPoint(x: 0, y: 1), in: weakCore)
        XCTAssertEqual(weakCore.dungeonHP, 5)

        let stackedCore = makeCore(
            mode: makeDungeonMode(
                spawn: GridPoint(x: 0, y: 0),
                exit: GridPoint(x: 4, y: 4),
                hp: 5,
                turnLimit: 8,
                enemies: [weakWatcher],
                runState: DungeonRunState(
                    dungeonID: "growth-tower",
                    carriedHP: 5,
                    relicEntries: [
                        DungeonRelicEntry(relicID: .watcherMonocle),
                        DungeonRelicEntry(relicID: .guardianCloak)
                    ]
                )
            )
        )
        playBasicMove(to: GridPoint(x: 0, y: 1), in: stackedCore)
        XCTAssertEqual(stackedCore.dungeonHP, 5)

        let strongStackedCore = makeCore(
            mode: makeDungeonMode(
                spawn: GridPoint(x: 0, y: 0),
                exit: GridPoint(x: 4, y: 4),
                hp: 5,
                turnLimit: 8,
                enemies: [
                    EnemyDefinition(
                        id: "strong-watcher",
                        name: "見張り",
                        position: GridPoint(x: 1, y: 1),
                        behavior: .watcher(direction: MoveVector(dx: -1, dy: 0), range: 2),
                        damage: 2
                    )
                ],
                runState: DungeonRunState(
                    dungeonID: "growth-tower",
                    carriedHP: 5,
                    relicEntries: [
                        DungeonRelicEntry(relicID: .watcherMonocle),
                        DungeonRelicEntry(relicID: .guardianCloak)
                    ]
                )
            )
        )
        playBasicMove(to: GridPoint(x: 0, y: 1), in: strongStackedCore)
        XCTAssertEqual(strongStackedCore.dungeonHP, 4)

        let marker = EnemyDefinition(
            id: "guardian-marker",
            name: "メテオ兵",
            position: GridPoint(x: 3, y: 1),
            behavior: .marker(directions: [], range: 2),
            damage: 2
        )
        var selectedCore: GameCore?
        var selectedMove: BasicOrthogonalMove?
        for seed in 0..<200 {
            let core = makeCore(
                mode: makeDungeonMode(
                    spawn: GridPoint(x: 0, y: 0),
                    exit: GridPoint(x: 4, y: 4),
                    hp: 5,
                    turnLimit: 8,
                    enemies: [marker],
                    runState: DungeonRunState(
                        dungeonID: "growth-tower",
                        carriedHP: 5,
                        relicEntries: [DungeonRelicEntry(relicID: .guardianCloak)],
                        cardVariationSeed: UInt64(seed)
                    )
                )
            )
            if let warningMove = core.availableBasicOrthogonalMoves().first(where: {
                core.enemyWarningPoints.contains($0.destination)
            }) {
                selectedCore = core
                selectedMove = warningMove
                break
            }
        }

        let markerCore = try XCTUnwrap(selectedCore)
        let warningMove = try XCTUnwrap(selectedMove)
        playBasicMove(to: warningMove.destination, in: markerCore)
        XCTAssertEqual(markerCore.dungeonHP, 4)
    }

    func testGrowthAndRogueTowerEnemyDamageScalesInLateFloors() throws {
        let growthTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let growthRunState = DungeonRunState(dungeonID: growthTower.id, carriedHP: 3, cardVariationSeed: 555)
        let growthFloorOne = try XCTUnwrap(growthTower.resolvedFloor(at: 0, runState: growthRunState))
        let growthFloorTwentyOne = try XCTUnwrap(growthTower.resolvedFloor(at: 20, runState: growthRunState))
        let growthFloorFortyOne = try XCTUnwrap(growthTower.resolvedFloor(at: 40, runState: growthRunState))

        XCTAssertTrue(growthFloorOne.enemies.allSatisfy { $0.damage == 1 })
        XCTAssertTrue(growthFloorTwentyOne.enemies.allSatisfy { $0.damage == 2 })
        XCTAssertTrue(growthFloorFortyOne.enemies.allSatisfy { $0.damage == 3 })

        let rogueTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))
        let rogueRunState = DungeonRunState(dungeonID: rogueTower.id, carriedHP: 3, rogueTowerSeed: 2468)
        let rogueFloorOne = try XCTUnwrap(rogueTower.resolvedFloor(at: 0, runState: rogueRunState))
        let rogueFloorTwentyOne = try XCTUnwrap(rogueTower.resolvedFloor(at: 20, runState: rogueRunState))
        let rogueFloorFortyOne = try XCTUnwrap(rogueTower.resolvedFloor(at: 40, runState: rogueRunState))

        XCTAssertTrue(rogueFloorOne.enemies.allSatisfy { $0.damage == 1 })
        XCTAssertTrue(rogueFloorTwentyOne.enemies.allSatisfy { $0.damage == 2 })
        XCTAssertTrue(rogueFloorFortyOne.enemies.allSatisfy { $0.damage == 3 })
    }

    func testStrongerTrapAndLavaDamageUseTargetedRelicReduction() throws {
        let trapPoint = GridPoint(x: 1, y: 0)
        let trapCore = makeCore(
            mode: makeDungeonMode(
                spawn: GridPoint(x: 0, y: 0),
                exit: GridPoint(x: 4, y: 4),
                hp: 5,
                turnLimit: 8,
                hazards: [.damageTrap(points: [trapPoint], damage: 2)]
            )
        )
        playBasicMove(to: trapPoint, in: trapCore)
        XCTAssertEqual(trapCore.dungeonHP, 4)

        let trapRelicCore = makeCore(
            mode: makeDungeonMode(
                spawn: GridPoint(x: 0, y: 0),
                exit: GridPoint(x: 4, y: 4),
                hp: 5,
                turnLimit: 8,
                hazards: [.damageTrap(points: [trapPoint], damage: 2)],
                runState: DungeonRunState(
                    dungeonID: "growth-tower",
                    carriedHP: 5,
                    relicEntries: [DungeonRelicEntry(relicID: .trapSole)]
                )
            )
        )
        playBasicMove(to: trapPoint, in: trapRelicCore)
        XCTAssertEqual(trapRelicCore.dungeonHP, 5)

        let trapCurseCore = makeCore(
            mode: makeDungeonMode(
                spawn: GridPoint(x: 0, y: 0),
                exit: GridPoint(x: 4, y: 4),
                hp: 5,
                turnLimit: 8,
                hazards: [.damageTrap(points: [trapPoint], damage: 2)],
                runState: DungeonRunState(
                    dungeonID: "growth-tower",
                    carriedHP: 5,
                    relicEntries: [DungeonRelicEntry(relicID: .trapSole)],
                    curseEntries: [DungeonCurseEntry(curseID: .trapMagnet)]
                )
            )
        )
        playBasicMove(to: trapPoint, in: trapCurseCore)
        XCTAssertEqual(trapCurseCore.dungeonHP, 5)

        let lavaPoint = GridPoint(x: 1, y: 0)
        let lavaCore = makeCore(
            mode: makeDungeonMode(
                spawn: GridPoint(x: 0, y: 0),
                exit: GridPoint(x: 4, y: 4),
                hp: 5,
                turnLimit: 8,
                hazards: [.lavaTile(points: [lavaPoint], damage: 2)],
                runState: DungeonRunState(
                    dungeonID: "growth-tower",
                    carriedHP: 5,
                    relicEntries: [DungeonRelicEntry(relicID: .emberCloak)]
                )
            )
        )
        playBasicMove(to: lavaPoint, in: lavaCore)
        XCTAssertEqual(lavaCore.dungeonHP, 4)

        let waitCore = makeCore(
            mode: makeDungeonMode(
                spawn: GridPoint(x: 0, y: 0),
                exit: GridPoint(x: 4, y: 4),
                hp: 5,
                turnLimit: 8,
                hazards: [.lavaTile(points: [GridPoint(x: 0, y: 0)], damage: 2)],
                cardAcquisitionMode: .inventoryOnly,
                runState: DungeonRunState(
                    dungeonID: "growth-tower",
                    carriedHP: 5,
                    rewardInventoryEntries: [DungeonInventoryEntry(support: .refillEmptySlots, rewardUses: 1)],
                    relicEntries: [DungeonRelicEntry(relicID: .emberCloak)]
                )
            )
        )
        let supportIndex = try XCTUnwrap(waitCore.handStacks.firstIndex { $0.topCard?.supportCard == .refillEmptySlots })
        waitCore.playSupportCard(at: supportIndex)
        XCTAssertEqual(waitCore.dungeonHP, 4)
    }

    func testGrowthAndRogueTowerHazardDamageDifferentiatesCaltropsAndLava() throws {
        let growthTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let growthRunState = DungeonRunState(dungeonID: growthTower.id, carriedHP: 3, cardVariationSeed: 777)
        let growthFloorTwenty = try XCTUnwrap(growthTower.resolvedFloor(at: 19, runState: growthRunState))
        let growthFloorTwentyOne = try XCTUnwrap(growthTower.resolvedFloor(at: 20, runState: growthRunState))
        let growthFloorForty = try XCTUnwrap(growthTower.resolvedFloor(at: 39, runState: growthRunState))
        let growthFloorFortyOne = try XCTUnwrap(growthTower.resolvedFloor(at: 40, runState: growthRunState))

        XCTAssertEqual(damageTrapDamages(in: growthFloorTwenty), [1])
        XCTAssertEqual(damageTrapDamages(in: growthFloorTwentyOne), [1])
        XCTAssertEqual(damageTrapDamages(in: growthFloorForty), [1])
        XCTAssertEqual(damageTrapDamages(in: growthFloorFortyOne), [1])
        XCTAssertEqual(lavaTileDamages(in: growthFloorForty), [2])
        XCTAssertEqual(lavaTileDamages(in: growthFloorFortyOne), [2])

        let rogueTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))
        let rogueRunState = DungeonRunState(dungeonID: rogueTower.id, carriedHP: 3, rogueTowerSeed: 2468)
        let rogueFloorTwenty = try XCTUnwrap(rogueTower.resolvedFloor(at: 19, runState: rogueRunState))
        let rogueFloorTwentyOne = try XCTUnwrap(rogueTower.resolvedFloor(at: 20, runState: rogueRunState))
        let rogueFloorForty = try XCTUnwrap(rogueTower.resolvedFloor(at: 39, runState: rogueRunState))
        let rogueFloorFortyOne = try XCTUnwrap(rogueTower.resolvedFloor(at: 40, runState: rogueRunState))

        XCTAssertEqual(damageTrapDamages(in: rogueFloorTwenty), [1])
        XCTAssertEqual(damageTrapDamages(in: rogueFloorTwentyOne), [1])
        XCTAssertEqual(lavaTileDamages(in: rogueFloorForty), [2])
        XCTAssertEqual(lavaTileDamages(in: rogueFloorFortyOne), [2])
    }

    func testTargetedBuffRelicsReduceMeteorTrapLavaPoisonAndFallDamage() {
        let marker = EnemyDefinition(
            id: "marker",
            name: "メテオ兵",
            position: GridPoint(x: 3, y: 1),
            behavior: .marker(directions: [], range: 2)
        )
        let markerCore = makeCore(
            mode: makeDungeonMode(
                spawn: GridPoint(x: 0, y: 0),
                exit: GridPoint(x: 4, y: 4),
                hp: 4,
                turnLimit: 8,
                enemies: [marker],
                runState: DungeonRunState(
                    dungeonID: "growth-tower",
                    carriedHP: 4,
                    relicEntries: [DungeonRelicEntry(relicID: .starUmbrella)],
                    curseEntries: [DungeonCurseEntry(curseID: .meteorRod)],
                    cardVariationSeed: 123
                )
            )
        )
        guard let warningMove = markerCore.availableBasicOrthogonalMoves().first(where: {
            markerCore.enemyWarningPoints.contains($0.destination)
        }) else {
            XCTFail("メテオ警告へ踏み込む基本移動候補が必要です")
            return
        }
        playBasicMove(to: warningMove.destination, in: markerCore)
        XCTAssertEqual(markerCore.dungeonHP, 3)

        let trapPoint = GridPoint(x: 1, y: 0)
        let lavaPoint = GridPoint(x: 2, y: 0)
        let brittlePoint = GridPoint(x: 3, y: 0)
        let hazardCore = makeCore(
            mode: makeDungeonMode(
                spawn: GridPoint(x: 0, y: 0),
                exit: GridPoint(x: 4, y: 4),
                hp: 6,
                turnLimit: 8,
                hazards: [
                    .damageTrap(points: [trapPoint], damage: 1),
                    .lavaTile(points: [lavaPoint], damage: 1),
                    .brittleFloor(points: [brittlePoint])
                ],
                runState: DungeonRunState(
                    dungeonID: "growth-tower",
                    carriedHP: 6,
                    relicEntries: [
                        DungeonRelicEntry(relicID: .trapSole),
                        DungeonRelicEntry(relicID: .emberCloak),
                        DungeonRelicEntry(relicID: .fallAnchor)
                    ],
                    curseEntries: [
                        DungeonCurseEntry(curseID: .trapMagnet),
                        DungeonCurseEntry(curseID: .oilSoakedBoots),
                        DungeonCurseEntry(curseID: .glassAnklet)
                    ]
                )
            )
        )
        playBasicMove(to: trapPoint, in: hazardCore)
        XCTAssertEqual(hazardCore.dungeonHP, 6)
        playBasicMove(to: lavaPoint, in: hazardCore)
        XCTAssertEqual(hazardCore.dungeonHP, 4)
        playBasicMove(to: brittlePoint, in: hazardCore)
        playBasicMove(to: lavaPoint, in: hazardCore)
        XCTAssertEqual(hazardCore.dungeonHP, 2)
        playBasicMove(to: brittlePoint, in: hazardCore)
        XCTAssertEqual(hazardCore.dungeonHP, 1)

        let poisonPoint = GridPoint(x: 1, y: 0)
        let poisonCore = makeCore(
            mode: makeDungeonMode(
                spawn: GridPoint(x: 0, y: 0),
                exit: GridPoint(x: 4, y: 4),
                hp: 3,
                turnLimit: 8,
                tileEffectOverrides: [poisonPoint: .poisonTrap],
                runState: DungeonRunState(
                    dungeonID: "growth-tower",
                    carriedHP: 3,
                    relicEntries: [DungeonRelicEntry(relicID: .antidoteStone)],
                    curseEntries: [DungeonCurseEntry(curseID: .poisonVial)]
                )
            )
        )
        playBasicMove(to: poisonPoint, in: poisonCore)
        XCTAssertEqual(poisonCore.poisonDamageTicksRemaining, 3)
    }

    func testRelicRewardRarityWeightsImproveLegendaryRateOnFastClear() {
        let entries = DungeonRelicID.allCases.map {
            DungeonWeightedRewardPoolEntry(item: .relic($0), weight: 1)
        }
        func legendaryCount(tuning: DungeonRewardDrawTuning) -> Int {
            (1...2_000).reduce(0) { count, seed in
                let draw = DungeonWeightedRewardPools.drawUniqueOffers(
                    from: entries,
                    context: .clearReward,
                    count: 1,
                    seed: UInt64(seed),
                    floorIndex: 20,
                    salt: 0x1E6E,
                    tuning: tuning
                ).first
                return count + ((draw?.relic?.rarity == .legendary) ? 1 : 0)
            }
        }

        let normalLegendaryCount = legendaryCount(
            tuning: DungeonRewardDrawTuning(clearMoveCount: 10, turnLimit: 10)
        )
        let fastLegendaryCount = legendaryCount(
            tuning: DungeonRewardDrawTuning(clearMoveCount: 5, turnLimit: 10)
        )
        let suppressedLegendaryCount = legendaryCount(
            tuning: DungeonRewardDrawTuning(
                clearMoveCount: 5,
                turnLimit: 10,
                suppressRelicQualityBonus: true
            )
        )

        XCTAssertGreaterThan(fastLegendaryCount, normalLegendaryCount)
        XCTAssertLessThanOrEqual(abs(suppressedLegendaryCount - normalLegendaryCount), 60)
    }

    func testSupportFloorPickupCanBeCollectedAsCardUse() throws {
        let pickup = DungeonCardPickupDefinition(
            id: "support-pickup",
            point: GridPoint(x: 1, y: 0),
            support: .refillEmptySlots
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            turnLimit: 8,
            cardAcquisitionMode: .inventoryOnly,
            cardPickups: [pickup]
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: pickup.point, in: core)

        XCTAssertTrue(core.collectedDungeonCardPickupIDs.contains(pickup.id))
        XCTAssertTrue(core.dungeonInventoryEntries.contains(DungeonInventoryEntry(support: .refillEmptySlots, rewardUses: 1)))
    }

    func testWarpedHourglassDoesNotChangeFloorPickupUses() throws {
        let pickup = DungeonCardPickupDefinition(
            id: "warped-pickup",
            point: GridPoint(x: 1, y: 0),
            card: .straightRight2,
            uses: 3
        )
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 3,
            curseEntries: [DungeonCurseEntry(curseID: .warpedHourglass)]
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            turnLimit: 8,
            cardAcquisitionMode: .inventoryOnly,
            cardPickups: [pickup],
            runState: runState
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: pickup.point, in: core)

        XCTAssertTrue(core.collectedDungeonCardPickupIDs.contains(pickup.id))
        XCTAssertTrue(core.dungeonInventoryEntries.contains(DungeonInventoryEntry(card: .straightRight2, rewardUses: 3)))
    }

    func testRelicRewardSelectionCarriesRelicWithoutUsingCardSlot() {
        let runState = DungeonRunState(dungeonID: "growth-tower", carriedHP: 3)
        let nextState = runState.advancedToNextFloor(
            carryoverHP: 3,
            currentFloorMoveCount: 6,
            rewardSelection: .addRelic(.glowingHeart),
            currentInventoryEntries: []
        )

        XCTAssertEqual(nextState.rewardInventoryEntries, [])
        XCTAssertEqual(nextState.relicEntries.map(\.relicID), [.glowingHeart])
        XCTAssertEqual(nextState.carriedHP, 5)
    }

    func testGrowthTowerWeightedRewardPoolsExposeSupportAndReserveRelics() {
        let rewardEntries = DungeonWeightedRewardPools.entries(floorIndex: 12, context: .clearReward)

        XCTAssertTrue(
            rewardEntries.contains { entry in
                if case .support = entry.item {
                    return entry.weight > 0
                }
                return false
            },
            "中盤以降の報酬プールには補助カードを低確率枠として含める"
        )
        XCTAssertTrue(
            rewardEntries.contains { entry in
                if case .relic = entry.item {
                    return entry.weight > 0
                }
                return false
            },
            "レリックはクリア報酬プールへ低確率枠として含める"
        )
    }

    func testGrowthTowerRewardPoolBiasesSupportCardsForNextFloorThreats() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let nextFloor = tower.floors[34]
        let baseEntries = DungeonWeightedRewardPools.entries(floorIndex: 33, context: .clearReward)
        let counteredEntries = DungeonWeightedRewardPools.entries(
            floorIndex: 33,
            context: .clearReward,
            countering: nextFloor
        )

        XCTAssertGreaterThan(
            supportWeight(.darknessSpell, in: counteredEntries),
            supportWeight(.darknessSpell, in: baseEntries)
        )
        XCTAssertGreaterThan(
            supportWeight(.railBreakSpell, in: counteredEntries),
            supportWeight(.railBreakSpell, in: baseEntries)
        )
        XCTAssertGreaterThan(
            supportWeight(.panacea, in: counteredEntries),
            supportWeight(.panacea, in: baseEntries)
        )
        XCTAssertGreaterThan(
            supportWeight(.barrierSpell, in: counteredEntries),
            supportWeight(.barrierSpell, in: baseEntries)
        )
        XCTAssertGreaterThan(
            supportWeight(.freezeSpell, in: counteredEntries),
            supportWeight(.freezeSpell, in: baseEntries)
        )
    }

    func testGrowthTowerFortyNinthFloorRewardBiasesRefillForFinalHandLoss() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let finalFloor = tower.floors[49]
        let baseEntries = DungeonWeightedRewardPools.entries(floorIndex: 48, context: .clearReward)
        let counteredEntries = DungeonWeightedRewardPools.entries(
            floorIndex: 48,
            context: .clearReward,
            countering: finalFloor
        )

        XCTAssertGreaterThan(
            supportWeight(.refillEmptySlots, in: counteredEntries),
            supportWeight(.refillEmptySlots, in: baseEntries),
            "49Fクリア報酬は50Fの手札破壊に備えて補給を強める"
        )
        XCTAssertGreaterThan(
            supportWeight(.refillEmptySlots, in: counteredEntries),
            supportWeight(.annihilationSpell, in: counteredEntries),
            "50F対策では補給を全滅の呪文より優先し、手札切れの詰み感を抑える"
        )
    }

    func testGrowthTowerSupportPoolsKeepAnnihilationSpellsRareComparedWithRoleCounters() {
        let floorIndexes = [5, 10, 15, 20, 30, 40]
        let contexts: [DungeonWeightedRewardPoolContext] = [.floorPickup, .clearReward]
        let roleCounters: Set<SupportCard> = [
            .darknessSpell,
            .railBreakSpell,
            .freezeSpell,
            .barrierSpell,
            .panacea,
            .flySpell
        ]

        for floorIndex in floorIndexes {
            for context in contexts {
                let entries = DungeonWeightedRewardPools.entries(floorIndex: floorIndex, context: context)
                let presentCounterWeights = roleCounters
                    .map { supportWeight($0, in: entries) }
                    .filter { $0 > 0 }
                guard let weakestCounterWeight = presentCounterWeights.min() else { continue }

                XCTAssertLessThanOrEqual(
                    supportWeight(.singleAnnihilationSpell, in: entries),
                    weakestCounterWeight,
                    "\(context) \(floorIndex + 1)F では消滅の呪文を個別対策より強い通常候補にしない"
                )
                XCTAssertLessThanOrEqual(
                    supportWeight(.annihilationSpell, in: entries),
                    weakestCounterWeight,
                    "\(context) \(floorIndex + 1)F では全滅の呪文を個別対策より強い通常候補にしない"
                )
            }
        }
    }

    func testGrowthTowerCounterBiasesMakeRoleCountersOutweighAnnihilationSpells() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let nextFloor = tower.floors[34]
        let counteredEntries = DungeonWeightedRewardPools.entries(
            floorIndex: 33,
            context: .clearReward,
            countering: nextFloor
        )
        let annihilationWeight = supportWeight(.annihilationSpell, in: counteredEntries)
        let singleAnnihilationWeight = supportWeight(.singleAnnihilationSpell, in: counteredEntries)

        for support in [
            SupportCard.darknessSpell,
            .railBreakSpell,
            .panacea,
            .barrierSpell,
            .freezeSpell,
            .refillEmptySlots
        ] {
            XCTAssertGreaterThan(
                supportWeight(support, in: counteredEntries),
                annihilationWeight,
                "\(support.displayName) は次階対策として全滅の呪文より優先される必要があります"
            )
            XCTAssertGreaterThan(
                supportWeight(support, in: counteredEntries),
                singleAnnihilationWeight,
                "\(support.displayName) は次階対策として消滅の呪文より優先される必要があります"
            )
        }
    }

    func testGrowthTowerEarlyFloorPoolsIncludeSingleAnnihilationSpellOnly() {
        let pickupSupports = DungeonWeightedRewardPools
            .entries(floorIndex: 0, context: .floorPickup)
            .compactMap { entry -> SupportCard? in
                guard entry.weight > 0, case .support(let support) = entry.item else { return nil }
                return support
            }
        let rewardSupports = DungeonWeightedRewardPools
            .entries(floorIndex: 0, context: .clearReward)
            .compactMap { entry -> SupportCard? in
                guard entry.weight > 0, case .support(let support) = entry.item else { return nil }
                return support
            }

        XCTAssertEqual(Set(pickupSupports), [.refillEmptySlots, .singleAnnihilationSpell])
        XCTAssertEqual(Set(rewardSupports), [.refillEmptySlots, .singleAnnihilationSpell])
        XCTAssertFalse(pickupSupports.contains(.annihilationSpell))
        XCTAssertFalse(pickupSupports.contains(.darknessSpell))
        XCTAssertFalse(pickupSupports.contains(.railBreakSpell))
        XCTAssertFalse(pickupSupports.contains(.freezeSpell))
        XCTAssertFalse(pickupSupports.contains(.barrierSpell))
        XCTAssertFalse(rewardSupports.contains(.annihilationSpell))
        XCTAssertFalse(rewardSupports.contains(.darknessSpell))
        XCTAssertFalse(rewardSupports.contains(.railBreakSpell))
        XCTAssertFalse(rewardSupports.contains(.freezeSpell))
        XCTAssertFalse(rewardSupports.contains(.barrierSpell))
    }

    func testRogueTowerRewardPoolsBalanceDirectionsAcrossAllBands() {
        let floorIndexes = [0, 5, 10, 15, 20, 30, 40]
        let contexts: [DungeonWeightedRewardPoolContext] = [.floorPickup, .clearReward]
        let straightCards: [MoveCard] = [.straightUp2, .straightRight2, .straightDown2, .straightLeft2]
        let diagonalCards: [MoveCard] = [.diagonalUpRight2, .diagonalDownRight2, .diagonalDownLeft2, .diagonalUpLeft2]
        let kingChoiceCards: [MoveCard] = [
            .kingUpwardDiagonalChoice,
            .kingRightDiagonalChoice,
            .kingDownwardDiagonalChoice,
            .kingLeftDiagonalChoice
        ]
        let knightChoiceCards: [MoveCard] = [
            .knightUpwardChoice,
            .knightRightwardChoice,
            .knightDownwardChoice,
            .knightLeftwardChoice
        ]

        for floorIndex in floorIndexes {
            for context in contexts {
                let entries = DungeonWeightedRewardPools.entries(
                    floorIndex: floorIndex,
                    context: context,
                    profile: .rogueTower
                )
                assertEqualMoveWeights(straightCards, in: entries, label: "\(context) \(floorIndex + 1)F straight")
                assertEqualMoveWeights(diagonalCards, in: entries, label: "\(context) \(floorIndex + 1)F diagonal")
                assertEqualMoveWeights(MoveCard.directionalRayCards, in: entries, label: "\(context) \(floorIndex + 1)F ray")
                assertEqualMoveWeights(kingChoiceCards, in: entries, label: "\(context) \(floorIndex + 1)F king choice")
                assertEqualMoveWeights(knightChoiceCards, in: entries, label: "\(context) \(floorIndex + 1)F knight choice")
            }
        }
    }

    func testRogueTowerRewardPoolShiftsFromSingleDirectionToChoiceCards() {
        let earlyEntries = DungeonWeightedRewardPools.entries(
            floorIndex: 0,
            context: .clearReward,
            profile: .rogueTower
        )
        let deepEntries = DungeonWeightedRewardPools.entries(
            floorIndex: 40,
            context: .clearReward,
            profile: .rogueTower
        )
        let earlySingle = singleDirectionMoveWeight(in: earlyEntries)
        let earlyRay = rayMoveWeight(in: earlyEntries)
        let earlyChoice = choiceMoveWeight(in: earlyEntries)
        let deepSingle = singleDirectionMoveWeight(in: deepEntries)
        let deepRay = rayMoveWeight(in: deepEntries)
        let deepChoice = choiceMoveWeight(in: deepEntries)

        XCTAssertGreaterThan(earlySingle, earlyRay)
        XCTAssertGreaterThan(earlyRay, earlyChoice)
        XCTAssertGreaterThan(deepChoice, deepSingle)
        XCTAssertGreaterThan(deepSingle, deepRay)
    }

    func testRogueTowerKnightMovementStyleKeepsOneStepDirectionWeightsBalanced() {
        let entries = DungeonWeightedRewardPools.entries(
            floorIndex: 20,
            context: .clearReward,
            movementStyle: .knight,
            profile: .rogueTower
        )

        assertEqualMoveWeights(
            [.straightUp1, .straightRight1, .straightDown1, .straightLeft1],
            in: entries,
            label: "knight one-step replacement"
        )
    }

    func testGrowthTowerRewardPoolsBalanceDirectionsAcrossAllBands() {
        let floorIndexes = [0, 5, 10, 15, 20, 30, 40]
        let contexts: [DungeonWeightedRewardPoolContext] = [.floorPickup, .clearReward]
        let straightCards: [MoveCard] = [.straightUp2, .straightRight2, .straightDown2, .straightLeft2]
        let diagonalCards: [MoveCard] = [.diagonalUpRight2, .diagonalDownRight2, .diagonalDownLeft2, .diagonalUpLeft2]
        let knightChoiceCards: [MoveCard] = [
            .knightUpwardChoice,
            .knightRightwardChoice,
            .knightDownwardChoice,
            .knightLeftwardChoice
        ]
        let kingChoiceCards: [MoveCard] = [
            .kingUpwardDiagonalChoice,
            .kingRightDiagonalChoice,
            .kingDownwardDiagonalChoice,
            .kingLeftDiagonalChoice
        ]

        for floorIndex in floorIndexes {
            for context in contexts {
                let entries = DungeonWeightedRewardPools.entries(
                    floorIndex: floorIndex,
                    context: context
                )
                assertBalancedMoveWeights(straightCards, in: entries, label: "\(context) \(floorIndex + 1)F straight")
                assertBalancedMoveWeights(diagonalCards, in: entries, label: "\(context) \(floorIndex + 1)F diagonal")
                assertBalancedMoveWeights(MoveCard.directionalRayCards, in: entries, label: "\(context) \(floorIndex + 1)F ray")
                assertBalancedMoveWeights(knightChoiceCards, in: entries, label: "\(context) \(floorIndex + 1)F knight choice")
                XCTAssertEqual(
                    kingChoiceCards.reduce(0) { $0 + moveWeight($1, in: entries) },
                    0,
                    "成長塔には試練塔専用のキング斜め選択カードを混ぜない"
                )
            }
        }
    }

    func testGrowthTowerRewardPoolKeepsEarlySingleDirectionEmphasis() {
        let earlyPickupEntries = DungeonWeightedRewardPools.entries(floorIndex: 0, context: .floorPickup)
        let earlyRewardEntries = DungeonWeightedRewardPools.entries(floorIndex: 0, context: .clearReward)

        XCTAssertGreaterThan(singleDirectionMoveWeight(in: earlyPickupEntries), rayMoveWeight(in: earlyPickupEntries))
        XCTAssertGreaterThan(singleDirectionMoveWeight(in: earlyPickupEntries), knightChoiceMoveWeight(in: earlyPickupEntries))
        XCTAssertGreaterThan(singleDirectionMoveWeight(in: earlyRewardEntries), rayMoveWeight(in: earlyRewardEntries))
        XCTAssertGreaterThan(singleDirectionMoveWeight(in: earlyRewardEntries), knightChoiceMoveWeight(in: earlyRewardEntries))
    }

    func testGrowthTowerRemedySupportPoolsStartInMiddleFloors() {
        let middlePickupSupports = supportPoolCards(floorIndex: 5, context: .floorPickup)
        let middleRewardSupports = supportPoolCards(floorIndex: 5, context: .clearReward)
        let laterPickupSupports = supportPoolCards(floorIndex: 10, context: .floorPickup)
        let laterRewardSupports = supportPoolCards(floorIndex: 10, context: .clearReward)

        XCTAssertFalse(middlePickupSupports.contains(.antidote))
        XCTAssertFalse(middleRewardSupports.contains(.antidote))
        XCTAssertTrue(middlePickupSupports.contains(.panacea))
        XCTAssertTrue(middleRewardSupports.contains(.panacea))
        XCTAssertFalse(laterPickupSupports.contains(.antidote))
        XCTAssertTrue(laterPickupSupports.contains(.panacea))
        XCTAssertTrue(laterPickupSupports.contains(.darknessSpell))
        XCTAssertTrue(laterPickupSupports.contains(.railBreakSpell))
        XCTAssertFalse(laterRewardSupports.contains(.antidote))
        XCTAssertTrue(laterRewardSupports.contains(.panacea))
        XCTAssertTrue(laterRewardSupports.contains(.darknessSpell))
        XCTAssertTrue(laterRewardSupports.contains(.railBreakSpell))
    }

    func testGrowthTowerResolvedCardsUseCurrentMoveCardsAndExcludeFixedWarp() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let runState = DungeonRunState(
            dungeonID: tower.id,
            carriedHP: 3,
            cardVariationSeed: 777
        )
        let currentMoveCards = Set(MoveCard.allCases)

        for floorIndex in tower.floors.indices {
            let floor = try XCTUnwrap(tower.resolvedFloor(at: floorIndex, runState: runState))
            XCTAssertTrue(
                floor.cardPickups.allSatisfy { pickup in
                    pickup.supportCard != nil || pickup.moveCard.map { currentMoveCards.contains($0) } == true
                }
            )
            XCTAssertTrue(floor.rewardMoveCardsAfterClear.allSatisfy { currentMoveCards.contains($0) })
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
        let upPickup = try XCTUnwrap(mode.dungeonRules?.cardPickups.first { $0.id == "tutorial-1-up2" })
        let rightPickup = try XCTUnwrap(mode.dungeonRules?.cardPickups.first { $0.id == "tutorial-1-right2" })

        playBasicMove(to: upPickup.point, in: core)

        XCTAssertEqual(
            core.dungeonInventoryEntries,
            [DungeonInventoryEntry(card: .straightUp2, rewardUses: 1)]
        )
        XCTAssertFalse(core.activeDungeonCardPickups.contains { $0.id == upPickup.id })

        playMove(to: rightPickup.point, in: core)

        XCTAssertFalse(core.dungeonInventoryEntries.contains { $0.card == .straightUp2 })
        XCTAssertTrue(core.dungeonInventoryEntries.contains { $0.card == .straightRight2 && $0.rewardUses == 1 && $0.pickupUses == 0 })
    }

    func testDungeonResumeSnapshotRestoresCurrentFloorState() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let mode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower))
        let core = makeCore(mode: mode)
        let upPickup = try XCTUnwrap(mode.dungeonRules?.cardPickups.first { $0.id == "tutorial-1-up2" })

        playBasicMove(to: upPickup.point, in: core)
        core.overrideEnemyFreezeTurnsRemainingForTesting(2)
        core.overrideDamageBarrierTurnsRemainingForTesting(2)

        let snapshot = try XCTUnwrap(core.makeDungeonResumeSnapshot())
        let resumeMode = try XCTUnwrap(DungeonLibrary.shared.resumeMode(from: snapshot))
        let restoredCore = makeCore(mode: resumeMode)

        XCTAssertTrue(restoredCore.restoreDungeonResumeSnapshot(snapshot))
        XCTAssertEqual(restoredCore.current, core.current)
        XCTAssertEqual(restoredCore.moveCount, core.moveCount)
        XCTAssertEqual(restoredCore.dungeonHP, core.dungeonHP)
        XCTAssertEqual(restoredCore.enemyFreezeTurnsRemaining, 2)
        XCTAssertEqual(restoredCore.damageBarrierTurnsRemaining, 2)
        XCTAssertEqual(restoredCore.remainingDungeonTurns, core.remainingDungeonTurns)
        XCTAssertEqual(restoredCore.dungeonInventoryEntries, core.dungeonInventoryEntries)
        XCTAssertEqual(restoredCore.collectedDungeonCardPickupIDs, core.collectedDungeonCardPickupIDs)
        XCTAssertEqual(Set(restoredCore.activeDungeonCardPickups.map(\.id)), Set(core.activeDungeonCardPickups.map(\.id)))
        XCTAssertEqual(restoredCore.dungeonRunLogEntries, core.dungeonRunLogEntries)
    }

    func testDungeonRunLogCarriesThroughFloorTransitionsAndFalls() throws {
        let entry = DungeonRunLogEntry(
            sequence: 0,
            floorNumber: 1,
            turn: 1,
            point: GridPoint(x: 1, y: 0),
            kind: .damage,
            hpBefore: 3,
            hpAfter: 2,
            message: "罠でHP -1（HP 3→2）"
        )
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 2,
            runLogEntries: [entry]
        )

        let advanced = runState.advancedToNextFloor(
            carryoverHP: 2,
            currentFloorMoveCount: 3,
            currentRunLogEntries: [entry]
        )
        let fallen = advanced.fallenToPreviousFloor(
            carryoverHP: 1,
            currentFloorMoveCount: 2,
            currentInventoryEntries: [],
            landingPoint: GridPoint(x: 0, y: 0),
            currentFloorCrackedPoints: [],
            currentFloorCollapsedPoints: [],
            currentRunLogEntries: advanced.runLogEntries
        )

        XCTAssertEqual(advanced.runLogEntries, [entry])
        XCTAssertEqual(fallen.runLogEntries, [entry])
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

    func testDungeonInventoryCarriesAllRemainingUsesBetweenFloors() {
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
            [
                DungeonInventoryEntry(card: .straightRight2, rewardUses: 6, pickupUses: 0),
                DungeonInventoryEntry(card: .straightUp2, rewardUses: 1, pickupUses: 0)
            ]
        )
    }

    func testDungeonInventoryEntryNormalizesLegacyPickupUsesIntoHandUses() {
        let entry = DungeonInventoryEntry(card: .straightRight2, rewardUses: 2, pickupUses: 1)

        XCTAssertEqual(entry.rewardUses, 3)
        XCTAssertEqual(entry.pickupUses, 0)
        XCTAssertEqual(entry.totalUses, 3)
    }

    func testDungeonRewardSelectionCanAddDuplicateRewardAndRemoveCarriedRewardCards() {
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
        let duplicated = runState.advancedToNextFloor(
            carryoverHP: 2,
            currentFloorMoveCount: 5,
            rewardSelection: .add(.straightRight2)
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
                DungeonInventoryEntry(card: .rayRight, rewardUses: 2)
            ]
        )
        XCTAssertEqual(
            duplicated.rewardInventoryEntries,
            [
                DungeonInventoryEntry(card: .straightRight2, rewardUses: 4),
                DungeonInventoryEntry(card: .straightUp2, rewardUses: 1)
            ]
        )
        XCTAssertEqual(
            removed.rewardInventoryEntries,
            [DungeonInventoryEntry(card: .straightRight2, rewardUses: 2)]
        )
    }

    func testDungeonRewardSelectionKeepsPickupUsesAutomatically() {
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
            currentInventoryEntries: [
                DungeonInventoryEntry(card: .straightRight2, rewardUses: 2),
                DungeonInventoryEntry(card: .straightUp2, pickupUses: 1)
            ]
        )
        let ignoredUsedPickup = runState.advancedToNextFloor(
            carryoverHP: 2,
            currentFloorMoveCount: 5,
            rewardSelection: .carryOverPickup(.straightUp2),
            currentInventoryEntries: [
                DungeonInventoryEntry(card: .straightRight2, rewardUses: 2),
                DungeonInventoryEntry(card: .straightUp2, pickupUses: 0)
            ],
            rewardAddUses: 3
        )
        let mergedExistingReward = runState.advancedToNextFloor(
            carryoverHP: 2,
            currentFloorMoveCount: 5,
            rewardSelection: .carryOverPickup(.straightRight2),
            currentInventoryEntries: [
                DungeonInventoryEntry(card: .straightRight2, rewardUses: 2, pickupUses: 1)
            ],
            rewardAddUses: 2
        )

        XCTAssertEqual(
            carriedPickup.rewardInventoryEntries,
            [
                DungeonInventoryEntry(card: .straightRight2, rewardUses: 2),
                DungeonInventoryEntry(card: .straightUp2, rewardUses: 1)
            ]
        )
        XCTAssertEqual(
            ignoredUsedPickup.rewardInventoryEntries,
            [DungeonInventoryEntry(card: .straightRight2, rewardUses: 2)]
        )
        XCTAssertEqual(
            mergedExistingReward.rewardInventoryEntries,
            [DungeonInventoryEntry(card: .straightRight2, rewardUses: 3)]
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
                deckPreset: .standardLight,
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

    func testDungeonRewardInventoryRemovalDropsAllUses() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let mode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower))
        let core = makeCore(mode: mode)

        XCTAssertTrue(core.addDungeonInventoryCardForTesting(.straightRight2, pickupUses: 1, rewardUses: 2))
        XCTAssertTrue(core.removeDungeonRewardInventoryCard(.straightRight2))

        XCTAssertTrue(core.dungeonInventoryEntries.isEmpty)
        XCTAssertNil(core.handStacks.first { $0.representativeMove == .straightRight2 })
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
        XCTAssertEqual(core.dungeonInventoryEntries.first { $0.card == nineCards[0] }?.rewardUses, 2)
    }

    func testDungeonInventoryKindLimitCarriesAcrossNextFloorAndFallReturn() throws {
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            currentFloorIndex: 1,
            carriedHP: 3,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .straightRight2, rewardUses: 1)],
            dungeonInventoryKindLimit: 6
        )

        let advanced = runState.advancedToNextFloor(
            carryoverHP: 3,
            currentFloorMoveCount: 2,
            currentInventoryEntries: [DungeonInventoryEntry(card: .straightRight2, rewardUses: 1)]
        )
        XCTAssertEqual(advanced.dungeonInventoryKindLimit, 6)

        let fallen = advanced.fallenToPreviousFloor(
            carryoverHP: 2,
            currentFloorMoveCount: 1,
            currentInventoryEntries: [DungeonInventoryEntry(card: .straightRight2, rewardUses: 1)],
            landingPoint: GridPoint(x: 1, y: 1),
            currentFloorCrackedPoints: [],
            currentFloorCollapsedPoints: []
        )
        XCTAssertEqual(fallen.dungeonInventoryKindLimit, 6)
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

        for floor in tower.floors {
            let mode = floor.makeGameMode(dungeonID: tower.id)
            let core = makeCore(mode: mode, cards: [.kingUpRight, .straightRight2, .straightDown2, .straightLeft2, .straightRight2])
            var route: [GridPoint] = []
            if let unlockPoint = floor.exitLock?.unlockPoint {
                route.append(contentsOf: try orthogonalRoute(from: floor.spawnPoint, to: unlockPoint, in: floor))
                route.append(contentsOf: try orthogonalRoute(from: unlockPoint, to: floor.exitPoint, in: floor))
            } else {
                route = try orthogonalRoute(from: floor.spawnPoint, to: floor.exitPoint, in: floor)
            }

            for destination in route {
                playBasicMove(to: destination, in: core)
            }

            XCTAssertEqual(core.progress, .cleared, "\(floor.title) は基本移動だけでも出口へ届く必要があります")
            assertTurnLimitSlack(for: floor, after: core)
        }
    }

    func testTutorialTowerCardRoutesShortenRepresentativeBasicRoutes() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))

        let firstFloorMode = tower.floors[0].makeGameMode(dungeonID: tower.id)
        let firstCore = makeCore(mode: firstFloorMode)
        playBasicMove(to: GridPoint(x: 0, y: 1), in: firstCore)
        XCTAssertTrue(firstCore.dungeonInventoryEntries.contains { $0.card == .straightUp2 && $0.rewardUses == 1 && $0.pickupUses == 0 })
        playMove(to: GridPoint(x: 0, y: 3), in: firstCore)
        XCTAssertTrue(firstCore.dungeonInventoryEntries.contains { $0.card == .straightRight2 && $0.rewardUses == 1 && $0.pickupUses == 0 })
        playMove(to: GridPoint(x: 2, y: 3), in: firstCore)
        playBasicMove(to: GridPoint(x: 2, y: 4), in: firstCore)
        playBasicMove(to: GridPoint(x: 3, y: 4), in: firstCore)
        playBasicMove(to: GridPoint(x: 4, y: 4), in: firstCore)
        XCTAssertEqual(firstCore.progress, .cleared)
        assertTurnLimitSlack(for: tower.floors[0], after: firstCore)

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
        playMove(to: GridPoint(x: 6, y: 4), in: secondCore)
        for destination in try orthogonalRoute(from: GridPoint(x: 6, y: 4), to: tower.floors[1].exitPoint, in: tower.floors[1]) {
            playBasicMove(to: destination, in: secondCore)
        }
        XCTAssertEqual(secondCore.progress, .cleared)
        assertTurnLimitSlack(for: tower.floors[1], after: secondCore)

        let thirdRunState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 2,
            carriedHP: 3,
            clearedFloorCount: 2,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .rayLeft, rewardUses: 3)]
        )
        let thirdFloorMode = tower.floors[2].makeGameMode(
            dungeonID: tower.id,
            carriedHP: thirdRunState.carriedHP,
            runState: thirdRunState
        )
        let thirdCore = makeCore(mode: thirdFloorMode)
        playMove(to: GridPoint(x: 0, y: 4), in: thirdCore)
        XCTAssertEqual(thirdCore.progress, .cleared)
        assertTurnLimitSlack(for: tower.floors[2], after: thirdCore)
    }

    func testTutorialTowerRewardCardsCreateUsefulNextFloorMoves() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))

        XCTAssertEqual(tower.floors[0].rewardMoveCardsAfterClear, [
            .straightRight2,
            .straightUp2,
            .knightRightwardChoice
        ])
        XCTAssertEqual(tower.floors[1].rewardMoveCardsAfterClear, [
            .rayLeft,
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
            secondCore.availableMoves().contains { $0.moveCard == .straightRight2 && $0.destination == GridPoint(x: 6, y: 4) },
            "1F 報酬の右2は 2F の見張り射線下を抜ける短縮手になる想定です"
        )

        let thirdRunState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 2,
            carriedHP: 3,
            clearedFloorCount: 2,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .rayLeft, rewardUses: 3)]
        )
        let thirdMode = tower.floors[2].makeGameMode(dungeonID: tower.id, runState: thirdRunState)
        let thirdCore = makeCore(mode: thirdMode)
        XCTAssertTrue(
            thirdCore.availableMoves().contains { $0.moveCard == .rayLeft && $0.destination == GridPoint(x: 0, y: 4) },
            "2F 報酬の左連続は 3F のひび割れ床列を一気に抜ける手になる想定です"
        )
    }

    func testTutorialTowerPickupsAndRewardsUseCurrentMoveCards() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let currentMoveCards = Set(MoveCard.allCases)

        for floor in tower.floors {
            XCTAssertTrue(
                floor.cardPickups.allSatisfy { pickup in
                    pickup.moveCard.map { currentMoveCards.contains($0) } == true
                },
                "\(floor.title) の床落ちカードは現行カードだけを使う"
            )
            XCTAssertTrue(
                floor.rewardMoveCardsAfterClear.allSatisfy { currentMoveCards.contains($0) },
                "\(floor.title) の報酬候補は現行カードだけを使う"
            )
        }
    }

    func testTutorialTowerThirdFloorDirectBrittleRouteCollapsesFloorWithoutHPDamage() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let thirdFloorMode = tower.floors[2].makeGameMode(dungeonID: tower.id)
        let core = makeCore(mode: thirdFloorMode)

        for destination in [
            GridPoint(x: 7, y: 4),
            GridPoint(x: 6, y: 4),
            GridPoint(x: 5, y: 4),
            GridPoint(x: 4, y: 4),
            GridPoint(x: 3, y: 4),
            GridPoint(x: 2, y: 4),
            GridPoint(x: 1, y: 4),
            GridPoint(x: 0, y: 4)
        ] {
            playBasicMove(to: destination, in: core)
        }

        XCTAssertEqual(core.progress, .cleared)
        XCTAssertEqual(core.moveCount, 8)
        XCTAssertEqual(core.dungeonHP, 3, "ヒビ床は踏んだ瞬間には落下ダメージを受けず、崩落床として残ります")
        XCTAssertTrue(core.collapsedFloorPoints.contains(GridPoint(x: 3, y: 4)))
        XCTAssertTrue(core.collapsedFloorPoints.contains(GridPoint(x: 4, y: 4)))
        XCTAssertTrue(core.collapsedFloorPoints.contains(GridPoint(x: 5, y: 4)))
    }

    func testTutorialTowerFourthFloorRequiresKeyBeforeExit() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let fourthFloorMode = tower.floors[3].makeGameMode(dungeonID: tower.id)
        let lockedCore = makeCore(mode: fourthFloorMode)

        for destination in [
            GridPoint(x: 1, y: 4),
            GridPoint(x: 2, y: 4),
            GridPoint(x: 3, y: 4),
            GridPoint(x: 3, y: 5),
            GridPoint(x: 4, y: 5),
            GridPoint(x: 5, y: 5),
            GridPoint(x: 6, y: 5),
            GridPoint(x: 7, y: 5),
            GridPoint(x: 8, y: 5),
            GridPoint(x: 8, y: 4)
        ] {
            playBasicMove(to: destination, in: lockedCore)
        }
        XCTAssertEqual(lockedCore.progress, .playing)
        XCTAssertFalse(lockedCore.isDungeonExitUnlocked)

        let unlockedCore = makeCore(mode: fourthFloorMode)
        for destination in [
            GridPoint(x: 0, y: 5),
            GridPoint(x: 0, y: 6),
            GridPoint(x: 1, y: 6),
            GridPoint(x: 2, y: 6),
            GridPoint(x: 3, y: 6),
            GridPoint(x: 4, y: 6),
            GridPoint(x: 5, y: 6),
            GridPoint(x: 6, y: 6),
            GridPoint(x: 7, y: 6),
            GridPoint(x: 8, y: 6),
            GridPoint(x: 8, y: 5),
            GridPoint(x: 8, y: 4)
        ] {
            playBasicMove(to: destination, in: unlockedCore)
        }
        XCTAssertEqual(unlockedCore.progress, .cleared)
        XCTAssertTrue(unlockedCore.isDungeonExitUnlocked)
    }

    func testTutorialTowerFifthFloorVisibleTrapRouteCostsHPButDetourDoesNot() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let fifthFloorMode = tower.floors[4].makeGameMode(dungeonID: tower.id)
        let trapCore = makeCore(mode: fifthFloorMode)

        for destination in [
            GridPoint(x: 7, y: 4),
            GridPoint(x: 6, y: 4),
            GridPoint(x: 5, y: 4),
            GridPoint(x: 4, y: 4),
            GridPoint(x: 3, y: 4),
            GridPoint(x: 2, y: 4),
            GridPoint(x: 1, y: 4),
            GridPoint(x: 0, y: 4)
        ] {
            playBasicMove(to: destination, in: trapCore)
        }
        XCTAssertEqual(trapCore.progress, .cleared)
        XCTAssertEqual(trapCore.dungeonHP, 1)

        let detourCore = makeCore(mode: fifthFloorMode)
        for destination in [
            GridPoint(x: 8, y: 3),
            GridPoint(x: 8, y: 2),
            GridPoint(x: 7, y: 2),
            GridPoint(x: 6, y: 2),
            GridPoint(x: 5, y: 2),
            GridPoint(x: 4, y: 2),
            GridPoint(x: 3, y: 2),
            GridPoint(x: 2, y: 2),
            GridPoint(x: 1, y: 2),
            GridPoint(x: 0, y: 2),
            GridPoint(x: 0, y: 3),
            GridPoint(x: 0, y: 4)
        ] {
            playBasicMove(to: destination, in: detourCore)
        }
        XCTAssertEqual(detourCore.progress, .cleared)
        XCTAssertEqual(detourCore.dungeonHP, 3)
    }

    func testTutorialTowerSixthFloorIntroducesWarpAndPatrol() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let sixthFloor = tower.floors[5]
        let mode = sixthFloor.makeGameMode(dungeonID: tower.id)
        let core = makeCore(mode: mode)

        XCTAssertFalse(sixthFloor.warpTilePairs.isEmpty)
        XCTAssertTrue(sixthFloor.enemies.contains { enemy in
            if case .patrol = enemy.behavior { return true }
            return false
        })

        for destination in [
            GridPoint(x: 0, y: 3),
            GridPoint(x: 0, y: 2),
            GridPoint(x: 1, y: 2),
            GridPoint(x: 2, y: 2),
            GridPoint(x: 2, y: 1),
            GridPoint(x: 6, y: 7),
            GridPoint(x: 6, y: 8),
            GridPoint(x: 7, y: 8),
            GridPoint(x: 8, y: 8)
        ] {
            playBasicMove(to: destination, in: core)
        }
        XCTAssertEqual(core.progress, .cleared)
    }




    func testCollapsedBrittleFloorRemainsEnterableWhenRevisitingFloor() {
        let brittlePoint = GridPoint(x: 1, y: 0)
        let runState = DungeonRunState(
            dungeonID: "test-tower",
            currentFloorIndex: 1,
            carriedHP: 3,
            collapsedFloorPointsByFloor: [1: [brittlePoint]]
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            hazards: [.brittleFloor(points: [brittlePoint])],
            allowsBasicOrthogonalMove: true,
            runState: runState
        )
        let core = makeCore(mode: mode, cards: [.rayRight, .straightRight2, .straightLeft2])

        XCTAssertTrue(core.collapsedFloorPoints.contains(brittlePoint))
        XCTAssertTrue(core.board.isTraversable(brittlePoint))
        XCTAssertTrue(core.availableBasicOrthogonalMoves().contains { $0.destination == brittlePoint })
        XCTAssertTrue(core.availableMoves().contains { $0.path.contains(brittlePoint) })

        playBasicMove(to: brittlePoint, in: core)

        XCTAssertEqual(core.current, brittlePoint)
        XCTAssertEqual(core.dungeonHP, 2)
        XCTAssertEqual(core.dungeonFallEvent?.point, brittlePoint)
        XCTAssertEqual(core.dungeonFallEvent?.sourceFloorIndex, 1)
        XCTAssertEqual(core.dungeonFallEvent?.destinationFloorIndex, 0)
    }

    func testCollapsedBrittleFloorPiercesWatcherSightButStillBlocksEnemyMovement() {
        let holePoint = GridPoint(x: 1, y: 2)
        let watcher = EnemyDefinition(
            id: "watcher",
            name: "見張り",
            position: GridPoint(x: 1, y: 1),
            behavior: .watcher(direction: MoveVector(dx: 0, dy: 1), range: 3)
        )
        let chaser = EnemyDefinition(
            id: "chaser",
            name: "追跡兵",
            position: GridPoint(x: 2, y: 2),
            behavior: .chaser
        )
        let runState = DungeonRunState(
            dungeonID: "test-tower",
            currentFloorIndex: 1,
            carriedHP: 3,
            collapsedFloorPointsByFloor: [1: [holePoint]]
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 2),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            enemies: [watcher, chaser],
            hazards: [.brittleFloor(points: [holePoint])],
            allowsBasicOrthogonalMove: true,
            runState: runState
        )
        let core = makeCore(mode: mode)

        XCTAssertTrue(core.enemyDangerPoints.contains(holePoint))
        XCTAssertTrue(core.enemyDangerPoints.contains(GridPoint(x: 1, y: 3)))
        XCTAssertFalse(core.enemyChaserMovementPreviews.contains { $0.next == holePoint })
    }


    func testDungeonRunStateFallsFromNinthFloorToEighthFloor() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let runState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 8,
            carriedHP: 2,
            totalMoveCount: 12,
            clearedFloorCount: 8,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .rayRight, rewardUses: 1)]
        )
        let crackedPoint = GridPoint(x: 3, y: 2)
        let fallen = runState.fallenToPreviousFloor(
            carryoverHP: 1,
            currentFloorMoveCount: 4,
            currentInventoryEntries: runState.rewardInventoryEntries,
            landingPoint: crackedPoint,
            currentFloorCrackedPoints: [],
            currentFloorCollapsedPoints: [crackedPoint]
        )

        XCTAssertTrue(tower.canAdvanceWithinRun(afterFloorIndex: 9))
        XCTAssertEqual(fallen.currentFloorIndex, 7)
        XCTAssertEqual(fallen.floorNumber, 8)
        XCTAssertEqual(fallen.carriedHP, 1)
        XCTAssertEqual(fallen.totalMoveCount, 16)
        XCTAssertEqual(fallen.clearedFloorCount, 8)
        XCTAssertEqual(fallen.pendingFallLandingPoint, crackedPoint)
        XCTAssertEqual(fallen.collapsedFloorPoints(for: 8), [crackedPoint])
        XCTAssertNotNil(tower.resolvedFloor(at: fallen.currentFloorIndex, runState: fallen))
    }

    func testFallingToClearedFloorRestoresBoardConsumptionButKeepsCurrentRunResources() throws {
        let landingPoint = GridPoint(x: 1, y: 1)
        let keyPoint = GridPoint(x: 1, y: 0)
        let cardPickup = DungeonCardPickupDefinition(
            id: "cleared-floor-card",
            point: GridPoint(x: 2, y: 1),
            card: .straightRight2
        )
        let relicPickup = DungeonRelicPickupDefinition(
            id: "cleared-floor-relic",
            point: GridPoint(x: 3, y: 1),
            candidateRelics: [.glowingHeart]
        )
        let healingPoint = GridPoint(x: 1, y: 2)
        let enemy = EnemyDefinition(
            id: "cleared-floor-patrol",
            name: "巡回兵",
            position: GridPoint(x: 4, y: 1),
            behavior: .patrol(path: [GridPoint(x: 4, y: 1), GridPoint(x: 4, y: 2)])
        )
        var restoredEnemyState = EnemyState(definition: enemy)
        restoredEnemyState.position = GridPoint(x: 4, y: 2)
        restoredEnemyState.patrolIndex = 1
        let clearedState = DungeonClearedFloorState(
            visitedPoints: [GridPoint(x: 0, y: 0), keyPoint, cardPickup.point, relicPickup.point, healingPoint, landingPoint],
            crackedFloorPoints: [],
            collapsedFloorPoints: [],
            consumedHealingTilePoints: [healingPoint],
            collectedDungeonCardPickupIDs: [cardPickup.id],
            collectedDungeonSpecialPickupIDs: ["cleared-floor-hand-expansion"],
            collectedDungeonRelicPickupIDs: [relicPickup.id],
            enemyStates: [restoredEnemyState],
            isDungeonExitUnlocked: true
        )
        let runState = DungeonRunState(
            dungeonID: "test-tower",
            currentFloorIndex: 0,
            carriedHP: 2,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .rayRight, rewardUses: 1)],
            clearedFloorStatesByFloor: [0: clearedState],
            pendingFallLandingPoint: landingPoint
        )
        let mode = makeDungeonMode(
            spawn: landingPoint,
            exit: GridPoint(x: 4, y: 4),
            hp: 2,
            turnLimit: 12,
            enemies: [enemy],
            hazards: [.healingTile(points: [healingPoint], amount: 1)],
            exitLock: DungeonExitLock(unlockPoint: keyPoint),
            cardAcquisitionMode: .inventoryOnly,
            cardPickups: [cardPickup],
            relicPickups: [relicPickup],
            runState: runState
        )
        let core = makeCore(mode: mode)

        XCTAssertEqual(core.current, landingPoint)
        XCTAssertEqual(core.dungeonHP, 2)
        XCTAssertEqual(core.dungeonInventoryEntries, [DungeonInventoryEntry(card: .rayRight, rewardUses: 1)])
        XCTAssertTrue(core.dungeonKeyPoints.isEmpty)
        XCTAssertFalse(core.activeDungeonCardPickups.contains { $0.id == cardPickup.id })
        XCTAssertFalse(core.activeDungeonRelicPickups.contains { $0.id == relicPickup.id })
        XCTAssertEqual(core.consumedHealingTilePoints, [healingPoint])
        XCTAssertFalse(core.healingTilePoints.contains(healingPoint))
        XCTAssertEqual(core.enemyStates, [restoredEnemyState])
    }

    func testClearedFloorRewardsOnlyAllowPreviouslyUnselectedOffersAfterFallReturn() {
        let firstOffers: [DungeonRewardOffer] = [
            .playable(.move(.rayRight)),
            .playable(.support(.barrierSpell)),
            .relic(.glowingHeart)
        ]
        let runState = DungeonRunState(
            dungeonID: "test-tower",
            currentFloorIndex: 0,
            carriedHP: 3
        )
        let advanced = runState.advancedToNextFloor(
            carryoverHP: 3,
            currentFloorMoveCount: 2,
            rewardSelection: .add(.rayRight),
            currentRewardOffers: firstOffers
        )
        let fallen = advanced.fallenToPreviousFloor(
            carryoverHP: 2,
            currentFloorMoveCount: 1,
            currentInventoryEntries: advanced.rewardInventoryEntries,
            landingPoint: GridPoint(x: 1, y: 1),
            currentFloorCrackedPoints: [],
            currentFloorCollapsedPoints: []
        )
        let stateAfterFirstClear = fallen.clearedFloorState(for: 0)
        let unselectedOffers = stateAfterFirstClear?.rewardOffers.filter {
            stateAfterFirstClear?.selectedRewardOffers.contains($0) == false
        }

        XCTAssertEqual(stateAfterFirstClear?.rewardOffers, firstOffers)
        XCTAssertEqual(stateAfterFirstClear?.selectedRewardOffers, [.playable(.move(.rayRight))])
        XCTAssertEqual(unselectedOffers, [.playable(.support(.barrierSpell)), .relic(.glowingHeart)])

        let advancedAgain = fallen.advancedToNextFloor(
            carryoverHP: 2,
            currentFloorMoveCount: 3,
            rewardSelection: .addSupport(.barrierSpell),
            currentRewardOffers: unselectedOffers ?? []
        )
        let stateAfterSecondClear = advancedAgain.clearedFloorState(for: 0)

        XCTAssertEqual(stateAfterSecondClear?.rewardOffers, firstOffers)
        XCTAssertEqual(
            stateAfterSecondClear?.selectedRewardOffers,
            [.playable(.move(.rayRight)), .playable(.support(.barrierSpell))]
        )
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
        let expectedDestination = GridPoint(
            x: tower.floors[1].spawnPoint.x + 2,
            y: tower.floors[1].spawnPoint.y
        )
        XCTAssertTrue(core.availableMoves().contains { $0.moveCard == .straightRight2 && $0.destination == expectedDestination })
        XCTAssertEqual(core.handStacks.first { $0.representativeMove == .straightRight2 }?.count, 3)
    }

    func testBasicOrthogonalMoveIsAvailableOnlyWhenDungeonRuleAllowsIt() {
        let enabledMode = makeDungeonMode(
            spawn: GridPoint(x: 2, y: 2),
            exit: GridPoint(x: 4, y: 4),
            turnLimit: 8
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
            turnLimit: 8,
            allowsBasicOrthogonalMove: false
        )
        let disabledCore = makeCore(
            mode: disabledMode,
            cards: [.straightRight2, .straightLeft2, .diagonalUpRight2, .diagonalDownLeft2, .rayUp]
        )

        XCTAssertTrue(disabledCore.availableBasicOrthogonalMoves().isEmpty)

    }

    func testKnightMovementStyleUsesKnightJumpAsBasicMove() {
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 2, y: 2),
            exit: GridPoint(x: 4, y: 4),
            turnLimit: 8,
            allowsBasicOrthogonalMove: true,
            movementStyle: .knight
        )
        let core = makeCore(mode: mode)

        XCTAssertEqual(Set(core.availableBasicOrthogonalMoves().map(\.destination)), [
            GridPoint(x: 4, y: 3),
            GridPoint(x: 3, y: 4),
            GridPoint(x: 1, y: 4),
            GridPoint(x: 0, y: 3),
            GridPoint(x: 0, y: 1),
            GridPoint(x: 1, y: 0),
            GridPoint(x: 3, y: 0),
            GridPoint(x: 4, y: 1)
        ])
    }

    func testKnightBasicMoveProcessesOnlyLandingPoint() {
        let skippedTrap = GridPoint(x: 3, y: 2)
        let landing = GridPoint(x: 4, y: 3)
        let landingPickup = DungeonCardPickupDefinition(
            id: "landing-pickup",
            point: landing,
            card: .rayLeft
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 2, y: 2),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            hazards: [.damageTrap(points: [skippedTrap], damage: 1)],
            cardAcquisitionMode: .inventoryOnly,
            cardPickups: [landingPickup],
            movementStyle: .knight
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: landing, in: core)

        XCTAssertEqual(core.dungeonHP, 3)
        XCTAssertFalse(core.board.isVisited(skippedTrap))
        XCTAssertTrue(core.board.isVisited(landing))
        XCTAssertTrue(core.collectedDungeonCardPickupIDs.contains(landingPickup.id))
    }

    func testGrowthTowerPoolsReplaceKnightCardsForKnightMovementStyleOnly() {
        let standardCards = moveCards(
            in: DungeonWeightedRewardPools.entries(
                floorIndex: 24,
                context: .clearReward,
                movementStyle: .orthogonal
            )
        )
        let knightCards = moveCards(
            in: DungeonWeightedRewardPools.entries(
                floorIndex: 24,
                context: .clearReward,
                movementStyle: .knight
            )
        )

        XCTAssertTrue(standardCards.contains(.knightRightwardChoice))
        XCTAssertFalse(standardCards.contains { MoveCard.orthogonalStepCards.contains($0) })
        XCTAssertFalse(knightCards.contains { knightReplacementSourceCards.contains($0) })
        XCTAssertTrue(knightCards.contains { MoveCard.orthogonalStepCards.contains($0) })
    }

    func testBasicOrthogonalMoveConsumesTurnButNoCard() {
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            turnLimit: 3
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

    func testBasicOrthogonalMoveCanClearExitAndTriggerFatigueRules() {
        let clearMode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 0, y: 1),
            turnLimit: 1
        )
        let clearCore = makeCore(mode: clearMode, cards: [.straightRight2, .straightLeft2, .rayRight])
        playBasicMove(to: GridPoint(x: 0, y: 1), in: clearCore)
        XCTAssertEqual(clearCore.progress, .cleared)

        let fatigueMode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            turnLimit: 1
        )
        let fatigueCore = makeCore(mode: fatigueMode, cards: [.straightRight2, .straightLeft2, .rayRight])
        playBasicMove(to: GridPoint(x: 0, y: 1), in: fatigueCore)
        XCTAssertEqual(fatigueCore.progress, .playing)
        XCTAssertEqual(fatigueCore.remainingDungeonTurns, 0)

        playBasicMove(to: GridPoint(x: 0, y: 2), in: fatigueCore)
        XCTAssertEqual(fatigueCore.progress, .playing)
        XCTAssertEqual(fatigueCore.dungeonHP, 2)
    }

    func testBasicOrthogonalMoveCollapsesBrittleFloorWithoutImmediateDamage() {
        let brittlePoint = GridPoint(x: 0, y: 1)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            hazards: [.brittleFloor(points: [brittlePoint])]
        )
        let core = makeCore(mode: mode, cards: [.straightRight2, .straightLeft2, .rayRight])

        playBasicMove(to: brittlePoint, in: core)

        XCTAssertTrue(core.collapsedFloorPoints.contains(brittlePoint))
        XCTAssertEqual(core.dungeonHP, 3)
    }

    func testExpandedRelicsAdjustRewardUsesAndTrapRewardWindow() throws {
        let trapPoint = GridPoint(x: 0, y: 1)
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 3,
            relicEntries: [
                DungeonRelicEntry(relicID: .windcutFeather),
                DungeonRelicEntry(relicID: .trapperGloves)
            ],
            curseEntries: [DungeonCurseEntry(curseID: .crackedShoes)]
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            hazards: [.damageTrap(points: [trapPoint], damage: 1)],
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            runState: runState
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: trapPoint, in: core)

        XCTAssertEqual(core.dungeonRelicEntries.first { $0.relicID == .trapperGloves }?.remainingUses, 1)

        let advancedWithRay = runState.advancedToNextFloor(
            carryoverHP: core.dungeonHP,
            currentFloorMoveCount: core.moveCount,
            rewardSelection: .add(.rayRight),
            currentInventoryEntries: core.dungeonInventoryEntries,
            currentRelicEntries: core.dungeonRelicEntries,
            currentCurseEntries: core.dungeonCurseEntries,
            rewardAddUses: 2
        )

        XCTAssertEqual(advancedWithRay.rewardInventoryEntries.first?.rewardUses, 1)
        XCTAssertEqual(advancedWithRay.relicEntries.first { $0.relicID == .trapperGloves }?.remainingUses, 0)

        let advancedWithSupport = runState.advancedToNextFloor(
            carryoverHP: 3,
            currentFloorMoveCount: 1,
            rewardSelection: .addSupport(.barrierSpell),
            currentInventoryEntries: [],
            currentRelicEntries: [DungeonRelicEntry(relicID: .twinPouch)],
            currentCurseEntries: [],
            rewardAddUses: 2,
            supportRewardAddUses: 2
        )

        XCTAssertEqual(advancedWithSupport.rewardInventoryEntries.first?.rewardUses, 2)
    }

    func testExpandedRelicsAndCursesAdjustEnemyFallAndFirstAction() {
        let watcher = EnemyDefinition(
            id: "watcher",
            name: "見張り",
            position: GridPoint(x: 1, y: 1),
            behavior: .watcher(direction: MoveVector(dx: -1, dy: 0), range: 2)
        )
        let enemyRunState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 3,
            relicEntries: [DungeonRelicEntry(relicID: .guardianIncense)]
        )
        let enemyMode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            enemies: [watcher],
            allowsBasicOrthogonalMove: true,
            runState: enemyRunState
        )
        let enemyCore = makeCore(mode: enemyMode)

        playBasicMove(to: GridPoint(x: 0, y: 1), in: enemyCore)

        XCTAssertEqual(enemyCore.dungeonHP, 3)
        XCTAssertEqual(enemyCore.dungeonRelicEntries.first { $0.relicID == .guardianIncense }?.remainingUses, 0)

        let bellRunState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 3,
            curseEntries: [DungeonCurseEntry(curseID: .heavyBell)]
        )
        let bellMode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            allowsBasicOrthogonalMove: true,
            runState: bellRunState
        )
        let bellCore = makeCore(mode: bellMode)

        playBasicMove(to: GridPoint(x: 0, y: 1), in: bellCore)

        XCTAssertEqual(bellCore.moveCount, 2)
    }

    func testCurseDefinitionsCoverExpandedRunCurses() {
        XCTAssertEqual(DungeonCurseID.allCases.count, 45)
        XCTAssertEqual(DungeonCurseID.newAcquisitionCases.count, 15)
        XCTAssertEqual(Set(DungeonCurseID.newAcquisitionCases).count, 15)
        XCTAssertTrue(DungeonCurseID.newAcquisitionCases.allSatisfy { DungeonCurseID.allCases.contains($0) })
        XCTAssertFalse(DungeonCurseID.newAcquisitionCases.contains(.rustyChain))
        XCTAssertFalse(DungeonCurseID.newAcquisitionCases.contains(.trapMagnet))
        XCTAssertFalse(DungeonCurseID.newAcquisitionCases.contains(.poisonVial))
        XCTAssertFalse(DungeonCurseID.newAcquisitionCases.contains(.supportOath))
        XCTAssertFalse(DungeonCurseID.newAcquisitionCases.contains(.cursedCrown))
        XCTAssertFalse(DungeonCurseID.newAcquisitionCases.contains(.oilSoakedBoots))
        XCTAssertFalse(DungeonCurseID.newAcquisitionCases.contains(.obsidianHeart))
        XCTAssertFalse(DungeonCurseID.newAcquisitionCases.contains(.greedyBag))
        XCTAssertFalse(DungeonCurseID.newAcquisitionCases.contains(.bottomlessPack))
        XCTAssertFalse(DungeonCurseID.newAcquisitionCases.contains(.relicHunterBrand))
        XCTAssertFalse(DungeonCurseID.newAcquisitionCases.contains(.ashHeart))
        XCTAssertTrue(DungeonCurseID.newAcquisitionCases.contains(.chaserScent))
        XCTAssertTrue(DungeonCurseID.newAcquisitionCases.contains(.warpedHourglass))
        XCTAssertTrue(DungeonCurseID.newAcquisitionCases.contains(.tinkersToolbox))
        XCTAssertTrue(DungeonCurseID.newAcquisitionCases.contains(.contractCodex))
        XCTAssertTrue(DungeonCurseID.newAcquisitionCases.contains(.royalIou))
        XCTAssertTrue(DungeonCurseID.newAcquisitionCases.contains(.quartermasterBell))
        XCTAssertTrue(DungeonCurseID.newAcquisitionCases.contains(.sleepingWarDrum))
        XCTAssertTrue(DungeonCurseID.newAcquisitionCases.contains(.swarmcallingTalisman))
        XCTAssertTrue(DungeonCurseID.newAcquisitionCases.contains(.gildedSeal))
        XCTAssertEqual(
            DungeonRelicPickupDefinition(id: "default", point: GridPoint(x: 0, y: 0)).candidateCurses,
            DungeonCurseID.newAcquisitionCases
        )
        XCTAssertTrue(DungeonCurseID.allCases.allSatisfy { !$0.displayName.isEmpty })
        XCTAssertTrue(DungeonCurseID.allCases.allSatisfy { !$0.upsideDescription.isEmpty })
        XCTAssertTrue(DungeonCurseID.allCases.allSatisfy { !$0.downsideDescription.isEmpty })
        XCTAssertTrue(DungeonCurseID.allCases.allSatisfy { !$0.releaseDescription.isEmpty })
        XCTAssertTrue(DungeonCurseID.allCases.allSatisfy { !$0.symbolName.isEmpty })
        XCTAssertTrue(DungeonCurseID.allCases.allSatisfy { $0.displayKind == .persistent || $0.displayKind == .temporary })
        XCTAssertFalse(DungeonCurseID.swarmcallingTalisman.upsideDescription.contains("5ターン"))
        XCTAssertFalse(DungeonCurseID.swarmcallingTalisman.downsideDescription.contains("成長塔"))
    }

    func testQuartermasterBellRefillsAtFloorStartAndPenalizesNoKillClear() {
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 3,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .straightRight2, rewardUses: 1)],
            curseEntries: [DungeonCurseEntry(curseID: .quartermasterBell)],
            dungeonInventoryKindLimit: 5
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 20,
            cardAcquisitionMode: .inventoryOnly,
            runState: runState
        )
        let core = makeCore(mode: mode)

        XCTAssertEqual(core.dungeonInventoryEntries.filter(\.hasUsesRemaining).count, 5)
        XCTAssertEqual(core.moveCount, 0)

        let penalized = runState.advancedToNextFloor(
            carryoverHP: 3,
            currentFloorMoveCount: 1,
            startedFloorWithEnemies: true,
            currentFloorDefeatedEnemyCount: 0
        )
        let defeatedOne = runState.advancedToNextFloor(
            carryoverHP: 3,
            currentFloorMoveCount: 1,
            startedFloorWithEnemies: true,
            currentFloorDefeatedEnemyCount: 1
        )
        let emptyFloor = runState.advancedToNextFloor(
            carryoverHP: 3,
            currentFloorMoveCount: 1,
            startedFloorWithEnemies: false,
            currentFloorDefeatedEnemyCount: 0
        )

        XCTAssertEqual(penalized.carriedHP, 2)
        XCTAssertEqual(defeatedOne.carriedHP, 3)
        XCTAssertEqual(emptyFloor.carriedHP, 3)
    }

    func testSleepingWarDrumSkipsEveryOtherEnemyTurnAndTriplesEnemyDamage() {
        let chaser = EnemyDefinition(
            id: "chaser",
            name: "追跡兵",
            position: GridPoint(x: 4, y: 4),
            behavior: .chaser
        )
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 5,
            curseEntries: [DungeonCurseEntry(curseID: .sleepingWarDrum)]
        )
        let core = makeCore(
            mode: makeDungeonMode(
                spawn: GridPoint(x: 0, y: 0),
                exit: GridPoint(x: 4, y: 0),
                hp: 5,
                turnLimit: 20,
                enemies: [chaser],
                runState: runState
            )
        )

        playBasicMove(to: GridPoint(x: 0, y: 1), in: core)
        XCTAssertEqual(core.enemyStates.first?.position, GridPoint(x: 4, y: 4))
        playBasicMove(to: GridPoint(x: 0, y: 2), in: core)
        XCTAssertNotEqual(core.enemyStates.first?.position, GridPoint(x: 4, y: 4))

        let watcher = EnemyDefinition(
            id: "watcher",
            name: "見張り",
            position: GridPoint(x: 1, y: 0),
            behavior: .watcher(direction: MoveVector(dx: 0, dy: 1), range: 3)
        )
        let damageCore = makeCore(
            mode: makeDungeonMode(
                spawn: GridPoint(x: 0, y: 0),
                exit: GridPoint(x: 4, y: 4),
                hp: 5,
                turnLimit: 20,
                enemies: [watcher],
                runState: runState
            )
        )
        playBasicMove(to: GridPoint(x: 0, y: 1), in: damageCore)
        playBasicMove(to: GridPoint(x: 1, y: 1), in: damageCore)
        XCTAssertEqual(damageCore.dungeonHP, 2)

        let reducedCore = makeCore(
            mode: makeDungeonMode(
                spawn: GridPoint(x: 0, y: 0),
                exit: GridPoint(x: 4, y: 4),
                hp: 5,
                turnLimit: 20,
                enemies: [watcher],
                runState: DungeonRunState(
                    dungeonID: "growth-tower",
                    carriedHP: 5,
                    relicEntries: [DungeonRelicEntry(relicID: .guardianCloak)],
                    curseEntries: [DungeonCurseEntry(curseID: .sleepingWarDrum)]
                )
            )
        )
        playBasicMove(to: GridPoint(x: 0, y: 1), in: reducedCore)
        playBasicMove(to: GridPoint(x: 1, y: 1), in: reducedCore)
        XCTAssertEqual(reducedCore.dungeonHP, 3)
    }

    func testSwarmcallingTalismanAddsBarrierAndDoublesResolvedEnemies() throws {
        let dungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let seed: UInt64 = 8128
        let baseRunState = DungeonRunState(dungeonID: dungeon.id, carriedHP: 3, cardVariationSeed: seed)
        let swarmRunState = DungeonRunState(
            dungeonID: dungeon.id,
            carriedHP: 3,
            curseEntries: [DungeonCurseEntry(curseID: .swarmcallingTalisman)],
            cardVariationSeed: seed
        )
        let floorIndex = try XCTUnwrap((0..<dungeon.floors.count).first { index in
            guard let floor = dungeon.resolvedFloor(at: index, runState: baseRunState) else { return false }
            return !floor.enemies.isEmpty && floor.enemies.count <= 4
        })
        let baseFloor = try XCTUnwrap(dungeon.resolvedFloor(at: floorIndex, runState: baseRunState))
        let swarmFloor = try XCTUnwrap(dungeon.resolvedFloor(at: floorIndex, runState: swarmRunState))

        XCTAssertEqual(swarmFloor.enemies.count, baseFloor.enemies.count * 2)
        XCTAssertEqual(Set(swarmFloor.enemies.map(\.position)).count, swarmFloor.enemies.count)
        XCTAssertFalse(swarmFloor.enemies.contains { $0.position == swarmFloor.spawnPoint || $0.position == swarmFloor.exitPoint })

        let core = makeCore(
            mode: makeDungeonMode(
                spawn: GridPoint(x: 0, y: 0),
                exit: GridPoint(x: 4, y: 4),
                hp: 3,
                turnLimit: 20,
                runState: swarmRunState
            )
        )
        XCTAssertEqual(core.damageBarrierTurnsRemaining, 3)
    }

    func testSwarmcallingTalismanDoublesRoguelikeTowerEnemies() throws {
        let dungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))
        let seed: UInt64 = 24680
        let floorIndex = 10
        let baseRunState = DungeonRunState(
            dungeonID: dungeon.id,
            carriedHP: 3,
            rogueTowerSeed: seed
        )
        let swarmRunState = DungeonRunState(
            dungeonID: dungeon.id,
            carriedHP: 3,
            curseEntries: [DungeonCurseEntry(curseID: .swarmcallingTalisman)],
            rogueTowerSeed: seed
        )
        let baseFloor = try XCTUnwrap(dungeon.resolvedFloor(at: floorIndex, runState: baseRunState))
        let swarmFloor = try XCTUnwrap(dungeon.resolvedFloor(at: floorIndex, runState: swarmRunState))

        XCTAssertFalse(baseFloor.enemies.isEmpty)
        XCTAssertGreaterThan(swarmFloor.enemies.count, baseFloor.enemies.count)
        XCTAssertLessThanOrEqual(swarmFloor.enemies.count, baseFloor.enemies.count * 2)
        XCTAssertEqual(Set(swarmFloor.enemies.map(\.position)).count, swarmFloor.enemies.count)
        XCTAssertFalse(swarmFloor.enemies.contains { $0.position == swarmFloor.spawnPoint || $0.position == swarmFloor.exitPoint })
    }

    func testGildedSealForcesRareRelicsAndClampsHP() {
        let offers = DungeonWeightedRewardPools.drawUniqueOffers(
            from: [
                DungeonWeightedRewardPoolEntry(item: .relic(.crackedShield), weight: 100),
                DungeonWeightedRewardPoolEntry(item: .relic(.starCup), weight: 1)
            ],
            context: .clearReward,
            count: 1,
            seed: 7,
            floorIndex: 0,
            salt: 11,
            tuning: DungeonRewardDrawTuning(forcesRareOrBetterRelics: true)
        )
        XCTAssertEqual(offers.first?.relic, .starCup)

        let pickupPoint = GridPoint(x: 1, y: 0)
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 5,
            curseEntries: [DungeonCurseEntry(curseID: .gildedSeal)]
        )
        let core = makeCore(
            mode: makeDungeonMode(
                spawn: GridPoint(x: 0, y: 0),
                exit: GridPoint(x: 4, y: 4),
                hp: 5,
                turnLimit: 20,
                relicPickups: [
                    DungeonRelicPickupDefinition(
                        id: "seal-chest",
                        point: pickupPoint,
                        kind: .safe,
                        candidateRelics: [.crackedShield, .starCup]
                    )
                ],
                runState: runState
            )
        )

        XCTAssertEqual(core.dungeonHP, 2)
        playBasicMove(to: pickupPoint, in: core)
        XCTAssertTrue(core.dungeonRelicEntries.contains { $0.relicID == .starCup })

        let healingCore = makeCore(
            mode: makeDungeonMode(
                spawn: GridPoint(x: 0, y: 0),
                exit: GridPoint(x: 4, y: 4),
                hp: 1,
                turnLimit: 20,
                hazards: [.healingTile(points: [pickupPoint], amount: 5)],
                runState: runState
            )
        )
        playBasicMove(to: pickupPoint, in: healingCore)
        XCTAssertEqual(healingCore.dungeonHP, 2)

        let next = runState.advancedToNextFloor(
            carryoverHP: 5,
            currentFloorMoveCount: 1
        )
        XCTAssertEqual(next.carriedHP, 2)
    }

    func testPloverContractRemovesBasicMoveAndExpandsHandLimitToTen() {
        let cards = Array(MoveCard.allCases.prefix(9)).map {
            DungeonInventoryEntry(card: $0, rewardUses: 1)
        }
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 3,
            rewardInventoryEntries: cards,
            curseEntries: [DungeonCurseEntry(curseID: .ploverContract)],
            dungeonInventoryKindLimit: 9
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 2, y: 2),
            exit: GridPoint(x: 4, y: 4),
            turnLimit: 20,
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            runState: runState
        )
        let core = makeCore(mode: mode)

        XCTAssertTrue(core.availableBasicOrthogonalMoves().isEmpty)
        XCTAssertEqual(core.dungeonInventoryKindLimit, 10)
    }

    func testEmptyHandTriggersAutomaticStaggerMove() {
        let trapPoint = GridPoint(x: 2, y: 0)
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 3,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .straightRight2, rewardUses: 1)],
            curseEntries: [DungeonCurseEntry(curseID: .ploverContract)],
            dungeonInventoryKindLimit: 5
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            turnLimit: 20,
            tileEffectOverrides: [trapPoint: .discardAllHands],
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            runState: runState
        )
        let core = makeCore(mode: mode)

        playMove(to: trapPoint, in: core)

        XCTAssertEqual(core.dungeonInventoryEntries.filter(\.hasUsesRemaining).count, 0)
        XCTAssertGreaterThan(core.moveCount, 1)
        XCTAssertNotEqual(core.current, trapPoint)
    }

    func testStaggerTrapForcesTwoMovesAfterEnemyTurns() {
        let trapPoint = GridPoint(x: 2, y: 3)
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 3,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .straightRight2, rewardUses: 1)],
            dungeonInventoryKindLimit: 5
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 2, y: 2),
            exit: GridPoint(x: 4, y: 4),
            turnLimit: 20,
            tileEffectOverrides: [trapPoint: .staggerTrap],
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            runState: runState
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: trapPoint, in: core)

        XCTAssertEqual(core.staggerForcedMovesRemaining, 0)
        XCTAssertEqual(core.moveCount, 3)
        XCTAssertNotEqual(core.current, trapPoint)
    }

    func testBuildChangingCursesAdjustPickupRewardUsesAndTurnLimit() {
        let pickupPoint = GridPoint(x: 1, y: 0)
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 3,
            curseEntries: [
                DungeonCurseEntry(curseID: .contractCodex),
                DungeonCurseEntry(curseID: .bottomlessPack),
                DungeonCurseEntry(curseID: .relicHunterBrand),
                DungeonCurseEntry(curseID: .supportOath)
            ]
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 10,
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            cardPickups: [
                DungeonCardPickupDefinition(
                    id: "pickup",
                    point: pickupPoint,
                    card: .straightRight2,
                    uses: 1
                )
            ],
            runState: runState
        )
        let core = makeCore(mode: mode)

        XCTAssertEqual(core.effectiveDungeonTurnLimit, 5)
        playBasicMove(to: pickupPoint, in: core)
        XCTAssertEqual(core.dungeonInventoryEntries.first { $0.moveCard == .straightRight2 }?.totalUses, 7)

        let curseEntries = [
            DungeonCurseEntry(curseID: .contractCodex),
            DungeonCurseEntry(curseID: .royalIou),
            DungeonCurseEntry(curseID: .relicHunterBrand),
            DungeonCurseEntry(curseID: .supportOath)
        ]
        XCTAssertEqual(
            DungeonRunState.adjustedMoveRewardBaseUses(2, relicEntries: [], curseEntries: curseEntries),
            5
        )
        XCTAssertEqual(
            DungeonRunState.adjustedRewardAddUses(
                2,
                for: .straightRight2,
                relicEntries: [],
                curseEntries: [DungeonCurseEntry(curseID: .relicHunterBrand)]
            ),
            1
        )
        XCTAssertEqual(
            DungeonRunState.adjustedSupportRewardUses(1, relicEntries: [], curseEntries: curseEntries),
            8
        )
    }

    func testChaserScentTriplesFloorPickupsOnlyOnChaserFloors() throws {
        let dungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let seed: UInt64 = 7281
        let baseRunState = DungeonRunState(
            dungeonID: dungeon.id,
            carriedHP: 3,
            cardVariationSeed: seed
        )
        let curseRunState = DungeonRunState(
            dungeonID: dungeon.id,
            carriedHP: 3,
            curseEntries: [DungeonCurseEntry(curseID: .chaserScent)],
            cardVariationSeed: seed
        )
        let chaserFloorIndex = try XCTUnwrap((0..<dungeon.floors.count).first { index in
            guard let floor = dungeon.resolvedFloor(at: index, runState: baseRunState) else { return false }
            return !floor.cardPickups.isEmpty && floor.enemies.contains { enemy in
                if case .chaser = enemy.behavior { return true }
                return false
            }
        })
        let noChaserFloorIndex = try XCTUnwrap((0..<dungeon.floors.count).first { index in
            guard let floor = dungeon.resolvedFloor(at: index, runState: baseRunState) else { return false }
            return !floor.cardPickups.isEmpty && !floor.enemies.contains { enemy in
                if case .chaser = enemy.behavior { return true }
                return false
            }
        })
        let baseChaserFloor = try XCTUnwrap(dungeon.resolvedFloor(at: chaserFloorIndex, runState: baseRunState))
        let curseChaserFloor = try XCTUnwrap(dungeon.resolvedFloor(at: chaserFloorIndex, runState: curseRunState))
        let baseNoChaserFloor = try XCTUnwrap(dungeon.resolvedFloor(at: noChaserFloorIndex, runState: baseRunState))
        let curseNoChaserFloor = try XCTUnwrap(dungeon.resolvedFloor(at: noChaserFloorIndex, runState: curseRunState))

        XCTAssertEqual(curseChaserFloor.cardPickups.count, baseChaserFloor.cardPickups.count * 3)
        XCTAssertEqual(curseNoChaserFloor.cardPickups.count, baseNoChaserFloor.cardPickups.count)
    }

    func testWarpedHourglassPenalizesSlowClearHPWithoutRewardUseBonus() {
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 4,
            curseEntries: [DungeonCurseEntry(curseID: .warpedHourglass)]
        )

        let fastClear = runState.advancedToNextFloor(
            carryoverHP: 4,
            currentFloorMoveCount: 4,
            rewardSelection: .add(.straightRight2),
            completedWithinHalfTurnLimit: true
        )
        let slowClear = runState.advancedToNextFloor(
            carryoverHP: 4,
            currentFloorMoveCount: 7,
            rewardSelection: .add(.straightRight2),
            completedWithinHalfTurnLimit: false
        )

        XCTAssertEqual(fastClear.rewardInventoryEntries.first { $0.moveCard == .straightRight2 }?.totalUses, 2)
        XCTAssertEqual(fastClear.carriedHP, 4)
        XCTAssertEqual(slowClear.rewardInventoryEntries.first { $0.moveCard == .straightRight2 }?.totalUses, 2)
        XCTAssertEqual(slowClear.carriedHP, 3)
    }

    func testBuildChangingCursesAdjustNextFloorHP() {
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 2,
            curseEntries: [
                DungeonCurseEntry(curseID: .royalIou),
                DungeonCurseEntry(curseID: .ashHeart)
            ]
        )

        let selectedReward = runState.advancedToNextFloor(
            carryoverHP: 2,
            currentFloorMoveCount: 1,
            rewardSelection: .add(.straightRight2)
        )
        let noReward = runState.advancedToNextFloor(
            carryoverHP: 2,
            currentFloorMoveCount: 1
        )

        XCTAssertEqual(selectedReward.carriedHP, 3)
        XCTAssertEqual(noReward.carriedHP, 4)
    }

    func testFloorStartHeartRelicsAndAshHeartStackFloorStartHealing() {
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 3,
            relicEntries: [
                DungeonRelicEntry(relicID: .starCup, floorStartCharge: 1),
                DungeonRelicEntry(relicID: .immortalHeart)
            ],
            curseEntries: [
                DungeonCurseEntry(curseID: .ashHeart)
            ]
        )

        let nextFloorState = runState.advancedToNextFloor(
            carryoverHP: 3,
            currentFloorMoveCount: 1
        )

        XCTAssertEqual(nextFloorState.carriedHP, 7)
    }

    func testFloorStartRecoveryRelicsCursesAndRationStackWithExistingOrder() {
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 2,
            relicEntries: [
                DungeonRelicEntry(relicID: .starCup, floorStartCharge: 1),
                DungeonRelicEntry(relicID: .travelerCanteen, remainingUses: 1),
                DungeonRelicEntry(relicID: .travelerRation)
            ],
            curseEntries: [
                DungeonCurseEntry(curseID: .obsidianHeart),
                DungeonCurseEntry(curseID: .ashHeart)
            ]
        )

        let nextFloorState = runState.advancedToNextFloor(
            carryoverHP: 2,
            currentFloorMoveCount: 1
        )

        XCTAssertEqual(nextFloorState.carriedHP, 5)
        XCTAssertEqual(nextFloorState.relicEntries.first { $0.relicID == .starCup }?.floorStartCharge, 0)
        XCTAssertNil(nextFloorState.relicEntries.first { $0.relicID == .travelerCanteen })
        XCTAssertTrue(nextFloorState.relicEntries.contains { $0.relicID == .travelerRation })
    }

    func testSurvivalRiskCursesReduceEnemyDamageAndIncreaseFatigueDamage() {
        let watcher = EnemyDefinition(
            id: "watcher",
            name: "見張り",
            position: GridPoint(x: 1, y: 1),
            behavior: .watcher(direction: MoveVector(dx: -1, dy: 0), range: 2)
        )
        let enemyCore = makeCore(
            mode: makeDungeonMode(
                spawn: GridPoint(x: 0, y: 0),
                exit: GridPoint(x: 4, y: 4),
                hp: 4,
                turnLimit: 8,
                enemies: [watcher],
                runState: DungeonRunState(
                    dungeonID: "growth-tower",
                    carriedHP: 4,
                    curseEntries: [DungeonCurseEntry(curseID: .hasteArmor)]
                )
            )
        )
        playBasicMove(to: GridPoint(x: 0, y: 1), in: enemyCore)
        XCTAssertEqual(enemyCore.dungeonHP, 4)

        let fatigueCore = makeCore(
            mode: makeDungeonMode(
                spawn: GridPoint(x: 0, y: 0),
                exit: GridPoint(x: 4, y: 4),
                hp: 5,
                turnLimit: 1,
                runState: DungeonRunState(
                    dungeonID: "growth-tower",
                    carriedHP: 5,
                    curseEntries: [DungeonCurseEntry(curseID: .hasteArmor)]
                )
            )
        )
        playBasicMove(to: GridPoint(x: 0, y: 1), in: fatigueCore)
        playBasicMove(to: GridPoint(x: 0, y: 0), in: fatigueCore)
        XCTAssertEqual(fatigueCore.dungeonHP, 3)
    }

    func testSurvivalRiskCursesReduceHazardDamageAndIncreaseFatigueDamage() {
        let trapPoint = GridPoint(x: 1, y: 0)
        let lavaPoint = GridPoint(x: 2, y: 0)
        let hazardCore = makeCore(
            mode: makeDungeonMode(
                spawn: GridPoint(x: 0, y: 0),
                exit: GridPoint(x: 4, y: 4),
                hp: 5,
                turnLimit: 8,
                hazards: [
                    .damageTrap(points: [trapPoint], damage: 1),
                    .lavaTile(points: [lavaPoint], damage: 1)
                ],
                runState: DungeonRunState(
                    dungeonID: "growth-tower",
                    carriedHP: 5,
                    curseEntries: [DungeonCurseEntry(curseID: .scorchedCloak)]
                )
            )
        )
        playBasicMove(to: trapPoint, in: hazardCore)
        playBasicMove(to: lavaPoint, in: hazardCore)
        XCTAssertEqual(hazardCore.dungeonHP, 4)

        let brittlePoint = GridPoint(x: 0, y: 1)
        let fallCore = makeCore(
            mode: makeDungeonMode(
                spawn: GridPoint(x: 0, y: 0),
                exit: GridPoint(x: 4, y: 4),
                hp: 5,
                turnLimit: 8,
                hazards: [.brittleFloor(points: [brittlePoint])],
                runState: DungeonRunState(
                    dungeonID: "growth-tower",
                    currentFloorIndex: 1,
                    carriedHP: 5,
                    curseEntries: [DungeonCurseEntry(curseID: .scorchedCloak)]
                )
            )
        )
        playBasicMove(to: brittlePoint, in: fallCore)
        XCTAssertEqual(fallCore.dungeonHP, 5)

        let fatigueCore = makeCore(
            mode: makeDungeonMode(
                spawn: GridPoint(x: 0, y: 0),
                exit: GridPoint(x: 4, y: 4),
                hp: 5,
                turnLimit: 1,
                runState: DungeonRunState(
                    dungeonID: "growth-tower",
                    carriedHP: 5,
                    curseEntries: [DungeonCurseEntry(curseID: .scorchedCloak)]
                )
            )
        )
        playBasicMove(to: GridPoint(x: 0, y: 1), in: fatigueCore)
        playBasicMove(to: GridPoint(x: 0, y: 0), in: fatigueCore)
        XCTAssertEqual(fatigueCore.dungeonHP, 3)
    }

    func testLastStandShieldReducesFirstDamagePerFloorAndLowersTurnLimit() {
        let trapPoint = GridPoint(x: 1, y: 0)
        let lavaPoint = GridPoint(x: 2, y: 0)
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 10,
            curseEntries: [DungeonCurseEntry(curseID: .lastStandShield)]
        )
        let core = makeCore(
            mode: makeDungeonMode(
                spawn: GridPoint(x: 0, y: 0),
                exit: GridPoint(x: 4, y: 4),
                hp: 10,
                turnLimit: 10,
                hazards: [
                    .damageTrap(points: [trapPoint], damage: 3),
                    .lavaTile(points: [lavaPoint], damage: 3)
                ],
                runState: runState
            )
        )

        XCTAssertEqual(core.effectiveDungeonTurnLimit, 6)
        playBasicMove(to: trapPoint, in: core)
        XCTAssertEqual(core.dungeonHP, 10)
        XCTAssertEqual(core.dungeonCurseEntries.first { $0.curseID == .lastStandShield }?.remainingUses, 0)

        playBasicMove(to: lavaPoint, in: core)
        XCTAssertEqual(core.dungeonHP, 8)

        let nextFloorState = runState.advancedToNextFloor(
            carryoverHP: core.dungeonHP,
            currentFloorMoveCount: core.moveCount,
            currentCurseEntries: core.dungeonCurseEntries
        )
        XCTAssertEqual(nextFloorState.curseEntries.first { $0.curseID == .lastStandShield }?.remainingUses, 1)
    }

    func testRouteChangingCursesAdjustLavaStateRewardUsesAndFastClearHP() throws {
        let lavaPoint = GridPoint(x: 1, y: 0)
        let lavaMode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 5,
            turnLimit: 8,
            hazards: [.lavaTile(points: [lavaPoint], damage: 1)],
            runState: DungeonRunState(
                dungeonID: "growth-tower",
                carriedHP: 5,
                curseEntries: [DungeonCurseEntry(curseID: .firewalkingTalisman)]
            )
        )
        let lavaCore = makeCore(mode: lavaMode)

        XCTAssertFalse(lavaCore.didStepOnLavaThisFloor)
        playBasicMove(to: lavaPoint, in: lavaCore)
        XCTAssertTrue(lavaCore.didStepOnLavaThisFloor)

        let snapshot = try XCTUnwrap(lavaCore.makeDungeonResumeSnapshot())
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(DungeonRunResumeSnapshot.self, from: data)
        let restoredCore = makeCore(mode: lavaMode)
        XCTAssertTrue(restoredCore.restoreDungeonResumeSnapshot(decoded))
        XCTAssertTrue(restoredCore.didStepOnLavaThisFloor)

        let waitRunState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 5,
            rewardInventoryEntries: [DungeonInventoryEntry(support: .refillEmptySlots, rewardUses: 1)],
            curseEntries: [DungeonCurseEntry(curseID: .firewalkingTalisman)]
        )
        let waitCore = makeCore(
            mode: makeDungeonMode(
                spawn: GridPoint(x: 0, y: 0),
                exit: GridPoint(x: 4, y: 4),
                hp: 5,
                turnLimit: 8,
                hazards: [.lavaTile(points: [GridPoint(x: 0, y: 0)], damage: 1)],
                cardAcquisitionMode: .inventoryOnly,
                runState: waitRunState
            )
        )
        let supportIndex = try XCTUnwrap(waitCore.handStacks.firstIndex { $0.topCard?.supportCard == .refillEmptySlots })
        waitCore.playSupportCard(at: supportIndex)
        XCTAssertEqual(waitCore.dungeonHP, 2)
        XCTAssertFalse(waitCore.didStepOnLavaThisFloor)

        let tinkerState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 3,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .straightRight2, rewardUses: 2)],
            curseEntries: [DungeonCurseEntry(curseID: .tinkersToolbox)]
        )
        let duplicated = tinkerState.advancedToNextFloor(
            carryoverHP: 3,
            currentFloorMoveCount: 1,
            rewardSelection: .add(.straightRight2)
        )
        let added = tinkerState.advancedToNextFloor(
            carryoverHP: 3,
            currentFloorMoveCount: 1,
            rewardSelection: .add(.rayRight)
        )
        XCTAssertEqual(duplicated.rewardInventoryEntries.filter { $0.moveCard == .straightRight2 }.map(\.totalUses).reduce(0, +), 4)
        XCTAssertEqual(added.rewardInventoryEntries.first { $0.moveCard == .rayRight }?.totalUses, 2)
        XCTAssertGreaterThan(
            DungeonWeightedRewardPools.rewardPlayableWeight(
                1,
                playable: .move(.straightRight2),
                tuning: DungeonRewardDrawTuning(preferredPlayables: [.move(.straightRight2)])
            ),
            DungeonWeightedRewardPools.rewardPlayableWeight(
                1,
                playable: .move(.rayRight),
                tuning: DungeonRewardDrawTuning(preferredPlayables: [.move(.straightRight2)])
            )
        )

        let expressState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 3,
            curseEntries: [DungeonCurseEntry(curseID: .expressTicket)]
        )
        XCTAssertEqual(
            expressState.advancedToNextFloor(
                carryoverHP: 3,
                currentFloorMoveCount: 4,
                completedWithinHalfTurnLimit: true
            ).carriedHP,
            6
        )
        XCTAssertEqual(
            expressState.advancedToNextFloor(
                carryoverHP: 3,
                currentFloorMoveCount: 5,
                completedWithinHalfTurnLimit: false
            ).carriedHP,
            3
        )
    }

    func testExpressTicketIncreasesFatigueDamage() {
        let core = makeCore(
            mode: makeDungeonMode(
                spawn: GridPoint(x: 0, y: 0),
                exit: GridPoint(x: 4, y: 4),
                hp: 5,
                turnLimit: 1,
                runState: DungeonRunState(
                    dungeonID: "growth-tower",
                    carriedHP: 5,
                    curseEntries: [DungeonCurseEntry(curseID: .expressTicket)]
                )
            )
        )

        playBasicMove(to: GridPoint(x: 0, y: 1), in: core)
        playBasicMove(to: GridPoint(x: 0, y: 0), in: core)

        XCTAssertEqual(core.dungeonHP, 3)
    }

    func testFlavorRelicsAndCursesAdjustKeyWarpHealingAndRewards() throws {
        let keyPoint = GridPoint(x: 1, y: 0)
        let keyMode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            exitLock: DungeonExitLock(unlockPoint: keyPoint),
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            runState: DungeonRunState(
                dungeonID: "flavor-key-test",
                carriedHP: 3,
                curseEntries: [DungeonCurseEntry(curseID: .upsideDownKey)]
            )
        )
        let keyCore = makeCore(mode: keyMode)

        XCTAssertEqual(keyCore.effectiveDungeonTurnLimit, 8)
        playBasicMove(to: keyPoint, in: keyCore)
        XCTAssertTrue(keyCore.isDungeonExitUnlocked)
        XCTAssertEqual(keyCore.effectiveDungeonTurnLimit, 6)

        let warpSource = GridPoint(x: 2, y: 0)
        let warpDestination = GridPoint(x: 4, y: 4)
        let cursedWarpMode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 0, y: 4),
            hp: 3,
            turnLimit: 8,
            warpTilePairs: ["laughing-warp": [warpSource, warpDestination]],
            cardAcquisitionMode: .inventoryOnly,
            runState: DungeonRunState(
                dungeonID: "flavor-cursed-warp-test",
                carriedHP: 3,
                rewardInventoryEntries: [
                    DungeonInventoryEntry(card: .straightRight2, rewardUses: 1),
                    DungeonInventoryEntry(card: .straightUp2, rewardUses: 1)
                ],
                curseEntries: [DungeonCurseEntry(curseID: .laughingDoor)],
                cardVariationSeed: 7
            )
        )
        let cursedWarpCore = makeCore(mode: cursedWarpMode)

        playMove(to: warpSource, in: cursedWarpCore)

        XCTAssertEqual(cursedWarpCore.current, warpDestination)
        XCTAssertEqual(cursedWarpCore.dungeonInventoryEntries.filter(\.hasUsesRemaining).count, 0)
        XCTAssertEqual(
            Set(cursedWarpCore.handStacks.compactMap(\.representativePlayable)),
            Set(cursedWarpCore.dungeonInventoryEntries.filter(\.hasUsesRemaining).map(\.playable))
        )

        let poisonPoint = GridPoint(x: 1, y: 0)
        let shacklePoint = GridPoint(x: 2, y: 0)
        let healPoint = GridPoint(x: 2, y: 1)
        let healingMode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 10,
            hazards: [.healingTile(points: [healPoint], amount: 1)],
            tileEffectOverrides: [
                poisonPoint: .poisonTrap,
                shacklePoint: .shackleTrap
            ],
            allowsBasicOrthogonalMove: true,
            cardAcquisitionMode: .inventoryOnly,
            runState: DungeonRunState(
                dungeonID: "flavor-heal-test",
                carriedHP: 3,
                relicEntries: [DungeonRelicEntry(relicID: .campfireCoal)],
                curseEntries: [DungeonCurseEntry(curseID: .flickeringCampfire)]
            )
        )
        let healingCore = makeCore(mode: healingMode)

        playBasicMove(to: poisonPoint, in: healingCore)
        playBasicMove(to: shacklePoint, in: healingCore)
        XCTAssertGreaterThan(healingCore.poisonDamageTicksRemaining, 0)
        XCTAssertTrue(healingCore.isShackled)

        playBasicMove(to: healPoint, in: healingCore)

        XCTAssertEqual(healingCore.dungeonHP, 7)
        XCTAssertEqual(healingCore.poisonDamageTicksRemaining, 0)
        XCTAssertFalse(healingCore.isShackled)
        XCTAssertTrue(healingCore.isIlluded)

        let merchantState = DungeonRunState(
            dungeonID: "flavor-reward-test",
            carriedHP: 2,
            relicEntries: [DungeonRelicEntry(relicID: .merchantsScale)],
            curseEntries: [DungeonCurseEntry(curseID: .taxCollector)]
        )
        let relicReward = merchantState.advancedToNextFloor(
            carryoverHP: 2,
            currentFloorMoveCount: 1,
            rewardSelection: .addRelic(.fallAnchor)
        )
        let cardReward = merchantState.advancedToNextFloor(
            carryoverHP: 2,
            currentFloorMoveCount: 1,
            rewardSelection: .add(.straightRight2)
        )

        XCTAssertEqual(relicReward.carriedHP, 2)
        XCTAssertEqual(cardReward.carriedHP, 1)
    }

    func testCurseV11EnemyWeaknessesAddSpecificDamage() throws {
        let watcherCore = makeCore(
            mode: makeDungeonMode(
                spawn: GridPoint(x: 0, y: 0),
                exit: GridPoint(x: 4, y: 4),
                hp: 4,
                turnLimit: 8,
                enemies: [
                    EnemyDefinition(
                        id: "watcher",
                        name: "見張り",
                        position: GridPoint(x: 1, y: 1),
                        behavior: .watcher(direction: MoveVector(dx: -1, dy: 0), range: 2)
                    )
                ],
                runState: DungeonRunState(
                    dungeonID: "growth-tower",
                    carriedHP: 4,
                    curseEntries: [DungeonCurseEntry(curseID: .watchersBrand)]
                )
            )
        )
        playBasicMove(to: GridPoint(x: 0, y: 1), in: watcherCore)
        XCTAssertEqual(watcherCore.dungeonHP, 2)

        let patrolCore = makeCore(
            mode: makeDungeonMode(
                spawn: GridPoint(x: 0, y: 0),
                exit: GridPoint(x: 4, y: 4),
                hp: 4,
                turnLimit: 8,
                enemies: [
                    EnemyDefinition(
                        id: "patrol",
                        name: "巡回兵",
                        position: GridPoint(x: 1, y: 1),
                        behavior: .patrol(path: [GridPoint(x: 1, y: 1), GridPoint(x: 2, y: 1)])
                    )
                ],
                runState: DungeonRunState(
                    dungeonID: "growth-tower",
                    carriedHP: 4,
                    curseEntries: [DungeonCurseEntry(curseID: .patrolBell)]
                )
            )
        )
        playBasicMove(to: GridPoint(x: 0, y: 1), in: patrolCore)
        XCTAssertEqual(patrolCore.dungeonHP, 2)

        let chaserCore = makeCore(
            mode: makeDungeonMode(
                spawn: GridPoint(x: 0, y: 0),
                exit: GridPoint(x: 4, y: 4),
                hp: 4,
                turnLimit: 8,
                enemies: [
                    EnemyDefinition(
                        id: "chaser",
                        name: "追跡兵",
                        position: GridPoint(x: 1, y: 1),
                        behavior: .chaser
                    )
                ],
                runState: DungeonRunState(
                    dungeonID: "growth-tower",
                    carriedHP: 4,
                    curseEntries: [DungeonCurseEntry(curseID: .chaserScent)]
                )
            )
        )
        playBasicMove(to: GridPoint(x: 0, y: 1), in: chaserCore)
        XCTAssertEqual(chaserCore.dungeonHP, 2)

        let marker = EnemyDefinition(
            id: "marker",
            name: "メテオ兵",
            position: GridPoint(x: 3, y: 1),
            behavior: .marker(directions: [], range: 2)
        )
        let markerMode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 4,
            turnLimit: 8,
            enemies: [marker],
            runState: DungeonRunState(
                dungeonID: "growth-tower",
                carriedHP: 4,
                curseEntries: [DungeonCurseEntry(curseID: .meteorRod)],
                cardVariationSeed: 123
            )
        )
        let markerCore = makeCore(mode: markerMode)
        guard let warningMove = markerCore.availableBasicOrthogonalMoves().first(where: {
            markerCore.enemyWarningPoints.contains($0.destination)
        }) else {
            XCTFail("メテオ警告へ踏み込む基本移動候補が必要です")
            return
        }
        playBasicMove(to: warningMove.destination, in: markerCore)
        XCTAssertEqual(markerCore.dungeonHP, 2)
    }

    func testCurseV11TrapStatusAndVisionWeaknesses() {
        let runState = DungeonRunState(
            dungeonID: "growth-tower",
            carriedHP: 10,
            rewardInventoryEntries: [
                DungeonInventoryEntry(card: .straightRight2, rewardUses: 1),
                DungeonInventoryEntry(card: .straightUp2, rewardUses: 1),
                DungeonInventoryEntry(support: .barrierSpell, rewardUses: 1)
            ],
            relicEntries: [
                DungeonRelicEntry(relicID: .smallLantern),
                DungeonRelicEntry(relicID: .spareTorch)
            ],
            curseEntries: [
                DungeonCurseEntry(curseID: .trapMagnet),
                DungeonCurseEntry(curseID: .oilSoakedBoots),
                DungeonCurseEntry(curseID: .glassAnklet),
                DungeonCurseEntry(curseID: .poisonVial),
                DungeonCurseEntry(curseID: .ironShackle),
                DungeonCurseEntry(curseID: .foolsMask),
                DungeonCurseEntry(curseID: .frayedMemory),
                DungeonCurseEntry(curseID: .wetTinder)
            ]
        )
        let trapPoint = GridPoint(x: 1, y: 0)
        let lavaPoint = GridPoint(x: 2, y: 0)
        let brittlePoint = GridPoint(x: 3, y: 0)
        let poisonPoint = GridPoint(x: 0, y: 1)
        let shacklePoint = GridPoint(x: 0, y: 2)
        let illusionPoint = GridPoint(x: 1, y: 2)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 10,
            turnLimit: 12,
            hazards: [
                .damageTrap(points: [trapPoint], damage: 1),
                .lavaTile(points: [lavaPoint], damage: 1),
                .brittleFloor(points: [brittlePoint])
            ],
            tileEffectOverrides: [
                poisonPoint: .poisonTrap,
                shacklePoint: .shackleTrap,
                illusionPoint: .illusionTrap
            ],
            runState: runState
        )
        let core = makeCore(mode: mode)

        XCTAssertEqual(core.effectiveDungeonTurnLimit, 15)
        XCTAssertEqual(core.dungeonDarknessVisionRadius, 2)

        playBasicMove(to: trapPoint, in: core)
        XCTAssertEqual(core.dungeonHP, 9)

        playBasicMove(to: lavaPoint, in: core)
        XCTAssertEqual(core.dungeonHP, 6)

        playBasicMove(to: brittlePoint, in: core)
        playBasicMove(to: lavaPoint, in: core)
        XCTAssertEqual(core.dungeonHP, 3)
        playBasicMove(to: brittlePoint, in: core)
        XCTAssertEqual(core.dungeonHP, 1)

        let poisonCore = makeCore(mode: mode)
        playBasicMove(to: poisonPoint, in: poisonCore)
        XCTAssertEqual(poisonCore.poisonDamageTicksRemaining, 4)

        playBasicMove(to: shacklePoint, in: poisonCore)
        XCTAssertTrue(poisonCore.isShackled)
        let moveCountAfterShackle = poisonCore.moveCount
        playBasicMove(to: illusionPoint, in: poisonCore)
        XCTAssertEqual(poisonCore.moveCount - moveCountAfterShackle, 1)
        XCTAssertTrue(poisonCore.isIlluded)
        XCTAssertEqual(poisonCore.handStacks.count, 3)
    }

    private func supportPoolCards(
        floorIndex: Int,
        context: DungeonWeightedRewardPoolContext
    ) -> Set<SupportCard> {
        Set(
            DungeonWeightedRewardPools
                .entries(floorIndex: floorIndex, context: context)
                .compactMap { entry -> SupportCard? in
                    guard entry.weight > 0, case .support(let support) = entry.item else { return nil }
                    return support
                }
        )
    }

    private func makeDungeonMode(
        spawn: GridPoint,
        exit: GridPoint,
        hp: Int = 3,
        turnLimit: Int?,
        enemies: [EnemyDefinition] = [],
        hazards: [HazardDefinition] = [],
        impassableTilePoints: Set<GridPoint> = [],
        tileEffectOverrides: [GridPoint: TileEffect] = [:],
        warpTilePairs: [String: [GridPoint]] = [:],
        exitLock: DungeonExitLock? = nil,
        allowsBasicOrthogonalMove: Bool = true,
        cardAcquisitionMode: DungeonCardAcquisitionMode = .deck,
        cardPickups: [DungeonCardPickupDefinition] = [],
        relicPickups: [DungeonRelicPickupDefinition] = [],
        movementStyle: DungeonMovementStyle = .orthogonal,
        difficulty: DungeonDifficulty = .growth,
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
                deckPreset: .standardLight,
                spawnRule: .fixed(spawn),
                penalties: GameMode.PenaltySettings(
                    deadlockPenaltyCost: 0,
                    manualRedrawPenaltyCost: 0,
                    manualDiscardPenaltyCost: 1,
                    revisitPenaltyCost: 0
                ),
                impassableTilePoints: impassableTilePoints,
                tileEffectOverrides: tileEffectOverrides,
                warpTilePairs: warpTilePairs,
                completionRule: .dungeonExit(exitPoint: exit),
                dungeonRules: DungeonRules(
                    difficulty: difficulty,
                    failureRule: DungeonFailureRule(initialHP: hp, turnLimit: turnLimit),
                    enemies: enemies,
                    hazards: hazards,
                    exitLock: exitLock,
                    allowsBasicOrthogonalMove: allowsBasicOrthogonalMove,
                    movementStyle: movementStyle,
                    cardAcquisitionMode: cardAcquisitionMode,
                    cardPickups: cardPickups,
                    relicPickups: relicPickups
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

    private var knightReplacementSourceCards: Set<MoveCard> {
        [
            .knightUp2Right1,
            .knightUp2Left1,
            .knightUp1Right2,
            .knightUp1Left2,
            .knightDown2Right1,
            .knightDown2Left1,
            .knightDown1Right2,
            .knightDown1Left2,
            .knightUpwardChoice,
            .knightRightwardChoice,
            .knightDownwardChoice,
            .knightLeftwardChoice
        ]
    }

    private func moveCards(in entries: [DungeonWeightedRewardPoolEntry]) -> [MoveCard] {
        entries.compactMap { entry in
            guard case .move(let card) = entry.item else { return nil }
            return card
        }
    }

    private func assertTurnLimitSlack(
        for floor: DungeonFloorDefinition,
        after core: GameCore,
        minimumSlack: Int = 3,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let turnLimit = floor.failureRule.turnLimit else {
            XCTFail("\(floor.title) は手数上限を持つ想定です", file: file, line: line)
            return
        }

        XCTAssertGreaterThanOrEqual(
            turnLimit - core.moveCount,
            minimumSlack,
            "\(floor.title) の代表ルートは最低 \(minimumSlack) 手の余裕を残す必要があります",
            file: file,
            line: line
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
            case .brittleFloor(let points, _):
                blocked.formUnion(points)
            case .hpHalvingTrap(let points):
                blocked.formUnion(points)
            case .damageTrap(let points, _):
                blocked.formUnion(points)
            case .lavaTile(let points, _):
                blocked.formUnion(points)
            case .healingTile(let points, _):
                blocked.formUnion(points)
            }
        }
        return blocked
    }

    private func growthTowerHazardPoints(for floor: DungeonFloorDefinition) -> Set<GridPoint> {
        var points: Set<GridPoint> = []
        for hazard in floor.hazards {
            switch hazard {
            case .brittleFloor(let hazardPoints, _):
                points.formUnion(hazardPoints)
            case .damageTrap(let hazardPoints, _):
                points.formUnion(hazardPoints)
            case .hpHalvingTrap(let hazardPoints):
                points.formUnion(hazardPoints)
            case .lavaTile(let hazardPoints, _):
                points.formUnion(hazardPoints)
            case .healingTile(let hazardPoints, _):
                points.formUnion(hazardPoints)
            }
        }
        return points
    }

    private func growthTowerDamagePressurePointCount(for floor: DungeonFloorDefinition) -> Int {
        floor.hazards.reduce(0) { total, hazard in
            switch hazard {
            case .brittleFloor(let points, _),
                 .damageTrap(let points, _),
                 .hpHalvingTrap(let points),
                 .lavaTile(let points, _):
                return total + points.count
            case .healingTile:
                return total
            }
        }
    }

    private func growthTowerBrittleFloorPointCount(
        for floor: DungeonFloorDefinition,
        initialState: BrittleFloorInitialState?
    ) -> Int {
        floor.hazards.reduce(0) { total, hazard in
            guard case .brittleFloor(let points, let state) = hazard else { return total }
            guard initialState == nil || state == initialState else { return total }
            return total + points.count
        }
    }

    private func growthTowerBrittleFloorPoints(for floor: DungeonFloorDefinition) -> Set<GridPoint> {
        floor.hazards.reduce(into: Set<GridPoint>()) { result, hazard in
            guard case .brittleFloor(let points, _) = hazard else { return }
            result.formUnion(points)
        }
    }

    private func rogueHandExpansionSeed(targeting surface: DungeonHandExpansionSpawnSurface) -> UInt64? {
        (1...500).map(UInt64.init).first { seed in
            let runState = DungeonRunState(
                dungeonID: "rogue-tower",
                carriedHP: 3,
                dungeonInventoryKindLimit: 5,
                rogueHandExpansionChanceStep: 99,
                rogueTowerSeed: seed
            )
            return runState.rogueHandExpansionSpawnSurface(floorIndex: 0, seed: seed) == surface
        }
    }

    private func damageTrapDamages(in floor: DungeonFloorDefinition) -> [Int] {
        Set(floor.hazards.compactMap { hazard -> Int? in
            guard case .damageTrap(_, let damage) = hazard else { return nil }
            return damage
        }).sorted()
    }

    private func lavaTileDamages(in floor: DungeonFloorDefinition) -> [Int] {
        Set(floor.hazards.compactMap { hazard -> Int? in
            guard case .lavaTile(_, let damage) = hazard else { return nil }
            return damage
        }).sorted()
    }

    private func lavaTilePoints(in floor: DungeonFloorDefinition) -> Set<GridPoint> {
        floor.hazards.reduce(into: Set<GridPoint>()) { result, hazard in
            guard case .lavaTile(let points, _) = hazard else { return }
            result.formUnion(points)
        }
    }

    private func lavaTileFields(in floor: DungeonFloorDefinition) -> [Set<GridPoint>] {
        floor.hazards.compactMap { hazard in
            guard case .lavaTile(let points, _) = hazard else { return nil }
            return points
        }
    }

    private func isSingleOrthogonalComponent(_ points: Set<GridPoint>) -> Bool {
        guard let start = points.first else { return false }
        var visited: Set<GridPoint> = [start]
        var queue: [GridPoint] = [start]
        while !queue.isEmpty {
            let point = queue.removeFirst()
            let neighbors = [
                point.offset(dx: 1, dy: 0),
                point.offset(dx: -1, dy: 0),
                point.offset(dx: 0, dy: 1),
                point.offset(dx: 0, dy: -1)
            ]
            for next in neighbors where points.contains(next) && !visited.contains(next) {
                visited.insert(next)
                queue.append(next)
            }
        }
        return visited == points
    }

    private func growthTowerStatusTrapPointCount(for floor: DungeonFloorDefinition) -> Int {
        growthTowerStatusTrapPoints(for: floor).count
    }

    private func growthTowerStatusTrapPoints(for floor: DungeonFloorDefinition) -> Set<GridPoint> {
        Set(floor.tileEffectOverrides.compactMap { point, effect in
            switch effect {
            case .poisonTrap, .shackleTrap, .illusionTrap, .staggerTrap, .relicBreakTrap,
                 .discardRandomHand, .discardAllMoveCards, .discardAllSupportCards, .discardAllHands:
                return point
            case .warp, .returnWarp, .shuffleHand, .blast, .slow, .swamp, .preserveCard:
                return nil
            }
        })
    }

    private func supportWeight(
        _ support: SupportCard,
        in entries: [DungeonWeightedRewardPoolEntry]
    ) -> Int {
        entries.reduce(0) { total, entry in
            guard case .support(let entrySupport) = entry.item,
                  entrySupport == support
            else { return total }
            return total + entry.weight
        }
    }

    private func moveWeight(
        _ move: MoveCard,
        in entries: [DungeonWeightedRewardPoolEntry]
    ) -> Int {
        entries.reduce(0) { total, entry in
            guard case .move(let entryMove) = entry.item,
                  entryMove == move
            else { return total }
            return total + entry.weight
        }
    }

    private func assertEqualMoveWeights(
        _ moves: [MoveCard],
        in entries: [DungeonWeightedRewardPoolEntry],
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let weights = moves.map { moveWeight($0, in: entries) }
        guard let expected = weights.first else { return }
        for (move, weight) in zip(moves, weights) {
            XCTAssertGreaterThan(weight, 0, "\(label) \(move.displayName)", file: file, line: line)
            XCTAssertEqual(weight, expected, "\(label) \(move.displayName)", file: file, line: line)
        }
    }

    private func assertBalancedMoveWeights(
        _ moves: [MoveCard],
        in entries: [DungeonWeightedRewardPoolEntry],
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let weights = moves.map { moveWeight($0, in: entries) }
        guard let expected = weights.first else { return }
        for (move, weight) in zip(moves, weights) {
            XCTAssertEqual(weight, expected, "\(label) \(move.displayName)", file: file, line: line)
        }
    }

    private func singleDirectionMoveWeight(in entries: [DungeonWeightedRewardPoolEntry]) -> Int {
        [
            MoveCard.straightUp2,
            .straightRight2,
            .straightDown2,
            .straightLeft2,
            .diagonalUpRight2,
            .diagonalDownRight2,
            .diagonalDownLeft2,
            .diagonalUpLeft2
        ].reduce(0) { $0 + moveWeight($1, in: entries) }
    }

    private func rayMoveWeight(in entries: [DungeonWeightedRewardPoolEntry]) -> Int {
        MoveCard.directionalRayCards.reduce(0) { $0 + moveWeight($1, in: entries) }
    }

    private func knightChoiceMoveWeight(in entries: [DungeonWeightedRewardPoolEntry]) -> Int {
        [
            MoveCard.knightUpwardChoice,
            .knightRightwardChoice,
            .knightDownwardChoice,
            .knightLeftwardChoice
        ].reduce(0) { $0 + moveWeight($1, in: entries) }
    }

    private func choiceMoveWeight(in entries: [DungeonWeightedRewardPoolEntry]) -> Int {
        [
            MoveCard.kingUpwardDiagonalChoice,
            .kingRightDiagonalChoice,
            .kingDownwardDiagonalChoice,
            .kingLeftDiagonalChoice,
            .knightUpwardChoice,
            .knightRightwardChoice,
            .knightDownwardChoice,
            .knightLeftwardChoice
        ].reduce(0) { $0 + moveWeight($1, in: entries) }
    }

    private func averageDamagePressure(in floors: ArraySlice<DungeonFloorDefinition>) -> Double {
        guard !floors.isEmpty else { return 0 }
        let total = floors.reduce(0) { $0 + growthTowerDamagePressurePointCount(for: $1) }
        return Double(total) / Double(floors.count)
    }

    private func enemyBehaviorKind(_ behavior: EnemyBehavior) -> String {
        switch behavior {
        case .guardPost:
            return "guardPost"
        case .patrol:
            return "patrol"
        case .watcher:
            return "watcher"
        case .rotatingWatcher:
            return "rotatingWatcher"
        case .chaser:
            return "chaser"
        case .marker:
            return "marker"
        case .targetedMarker:
            return "targetedMarker"
        }
    }

    @discardableResult
    private func assertWatchersFaceWidestOpenSightLine(
        in floor: DungeonFloorDefinition,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> (watcherCount: Int, edgeWatcherCount: Int) {
        var watcherCount = 0
        var edgeWatcherCount = 0
        for enemy in floor.enemies {
            guard let direction = watcherInitialDirection(for: enemy.behavior) else { continue }
            watcherCount += 1
            if enemy.position.x == 0
                || enemy.position.y == 0
                || enemy.position.x == floor.boardSize - 1
                || enemy.position.y == floor.boardSize - 1 {
                edgeWatcherCount += 1
            }

            let actualLength = watcherSightLineLength(
                from: enemy.position,
                direction: direction,
                in: floor
            )
            let directions = [
                MoveVector(dx: 1, dy: 0),
                MoveVector(dx: -1, dy: 0),
                MoveVector(dx: 0, dy: 1),
                MoveVector(dx: 0, dy: -1)
            ]
            let widestLength = directions
                .map { watcherSightLineLength(from: enemy.position, direction: $0, in: floor) }
                .max() ?? 0
            guard widestLength > 0 else { continue }

            XCTAssertEqual(
                actualLength,
                widestLength,
                "\(context) / \(enemy.id) は壁や岩柱ですぐ止まる方向ではなく、最も広い射線方向を向く必要があります",
                file: file,
                line: line
            )
        }
        return (watcherCount, edgeWatcherCount)
    }

    private func watcherInitialDirection(for behavior: EnemyBehavior) -> MoveVector? {
        switch behavior {
        case .watcher(let direction, _):
            return direction
        case .rotatingWatcher(let initialDirection, _, _):
            return initialDirection
        case .guardPost, .patrol, .chaser, .marker, .targetedMarker:
            return nil
        }
    }

    private func watcherSightLineLength(
        from origin: GridPoint,
        direction: MoveVector,
        in floor: DungeonFloorDefinition
    ) -> Int {
        var length = 0
        var point = origin.offset(dx: direction.dx, dy: direction.dy)
        while point.isInside(boardSize: floor.boardSize), !floor.impassableTilePoints.contains(point) {
            length += 1
            point = point.offset(dx: direction.dx, dy: direction.dy)
        }
        return length
    }

    private func isOrthogonalStepPath(_ path: [GridPoint]) -> Bool {
        guard path.count > 1 else { return true }
        return zip(path, path.dropFirst()).allSatisfy { before, after in
            manhattanDistance(from: before, to: after) == 1
        }
    }

    private func assertPatrolPathCanMove(
        _ path: [GridPoint],
        in floor: DungeonFloorDefinition,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(
            Set(path).count,
            4,
            "\(context) の巡回路は4マス以上の実移動先を持つ必要があります",
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            path.count,
            6,
            "\(context) の巡回路は往復込み6マス以上にします",
            file: file,
            line: line
        )
        XCTAssertTrue(
            isOrthogonalStepPath(path),
            "\(context) の巡回路は上下左右1マス連続にします",
            file: file,
            line: line
        )
        if isClosedPatrolLoop(path) {
            XCTAssertEqual(
                manhattanDistance(from: path[path.count - 1], to: path[0]),
                1,
                "\(context) のループ巡回路は末尾から先頭へ上下左右1マスで戻れる必要があります",
                file: file,
                line: line
            )
        }
        let collapsedPoints = initialCollapsedFloorPoints(in: floor)
        XCTAssertTrue(
            path.allSatisfy {
                $0.isInside(boardSize: floor.boardSize)
                    && !floor.impassableTilePoints.contains($0)
                    && !collapsedPoints.contains($0)
            },
            "\(context) の巡回路は初期地形で敵が通れる床だけを通します",
            file: file,
            line: line
        )
    }

    private func initialCollapsedFloorPoints(in floor: DungeonFloorDefinition) -> Set<GridPoint> {
        var points: Set<GridPoint> = []
        for hazard in floor.hazards {
            if case .brittleFloor(let hazardPoints, .collapsed) = hazard {
                points.formUnion(hazardPoints)
            }
        }
        return points
    }

    private func assertWarpPairsAvoidOrthogonalAdjacency(
        in floor: DungeonFloorDefinition,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for (pairID, points) in floor.warpTilePairs {
            for firstIndex in points.indices {
                for secondIndex in points.indices.dropFirst(firstIndex + 1) {
                    XCTAssertNotEqual(
                        manhattanDistance(from: points[firstIndex], to: points[secondIndex]),
                        1,
                        "\(context) / \(pairID) の同一ワープペアは上下左右に直接隣接させません",
                        file: file,
                        line: line
                    )
                }
            }
        }
    }

    private func assertFallSecretChamberCannotBeEnteredByNormalMovement(
        _ secret: DungeonFallSecretDefinition,
        in floor: DungeonFloorDefinition,
        dungeonID: String,
        floorIndex: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let chamberPoints: Set<GridPoint> = [
            secret.landingPoint,
            secret.treasurePickup.point,
            secret.returnWarpPoint
        ]
        let allMoveCardStacks = MoveCard.allCases.map { card in
            HandStack(cards: [DealtCard(move: card)])
        }

        for movementStyle in DungeonMovementStyle.allCases {
            let mode = floor.makeGameMode(
                dungeonID: dungeonID,
                runState: DungeonRunState(
                    dungeonID: dungeonID,
                    currentFloorIndex: floorIndex,
                    carriedHP: 3,
                    movementStyle: movementStyle
                )
            )
            let core = makeCore(mode: mode)

            for point in allBoardPoints(boardSize: floor.boardSize)
                where !chamberPoints.contains(point) && core.board.isTraversable(point) {
                let cardDestinations = Set(
                    core.availableMoves(handStacks: allMoveCardStacks, current: point)
                        .map(\.destination)
                )
                XCTAssertTrue(
                    cardDestinations.isDisjoint(with: chamberPoints),
                    "\(floor.title) の落下専用小部屋へ \(movementStyle.displayName) / \(point) からカード移動で入れない必要があります",
                    file: file,
                    line: line
                )

                let basicDestinations = Set(
                    core.availableBasicOrthogonalMoves(current: point)
                        .map(\.destination)
                )
                XCTAssertTrue(
                    basicDestinations.isDisjoint(with: chamberPoints),
                    "\(floor.title) の落下専用小部屋へ \(movementStyle.displayName) / \(point) から基本移動で入れない必要があります",
                    file: file,
                    line: line
                )
            }
        }
    }

    private func assertFallSecretChamberRemainsUsableAfterFalling(
        _ secret: DungeonFallSecretDefinition,
        in floor: DungeonFloorDefinition,
        dungeonID: String,
        floorIndex: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let mode = floor.makeGameMode(
            dungeonID: dungeonID,
            runState: DungeonRunState(
                dungeonID: dungeonID,
                currentFloorIndex: floorIndex,
                carriedHP: 3,
                pendingFallLandingPoint: secret.landingPoint
            )
        )
        let core = makeCore(mode: mode)
        let landingDestinations = Set(core.availableBasicOrthogonalMoves().map(\.destination))

        XCTAssertTrue(
            landingDestinations.contains(secret.treasurePickup.point),
            "\(floor.title) の落下後は小部屋の宝箱へ歩ける必要があります",
            file: file,
            line: line
        )
        XCTAssertTrue(
            landingDestinations.contains(secret.returnWarpPoint),
            "\(floor.title) の落下後は帰還ワープへ歩ける必要があります",
            file: file,
            line: line
        )
    }

    private func majorGrowthTowerGimmickOverlaps(for floor: DungeonFloorDefinition) -> [String] {
        var occupantsByPoint: [GridPoint: [String]] = [:]
        let sharedLoopKeys = sharedPatrolLoopKeys(in: floor)

        func add(_ label: String, at point: GridPoint) {
            if occupantsByPoint[point]?.contains(label) == true {
                return
            }
            occupantsByPoint[point, default: []].append(label)
        }

        add("開始", at: floor.spawnPoint)
        add("階段", at: floor.exitPoint)
        if let unlockPoint = floor.exitLock?.unlockPoint {
            add("鍵", at: unlockPoint)
        }

        for pickup in floor.cardPickups {
            add("拾得カード:\(pickup.id)", at: pickup.point)
        }
        for pickup in floor.relicPickups {
            add("宝箱:\(pickup.id)", at: pickup.point)
        }
        for point in floor.tileEffectOverrides.keys {
            add("床効果", at: point)
        }
        for enemy in floor.enemies {
            switch enemy.behavior {
            case .patrol(let path):
                let loopKey = patrolLoopKey(path)
                let label = loopKey.map { sharedLoopKeys.contains($0) ? "共有巡回:\($0)" : "巡回:\(enemy.id)" }
                    ?? "巡回:\(enemy.id)"
                for point in Set(path) {
                    add(label, at: point)
                }
            case .chaser, .guardPost, .marker, .targetedMarker, .watcher, .rotatingWatcher:
                add("敵:\(enemy.id)", at: enemy.position)
            }
        }
        for point in floor.impassableTilePoints {
            add("固定障害物", at: point)
        }
        for hazard in floor.hazards {
            switch hazard {
            case .brittleFloor(let points, _):
                for point in points {
                    add("ひび割れ床", at: point)
                }
            case .damageTrap(let points, _):
                for point in points {
                    add("ダメージ罠", at: point)
                }
            case .hpHalvingTrap(let points):
                for point in points {
                    add("衰弱罠", at: point)
                }
            case .lavaTile(let points, _):
                for point in points {
                    add("溶岩", at: point)
                }
            case .healingTile(let points, _):
                for point in points {
                    add("回復床", at: point)
                }
            }
        }
        for points in floor.warpTilePairs.values {
            for point in points {
                add("ワープ床", at: point)
            }
        }

        return occupantsByPoint
            .filter { $0.value.count > 1 }
            .map { point, occupants in "\(point): \(occupants.joined(separator: ", "))" }
            .sorted()
    }

    private func disallowedGrowthTowerImpassablePoints(for floor: DungeonFloorDefinition) -> Set<GridPoint> {
        var blocked: Set<GridPoint> = [
            floor.spawnPoint,
            floor.exitPoint
        ]
        blocked.formUnion(floor.cardPickups.map(\.point))
        blocked.formUnion(floor.relicPickups.map(\.point))
        blocked.formUnion(floor.enemies.map(\.position))
        for enemy in floor.enemies {
            if case .patrol(let path) = enemy.behavior {
                blocked.formUnion(path)
            }
        }
        blocked.formUnion(floor.tileEffectOverrides.keys)
        blocked.formUnion(floor.warpTilePairs.values.flatMap { $0 })
        if let unlockPoint = floor.exitLock?.unlockPoint {
            blocked.insert(unlockPoint)
        }
        for hazard in floor.hazards {
            switch hazard {
            case .brittleFloor(let points, _):
                blocked.formUnion(points)
            case .hpHalvingTrap(let points):
                blocked.formUnion(points)
            case .damageTrap(let points, _):
                blocked.formUnion(points)
            case .lavaTile(let points, _):
                blocked.formUnion(points)
            case .healingTile(let points, _):
                blocked.formUnion(points)
            }
        }
        return blocked
    }

    private func disallowedGrowthTowerPatrolPoints(
        for floor: DungeonFloorDefinition,
        excludingEnemyID enemyID: String
    ) -> Set<GridPoint> {
        let sharedLoopKeys = sharedPatrolLoopKeys(in: floor)
        let currentSharedLoopKey = floor.enemies.first { $0.id == enemyID }.flatMap { enemy -> String? in
            guard case .patrol(let path) = enemy.behavior else { return nil }
            let key = patrolLoopKey(path)
            return key.map { sharedLoopKeys.contains($0) ? $0 : nil } ?? nil
        }
        var blocked: Set<GridPoint> = [
            floor.spawnPoint,
            floor.exitPoint
        ]
        blocked.formUnion(floor.cardPickups.map(\.point))
        blocked.formUnion(floor.relicPickups.map(\.point))
        blocked.formUnion(floor.impassableTilePoints)
        blocked.formUnion(floor.tileEffectOverrides.keys)
        blocked.formUnion(floor.warpTilePairs.values.flatMap { $0 })
        blocked.formUnion(floor.enemies.compactMap { enemy in
            if enemy.id == enemyID { return nil }
            if let currentSharedLoopKey,
               case .patrol(let path) = enemy.behavior,
               patrolLoopKey(path) == currentSharedLoopKey {
                return nil
            }
            return enemy.position
        })
        for enemy in floor.enemies where enemy.id != enemyID {
            guard case .patrol(let path) = enemy.behavior else { continue }
            if let currentSharedLoopKey,
               patrolLoopKey(path) == currentSharedLoopKey {
                continue
            }
            blocked.formUnion(path)
        }
        if let unlockPoint = floor.exitLock?.unlockPoint {
            blocked.insert(unlockPoint)
        }
        for hazard in floor.hazards {
            switch hazard {
            case .brittleFloor(let points, _):
                blocked.formUnion(points)
            case .hpHalvingTrap(let points):
                blocked.formUnion(points)
            case .damageTrap(let points, _):
                blocked.formUnion(points)
            case .lavaTile(let points, _):
                blocked.formUnion(points)
            case .healingTile(let points, _):
                blocked.formUnion(points)
            }
        }
        return blocked
    }

    private func sharedPatrolLoopKeys(in floor: DungeonFloorDefinition) -> Set<String> {
        let loopKeys = floor.enemies.compactMap { enemy -> String? in
            guard case .patrol(let path) = enemy.behavior else { return nil }
            return patrolLoopKey(path)
        }
        let grouped = Dictionary(grouping: loopKeys, by: { $0 })
        return Set(grouped.compactMap { key, values in values.count > 1 ? key : nil })
    }

    private func patrolLoopKey(_ path: [GridPoint]) -> String? {
        guard isClosedPatrolLoop(path) else { return nil }
        return path.map { "\($0.x),\($0.y)" }.joined(separator: ";")
    }

    private func isClosedPatrolLoop(_ path: [GridPoint]) -> Bool {
        guard path.count >= 4,
              Set(path).count == path.count,
              let first = path.first,
              let last = path.last
        else { return false }
        return isOrthogonalStepPath(path)
            && manhattanDistance(from: first, to: last) == 1
    }

    private func allBoardPoints(boardSize: Int) -> [GridPoint] {
        (0..<boardSize).flatMap { y in
            (0..<boardSize).map { x in GridPoint(x: x, y: y) }
        }
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

    private func orthogonalRoute(
        from start: GridPoint,
        to goal: GridPoint,
        in floor: DungeonFloorDefinition,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [GridPoint] {
        guard start.isInside(boardSize: floor.boardSize), goal.isInside(boardSize: floor.boardSize) else {
            XCTFail("経路の始点または終点が盤面外です: \(start) -> \(goal)", file: file, line: line)
            return []
        }
        if start == goal { return [] }

        let directions = [
            MoveVector(dx: 1, dy: 0),
            MoveVector(dx: -1, dy: 0),
            MoveVector(dx: 0, dy: 1),
            MoveVector(dx: 0, dy: -1)
        ]
        var queue: [GridPoint] = [start]
        var visited: Set<GridPoint> = [start]
        var previousByPoint: [GridPoint: GridPoint] = [:]

        while !queue.isEmpty {
            let point = queue.removeFirst()
            if point == goal { break }

            for direction in directions {
                let next = GridPoint(x: point.x + direction.dx, y: point.y + direction.dy)
                guard next.isInside(boardSize: floor.boardSize),
                      !floor.impassableTilePoints.contains(next),
                      !visited.contains(next)
                else {
                    continue
                }
                visited.insert(next)
                previousByPoint[next] = point
                queue.append(next)
            }
        }

        guard visited.contains(goal) else {
            XCTFail("基本移動経路が見つかりません: \(start) -> \(goal)", file: file, line: line)
            return []
        }

        var reversed: [GridPoint] = [goal]
        var current = goal
        while let previous = previousByPoint[current], previous != start {
            reversed.append(previous)
            current = previous
        }
        return reversed.reversed()
    }

    private func makeCore(
        mode: GameMode,
        cards: [MoveCard] = [.straightRight2, .straightUp2, .rayRight, .kingUpRight, .straightRight2]
    ) -> GameCore {
        GameCore.makeTestInstance(
            deck: Deck.makeTestDeck(cards: cards, configuration: mode.deckConfiguration),
            current: mode.initialSpawnPoint,
            mode: mode
        )
    }

    private func playMove(to destination: GridPoint, in core: GameCore, file: StaticString = #filePath, line: UInt = #line) {
        guard let move = core.availableMoves().first(where: { $0.destination == destination }) else {
            if let basicMove = core.availableBasicOrthogonalMoves().first(where: { $0.destination == destination }) {
                core.playBasicOrthogonalMove(using: basicMove)
                return
            }
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

    private func annihilateAllEnemies(in core: GameCore, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(core.addDungeonInventorySupportCardForTesting(.annihilationSpell, rewardUses: 1), file: file, line: line)
        guard let supportIndex = core.handStacks.firstIndex(where: { $0.topCard?.supportCard == .annihilationSpell }) else {
            XCTFail("全滅の呪文が手札にありません", file: file, line: line)
            return
        }
        core.playSupportCard(at: supportIndex)
    }

    private func makeGuardEnemies(count: Int) -> [EnemyDefinition] {
        let points = (0..<5).flatMap { y in
            (0..<5).map { x in GridPoint(x: x, y: y) }
        }.filter {
            $0 != GridPoint(x: 0, y: 0) && $0 != GridPoint(x: 4, y: 4)
        }
        return Array(points.prefix(count)).enumerated().map { index, point in
            EnemyDefinition(
                id: "guard-\(index)",
                name: "番兵",
                position: point,
                behavior: .guardPost
            )
        }
    }

    private func isGuardPost(_ enemy: EnemyDefinition) -> Bool {
        if case .guardPost = enemy.behavior { return true }
        return false
    }

    private func isWatcher(_ enemy: EnemyDefinition) -> Bool {
        if case .watcher = enemy.behavior { return true }
        return false
    }

    private func isPatrol(_ enemy: EnemyDefinition) -> Bool {
        if case .patrol = enemy.behavior { return true }
        return false
    }

    private func isChaser(_ enemy: EnemyDefinition) -> Bool {
        if case .chaser = enemy.behavior { return true }
        return false
    }

    private func playDiagnosticMessages() -> [String] {
        DebugLogHistory.shared.snapshot()
            .map(\.message)
            .filter { $0.contains("[PLAY]") }
    }
}
