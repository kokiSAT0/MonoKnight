import XCTest
@testable import Game

/// GameCore.availableMoves() がレイ型カードの挙動を正しく解決するか検証するテスト
final class GameCoreAvailableMovesTests: XCTestCase {
    /// 盤端と障害物に応じてレイ型カードが停止することを確認する
    func testDirectionalRayStopsAtBoardEdgeAndObstacle() {
        // --- 盤端まで進むケースを検証 ---
        let edgeRegulation = GameMode.Regulation(
            boardSize: BoardGeometry.standardSize,
            handSize: 1,
            nextPreviewCount: 0,
            allowsStacking: true,
            deckPreset: .directionalRayFocus,
            spawnRule: .fixed(GridPoint(x: 2, y: 2)),
            penalties: GameMode.PenaltySettings(
                deadlockPenaltyCost: 0,
                manualRedrawPenaltyCost: 0,
                manualDiscardPenaltyCost: 0,
                revisitPenaltyCost: 0
            )
        )
        let edgeMode = GameMode(
            identifier: .freeCustom,
            displayName: "レイ端テスト",
            regulation: edgeRegulation,
            leaderboardEligible: false
        )
        let edgeDeck = Deck.makeTestDeck(cards: [.rayUp], configuration: edgeRegulation.deckPreset.configuration)
        let edgeCore = GameCore.makeTestInstance(deck: edgeDeck, current: GridPoint(x: 2, y: 2), mode: edgeMode)
        let rayStack = HandStack(cards: [DealtCard(move: .rayUp)])
        let edgeMoves = edgeCore.availableMoves(handStacks: [rayStack], current: GridPoint(x: 2, y: 2))
        XCTAssertEqual(edgeMoves.count, 1, "盤端テストで候補数が 1 件になっていません")
        if let move = edgeMoves.first {
            XCTAssertEqual(move.destination, GridPoint(x: 2, y: 4), "盤端到達先が期待値と異なります")
            XCTAssertEqual(move.path, [GridPoint(x: 2, y: 3), GridPoint(x: 2, y: 4)], "通過マスの記録が不足しています")
        }

        // --- 障害物で停止するケースを検証 ---
        let obstaclePoint = GridPoint(x: 2, y: 4)
        let obstacleRegulation = GameMode.Regulation(
            boardSize: BoardGeometry.standardSize,
            handSize: 1,
            nextPreviewCount: 0,
            allowsStacking: true,
            deckPreset: .directionalRayFocus,
            spawnRule: .fixed(GridPoint(x: 2, y: 2)),
            penalties: GameMode.PenaltySettings(
                deadlockPenaltyCost: 0,
                manualRedrawPenaltyCost: 0,
                manualDiscardPenaltyCost: 0,
                revisitPenaltyCost: 0
            ),
            impassableTilePoints: [obstaclePoint]
        )
        let obstacleMode = GameMode(
            identifier: .freeCustom,
            displayName: "レイ障害物テスト",
            regulation: obstacleRegulation,
            leaderboardEligible: false
        )
        let obstacleDeck = Deck.makeTestDeck(cards: [.rayUp], configuration: obstacleRegulation.deckPreset.configuration)
        let obstacleCore = GameCore.makeTestInstance(deck: obstacleDeck, current: GridPoint(x: 2, y: 2), mode: obstacleMode)
        let obstacleMoves = obstacleCore.availableMoves(handStacks: [rayStack], current: GridPoint(x: 2, y: 2))
        XCTAssertEqual(obstacleMoves.count, 1, "障害物テストで候補数が 1 件になっていません")
        if let move = obstacleMoves.first {
            XCTAssertEqual(move.destination, GridPoint(x: 2, y: 3), "障害物直前で停止していません")
            XCTAssertEqual(move.path, [GridPoint(x: 2, y: 3)], "障害物直前までの経路記録が想定と異なります")
        }
    }

    /// レイ型カードの通過マスがすべて踏破扱いになるように記録されているか検証する
    func testDirectionalRayTraversedPointsIncludeEntireRoute() {
        let regulation = GameMode.Regulation(
            boardSize: BoardGeometry.standardSize,
            handSize: 1,
            nextPreviewCount: 0,
            allowsStacking: true,
            deckPreset: .directionalRayFocus,
            spawnRule: .fixed(GridPoint(x: 0, y: 0)),
            penalties: GameMode.PenaltySettings(
                deadlockPenaltyCost: 0,
                manualRedrawPenaltyCost: 0,
                manualDiscardPenaltyCost: 0,
                revisitPenaltyCost: 0
            )
        )
        let mode = GameMode(
            identifier: .freeCustom,
            displayName: "レイ踏破テスト",
            regulation: regulation,
            leaderboardEligible: false
        )
        let deck = Deck.makeTestDeck(cards: [.rayUpRight], configuration: regulation.deckPreset.configuration)
        let core = GameCore.makeTestInstance(deck: deck, current: GridPoint(x: 0, y: 0), mode: mode)
        let stack = HandStack(cards: [DealtCard(move: .rayUpRight)])
        let moves = core.availableMoves(handStacks: [stack], current: GridPoint(x: 0, y: 0))
        XCTAssertEqual(moves.count, 1, "踏破テストで候補数が 1 件ではありません")
        if let move = moves.first {
            let expectedPath = [
                GridPoint(x: 1, y: 1),
                GridPoint(x: 2, y: 2),
                GridPoint(x: 3, y: 3),
                GridPoint(x: 4, y: 4)
            ]
            XCTAssertEqual(move.path, expectedPath, "通過マスが全経路を表していません")
        }
    }

