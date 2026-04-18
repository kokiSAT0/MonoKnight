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
            identifier: .freeCustom,
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

    func testModeForFallbackIdentifiersReturnsStandard() {
        let fallbackIdentifiers: [GameMode.Identifier] = [
            .dailyFixedChallenge,
            .dailyRandomChallenge,
            .freeCustom,
            .campaignStage,
            .dailyFixed,
            .dailyRandom
        ]

        for identifier in fallbackIdentifiers {
            XCTAssertEqual(GameMode.mode(for: identifier), .standard, "\(identifier) の fallback が standard ではありません")
        }
    }

    func testPresentationStringsRemainStableAfterExtraction() {
        XCTAssertEqual(GameMode.DifficultyRank.balanced.badgeLabel, "標準")
        XCTAssertEqual(GameMode.DifficultyRank.advanced.accessibilityDescription, "難易度は高難度です")
        XCTAssertEqual(GameMode.SpawnRule.fixed(GridPoint(x: 2, y: 2)).summaryText, "固定スポーン")
        XCTAssertEqual(GameMode.SpawnRule.chooseAnyAfterPreview.summaryText, "任意スポーン")
    }
}
