import Foundation

public extension GameMode {
    /// 盤面へ適用するタイル効果を合成して返す
    /// - Important: ワープ定義は自動的に `TileEffect.warp` へ展開し、個別指定された効果より優先度は低い（手動指定があればそちらを採用）
    var tileEffects: [GridPoint: TileEffect] {
        regulationSnapshot.resolvedTileEffects
    }
}

extension GameMode.Regulation {
    /// 盤面へ適用するタイル効果を合成して返す
    /// - Important: warp pair は自動的に循環ワープへ展開し、個別 override がある座標は上書きしない
    var resolvedTileEffects: [GridPoint: TileEffect] {
        var effects = tileEffectOverrides
        for (pairID, points) in warpTilePairs {
            guard points.count >= 2 else { continue }

            var uniquePoints: [GridPoint] = []
            var seen: Set<GridPoint> = []
            for point in points where seen.insert(point).inserted {
                uniquePoints.append(point)
            }
            guard uniquePoints.count >= 2 else { continue }

            for (index, point) in uniquePoints.enumerated() {
                guard effects[point] == nil else { continue }
                let destination = uniquePoints[(index + 1) % uniquePoints.count]
                effects[point] = .warp(pairID: pairID, destination: destination)
            }
        }
        return effects
    }

    /// デコード処理
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let decodedBoardSize = try container.decode(Int.self, forKey: .boardSize)
        let decodedHandSize = try container.decode(Int.self, forKey: .handSize)
        let decodedNextPreview = try container.decode(Int.self, forKey: .nextPreviewCount)
        let decodedAllowsStacking = try container.decode(Bool.self, forKey: .allowsStacking)
        let decodedDeckPreset = try container.decode(GameDeckPreset.self, forKey: .deckPreset)
        let decodedBonusMoveCards = try container.decodeIfPresent([MoveCard].self, forKey: .bonusMoveCards) ?? []
        let decodedSpawnRule = try container.decode(GameMode.SpawnRule.self, forKey: .spawnRule)
        let decodedPenalties = try container.decode(GameMode.PenaltySettings.self, forKey: .penalties)
        let decodedImpassable = try container.decodeIfPresent(Set<GridPoint>.self, forKey: .impassableTilePoints) ?? []
        let decodedEffects = try container.decodeIfPresent([GridPoint: TileEffect].self, forKey: .tileEffectOverrides) ?? [:]
        let decodedWarpPairs = try container.decodeIfPresent([String: [GridPoint]].self, forKey: .warpTilePairs) ?? [:]
        let decodedCompletionRule = try container.decodeIfPresent(GameMode.CompletionRule.self, forKey: .completionRule)
            ?? .dungeonExit(exitPoint: BoardGeometry.defaultSpawnPoint(for: decodedBoardSize))
        let decodedDungeonRules = try container.decodeIfPresent(DungeonRules.self, forKey: .dungeonRules)

        boardSize = decodedBoardSize
        handSize = decodedHandSize
        nextPreviewCount = decodedNextPreview
        allowsStacking = decodedAllowsStacking
        deckPreset = decodedDeckPreset
        bonusMoveCards = decodedBonusMoveCards.isEmpty ? nil : decodedBonusMoveCards
        spawnRule = decodedSpawnRule
        penalties = decodedPenalties
        impassableTilePoints = decodedImpassable
        tileEffectOverrides = decodedEffects
        warpTilePairs = decodedWarpPairs
        completionRule = decodedCompletionRule
        dungeonRules = decodedDungeonRules
    }

    /// エンコード処理
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(boardSize, forKey: .boardSize)
        try container.encode(handSize, forKey: .handSize)
        try container.encode(nextPreviewCount, forKey: .nextPreviewCount)
        try container.encode(allowsStacking, forKey: .allowsStacking)
        try container.encode(deckPreset, forKey: .deckPreset)
        if let bonusMoveCards, !bonusMoveCards.isEmpty {
            try container.encode(bonusMoveCards, forKey: .bonusMoveCards)
        }
        try container.encode(spawnRule, forKey: .spawnRule)
        try container.encode(penalties, forKey: .penalties)
        if !impassableTilePoints.isEmpty {
            try container.encode(impassableTilePoints, forKey: .impassableTilePoints)
        }
        if !tileEffectOverrides.isEmpty {
            try container.encode(tileEffectOverrides, forKey: .tileEffectOverrides)
        }
        if !warpTilePairs.isEmpty {
            try container.encode(warpTilePairs, forKey: .warpTilePairs)
        }
        try container.encode(completionRule, forKey: .completionRule)
        if let dungeonRules {
            try container.encode(dungeonRules, forKey: .dungeonRules)
        }
    }

}
