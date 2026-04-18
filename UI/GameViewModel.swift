import Combine  // Combine を利用して GameCore の更新を ViewModel 経由で伝搬する
import Foundation
import Game
import SharedSupport
import SwiftUI
import UIKit

// MARK: - ペナルティバナー制御専用ユーティリティ

/// ペナルティバナーの表示時間とキャンセル操作を抽象化するためのプロトコル
/// - Important: テストではスパイ実装を注入し、`scheduleAutoDismiss` / `cancel` が期待通り呼ばれたか検証できるようにする。
protocol PenaltyBannerScheduling: AnyObject {
    /// バナーの自動クローズ処理を一定時間後に実行する
    /// - Parameters:
    ///   - delay: 自動的に閉じるまでの待機秒数
    ///   - handler: 遅延実行したい処理本体
    func scheduleAutoDismiss(after delay: TimeInterval, handler: @escaping () -> Void)

    /// 保持している自動クローズ処理を破棄する
    func cancel()
}

/// ペナルティ発生時に表示するバナーの自動クローズを一元管理するためのヘルパークラス
/// - Note: `DispatchWorkItem` のライフサイクル管理を ViewModel 本体から切り離し、
///   将来的にバナー表示の継続時間やディスパッチキューを差し替える際の影響範囲を最小化する狙いがある。
final class PenaltyBannerScheduler: PenaltyBannerScheduling {
    /// 自動クローズを担当する WorkItem。複数回表示された際にキャンセル漏れが起こらないよう保持する
    private var dismissWorkItem: DispatchWorkItem?
    /// 非同期実行に利用するディスパッチキュー
    private let queue: DispatchQueue

    /// - Parameter queue: デフォルトでメインキューを利用するが、テスト時に差し替えられるように引数化している
    init(queue: DispatchQueue = .main) {
        self.queue = queue
    }

    /// バナーを一定時間後に非表示へ戻すスケジュールを登録する
    /// - Parameters:
    ///   - delay: 非表示へ切り替えるまでの待ち時間（秒）
    ///   - handler: 非表示へ切り替える際に実行するクロージャ
    func scheduleAutoDismiss(after delay: TimeInterval, handler: @escaping () -> Void) {
        cancel()

        // WorkItem が完了したタイミングで自身の参照を解放し、再表示時に新しい WorkItem を安全に登録できるようにする
        let workItem = DispatchWorkItem { [weak self] in
            defer { self?.dismissWorkItem = nil }
            handler()
        }
        dismissWorkItem = workItem
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    /// 登録済みの WorkItem をキャンセルし、リセットする
    func cancel() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
    }
}

/// ポーズメニューへ渡すキャンペーン進捗のサマリー
/// - Note: ステージ定義と保存済み進捗をまとめて保持し、View 側でのアンラップ処理を簡潔にする
struct CampaignPauseSummary {
    /// 対象ステージの定義
    let stage: CampaignStage
    /// 保存済みの進捗（まだプレイしていない場合は nil）
    let progress: CampaignStageProgress?
}

/// GameView のロジックとサービス連携を担う ViewModel
/// 描画に直接関係しない処理を SwiftUI View から切り離し、責務を明確化する
@MainActor
final class GameViewModel: ObservableObject {
    /// ゲームモードごとの設定
    let mode: GameMode
    /// Game パッケージが提供するファクトリセット
    let gameInterfaces: GameModuleInterfaces
    /// Game Center 連携を担当するサービス
    let gameCenterService: GameCenterServiceProtocol
    /// 広告表示の状態管理を担当するサービス
    let adsService: AdsServiceProtocol
    /// キャンペーン進捗ストア
    let campaignProgressStore: CampaignProgressStore
    /// Game Center サインインを再度促す要求を親へ伝えるクロージャ
    let onRequestGameCenterSignIn: ((GameCenterSignInPromptReason) -> Void)?
    /// タイトル復帰時に親へ伝えるためのクロージャ
    let onRequestReturnToTitle: (() -> Void)?
    /// クリア後に別のキャンペーンステージへ遷移したい場合のリクエストクロージャ
    /// - Note: ルート側でゲーム準備フローを再実行するため、`GameView` から直接モードを差し替えずに委譲する
    let onRequestStartCampaignStage: ((CampaignStage) -> Void)?

    /// SwiftUI から観測するゲームロジック本体
    @Published private(set) var core: GameCore
    /// SpriteKit と SwiftUI を仲介するための ViewModel
    let boardBridge: GameBoardBridgeViewModel
    /// 現在選択中の手札スタック ID
    /// - Important: 手札スロットの選択状態を SwiftUI から装飾できるよう公開し、候補マス確定後にリセットする。
    @Published var selectedHandStackID: UUID?

