import XCTest
@testable import MonoKnightApp
import Game

/// キャンペーン進捗ストアの基本的な挙動を検証するテスト
final class CampaignProgressStoreTests: XCTestCase {
    /// テスト用に分離された UserDefaults を生成
    private func makeIsolatedDefaults() throws -> UserDefaults {
        let suiteName = "campaign_progress_tests." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("UserDefaults を生成できませんでした")
            throw NSError(domain: "CampaignProgressStoreTests", code: -1)
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    /// 1-1 ステージの解放条件が初期状態で満たされていることを確認
    func testStageInitiallyUnlocked() throws {
        let defaults = try makeIsolatedDefaults()
        let store = CampaignProgressStore(userDefaults: defaults)
        let library = CampaignLibrary.shared
        let stageID = CampaignStageID(chapter: 1, index: 1)
        guard let stage = library.stage(with: stageID) else {
            XCTFail("ステージ定義が見つかりません")
            return
        }

        XCTAssertTrue(store.isStageUnlocked(stage), "初期ステージは最初から解放されている想定です")
    }

    /// クリア登録によってスター数やベストスコアが更新されることを検証
    func testRegisterClearUpdatesProgress() throws {
        let defaults = try makeIsolatedDefaults()
        let store = CampaignProgressStore(userDefaults: defaults)
        let library = CampaignLibrary.shared
        let stageID = CampaignStageID(chapter: 1, index: 1)
        guard let stage = library.stage(with: stageID) else {
            XCTFail("ステージ定義が見つかりません")
            return
        }

        let metrics = CampaignStageClearMetrics(
            moveCount: 16,
            penaltyCount: 0,
            elapsedSeconds: 90,
            totalMoveCount: 16,
            score: 250,
            hasRevisitedTile: false
        )

        let record = store.registerClear(for: stage, metrics: metrics)
        XCTAssertEqual(record.progress.earnedStars, 3, "1-1 は指定条件を満たすと 3 スター獲得できる想定です")
        XCTAssertEqual(store.totalStars, 3)

        // より悪いスコアで再登録してもベスト値は維持されることを確認
        let worseMetrics = CampaignStageClearMetrics(
            moveCount: 20,
            penaltyCount: 2,
            elapsedSeconds: 140,
            totalMoveCount: 22,
            score: 360,
            hasRevisitedTile: true
        )
        _ = store.registerClear(for: stage, metrics: worseMetrics)
        let stored = store.progress(for: stageID)
        XCTAssertEqual(stored?.bestScore, metrics.score, "ベストスコアはより良い値を保持する必要があります")
        XCTAssertEqual(stored?.earnedStars, 3, "一度獲得したスターは維持される想定です")
    }
}
