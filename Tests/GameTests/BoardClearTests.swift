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

    /// タイル効果が盤面から取得できるか検証する
    func testBoardReturnsTileEffects() {
        // ワープペアとシャッフル効果を同時に登録して取得を確認する
        let warpA = GridPoint(x: 0, y: 0)
        let warpB = GridPoint(x: 1, y: 1)
        let shufflePoint = GridPoint(x: 2, y: 2)
        let boostPoint = GridPoint(x: 0, y: 2)
        let slowPoint = GridPoint(x: 1, y: 2)
        let nextRefreshPoint = GridPoint(x: 2, y: 0)
        let freeFocusPoint = GridPoint(x: 0, y: 1)
        let preserveCardPoint = GridPoint(x: 2, y: 1)
        let draftPoint = GridPoint(x: 1, y: 0)
        let overloadPoint = GridPoint(x: 3, y: 0)
        let targetSwapPoint = GridPoint(x: 3, y: 1)
        let openGatePoint = GridPoint(x: 3, y: 3)
        let openGateTarget = GridPoint(x: 0, y: 3)
        let board = Board(
            size: 4,
            tileEffects: [
                warpA: .warp(pairID: "warp_pair", destination: warpB),
                warpB: .warp(pairID: "warp_pair", destination: warpA),
                shufflePoint: .shuffleHand,
                boostPoint: .boost,
                slowPoint: .slow,
                nextRefreshPoint: .nextRefresh,
                freeFocusPoint: .freeFocus,
                preserveCardPoint: .preserveCard,
                draftPoint: .draft,
                overloadPoint: .overload,
                targetSwapPoint: .targetSwap,
                openGatePoint: .openGate(target: openGateTarget),
            ]
        )

        // TileState と effect(at:) の両方で同じ効果が参照できることを確認
        XCTAssertEqual(board.effect(at: warpA), .warp(pairID: "warp_pair", destination: warpB))
        XCTAssertEqual(board.state(at: warpA)?.effect, .warp(pairID: "warp_pair", destination: warpB))
        XCTAssertEqual(board.effect(at: shufflePoint), .shuffleHand)
        XCTAssertEqual(board.state(at: shufflePoint)?.effect, .shuffleHand)
        XCTAssertEqual(board.effect(at: boostPoint), .boost)
        XCTAssertEqual(board.state(at: boostPoint)?.effect, .boost)
        XCTAssertEqual(board.effect(at: slowPoint), .slow)
        XCTAssertEqual(board.state(at: slowPoint)?.effect, .slow)
        XCTAssertEqual(board.effect(at: nextRefreshPoint), .nextRefresh)
        XCTAssertEqual(board.state(at: nextRefreshPoint)?.effect, .nextRefresh)
        XCTAssertEqual(board.effect(at: freeFocusPoint), .freeFocus)
        XCTAssertEqual(board.state(at: freeFocusPoint)?.effect, .freeFocus)
        XCTAssertEqual(board.effect(at: preserveCardPoint), .preserveCard)
        XCTAssertEqual(board.state(at: preserveCardPoint)?.effect, .preserveCard)
        XCTAssertEqual(board.effect(at: draftPoint), .draft)
        XCTAssertEqual(board.state(at: draftPoint)?.effect, .draft)
        XCTAssertEqual(board.effect(at: overloadPoint), .overload)
        XCTAssertEqual(board.state(at: overloadPoint)?.effect, .overload)
        XCTAssertEqual(board.effect(at: targetSwapPoint), .targetSwap)
        XCTAssertEqual(board.state(at: targetSwapPoint)?.effect, .targetSwap)
        XCTAssertEqual(board.effect(at: openGatePoint), .openGate(target: openGateTarget))
        XCTAssertEqual(board.state(at: openGatePoint)?.effect, .openGate(target: openGateTarget))
    }

    func testBoardOpenGateTurnsImpassableTileIntoUnvisitedTraversableTile() {
        let gateTarget = GridPoint(x: 1, y: 1)
        var board = Board(size: 3, impassablePoints: [gateTarget])

        XCTAssertTrue(board.isImpassable(gateTarget))
        XCTAssertFalse(board.isTraversable(gateTarget))
        XCTAssertEqual(board.remainingCount, 8)

        XCTAssertTrue(board.openGate(at: gateTarget))

        XCTAssertFalse(board.isImpassable(gateTarget))
        XCTAssertTrue(board.isTraversable(gateTarget))
        XCTAssertFalse(board.isVisited(gateTarget))
        XCTAssertEqual(board.remainingCount, 9)
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
