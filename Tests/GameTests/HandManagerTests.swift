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
            shouldApplyProbabilityReduction: false,
            normalWeightMultiplier: 1,
            reducedWeightMultiplier: 1,
            reductionDuration: 0,
            deckSummaryText: "テスト用構成"
        )
    }

    /// ユニーク移動パターン数が 2〜4 種類のデッキでも補充処理が完了することを確認する
    func testRefillHandStacksTerminatesForLimitedUniqueSignatures() {
        // それぞれ異なるユニーク数になる構成を並べ、ループで一括検証する
        let scenarios: [(description: String, configuration: Deck.Configuration, preset: [MoveCard])] = [
            (
                "2種類の選択キング",
                .kingOrthogonalChoiceOnly,
                [.kingUpOrDown, .kingUpOrDown, .kingUpOrDown, .kingLeftOrRight, .kingUpOrDown, .kingLeftOrRight]
            ),
            (
                "3種類の直線移動",
                makeConfiguration(moves: [.kingUp, .kingRight, .kingDown]),
                [.kingUp, .kingUp, .kingRight, .kingUp, .kingDown, .kingRight, .kingDown]
            ),
            (
                "4種類の桂馬選択カード",
                .knightChoiceOnly,
                [.knightUpwardChoice, .knightUpwardChoice, .knightRightwardChoice, .knightDownwardChoice, .knightLeftwardChoice, .knightRightwardChoice]
            )
        ]

        for scenario in scenarios {
            var deck = Deck.makeTestDeck(cards: scenario.preset, configuration: scenario.configuration)
            let uniqueCount = deck.uniqueMoveSignatureCount()

            let handManager = HandManager(handSize: 5, nextPreviewCount: 0, allowsCardStacking: true)
            handManager.refillHandStacks(using: &deck)

            // ユニークシグネチャ数と手札上限の小さい方までしかスタックが作られないことを確認する
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
            .kingUpOrDown,
            .kingLeftOrRight,
            .kingUpOrDown,
            .kingUpOrDown,
            .kingLeftOrRight
        ]
        var deck = Deck.makeTestDeck(cards: preset, configuration: .kingOrthogonalChoiceOnly)
        let uniqueCount = deck.uniqueMoveSignatureCount()

        let handManager = HandManager(handSize: 5, nextPreviewCount: 0, allowsCardStacking: true)
        handManager.refillHandStacks(using: &deck, preferredInsertionIndices: [0, 1, 2])

        // ユニーク上限（2 種類）を超えるスタックが生成されていないかチェックする
        XCTAssertEqual(handManager.handStacks.count, min(5, uniqueCount))
    }
}
