#if canImport(UIKit)
import XCTest
import SwiftUI
import Game
@testable import MonoKnightApp

/// MoveCardIllustrationView のアクセシビリティ挙動を検証するテスト
/// - Note: VoiceOver の読み上げ内容が複数候補カードでも自然な文面になるか確認する
@MainActor
final class MoveCardIllustrationViewAccessibilityTests: XCTestCase {
    private var dungeonResultPresentation: ResultSummaryPresentation {
        ResultSummaryPresentation(
            moveCount: 6,
            penaltyCount: 0,
            usesDungeonExit: true,
            isFailed: false,
            failureReason: nil,
            dungeonHP: 2,
            remainingDungeonTurns: 3,
            dungeonRunFloorText: "基礎塔 1/6F",
            rogueTowerRecordText: nil,
            dungeonRunTotalMoveCount: 6,
            dungeonRewardMoveCards: [],
            dungeonInventoryEntries: [],
            dungeonGrowthAward: nil,
            hasNextDungeonFloor: true,
            elapsedSeconds: 20
        )
    }

    /// 複数候補カードでは盤面で方向を選ぶ旨が案内されることを確認する
    func testHandModeAccessibilityHintMentionsDirectionChoiceWhenMultipleCandidatesExist() {
        let candidateCount = MoveCard.kingRightDiagonalChoice.movementVectors.count

        let hint = MoveCardIllustrationView.Mode.hand.accessibilityHint(forCandidateCount: candidateCount)
        XCTAssertTrue(hint.contains("盤面で移動方向を決めてください"), "複数候補時に方向選択を促す文言が含まれていません")
        XCTAssertTrue(hint.contains("候補は 2 方向"), "候補数の案内が含まれていません: \(hint)")
    }

    /// 複数候補カードではラベル末尾に補足が追加されることを確認する
    func testHandModeAccessibilityLabelAddsMultipleDirectionSuffix() {
        let candidateCount = MoveCard.kingRightDiagonalChoice.movementVectors.count

        let label = MoveCard.kingRightDiagonalChoice.displayName
            + MoveCardIllustrationView.Mode.hand.accessibilitySuffix(forCandidateCount: candidateCount)
        XCTAssertTrue(label.contains("複数方向の候補あり"), "複数候補を示す補足がラベルに含まれていません: \(label)")
    }

    /// 報酬カード選択 UI が表示を軽くしても、読み上げに必要な情報を保持することを確認する
    func testDungeonRewardCardChoicePresentationKeepsCardIdentityAndUses() {
        let rewardCards: [MoveCard] = [.straightRight2, .straightUp2, .knightRightwardChoice]
        let choices = rewardCards.map { DungeonRewardCardChoicePresentation(card: $0) }

        XCTAssertEqual(choices.count, 3, "報酬候補は3件を横並びカードとして表示する想定です")
        XCTAssertEqual(choices.map(\.accessibilityIdentifier), [
            "dungeon_reward_card_右2",
            "dungeon_reward_card_上2",
            "dungeon_reward_card_右桂 (選択)"
        ])

        for choice in choices {
            XCTAssertEqual(choice.actionText, "手札に追加")
            XCTAssertEqual(choice.usesBadgeText, "2回")
            XCTAssertTrue(choice.accessibilityLabel.contains(choice.title), "読み上げにカード名が含まれていません")
            XCTAssertTrue(choice.accessibilityLabel.contains("手札に追加"), "読み上げにカードを手札へ追加する操作が含まれていません")
            XCTAssertTrue(choice.accessibilityLabel.contains("2回"), "読み上げに報酬カードの使用回数が含まれていません")
            XCTAssertTrue(choice.accessibilityLabel.contains("選ぶと次の階へ進みます"), "読み上げに選択後の遷移が含まれていません")
            XCTAssertTrue(
                choice.accessibilityLabel.contains(choice.card.encyclopediaDescription),
                "画面上の説明文を省略しても、読み上げにはカード説明を残します"
            )
            XCTAssertTrue(choice.accessibilityHint.contains("効果を確認"))
        }
    }

    func testDungeonRewardCardChoicePresentationExplainsDisabledFullHand() {
        let choice = DungeonRewardCardChoicePresentation(
            card: .straightRight2,
            isEnabled: false
        )

        XCTAssertFalse(choice.isEnabled)
        XCTAssertTrue(choice.accessibilityLabel.contains("手札がいっぱいです"))
        XCTAssertTrue(choice.accessibilityLabel.contains("手札から外すか"))
        XCTAssertTrue(choice.accessibilityLabel.contains("報酬を取らずに進めます"))
        XCTAssertTrue(choice.accessibilityHint.contains("報酬を取らずに進める"))
        XCTAssertTrue(choice.accessibilityHint.contains("効果を確認"))
        XCTAssertFalse(choice.accessibilityLabel.contains("選ぶと次の階へ進みます"))
    }

