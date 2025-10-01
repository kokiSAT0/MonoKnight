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

    /// MoveCard の移動ベクトルが従来の dx/dy と同じ値を返すかを確認する
    func testMoveCardMovementVectorsMatchLegacyValues() {
        let card = MoveCard.kingRight
        let expectedVector = MoveVector(dx: 1, dy: 0)
        XCTAssertEqual(card.movementVectors, [expectedVector], "移動候補配列が既存仕様と一致しません")
        XCTAssertEqual(card.primaryVector, expectedVector, "primaryVector が従来値と一致しません")

        let knightCard = MoveCard.knightUp1Right2
        let knightVector = MoveVector(dx: 2, dy: 1)
        XCTAssertEqual(knightCard.movementVectors, [knightVector], "桂馬カードの移動候補が想定と異なります")
        XCTAssertEqual(knightCard.primaryVector, knightVector, "桂馬カードの代表ベクトルが想定と異なります")
    }
}
