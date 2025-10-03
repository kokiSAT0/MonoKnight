import XCTest
@testable import Game

/// 日替わりチャレンジ関連のロジックを検証するテスト
final class DailyChallengeDefinitionTests: XCTestCase {
    /// 同じシードでランダム版が完全に再現されることを確認
    func testRandomModeDeterministicPerSeed() {
        // 固定シードを用意し、同じ入力から同一モードが生成されるかを確認する。
        let seed: UInt64 = 0x1234_5678_ABCD_EF01
        let modeA = DailyChallengeDefinition.makeRandomMode(baseSeed: seed)
        let modeB = DailyChallengeDefinition.makeRandomMode(baseSeed: seed)

        XCTAssertEqual(modeA, modeB, "同一シードでは同一設定になるべきです")
        XCTAssertEqual(modeA.deckSeed, modeB.deckSeed, "山札シードも一致している必要があります")
    }

    /// 固定版とランダム版で山札シードが衝突しないことを確認
    func testVariantDeckSeedsDoNotCollide() {
        let seed: UInt64 = 0xDEAD_BEEF_0000_0001
        let fixedMode = DailyChallengeDefinition.makeFixedMode(baseSeed: seed)
        let randomMode = DailyChallengeDefinition.makeRandomMode(baseSeed: seed)

        XCTAssertNotEqual(fixedMode.deckSeed, randomMode.deckSeed, "バリアント間で山札シードが衝突しないようにする")
    }

    /// 固定版がキャンペーン 5-8 と同じレギュレーションを持つことを確認
    func testFixedModeMatchesCampaignStage58() {
        let seed: UInt64 = 12345
        let fixedMode = DailyChallengeDefinition.makeFixedMode(baseSeed: seed)

        guard let stage = CampaignLibrary.shared.stage(with: CampaignStageID(chapter: 5, index: 8)) else {
            XCTFail("キャンペーン 5-8 が定義されている前提です")
            return
        }
        let campaignMode = stage.makeGameMode()

        XCTAssertEqual(fixedMode.regulationSnapshot, campaignMode.regulationSnapshot, "固定版は 5-8 の設定と一致している必要があります")
    }
}
