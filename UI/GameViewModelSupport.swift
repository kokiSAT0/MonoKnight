import Combine
import Foundation
import Game
import SharedSupport
import SwiftUI
import UIKit

/// 手札選択と候補ハイライトに関する内部状態
@MainActor
struct GameSessionState {
    /// 手札選択を表す内部モデル
    struct SelectedCardSelection {
        let stackID: UUID
        let cardID: UUID
    }

    private var selectedCardSelection: SelectedCardSelection?

    var hasSelection: Bool {
        selectedCardSelection != nil
    }

    func isSelected(stackID: UUID) -> Bool {
        selectedCardSelection?.stackID == stackID
    }

    mutating func updateSelection(stackID: UUID, cardID: UUID, selectedHandStackID: inout UUID?) {
        selectedCardSelection = SelectedCardSelection(stackID: stackID, cardID: cardID)
        selectedHandStackID = stackID
    }

    func matchingMoves(in core: GameCore) -> [ResolvedCardMove] {
        guard let selection = selectedCardSelection else { return [] }
        return core.availableMoves().filter { candidate in
            candidate.stackID == selection.stackID && candidate.card.id == selection.cardID
        }
    }

    mutating func clearSelection(
        boardBridge: GameBoardBridgeViewModel,
        selectedHandStackID: inout UUID?
    ) {
        let hasSelection = selectedCardSelection != nil || selectedHandStackID != nil
        let hasForcedHighlights = !boardBridge.forcedSelectionHighlightPoints.isEmpty
        guard hasSelection || hasForcedHighlights else { return }

        selectedCardSelection = nil
        selectedHandStackID = nil
        boardBridge.updateForcedSelectionHighlights([])
    }

    mutating func refreshSelectionIfNeeded(
        with handStacks: [HandStack],
        core: GameCore,
        boardBridge: GameBoardBridgeViewModel,
        selectedHandStackID: inout UUID?
    ) {
        guard let selection = selectedCardSelection else { return }

        guard let stack = handStacks.first(where: { $0.id == selection.stackID }),
              let topCard = stack.topCard,
              topCard.id == selection.cardID else {
            clearSelection(boardBridge: boardBridge, selectedHandStackID: &selectedHandStackID)
            return
        }

        applyHighlights(
            core: core,
            boardBridge: boardBridge,
            selectedHandStackID: &selectedHandStackID
        )
    }

    mutating func applyHighlights(
        core: GameCore,
        boardBridge: GameBoardBridgeViewModel,
        using resolvedMoves: [ResolvedCardMove]? = nil,
        selectedHandStackID: inout UUID?
    ) {
        guard let current = core.current,
              let selection = selectedCardSelection else {
            clearSelection(boardBridge: boardBridge, selectedHandStackID: &selectedHandStackID)
            return
        }

        let moves = resolvedMoves ?? core.availableMoves().filter { candidate in
            candidate.stackID == selection.stackID && candidate.card.id == selection.cardID
        }

        guard !moves.isEmpty else {
            clearSelection(boardBridge: boardBridge, selectedHandStackID: &selectedHandStackID)
            return
        }

        let destinations = Set(moves.map(\.destination))
        if moves.first?.card.move == .superWarp {
            boardBridge.updateForcedSelectionHighlights(destinations)
            return
        }

        let vectors = moves.map(\.moveVector)
        boardBridge.updateForcedSelectionHighlights(destinations, origin: current, movementVectors: vectors)
    }
}

/// ペナルティバナー表示の責務をまとめたヘルパー
final class GamePenaltyBannerController {
    private let scheduler: PenaltyBannerScheduling

    init(scheduler: PenaltyBannerScheduling) {
        self.scheduler = scheduler
    }

    func handlePenaltyEvent(
        _ event: PenaltyEvent,
        hapticsEnabled: Bool,
        setActiveBanner: @escaping (PenaltyEvent?) -> Void
    ) {
        scheduler.cancel()

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8, blendDuration: 0.2)) {
            setActiveBanner(event)
        }

        if hapticsEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }

        scheduler.scheduleAutoDismiss(after: 2.6) {
            withAnimation(.easeOut(duration: 0.25)) {
                setActiveBanner(nil)
            }
        }
    }

    func cancel(setActiveBanner: (PenaltyEvent?) -> Void) {
        scheduler.cancel()
        setActiveBanner(nil)
    }
}

