import XCTest
@testable import Game

/// GameCore のうち、塔攻略モードでも直接使う薄い結合点を検証するテスト。
final class GameCoreTests: XCTestCase {
    func testDungeonInventoryDirectionSortKeepsSupportCardsAfterMoveCards() throws {
        let mode = makeInventoryDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4)
        )
        let core = GameCore(mode: mode)

        XCTAssertTrue(core.addDungeonInventoryCardForTesting(.straightRight2, pickupUses: 1))
        XCTAssertTrue(core.addDungeonInventorySupportCardForTesting(.refillEmptySlots, rewardUses: 1))
        XCTAssertTrue(core.addDungeonInventoryCardForTesting(.straightUp2, pickupUses: 1))
        let supportStackID = try XCTUnwrap(
            core.handStacks.first { $0.representativeSupport == .refillEmptySlots }?.id
        )

        core.updateHandOrderingStrategy(.directionSorted)

        XCTAssertEqual(
            core.handStacks.compactMap(\.representativePlayable),
            [
                .move(.straightUp2),
                .move(.straightRight2),
                .support(.refillEmptySlots)
            ]
        )
        XCTAssertEqual(
            core.dungeonInventoryEntries.map(\.playable),
            [
                .move(.straightUp2),
                .move(.straightRight2),
                .support(.refillEmptySlots)
            ]
        )
        XCTAssertEqual(
            core.handStacks.first { $0.representativeSupport == .refillEmptySlots }?.id,
            supportStackID
        )
    }

    func testAvailableMovesSkipsImpassableDestinationsInDungeonInventoryMode() {
        let impassablePoint = GridPoint(x: 3, y: 2)
        let mode = makeInventoryDungeonMode(
            spawn: GridPoint(x: 2, y: 2),
            exit: GridPoint(x: 4, y: 4),
            impassableTilePoints: [impassablePoint]
        )
        let core = GameCore(mode: mode)

        XCTAssertTrue(core.addDungeonInventoryCardForTesting(.straightRight2, pickupUses: 1))
        XCTAssertTrue(core.addDungeonInventoryCardForTesting(.kingUpRight, pickupUses: 1))

        let destinations = Set(core.availableMoves().map(\.destination))
        XCTAssertFalse(destinations.contains(impassablePoint), "塔攻略の移動候補に通行不可マスを含めてはいけません")
        XCTAssertTrue(destinations.contains(GridPoint(x: 3, y: 3)), "通行可能なカード移動候補まで消えてはいけません")
    }

    func testPlayCardAppliesWarpEffectInDungeonInventoryMode() {
        let warpSource = GridPoint(x: 3, y: 2)
        let warpDestination = GridPoint(x: 1, y: 4)
        let mode = makeInventoryDungeonMode(
            spawn: GridPoint(x: 1, y: 2),
            exit: GridPoint(x: 4, y: 4),
            warpTilePairs: ["test_warp": [warpSource, warpDestination]]
        )
        let core = GameCore(mode: mode)

        XCTAssertTrue(core.addDungeonInventoryCardForTesting(.straightRight2, pickupUses: 1))
        guard let move = core.availableMoves().first(where: { $0.moveCard == .straightRight2 }) else {
            XCTFail("右方向カードが候補に含まれていません")
            return
        }

        core.playCard(using: move)

        XCTAssertEqual(core.current, warpDestination, "ワープ床を踏んだ塔カード移動は最終位置をワープ先へ更新します")
        XCTAssertTrue(core.board.isVisited(warpSource), "ワープ元マスも踏破扱いにします")
        XCTAssertTrue(core.board.isVisited(warpDestination), "ワープ先マスも踏破扱いにします")
    }

    func testPlayCardAppliesBlastTileFixedDirectionUntilObstacle() throws {
        let blastPoint = GridPoint(x: 2, y: 1)
        let obstacle = GridPoint(x: 2, y: 3)
        let mode = makeInventoryDungeonMode(
            spawn: GridPoint(x: 0, y: 1),
            exit: GridPoint(x: 4, y: 4),
            impassableTilePoints: [obstacle],
            tileEffectOverrides: [blastPoint: .blast(direction: MoveVector(dx: 0, dy: 1))]
        )
        let core = GameCore(mode: mode)
        XCTAssertTrue(core.addDungeonInventoryCardForTesting(.straightRight2, pickupUses: 1))

        let move = try XCTUnwrap(core.availableMoves().first { $0.moveCard == .straightRight2 })
        core.playCard(using: move)

        XCTAssertEqual(core.current, GridPoint(x: 2, y: 2), "進入方向ではなく床に表示された方向へ吹き飛び、障害物直前で止まります")
        XCTAssertEqual(core.lastMovementResolution?.path, [blastPoint, GridPoint(x: 2, y: 2)])
    }

    func testBlastTileDoesNotMoveWhenNextTileIsBlocked() throws {
        let blastPoint = GridPoint(x: 2, y: 1)
        let obstacle = GridPoint(x: 3, y: 1)
        let mode = makeInventoryDungeonMode(
            spawn: GridPoint(x: 0, y: 1),
            exit: GridPoint(x: 4, y: 4),
            impassableTilePoints: [obstacle],
            tileEffectOverrides: [blastPoint: .blast(direction: MoveVector(dx: 1, dy: 0))]
        )
        let core = GameCore(mode: mode)
        XCTAssertTrue(core.addDungeonInventoryCardForTesting(.straightRight2, pickupUses: 1))

        let move = try XCTUnwrap(core.availableMoves().first { $0.moveCard == .straightRight2 })
        core.playCard(using: move)

        XCTAssertEqual(core.current, blastPoint)
        XCTAssertEqual(core.lastMovementResolution?.path, [blastPoint])
    }

    func testBasicOrthogonalMoveAppliesBlastTile() throws {
        let blastPoint = GridPoint(x: 1, y: 0)
        let mode = makeInventoryDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            tileEffectOverrides: [blastPoint: .blast(direction: MoveVector(dx: 1, dy: 0))],
            allowsBasicOrthogonalMove: true
        )
        let core = GameCore(mode: mode)

        let move = try XCTUnwrap(core.availableBasicOrthogonalMoves().first { $0.destination == blastPoint })
        core.playBasicOrthogonalMove(using: move)

        XCTAssertEqual(core.current, GridPoint(x: 4, y: 0))
        XCTAssertEqual(core.lastMovementResolution?.path, [
            GridPoint(x: 1, y: 0),
            GridPoint(x: 2, y: 0),
            GridPoint(x: 3, y: 0),
            GridPoint(x: 4, y: 0),
        ])
    }

    func testDungeonTurnLimitAppliesFatigueInsteadOfImmediateFailure() {
        let mode = makeInventoryDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            allowsBasicOrthogonalMove: true,
            turnLimit: 2
        )
        let core = GameCore(mode: mode)

        playBasicMove(to: GridPoint(x: 1, y: 0), in: core)
        playBasicMove(to: GridPoint(x: 2, y: 0), in: core)

        XCTAssertEqual(core.progress, .playing)
        XCTAssertEqual(core.dungeonHP, 3)
        XCTAssertEqual(core.remainingDungeonTurns, 0)

        playBasicMove(to: GridPoint(x: 3, y: 0), in: core)

        XCTAssertEqual(core.progress, .playing)
        XCTAssertEqual(core.dungeonHP, 2, "上限超過1手目は即失敗ではなく疲労でHPを1減らします")

        playBasicMove(to: GridPoint(x: 4, y: 0), in: core)
        playBasicMove(to: GridPoint(x: 4, y: 1), in: core)

        XCTAssertEqual(core.progress, .playing)
        XCTAssertEqual(core.dungeonHP, 2, "超過2手目と3手目は追加疲労ダメージなしです")

        playBasicMove(to: GridPoint(x: 3, y: 1), in: core)

        XCTAssertEqual(core.progress, .playing)
        XCTAssertEqual(core.dungeonHP, 1, "超過4手目で次の疲労ダメージが入ります")
    }

    func testDungeonFatigueFailsOnlyWhenHPReachesZero() {
        let mode = makeInventoryDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            allowsBasicOrthogonalMove: true,
            turnLimit: 1,
            carriedHP: 1
        )
        let core = GameCore(mode: mode)

        playBasicMove(to: GridPoint(x: 1, y: 0), in: core)
        XCTAssertEqual(core.progress, .playing)
        XCTAssertEqual(core.dungeonHP, 1)

        playBasicMove(to: GridPoint(x: 2, y: 0), in: core)

        XCTAssertEqual(core.progress, .failed)
        XCTAssertEqual(core.dungeonHP, 0)
    }

    func testDungeonFatigueBypassesDamageBarrier() throws {
        let mode = makeInventoryDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            allowsBasicOrthogonalMove: true,
            turnLimit: 1
        )
        let core = GameCore(mode: mode)
        XCTAssertTrue(core.addDungeonInventorySupportCardForTesting(.barrierSpell, rewardUses: 1))
        let supportIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.topCard?.supportCard == .barrierSpell })

        core.playSupportCard(at: supportIndex)
        XCTAssertEqual(core.moveCount, 1)
        XCTAssertEqual(core.damageBarrierTurnsRemaining, 2)

        playBasicMove(to: GridPoint(x: 1, y: 0), in: core)

        XCTAssertEqual(core.progress, .playing)
        XCTAssertEqual(core.dungeonHP, 2, "疲労ダメージは障壁では防げません")
        XCTAssertGreaterThan(core.damageBarrierTurnsRemaining, 0)
    }

    func testDungeonExitTakesPriorityOverOvertimeFatigue() {
        let mode = makeInventoryDungeonMode(
            spawn: GridPoint(x: 2, y: 4),
            exit: GridPoint(x: 4, y: 4),
            allowsBasicOrthogonalMove: true,
            turnLimit: 1,
            carriedHP: 1
        )
        let core = GameCore(mode: mode)

        playBasicMove(to: GridPoint(x: 3, y: 4), in: core)
        playBasicMove(to: GridPoint(x: 4, y: 4), in: core)

        XCTAssertEqual(core.progress, .cleared)
        XCTAssertEqual(core.dungeonHP, 1)
    }

    func testBlastPathDefeatsEnemiesAndCollectsPickupsAlongTheWay() throws {
        let blastPoint = GridPoint(x: 2, y: 0)
        let enemy = EnemyDefinition(
            id: "blast-path-enemy",
            name: "番兵",
            position: GridPoint(x: 3, y: 0),
            behavior: .guardPost
        )
        let pickup = DungeonCardPickupDefinition(
            id: "blast-path-pickup",
            point: GridPoint(x: 4, y: 0),
            card: .kingUpRight
        )
        let mode = makeInventoryDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            tileEffectOverrides: [blastPoint: .blast(direction: MoveVector(dx: 1, dy: 0))],
            cardPickups: [pickup],
            enemies: [enemy]
        )
        let core = GameCore(mode: mode)
        XCTAssertTrue(core.addDungeonInventoryCardForTesting(.straightRight2, pickupUses: 1))

        let move = try XCTUnwrap(core.availableMoves().first { $0.moveCard == .straightRight2 })
        core.playCard(using: move)

        XCTAssertFalse(core.enemyStates.contains { $0.id == enemy.id })
        XCTAssertFalse(core.activeDungeonCardPickups.contains { $0.id == pickup.id })
        XCTAssertTrue(core.dungeonInventoryEntries.contains { $0.playable == pickup.playable })
    }

    func testDungeonInventoryStacksDuplicateCardsAndRejectsNewCardAtNineKindsWhenBasicMoveUsesTenthSlot() {
        let mode = makeInventoryDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            allowsBasicOrthogonalMove: true
        )
        let core = GameCore(mode: mode)
        let nineCards = Array(MoveCard.allCases.prefix(9))
        let tenth = MoveCard.allCases[9]

        for card in nineCards {
            XCTAssertTrue(core.addDungeonInventoryCardForTesting(card, pickupUses: 1))
        }

        XCTAssertEqual(core.dungeonInventoryEntries.count, 9)
        XCTAssertFalse(core.addDungeonInventoryCardForTesting(tenth, pickupUses: 1), "塔攻略の通常カード種類数は基本移動固定枠を除く9種類までです")
        XCTAssertTrue(core.addDungeonInventoryCardForTesting(nineCards[0], pickupUses: 1), "同じカードは種類枠を増やさず回数として積めます")
        XCTAssertEqual(core.dungeonInventoryEntries.count, 9)
        XCTAssertEqual(core.dungeonInventoryEntries.first { $0.card == nineCards[0] }?.rewardUses, 2)
    }

    func testHandleTapPrefersBasicOrthogonalMoveOverMatchingCardMove() {
        let origin = GridPoint(x: 0, y: 0)
        let destination = GridPoint(x: 1, y: 0)
        let blocker = GridPoint(x: 2, y: 0)
        let mode = makeInventoryDungeonMode(
            spawn: origin,
            exit: GridPoint(x: 4, y: 4),
            impassableTilePoints: [blocker],
            allowsBasicOrthogonalMove: true
        )
        let core = GameCore(mode: mode)

        XCTAssertTrue(core.addDungeonInventoryCardForTesting(.rayRight, pickupUses: 1))
        XCTAssertTrue(
            core.availableMoves().contains { $0.moveCard == .rayRight && $0.destination == destination },
            "レイ型カードが基本移動と同じマスへ届く前提が崩れています"
        )
        XCTAssertTrue(
            core.availableBasicOrthogonalMoves().contains { $0.destination == destination },
            "基本移動で目的地へ届く前提が崩れています"
        )

        #if canImport(SpriteKit)
        core.handleTap(at: destination)
        XCTAssertNil(core.boardTapPlayRequest, "基本移動で届くマスではカード使用リクエストを出さない想定です")
        XCTAssertEqual(
            core.boardTapBasicMoveRequest?.move.destination,
            destination,
            "基本移動リクエストの目的地が想定と異なります"
        )
        #endif
    }

    func testResolvedMoveForBoardTapDoesNotAutoPreferSingleVectorCard() {
        let origin = GridPoint(x: 0, y: 0)
        let destination = GridPoint(x: 2, y: 0)
        let blocker = GridPoint(x: 3, y: 0)
        let mode = makeInventoryDungeonMode(
            spawn: origin,
            exit: GridPoint(x: 4, y: 4),
            impassableTilePoints: [blocker]
        )
        let core = GameCore(mode: mode)

        XCTAssertTrue(core.addDungeonInventoryCardForTesting(.rayRight, pickupUses: 1))
        XCTAssertTrue(core.addDungeonInventoryCardForTesting(.straightRight2, pickupUses: 1))

        let destinationMoves = core.availableMoves().filter { $0.destination == destination }
        XCTAssertEqual(Set(destinationMoves.map(\.stackID)).count, 2, "異なるカードスタックの競合前提が崩れています")

        let resolved = core.resolvedMoveForBoardTap(at: destination)
        XCTAssertEqual(resolved?.moveCard, .rayRight, "単一方向カードを自動優先せず、代表候補だけを返す想定です")
    }

    func testRefillSupportCardFillsDungeonEmptySlotsWithTemporaryMoveCards() throws {
        let dungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let runState = DungeonRunState(
            dungeonID: dungeon.id,
            currentFloorIndex: 10,
            carriedHP: 3,
            rewardInventoryEntries: [DungeonInventoryEntry(support: .refillEmptySlots, rewardUses: 1)],
            cardVariationSeed: 42
        )
        let floor = try XCTUnwrap(dungeon.resolvedFloor(at: 10, runState: runState))
        let core = GameCore(mode: floor.makeGameMode(dungeonID: dungeon.id, difficulty: dungeon.difficulty, runState: runState))
        let supportIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.topCard?.supportCard == .refillEmptySlots })

        core.playSupportCard(at: supportIndex)

        XCTAssertFalse(core.dungeonInventoryEntries.contains { $0.supportCard == .refillEmptySlots })
        XCTAssertEqual(core.dungeonInventoryEntries.count, 9)
        XCTAssertTrue(core.dungeonInventoryEntries.allSatisfy { $0.rewardUses == 1 && $0.pickupUses == 0 })
        let refilledMoves = core.dungeonInventoryEntries.compactMap(\.moveCard)
        XCTAssertEqual(Set(refilledMoves).count, 9)
        XCTAssertTrue(Set(refilledMoves).isSubset(of: Set(MoveCard.allCases)))
    }

    func testRefillSupportRewardCarriesOnlyOneUse() {
        let runState = DungeonRunState(dungeonID: "growth-tower", carriedHP: 3)

        let advanced = runState.advancedToNextFloor(
            carryoverHP: 3,
            currentFloorMoveCount: 4,
            rewardSelection: .addSupport(.refillEmptySlots),
            rewardAddUses: 4
        )

        XCTAssertEqual(
            advanced.rewardInventoryEntries,
            [DungeonInventoryEntry(support: .refillEmptySlots, rewardUses: 1)]
        )
    }

    func testAnnihilationSpellClearsAllEnemiesWithoutEnemyTurn() throws {
        let enemies = [
            EnemyDefinition(
                id: "guard",
                name: "番兵",
                position: GridPoint(x: 2, y: 1),
                behavior: .guardPost
            ),
            EnemyDefinition(
                id: "patrol",
                name: "巡回兵",
                position: GridPoint(x: 3, y: 3),
                behavior: .patrol(path: [
                    GridPoint(x: 3, y: 3),
                    GridPoint(x: 3, y: 4)
                ])
            ),
            EnemyDefinition(
                id: "marker",
                name: "メテオ兵",
                position: GridPoint(x: 4, y: 3),
                behavior: .marker(directions: [], range: 2)
            )
        ]
        let mode = makeInventoryDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            enemies: enemies
        )
        let core = GameCore(mode: mode)
        XCTAssertTrue(core.addDungeonInventorySupportCardForTesting(.annihilationSpell, rewardUses: 1))
        let supportIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.topCard?.supportCard == .annihilationSpell })

        XCTAssertTrue(core.isSupportCardUsable(in: core.handStacks[supportIndex]))
        XCTAssertFalse(core.enemyDangerPoints.isEmpty)
        XCTAssertFalse(core.enemyWarningPoints.isEmpty)
        XCTAssertFalse(core.enemyPatrolMovementPreviews.isEmpty)

        core.playSupportCard(at: supportIndex)

        XCTAssertTrue(core.enemyStates.isEmpty)
        XCTAssertTrue(core.enemyDangerPoints.isEmpty)
        XCTAssertTrue(core.enemyWarningPoints.isEmpty)
        XCTAssertTrue(core.enemyPatrolMovementPreviews.isEmpty)
        XCTAssertTrue(core.enemyChaserMovementPreviews.isEmpty)
        XCTAssertFalse(core.dungeonInventoryEntries.contains { $0.supportCard == .annihilationSpell })
        XCTAssertEqual(core.moveCount, 1)
        XCTAssertNil(core.dungeonEnemyTurnEvent)
    }

    func testFreezeSpellStopsThreeEnemyTurnsAndHidesThreats() throws {
        let enemies = [
            EnemyDefinition(
                id: "patrol",
                name: "巡回兵",
                position: GridPoint(x: 4, y: 1),
                behavior: .patrol(path: [
                    GridPoint(x: 4, y: 1),
                    GridPoint(x: 4, y: 2)
                ])
            ),
            EnemyDefinition(
                id: "marker",
                name: "メテオ兵",
                position: GridPoint(x: 3, y: 3),
                behavior: .marker(directions: [], range: 2)
            )
        ]
        let mode = makeInventoryDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            allowsBasicOrthogonalMove: true,
            enemies: enemies
        )
        let core = GameCore(mode: mode)
        XCTAssertTrue(core.addDungeonInventorySupportCardForTesting(.freezeSpell, rewardUses: 1))
        let supportIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.topCard?.supportCard == .freezeSpell })

        XCTAssertFalse(core.enemyDangerPoints.isEmpty)
        XCTAssertFalse(core.enemyWarningPoints.isEmpty)
        XCTAssertFalse(core.enemyPatrolMovementPreviews.isEmpty)

        core.playSupportCard(at: supportIndex)

        XCTAssertEqual(core.enemyFreezeTurnsRemaining, 2)
        XCTAssertEqual(core.enemyStates.first { $0.id == "patrol" }?.position, GridPoint(x: 4, y: 1))
        XCTAssertTrue(core.enemyDangerPoints.isEmpty)
        XCTAssertTrue(core.enemyWarningPoints.isEmpty)
        XCTAssertTrue(core.enemyPatrolMovementPreviews.isEmpty)
        XCTAssertTrue(core.enemyChaserMovementPreviews.isEmpty)
        XCTAssertNil(core.dungeonEnemyTurnEvent)

        let firstBasic = try XCTUnwrap(core.availableBasicOrthogonalMoves().first { $0.destination == GridPoint(x: 1, y: 0) })
        core.playBasicOrthogonalMove(using: firstBasic)

        XCTAssertEqual(core.enemyFreezeTurnsRemaining, 1)
        XCTAssertEqual(core.enemyStates.first { $0.id == "patrol" }?.position, GridPoint(x: 4, y: 1))
        XCTAssertTrue(core.enemyDangerPoints.isEmpty)
        XCTAssertTrue(core.enemyWarningPoints.isEmpty)

        let secondBasic = try XCTUnwrap(core.availableBasicOrthogonalMoves().first { $0.destination == GridPoint(x: 2, y: 0) })
        core.playBasicOrthogonalMove(using: secondBasic)

        XCTAssertEqual(core.enemyFreezeTurnsRemaining, 0)
        XCTAssertEqual(core.enemyStates.first { $0.id == "patrol" }?.position, GridPoint(x: 4, y: 1))
        XCTAssertFalse(core.enemyDangerPoints.isEmpty)
        XCTAssertFalse(core.enemyWarningPoints.isEmpty)
    }

    func testFreezeSpellAllowsEnemyTurnAfterThirdStoppedTurn() throws {
        let patrol = EnemyDefinition(
            id: "patrol",
            name: "巡回兵",
            position: GridPoint(x: 4, y: 1),
            behavior: .patrol(path: [
                GridPoint(x: 4, y: 1),
                GridPoint(x: 4, y: 2)
            ])
        )
        let mode = makeInventoryDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            allowsBasicOrthogonalMove: true,
            enemies: [patrol]
        )
        let core = GameCore(mode: mode)
        XCTAssertTrue(core.addDungeonInventorySupportCardForTesting(.freezeSpell, rewardUses: 1))
        let supportIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.topCard?.supportCard == .freezeSpell })

        core.playSupportCard(at: supportIndex)
        for destination in [GridPoint(x: 1, y: 0), GridPoint(x: 2, y: 0)] {
            let move = try XCTUnwrap(core.availableBasicOrthogonalMoves().first { $0.destination == destination })
            core.playBasicOrthogonalMove(using: move)
        }
        XCTAssertEqual(core.enemyFreezeTurnsRemaining, 0)
        XCTAssertEqual(core.enemyStates.first?.position, GridPoint(x: 4, y: 1))

        let normalTurnMove = try XCTUnwrap(core.availableBasicOrthogonalMoves().first { $0.destination == GridPoint(x: 3, y: 0) })
        core.playBasicOrthogonalMove(using: normalTurnMove)

        XCTAssertEqual(core.enemyStates.first?.position, GridPoint(x: 4, y: 2))
        XCTAssertNotNil(core.dungeonEnemyTurnEvent)
    }

    func testBarrierSpellNegatesDamageForThreeTurnsThenDamageReturns() throws {
        let guardEnemy = EnemyDefinition(
            id: "guard",
            name: "番兵",
            position: GridPoint(x: 2, y: 2),
            behavior: .guardPost
        )
        let mode = makeInventoryDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            allowsBasicOrthogonalMove: true,
            enemies: [guardEnemy],
            hazards: [
                .damageTrap(points: [GridPoint(x: 1, y: 0)], damage: 1),
                .lavaTile(points: [GridPoint(x: 2, y: 0)], damage: 1)
            ]
        )
        let core = GameCore(mode: mode)
        XCTAssertTrue(core.addDungeonInventorySupportCardForTesting(.barrierSpell, rewardUses: 1))
        let supportIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.topCard?.supportCard == .barrierSpell })

        core.playSupportCard(at: supportIndex)
        XCTAssertEqual(core.dungeonHP, 3)
        XCTAssertEqual(core.damageBarrierTurnsRemaining, 2)

        let trapMove = try XCTUnwrap(core.availableBasicOrthogonalMoves().first { $0.destination == GridPoint(x: 1, y: 0) })
        core.playBasicOrthogonalMove(using: trapMove)
        XCTAssertEqual(core.dungeonHP, 3)
        XCTAssertEqual(core.damageBarrierTurnsRemaining, 1)

        let lavaMove = try XCTUnwrap(core.availableBasicOrthogonalMoves().first { $0.destination == GridPoint(x: 2, y: 0) })
        core.playBasicOrthogonalMove(using: lavaMove)
        XCTAssertEqual(core.dungeonHP, 3)
        XCTAssertEqual(core.damageBarrierTurnsRemaining, 0)

        let dangerMove = try XCTUnwrap(core.availableBasicOrthogonalMoves().first { $0.destination == GridPoint(x: 2, y: 1) })
        core.playBasicOrthogonalMove(using: dangerMove)
        XCTAssertEqual(core.dungeonHP, 2)
    }

    func testBarrierSpellProtectsMarkerDamageWithoutConsumingMitigation() throws {
        let marker = EnemyDefinition(
            id: "marker",
            name: "メテオ兵",
            position: GridPoint(x: 4, y: 4),
            behavior: .marker(directions: [], range: 80)
        )
        let runState = DungeonRunState(
            dungeonID: "test-dungeon",
            carriedHP: 3,
            markerDamageMitigationsRemaining: 1
        )
        let mode = makeInventoryDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 0),
            allowsBasicOrthogonalMove: true,
            enemies: [marker],
            runState: runState
        )
        let core = GameCore(mode: mode)
        XCTAssertTrue(core.addDungeonInventorySupportCardForTesting(.barrierSpell, rewardUses: 1))
        let supportIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.topCard?.supportCard == .barrierSpell })

        core.playSupportCard(at: supportIndex)
        let warningPoints = core.enemyWarningPoints
        let warningMove = try XCTUnwrap(core.availableBasicOrthogonalMoves().first { warningPoints.contains($0.destination) })
        core.playBasicOrthogonalMove(using: warningMove)

        XCTAssertEqual(core.dungeonHP, 3)
        XCTAssertEqual(core.markerDamageMitigationsRemaining, 1)
        XCTAssertEqual(core.damageBarrierTurnsRemaining, 1)
    }

    func testDarknessSpellSuppressesWatcherLasersForFloorOnly() throws {
        let watcher = EnemyDefinition(
            id: "watcher",
            name: "見張り",
            position: GridPoint(x: 2, y: 1),
            behavior: .watcher(direction: MoveVector(dx: 0, dy: -1), range: 3)
        )
        let rotatingWatcher = EnemyDefinition(
            id: "rotating-watcher",
            name: "回転見張り",
            position: GridPoint(x: 1, y: 1),
            behavior: .rotatingWatcher(
                initialDirection: MoveVector(dx: 0, dy: 1),
                rotationDirection: .clockwise,
                range: 3
            )
        )
        let guardPost = EnemyDefinition(
            id: "guard",
            name: "番兵",
            position: GridPoint(x: 4, y: 1),
            behavior: .guardPost
        )
        let marker = EnemyDefinition(
            id: "marker",
            name: "メテオ兵",
            position: GridPoint(x: 4, y: 4),
            behavior: .marker(directions: [], range: 2)
        )
        let watcherDanger = GridPoint(x: 2, y: 0)
        let guardDanger = GridPoint(x: 4, y: 0)
        let mode = makeInventoryDungeonMode(
            spawn: watcherDanger,
            exit: GridPoint(x: 0, y: 4),
            allowsBasicOrthogonalMove: true,
            enemies: [watcher, rotatingWatcher, guardPost, marker]
        )
        let core = GameCore(mode: mode)
        XCTAssertTrue(core.addDungeonInventorySupportCardForTesting(.darknessSpell, rewardUses: 1))
        let supportIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.topCard?.supportCard == .darknessSpell })

        XCTAssertTrue(core.isSupportCardUsable(in: core.handStacks[supportIndex]))
        XCTAssertTrue(core.enemyDangerPoints.contains(watcherDanger))
        XCTAssertFalse(core.enemyWarningPoints.isEmpty)

        core.playSupportCard(at: supportIndex)

        XCTAssertTrue(core.isWatcherLaserSuppressed)
        XCTAssertEqual(core.dungeonHP, 3)
        XCTAssertEqual(core.moveCount, 1)
        XCTAssertFalse(core.dungeonInventoryEntries.contains { $0.supportCard == .darknessSpell })
        XCTAssertFalse(core.enemyDangerPoints.contains(watcherDanger))
        XCTAssertFalse(core.enemyDangerDisplayPoints.contains(watcherDanger))
        XCTAssertTrue(core.enemyDangerPoints.contains(guardDanger))
        XCTAssertFalse(core.enemyWarningPoints.isEmpty)
        XCTAssertEqual(core.enemyStates.first { $0.id == "rotating-watcher" }?.rotationIndex, 1)
        XCTAssertTrue(core.addDungeonInventorySupportCardForTesting(.darknessSpell, rewardUses: 1))
        let repeatedSupportIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.topCard?.supportCard == .darknessSpell })
        XCTAssertFalse(core.isSupportCardUsable(in: core.handStacks[repeatedSupportIndex]))
    }

    func testDarknessSpellRequiresWatcherLaserEnemyAndPersistsThroughResume() throws {
        let patrol = EnemyDefinition(
            id: "patrol",
            name: "巡回兵",
            position: GridPoint(x: 3, y: 1),
            behavior: .patrol(path: [
                GridPoint(x: 3, y: 1),
                GridPoint(x: 3, y: 2)
            ])
        )
        let watcher = EnemyDefinition(
            id: "watcher",
            name: "見張り",
            position: GridPoint(x: 2, y: 1),
            behavior: .watcher(direction: MoveVector(dx: 0, dy: -1), range: 3)
        )
        let noWatcherMode = makeInventoryDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            enemies: [patrol]
        )
        let noWatcherCore = GameCore(mode: noWatcherMode)
        XCTAssertTrue(noWatcherCore.addDungeonInventorySupportCardForTesting(.darknessSpell, rewardUses: 1))
        let unusableIndex = try XCTUnwrap(noWatcherCore.handStacks.firstIndex { $0.topCard?.supportCard == .darknessSpell })
        XCTAssertFalse(noWatcherCore.isSupportCardUsable(in: noWatcherCore.handStacks[unusableIndex]))

        let watcherMode = makeInventoryDungeonMode(
            spawn: GridPoint(x: 2, y: 0),
            exit: GridPoint(x: 4, y: 4),
            enemies: [watcher]
        )
        let core = GameCore(mode: watcherMode)
        XCTAssertTrue(core.addDungeonInventorySupportCardForTesting(.darknessSpell, rewardUses: 1))
        let supportIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.topCard?.supportCard == .darknessSpell })
        core.playSupportCard(at: supportIndex)

        let snapshot = try XCTUnwrap(core.makeDungeonResumeSnapshot())
        let data = try JSONEncoder().encode(snapshot)
        let decodedSnapshot = try JSONDecoder().decode(DungeonRunResumeSnapshot.self, from: data)
        let restoredCore = GameCore(mode: watcherMode)

        XCTAssertTrue(restoredCore.restoreDungeonResumeSnapshot(decodedSnapshot))
        XCTAssertTrue(restoredCore.isWatcherLaserSuppressed)
        XCTAssertTrue(restoredCore.enemyDangerPoints.isEmpty)
    }

    func testRailBreakSpellStopsPatrolMovementOnlyForFloor() throws {
        let patrol = EnemyDefinition(
            id: "patrol",
            name: "巡回兵",
            position: GridPoint(x: 3, y: 3),
            behavior: .patrol(path: [
                GridPoint(x: 3, y: 3),
                GridPoint(x: 3, y: 4)
            ])
        )
        let chaser = EnemyDefinition(
            id: "chaser",
            name: "追跡兵",
            position: GridPoint(x: 4, y: 0),
            behavior: .chaser
        )
        let patrolDanger = GridPoint(x: 3, y: 2)
        let mode = makeInventoryDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 0, y: 4),
            enemies: [patrol, chaser]
        )
        let core = GameCore(mode: mode)
        XCTAssertTrue(core.addDungeonInventorySupportCardForTesting(.railBreakSpell, rewardUses: 1))
        let supportIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.topCard?.supportCard == .railBreakSpell })

        XCTAssertTrue(core.isSupportCardUsable(in: core.handStacks[supportIndex]))
        XCTAssertFalse(core.enemyPatrolRailPreviews.isEmpty)
        XCTAssertFalse(core.enemyPatrolMovementPreviews.isEmpty)
        XCTAssertTrue(core.enemyDangerPoints.contains(patrolDanger))

        core.playSupportCard(at: supportIndex)

        XCTAssertTrue(core.isPatrolRailDestroyed)
        XCTAssertEqual(core.moveCount, 1)
        XCTAssertEqual(core.dungeonHP, 3)
        XCTAssertEqual(core.enemyStates.first { $0.id == "patrol" }?.position, GridPoint(x: 3, y: 3))
        XCTAssertEqual(core.enemyStates.first { $0.id == "chaser" }?.position, GridPoint(x: 3, y: 0))
        XCTAssertTrue(core.enemyPatrolRailPreviews.isEmpty)
        XCTAssertTrue(core.enemyPatrolMovementPreviews.isEmpty)
        XCTAssertFalse(core.enemyChaserMovementPreviews.isEmpty)
        XCTAssertTrue(core.enemyDangerPoints.contains(patrolDanger))
        XCTAssertFalse(core.dungeonInventoryEntries.contains { $0.supportCard == .railBreakSpell })

        XCTAssertTrue(core.addDungeonInventorySupportCardForTesting(.railBreakSpell, rewardUses: 1))
        let repeatedSupportIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.topCard?.supportCard == .railBreakSpell })
        XCTAssertFalse(core.isSupportCardUsable(in: core.handStacks[repeatedSupportIndex]))
    }

    func testRailBreakSpellRequiresPatrolEnemyAndPersistsThroughResume() throws {
        let watcher = EnemyDefinition(
            id: "watcher",
            name: "見張り",
            position: GridPoint(x: 2, y: 1),
            behavior: .watcher(direction: MoveVector(dx: 0, dy: -1), range: 3)
        )
        let patrol = EnemyDefinition(
            id: "patrol",
            name: "巡回兵",
            position: GridPoint(x: 3, y: 1),
            behavior: .patrol(path: [
                GridPoint(x: 3, y: 1),
                GridPoint(x: 3, y: 2)
            ])
        )
        let noPatrolMode = makeInventoryDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            enemies: [watcher]
        )
        let noPatrolCore = GameCore(mode: noPatrolMode)
        XCTAssertTrue(noPatrolCore.addDungeonInventorySupportCardForTesting(.railBreakSpell, rewardUses: 1))
        let unusableIndex = try XCTUnwrap(noPatrolCore.handStacks.firstIndex { $0.topCard?.supportCard == .railBreakSpell })
        XCTAssertFalse(noPatrolCore.isSupportCardUsable(in: noPatrolCore.handStacks[unusableIndex]))

        let patrolMode = makeInventoryDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            enemies: [patrol]
        )
        let core = GameCore(mode: patrolMode)
        XCTAssertTrue(core.addDungeonInventorySupportCardForTesting(.railBreakSpell, rewardUses: 1))
        let supportIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.topCard?.supportCard == .railBreakSpell })
        core.playSupportCard(at: supportIndex)

        let snapshot = try XCTUnwrap(core.makeDungeonResumeSnapshot())
        let data = try JSONEncoder().encode(snapshot)
        let decodedSnapshot = try JSONDecoder().decode(DungeonRunResumeSnapshot.self, from: data)
        let restoredCore = GameCore(mode: patrolMode)

        XCTAssertTrue(restoredCore.restoreDungeonResumeSnapshot(decodedSnapshot))
        XCTAssertTrue(restoredCore.isPatrolRailDestroyed)
        XCTAssertTrue(restoredCore.enemyPatrolRailPreviews.isEmpty)
        XCTAssertTrue(restoredCore.enemyPatrolMovementPreviews.isEmpty)
    }

    func testAntidoteClearsPoisonAndConsumesOneTurn() throws {
        let poisonTrap = GridPoint(x: 1, y: 0)
        let mode = makeInventoryDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            tileEffectOverrides: [poisonTrap: .poisonTrap],
            allowsBasicOrthogonalMove: true
        )
        let core = GameCore(mode: mode)
        XCTAssertTrue(core.addDungeonInventorySupportCardForTesting(.antidote, rewardUses: 1))
        let move = try XCTUnwrap(core.availableBasicOrthogonalMoves().first { $0.destination == poisonTrap })
        core.playBasicOrthogonalMove(using: move)
        let supportIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.topCard?.supportCard == .antidote })

        XCTAssertTrue(core.isSupportCardUsable(in: core.handStacks[supportIndex]))
        core.playSupportCard(at: supportIndex)

        XCTAssertEqual(core.poisonDamageTicksRemaining, 0)
        XCTAssertEqual(core.poisonActionsUntilNextDamage, 0)
        XCTAssertFalse(core.dungeonInventoryEntries.contains { $0.supportCard == .antidote })
        XCTAssertEqual(core.moveCount, 2)
    }

    func testPanaceaClearsPoisonAndShackleThenNextActionUsesNormalCost() throws {
        let poisonTrap = GridPoint(x: 1, y: 0)
        let shackleTrap = GridPoint(x: 1, y: 1)
        let mode = makeInventoryDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            tileEffectOverrides: [
                poisonTrap: .poisonTrap,
                shackleTrap: .shackleTrap
            ],
            allowsBasicOrthogonalMove: true
        )
        let core = GameCore(mode: mode)
        playBasicMove(to: poisonTrap, in: core)
        playBasicMove(to: shackleTrap, in: core)
        XCTAssertTrue(core.addDungeonInventorySupportCardForTesting(.panacea, rewardUses: 1))
        let supportIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.topCard?.supportCard == .panacea })

        XCTAssertTrue(core.isShackled)
        XCTAssertTrue(core.isSupportCardUsable(in: core.handStacks[supportIndex]))
        core.playSupportCard(at: supportIndex)

        XCTAssertFalse(core.isShackled)
        XCTAssertEqual(core.poisonDamageTicksRemaining, 0)
        XCTAssertEqual(core.poisonActionsUntilNextDamage, 0)
        XCTAssertEqual(core.moveCount, 3)

        playBasicMove(to: GridPoint(x: 2, y: 1), in: core)
        XCTAssertEqual(core.moveCount, 4)
    }

    func testAntidoteRequiresPoisonButPanaceaCanCureShackleOnly() throws {
        let shackleTrap = GridPoint(x: 1, y: 0)
        let mode = makeInventoryDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            tileEffectOverrides: [shackleTrap: .shackleTrap],
            allowsBasicOrthogonalMove: true
        )
        let core = GameCore(mode: mode)
        playBasicMove(to: shackleTrap, in: core)
        XCTAssertTrue(core.addDungeonInventorySupportCardForTesting(.antidote, rewardUses: 1))
        XCTAssertTrue(core.addDungeonInventorySupportCardForTesting(.panacea, rewardUses: 1))
        let antidoteIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.topCard?.supportCard == .antidote })
        let panaceaIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.topCard?.supportCard == .panacea })

        XCTAssertFalse(core.isSupportCardUsable(in: core.handStacks[antidoteIndex]))
        XCTAssertTrue(core.isSupportCardUsable(in: core.handStacks[panaceaIndex]))
    }

    func testRemediesCannotBeSpentWithoutStatusAilments() throws {
        let mode = makeInventoryDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4)
        )
        let core = GameCore(mode: mode)
        XCTAssertTrue(core.addDungeonInventorySupportCardForTesting(.antidote, rewardUses: 1))
        XCTAssertTrue(core.addDungeonInventorySupportCardForTesting(.panacea, rewardUses: 1))
        let antidoteIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.topCard?.supportCard == .antidote })
        let panaceaIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.topCard?.supportCard == .panacea })

        XCTAssertFalse(core.isSupportCardUsable(in: core.handStacks[antidoteIndex]))
        XCTAssertFalse(core.isSupportCardUsable(in: core.handStacks[panaceaIndex]))
        core.playSupportCard(at: antidoteIndex)
        core.playSupportCard(at: panaceaIndex)

        XCTAssertTrue(core.dungeonInventoryEntries.contains { $0.supportCard == .antidote })
        XCTAssertTrue(core.dungeonInventoryEntries.contains { $0.supportCard == .panacea })
        XCTAssertEqual(core.moveCount, 0)
    }

    func testSingleAnnihilationSpellSelectsOneEnemyThenAdvancesEnemyTurn() throws {
        let enemies = [
            EnemyDefinition(
                id: "guard",
                name: "番兵",
                position: GridPoint(x: 1, y: 0),
                behavior: .guardPost
            ),
            EnemyDefinition(
                id: "chaser",
                name: "追跡兵",
                position: GridPoint(x: 4, y: 4),
                behavior: .chaser
            )
        ]
        let mode = makeInventoryDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            enemies: enemies
        )
        let core = GameCore(mode: mode)
        XCTAssertTrue(core.addDungeonInventorySupportCardForTesting(.singleAnnihilationSpell, rewardUses: 1))
        let supportIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.topCard?.supportCard == .singleAnnihilationSpell })

        XCTAssertTrue(core.beginTargetedSupportCardSelection(at: supportIndex))
        XCTAssertEqual(core.targetedSupportCardTargetPoints, Set(enemies.map(\.position)))
        XCTAssertTrue(core.playTargetedSupportCard(at: GridPoint(x: 1, y: 0)))

        XCTAssertEqual(core.enemyStates.map(\.id), ["chaser"])
        XCTAssertEqual(core.enemyStates.first?.position, GridPoint(x: 3, y: 4))
        XCTAssertFalse(core.dungeonInventoryEntries.contains { $0.supportCard == .singleAnnihilationSpell })
        XCTAssertEqual(core.moveCount, 1)
        XCTAssertNotNil(core.dungeonEnemyTurnEvent)
        XCTAssertNil(core.pendingTargetedSupportCard)
    }

    func testSingleAnnihilationSpellDoesNotSpendOnNonEnemyTarget() throws {
        let enemy = EnemyDefinition(
            id: "guard",
            name: "番兵",
            position: GridPoint(x: 2, y: 0),
            behavior: .guardPost
        )
        let mode = makeInventoryDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            enemies: [enemy]
        )
        let core = GameCore(mode: mode)
        XCTAssertTrue(core.addDungeonInventorySupportCardForTesting(.singleAnnihilationSpell, rewardUses: 1))
        let supportIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.topCard?.supportCard == .singleAnnihilationSpell })

        XCTAssertTrue(core.beginTargetedSupportCardSelection(at: supportIndex))
        XCTAssertFalse(core.playTargetedSupportCard(at: GridPoint(x: 1, y: 0)))

        XCTAssertEqual(core.enemyStates.map(\.id), ["guard"])
        XCTAssertTrue(core.dungeonInventoryEntries.contains { $0.supportCard == .singleAnnihilationSpell })
        XCTAssertEqual(core.moveCount, 0)
        XCTAssertNotNil(core.pendingTargetedSupportCard)
    }

    func testSingleAnnihilationSpellTargetTapTakesPriorityOverBasicMove() throws {
        let enemyPoint = GridPoint(x: 1, y: 0)
        let enemy = EnemyDefinition(
            id: "guard",
            name: "番兵",
            position: enemyPoint,
            behavior: .guardPost
        )
        let mode = makeInventoryDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            allowsBasicOrthogonalMove: true,
            enemies: [enemy]
        )
        let core = GameCore(mode: mode)
        XCTAssertTrue(core.addDungeonInventorySupportCardForTesting(.singleAnnihilationSpell, rewardUses: 1))
        let supportIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.topCard?.supportCard == .singleAnnihilationSpell })

        XCTAssertTrue(core.beginTargetedSupportCardSelection(at: supportIndex))
        core.handleTap(at: enemyPoint)

        XCTAssertEqual(core.current, GridPoint(x: 0, y: 0))
        XCTAssertTrue(core.enemyStates.isEmpty)
        XCTAssertNil(core.boardTapBasicMoveRequest)
        XCTAssertEqual(core.moveCount, 1)
    }

    func testAnnihilationSpellCannotBeSpentWhenNoEnemiesRemain() throws {
        let mode = makeInventoryDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4)
        )
        let core = GameCore(mode: mode)
        XCTAssertTrue(core.addDungeonInventorySupportCardForTesting(.annihilationSpell, rewardUses: 1))
        let supportIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.topCard?.supportCard == .annihilationSpell })

        XCTAssertFalse(core.isSupportCardUsable(in: core.handStacks[supportIndex]))
        core.playSupportCard(at: supportIndex)

        XCTAssertTrue(core.dungeonInventoryEntries.contains { $0.supportCard == .annihilationSpell })
        XCTAssertEqual(core.moveCount, 0)
    }

    func testAnnihilationSpellRewardCarriesOnlyOneUse() {
        let runState = DungeonRunState(dungeonID: "growth-tower", carriedHP: 3)

        let advanced = runState.advancedToNextFloor(
            carryoverHP: 3,
            currentFloorMoveCount: 4,
            rewardSelection: .addSupport(.annihilationSpell),
            rewardAddUses: 4
        )

        XCTAssertEqual(
            advanced.rewardInventoryEntries,
            [DungeonInventoryEntry(support: .annihilationSpell, rewardUses: 1)]
        )
    }

    func testSingleAnnihilationSpellRewardCarriesOnlyOneUse() {
        let runState = DungeonRunState(dungeonID: "growth-tower", carriedHP: 3)

        let advanced = runState.advancedToNextFloor(
            carryoverHP: 3,
            currentFloorMoveCount: 4,
            rewardSelection: .addSupport(.singleAnnihilationSpell),
            rewardAddUses: 4
        )

        XCTAssertEqual(
            advanced.rewardInventoryEntries,
            [DungeonInventoryEntry(support: .singleAnnihilationSpell, rewardUses: 1)]
        )
    }

    func testFreezeSpellRewardCarriesOnlyOneUse() {
        let runState = DungeonRunState(dungeonID: "growth-tower", carriedHP: 3)

        let advanced = runState.advancedToNextFloor(
            carryoverHP: 3,
            currentFloorMoveCount: 4,
            rewardSelection: .addSupport(.freezeSpell),
            rewardAddUses: 4
        )

        XCTAssertEqual(
            advanced.rewardInventoryEntries,
            [DungeonInventoryEntry(support: .freezeSpell, rewardUses: 1)]
        )
    }

    func testRefillSupportCardDoesNotAddCardsWhenInventoryWasAlreadyFull() throws {
        let dungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let runState = DungeonRunState(
            dungeonID: dungeon.id,
            currentFloorIndex: 10,
            carriedHP: 3,
            rewardInventoryEntries: [
                DungeonInventoryEntry(support: .refillEmptySlots, rewardUses: 1),
                DungeonInventoryEntry(card: .straightRight2, rewardUses: 1),
                DungeonInventoryEntry(card: .straightLeft2, rewardUses: 1),
                DungeonInventoryEntry(card: .straightUp2, rewardUses: 1),
                DungeonInventoryEntry(card: .straightDown2, rewardUses: 1),
                DungeonInventoryEntry(card: .diagonalUpRight2, rewardUses: 1),
                DungeonInventoryEntry(card: .diagonalDownRight2, rewardUses: 1),
                DungeonInventoryEntry(card: .diagonalDownLeft2, rewardUses: 1),
                DungeonInventoryEntry(card: .diagonalUpLeft2, rewardUses: 1)
            ],
            cardVariationSeed: 42
        )
        let floor = try XCTUnwrap(dungeon.resolvedFloor(at: 10, runState: runState))
        let core = GameCore(mode: floor.makeGameMode(dungeonID: dungeon.id, difficulty: dungeon.difficulty, runState: runState))
        let supportIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.topCard?.supportCard == .refillEmptySlots })

        core.playSupportCard(at: supportIndex)

        XCTAssertFalse(core.dungeonInventoryEntries.contains { $0.supportCard == .refillEmptySlots })
        XCTAssertEqual(core.dungeonInventoryEntries.count, 8)
        XCTAssertFalse(core.dungeonInventoryEntries.contains { $0.pickupUses > 0 })
    }

    func testFullDungeonPickupStartsDiscardChoiceForNewCard() throws {
        let pickupPoint = GridPoint(x: 1, y: 0)
        let nineCards = Array(MoveCard.allCases.prefix(9))
        let newCard = try XCTUnwrap(MoveCard.allCases.dropFirst(9).first)
        let pickup = DungeonCardPickupDefinition(id: "new_pickup", point: pickupPoint, card: newCard)
        let mode = makeInventoryDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            allowsBasicOrthogonalMove: true,
            cardPickups: [pickup]
        )
        let core = GameCore(mode: mode)
        for card in nineCards {
            XCTAssertTrue(core.addDungeonInventoryCardForTesting(card, pickupUses: 1))
        }

        let move = try XCTUnwrap(core.availableBasicOrthogonalMoves().first { $0.destination == pickupPoint })
        core.playBasicOrthogonalMove(using: move)

        XCTAssertEqual(core.pendingDungeonPickupChoice?.pickup, pickup)
        XCTAssertEqual(core.pendingDungeonPickupChoice?.discardCandidates.count, 9)
        XCTAssertTrue(core.activeDungeonCardPickups.contains { $0.id == pickup.id })
        XCTAssertEqual(core.dungeonInventoryEntries.count, 9)
    }

    func testFullDungeonPickupStacksExistingCardWithoutChoice() throws {
        let pickupPoint = GridPoint(x: 1, y: 0)
        let nineCards = Array(MoveCard.allCases.prefix(9))
        let pickup = DungeonCardPickupDefinition(id: "same_pickup", point: pickupPoint, card: nineCards[0])
        let mode = makeInventoryDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            allowsBasicOrthogonalMove: true,
            cardPickups: [pickup]
        )
        let core = GameCore(mode: mode)
        for card in nineCards {
            XCTAssertTrue(core.addDungeonInventoryCardForTesting(card, pickupUses: 1))
        }

        let move = try XCTUnwrap(core.availableBasicOrthogonalMoves().first { $0.destination == pickupPoint })
        core.playBasicOrthogonalMove(using: move)

        XCTAssertNil(core.pendingDungeonPickupChoice)
        XCTAssertFalse(core.activeDungeonCardPickups.contains { $0.id == pickup.id })
        XCTAssertEqual(core.dungeonInventoryEntries.first { $0.card == nineCards[0] }?.rewardUses, 2)
        XCTAssertEqual(core.dungeonInventoryEntries.count, 9)
    }

    func testPendingDungeonPickupCanDiscardNewCardWithoutPenalty() throws {
        let pickupPoint = GridPoint(x: 1, y: 0)
        let nineCards = Array(MoveCard.allCases.prefix(9))
        let newCard = try XCTUnwrap(MoveCard.allCases.dropFirst(9).first)
        let pickup = DungeonCardPickupDefinition(id: "discard_new_pickup", point: pickupPoint, card: newCard)
        let core = try makeCoreWithFullInventoryAndPendingPickup(pickup: pickup, existingCards: nineCards)
        let moveCountAfterPickup = core.moveCount
        let penaltyAfterPickup = core.penaltyCount
        let inventoryBefore = core.dungeonInventoryEntries

        XCTAssertTrue(core.discardPendingDungeonPickupCard())

        XCTAssertNil(core.pendingDungeonPickupChoice)
        XCTAssertEqual(core.dungeonInventoryEntries, inventoryBefore)
        XCTAssertFalse(core.activeDungeonCardPickups.contains { $0.id == pickup.id })
        XCTAssertEqual(core.moveCount, moveCountAfterPickup)
        XCTAssertEqual(core.penaltyCount, penaltyAfterPickup)
    }

    func testPendingDungeonPickupCanReplaceExistingCardWithoutPenalty() throws {
        let pickupPoint = GridPoint(x: 1, y: 0)
        let nineCards = Array(MoveCard.allCases.prefix(9))
        let newCard = try XCTUnwrap(MoveCard.allCases.dropFirst(9).first)
        let pickup = DungeonCardPickupDefinition(id: "replace_pickup", point: pickupPoint, card: newCard)
        let core = try makeCoreWithFullInventoryAndPendingPickup(pickup: pickup, existingCards: nineCards)
        let discarded = PlayableCard.move(nineCards[0])
        let moveCountAfterPickup = core.moveCount
        let penaltyAfterPickup = core.penaltyCount

        XCTAssertTrue(core.replaceDungeonInventoryEntryForPendingPickup(discarding: discarded))

        XCTAssertNil(core.pendingDungeonPickupChoice)
        XCTAssertFalse(core.dungeonInventoryEntries.contains { $0.playable == discarded })
        XCTAssertTrue(core.dungeonInventoryEntries.contains { $0.moveCard == newCard && $0.rewardUses == pickup.uses && $0.pickupUses == 0 })
        XCTAssertFalse(core.activeDungeonCardPickups.contains { $0.id == pickup.id })
        XCTAssertEqual(core.dungeonInventoryEntries.count, 9)
        XCTAssertEqual(core.moveCount, moveCountAfterPickup)
        XCTAssertEqual(core.penaltyCount, penaltyAfterPickup)
    }

    func testPendingDungeonPickupChoiceBlocksMovementAndRestoresFromSnapshot() throws {
        let pickupPoint = GridPoint(x: 1, y: 0)
        let nineCards = Array(MoveCard.allCases.prefix(9))
        let newCard = try XCTUnwrap(MoveCard.allCases.dropFirst(9).first)
        let pickup = DungeonCardPickupDefinition(id: "resume_pickup", point: pickupPoint, card: newCard)
        let core = try makeCoreWithFullInventoryAndPendingPickup(pickup: pickup, existingCards: nineCards)
        let currentAfterPickup = core.current
        let moveCountAfterPickup = core.moveCount

        if let blockedMove = core.availableBasicOrthogonalMoves().first {
            core.playBasicOrthogonalMove(using: blockedMove)
        }
        XCTAssertEqual(core.current, currentAfterPickup)
        XCTAssertEqual(core.moveCount, moveCountAfterPickup)

        let snapshot = try XCTUnwrap(core.makeDungeonResumeSnapshot())
        let data = try JSONEncoder().encode(snapshot)
        let decodedSnapshot = try JSONDecoder().decode(DungeonRunResumeSnapshot.self, from: data)
        let restoredCore = GameCore(mode: core.mode)

        XCTAssertTrue(restoredCore.restoreDungeonResumeSnapshot(decodedSnapshot))
        XCTAssertEqual(restoredCore.pendingDungeonPickupChoice, core.pendingDungeonPickupChoice)
        XCTAssertEqual(restoredCore.current, currentAfterPickup)
    }

    func testSwampBlocksMoveCardsButAllowsBasicMoveAndSupportCards() {
        let spawn = GridPoint(x: 1, y: 1)
        let mode = makeInventoryDungeonMode(
            spawn: spawn,
            exit: GridPoint(x: 4, y: 4),
            tileEffectOverrides: [spawn: .swamp],
            allowsBasicOrthogonalMove: true
        )
        let deck = Deck.makeTestDeck(cards: [.straightRight2], configuration: mode.regulationSnapshot.deckPreset.configuration)
        let core = GameCore.makeTestInstance(deck: deck, current: spawn, mode: mode)
        let moveStack = HandStack(cards: [DealtCard(move: .straightRight2)])
        let supportStack = HandStack(cards: [DealtCard(support: .refillEmptySlots)])

        XCTAssertTrue(core.availableMoves(handStacks: [moveStack], current: spawn).isEmpty)
        XCTAssertFalse(core.availableBasicOrthogonalMoves(current: spawn).isEmpty)
        XCTAssertTrue(core.isSupportCardUsable(in: supportStack))
    }

    private func playBasicMove(
        to destination: GridPoint,
        in core: GameCore,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let move = core.availableBasicOrthogonalMoves().first(where: { $0.destination == destination }) else {
            XCTFail("基本移動候補が見つかりません: \(destination)", file: file, line: line)
            return
        }
        core.playBasicOrthogonalMove(using: move)
    }

    private func makeInventoryDungeonMode(
        spawn: GridPoint,
        exit: GridPoint,
        impassableTilePoints: Set<GridPoint> = [],
        warpTilePairs: [String: [GridPoint]] = [:],
        tileEffectOverrides: [GridPoint: TileEffect] = [:],
        allowsBasicOrthogonalMove: Bool = false,
        cardPickups: [DungeonCardPickupDefinition] = [],
        enemies: [EnemyDefinition] = [],
        hazards: [HazardDefinition] = [],
        runState: DungeonRunState? = nil,
        turnLimit: Int? = nil,
        carriedHP: Int = 3,
        isDarknessEnabled: Bool = false
    ) -> GameMode {
        let resolvedRunState = runState ?? DungeonRunState(dungeonID: "test-dungeon", carriedHP: carriedHP)
        return GameMode(
            identifier: .dungeonFloor,
            displayName: "塔攻略テスト",
            regulation: GameMode.Regulation(
                boardSize: BoardGeometry.standardSize,
                handSize: 5,
                nextPreviewCount: 0,
                allowsStacking: true,
                deckPreset: .standardLight,
                spawnRule: .fixed(spawn),
                penalties: GameMode.PenaltySettings(
                    deadlockPenaltyCost: 0,
                    manualRedrawPenaltyCost: 0,
                    manualDiscardPenaltyCost: 0,
                    revisitPenaltyCost: 0
                ),
                impassableTilePoints: impassableTilePoints,
                tileEffectOverrides: tileEffectOverrides,
                warpTilePairs: warpTilePairs,
                completionRule: .dungeonExit(exitPoint: exit),
                dungeonRules: DungeonRules(
                    difficulty: .growth,
                    failureRule: DungeonFailureRule(initialHP: carriedHP, turnLimit: turnLimit),
                    enemies: enemies,
                    hazards: hazards,
                    allowsBasicOrthogonalMove: allowsBasicOrthogonalMove,
                    cardAcquisitionMode: .inventoryOnly,
                    cardPickups: cardPickups,
                    isDarknessEnabled: isDarknessEnabled
                )
            ),
            leaderboardEligible: false,
            dungeonMetadata: GameMode.DungeonMetadata(
                dungeonID: "test-dungeon",
                floorID: "test-floor",
                runState: resolvedRunState
            )
        )
    }

    private func makeCoreWithFullInventoryAndPendingPickup(
        pickup: DungeonCardPickupDefinition,
        existingCards: [MoveCard]
    ) throws -> GameCore {
        let mode = makeInventoryDungeonMode(
            spawn: GridPoint(x: 0, y: 0),
            exit: GridPoint(x: 4, y: 4),
            allowsBasicOrthogonalMove: true,
            cardPickups: [pickup]
        )
        let core = GameCore(mode: mode)
        for card in existingCards {
            XCTAssertTrue(core.addDungeonInventoryCardForTesting(card, pickupUses: 1))
        }
        let move = try XCTUnwrap(core.availableBasicOrthogonalMoves().first { $0.destination == pickup.point })
        core.playBasicOrthogonalMove(using: move)
        XCTAssertNotNil(core.pendingDungeonPickupChoice)
        return core
    }
}
