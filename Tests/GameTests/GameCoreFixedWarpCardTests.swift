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
    private func makeDeck(for regulation: GameMode.Regulation) -> Deck {
        let configuration = regulation.deckPreset.configurationIncludingFixedWarpCard()
        let preloadCards: [MoveCard] = [
            .fixedWarp,
            .kingUp,
            .kingRight,
            .kingDown,
            .kingLeft
        ]
        return Deck.makeTestDeck(cards: preloadCards, configuration: configuration)
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
        let deck = makeDeck(for: regulation)
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
        XCTAssertEqual(warpCandidates.count, 1, "既踏マス除外後は 1 件のみ残る想定です")

        let candidate = try XCTUnwrap(warpCandidates.first)
        XCTAssertEqual(candidate.destination, validTargetA, "到達先がバリデーション結果と一致していません")
        XCTAssertEqual(candidate.path, [validTargetA], "通過マスが固定ワープ仕様と異なります")
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
        let deck = makeDeck(for: regulation)
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
        let deck = makeDeck(for: regulation)
        let core = GameCore.makeTestInstance(
            deck: deck,
            current: spawnPoint,
            mode: mode,
            initialVisitedPoints: [spawnPoint]
        )

        let moves = core.availableMoves()
        let warpCandidates = moves.filter { $0.card.move == .fixedWarp }
        XCTAssertEqual(warpCandidates.count, 2, "未踏状態では 2 件の固定ワープ候補が得られる想定です")

        // --- 左下ターゲットを選択して実際にカードをプレイ ---
        let targetMove = try XCTUnwrap(warpCandidates.first { $0.destination == validTargetA })
        core.playCard(using: targetMove)

        // --- 最終位置や踏破状態が更新されていることを確認 ---
        XCTAssertEqual(core.current, validTargetA, "固定ワープ後の現在地が期待値と異なります")
        XCTAssertTrue(core.board.isVisited(validTargetA), "ワープ先が踏破扱いになっていません")
        XCTAssertEqual(core.moveCount, 1, "固定ワープの使用で手数が加算されていません")
        XCTAssertFalse(core.hasRevisitedTile, "固定ワープ初回使用で再訪扱いになるのは想定外です")
    }
}