/// リザルト表示周辺の UI 状態をまとめる内部ヘルパー
@MainActor
struct ResultPresentationState {
    var showingResult = false
    var latestCampaignClearRecord: CampaignStageClearRecord?
    var newlyUnlockedStages: [CampaignStage] = []

    mutating func applyClearOutcome(_ outcome: GameFlowCoordinator.ClearOutcome) {
        latestCampaignClearRecord = outcome.latestCampaignClearRecord
        newlyUnlockedStages = outcome.newlyUnlockedStages
        showingResult = outcome.shouldShowResult
    }

    mutating func hideResult() {
        showingResult = false
    }
}

/// メニュー確認や一時的な UI 状態をまとめる内部ヘルパー
@MainActor
struct SessionUIState {
    var activePenaltyBanner: PenaltyEvent?
    var pendingMenuAction: GameMenuAction?
    var isPauseMenuPresented = false
    var displayedElapsedSeconds = 0

    mutating func updateDisplayedElapsedTime(_ seconds: Int) {
        displayedElapsedSeconds = seconds
    }

    mutating func presentPauseMenu() {
        isPauseMenuPresented = true
    }

    mutating func setPauseMenuPresented(_ isPresented: Bool) {
        isPauseMenuPresented = isPresented
    }

    mutating func requestManualPenalty(cost: Int) {
        pendingMenuAction = .manualPenalty(penaltyCost: cost)
    }

    mutating func requestReturnToTitle() {
        pendingMenuAction = .returnToTitle
    }

    mutating func clearPendingMenuAction() {
        pendingMenuAction = nil
    }

    mutating func setActivePenaltyBanner(_ event: PenaltyEvent?) {
        activePenaltyBanner = event
    }

    mutating func resetTransientUIForTitleReturn() {
        activePenaltyBanner = nil
        pendingMenuAction = nil
        isPauseMenuPresented = false
    }

    func isManualDiscardButtonEnabled(progress: GameProgress, handStacks: [HandStack]) -> Bool {
        progress == .playing && !handStacks.isEmpty
    }

    func manualDiscardAccessibilityHint(
        penaltyCost: Int,
        isAwaitingManualDiscardSelection: Bool
    ) -> String {
        if isAwaitingManualDiscardSelection {
            return "捨て札モードを終了します。カードを選ばずに通常操作へ戻ります。"
        }

        if penaltyCost > 0 {
            return "手数を\(penaltyCost)消費して、選択した手札 1 種類をまとめて捨て札にし、新しいカードを補充します。"
        } else {
            return "手数を消費せずに、選択した手札 1 種類をまとめて捨て札にし、新しいカードを補充します。"
        }
    }

    func isManualPenaltyButtonEnabled(progress: GameProgress) -> Bool {
        progress == .playing
    }

    func manualPenaltyAccessibilityHint(
        penaltyCost: Int,
        handSize: Int,
        stackingRuleDetailText: String
    ) -> String {
        let refillDescription = "手札スロットを全て空にし、新しいカードを最大 \(handSize) 種類まで補充します。"

        if penaltyCost > 0 {
            return "手数を\(penaltyCost)消費して\(refillDescription)\(stackingRuleDetailText)"
        } else {
            return "手数を消費せずに\(refillDescription)\(stackingRuleDetailText)"
        }
    }
}

