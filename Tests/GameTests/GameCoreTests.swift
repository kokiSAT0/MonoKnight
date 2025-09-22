import XCTest
@testable import Game

/// GameCore の主要メソッドを検証するテスト
final class GameCoreTests: XCTestCase {
    /// 手札が全て盤外となった場合にペナルティが加算されるかを確認
    func testDeadlockPenaltyApplied() {
        // --- テスト用デッキ構築 ---
        // 新実装では「先頭が最初にドローされる」ため、引かせたい順に並べる
        let deck = Deck.makeTestDeck(cards: [
            // --- 初期手札 5 枚（すべて盤外になるカード）---
            .diagonalDownLeft2,
            .straightLeft2,
            .straightDown2,
            .knightDown2Right1,
            .knightDown2Left1,
            // --- 初期先読み 3 枚（手札補充時にこの順で出現）---
            .kingRight,
            .kingUp,
            .diagonalUpLeft2,
            // --- 引き直し後の手札 5 枚（盤内へ移動可能）---
            .kingUpLeft,
            .kingLeft,
            .kingDown,
            .knightUp1Right2,
            .straightRight2,
            // --- 引き直し後の先読みカード 3 枚 ---
            .diagonalUpRight2,
            .straightUp2,
            .knightUp2Right1
        ])
        // 左下隅 (0,0) から開始し、全手札が盤外となる状況を用意
        let core = GameCore.makeTestInstance(deck: deck, current: GridPoint(x: 0, y: 0))

        // ペナルティが +5 されているか
        XCTAssertEqual(core.penaltyCount, 5, "手詰まり時にペナルティが加算されていない")
        // ペナルティ処理後は進行状態が playing に戻るか
        XCTAssertEqual(core.progress, .playing, "ペナルティ後は playing 状態に戻るべき")
        // 引き直し後の手札枚数が 5 枚確保されているか
        XCTAssertEqual(core.hand.count, 5, "引き直し後の手札枚数が 5 枚ではない")
        // 引き直し後の手札に使用可能なカードが少なくとも 1 枚あるか
        if let current = core.current {
            let boardSize = core.mode.boardSize
            let playableExists = core.hand.contains { $0.move.canUse(from: current, boardSize: boardSize) }
            XCTAssertTrue(playableExists, "引き直し後の手札に利用可能なカードが存在しない")
        } else {
            XCTFail("現在地が nil のままです")
        }
        // 先読みカードが 3 枚揃っているか（NEXT 表示用）
        XCTAssertEqual(core.nextCards.count, 3, "引き直し後の先読みカードが 3 枚補充されていない")
    }

    /// 手詰まり後に再び手詰まりが発生した場合でも追加ペナルティが加算されないことを確認
    func testConsecutiveDeadlockDoesNotAddExtraPenalty() {
        // --- テスト用デッキ構築 ---
        // 2 回連続で盤外カードだけが配られ、最後に盤内へ進めるカードが揃うシナリオを用意
        let deck = Deck.makeTestDeck(cards: [
            // --- 初期手札 5 枚（すべて盤外）---
            .diagonalDownLeft2,
            .straightLeft2,
            .straightDown2,
            .knightDown2Right1,
            .knightDown2Left1,
            // --- 初期先読み 3 枚 ---
            .kingRight,
            .kingUp,
            .diagonalUpLeft2,
            // --- 1 回目の引き直し手札（再び盤外のみ）---
            .diagonalDownLeft2,
            .straightLeft2,
            .straightDown2,
            .knightDown2Right1,
            .knightDown2Left1,
            // --- 1 回目の引き直し先読み ---
            .kingRight,
            .kingUp,
            .diagonalUpLeft2,
            // --- 2 回目の引き直し手札（盤内へ進めるカードを含む）---
            .kingRight,
            .kingUp,
            .kingLeft,
            .knightUp1Right2,
            .straightRight2,
            // --- 2 回目の引き直し先読み ---
            .diagonalUpRight2,
            .straightUp2,
            .knightUp2Right1
        ])

        // 左下隅 (0,0) から開始し、連続手詰まりを強制
        let core = GameCore.makeTestInstance(deck: deck, current: GridPoint(x: 0, y: 0))

        // ペナルティは最初の支払いのみで +5 に留まるか
        XCTAssertEqual(core.penaltyCount, 5, "連続手詰まりでも追加ペナルティが加算されている")
        // 連続手詰まり処理後もプレイ継続できるか
        XCTAssertEqual(core.progress, .playing, "連続手詰まり処理後に playing 状態へ戻っていない")
        // 最終的な手札 5 枚の中に使用可能なカードがあるか
        if let current = core.current {
            let boardSize = core.mode.boardSize
            let playableExists = core.hand.contains { $0.move.canUse(from: current, boardSize: boardSize) }
            XCTAssertTrue(playableExists, "連続手詰まり後の手札に使用可能なカードが存在しない")
        } else {
            XCTFail("現在地が nil のままです")
        }
    }

