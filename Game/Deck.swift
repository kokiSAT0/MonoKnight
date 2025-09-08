import Foundation

/// デッキを管理する構造体
/// - 備考: 山札・捨札を持ち、山札が尽きたら捨札から再構築する
struct Deck<Card> {
    /// 山札（先頭を末尾として扱うスタック）
    private var drawPile: [Card]
    /// 捨札
    private var discardPile: [Card] = []

    /// 初期化
    /// - Parameter cards: 初期山札に入れるカード配列
    init(cards: [Card]) {
        // 末尾から `popLast()` で引けるよう順序を反転
        self.drawPile = cards.reversed()
    }

    /// 1 枚カードを引く
    /// - Returns: 引いたカード。山札・捨札とも空なら nil
    mutating func draw() -> Card? {
        // 山札が空なら捨札から再構築
        if drawPile.isEmpty {
            rebuild()
        }
        // 再構築後も空なら nil を返す
        return drawPile.popLast()
    }

    /// 使用済みカードを捨札へ送る
    /// - Parameter card: 捨てるカード
    mutating func discard(_ card: Card) {
        discardPile.append(card)
    }

    /// 捨札を山札に戻してリセットする
    mutating func rebuild() {
        // 捨札の順序を保ったまま山札へ積み直し
        drawPile = discardPile.reversed()
        discardPile.removeAll()
    }

    /// 現在の山札が空かを返す
    var isEmpty: Bool { drawPile.isEmpty }
}

