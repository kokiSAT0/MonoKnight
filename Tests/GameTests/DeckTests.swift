import XCTest
@testable import Game

/// 塔用カードプールとテスト用固定ドローの挙動を検証する
final class DeckTests: XCTestCase {
    func testStandardLightDeckConfiguration() {
        let config = Deck.Configuration.standardLight
        XCTAssertEqual(Set(config.allowedMoves), Set(MoveCard.standardSet))

        let shortRangeWeight = config.weightProfile.weight(for: .kingUpRight)
        let longRangeWeight = config.weightProfile.weight(for: .straightUp2)
        XCTAssertEqual(shortRangeWeight, 3)
        XCTAssertEqual(longRangeWeight, 1)
        XCTAssertEqual(config.weightProfile.weight(for: .rayUp), 1)
        XCTAssertGreaterThan(shortRangeWeight, longRangeWeight)
    }

    func testKingAndKnightBasicDeckConfiguration() {
        let config = Deck.Configuration.kingAndKnightBasic
        let expectedMoves = Set(MoveCard.standardSet.filter { $0.isKingType || $0.isKnightType })
        XCTAssertEqual(Set(config.allowedMoves), expectedMoves)
        XCTAssertTrue(expectedMoves.allSatisfy { config.weightProfile.weight(for: $0) == 1 })
    }

    func testMoveCardAllCasesContainsTowerRewardMoves() {
        let expected: Set<MoveCard> = [
            .straightRight2,
            .straightLeft2,
            .straightUp2,
            .straightDown2,
            .diagonalUpRight2,
            .diagonalDownRight2,
            .diagonalDownLeft2,
            .diagonalUpLeft2,
            .rayRight,
            .rayLeft,
            .rayUp,
            .rayDown,
            .knightRightwardChoice,
            .knightLeftwardChoice,
            .knightUpwardChoice,
            .knightDownwardChoice
        ]
        XCTAssertTrue(expected.isSubset(of: Set(MoveCard.allCases)))
    }

    func testMakeTestDeckUsesPresetSequence() {
        let preset: [MoveCard] = [
            .kingUpRight,
            .straightRight2,
            .diagonalDownLeft2
        ]
        var deck = Deck.makeTestDeck(cards: preset)

        var drawn: [MoveCard] = []
        for _ in 0..<preset.count {
            guard let card = deck.draw() else {
                XCTFail("プリセット配列の長さ分を引けませんでした")
                return
            }
            drawn.append(card.move)
        }
        XCTAssertEqual(drawn, preset)

        for _ in 0..<10 {
            XCTAssertNotNil(deck.draw())
        }

        deck.reset()
        drawn.removeAll()
        for _ in 0..<preset.count {
            guard let card = deck.draw() else {
                XCTFail("リセット後にプリセットを再取得できませんでした")
                return
            }
            drawn.append(card.move)
        }
        XCTAssertEqual(drawn, preset)
    }

    func testBonusMoveCardsAddMissingCardsAndIncreaseExistingWeights() {
        let config = Deck.Configuration.kingAndKnightBasic.addingBonusMoveCards([
            .kingUpRight,
            .rayRight
        ])

        XCTAssertTrue(config.allowedMoves.contains(.rayRight))
        XCTAssertEqual(config.weightProfile.weight(for: .kingUpRight), 2)
        XCTAssertEqual(config.weightProfile.weight(for: .rayRight), 2)
        XCTAssertTrue(config.deckSummaryText.contains("報酬"))
    }
}
