import SwiftUI
import UIKit
import XCTest
@testable import MonoKnightApp

@MainActor
final class DiagnosticsCenterViewTests: XCTestCase {
    func testDiagnosticsCenterExposesShareButtonIdentifier() {
        DebugLogHistory.shared.setFrontEndViewerEnabled(true)
        DebugLogHistory.shared.clear()
        debugLog("[PLAY] event=diagnostics_share_test")

        let controller = UIHostingController(
            rootView: NavigationStack {
                DiagnosticsCenterView()
            }
        )

        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertNotNil(controller.view, "診断ログ画面の生成に失敗しました")
        XCTAssertEqual(DiagnosticsCenterAccessibilityIdentifier.shareButton, "diagnostics_share_button")
        DebugLogHistory.shared.clear()
    }
}
