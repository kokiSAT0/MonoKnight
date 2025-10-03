import XCTest
@testable import MonoKnightApp
import Game

/// CampaignStageSelectionView に関連するヘルパーの挙動を検証するテスト
final class CampaignStageSelectionViewTests: XCTestCase {
    /// テストごとに独立した UserDefaults を生成し、副作用の混入を防ぐ
    private func makeIsolatedDefaults() throws -> UserDefaults {
        let suiteName = "campaign_stage_selection_tests." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("UserDefaults を生成できませんでした")
            throw NSError(domain: "CampaignStageSelectionViewTests", code: -1)
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    /// 未クリアかつ解放済みステージが複数章に存在する場合、該当章 ID をすべて返却できることを確認
    @MainActor
    func testHelperReturnsAllChaptersWithUnlockedUnclearedStages() throws {
        let defaults = try makeIsolatedDefaults()
        let progressStore = CampaignProgressStore(userDefaults: defaults)
        let library = CampaignLibrary.shared

        // デバッグ用全解放フラグを利用し、全ステージをロック解除した状態でスター未獲得のままにする
        progressStore.enableDebugUnlock()

        let chapterIDs = chapterIDsWithUnlockedUnclearedStages(library: library, progressStore: progressStore)
        let expectedChapterIDs = Set(library.chapters.map { $0.id })

        XCTAssertEqual(chapterIDs, expectedChapterIDs, "全章が未クリア扱いのときは、全章の ID が展開候補になる想定です")
    }

    /// 未クリアステージが存在しない場合でも、最新の解放章へフォールバックすることを確認
    @MainActor
    func testHelperFallsBackToLatestUnlockedChapterWhenNoTargetsExist() throws {
        let defaults = try makeIsolatedDefaults()
        let progressStore = CampaignProgressStore(userDefaults: defaults)
        let library = CampaignLibrary.shared

        // すべてのステージを順にクリア済みにし、スター 1 以上を獲得した状態を再現する
        let metrics = CampaignStageClearMetrics(
            moveCount: 20,
            penaltyCount: 0,
            elapsedSeconds: 120,
            totalMoveCount: 20,
            score: 200,
            hasRevisitedTile: false
        )
        for stage in library.allStages {
            progressStore.registerClear(for: stage, metrics: metrics)
        }

        let chapterIDs = chapterIDsWithUnlockedUnclearedStages(library: library, progressStore: progressStore)
        if let latestChapterID = library.chapters.last?.id {
            XCTAssertEqual(chapterIDs, [latestChapterID], "未クリアが無い場合は、最後に解放された章のみを展開対象とする想定です")
        } else {
            XCTAssertTrue(chapterIDs.isEmpty, "章が存在しない場合は空集合を返す想定です")
        }
    }
}