    func testDungeonRewardCardChoicePresentationDoesNotExposeTacticalHint() {
        let choice = DungeonRewardCardChoicePresentation(
            offer: .playable(.support(.darknessSpell)),
            rewardUses: 1,
            accessibilityIdentifierPrefix: "dungeon_reward_support_card",
            accessibilityRoleText: "手札に追加する補助カード"
        )

        XCTAssertFalse(choice.accessibilityLabel.contains("暗闇に強い"))
        XCTAssertFalse(choice.detailPresentation.secondaryDescriptions.contains("暗闇に強い"))
        XCTAssertFalse(choice.accessibilityLabel.contains("おすすめ"))
        XCTAssertFalse(choice.accessibilityLabel.contains("正解"))
        XCTAssertFalse(choice.accessibilityLabel.contains("最適"))
    }

    func testDungeonRewardRelicChoicePresentationOpensDetailBeforeAdvance() {
        let choice = DungeonRewardCardChoicePresentation(
            offer: .relic(.silverNeedle),
            rewardUses: 0,
            accessibilityIdentifierPrefix: "dungeon_reward_relic",
            accessibilityRoleText: "獲得する遺物"
        )

        XCTAssertEqual(choice.usesBadgeText, "コモン")
        XCTAssertEqual(DungeonRelicID.silverNeedle.symbolName, "pin.fill")
        XCTAssertEqual(choice.accessibilityIdentifier, "dungeon_reward_relic_銀の針")
        XCTAssertTrue(choice.accessibilityHint.contains("詳細を確認します"))
        XCTAssertTrue(choice.accessibilityHint.contains("効果を確認"))
        XCTAssertFalse(choice.accessibilityLabel.contains("一時レリック"))
        XCTAssertFalse(choice.accessibilityLabel.contains("永続レリック"))
        XCTAssertTrue(choice.accessibilityLabel.contains("コモン"))
        XCTAssertTrue(choice.accessibilityLabel.contains(DungeonRelicID.silverNeedle.effectDescription))
    }

    func testDungeonRewardDetailPresentationUsesExistingDescriptions() {
        let moveChoice = DungeonRewardCardChoicePresentation(card: .straightRight2)
        let moveDetail = moveChoice.detailPresentation

        XCTAssertEqual(moveDetail.title, MoveCard.straightRight2.displayName)
        XCTAssertEqual(moveDetail.badgeText, "2回")
        XCTAssertEqual(moveDetail.primaryDescription, MoveCard.straightRight2.encyclopediaDescription)
        XCTAssertEqual(moveDetail.visualTone, .standard)
        XCTAssertTrue(moveDetail.secondaryDescriptions.contains("手札に追加するカード"))

        let supportChoice = DungeonRewardCardChoicePresentation(
            offer: .playable(.support(.barrierSpell)),
            rewardUses: 1,
            accessibilityIdentifierPrefix: "dungeon_reward_support_card",
            accessibilityRoleText: "手札に追加する補助カード"
        )
        let supportDetail = supportChoice.detailPresentation

        XCTAssertEqual(supportDetail.title, SupportCard.barrierSpell.displayName)
        XCTAssertEqual(supportDetail.badgeText, "1回")
        XCTAssertEqual(supportDetail.primaryDescription, SupportCard.barrierSpell.encyclopediaDescription)
        XCTAssertEqual(supportDetail.visualTone, .standard)
        XCTAssertTrue(supportDetail.secondaryDescriptions.contains(SupportCard.barrierSpell.encyclopediaCategory))

        let relicChoice = DungeonRewardCardChoicePresentation(
            offer: .relic(.fieldMedkit),
            rewardUses: 0,
            accessibilityIdentifierPrefix: "dungeon_reward_relic",
            accessibilityRoleText: "獲得する遺物"
        )
        let relicDetail = relicChoice.detailPresentation

        XCTAssertEqual(relicDetail.title, DungeonRelicID.fieldMedkit.displayName)
        XCTAssertEqual(relicDetail.badgeText, DungeonRelicID.fieldMedkit.rarity.displayName)
        XCTAssertEqual(relicDetail.primaryDescription, DungeonRelicID.fieldMedkit.effectDescription)
        XCTAssertEqual(relicDetail.visualTone, .rare)
    }

