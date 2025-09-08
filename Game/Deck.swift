import Foundation
#if canImport(GameplayKit)
import GameplayKit
#endif

/// 山札・手札・捨札を管理するデッキ構造体
/// - Note: MoveCard を 5 枚ずつ計 80 枚で構成し、
///         GameplayKit の乱数でシャッフルを行う。
struct Deck {
    // MARK: - 内部状態
    /// 山札。配列の末尾をトップとして扱う
    private var drawPile: [MoveCard] = []
    /// 捨札。使用済みカードを蓄える
    private var discardPile: [MoveCard] = []

    #if canImport(GameplayKit)
    /// 乱数生成器（メルセンヌツイスタ）
    private var random: GKRandomSource
    #else
    /// Linux 等 GameplayKit が使えない環境向けの乱数
    private var random = SystemRandomNumberGenerator()
    #endif

    // MARK: - 初期化
    /// デッキを生成する
    /// - Parameter seed: 乱数シード。指定すると再現性のあるシャッフルとなる
    init(seed: UInt64? = nil) {
        #if canImport(GameplayKit)
        if let seed = seed {
            random = GKMersenneTwisterRandomSource(seed: seed)
        } else {
            random = GKMersenneTwisterRandomSource()
        }
        #endif
        reset() // 80 枚の山札を構築してシャッフル
    }

    // MARK: - デッキ構築
    /// 山札と捨札をリセットし、80 枚のカードをシャッフルする
    mutating func reset() {
        drawPile.removeAll()
        discardPile.removeAll()
        // 各カードを 5 枚ずつ用意
        for _ in 0..<5 {
            drawPile.append(contentsOf: MoveCard.allCases)
        }
        shuffle()
    }

    /// 山札をシャッフルする
    mutating func shuffle() {
        #if canImport(GameplayKit)
        // GameplayKit のシャッフル。Any 配列が返るのでキャストする
        if let shuffled = random.arrayByShufflingObjects(in: drawPile) as? [MoveCard] {
            drawPile = shuffled
        }
        #else
        // 標準ライブラリのシャッフルを使用
        drawPile.shuffle(using: &random)
        #endif
    }

    // MARK: - ドロー処理
    /// 1 枚カードを引く。山札が尽きた場合は捨札から再構築する
    /// - Returns: 引いたカード。全て空なら nil
    mutating func draw() -> MoveCard? {
        // 山札が空なら捨札からリシャッフル
        if drawPile.isEmpty { rebuildFromDiscard() }
        return drawPile.popLast()
    }

    /// 複数枚まとめて引く
    /// - Parameter count: 引く枚数
    /// - Returns: 引いたカード配列（足りない場合は少なくなる）
    mutating func draw(count: Int) -> [MoveCard] {
        var result: [MoveCard] = []
        for _ in 0..<count {
            if let card = draw() { result.append(card) }
        }
        return result
    }

    // MARK: - 捨札処理
    /// 使用済みカードを捨札へ送る
    /// - Parameter card: 捨てるカード
    mutating func discard(_ card: MoveCard) {
        discardPile.append(card)
    }

    /// 捨札から山札を再構築しシャッフルする
    private mutating func rebuildFromDiscard() {
        guard !discardPile.isEmpty else { return }
        drawPile = discardPile
        discardPile.removeAll()
        shuffle()
    }

    // MARK: - 全引き直し
    /// 手札と先読みカードをすべて捨札に送り、新しいカードを引き直す
    /// - Parameters:
    ///   - hand: 現在の手札（3 枚を想定）
    ///   - next: 先読みカード
    /// - Returns: 新しい手札と先読みカードのタプル
    mutating func fullRedraw(hand: [MoveCard], next: MoveCard?) -> (hand: [MoveCard], next: MoveCard?) {
        // 既存カードをすべて捨札へ
        hand.forEach { discard($0) }
        if let next = next { discard(next) }
        // 新しい手札と先読みを引く
        let newHand = draw(count: hand.count)
        let newNext = draw()
        return (newHand, newNext)
    }
}

#if DEBUG
/// テストコードから利用するための拡張
/// - Note: 既存の初期化子 `init(seed:)` を基に、任意のカード列を山札として設定する。
///         本体コードへの影響を避けるため `DEBUG` ビルド時のみ有効。
extension Deck {
    /// 任意のカード配列を山札として持つテスト用デッキを生成する
    /// - Parameter cards: 山札にしたいカード配列（末尾がトップ）
    /// - Returns: 指定したカードのみを含むデッキ
    static func makeTestDeck(cards: [MoveCard]) -> Deck {
        var deck = Deck(seed: 0) // 乱数シードを固定して初期化
        deck.drawPile = cards    // ファイル内拡張のため private にアクセス可能
        deck.discardPile = []    // 捨札は空で開始
        return deck
    }
}
#endif
