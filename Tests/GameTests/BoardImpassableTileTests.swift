import XCTest
@testable import Game

/// 移動不可マス（障害物）に関する振る舞いを確認するテスト
final class BoardImpassableTileTests: XCTestCase {
    /// イニシャライザで指定した座標が確実に移動不可マスとして扱われるかを検証する
    func testInitializerMarksTileAsImpassable() {
        // 2x2 の最小サイズ盤面に 1 マスだけ障害物を配置する
        let impassablePoint = GridPoint(x: 0, y: 1)
        let board = Board(
            size: 2,
            impassablePoints: Set([impassablePoint])
        )

        // state(at:) から取得した TileState の移動可否が false であることを確認する
        let tileState = board.state(at: impassablePoint)
        XCTAssertNotNil(tileState, "盤面内のマスが nil を返しました")
        XCTAssertEqual(tileState?.isTraversable, false, "障害物マスが移動可能と判定されています")
        // Board の補助メソッドでも一貫して判定できることをテストする
        XCTAssertTrue(board.isImpassable(impassablePoint), "isImpassable が true を返していません")
        XCTAssertFalse(board.isTraversable(impassablePoint), "isTraversable が true を返しています")
    }

    /// markVisited を呼んでも移動不可マスの残数が変化しないことを確認する
    func testMarkVisitedDoesNotChangeImpassableTile() {
        // 障害物を 1 マス配置した盤面を用意する
        let impassablePoint = GridPoint(x: 1, y: 1)
        var board = Board(
            size: 3,
            impassablePoints: Set([impassablePoint])
        )

        // 障害物マスに対して markVisited を実行する
        board.markVisited(impassablePoint)

        // TileState の残数が 0 のままであり、訪問済み判定も変わらないことを確認する
        let tileState = board.state(at: impassablePoint)
        XCTAssertEqual(tileState?.remainingVisits, 0, "障害物マスの残数が変化しています")
        XCTAssertEqual(tileState?.isVisited, true, "障害物マスの訪問済みフラグが false になっています")

        // 障害物以外のマスは通常通り残数にカウントされることを確認する
        XCTAssertEqual(board.remainingCount, 8, "移動可能マスの残数計算が想定と異なります")
    }

    /// 初期踏破対象に障害物を指定した場合でも安全に無視されるか検証する
    func testInitialVisitedPointsIgnoreImpassableTiles() {
        // 障害物と初期踏破指定を同一座標に設定する
        let impassablePoint = GridPoint(x: 0, y: 0)
        var board = Board(
            size: 3,
            initialVisitedPoints: [impassablePoint],
            impassablePoints: Set([impassablePoint])
        )

        // markVisited の代わりに初期化時に呼ばれているかを検証するため、残数を再計算する
        XCTAssertTrue(board.isImpassable(impassablePoint), "障害物が想定通り初期化されていません")
        XCTAssertEqual(board.remainingCount, 8, "障害物を含む初期踏破指定で残数が狂っています")

        // 障害物以外のマスへ markVisited を実行しても問題なく減算されることを確認する
        let traversablePoint = GridPoint(x: 1, y: 0)
        board.markVisited(traversablePoint)
        XCTAssertTrue(board.isVisited(traversablePoint), "移動可能マスの踏破処理が働いていません")
    }
}
