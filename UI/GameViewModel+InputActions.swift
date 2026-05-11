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

    func unusableReason(for stack: HandStack) -> String? {
        guard let topCard = stack.topCard else { return nil }
        guard core.progress == .playing else {
            return "今はカードを使えません"
        }

        if let support = topCard.supportCard {
            return unusableSupportReason(for: support)
        }

        if let current = core.current,
           core.board.effect(at: current) == .swamp {
            return "沼の上では移動カードを使えません"
        }

        let hasCandidate = core.availableMoves().contains { candidate in
            candidate.stackID == stack.id && candidate.card.id == topCard.id
        }
        return hasCandidate ? nil : "このカードで移動できるマスがありません"
    }

    func unusableBasicMoveReason() -> String? {
        guard core.progress == .playing else {
            return "今はカードを使えません"
        }
        guard core.availableBasicOrthogonalMoves().isEmpty else {
            return nil
        }
        return "上下左右に移動できるマスがありません"
    }

    private func unusableSupportReason(for support: SupportCard) -> String? {
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
            ) { [weak self] message, destination in
                self?.boardTapSelectionWarning = BoardTapSelectionWarning(
                    message: message,
                    destination: destination
                )
            }
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

    func clearSelectedCardSelection() {
        core.cancelTargetedSupportCardSelection()
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
