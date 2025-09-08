import SwiftUI

/// ゲーム画面と設定画面を切り替えるルートビュー
/// `TabView` を用いて 2 つのタブを提供する
struct RootView: View {
    /// Game Center サービス（本番/モックで差し替え可能）
    let gameCenterService: GameCenterServiceProtocol
    /// 広告サービス（GameView へ伝搬するため保持）
    let adsService: AdsServiceProtocol

    /// Game Center 認証済みかどうかを追跡するフラグ
    /// - Note: `onAppear` が複数回呼ばれても二重認証を避ける
    @State private var didAuthenticate = false

    /// 依存性を注入するための初期化子
    /// - Parameters:
    ///   - gameCenterService: Game Center のサービス
    ///   - adsService: 広告サービス
    init(
        gameCenterService: GameCenterServiceProtocol = GameCenterService.shared,
        adsService: AdsServiceProtocol = AdsService.shared
    ) {
        self.gameCenterService = gameCenterService
        self.adsService = adsService
    }

    var body: some View {
        TabView {
            // MARK: - ゲームタブ
            GameView(gameCenterService: gameCenterService, adsService: adsService)
                .tabItem {
                    // システムアイコンとラベルを組み合わせてタブを定義
                    Label("ゲーム", systemImage: "gamecontroller")
                }

            // MARK: - 設定タブ
            SettingsView()
                .tabItem {
                    Label("設定", systemImage: "gearshape")
                }
        }
        .onAppear {
            // ルート ViewController が取得できるタイミングで認証を実施
            // Game Center のログイン UI を安全に表示できる
            guard !didAuthenticate else { return } // 二重呼び出しを防止
            gameCenterService.authenticateLocalPlayer()
            didAuthenticate = true
        }
    }
}

// MARK: - プレビュー
#Preview {
    RootView()
}

