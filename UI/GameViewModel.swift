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
    /// 遊び方辞典の発見状態ストア
    let encyclopediaDiscoveryStore: EncyclopediaDiscoveryStore
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
    /// 移動演出中だけ利用する HP 表示上書き
    @Published var movementPresentationDungeonHP: Int?
    /// 移動演出中は手札/HP の通常同期を一時停止する
    var isMovementPresentationActive = false
    /// 移動演出が終わってから反映する進行状態
    var deferredProgressDuringMovementPresentation: GameProgress?
    /// 移動演出が終わってから反映する落下イベント
    var deferredDungeonFallEventDuringMovementPresentation: DungeonFallEvent?
    /// 移動後に保留された敵ターンが終わるまで結果表示を待つかどうか
    var isWaitingForEnemyTurnPresentationAfterMovement = false
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
    /// 取得直後に詳細表示する遺物/宝箱結果
    @Published var activeDungeonRelicAcquisitionPresentation: DungeonRelicAcquisitionPresentation?
    var pendingDungeonRelicAcquisitionPresentations: [DungeonRelicAcquisitionPresentation] = []
    var observedDungeonRelicAcquisitionPresentationIDs: Set<UUID> = []
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
    /// 出口到達型ダンジョンかどうか
    var usesDungeonExit: Bool { mode.usesDungeonExit }
    /// ダンジョン HP
    var dungeonHP: Int { movementPresentationDungeonHP ?? core.dungeonHP }
    /// ダンジョン残り手数
    var remainingDungeonTurns: Int? { core.remainingDungeonTurns }
    /// ダンジョン手数上限
    var dungeonTurnLimit: Int? { core.effectiveDungeonTurnLimit }
    /// 凍結の呪文で停止している敵ターンの残り回数
    var enemyFreezeTurnsRemaining: Int { core.enemyFreezeTurnsRemaining }
    /// 障壁の呪文で HP ダメージを無効化できる残り回数
    var damageBarrierTurnsRemaining: Int { core.damageBarrierTurnsRemaining }
    /// 足枷罠で現在フロア中の全行動が重くなっているかどうか
    var isShackled: Bool { core.isShackled }
    /// 毒状態の残りダメージ回数
    var poisonDamageTicksRemaining: Int { core.poisonDamageTicksRemaining }
    /// 次の毒ダメージまでの成功行動数
    var poisonActionsUntilNextDamage: Int { core.poisonActionsUntilNextDamage }
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
        availableDungeonRewardOffers.compactMap(\.move)
    }
    /// 現在フロアのクリア後に選べる報酬カードを、移動/補助/遺物を同じ枠として返す
    var availableDungeonRewardOffers: [DungeonRewardOffer] {
        guard !isResultFailed,
              let metadata = mode.dungeonMetadataSnapshot,
              let runState = metadata.runState,
              let dungeon = DungeonLibrary.shared.dungeon(with: metadata.dungeonID),
              dungeon.floors.indices.contains(runState.currentFloorIndex),
              dungeon.canAdvanceWithinRun(afterFloorIndex: runState.currentFloorIndex)
        else { return [] }
        let floor = dungeon.resolvedFloor(
            at: runState.currentFloorIndex,
            runState: runState
        )
        let baseRewardCount = (floor?.rewardMoveCardsAfterClear.count ?? 0)
            + (floor?.rewardSupportCardsAfterClear.count ?? 0)
        let rewardChoiceBonus =
            (core.dungeonRelicEntries.contains { $0.relicID == .victoryBanner } ? 1 : 0) +
            (core.dungeonCurseEntries.contains { $0.curseID == .crackedCompass } ? 1 : 0)
        let rewardCount = min(baseRewardCount + rewardChoiceBonus, 4)
        guard rewardCount > 0 else { return [] }

        let tuning = DungeonRewardDrawTuning(
            clearMoveCount: core.moveCount,
            turnLimit: core.effectiveDungeonTurnLimit
        )
        let ownedRelics = Set(core.dungeonRelicEntries.map(\.relicID))
        let baseOffers: [DungeonRewardOffer]
        if dungeon.difficulty == .growth,
           let seed = runState.cardVariationSeed {
            let drawnOffers = DungeonWeightedRewardPools.drawUniqueOffers(
                from: DungeonWeightedRewardPools.entries(floorIndex: runState.currentFloorIndex, context: .clearReward),
                context: .clearReward,
                count: rewardCount,
                seed: seed,
                floorIndex: runState.currentFloorIndex,
                salt: 0xA11D,
                tuning: tuning,
                excludingRelics: ownedRelics
            )
            let fallbackOffers = ((floor?.rewardMoveCardsAfterClear ?? []).map { DungeonRewardOffer.playable(.move($0)) })
                + ((floor?.rewardSupportCardsAfterClear ?? []).map { DungeonRewardOffer.playable(.support($0)) })
            baseOffers = drawnOffers + fallbackOffers.filter { !drawnOffers.contains($0) }.prefix(max(rewardCount - drawnOffers.count, 0))
        } else {
            baseOffers = ((floor?.rewardMoveCardsAfterClear ?? []).map { DungeonRewardOffer.playable(.move($0)) })
                + ((floor?.rewardSupportCardsAfterClear ?? []).map { DungeonRewardOffer.playable(.support($0)) })
        }
        return dungeonGrowthStore.rewardOffers(
            for: baseOffers,
            dungeon: dungeon,
            floorIndex: runState.currentFloorIndex,
            seed: runState.cardVariationSeed,
            tuning: tuning,
            ownedRelics: ownedRelics,
            minimumChoiceCount: rewardCount
        )
    }
    /// 現在フロアのクリア後に選べる報酬カードを、移動/補助を同じ3択枠として返す
    var availableDungeonRewardCards: [PlayableCard] {
        availableDungeonRewardOffers.compactMap(\.playable)
    }
    /// 満杯時でも既存カードの重ね取りは許可し、新規種類だけを止める
    func canAddDungeonRewardMoveCard(_ card: MoveCard) -> Bool {
        canAddDungeonRewardPlayable(.move(card))
    }
    /// 現在フロアのクリア後に選べる補助報酬カード
    var availableDungeonRewardSupportCards: [SupportCard] {
        availableDungeonRewardOffers.compactMap(\.support)
    }
    /// 満杯時でも既存補助カードの重ね取りは許可し、新規種類だけを止める
    func canAddDungeonRewardSupportCard(_ support: SupportCard) -> Bool {
        canAddDungeonRewardPlayable(.support(support))
    }
    /// 拾得カードはクリア時に自動で次フロアへ持ち越すため、通常 UI では選択候補を出さない
    var carryoverCandidateDungeonPickupEntries: [DungeonInventoryEntry] {
        []
    }
    /// 新しく手札へ追加したカードに付与する使用回数
    var dungeonRewardAddUses: Int {
        guard let metadata = mode.dungeonMetadataSnapshot,
              let dungeon = DungeonLibrary.shared.dungeon(with: metadata.dungeonID)
        else { return 2 }
        let heavyCrownBonus = core.dungeonRelicEntries.contains { $0.relicID == .heavyCrown } ? 1 : 0
        let cursedCrownBonus = core.dungeonCurseEntries.contains { $0.curseID == .cursedCrown } ? 2 : 0
        let cursePenalty = core.dungeonCurseEntries.contains { $0.curseID == .bloodPact && $0.remainingUses > 0 } ? 1 : 0
        let warpedHourglassPenalty = core.dungeonCurseEntries.contains { $0.curseID == .warpedHourglass } ? 1 : 0
        let greedyBagPenalty = core.dungeonCurseEntries.contains { $0.curseID == .greedyBag } ? 2 : 0
        return max(dungeonGrowthStore.rewardAddUses(for: dungeon) + heavyCrownBonus + cursedCrownBonus - cursePenalty - warpedHourglassPenalty - greedyBagPenalty, 1)
    }
    /// クリア後に強化/整理できる手札の報酬カード
    var adjustableDungeonRewardEntries: [DungeonInventoryEntry] {
        guard !isResultFailed,
              let metadata = mode.dungeonMetadataSnapshot,
              let runState = metadata.runState,
              let dungeon = DungeonLibrary.shared.dungeon(with: metadata.dungeonID),
              dungeon.canAdvanceWithinRun(afterFloorIndex: runState.currentFloorIndex)
        else { return [] }
        return dungeonInventoryEntries.filter(\.hasUsesRemaining)
    }
    private func canAddDungeonRewardPlayable(_ playable: PlayableCard) -> Bool {
        let liveEntries = dungeonInventoryEntries.filter(\.hasUsesRemaining)
        if liveEntries.contains(where: { $0.playable == playable }) {
            return true
        }
        return liveEntries.count < 9
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
    /// 将来の試練塔でスコア送信対象にするかどうか
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
    /// HP 低下演出の誤発火を避けるため、直近に観測したダンジョン HP を保持する
    var lastObservedDungeonHPForDamageEffect: Int?
    /// 敵ターン演出へ委譲した HP 低下イベントを重複再生しないために保持する
    var deferredEnemyDamageEventID: UUID?

    /// Combine の購読を保持するセット
    var cancellables = Set<AnyCancellable>()
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
        encyclopediaDiscoveryStore: @MainActor @autoclosure () -> EncyclopediaDiscoveryStore = EncyclopediaDiscoveryStore(),
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
        self.encyclopediaDiscoveryStore = encyclopediaDiscoveryStore()
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
        self.boardBridge.onMovementPresentationStarted = { [weak self] resolution in
            self?.beginMovementPresentation(using: resolution)
        }
        self.boardBridge.onMovementPresentationStep = { [weak self] step in
            self?.applyMovementPresentationStep(step)
        }
        self.boardBridge.onMovementPresentationFinished = { [weak self] in
            self?.finishMovementPresentation()
        }
        self.boardBridge.onEnemyTurnDamageResolved = { [weak self] event in
            self?.applyEnemyTurnDamagePresentation(event)
        }
        self.boardBridge.onEnemyTurnAnimationFinished = { [weak self] event in
            self?.finishEnemyTurnPresentation(event)
        }
        self.lastTutorialMoveCount = generatedCore.moveCount
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
        recordInitialEncyclopediaDiscoveries()
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
