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

    /// 複数候補のうち一部のみ盤内となるケースで canUse が true を返すか確認する
    func testCanUseWithMultipleMovementCandidates() {
        // 標準 5x5 盤を前提に左下端からの移動をテストする
        let boardSize = BoardGeometry.standardSize
        let origin = GridPoint(x: 0, y: 0)
        // 最初の候補は盤外、次の候補は盤内となるようベクトルを差し替える
        let outsideVector = MoveVector(dx: -1, dy: 0)
        let insideVector = MoveVector(dx: 0, dy: 1)
        MoveCard.setTestMovementVectors([outsideVector, insideVector], for: .kingRight)
        // テスト後は副作用を残さないように元の定義へ戻す
        defer { MoveCard.setTestMovementVectors(nil, for: .kingRight) }

        // 盤内に入る候補が存在するため true を期待する（修正前は false だった想定ケース）
        XCTAssertTrue(MoveCard.kingRight.canUse(from: origin, boardSize: boardSize))
    }
}
