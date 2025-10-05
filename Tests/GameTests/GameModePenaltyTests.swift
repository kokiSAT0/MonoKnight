import XCTest
@testable import Game

/// GameMode のペナルティ設定が GameCore の挙動へ正しく反映されるかを検証するテスト
final class GameModePenaltyTests: XCTestCase {
    /// deadlockPenaltyCost の値に合わせて自動ペナルティが加算されるか確認する
    func testDeadlockPenaltyUsesModeConfiguration() {
        // --- カスタムモードのレギュレーションを定義（ペナルティ量を分かりやすく変更）---
        let regulation = GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standard,
            spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 5)),
            penalties: GameMode.PenaltySettings(
                deadlockPenaltyCost: 7,
                manualRedrawPenaltyCost: 4,
                manualDiscardPenaltyCost: 2,
                revisitPenaltyCost: 0
            )
        )
        let mode = GameMode(identifier: .freeCustom, displayName: "カスタム", regulation: regulation)

        // --- 盤外カードのみの手札を用意し、初期化時に強制的に手詰まりへ誘導 ---
        let deck = Deck.makeTestDeck(cards: [
            .diagonalDownLeft2,
            .straightLeft2,
            .straightDown2,
            .knightDown2Right1,
            .knightDown2Left1,
            .kingRight,
            .kingUp,
            .diagonalUpLeft2,
            .kingUpLeft,
            .kingLeft
        ])

        let core = GameCore.makeTestInstance(deck: deck, current: GridPoint(x: 0, y: 0), mode: mode)

        XCTAssertEqual(core.penaltyCount, 7, "deadlockPenaltyCost の設定値が反映されていません")
        // 連続排出抑制を廃止したことで、直後の引き直しが再度手詰まりになる場合がある
        // （= `applyPenaltyRedraw` が追加ペナルティなしで再度呼ばれるケース）。
        // その際は `penaltyEvent` が無料再抽選イベントへ更新されるため、値の厳密比較は行わない。
    }

    /// manualRedrawPenaltyCost の設定が applyManualPenaltyRedraw() に反映されるか確認する
    func testManualRedrawPenaltyUsesModeConfiguration() {
        // --- 手動引き直しのペナルティのみを強調したレギュレーションを定義 ---
        let regulation = GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standard,
            spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 5)),
            penalties: GameMode.PenaltySettings(
                deadlockPenaltyCost: 0,
                manualRedrawPenaltyCost: 3,
                manualDiscardPenaltyCost: 1,
                revisitPenaltyCost: 0
            )
        )
        let mode = GameMode(identifier: .freeCustom, displayName: "カスタム", regulation: regulation)

        // --- 初期手札で盤内へ進めるカードを含め、手詰まりが発生しないようにする ---
        let deck = Deck.makeTestDeck(cards: [
            .kingUp,
            .kingLeft,
            .kingRight,
            .knightUp1Right2,
            .kingDown,
            .straightUp2,
            .straightRight2,
            .diagonalUpRight2,
            .knightUp2Left1,
            .kingUpLeft
        ])

        let core = GameCore.makeTestInstance(deck: deck, mode: mode)
        XCTAssertEqual(core.penaltyCount, 0, "初期状態でペナルティが加算されてはいけません")

        core.applyManualPenaltyRedraw()

        XCTAssertEqual(core.penaltyCount, 3, "manualRedrawPenaltyCost が反映されていません")
        XCTAssertEqual(core.penaltyEvent?.penaltyAmount, 3, "最後に加算したペナルティ量が 3 になっていません")
        XCTAssertEqual(core.penaltyEvent?.trigger, .manualRedraw, "手動引き直しイベントのトリガーが manualRedraw になっていません")
    }

    /// manualDiscardPenaltyCost が 0 の場合に追加ペナルティが発生しないことを検証する
    func testManualDiscardPenaltyAllowsZeroCost() {
        // --- 捨て札ペナルティを 0 に設定したレギュレーションを用意 ---
        let regulation = GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standard,
            spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 5)),
            penalties: GameMode.PenaltySettings(
                deadlockPenaltyCost: 0,
                manualRedrawPenaltyCost: 2,
                manualDiscardPenaltyCost: 0,
                revisitPenaltyCost: 0
            )
        )
        let mode = GameMode(identifier: .freeCustom, displayName: "カスタム", regulation: regulation)

        let deck = Deck.makeTestDeck(cards: [
            .kingUp,
            .kingLeft,
            .knightUp1Right2,
            .kingRight,
            .kingDown,
            .straightUp2,
            .knightUp2Right1,
            .diagonalUpRight2,
            .kingUpRight,
            .straightRight2
        ])

        let core = GameCore.makeTestInstance(deck: deck, mode: mode)
        let initialPenalty = core.penaltyCount

        // --- 捨て札モードを開始し、先頭のスタックを捨て札にする ---
        XCTAssertFalse(core.isAwaitingManualDiscardSelection, "初期状態で捨て札モードになっていてはいけません")
        core.beginManualDiscardSelection()
        XCTAssertTrue(core.isAwaitingManualDiscardSelection, "捨て札モードの開始に失敗しています")

        guard let stackID = core.handStacks.first?.id else {
            XCTFail("手札スタックが存在しません")
            return
        }

        let succeeded = core.discardHandStack(withID: stackID)
        XCTAssertTrue(succeeded, "捨て札操作が失敗しました")

        XCTAssertEqual(core.penaltyCount, initialPenalty, "manualDiscardPenaltyCost=0 の場合はペナルティが増えてはいけません")
        XCTAssertFalse(core.isAwaitingManualDiscardSelection, "捨て札操作後はモードが解除されているべきです")
    }
}
