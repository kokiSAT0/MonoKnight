import XCTest
@testable import Game

final class GameModeRegulationTests: XCTestCase {
    func testTileEffectsPreferOverridesOverWarpPairs() {
        let warpPointA = GridPoint(x: 0, y: 0)
        let warpPointB = GridPoint(x: 4, y: 4)
        let overriddenEffect: TileEffect = .shuffleHand
        let mode = GameMode(
            identifier: .dungeonFloor,
            displayName: "tile effect test",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standard,
                spawnRule: .fixed(GridPoint(x: 2, y: 2)),
                penalties: GameMode.PenaltySettings(
                    deadlockPenaltyCost: 3,
                    manualRedrawPenaltyCost: 2,
                    manualDiscardPenaltyCost: 1,
                    revisitPenaltyCost: 0
                ),
                tileEffectOverrides: [warpPointA: overriddenEffect],
                warpTilePairs: ["pair": [warpPointA, warpPointB]]
            )
        )

        XCTAssertEqual(mode.tileEffects[warpPointA], overriddenEffect)
        XCTAssertEqual(mode.tileEffects[warpPointB], .warp(pairID: "pair", destination: warpPointA))
    }

    func testTileEffectsRoundTripThroughRegulationCoding() throws {
        let blastPoint = GridPoint(x: 2, y: 1)
        let slowPoint = GridPoint(x: 2, y: 3)
        let preserveCardPoint = GridPoint(x: 1, y: 1)
        let regulation = GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standard,
            spawnRule: .fixed(GridPoint(x: 2, y: 2)),
            penalties: GameMode.PenaltySettings(
                deadlockPenaltyCost: 0,
                manualRedrawPenaltyCost: 0,
                manualDiscardPenaltyCost: 1,
                revisitPenaltyCost: 0
            ),
            tileEffectOverrides: [
                blastPoint: .blast(direction: MoveVector(dx: 0, dy: -1)),
                slowPoint: .slow,
                preserveCardPoint: .preserveCard,
            ],
            completionRule: .targetCollection(goalCount: 12)
        )

        let data = try JSONEncoder().encode(regulation)
        let decoded = try JSONDecoder().decode(GameMode.Regulation.self, from: data)

        XCTAssertEqual(decoded.tileEffectOverrides[blastPoint], .blast(direction: MoveVector(dx: 0, dy: -1)))
        XCTAssertEqual(decoded.resolvedTileEffects[blastPoint], .blast(direction: MoveVector(dx: 0, dy: -1)))
        XCTAssertEqual(decoded.tileEffectOverrides[slowPoint], .slow)
        XCTAssertEqual(decoded.resolvedTileEffects[slowPoint], .slow)
        XCTAssertEqual(decoded.tileEffectOverrides[preserveCardPoint], .preserveCard)
        XCTAssertEqual(decoded.resolvedTileEffects[preserveCardPoint], .preserveCard)
    }

    func testPresentationStringsRemainStableAfterExtraction() {
        XCTAssertEqual(GameMode.DifficultyRank.balanced.badgeLabel, "標準")
        XCTAssertEqual(GameMode.DifficultyRank.advanced.accessibilityDescription, "難易度は高難度です")
        XCTAssertEqual(GameMode.SpawnRule.fixed(GridPoint(x: 2, y: 2)).summaryText, "固定スポーン")
        XCTAssertEqual(GameMode.SpawnRule.chooseAnyAfterPreview.summaryText, "任意スポーン")
    }
}
