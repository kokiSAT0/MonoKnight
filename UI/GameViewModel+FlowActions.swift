import Foundation
import Game
import SharedSupport

@MainActor
extension GameViewModel {
    func clearBoardTapSelectionWarning() {
        boardTapSelectionWarning = nil
    }

    func clearTargetCaptureFeedback() {
        targetCaptureFeedbackDismissTask?.cancel()
        targetCaptureFeedbackDismissTask = nil
        targetCaptureFeedback = nil
    }

    func finalizeResultDismissal() {
        applyResultPresentationMutation { state in
            state.hideResult()
        }
    }

    func requestManualPenalty() {
        guard isManualPenaltyButtonEnabled else { return }
        applySessionUIMutation { state in
            state.requestManualPenalty(cost: core.mode.usesTargetCollection ? -15 : core.mode.manualRedrawPenaltyCost)
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
        prepareForDungeonFloorAdvance()
        onRequestStartDungeonFloor?(nextMode)
    }

    func handleDungeonRewardSelection(_ rewardMoveCard: MoveCard) {
        guard availableDungeonRewardMoveCards.contains(rewardMoveCard),
              let nextMode = makeNextDungeonFloorMode(rewardMoveCard: rewardMoveCard)
        else { return }
        prepareForDungeonFloorAdvance()
        onRequestStartDungeonFloor?(nextMode)
    }

    func handleResultReturnToTitle() {
        prepareForReturnToTitle()
        onRequestReturnToTitle?()
    }

    func handleCampaignStageAdvance(to stage: CampaignStage) {
        sessionResetCoordinator.prepareForCampaignStageAdvance(
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
                clearTargetCaptureFeedback()
            },
            clearBoardTapSelectionWarning: { [self] in
                clearBoardTapSelectionWarning()
            },
            resetAdsPlayFlag: { [self] in
                sessionServicesCoordinator.resetAdsPlayFlag(using: adsService)
            }
        )

        sessionServicesCoordinator.handleCampaignStageAdvance(
            to: stage,
            campaignProgressStore: campaignProgressStore,
            onRequestStartCampaignStage: onRequestStartCampaignStage
        )
    }

    func prepareForDungeonFloorAdvance() {
        sessionResetCoordinator.prepareForCampaignStageAdvance(
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
                clearTargetCaptureFeedback()
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

    func makeNextDungeonFloorMode(rewardMoveCard: MoveCard? = nil) -> GameMode? {
        guard !isResultFailed,
              let metadata = mode.dungeonMetadataSnapshot,
              let runState = metadata.runState,
              let dungeon = DungeonLibrary.shared.dungeon(with: metadata.dungeonID)
        else { return nil }

        let nextIndex = runState.currentFloorIndex + 1
        guard dungeon.floors.indices.contains(nextIndex) else { return nil }

        let nextRunState = runState.advancedToNextFloor(
            carryoverHP: core.dungeonHP,
            currentFloorMoveCount: core.moveCount,
            rewardMoveCard: rewardMoveCard,
            currentInventoryEntries: core.dungeonInventoryEntries
        )
        let nextFloor = dungeon.floors[nextIndex]
        return nextFloor.makeGameMode(
            dungeonID: dungeon.id,
            carriedHP: nextRunState.carriedHP,
            runState: nextRunState
        )
    }

    func makeRestartDungeonRunMode() -> GameMode? {
        guard let metadata = mode.dungeonMetadataSnapshot,
              let dungeon = DungeonLibrary.shared.dungeon(with: metadata.dungeonID)
        else { return nil }

        return DungeonLibrary.shared.firstFloorMode(for: dungeon)
    }

    func cancelPenaltyBannerDisplay() {
        penaltyBannerController.cancel { [weak self] banner in
            self?.applySessionUIMutation { state in
                state.setActivePenaltyBanner(banner)
            }
        }
    }

    func prepareForReturnToTitle() {
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
                clearTargetCaptureFeedback()
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

    func resetSessionForNewPlay() {
        sessionResetCoordinator.resetSessionForNewPlay(
            prepareForReturnToTitle: { [self] in prepareForReturnToTitle() },
            resetCore: { [self] in core.reset() },
            resetPauseController: { [self] in pauseController.reset() }
        )
    }
}
