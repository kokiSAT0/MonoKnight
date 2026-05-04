import XCTest
@testable import MonoKnightApp
import Game

/// 旧目的地制キャンペーン選択 UI は通常導線から外れているため、ヘルパーが最低限動くことだけ確認する。
@MainActor
final class CampaignStageSelectionViewTests: XCTestCase {
    func testLegacyCampaignSelectionHelperReturnsSomeChapterForCompatibleProgress() throws {
        let suiteName = "campaign_stage_selection_tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let progressStore = CampaignProgressStore(userDefaults: defaults)
        let library = CampaignLibrary.shared
        progressStore.enableDebugUnlock()

        let chapterIDs = chapterIDsWithUnlockedUnclearedStages(library: library, progressStore: progressStore)

        XCTAssertFalse(library.chapters.isEmpty)
        XCTAssertFalse(chapterIDs.isEmpty)
    }
}
