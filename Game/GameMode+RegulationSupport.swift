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

    /// 固定ワープカードの目的地を検証してから登録するヘルパー
    /// - Parameters:
    ///   - rawTargets: モード設定で宣言された元の座標集合
    ///   - boardSize: 対象盤面サイズ
    ///   - impassableTilePoints: 障害物として扱うマス集合
    /// - Returns: 盤外・障害物・重複を除去した安全な辞書
    static func sanitizeFixedWarpTargets(
        _ rawTargets: [MoveCard: [GridPoint]],
        boardSize: Int,
        impassableTilePoints: Set<GridPoint>
    ) -> [MoveCard: [GridPoint]] {
        guard boardSize > 0, !rawTargets.isEmpty else { return [:] }

        let validRange = 0..<boardSize
        let isInsideBoard: (GridPoint) -> Bool = { point in
            validRange.contains(point.x) && validRange.contains(point.y)
        }

        var sanitized: [MoveCard: [GridPoint]] = [:]

        for (card, points) in rawTargets {
            guard !points.isEmpty else { continue }

            var filtered: [GridPoint] = []
            filtered.reserveCapacity(points.count)
            var seen: Set<GridPoint> = []

            for point in points {
                guard isInsideBoard(point), !impassableTilePoints.contains(point) else { continue }
                guard seen.insert(point).inserted else { continue }
                filtered.append(point)
            }

            guard !filtered.isEmpty else { continue }
            sanitized[card] = filtered
        }

        return sanitized
    }

    /// 固定ワープカードの最終的な目的地リストを決定する
    static func finalizeFixedWarpTargets(
        rawTargets: [MoveCard: [GridPoint]],
        boardSize: Int,
        impassableTilePoints: Set<GridPoint>,
        deckPreset: GameDeckPreset
    ) -> [MoveCard: [GridPoint]] {
        let sanitized = sanitizeFixedWarpTargets(
            rawTargets,
            boardSize: boardSize,
            impassableTilePoints: impassableTilePoints
        )
        if !sanitized.isEmpty {
            return sanitized
        }

        let allowedMoves = deckPreset.configuration.allowedMoves
        guard allowedMoves.contains(.fixedWarp) else { return [:] }
        return defaultFixedWarpTargets(
            boardSize: boardSize,
            impassableTilePoints: impassableTilePoints
        )
    }

    /// 盤面全域から固定ワープカード用の目的地候補を生成する
    static func defaultFixedWarpTargets(
        boardSize: Int,
        impassableTilePoints: Set<GridPoint>
    ) -> [MoveCard: [GridPoint]] {
        guard boardSize > 0 else { return [:] }

        let allPoints = BoardGeometry.allPoints(for: boardSize)
        let traversablePoints = allPoints.filter { point in
            !impassableTilePoints.contains(point)
        }
        guard !traversablePoints.isEmpty else { return [:] }
        return [.fixedWarp: traversablePoints]
    }

    /// デコード処理（固定ワープ定義は一旦文字列キーとして受け取り、MoveCard へ変換する）
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let decodedBoardSize = try container.decode(Int.self, forKey: .boardSize)
        let decodedHandSize = try container.decode(Int.self, forKey: .handSize)
        let decodedNextPreview = try container.decode(Int.self, forKey: .nextPreviewCount)
        let decodedAllowsStacking = try container.decode(Bool.self, forKey: .allowsStacking)
        let decodedDeckPreset = try container.decode(GameDeckPreset.self, forKey: .deckPreset)
        let decodedSpawnRule = try container.decode(GameMode.SpawnRule.self, forKey: .spawnRule)
        let decodedPenalties = try container.decode(GameMode.PenaltySettings.self, forKey: .penalties)
        let decodedAdditional = try container.decodeIfPresent([GridPoint: Int].self, forKey: .additionalVisitRequirements) ?? [:]
        let decodedToggle = try container.decodeIfPresent(Set<GridPoint>.self, forKey: .toggleTilePoints) ?? []
        let decodedImpassable = try container.decodeIfPresent(Set<GridPoint>.self, forKey: .impassableTilePoints) ?? []
        let decodedEffects = try container.decodeIfPresent([GridPoint: TileEffect].self, forKey: .tileEffectOverrides) ?? [:]
        let decodedWarpPairs = try container.decodeIfPresent([String: [GridPoint]].self, forKey: .warpTilePairs) ?? [:]
        let rawFixedWarpTargets = try container.decodeIfPresent([String: [GridPoint]].self, forKey: .fixedWarpCardTargets) ?? [:]
        let decodedCompletionRule = try container.decodeIfPresent(GameMode.CompletionRule.self, forKey: .completionRule) ?? .boardClear

        let decodedTargets = Self.decodeFixedWarpTargets(from: rawFixedWarpTargets)
        let sanitizedTargets = Self.finalizeFixedWarpTargets(
            rawTargets: decodedTargets,
            boardSize: decodedBoardSize,
            impassableTilePoints: decodedImpassable,
            deckPreset: decodedDeckPreset
        )

        boardSize = decodedBoardSize
        handSize = decodedHandSize
        nextPreviewCount = decodedNextPreview
        allowsStacking = decodedAllowsStacking
        deckPreset = decodedDeckPreset
        spawnRule = decodedSpawnRule
        penalties = decodedPenalties
        additionalVisitRequirements = decodedAdditional
        toggleTilePoints = decodedToggle
        impassableTilePoints = decodedImpassable
        tileEffectOverrides = decodedEffects
        warpTilePairs = decodedWarpPairs
        fixedWarpCardTargets = sanitizedTargets
        completionRule = decodedCompletionRule
    }

    /// エンコード処理（固定ワープ定義は MoveCard のインデックスをキーに変換する）
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(boardSize, forKey: .boardSize)
        try container.encode(handSize, forKey: .handSize)
        try container.encode(nextPreviewCount, forKey: .nextPreviewCount)
        try container.encode(allowsStacking, forKey: .allowsStacking)
        try container.encode(deckPreset, forKey: .deckPreset)
        try container.encode(spawnRule, forKey: .spawnRule)
        try container.encode(penalties, forKey: .penalties)
        if !additionalVisitRequirements.isEmpty {
            try container.encode(additionalVisitRequirements, forKey: .additionalVisitRequirements)
        }
        if !toggleTilePoints.isEmpty {
            try container.encode(toggleTilePoints, forKey: .toggleTilePoints)
        }
        if !impassableTilePoints.isEmpty {
            try container.encode(impassableTilePoints, forKey: .impassableTilePoints)
        }
        if !tileEffectOverrides.isEmpty {
            try container.encode(tileEffectOverrides, forKey: .tileEffectOverrides)
        }
        if !warpTilePairs.isEmpty {
            try container.encode(warpTilePairs, forKey: .warpTilePairs)
        }
        let encodedTargets = Self.encodeFixedWarpTargets(fixedWarpCardTargets)
        if !encodedTargets.isEmpty {
            try container.encode(encodedTargets, forKey: .fixedWarpCardTargets)
        }
        try container.encode(completionRule, forKey: .completionRule)
    }

    /// エンコード用に MoveCard を安定キーへ変換する
    static func encodeFixedWarpTargets(_ targets: [MoveCard: [GridPoint]]) -> [String: [GridPoint]] {
        guard !targets.isEmpty else { return [:] }
        var encoded: [String: [GridPoint]] = [:]
        for (card, points) in targets {
            guard let index = MoveCard.allCases.firstIndex(of: card) else { continue }
            encoded[String(index)] = points
        }
        return encoded
    }

    /// デコード時に MoveCard のインデックスへ戻す
    static func decodeFixedWarpTargets(from raw: [String: [GridPoint]]) -> [MoveCard: [GridPoint]] {
        guard !raw.isEmpty else { return [:] }
        var decoded: [MoveCard: [GridPoint]] = [:]
        for (key, points) in raw {
            guard let index = Int(key), MoveCard.allCases.indices.contains(index) else { continue }
            let card = MoveCard.allCases[index]
            decoded[card] = points
        }
        return decoded
    }
}
