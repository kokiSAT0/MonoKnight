import Foundation
import Game
import SwiftUI
import UIKit

@MainActor
struct GameSessionState {
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