/// 手札タップと盤面タップの入力フローをまとめるヘルパー
@MainActor
struct GameInputFlowCoordinator {
    func handleHandSlotTap(
        at index: Int,
        core: GameCore,
        boardBridge: GameBoardBridgeViewModel,
        sessionState: inout GameSessionState,
        selectedHandStackID: inout UUID?,
        hapticsEnabled: Bool
    ) {
        guard boardBridge.animatingCard == nil else { return }
        guard core.handStacks.indices.contains(index) else { return }

        let latestStack = core.handStacks[index]

        if core.isAwaitingManualDiscardSelection {
            clearSelectedCardSelection(
                sessionState: &sessionState,
                boardBridge: boardBridge,
                selectedHandStackID: &selectedHandStackID
            )
            withAnimation(.easeInOut(duration: 0.2)) {
                let success = core.discardHandStack(withID: latestStack.id)
                if success, hapticsEnabled {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                }
            }
            return
        }

        guard let topCard = latestStack.topCard else {
            clearSelectedCardSelection(
                sessionState: &sessionState,
                boardBridge: boardBridge,
                selectedHandStackID: &selectedHandStackID
            )
            return
        }

        if sessionState.isSelected(stackID: latestStack.id) {
            clearSelectedCardSelection(
                sessionState: &sessionState,
                boardBridge: boardBridge,
                selectedHandStackID: &selectedHandStackID
            )
            return
        }

        guard core.progress == .playing else {
            clearSelectedCardSelection(
                sessionState: &sessionState,
                boardBridge: boardBridge,
                selectedHandStackID: &selectedHandStackID
            )
            return
        }

        guard boardBridge.isCardUsable(latestStack) else {
            clearSelectedCardSelection(
                sessionState: &sessionState,
                boardBridge: boardBridge,
                selectedHandStackID: &selectedHandStackID
            )
            if hapticsEnabled {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
            return
        }

        let resolvedMoves = core.availableMoves().filter { candidate in
            candidate.stackID == latestStack.id && candidate.card.id == topCard.id
        }

        guard !resolvedMoves.isEmpty else {
            clearSelectedCardSelection(
                sessionState: &sessionState,
                boardBridge: boardBridge,
                selectedHandStackID: &selectedHandStackID
            )
            return
        }

        if resolvedMoves.count == 1, let singleMove = resolvedMoves.first {
            clearSelectedCardSelection(
                sessionState: &sessionState,
                boardBridge: boardBridge,
                selectedHandStackID: &selectedHandStackID
            )
            _ = boardBridge.animateCardPlay(using: singleMove)
            return
        }

        sessionState.updateSelection(
            stackID: latestStack.id,
            cardID: topCard.id,
            selectedHandStackID: &selectedHandStackID
        )
        sessionState.applyHighlights(
            core: core,
            boardBridge: boardBridge,
            using: resolvedMoves,
            selectedHandStackID: &selectedHandStackID
        )
    }

    func handleBoardTapPlayRequest(
        _ request: BoardTapPlayRequest,
        core: GameCore,
        boardBridge: GameBoardBridgeViewModel,
        sessionState: inout GameSessionState,
        selectedHandStackID: inout UUID?,
        hapticsEnabled: Bool,
        presentBoardTapSelectionWarning: (String, GridPoint) -> Void
    ) {
        defer { core.clearBoardTapPlayRequest(request.id) }

        guard boardBridge.animatingCard == nil else { return }

        guard sessionState.hasSelection else {
            let availableMoves = core.availableMoves()
            let destinationCandidates = availableMoves.filter { $0.destination == request.destination }
            let containsSingleVectorCard = destinationCandidates.contains { candidate in
                candidate.card.move.movementVectors.count == 1
            }
            let conflictingStackIDs = Set(destinationCandidates.map(\.stackID))

            if conflictingStackIDs.count >= 2 && !containsSingleVectorCard {
                presentBoardTapSelectionWarning(
                    "複数のカードが同じマスを指定しています。手札から使いたいカードを選んでからマスをタップしてください。",
                    request.destination
                )

                if hapticsEnabled {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                }
                return
            }

            if request.resolvedMove.card.move == .superWarp {
                presentBoardTapSelectionWarning(
                    "全域ワープカードを使うには、先に手札からカードを選択してください。",
                    request.destination
                )

                if hapticsEnabled {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                }
                return
            }

            let didStart = boardBridge.animateCardPlay(using: request.resolvedMove)
            if didStart {
                clearSelectedCardSelection(
                    sessionState: &sessionState,
                    boardBridge: boardBridge,
                    selectedHandStackID: &selectedHandStackID
                )
            }
            return
        }

        let matchingMoves = sessionState.matchingMoves(in: core)

        guard !matchingMoves.isEmpty else {
            clearSelectedCardSelection(
                sessionState: &sessionState,
                boardBridge: boardBridge,
                selectedHandStackID: &selectedHandStackID
            )
            return
        }

        guard let chosenMove = matchingMoves.first(where: { $0.destination == request.destination }) else {
            sessionState.applyHighlights(
                core: core,
                boardBridge: boardBridge,
                using: matchingMoves,
                selectedHandStackID: &selectedHandStackID
            )
            return
        }

        let didStart = boardBridge.animateCardPlay(using: chosenMove)
        if didStart {
            clearSelectedCardSelection(
                sessionState: &sessionState,
                boardBridge: boardBridge,
                selectedHandStackID: &selectedHandStackID
            )
        } else {
            sessionState.applyHighlights(
                core: core,
                boardBridge: boardBridge,
                using: matchingMoves,
                selectedHandStackID: &selectedHandStackID
            )
        }
    }

    func refreshSelectionIfNeeded(
        with handStacks: [HandStack],
        core: GameCore,
        boardBridge: GameBoardBridgeViewModel,
        sessionState: inout GameSessionState,
        selectedHandStackID: inout UUID?
    ) {
        sessionState.refreshSelectionIfNeeded(
            with: handStacks,
            core: core,
            boardBridge: boardBridge,
            selectedHandStackID: &selectedHandStackID
        )
    }

    func clearSelectedCardSelection(
        sessionState: inout GameSessionState,
        boardBridge: GameBoardBridgeViewModel,
        selectedHandStackID: inout UUID?
    ) {
        sessionState.clearSelection(
            boardBridge: boardBridge,
            selectedHandStackID: &selectedHandStackID
        )
    }
}

/// GameCore 購読登録と progress 起点の副作用をまとめるヘルパー
@MainActor
struct GameCoreBindingCoordinator {
    func bind(
        core: GameCore,
        cancellables: inout Set<AnyCancellable>,
        onPenaltyEvent: @escaping (PenaltyEvent) -> Void,
        onHandStacksChange: @escaping ([HandStack]) -> Void,
        onBoardTapPlayRequest: @escaping (BoardTapPlayRequest) -> Void,
        onProgressChange: @escaping (GameProgress) -> Void,
        onElapsedTimeChange: @escaping () -> Void
    ) {
        core.$penaltyEvent
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { event in
                guard let event else { return }
                onPenaltyEvent(event)
            }
            .store(in: &cancellables)

        core.$handStacks
            .receive(on: RunLoop.main)
            .sink { newHandStacks in
                onHandStacksChange(newHandStacks)
            }
            .store(in: &cancellables)

        core.$boardTapPlayRequest
            .receive(on: RunLoop.main)
            .sink { request in
                guard let request else { return }
                onBoardTapPlayRequest(request)
            }
            .store(in: &cancellables)

        core.$progress
            .receive(on: RunLoop.main)
            .sink { progress in
                onProgressChange(progress)
            }
            .store(in: &cancellables)

        core.$elapsedSeconds
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { _ in
                onElapsedTimeChange()
            }
            .store(in: &cancellables)
    }

