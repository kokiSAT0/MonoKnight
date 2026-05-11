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
                deckPreset: .standardLight,
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
        XCTAssertEqual(mode.tileEffects[warpPointB], TileEffect.warp(pairID: "pair", destination: warpPointA))
    }

    func testTileEffectsRoundTripThroughRegulationCoding() throws {
        let blastPoint = GridPoint(x: 2, y: 1)
        let slowPoint = GridPoint(x: 2, y: 3)
        let shacklePoint = GridPoint(x: 4, y: 0)
        let swampPoint = GridPoint(x: 1, y: 3)
        let preserveCardPoint = GridPoint(x: 1, y: 1)
        let discardRandomPoint = GridPoint(x: 3, y: 1)
        let discardMovePoint = GridPoint(x: 0, y: 3)
        let discardSupportPoint = GridPoint(x: 4, y: 1)
        let discardAllPoint = GridPoint(x: 3, y: 3)
        let poisonPoint = GridPoint(x: 4, y: 3)
        let illusionPoint = GridPoint(x: 0, y: 1)
        let returnWarpPoint = GridPoint(x: 0, y: 4)
        let returnWarpDestination = GridPoint(x: 2, y: 4)
        let regulation = GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standardLight,
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
                shacklePoint: .shackleTrap,
                swampPoint: .swamp,
                preserveCardPoint: .preserveCard,
                discardRandomPoint: .discardRandomHand,
                discardMovePoint: .discardAllMoveCards,
                discardSupportPoint: .discardAllSupportCards,
                discardAllPoint: .discardAllHands,
                poisonPoint: .poisonTrap,
                illusionPoint: .illusionTrap,
                returnWarpPoint: .returnWarp(destination: returnWarpDestination),
            ],
            completionRule: .dungeonExit(exitPoint: GridPoint(x: 4, y: 4))
        )

        let data = try JSONEncoder().encode(regulation)
        let decoded = try JSONDecoder().decode(GameMode.Regulation.self, from: data)

        XCTAssertEqual(decoded.tileEffectOverrides[blastPoint], TileEffect.blast(direction: MoveVector(dx: 0, dy: -1)))
        XCTAssertEqual(decoded.resolvedTileEffects[blastPoint], TileEffect.blast(direction: MoveVector(dx: 0, dy: -1)))
        XCTAssertEqual(decoded.tileEffectOverrides[slowPoint], TileEffect.slow)
        XCTAssertEqual(decoded.resolvedTileEffects[slowPoint], TileEffect.slow)
        XCTAssertEqual(decoded.tileEffectOverrides[shacklePoint], TileEffect.shackleTrap)
        XCTAssertEqual(decoded.resolvedTileEffects[shacklePoint], TileEffect.shackleTrap)
        XCTAssertEqual(decoded.tileEffectOverrides[swampPoint], TileEffect.swamp)
        XCTAssertEqual(decoded.resolvedTileEffects[swampPoint], TileEffect.swamp)
        XCTAssertEqual(decoded.tileEffectOverrides[preserveCardPoint], TileEffect.preserveCard)
        XCTAssertEqual(decoded.resolvedTileEffects[preserveCardPoint], TileEffect.preserveCard)
        XCTAssertEqual(decoded.tileEffectOverrides[discardRandomPoint], TileEffect.discardRandomHand)
        XCTAssertEqual(decoded.resolvedTileEffects[discardRandomPoint], TileEffect.discardRandomHand)
        XCTAssertEqual(decoded.tileEffectOverrides[discardMovePoint], TileEffect.discardAllMoveCards)
        XCTAssertEqual(decoded.resolvedTileEffects[discardMovePoint], TileEffect.discardAllMoveCards)
        XCTAssertEqual(decoded.tileEffectOverrides[discardSupportPoint], TileEffect.discardAllSupportCards)
        XCTAssertEqual(decoded.resolvedTileEffects[discardSupportPoint], TileEffect.discardAllSupportCards)
        XCTAssertEqual(decoded.tileEffectOverrides[discardAllPoint], TileEffect.discardAllHands)
        XCTAssertEqual(decoded.resolvedTileEffects[discardAllPoint], TileEffect.discardAllHands)
        XCTAssertEqual(decoded.tileEffectOverrides[poisonPoint], TileEffect.poisonTrap)
        XCTAssertEqual(decoded.resolvedTileEffects[poisonPoint], TileEffect.poisonTrap)
        XCTAssertEqual(decoded.tileEffectOverrides[illusionPoint], TileEffect.illusionTrap)
        XCTAssertEqual(decoded.resolvedTileEffects[illusionPoint], TileEffect.illusionTrap)
        XCTAssertEqual(decoded.tileEffectOverrides[returnWarpPoint], TileEffect.returnWarp(destination: returnWarpDestination))
        XCTAssertEqual(decoded.resolvedTileEffects[returnWarpPoint], TileEffect.returnWarp(destination: returnWarpDestination))
    }

    func testPresentationStringsRemainStableAfterExtraction() {
        XCTAssertEqual(GameMode.DifficultyRank.balanced.badgeLabel, "標準")
        XCTAssertEqual(GameMode.DifficultyRank.advanced.accessibilityDescription, "難易度は高難度です")
        XCTAssertEqual(GameMode.SpawnRule.fixed(GridPoint(x: 2, y: 2)).summaryText, "固定スポーン")
        XCTAssertEqual(GameMode.SpawnRule.chooseAnyAfterPreview.summaryText, "任意スポーン")
    }
}
