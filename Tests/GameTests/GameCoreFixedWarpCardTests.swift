import XCTest
@testable import Game

/// 固定座標ワープカードに関する挙動を検証するテスト
final class GameCoreFixedWarpCardTests: XCTestCase {
    /// テストで共通利用するスポーン座標（標準盤の中央）
    private let spawnPoint = GridPoint(x: 2, y: 2)
    /// テスト用に有効とする固定ワープ先（盤面左下）
    private let validTargetA = GridPoint(x: 0, y: 0)
    /// テスト用に有効とする固定ワープ先（盤面右上）
    private let validTargetB = GridPoint(x: 4, y: 4)
    /// 盤面から除外する障害物マス（固定ワープ候補に含まれるが弾かれる想定）
    private let impassableTarget = GridPoint(x: 1, y: 1)
    /// 盤外として除外される座標（バリデーションが正しく動作するか確認するためのダミー）
    private let outsideTarget = GridPoint(x: 5, y: 5)

    /// 固定ワープカードを含むレギュレーションを生成するヘルパー
    private func makeRegulation() -> GameMode.Regulation {
        let rawTargets: [MoveCard: [GridPoint]] = [
            .fixedWarp: [
                validTargetA,
                impassableTarget, // 障害物として除外される想定
                outsideTarget,    // 盤外のため除外される想定
                validTargetB,
                validTargetA      // 重複チェックが働いて 2 回目は無視される
            ]
        ]

        return GameMode.Regulation(
            boardSize: BoardGeometry.standardSize,
            handSize: 5,
            nextPreviewCount: 0,
            allowsStacking: true,
            deckPreset: .standard,
            spawnRule: .fixed(spawnPoint),
            penalties: GameMode.PenaltySettings(
                deadlockPenaltyCost: 0,
                manualRedrawPenaltyCost: 0,
                manualDiscardPenaltyCost: 0,
                revisitPenaltyCost: 0
            ),
            impassableTilePoints: [impassableTarget],
            fixedWarpCardTargets: rawTargets
        )
    }

    /// 固定ワープカードが必ず手札へ配られるテスト用デッキを生成する
    /// - Parameters:
    ///   - mode: 目的地プールを参照する対象モード
    ///   - destinations: ワープ目的地の割り当て順を明示したい場合に指定（nil の場合はモード既定順）
    private func makeDeck(for mode: GameMode, destinations: [GridPoint]? = nil) -> Deck {
        let configuration = mode.deckConfiguration
        let preloadCards: [MoveCard] = [
            .fixedWarp,
            .kingUp,
            .kingRight,
            .kingDown,
            .kingLeft
        ]
        let warpDestinations = destinations ?? mode.fixedWarpDestinationPool
        return Deck.makeTestDeck(
            cards: preloadCards,
            configuration: configuration,
            fixedWarpDestinations: warpDestinations
        )
    }

    /// availableMoves() がモード定義のターゲットを尊重し、盤外・障害物・既踏マスを除外することを確認する
    func testFixedWarpAvailableMovesRespectsModeTargets() throws {
        // --- モードと GameCore を初期化し、片方のワープ先を既踏扱いにする ---
        let regulation = makeRegulation()
        let mode = GameMode(
            identifier: .freeCustom,
            displayName: "固定ワープ候補テスト",
            regulation: regulation,
            leaderboardEligible: false
        )
        let deck = makeDeck(for: mode, destinations: [validTargetB])
        let initialVisited = [spawnPoint, validTargetB]
        let core = GameCore.makeTestInstance(
            deck: deck,
            current: spawnPoint,
            mode: mode,
            initialVisitedPoints: initialVisited
        )

        // --- バリデーション済みターゲットが期待通りに整列しているか検証 ---
        let sanitizedTargets = mode.fixedWarpCardTargets[.fixedWarp]
        XCTAssertEqual(
            sanitizedTargets,
            [validTargetA, validTargetB],
            "固定ワープ用ターゲットのバリデーション結果が想定と異なります"
        )

        // --- availableMoves() で候補を取得し、既踏マスが除外されていることを確認 ---
        let moves = core.availableMoves()
        let warpCandidates = moves.filter { $0.card.move == .fixedWarp }
        XCTAssertEqual(warpCandidates.count, 1, "目的地が 1 件のみのため候補も単一になる想定です")

        let candidate = try XCTUnwrap(warpCandidates.first)
        XCTAssertEqual(candidate.destination, validTargetB, "カードに割り当てた目的地と一致していません")
        XCTAssertEqual(candidate.card.fixedWarpDestination, validTargetB, "カード内部の目的地メタデータが想定と異なります")
        XCTAssertEqual(candidate.path, [validTargetB], "通過マスが固定ワープ仕様と異なります")
    }

    /// 盤面タップによる選択が固定ワープ候補と整合することを検証する
    func testFixedWarpBoardTapSelectionReturnsMatchingMove() throws {
        // --- ワープ候補をすべて未踏状態にし、タップ選択を実行 ---
        let regulation = makeRegulation()
        let mode = GameMode(
            identifier: .freeCustom,
            displayName: "固定ワープタップテスト",
            regulation: regulation,
            leaderboardEligible: false
        )
        let deck = makeDeck(for: mode, destinations: [validTargetB])
        let core = GameCore.makeTestInstance(
            deck: deck,
            current: spawnPoint,
            mode: mode,
            initialVisitedPoints: [spawnPoint]
        )

        // --- 盤面タップで右上ターゲットを選択し、固定ワープ候補が返ることを確認 ---
        let tapTarget = validTargetB
        let resolved = try XCTUnwrap(core.resolvedMoveForBoardTap(at: tapTarget), "固定ワープ候補がタップ選択で取得できません")
        XCTAssertEqual(resolved.card.move, .fixedWarp, "盤面タップで取得したカード種別が固定ワープではありません")
        XCTAssertEqual(resolved.destination, tapTarget, "盤面タップの到達先が想定と一致しません")
        XCTAssertEqual(resolved.card.fixedWarpDestination, tapTarget, "カード内部の目的地がタップ先と一致していません")
    }

