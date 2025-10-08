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

    /// スタンダード軽量デッキが長距離カードの重みを抑えているか検証する
    func testStandardLightDeckConfiguration() {
        let config = Deck.Configuration.standardLight
        let allowedMoves = Set(config.allowedMoves)
        let standardMoves = Set(MoveCard.standardSet)

        // MARK: 標準セットと同じカード群を保持しているか確認
        XCTAssertEqual(allowedMoves, standardMoves, "スタンダード軽量構成のカード集合が標準セットと一致しません")

        // MARK: 長距離カードの重みが通常カードより低く設定されているか検証
        let kingWeight = config.weightProfile.weight(for: .kingUp)
        let longRangeWeight = config.weightProfile.weight(for: .straightUp2)
        XCTAssertGreaterThan(kingWeight, longRangeWeight, "長距離カードの重みが軽量化されていません")
        XCTAssertEqual(longRangeWeight, 1, "長距離カードの重みが想定値と異なります")
        XCTAssertEqual(kingWeight, 3, "キングカードの重みが想定値と異なります")
        XCTAssertEqual(config.weightProfile.weight(for: .rayUp), 1, "レイ型カードの重みが軽量化されていません")

        // MARK: サマリー文言が仕様通りかチェック
        XCTAssertEqual(config.deckSummaryText, "長距離カード抑制型標準デッキ")
    }

    /// 標準デッキへ縦横選択カードを追加するプリセットの内容を検証する
    func testStandardWithOrthogonalChoicesDeckConfiguration() {
        let config = Deck.Configuration.standardWithOrthogonalChoices
        let allowedMoves = Set(config.allowedMoves)
        let standardMoves = Set(MoveCard.standardSet)
        // MARK: 標準カード群がすべて含まれていることを確認
        XCTAssertTrue(standardMoves.isSubset(of: allowedMoves), "標準カードが欠落しています")
        // MARK: 追加カードが正しく入っているか確認
        let expectedChoices: Set<MoveCard> = [.kingUpOrDown, .kingLeftOrRight]
        XCTAssertTrue(expectedChoices.isSubset(of: allowedMoves), "上下左右選択キングが不足しています")
        // MARK: 選択式キングの学習を促すため重み 2 で上書きされていることを確認
        expectedChoices.forEach { choice in
            XCTAssertEqual(config.weightProfile.weight(for: choice), 2, "縦横選択キングの重みが想定値の 2 ではありません: \(choice)")
        }
        // MARK: 既存カードは重み 1 を維持しているか念のためチェック
        XCTAssertEqual(config.weightProfile.weight(for: .kingUp), 1, "標準カードの重みが 1 から変化しています")
        // MARK: サマリー文言がプレイヤー向け説明と一致しているか検証
        XCTAssertEqual(config.deckSummaryText, "標準＋上下左右選択キング")
    }

    /// 標準デッキへ斜め選択カードを追加するプリセットの内容を検証する
    func testStandardWithDiagonalChoicesDeckConfiguration() {
        let config = Deck.Configuration.standardWithDiagonalChoices
        let allowedMoves = Set(config.allowedMoves)
        let standardMoves = Set(MoveCard.standardSet)
        XCTAssertTrue(standardMoves.isSubset(of: allowedMoves), "標準カードが欠落しています")
        let expectedChoices: Set<MoveCard> = [
            .kingUpwardDiagonalChoice,
            .kingRightDiagonalChoice,
            .kingDownwardDiagonalChoice,
            .kingLeftDiagonalChoice
        ]
        XCTAssertTrue(expectedChoices.isSubset(of: allowedMoves), "斜め選択キングが不足しています")
        // MARK: 斜め選択キングだけ重み 2 で抽選されることを検証
        expectedChoices.forEach { choice in
            XCTAssertEqual(config.weightProfile.weight(for: choice), 2, "斜め選択キングの重みが想定値の 2 ではありません: \(choice)")
        }
        // MARK: 標準カードが従来通り重み 1 のままか確認
        XCTAssertEqual(config.weightProfile.weight(for: .kingUp), 1, "標準カードの重みが 1 から変化しています")
        XCTAssertEqual(config.deckSummaryText, "標準＋斜め選択キング")
    }

    /// 標準デッキへ桂馬選択カードを追加するプリセットの内容を検証する
    func testStandardWithKnightChoicesDeckConfiguration() {
        let config = Deck.Configuration.standardWithKnightChoices
        let allowedMoves = Set(config.allowedMoves)
        let standardMoves = Set(MoveCard.standardSet)
        XCTAssertTrue(standardMoves.isSubset(of: allowedMoves), "標準カードが欠落しています")
        let expectedChoices: Set<MoveCard> = [
            .knightUpwardChoice,
            .knightRightwardChoice,
            .knightDownwardChoice,
            .knightLeftwardChoice
        ]
        XCTAssertTrue(expectedChoices.isSubset(of: allowedMoves), "桂馬選択カードが不足しています")
        // MARK: 桂馬選択カードのみ重み 2 に引き上げられていることを確認
        expectedChoices.forEach { choice in
            XCTAssertEqual(config.weightProfile.weight(for: choice), 2, "桂馬選択カードの重みが想定値の 2 ではありません: \(choice)")
        }
        // MARK: スタンダードカードの重みは 1 を維持していることを確認
        XCTAssertEqual(config.weightProfile.weight(for: .knightUp2Right1), 1, "既存桂馬カードの重みが 1 から変化しています")
        XCTAssertEqual(config.deckSummaryText, "標準＋桂馬選択カード")
    }

    /// 標準デッキへ全選択カードを追加するプリセットの内容を検証する
    func testStandardWithAllChoicesDeckConfiguration() {
        let config = Deck.Configuration.standardWithAllChoices
        let allowedMoves = Set(config.allowedMoves)
        let standardMoves = Set(MoveCard.standardSet)
        XCTAssertTrue(standardMoves.isSubset(of: allowedMoves), "標準カードが欠落しています")
        let expectedChoices: Set<MoveCard> = [
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
        XCTAssertTrue(expectedChoices.isSubset(of: allowedMoves), "全選択カードが揃っていません")
        XCTAssertFalse(allowedMoves.contains(.superWarp), "全域ワープカードは別デッキで練習する想定のため混在しません")
        // MARK: 選択式カードは単一方向カードの 2 倍である重み 2 に引き上げられているか検証
        expectedChoices.forEach { choice in
            XCTAssertEqual(config.weightProfile.weight(for: choice), 2, "全選択カードの重みが想定値 2 と異なります: \(choice)")
        }
        // MARK: 既存の単一方向カードは従来どおり重み 1 を維持しているかチェック
        XCTAssertEqual(config.weightProfile.weight(for: .kingUp), 1, "標準カードの重みが 1 から変化しています")
        XCTAssertEqual(config.deckSummaryText, "標準＋全選択カード")
    }

    /// 固定ワープ特化デッキが固定ワープのみで構成されていることを検証する
    func testFixedWarpSpecializedDeckConfiguration() {
        let config = Deck.Configuration.fixedWarpSpecialized
        XCTAssertEqual(config.allowedMoves, [.fixedWarp], "固定ワープ特化デッキには他カードを含めない想定です")
        XCTAssertEqual(config.weightProfile.weight(for: .fixedWarp), 1, "固定ワープの重みは均一の 1 を維持する想定です")
        XCTAssertEqual(config.deckSummaryText, "固定ワープ特化デッキ")
    }

    /// 全域ワープ高頻度デッキが標準カードと全域ワープを適切に混在させているか検証する
    func testSuperWarpHighFrequencyDeckConfiguration() {
        let config = Deck.Configuration.superWarpHighFrequency
        let allowedMoves = Set(config.allowedMoves)
        let standardMoves = Set(MoveCard.standardSet)

        XCTAssertTrue(standardMoves.isSubset(of: allowedMoves), "標準カードが不足しています")
        XCTAssertTrue(allowedMoves.contains(.superWarp), "全域ワープが含まれていません")
        XCTAssertEqual(config.weightProfile.weight(for: .superWarp), 4, "全域ワープの重みが想定値 4 と異なります")
        XCTAssertEqual(config.weightProfile.weight(for: .kingUp), 1, "標準カードの重みが 1 から変化しています")
        XCTAssertEqual(config.deckSummaryText, "標準＋全域ワープ高頻度")
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

    /// standardSet が単方向＋レイ型 32 種のみで構成され、選択カードが含まれないことを確認する
    func testStandardSetDoesNotIncludeChoiceCards() {
        XCTAssertEqual(MoveCard.standardSet.count, 32, "スタンダードセットの枚数が 32 枚ではありません")
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
        MoveCard.directionalRayCards.forEach { card in
            XCTAssertTrue(MoveCard.standardSet.contains(card), "レイ型カードがスタンダードセットから漏れています: \(card)")
        }
    }

    /// レイ型カード特化プリセットの構成と重みを検証する
    func testDirectionalRayFocusDeckConfiguration() {
        let config = Deck.Configuration.directionalRayFocus
        let allowedMoves = Set(config.allowedMoves)
        let expectedRays = Set(MoveCard.directionalRayCards)
        let supportKings: Set<MoveCard> = [.kingUp, .kingRight, .kingDown, .kingLeft]

        XCTAssertTrue(expectedRays.isSubset(of: allowedMoves), "レイ型カードが不足しています")
        XCTAssertTrue(supportKings.isSubset(of: allowedMoves), "補助用キングが不足しています")

        expectedRays.forEach { card in
            XCTAssertEqual(config.weightProfile.weight(for: card), 3, "レイ型カードの重みが想定値 3 と異なります: \(card)")
        }
        supportKings.forEach { card in
            XCTAssertEqual(config.weightProfile.weight(for: card), 1, "補助用キングの重みが想定値 1 と異なります: \(card)")
        }

        XCTAssertEqual(config.deckSummaryText, "連続移動カード集中デッキ", "サマリー文言が仕様と一致していません")
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

    /// キングと桂馬 16 種構成デッキの内容を検証する
    func testKingAndKnightBasicDeckConfiguration() {
        let config = Deck.Configuration.kingAndKnightBasic
        let allowedMoves = Set(config.allowedMoves)
        let expectedMoves = Set(MoveCard.standardSet.filter { $0.isKingType || $0.isKnightType })

        // MARK: キング＋桂馬 16 種が揃っているか確認
        XCTAssertEqual(allowedMoves, expectedMoves, "キング＋ナイト基礎構成のカード集合が仕様と一致しません")

        // MARK: 重み設定が均一かどうか検証
        XCTAssertEqual(config.weightProfile.weight(for: .kingUp), 1, "キングカードの重みが均一ではありません")
        XCTAssertEqual(config.weightProfile.weight(for: .knightUp2Right1), 1, "桂馬カードの重みが均一ではありません")

        // MARK: サマリー文言が仕様通りか確認
        XCTAssertEqual(config.deckSummaryText, "キングと桂馬の基礎デッキ")
    }

    /// キングと桂馬のみの限定デッキを検証する
    func testKingPlusKnightOnlyDeckConfiguration() {
        let config = Deck.Configuration.kingPlusKnightOnly
        let expected: Set<MoveCard> = [
            .kingUp,
            .kingRight,
            .kingDown,
            .kingLeft,
            .knightUp2Right1,
            .knightUp2Left1,
            .knightDown2Right1,
            .knightDown2Left1
        ]

        // MARK: 許可カードが 8 種に限定されているか確認
        XCTAssertEqual(Set(config.allowedMoves), expected, "キング＋ナイト限定構成のカード集合が仕様と一致しません")

        // MARK: 重みが均一に設定されているか確認
        XCTAssertTrue(expected.allSatisfy { config.weightProfile.weight(for: $0) == 1 }, "限定構成の重みが均一になっていません")

        // MARK: サマリー文言が仕様通りかチェック
        XCTAssertEqual(config.deckSummaryText, "キングと桂馬の限定デッキ")
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
