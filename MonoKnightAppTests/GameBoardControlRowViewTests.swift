import XCTest
@testable import Game
@testable import MonoKnightApp

final class GameBoardControlRowViewTests: XCTestCase {
    func testDungeonHPAccessibilityIncludesCriticalStateAtOneHP() {
        XCTAssertTrue(GameBoardControlRowView.isCriticalDungeonHP(1))
        XCTAssertEqual(GameBoardControlRowView.dungeonHPAccessibilityValue(for: 1), "1、瀕死")
    }

    func testDungeonHPAccessibilityIncludesCriticalStateAtZeroHP() {
        XCTAssertTrue(GameBoardControlRowView.isCriticalDungeonHP(0))
        XCTAssertEqual(GameBoardControlRowView.dungeonHPAccessibilityValue(for: 0), "0、瀕死")
    }

    func testDungeonHPAccessibilityStaysNormalAboveOneHP() {
        XCTAssertFalse(GameBoardControlRowView.isCriticalDungeonHP(2))
        XCTAssertEqual(GameBoardControlRowView.dungeonHPAccessibilityValue(for: 2), "2")
    }

    func testDungeonTurnProgressUsesRemainingOverLimit() {
        XCTAssertEqual(GameBoardControlRowView.dungeonTurnProgress(remaining: 12, limit: 18), 12.0 / 18.0)
    }

    func testDungeonTurnProgressIsZeroWhenNoTurnsRemain() {
        XCTAssertEqual(GameBoardControlRowView.dungeonTurnProgress(remaining: 0, limit: 18), 0)
    }

    func testDungeonTurnProgressIsNilWithoutLimit() {
        XCTAssertNil(GameBoardControlRowView.dungeonTurnProgress(remaining: nil, limit: nil))
        XCTAssertEqual(GameBoardControlRowView.dungeonTurnValueText(remaining: nil, limit: nil), "∞")
        XCTAssertEqual(GameBoardControlRowView.dungeonTurnAccessibilityValue(remaining: nil, limit: nil), "制限なし")
    }

    func testDungeonTurnAccessibilityIncludesLimitAndRemaining() {
        XCTAssertEqual(GameBoardControlRowView.dungeonTurnValueText(remaining: 12, limit: 18), "12/18")
        XCTAssertEqual(GameBoardControlRowView.dungeonTurnAccessibilityValue(remaining: 12, limit: 18), "18手中12手残り")
    }

    func testCompactDungeonFloorTextKeepsOnlyFloorToken() {
        XCTAssertEqual(GameBoardControlRowView.compactDungeonFloorText("成長塔 12/50F"), "12/50F")
        XCTAssertEqual(GameBoardControlRowView.compactDungeonFloorText("試練塔 27F"), "27F")
    }

    func testDungeonTurnAccessibilityDescribesFatiguePips() {
        let fatigue = DungeonFatigueIndicatorState(filledCount: 2, totalCount: 3, isDamageStep: false)

        XCTAssertEqual(
            GameBoardControlRowView.dungeonTurnAccessibilityValue(remaining: 0, limit: 18, fatigue: fatigue),
            "残り手数0。疲労状態。3段階中2段階。次の段階でHPを1失います"
        )
    }

    func testDungeonTurnAccessibilityDescribesFatigueDamageStep() {
        let fatigue = DungeonFatigueIndicatorState(filledCount: 3, totalCount: 3, isDamageStep: true)

        XCTAssertEqual(
            GameBoardControlRowView.dungeonTurnAccessibilityValue(remaining: 0, limit: 18, fatigue: fatigue),
            "残り手数0。疲労ダメージが発生しました"
        )
    }

    func testDungeonTurnsBecomeCriticalAtQuarterRemaining() {
        XCTAssertFalse(GameBoardControlRowView.isCriticalDungeonTurns(remaining: 5, limit: 18))
        XCTAssertTrue(GameBoardControlRowView.isCriticalDungeonTurns(remaining: 4, limit: 18))
        XCTAssertTrue(GameBoardControlRowView.isCriticalDungeonTurns(remaining: 0, limit: 18))
    }

    func testDungeonStatusEffectsAreEmptyWhenNoStatusIsActive() {
        let effects = GameBoardControlRowView.dungeonStatusEffects(
            enemyFreezeTurnsRemaining: 0,
            damageBarrierTurnsRemaining: 0,
            isShackled: false,
            isIlluded: false,
            poisonDamageTicksRemaining: 0,
            poisonActionsUntilNextDamage: 0
        )

        XCTAssertTrue(effects.isEmpty)
    }

    func testDungeonStatusEffectsUseCountsForFreezeBarrierAndPoisonBadges() {
        let effects = GameBoardControlRowView.dungeonStatusEffects(
            enemyFreezeTurnsRemaining: 3,
            damageBarrierTurnsRemaining: 2,
            isShackled: false,
            isIlluded: false,
            poisonDamageTicksRemaining: 4,
            poisonActionsUntilNextDamage: 1
        )

        XCTAssertEqual(effects.map(\.kind), [.enemyFreeze, .damageBarrier, .poison])
        XCTAssertEqual(effects.map(\.badgeText), ["3", "2", "1"])
        XCTAssertEqual(effects[0].accessibilityValue, "残り3ターン")
        XCTAssertEqual(effects[1].accessibilityValue, "残り2ターン、HPダメージを無効化")
        XCTAssertEqual(effects[2].accessibilityValue, "次の毒ダメージまで1行動、残り4回")
    }

    func testDungeonStatusEffectsDescribeShackleAndIllusion() {
        let effects = GameBoardControlRowView.dungeonStatusEffects(
            enemyFreezeTurnsRemaining: 0,
            damageBarrierTurnsRemaining: 0,
            isShackled: true,
            isIlluded: true,
            poisonDamageTicksRemaining: 0,
            poisonActionsUntilNextDamage: 0
        )

        XCTAssertEqual(effects.map(\.kind), [.shackle, .illusion])
        XCTAssertEqual(effects.map(\.badgeText), ["2", "?"])
        XCTAssertEqual(effects[0].accessibilityLabel, "足枷状態")
        XCTAssertTrue(effects[0].accessibilityValue.contains("手数が2"))
        XCTAssertEqual(effects[1].accessibilityLabel, "幻惑状態")
        XCTAssertTrue(effects[1].accessibilityValue.contains("移動カードの正体が分からず"))
    }

    func testPoisonStatusEffectDetailIncludesNextCountdownAndRemainingTicks() {
        let effect = DungeonStatusEffectPresentation.poison(actionsUntilNextDamage: 2, ticksRemaining: 3)

        XCTAssertEqual(effect.badgeText, "2")
        XCTAssertEqual(effect.currentValueText, "次の毒ダメージまで 2 行動、残り 3 回")
        XCTAssertTrue(effect.detailText.contains("一定間隔でHPを1失います"))
        XCTAssertEqual(effect.accessibilityIdentifier, "dungeon_status_effect_poison")
    }
}