    /// playCard(using:) が固定ワープカードの踏破処理と最終位置更新を正しく行うことを確認する
    func testPlayCardWithFixedWarpUpdatesBoardState() throws {
        // --- 初期化して availableMoves() から固定ワープ候補を取得 ---
        let regulation = makeRegulation()
        let mode = GameMode(
            identifier: .freeCustom,
            displayName: "固定ワープ実行テスト",
            regulation: regulation,
            leaderboardEligible: false
        )
        let deck = makeDeck(for: mode, destinations: [validTargetA])
        let core = GameCore.makeTestInstance(
            deck: deck,
            current: spawnPoint,
            mode: mode,
            initialVisitedPoints: [spawnPoint]
        )

        let moves = core.availableMoves()
        let warpCandidates = moves.filter { $0.card.move == .fixedWarp }
        XCTAssertEqual(warpCandidates.count, 1, "カードごとに単一のワープ先を提示する想定です")

        // --- 左下ターゲットを選択して実際にカードをプレイ ---
        let targetMove = try XCTUnwrap(warpCandidates.first)
        core.playCard(using: targetMove)

        // --- 最終位置や踏破状態が更新されていることを確認 ---
        XCTAssertEqual(core.current, validTargetA, "固定ワープ後の現在地が期待値と異なります")
        XCTAssertTrue(core.board.isVisited(validTargetA), "ワープ先が踏破扱いになっていません")
        XCTAssertEqual(core.moveCount, 1, "固定ワープの使用で手数が加算されていません")
        XCTAssertFalse(core.hasRevisitedTile, "固定ワープ初回使用で再訪扱いになるのは想定外です")
    }

    /// 固定ワープカードのターゲットが未指定でも自動生成され、常に使用可能になることを確認する
    func testFixedWarpTargetsFallbackGeneratesTraversableTiles() throws {
        // --- 障害物を含むワープ訓練用レギュレーションを用意（固定ターゲットは未指定） ---
        let impassable = Set([GridPoint(x: 1, y: 3)])
        let regulation = GameMode.Regulation(
            boardSize: BoardGeometry.standardSize,
            handSize: 5,
            nextPreviewCount: 0,
            allowsStacking: true,
            deckPreset: .standardWithWarpCards,
            spawnRule: .fixed(spawnPoint),
            penalties: GameMode.PenaltySettings(
                deadlockPenaltyCost: 0,
                manualRedrawPenaltyCost: 0,
                manualDiscardPenaltyCost: 0,
                revisitPenaltyCost: 0
            ),
            impassableTilePoints: impassable
        )

        let mode = GameMode(
            identifier: .freeCustom,
            displayName: "固定ワープ自動生成テスト",
            regulation: regulation,
            leaderboardEligible: false
        )

        // --- デフォルト生成されたターゲットが障害物以外の全マスを網羅しているか検証 ---
        let fallbackTargets = try XCTUnwrap(mode.fixedWarpCardTargets[.fixedWarp], "固定ワープのフォールバックターゲットが生成されていません")
        let expectedTargets = BoardGeometry.allPoints(for: BoardGeometry.standardSize).filter { point in
            !impassable.contains(point)
        }
        XCTAssertEqual(fallbackTargets, expectedTargets, "自動生成された固定ワープ候補が期待と一致しません")

        // --- availableMoves() からも同じターゲットが候補として列挙されるか確認 ---
        let presetCards = Array(repeating: MoveCard.fixedWarp, count: 8)
        let deck = Deck.makeTestDeck(
            cards: presetCards,
            configuration: regulation.deckPreset.configuration,
            fixedWarpDestinations: fallbackTargets
        )
        let core = GameCore.makeTestInstance(
            deck: deck,
            current: spawnPoint,
            mode: mode,
            initialVisitedPoints: [spawnPoint]
        )

        let moves = core.availableMoves()
        let warpMoves = moves.filter { $0.card.move == .fixedWarp }
        let firstMove = try XCTUnwrap(warpMoves.first, "固定ワープ候補が得られません")
        XCTAssertTrue(fallbackTargets.contains(firstMove.destination), "availableMoves() から取得した目的地がフォールバック集合に含まれていません")

        // --- 最初のカードを使用し、次に配られるカードが順番に更新されるか確認 ---
        core.playCard(using: firstMove)
        if fallbackTargets.count >= 2 {
            let nextCard = try XCTUnwrap(core.handStacks.first?.topCard, "ワープカードの再補充に失敗しています")
            let nextDestination = try XCTUnwrap(nextCard.fixedWarpDestination, "補充後の固定ワープ目的地が設定されていません")
            XCTAssertTrue(fallbackTargets.contains(nextDestination), "補充後の目的地がフォールバック集合に含まれていません")
            XCTAssertNotEqual(nextDestination, firstMove.destination, "巡回中に同じ目的地が連続して割り当てられています")
        }
    }
}