    /// 結果画面表示フラグ
    @Published var showingResult = false {
        didSet {
            resultPresentationState.showingResult = showingResult
        }
    }
    /// 直近のキャンペーンステージクリア記録
    /// - Note: リザルト画面でリワード進捗を可視化するため、クリア時に `flowCoordinator` から更新する
    @Published private(set) var latestCampaignClearRecord: CampaignStageClearRecord? {
        didSet {
            resultPresentationState.latestCampaignClearRecord = latestCampaignClearRecord
        }
    }
    /// 今回のクリアで新たに解放されたステージ一覧
    /// - Important: ユーザーをそのまま次の挑戦へ誘導するため、`ResultView` 側へ渡してボタン表示を制御する
    @Published private(set) var newlyUnlockedStages: [CampaignStage] = [] {
        didSet {
            resultPresentationState.newlyUnlockedStages = newlyUnlockedStages
        }
    }
    /// 手詰まりバナーに表示するイベント情報
    @Published var activePenaltyBanner: PenaltyEvent? {
        didSet {
            sessionUIState.activePenaltyBanner = activePenaltyBanner
        }
    }
    /// メニューで確認待ちのアクション
    @Published var pendingMenuAction: GameMenuAction? {
        didSet {
            sessionUIState.pendingMenuAction = pendingMenuAction
        }
    }
    /// ポーズメニューの表示状態
    @Published var isPauseMenuPresented = false {
        didSet {
            sessionUIState.setPauseMenuPresented(isPauseMenuPresented)
            handlePauseMenuVisibilityChange(isPresented: isPauseMenuPresented)
        }
    }
    /// 統計バッジ領域の高さ
    @Published var statisticsHeight: CGFloat = 0
    /// 手札セクションの高さ
    @Published var handSectionHeight: CGFloat = 0
    /// 画面に表示している経過秒数
    @Published var displayedElapsedSeconds: Int = 0 {
        didSet {
            sessionUIState.displayedElapsedSeconds = displayedElapsedSeconds
        }
    }
    /// 暫定スコア
    var displayedScore: Int {
        core.totalMoveCount * 10 + displayedElapsedSeconds
    }
    /// 現在の移動回数
    /// - Note: 統計バッジ表示で利用し、View 側から GameCore への直接依存を減らす
    var moveCount: Int { core.moveCount }
    /// 累計ペナルティ手数
    /// - Note: ペナルティバナーや統計表示の数値として再利用する
    var penaltyCount: Int { core.penaltyCount }
    /// クリア確定時点の経過秒数
    /// - Note: 結果画面や統計表示で参照するための公開プロパティ
    var elapsedSeconds: Int { core.elapsedSeconds }
    /// 未踏破マスの残数
    /// - Note: 進行状況バッジに表示するために用意する
    var remainingTiles: Int { core.remainingTiles }
    /// ポーズメニューで表示するキャンペーン情報
    /// - Note: モードに紐付くステージ ID からライブラリを引き、保存済み進捗をまとめて返す
    var campaignPauseSummary: CampaignPauseSummary? {
        sessionServicesCoordinator.makeCampaignPauseSummary(
            mode: mode,
            campaignLibrary: campaignLibrary,
            campaignProgressStore: campaignProgressStore
        )
    }
    /// ポーズメニューで再利用するペナルティ説明文の一覧
    /// - Important: RootView の事前案内と文言・順序を揃え、体験の一貫性を保つ
    var pauseMenuPenaltyItems: [String] {
        [
            mode.deadlockPenaltyCost > 0 ? "手詰まり +\(mode.deadlockPenaltyCost) 手" : "手詰まり ペナルティなし",
            mode.manualRedrawPenaltyCost > 0 ? "引き直し +\(mode.manualRedrawPenaltyCost) 手" : "引き直し ペナルティなし",
            mode.manualDiscardPenaltyCost > 0 ? "捨て札 +\(mode.manualDiscardPenaltyCost) 手" : "捨て札 ペナルティなし",
            mode.revisitPenaltyCost > 0 ? "再訪 +\(mode.revisitPenaltyCost) 手" : "再訪ペナルティなし"
        ]
    }
    /// 現在のゲーム進行状態
    /// - Note: GameView 側でオーバーレイ表示を切り替える際に利用する
    var progress: GameProgress { core.progress }
    /// ペナルティバナー表示中かどうか
    /// - Note: SwiftUI 側の表示切り替えで利用するシンプルなフラグ
    var isShowingPenaltyBanner: Bool { activePenaltyBanner != nil }
    /// 捨て札選択待機中かどうか
    /// - Note: ボタンのスタイル切り替えに必要な状態をカプセル化する
    var isAwaitingManualDiscardSelection: Bool { core.isAwaitingManualDiscardSelection }
    /// 現在の駒位置
    /// - Note: カード移動演出でフォールバック座標として参照する
    var currentPosition: GridPoint? { core.current }
    /// ランキング送信対象かどうか
    var isLeaderboardEligible: Bool { mode.isLeaderboardEligible }
    /// レイアウト診断用のスナップショット
    @Published var lastLoggedLayoutSnapshot: BoardLayoutSnapshot?
    /// 経過秒数を 1 秒刻みで更新するためのタイマーパブリッシャ
    let elapsedTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    /// ハプティクスの有効/無効設定
    var hapticsEnabled = true
    /// ガイドモードの有効/無効設定
    var guideModeEnabled = true
    /// Game Center 認証済みかどうかを UI と共有するフラグ
    @Published var isGameCenterAuthenticated: Bool
    /// 盤面タップ時にカード選択が必要なケースを利用者へ知らせるための警告状態
    /// - Important: `Identifiable` なペイロードを保持し、SwiftUI 側で `.alert(item:)` を使って監視できるようにする
    @Published var boardTapSelectionWarning: BoardTapSelectionWarning?

