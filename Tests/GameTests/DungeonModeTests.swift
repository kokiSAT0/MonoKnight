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
        XCTAssertTrue(core.dungeonRunLogEntries.contains { $0.kind == .damage && $0.message.contains("見張りの攻撃でHP -1") })
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
        XCTAssertTrue(core.dungeonRunLogEntries.contains { $0.kind == .damage && $0.message.contains("回転見張りの攻撃でHP -1") })
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
        XCTAssertTrue(core.dungeonRunLogEntries.contains { $0.kind == .damage && $0.message.contains("メテオ兵のメテオでHP -1") })
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
            enem