import XCTest
@testable import Game

/// 全踏破判定に関するテスト
final class BoardClearTests: XCTestCase {
    /// 全マスを踏破すると `isCleared` が true になるか
    func testBoardClear() {
        let boardSize = 5
        var board = Board(size: boardSize)
        // 盤面全ての座標を順番に踏破済みにする
        for x in 0..<boardSize {
            for y in 0..<boardSize {
                board.markVisited(GridPoint(x: x, y: y))
            }
        }
        // 全マス踏破したためクリア判定が true
        XCTAssertTrue(board.isCleared)
    }

    /// 途中まで踏破した場合に false となるか
    func testBoardNotClear() {
        let boardSize = 5
        let center = GridPoint.center(of: boardSize)
        let board = Board(size: boardSize, initialVisitedPoints: [center])
        // 中央以外は踏破していないため false のはず
        XCTAssertFalse(board.isCleared)
    }
}
