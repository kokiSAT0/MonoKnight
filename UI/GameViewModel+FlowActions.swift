import Foundation
import Game
import SharedSupport

@MainActor
extension GameViewModel {
    func clearBoardTapSelectionWarning() {
        boardTapSelectionWarning = nil
    }

    func finalizeResultDismissal() {
        applyResultPresentationMutation { state in
            state.hideResult()
        }
    }

    var isInspectingFailedBoard: Bool {
        isResultFailed && !showingResult
    }

    func showFailedResultFromBoardInspection() {
        guard isResultFailed else { return }
        applyResultPresentationMutation { state in
            state.showingResult = true
        }
    }

    func requestManualPenalty() {
        guard isManualPenaltyButtonEnabled else { return }
        applySessionUIMutation { state in
            state.requestManualPenalty(cost: core.mode.manualRedrawPenaltyCost)
        }
    }

    func requestReturnToTitle() {
        applySessionUIMutation { state in
            state.requestReturnToTitle()
        }
    }

    func presentPauseMenu() {
        debugLog("GameViewModel: ポーズメニュー表示要求")
        applySessionUIMutation { state in
            state.presentPauseMenu()
        }
    }

    func performMenuAction(_ action: GameMenuAction) {
        applySessionUIMutation { state in
            state.clearPendingMenuAction()
        }
        clearSelectedCardSelection()
        switch action {
        case .manualPenalty:
            cancelPenaltyBannerDisplay()
            core.applyManualPenaltyRedraw()
        case .reset:
            resetSessionForNewPlay()
        case .returnToTitle:
            saveCurrentDungeonResumeIfPossible()
            prepareForReturnToTitle()
            onRequestReturnToTitle?()
        }
    }

    func handleResultRetry() {
        if mode.dungeonMetadataSnapshot?.runState != nil,
           let restartMode = makeRestartDungeonRunMode() {
            prepareForDungeonFloorAdvance()
            onRequestStartDungeonFloor?(restartMode)
            return
        }
        resetSessionForNewPlay()
    }

    func handleNextDungeonFloorAdvance() {
        guard let nextMode = makeNextDungeonFloorMode() else { return }
        saveInitialDungeonResume(for: nextMode)
        prepareForDungeonFloorAdvance()
        onRequestStartDungeonFloor?(nextMode)
    }

    func handleDungeonRewardSelection(_ rewardMoveCard: MoveCard) {
        guard availableDungeonRewardMoveCards.contains(rewardMoveCard),
              canAddDungeonRewardMoveCard(rewardMoveCard),
              let nextMode = makeNextDungeonFloorMode(rewardSelection: .add(rewardMoveCard))
        else { return }
        saveInitialDungeonResume(for: nextMode)
        prepareForDungeonFloorAdvance()
        onRequestStartDungeonFloor?(nextMode)
    }

    func handleDungeonRewardSupportSelection(_ supportCard: SupportCard) {
        guard availableDungeonRewardSupportCards.contains(supportCard),
              canAddDungeonRewardSupportCard(supportCard),
              let nextMode = makeNextDungeonFloorMode(rewardSelection: .addSupport(supportCard))
        else { return }
        saveInitialDungeonResume(for: nextMode)
        prepareForDungeonFloorAdvance()
        onRequestStartDungeonFloor?(nextMode)
    }

    func handleDungeonRewardSelection(_ selection: DungeonRewardSelection) {
        guard isDungeonRewardSelectionAvailable(selection),
              let nextMode = makeNextDungeonFloorMode(rewardSelection: selection)
        else { return }
        saveInitialDungeonResume(for: nextMode)
        prepareForDungeonFloorAdvance()
        onRequestStartDungeonFloor?(nextMode)
    }

    func handleDungeonRewardCardRemoval(_ card: MoveCard) {
        guard adjustableDungeonRewardEntries.contains(where: { $0.moveCard == card && $0.hasUsesRemaining }) else {
            return
        }
        _ = core.removeDungeonRewardInventoryCard(card)
    }

    func handleDungeonRewardSupportRemoval(_ support: SupportCard) {
        guard adjustableDungeonRewardEntries.contains(where: { $0.supportCard == support && $0.hasUsesRemaining }) else {
            return
        }
        _ = core.removeDungeonRewardInventorySupportCard(support)
    }

    func handleResultReturnToTitle() {
        prepareForReturnToTitle()
        onRequestReturnToTitle?()
    }

