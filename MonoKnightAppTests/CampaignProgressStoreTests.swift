import XCTest
@testable import MonoKnightApp
import Game

/// 旧目的地制キャンペーン進捗は凍結中のため、保存互換とクラッシュ回避を中心に確認する。
@MainActor
final class CampaignProgressStoreTests: XCTestCase {
    private func makeIsolatedDefaults() throws -> UserDefaults {
        let suiteName = "campaign_progress_tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testLegacyCampaignProgressLoadsAndRegistersClear() throws {
        let defaults = try makeIsolatedDefaults()
        let store = CampaignProgressStore(userDefaults: defaults)
        let stage = try XCTUnwrap(CampaignLibrary.shared.allStages.first)
        let metrics = CampaignStageClearMetrics(
            moveCount: 16,
            penaltyCount: 0,
            elapsedSeconds: 90,
            totalMoveCount: 16,
            score: 205,
            hasRevisitedTile: false
        )

        XCTAssertTrue(store.isStageUnlocked(stage))

        let record = store.registerClear(for: stage, metrics: metrics)

        XCTAssertGreaterThan(record.progress.earnedStars, 0)
        XCTAssertNotNil(store.progress(for: stage.id))
    }

    func testLegacyCampaignProgressReplacesOldScoreVersionOnNextClear() throws {
        let defaults = try makeIsolatedDefaults()
        let stage = try XCTUnwrap(CampaignLibrary.shared.allStages.first)
        let legacyProgress = CampaignStageProgress(earnedStars: 1, bestScore: 20, bestScoreVersion: nil)
        let encoded = try JSONEncoder().encode([stage.id.storageKey: legacyProgress])
        defaults.set(encoded, forKey: StorageKey.UserDefaults.campaignProgress)

        let store = CampaignProgressStore(userDefaults: defaults)
        let metrics = CampaignStageClearMetrics(
            moveCount: 12,
            penaltyCount: 0,
            elapsedSeconds: 999,
            totalMoveCount: 12,
            score: 150,
            hasRevisitedTile: false
        )

        _ = store.registerClear(for: stage, metrics: metrics)

        XCTAssertEqual(store.progress(for: stage.id)?.bestScore, 150)
        XCTAssertEqual(store.progress(for: stage.id)?.bestScoreVersion, CampaignScoring.currentVersion)
    }
}
