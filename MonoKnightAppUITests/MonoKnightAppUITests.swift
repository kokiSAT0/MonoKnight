//
//  MonoKnightAppUITests.swift
//  MonoKnightAppUITests
//
//  Created by koki sato on 2025/09/10.
//

import XCTest

final class MonoKnightAppUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    /// 手札スロットのアクセシビリティ情報がスタック仕様に更新されているかを検証する
    @MainActor
    func testHandSlotsExposeStackAccessibility() throws {
        let app = XCUIApplication()
        app.launch()

        // 手札スロット 5 つそれぞれに識別子とラベルが設定されているか確認する
        for index in 0..<5 {
            let identifier = "hand_slot_\(index)"
            let slot = app.descendants(matching: .any)[identifier]

            XCTAssertTrue(slot.waitForExistence(timeout: 5), "手札スロット \(index) が表示されていません")

            // ラベルは「方向名、残り X 枚」の形式を想定するため、「残り」と「枚」が含まれているかを検証する
            XCTAssertTrue(slot.label.contains("残り"), "スロット \(index) のラベルに残枚数が含まれていません: \(slot.label)")
            XCTAssertTrue(slot.label.contains("枚"), "スロット \(index) のラベルに枚数表現がありません: \(slot.label)")

            // ヒントではスタック仕様や使用可否を案内しているため、代表的なキーワードのいずれかを含むことを確認する
            if let hint = slot.accessibilityHintText {
                let containsExpectedKeyword = hint.contains("重なっています") || hint.contains("ダブルタップ") || hint.contains("使用できません")
                XCTAssertTrue(containsExpectedKeyword, "スロット \(index) のヒントがスタック仕様を説明していません: \(hint)")
            }
        }
    }
}

// MARK: - UI テスト専用ヘルパー
private extension XCUIElement {
    /// VoiceOver ヒント文をリフレクション経由で取得し、テスト検証に利用できるようにする
    var accessibilityHintText: String? {
        value(forKey: "accessibilityHint") as? String
    }
}
