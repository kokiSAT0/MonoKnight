import Foundation
#if canImport(GameplayKit)
import GameplayKit
#endif

/// 山札・手札・捨札を管理するデッキ構造体
/// - Note: 標準カードは 1 種につき 5 枚、王将型はその 2 倍の 10 枚を投入し、
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

    /// 標準カード 1 種あたりの基準枚数
    private static let standardCopiesPerCard = 5
    /// 王将型カード 1 種あたりの枚数（標準の 2 倍）
    private static let kingCopiesPerCard = Self.standardCopiesPerCard * 2

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
        reset() // 各種カードを所定枚数だけ構築してシャッフル
    }

    // MARK: - デッキ構築
    /// 山札と捨札をリセットし、配分調整済みのカードをシャッフルする
    mutating func reset() {
        drawPile.removeAll()
        discardPile.removeAll()
        // 王将型は標準カードの 2 倍、それ以外は基準枚数を追加
        for card in MoveCard.allCases {
            let copies = card.isKingType ? Deck.kingCopiesPerCard : Deck.standardCopiesPerCard
            // Array(repeating:) を使って同一カードを必要枚数だけ追加
            drawPile.append(contentsOf: Array(repeating: card, count: copies))
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
    ///   - hand: 現在の手札（渡された枚数分だけ新たに引き直す）
    ///   - nextCards: 現在先読みとして保持しているカード群
    ///   - nextCount: 先読みとして確保したい枚数（例: 3 枚）
    /// - Returns: 新しい手札と先読みカード群のタプル
    mutating func fullRedraw(hand: [MoveCard], nextCards: [MoveCard], nextCount: Int) -> (hand: [MoveCard], nextCards: [MoveCard]) {
        // 既存カードをすべて捨札へ
        hand.forEach { discard($0) }
        nextCards.forEach { discard($0) }
        // hand.count を利用することで、手札枚数が 5 枚でも柔軟に再配布できる
        let newHand = draw(count: hand.count)
        // 先読み枚数は nextCount を基準に確保する
        let newNextCards = draw(count: nextCount)
        return (newHand, newNextCards)
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