    func handleProgressChange(
        _ progress: GameProgress,
        boardBridge: GameBoardBridgeViewModel,
        updateDisplayedElapsedTime: () -> Void,
        clearSelectedCardSelection: () -> Void,
        resolveClearOutcome: () -> GameFlowCoordinator.ClearOutcome?,
        applyClearOutcome: (GameFlowCoordinator.ClearOutcome) -> Void
    ) {
        debugLog("進行状態の更新を受信: 状態=\(String(describing: progress))")

        updateDisplayedElapsedTime()
        boardBridge.handleProgressChange(progress)

        if progress != .playing {
            clearSelectedCardSelection()
        }

        guard progress == .cleared, let outcome = resolveClearOutcome() else { return }
        applyClearOutcome(outcome)
    }
}

/// タイトル復帰と新規プレイ開始時の UI 後始末をまとめるヘルパー
@MainActor
struct GameSessionResetCoordinator {
    func prepareForReturnToTitle(
        clearSelectedCardSelection: () -> Void,
        cancelPenaltyBannerDisplay: () -> Void,
        hideResult: () -> Void,
        resetTransientUI: () -> Void,
        clearBoardTapSelectionWarning: () -> Void,
        resetAdsPlayFlag: () -> Void,
        resetPauseController: () -> Void
    ) {
        clearSelectedCardSelection()
        cancelPenaltyBannerDisplay()
        hideResult()
        resetTransientUI()
        clearBoardTapSelectionWarning()
        resetAdsPlayFlag()
        resetPauseController()
    }

