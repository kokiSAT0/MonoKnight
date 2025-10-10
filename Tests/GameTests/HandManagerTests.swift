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
            .kingUpOrDown,
            .kingLeftOrRight,
            .kingUpOrDown,
            .kingUpOrDown,
            .kingLeftOrRight
        ]
        var deck = Deck.makeTestDeck(cards: preset, configuration: .kingOrthogonalChoiceOnly)
        let uniqueCount = deck.uniqueMoveIdentityCount()

        let handManager = HandManager(handSize: 5, nextPreviewCount: 0, allowsCardStacking: true)
        handManager.refillHandStacks(using: &deck, preferredInsertionIndices: [0, 1, 2])

        // ユニーク上限（2 種類）を超えるスタックが生成されていないかチェックする
        XCTAssertEqual(handManager.handStacks.count, min(5, uniqueCount))
    }

    /// 固定ワープカードが異なる目的地を指す場合はスタックしないことを検証する
    func testFixedWarpCardsWithDifferentDestinationsDoNotStack() {
        // 固定ワープカードを含む構成を用意し、異なる目的地を 2 つ割り当てる
        let configuration = Deck.Configuration.standard.addingFixedWarpCard()
        let destinations = [
            GridPoint(x: 0, y: 0),
            GridPoint(x: 4, y: 4)
        ]
        var deck = Deck.makeTestDeck(
            cards: [.fixedWarp, .fixedWarp],
            configuration: configuration,
            fixedWarpDestinations: destinations
        )

        let handManager = HandManager(handSize: 5, nextPreviewCount: 0, allowsCardStacking: true)
        handManager.refillHandStacks(using: &deck)

        // 手札内で固定ワープカードが 2 スタックに分かれていることを確認する（他カードの補充でスタック数自体は増えても良い）
        let fixedWarpStacks = handManager.handStacks.filter { $0.topCard?.move == .fixedWarp }
        XCTAssertEqual(fixedWarpStacks.count, 2, "目的地が異なる固定ワープカードは別スタックで管理されるべきです")
        let obtainedDestinations = fixedWarpStacks.compactMap { $0.topCard?.fixedWarpDestination }
        XCTAssertEqual(
            Set(obtainedDestinations),
            Set(destinations),
            "手札に保持されたワープ先が想定と一致していません"
        )
        // 各スタック内部でも目的地が混在していないことを念押しでチェックする
        for stack in fixedWarpStacks {
            guard let representative = stack.topCard?.fixedWarpDestination else {
                XCTFail("ワープスタックの代表カードに目的地がありません")
                continue
            }
            XCTAssertTrue(
                stack.cards.allSatisfy { $0.fixedWarpDestination == representative },
                "同一スタック内には同じ目的地のみが積まれている必要があります"
            )
        }
    }

    /// 固定ワープカードが同一目的地を共有している場合は従来通りスタックされることを確認する
    func testFixedWarpCardsWithIdenticalDestinationsStack() {
        // 同じ目的地を 2 回供給し、スタックが 1 つにまとまることを検証する
        let configuration = Deck.Configuration.standard.addingFixedWarpCard()
        let destination = GridPoint(x: 2, y: 3)
        var deck = Deck.makeTestDeck(
            cards: [.fixedWarp, .fixedWarp],
            configuration: configuration,
            fixedWarpDestinations: [destination, destination]
        )

        let handManager = HandManager(handSize: 5, nextPreviewCount: 0, allowsCardStacking: true)
        handManager.refillHandStacks(using: &deck)

        // 同一目的地であればカード情報が一致するため、従来通り 1 スタックへ積み重なる
        let fixedWarpStacks = handManager.handStacks.filter { $0.topCard?.move == .fixedWarp }
        XCTAssertEqual(fixedWarpStacks.count, 1, "同一目的地の固定ワープカードは 1 スタックで共有される想定です")
        XCTAssertGreaterThanOrEqual(fixedWarpStacks.first?.count ?? 0, 2, "同一スタック内に 2 枚以上積まれている必要があります")
        XCTAssertEqual(fixedWarpStacks.first?.topCard?.fixedWarpDestination, destination)
    }
}
