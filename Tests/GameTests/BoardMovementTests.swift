import XCTest
@testable import Game

/// 盤外移動判定に関するテスト
final class BoardMovementTests: XCTestCase {
    /// 中央から盤外へ出る移動が正しく検出されるか
    func testOutOfBoundsMove() {
        // 盤面サイズは BoardGeometry から取得し、テストコードも本番と同じ定義を参照する
        let boardSize = BoardGeometry.standardSize
        let origin = GridPoint.center(of: boardSize)
        // 盤の外へ 3 マス右に移動
        let outside = origin.offset(dx: 3, dy: 0)
        // 範囲外なので `isInside` は false になるべき
        XCTAssertFalse(outside.isInside(boardSize: boardSize))
    }

    /// 盤内の移動が有効と判定されるか
    func testInsideMove() {
        let boardSize = BoardGeometry.standardSize
        let origin = GridPoint.center(of: boardSize)
        // 1 マス右は盤内
        let inside = origin.offset(dx: 1, dy: 0)
        XCTAssertTrue(inside.isInside(boardSize: boardSize))
    }

    /// MovePattern が従来の単一ベクトルと同じ移動を生成するか確認する
    func testMovePatternResolvesLegacyVectors() {
        let boardSize = BoardGeometry.standardSize
        let origin = GridPoint.center(of: boardSize)
        let board = Board(size: boardSize)
        let context = MoveCard.MovePattern.ResolutionContext(
            boardSize: board.size,
            contains: { board.contains($0) },
            isTraversable: { board.isTraversable($0) }
        )

        let card = MoveCard.kingUpRight
        let expectedVector = MoveVector(dx: 1, dy: 1)
        let kingPaths = card.resolvePaths(from: origin, context: context)
        XCTAssertEqual(kingPaths.map(\.vector), [expectedVector], "移動パターンが想定ベクトルを返していません")
        XCTAssertEqual(kingPaths.first?.destination, origin.offset(dx: 1, dy: 1), "移動先が従来の仕様と一致していません")
        XCTAssertEqual(card.movePattern.identity, .relativeSteps([expectedVector]), "アイデンティティが想定の相対単歩と一致しません")
        XCTAssertEqual(card.primaryVector, expectedVector, "primaryVector が従来値と一致しません")

        let knightCard = MoveCard.knightUp1Right2
        let knightVector = MoveVector(dx: 2, dy: 1)
        let knightPaths = knightCard.resolvePaths(from: origin, context: context)
        XCTAssertEqual(knightPaths.map(\.vector), [knightVector], "桂馬カードの移動パターンが想定ベクトルを返していません")
        XCTAssertEqual(knightPaths.first?.destination, origin.offset(dx: 2, dy: 1), "桂馬カードの移動先が想定と異なります")
        XCTAssertEqual(knightCard.movePattern.identity, .relativeSteps([knightVector]), "桂馬カードのアイデンティティが想定と異なります")
        XCTAssertEqual(knightCard.primaryVector, knightVector, "桂馬カードの代表ベクトルが想定と異なります")
    }

