import XCTest
@testable import Game

/// 重み付き山札の挙動を検証するテスト
final class DeckTests: XCTestCase {
    /// 標準デッキの重みプロファイルが全カードで均一になっていることを直接検証する
    func testStandardDeckWeightProfileIsUniform() {
        let config = Deck.Configuration.standard
        let allowedMoves = config.allowedMoves

        // --- 標準デッキに対象カードが存在することを確認（安全策） ---
        XCTAssertFalse(allowedMoves.isEmpty, "標準デッキの許可カードが空です")

        // --- 重みプロファイルから取得した値がすべて同一か検証する ---
        let weights = allowedMoves.map { config.weightProfile.weight(for: $0) }
        let uniqueWeights = Set(weights)

        // 少なくとも一つの値が取得できていることを確認
        XCTAssertFalse(uniqueWeights.isEmpty, "重みプロファイルから値を取得できませんでした")

        // 均一重みであれば集合の要素数は 1 になる想定
        XCTAssertEqual(uniqueWeights.count, 1, "標準デッキの重みがカードごとにばらついています: \(uniqueWeights)")

        // 現行仕様では 1 を想定値として扱うため、値自体も確認する
        XCTAssertEqual(uniqueWeights.first, 1, "標準デッキの重みが 1 以外になっています")
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

        // 重みプロファイル経由で均一重みになっているかを確認
        XCTAssertEqual(config.weightProfile.weight(for: .kingUpOrDown), 1, "上下選択カードの重みが均一ではありません")
        XCTAssertEqual(config.weightProfile.weight(for: .kingLeftOrRight), 1, "左右選択カードの重みが均一ではありません")
    }

    /// 上下左右選択キング専用デッキの設定を確認する
    func testKingOrthogonalChoiceOnlyDeckConfiguration() {
        let config = Deck.Configuration.kingOrthogonalChoiceOnly
        XCTAssertEqual(Set(config.allowedMoves), [.kingUpOrDown, .kingLeftOrRight], "許可カードが縦横選択キングのみになっていません")
        XCTAssertEqual(config.deckSummaryText, "上下左右の選択キング限定", "サマリーテキストが仕様と異なります")
        XCTAssertEqual(config.weightProfile.weight(for: .kingUpOrDown), 1, "上下選択キングの重みが均一ではありません")
        XCTAssertEqual(config.weightProfile.weight(for: .kingLeftOrRight), 1, "左右選択キングの重みが均一ではありません")
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
        XCTAssertTrue(expected.allSatisfy { config.weightProfile.weight(for: $0) == 1 }, "斜め選択キングの重みが均等になっていません")
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
        XCTAssertTrue(expected.allSatisfy { config.weightProfile.weight(for: $0) == 1 }, "桂馬選択カードの重みが均等になっていません")
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
        XCTAssertTrue(expected.allSatisfy { config.weightProfile.weight(for: $0) == 1 }, "混合デッキ内の重みが均等ではありません")
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
