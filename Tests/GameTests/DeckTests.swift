import XCTest
@testable import Game

/// 重み付き山札の挙動を検証するテスト
final class DeckTests: XCTestCase {
    /// 王将型カードが約 1.5 倍の頻度で出現するかを統計的に確認する
    func testWeightedRandomPrefersKingMoves() {
        var deck = Deck(seed: 12345)
        let sampleCount = 20_000 // 十分な試行回数を確保してばらつきを抑える
        var counts: [MoveCard: Int] = [:]

        for _ in 0..<sampleCount {
            guard let card = deck.draw() else {
                XCTFail("ドロー結果が nil になるのは想定外です")
                return
            }
            counts[card, default: 0] += 1
        }

        let kingCards = MoveCard.allCases.filter { $0.isKingType }
        let otherCards = MoveCard.allCases.filter { !$0.isKingType }
        let kingTotal = kingCards.reduce(0) { $0 + counts[$1, default: 0] }
        let otherTotal = otherCards.reduce(0) { $0 + counts[$1, default: 0] }
        let kingAverage = Double(kingTotal) / Double(kingCards.count)
        let otherAverage = Double(otherTotal) / Double(otherCards.count)
        let ratio = kingAverage / otherAverage

        // 理論上の比率は 3:2 = 1.5。サンプル誤差を考慮し 1.35〜1.65 を許容
        XCTAssertGreaterThanOrEqual(ratio, 1.35, "王将型の平均出現数が期待値より低い: \(ratio)")
        XCTAssertLessThanOrEqual(ratio, 1.65, "王将型の平均出現数が期待値より高い: \(ratio)")
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

    /// makeTestDeck で指定した配列が優先的に返され、reset() で再利用できるか確認
    func testMakeTestDeckUsesPresetSequence() {
        let preset: [MoveCard] = [
            .kingUp,
            .straightRight2,
            .diagonalDownLeft2
        ]
        var deck = Deck.makeTestDeck(cards: preset)

        // --- 初回ドロー ---
        var drawn: [MoveCard] = []
        for _ in 0..<preset.count {
            guard let card = deck.draw() else {
                XCTFail("プリセット配列の長さ分を引けませんでした")
                return
            }
            drawn.append(card)
        }
        XCTAssertEqual(drawn, preset, "プリセット順にカードが返却されていません")

        // プリセット消費後も通常の抽選が継続するかを軽く確認（nil が返らないこと）
        for _ in 0..<10 {
            XCTAssertNotNil(deck.draw(), "プリセット消費後に抽選が停止しています")
        }

        // reset() でプリセットが復元されるか
        deck.reset()
        drawn.removeAll()
        for _ in 0..<preset.count {
            guard let card = deck.draw() else {
                XCTFail("リセット後にプリセットを再取得できませんでした")
                return
            }
            drawn.append(card)
        }
        XCTAssertEqual(drawn, preset, "リセット後のプリセット順が一致しません")
    }
}
