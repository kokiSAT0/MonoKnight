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

        core.$moveCount
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
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

    func handleHandStacksChange(_ newHandStacks: [HandStack]) {
        guard !isMovementPresentationActive else { return }
        displayedHandStacks = Self.visibleHandStacks(from: newHandStacks, mode: mode)
        refreshSelectionIfNeeded(with: displayedHandStacks)
    }

    static func visibleHandStacks(from handStacks: [HandStack], mode: GameMode) -> [HandStack] {
        guard mode.usesDungeonExit else { return handStacks }
        return Array(handStacks.prefix(dungeonInventoryVisibleSlotCount))
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
            displayedHandStacks = Self.visibleHandStacks(from: initialHandStacks, mode: mode)
            refreshSelectionIfNeeded(with: displayedHandStacks)
        }
    }

    func applyMovementPresentationStep(_ step: MovementResolution.PresentationStep) {
        guard mode.usesDungeonExit else { return }
        isMovementPresentationActive = true
        movementPresentationDungeonHP = step.hpAfter
        displayedHandStacks = Self.visibleHandStacks(from: step.handStacksAfter, mode: mode)
        refreshSelectionIfNeeded(with: displayedHandStacks)
        if step.tookDamage {
            boardBridge.playDamageEffect()
            lastObservedDungeonHPForDamageEffect = step.hpAfter
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
        displayedHandStacks = Self.visibleHandStacks(from: core.handStacks, mode: mode)
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
