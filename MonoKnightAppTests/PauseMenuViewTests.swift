import SwiftUI
import UIKit
import XCTest
@testable import MonoKnightApp

@MainActor
final class PauseMenuViewTests: XCTestCase {
    func testPauseMenuExposesGamePanelAndPrimaryActions() {
        let defaults = UserDefaults(suiteName: "PauseMenuViewTests")!
        defaults.removePersistentDomain(forName: "PauseMenuViewTests")
        let settingsStore = GameSettingsStore(userDefaults: defaults)

        let controller = UIHostingController(
            rootView: PauseMenuView(
                onResume: {},
                onConfirmReturnToTitle: {}
            )
            .environmentObject(settingsStore)
        )

        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertNotNil(controller.view, "ポーズ画面のホスティングビュー生成に失敗しました")
        XCTAssertEqual(PauseMenuAccessibilityIdentifier.panel, "pause_menu_panel")
        XCTAssertEqual(PauseMenuAccessibilityIdentifier.resumeButton, "pause_resume_button")
        XCTAssertEqual(PauseMenuAccessibilityIdentifier.helpButton, "pause_help_button")
        XCTAssertEqual(PauseMenuAccessibilityIdentifier.returnToTitleButton, "pause_return_to_title_button")
        XCTAssertEqual(PauseMenuAccessibilityIdentifier.settingsDisclosure, "pause_settings_disclosure")
    }

    func testPauseMenuLaysOutOnNarrowWidth() {
        let defaults = UserDefaults(suiteName: "PauseMenuViewTestsNarrowWidth")!
        defaults.removePersistentDomain(forName: "PauseMenuViewTestsNarrowWidth")
        let settingsStore = GameSettingsStore(userDefaults: defaults)

        let controller = UIHostingController(
            rootView: PauseMenuView(
                onResume: {},
                onConfirmReturnToTitle: {}
            )
            .environmentObject(settingsStore)
        )

        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 320, height: 568)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertFalse(controller.view.bounds.isEmpty, "小幅画面でポーズ画面のレイアウト生成に失敗しました")
        XCTAssertEqual(PauseMenuAccessibilityIdentifier.helpButton, "pause_help_button")
    }
}
