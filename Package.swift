// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MonoKnight",
    platforms: [
        // iOS16 以降を対象
        .iOS(.v16)
    ],
    products: [
        // ゲームロジックをライブラリとして公開
        .library(
            name: "Game",
            targets: ["Game"]
        ),
        // アプリとゲームモジュールで共有するサポート機能
        .library(
            name: "SharedSupport",
            targets: ["SharedSupport"]
        )
    ],
    targets: [
        // アプリとゲームロジックの双方で利用する共有ターゲット
        .target(
            name: "SharedSupport",
            path: "Shared"
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
