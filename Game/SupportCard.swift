import Foundation

/// 移動せずに効果を発動する補助専用カード
public enum SupportCard: String, CaseIterable, Codable, Hashable {
    /// 空き手札枠を移動カードで補給する
    case refillEmptySlots
    /// 選んだ敵 1 体を消滅させる
    case singleAnnihilationSpell
    /// 現在フロアの敵をすべて消滅させる
    case annihilationSpell

    public var displayName: String {
        switch self {
        case .refillEmptySlots:
            return "補給"
        case .singleAnnihilationSpell:
            return "消滅の呪文"
        case .annihilationSpell:
            return "全滅の呪文"
        }
    }

    public var encyclopediaCategory: String {
        switch self {
        case .refillEmptySlots:
            return "補助カード"
        case .singleAnnihilationSpell, .annihilationSpell:
            return "呪文系カード"
        }
    }

    public var encyclopediaDescription: String {
        switch self {
        case .refillEmptySlots:
            return "移動せず 1 手使い、空いている所持枠を塔用移動カード全体から未所持の移動カードで補給します。"
        case .singleAnnihilationSpell:
            return "移動せず 1 手使い、選んだ敵1体を消滅させます。"
        case .annihilationSpell:
            return "移動せず 1 手使い、このフロアの敵をすべて消滅させます。"
        }
    }

    public var requiresEnemyTargetSelection: Bool {
        switch self {
        case .singleAnnihilationSpell:
            return true
        case .refillEmptySlots, .annihilationSpell:
            return false
        }
    }
}

/// 手札や山札で扱うカード本体
public enum PlayableCard: Codable, Hashable {
    /// 盤面上で駒を移動させるカード
    case move(MoveCard)
    /// 移動せずに手札を整える補助カード
    case support(SupportCard)

    public var move: MoveCard? {
        if case .move(let move) = self { return move }
        return nil
    }

    public var support: SupportCard? {
        if case .support(let support) = self { return support }
        return nil
    }

    public var displayName: String {
        switch self {
        case .move(let move):
            return move.displayName
        case .support(let support):
            return support.displayName
        }
    }

    public var isSupport: Bool {
        if case .support = self { return true }
        return false
    }

    public var identityText: String {
        switch self {
        case .move(let move):
            return "move:\(move.displayName)"
        case .support(let support):
            return "support:\(support.rawValue)"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case move
        case support
    }

    private enum Kind: String, Codable {
        case move
        case support
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decodeIfPresent(Kind.self, forKey: .type) ?? .move
        switch kind {
        case .move:
            self = .move(try container.decode(MoveCard.self, forKey: .move))
        case .support:
            self = .support(try container.decode(SupportCard.self, forKey: .support))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .move(let move):
            try container.encode(Kind.move, forKey: .type)
            try container.encode(move, forKey: .move)
        case .support(let support):
            try container.encode(Kind.support, forKey: .type)
            try container.encode(support, forKey: .support)
        }
    }
}

/// ヘルプ内の補助カード辞典で表示する 1 件分の情報
public struct SupportCardEncyclopediaEntry: Identifiable, Equatable {
    public let id: Int
    public let card: SupportCard
    public let displayName: String
    public let category: String
    public let description: String

    public init(id: Int, card: SupportCard, displayName: String, category: String, description: String) {
        self.id = id
        self.card = card
        self.displayName = displayName
        self.category = category
        self.description = description
    }
}

public extension SupportCard {
    var encyclopediaDiscoveryID: EncyclopediaDiscoveryID {
        EncyclopediaDiscoveryID(category: .supportCard, itemID: rawValue)
    }

    static var encyclopediaEntries: [SupportCardEncyclopediaEntry] {
        allCases.enumerated().map { index, card in
            SupportCardEncyclopediaEntry(
                id: index,
                card: card,
                displayName: card.displayName,
                category: card.encyclopediaCategory,
                description: card.encyclopediaDescription
            )
        }
    }
}
