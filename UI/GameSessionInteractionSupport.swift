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

    private enum Selection {
        case handStack(SelectedCardSelection)
        case basicOrthogonal
    }

    private var selection: Selection?

    var hasSelection: Bool {
        selection != nil
    }

    var isBasicOrthogonalSelected: Bool {
        if case .basicOrthogonal = selection {
            return true
        }
        return false
    }

    func isSelected(stackID: UUID) -> Bool {
        if case let .handStack(selectedCardSelection) = selection {
            return selectedCardSelection.stackID == stackID
        }
        return false
    }

    mutating func updateSelection(stackID: UUID, cardID: UUID, selectedHandStackID: inout UUID?) {
        selection = .handStack(SelectedCardSelection(stackID: stackID, cardID: cardID))
        selectedHandStackID = stackID
    }

    mutating func updateBasicOrthogonalSelection(selectedHandStackID: inout UUID?) {
        selection = .basicOrthogonal
        selectedHandStackID = nil
    }

    func matchingMoves(in core: GameCore) -> [ResolvedCardMove] {
        guard case let .handStack(selection) = selection else { return [] }
        return core.availableMoves().filter { candidate in
            candidate.stackID == selection.stackID && candidate.card.id == selection.cardID
        }
    }

    mutating func clearSelection(
        boardBridge: GameBoardBridgeViewModel,
        selectedHandStackID: inout UUID?
    ) {
        let hasSelection = selection != nil || selectedHandStackID != nil
        let hasForcedHighlights = !boardBridge.forcedSelectionHighlightPoints.isEmpty
        guard hasSelection || hasForcedHighlights else { return }

        selection = nil
        selectedHandStackID = nil
        boardBridge.updateForcedSelectionHighlights([])
    }

    mutating func refreshSelectionIfNeeded(
        with handStacks: [HandStack],
        core: GameCore,
        boardBridge: GameBoardBridgeViewModel,
        selectedHandStackID: inout UUID?
    ) {
        guard case let .handStack(selection) = selection else {
            applyHighlights(
                core: core,
                boardBridge: boardBridge,
                selectedHandStackID: &selectedHandStackID
            )
            return
        }

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
        guard core.current != nil,
              let selection else {
            clearSelection(boardBridge: boardBridge, selectedHandStackID: &selectedHandStackID)
            return
        }

        if case .basicOrthogonal = selection {
            let destinations = Set(core.availableBasicOrthogonalMoves().map(\.destination))
            guard !destinations.isEmpty else {
                clearSelection(boardBridge: boardBridge, selectedHandStackID: &selectedHandStackID)
                return
            }
            boardBridge.updateForcedSelectionHighlights(destinations)
            return
        }

        guard case let .handStack(selectedCardSelection) = selection,
              let current = core.current else {
            clearSelection(boardBridge: boardBridge, selectedHandStackID: &selectedHandStackID)
            return
        }

        let moves = resolvedMoves ?? core.availableMoves().filter { candidate in
            candidate.stackID == selectedCardSelection.stackID && candidate.card.id == selectedCardSelection.cardID
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
        hapticsEnabled: Bool,
        guideModeEnabled: Bool,
        basicMoveSlotIndex: Int?,
        presentsBasicMoveCard: Bool
    ) {
        guard boardBridge.animatingCard == nil else { return }
        guard !core.isAwaitingDungeonPickupChoice else { return }
        if presentsBasicMoveCard, let basicMoveSlotIndex, index == basicMoveSlotIndex {
            handleBasicMoveSlotTap(
                core: core,
                boardBridge: boardBridge,
                sessionState: &sessionState,
                selectedHandStackID: &selectedHandStackID,
                hapticsEnabled: hapticsEnabled
            )
            return
        }
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

        if core.isAwaitingSupportSwapSelection {
            clearSelectedCardSelection(
                sessionState: &sessionState,
                boardBridge: boardBridge,
                selectedHandStackID: &selectedHandStackID
            )
            withAnimation(.easeInOut(duration: 0.2)) {
                let success = core.applySupportSwap(toTargetStackID: latestStack.id)
                if success, hapticsEnabled {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
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

        if topCard.supportCard != nil {
            guard core.isSupportCardUsable(in: latestStack) else {
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
            clearSelectedCardSelection(
                sessionState: &sessionState,
                boardBridge: boardBridge,
                selectedHandStackID: &selectedHandStackID
            )
            core.playSupportCard(at: index)
            if hapticsEnabled {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
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

        if guideModeEnabled, resolvedMoves.count == 1, let singleMove = resolvedMoves.first {
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

    private func handleBasicMoveSlotTap(
        core: GameCore,
        boardBridge: GameBoardBridgeViewModel,
        sessionState: inout GameSessionState,
        selectedHandStackID: inout UUID?,
        hapticsEnabled: Bool
    ) {
        if core.isAwaitingManualDiscardSelection || core.isAwaitingSupportSwapSelection {
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

        if sessionState.isBasicOrthogonalSelected {
            clearSelectedCardSelection(
                sessionState: &sessionState,
                boardBridge: boardBridge,
                selectedHandStackID: &selectedHandStackID
            )
            return
        }

        guard !core.availableBasicOrthogonalMoves().isEmpty else {
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

        sessionState.updateBasicOrthogonalSelection(selectedHandStackID: &selectedHandStackID)
        sessionState.applyHighlights(
            core: core,
            boardBridge: boardBridge,
            selectedHandStackID: &selectedHandStackID
        )
    }

    func handleBoardTapPlayRequest(
        _ request: BoardTapPlayRequest,
        core: GameCore,
        boardBridge: GameBoardBridgeViewModel,
        sessionState: inout GameSessionState,
        selectedHandStackID: inout UUID?,
        guideModeEnabled: Bool,
        hapticsEnabled: Bool,
        presentBoardTapSelectionWarning: (String, GridPoint) -> Void
    ) {
        defer { core.clearBoardTapPlayRequest(request.id) }

        guard boardBridge.animatingCard == nil else { return }
        guard !core.isAwaitingDungeonPickupChoice else { return }

        guard sessionState.hasSelection else {
            guard guideModeEnabled else { return }
            let availableMoves = core.availableMoves()
            let destinationCandidates = availableMoves.filter { $0.destination == request.destination }
            let conflictingStackIDs = Set(destinationCandidates.map(\.stackID))

            if conflictingStackIDs.count >= 2 {
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

        if sessionState.isBasicOrthogonalSelected {
            sessionState.applyHighlights(
                core: core,
                boardBridge: boardBridge,
                selectedHandStackID: &selectedHandStackID
            )
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

    func handleBoardTapBasicMoveRequest(
        _ request: BoardTapBasicMoveRequest,
        core: GameCore,
        boardBridge: GameBoardBridgeViewModel,
        sessionState: inout GameSessionState,
        selectedHandStackID: inout UUID?,
        guideModeEnabled: Bool
    ) {
        defer { core.clearBoardTapBasicMoveRequest(request.id) }
        guard boardBridge.animatingCard == nil else { return }
        guard !core.isAwaitingDungeonPickupChoice else { return }

        if sessionState.isBasicOrthogonalSelected {
            clearSelectedCardSelection(
                sessionState: &sessionState,
                boardBridge: boardBridge,
                selectedHandStackID: &selectedHandStackID
            )
            core.playBasicOrthogonalMove(using: request.move)
            return
        }

        guard !sessionState.hasSelection else {
            let matchingMoves = sessionState.matchingMoves(in: core)
            if matchingMoves.isEmpty {
                clearSelectedCardSelection(
                    sessionState: &sessionState,
                    boardBridge: boardBridge,
                    selectedHandStackID: &selectedHandStackID
                )
            } else {
                if let chosenMove = matchingMoves.first(where: { $0.destination == request.move.destination }) {
                    let didStart = boardBridge.animateCardPlay(using: chosenMove)
                    if didStart {
                        clearSelectedCardSelection(
                            sessionState: &sessionState,
                            boardBridge: boardBridge,
                            selectedHandStackID: &selectedHandStackID
                        )
                    }
                    return
                }
                sessionState.applyHighlights(
                    core: core,
                    boardBridge: boardBridge,
                    using: matchingMoves,
                    selectedHandStackID: &selectedHandStackID
                )
            }
            return
        }

        guard guideModeEnabled else { return }

        clearSelectedCardSelection(
            sessionState: &sessionState,
            boardBridge: boardBridge,
            selectedHandStackID: &selectedHandStackID
        )
        core.playBasicOrthogonalMove(using: request.move)
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
