import XCTest
@testable import Game

/// BoardGeometry ユーティリティの振る舞いを検証するテスト
final class BoardGeometryTests: XCTestCase {
    /// 標準サイズで中央マスが返るかどうか
    func testDefaultSpawnPointIsCenter() {
        let size = BoardGeometry.standardSize
        let spawnPoint = BoardGeometry.defaultSpawnPoint(for: size)
        // 中央座標と一致することを確認する
        XCTAssertEqual(spawnPoint, GridPoint.center(of: size))
    }

    /// 初期踏破マスが中央 1 マスだけになるかどうか
    func testDefaultInitialVisitedPoints() {
        let size = BoardGeometry.standardSize
        let visited = BoardGeometry.defaultInitialVisitedPoints(for: size)
        // 空配列にならず中央マスが含まれていることを保証する
        XCTAssertEqual(visited, [GridPoint.center(of: size)])
    }

    /// allPoints が盤面全体の座標を漏れなく返すかどうか
    func testAllPointsCoversBoard() {
        let size = 3
        let points = BoardGeometry.allPoints(for: size)
        // 3×3 なので 9 個の座標が取得できるはず
        XCTAssertEqual(points.count, size * size)
        // 端の座標も漏れなく含まれることを確認する
        XCTAssertTrue(points.contains(GridPoint(x: 2, y: 2)))
        XCTAssertTrue(points.contains(GridPoint(x: 0, y: 0)))
    }
}
