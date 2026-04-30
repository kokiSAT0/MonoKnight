import XCTest
@testable import Game

final class MoveCardPresentationTests: XCTestCase {
    func testPresentationMetadataRemainsStableAfterExtraction() {
        XCTAssertEqual(MoveCard.kingUp.displayName, "上1")
        XCTAssertEqual(MoveCard.knightRightwardChoice.displayName, "右桂 (選択)")
        XCTAssertEqual(MoveCard.superWarp.displayName, "全域ワープ")

        XCTAssertEqual(MoveCard.kingUp.kind, .normal)
        XCTAssertEqual(MoveCard.knightLeftwardChoice.kind, .choice)
        XCTAssertEqual(MoveCard.rayDown.kind, .multiStep)
        XCTAssertEqual(MoveCard.rayDown.multiStepUnitVector, MoveVector(dx: 0, dy: -1))
    }

    func testRegistrySetsRemainStableAfterExtraction() {
        XCTAssertEqual(MoveCard.directionalRayCards.count, 8)
        XCTAssertEqual(MoveCard.standardSet.count, 32)
        XCTAssertTrue(MoveCard.allCases.contains(.fixedWarp))
        XCTAssertTrue(MoveCard.allCases.contains(.superWarp))
    }

    func testCardEncyclopediaEntriesCoverAllMoveCardsByRepresentativeGroups() {
        let entries = MoveCard.encyclopediaEntries
        let includedCards = entries.flatMap(\.includedCards)

        XCTAssertEqual(entries.count, 9)
        XCTAssertEqual(Set(includedCards), Set(MoveCard.allCases))
        XCTAssertEqual(includedCards.count, MoveCard.allCases.count)
        XCTAssertTrue(entries.allSatisfy { !$0.displayName.isEmpty })
        XCTAssertTrue(entries.allSatisfy { !$0.category.isEmpty })
        XCTAssertTrue(entries.allSatisfy { !$0.description.isEmpty })
    }

    func testCardEncyclopediaCompressesDirectionVariants() {
        let entries = MoveCard.encyclopediaEntries

        XCTAssertEqual(entries.filter { $0.category == "キング" }.count, 1)
        XCTAssertEqual(entries.filter { $0.category == "ナイト" }.count, 1)
        XCTAssertEqual(entries.filter { $0.category == "直線2マス" }.count, 1)
        XCTAssertEqual(entries.filter { $0.category == "斜め2マス" }.count, 1)
        XCTAssertEqual(entries.filter { $0.category == "レイ" }.count, 1)

        XCTAssertEqual(entries.first { $0.displayName == "キング1マス" }?.includedCards.count, 8)
        XCTAssertEqual(entries.first { $0.displayName == "ナイト" }?.includedCards.count, 8)
        XCTAssertEqual(entries.first { $0.displayName == "レイ" }?.includedCards, MoveCard.directionalRayCards)
    }

    func testCardEncyclopediaKeepsDistinctSpecialCardsSeparate() {
        let entries = MoveCard.encyclopediaEntries

        XCTAssertTrue(entries.contains { $0.card == .superWarp && $0.includedCards == [.superWarp] })
        XCTAssertTrue(entries.contains { $0.card == .fixedWarp && $0.includedCards == [.fixedWarp] })
    }

    func testRepresentativeCardEncyclopediaMetadata() {
        XCTAssertEqual(MoveCard.kingUp.encyclopediaCategory, "キング")
        XCTAssertTrue(MoveCard.kingUp.encyclopediaDescription.contains("1 マス"))

        XCTAssertEqual(MoveCard.knightRightwardChoice.encyclopediaCategory, "選択ナイト")
        XCTAssertTrue(MoveCard.knightRightwardChoice.encyclopediaDescription.contains("選んで跳びます"))

        XCTAssertEqual(MoveCard.rayDown.encyclopediaCategory, "レイ")
        XCTAssertTrue(MoveCard.rayDown.encyclopediaDescription.contains("盤端や障害物"))

        XCTAssertEqual(MoveCard.superWarp.encyclopediaCategory, "ワープ")
        XCTAssertEqual(MoveCard.fixedWarp.encyclopediaCategory, "ワープ")
    }

    func testTileEncyclopediaEntriesCoverCoreTileKinds() {
        let entries = TileEncyclopediaEntry.allEntries
        let entryIDs = Set(entries.map(\.id))

        XCTAssertTrue(entries.allSatisfy { !$0.displayName.isEmpty })
        XCTAssertTrue(entries.allSatisfy { !$0.category.isEmpty })
        XCTAssertTrue(entries.allSatisfy { !$0.description.isEmpty })
        XCTAssertEqual(entries.first { $0.id == "normal" }?.previewKind, .normal)
        XCTAssertEqual(entries.first { $0.id == "spawn" }?.previewKind, .spawn)
        XCTAssertEqual(entries.first { $0.id == "target" }?.previewKind, .target)
        XCTAssertEqual(entries.first { $0.id == "nextTarget" }?.previewKind, .nextTarget)
        XCTAssertEqual(entries.first { $0.id == "multiVisit" }?.previewKind, .multiVisit)
        XCTAssertEqual(entries.first { $0.id == "toggle" }?.previewKind, .toggle)
        XCTAssertEqual(entries.first { $0.id == "impassable" }?.previewKind, .impassable)
        let targetEntries = entries.filter { $0.category == "目的地" }
        XCTAssertFalse(targetEntries.contains { $0.displayName.contains("NEXT") || $0.description.contains("紫") || $0.description.contains("オレンジ") })
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

        let specialPreviewIDs = Set(entries.compactMap { entry -> String? in
            if case .effect = entry.previewKind {
                return entry.id
            }
            return nil
        })
        XCTAssertEqual(specialPreviewIDs, [
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
        ])
    }
}
