import XCTest
@testable import Game

/// 盤面モデルの基本挙動に関するテスト
final class BoardClearTests: XCTestCase {
    /// タイル効果が盤面から取得できるか検証する
    func testBoardReturnsTileEffects() {
        // ワープペアとシャッフル効果を同時に登録して取得を確認する
        let warpA = GridPoint(x: 0, y: 0)
        let warpB = GridPoint(x: 1, y: 1)
        let shufflePoint = GridPoint(x: 2, y: 2)
        let blastPoint = GridPoint(x: 0, y: 2)
        let slowPoint = GridPoint(x: 1, y: 2)
        let shacklePoint = GridPoint(x: 2, y: 3)
        let poisonPoint = GridPoint(x: 3, y: 3)
        let illusionPoint = GridPoint(x: 0, y: 1)
        let preserveCardPoint = GridPoint(x: 2, y: 1)
        let discardRandomPoint = GridPoint(x: 3, y: 1)
        let discardAllPoint = GridPoint(x: 3, y: 2)
        let discardMovePoint = GridPoint(x: 0, y: 3)
        let discardSupportPoint = GridPoint(x: 1, y: 3)
        let board = Board(
            size: 4,
            tileEffects: [
                warpA: .warp(pairID: "warp_pair", destination: warpB),
                warpB: .warp(pairID: "warp_pair", destination: warpA),
                shufflePoint: .shuffleHand,
                blastPoint: .blast(direction: MoveVector(dx: 1, dy: 0)),
                slowPoint: .slow,
                shacklePoint: .shackleTrap,
                poisonPoint: .poisonTrap,
                illusionPoint: .illusionTrap,
                preserveCardPoint: .preserveCard,
                discardRandomPoint: .discardRandomHand,
                discardMovePoint: .discardAllMoveCards,
                discardSupportPoint: .discardAllSupportCards,
                discardAllPoint: .discardAllHands,
            ]
        )

        // TileState と effect(at:) の両方で同じ効果が参照できることを確認
        XCTAssertEqual(board.effect(at: warpA), .warp(pairID: "warp_pair", destination: warpB))
        XCTAssertEqual(board.state(at: warpA)?.effect, .warp(pairID: "warp_pair", destination: warpB))
        XCTAssertEqual(board.effect(at: shufflePoint), .shuffleHand)
        XCTAssertEqual(board.state(at: shufflePoint)?.effect, .shuffleHand)
        XCTAssertEqual(board.effect(at: blastPoint), .blast(direction: MoveVector(dx: 1, dy: 0)))
        XCTAssertEqual(board.state(at: blastPoint)?.effect, .blast(direction: MoveVector(dx: 1, dy: 0)))
        XCTAssertEqual(board.effect(at: slowPoint), .slow)
        XCTAssertEqual(board.state(at: slowPoint)?.effect, .slow)
        XCTAssertEqual(board.effect(at: shacklePoint), .shackleTrap)
        XCTAssertEqual(board.state(at: shacklePoint)?.effect, .shackleTrap)
        XCTAssertEqual(board.effect(at: poisonPoint), .poisonTrap)
        XCTAssertEqual(board.state(at: poisonPoint)?.effect, .poisonTrap)
        XCTAssertEqual(board.effect(at: illusionPoint), .illusionTrap)
        XCTAssertEqual(board.state(at: illusionPoint)?.effect, .illusionTrap)
        XCTAssertEqual(board.effect(at: preserveCardPoint), .preserveCard)
        XCTAssertEqual(board.state(at: preserveCardPoint)?.effect, .preserveCard)
        XCTAssertEqual(board.effect(at: discardRandomPoint), .discardRandomHand)
        XCTAssertEqual(board.state(at: discardRandomPoint)?.effect, .discardRandomHand)
        XCTAssertEqual(board.effect(at: discardMovePoint), .discardAllMoveCards)
        XCTAssertEqual(board.state(at: discardMovePoint)?.effect, .discardAllMoveCards)
        XCTAssertEqual(board.effect(at: discardSupportPoint), .discardAllSupportCards)
        XCTAssertEqual(board.state(at: discardSupportPoint)?.effect, .discardAllSupportCards)
        XCTAssertEqual(board.effect(at: discardAllPoint), .discardAllHands)
        XCTAssertEqual(board.state(at: discardAllPoint)?.effect, .discardAllHands)
    }

    func testInvalidBlastDirectionsAreDiscarded() {
        let validBlastPoint = GridPoint(x: 0, y: 0)
        let diagonalBlastPoint = GridPoint(x: 1, y: 0)
        let longBlastPoint = GridPoint(x: 2, y: 0)
        let zeroBlastPoint = GridPoint(x: 0, y: 1)
        let board = Board(
            size: 4,
            tileEffects: [
                validBlastPoint: .blast(direction: MoveVector(dx: 0, dy: 1)),
                diagonalBlastPoint: .blast(direction: MoveVector(dx: 1, dy: 1)),
                longBlastPoint: .blast(direction: MoveVector(dx: 2, dy: 0)),
                zeroBlastPoint: .blast(direction: MoveVector(dx: 0, dy: 0)),
            ]
        )

        XCTAssertEqual(board.effect(at: validBlastPoint), .blast(direction: MoveVector(dx: 0, dy: 1)))
        XCTAssertNil(board.effect(at: diagonalBlastPoint))
        XCTAssertNil(board.effect(at: longBlastPoint))
        XCTAssertNil(board.effect(at: zeroBlastPoint))
    }

    /// 不正なワープ定義が安全に除外されるか検証する
    func testInvalidWarpDefinitionIsDiscarded() {
        // 片側のみ登録されたワープは辞書から除外される想定
        let invalidWarpSource = GridPoint(x: 0, y: 0)
        let invalidWarpDestination = GridPoint(x: 4, y: 4)
        let board = Board(
            size: 3,
            tileEffects: [
                invalidWarpSource: .warp(pairID: "broken", destination: invalidWarpDestination)
            ]
        )

        XCTAssertNil(board.effect(at: invalidWarpSource), "片側のみのワープ定義は破棄されるべき")
        XCTAssertNil(board.state(at: invalidWarpSource)?.effect, "TileState 側からも効果が除去されているか検証")
    }
}
