import XCTest
@testable import Game

final class GameModeRegulationTests: XCTestCase {
    func testRegulationDecodeSanitizesFixedWarpTargets() throws {
        let fixedWarpIndex = try XCTUnwrap(MoveCard.allCases.firstIndex(of: .fixedWarp))
        let payload: [String: Any] = [
            "boardSize": 5,
            "handSize": 5,
            "nextPreviewCount": 3,
            "allowsStacking": true,
            "deckPreset": "standardWithWarpCards",
            "spawnRule": [
                "type": "fixed",
                "point": ["x": 2, "y": 2]
            ],
            "penalties": [
                "deadlockPenaltyCost": 3,
                "manualRedrawPenaltyCost": 2,
                "manualDiscardPenaltyCost": 1,
                "revisitPenaltyCost": 0
            ],
            "impassableTilePoints": [
                ["x": 1, "y": 1]
            ],
            "fixedWarpCardTargets": [
                "999": [
                    ["x": 0, "y": 0]
                ],
                String(fixedWarpIndex): [
                    ["x": 0, "y": 0],
                    ["x": 1, "y": 1],
                    ["x": 0, "y": 0],
                    ["x": 4, "y": 4],
                    ["x": 5, "y": 5]
                ]
            ]
        ]

        let decoder = JSONDecoder()
        let data = try JSONSerialization.data(withJSONObject: payload)
        let regulation = try decoder.decode(GameMode.Regulation.self, from: data)

        XCTAssertEqual(
            regulation.fixedWarpCardTargets[.fixedWarp],
            [GridPoint(x: 0, y: 0), GridPoint(x: 4, y: 4)]
        )
    }

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

    func testBoostTileEffectRoundTripsThroughRegulationCoding() throws {
        let boostPoint = GridPoint(x: 2, y: 1)
        let slowPoint = GridPoint(x: 2, y: 3)
        let nextRefreshPoint = GridPoint(x: 0, y: 4)
        let freeFocusPoint = GridPoint(x: 4, y: 0)
        let preserveCardPoint = GridPoint(x: 1, y: 1)
        let draftPoint = GridPoint(x: 3, y: 3)
        let overloadPoint = GridPoint(x: 1, y: 3)
        let targetSwapPoint = GridPoint(x: 3, y: 1)
        let openGatePoint = GridPoint(x: 0, y: 2)
        let openGateTarget = GridPoint(x: 4, y: 2)
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
                boostPoint: .boost,
                slowPoint: .slow,
                nextRefreshPoint: .nextRefresh,
                freeFocusPoint: .freeFocus,
                preserveCardPoint: .preserveCard,
                draftPoint: .draft,
                overloadPoint: .overload,
                targetSwapPoint: .targetSwap,
                openGatePoint: .openGate(target: openGateTarget),
            ],
            completionRule: .targetCollection(goalCount: 12)
        )

        let data = try JSONEncoder().encode(regulation)
        let decoded = try JSONDecoder().decode(GameMode.Regulation.self, from: data)

        XCTAssertEqual(decoded.tileEffectOverrides[boostPoint], .boost)
        XCTAssertEqual(decoded.resolvedTileEffects[boostPoint], .boost)
        XCTAssertEqual(decoded.tileEffectOverrides[slowPoint], .slow)
        XCTAssertEqual(decoded.resolvedTileEffects[slowPoint], .slow)
        XCTAssertEqual(decoded.tileEffectOverrides[nextRefreshPoint], .nextRefresh)
        XCTAssertEqual(decoded.resolvedTileEffects[nextRefreshPoint], .nextRefresh)
        XCTAssertEqual(decoded.tileEffectOverrides[freeFocusPoint], .freeFocus)
        XCTAssertEqual(decoded.resolvedTileEffects[freeFocusPoint], .freeFocus)
        XCTAssertEqual(decoded.tileEffectOverrides[preserveCardPoint], .preserveCard)
        XCTAssertEqual(decoded.resolvedTileEffects[preserveCardPoint], .preserveCard)
        XCTAssertEqual(decoded.tileEffectOverrides[draftPoint], .draft)
        XCTAssertEqual(decoded.resolvedTileEffects[draftPoint], .draft)
        XCTAssertEqual(decoded.tileEffectOverrides[overloadPoint], .overload)
        XCTAssertEqual(decoded.resolvedTileEffects[overloadPoint], .overload)
        XCTAssertEqual(decoded.tileEffectOverrides[targetSwapPoint], .targetSwap)
        XCTAssertEqual(decoded.resolvedTileEffects[targetSwapPoint], .targetSwap)
        XCTAssertEqual(decoded.tileEffectOverrides[openGatePoint], .openGate(target: openGateTarget))
        XCTAssertEqual(decoded.resolvedTileEffects[openGatePoint], .openGate(target: openGateTarget))
    }

    func testPresentationStringsRemainStableAfterExtraction() {
        XCTAssertEqual(GameMode.DifficultyRank.balanced.badgeLabel, "標準")
        XCTAssertEqual(GameMode.DifficultyRank.advanced.accessibilityDescription, "難易度は高難度です")
        XCTAssertEqual(GameMode.SpawnRule.fixed(GridPoint(x: 2, y: 2)).summaryText, "固定スポーン")
        XCTAssertEqual(GameMode.SpawnRule.chooseAnyAfterPreview.summaryText, "任意スポーン")
    }
}