    /// Combine の購読を保持するセット
    var cancellables = Set<AnyCancellable>()
    /// キャンペーン定義
    private let campaignLibrary = CampaignLibrary.shared
    /// 現在時刻を取得するためのクロージャ。テストでは任意の値へ差し替える
    let currentDateProvider: () -> Date
    /// 手札選択と強制ハイライト制御を担当する内部状態
    var sessionState = GameSessionState()
    /// ペナルティバナー表示の責務を分離したヘルパー
    let penaltyBannerController: GamePenaltyBannerController
    /// タイマー停止理由を一元管理するヘルパー
    let pauseController: GamePauseController
    /// リザルト遷移とキャンペーン進捗更新を担当するヘルパー
    let flowCoordinator: GameFlowCoordinator
    /// 手札タップと盤面タップの入力フローを担当するヘルパー
    let inputFlowCoordinator: GameInputFlowCoordinator
    /// GameCore 購読と progress 起点の副作用を担当するヘルパー
    let coreBindingCoordinator: GameCoreBindingCoordinator
    /// タイトル復帰と新規プレイ開始時の後始末を担当するヘルパー
    let sessionResetCoordinator: GameSessionResetCoordinator
    /// 初期表示準備と設定同期を担当するヘルパー
    let appearanceSettingsCoordinator: GameAppearanceSettingsCoordinator
    /// Game Center / Campaign / Ads の橋渡しを担当するヘルパー
    let sessionServicesCoordinator: GameSessionServicesCoordinator
    /// リザルト表示の内部状態
    var resultPresentationState = ResultPresentationState()
    /// セッション中の補助 UI 状態
    var sessionUIState = SessionUIState()

