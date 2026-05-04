import Combine
import Foundation
import Game
import SharedSupport
import SwiftUI

@MainActor
struct GameCoreBindingCoordinator {
    func bind(
        core: GameCore,
        cancellables: inout Set<AnyCancellable>,
        onPenaltyEvent: @escaping (PenaltyEvent) -> Void,
        onHandStacksChange: @escaping ([HandStack]) -> Void,
        onBoardTapPlayRequest: @escaping (BoardTapPlayRequest) -> Void,
        onBoardTapBasicMoveRequest: @escaping (BoardTapBasicMoveRequest) -> Void,
        onSpawnSelectionWarning: @escaping (SpawnSelectionWarning) -> Void,
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

        core.$boardTapBasicMoveRequest
            .receive(on: RunLoop.main)
            .sink { request in
                guard let request else { return }
                onBoardTapBasicMoveRequest(request)
            }
            .store(in: &cancellables)

        core.$spawnSelectionWarning
            .receive(on: RunLoop.main)
            .sink { warning in
                guard let warning else { return }
                onSpawnSelectionWarning(warning)
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

        if progress == .failed {
            applyClearOutcome(
                GameFlowCoordinator.ClearOutcome(
                    shouldShowResult: true
                )
            )
            return
        }

        guard progress == .cleared, let outcome = resolveClearOutcome() else { return }
        applyClearOutcome(outcome)
    }
}

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

    func prepareForDungeonAdvance(
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

    func resolveClearOutcome(
        mode: GameMode,
        core: GameCore,
        isGameCenterAuthenticated: Bool,
        flowCoordinator: GameFlowCoordinator,
        gameCenterService: GameCenterServiceProtocol,
        onRequestGameCenterSignIn: ((GameCenterSignInPromptReason) -> Void)?
    ) -> GameFlowCoordinator.ClearOutcome {
        flowCoordinator.handleClearedProgress(
            mode: mode,
            core: core,
            isGameCenterAuthenticated: isGameCenterAuthenticated,
            gameCenterService: gameCenterService,
            onRequestGameCenterSignIn: onRequestGameCenterSignIn
        )
    }

    func resetAdsPlayFlag(using adsService: AdsServiceProtocol) {
        adsService.resetPlayFlag()
    }

}

final class GamePauseController {
    private(set) var isTimerPausedForMenu = false
    private(set) var isTimerPausedForScenePhase = false
    private(set) var shouldPresentPauseMenuAfterScenePhaseResume = false
    private(set) var isTimerPausedForPreparationOverlay = false

    func supportsTimerPausing(for mode: GameMode) -> Bool {
        !mode.isLeaderboardEligible && mode.usesDungeonExit
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

@MainActor
final class GameFlowCoordinator {
    struct ClearOutcome {
        let shouldShowResult: Bool
    }

    func handleClearedProgress(
        mode: GameMode,
        core: GameCore,
        isGameCenterAuthenticated: Bool,
        gameCenterService: GameCenterServiceProtocol,
        onRequestGameCenterSignIn: ((GameCenterSignInPromptReason) -> Void)?
    ) -> ClearOutcome {
        if mode.isLeaderboardEligible {
            if isGameCenterAuthenticated {
                gameCenterService.submitScore(core.score, for: mode.identifier)
            } else {
                debugLog("GameViewModel: Game Center 未認証のためスコア送信をスキップしました")
                onRequestGameCenterSignIn?(.scoreSubmissionSkipped)
            }
        }

        return ClearOutcome(shouldShowResult: true)
    }
}
