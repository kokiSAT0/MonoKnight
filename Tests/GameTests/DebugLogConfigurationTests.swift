import XCTest
@testable import SharedSupport

/// DebugLogConfiguration の初期値や切り替え挙動を確認するテスト
/// - Note: 標準出力をテスト中に抑制できているかを明示的に検証する
final class DebugLogConfigurationTests: XCTestCase {
    override func tearDownWithError() throws {
        // 他テストへの影響を避けるため、毎回標準出力抑制へ戻す
        DebugLogConfiguration.shared.setStandardOutputLogging(enabled: false)
        DebugLogHistory.shared.setFrontEndViewerEnabled(true)
        DebugLogHistory.shared.clear()
    }

    func testStandardOutputIsDisabledByDefaultDuringUnitTests() {
        // XCTest 起動時には shouldPrintToStandardOutput が false で初期化される想定
        XCTAssertFalse(
            DebugLogConfiguration.shared.shouldPrintToStandardOutput,
            "ユニットテスト環境では標準出力を抑制するべき"
        )
    }

    func testStandardOutputCanBeToggledViaSetter() {
        // UI からの操作を想定して true に切り替えられるかを検証
        DebugLogConfiguration.shared.setStandardOutputLogging(enabled: true)
        XCTAssertTrue(
            DebugLogConfiguration.shared.shouldPrintToStandardOutput,
            "有効化メソッドで標準出力が再開するべき"
        )

        // 元に戻す操作も想定通り動作するか確認
        DebugLogConfiguration.shared.setStandardOutputLogging(enabled: false)
        XCTAssertFalse(
            DebugLogConfiguration.shared.shouldPrintToStandardOutput,
            "無効化メソッドで標準出力を再び抑制できるべき"
        )
    }

    func testPlayDiagnosticLogIsCapturedInHistory() {
        DebugLogHistory.shared.setFrontEndViewerEnabled(true)
        DebugLogHistory.shared.clear()

        debugLog("[PLAY] event=test_capture floor=1 turn=0 hp=3")

        XCTAssertTrue(
            DebugLogHistory.shared.snapshot().contains { entry in
                entry.level == .info && entry.message.contains("[PLAY] event=test_capture")
            },
            "[PLAY] ログは既存の診断ログ履歴へ保存されるべき"
        )
    }

    func testDebugLogShareReportIncludesContextAndLimitsRecentLogs() {
        let entries = (0..<5).map { index in
            DebugLogEntry(level: .info, message: "[PLAY] event=test_\(index)")
        }
        let report = DebugLogShareReportFormatter.makeReport(
            context: DebugLogShareReportContext(
                title: "塔テスト 3F",
                details: [
                    ("HP", "2"),
                    ("位置", "(1,2)")
                ]
            ),
            entries: entries,
            appVersion: "1.2.3",
            deviceDescription: "iPhone / iOS 18.6",
            generatedAt: Date(timeIntervalSince1970: 0),
            logLimit: 2
        )

        XCTAssertTrue(report.contains("何が変だったか一言追記してください"))
        XCTAssertTrue(report.contains("状況: 塔テスト 3F"))
        XCTAssertTrue(report.contains("アプリ: 1.2.3"))
        XCTAssertTrue(report.contains("端末: iPhone / iOS 18.6"))
        XCTAssertTrue(report.contains("HP: 2"))
        XCTAssertTrue(report.contains("[PLAY] event=test_3"))
        XCTAssertTrue(report.contains("[PLAY] event=test_4"))
        XCTAssertFalse(report.contains("[PLAY] event=test_2"))
    }

    func testDebugLogShareReportWorksWithoutLogs() {
        let report = DebugLogShareReportFormatter.makeReport(
            context: DebugLogShareReportContext(title: "診断ログ"),
            entries: [],
            appVersion: "unknown",
            deviceDescription: "unknown",
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertTrue(report.contains("直近ログ: 0件"))
        XCTAssertTrue(report.contains("ログはありません"))
    }
}
