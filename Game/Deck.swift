import Foundation
import GameplayKit

/// 山札・捨札・手札の引き直しを管理する構造体
/// - 備考: 16 種の `MoveCard` を各5枚ずつ用意し、合計80枚で構成される
struct Deck {
    /// 山札（ドローするカードの山）
    private var drawPile: [MoveCard]
    /// 捨札（使用済みカードの置き場）
    private var discardPile: [MoveCard]
    /// 乱数生成器。シード指定で再現性のあるシャッフルを実現
    private var randomSource: GKRandomSource

    /// 初期化。デッキを構築し、初回シャッフルを行う
    /// - Parameter seed: 乱数シード（指定しない場合はランダム）
    init(seed: UInt64? = nil) {
        // 乱数生成器の用意。GameplayKit のメルセンヌツイスターを使用
        if let seed = seed {
            self.randomSource = GKMersenneTwisterRandomSource(seed: seed)
        } else {
            self.randomSource = GKMersenneTwisterRandomSource()
        }

        // 16 種のカードを各 5 枚ずつ複製して山札を作成
        var cards: [MoveCard] = []
        for card in MoveCard.all {
            for _ in 0..<5 {
                cards.append(card)
            }
        }
        self.drawPile = cards
        self.discardPile = []

        // 初回にシャッフルしておく
        shuffle()
    }

    /// 山札をシャッフルする
    /// - 備考: GameplayKit の `arrayByShufflingObjects` を利用
    mutating func shuffle() {
        let shuffled = randomSource.arrayByShufflingObjects(in: drawPile)
        self.drawPile = shuffled as? [MoveCard] ?? drawPile
    }

    /// 1 枚カードを引く
    /// - Returns: ドローしたカード。山札が枯渇している場合は nil
    /// - note: 山札が空で捨札が存在する場合は自動的に再構築する
    mutating func draw() -> MoveCard? {
        // 山札が空なら捨札から再構築を試みる
        if drawPile.isEmpty {
            reshuffle()
        }
        // 再構築後でも空ならドロー不可
        guard !drawPile.isEmpty else { return nil }
        return drawPile.removeFirst()
    }

    /// 複数枚のドローを行う
    /// - Parameter count: 引きたい枚数
    /// - Returns: ドローしたカードの配列（不足分は欠損する）
    mutating func draw(_ count: Int) -> [MoveCard] {
        var results: [MoveCard] = []
        for _ in 0..<count {
            if let card = draw() {
                results.append(card)
            }
        }
        return results
    }

    /// 指定したカードを捨札に置く
    /// - Parameter card: 捨てたいカード
    mutating func discard(_ card: MoveCard) {
        discardPile.append(card)
    }

    /// 捨札を山札に戻してシャッフルする
    /// - note: 捨札が空の場合は何もしない
    mutating func reshuffle() {
        guard !discardPile.isEmpty else { return }
        drawPile.append(contentsOf: discardPile)
        discardPile.removeAll()
        shuffle()
    }

    /// 手札をすべて引き直す（全引き直し）
    /// - Parameter hand: 引き直したい手札（inout で上書き）
    mutating func mulligan(hand: inout [MoveCard]) {
        // 現在の手札枚数を保持しておく
        let count = hand.count

        // 現在の手札をすべて捨札に移動
        for card in hand {
            discard(card)
        }
        hand.removeAll()

        // 退避しておいた枚数分だけ新しくドローし直す
        let newCards = draw(count)
        hand.append(contentsOf: newCards)
    }
}

