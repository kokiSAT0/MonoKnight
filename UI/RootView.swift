import SwiftUI
import Game
import SharedSupport // 共有ログユーティリティを利用するために追加

/// ゲームプレイとタイトル画面を統括するルートビュー
/// タイトル画面での設定シート表示やゲーム開始フローをまとめて制御する
@MainActor
/// SwiftUI ビュー全体を MainActor 上で扱い、MainActor 隔離されたシングルトン（GameCenterService / AdsService）へアクセスする際の競合を防ぐ
/// - NOTE: Swift 6 で厳格化された並行性モデルに追従し、ビルドエラー（MainActor 分離違反）を確実に回避するための指定
struct RootView: View {
    /// 画面全体の配色を揃えるためのテーマ。タブやトップバーの背景色を一元管理するためここで生成する
    var theme = AppTheme()
    /// Game モジュール側の公開インターフェース束を保持し、GameView へ確実に注入できるようにする
    /// - NOTE: 依存をまとめておくことで、将来的にモック実装へ切り替える際も RootView の初期化だけで完結させられる
    let gameInterfaces: GameModuleInterfaces
    /// Game Center 連携を扱うサービス（プロトコル型で受け取る）
    let gameCenterService: GameCenterServiceProtocol
    /// 広告表示を扱うサービス（GameView へ受け渡す）
    let adsService: AdsServiceProtocol
    /// ユーザー設定を集約したストア
    let gameSettingsStore: GameSettingsStore
    /// デバイスの横幅サイズクラスを参照し、iPad などレギュラー幅での余白やログ出力を調整する
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    /// 画面全体の状態とログ出力を一元管理するステートストア
    /// - NOTE: onChange 連鎖による複雑な型推論を避け、プロパティ監視をクラス内の didSet へ集約する
    @StateObject var stateStore: RootViewStateStore
    /// ゲーム準備のワークアイテムと開始待ち状態を調停する coordinator
    @StateObject var preparationCoordinator = RootViewPreparationCoordinator()
    /// 塔ダンジョンの永続成長を管理するストア
    @StateObject var dungeonGrowthStore: DungeonGrowthStore
    /// 塔攻略の中断復帰を管理するストア
    @StateObject var dungeonRunResumeStore: DungeonRunResumeStore
    /// 試練塔のローカル最高到達記録を管理するストア
    @StateObject var rogueTowerRecordStore: RogueTowerRecordStore
    /// 基礎塔の完了状態と成長塔への初回誘導状態を管理するストア
    @StateObject var tutorialTowerProgressStore: TutorialTowerProgressStore
    /// タイトル画面まわりの遷移要求をまとめる coordinator
    let titleFlowCoordinator = RootViewTitleFlowCoordinator()
    /// Game Center の認証要求と再サインイン促しをまとめる補助
    let gameCenterPromptPresenter = RootViewGameCenterPromptPresenter()
    /// 依存サービスを外部から注入可能にする初期化処理
    /// - Parameters:
    ///   - gameCenterService: Game Center 連携用サービス（デフォルトはシングルトン）
    ///   - adsService: 広告表示用サービス（デフォルトはシングルトン）
    init(gameInterfaces: GameModuleInterfaces = .live,
         gameCenterService: GameCenterServiceProtocol? = nil,
         adsService: AdsServiceProtocol? = nil,
         gameSettingsStore: GameSettingsStore? = nil) {
        // Swift 6 ではデフォルト引数の評価が非分離コンテキストで行われるため、
        // `@MainActor` に隔離されたシングルトンを安全に利用するためにイニシャライザ内で解決する。
        let resolvedGameCenterService = gameCenterService ?? GameCenterService.shared
        let resolvedAdsService = adsService ?? AdsService.shared
        let resolvedGameSettingsStore = gameSettingsStore ?? GameSettingsStore()

        self.gameInterfaces = gameInterfaces
        self.gameCenterService = resolvedGameCenterService
        self.adsService = resolvedAdsService
        self.gameSettingsStore = resolvedGameSettingsStore
        // 画面状態を一括管理するステートストアを生成し、初期認証状態を反映する。
        _stateStore = StateObject(
            wrappedValue: RootViewStateStore(
                initialIsAuthenticated: resolvedGameCenterService.isAuthenticated
            )
        )
        _dungeonGrowthStore = StateObject(wrappedValue: DungeonGrowthStore())
        _dungeonRunResumeStore = StateObject(wrappedValue: DungeonRunResumeStore())
        _rogueTowerRecordStore = StateObject(wrappedValue: RogueTowerRecordStore())
        _tutorialTowerProgressStore = StateObject(wrappedValue: TutorialTowerProgressStore())
    }

    var body: some View {
        attachRootStateObservers(
            to: GeometryReader { geometry in
                // MARK: - GeometryReader が提供するサイズや safe area を専用コンテキストへまとめ、下層ビューへシンプルに引き渡す
                let layoutContext = makeLayoutContext(from: geometry)

                // MARK: - 生成済みのコンテキストを使い、型階層の浅いサブビューへ委譲して型チェック負荷を分散する
                makeRootContentView(with: layoutContext)
            }
        )
        .environmentObject(gameSettingsStore)
    }
}
