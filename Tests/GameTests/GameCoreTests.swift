import XCTest
@testable import Game

/// `GameCore` のペナルティ判定やリセット挙動を検証するテスト
/// - NOTE: コメントは可読性向上のため日本語で詳細に記述する
final class GameCoreTests: XCTestCase {
    /// 手札がすべて盤外の場合にペナルティが正しく加算されるか
    func testDeadlockPenaltyApplied() {
        let core = GameCore()
        // 左下隅にいると仮定し、どのカードも盤外へ出るような手札を設定
        core.setStateForTest(
            hand: [.straightLeft2, .straightDown2, .diagonalDownLeft2],
            next: nil,
            current: GridPoint(x: 0, y: 0)
        )
        // ペナルティ適用前は 0 のはず
        XCTAssertEqual(core.penaltyCount, 0)
        // デッドロック判定を直接呼び出し
        core.invokeDeadlockCheckForTest()
        // すべてのカードが盤外のため +5 のペナルティが加算される
        XCTAssertEqual(core.penaltyCount, 5)
        // ペナルティ処理後は再びプレイング状態に戻る
        XCTAssertEqual(core.progress, .playing)
    }

    /// `reset()` によりゲーム状態が初期化されるか
    func testReset() {
        let core = GameCore()
        // まず 1 手進めて移動回数を 1 にする
        core.playCard(at: 0)
        // さらに意図的にデッドロックを発生させてペナルティを加算
        core.setStateForTest(
            hand: [.straightLeft2, .straightDown2, .diagonalDownLeft2],
            next: nil,
            current: GridPoint(x: 0, y: 0)
        )
        core.invokeDeadlockCheckForTest()
        // ここまでで moveCount は 1、penaltyCount は 5 になっている想定
        // --- リセット実行 ---
        core.reset()
        // 現在位置が中央に戻るか
        XCTAssertEqual(core.current, .center)
        // 手数・ペナルティが 0 に戻るか
        XCTAssertEqual(core.moveCount, 0)
        XCTAssertEqual(core.penaltyCount, 0)
        // 進行状態が playing へ戻るか
        XCTAssertEqual(core.progress, .playing)
        // 盤面の踏破状況も初期状態（中央のみ踏破）か確認
        XCTAssertTrue(core.board.isVisited(.center))
        XCTAssertFalse(core.board.isVisited(GridPoint(x: 0, y: 0)))
    }
}
