import Foundation

/// 移動せずに手札を整える補助専用カード
public enum SupportCard: String, CaseIterable, Codable, Hashable {
    /// NEXT 表示だけを引き直す
    case nextRefresh
    /// 別の手札スタックを 1 種類捨てて補充する
    case swapOne
    /// 表示中目的地へ近づきやすい手札へ寄せる
    case guidance
    /// 空き手札枠を移動カードで補給する
    case refillEmptySlots

    public var displayName: String {
        switch self {
        case .nextRefresh:
            return "NEXT更新"
        case .swapOne:
            return "入替"
        case .guidance:
            return "導き"
        case .refillEmptySlots:
            return "補給"
        }
    }

    public var encyclopediaDescription: String {
        switch self {
        case .nextRefresh:
            return "移動せず 1 手使い、NEXT の 3 枚だけを引き直します。手札はそのまま残ります。"
        case .swapOne:
            return "移動せず 1 手使い、このカード以外の手札 1 種類を捨てて補充します。"
        case .guidance:
            return "移動せず 1 手使い、表示中の目的地へ近づきやすい手札と NEXT に整えます。フォーカス回数は増えません。"
        case .refillEmptySlots:
            return "移動せず 1 手使い、空いている手札枠をランダムな移動カードで補給します。"
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
    static var encyclopediaEntries: [SupportCardEncyclopediaEntry] {
        allCases.enumerated().map { index, card in
            SupportCardEncyclopediaEntry(
                id: index,
                card: card,
                displayName: card.displayName,
                category: "補助カード",
                description: card.encyclopediaDescription
            )
        }
    }
}