    /// ViewModel の初期化
    /// - Parameters:
    ///   - mode: 選択されたゲームモード
    ///   - gameInterfaces: GameCore を生成するためのファクトリ
    ///   - gameCenterService: スコア送信に利用するサービス
    ///   - adsService: 広告表示制御を担うサービス
    ///   - onRequestReturnToTitle: タイトルへ戻る際に呼び出すクロージャ
    init(
        mode: GameMode,
        gameInterfaces: GameModuleInterfaces,
        gameCenterService: GameCenterServiceProtocol,
        adsService: AdsServiceProtocol,
        // `CampaignProgressStore` は @MainActor 隔離のため、デフォルト引数で直接生成すると
        // ビルドエラーが発生する。そこで `@autoclosure` 付きのファクトリを受け取り、
        // メインアクター上で初期化処理を実行するようにする。
        campaignProgressStore: @MainActor @autoclosure () -> CampaignProgressStore = CampaignProgressStore(),
        onRequestGameCenterSignIn: ((GameCenterSignInPromptReason) -> Void)?,
        onRequestReturnToTitle: (() -> Void)?,
        onRequestStartCampaignStage: ((CampaignStage) -> Void)?,
        penaltyBannerScheduler: PenaltyBannerScheduling = PenaltyBannerScheduler(),
        initialHandOrderingRawValue: String? = nil,
        initialGameCenterAuthenticationState: Bool = false,
        currentDateProvider: @escaping () -> Date = Date.init
    ) {
        self.mode = mode
        self.gameInterfaces = gameInterfaces
        self.gameCenterService = gameCenterService
        self.adsService = adsService
        // 上記のファクトリをここで評価し、@MainActor コンテキストから安全にインスタンス化する
        self.campaignProgressStore = campaignProgressStore()
        self.onRequestGameCenterSignIn = onRequestGameCenterSignIn
        self.onRequestReturnToTitle = onRequestReturnToTitle
        self.onRequestStartCampaignStage = onRequestStartCampaignStage
        self.penaltyBannerController = GamePenaltyBannerController(scheduler: penaltyBannerScheduler)
        self.pauseController = GamePauseController()
        self.flowCoordinator = GameFlowCoordinator()
        self.inputFlowCoordinator = GameInputFlowCoordinator()
        self.coreBindingCoordinator = GameCoreBindingCoordinator()
        self.sessionResetCoordinator = GameSessionResetCoordinator()
        self.appearanceSettingsCoordinator = GameAppearanceSettingsCoordinator()
        self.sessionServicesCoordinator = GameSessionServicesCoordinator()
        self.isGameCenterAuthenticated = initialGameCenterAuthenticationState
        self.currentDateProvider = currentDateProvider

        // GameCore を生成し、ViewModel 経由で観測できるようにする
        let generatedCore = gameInterfaces.makeGameCore(mode)
        self.core = generatedCore
        self.boardBridge = GameBoardBridgeViewModel(core: generatedCore, mode: mode)

        // GameCore の変更を ViewModel 経由で SwiftUI へ伝える
        generatedCore.objectWillChange
            .sink { [weak self] _ in
                guard let self else { return }
                self.objectWillChange.send()
            }
            .store(in: &cancellables)

        // BoardBridge の描画更新も ViewModel 経由で伝播し、GameView 側が単一の監視対象で済むようにする
        boardBridge.objectWillChange
            .sink { [weak self] _ in
                guard let self else { return }
                self.objectWillChange.send()
            }
            .store(in: &cancellables)

        // GameCore が公開する各種状態を監視し、SwiftUI 側の責務を軽量化する
        bindGameCore()

        // ユーザー設定から手札並び順を復元する
        if let rawValue = initialHandOrderingRawValue {
            restoreHandOrderingStrategy(from: rawValue)
        }
    }

    /// 手札表示の並び替え設定を即座に反映する
    /// 盤面タップ時に提示する警告ペイロード
    /// - Note: View 層で扱いやすいよう `Identifiable` を満たし、メッセージや対象マスなどの情報をまとめて保持する
    struct BoardTapSelectionWarning: Identifiable, Equatable {
        /// 識別子。複数回同じ警告を表示するケースに備えて毎回新規 ID を採番する
        let id = UUID()
        /// 利用者へ表示する本文
        let message: String
        /// 競合が発生した座標。デバッグ用途で参照できるようにしておく
        let destination: GridPoint
    }

    // MARK: - 手動操作ボタンのサポート

    /// 捨て札ボタンを操作可能かどうか判定する
    /// - Returns: 進行中かつ手札が 1 種類以上存在する場合に true
    var isManualDiscardButtonEnabled: Bool {
        sessionUIState.isManualDiscardButtonEnabled(
            progress: core.progress,
            handStacks: core.handStacks
        )
    }

    /// 捨て札ボタンに設定するアクセシビリティ説明文
    /// - Returns: 選択モード中かどうか、およびペナルティの有無に応じた説明テキスト
    var manualDiscardAccessibilityHint: String {
        sessionUIState.manualDiscardAccessibilityHint(
            penaltyCost: core.mode.manualDiscardPenaltyCost,
            isAwaitingManualDiscardSelection: core.isAwaitingManualDiscardSelection
        )
    }

    /// 捨て札モードの開始/終了をトグルする
    /// - Note: ボタンが無効な状態では開始せず、選択中であれば常に終了させる
    func toggleManualDiscardSelection() {
        clearSelectedCardSelection()
        if core.isAwaitingManualDiscardSelection {
            core.cancelManualDiscardSelection()
            return
        }

        guard isManualDiscardButtonEnabled else { return }
        core.beginManualDiscardSelection()
    }

    /// 手動ペナルティボタンを操作可能かどうか判定する
    /// - Returns: プレイ中であれば true
    var isManualPenaltyButtonEnabled: Bool {
        sessionUIState.isManualPenaltyButtonEnabled(progress: core.progress)
    }