    func prepareForDungeonFloorAdvance() {
        clearDungeonRelicAcquisitionPresentationQueue()
        dungeonFallAdvanceTask?.cancel()
        dungeonFallAdvanceTask = nil
        sessionResetCoordinator.prepareForDungeonAdvance(
            cancelPenaltyBannerDisplay: { [self] in cancelPenaltyBannerDisplay() },
            hideResult: { [self] in
                applyResultPresentationMutation { state in
                    state.hideResult()
                }
            },
            resetTransientUI: { [self] in
                applySessionUIMutation { state in
                    state.resetTransientUIForTitleReturn()
                }
            },
            clearBoardTapSelectionWarning: { [self] in
                clearBoardTapSelectionWarning()
            },
            resetAdsPlayFlag: { [self] in
                sessionServicesCoordinator.resetAdsPlayFlag(using: adsService)
            }
        )
        pauseController.reset()
    }

    func handleDungeonFallEvent(_ event: DungeonFallEvent) {
        guard let nextMode = makeFallenDungeonFloorMode(event: event) else {
            core.clearDungeonFallEvent(event.id)
            return
        }

        core.clearDungeonFallEvent(event.id)
        boardBridge.playDungeonFallEffect(at: event.point)
        dungeonFallAdvanceTask?.cancel()
        dungeonFallAdvanceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 240_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.saveInitialDungeonResume(for: nextMode)
                self.prepareForDungeonFloorAdvance()
                self.onRequestStartDungeonFloor?(nextMode)
            }
        }
    }

    func makeNextDungeonFloorMode(rewardMoveCard: MoveCard? = nil) -> GameMode? {
        let selection = rewardMoveCard.map { DungeonRewardSelection.add($0) }
        return makeNextDungeonFloorMode(rewardSelection: selection)
    }

    func makeNextDungeonFloorMode(rewardSelection: DungeonRewardSelection?) -> GameMode? {
        guard !isResultFailed,
              let metadata = mode.dungeonMetadataSnapshot,
              let runState = metadata.runState,
              let dungeon = DungeonLibrary.shared.dungeon(with: metadata.dungeonID)
        else { return nil }

        let nextIndex = runState.currentFloorIndex + 1
        guard dungeon.canAdvanceWithinRun(afterFloorIndex: runState.currentFloorIndex) else { return nil }

        let nextRunState = runState.advancedToNextFloor(
            carryoverHP: core.dungeonHP,
            currentFloorMoveCount: core.moveCount,
            rewardSelection: rewardSelection,
            currentInventoryEntries: core.dungeonInventoryEntries,
            currentRelicEntries: core.dungeonRelicEntries,
            currentCurseEntries: core.dungeonCurseEntries,
            collectedDungeonRelicPickupIDs: core.collectedDungeonRelicPickupIDs,
            rewardAddUses: dungeonRewardAddUses,
            supportRewardAddUses: dungeonSupportRewardAddUses,
            hazardDamageMitigationsRemaining: core.hazardDamageMitigationsRemaining,
            enemyDamageMitigationsRemaining: core.enemyDamageMitigationsRemaining,
            markerDamageMitigationsRemaining: core.markerDamageMitigationsRemaining
        )
        guard let nextFloor = dungeon.resolvedFloor(at: nextIndex, runState: nextRunState) else { return nil }
        return nextFloor.makeGameMode(
            dungeonID: dungeon.id,
            difficulty: dungeon.difficulty,
            carriedHP: nextRunState.carriedHP,
            runState: nextRunState
        )
    }

    func makeFallenDungeonFloorMode(event: DungeonFallEvent) -> GameMode? {
        guard core.dungeonHP > 0,
              let metadata = mode.dungeonMetadataSnapshot,
              let runState = metadata.runState,
              runState.currentFloorIndex == event.sourceFloorIndex,
              let dungeon = DungeonLibrary.shared.dungeon(with: metadata.dungeonID),
              (dungeon.supportsInfiniteFloors || dungeon.floors.indices.contains(event.destinationFloorIndex)),
              event.destinationFloorIndex == runState.currentFloorIndex - 1,
              event.destinationFloorIndex < runState.currentFloorIndex
        else { return nil }

        let nextRunState = runState.fallenToPreviousFloor(
            carryoverHP: core.dungeonHP,
            currentFloorMoveCount: core.moveCount,
            currentInventoryEntries: core.dungeonInventoryEntries,
            currentRelicEntries: core.dungeonRelicEntries,
            currentCurseEntries: core.dungeonCurseEntries,
            collectedDungeonRelicPickupIDs: core.collectedDungeonRelicPickupIDs,
            landingPoint: event.point,
            currentFloorCrackedPoints: core.crackedFloorPoints,
            currentFloorCollapsedPoints: core.collapsedFloorPoints,
            hazardDamageMitigationsRemaining: core.hazardDamageMitigationsRemaining,
            enemyDamageMitigationsRemaining: core.enemyDamageMitigationsRemaining,
            markerDamageMitigationsRemaining: core.markerDamageMitigationsRemaining
        )
        guard let nextFloor = dungeon.resolvedFloor(at: event.destinationFloorIndex, runState: nextRunState) else {
            return nil
        }
        return nextFloor.makeGameMode(
            dungeonID: dungeon.id,
            difficulty: dungeon.difficulty,
            carriedHP: nextRunState.carriedHP,
            runState: nextRunState
        )
    }

    func makeRestartDungeonRunMode() -> GameMode? {
        guard let metadata = mode.dungeonMetadataSnapshot,
              let dungeon = DungeonLibrary.shared.dungeon(with: metadata.dungeonID)
        else { return nil }

        let restartFloorIndex = metadata.runState?.currentFloorIndex ?? 0
        let sectionStartFloorIndex = dungeon.difficulty == .growth
            ? (restartFloorIndex / 10) * 10
            : 0
        return DungeonLibrary.shared.floorMode(
            for: dungeon,
            floorIndex: sectionStartFloorIndex,
            initialHPBonus: dungeonGrowthStore.initialHPBonus(
                for: dungeon,
                startingFloorIndex: sectionStartFloorIndex
            ),
            startingRewardEntries: dungeonGrowthStore.startingRewardEntries(
                for: dungeon,
                startingFloorIndex: sectionStartFloorIndex
            ),
            startingHazardDamageMitigations: dungeonGrowthStore.startingHazardDamageMitigations(
                for: dungeon
            ),
            startingEnemyDamageMitigations: dungeonGrowthStore.startingEnemyDamageMitigations(
                for: dungeon
            ),
            startingMarkerDamageMitigations: dungeonGrowthStore.startingMarkerDamageMitigations(
                for: dungeon
            )
        )
    }

    private func isDungeonRewardSelectionAvailable(_ selection: DungeonRewardSelection) -> Bool {
        switch selection {
        case .add(let card):
            return availableDungeonRewardMoveCards.contains(card) && canAddDungeonRewardMoveCard(card)
        case .addSupport(let support):
            return availableDungeonRewardSupportCards.contains(support) && canAddDungeonRewardSupportCard(support)
        case .addRelic(let relic):
            return availableDungeonRewardOffers.contains(.relic(relic))
                && !core.dungeonRelicEntries.contains(where: { $0.relicID == relic })
        case .carryOverPickup(let card):
            return carryoverCandidateDungeonPickupEntries.contains { $0.card == card && $0.hasUsesRemaining }
        case .remove(let card):
            return adjustableDungeonRewardEntries.contains { $0.moveCard == card && $0.hasUsesRemaining }
        case .removeSupport(let support):
            return adjustableDungeonRewardEntries.contains { $0.supportCard == support && $0.hasUsesRemaining }
        }
    }

    func cancelPenaltyBannerDisplay() {
        penaltyBannerController.cancel { [weak self] banner in
            self?.applySessionUIMutation { state in
                state.setActivePenaltyBanner(banner)
            }
        }
    }

    func prepareForReturnToTitle() {
        clearDungeonRelicAcquisitionPresentationQueue()
        sessionResetCoordinator.prepareForReturnToTitle(
            clearSelectedCardSelection: { [self] in clearSelectedCardSelection() },
            cancelPenaltyBannerDisplay: { [self] in cancelPenaltyBannerDisplay() },
            hideResult: { [self] in
                applyResultPresentationMutation { state in
                    state.hideResult()
                }
            },
            resetTransientUI: { [self] in
                applySessionUIMutation { state in
                    state.resetTransientUIForTitleReturn()
                }
            },
            clearBoardTapSelectionWarning: { [self] in
                clearBoardTapSelectionWarning()
            },
            resetAdsPlayFlag: { [self] in
                sessionServicesCoordinator.resetAdsPlayFlag(using: adsService)
            },
            resetPauseController: { [self] in
                pauseController.reset()
            }
        )
    }

    private func clearDungeonRelicAcquisitionPresentationQueue() {
        activeDungeonRelicAcquisitionPresentation = nil
        pendingDungeonRelicAcquisitionPresentations.removeAll()
        deferredProgressDuringMovementPresentation = nil
    }

    func resetSessionForNewPlay() {
        dungeonRunResumeStore.clear()
        sessionResetCoordinator.resetSessionForNewPlay(
            prepareForReturnToTitle: { [self] in prepareForReturnToTitle() },
            resetCore: { [self] in core.reset() },
            resetPauseController: { [self] in pauseController.reset() }
        )
    }

    func saveCurrentDungeonResumeIfPossible() {
        guard let snapshot = core.makeDungeonResumeSnapshot() else { return }
        dungeonRunResumeStore.save(snapshot)
    }

    func saveInitialDungeonResume(for mode: GameMode) {
        let nextCore = GameCore(mode: mode)
        guard let snapshot = nextCore.makeDungeonResumeSnapshot() else { return }
        dungeonRunResumeStore.save(snapshot)
    }
}
