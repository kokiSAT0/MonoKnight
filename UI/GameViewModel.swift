import Combine  // Combine を利用して GameCore の更新を ViewModel 経由で伝搬する
import Foundation
import Game
import SharedSupport
import SwiftUI

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
    /// 塔ダンジョンの永続成長ストア
    let dungeonGrowthStore: DungeonGrowthStore
    /// 塔攻略の中断復帰ストア
    let dungeonRunResumeStore: DungeonRunResumeStore
    /// Game Center サインインを再度促す要求を親へ伝えるクロージャ
    let onRequestGameCenterSignIn: ((GameCenterSignInPromptReason) -> Void)?
    /// タイトル復帰時に親へ伝えるためのクロージャ
    let onRequestReturnToTitle: (() -> Void)?
    /// ダンジョンランで次のフロアへ遷移したい場合のリクエストクロージャ
    let onRequestStartDungeonFloor: ((GameMode) -> Void)?

    /// SwiftUI から観測するゲームロジック本体
    @Published private(set) var core: GameCore
    /// 初回描画から使う手札表示用スナップショット
    /// - Note: `core.$handStacks` の初回通知を待たず、塔の持ち越し報酬カードを開始直後から表示する。
    @Published var displayedHandStacks: [HandStack] = []
    static let dungeonInventoryVisibleSlotCount = 9
    static let dungeonBasicMoveSlotIndex = 9
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
    /// 直近の塔クリアで得た成長報酬
    @Published var latestDungeonGrowthAward: DungeonGrowthAward?
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
        if mode.usesTargetCollection {
            return core.moveCount * 10 + displayedElapsedSeconds + core.focusCount * 15
        }
        return core.totalMoveCount * 10 + displayedElapsedSeconds
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
    /// 目的地制で現在狙うマス
    var targetPoint: GridPoint? { core.targetPoint }
    /// 目的地制の先読み
    var upcomingTargetPoints: [GridPoint] { core.upcomingTargetPoints }
    /// 獲得済み目的地数
    var capturedTargetCount: Int { core.capturedTargetCount }
    /// 目標目的地数
    var targetGoalCount: Int { core.targetGoalCount }
    /// 残り目標数
    var remainingTargetCount: Int { core.remainingTargetCount }
    /// フォーカス使用回数
    var focusCount: Int { core.focusCount }
    /// 目的地制モードかどうか
    var usesTargetCollection: Bool { mode.usesTargetCollection }
    /// 出口到達型ダンジョンかどうか
    var usesDungeonExit: Bool { mode.usesDungeonExit }
    /// ダンジョン HP
    var dungeonHP: Int { core.dungeonHP }
    /// ダンジョン残り手数
    var remainingDungeonTurns: Int? { core.remainingDungeonTurns }
    /// ダンジョン手数上限
    var dungeonTurnLimit: Int? { mode.dungeonRules?.failureRule.turnLimit }
    /// ダンジョン出口座標
    var dungeonExitPoint: GridPoint? { mode.dungeonExitPoint }
    /// ダンジョン出口が解錠済みかどうか
    var isDungeonExitUnlocked: Bool { core.isDungeonExitUnlocked }
    /// ダンジョンラン状態
    var dungeonRunState: DungeonRunState? { mode.dungeonMetadataSnapshot?.runState }
    /// ダンジョンランの階層表示
    var dungeonRunFloorText: String? {
        guard let metadata = mode.dungeonMetadataSnapshot,
              let runState = metadata.runState,
              let dungeon = DungeonLibrary.shared.dungeon(with: metadata.dungeonID)
        else { return nil }
        return "\(dungeon.title) \(runState.floorNumber)/\(dungeon.floors.count)F"
    }
    /// リザルトの再挑戦ボタンに表示する開始階
    var dungeonRetryStartFloorText: String? {
        guard let metadata = mode.dungeonMetadataSnapshot,
              let dungeon = DungeonLibrary.shared.dungeon(with: metadata.dungeonID)
        else { return nil }

        let currentFloorIndex = metadata.runState?.currentFloorIndex ?? 0
        let startFloorIndex = dungeon.difficulty == .growth
            ? (currentFloorIndex / 10) * 10
            : 0
        return "\(startFloorIndex + 1)F"
    }
    /// リザルトの再挑戦ボタン文言
    var resultRetryButtonTitle: String {
        guard mode.usesDungeonExit else { return "リトライ" }
        return "\(dungeonRetryStartFloorText ?? "1F")から再挑戦"
    }
    /// ダンジョンランの累計移動手数
    var dungeonRunTotalMoveCount: Int? {
        dungeonRunState?.totalMoveCountIncludingCurrentFloor(core.moveCount)
    }
    /// ラン中に持ち越している報酬カード
    var dungeonRewardInventoryEntries: [DungeonInventoryEntry] {
        core.dungeonInventoryEntries.compactMap { $0.carryingRewardUsesOnly() }
    }
    /// 塔で現在所持しているカード
    var dungeonInventoryEntries: [DungeonInventoryEntry] {
        core.dungeonInventoryEntries
    }
    /// 現在フロアのクリア後に選べる報酬カード
    var availableDungeonRewardMoveCards: [MoveCard] {
        guard !isResultFailed,
              let metadata = mode.dungeonMetadataSnapshot,
              let runState = metadata.runState,
              let dungeon = DungeonLibrary.shared.dungeon(with: metadata.dungeonID),
              dungeon.floors.indices.contains(runState.currentFloorIndex),
              dungeon.canAdvanceWithinRun(afterFloorIndex: runState.currentFloorIndex)
        else { return [] }
        let baseCards = dungeon.resolvedFloor(
            at: runState.currentFloorIndex,
            runState: runState
        )?.rewardMoveCardsAfterClear ?? []
        return dungeonGrowthStore.rewardMoveCards(for: baseCards, dungeon: dungeon)
    }
    /// 現在フロアのクリア後に選べる補助報酬カード
    var availableDungeonRewardSupportCards: [SupportCard] {
        guard !isResultFailed,
              let metadata = mode.dungeonMetadataSnapshot,
              let runState = metadata.runState,
              let dungeon = DungeonLibrary.shared.dungeon(with: metadata.dungeonID),
              dungeon.floors.indices.contains(runState.currentFloorIndex),
              dungeon.canAdvanceWithinRun(afterFloorIndex: runState.currentFloorIndex)
        else { return [] }
        return dungeon.resolvedFloor(
            at: runState.currentFloorIndex,
            runState: runState
        )?.rewardSupportCardsAfterClear ?? []
    }
    /// 旧互換用: 拾得カードはクリア時に自動で次フロアへ持ち越すため、通常 UI では選択候補を出さない
    var carryoverCandidateDungeonPickupEntries: [DungeonInventoryEntry] {
        []
    }
    /// 新しく手札へ追加したカードに付与する使用回数
    var dungeonRewardAddUses: Int {
        guard let metadata = mode.dungeonMetadataSnapshot,
              let dungeon = DungeonLibrary.shared.dungeon(with: metadata.dungeonID)
        else { return 2 }
        return dungeonGrowthStore.rewardAddUses(for: dungeon)
    }
    /// クリア後に強化/整理できる手札の報酬カード
    var adjustableDungeonRewardEntries: [DungeonInventoryEntry] {
        guard !isResultFailed,
              let metadata = mode.dungeonMetadataSnapshot,
              let runState = metadata.runState,
              let dungeon = DungeonLibrary.shared.dungeon(with: metadata.dungeonID),
              dungeon.difficulty == .growth,
              dungeon.canAdvanceWithinRun(afterFloorIndex: runState.currentFloorIndex)
        else { return [] }
        return dungeonRewardInventoryEntries
    }
    /// 次のダンジョンフロア名
    var nextDungeonFloorTitle: String? {
        makeNextDungeonFloorMode()?.displayName
    }
    /// 現在のゲーム進行状態
    /// - Note: GameView 側でオーバーレイ表示を切り替える際に利用する
    var progress: GameProgress { core.progress }
    /// リザルト表示中の失敗状態
    var isResultFailed: Bool { core.progress == .failed }
    /// 失敗理由の短い表示文
    var failureReasonText: String? {
        guard core.progress == .failed else { return nil }
        if mode.usesDungeonExit {
            if core.dungeonHP <= 0 {
                return "HPが0になりました"
            }
            if core.remainingDungeonTurns == 0 {
                return "残り手数が0になりました"
            }
        }
        return "攻略に失敗しました"
    }
    /// ペナルティバナー表示中かどうか
    /// - Note: SwiftUI 側の表示切り替えで利用するシンプルなフラグ
    var isShowingPenaltyBanner: Bool { activePenaltyBanner != nil }
    /// 捨て札選択待機中かどうか
    /// - Note: ボタンのスタイル切り替えに必要な状態をカプセル化する
    var isAwaitingManualDiscardSelection: Bool { core.isAwaitingManualDiscardSelection }
    var pendingDungeonPickupChoice: PendingDungeonPickupChoice? { core.pendingDungeonPickupChoice }
    var presentsBasicMoveCard: Bool {
        mode.usesDungeonExit && mode.dungeonRules?.allowsBasicOrthogonalMove == true
    }
    var isBasicMoveCardSelected: Bool {
        sessionState.isBasicOrthogonalSelected
    }
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
    @Published var boardTapSelectionWarning: GameBoardTapSelectionWarning?
    /// 目的地獲得直後に表示する短いフィードバック
    @Published var targetCaptureFeedback: TargetCaptureFeedback?
    /// HP 低下演出の誤発火を避けるため、直近に観測したダンジョン HP を保持する
    var lastObservedDungeonHPForDamageEffect: Int?
    /// 敵ターン演出へ委譲した HP 低下イベントを重複再生しないために保持する
    var deferredEnemyDamageEventID: UUID?

    /// Combine の購読を保持するセット
    var cancellables = Set<AnyCancellable>()
    /// 目的地獲得フィードバックの自動消滅タスク
    var targetCaptureFeedbackDismissTask: Task<Void, Never>?
    /// ひび割れ床落下後、次フロアへ移るまでの短い待機タスク
    var dungeonFallAdvanceTask: Task<Void, Never>?
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
    /// Game Center / Ads の橋渡しを担当するヘルパー
    let sessionServicesCoordinator: GameSessionServicesCoordinator
    /// リザルト表示の内部状態
    var resultPresentationState = ResultPresentationState()
    /// セッション中の補助 UI 状態
    var sessionUIState = SessionUIState()
    /// チュートリアルイベント検出用の前回移動回数
    var lastTutorialMoveCount: Int = 0
    /// チュートリアルイベント検出用の前回目的地獲得数
    var lastTutorialCapturedTargetCount: Int = 0
    /// チュートリアルイベント検出用の前回フォーカス回数
    var lastTutorialFocusCount: Int = 0
    /// チュートリアルイベント検出用の前回進行状態
    var lastTutorialProgress: GameProgress = .playing

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
        dungeonGrowthStore: @MainActor @autoclosure () -> DungeonGrowthStore = DungeonGrowthStore(),
        dungeonRunResumeStore: @MainActor @autoclosure () -> DungeonRunResumeStore = DungeonRunResumeStore(),
        onRequestGameCenterSignIn: ((GameCenterSignInPromptReason) -> Void)? = nil,
        onRequestReturnToTitle: (() -> Void)?,
        onRequestStartDungeonFloor: ((GameMode) -> Void)? = nil,
        penaltyBannerScheduler: PenaltyBannerScheduling = PenaltyBannerScheduler(),
        initialHandOrderingRawValue: String? = nil,
        initialGameCenterAuthenticationState: Bool = false,
        currentDateProvider: @escaping () -> Date = Date.init
    ) {
        self.mode = mode
        self.gameInterfaces = gameInterfaces
        self.gameCenterService = gameCenterService
        self.adsService = adsService
        self.dungeonGrowthStore = dungeonGrowthStore()
        self.dungeonRunResumeStore = dungeonRunResumeStore()
        self.onRequestGameCenterSignIn = onRequestGameCenterSignIn
        self.onRequestReturnToTitle = onRequestReturnToTitle
        self.onRequestStartDungeonFloor = onRequestStartDungeonFloor
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
        if let snapshot = self.dungeonRunResumeStore.snapshot,
           snapshot.dungeonID == mode.dungeonMetadataSnapshot?.dungeonID {
            let restored = generatedCore.restoreDungeonResumeSnapshot(snapshot)
            if !restored {
                self.dungeonRunResumeStore.clear()
            }
        }
        self.core = generatedCore
        self.displayedHandStacks = Self.visibleHandStacks(from: generatedCore.handStacks, mode: mode)
        self.boardBridge = GameBoardBridgeViewModel(core: generatedCore, mode: mode)
        self.lastTutorialMoveCount = generatedCore.moveCount
        self.lastTutorialCapturedTargetCount = generatedCore.capturedTargetCount
        self.lastTutorialFocusCount = generatedCore.focusCount
        self.lastTutorialProgress = generatedCore.progress

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
        generatedCore.resolvePendingDungeonFallLandingIfNeeded()

        // ユーザー設定から手札並び順を復元する
        if let rawValue = initialHandOrderingRawValue {
            restoreHandOrderingStrategy(from: rawValue)
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
        if core.mode.usesTargetCollection {
            return "表示中の目的地へ近づきやすいカードを優先して手札を整えます。スコアに15ポイント加算されます。"
        }
        return sessionUIState.manualPenaltyAccessibilityHint(
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
