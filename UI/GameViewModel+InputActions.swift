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

    func handleHandSlotTap(at index: Int) {
        let shouldNotifyTutorial: Bool = {
            guard boardBridge.animatingCard == nil else { return false }
            guard core.progress == .playing else { return false }
            guard !core.isAwaitingManualDiscardSelection else { return false }
            guard !core.isAwaitingSupportSwapSelection else { return false }
            guard core.handStacks.indices.contains(index) else { return false }
            let stack = core.handStacks[index]
            guard let topCard = stack.topCard else { return false }
            if topCard.supportCard != nil {
                return core.isSupportCardUsable(in: stack)
            }
            guard boardBridge.isCardUsable(stack) else { return false }
            return core.availableMoves().contains { move in
                move.stackID == stack.id && move.card.id == topCard.id
            }
        }()
        inputFlowCoordinator.handleHandSlotTap(
            at: index,
            core: core,
            boardBridge: boardBridge,
            sessionState: &sessionState,
            selectedHandStackID: &selectedHandStackID,
            hapticsEnabled: hapticsEnabled
        )
        if shouldNotifyTutorial {
            handleCampaignTutorialEvent(.handSelected)
        }
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

    func handleBoardTapBasicMoveRequest(_ request: BoardTapBasicMoveRequest) {
        inputFlowCoordinator.handleBoardTapBasicMoveRequest(
            request,
            core: core,
            boardBridge: boardBridge,
            sessionState: &sessionState,
            selectedHandStackID: &selectedHandStackID
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
}
