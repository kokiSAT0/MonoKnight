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
            cards: [.straightRight2, .kingUpRight, .straightLeft2, .straightDown2, .straightRight2]
        )

        XCTAssertTrue(mode.usesDungeonExit)
        playMove(to: GridPoint(x: 1, y: 0), in: core)

        XCTAssertEqual(core.progress, .cleared)
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

        XCTAssertEqual(core.dungeonHP, 2)
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

    func testSuspiciousRelicPickupCanGrantCurse() throws {
        let pickup = DungeonRelicPickupDefinition(
            id: "test-deep-0",
            point: GridPoint(x: 0, y: 1),
            kind: .suspiciousDeep,
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

        XCTAssertEqual(core.dungeonCurseEntries.map(\.curseID), [.rustyChain])
        XCTAssertEqual(core.dungeonHP, 4)
        XCTAssertEqual(core.effectiveDungeonTurnLimit, 6)
        XCTAssertTrue(core.collectedDungeonRelicPickupIDs.contains(pickup.id))
        XCTAssertEqual(core.dungeonRelicAcquisitionPresentations.first?.outcome, .curse)
        XCTAssertEqual(core.dungeonRelicAcquisitionPresentations.first?.items, [.curse(DungeonCurseEntry(curseID: .rustyChain))])
    }

    func testSuspiciousRelicPickupMimicCanFailRun() throws {
        let pickup = DungeonRelicPickupDefinition(
            id: "test-deep-33",
            point: GridPoint(x: 0, y: 1),
            kind: .suspiciousDeep
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

        XCTAssertEqual(core.dungeonHP, 0)
        XCTAssertEqual(core.progress, .failed)
        XCTAssertTrue(core.collectedDungeonRelicPickupIDs.contains(pickup.id))
        XCTAssertEqual(core.dungeonRelicAcquisitionPresentations.first?.outcome, .mimic)
        XCTAssertEqual(core.dungeonRelicAcquisitionPresentations.first?.items, [.mimicDamage(2)])
    }

    func testSuspiciousRelicPickupPandoraGrantsRelicAndCurse() throws {
        let pickup = DungeonRelicPickupDefinition(
            id: "test-deep-2",
            point: GridPoint(x: 0, y: 1),
            kind: .suspiciousDeep,
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

        XCTAssertEqual(core.dungeonRelicEntries.map(\.relicID), [.blackFeather])
        XCTAssertEqual(core.dungeonCurseEntries.map(\.curseID), [.bloodPact])
        XCTAssertEqual(core.dungeonRelicAcquisitionPresentations.first?.outcome, .pandora)
        XCTAssertEqual(
            core.dungeonRelicAcquisitionPresentations.first?.items,
            [.relic(DungeonRelicEntry(relicID: .blackFeather)), .curse(DungeonCurseEntry(curseID: .bloodPact))]
        )
    }

    func testPandoraAndSuspiciousPickupsExcludeOwnedRelicsAndCurses() throws {
        let pandoraPickup = DungeonRelicPickupDefinition(
            id: "test-deep-2",
            point: GridPoint(x: 0, y: 1),
            kind: .suspiciousDeep,
            candidateRelics: [.blackFeather, .travelerBoots],
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
            relicPickups: [pandoraPickup],
            runState: runState
        )
        let pandoraCore = makeCore(mode: pandoraMode)

        playBasicMove(to: pandoraPickup.point, in: pandoraCore)

        XCTAssertEqual(pandoraCore.dungeonRelicEntries.map(\.relicID), [.blackFeather, .travelerBoots])
        XCTAssertEqual(pandoraCore.dungeonCurseEntries.map(\.curseID), [.bloodPact])

        let curseFilteredPickup = DungeonRelicPickupDefinition(
            id: "test-deep-0",
            point: GridPoint(x: 0, y: 1),
            kind: .suspiciousDeep,
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

        XCTAssertEqual(curseFilteredCore.dungeonCurseEntries.filter { $0.curseID == .rustyChain }.count, 1)
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
            kind: .suspiciousDeep,
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

        XCTAssertEqual(core.effectiveDungeonTurnLimit, 12)

        let advanced = runState.advancedToNextFloor(
            carryoverHP: 5,
            currentFloorMoveCount: 0,
            currentInventoryEntries: core.dungeonInventoryEntries,
            currentCurseEntries: core.dungeonCurseEntries
        )

        XCTAssertEqual(advanced.carriedHP, 4)
        XCTAssertEqual(advanced.curseEntries.map(\.curseID), [.cursedCrown, .obsidianHeart, .warpedHourglass])
    }

    func testAddedRelicsAdjustTurnsPickupsFloorStartAndCurseConversion() throws {
        let pickup = DungeonRelicPickupDefinition(
            id: "test-deep-0",
            point: GridPoint(x: 0, y: 1),
            kind: .suspiciousDeep,
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
                DungeonRelicEntry(relicID: .starCup)
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
        playBasicMove(to: GridPoint(x: 0, y: 0), in: core)
        playBasicMove(to: trapPoint, in: core)

        XCTAssertEqual(core.dungeonHP, 1)
        XCTAssertEqual(core.dungeonRelicEntries.first { $0.relicID == .silverNeedle }?.remainingUses, 0)
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
        XCTAssertEqual(core.dungeonInventoryEntries.first?.rewardUses, 3)

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

        XCTAssertNil(core.dungeonFallEvent)
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
            enemies: [watcher],
            allowsBasicOrthogonalMove: true
        )
        let core = makeCore(mode: mode)

        XCTAssertFalse(core.enemyDangerPoints.contains(watcher.position))
        XCTAssertTrue(core.enemyDangerPoints.contains(GridPoint(x: 1, y: 1)))
        playBasicMove(to: GridPoint(x: 1, y: 1), in: core)

        XCTAssertEqual(core.dungeonHP, 1)
        XCTAssertEqual(core.progress, .playing)
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
            enemies: [rotatingWatcher],
            allowsBasicOrthogonalMove: true
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

    func testRotatingWatcherDisplayDangerShowsNextTurnLine() throws {
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
        XCTAssertTrue(core.enemyDangerDisplayPoints.contains(GridPoint(x: 3, y: 1)))
        XCTAssertFalse(core.enemyDangerDisplayPoints.contains(GridPoint(x: 4, y: 1)))
        XCTAssertFalse(core.enemyDangerDisplayPoints.contains(GridPoint(x: 2, y: 2)))
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
            enemies: [rotatingWatcher],
            allowsBasicOrthogonalMove: true
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
            position: GridPoint(x: 4, y: 4),
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
            enemies: [patrol, rotatingWatcher, chaser, marker],
            allowsBasicOrthogonalMove: true
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
            enemies: [marker],
            allowsBasicOrthogonalMove: true
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
            impassableTilePoints: [GridPoint(x: 2, y: 1)],
            allowsBasicOrthogonalMove: true
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
            enemies: [chaser],
            allowsBasicOrthogonalMove: true
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: GridPoint(x: 1, y: 0), in: core)

        XCTAssertEqual(core.enemyStates.first?.position, GridPoint(x: 2, y: 0))
        XCTAssertEqual(core.dungeonHP, 2)
        XCTAssertEqual(core.progress, .playing)
        XCTAssertEqual(core.dungeonEnemyTurnEvent?.attackedPlayer, true)
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
            enemies: [patrol],
            allowsBasicOrthogonalMove: true
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
            enemies: [patrol],
            allowsBasicOrthogonalMove: true
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: GridPoint(x: 1, y: 1), in: core)

        XCTAssertEqual(core.enemyStates.first?.position, GridPoint(x: 2, y: 1))
        XCTAssertEqual(core.enemyStates.first?.patrolIndex, 1)
        XCTAssertEqual(core.dungeonHP, 2)
        XCTAssertEqual(core.progress, .playing)
        XCTAssertEqual(core.dungeonEnemyTurnEvent?.attackedPlayer, true)
    }

    func testLaterEnemyStaysWhenEarlierEnemyReservesSameDestination() throws {
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
        XCTAssertTrue(core.enemyChaserMovementPreviews.isEmpty)

        playMove(to: GridPoint(x: 2, y: 0), in: core)

        let patrolState = try XCTUnwrap(core.enemyStates.first { $0.id == "patrol" })
        let chaserState = try XCTUnwrap(core.enemyStates.first { $0.id == "chaser" })
        XCTAssertEqual(patrolState.position, GridPoint(x: 2, y: 1))
        XCTAssertEqual(patrolState.patrolIndex, 1)
        XCTAssertEqual(chaserState.position, GridPoint(x: 3, y: 1))
        XCTAssertEqual(
            Set(core.enemyStates.map(\.position)),
            [GridPoint(x: 2, y: 1), GridPoint(x: 3, y: 1)]
        )
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

    func testPatrolRailPreviewExcludesMismatchedCurrentPosition() throws {
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

        XCTAssertTrue(core.enemyPatrolRailPreviews.isEmpty)
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

    func testBrittleFloorCracksThenCollapsesOnSecondStep() throws {
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

        playMove(to: brittlePoint, in: core)
        XCTAssertTrue(core.crackedFloorPoints.contains(brittlePoint))
        XCTAssertFalse(core.collapsedFloorPoints.contains(brittlePoint))

        playMove(to: GridPoint(x: 0, y: 0), in: core)
        playMove(to: brittlePoint, in: core)

        XCTAssertFalse(core.crackedFloorPoints.contains(brittlePoint))
        XCTAssertTrue(core.collapsedFloorPoints.contains(brittlePoint))
        XCTAssertEqual(core.dungeonHP, 2)
        XCTAssertEqual(core.dungeonFallEvent?.point, brittlePoint)
        XCTAssertEqual(core.dungeonFallEvent?.sourceFloorIndex, 1)
        XCTAssertEqual(core.dungeonFallEvent?.destinationFloorIndex, 0)
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

        XCTAssertTrue(core.crackedFloorPoints.contains(landingPoint))
        XCTAssertFalse(core.collapsedFloorPoints.contains(landingPoint))
        XCTAssertNil(core.dungeonFallEvent)
        XCTAssertEqual(core.dungeonHP, 2)
        XCTAssertEqual(core.progress, .playing)
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
            hazards: [.damageTrap(points: [trapPoint], damage: 1)],
            allowsBasicOrthogonalMove: true
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: trapPoint, in: core)

        XCTAssertEqual(core.dungeonHP, 2)
        XCTAssertEqual(core.progress, .playing)
        XCTAssertEqual(core.damageTrapPoints, [trapPoint])
    }

    func testLavaTileDamagesPlayerWhenSteppedOn() throws {
        let lavaPoint = GridPoint(x: 1, y: 0)
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            hazards: [.lavaTile(points: [lavaPoint], damage: 1)],
            allowsBasicOrthogonalMove: true
        )
        let core = makeCore(mode: mode)

        playBasicMove(to: lavaPoint, in: core)

        XCTAssertEqual(core.dungeonHP, 2)
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
            tileEffectOverrides: [trapPoint: .discardRandomHand],
            allowsBasicOrthogonalMove: true
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
            tileEffectOverrides: [trapPoint: .discardAllHands],
            allowsBasicOrthogonalMove: true
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

        XCTAssertEqual(core.dungeonHP, 1)
        XCTAssertEqual(core.progress, .playing)
        XCTAssertEqual(core.lastMovementResolution?.presentationSteps.map(\.hpAfter), [2, 1, 1, 1])
    }

    func testLeavingLavaDoesNotApplyExtraWaitDamage() throws {
        let lavaPoint = GridPoint(x: 0, y: 0)
        let mode = makeDungeonMode(
            spawn: lavaPoint,
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            hazards: [.lavaTile(points: [lavaPoint], damage: 1)],
            allowsBasicOrthogonalMove: true
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

        XCTAssertEqual(core.dungeonHP, 2)
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

        XCTAssertEqual(core.dungeonHP, 2)
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
            hazards: [.healingTile(points: [healingPoint], amount: 1)],
            allowsBasicOrthogonalMove: true
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
            hazards: [.healingTile(points: [healingPoint], amount: 1)],
            allowsBasicOrthogonalMove: true
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

    func testRayMoveStopsAtIntermediateBrittleCollapse() throws {
        let brittlePoint = GridPoint(x: 1, y: 0)
        let laterPoint = GridPoint(x: 2, y: 0)
        let runState = DungeonRunState(
            dungeonID: "test-tower",
            currentFloorIndex: 1,
            carriedHP: 3,
            crackedFloorPointsByFloor: [1: [brittlePoint]]
        )
        let mode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            hp: 3,
            turnLimit: 8,
            hazards: [.brittleFloor(points: [brittlePoint])],
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

    func testShackleTrapAppliesTwoTurnCostAndEnemyTurnsImmediately() throws {
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
        XCTAssertEqual(core.moveCount, 2)
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
        XCTAssertEqual(core.moveCount, 2)
    }

    func testShackleStateMakesLaterBasicMoveCostTwoAndAdvanceEnemiesTwice() throws {
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
        XCTAssertEqual(core.moveCount, 4)
        XCTAssertEqual(core.dungeonEnemyTurnEvent?.phases.count, 2)
    }

    func testSupportCardOnShackleAndLavaResolvesLavaOnceThenTwoEnemyTurns() throws {
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
        XCTAssertEqual(core.moveCount, 4)
        XCTAssertEqual(core.dungeonHP, 1)
        XCTAssertEqual(core.dungeonEnemyTurnEvent?.phases.count, 2)
    }

    func testAntidoteClearsPoisonBeforeSupportActionCanDealPoisonDamage() throws {
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
        let supportIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.topCard?.supportCard == .antidote })

        core.playSupportCard(at: supportIndex)

        XCTAssertEqual(core.dungeonHP, 3)
        XCTAssertEqual(core.poisonDamageTicksRemaining, 0)
        XCTAssertEqual(core.poisonActionsUntilNextDamage, 0)
        XCTAssertEqual(core.moveCount, 4)
    }

    func testPanaceaOnShackleUsesShackleCostThenResolvesOneEnemyTurn() throws {
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
        XCTAssertEqual(core.moveCount, 4)
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
        XCTAssertEqual(core.moveCount, 3)
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
        let core = makeCore(mode: mode, cards: [.rayRight, .kingUpRight, .straightRight2, .straightLeft2, .straightDown2])

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
        XCTAssertNil(library.dungeon(with: "patrol-tower"))
        XCTAssertNil(library.dungeon(with: "key-door-tower"))
        XCTAssertNil(library.dungeon(with: "warp-tower"))
        XCTAssertNil(library.dungeon(with: "trap-tower"))
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
            "暗闇の遠回り",
            "暗闇の射線",
            "暗闇の前哨",
            "第二関門"
        ])
        for floorIndex in 0..<10 {
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
        XCTAssertEqual(tower.floors[19].rewardMoveCardsAfterClear, [])
        XCTAssertTrue(tower.canAdvanceWithinRun(afterFloorIndex: 9))
        XCTAssertTrue(tower.canAdvanceWithinRun(afterFloorIndex: 10))
    }

    func testGrowthTowerAddsDarknessOnlyToLateFloors() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let darknessFloorIDs = Set(tower.floors.filter(\.isDarknessEnabled).map(\.id))

        XCTAssertEqual(darknessFloorIDs, ["growth-17", "growth-18", "growth-19"])
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
                case .lavaTile(let lavaPoints, _):
                    hasDamageTrap = true
                    points.append(contentsOf: lavaPoints)
                case .brittleFloor(let brittlePoints):
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

    func testHealingTilesAppearOnlyInGrowthTowerAtSparseFixedFloors() throws {
        let growthTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let allTowers = DungeonLibrary.shared.dungeons

        let healingFloors = growthTower.floors.enumerated().compactMap { index, floor -> (Int, Set<GridPoint>)? in
            let points = floor.hazards.reduce(into: Set<GridPoint>()) { result, hazard in
                if case .healingTile(let healingPoints, let amount) = hazard {
                    XCTAssertEqual(amount, 1)
                    result.formUnion(healingPoints)
                }
            }
            return points.isEmpty ? nil : (index + 1, points)
        }

        XCTAssertEqual(healingFloors.map(\.0), [6, 12, 16, 19])
        XCTAssertEqual(healingFloors.reduce(0) { $0 + $1.1.count }, 4)

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
            spawn: GridPoint(x: 2, y: 3),
            exit: GridPoint(x: 8, y: 8),
            hp: 3,
            turnLimit: 6,
            enemies: [patrol],
            allowsBasicOrthogonalMove: true
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



    func testRoguelikeTowerDefinitionsStayInsideBoardAndExposeMixedGimmicks() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))
        var hasWarp = false
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
                case .lavaTile(let lavaPoints, let damage):
                    hasDamageTrap = true
                    XCTAssertEqual(damage, 1)
                    points.append(contentsOf: lavaPoints)
                case .brittleFloor(let brittlePoints):
                    hasBrittleFloor = true
                    points.append(contentsOf: brittlePoints)
                case .healingTile(let healingPoints, _):
                    points.append(contentsOf: healingPoints)
                }
            }
            for warpPoints in floor.warpTilePairs.values {
                hasWarp = true
                XCTAssertGreaterThanOrEqual(warpPoints.count, 2)
                points.append(contentsOf: warpPoints)
            }

            XCTAssertTrue(
                points.allSatisfy { $0.isInside(boardSize: floor.boardSize) },
                "\(floor.title) の配置はすべて 9×9 盤面内に収める必要があります"
            )
        }

        XCTAssertTrue(hasWarp)
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

        let secondCore = makeCore(
            mode: tower.floors[1].makeGameMode(
                dungeonID: tower.id,
                difficulty: tower.difficulty
            )
        )
        playBasicMove(to: GridPoint(x: 1, y: 4), in: secondCore)
        for destination in [
            GridPoint(x: 1, y: 5),
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
            playBasicMove(to: destination, in: secondCore)
        }
        XCTAssertEqual(secondCore.progress, .cleared)
        XCTAssertEqual(secondCore.dungeonHP, 3)

        let thirdCore = makeCore(
            mode: tower.floors[2].makeGameMode(
                dungeonID: tower.id,
                difficulty: tower.difficulty
            )
        )
        playBasicMove(to: GridPoint(x: 0, y: 1), in: thirdCore)
        playMove(to: GridPoint(x: 8, y: 1), in: thirdCore)
        for destination in [
            GridPoint(x: 6, y: 7),
            GridPoint(x: 6, y: 8),
            GridPoint(x: 7, y: 8),
            GridPoint(x: 8, y: 8)
        ] {
            playBasicMove(to: destination, in: thirdCore)
        }
        XCTAssertEqual(thirdCore.progress, .cleared)
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

                for enemy in resolvedFloor.enemies {
                    if case .patrol(let path) = enemy.behavior {
                        XCTAssertTrue(isOrthogonalStepPath(path), "\(resolvedFloor.title) の巡回路は上下左右1マス連続にします")
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
            XCTAssertEqual(resolvedFloors[10].spawnPoint, tower.floors[10].spawnPoint)
            for floorIndex in resolvedFloors.indices.dropLast() where floorIndex + 1 != 10 {
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

    func testWarpedHourglassReducesFloorPickupUsesToMinimumOne() throws {
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
        XCTAssertTrue(core.dungeonInventoryEntries.contains(DungeonInventoryEntry(card: .straightRight2, rewardUses: 2)))
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

    func testGrowthTowerRemedySupportPoolsStartInMiddleFloors() {
        let middlePickupSupports = supportPoolCards(floorIndex: 5, context: .floorPickup)
        let middleRewardSupports = supportPoolCards(floorIndex: 5, context: .clearReward)
        let laterPickupSupports = supportPoolCards(floorIndex: 10, context: .floorPickup)
        let laterRewardSupports = supportPoolCards(floorIndex: 10, context: .clearReward)

        XCTAssertTrue(middlePickupSupports.contains(.antidote))
        XCTAssertTrue(middleRewardSupports.contains(.antidote))
        XCTAssertFalse(middlePickupSupports.contains(.panacea))
        XCTAssertFalse(middleRewardSupports.contains(.panacea))
        XCTAssertTrue(laterPickupSupports.contains(.antidote))
        XCTAssertTrue(laterPickupSupports.contains(.panacea))
        XCTAssertTrue(laterPickupSupports.contains(.darknessSpell))
        XCTAssertTrue(laterPickupSupports.contains(.railBreakSpell))
        XCTAssertTrue(laterRewardSupports.contains(.antidote))
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

        playBasicMove(to: GridPoint(x: 1, y: 1), in: core)

        XCTAssertEqual(
            core.dungeonInventoryEntries,
            [DungeonInventoryEntry(card: .straightUp2, rewardUses: 1)]
        )
        XCTAssertFalse(core.activeDungeonCardPickups.contains { $0.point == GridPoint(x: 1, y: 1) })

        playMove(to: GridPoint(x: 1, y: 3), in: core)

        XCTAssertFalse(core.dungeonInventoryEntries.contains { $0.card == .straightUp2 })
        XCTAssertTrue(core.dungeonInventoryEntries.contains { $0.card == .straightRight2 && $0.rewardUses == 1 && $0.pickupUses == 0 })
    }

    func testDungeonResumeSnapshotRestoresCurrentFloorState() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let mode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower))
        let core = makeCore(mode: mode)

        playBasicMove(to: GridPoint(x: 1, y: 1), in: core)
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
                DungeonInventoryEntry(card: .rayRight, rewardUses: 2)
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
            let core = makeCore(mode: mode, cards: [.kingUpRight, .straightRight2, .straightDown2, .straightLeft2, .straightRight2])

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
        playBasicMove(to: GridPoint(x: 1, y: 1), in: firstCore)
        XCTAssertTrue(firstCore.dungeonInventoryEntries.contains { $0.card == .straightUp2 && $0.rewardUses == 1 && $0.pickupUses == 0 })
        playMove(to: GridPoint(x: 1, y: 3), in: firstCore)
        XCTAssertTrue(firstCore.dungeonInventoryEntries.contains { $0.card == .straightRight2 && $0.rewardUses == 1 && $0.pickupUses == 0 })
        playMove(to: GridPoint(x: 3, y: 3), in: firstCore)
        playBasicMove(to: GridPoint(x: 3, y: 4), in: firstCore)
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
        assertTurnLimitSlack(for: tower.floors[1], after: secondCore)

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

    func testCollapsedBrittleFloorStillBlocksEnemySightAndMovement() {
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

        XCTAssertFalse(core.enemyDangerPoints.contains(holePoint))
        XCTAssertFalse(core.enemyDangerPoints.contains(GridPoint(x: 1, y: 3)))
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
            turnLimit: 8,
            allowsBasicOrthogonalMove: false
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

    func testBasicOrthogonalMoveCanClearExitAndTriggerFatigueRules() {
        let clearMode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 0, y: 1),
            turnLimit: 1,
            allowsBasicOrthogonalMove: true
        )
        let clearCore = makeCore(mode: clearMode, cards: [.straightRight2, .straightLeft2, .rayRight])
        playBasicMove(to: GridPoint(x: 0, y: 1), in: clearCore)
        XCTAssertEqual(clearCore.progress, .cleared)

        let fatigueMode = makeDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            turnLimit: 1,
            allowsBasicOrthogonalMove: true
        )
        let fatigueCore = makeCore(mode: fatigueMode, cards: [.straightRight2, .straightLeft2, .rayRight])
        playBasicMove(to: GridPoint(x: 0, y: 1), in: fatigueCore)
        XCTAssertEqual(fatigueCore.progress, .playing)
        XCTAssertEqual(fatigueCore.remainingDungeonTurns, 0)

        playBasicMove(to: GridPoint(x: 0, y: 2), in: fatigueCore)
        XCTAssertEqual(fatigueCore.progress, .playing)
        XCTAssertEqual(fatigueCore.dungeonHP, 2)
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
                    difficulty: .growth,
                    failureRule: DungeonFailureRule(initialHP: hp, turnLimit: turnLimit),
                    enemies: enemies,
                    hazards: hazards,
                    exitLock: exitLock,
                    allowsBasicOrthogonalMove: allowsBasicOrthogonalMove,
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
            case .brittleFloor(let points):
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
            case .brittleFloor(let hazardPoints):
                points.formUnion(hazardPoints)
            case .damageTrap(let hazardPoints, _):
                points.formUnion(hazardPoints)
            case .lavaTile(let hazardPoints, _):
                points.formUnion(hazardPoints)
            case .healingTile(let hazardPoints, _):
                points.formUnion(hazardPoints)
            }
        }
        return points
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
        }
    }

    private func isOrthogonalStepPath(_ path: [GridPoint]) -> Bool {
        guard path.count > 1 else { return true }
        return zip(path, path.dropFirst()).allSatisfy { before, after in
            manhattanDistance(from: before, to: after) == 1
        }
    }

    private func majorGrowthTowerGimmickOverlaps(for floor: DungeonFloorDefinition) -> [String] {
        var occupantsByPoint: [GridPoint: [String]] = [:]

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
                for point in Set(path) {
                    add("巡回:\(enemy.id)", at: point)
                }
            case .chaser, .guardPost, .marker, .watcher, .rotatingWatcher:
                add("敵:\(enemy.id)", at: enemy.position)
            }
        }
        for point in floor.impassableTilePoints {
            add("固定障害物", at: point)
        }
        for hazard in floor.hazards {
            switch hazard {
            case .brittleFloor(let points):
                for point in points {
                    add("ひび割れ床", at: point)
                }
            case .damageTrap(let points, _):
                for point in points {
                    add("ダメージ罠", at: point)
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
            case .brittleFloor(let points):
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
            case .lavaTile(let points, _):
                blocked.formUnion(points)
            case .healingTile(let points, _):
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
}
