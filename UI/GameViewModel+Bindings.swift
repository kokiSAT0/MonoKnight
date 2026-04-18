import Combine
import Foundation
import Game

@MainActor
extension GameViewModel {
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