    /// 手動ペナルティボタンのアクセシビリティ説明文
    /// - Returns: 手数消費量とスタック仕様を含めた説明テキスト
    var manualPenaltyAccessibilityHint: String {
        sessionUIState.manualPenaltyAccessibilityHint(
            penaltyCost: core.mode.manualRedrawPenaltyCost,
            handSize: core.mode.handSize,
            stackingRuleDetailText: core.mode.stackingRuleDetailText
        )
    }

}

#if DEBUG || canImport(XCTest)
extension GameViewModel {
    /// テスト専用ラッパー: プライベートな進行状態ハンドラを直接呼び出し、リザルト挙動を検証する
    func handleProgressChangeForTesting(_ progress: GameProgress) {
        handleProgressChange(progress)
    }

    /// テスト専用にポーズメニュー表示状態を直接切り替えるユーティリティ
    /// - Parameter isPresented: 新しい表示状態
    func setPauseMenuPresentedForTesting(_ isPresented: Bool) {
        isPauseMenuPresented = isPresented
    }
}
#endif

extension GameViewModel {
    func applyResultPresentationMutation(_ mutation: (inout ResultPresentationState) -> Void) {
        mutation(&resultPresentationState)
        syncResultPresentationFromState()
    }

    func syncResultPresentationFromState() {
        if showingResult != resultPresentationState.showingResult {
            showingResult = resultPresentationState.showingResult
        }
        latestCampaignClearRecord = resultPresentationState.latestCampaignClearRecord
        newlyUnlockedStages = resultPresentationState.newlyUnlockedStages
    }

    func applySessionUIMutation(_ mutation: (inout SessionUIState) -> Void) {
        mutation(&sessionUIState)
        syncSessionUIFromState()
    }

    func syncSessionUIFromState() {
        if activePenaltyBanner != sessionUIState.activePenaltyBanner {
            activePenaltyBanner = sessionUIState.activePenaltyBanner
        }
        if pendingMenuAction != sessionUIState.pendingMenuAction {
            pendingMenuAction = sessionUIState.pendingMenuAction
        }
        if isPauseMenuPresented != sessionUIState.isPauseMenuPresented {
            isPauseMenuPresented = sessionUIState.isPauseMenuPresented
        }
        if displayedElapsedSeconds != sessionUIState.displayedElapsedSeconds {
            displayedElapsedSeconds = sessionUIState.displayedElapsedSeconds
        }
    }

    /// キャンペーンモードでタイマー制御を行うべきかどうか
    var supportsTimerPausing: Bool {
        pauseController.supportsTimerPausing(for: mode)
    }

    /// ポーズメニューの開閉に応じてタイマーの停止/再開を制御する
    /// - Parameter isPresented: 現在のポーズメニュー表示状態
    func handlePauseMenuVisibilityChange(isPresented: Bool) {
        pauseController.handlePauseMenuVisibilityChange(
            isPresented: isPresented,
            supportsTimerPausing: supportsTimerPausing,
            progress: core.progress,
            pauseTimer: { [self] in
                core.pauseTimer(referenceDate: currentDateProvider())
            },
            resumeTimer: { [self] in
                core.resumeTimer(referenceDate: currentDateProvider())
            }
        )
    }
}

/// ゲーム画面のメニュー操作を表す列挙型
enum GameMenuAction: Hashable, Identifiable {
    case manualPenalty(penaltyCost: Int)
    case reset
    case returnToTitle

    /// Identifiable 準拠のための識別子
    var id: Int {
        switch self {
        case .manualPenalty:
            return 0
        case .reset:
            return 1
        case .returnToTitle:
            return 2
        }
    }

    /// 確認ダイアログ用のボタンタイトル
    var confirmationButtonTitle: String {
        switch self {
        case .manualPenalty:
            return "ペナルティを払う"
        case .reset:
            return "リセットする"
        case .returnToTitle:
            return "タイトルへ戻る"
        }
    }

    /// 確認ダイアログで表示する説明文
    var confirmationMessage: String {
        switch self {
        case .manualPenalty(let cost):
            if cost > 0 {
                return "手数を\(cost)増やして手札スロットを引き直します。現在の手札スロットは空になります。よろしいですか？"
            } else {
                return "手数を増やさずに手札スロットを引き直します。現在の手札スロットは空になります。よろしいですか？"
            }
        case .reset:
            return "現在の進行状況を破棄して、最初からやり直します。よろしいですか？"
        case .returnToTitle:
            return "ゲームを終了してタイトル画面へ戻ります。現在のプレイ内容は保存されません。"
        }
    }

    /// ボタンのロール種別
    var buttonRole: ButtonRole? {
        .destructive
    }
}
