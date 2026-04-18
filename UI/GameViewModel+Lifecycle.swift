import Foundation
import Game
import SwiftUI

@MainActor
extension GameViewModel {
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

    func updateDisplayedElapsedTime() {
        appearanceSettingsCoordinator.updateDisplayedElapsedTime(
            liveElapsedSeconds: core.liveElapsedSeconds
        ) { [weak self] seconds in
            self?.applySessionUIMutation { state in
                state.updateDisplayedElapsedTime(seconds)
            }
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

    func updateBoardAnchor(_ anchor: Anchor<CGRect>?) {
        boardBridge.updateBoardAnchor(anchor)
    }
}
