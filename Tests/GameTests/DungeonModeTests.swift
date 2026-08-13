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
     