    func resetSessionForNewPlay(
        prepareForReturnToTitle: () -> Void,
        resetCore: () -> Void,
        resetPauseController: () -> Void
    ) {
        prepareForReturnToTitle()
        resetCore()
        resetPauseController()
    }

    func prepareForCampaignStageAdvance(
        cancelPenaltyBannerDisplay: () -> Void,
        hideResult: () -> Void,
        resetTransientUI: () -> Void,
        clearBoardTapSelectionWarning: () -> Void,
        resetAdsPlayFlag: () -> Void
    ) {
        cancelPenaltyBannerDisplay()
        hideResult()
        resetTransientUI()
        clearBoardTapSelectionWarning()
        resetAdsPlayFlag()
    }
}

/// 初期表示準備と設定同期をまとめるヘルパー
@MainActor
struct GameAppearanceSettingsCoordinator {
    func restoreHandOrderingStrategy(from rawValue: String, core: GameCore) {
        guard let strategy = HandOrderingStrategy(rawValue: rawValue) else { return }
        core.updateHandOrderingStrategy(strategy)
    }

    func applyHandOrderingStrategy(rawValue: String, core: GameCore) {
        let strategy = HandOrderingStrategy(rawValue: rawValue) ?? .insertionOrder
        core.updateHandOrderingStrategy(strategy)
    }

    func updateGuideMode(
        enabled: Bool,
        boardBridge: GameBoardBridgeViewModel,
        setGuideModeEnabled: (Bool) -> Void
    ) {
        setGuideModeEnabled(enabled)
        boardBridge.updateGuideMode(enabled: enabled)
    }

    func updateHapticsSetting(
        isEnabled: Bool,
        boardBridge: GameBoardBridgeViewModel,
        setHapticsEnabled: (Bool) -> Void
    ) {
        setHapticsEnabled(isEnabled)
        boardBridge.updateHapticsSetting(isEnabled: isEnabled)
    }

    func updateDisplayedElapsedTime(
        liveElapsedSeconds: Int,
        applySessionUIMutation: (Int) -> Void
    ) {
        applySessionUIMutation(liveElapsedSeconds)
    }

    func prepareForAppear(
        colorScheme: ColorScheme,
        guideModeEnabled: Bool,
        hapticsEnabled: Bool,
        handOrderingStrategy: HandOrderingStrategy,
        isPreparationOverlayVisible: Bool,
        boardBridge: GameBoardBridgeViewModel,
        core: GameCore,
        updateGuideMode: (Bool) -> Void,
        updateHapticsSetting: (Bool) -> Void,
        updateDisplayedElapsedTime: () -> Void,
        handlePreparationOverlayChange: (Bool) -> Void
    ) {
        boardBridge.prepareForAppear(
            colorScheme: colorScheme,
            guideModeEnabled: guideModeEnabled,
            hapticsEnabled: hapticsEnabled
        )
        updateHapticsSetting(hapticsEnabled)
        updateGuideMode(guideModeEnabled)
        updateDisplayedElapsedTime()
        core.updateHandOrderingStrategy(handOrderingStrategy)
        handlePreparationOverlayChange(isPreparationOverlayVisible)
    }
}

/// Game Center / CampaignProgress / Ads の橋渡しをまとめるヘルパー
@MainActor
struct GameSessionServicesCoordinator {
    func updateGameCenterAuthenticationStatus(
        currentValue: Bool,
        newValue: Bool,
        setAuthenticationStatus: (Bool) -> Void
    ) {
        guard currentValue != newValue else { return }
        debugLog("GameViewModel: Game Center 認証状態が更新されました -> \(newValue)")
        setAuthenticationStatus(newValue)
    }