    /// reset() が初期状態に戻すかを確認
    func testResetReturnsToInitialState() {
        // 上と同じデッキ構成で GameCore を生成し、ペナルティ適用後の状態から開始
        let deck = Deck.makeTestDeck(cards: [
            // --- 初期手札 5 枚（全て盤外でペナルティを誘発）---
            .diagonalDownLeft2,
            .straightLeft2,
            .straightDown2,
            .knightDown2Right1,
            .knightDown2Left1,
            // --- 初期先読みカード 3 枚 ---
            .kingRight,
            .kingUp,
            .diagonalUpLeft2,
            // --- 引き直し後の手札（盤内に進める 5 枚）---
            .kingUpLeft,
            .kingLeft,
            .kingDown,
            .knightUp1Right2,
            .straightRight2,
            // --- 引き直し後に表示される先読みカード 3 枚 ---
            .diagonalUpRight2,
            .straightUp2,
            .knightUp2Right1
        ])
        let core = GameCore.makeTestInstance(deck: deck, current: GridPoint(x: 0, y: 0))

        // 手札の中から使用可能なカードを 1 枚選び、実際に移動させる
        if let current = core.current,
           let index = core.hand.firstIndex(where: { $0.move.canUse(from: current, boardSize: core.mode.boardSize) }) {
            core.playCard(at: index)
        }
        // 移動が記録されているか確認
        XCTAssertEqual(core.moveCount, 1, "移動後の手数が想定通りではない")

        // reset() を実行し、全ての状態が初期化されるか検証
        core.reset()
        let centerPoint = GridPoint.center(of: core.mode.boardSize)
        XCTAssertEqual(core.current, centerPoint, "駒の位置が初期化されていない")
        XCTAssertEqual(core.moveCount, 0, "移動カウントがリセットされていない")
        XCTAssertEqual(core.penaltyCount, 0, "ペナルティカウントがリセットされていない")
        XCTAssertEqual(core.elapsedSeconds, 0, "所要時間がリセットされていない")
        XCTAssertEqual(core.progress, .playing, "ゲーム状態が playing に戻っていない")
        XCTAssertEqual(core.hand.count, 5, "手札枚数が初期値と異なる")
        XCTAssertEqual(core.nextCards.count, 3, "先読みカードが 3 枚確保されていない")
        // 盤面の踏破状態も初期化されているか
        XCTAssertTrue(core.board.isVisited(centerPoint), "盤面中央が踏破済みになっていない")
        XCTAssertFalse(core.board.isVisited(GridPoint(x: 0, y: 0)), "開始位置が踏破済みのままになっている")
    }

