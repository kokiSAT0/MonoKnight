import Foundation
import GameplayKit

/// 山札・手札・捨札を管理する構造体
/// - Note: 16 種の `MoveCard` を各 5 枚ずつ、計 80 枚で構成される
struct Deck {
    // MARK: - 内部状態
    /// 乱数生成器（シード指定で再現性を持たせる）
    private var random: GKMersenneTwisterRandomSource
    /// ドローに使用する山札
    private var drawPile: [MoveCard]
    /// 使用済みカードを保持する捨札
    private var discardPile: [MoveCard]

    // MARK: - 初期化
    /// デッキを初期化しシャッフルする
    /// - Parameter seed: 乱数シード。省略時は現在時刻を使用
    init(seed: UInt64 = UInt64(Date().timeIntervalSince1970)) {
        self.random = GKMersenneTwisterRandomSource(seed: seed)
        self.drawPile = []
        self.discardPile = []
        resetDeck()
    }

    /// 80 枚のカードを再生成してシャッフルする
    private mutating func resetDeck() {
        // 各カードを 5 枚ずつ山札に追加
        drawPile = []
        for _ in 0..<5 {
            drawPile.append(contentsOf: MoveCard.allCases)
        }
        // シャッフルして初期化完了
        shuffle()
    }

    // MARK: - 山札操作
    /// 山札をシャッフルする
    mutating func shuffle() {
        // GameplayKit の乱数を利用してシャッフル
        drawPile = random.arrayByShufflingObjects(in: drawPile) as? [MoveCard] ?? drawPile
    }

    /// 1 枚カードを引く。山札が空なら捨札を再構築してから引く
    /// - Returns: 引いた `MoveCard`。デッキが完全に空の場合は nil
    mutating func draw() -> MoveCard? {
        if drawPile.isEmpty {
            reshuffleFromDiscard()
        }
        return drawPile.isEmpty ? nil : drawPile.removeLast()
    }

    /// 指定枚数のカードを引く
    /// - Parameter count: 引きたい枚数
    /// - Returns: 引いたカードの配列（不足分は無視）
    mutating func drawCards(_ count: Int) -> [MoveCard] {
        var cards: [MoveCard] = []
        for _ in 0..<count {
            guard let card = draw() else { break }
            cards.append(card)
        }
        return cards
    }

    /// 使用済みカードを捨札に移動する
    /// - Parameter card: 捨てたいカード
    mutating func discard(_ card: MoveCard) {
        discardPile.append(card)
    }

    /// 捨札から山札を再構築しシャッフルする
    mutating func reshuffleFromDiscard() {
        guard !discardPile.isEmpty else { return }
        drawPile = discardPile
        discardPile.removeAll()
        shuffle()
    }

    /// 全引き直し: 手札をすべて捨札に送り、同枚数の新しいカードを引く
    /// - Parameter hand: 現在の手札（呼び出し元で保持している配列）
    mutating func redrawHand(_ hand: inout [MoveCard]) {
        let count = hand.count
        // 手札を捨札に移動
        discardPile.append(contentsOf: hand)
        hand.removeAll()
        // 同枚数のカードを新たに引く
        hand.append(contentsOf: drawCards(count))
    }
}

