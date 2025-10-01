import XCTest
@testable import Game

/// GameCore の主要メソッドを検証するテスト
final class GameCoreTests: XCTestCase {
    /// 手札が全て盤外となった場合にペナルティが加算されるかを確認
    func testDeadlockPenaltyApplied() {
        // --- テスト用デッキ構築 ---
        // 新実装では「先頭が最初にドローされる」ため、引かせたい順に並べる
        let deck = Deck.makeTestDeck(cards: [
            // --- 初期手札スロット 5 枠（すべて盤外になるカード）---
            .diagonalDownLeft2,
            .straightLeft2,
            .straightDown2,
            .knightDown2Right1,
            .knightDown2Left1,
            // --- 初期先読み 3 枚（手札補充時にこの順で出現）---
            .kingRight,
            .kingUp,
            .diagonalUpLeft2,
            // --- 引き直し後の手札スロット 5 枠（盤内へ移動可能）---
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
        // 引き直し後の手札スタック数が 5 種類確保されているか
        XCTAssertEqual(core.handStacks.count, 5, "引き直し後の手札スタック数が 5 種類ではない")
        // 引き直し後の手札に使用可能なカードが少なくとも 1 枚あるか
        if let current = core.current {
            let moves = core.availableMoves(current: current)
            XCTAssertFalse(moves.isEmpty, "引き直し後の手札に利用可能なカードが存在しない")
        } else {
            XCTFail("現在地が nil のままです")
        }
        // 先読みカードが 3 枚揃っているか（NEXT 表示用）
        XCTAssertEqual(core.nextCards.count, 3, "引き直し後の先読みカードが 3 枚補充されていない")
    }

    /// availableMoves() が盤外カードを除外し、座標順へ整列するかを検証
    func testAvailableMovesFiltersAndSortsByDestination() {
        let deck = Deck.makeTestDeck(cards: [
            .kingLeft,
            .kingRight,
            .kingUp,
            .straightRight2,
            .knightUp1Right2,
            .straightUp2,
            .kingDown,
            .straightLeft2,
            .straightDown2
        ])
        let core = GameCore.makeTestInstance(deck: deck, current: GridPoint(x: 0, y: 0))

        let moves = core.availableMoves()
        XCTAssertEqual(moves.map { $0.destination }, [
            GridPoint(x: 1, y: 0),
            GridPoint(x: 2, y: 0),
            GridPoint(x: 0, y: 1),
            GridPoint(x: 2, y: 1)
        ])
    }

    /// 手詰まり後に再び手詰まりが発生した場合でも追加ペナルティが加算されないことを確認
    func testConsecutiveDeadlockDoesNotAddExtraPenalty() {
        // --- テスト用デッキ構築 ---
        // 2 回連続で盤外カードだけが配られ、最後に盤内へ進めるカードが揃うシナリオを用意
        let deck = Deck.makeTestDeck(cards: [
            // --- 初期手札スロット 5 枠（すべて盤外）---
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
        // 最終的な手札スタック 5 種類の中に使用可能なカードがあるか
        if let current = core.current {
            let moves = core.availableMoves(current: current)
            XCTAssertFalse(moves.isEmpty, "連続手詰まり後の手札に使用可能なカードが存在しない")
        } else {
            XCTFail("現在地が nil のままです")
        }
    }

    /// スタック分割設定でも同一座標カードが隣接して列挙されるかを検証
    func testAvailableMovesKeepsDuplicateDestinationsAdjacent() {
        let regulation = GameMode.Regulation(
            boardSize: BoardGeometry.standardSize,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: false,
            deckPreset: .standard,
            spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: BoardGeometry.standardSize)),
            penalties: GameMode.PenaltySettings(
                deadlockPenaltyCost: 5,
                manualRedrawPenaltyCost: 5,
                manualDiscardPenaltyCost: 1,
                revisitPenaltyCost: 0
            )
        )
        let customMode = GameMode(
            identifier: .freeCustom,
            displayName: "テスト用",
            regulation: regulation,
            leaderboardEligible: false
        )

        let deck = Deck.makeTestDeck(cards: [
            .kingUp,
            .kingUp,
            .kingRight,
            .kingDown,
            .kingLeft,
            .diagonalUpRight2,
            .diagonalUpLeft2,
            .knightUp1Right2,
            .knightUp1Left2
        ])

        let core = GameCore.makeTestInstance(deck: deck, mode: customMode)

        let moves = core.availableMoves()
        let destination = GridPoint(x: 2, y: 3)
        let matchingIndices = moves.indices.filter { moves[$0].destination == destination }
        XCTAssertEqual(matchingIndices.count, 2, "同一座標へのカードが 2 枚列挙されていない")
        if let first = matchingIndices.first {
            XCTAssertEqual(matchingIndices, [first, first + 1], "同一座標カードが隣接順になっていない")
            XCTAssertNotEqual(moves[first].stackID, moves[first + 1].stackID, "異なるスタックを識別できていない")
        } else {
            XCTFail("対象座標のカードが見つからない")
        }
    }

    /// 複数候補ベクトルを持つカードでも availableMoves と playCard(at:selecting:) で狙った方向を選べるかを検証
    func testPlayCardSelectingMoveVectorSupportsMultipleVectors() {
        // テスト実行中のみキング上カードへ上下 2 ベクトルを付与し、複数候補カードを再現する
        MoveCard.setTestMovementVectors([
            MoveVector(dx: 0, dy: 1),
            MoveVector(dx: 0, dy: -1)
        ], for: .kingUp)
        defer { MoveCard.setTestMovementVectors(nil, for: .kingUp) }

        let deck = Deck.makeTestDeck(cards: [
            .kingUp,
            .kingRight,
            .kingDown,
            .kingLeft,
            .kingUpLeft,
            .straightUp2,
            .straightRight2,
            .diagonalUpRight2,
            .diagonalUpLeft2,
            .straightDown2
        ])
        let core = GameCore.makeTestInstance(deck: deck, current: GridPoint(x: 2, y: 2))

        let moves = core.availableMoves()
        let kingMoves = moves.filter { $0.card.move == .kingUp }

        XCTAssertEqual(kingMoves.count, 2, "複数候補カードのベクトル展開数が想定と異なる")
        XCTAssertEqual(
            Set(kingMoves.map { $0.destination }),
            Set([
                GridPoint(x: 2, y: 3),
                GridPoint(x: 2, y: 1)
            ]),
            "複数候補カードの移動先が正しく算出されていない"
        )

        guard let downwardMove = kingMoves.first(where: { $0.moveVector.dy == -1 }) else {
            XCTFail("下方向へ移動する候補が見つからない")
            return
        }

        // playCard(at:selecting:) に下方向ベクトルを指定し、意図した方向だけが実行されることを確認する
        core.playCard(at: downwardMove.stackIndex, selecting: downwardMove.moveVector)

        XCTAssertEqual(core.current, GridPoint(x: 2, y: 1), "選択したベクトルで移動できていない")
        XCTAssertEqual(core.moveCount, 1, "移動回数の加算が行われていない")
        XCTAssertTrue(core.board.isVisited(GridPoint(x: 2, y: 1)), "移動後マスが踏破扱いになっていない")
        XCTAssertFalse(core.board.isVisited(GridPoint(x: 2, y: 3)), "未選択方向まで踏破扱いになっている")

        // --- 再検証: 上方向を選択するケース ---
        // 新しい GameCore を生成し、今度は上方向ベクトルを playCard(using:) で選択できることを確認する。
        let secondCore = GameCore.makeTestInstance(deck: deck, current: GridPoint(x: 2, y: 2))
        let secondMoves = secondCore.availableMoves()
        guard let upwardMove = secondMoves.first(where: { $0.card.move == .kingUp && $0.moveVector.dy == 1 }) else {
            XCTFail("上方向へ移動する候補が再生成後に見つからない")
            return
        }

        secondCore.playCard(using: upwardMove)
        XCTAssertEqual(secondCore.current, GridPoint(x: 2, y: 3), "ResolvedCardMove でも上方向へ移動できていない")
    }

    /// 盤面タップで複数候補と通常カードが同じマスへ到達できる場合、通常カードが優先されることを確認
    func testHandleTapPrefersSingleVectorCardWhenDestinationOverlaps() {
        // キング上カードへ 2 方向ベクトルを付与し、複数候補カードと通常カードの競合状況を作り出す
        MoveCard.setTestMovementVectors([
            MoveVector(dx: 0, dy: 1),
            MoveVector(dx: 1, dy: 1)
        ], for: .kingUp)
        defer { MoveCard.setTestMovementVectors(nil, for: .kingUp) }

        // 先頭スタックに複数候補カード、2 番目に通常カードが来るようにデッキを並べる
        let deck = Deck.makeTestDeck(cards: [
            .kingUp,
            .kingUpRight,
            .kingDown,
            .kingLeft,
            .kingUpLeft,
            .straightUp2,
            .straightRight2,
            .straightDown2
        ])
        let core = GameCore.makeTestInstance(deck: deck, current: GridPoint(x: 2, y: 2))

        // (3,3) のマスは通常カード（キング右上）と複数候補カード双方で到達可能
        let destination = GridPoint(x: 3, y: 3)

        guard let resolved = core.resolvedMoveForBoardTap(at: destination) else {
            XCTFail("盤面タップ候補の算出に失敗しました")
            return
        }

        // 優先順位ロジックにより、通常カード（キング右上）が選択されることを検証
        XCTAssertEqual(resolved.stackIndex, 1, "通常カードのスタックが優先されていません")
        XCTAssertEqual(resolved.card.move, .kingUpRight, "通常カードが選択されていません")
        XCTAssertEqual(resolved.moveVector, MoveVector(dx: 1, dy: 1), "通常カードのベクトルが設定されていません")

#if canImport(SpriteKit)
        // SpriteKit 利用環境では handleTap(at:) 経由でも同じ候補が選択されることを確認する
        core.handleTap(at: destination)
        guard let request = core.boardTapPlayRequest else {
            XCTFail("BoardTapPlayRequest が生成されていません")
            return
        }
        XCTAssertEqual(request.resolvedMove, resolved, "handleTap(at:) の結果が優先順位と一致していません")
#endif
    }

    /// reset() が初期状態に戻すかを確認
    func testResetReturnsToInitialState() {
        // 上と同じデッキ構成で GameCore を生成し、ペナルティ適用後の状態から開始
        let deck = Deck.makeTestDeck(cards: [
            // --- 初期手札スロット 5 枠（全て盤外でペナルティを誘発）---
            .diagonalDownLeft2,
            .straightLeft2,
            .straightDown2,
            .knightDown2Right1,
            .knightDown2Left1,
            // --- 初期先読みカード 3 枚 ---
            .kingRight,
            .kingUp,
            .diagonalUpLeft2,
            // --- 引き直し後の手札スロット（盤内に進める 5 種類）---
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
        if let resolved = core.availableMoves().first {
            core.playCard(using: resolved)
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
        XCTAssertEqual(core.handStacks.count, 5, "手札スタック数が初期値と異なる")
        XCTAssertEqual(core.nextCards.count, 3, "先読みカードが 3 枚確保されていない")
        // 盤面の踏破状態も初期化されているか
        XCTAssertTrue(core.board.isVisited(centerPoint), "盤面中央が踏破済みになっていない")
        XCTAssertFalse(core.board.isVisited(GridPoint(x: 0, y: 0)), "開始位置が踏破済みのままになっている")
    }

    /// 初期化直後・リセット直後に手札スタック 5 種類が常に確保されるかを確認
    func testInitialAndResetHandCountIsFive() {
        // デフォルト初期化で手札スロットが 5 枠配られているかチェック
        let core = GameCore()
        XCTAssertEqual(core.handStacks.count, 5, "初期化直後の手札スタック数が 5 種類になっていない")

        // reset() 実行後も 5 スロットに戻っているか確認
        core.reset()
        XCTAssertEqual(core.handStacks.count, 5, "リセット直後の手札スタック数が 5 種類になっていない")
    }

    /// 連続して同じカードをドローした場合にスタックへ積み増されるか検証
    func testHandRefillStacksAccumulatesDuplicates() {
        let deck = Deck.makeTestDeck(cards: [
            .kingRight,
            .kingRight,
            .kingUp,
            .kingDown,
            .kingLeft,
            .knightUp1Right2,
            .straightUp2,
            .diagonalUpRight2,
            .kingUpRight,
            .diagonalUpLeft2
        ])
        let core = GameCore.makeTestInstance(deck: deck)

        // 初期手札ではキング右が 2 枚スタックされ、他の 4 種は単枚のはず
        XCTAssertEqual(core.handStacks.count, 5)
        XCTAssertEqual(core.handStacks.first?.count, 2)
        XCTAssertEqual(
            core.handStacks.compactMap { $0.topCard?.move },
            [.kingRight, .kingUp, .kingDown, .kingLeft, .knightUp1Right2]
        )
        XCTAssertEqual(
            core.nextCards.map { $0.move },
            [.straightUp2, .diagonalUpRight2, .kingUpRight]
        )

        // スタック枚数が 2 枚のスロットをプレイしても、残り 1 枚が保持され NEXT は消費されない
        core.playCard(at: 0)
        XCTAssertEqual(core.handStacks.count, 5)
        XCTAssertEqual(core.handStacks.first?.count, 1)
        XCTAssertEqual(core.handStacks.first?.topCard?.move, .kingRight)
        XCTAssertEqual(
            core.nextCards.map { $0.move },
            [.straightUp2, .diagonalUpRight2, .kingUpRight]
        )

        // 単枚スタックを消費すると NEXT 先頭が新規スタックとして補充される
        if let targetIndex = core.handStacks.enumerated().first(where: { $0.element.topCard?.move == .kingUp })?.offset {
            core.playCard(at: targetIndex)
        } else {
            XCTFail("想定していたキング上のスタックが見つかりません")
            return
        }

        XCTAssertEqual(core.handStacks.count, 5)
        XCTAssertTrue(core.handStacks.contains(where: { $0.topCard?.move == .straightUp2 }))
        XCTAssertEqual(
            core.nextCards.map { $0.move },
            [.diagonalUpRight2, .kingUpRight, .diagonalUpLeft2]
        )
    }

    /// HandManager を介した補充処理が playCard と reset から正しく利用されることを確認
    func testHandManagerHandlesPlayAndResetFlow() {
        // 手札 5 枚 + NEXT 3 枚 + 追加入れ替え用 2 枚を明示的に用意
        let deck = Deck.makeTestDeck(cards: [
            .kingUp,
            .kingRight,
            .kingLeft,
            .kingDown,
            .kingUpLeft,
            .straightUp2,
            .straightRight2,
            .straightDown2,
            .diagonalUpLeft2,
            .diagonalUpRight2
        ])
        let core = GameCore.makeTestInstance(deck: deck)
        let manager = core.handManager

        // 初期構成を控えておき、reset(startNewGame: false) で再現できるか検証する
        let initialHandMoves = core.handStacks.compactMap { $0.topCard?.move }
        let initialNextMoves = core.nextCards.map { $0.move }
        XCTAssertEqual(initialHandMoves, [.kingUp, .kingRight, .kingLeft, .kingDown, .kingUpLeft])
        XCTAssertEqual(initialNextMoves, [.straightUp2, .straightRight2, .straightDown2])

        // 先頭スタックを使用し、NEXT の先頭が差し戻されることを確認
        core.playCard(at: 0)
        XCTAssertTrue(manager === core.handManager, "playCard 後も HandManager インスタンスが差し替わらないこと")
        XCTAssertEqual(manager.handStacks.count, 5, "HandManager 経由でも手札スロット数が維持されるべき")
        XCTAssertEqual(manager.handStacks.first?.topCard?.move, .straightUp2, "NEXT の先頭カードが空きスロットへ戻っていない")
        XCTAssertEqual(
            manager.nextCards.map { $0.move },
            [.straightRight2, .straightDown2, .diagonalUpLeft2],
            "手札補充後の NEXT 構成が想定と一致しない"
        )

        // 同一シードでリセットすると初期配列へ戻り、HandManager も再利用されること
        core.reset(startNewGame: false)
        XCTAssertTrue(manager === core.handManager, "reset で HandManager が再生成されるのは望ましくない")
        XCTAssertEqual(core.handStacks.compactMap { $0.topCard?.move }, initialHandMoves, "リセット後の手札構成が初期値と異なる")
        XCTAssertEqual(core.nextCards.map { $0.move }, initialNextMoves, "リセット後の NEXT 構成が初期値と異なる")
    }

    /// 挿入順設定でカードを使用した際、空いたスロットに新しいカードが同じ位置で補充されるか検証
    func testInsertionOrderRefillKeepsSlotPosition() {
        let deck = Deck.makeTestDeck(cards: [
            // --- 初期手札 5 枚（すべて異なるカード）---
            .kingUp,
            .kingRight,
            .kingDown,
            .kingLeft,
            .kingUpLeft,
            // --- 先読み 3 枚（手札補充の順番）---
            .knightUp1Right2,
            .straightUp2,
            .diagonalUpRight2,
            // --- 先読み補充用の追加カード ---
            .kingUpRight
        ])
        let core = GameCore.makeTestInstance(deck: deck)

        XCTAssertEqual(
            core.handStacks.compactMap { $0.topCard?.move },
            [.kingUp, .kingRight, .kingDown, .kingLeft, .kingUpLeft],
            "初期手札の想定順序と一致しません"
        )

        // 2 番目のスロット（キング右）を使用すると、その位置に NEXT 先頭が補充されるはず
        core.playCard(at: 1)

        XCTAssertEqual(
            core.handStacks.compactMap { $0.topCard?.move },
            [.kingUp, .knightUp1Right2, .kingDown, .kingLeft, .kingUpLeft],
            "挿入順の設定で使用したスロットが末尾に移動してしまっています"
        )
        XCTAssertEqual(
            core.nextCards.map { $0.move },
            [.straightUp2, .diagonalUpRight2, .kingUpRight],
            "NEXT キューの更新順序が想定と異なります"
        )
    }

    /// 先読みカードが既存スタックと重なった場合でも空きスロットが正しく埋まるか検証
    func testInsertionOrderRefillHandlesStackingBeforeFillingGap() {
        let deck = Deck.makeTestDeck(cards: [
            // --- 初期手札 5 枚 ---
            .kingUp,
            .kingRight,
            .kingDown,
            .kingLeft,
            .knightUp1Right2,
            // --- 先読み 3 枚（最初に補充されるカード列）---
            .kingRight,
            .straightUp2,
            .diagonalUpRight2,
            // --- 先読み補充用の追加カード ---
            .kingUpRight,
            .knightUp2Right1
        ])
        let core = GameCore.makeTestInstance(deck: deck)

        // 3 番目のスロット（キング下）を使用し、空きが出来た位置に注目する
        core.playCard(at: 2)

        // 先読みの 1 枚目（キング右）は既存スタックへ積み増され、2 枚目が空きスロットに入る想定
        XCTAssertEqual(core.handStacks.count, 5, "手札スロット数が 5 に戻っていません")
        XCTAssertEqual(
            core.handStacks.compactMap { $0.topCard?.move },
            [.kingUp, .kingRight, .straightUp2, .kingLeft, .knightUp1Right2],
            "空きスロットに新カードが補充されていません"
        )
        let kingRightVectors = MoveCard.kingRight.movementVectors
        if let rightStack = core.handStacks.first(where: { $0.representativeVectors == kingRightVectors }) {
            XCTAssertEqual(rightStack.count, 2, "重なったカード枚数が想定と異なります")
        } else {
            XCTFail("キング右のスタックが見つかりません")
        }
        XCTAssertEqual(
            core.nextCards.map { $0.move },
            [.diagonalUpRight2, .kingUpRight, .knightUp2Right1],
            "先読みの補充結果が想定と異なります"
        )
    }

    /// 捨て札ペナルティでスタックを削除し、新しいカードが補充されるか検証
    func testManualDiscardRemovesStackAndAddsPenalty() {
        let deck = Deck.makeTestDeck(cards: [
            // --- 初期手札構成（キング右だけ 2 枚スタックさせる）---
            .kingRight,
            .kingRight,
            .kingUp,
            .kingDown,
            .kingLeft,
            .knightUp1Right2,
            // --- 先読み 3 枚 ---
            .straightUp2,
            .diagonalUpRight2,
            .kingUpRight,
            // --- 捨て札後に補充するための追加カード ---
            .straightDown2
        ])
        let core = GameCore.makeTestInstance(deck: deck)

        XCTAssertEqual(core.handStacks.count, 5)
        guard let targetStack = core.handStacks.first else {
            XCTFail("初期手札が取得できません")
            return
        }
        XCTAssertEqual(targetStack.count, 2)

        core.beginManualDiscardSelection()
        XCTAssertTrue(core.isAwaitingManualDiscardSelection)

        let initialPenalty = core.penaltyCount
        let discardResult = core.discardHandStack(withID: targetStack.id)
        XCTAssertTrue(discardResult, "捨て札処理が成功しませんでした")

        XCTAssertFalse(core.isAwaitingManualDiscardSelection)
        XCTAssertEqual(core.penaltyCount, initialPenalty + core.mode.manualDiscardPenaltyCost)
        XCTAssertEqual(core.handStacks.count, 5)
        let kingRightVectors = MoveCard.kingRight.movementVectors
        let straightUpVectors = MoveCard.straightUp2.movementVectors
        XCTAssertFalse(core.handStacks.contains(where: { $0.representativeVectors == kingRightVectors }))
        XCTAssertTrue(core.handStacks.contains(where: { $0.representativeVectors == straightUpVectors }))
        XCTAssertEqual(
            core.nextCards.map { $0.move },
            [.diagonalUpRight2, .kingUpRight, .straightDown2]
        )
    }

    /// 同じシードでゲームをやり直したい場合に `startNewGame: false` が利用できるか検証
    func testResetCanReuseSameSeedWhenRequested() {
        // 5 スロット分の手札と 3 枚の先読みが明確に分かるよう、連続する 8 枚のカードを用意
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
        let initialHand = core.handStacks.compactMap { $0.topCard?.move }
        let initialNext = core.nextCards.map { $0.move }

        // 同一シードを維持するモードでリセットし、手札が再現されるかを確認
        core.reset(startNewGame: false)

        XCTAssertEqual(core.handStacks.compactMap { $0.topCard?.move }, initialHand, "同一シードでのリセット時は手札構成が一致するべき")
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
        XCTAssertFalse(core.hasRevisitedTile, "初期状態で再訪フラグが立っていてはいけません")

        guard let firstMoveIndex = core.handStacks.enumerated().first(where: { _, stack in
            stack.topCard?.move == .knightUp2Right1
        })?.offset else {
            XCTFail("想定していた移動カードが手札に存在しません")
            return
        }
        core.playCard(at: firstMoveIndex)
        XCTAssertEqual(core.penaltyCount, 0)
        XCTAssertFalse(core.hasRevisitedTile, "未踏マスを移動した直後はフラグが false のままの想定です")

        guard let returnIndex = core.handStacks.enumerated().first(where: { _, stack in
            stack.topCard?.move == .knightDown2Left1
        })?.offset else {
            XCTFail("戻り用のカードが手札から見つかりません")
            return
        }
        core.playCard(at: returnIndex)

        XCTAssertEqual(core.penaltyCount, core.mode.revisitPenaltyCost, "既踏マスへの再訪ペナルティが適用されていない")
        XCTAssertTrue(core.hasRevisitedTile, "既踏マスへ戻った場合はフラグが立つべきです")
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
        XCTAssertEqual(core.handStacks.compactMap { $0.topCard?.move }, expected, "方向ソート設定で手札が期待通りに並んでいない")
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

        guard let playIndex = core.handStacks.enumerated().first(where: { _, stack in
            stack.topCard?.move == .kingRight
        })?.offset else {
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
        XCTAssertEqual(core.handStacks.compactMap { $0.topCard?.move }, expected, "カード使用後の方向ソート結果が期待と異なります")
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
