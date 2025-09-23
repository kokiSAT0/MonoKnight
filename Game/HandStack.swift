import Foundation

/// 手札の 1 スロットをスタック形式で管理するための構造体
/// - Note: 同じ種類のカードを重ねて保持し、UI では常に最上段の `DealtCard` を表示する。
public struct HandStack: Identifiable, Equatable {
    /// スタック自体を識別するための UUID
    public let id: UUID
    /// スタックに積まれているカード列（末尾が最新＝表向きのカード）
    public private(set) var cards: [DealtCard]

    /// イニシャライザ
    /// - Parameters:
    ///   - id: 既存スタックを再構築するときに利用する識別子（省略時は自動採番）
    ///   - cards: スタックへ積むカード配列（少なくとも 1 枚必要）
    public init(id: UUID = UUID(), cards: [DealtCard]) {
        // 空配列はスタックとして成立しないため、デバッグビルドでは気付きやすいようアサートを入れておく
        assert(!cards.isEmpty, "HandStack は最低 1 枚のカードを保持する必要があります")
        self.id = id
        self.cards = cards
    }

    /// 先頭に表示されるカード（末尾の要素）
    public var topCard: DealtCard? { cards.last }

    /// スタックに積まれているカード枚数
    public var count: Int { cards.count }

    /// スタックが空になっているかどうか
    public var isEmpty: Bool { cards.isEmpty }

    /// 最新カードの MoveCard を取得する。スタックが空の場合は nil。
    public var representativeMove: MoveCard? { topCard?.move }

    /// 同じ種類のカードを積み増しする
    /// - Parameter card: 追加したい `DealtCard`
    public mutating func append(_ card: DealtCard) {
        cards.append(card)
    }

    /// 表向きのカードを 1 枚取り除く
    /// - Returns: 取り除いた `DealtCard`（スタックが空だった場合は nil）
    @discardableResult
    public mutating func removeTopCard() -> DealtCard? {
        guard !cards.isEmpty else { return nil }
        return cards.removeLast()
    }
}
