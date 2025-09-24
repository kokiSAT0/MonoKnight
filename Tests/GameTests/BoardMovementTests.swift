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
}
