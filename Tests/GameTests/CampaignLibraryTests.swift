import XCTest
@testable import Game

/// 旧目的地制キャンペーンは通常導線から外れているため、詳細な進行設計ではなく互換の最低限だけを守る。
final class CampaignLibraryTests: XCTestCase {
    func testLegacyCampaignLibraryLoadsRegisteredStages() {
        let library = CampaignLibrary.shared

        XCTAssertFalse(library.chapters.isEmpty)
        XCTAssertFalse(library.allStages.isEmpty)
        XCTAssertTrue(library.allStages.allSatisfy { library.stage(with: $0.id) == $0 })
    }

    func testLegacyCampaignStageCanStillCreatePlayableMode() throws {
        let stage = try XCTUnwrap(CampaignLibrary.shared.allStages.first)
        let mode = stage.makeGameMode()

        XCTAssertEqual(mode.identifier, .campaignStage)
        XCTAssertEqual(mode.campaignMetadataSnapshot?.stageID, stage.id)
        XCTAssertEqual(mode.regulationSnapshot, stage.regulation)
        XCTAssertFalse(mode.isLeaderboardEligible)
    }

    func testLegacyCampaignCoordinatesStayInsideTheirBoards() {
        for stage in CampaignLibrary.shared.allStages {
            let boardSize = stage.regulation.boardSize

            for point in stage.regulation.impassableTilePoints {
                XCTAssertTrue(point.isInside(boardSize: boardSize), "\(stage.displayCode) の障害物 \(point) が盤外です")
            }
            for (point, effect) in stage.regulation.tileEffectOverrides {
                XCTAssertTrue(point.isInside(boardSize: boardSize), "\(stage.displayCode) の特殊マス \(point) が盤外です")
                if case .openGate(let target) = effect {
                    XCTAssertTrue(target.isInside(boardSize: boardSize), "\(stage.displayCode) の開門先 \(target) が盤外です")
                }
            }
            for points in stage.regulation.warpTilePairs.values {
                for point in points {
                    XCTAssertTrue(point.isInside(boardSize: boardSize), "\(stage.displayCode) のワープ \(point) が盤外です")
                }
            }
            for points in stage.regulation.fixedWarpCardTargets.values {
                for point in points {
                    XCTAssertTrue(point.isInside(boardSize: boardSize), "\(stage.displayCode) の固定ワープ先 \(point) が盤外です")
                }
            }
        }
    }
}
