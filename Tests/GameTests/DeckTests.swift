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
        let allowedMoves = Deck.Configuration.standard.allowedMoves
        let kingCards = allowedMoves.filter { $0.isKingType }
        let knightCards = allowedMoves.filter { $0.isKnightType }
        let diagonalCards = allowedMoves.filter { $0.isDiagonalDistanceFour }

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
            .kingUpLeft,
            .kingUpOrDown,
            .kingLeftOrRight,
            .kingUpwardDiagonalChoice,
            .kingRightDiagonalChoice,
            .kingDownwardDiagonalChoice,
            .kingLeftDiagonalChoice
        ]

        // allCases の結果を集合化して比較し、山札構築時に含まれることを保証する
        let allCasesSet = Set(MoveCard.allCases)

        // 山札生成が MoveCard.allCases を利用するため、ここで欠けていれば山札からも欠落する
        XCTAssertTrue(kingMoves.isSubset(of: allCasesSet))
    }

    /// standardSet が従来 24 種のみで構成され、新カードが混入していないことを確認する
    func testStandardSetDoesNotIncludeChoiceCards() {
        XCTAssertEqual(MoveCard.standardSet.count, 24, "スタンダードセットの枚数が 24 枚から変化しています")
        XCTAssertFalse(MoveCard.standardSet.contains(.kingUpOrDown), "選択式カードがスタンダードセットへ混入しています")
        XCTAssertFalse(MoveCard.standardSet.contains(.kingLeftOrRight), "選択式カードがスタンダードセットへ混入しています")
        XCTAssertFalse(MoveCard.standardSet.contains(.kingUpwardDiagonalChoice), "選択式カードがスタンダードセットへ混入しています")
        XCTAssertFalse(MoveCard.standardSet.contains(.kingRightDiagonalChoice), "選択式カードがスタンダードセットへ混入しています")
        XCTAssertFalse(MoveCard.standardSet.contains(.kingDownwardDiagonalChoice), "選択式カードがスタンダードセットへ混入しています")
        XCTAssertFalse(MoveCard.standardSet.contains(.kingLeftDiagonalChoice), "選択式カードがスタンダードセットへ混入しています")
        XCTAssertFalse(MoveCard.standardSet.contains(.knightUpwardChoice), "選択式カードがスタンダードセットへ混入しています")
        XCTAssertFalse(MoveCard.standardSet.contains(.knightRightwardChoice), "選択式カードがスタンダードセットへ混入しています")
        XCTAssertFalse(MoveCard.standardSet.contains(.knightDownwardChoice), "選択式カードがスタンダードセットへ混入しています")
        XCTAssertFalse(MoveCard.standardSet.contains(.knightLeftwardChoice), "選択式カードがスタンダードセットへ混入しています")
    }

    /// directionChoice 構成が新カードを含み、重みも設定されていることを検証する
    func testDirectionChoiceDeckIncludesMultiDirectionCards() {
        let config = Deck.Configuration.directionChoice
        let allowedMoves = config.allowedMoves
        XCTAssertTrue(allowedMoves.contains(.kingUpOrDown), "上下選択カードがデッキに含まれていません")
        XCTAssertTrue(allowedMoves.contains(.kingLeftOrRight), "左右選択カードがデッキに含まれていません")

        // 重みが設定されているかを確認（未設定の場合は nil になる）
        XCTAssertEqual(config.baseWeights[.kingUpOrDown], 3, "上下選択カードの重みが想定外です")
        XCTAssertEqual(config.baseWeights[.kingLeftOrRight], 3, "左右選択カードの重みが想定外です")
    }

    /// 上下左右選択キング専用デッキの設定を確認する
    func testKingOrthogonalChoiceOnlyDeckConfiguration() {
        let config = Deck.Configuration.kingOrthogonalChoiceOnly
        XCTAssertEqual(Set(config.allowedMoves), [.kingUpOrDown, .kingLeftOrRight], "許可カードが縦横選択キングのみになっていません")
        XCTAssertEqual(config.deckSummaryText, "上下左右の選択キング限定", "サマリーテキストが仕様と異なります")
        XCTAssertEqual(config.baseWeights.count, 2, "重み設定が 2 種以上になっています")
        XCTAssertEqual(config.baseWeights[.kingUpOrDown], 1, "上下選択キングの重みが想定外です")
        XCTAssertEqual(config.baseWeights[.kingLeftOrRight], 1, "左右選択キングの重みが想定外です")
    }

    /// 斜め選択キング専用デッキの設定を確認する
    func testKingDiagonalChoiceOnlyDeckConfiguration() {
        let config = Deck.Configuration.kingDiagonalChoiceOnly
        let expected: Set<MoveCard> = [
            .kingUpwardDiagonalChoice,
            .kingRightDiagonalChoice,
            .kingDownwardDiagonalChoice,
            .kingLeftDiagonalChoice
        ]
        XCTAssertEqual(Set(config.allowedMoves), expected, "許可カードが斜め選択キング 4 種と一致していません")
        XCTAssertTrue(expected.allSatisfy { config.baseWeights[$0] == 1 }, "斜め選択キングの重みが均等になっていません")
        XCTAssertEqual(config.deckSummaryText, "斜め選択キング限定", "サマリーテキストが仕様と異なります")
    }

    /// 桂馬選択専用デッキの設定を確認する
    func testKnightChoiceOnlyDeckConfiguration() {
        let config = Deck.Configuration.knightChoiceOnly
        let expected: Set<MoveCard> = [
            .knightUpwardChoice,
            .knightRightwardChoice,
            .knightDownwardChoice,
            .knightLeftwardChoice
        ]
        XCTAssertEqual(Set(config.allowedMoves), expected, "許可カードが桂馬選択 4 種と一致していません")
        XCTAssertTrue(expected.allSatisfy { config.baseWeights[$0] == 1 }, "桂馬選択カードの重みが均等になっていません")
        XCTAssertEqual(config.deckSummaryText, "桂馬選択カード限定", "サマリーテキストが仕様と異なります")
    }

    /// 全選択カード混合デッキの設定を確認する
    func testAllChoiceMixedDeckConfiguration() {
        let config = Deck.Configuration.allChoiceMixed
        let expected: Set<MoveCard> = [
            .kingUpOrDown,
            .kingLeftOrRight,
            .kingUpwardDiagonalChoice,
            .kingRightDiagonalChoice,
            .kingDownwardDiagonalChoice,
            .kingLeftDiagonalChoice,
            .knightUpwardChoice,
            .knightRightwardChoice,
            .knightDownwardChoice,
            .knightLeftwardChoice
        ]
        XCTAssertEqual(Set(config.allowedMoves), expected, "全選択カード混合デッキの内容が一致していません")
        XCTAssertTrue(expected.allSatisfy { config.baseWeights[$0] == 1 }, "混合デッキ内の重みが均等ではありません")
        XCTAssertEqual(config.deckSummaryText, "選択カード総合ミックス", "サマリーテキストが仕様と異なります")
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
