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
}
