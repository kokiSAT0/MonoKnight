import SwiftUI
import Foundation

// MARK: - アプリのエントリーポイント
// `@main` 属性を付与した構造体からアプリが開始される
@main
struct KnightCardsApp: App {
    /// Game Center サービス（本番またはテスト用）
    private let gameCenterService: GameCenterServiceProtocol
    /// 広告サービス（本番またはテスト用）
    private let adsService: AdsServiceProtocol

    /// イニシャライザで環境に応じたサービスを選択
    init() {
        // UI テスト実行時は Xcode が設定する環境変数を利用
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if isTesting {
            // テスト用のダミーサービスを使用
            self.gameCenterService = GameCenterServiceMock()
            self.adsService = AdsServiceMock()
        } else {
            // 通常はシングルトンを使用
            self.gameCenterService = GameCenterService.shared
            self.adsService = AdsService.shared
        }
    }

    var body: some Scene {
        WindowGroup {
            // MARK: 起動直後に表示するルートビュー
            // TabView でゲームと設定を切り替える `RootView` を表示
            RootView(
                gameCenterService: gameCenterService,
                adsService: adsService
            )
        }
    }
}

