import XCTest
@testable import Game

final class MoveCardPresentationTests: XCTestCase {
    func testPresentationMetadataRemainsStableAfterExtraction() {
        XCTAssertEqual(MoveCard.kingUpRight.displayName, "右上1")
        XCTAssertEqual(MoveCard.knightRightwardChoice.displayName, "右桂 (選択)")

        XCTAssertEqual(MoveCard.kingUpRight.kind, .normal)
        XCTAssertEqual(MoveCard.knightLeftwardChoice.kind, .choice)
        XCTAssertEqual(MoveCard.rayDown.kind, .multiStep)
        XCTAssertEqual(MoveCard.rayDown.multiStepUnitVector, MoveVector(dx: 0, dy: -1))
    }

    func testRegistrySetsRemainStableAfterExtraction() {
        XCTAssertEqual(MoveCard.directionalRayCards.count, 8)
        XCTAssertEqual(MoveCard.standardSet.count, 28)
        XCTAssertFalse(MoveCard.allCases.map(\.displayName).contains("固定ワープ"))
        XCTAssertFalse(MoveCard.allCases.map(\.displayName).contains("全域ワープ"))
    }

    func testCardEncyclopediaEntriesCoverAllMoveCardsByRepresentativeGroups() {
        let entries = MoveCard.encyclopediaEntries
        let includedCards = entries.flatMap(\.includedCards)

        XCTAssertEqual(entries.count, 7)
        XCTAssertEqual(Set(includedCards), Set(MoveCard.allCases))
        XCTAssertEqual(includedCards.count, MoveCard.allCases.count)
        XCTAssertTrue(entries.allSatisfy { !$0.displayName.isEmpty })
        XCTAssertTrue(entries.allSatisfy { !$0.category.isEmpty })
        XCTAssertTrue(entries.allSatisfy { !$0.description.isEmpty })
    }

    func testSupportCardEncyclopediaEntriesCoverAllSupportCards() {
        let entries = SupportCard.encyclopediaEntries

        XCTAssertEqual(entries.map(\.card), SupportCard.allCases)
        XCTAssertTrue(entries.allSatisfy { $0.category == "補助カード" })
        XCTAssertTrue(entries.allSatisfy { !$0.displayName.isEmpty })
        XCTAssertTrue(entries.allSatisfy { !$0.description.isEmpty })
        XCTAssertTrue(entries.first { $0.card == .refillEmptySlots }?.description.contains("塔用移動カード全体") == true)
    }

    func testEnemyEncyclopediaEntriesCoverAllEnemyPresentationKinds() {
        let entries = EnemyEncyclopediaEntry.allEntries

        XCTAssertEqual(entries.map(\.kind), EnemyPresentationKind.allCases)
        XCTAssertEqual(entries.count, 6)
        XCTAssertTrue(entries.allSatisfy { !$0.displayName.isEmpty })
        XCTAssertTrue(entries.allSatisfy { !$0.behaviorSummary.isEmpty })
        XCTAssertTrue(entries.allSatisfy { !$0.dangerSummary.isEmpty })
        XCTAssertEqual(entries.first { $0.kind == .marker }?.displayName, "メテオ兵")
    }

    func testEnemyBehaviorPresentationKindsRemainStable() {
        XCTAssertEqual(EnemyBehavior.guardPost.presentationKind, .guardPost)
        XCTAssertEqual(EnemyBehavior.patrol(path: []).presentationKind, .patrol)
        XCTAssertEqual(EnemyBehavior.watcher(direction: MoveVector(dx: 1, dy: 0), range: 2).presentationKind, .watcher)
        XCTAssertEqual(
            EnemyBehavior.rotatingWatcher(
                initialDirection: MoveVector(dx: 0, dy: 1),
                rotationDirection: .clockwise,
                range: 2
            ).presentationKind,
            .rotatingWatcher
        )
        XCTAssertEqual(EnemyBehavior.chaser.presentationKind, .chaser)
        XCTAssertEqual(EnemyBehavior.marker(directions: [], range: 2).presentationKind, .marker)
    }

    func testCardEncyclopediaCompressesDirectionVariants() {
        let entries = MoveCard.encyclopediaEntries

        XCTAssertEqual(entries.filter { $0.category == "キング" }.count, 1)
        XCTAssertEqual(entries.filter { $0.category == "ナイト" }.count, 1)
        XCTAssertEqual(entries.filter { $0.category == "直線2マス" }.count, 1)
        XCTAssertEqual(entries.filter { $0.category == "斜め2マス" }.count, 1)
        XCTAssertEqual(entries.filter { $0.category == "レイ" }.count, 1)

        XCTAssertEqual(entries.first { $0.displayName == "斜めキング1マス" }?.includedCards.count, 4)
        XCTAssertEqual(entries.first { $0.displayName == "ナイト" }?.includedCards.count, 8)
        XCTAssertEqual(entries.first { $0.displayName == "レイ" }?.includedCards, MoveCard.directionalRayCards)
    }

