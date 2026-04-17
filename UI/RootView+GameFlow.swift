import SwiftUI
import SharedSupport
import Game

extension RootView {
    func handleGameCenterSignInRequest(reason: GameCenterSignInPromptReason) {
        gameCenterPromptPresenter.presentPrompt(for: reason, stateStore: stateStore)
    }

    func startGamePreparation(for mode: GameMode, context: GamePreparationContext) {
        preparationCoordinator.startPreparation(for: mode, context: context, stateStore: stateStore)
    }

    func handleReturnToTitleRequest() {
        titleFlowCoordinator.handleReturnToTitleRequest(
            stateStore: stateStore,
            preparationCoordinator: preparationCoordinator
        )
    }

    func handleReturnToCampaignStageSelectionRequest() {
        titleFlowCoordinator.handleReturnToCampaignStageSelectionRequest(
            stateStore: stateStore,
            preparationCoordinator: preparationCoordinator
        )
    }

    func cancelPendingGameActivationWorkItem() {
        preparationCoordinator.cancelPendingGameActivationWorkItem(stateStore: stateStore)
    }

    func finishGamePreparationAndStart() {
        preparationCoordinator.finishPreparationAndStart(stateStore: stateStore)
    }

    func handleGameCenterAuthenticationRequest(completion: @escaping (Bool) -> Void) {
        gameCenterPromptPresenter.requestAuthentication(
            stateStore: stateStore,
            gameCenterService: gameCenterService,
            completion: completion
        )
    }
}
