import XCTest
@testable import Game

final class MoveCardPresentationTests: XCTestCase {
    func testPresentationMetadataRemainsStableAfterExtraction() {
        XCTAssertEqual(MoveCard.kingUp.displayName, "上1")
        XCTAssertEqual(MoveCard.knightRightwardChoice.displayName, "右桂 (選択)")
        XCTAssertEqual(MoveCard.superWarp.displayName, "全域ワープ")
        XCTAssertEqual(MoveCard.effectStep.displayName, "特殊ステップ")

        XCTAssertEqual(MoveCard.kingUp.kind, .normal)
        XCTAssertEqual(MoveCard.knightLeftwardChoice.kind, .choice)
        XCTAssertEqual(MoveCard.rayDown.kind, .multiStep)
        XCTAssertEqual(MoveCard.effectKnight.kind, .effectAssist)
        XCTAssertEqual(MoveCard.rayDown.multiStepUnitVector, MoveVector(dx: 0, dy: -1))
    }

    func testRegistrySetsRemainStableAfterExtraction() {
        XCTAssertEqual(MoveCard.directionalRayCards.count, 8)
        XCTAssertEqual(MoveCard.standardSet.count, 32)
        XCTAssertTrue(MoveCard.allCases.contains(.fixedWarp))
        XCTAssertTrue(MoveCard.allCases.contains(.superWarp))
        XCTAssertEqual(MoveCard.effectAssistCards, [.effectStep, .effectKnight, .effectLine])
        XCTAssertTrue(MoveCard.allCases.contains(.effectLine))
    }

    func testCardEncyclopediaEntriesCoverAllMoveCards() {
        let entries = MoveCard.encyclopediaEntries

        XCTAssertEqual(entries.count, MoveCard.allCases.count)
        XCTAssertEqual(entries.map(\.card), MoveCard.allCases)
        XCTAssertTrue(entries.allSatisfy { !$0.displayName.isEmpty })
        XCTAssertTrue(entries.allSatisfy { !$0.category.isEmpty })
        XCTAssertTrue(entries.allSatisfy { !$0.description.isEmpty })
    }

    func testRepresentativeCardEncyclopediaMetadata() {
        XCTAssertEqual(MoveCard.kingUp.encyclopediaCategory, "キング")
        XCTAssertTrue(MoveCard.kingUp.encyclopediaDescription.contains("1 マス"))

        XCTAssertEqual(MoveCard.knightRightwardChoice.encyclopediaCategory, "選択ナイト")
        XCTAssertTrue(MoveCard.knightRightwardChoice.encyclopediaDescription.contains("選んで跳びます"))

        XCTAssertEqual(MoveCard.rayDown.encyclopediaCategory, "レイ")
        XCTAssertTrue(MoveCard.rayDown.encyclopediaDescription.contains("盤端や障害物"))

        XCTAssertEqual(MoveCard.superWarp.encyclopediaCategory, "ワープ")
        XCTAssertTrue(MoveCard.effectLine.encyclopediaDescription.contains("特殊マス"))
    }

    func testTileEncyclopediaEntriesCoverCoreTileKinds() {
        let entries = TileEncyclopediaEntry.allEntries
        let entryIDs = Set(entries.map(\.id))

        XCTAssertTrue(entries.allSatisfy { !$0.displayName.isEmpty })
        XCTAssertTrue(entries.allSatisfy { !$0.category.isEmpty })
        XCTAssertTrue(entries.allSatisfy { !$0.description.isEmpty })
        XCTAssertTrue(entryIDs.isSuperset(of: [
            "normal",
            "spawn",
            "target",
            "nextTarget",
            "multiVisit",
            "toggle",
            "impassable",
            "warp",
            "shuffleHand",
            "boost",
            "slow",
            "nextRefresh",
            "freeFocus",
            "preserveCard",
            "draft",
            "overload",
            "targetSwap",
            "openGate"
        ]))
    }
}
