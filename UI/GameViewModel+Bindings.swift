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
                self?.refreshSelectionIfNeeded(with: newHandStacks)
            },
            onBoardTapPlayRequest: { [weak self] request in
                self?.handleBoardTapPlayRequest(request)
            },
            onSpawnSelectionWarning: { [weak self] warning in
                self?.handleSpawnSelectionWarning(warning)
            },
            onProgressChange: { [weak self] progress in
                self?.handleProgressChange(progress)
            },
            onElapsedTimeChange: { [weak self] in
                self?.updateDisplayedElapsedTime()
            }
        )

        core.$moveCount
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] moveCount in
                self?.handleTutorialMoveCountChange(moveCount)
            }
            .store(in: &cancellables)

        core.$capturedTargetCount
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] capturedTargetCount in
                self?.handleTutorialCapturedTargetCountChange(capturedTargetCount)
            }
            .store(in: &cancellables)

        core.$focusCount
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] focusCount in
                self?.handleTutorialFocusCountChange(focusCount)
            }
            .store(in: &cancellables)

        core.$isOverloadCharged
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        core.$progress
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] progress in
                self?.handleTutorialProgressChange(progress)
            }
            .store(in: &cancellables)
    }

    func handleSpawnSelectionWarning(_ warning: SpawnSelectionWarning) {
        let message: String
        switch warning.reason {
        case .targetTile:
            message = "目的地マスは開始位置にできません。目的地以外のマスを選んでください。"
        }

        boardTapSelectionWarning = BoardTapSelectionWarning(
            message: message,
            destination: warning.point
        )
        core.clearSpawnSelectionWarning(warning.id)

        if hapticsEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    func handleProgressChange(_ progress: GameProgress) {
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
                return sessionServicesCoordinator.resolveClearOutcome(
                    mode: mode,
                    core: core,
                    isGameCenterAuthenticated: isGameCenterAuthenticated,
                    flowCoordinator: flowCoordinator,
                    gameCenterService: gameCenterService,
                    onRequestGameCenterSignIn: onRequestGameCenterSignIn,
                    campaignProgressStore: campaignProgressStore
                )
            },
            applyClearOutcome: { [self] outcome in
                applyResultPresentationMutation { state in
                    state.applyClearOutcome(outcome)
                }
            }
        )
    }

    func startCampaignTutorialIfNeeded() {
        campaignTutorialCard = campaignTutorialController.startIfNeeded()?.card
        applyCampaignTutorialHighlights()
    }

    func handleCampaignTutorialEvent(_ event: CampaignTutorialEvent) {
        campaignTutorialCard = campaignTutorialController.handle(event)?.card
        applyCampaignTutorialHighlights()
    }

    func dismissCampaignTutorial() {
        campaignTutorialCard = campaignTutorialController.dismissActiveStep()?.card
        applyCampaignTutorialHighlights()
    }

    func handleTutorialMoveCountChange(_ newMoveCount: Int) {
        defer { lastTutorialMoveCount = newMoveCount }
        guard newMoveCount > lastTutorialMoveCount else { return }
        handleCampaignTutorialEvent(.firstMove)
    }

    func handleTutorialCapturedTargetCountChange(_ newCapturedTargetCount: Int) {
        defer { lastTutorialCapturedTargetCount = newCapturedTargetCount }
        guard newCapturedTargetCount > lastTutorialCapturedTargetCount else { return }
        showTargetCaptureFeedback(
            capturedCount: newCapturedTargetCount,
            incrementCount: newCapturedTargetCount - lastTutorialCapturedTargetCount
        )
        handleCampaignTutorialEvent(.targetCaptured)
    }

    func handleTutorialFocusCountChange(_ newFocusCount: Int) {
        defer { lastTutorialFocusCount = newFocusCount }
        guard newFocusCount > lastTutorialFocusCount else { return }
        handleCampaignTutorialEvent(.focusUsed)
    }

    func handleTutorialProgressChange(_ newProgress: GameProgress) {
        defer { lastTutorialProgress = newProgress }
        guard lastTutorialProgress == .awaitingSpawn, newProgress == .playing else { return }
        handleCampaignTutorialEvent(.spawnSelected)
    }

    func applyCampaignTutorialHighlights() {
        guard selectedHandStackID == nil else { return }
        guard let step = campaignTutorialController.activeStep else {
            boardBridge.updateForcedSelectionHighlights([])
            return
        }

        switch step.forcedHighlight {
        case .none:
            boardBridge.updateForcedSelectionHighlights([])
        case .currentTarget:
            boardBridge.updateForcedSelectionHighlights(Set([core.targetPoint].compactMap { $0 }))
        case .upcomingTargets:
            boardBridge.updateForcedSelectionHighlights(Set(core.upcomingTargetPoints))
        case .allTargets:
            var points = Set(core.upcomingTargetPoints)
            if let targetPoint = core.targetPoint {
                points.insert(targetPoint)
            }
            boardBridge.updateForcedSelectionHighlights(points)
        }
    }

    func showTargetCaptureFeedback(capturedCount: Int, incrementCount: Int) {
        guard core.mode.usesTargetCollection else { return }
        guard incrementCount > 0 else { return }

        targetCaptureFeedbackDismissTask?.cancel()
        targetCaptureFeedbackDismissTask = nil

        withAnimation(.spring(response: 0.32, dampingFraction: 0.82, blendDuration: 0.18)) {
            targetCaptureFeedback = TargetCaptureFeedback(
                capturedCount: capturedCount,
                incrementCount: incrementCount
            )
        }

        if hapticsEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }

        targetCaptureFeedbackDismissTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 750_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.24)) {
                    self?.targetCaptureFeedback = nil
                }
                self?.targetCaptureFeedbackDismissTask = nil
            }
        }
    }
}
