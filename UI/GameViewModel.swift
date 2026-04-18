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
    @Published private(set) var selectedHandStackID: UUID?

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
    private(set) var hapticsEnabled = true
    /// ガイドモードの有効/無効設定
    private(set) var guideModeEnabled = true
    /// Game Center 認証済みかどうかを UI と共有するフラグ
    @Published private(set) var isGameCenterAuthenticated: Bool
    /// 盤面タップ時にカード選択が必要なケースを利用者へ知らせるための警告状態
    /// - Important: `Identifiable` なペイロードを保持し、SwiftUI 側で `.alert(item:)` を使って監視できるようにする
    @Published var boardTapSelectionWarning: BoardTapSelectionWarning?

    /// Combine の購読を保持するセット
    private var cancellables = Set<AnyCancellable>()
    /// キャンペーン定義
    private let campaignLibrary = CampaignLibrary.shared
    /// 現在時刻を取得するためのクロージャ。テストでは任意の値へ差し替える
    private let currentDateProvider: () -> Date
    /// 手札選択と強制ハイライト制御を担当する内部状態
    private var sessionState = GameSessionState()
    /// ペナルティバナー表示の責務を分離したヘルパー
    private let penaltyBannerController: GamePenaltyBannerController
    /// タイマー停止理由を一元管理するヘルパー
    private let pauseController: GamePauseController
    /// リザルト遷移とキャンペーン進捗更新を担当するヘルパー
    private let flowCoordinator: GameFlowCoordinator
    /// 手札タップと盤面タップの入力フローを担当するヘルパー
    private let inputFlowCoordinator: GameInputFlowCoordinator
    /// GameCore 購読と progress 起点の副作用を担当するヘルパー
    private let coreBindingCoordinator: GameCoreBindingCoordinator
    /// タイトル復帰と新規プレイ開始時の後始末を担当するヘルパー
    private let sessionResetCoordinator: GameSessionResetCoordinator
    /// 初期表示準備と設定同期を担当するヘルパー
    private let appearanceSettingsCoordinator: GameAppearanceSettingsCoordinator
    /// Game Center / Campaign / Ads の橋渡しを担当するヘルパー
    private let sessionServicesCoordinator: GameSessionServicesCoordinator
    /// リザルト表示の内部状態
    private var resultPresentationState = ResultPresentationState()
    /// セッション中の補助 UI 状態
    private var sessionUIState = SessionUIState()

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

    /// ユーザー設定から手札の並び替え戦略を復元する
    /// - Parameter rawValue: UserDefaults に保存されている文字列値
    func restoreHandOrderingStrategy(from rawValue: String) {
        appearanceSettingsCoordinator.restoreHandOrderingStrategy(from: rawValue, core: core)
    }

    /// 手札表示の並び替え設定を即座に反映する
    /// - Parameter rawValue: AppStorage から得た値
    func applyHandOrderingStrategy(rawValue: String) {
        appearanceSettingsCoordinator.applyHandOrderingStrategy(rawValue: rawValue, core: core)
    }

    /// Game Center 認証状態を更新し、必要に応じてログへ記録する
    /// - Parameter newValue: 最新の認証可否
    func updateGameCenterAuthenticationStatus(_ newValue: Bool) {
        sessionServicesCoordinator.updateGameCenterAuthenticationStatus(
            currentValue: isGameCenterAuthenticated,
            newValue: newValue
        ) { [weak self] updatedValue in
            self?.isGameCenterAuthenticated = updatedValue
        }
    }

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

    /// ガイドモードの設定値を更新し、必要に応じてハイライトを再描画する
    /// - Parameter enabled: 新しいガイドモード設定
    func updateGuideMode(enabled: Bool) {
        appearanceSettingsCoordinator.updateGuideMode(
            enabled: enabled,
            boardBridge: boardBridge
        ) { [weak self] updatedValue in
            self?.guideModeEnabled = updatedValue
        }
    }

    /// ハプティクスの設定を更新する
    /// - Parameter isEnabled: ユーザー設定から得たハプティクス有効フラグ
    func updateHapticsSetting(isEnabled: Bool) {
        appearanceSettingsCoordinator.updateHapticsSetting(
            isEnabled: isEnabled,
            boardBridge: boardBridge
        ) { [weak self] updatedValue in
            self?.hapticsEnabled = updatedValue
        }
    }

    /// 盤面タップ警告を外部からクリアしたい場合のユーティリティ
    /// - Important: トースト表示の自動消滅と同期させるため、View 層から明示的に呼び出せるよう公開する
    func clearBoardTapSelectionWarning() {
        boardTapSelectionWarning = nil
    }

    /// 結果画面を閉じた際の後処理
    func finalizeResultDismissal() {
        applyResultPresentationMutation { state in
            state.hideResult()
        }
    }

    /// SpriteKit シーンの配色を更新する
    /// - Parameter scheme: 現在のカラースキーム
    func applyScenePalette(for scheme: ColorScheme) {
        boardBridge.applyScenePalette(for: scheme)
    }

    /// ハイライト表示を最新の状態へ更新する
    func refreshGuideHighlights(
        handOverride: [HandStack]? = nil,
        currentOverride: GridPoint? = nil,
        progressOverride: GameProgress? = nil
    ) {
        boardBridge.refreshGuideHighlights(
            handOverride: handOverride,
            currentOverride: currentOverride,
            progressOverride: progressOverride
        )
    }

    /// カード選択 UI から強制的に盤面ハイライトを表示したい場合のエントリポイント
    /// - Parameter points: ユーザーに示したい候補座標集合。空集合を渡すと強制表示を解除する。
    /// - Note: チュートリアルやヒント UI で特定マスを指示したいケースを想定し、View 層から直接 `GameScene` へ触れずに更新できるようにする。
    func updateForcedSelectionHighlight(points: Set<GridPoint>) {
        boardBridge.updateForcedSelectionHighlights(points)
    }

    /// 特定の手札スタックに応じた強制ハイライトを更新するユーティリティ
    /// - Parameter stack: ハイライトしたいスタック。nil や未使用カードの場合は解除を行う。
    /// - Important: カード選択 UI でフォーカスが移動した際に呼び出し、解除時は `nil` を渡す運用を想定している。
    func updateForcedSelectionHighlight(for stack: HandStack?) {
        guard
            let stack,
            let current = core.current,
            let card = stack.topCard
        else {
            boardBridge.updateForcedSelectionHighlights([])
            return
        }

        // --- 現在の盤面状態をスナップショットし、障害物や既踏マスを含めた判定コンテキストを構築する ---
        let snapshotBoard = core.board
        let context = MoveCard.MovePattern.ResolutionContext(
            boardSize: snapshotBoard.size,
            contains: { point in snapshotBoard.contains(point) },
            isTraversable: { point in snapshotBoard.isTraversable(point) },
            isVisited: { point in snapshotBoard.isVisited(point) }
        )

        // --- MovePattern.resolvePaths を用いて実際に到達可能な経路のみを抽出する ---
        let availablePaths = card.move.resolvePaths(from: current, context: context)
        let destinations = Set(availablePaths.map { $0.destination })

        // --- 候補が存在しない場合は安全に解除し、存在する場合のみ強制ハイライトを更新する ---
        boardBridge.updateForcedSelectionHighlights(destinations)
    }

    /// 表示用の経過時間を再計算する
    func updateDisplayedElapsedTime() {
        // GameCore 側では経過秒数をリアルタイム計測しつつ、クリア確定時に `elapsedSeconds` へ確定値を格納する。
        // プレイ中に UI で使用する値は `liveElapsedSeconds` を参照することで、
        // ストップウォッチのように 1 秒刻みで増加し続ける体験を提供できるようにする。
        appearanceSettingsCoordinator.updateDisplayedElapsedTime(
            liveElapsedSeconds: core.liveElapsedSeconds
        ) { [weak self] seconds in
            self?.applySessionUIMutation { state in
                state.updateDisplayedElapsedTime(seconds)
            }
        }
    }

    /// 指定スタックのカードが現在位置から使用可能か判定する
    func isCardUsable(_ stack: HandStack) -> Bool {
        boardBridge.isCardUsable(stack)
    }

    /// 手札スタックのトップカードを盤面へ送るアニメーションを準備する
    @discardableResult
    func animateCardPlay(for stack: HandStack, at index: Int) -> Bool {
        boardBridge.animateCardPlay(for: stack, at: index)
    }

    /// 手札スロットがタップされた際の挙動を集約する
    /// - Parameter index: ユーザーが操作したスロットの添字
    func handleHandSlotTap(at index: Int) {
        inputFlowCoordinator.handleHandSlotTap(
            at: index,
            core: core,
            boardBridge: boardBridge,
            sessionState: &sessionState,
            selectedHandStackID: &selectedHandStackID,
            hapticsEnabled: hapticsEnabled
        )
    }

    /// 盤面タップに応じたプレイ要求を処理する
    /// - Important: BoardTapPlayRequest の受付は GameViewModel が単一窓口となる。描画橋渡し層や View 側で同様の処理を複製しないこと
    func handleBoardTapPlayRequest(_ request: BoardTapPlayRequest) {
        inputFlowCoordinator.handleBoardTapPlayRequest(
            request,
            core: core,
            boardBridge: boardBridge,
            sessionState: &sessionState,
            selectedHandStackID: &selectedHandStackID,
            hapticsEnabled: hapticsEnabled
        ) { [weak self] message, destination in
            self?.boardTapSelectionWarning = BoardTapSelectionWarning(
                message: message,
                destination: destination
            )
        }
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

    /// 手動ペナルティの確認ダイアログを表示するようリクエストする
    /// - Note: ゲームが進行中でない場合は無視し、誤操作によるダイアログ表示を防ぐ
    func requestManualPenalty() {
        guard isManualPenaltyButtonEnabled else { return }
        applySessionUIMutation { state in
            state.requestManualPenalty(cost: core.mode.manualRedrawPenaltyCost)
        }
    }

    /// ホームボタンの押下をトリガーに、タイトルへ戻る確認ダイアログを表示する
    /// - Note: 直接リセットを実行せず、一度 pendingMenuAction へ格納して既存の確認フローを流用する
    func requestReturnToTitle() {
        applySessionUIMutation { state in
            state.requestReturnToTitle()
        }
    }

    /// ポーズメニューを表示する
    /// - Note: ログ出力もここでまとめて行い、UI 側の責務を軽量化する
    func presentPauseMenu() {
        debugLog("GameViewModel: ポーズメニュー表示要求")
        applySessionUIMutation { state in
            state.presentPauseMenu()
        }
    }

    /// scenePhase の変化に応じてタイマーの停止/再開を制御する
    /// - Parameter newPhase: 画面のアクティブ状態
    func handleScenePhaseChange(_ newPhase: ScenePhase) {
        pauseController.handleScenePhaseChange(
            newPhase,
            supportsTimerPausing: supportsTimerPausing,
            progress: core.progress,
            pauseTimer: { [self] in
                core.pauseTimer(referenceDate: currentDateProvider())
            },
            presentPauseMenu: { [self] in
                presentPauseMenu()
            }
        )
    }

    /// ゲーム準備オーバーレイの表示/非表示を受け取り、タイマー制御を統合する
    /// - Parameter isVisible: 現在のローディング表示状態
    func handlePreparationOverlayChange(isVisible: Bool) {
        pauseController.handlePreparationOverlayChange(
            isVisible: isVisible,
            supportsTimerPausing: supportsTimerPausing,
            progress: core.progress,
            pauseTimer: { [self] in
                core.pauseTimer(referenceDate: currentDateProvider())
            },
            resumeTimer: { [self] in
                core.resumeTimer(referenceDate: currentDateProvider())
            },
            presentPauseMenu: { [self] in
                presentPauseMenu()
            }
        )
    }

    /// ゲームの進行状況に応じた操作をまとめて処理する
    func performMenuAction(_ action: GameMenuAction) {
        applySessionUIMutation { state in
            state.clearPendingMenuAction()
        }
        clearSelectedCardSelection()
        switch action {
        case .manualPenalty:
            cancelPenaltyBannerDisplay()
            core.applyManualPenaltyRedraw()

        case .reset:
            resetSessionForNewPlay()

        case .returnToTitle:
            prepareForReturnToTitle()
            onRequestReturnToTitle?()
        }
    }

    /// 盤面サイズや踏破状況などを初期化する
    func prepareForAppear(
        colorScheme: ColorScheme,
        guideModeEnabled: Bool,
        hapticsEnabled: Bool,
        handOrderingStrategy: HandOrderingStrategy,
        isPreparationOverlayVisible: Bool
    ) {
        appearanceSettingsCoordinator.prepareForAppear(
            colorScheme: colorScheme,
            guideModeEnabled: guideModeEnabled,
            hapticsEnabled: hapticsEnabled,
            handOrderingStrategy: handOrderingStrategy,
            isPreparationOverlayVisible: isPreparationOverlayVisible,
            boardBridge: boardBridge,
            core: core,
            updateGuideMode: { [weak self] enabled in
                self?.updateGuideMode(enabled: enabled)
            },
            updateHapticsSetting: { [weak self] isEnabled in
                self?.updateHapticsSetting(isEnabled: isEnabled)
            },
            updateDisplayedElapsedTime: { [weak self] in
                self?.updateDisplayedElapsedTime()
            },
            handlePreparationOverlayChange: { [weak self] isVisible in
                self?.handlePreparationOverlayChange(isVisible: isVisible)
            }
        )
    }

    /// ペナルティイベントを受信した際の処理
    /// - Parameter event: GameCore から通知された最新のペナルティ詳細
    func handlePenaltyEvent(_ event: PenaltyEvent) {
        penaltyBannerController.handlePenaltyEvent(
            event,
            hapticsEnabled: hapticsEnabled
        ) { [weak self] banner in
            self?.applySessionUIMutation { state in
                state.setActivePenaltyBanner(banner)
            }
        }
    }

    /// 盤面レイアウト関連のアンカー情報を更新する
    func updateBoardAnchor(_ anchor: Anchor<CGRect>?) {
        boardBridge.updateBoardAnchor(anchor)
    }

    /// 結果画面からリトライを選択した際の共通処理
    func handleResultRetry() {
        resetSessionForNewPlay()
    }

    /// リザルト画面からホームへ戻るリクエストを受け取った際の共通処理
    /// - Note: リトライ時と同じ初期化を行った上で、ルートビューへ遷移要求を転送する
    func handleResultReturnToTitle() {
        prepareForReturnToTitle()
        onRequestReturnToTitle?()
    }

    /// 手札選択状態を初期化し、盤面ハイライトを消去する
    private func clearSelectedCardSelection() {
        inputFlowCoordinator.clearSelectedCardSelection(
            sessionState: &sessionState,
            boardBridge: boardBridge,
            selectedHandStackID: &selectedHandStackID
        )
    }

    /// 手札更新後も選択状態が維持できるか検証し、必要に応じてリセットする
    /// - Parameter handStacks: 最新の手札スタック一覧
    private func refreshSelectionIfNeeded(with handStacks: [HandStack]) {
        inputFlowCoordinator.refreshSelectionIfNeeded(
            with: handStacks,
            core: core,
            boardBridge: boardBridge,
            sessionState: &sessionState,
            selectedHandStackID: &selectedHandStackID
        )
    }

    /// ペナルティバナー表示に関連する状態とワークアイテムをまとめて破棄する
    /// - Note: 手動ペナルティやリセット操作後にバナーが残存しないよう、共通処理として切り出している
    private func cancelPenaltyBannerDisplay() {
        penaltyBannerController.cancel { [weak self] banner in
            self?.applySessionUIMutation { state in
                state.setActivePenaltyBanner(banner)
            }
        }
    }

    /// ホーム画面へ戻る際に共通で必要となる状態リセットをひとまとめにする
    /// - Important: タイトルへ戻る場合はプレイ内容を保持したまま、UI 状態のみを初期化したいので `core.reset()` は呼び出さない
    private func prepareForReturnToTitle() {
        sessionResetCoordinator.prepareForReturnToTitle(
            clearSelectedCardSelection: { [self] in clearSelectedCardSelection() },
            cancelPenaltyBannerDisplay: { [self] in cancelPenaltyBannerDisplay() },
            hideResult: { [self] in
                applyResultPresentationMutation { state in
                    state.hideResult()
                }
            },
            resetTransientUI: { [self] in
                applySessionUIMutation { state in
                    state.resetTransientUIForTitleReturn()
                }
            },
            clearBoardTapSelectionWarning: { [self] in
                clearBoardTapSelectionWarning()
            },
            resetAdsPlayFlag: { [self] in
                sessionServicesCoordinator.resetAdsPlayFlag(using: adsService)
            },
            resetPauseController: { [self] in
                pauseController.reset()
            }
        )
    }

    /// 新しいプレイを始める際に必要な初期化処理を共通化する
    /// - Note: リザルトからのリトライやリセット操作で重複していた処理を一本化し、将来的な初期化追加にも対応しやすくする
    private func resetSessionForNewPlay() {
        sessionResetCoordinator.resetSessionForNewPlay(
            prepareForReturnToTitle: { [self] in prepareForReturnToTitle() },
            resetCore: { [self] in core.reset() },
            resetPauseController: { [self] in pauseController.reset() }
        )
    }

    /// GameCore のストリームを監視し、UI 更新に必要な副作用を引き受ける
    private func bindGameCore() {
        coreBindingCoordinator.bind(
            core: core,
            cancellables: &cancellables,
            onPenaltyEvent: { [weak self] event in
                self?.handlePenaltyEvent(event)
            },
            onHandStacksChange: { [weak self] newHandStacks in
                self?.refreshSelectionIfNeeded(with: newHandStacks)
            },
            onBoardTapPlayRequest: { [weak self] request in
                self?.handleBoardTapPlayRequest(request)
            },
            onProgressChange: { [weak self] progress in
                self?.handleProgressChange(progress)
            },
            onElapsedTimeChange: { [weak self] in
                self?.updateDisplayedElapsedTime()
            }
        )
    }

    /// 進行状態の変化に応じた副作用をまとめる
    /// - Parameter progress: GameCore が提供する現在の進行状態
    private func handleProgressChange(_ progress: GameProgress) {
        coreBindingCoordinator.handleProgressChange(
            progress,
            boardBridge: boardBridge,
            updateDisplayedElapsedTime: { [self] in
                updateDisplayedElapsedTime()
            },
            clearSelectedCardSelection: { [self] in
                clearSelectedCardSelection()
            },
            resolveClearOutcome: { [self] in
                guard progress == .cleared else { return nil }
                return sessionServicesCoordinator.resolveClearOutcome(
                    mode: mode,
                    core: core,
                    isGameCenterAuthenticated: isGameCenterAuthenticated,
                    flowCoordinator: flowCoordinator,
                    gameCenterService: gameCenterService,
                    onRequestGameCenterSignIn: onRequestGameCenterSignIn,
                    campaignProgressStore: campaignProgressStore
                )
            },
            applyClearOutcome: { [self] outcome in
                applyResultPresentationMutation { state in
                    state.applyClearOutcome(outcome)
                }
            }
        )
    }

    /// 新しく解放されたキャンペーンステージへ遷移するリクエストを処理する
    /// - Parameter stage: 遷移先のステージ
    func handleCampaignStageAdvance(to stage: CampaignStage) {
        // バナー表示などの残留状態を片付けつつリザルトを閉じ、新規ステージへ進む準備を整える
        sessionResetCoordinator.prepareForCampaignStageAdvance(
            cancelPenaltyBannerDisplay: { [self] in cancelPenaltyBannerDisplay() },
            hideResult: { [self] in
                applyResultPresentationMutation { state in
                    state.hideResult()
                }
            },
            resetTransientUI: { [self] in
                applySessionUIMutation { state in
                    state.resetTransientUIForTitleReturn()
                }
            },
            clearBoardTapSelectionWarning: { [self] in
                clearBoardTapSelectionWarning()
            },
            resetAdsPlayFlag: { [self] in
                sessionServicesCoordinator.resetAdsPlayFlag(using: adsService)
            }
        )

        // ルートビュー側へ遷移要求を転送し、ゲーム準備フローを再利用する
        sessionServicesCoordinator.handleCampaignStageAdvance(
            to: stage,
            campaignProgressStore: campaignProgressStore,
            onRequestStartCampaignStage: onRequestStartCampaignStage
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

private extension GameViewModel {
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
