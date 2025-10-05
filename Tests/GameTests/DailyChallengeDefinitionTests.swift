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

    /// ランダム版で採用されるペナルティ範囲が新基準へ沿っているかを確認
    func testRandomModePenaltyRangesFollowBaseline() {
        // 観測値を収集し、2 値を含むかどうかを後段で確認する。
        var observedRedrawCosts: Set<Int> = []
        var observedDiscardCosts: Set<Int> = []
        var observedRevisitCosts: Set<Int> = []

        // 連続シードを複数評価し、乱数の偏りで判定がブレないようにする。
        for offset in 0..<128 {
            let seed = 0xCAFEBABE_0000_0000 &+ UInt64(offset)
            let mode = DailyChallengeDefinition.makeRandomMode(baseSeed: seed)
            let penalties = mode.regulationSnapshot.penalties

            XCTAssertEqual(penalties.deadlockPenaltyCost, 3, "deadlock ペナルティは常に +3 手へ固定される想定です")
            XCTAssertTrue([2, 3].contains(penalties.manualRedrawPenaltyCost), "manual redraw は +2〜+3 手の範囲に収まる必要があります")
            XCTAssertTrue([1, 2].contains(penalties.manualDiscardPenaltyCost), "manual discard は +1〜+2 手の範囲に収まる必要があります")
            XCTAssertTrue([0, 1].contains(penalties.revisitPenaltyCost), "revisit は 0〜+1 手の範囲に収まる必要があります")

            observedRedrawCosts.insert(penalties.manualRedrawPenaltyCost)
            observedDiscardCosts.insert(penalties.manualDiscardPenaltyCost)
            observedRevisitCosts.insert(penalties.revisitPenaltyCost)
        }

        // manual redraw は最低でも +2 手を選択肢として保持する仕様なので、実際に出現することを確認する。
        XCTAssertTrue(observedRedrawCosts.contains(2), "manual redraw で +2 手が選ばれるケースを生成できていません")
        // manual discard / revisit も中心値が出現するかを確認する。
        XCTAssertTrue(observedDiscardCosts.contains(1), "manual discard で +1 手が出現することを保証する必要があります")
        XCTAssertTrue(observedRevisitCosts.contains(0), "revisit で 0 手運用が出現することを保証する必要があります")
    }
}
