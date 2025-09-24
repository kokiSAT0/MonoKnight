// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MonoKnight",
    platforms: [
        // iOS16 以降を対象
        .iOS(.v16)
    ],
    products: [
        // 共有ユーティリティをまとめたライブラリ
        .library(
            name: "SharedSupport",
            targets: ["SharedSupport"]
        ),
        // ゲームロジックをライブラリとして公開
        .library(
            name: "Game",
            targets: ["Game"]
        )
    ],
    targets: [
        // SharedSupport モジュールはロギングなどの共通処理を提供
        .target(
            name: "SharedSupport",
            path: "Shared/Logging"
        ),
        // Game モジュールは既存の Game ディレクトリを利用
        .target(
            name: "Game",
            dependencies: ["SharedSupport"],
            path: "Game"
        ),
        // 単体テスト用ターゲット
        .testTarget(
            name: "GameTests",
            dependencies: ["Game"],
            path: "Tests/GameTests"
        ),
        // XCUITest 用ターゲット（エミュレーター上での UI 動作確認用）
        .testTarget(
            name: "GameUITests",
            dependencies: [],
            path: "Tests/GameUITests"
        )
    ]
)
