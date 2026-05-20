import SwiftUI
import UIKit
import XCTest
@testable import MonoKnightApp
@testable import Game

@MainActor
final class DiagnosticsCenterViewTests: XCTestCase {
    func testSettingsDiagnosticsMenuAvailabilityDoesNotDependOnLogCapture() {
        DebugLogHistory.shared.setFrontEndViewerAvailable(true)
        DebugLogHistory.shared.setFrontEndViewerEnabled(false)
        defer {
            DebugLogHistory.shared.setFrontEndViewerEnabled(true)
            DebugLogHistory.shared.setFrontEndViewerAvailable(true)
        }

        let view = SettingsView()

        XCTAssertTrue(view.isDiagnosticsMenuAvailable)
    }

    func testDiagnosticsCenterExposesShareButtonIdentifier() {
        DebugLogHistory.shared.setFrontEndViewerEnabled(true)
        DebugLogHistory.shared.clear()
        debugLog("[PLAY] event=diagnostics_share_test")
        let resumeStore = makeIsolatedDungeonRunResumeStore()

        let controller = UIHostingController(
            rootView: NavigationStack {
                DiagnosticsCenterView(dungeonRunResumeStore: resumeStore)
            }
        )

        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertNotNil(controller.view, "診断ログ画面の生成に失敗しました")
        XCTAssertEqual(DiagnosticsCenterAccessibilityIdentifier.shareButton, "diagnostics_share_button")
        XCTAssertEqual(DiagnosticsCenterAccessibilityIdentifier.reproductionInput, "diagnostics_reproduction_input")
        XCTAssertEqual(DiagnosticsCenterAccessibilityIdentifier.reproductionImportButton, "diagnostics_reproduction_import_button")
        DebugLogHistory.shared.clear()
    }

    func testTesterReproductionPayloadRejectsInvalidText() {
        XCTAssertNil(TesterReproductionPayload.decode("not a repro payload"))
        XCTAssertNil(TesterReproductionPayload.decode("\(TesterReproductionPayload.prefix)not-base64"))
    }

    func testDiagnosticsReproductionImporterSavesValidPayloadAndRejectsInvalidText() throws {
        let resumeStore = makeIsolatedDungeonRunResumeStore()
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))
        let mode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower, cardVariationSeed: 13_579))
        let snapshot = try XCTUnwrap(GameCore(mode: mode).makeDungeonResumeSnapshot())
        let encoded = try XCTUnwrap(TesterReproductionPayload(snapshot: snapshot).encodedString)

        let result = DiagnosticsReproductionImporter.importSnapshot(from: encoded, into: resumeStore)

        guard case .success(let importedSnapshot) = result else {
            return XCTFail("正しい再現データは保存できるべき")
        }
        XCTAssertEqual(importedSnapshot, snapshot)
        XCTAssertEqual(resumeStore.snapshot, snapshot)

        let invalidStore = makeIsolatedDungeonRunResumeStore()
        let invalidResult = DiagnosticsReproductionImporter.importSnapshot(from: "invalid", into: invalidStore)
        XCTAssertEqual(invalidResult, .failure(.invalidPayload))
        XCTAssertNil(invalidStore.snapshot)
    }

    private func makeIsolatedDungeonRunResumeStore() -> DungeonRunResumeStore {
        let suiteName = "MonoKnightAppTests.diagnostics.resume.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return DungeonRunResumeStore(userDefaults: defaults)
    }
}