    /// UI 側へ渡す候補数が 1 件に固定され、選択式扱いにならないことを確認する
    func testDirectionalRayProvidesSingleCandidate() {
        let regulation = GameMode.Regulation(
            boardSize: BoardGeometry.standardSize,
            handSize: 1,
            nextPreviewCount: 0,
            allowsStacking: true,
            deckPreset: .directionalRayFocus,
            spawnRule: .fixed(GridPoint(x: 2, y: 2)),
            penalties: GameMode.PenaltySettings(
                deadlockPenaltyCost: 0,
                manualRedrawPenaltyCost: 0,
                manualDiscardPenaltyCost: 0,
                revisitPenaltyCost: 0
            )
        )
        let mode = GameMode(
            identifier: .freeCustom,
            displayName: "レイ候補数テスト",
            regulation: regulation,
            leaderboardEligible: false
        )
        let deck = Deck.makeTestDeck(cards: [.rayRight], configuration: regulation.deckPreset.configuration)
        let core = GameCore.makeTestInstance(deck: deck, current: GridPoint(x: 2, y: 2), mode: mode)
        let stack = HandStack(cards: [DealtCard(move: .rayRight)])
        let moves = core.availableMoves(handStacks: [stack], current: GridPoint(x: 2, y: 2))
        XCTAssertEqual(moves.count, 1, "レイ型カードが複数候補を返しています")
    }

    /// 全域ワープカードが障害物や既踏マスを候補から除外し、盤面タップ選択でも安全に扱えることを検証する
    func testSuperWarpExcludesVisitedAndImpassableTiles() {
        // --- 盤面条件を定義（障害物と既踏マスを意図的に配置） ---
        let boardSize = BoardGeometry.standardSize
        let origin = GridPoint(x: 2, y: 2)
        let visitedPoint = GridPoint(x: 4, y: 4)
        let impassablePoint = GridPoint(x: 1, y: 3)

        let regulation = GameMode.Regulation(
            boardSize: boardSize,
            handSize: 1,
            nextPreviewCount: 0,
            allowsStacking: true,
            deckPreset: .standardWithAllChoices,
            spawnRule: .fixed(origin),
            penalties: GameMode.PenaltySettings(
                deadlockPenaltyCost: 0,
                manualRedrawPenaltyCost: 0,
                manualDiscardPenaltyCost: 0,
                revisitPenaltyCost: 0
            ),
            impassableTilePoints: [impassablePoint]
        )

        let mode = GameMode(
            identifier: .freeCustom,
            displayName: "全域ワープ候補テスト",
            regulation: regulation,
            leaderboardEligible: false
        )

        let deck = Deck.makeTestDeck(cards: [.superWarp], configuration: .standardWithAllChoices)
        let visitedPoints = [origin, visitedPoint]
        let core = GameCore.makeTestInstance(
            deck: deck,
            current: origin,
            mode: mode,
            initialVisitedPoints: visitedPoints
        )

        // --- 手札スタックを手動構築し、availableMoves の結果を取得 ---
        let stack = HandStack(cards: [DealtCard(move: .superWarp)])
        let moves = core.availableMoves(handStacks: [stack], current: origin)

        // --- 盤面全域から障害物・既踏マスが除外されていることを検証 ---
        let destinations = Set(moves.map { $0.destination })
        XCTAssertFalse(destinations.contains(visitedPoint), "既踏マスが候補に残ってしまっています")
        XCTAssertFalse(destinations.contains(impassablePoint), "障害物マスが候補に含まれています")

        let expectedDestinations = Set(
            BoardGeometry.allPoints(for: boardSize).filter { point in
                point != origin && point != visitedPoint && point != impassablePoint
            }
        )
        XCTAssertEqual(destinations, expectedDestinations, "全域ワープの到達候補集合が仕様と一致しません")

        // --- 候補数も計算上の期待値と一致することを確認 ---
        let blockedPoints = Set([origin, visitedPoint, impassablePoint])
        let expectedCount = boardSize * boardSize - blockedPoints.count
        XCTAssertEqual(moves.count, expectedCount, "全域ワープの候補数が期待値と異なります")

        // --- 盤面タップ選択が有効マスに対して成功し、無効マスでは nil を返すことを検証 ---
        if let tapMove = core.resolvedMoveForBoardTap(at: GridPoint(x: 0, y: 0)) {
            XCTAssertEqual(tapMove.destination, GridPoint(x: 0, y: 0), "盤面タップで解決した目的地が想定と異なります")
            XCTAssertEqual(tapMove.card.move, .superWarp, "盤面タップで解決したカード種別が全域ワープではありません")
        } else {
            XCTFail("有効マスをタップした際に候補が返されませんでした")
        }
        XCTAssertNil(core.resolvedMoveForBoardTap(at: visitedPoint), "既踏マスをタップした際は候補が存在しない想定です")
        XCTAssertNil(core.resolvedMoveForBoardTap(at: impassablePoint), "障害物タップ時は候補が存在しない想定です")
    }
}
