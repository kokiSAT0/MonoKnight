import Combine
import Foundation
import Game
import SwiftUI
import UIKit

@MainActor
extension GameViewModel {
    func handlePenaltyEvent(_ event: PenaltyEvent) {
        penaltyBannerController.handlePenaltyEvent(
            event,
            hapticsEnabled: hapticsEnabled
        ) { [weak self] banner in
            self?.applySessionUIMutation { state in
                state.setActivePenaltyBanner(banner)
            }
        }
    }

    func bindGameCore() {
        coreBindingCoordinator.bind(
            core: core,
            cancellables: &cancellables,
            onPenaltyEvent: { [weak self] event in
                self?.handlePenaltyEvent(event)
            },
            onHandStacksChange: { [weak self] newHandStacks in
                self?.recordDisplayedHandDiscoveries(newHandStacks)
                self?.handleHandStacksChange(newHandStacks)
            },
            onBoardTapPlayRequest: { [weak self] request in
                self?.handleBoardTapPlayRequest(request)
            },
            onBoardTapBasicMoveRequest: { [weak self] request in
                self?.handleBoardTapBasicMoveRequest(request)
            },
            onProgressChange: { [weak self] progress in
                self?.handleProgressChange(progress)
            },
            onElapsedTimeChange: { [weak self] in
                self?.updateDisplayedElapsedTime()
            }
        )

        core.$dungeonFallEvent
            .receive(on: RunLoop.main)
            .sink { [weak self] event in
                guard let event else { return }
                guard self?.isMovementPresentationActive != true else {
                    self?.deferredDungeonFallEventDuringMovementPresentation = event
                    return
                }
                self?.handleDungeonFallEvent(event)
            }
            .store(in: &cancellables)

        core.$dungeonEnemyTurnEvent
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] event in
                guard event.isParalysisRest, let point = event.paralysisTrapPoint else { return }
                self?.boardTapSelectionWarning = BoardTapSelectionWarning(
                    message: "麻痺罠で1回休み。敵が続けて動きます。",
                    destination: point
                )
            }
            .store(in: &cancellables)

        core.$dungeonLockedExitReachEvent
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] event in
                guard let self else { return }
                defer { self.core.clearDungeonLockedExitReachEvent(event.id) }
                if self.shouldDeferLockedExitReachNoticeDuringMovementPresentation(event) {
                    return
                }
                self.presentLockedExitReachNoticeIfNeeded(for: event)
            }
            .store(in: &cancellables)

        core.$moveCount
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] moveCount in
                if moveCount == 0 {
                    self?.displayedLockedExitReachNoticeKeys.removeAll()
                }
                self?.saveCurrentDungeonResumeIfPossible()
            }
            .store(in: &cancellables)

        core.$dungeonHP
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] dungeonHP in
                self?.handleDungeonHPChange(dungeonHP)
                self?.saveCurrentDungeonResumeIfPossible()
            }
            .store(in: &cancellables)

        core.$dungeonRelicEntries
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] entries in
                self?.recordRelicDiscoveries(entries)
            }
            .store(in: &cancellables)

        core.$dungeonCurseEntries
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] entries in
                self?.recordCurseDiscoveries(entries)
            }
            .store(in: &cancellables)

        core.$dungeonRelicAcquisitionPresentations
            .receive(on: RunLoop.main)
            .sink { [weak self] presentations in
                self?.enqueueDungeonRelicAcquisitionPresentations(presentations)
            }
            .store(in: &cancellables)

    }

    private func presentLockedExitReachNoticeIfNeeded(for event: DungeonLockedExitReachEvent) {
        let key = lockedExitReachNoticeKey(for: event)
        guard !displayedLockedExitReachNoticeKeys.contains(key) else { return }
        displayedLockedExitReachNoticeKeys.insert(key)
        boardTapSelectionWarning = BoardTapSelectionWarning(
            message: "鍵を取るまで階段は使えません",
            destination: event.exitPoint
        )
    }

    private func lockedExitReachNoticeKey(for event: DungeonLockedExitReachEvent) -> String {
        if let metadata = mode.dungeonMetadataSnapshot {
            return "\(metadata.dungeonID):\(metadata.floorID):\(event.exitPoint.x),\(event.exitPoint.y)"
        }
        return "\(mode.identifier.rawValue):\(event.exitPoint.x),\(event.exitPoint.y)"
    }

    private func shouldDeferLockedExitReachNoticeDuringMovementPresentation(
        _ event: DungeonLockedExitReachEvent
    ) -> Bool {
        guard isMovementPresentationActive,
              let resolution = core.lastMovementResolution,
              resolution.path.count > 1
        else { return false }
        return resolution.presentationSteps.contains { step in
            step.dungeonLockedExitReachEvent?.id == event.id
        }
    }

    func handleHandStacksChange(_ newHandStacks: [HandStack]) {
        guard !isMovementPresentationActive else { return }
        updateDisplayedHandStacks(Self.visibleHandStacks(from: newHandStacks, mode: mode))
        refreshSelectionIfNeeded(with: displayedHandStacks)
    }

    static func visibleHandStacks(from handStacks: [HandStack], mode: GameMode) -> [HandStack] {
        guard mode.usesDungeonExit else { return handStacks }
        return Array(handStacks.prefix(dungeonInventoryVisibleSlotCount))
    }

    static func newlyAddedHandStackIDs(previous: [HandStack], current: [HandStack]) -> Set<UUID> {
        let previousCounts = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0.count) })
        return Set(current.compactMap { stack in
            guard let previousCount = previousCounts[stack.id] else { return stack.id }
            return stack.count > previousCount ? stack.id : nil
        })
    }

    func updateDisplayedHandStacks(
        _ newDisplayedHandStacks: [HandStack],
        animatingAdditions: Bool = true
    ) {
        let addedIDs = animatingAdditions && mode.usesDungeonExit
            ? Self.newlyAddedHandStackIDs(
                previous: previousDisplayedHandStacksForAdditionEffect,
                current: newDisplayedHandStacks
            )
            : []
        displayedHandStacks = newDisplayedHandStacks
        previousDisplayedHandStacksForAdditionEffect = newDisplayedHandStacks
        guard !addedIDs.isEmpty else { return }
        presentHandAdditionEffect(for: addedIDs)
    }

    private func presentHandAdditionEffect(for stackIDs: Set<UUID>) {
        handAdditionEffectGeneration += 1
        let generation = handAdditionEffectGeneration
        withAnimation(.spring(response: 0.24, dampingFraction: 0.72)) {
            recentlyAddedHandStackIDs = stackIDs
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard let self, self.handAdditionEffectGeneration == generation else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                self.recentlyAddedHandStackIDs.removeAll()
            }
        }
    }

    func handleProgressChange(_ progress: GameProgress) {
        guard !hasPendingDungeonRelicAcquisitionPresentation else {
            deferredProgressDuringMovementPresentation = progress
            return
        }
        guard !isWaitingForEnemyTurnPresentationAfterMovement else {
            deferredProgressDuringMovementPresentation = progress
            return
        }
        guard !isMovementPresentationActive else {
            deferredProgressDuringMovementPresentation = progress
            return
        }
        if progress == .failed || shouldClearDungeonResumeAfterClear(progress) {
            dungeonRunResumeStore.clear()
        }
        registerRogueTowerRecordIfNeeded(progress: progress)
        if progress == .cleared {
            registerTutorialTowerClearIfNeeded()
            recordRewardOfferDiscoveries()
        }
        coreBindingCoordinator.handleProgressChange(
            progress,
            boardBridge: boardBridge,
            updateDisplayedElapsedTime: { [self] in
                updateDisplayedElapsedTime()
            },
            clearSelectedCardSelection: { [self] in
                clearSelectedCardSelection()
            },
            resolveClearOutcome: { [self] in
                guard progress == .cleared else { return nil }
                let outcome = sessionServicesCoordinator.resolveClearOutcome(
                    mode: mode,
                    core: core,
                    isGameCenterAuthenticated: isGameCenterAuthenticated,
                    flowCoordinator: flowCoordinator,
                    gameCenterService: gameCenterService,
                    onRequestGameCenterSignIn: onRequestGameCenterSignIn
                )
                latestDungeonGrowthAward = registerDungeonGrowthAwardIfNeeded()
                return outcome
            },
            applyClearOutcome: { [self] outcome in
                applyResultPresentationMutation { state in
                    state.applyClearOutcome(outcome)
                }
            }
        )
    }

    func beginMovementPresentation(using resolution: MovementResolution) {
        guard mode.usesDungeonExit else { return }
        isMovementPresentationActive = true
        deferredProgressDuringMovementPresentation = nil
        deferredDungeonFallEventDuringMovementPresentation = nil
        movementPresentationDungeonHP = resolution.presentationInitialHP ?? core.dungeonHP
        if let initialHandStacks = resolution.presentationInitialHandStacks {
            updateDisplayedHandStacks(
                Self.visibleHandStacks(from: initialHandStacks, mode: mode),
                animatingAdditions: false
            )
            refreshSelectionIfNeeded(with: displayedHandStacks)
        }
    }

    func applyMovementPresentationStep(_ step: MovementResolution.PresentationStep) {
        guard mode.usesDungeonExit else { return }
        isMovementPresentationActive = true
        movementPresentationDungeonHP = step.hpAfter
        updateDisplayedHandStacks(Self.visibleHandStacks(from: step.handStacksAfter, mode: mode))
        refreshSelectionIfNeeded(with: displayedHandStacks)
        if step.tookDamage {
            boardBridge.playDamageEffect()
            lastObservedDungeonHPForDamageEffect = step.hpAfter
        }
        if let lockedExitReachEvent = step.dungeonLockedExitReachEvent {
            presentLockedExitReachNoticeIfNeeded(for: lockedExitReachEvent)
        }
    }

    func finishMovementPresentation() {
        guard isMovementPresentationActive else { return }
        let pendingEnemyTurn = boardBridge.pendingEnemyTurnEventAfterMovementReplay
        isMovementPresentationActive = false
        isWaitingForEnemyTurnPresentationAfterMovement = pendingEnemyTurn != nil
        if let pendingEnemyTurn, pendingEnemyTurn.attackedPlayer {
            movementPresentationDungeonHP = pendingEnemyTurn.hpBefore
            lastObservedDungeonHPForDamageEffect = pendingEnemyTurn.hpBefore
        } else {
            movementPresentationDungeonHP = nil
        }
        updateDisplayedHandStacks(Self.visibleHandStacks(from: core.handStacks, mode: mode))
        refreshSelectionIfNeeded(with: displayedHandStacks)

        guard !isWaitingForEnemyTurnPresentationAfterMovement else { return }
        flushDeferredMovementPresentationOutcomes()
        handleDungeonHPChange(core.dungeonHP)
    }

    func applyEnemyTurnDamagePresentation(_ event: DungeonEnemyTurnEvent) {
        guard mode.usesDungeonExit else { return }
        guard event.attackedPlayer, event.hpAfter < event.hpBefore else { return }
        movementPresentationDungeonHP = event.hpAfter
        lastObservedDungeonHPForDamageEffect = event.hpAfter
        deferredEnemyDamageEventID = event.id
    }

    func finishEnemyTurnPresentation(_ event: DungeonEnemyTurnEvent) {
        guard mode.usesDungeonExit else { return }
        guard isWaitingForEnemyTurnPresentationAfterMovement || movementPresentationDungeonHP != nil else { return }
        isWaitingForEnemyTurnPresentationAfterMovement = false
        movementPresentationDungeonHP = nil
        flushDeferredMovementPresentationOutcomes()
        handleDungeonHPChange(core.dungeonHP)
    }

    private func flushDeferredMovementPresentationOutcomes() {
        presentNextDungeonRelicAcquisitionIfPossible()
        guard !hasPendingDungeonRelicAcquisitionPresentation else { return }
        if let deferredFall = deferredDungeonFallEventDuringMovementPresentation {
            deferredDungeonFallEventDuringMovementPresentation = nil
            handleDungeonFallEvent(deferredFall)
        }
        if let deferredProgress = deferredProgressDuringMovementPresentation {
            deferredProgressDuringMovementPresentation = nil
            handleProgressChange(deferredProgress)
        }
    }

    private var hasPendingDungeonRelicAcquisitionPresentation: Bool {
        activeDungeonRelicAcquisitionPresentation != nil
            || !pendingDungeonRelicAcquisitionPresentations.isEmpty
    }

    func enqueueDungeonRelicAcquisitionPresentations(_ presentations: [DungeonRelicAcquisitionPresentation]) {
        let newPresentations = presentations.filter { presentation in
            !observedDungeonRelicAcquisitionPresentationIDs.contains(presentation.id)
        }
        guard !newPresentations.isEmpty else { return }
        observedDungeonRelicAcquisitionPresentationIDs.formUnion(newPresentations.map(\.id))
        pendingDungeonRelicAcquisitionPresentations.append(contentsOf: newPresentations)
        presentNextDungeonRelicAcquisitionIfPossible()
    }

    func dismissActiveDungeonRelicAcquisitionPresentation() {
        activeDungeonRelicAcquisitionPresentation = nil
        presentNextDungeonRelicAcquisitionIfPossible()
        if !hasPendingDungeonRelicAcquisitionPresentation {
            flushDeferredMovementPresentationOutcomes()
            handleDungeonHPChange(core.dungeonHP)
        }
    }

    func presentNextDungeonRelicAcquisitionIfPossible() {
        guard activeDungeonRelicAcquisitionPresentation == nil,
              !isMovementPresentationActive,
              !isWaitingForEnemyTurnPresentationAfterMovement,
              !pendingDungeonRelicAcquisitionPresentations.isEmpty
        else { return }
        activeDungeonRelicAcquisitionPresentation = pendingDungeonRelicAcquisitionPresentations.removeFirst()
    }

    private func shouldClearDungeonResumeAfterClear(_ progress: GameProgress) -> Bool {
        guard progress == .cleared,
              let runState = dungeonRunState,
              let dungeon = DungeonLibrary.shared.dungeon(with: runState.dungeonID)
        else { return false }
        return !dungeon.canAdvanceWithinRun(afterFloorIndex: runState.currentFloorIndex)
    }

    private func registerDungeonGrowthAwardIfNeeded() -> DungeonGrowthAward? {
        guard let metadata = mode.dungeonMetadataSnapshot,
              let runState = metadata.runState,
              let dungeon = DungeonLibrary.shared.dungeon(with: metadata.dungeonID)
        else { return nil }

        let hasNextFloor = dungeon.canAdvanceWithinRun(afterFloorIndex: runState.currentFloorIndex)
        return dungeonGrowthStore.registerDungeonClear(dungeon: dungeon, runState: runState, hasNextFloor: hasNextFloor)
    }

    private func registerTutorialTowerClearIfNeeded() {
        guard let metadata = mode.dungeonMetadataSnapshot,
              let runState = metadata.runState,
              let dungeon = DungeonLibrary.shared.dungeon(with: metadata.dungeonID)
        else { return }
        tutorialTowerProgressStore.registerTutorialTowerClear(dungeon: dungeon, runState: runState)
    }

    private func registerRogueTowerRecordIfNeeded(progress: GameProgress) {
        guard progress == .cleared || progress == .failed,
              let metadata = mode.dungeonMetadataSnapshot,
              let runState = metadata.runState,
              let dungeon = DungeonLibrary.shared.dungeon(with: metadata.dungeonID),
              dungeon.supportsInfiniteFloors
        else { return }
        let reachedFloorNumber = progress == .cleared
            ? runState.floorNumber + 1
            : runState.floorNumber
        _ = rogueTowerRecordStore.registerReachedFloor(reachedFloorNumber, for: dungeon)
    }

    func handleDungeonHPChange(_ newHP: Int) {
        guard !isMovementPresentationActive else { return }
        if core.lastMovementResolution?.presentationSteps.contains(where: \.tookDamage) == true {
            return
        }
        defer { lastObservedDungeonHPForDamageEffect = newHP }
        guard mode.usesDungeonExit,
              let previousHP = lastObservedDungeonHPForDamageEffect,
              newHP < previousHP
        else { return }

        if let enemyTurnEvent = core.dungeonEnemyTurnEvent,
           enemyTurnEvent.id != deferredEnemyDamageEventID,
           enemyTurnEvent.attackedPlayer,
           enemyTurnEvent.hpBefore == previousHP,
           enemyTurnEvent.hpAfter == newHP {
            movementPresentationDungeonHP = previousHP
            deferredEnemyDamageEventID = enemyTurnEvent.id
            return
        }

        boardBridge.playDamageEffect()
    }

}
