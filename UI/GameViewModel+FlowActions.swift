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

    var canRestartCurrentDungeonFloorForTesting: Bool {
        mode.usesDungeonExit
            && DebugLogHistory.shared.isFrontEndViewerAvailable
            && floorStartDungeonResumeSnapshot != nil
    }

    func handleRestartCurrentDungeonFloorForTesting() {
        guard canRestartCurrentDungeonFloorForTesting,
              let snapshot = floorStartDungeonResumeSnapshot
        else { return }

        clearSelectedCardSelection()
        clearBoardTapSelectionWarning()
        cancelPenaltyBannerDisplay()
        dungeonFallAdvanceTask?.cancel()
        dungeonFallAdvanceTask = nil
        clearDungeonRelicAcquisitionPresentationQueue()
        pendingDungeonRelicPickupChoice = nil
        isMovementPresentationActive = false
        movementPresentationOverlayPause = nil
        movementPresentationReachedCardPickupIDs.removeAll()
        movementPresentationReachedRelicPickupIDs.removeAll()
        movementPresentationSeenCardPickupIDs.removeAll()
        movementPresentationSeenRelicPickupIDs.removeAll()
        isWaitingForEnemyTurnPresentationAfterMovement = false
        movementPresentationDungeonHP = nil
        deferredProgressDuringMovementPresentation = nil
        deferredDungeonFallEventDuringMovementPresentation = nil
        deferredDungeonRewindReviveEventDuringMovementPresentation = nil
        deferredEnemyDamageEventID = nil
        recentlyAddedHandStackIDs.removeAll()
        displayedLockedExitReachNoticeKeys.removeAll()
        latestDungeonGrowthAward = nil
        applySessionUIMutation { state in
            state.resetTransientUIForTitleReturn()
        }
        applyResultPresentationMutation { state in
            state.hideResult()
        }
        pauseController.reset()

        guard core.restoreDungeonResumeSnapshot(snapshot) else { return }
        dungeonRunResumeStore.save(snapshot)
        dungeonRunLogEntries = core.dungeonRunLogEntries
        lastObservedDungeonHPForDamageEffect = core.dungeonHP
        updateDisplayedHandStacks(
            Self.visibleHandStacks(from: core.handStacks, mode: mode),
            animatingAdditions: false
        )
        refreshSelectionIfNeeded(with: displayedHandStacks)
        refreshGuideHighlights()
        updateDisplayedElapsedTime()
        debugLog("[PLAY] event=current_floor_restart floor=\(snapshot.floorIndex + 1) hp=\(snapshot.dungeonHP)")
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
        let normalizedSupport = supportCard.normalizedForInventory
        guard availableDungeonRewardSupportCards.contains(normalizedSupport),
              canAddDungeonRewardSupportCard(normalizedSupport),
              let nextMode = makeNextDungeonFloorMode(rewardSelection: .addSupport(normalizedSupport))
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
        let normalizedSupport = support.normalizedForInventory
        guard adjustableDungeonRewardEntries.contains(where: { $0.supportCard == normalizedSupport && $0.hasUsesRemaining }) else {
            return
        }
        _ = core.removeDungeonRewardInventorySupportCard(normalizedSupport)
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

    func handleDungeonRewindReviveEvent(_ event: DungeonRewindReviveEvent) {
        guard let nextMode = makeRewindReviveDungeonFloorMode(event: event) else {
            core.clearDungeonRewindReviveEvent(event.id)
            return
        }

        core.clearDungeonRewindReviveEvent(event.id)
        dungeonFallAdvanceTask?.cancel()
        dungeonFallAdvanceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
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
            currentFloorElapsedSeconds: core.elapsedSeconds,
            rewardSelection: rewardSelection,
            currentInventoryEntries: core.dungeonInventoryEntries,
            currentRelicEntries: core.dungeonRelicEntries,
            currentCurseEntries: core.dungeonCurseEntries,
            collectedDungeonSpecialPickupIDs: core.collectedDungeonSpecialPickupIDs,
            collectedDungeonRelicPickupIDs: core.collectedDungeonRelicPickupIDs,
            rewardAddUses: dungeonRewardAddUses,
            supportRewardAddUses: baseDungeonSupportRewardAddUses,
            areDungeonRelicAndCurseEffectsEnabled: core.areDungeonRelicAndCurseEffectsEnabled,
            completedWithinHalfTurnLimit: isCurrentDungeonClearWithinHalfTurnLimit,
            startedFloorWithEnemies: core.didStartCurrentFloorWithEnemies,
            currentFloorDefeatedEnemyCount: core.currentFloorDefeatedEnemyCount,
            hazardDamageMitigationsRemaining: core.hazardDamageMitigationsRemaining,
            enemyDamageMitigationsRemaining: core.enemyDamageMitigationsRemaining,
            markerDamageMitigationsRemaining: core.markerDamageMitigationsRemaining,
            currentRunLogEntries: core.dungeonRunLogEntries,
            currentFloorVisitedPoints: Set(core.board.visitedPoints),
            currentFloorCrackedPoints: core.crackedFloorPoints,
            currentFloorCollapsedPoints: core.collapsedFloorPoints,
            currentFloorConsumedHealingTilePoints: core.consumedHealingTilePoints,
            currentFloorConsumedDamageTrapPoints: core.consumedDamageTrapPoints,
            currentFloorCollectedDungeonCardPickupIDs: core.collectedDungeonCardPickupIDs,
            currentFloorCollectedDungeonSpecialPickupIDs: core.collectedDungeonSpecialPickupIDs,
            currentFloorEnemyStates: core.enemyStates,
            isCurrentFloorDungeonExitUnlocked: core.isDungeonExitUnlocked,
            currentRewardOffers: availableDungeonRewardOffers
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
            currentFloorElapsedSeconds: core.elapsedSeconds,
            currentInventoryEntries: core.dungeonInventoryEntries,
            currentRelicEntries: core.dungeonRelicEntries,
            currentCurseEntries: core.dungeonCurseEntries,
            collectedDungeonSpecialPickupIDs: core.collectedDungeonSpecialPickupIDs,
            collectedDungeonRelicPickupIDs: core.collectedDungeonRelicPickupIDs,
            landingPoint: event.point,
            currentFloorCrackedPoints: core.crackedFloorPoints,
            currentFloorCollapsedPoints: core.collapsedFloorPoints,
            hazardDamageMitigationsRemaining: core.hazardDamageMitigationsRemaining,
            enemyDamageMitigationsRemaining: core.enemyDamageMitigationsRemaining,
            markerDamageMitigationsRemaining: core.markerDamageMitigationsRemaining,
            currentRunLogEntries: core.dungeonRunLogEntries
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

    func makeRewindReviveDungeonFloorMode(event: DungeonRewindReviveEvent) -> GameMode? {
        guard core.dungeonHP > 0,
              let metadata = mode.dungeonMetadataSnapshot,
              let runState = metadata.runState,
              runState.currentFloorIndex == event.sourceFloorIndex,
              let dungeon = DungeonLibrary.shared.dungeon(with: metadata.dungeonID),
              (dungeon.supportsInfiniteFloors || dungeon.floors.indices.contains(event.destinationFloorIndex)),
              event.destinationFloorIndex <= runState.currentFloorIndex
        else { return nil }

        let nextRunState = runState.revivedAtPreviousFloor(
            floorIndex: event.destinationFloorIndex,
            currentFloorMoveCount: core.moveCount,
            currentFloorElapsedSeconds: core.elapsedSeconds,
            currentInventoryEntries: core.dungeonInventoryEntries,
            currentRelicEntries: core.dungeonRelicEntries,
            currentCurseEntries: core.dungeonCurseEntries,
            collectedDungeonSpecialPickupIDs: core.collectedDungeonSpecialPickupIDs,
            collectedDungeonRelicPickupIDs: core.collectedDungeonRelicPickupIDs,
            hazardDamageMitigationsRemaining: core.hazardDamageMitigationsRemaining,
            enemyDamageMitigationsRemaining: core.enemyDamageMitigationsRemaining,
            markerDamageMitigationsRemaining: core.markerDamageMitigationsRemaining,
            currentRunLogEntries: core.dungeonRunLogEntries
        )
        guard let nextFloor = dungeon.resolvedFloor(at: event.destinationFloorIndex, runState: nextRunState) else {
            return nil
        }
        return nextFloor.makeGameMode(
            dungeonID: dungeon.id,
            difficulty: dungeon.difficulty,
            carriedHP: event.hpAfterRevive,
            runState: nextRunState
        )
    }

    func makeRestartDungeonRunMode() -> GameMode? {
        guard let metadata = mode.dungeonMetadataSnapshot,
              let dungeon = DungeonLibrary.shared.dungeon(with: metadata.dungeonID)
        else { return nil }

        let restartFloorIndex = metadata.runState?.currentFloorIndex ?? 0
        let restartMovementStyle = metadata.runState?.movementStyle ?? .orthogonal
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
                startingFloorIndex: sectionStartFloorIndex,
                movementStyle: restartMovementStyle
            ) + dungeonGrowthStore.retryRewardEntries(
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
            ),
            movementStyle: restartMovementStyle,
            dungeonInventoryKindLimit: dungeonGrowthStore.dungeonInventoryKindLimit(for: dungeon)
        )
    }

    private func isDungeonRewardSelectionAvailable(_ selection: DungeonRewardSelection) -> Bool {
        switch selection {
        case .add(let card):
            return availableDungeonRewardMoveCards.contains(card) && canAddDungeonRewardMoveCard(card)
        case .addSupport(let support):
            let normalizedSupport = support.normalizedForInventory
            return availableDungeonRewardSupportCards.contains(normalizedSupport) && canAddDungeonRewardSupportCard(normalizedSupport)
        case .addRelic(let relic):
            return availableDungeonRewardOffers.contains(.relic(relic))
                && !core.dungeonRelicEntries.contains(where: { $0.relicID == relic })
        case .handExpansion:
            return availableDungeonRewardOffers.contains(.handExpansion)
        case .carryOverPickup(let card):
            return carryoverCandidateDungeonPickupEntries.contains { $0.card == card && $0.hasUsesRemaining }
        case .remove(let card):
            return adjustableDungeonRewardEntries.contains { $0.moveCard == card && $0.hasUsesRemaining }
        case .removeSupport(let support):
            let normalizedSupport = support.normalizedForInventory
            return adjustableDungeonRewardEntries.contains { $0.supportCard == normalizedSupport && $0.hasUsesRemaining }
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
        restoreDungeonChoiceOverlay()
        activeDungeonRelicAcquisitionPresentation = nil
        pendingDungeonRelicAcquisitionPresentations.removeAll()
        deferredProgressDuringMovementPresentation = nil
        deferredDungeonRewindReviveEventDuringMovementPresentation = nil
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
