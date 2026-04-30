import Foundation

public enum TargetLabCardGroup: String, CaseIterable, Codable, Hashable {
    case standard
    case choice
    case ray
    case warp

    public var displayName: String {
        switch self {
        case .standard: return "標準"
        case .choice: return "選択"
        case .ray: return "レイ"
        case .warp: return "ワープ"
        }
    }

    var cards: [MoveCard] {
        switch self {
        case .standard:
            return MoveCard.standardSet.filter { !MoveCard.directionalRayCards.contains($0) }
        case .choice:
            return [
                .kingUpOrDown,
                .kingLeftOrRight,
                .kingUpwardDiagonalChoice,
                .kingRightDiagonalChoice,
                .kingDownwardDiagonalChoice,
                .kingLeftDiagonalChoice,
                .knightUpwardChoice,
                .knightRightwardChoice,
                .knightDownwardChoice,
                .knightLeftwardChoice
            ]
        case .ray:
            return MoveCard.directionalRayCards
        case .warp:
            return [.fixedWarp, .superWarp]
        }
    }
}

public enum TargetLabTileKind: String, CaseIterable, Codable, Hashable {
    case warp
    case shuffleHand
    case boost
    case slow
    case nextRefresh
    case freeFocus
    case preserveCard
    case draft
    case overload
    case targetSwap
    case openGate

    public var displayName: String {
        switch self {
        case .warp: return "ワープ"
        case .shuffleHand: return "シャッフル"
        case .boost: return "加速"
        case .slow: return "減速"
        case .nextRefresh: return "NEXT更新"
        case .freeFocus: return "無料フォーカス"
        case .preserveCard: return "カード温存"
        case .draft: return "ドラフト"
        case .overload: return "過負荷"
        case .targetSwap: return "転換"
        case .openGate: return "開門"
        }
    }
}

public struct TargetLabExperimentSettings: Equatable, Codable {
    public var enabledCardGroups: Set<TargetLabCardGroup>
    public var enabledTileKinds: Set<TargetLabTileKind>

    public static let `default` = TargetLabExperimentSettings(
        enabledCardGroups: Set(TargetLabCardGroup.allCases),
        enabledTileKinds: Set(TargetLabTileKind.allCases)
    )

    public var hasPlayableCards: Bool { !enabledCardGroups.isEmpty }

    public init(
        enabledCardGroups: Set<TargetLabCardGroup>,
        enabledTileKinds: Set<TargetLabTileKind>
    ) {
        self.enabledCardGroups = enabledCardGroups
        self.enabledTileKinds = enabledTileKinds
    }

    private enum CodingKeys: String, CodingKey {
        case enabledCardGroups
        case enabledTileKinds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedGroups = Self.decodeLossySet(
            forKey: .enabledCardGroups,
            from: container,
            type: TargetLabCardGroup.self
        )
        let decodedTileKinds = Self.decodeLossySet(
            forKey: .enabledTileKinds,
            from: container,
            type: TargetLabTileKind.self
        )

        enabledCardGroups = decodedGroups ?? Self.default.enabledCardGroups
        if enabledCardGroups.isEmpty {
            enabledCardGroups = Self.default.enabledCardGroups
        }
        enabledTileKinds = decodedTileKinds ?? Self.default.enabledTileKinds
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabledCardGroups.map(\.rawValue).sorted(), forKey: .enabledCardGroups)
        try container.encode(enabledTileKinds.map(\.rawValue).sorted(), forKey: .enabledTileKinds)
    }

    private static func decodeLossySet<T: RawRepresentable>(
        forKey key: CodingKeys,
        from container: KeyedDecodingContainer<CodingKeys>,
        type: T.Type
    ) -> Set<T>? where T.RawValue == String, T: Hashable {
        guard container.contains(key) else { return nil }
        let rawValues = (try? container.decode([String].self, forKey: key)) ?? []
        return Set(rawValues.compactMap { T(rawValue: $0) })
    }
}