    func makeCampaignPauseSummary(
        mode: GameMode,
        campaignLibrary: CampaignLibrary,
        campaignProgressStore: CampaignProgressStore
    ) -> CampaignPauseSummary? {
        guard let metadata = mode.campaignMetadataSnapshot else {
            return nil
        }
        let stageID = metadata.stageID
        guard let stage = campaignLibrary.stage(with: stageID) else {
            debugLog("GameViewModel: キャンペーンステージ定義が見つかりません stageID=\(stageID.displayCode)")
            return nil
        }
        let progress = campaignProgressStore.progress(for: stage.id)
        return CampaignPauseSummary(stage: stage, progress: progress)
    }

    func resolveClearOutcome(
        mode: GameMode,
        core: GameCore,
        isGameCenterAuthenticated: Bool,
        flowCoordinator: GameFlowCoordinator,
        gameCenterService: GameCenterServiceProtocol,
        onRequestGameCenterSignIn: ((GameCenterSignInPromptReason) -> Void)?,
        campaignProgressStore: CampaignProgressStore
    ) -> GameFlowCoordinator.ClearOutcome {
        flowCoordinator.handleClearedProgress(
            mode: mode,
            core: core,
            isGameCenterAuthenticated: isGameCenterAuthenticated,
            gameCenterService: gameCenterService,
            onRequestGameCenterSignIn: onRequestGameCenterSignIn,
            campaignProgressStore: campaignProgressStore
        )
    }

    func resetAdsPlayFlag(using adsService: AdsServiceProtocol) {
        adsService.resetPlayFlag()
    }

    func handleCampaignStageAdvance(
        to stage: CampaignStage,
        campaignProgressStore: CampaignProgressStore,
        onRequestStartCampaignStage: ((CampaignStage) -> Void)?
    ) {
        guard campaignProgressStore.isStageUnlocked(stage) else { return }
        onRequestStartCampaignStage?(stage)
    }
}

/// タイマー停止理由と復帰条件を一元管理するヘルパー
final class GamePauseController {
    private(set) var isTimerPausedForMenu = false
    private(set) var isTimerPausedForScenePhase = false
    private(set) var shouldPresentPauseMenuAfterScenePhaseResume = false
    private(set) var isTimerPausedForPreparationOverlay = false

    func supportsTimerPausing(for mode: GameMode) -> Bool {
        !mode.isLeaderboardEligible && mode.campaignMetadataSnapshot != nil
    }

    func reset() {
        isTimerPausedForMenu = false
        isTimerPausedForScenePhase = false
        shouldPresentPauseMenuAfterScenePhaseResume = false
        isTimerPausedForPreparationOverlay = false
    }

    func handleScenePhaseChange(
        _ newPhase: ScenePhase,
        supportsTimerPausing: Bool,
        progress: GameProgress,
        pauseTimer: () -> Void,
        presentPauseMenu: () -> Void
    ) {
        guard supportsTimerPausing else { return }

        switch newPhase {
        case .inactive, .background:
            guard !isTimerPausedForScenePhase, progress == .playing else { return }
            pauseTimer()
            isTimerPausedForScenePhase = true
            shouldPresentPauseMenuAfterScenePhaseResume = true

        case .active:
            guard isTimerPausedForScenePhase else {
                shouldPresentPauseMenuAfterScenePhaseResume = false
                return
            }

            guard shouldPresentPauseMenuAfterScenePhaseResume else { return }

            guard progress == .playing else {
                shouldPresentPauseMenuAfterScenePhaseResume = false
                isTimerPausedForScenePhase = false
                return
            }

            guard !isTimerPausedForMenu, !isTimerPausedForPreparationOverlay else {
                return
            }

            shouldPresentPauseMenuAfterScenePhaseResume = false
            presentPauseMenu()

        @unknown default:
            break
        }
    }

    func handlePreparationOverlayChange(
        isVisible: Bool,
        supportsTimerPausing: Bool,
        progress: GameProgress,
        pauseTimer: () -> Void,
        resumeTimer: () -> Void,
        presentPauseMenu: () -> Void
    ) {
        guard supportsTimerPausing else { return }

        if isVisible {
            guard !isTimerPausedForPreparationOverlay else { return }
            isTimerPausedForPreparationOverlay = true

            guard !isTimerPausedForMenu, !isTimerPausedForScenePhase, progress == .playing else { return }
            pauseTimer()
        } else {
            guard isTimerPausedForPreparationOverlay else { return }
            isTimerPausedForPreparationOverlay = false

            if isTimerPausedForScenePhase,
               shouldPresentPauseMenuAfterScenePhaseResume,
               progress == .playing {
                presentPauseMenu()
                return
            }

            guard !isTimerPausedForMenu, !isTimerPausedForScenePhase, progress == .playing else { return }
            resumeTimer()
        }
    }

