import Foundation
import Game

@MainActor
extension GameViewModel {
    func updateForcedSelectionHighlight(points: Set<GridPoint>) {
        boardBridge.updateForcedSelectionHighlights(points)
    }

    func updateForcedSelectionHighlight(for stack: HandStack?) {
        guard
            let stack,
            core.current != nil,
            let card = stack.topCard
        else {
            boardBridge.updateForcedSelectionHighlights([])
            return
        }

        let destinations = core.availableMoves()
            .filter { $0.stackID == stack.id && $0.card.id == card.id }
            .map(\.destination)
        boardBridge.updateForcedSelectionHighlights(Set(destinations))
    }

    func isCardUsable(_ stack: HandStack) -> Bool {
        boardBridge.isCardUsable(stack)
    }

    @discardableResult
    func animateCardPlay(for stack: HandStack, at index: Int) -> Bool {
        boardBridge.animateCardPlay(for: stack, at: index)
    }

    private func mutateSelectionState(
        _ mutation: (inout GameSessionState, inout UUID?) -> Void
    ) {
        var nextSessionState = sessionState
        var nextSelectedHandStackID = selectedHandStackID
        mutation(&nextSessionState, &nextSelectedHandStackID)
        sessionState = nextSessionState
        selectedHandStackID = nextSelectedHandStackID
    }

    func handleHandSlotTap(at index: Int) {
        mutateSelectionState { sessionState, selectedHandStackID in
            inputFlowCoordinator.handleHandSlotTap(
                at: index,
                core: core,
                boardBridge: boardBridge,
                sessionState: &sessionState,
                selectedHandStackID: &selectedHandStackID,
                hapticsEnabled: hapticsEnabled,
                guideModeEnabled: guideModeEnabled,
                basicMoveSlotIndex: presentsBasicMoveCard ? Self.dungeonBasicMoveSlotIndex : nil,
                presentsBasicMoveCard: presentsBasicMoveCard
            )
        }
    }

    func handleBoardTapPlayRequest(_ request: BoardTapPlayRequest) {
        mutateSelectionState { sessionState, selectedHandStackID in
            inputFlowCoordinator.handleBoardTapPlayRequest(
                request,
                core: core,
                boardBridge: boardBridge,
                sessionState: &sessionState,
                selectedHandStackID: &selectedHandStackID,
                guideModeEnabled: guideModeEnabled,
                hapticsEnabled: hapticsEnabled
            ) { [weak self] message, destination in
                self?.boardTapSelectionWarning = BoardTapSelectionWarning(
                    message: message,
                    destination: destination
                )
            }
        }
    }

    func handleBoardTapBasicMoveRequest(_ request: BoardTapBasicMoveRequest) {
        mutateSelectionState { sessionState, selectedHandStackID in
            inputFlowCoordinator.handleBoardTapBasicMoveRequest(
                request,
                core: core,
                boardBridge: boardBridge,
                sessionState: &sessionState,
                selectedHandStackID: &selectedHandStackID,
                guideModeEnabled: guideModeEnabled
            )
        }
    }

    func clearSelectedCardSelection() {
        mutateSelectionState { sessionState, selectedHandStackID in
            inputFlowCoordinator.clearSelectedCardSelection(
                sessionState: &sessionState,
                boardBridge: boardBridge,
                selectedHandStackID: &selectedHandStackID
            )
        }
    }

    func discardPendingDungeonPickupCard() {
        clearSelectedCardSelection()
        _ = core.discardPendingDungeonPickupCard()
        saveCurrentDungeonResumeIfPossible()
    }

    func replaceDungeonInventoryEntryForPendingPickup(discarding playable: PlayableCard) {
        clearSelectedCardSelection()
        _ = core.replaceDungeonInventoryEntryForPendingPickup(discarding: playable)
        saveCurrentDungeonResumeIfPossible()
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
}
