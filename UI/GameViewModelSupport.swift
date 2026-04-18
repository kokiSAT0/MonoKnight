import Combine
import Foundation
import Game
import SharedSupport
import SwiftUI
import UIKit

// MARK: - GameViewModel split-file action and lifecycle surface

@MainActor
extension GameViewModel {
    typealias BoardTapSelectionWarning = GameBoardTapSelectionWarning

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

    var supportsTimerPausing: Bool {
        pauseController.supportsTimerPausing(for: mode)
    }

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

    func restoreHandOrderingStrategy(from rawValue: String) {
        appearanceSettingsCoordinator.restoreHandOrderingStrategy(from: rawValue, core: core)
    }

    func applyHandOrderingStrategy(rawValue: String) {
        appearanceSettingsCoordinator.applyHandOrderingStrategy(rawValue: rawValue, core: core)
    }

    func updateGameCenterAuthenticationStatus(_ newValue: Bool) {
        sessionServicesCoordinator.updateGameCenterAuthenticationStatus(
            currentValue: isGameCenterAuthenticated,
            newValue: newValue
        ) { [weak self] updatedValue in
            self?.isGameCenterAuthenticated = updatedValue
        }
    }

    func updateGuideMode(enabled: Bool) {
        appearanceSettingsCoordinator.updateGuideMode(
            enabled: enabled,
            boardBridge: boardBridge
        ) { [weak self] updatedValue in
            self?.guideModeEnabled = updatedValue
        }
    }

    func updateHapticsSetting(isEnabled: Bool) {
        appearanceSettingsCoordinator.updateHapticsSetting(
            isEnabled: isEnabled,
            boardBridge: boardBridge
        ) { [weak self] updatedValue in
            self?.hapticsEnabled = updatedValue
        }
    }

    func clearBoardTapSelectionWarning() {
        boardTapSelectionWarning = nil
    }

    func finalizeResultDismissal() {
        applyResultPresentationMutation { state in
            state.hideResult()
        }
    }

    func applyScenePalette(for scheme: ColorScheme) {
        boardBridge.applyScenePalette(for: scheme)
    }

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

    func updateForcedSelectionHighlight(points: Set<GridPoint>) {
        boardBridge.updateForcedSelectionHighlights(points)
    }

    func updateForcedSelectionHighlight(for stack: HandStack?) {
        guard
            let stack,
            let current = core.current,
            let card = stack.topCard
        else {
            boardBridge.updateForcedSelectionHighlights([])
            return
        }

        let snapshotBoard = core.board
        let context = MoveCard.MovePattern.ResolutionContext(
            boardSize: snapshotBoard.size,
            contains: { point in snapshotBoard.contains(point) },
            isTraversable: { point in snapshotBoard.isTraversable(point) },
            isVisited: { point in snapshotBoard.isVisited(point) }
        )
        let availablePaths = card.move.resolvePaths(from: current, context: context)
        boardBridge.updateForcedSelectionHighlights(Set(availablePaths.map(\.destination)))
    }

    func updateDisplayedElapsedTime() {
        appearanceSettingsCoordinator.updateDisplayedElapsedTime(
            liveElapsedSeconds: core.liveElapsedSeconds
        ) { [weak self] seconds in
            self?.applySessionUIMutation { state in
                state.updateDisplayedElapsedTime(seconds)
            }
        }
    }

    func isCardUsable(_ stack: HandStack) -> Bool {
        boardBridge.isCardUsable(stack)
    }

    @discardableResult
    func animateCardPlay(for stack: HandStack, at index: Int) -> Bool {
        boardBridge.animateCardPlay(for: stack, at: index)
    }

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

    func requestManualPenalty() {
        guard isManualPenaltyButtonEnabled else { return }
        applySessionUIMutation { state in
            state.requestManualPenalty(cost: core.mode.manualRedrawPenaltyCost)
        }
    }

    func requestReturnToTitle() {
        applySessionUIMutation { state in
            state.requestReturnToTitle()
        }
    }

    func presentPauseMenu() {
        debugLog("GameViewModel: ポーズメニュー表示要求")
        applySessionUIMutation { state in
            state.presentPauseMenu()
        }
    }

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

    func updateBoardAnchor(_ anchor: Anchor<CGRect>?) {
        boardBridge.updateBoardAnchor(anchor)
    }

    func handleResultRetry() {
        resetSessionForNewPlay()
    }

    func handleResultReturnToTitle() {
        prepareForReturnToTitle()
        onRequestReturnToTitle?()
    }

    func handleCampaignStageAdvance(to stage: CampaignStage) {
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

        sessionServicesCoordinator.handleCampaignStageAdvance(
            to: stage,
            campaignProgressStore: campaignProgressStore,
            onRequestStartCampaignStage: onRequestStartCampaignStage
        )
    }

    func clearSelectedCardSelection() {
        inputFlowCoordinator.clearSelectedCardSelection(
            sessionState: &sessionState,
            boardBridge: boardBridge,
            selectedHandStackID: &selectedHandStackID
        )
    }

    func refreshSelectionIfNeeded(with handStacks: [HandStack]) {
        inputFlowCoordinator.refreshSelectionIfNeeded(
            with: handStacks,
            core: core,
            boardBridge: boardBridge,
            sessionState: &sessionState,
            selectedHandStackID: &selectedHandStackID
        )
    }

    func cancelPenaltyBannerDisplay() {
        penaltyBannerController.cancel { [weak self] banner in
            self?.applySessionUIMutation { state in
                state.setActivePenaltyBanner(banner)
            }
        }
    }

    func prepareForReturnToTitle() {
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

    func resetSessionForNewPlay() {
        sessionResetCoordinator.resetSessionForNewPlay(
            prepareForReturnToTitle: { [self] in prepareForReturnToTitle() },
            resetCore: { [self] in core.reset() },
            resetPauseController: { [self] in pauseController.reset() }
        )
    }

    func bindGameCore() {
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

    func handleProgressChange(_ progress: GameProgress) {
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
}
