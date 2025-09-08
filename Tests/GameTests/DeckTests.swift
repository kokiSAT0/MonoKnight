import XCTest
@testable import Game

/// デッキ再構築の挙動を検証するテスト
final class DeckTests: XCTestCase {
    /// 山札が尽きた際に捨札から再構築されるか
    func testDeckRebuild() {
        // シード指定で 2 枚のみのテスト用デッキを生成
        // 配列の先頭から順に引かれる点に注意
        var deck = Deck.makeTestDeck(
            cards: [.knightUp2Right1, .knightUp2Left1],
            seed: 0
        )

        // --- 1 枚目の処理 ---
        // 山札から 1 枚目を引く（結果: knightUp2Right1）
        let first = deck.draw()!
        // 引いたカードをそのまま捨札へ投入
        deck.discard(first)
        // ここまでで山札は 1 枚、捨札は [first]

        // --- 2 枚目の処理 ---
        // 残り 1 枚を引いて捨札へ送る
        let second = deck.draw()!
        deck.discard(second)
        // これで山札は空、捨札は [first, second]

        // --- 再構築の確認 ---
        // 山札が空の状態で 1 枚目をドローすると、捨札から山札が再構築される
        let rebuiltFirst = deck.draw()
        // 続けてもう 1 枚ドローすると、元の 2 枚がすべて戻るはず
        let rebuiltSecond = deck.draw()

        // 再構築後に得られたカード集合は、捨て札に送った 2 枚と一致する
        let rebuiltSet = Set([rebuiltFirst, rebuiltSecond].compactMap { $0 })
        let originalSet = Set([first, second])
        XCTAssertEqual(rebuiltSet, originalSet)
    }
}