    func handlePauseMenuVisibilityChange(
        isPresented: Bool,
        supportsTimerPausing: Bool,
        progress: GameProgress,
        pauseTimer: () -> Void,
        resumeTimer: () -> Void
    ) {
        guard supportsTimerPausing else { return }

        if isPresented {
            guard progress == .playing else { return }
            guard !isTimerPausedForMenu else { return }
            if !isTimerPausedForScenePhase {
                pauseTimer()
            }
            isTimerPausedForMenu = true
        } else {
            guard isTimerPausedForMenu else { return }
            let wasMenuPauseActive = isTimerPausedForMenu
            isTimerPausedForMenu = false
            let wasScenePhasePauseActive = isTimerPausedForScenePhase
            isTimerPausedForScenePhase = false
            shouldPresentPauseMenuAfterScenePhaseResume = false
            guard !isTimerPausedForPreparationOverlay else { return }
            guard progress == .playing else { return }
            guard wasScenePhasePauseActive || wasMenuPauseActive else { return }
            resumeTimer()
        }
    }
}

/// リザルト表示とキャンペーン進捗更新の責務をまとめたヘルパー
@MainActor
final class GameFlowCoordinator {
    struct ClearOutcome {
        let latestCampaignClearRecord: CampaignStageClearRecord?
        let newlyUnlockedStages: [CampaignStage]
        let shouldShowResult: Bool
    }

    private let campaignLibrary = CampaignLibrary.shared

    func handleClearedProgress(
        mode: GameMode,
        core: GameCore,
        isGameCenterAuthenticated: Bool,
        gameCenterService: GameCenterServiceProtocol,
        onRequestGameCenterSignIn: ((GameCenterSignInPromptReason) -> Void)?,
        campaignProgressStore: CampaignProgressStore
    ) -> ClearOutcome {
        if mode.isLeaderboardEligible {
            if isGameCenterAuthenticated {
                gameCenterService.submitScore(core.score, for: mode.identifier)
            } else {
                debugLog("GameViewModel: Game Center 未認証のためスコア送信をスキップしました")
                onRequestGameCenterSignIn?(.scoreSubmissionSkipped)
            }
        }

        guard let metadata = mode.campaignMetadataSnapshot,
              let stage = campaignLibrary.stage(with: metadata.stageID) else {
            return ClearOutcome(
                latestCampaignClearRecord: nil,
                newlyUnlockedStages: [],
                shouldShowResult: true
            )
        }

        let unlockedStageIDsBefore = Set(
            campaignLibrary.allStages
                .filter { campaignProgressStore.isStageUnlocked($0) }
                .map(\.id)
        )

        let metrics = CampaignStageClearMetrics(
            moveCount: core.moveCount,
            penaltyCount: core.penaltyCount,
            elapsedSeconds: core.elapsedSeconds,
            totalMoveCount: core.totalMoveCount,
            score: core.score,
            hasRevisitedTile: core.hasRevisitedTile
        )

        let record = campaignProgressStore.registerClear(for: stage, metrics: metrics)
        let unlockedStagesAfter = campaignLibrary.allStages.filter { campaignProgressStore.isStageUnlocked($0) }
        let unlockedDiff = unlockedStagesAfter.filter { !unlockedStageIDsBefore.contains($0.id) }

        let newlyUnlockedStages: [CampaignStage]
        if unlockedDiff.isEmpty {
            newlyUnlockedStages = campaignLibrary.allStages.filter { stage in
                campaignProgressStore.isStageUnlocked(stage) &&
                    (campaignProgressStore.progress(for: stage.id)?.earnedStars ?? 0) == 0
            }
        } else {
            newlyUnlockedStages = unlockedDiff
        }

        return ClearOutcome(
            latestCampaignClearRecord: record,
            newlyUnlockedStages: newlyUnlockedStages,
            shouldShowResult: true
        )
    }
}