    /// 初期化直後・リセット直後に手札 5 枚が常に確保されるかを確認
    func testInitialAndResetHandCountIsFive() {
        // デフォルト初期化で手札が 5 枚配られているかチェック
        let core = GameCore()
        XCTAssertEqual(core.hand.count, 5, "初期化直後の手札枚数が 5 枚になっていない")

        // reset() 実行後も 5 枚に戻っているか確認
        core.reset()
        XCTAssertEqual(core.hand.count, 5, "リセット直後の手札枚数が 5 枚になっていない")
    }

    /// 同じシードでゲームをやり直したい場合に `startNewGame: false` が利用できるか検証
    func testResetCanReuseSameSeedWhenRequested() {
        // 5 枚の手札と 3 枚の先読みが明確に分かるよう、連続する 8 枚のカードを用意
        let preset: [MoveCard] = [
            .kingUp,
            .kingRight,
            .kingDown,
            .kingLeft,
            .kingUpLeft,
            .knightUp1Right2,
            .knightUp2Right1,
            .straightUp2
        ]
        let deck = Deck.makeTestDeck(cards: preset)
        let core = GameCore.makeTestInstance(deck: deck)

        // リセット前の手札と先読み構成を控えておき、後で比較できるようにする
        let initialHand = core.hand.map { $0.move }
        let initialNext = core.nextCards.map { $0.move }

        // 同一シードを維持するモードでリセットし、手札が再現されるかを確認
        core.reset(startNewGame: false)

        XCTAssertEqual(core.hand.map { $0.move }, initialHand, "同一シードでのリセット時は手札構成が一致するべき")
        XCTAssertEqual(core.nextCards.map { $0.move }, initialNext, "同一シードでのリセット時は先読み構成が一致するべき")
    }

    /// クラシカルチャレンジでスポーン選択が必須になるか検証
    func testClassicalModeRequiresSpawnSelection() {
        let deck = Deck.makeTestDeck(
            cards: [
                .knightUp2Right1,
                .knightDown2Left1,
                .knightUp1Right2,
                .knightUp1Left2,
                .knightDown1Right2,
                .knightUp2Left1,
                .knightDown2Right1,
                .knightDown1Left2
            ],
            configuration: .classicalChallenge
        )
        let core = GameCore.makeTestInstance(deck: deck, current: nil, mode: .classicalChallenge)

        XCTAssertNil(core.current, "クラシカルチャレンジでは初期位置が未決定のはず")
        XCTAssertEqual(core.progress, .awaitingSpawn)

        let spawnPoint = GridPoint(x: 3, y: 3)
        core.simulateSpawnSelection(forTesting: spawnPoint)

        XCTAssertEqual(core.current, spawnPoint)
        XCTAssertTrue(core.board.isVisited(spawnPoint))
        XCTAssertEqual(core.progress, .playing)
    }

    /// クラシカルチャレンジで既踏マスへ戻った際にペナルティが加算されるか検証
    func testRevisitPenaltyAppliedInClassicalMode() {
        let deck = Deck.makeTestDeck(
            cards: [
                .knightUp2Right1,
                .knightDown2Left1,
                .knightUp1Right2,
                .knightUp1Left2,
                .knightDown1Right2,
                .knightUp2Left1,
                .knightDown2Right1,
                .knightDown1Left2,
                .knightUp1Right2,
                .knightDown1Left2
            ],
            configuration: .classicalChallenge
        )
        let core = GameCore.makeTestInstance(deck: deck, current: nil, mode: .classicalChallenge)
        let spawnPoint = GridPoint(x: 2, y: 2)
        core.simulateSpawnSelection(forTesting: spawnPoint)

        XCTAssertEqual(core.penaltyCount, 0)

        guard let firstMoveIndex = core.hand.firstIndex(where: { $0.move == .knightUp2Right1 }) else {
            XCTFail("想定していた移動カードが手札に存在しません")
            return
        }
        core.playCard(at: firstMoveIndex)
        XCTAssertEqual(core.penaltyCount, 0)

        guard let returnIndex = core.hand.firstIndex(where: { $0.move == .knightDown2Left1 }) else {
            XCTFail("戻り用のカードが手札から見つかりません")
            return
        }
        core.playCard(at: returnIndex)

        XCTAssertEqual(core.penaltyCount, core.mode.revisitPenaltyCost, "既踏マスへの再訪ペナルティが適用されていない")
    }

