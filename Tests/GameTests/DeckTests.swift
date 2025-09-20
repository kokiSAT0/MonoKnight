import XCTest
@testable import Game

/// デッキ再構築の挙動を検証するテスト
final class DeckTests: XCTestCase {
    /// 山札が尽きた際に捨札から再構築されるか
    func testDeckRebuild() {
        // テスト専用の小規模デッキを 1 枚だけ用意
        // 末尾が山札のトップになる点に注意
        var deck = Deck.makeTestDeck(cards: [.knightUp2Right1])

        // --- 1 回目のドロー ---
        // 山札から 1 枚引き、同じカードを捨札へ送る
        let firstDraw = deck.draw()!
        deck.discard(firstDraw)

        // --- 2 回目のドロー ---
        // 山札が空になったため、捨札から自動的に再構築される
        // この時点で捨札には 1 枚だけ存在するため、同じカードが戻るはず
        let rebuilt = deck.draw()

        // 再構築後に引いたカードが最初に引いたものと一致するかを検証
        XCTAssertEqual(rebuilt, firstDraw)
    }

    /// MoveCard.allCases にキング型 8 種が含まれているかを検証する
    func testMoveCardAllCasesContainsKingMoves() {
        // 期待するキング型カードを明示的に列挙し、抜け漏れを防ぐ
        let kingMoves: Set<MoveCard> = [
            .kingUp,
            .kingUpRight,
            .kingRight,
            .kingDownRight,
            .kingDown,
            .kingDownLeft,
            .kingLeft,
            .kingUpLeft
        ]

        // allCases の結果を集合化して比較し、山札構築時に含まれることを保証する
        let allCasesSet = Set(MoveCard.allCases)

        // 山札生成が MoveCard.allCases を利用するため、ここで欠けていれば山札からも欠落する
        XCTAssertTrue(kingMoves.isSubset(of: allCasesSet))
    }
}
