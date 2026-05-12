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

        if let stack = core.handStacks.first(where: { $0.id == selectedCardSelection.stackID }),
           let topCard = stack.topCard,
           topCard.id == selectedCardSelection.cardID,
           topCard.supportCard?.requiresEnemyTargetSelection == true {
            let targets = core.targetedSupportCardTargetPoints
            guard !targets.isEmpty else {
                clearSelection(boardBridge: boardBridge, selectedHandStackID: &selectedHandStackID)
                return
            }
            boardBridge.updateForcedSelectionHighlights(targets)
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
        presentsBasicMoveCard: Bool,
        presentInputWarning: (String, GridPoint) -> Void
    ) {
        guard !boardBridge.isInputAnimationActive else { return }
        if presentsBasicMoveCard, let basicMoveSlotIndex, index == basicMoveSlotIndex {
            guard !core.isAwaitingDungeonPickupChoice else { return }
            handleBasicMoveSlotTap(
                core: core,
                boardBridge: boardBridge,
                sessionState: &sessionState,
                selectedHandStackID: &selectedHandStackID,
                hapticsEnabled: hapticsEnabled,
                presentInputWarning: presentInputWarning
            )
            return
        }
        guard core.handStacks.indices.contains(index) else { return }

        let latestStack = core.handStacks[index]

        if core.isAwaitingDungeonPickupChoice {
            clearSelectedCardSelection(
                sessionState: &sessionState,
                boardBridge: boardBridge,
                selectedHandStackID: &selectedHandStackID
            )
            guard let playable = latestStack.representativePlayable else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                let success = core.replaceDungeonInventoryEntryForPendingPickup(discarding: playable)
                if success, hapticsEnabled {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
            return
        }

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
            core.cancelTargetedSupportCardSelection()
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

        if let support = topCard.supportCard {
            guard core.isSupportCardUsable(in: latestStack) else {
                clearSelectedCardSelection(
                    sessionState: &sessionState,
                    boardBridge: boardBridge,
                    selectedHandStackID: &selectedHandStackID
                )
                presentInputWarning(
                    inputWarningMessage(for: latestStack, in: core),
                    core.current ?? GridPoint(x: 0, y: 0)
                )
                playInvalidInputFeedback(boardBridge: boardBridge, point: core.current, hapticsEnabled: hapticsEnabled)
                return
            }
            if support.requiresEnemyTargetSelection {
                guard core.beginTargetedSupportCardSelection(at: index) else {
                    clearSelectedCardSelection(
                        sessionState: &sessionState,
                        boardBridge: boardBridge,
                        selectedHandStackID: &selectedHandStackID
                    )
                    presentInputWarning(
                        inputWarningMessage(for: latestStack, in: core),
                        core.current ?? GridPoint(x: 0, y: 0)
                    )
                    playInvalidInputFeedback(boardBridge: boardBridge, point: core.current, hapticsEnabled: hapticsEnabled)
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
                    selectedHandStackID: &selectedHandStackID
                )
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

        if core.isIlluded {
            core.cancelTargetedSupportCardSelection()
            clearSelectedCardSelection(
                sessionState: &sessionState,
                boardBridge: boardBridge,
                selectedHandStackID: &selectedHandStackID
            )
            guard let randomMove = core.randomIllusionMove() else {
                playInvalidInputFeedback(boardBridge: boardBridge, point: core.current, hapticsEnabled: hapticsEnabled)
                return
            }
            _ = boardBridge.animateCardPlay(using: randomMove)
            return
        }

        core.cancelTargetedSupportCardSelection()
        guard boardBridge.isCardUsable(latestStack) else {
            clearSelectedCardSelection(
                sessionState: &sessionState,
                boardBridge: boardBridge,
                selectedHandStackID: &selectedHandStackID
            )
            presentInputWarning(
                inputWarningMessage(for: latestStack, in: core),
                core.current ?? GridPoint(x: 0, y: 0)
            )
            playInvalidInputFeedback(boardBridge: boardBridge, point: core.current, hapticsEnabled: hapticsEnabled)
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
        hapticsEnabled: Bool,
        presentInputWarning: (String, GridPoint) -> Void
    ) {
        if core.isAwaitingManualDiscardSelection {
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
            core.cancelTargetedSupportCardSelection()
            clearSelectedCardSelection(
                sessionState: &sessionState,
                boardBridge: boardBridge,
                selectedHandStackID: &selectedHandStackID
            )
            return
        }

        core.cancelTargetedSupportCardSelection()
        guard !core.availableBasicOrthogonalMoves().isEmpty else {
            clearSelectedCardSelection(
                sessionState: &sessionState,
                boardBridge: boardBridge,
                selectedHandStackID: &selectedHandStackID
            )
            presentInputWarning(
                basicMoveWarningMessage(in: core),
                core.current ?? GridPoint(x: 0, y: 0)
            )
            playInvalidInputFeedback(boardBridge: boardBridge, point: core.current, hapticsEnabled: hapticsEnabled)
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
        presentBoardTapSelectionWarning: (String, GridPoint, Set<UUID>) -> Void
    ) {
        defer { core.clearBoardTapPlayRequest(request.id) }

        guard !boardBridge.isInputAnimationActive else { return }
        guard !core.isAwaitingDungeonPickupChoice else { return }

        guard sessionState.hasSelection else {
            guard guideModeEnabled else { return }
            if core.isIlluded {
                presentBoardTapSelectionWarning(
                    "幻惑中は移動カードを手札から選ぶと、使われるカードと移動先がランダムに決まります。",
                    request.destination,
                    []
                )

                playInvalidInputFeedback(
                    boardBridge: boardBridge,
                    point: request.destination,
                    hapticsEnabled: hapticsEnabled
                )
                return
            }
            let availableMoves = core.availableMoves()
            let destinationCandidates = availableMoves.filter { $0.destination == request.destination }
            let conflictingStackIDs = Set(destinationCandidates.map(\.stackID))

            if conflictingStackIDs.count >= 2 {
                presentBoardTapSelectionWarning(
                    "複数のカードが同じマスを指定しています。手札から使いたいカードを選んでからマスをタップしてください。",
                    request.destination,
                    conflictingStackIDs
                )

                playInvalidInputFeedback(
                    boardBridge: boardBridge,
                    point: request.destination,
                    hapticsEnabled: hapticsEnabled
                )
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
            presentBoardTapSelectionWarning(
                "このカードではそのマスへ移動できません",
                request.destination,
                []
            )
            playInvalidInputFeedback(
                boardBridge: boardBridge,
                point: request.destination,
                hapticsEnabled: hapticsEnabled
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
        guideModeEnabled: Bool,
        hapticsEnabled: Bool,
        presentInputWarning: (String, GridPoint) -> Void
    ) {
        defer { core.clearBoardTapBasicMoveRequest(request.id) }
        guard !boardBridge.isInputAnimationActive else { return }
        guard !core.isAwaitingDungeonPickupChoice else { return }

        if sessionState.isBasicOrthogonalSelected {
            clearSelectedCardSelection(
                sessionState: &sessionState,
                boardBridge: boardBridge,
                selectedHandStackID: &selectedHandStackID
            )
            core.playBasicOrthogonalMove(using: request.move)
            if hapticsEnabled {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
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
                presentInputWarning(
                    "このカードではそのマスへ移動できません",
                    request.move.destination
                )
                playInvalidInputFeedback(
                    boardBridge: boardBridge,
                    point: request.move.destination,
                    hapticsEnabled: hapticsEnabled
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
        if hapticsEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func playInvalidInputFeedback(
        boardBridge: GameBoardBridgeViewModel,
        point: GridPoint?,
        hapticsEnabled: Bool
    ) {
        boardBridge.playInvalidSelectionFeedback(at: point)
        if hapticsEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    private func inputWarningMessage(for stack: HandStack, in core: GameCore) -> String {
        guard let topCard = stack.topCard else {
            return "今はカードを使えません"
        }
        guard core.progress == .playing else {
            return "今はカードを使えません"
        }

        if let support = topCard.supportCard {
            return supportWarningMessage(for: support, in: core) ?? "今はカードを使えません"
        }

        if let current = core.current,
           core.board.effect(at: current) == .swamp {
            return "沼の上では移動カードを使えません"
        }
        return "このカードで移動できるマスがありません"
    }

    private func basicMoveWarningMessage(in core: GameCore) -> String {
        core.progress == .playing ? "上下左右に移動できるマスがありません" : "今はカードを使えません"
    }

    private func supportWarningMessage(for support: SupportCard, in core: GameCore) -> String? {
        switch support {
        case .refillEmptySlots, .barrierSpell:
            return nil
        case .singleAnnihilationSpell, .annihilationSpell, .freezeSpell:
            return core.enemyStates.isEmpty ? "このフロアに対象の敵がいません" : nil
        case .darknessSpell:
            let hasWatcherLaser = core.enemyStates.contains { enemy in
                switch enemy.behavior {
                case .watcher, .rotatingWatcher:
                    return true
                case .guardPost, .patrol, .chaser, .marker:
                    return false
                }
            }
            if !hasWatcherLaser {
                return "見張りレーザーがないため使えません"
            }
            return core.isWatcherLaserSuppressed ? "見張りレーザーはすでに封じています" : nil
        case .railBreakSpell:
            let hasPatrolRail = core.enemyStates.contains { enemy in
                if case .patrol = enemy.behavior { return true }
                return false
            }
            if !hasPatrolRail {
                return "巡回レールがないため使えません"
            }
            return core.isPatrolRailDestroyed ? "巡回レールはすでに破壊済みです" : nil
        case .antidote:
            return core.poisonDamageTicksRemaining > 0 ? nil : "毒状態ではないため使えません"
        case .panacea:
            let hasRecoverableState = core.poisonDamageTicksRemaining > 0 || core.isShackled || core.isIlluded
            return hasRecoverableState ? nil : "解除する状態異常がありません"
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
        if !sessionState.hasSelection {
            core.cancelTargetedSupportCardSelection()
        }
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