    func testDungeonRewardRelicChoicePresentationExposesRarityVisualTone() {
        let common = DungeonRewardCardChoicePresentation(offer: .relic(.silverNeedle), rewardUses: 0)
        let rare = DungeonRewardCardChoicePresentation(offer: .relic(.fieldMedkit), rewardUses: 0)
        let legendary = DungeonRewardCardChoicePresentation(offer: .relic(.royalCrown), rewardUses: 0)

        XCTAssertEqual(common.usesBadgeText, DungeonRelicRarity.common.displayName)
        XCTAssertEqual(common.visualTone, .common)
        XCTAssertEqual(common.detailPresentation.visualTone, .common)

        XCTAssertEqual(rare.usesBadgeText, DungeonRelicRarity.rare.displayName)
        XCTAssertEqual(rare.visualTone, .rare)
        XCTAssertEqual(rare.detailPresentation.visualTone, .rare)

        XCTAssertEqual(legendary.usesBadgeText, DungeonRelicRarity.legendary.displayName)
        XCTAssertEqual(legendary.visualTone, .legendary)
        XCTAssertEqual(legendary.detailPresentation.visualTone, .legendary)
    }

    func testDungeonPickupCarryoverChoicePresentationExplainsHandAddition() {
        let choice = DungeonRewardCardChoicePresentation(
            card: .straightUp2,
            rewardUses: 1,
            sourceText: "このフロアで拾ったカード",
            accessibilityIdentifierPrefix: "dungeon_pickup_carryover_card",
            accessibilityRoleText: "手札に追加するカード"
        )

        XCTAssertEqual(choice.actionText, "手札に追加")
        XCTAssertEqual(choice.sourceText, "このフロアで拾ったカード")
        XCTAssertEqual(choice.usesBadgeText, "1回")
        XCTAssertEqual(choice.accessibilityIdentifier, "dungeon_pickup_carryover_card_上2")
        XCTAssertTrue(choice.accessibilityLabel.contains("このフロアで拾ったカード"))
        XCTAssertTrue(choice.accessibilityLabel.contains("手札に追加"))
        XCTAssertFalse(choice.accessibilityLabel.contains("報酬カード化"))
        XCTAssertFalse(choice.accessibilityLabel.contains("持ち越し"))
        XCTAssertTrue(choice.accessibilityLabel.contains("1回"))
        XCTAssertTrue(choice.accessibilityLabel.contains("選ぶと次の階へ進みます"))
        XCTAssertTrue(
            choice.accessibilityLabel.contains(choice.card.encyclopediaDescription),
            "床カード由来でも読み上げにはカード説明を残します"
        )
    }

    func testDungeonCarriedRewardChoicePresentationExplainsCardActions() {
        let choice = DungeonCarriedRewardChoicePresentation(
            entry: DungeonInventoryEntry(card: .straightRight2, rewardUses: 2)
        )

        XCTAssertEqual(choice.title, "右2")
        XCTAssertEqual(choice.usesBadgeText, "現在2回")
        XCTAssertTrue(choice.isAdjustable)
        XCTAssertEqual(choice.removeAccessibilityIdentifier, "dungeon_reward_remove_右2")
        XCTAssertTrue(choice.removeAccessibilityLabel.contains("右2"))
        XCTAssertTrue(choice.removeAccessibilityLabel.contains("手札"))
        XCTAssertTrue(choice.removeAccessibilityLabel.contains("現在2回"))
        XCTAssertTrue(choice.removeAccessibilityLabel.contains("手札から外す"))
        XCTAssertTrue(choice.removeAccessibilityLabel.contains("報酬は消費しません"))
        XCTAssertFalse(choice.removeAccessibilityLabel.contains("選ぶと次の階へ進みます"))
    }

    func testDungeonCarriedRewardChoicePresentationTreatsPickupUsesAsHandUses() {
        let choice = DungeonCarriedRewardChoicePresentation(
            entry: DungeonInventoryEntry(card: .straightUp2, pickupUses: 1)
        )

        XCTAssertEqual(choice.title, "上2")
        XCTAssertEqual(choice.usesBadgeText, "現在1回")
        XCTAssertTrue(choice.isAdjustable)
        XCTAssertTrue(choice.removeAccessibilityLabel.contains("現在1回"))
    }

