import XCTest
@testable import Game

/// HandManager の補充ロジックを検証するテスト群
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
final class HandManagerTests: XCTestCase {
    /// 任意のカード配列から簡易的な山札設定を生成するヘルパー
    /// - Parameter moves: 許可したい MoveCard の配列
    /// - Returns: テスト用に均一重み・抑制なしで構築した設定
    private func makeConfiguration(moves: [MoveCard]) -> Deck.Configuration {
        Deck.Configuration(
            allowedMoves: moves,
            weightProfile: Deck.WeightProfile(defaultWeight: 1),
            deckSummaryText: "テスト用構成"
        )
    }

    /// ユニーク移動パターン数が 2〜4 種類のデッキでも補充処理が完了することを確認する
    func testRefillHandStacksTerminatesForLimitedUniqueSignatures() {
        // それぞれ異なるユニーク数になる構成を並べ、ループで一括検証する
        let scenarios: [(description: String, configuration: Deck.Configuration, preset: [MoveCard])] = [
            (
                "2種類の斜め選択キング",
                makeConfiguration(moves: [.kingUpwardDiagonalChoice, .kingRightDiagonalChoice]),
                [.kingUpwardDiagonalChoice, .kingUpwardDiagonalChoice, .kingUpwardDiagonalChoice, .kingRightDiagonalChoice, .kingUpwardDiagonalChoice, .kingRightDiagonalChoice]
            ),
            (
                "3種類の直線移動",
                makeConfiguration(moves: [.straightUp2, .straightRight2, .straightDown2]),
                [.straightUp2, .straightUp2, .straightRight2, .straightUp2, .straightDown2, .straightRight2, .straightDown2]
            ),
            (
                "4種類の桂馬選択カード",
                makeConfiguration(moves: [.knightUpwardChoice, .knightRightwardChoice, .knightDownwardChoice, .knightLeftwardChoice]),
                [.knightUpwardChoice, .knightUpwardChoice, .knightRightwardChoice, .knightDownwardChoice, .knightLeftwardChoice, .knightRightwardChoice]
            )
        ]

        for scenario in scenarios {
            var deck = Deck.makeTestDeck(cards: scenario.preset, configuration: scenario.configuration)
            let uniqueCount = deck.uniqueMoveIdentityCount()

            let handManager = HandManager(handSize: 5, nextPreviewCount: 0, allowsCardStacking: true)
            handManager.refillHandStacks(using: &deck)

            // ユニークパターン数と手札上限の小さい方までしかスタックが作られないことを確認する
            XCTAssertEqual(
                handManager.handStacks.count,
                min(5, uniqueCount),
                "\(scenario.description) でスタック数が想定と異なります"
            )
        }
    }

    /// preferredInsertionIndices が上限超過していても無限ループに陥らないことを検証する
    func testRefillHandStacksHandlesExcessPreferredInsertionIndices() {
        let preset: [MoveCard] = [
            .kingUpwardDiagonalChoice,
            .kingRightDiagonalChoice,
            .kingUpwardDiagonalChoice,
            .kingUpwardDiagonalChoice,
            .kingRightDiagonalChoice
        ]
        var deck = Deck.makeTestDeck(
            cards: preset,
            configuration: makeConfiguration(moves: [.kingUpwardDiagonalChoice, .kingRightDiagonalChoice])
        )
        let uniqueCount = deck.uniqueMoveIdentityCount()

        let handManager = HandManager(handSize: 5, nextPreviewCount: 0, allowsCardStacking: true)
        handManager.refillHandStacks(using: &deck, preferredInsertionIndices: [0, 1, 2])

        // ユニーク上限（2 種類）を超えるスタックが生成されていないかチェックする
        XCTAssertEqual(handManager.handStacks.count, min(5, uniqueCount))
    }

    /// 補助カードは移動カードとは別種としてスタック管理されることを確認する
    func testSupportCardsStackSeparatelyFromMoveCards() {
        var deck = Deck.makeTestDeck(playableCards: [
            .support(.refillEmptySlots),
            .move(.kingUpRight),
            .support(.refillEmptySlots),
            .move(.kingUpRight)
        ], configuration: Deck.Configuration(
            allowedMoves: [.kingUpRight],
            allowedSupportCards: [.refillEmptySlots],
            weightProfile: Deck.WeightProfile(defaultWeight: 1),
            deckSummaryText: "補助カードテスト用構成"
        ))

        let handManager = HandManager(handSize: 5, nextPreviewCount: 0, allowsCardStacking: true)
        handManager.refillHandStacks(using: &deck)

        let supportStacks = handManager.handStacks.filter { $0.topCard?.supportCard == .refillEmptySlots }
        let kingStacks = handManager.handStacks.filter { $0.topCard?.moveCard == .kingUpRight }
        XCTAssertEqual(supportStacks.count, 1, "同じ補助カードは同一スタックへまとまる想定です")
        XCTAssertEqual(supportStacks.first?.count, 1)
        XCTAssertEqual(kingStacks.count, 1, "同じ移動カードは従来通り同一スタックへまとまる想定です")
        XCTAssertEqual(kingStacks.first?.count, 1)
    }

    /// 方向ソートではカード種別を最上位にし、補助カードが移動カードの間へ入らないことを確認する
    func testDirectionSortedOrderingKeepsSupportCardsAfterMoveCards() {
        var deck = Deck.makeTestDeck(playableCards: [
            .move(.straightRight2),
            .support(.refillEmptySlots),
            .move(.straightUp2)
        ], configuration: Deck.Configuration(
            allowedMoves: [.straightRight2, .straightUp2],
            allowedSupportCards: [.refillEmptySlots],
            weightProfile: Deck.WeightProfile(defaultWeight: 1),
            deckSummaryText: "方向ソート補助カードテスト用構成"
        ))

        let handManager = HandManager(
            handSize: 5,
            nextPreviewCount: 0,
            allowsCardStacking: true,
            initialOrderingStrategy: .directionSorted
        )
        handManager.refillHandStacks(using: &deck)
        handManager.reorderHandIfNeeded()

        XCTAssertEqual(
            handManager.handStacks.compactMap(\.representativePlayable),
            [
                .move(.straightUp2),
                .move(.straightRight2),
                .support(.refillEmptySlots)
            ]
        )
    }
}
