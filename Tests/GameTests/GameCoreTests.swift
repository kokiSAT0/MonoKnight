import XCTest
@testable import Game

/// GameCore のうち、塔攻略モードでも直接使う薄い結合点を検証するテスト。
final class GameCoreTests: XCTestCase {
    func testAvailableMovesSkipsImpassableDestinationsInDungeonInventoryMode() {
        let impassablePoint = GridPoint(x: 3, y: 2)
        let mode = makeInventoryDungeonMode(
            spawn: GridPoint(x: 2, y: 2),
            exit: GridPoint(x: 4, y: 4),
            impassableTilePoints: [impassablePoint]
        )
        let core = GameCore(mode: mode)

        XCTAssertTrue(core.addDungeonInventoryCardForTesting(.kingRight, pickupUses: 1))
        XCTAssertTrue(core.addDungeonInventoryCardForTesting(.kingUp, pickupUses: 1))

        let destinations = Set(core.availableMoves().map(\.destination))
        XCTAssertFalse(destinations.contains(impassablePoint), "塔攻略の移動候補に通行不可マスを含めてはいけません")
        XCTAssertTrue(destinations.contains(GridPoint(x: 2, y: 3)), "通行可能なカード移動候補まで消えてはいけません")
    }

    func testPlayCardAppliesWarpEffectInDungeonInventoryMode() {
        let warpSource = GridPoint(x: 3, y: 2)
        let warpDestination = GridPoint(x: 1, y: 4)
        let mode = makeInventoryDungeonMode(
            spawn: GridPoint(x: 2, y: 2),
            exit: GridPoint(x: 4, y: 4),
            warpTilePairs: ["test_warp": [warpSource, warpDestination]]
        )
        let core = GameCore(mode: mode)

        XCTAssertTrue(core.addDungeonInventoryCardForTesting(.kingRight, pickupUses: 1))
        guard let move = core.availableMoves().first(where: { $0.moveCard == .kingRight }) else {
            XCTFail("右方向カードが候補に含まれていません")
            return
        }

        core.playCard(using: move)

        XCTAssertEqual(core.current, warpDestination, "ワープ床を踏んだ塔カード移動は最終位置をワープ先へ更新します")
        XCTAssertTrue(core.board.isVisited(warpSource), "ワープ元マスも踏破扱いにします")
        XCTAssertTrue(core.board.isVisited(warpDestination), "ワープ先マスも踏破扱いにします")
    }

    func testDungeonInventoryStacksDuplicateCardsAndRejectsNewCardAtTenKinds() {
        let mode = makeInventoryDungeonMode(spawn: GridPoint(x: 0, y: 0), exit: GridPoint(x: 4, y: 4))
        let core = GameCore(mode: mode)
        let tenCards = Array(MoveCard.allCases.prefix(10))
        let eleventh = MoveCard.allCases[10]

        for card in tenCards {
            XCTAssertTrue(core.addDungeonInventoryCardForTesting(card, pickupUses: 1))
        }

        XCTAssertEqual(core.dungeonInventoryEntries.count, 10)
        XCTAssertFalse(core.addDungeonInventoryCardForTesting(eleventh, pickupUses: 1), "塔攻略の所持カード種類数は10種類までです")
        XCTAssertTrue(core.addDungeonInventoryCardForTesting(tenCards[0], pickupUses: 1), "同じカードは種類枠を増やさず回数として積めます")
        XCTAssertEqual(core.dungeonInventoryEntries.count, 10)
        XCTAssertEqual(core.dungeonInventoryEntries.first { $0.card == tenCards[0] }?.pickupUses, 2)
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

    private func makeInventoryDungeonMode(
        spawn: GridPoint,
        exit: GridPoint,
        impassableTilePoints: Set<GridPoint> = [],
        warpTilePairs: [String: [GridPoint]] = [:],
        allowsBasicOrthogonalMove: Bool = false
    ) -> GameMode {
        GameMode(
            identifier: .dungeonFloor,
            displayName: "塔攻略テスト",
            regulation: GameMode.Regulation(
                boardSize: BoardGeometry.standardSize,
                handSize: 5,
                nextPreviewCount: 0,
                allowsStacking: true,
                deckPreset: .standard,
                spawnRule: .fixed(spawn),
                penalties: GameMode.PenaltySettings(
                    deadlockPenaltyCost: 0,
                    manualRedrawPenaltyCost: 0,
                    manualDiscardPenaltyCost: 0,
                    revisitPenaltyCost: 0
                ),
                impassableTilePoints: impassableTilePoints,
                warpTilePairs: warpTilePairs,
                completionRule: .dungeonExit(exitPoint: exit),
                dungeonRules: DungeonRules(
                    difficulty: .growth,
                    failureRule: DungeonFailureRule(initialHP: 3, turnLimit: nil),
                    allowsBasicOrthogonalMove: allowsBasicOrthogonalMove,
                    cardAcquisitionMode: .inventoryOnly
                )
            ),
            leaderboardEligible: false
        )
    }
}
