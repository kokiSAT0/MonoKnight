import Combine
import Foundation
import Game
import SharedSupport
import SwiftUI
import UIKit

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
}
