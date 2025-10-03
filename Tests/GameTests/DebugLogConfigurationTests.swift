import XCTest
@testable import SharedSupport

/// DebugLogConfiguration の初期値や切り替え挙動を確認するテスト
/// - Note: 標準出力をテスト中に抑制できているかを明示的に検証する
final class DebugLogConfigurationTests: XCTestCase {
    override func tearDownWithError() throws {
        // 他テストへの影響を避けるため、毎回標準出力抑制へ戻す
        DebugLogConfiguration.shared.setStandardOutputLogging(enabled: false)
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
}
