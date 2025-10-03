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

    /// デバッグ用パスコードを有効化すると全ステージの解放条件が満たされることを確認
    @MainActor
    func testDebugUnlockOverridesRequirement() throws {
        let defaults = try makeIsolatedDefaults()
        let store = CampaignProgressStore(userDefaults: defaults)
        let library = CampaignLibrary.shared

        let lockedStageID = CampaignStageID(chapter: 1, index: 2)
        guard let lockedStage = library.stage(with: lockedStageID) else {
            XCTFail("ステージ定義が見つかりません")
            return
        }

        XCTAssertFalse(store.isStageUnlocked(lockedStage), "前提条件として 1-2 は初期状態でロックされている想定です")

        store.enableDebugUnlock()

        XCTAssertTrue(store.isDebugUnlockEnabled, "パスコード有効化後はフラグが true になる必要があります")
        XCTAssertTrue(store.isStageUnlocked(lockedStage), "全ステージ解放フラグが立つとロックを無視して遊べる必要があります")

        // 再生成したストアでもフラグが維持され、永続化されていることを確認する
        let reloadedStore = CampaignProgressStore(userDefaults: defaults)
        XCTAssertTrue(reloadedStore.isDebugUnlockEnabled, "UserDefaults 経由で再読み込みしても全解放状態が保持される必要があります")
        XCTAssertTrue(reloadedStore.isStageUnlocked(lockedStage), "再生成後もステージが解放されたままになる想定です")
    }

    /// 章単位のスター合計が解放条件へ反映されることを検証する
    func testChapterTotalStarsUnlocksNextChapter() throws {
        let defaults = try makeIsolatedDefaults()
        let store = CampaignProgressStore(userDefaults: defaults)
        let library = CampaignLibrary.shared

        let nextChapterStageID = CampaignStageID(chapter: 2, index: 1)
        guard let nextChapterStage = library.stage(with: nextChapterStageID) else {
            XCTFail("第2章のステージ定義が見つかりません")
            return
        }

        // MARK: スター 0 の状態では第 2 章の入り口がロックされている想定
        XCTAssertFalse(store.isStageUnlocked(nextChapterStage), "第1章のスター合計が不足している場合はロックが維持される必要があります")

        // MARK: 第 1 章の 6 ステージ分を順番にクリアし、スター合計を 18 まで伸ばす
        let stageIDsToClear: [CampaignStageID] = [
            CampaignStageID(chapter: 1, index: 1),
            CampaignStageID(chapter: 1, index: 2),
            CampaignStageID(chapter: 1, index: 3),
            CampaignStageID(chapter: 1, index: 4),
            CampaignStageID(chapter: 1, index: 5),
            CampaignStageID(chapter: 1, index: 6)
        ]
        // 3 スター獲得を想定した共通メトリクス（スコアとペナルティを十分小さく保つ）
        let perfectMetrics = CampaignStageClearMetrics(
            moveCount: 10,
            penaltyCount: 0,
            elapsedSeconds: 50,
            totalMoveCount: 10,
            score: 200,
            hasRevisitedTile: false
        )

        for stageID in stageIDsToClear.prefix(5) {
            guard let stage = library.stage(with: stageID) else {
                XCTFail("ステージ \(stageID.displayCode) の定義が見つかりません")
                return
            }
            _ = store.registerClear(for: stage, metrics: perfectMetrics)
        }

        // MARK: スター合計 15 の時点では解放条件に届かないことを確認
        XCTAssertEqual(store.totalStars(inChapter: 1), 15, "5 ステージクリア後のスター合計が想定と異なります")
        XCTAssertFalse(store.isStageUnlocked(nextChapterStage), "スターが 16 未満の場合はロックが継続する想定です")

        // MARK: 6 ステージ目をクリアして合計 18 に達すると解放される
        if let finalStage = library.stage(with: stageIDsToClear[5]) {
            _ = store.registerClear(for: finalStage, metrics: perfectMetrics)
        } else {
            XCTFail("ステージ \(stageIDsToClear[5].displayCode) の定義が見つかりません")
            return
        }

        XCTAssertEqual(store.totalStars(inChapter: 1), 18, "第1章で獲得したスター数の集計が期待値と異なります")
        XCTAssertTrue(store.isStageUnlocked(nextChapterStage), "スターが 16 以上になった時点で第 2 章の入口は解放される必要があります")
    }
}