    func testDungeonCarriedRewardChoicePresentationCountsRewardAndPickupUses() {
        let choice = DungeonCarriedRewardChoicePresentation(
            entry: DungeonInventoryEntry(card: .straightRight2, rewardUses: 2, pickupUses: 1)
        )

        XCTAssertEqual(choice.usesBadgeText, "現在3回")
        XCTAssertTrue(choice.isAdjustable)
        XCTAssertTrue(choice.removeAccessibilityLabel.contains("現在3回"))
    }

    func testResultActionSectionKeepsPickupOnlyInventoryEntriesVisible() {
        let pickupOnly = DungeonInventoryEntry(card: .straightUp2, pickupUses: 1)
        let section = ResultActionSection(
            presentation: dungeonResultPresentation,
            modeIdentifier: .dungeonFloor,
            modeDisplayName: "塔ダンジョン",
            nextDungeonFloorTitle: "2F",
            retryButtonTitle: "1Fから再挑戦",
            dungeonRewardInventoryEntries: [pickupOnly],
            showsLeaderboardButton: false,
            isGameCenterAuthenticated: false,
            onRequestGameCenterSignIn: nil,
            onSelectNextDungeonFloor: {},
            onRetry: {},
            onReturnToTitle: nil,
            gameCenterService: GameCenterService.shared,
            hapticsEnabled: false
        )

        XCTAssertEqual(section.dungeonRewardInventoryEntries, [pickupOnly])
    }

    func testResultActionSectionShowsSkipRewardActionWhenChoicesExist() {
        let section = ResultActionSection(
            presentation: dungeonResultPresentation,
            modeIdentifier: .dungeonFloor,
            modeDisplayName: "塔ダンジョン",
            nextDungeonFloorTitle: "2F",
            retryButtonTitle: "1Fから再挑戦",
            dungeonRewardMoveCards: [.straightRight2],
            showsLeaderboardButton: false,
            isGameCenterAuthenticated: false,
            onRequestGameCenterSignIn: nil,
            onSelectNextDungeonFloor: {},
            onSelectDungeonRewardMoveCard: { _ in },
            onRetry: {},
            onReturnToTitle: nil,
            gameCenterService: GameCenterService.shared,
            hapticsEnabled: false
        )

        XCTAssertTrue(section.showsSkipDungeonRewardAction)
    }

    func testResultActionSectionUsesThreeColumnsForHandInventory() {
        XCTAssertEqual(ResultActionSection.resultHandGridColumnCount, 3)
        XCTAssertEqual(ResultActionSection.fixedThreeColumnGridItems(spacing: 8).count, 3)
    }

    func testResultActionPolicyHidesPersistentActionsDuringIntermediateDungeonClear() {
        let policy = ResultActionDisplayPolicy(
            usesDungeonExit: true,
            isFailed: false,
            hasNextDungeonFloor: true,
            allowsLeaderboardButton: true,
            hasReturnToTitle: true
        )

        XCTAssertTrue(policy.isIntermediateDungeonClear)
        XCTAssertFalse(policy.showsReturnToTitleButton)
        XCTAssertFalse(policy.showsInspectFailedBoardButton)
        XCTAssertFalse(policy.showsRetryButton)
        XCTAssertFalse(policy.showsLeaderboardButton)
        XCTAssertFalse(policy.showsShareLink)
    }

    func testResultActionPolicyShowsPersistentActionsForFinalDungeonClear() {
        let policy = ResultActionDisplayPolicy(
            usesDungeonExit: true,
            isFailed: false,
            hasNextDungeonFloor: false,
            allowsLeaderboardButton: true,
            hasReturnToTitle: true
        )

        XCTAssertFalse(policy.isIntermediateDungeonClear)
        XCTAssertTrue(policy.showsReturnToTitleButton)
        XCTAssertFalse(policy.showsInspectFailedBoardButton)
        XCTAssertTrue(policy.showsRetryButton)
        XCTAssertTrue(policy.showsLeaderboardButton)
        XCTAssertTrue(policy.showsShareLink)
    }

    func testResultActionPolicyShowsPersistentActionsForDungeonFailure() {
        let policy = ResultActionDisplayPolicy(
            usesDungeonExit: true,
            isFailed: true,
            hasNextDungeonFloor: true,
            allowsLeaderboardButton: false,
            hasReturnToTitle: true
        )

        XCTAssertFalse(policy.isIntermediateDungeonClear)
        XCTAssertTrue(policy.showsReturnToTitleButton)
        XCTAssertTrue(policy.showsInspectFailedBoardButton)
        XCTAssertTrue(policy.showsRetryButton)
        XCTAssertFalse(policy.showsLeaderboardButton)
        XCTAssertTrue(policy.showsShareLink)
    }
}
#endif