    /// 複数方向候補カードが 2 方向のベクトルを保持し、primaryVector が先頭を指すかを確認する
    func testMultiDirectionCardProvidesTwoCandidates() {
        let boardSize = BoardGeometry.standardSize
        let origin = GridPoint.center(of: boardSize)
        let board = Board(size: boardSize)
        let context = MoveCard.MovePattern.ResolutionContext(
            boardSize: board.size,
            contains: { board.contains($0) },
            isTraversable: { board.isTraversable($0) }
        )

        let upwardDiagonalChoice = MoveCard.kingUpwardDiagonalChoice
        let upwardPaths = upwardDiagonalChoice.resolvePaths(from: origin, context: context)
        XCTAssertEqual(upwardPaths.count, 2, "上斜め選択カードの候補数が 2 ではありません")
        XCTAssertEqual(upwardPaths[0].vector, MoveVector(dx: 1, dy: 1), "上斜め選択カードの先頭ベクトルが右上方向になっていません")
        XCTAssertEqual(upwardPaths[1].vector, MoveVector(dx: -1, dy: 1), "上斜め選択カードの 2 番目ベクトルが左上方向になっていません")
        XCTAssertEqual(upwardDiagonalChoice.movePattern.identity, .relativeSteps([MoveVector(dx: 1, dy: 1), MoveVector(dx: -1, dy: 1)]), "上斜め選択カードのアイデンティティが想定と異なります")
        XCTAssertEqual(upwardDiagonalChoice.primaryVector, MoveVector(dx: 1, dy: 1), "上斜め選択カードの primaryVector が想定外です")

        let rightDiagonalChoice = MoveCard.kingRightDiagonalChoice
        let rightPaths = rightDiagonalChoice.resolvePaths(from: origin, context: context)
        XCTAssertEqual(rightPaths.count, 2, "右斜め選択カードの候補数が 2 ではありません")
        XCTAssertEqual(rightPaths[0].vector, MoveVector(dx: 1, dy: 1), "右斜め選択カードの先頭ベクトルが右上方向になっていません")
        XCTAssertEqual(rightPaths[1].vector, MoveVector(dx: 1, dy: -1), "右斜め選択カードの 2 番目ベクトルが右下方向になっていません")
        XCTAssertEqual(rightDiagonalChoice.movePattern.identity, .relativeSteps([MoveVector(dx: 1, dy: 1), MoveVector(dx: 1, dy: -1)]), "右斜め選択カードのアイデンティティが想定と異なります")
        XCTAssertEqual(rightDiagonalChoice.primaryVector, MoveVector(dx: 1, dy: 1), "右斜め選択カードの primaryVector が想定外です")
    }

    /// 複数候補のうち一部のみ盤内となるケースで canUse が true を返すか確認する
    func testCanUseWithMultipleMovementCandidates() {
        // 標準 5x5 盤を前提に左下端からの移動をテストする
        let boardSize = BoardGeometry.standardSize
        let origin = GridPoint(x: 0, y: 0)
        // 最初の候補は盤外、次の候補は盤内となるようベクトルを差し替える
        let outsideVector = MoveVector(dx: -1, dy: 0)
        let insideVector = MoveVector(dx: 0, dy: 1)
        MoveCard.setTestMovementVectors([outsideVector, insideVector], for: .kingUpRight)
        // テスト後は副作用を残さないように元の定義へ戻す
        defer { MoveCard.setTestMovementVectors(nil, for: .kingUpRight) }

        // 盤内に入る候補が存在するため true を期待する（修正前は false だった想定ケース）
        XCTAssertTrue(MoveCard.kingUpRight.canUse(from: origin, boardSize: boardSize))
    }

    /// availableMoves() が MovementResolution の経路情報を露出することを確認する
    func testAvailableMovesProvidesMovementPathForDungeonInventoryCard() {
        let origin = GridPoint.center(of: BoardGeometry.standardSize)
        let mode = GameMode(
            identifier: .dungeonFloor,
            displayName: "塔移動経路テスト",
            regulation: GameMode.Regulation(
                boardSize: BoardGeometry.standardSize,
                handSize: 5,
                nextPreviewCount: 0,
                allowsStacking: true,
                deckPreset: .standard,
                spawnRule: .fixed(origin),
                penalties: GameMode.PenaltySettings(
                    deadlockPenaltyCost: 0,
                    manualRedrawPenaltyCost: 0,
                    manualDiscardPenaltyCost: 0,
                    revisitPenaltyCost: 0
                ),
                completionRule: .dungeonExit(exitPoint: GridPoint(x: 4, y: 4)),
                dungeonRules: DungeonRules(
                    difficulty: .growth,
                    failureRule: DungeonFailureRule(initialHP: 3, turnLimit: nil),
                    cardAcquisitionMode: .inventoryOnly
                )
            ),
            leaderboardEligible: false
        )
        let core = GameCore(mode: mode)

        XCTAssertTrue(core.addDungeonInventoryCardForTesting(.straightRight2, pickupUses: 1))

        guard let straightMove = core.availableMoves().first(where: { $0.card.move == .straightRight2 }) else {
            XCTFail("直進 2 マスカードが候補に含まれていません")
            return
        }

        XCTAssertEqual(straightMove.path, [GridPoint(x: origin.x + 2, y: origin.y)], "MovementResolution の経路が想定と異なります")
        XCTAssertEqual(straightMove.resolution.finalPosition, GridPoint(x: origin.x + 2, y: origin.y), "MovementResolution.finalPosition が想定地点を指していません")
    }
}
