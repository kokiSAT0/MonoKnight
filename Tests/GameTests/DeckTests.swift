import XCTest
@testable import Game

/// デッキ再構築の挙動を検証するテスト
final class DeckTests: XCTestCase {
    /// 山札が尽きた際に捨札から再構築されるか
    func testDeckRebuild() {
        // 乱数シードを固定してデッキを生成
        var deck = Deck(seed: 0)

        // 80 枚すべてのカードを引いて捨札に送る
        // MoveCard は 16 種 × 5 枚 = 80 枚
        for _ in 0..<(MoveCard.allCases.count * 5) {
            let card = deck.draw()!
            deck.discard(card)
        }

        // 山札が空になった状態で draw すると捨札から再構築される
        let rebuilt = deck.draw()

        // 再構築後は何らかのカードが返るはず（nil でないことを確認）
        XCTAssertNotNil(rebuilt)
    }
}
