import XCTest
@testable import Game

/// デッキ再構築の挙動を検証するテスト
final class DeckTests: XCTestCase {
    /// 山札が尽きた際に捨札から再構築されるか
    func testDeckRebuild() {
        // 2 枚だけの簡易デッキを用意
        var deck = Deck(cards: [1, 2])

        // 1 枚目を引いて捨て札へ
        let first = deck.draw()!
        deck.discard(first)

        // 2 枚目も同様に処理
        let second = deck.draw()!
        deck.discard(second)

        // ここで山札は空。次に draw すると捨札から再構築される
        let rebuilt = deck.draw()

        // 再構築後の最初のカードは最初に捨てた `1` のはず
        XCTAssertEqual(rebuilt, first)
    }
}
