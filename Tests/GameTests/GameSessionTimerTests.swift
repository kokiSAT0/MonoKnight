import XCTest
@testable import Game

/// GameSessionTimer 単体の挙動を検証するテストケース
final class GameSessionTimerTests: XCTestCase {

    /// finalize を実行した際に小数点以下が四捨五入されることを確認
    func testFinalizeRoundsElapsedSeconds() {
        // 1970-01-01T00:00:00 を開始時刻として固定
        var timer = GameSessionTimer(now: Date(timeIntervalSince1970: 0))
        // 5.6 秒経過した時点で finalize を実行し、整数へ丸められることを検証
        let result = timer.finalize(referenceDate: Date(timeIntervalSince1970: 5.6))
        XCTAssertEqual(result, 6, "四捨五入結果が期待値と一致していません")
        XCTAssertTrue(timer.isFinalized, "finalize 実行後は終了済みフラグが立つべきです")
        XCTAssertEqual(timer.elapsedSeconds, 6, "確定済みの秒数も更新されている必要があります")
    }

    /// finalize 済みの場合に再度 finalize を実行しても値が変化しないことを確認
    func testFinalizeKeepsValueWhenAlreadyFinalized() {
        var timer = GameSessionTimer(now: Date(timeIntervalSince1970: 0))
        _ = timer.finalize(referenceDate: Date(timeIntervalSince1970: 10.2))
        // 既に終了している状態で別の時刻を渡しても値が固定されていることを確認
        let result = timer.finalize(referenceDate: Date(timeIntervalSince1970: 30))
        XCTAssertEqual(result, 10, "二度目以降の finalize で値が変わってはいけません")
    }

    /// reset で開始時刻と終了状態がリセットされ、ライブ計測が再開されることを確認
    func testResetClearsFinalizedState() {
        var timer = GameSessionTimer(now: Date(timeIntervalSince1970: 0))
        _ = timer.finalize(referenceDate: Date(timeIntervalSince1970: 8))
        timer.reset(now: Date(timeIntervalSince1970: 20))
        XCTAssertFalse(timer.isFinalized, "リセット後は未確定状態へ戻るべきです")
        XCTAssertEqual(timer.elapsedSeconds, 0, "リセットで確定秒数は 0 に戻る必要があります")
        let live = timer.liveElapsedSeconds(asOf: Date(timeIntervalSince1970: 25))
        XCTAssertEqual(live, 5, "リセット後のライブ計測が期待値と一致しません")
    }

    /// 一時停止中は liveElapsedSeconds が増加しないことを確認
    func testLiveElapsedSecondsRemainsStableWhilePaused() {
        var timer = GameSessionTimer(now: Date(timeIntervalSince1970: 0))
        // 30 秒経過したタイミングで一時停止を開始する
        timer.beginPause(at: Date(timeIntervalSince1970: 30))
        // 60 秒間待機しても一時停止中なので経過時間は変わらない想定
        let pausedElapsed = timer.liveElapsedSeconds(asOf: Date(timeIntervalSince1970: 90))
        XCTAssertEqual(pausedElapsed, 30, "一時停止中に経過秒数が増加してはいけません")

        // 一時停止を解除した後は再びカウントが進む
        timer.endPause(at: Date(timeIntervalSince1970: 90))
        let resumedElapsed = timer.liveElapsedSeconds(asOf: Date(timeIntervalSince1970: 120))
        XCTAssertEqual(resumedElapsed, 60, "一時停止解除後の経過秒数が想定値と一致しません")
    }

    /// finalize が累積一時停止時間を差し引いて計算されることを確認
    func testFinalizeSubtractsPausedDurationIncludingActivePause() {
        var timer = GameSessionTimer(now: Date(timeIntervalSince1970: 0))
        // 最初の一時停止（30 秒間）
        timer.beginPause(at: Date(timeIntervalSince1970: 40))
        timer.endPause(at: Date(timeIntervalSince1970: 70))

        // 二度目の一時停止を開始し、解除しないまま finalize する
        timer.beginPause(at: Date(timeIntervalSince1970: 90))
        let finalized = timer.finalize(referenceDate: Date(timeIntervalSince1970: 150))

        XCTAssertEqual(finalized, 60, "一時停止時間を差し引いた finalize の結果が期待値と一致しません")
        XCTAssertEqual(timer.elapsedSeconds, 60, "確定済み経過秒数も同じ値で保持されるべきです")
    }
}