    func testRepresentativeCardEncyclopediaMetadata() {
        XCTAssertEqual(MoveCard.kingUpRight.encyclopediaCategory, "キング")
        XCTAssertTrue(MoveCard.kingUpRight.encyclopediaDescription.contains("1 マス"))
        XCTAssertTrue(MoveCard.kingUpRight.encyclopediaDescription.contains("基本移動"))

        XCTAssertEqual(MoveCard.knightRightwardChoice.encyclopediaCategory, "選択ナイト")
        XCTAssertTrue(MoveCard.knightRightwardChoice.encyclopediaDescription.contains("選んで跳びます"))

        XCTAssertEqual(MoveCard.rayDown.encyclopediaCategory, "レイ")
        XCTAssertTrue(MoveCard.rayDown.encyclopediaDescription.contains("盤端や障害物"))
    }

    func testTileEncyclopediaEntriesCoverCoreTileKinds() {
        let entries = TileEncyclopediaEntry.allEntries
        let entryIDs = Set(entries.map(\.id))

        XCTAssertTrue(entries.allSatisfy { !$0.displayName.isEmpty })
        XCTAssertTrue(entries.allSatisfy { !$0.category.isEmpty })
        XCTAssertTrue(entries.allSatisfy { !$0.description.isEmpty })
        XCTAssertEqual(entries.first { $0.id == "normal" }?.previewKind, .normal)
        XCTAssertEqual(entries.first { $0.id == "spawn" }?.previewKind, .spawn)
        XCTAssertEqual(entries.first { $0.id == "dungeonExit" }?.previewKind, .dungeonExit)
        XCTAssertEqual(entries.first { $0.id == "lockedDungeonExit" }?.previewKind, .lockedDungeonExit)
        XCTAssertEqual(entries.first { $0.id == "dungeonKey" }?.previewKind, .dungeonKey)
        XCTAssertEqual(entries.first { $0.id == "cardPickup" }?.previewKind, .cardPickup)
        XCTAssertEqual(entries.first { $0.id == "impassable" }?.previewKind, .impassable)
        XCTAssertEqual(entries.first { $0.id == "damageTrap" }?.previewKind, .damageTrap)
        XCTAssertEqual(entries.first { $0.id == "healingTile" }?.previewKind, .healingTile)
        XCTAssertEqual(entries.first { $0.id == "brittleFloor" }?.previewKind, .brittleFloor)
        XCTAssertEqual(entries.first { $0.id == "collapsedFloor" }?.previewKind, .collapsedFloor)
        XCTAssertEqual(entries.first { $0.id == "enemyDanger" }?.previewKind, .enemyDanger)
        XCTAssertEqual(entries.first { $0.id == "enemyWarning" }?.previewKind, .enemyWarning)
        XCTAssertFalse(entries.contains { ["目的地", "踏破"].contains($0.category) })
        XCTAssertFalse(entryIDs.contains("target"))
        XCTAssertFalse(entryIDs.contains("nextTarget"))
        XCTAssertFalse(entryIDs.contains("multiVisit"))
        XCTAssertFalse(entryIDs.contains("toggle"))
        XCTAssertTrue(entryIDs.isSuperset(of: [
            "normal",
            "spawn",
            "dungeonExit",
            "lockedDungeonExit",
            "dungeonKey",
            "cardPickup",
            "impassable",
            "damageTrap",
            "healingTile",
            "brittleFloor",
            "collapsedFloor",
            "enemyDanger",
            "enemyWarning",
            "warp",
            "blast",
            "paralysisTrap",
            "discardRandomHandTrap",
            "discardAllHandsTrap",
        ]))

        let specialPreviewIDs = Set(entries.compactMap { entry -> String? in
            if case .effect = entry.previewKind {
                return entry.id
            }
            return nil
        })
        XCTAssertEqual(specialPreviewIDs, [
            "blast",
            "discardAllHandsTrap",
            "discardRandomHandTrap",
            "paralysisTrap",
            "warp"
        ])
    }

    func testHelpEncyclopediaTextAvoidsRemovedLegacyModeTerms() {
        let cardTexts = MoveCard.encyclopediaEntries.flatMap { [$0.displayName, $0.category, $0.description] }
        let supportTexts = SupportCard.encyclopediaEntries.flatMap { [$0.displayName, $0.category, $0.description] }
        let enemyTexts = EnemyEncyclopediaEntry.allEntries.flatMap { [$0.displayName, $0.behaviorSummary, $0.dangerSummary] }
        let tileTexts = TileEncyclopediaEntry.allEntries.flatMap { [$0.displayName, $0.category, $0.description] }
        let allTexts = cardTexts + supportTexts + enemyTexts + tileTexts
        let removedTerms = ["目的地", "全踏破", "フォーカス", "Game Center", "ランキング", "踏破対象"]

        for term in removedTerms {
            XCTAssertFalse(
                allTexts.contains { $0.contains(term) },
                "ヘルプ辞典に旧モード由来の文言 \(term) が残っています"
            )
        }
    }
}
