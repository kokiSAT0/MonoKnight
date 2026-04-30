import XCTest
@testable import MonoKnightApp
import Game

/// キャンペーン進捗ストアの基本的な挙動を検証するテスト
@MainActor
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
            score: 205,
            hasRevisitedTile: false
        )

        let record = store.registerClear(for: stage, metrics: metrics)
        XCTAssertEqual(record.progress.earnedStars, 3, "1-1 は指定条件を満たすと 3 スター獲得できる想定です")
        XCTAssertEqual(store.totalStars, 3)

        // より低いスコアで再登録してもベスト値は維持されることを確認
        let worseMetrics = CampaignStageClearMetrics(
            moveCount: 20,
            penaltyCount: 2,
            elapsedSeconds: 140,
            totalMoveCount: 22,
            score: 120,
            hasRevisitedTile: true
        )
        _ = store.registerClear(for: stage, metrics: worseMetrics)
        let stored = store.progress(for: stageID)
        XCTAssertEqual(stored?.bestScore, metrics.score, "ベストスコアはより良い値を保持する必要があります")
        XCTAssertEqual(stored?.bestScoreVersion, CampaignScoring.currentVersion)
        XCTAssertEqual(stored?.earnedStars, 3, "一度獲得したスターは維持される想定です")
    }

    /// 旧スコア方式の保存値は、新方式の初回クリアで置き換えることを検証
    func testRegisterClearReplacesLegacyBestScoreVersion() throws {
        let defaults = try makeIsolatedDefaults()
        let library = CampaignLibrary.shared
        let stageID = CampaignStageID(chapter: 1, index: 1)
        guard let stage = library.stage(with: stageID) else {
            XCTFail("ステージ定義が見つかりません")
            return
        }

        let legacyProgress = CampaignStageProgress(earnedStars: 1, bestScore: 20, bestScoreVersion: nil)
        let encoded = try JSONEncoder().encode([stageID.storageKey: legacyProgress])
        defaults.set(encoded, forKey: StorageKey.UserDefaults.campaignProgress)

        let store = CampaignProgressStore(userDefaults: defaults)
        let newMetrics = CampaignStageClearMetrics(
            moveCount: 12,
            penaltyCount: 0,
            elapsedSeconds: 999,
            totalMoveCount: 12,
            score: 150,
            hasRevisitedTile: false
        )

        _ = store.registerClear(for: stage, metrics: newMetrics)
        XCTAssertEqual(store.progress(for: stageID)?.bestScore, 150)
        XCTAssertEqual(store.progress(for: stageID)?.bestScoreVersion, CampaignScoring.currentVersion)

        let lowerNewScoreMetrics = CampaignStageClearMetrics(
            moveCount: 20,
            penaltyCount: 0,
            elapsedSeconds: 20,
            totalMoveCount: 20,
            score: 100,
            hasRevisitedTile: false
        )
        _ = store.registerClear(for: stage, metrics: lowerNewScoreMetrics)
        XCTAssertEqual(store.progress(for: stageID)?.bestScore, 150, "新方式同士では高いスコアを保持します")
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

    /// 全解放フラグを無効化するとロック状態へ戻り、永続化も反映されることを確認する
    @MainActor
    func testDebugUnlockCanBeDisabled() throws {
        let defaults = try makeIsolatedDefaults()
        let store = CampaignProgressStore(userDefaults: defaults)
        let library = CampaignLibrary.shared

        let lockedStageID = CampaignStageID(chapter: 1, index: 2)
        guard let lockedStage = library.stage(with: lockedStageID) else {
            XCTFail("ステージ定義が見つかりません")
            return
        }

        // 前提として全解放を有効化し、無効化前の状態を整える
        store.enableDebugUnlock()
        XCTAssertTrue(store.isDebugUnlockEnabled)
        XCTAssertTrue(store.isStageUnlocked(lockedStage))

        // 無効化後はロックが復帰し、フラグが false に戻ることを確認
        store.disableDebugUnlock()
        XCTAssertFalse(store.isDebugUnlockEnabled, "disableDebugUnlock 呼び出しでフラグが false に戻る必要があります")
        XCTAssertFalse(store.isStageUnlocked(lockedStage), "全解放解除後は通常の解放条件に従う想定です")

        // UserDefaults へも反映されているか確認するため新しいインスタンスを生成
        let reloadedStore = CampaignProgressStore(userDefaults: defaults)
        XCTAssertFalse(reloadedStore.isDebugUnlockEnabled, "永続化内容も false に戻る必要があります")
        XCTAssertFalse(reloadedStore.isStageUnlocked(lockedStage), "再生成してもロック状態が維持されることを検証します")
    }

    /// 前章最終ステージのクリアが次章の解放条件へ反映されることを検証する
    func testStageClearUnlocksNextChapter() throws {
        let defaults = try makeIsolatedDefaults()
        let store = CampaignProgressStore(userDefaults: defaults)
        let library = CampaignLibrary.shared

        let nextChapterStageID = CampaignStageID(chapter: 2, index: 1)
        let previousChapterFinalStageID = CampaignStageID(chapter: 1, index: 8)
        guard let nextChapterStage = library.stage(with: nextChapterStageID) else {
            XCTFail("第2章のステージ定義が見つかりません")
            return
        }
        guard let previousChapterFinalStage = library.stage(with: previousChapterFinalStageID) else {
            XCTFail("第1章の最終ステージ定義が見つかりません")
            return
        }

        XCTAssertFalse(store.isStageUnlocked(nextChapterStage), "前章最終ステージが未クリアの場合はロックが維持される必要があります")

        let clearMetrics = CampaignStageClearMetrics(
            moveCount: 10,
            penaltyCount: 0,
            elapsedSeconds: 50,
            totalMoveCount: 10,
            score: 200,
            hasRevisitedTile: false
        )
        _ = store.registerClear(for: previousChapterFinalStage, metrics: clearMetrics)

        XCTAssertTrue(store.isStageUnlocked(nextChapterStage), "前章最終ステージのクリア後に第2章の入口が解放される必要があります")
    }
}
