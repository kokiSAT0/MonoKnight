#if canImport(UIKit)
import XCTest
import SwiftUI
import Game
@testable import MonoKnightApp

/// MoveCardIllustrationView のアクセシビリティ挙動を検証するテスト
/// - Note: VoiceOver の読み上げ内容が複数候補カードでも自然な文面になるか確認する
@MainActor
final class MoveCardIllustrationViewAccessibilityTests: XCTestCase {

    /// 複数候補カードでは盤面で方向を選ぶ旨が案内されることを確認する
    func testHandModeAccessibilityHintMentionsDirectionChoiceWhenMultipleCandidatesExist() {
        let overrideVectors = [
            MoveVector(dx: 1, dy: 0),
            MoveVector(dx: -1, dy: 0),
            MoveVector(dx: 0, dy: 1)
        ]
        MoveCard.setTestMovementVectors(overrideVectors, for: .kingRight)
        defer { MoveCard.setTestMovementVectors(nil, for: .kingRight) }

        let view = MoveCardIllustrationView(card: .kingRight, mode: .hand)
        let controller = UIHostingController(rootView: view)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 120, height: 180)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        let hint = controller.view.accessibilityHint ?? ""
        XCTAssertTrue(hint.contains("盤面で移動方向を決めてください"), "複数候補時に方向選択を促す文言が含まれていません")
        XCTAssertTrue(hint.contains("候補は 3 方向"), "候補数の案内が含まれていません: \(hint)")
    }

    /// 複数候補カードではラベル末尾に補足が追加されることを確認する
    func testHandModeAccessibilityLabelAddsMultipleDirectionSuffix() {
        let overrideVectors = [
            MoveVector(dx: 2, dy: 0),
            MoveVector(dx: -2, dy: 0)
        ]
        MoveCard.setTestMovementVectors(overrideVectors, for: .straightRight2)
        defer { MoveCard.setTestMovementVectors(nil, for: .straightRight2) }

        let view = MoveCardIllustrationView(card: .straightRight2, mode: .hand)
        let controller = UIHostingController(rootView: view)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 120, height: 180)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        let label = controller.view.accessibilityLabel ?? ""
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
            XCTAssertEqual(choice.usesBadgeText, "3回使える")
            XCTAssertTrue(choice.accessibilityLabel.contains(choice.title), "読み上げにカード名が含まれていません")
            XCTAssertTrue(choice.accessibilityLabel.contains("手札に追加"), "読み上げにカードを手札へ追加する操作が含まれていません")
            XCTAssertTrue(choice.accessibilityLabel.contains("3回使える"), "読み上げに報酬カードの使用回数が含まれていません")
            XCTAssertTrue(choice.accessibilityLabel.contains("選ぶと次の階へ進みます"), "読み上げに選択後の遷移が含まれていません")
            XCTAssertTrue(
                choice.accessibilityLabel.contains(choice.card.encyclopediaDescription),
                "画面上の説明文を省略しても、読み上げにはカード説明を残します"
            )
        }
    }

    func testDungeonPickupCarryoverChoicePresentationExplainsHandAddition() {
        let choice = DungeonRewardCardChoicePresentation(
            card: .straightUp2,
            rewardUses: 4,
            sourceText: "このフロアで拾ったカード",
            accessibilityIdentifierPrefix: "dungeon_pickup_carryover_card",
            accessibilityRoleText: "手札に追加するカード"
        )

        XCTAssertEqual(choice.actionText, "手札に追加")
        XCTAssertEqual(choice.sourceText, "このフロアで拾ったカード")
        XCTAssertEqual(choice.usesBadgeText, "4回使える")
        XCTAssertEqual(choice.accessibilityIdentifier, "dungeon_pickup_carryover_card_上2")
        XCTAssertTrue(choice.accessibilityLabel.contains("このフロアで拾ったカード"))
        XCTAssertTrue(choice.accessibilityLabel.contains("手札に追加"))
        XCTAssertFalse(choice.accessibilityLabel.contains("報酬カード化"))
        XCTAssertFalse(choice.accessibilityLabel.contains("持ち越し"))
        XCTAssertTrue(choice.accessibilityLabel.contains("4回使える"))
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
        XCTAssertEqual(choice.upgradeAccessibilityIdentifier, "dungeon_reward_upgrade_右2")
        XCTAssertEqual(choice.removeAccessibilityIdentifier, "dungeon_reward_remove_右2")
        XCTAssertTrue(choice.upgradeAccessibilityLabel.contains("右2"))
        XCTAssertTrue(choice.upgradeAccessibilityLabel.contains("手札"))
        XCTAssertTrue(choice.upgradeAccessibilityLabel.contains("現在2回"))
        XCTAssertTrue(choice.upgradeAccessibilityLabel.contains("使用回数+1"))
        XCTAssertTrue(choice.upgradeAccessibilityLabel.contains("選ぶと次の階へ進みます"))
        XCTAssertTrue(choice.removeAccessibilityLabel.contains("手札から外す"))
        XCTAssertTrue(choice.removeAccessibilityLabel.contains("報酬は消費しません"))
        XCTAssertFalse(choice.removeAccessibilityLabel.contains("選ぶと次の階へ進みます"))
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
        XCTAssertTrue(policy.showsRetryButton)
        XCTAssertFalse(policy.showsLeaderboardButton)
        XCTAssertTrue(policy.showsShareLink)
    }
}
#endif
