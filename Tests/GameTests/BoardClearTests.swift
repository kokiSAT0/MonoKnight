import XCTest
@testable import Game

/// 全踏破判定に関するテスト
final class BoardClearTests: XCTestCase {
    /// 全マスを踏破すると `isCleared` が true になるか
    func testBoardClear() {
        // BoardGeometry.standardSize を利用し、テストでも本番と同じ基準値を用いる
        let boardSize = BoardGeometry.standardSize
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
        let boardSize = BoardGeometry.standardSize
        let center = GridPoint.center(of: boardSize)
        let board = Board(size: boardSize, initialVisitedPoints: [center])
        // 中央以外は踏破していないため false のはず
        XCTAssertFalse(board.isCleared)
    }

    /// 複数回踏破が必要なマスが正しく段階的に処理されるか
    func testMultiVisitTileRequiresMultipleSteps() {
        // 4×4 盤で (1,1) のマスに 2 回踏破が必要な設定を適用する
        let specialPoint = GridPoint(x: 1, y: 1)
        var board = Board(size: 4, requiredVisitOverrides: [specialPoint: 2])

        XCTAssertFalse(board.isVisited(specialPoint), "初期状態では未踏破のはず")
        XCTAssertEqual(board.remainingCount, 16, "未踏破マスが 16 のままか確認する")

        board.markVisited(specialPoint)
        XCTAssertFalse(board.isVisited(specialPoint), "1 回踏んだだけでは踏破完了にならない")
        XCTAssertEqual(board.remainingCount, 16, "残り踏破数は変化しない")

        board.markVisited(specialPoint)
        XCTAssertTrue(board.isVisited(specialPoint), "2 回目で踏破済みになる")
        XCTAssertEqual(board.remainingCount, 15, "1 マス分だけ残数が減る")
    }

    /// トグルマスが踏むたびに踏破⇔未踏破へ反転するかを確認する
    func testToggleTileFlipsVisitedState() {
        let togglePoint = GridPoint(x: 0, y: 0)
        var board = Board(size: 3, togglePoints: Set([togglePoint]))

        XCTAssertFalse(board.isVisited(togglePoint), "初期状態では未踏破")
        XCTAssertEqual(board.remainingCount, 9, "3×3 盤なので未踏破数は 9")

        board.markVisited(togglePoint)
        XCTAssertTrue(board.isVisited(togglePoint), "1 回踏むと踏破済みに変わる")
        XCTAssertEqual(board.remainingCount, 8, "踏破済みなので残マスが 1 減る")

        board.markVisited(togglePoint)
        XCTAssertFalse(board.isVisited(togglePoint), "2 回目で未踏破へ戻る")
        XCTAssertEqual(board.remainingCount, 9, "未踏破へ戻るため残マスが再び増える")

        board.markVisited(togglePoint)
        XCTAssertTrue(board.isVisited(togglePoint), "3 回目で再び踏破済みになる")
        XCTAssertEqual(board.remainingCount, 8, "踏破済みになれば残マスが減る")
    }
}