    /// クラシカルチャレンジの手動引き直しでモード固有のペナルティ量が適用されるか検証
    func testManualPenaltyUsesModeCost() {
        let deck = Deck.makeTestDeck(
            cards: [
                .knightUp2Right1,
                .knightDown2Left1,
                .knightUp1Right2,
                .knightUp1Left2,
                .knightDown1Right2,
                .knightUp2Left1,
                .knightDown2Right1,
                .knightDown1Left2,
                .knightUp1Right2,
                .knightDown1Left2
            ],
            configuration: .classicalChallenge
        )
        let core = GameCore.makeTestInstance(deck: deck, current: nil, mode: .classicalChallenge)
        core.simulateSpawnSelection(forTesting: GridPoint(x: 1, y: 1))

        XCTAssertEqual(core.penaltyCount, 0)
        core.applyManualPenaltyRedraw()
        XCTAssertEqual(core.penaltyCount, core.mode.manualRedrawPenaltyCost)
        XCTAssertEqual(core.lastPenaltyAmount, core.mode.manualRedrawPenaltyCost)
        XCTAssertEqual(core.progress, .playing)
    }

    /// 手札の方向ソート設定が期待通りの順序へ並べ替えられるか検証
    func testHandOrderingDirectionSortReordersHand() {
        let deck = Deck.makeTestDeck(cards: [
            .kingRight,
            .diagonalUpLeft2,
            .straightLeft2,
            .kingUp,
            .diagonalDownLeft2,
            .kingLeft,
            .straightUp2,
            .kingDown,
            .kingUpRight
        ])
        let core = GameCore.makeTestInstance(deck: deck)

        // 方向ソートへ切り替えて順序が調整されるか確認
        core.updateHandOrderingStrategy(.directionSorted)

        let expected: [MoveCard] = [
            .diagonalUpLeft2,
            .straightLeft2,
            .diagonalDownLeft2,
            .kingUp,
            .kingRight
        ]
        XCTAssertEqual(core.hand.map(\.move), expected, "方向ソート設定で手札が期待通りに並んでいない")
    }

    /// 方向ソート設定でカードを使用した後も新しい手札が正しい順序に保たれるか検証
    func testHandOrderingDirectionSortAfterDraw() {
        let deck = Deck.makeTestDeck(cards: [
            .kingRight,
            .diagonalUpLeft2,
            .straightLeft2,
            .kingUp,
            .diagonalDownLeft2,
            .kingLeft,
            .straightUp2,
            .kingDown,
            .kingUpRight
        ])
        let core = GameCore.makeTestInstance(deck: deck)

        core.updateHandOrderingStrategy(.directionSorted)

        guard let playIndex = core.hand.firstIndex(where: { $0.move == .kingRight }) else {
            XCTFail("想定したカードが手札に存在しません")
            return
        }

        core.playCard(at: playIndex)

        let expected: [MoveCard] = [
            .diagonalUpLeft2,
            .straightLeft2,
            .diagonalDownLeft2,
            .kingLeft,
            .kingUp
        ]
        XCTAssertEqual(core.hand.map(\.move), expected, "カード使用後の方向ソート結果が期待と異なります")
    }

    /// スコア計算が「手数×10 + 経過秒数」で行われることを確認
    func testScoreCalculationUsesPointsFormula() {
        let core = GameCore()
        // テスト用に任意のメトリクスを設定
        core.overrideMetricsForTesting(moveCount: 12, penaltyCount: 5, elapsedSeconds: 37)

        XCTAssertEqual(core.totalMoveCount, 17, "合計手数の算出が期待値と異なる")
        XCTAssertEqual(core.score, 207, "ポイント計算が仕様と一致していない")
    }
}
