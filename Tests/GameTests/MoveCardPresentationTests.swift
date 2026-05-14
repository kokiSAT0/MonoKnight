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
        XCTAssertTrue(entries.allSatisfy { !$0.category.isEmpty })
        XCTAssertTrue(entries.allSatisfy { !$0.displayName.isEmpty })
        XCTAssertTrue(entries.allSatisfy { !$0.description.isEmpty })
        XCTAssertTrue(entries.first { $0.card == .refillEmptySlots }?.description.contains("塔用移動カード全体") == true)
        XCTAssertEqual(entries.first { $0.card == .singleAnnihilationSpell }?.category, "呪文系カード")
        XCTAssertTrue(entries.first { $0.card == .singleAnnihilationSpell }?.description.contains("敵1体を消滅") == true)
        XCTAssertEqual(entries.first { $0.card == .annihilationSpell }?.category, "呪文系カード")
        XCTAssertTrue(entries.first { $0.card == .annihilationSpell }?.description.contains("敵をすべて消滅") == true)
        XCTAssertEqual(entries.first { $0.card == .barrierSpell }?.category, "呪文系カード")
        XCTAssertTrue(entries.first { $0.card == .barrierSpell }?.description.contains("HP ダメージを無効化") == true)
        XCTAssertEqual(entries.first { $0.card == .darknessSpell }?.category, "呪文系カード")
        XCTAssertTrue(entries.first { $0.card == .darknessSpell }?.description.contains("レーザー攻撃を封じ") == true)
        XCTAssertEqual(entries.first { $0.card == .railBreakSpell }?.category, "呪文系カード")
        XCTAssertTrue(entries.first { $0.card == .railBreakSpell }?.description.contains("レール移動を封じ") == true)
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
        XCTAssertEqual(entries.first { $0.id == "dungeonRelicPickup" }?.previewKind, .dungeonRelicPickup)
        XCTAssertEqual(entries.first { $0.id == "impassable" }?.previewKind, .impassable)
        XCTAssertEqual(entries.first { $0.id == "damageTrap" }?.previewKind, .damageTrap)
        XCTAssertEqual(entries.first { $0.id == "lavaTile" }?.previewKind, .lavaTile)
        XCTAssertEqual(entries.first { $0.id == "healingTile" }?.previewKind, .healingTile)
        XCTAssertEqual(entries.first { $0.id == "brittleFloor" }?.previewKind, .brittleFloor)
        XCTAssertEqual(entries.first { $0.id == "hiddenWeakFloor" }?.previewKind, .hiddenWeakFloor)
        XCTAssertEqual(entries.first { $0.id == "collapsedFloor" }?.previewKind, .collapsedFloor)
        XCTAssertEqual(entries.first { $0.id == "shackleTrap" }?.previewKind, .effect(.shackleTrap))
        XCTAssertEqual(entries.first { $0.id == "poisonTrap" }?.previewKind, .effect(.poisonTrap))
        XCTAssertEqual(entries.first { $0.id == "illusionTrap" }?.previewKind, .effect(.illusionTrap))
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
            "dungeonRelicPickup",
            "impassable",
            "damageTrap",
            "lavaTile",
            "healingTile",
            "brittleFloor",
            "hiddenWeakFloor",
            "collapsedFloor",
            "enemyDanger",
            "enemyWarning",
            "warp",
            "returnWarp",
            "blast",
            "shuffleHand",
            "preserveCard",
            "paralysisTrap",
            "shackleTrap",
            "illusionTrap",
            "poisonTrap",
            "swamp",
            "discardRandomHandTrap",
            "discardAllMoveCardsTrap",
            "discardAllSupportCardsTrap",
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
            "discardAllMoveCardsTrap",
            "discardAllSupportCardsTrap",
            "discardRandomHandTrap",
            "paralysisTrap",
            "illusionTrap",
            "poisonTrap",
            "preserveCard",
            "returnWarp",
            "shackleTrap",
            "shuffleHand",
            "swamp",
            "warp"
        ])
    }

    func testRelicCurseAndEventEncyclopediaEntriesCoverDefinitions() {
        let relicEntries = DungeonRelicEncyclopediaEntry.allEntries
        let curseEntries = DungeonCurseEncyclopediaEntry.allEntries
        let eventEntries = DungeonEventEncyclopediaEntry.allEntries

        XCTAssertEqual(relicEntries.map(\.relicID), DungeonRelicID.allCases)
        XCTAssertTrue(relicEntries.allSatisfy { !$0.displayName.isEmpty })
        XCTAssertTrue(relicEntries.allSatisfy { !$0.effectDescription.isEmpty })
        XCTAssertTrue(relicEntries.allSatisfy { !$0.rarity.displayName.isEmpty })
        XCTAssertTrue(relicEntries.allSatisfy { !$0.rarity.badgeText.isEmpty })
        XCTAssertEqual(
            DungeonRelicAcquisitionPresentation.Item.relic(DungeonRelicEntry(relicID: .silverNeedle)).primaryDescription,
            DungeonRelicID.silverNeedle.effectDescription
        )
        XCTAssertFalse(DungeonRelicID.silverNeedle.symbolName.isEmpty)
        XCTAssertEqual(DungeonRelicID.silverNeedle.symbolName, "pin.fill")
        XCTAssertNotEqual(DungeonRelicID.silverNeedle.symbolName, "needle.fill")
        let temporaryRelics: Set<DungeonRelicID> = [
            .crackedShield,
            .blackFeather,
            .silverNeedle,
            .moonMirror,
            .guardianIncense,
            .trapperGloves,
            .oldRope,
            .guardianAegis,
            .dullNeedle,
            .patchedRope,
            .purifyingCharm,
            .phoenixFeather
        ]
        let persistentRelics: Set<DungeonRelicID> = [
            .heavyCrown,
            .glowingHeart,
            .oldMap,
            .chippedHourglass,
            .travelerBoots,
            .starCup,
            .explorerBag,
            .victoryBanner,
            .windcutFeather,
            .whiteChalk,
            .spareTorch,
            .twinPouch,
            .gamblerCoin,
            .royalCrown,
            .immortalHeart,
            .stargazerHourglass,
            .woodenAmulet,
            .copperHourglass,
            .travelerRation,
            .smallLantern,
            .fieldMedkit,
            .scoutCompass,
            .quickSheath,
            .sageCodex,
            .trapSole,
            .emberCloak,
            .watcherMonocle,
            .railCharm,
            .chaserDecoy,
            .antidoteStone,
            .starUmbrella,
            .fallAnchor,
            .foldingMap,
            .phantomTicket,
            .campfireCoal,
            .merchantsScale
        ]
        XCTAssertEqual(Set(DungeonRelicID.allCases), temporaryRelics.union(persistentRelics))
        XCTAssertTrue(temporaryRelics.allSatisfy { $0.displayKind == .temporary })
        XCTAssertTrue(persistentRelics.allSatisfy { $0.displayKind == .persistent })
        XCTAssertEqual(DungeonRelicID.heavyCrown.rarity, .common)
        XCTAssertEqual(DungeonRelicID.heavyCrown.effectDescription, "移動報酬カードを新しく得る時、使用回数が+1される。")
        XCTAssertEqual(DungeonRelicID.twinPouch.effectDescription, "補助報酬カードを新しく得る時、使用回数が+1される。")
        XCTAssertEqual(DungeonRelicID.royalCrown.rarity, .legendary)
        XCTAssertEqual(DungeonRelicID.sageCodex.effectDescription, "新しく得る拾得カード、移動報酬カード、補助報酬カードの使用回数が+1される。")

        XCTAssertEqual(curseEntries.map(\.curseID), DungeonCurseID.allCases)
        XCTAssertTrue(curseEntries.allSatisfy { !$0.displayName.isEmpty })
        XCTAssertTrue(curseEntries.allSatisfy { !$0.effectDescription.isEmpty })
        XCTAssertTrue(curseEntries.allSatisfy { !$0.upsideDescription.isEmpty })
        XCTAssertTrue(curseEntries.allSatisfy { !$0.downsideDescription.isEmpty })
        XCTAssertTrue(curseEntries.allSatisfy { !$0.releaseDescription.isEmpty })
        XCTAssertTrue(curseEntries.allSatisfy { !$0.displayKind.displayName.isEmpty })
        XCTAssertTrue(curseEntries.allSatisfy { !$0.displayKind.badgeText.isEmpty })
        XCTAssertEqual(curseEntries.first { $0.curseID == .thornMark }?.displayKind, .temporary)
        XCTAssertEqual(curseEntries.first { $0.curseID == .bloodPact }?.displayKind, .temporary)
        XCTAssertEqual(curseEntries.first { $0.curseID == .rustyChain }?.displayKind, .persistent)
        XCTAssertEqual(curseEntries.first { $0.curseID == .redChalice }?.displayKind, .persistent)

        XCTAssertEqual(eventEntries.map(\.kind), DungeonEventEncyclopediaKind.allCases)
        XCTAssertTrue(eventEntries.allSatisfy { !$0.displayName.isEmpty })
        XCTAssertTrue(eventEntries.allSatisfy { !$0.description.isEmpty })
        XCTAssertEqual(DungeonRelicPickupKind.safe.encyclopediaEventKind, .safeChest)
        XCTAssertEqual(DungeonRelicPickupKind.suspiciousLight.encyclopediaEventKind, .suspiciousLightChest)
        XCTAssertEqual(DungeonRelicPickupKind.suspiciousDeep.encyclopediaEventKind, .suspiciousDeepChest)
    }

    func testEncyclopediaDiscoveryIDsAreStableAndParseUnknownsSafely() {
        let cardID = MoveCard.straightRight2.encyclopediaDiscoveryID
        let supportID = SupportCard.refillEmptySlots.encyclopediaDiscoveryID
        let enemyID = EnemyPresentationKind.chaser.encyclopediaDiscoveryID
        let tileID = TileEncyclopediaEntry.allEntries.first { $0.id == "warp" }!.encyclopediaDiscoveryID
        let relicID = DungeonRelicID.glowingHeart.encyclopediaDiscoveryID
        let curseID = DungeonCurseID.bloodPact.encyclopediaDiscoveryID
        let eventID = DungeonEventEncyclopediaKind.pandoraOutcome.encyclopediaDiscoveryID

        XCTAssertEqual(EncyclopediaDiscoveryID(rawValue: cardID.rawValue), cardID)
        XCTAssertEqual(EncyclopediaDiscoveryID(rawValue: supportID.rawValue), supportID)
        XCTAssertEqual(EncyclopediaDiscoveryID(rawValue: enemyID.rawValue), enemyID)
        XCTAssertEqual(EncyclopediaDiscoveryID(rawValue: tileID.rawValue), tileID)
        XCTAssertEqual(EncyclopediaDiscoveryID(rawValue: relicID.rawValue), relicID)
        XCTAssertEqual(EncyclopediaDiscoveryID(rawValue: curseID.rawValue), curseID)
        XCTAssertEqual(EncyclopediaDiscoveryID(rawValue: eventID.rawValue), eventID)
        XCTAssertNil(EncyclopediaDiscoveryID(rawValue: "futureCategory:futureItem"))
        XCTAssertNil(EncyclopediaDiscoveryID(rawValue: "card"))
    }

    func testHelpEncyclopediaTextAvoidsRemovedLegacyModeTerms() {
        let cardTexts = MoveCard.encyclopediaEntries.flatMap { [$0.displayName, $0.category, $0.description] }
        let supportTexts = SupportCard.encyclopediaEntries.flatMap { [$0.displayName, $0.category, $0.description] }
        let enemyTexts = EnemyEncyclopediaEntry.allEntries.flatMap { [$0.displayName, $0.behaviorSummary, $0.dangerSummary] }
        let tileTexts = TileEncyclopediaEntry.allEntries.flatMap { [$0.displayName, $0.category, $0.description] }
        let relicTexts = DungeonRelicEncyclopediaEntry.allEntries.flatMap { [$0.displayName, $0.effectDescription, $0.noteDescription ?? ""] }
        let curseTexts = DungeonCurseEncyclopediaEntry.allEntries.flatMap {
            [$0.displayName, $0.effectDescription, $0.upsideDescription, $0.downsideDescription, $0.releaseDescription]
        }
        let eventTexts = DungeonEventEncyclopediaEntry.allEntries.flatMap { [$0.displayName, $0.description] }
        let allTexts = cardTexts + supportTexts + enemyTexts + tileTexts + relicTexts + curseTexts + eventTexts
        let removedTerms = ["目的地", "全踏破", "フォーカス", "Game Center", "ランキング", "踏破対象"]

        for term in removedTerms {
            XCTAssertFalse(
                allTexts.contains { $0.contains(term) },
                "ヘルプ辞典に旧モード由来の文言 \(term) が残っています"
            )
        }
    }
}
