import XCTest
@testable import Game

/// 重み付き山札の挙動を検証するテスト
final class DeckTests: XCTestCase {
    /// 山札の重み付けが仕様通り（キング 1.5 倍・斜め 2 マスは桂馬の半分）になっているか統計的に確認する
    func testWeightedRandomPrefersKingMoves() {
        var deck = Deck(seed: 12345)
        let sampleCount = 20_000 // 十分な試行回数を確保してばらつきを抑える
        var counts: [MoveCard: Int] = [:]

        for _ in 0..<sampleCount {
            guard let dealtCard = deck.draw() else {
                XCTFail("ドロー結果が nil になるのは想定外です")
                return
            }
            counts[dealtCard.move, default: 0] += 1
        }

        // --- 各カテゴリの平均出現回数を計算 ---
        let kingCards = MoveCard.allCases.filter { $0.isKingType }
        let knightCards = MoveCard.allCases.filter { $0.isKnightType }
        let diagonalCards = MoveCard.allCases.filter { $0.isDiagonalDistanceFour }

        func average(for cards: [MoveCard]) -> Double {
            // 該当カードが存在しない場合は 0 を返す（安全策）
            guard !cards.isEmpty else { return 0 }
            let total = cards.reduce(0) { $0 + counts[$1, default: 0] }
            return Double(total) / Double(cards.count)
        }

        let kingAverage = average(for: kingCards)
        let knightAverage = average(for: knightCards)
        let diagonalAverage = average(for: diagonalCards)

        // サンプルデータが正しく集計できているか前提チェック
        XCTAssertGreaterThan(kingAverage, 0, "キング型の平均値が 0 です")
        XCTAssertGreaterThan(knightAverage, 0, "ナイト型の平均値が 0 です")
        XCTAssertGreaterThan(diagonalAverage, 0, "斜め 2 マス型の平均値が 0 です")

        // --- 比率チェック ---
        let kingToKnight = kingAverage / knightAverage
        let diagonalToKnight = diagonalAverage / knightAverage

        // 理論上の比率は 3:2 = 1.5。サンプル誤差を考慮し 1.35〜1.65 を許容
        XCTAssertGreaterThanOrEqual(kingToKnight, 1.35, "王将型の平均出現数が期待値より低い: \(kingToKnight)")
        XCTAssertLessThanOrEqual(kingToKnight, 1.65, "王将型の平均出現数が期待値より高い: \(kingToKnight)")

        // 斜め 2 マスは 1:2 = 0.5 を目標。許容範囲を 0.4〜0.6 に設定
        XCTAssertGreaterThanOrEqual(diagonalToKnight, 0.4, "斜め 2 マスカードの平均出現数が期待値より低い: \(diagonalToKnight)")
        XCTAssertLessThanOrEqual(diagonalToKnight, 0.6, "斜め 2 マスカードの平均出現数が期待値より高い: \(diagonalToKnight)")
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

    /// クラシカルチャレンジ設定では桂馬カードのみが配られるか検証する
    func testClassicalChallengeDeckDrawsOnlyKnightMoves() {
        var deck = Deck(seed: 2024, configuration: .classicalChallenge)
        let sampleCount = 200
        for _ in 0..<sampleCount {
            guard let card = deck.draw()?.move else {
                XCTFail("クラシカルチャレンジのデッキで nil が返却されました")
                return
            }
            XCTAssertTrue(card.isKnightType, "桂馬以外のカードが出現: \(card)")
        }
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
            drawn.append(card.move)
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
            drawn.append(card.move)
        }
        XCTAssertEqual(drawn, preset, "リセット後のプリセット順が一致しません")
    }
}
