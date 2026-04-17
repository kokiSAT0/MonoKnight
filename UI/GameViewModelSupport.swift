import Foundation
import Game
import SharedSupport
import SwiftUI
import UIKit

/// 手札選択と候補ハイライトに関する内部状態
@MainActor
struct GameSessionState {
    /// 手札選択を表す内部モデル
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

/// ペナルティバナー表示の責務をまとめたヘルパー
final class GamePenaltyBannerController {
    private let scheduler: PenaltyBannerScheduling

    init(scheduler: PenaltyBannerScheduling) {
        self.scheduler = scheduler
    }

    func handlePenaltyEvent(
        _ event: PenaltyEvent,
        hapticsEnabled: Bool,
        setActiveBanner: @escaping (PenaltyEvent?) -> Void
    ) {
        scheduler.cancel()

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8, blendDuration: 0.2)) {
            setActiveBanner(event)
        }

        if hapticsEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }

        scheduler.scheduleAutoDismiss(after: 2.6) {
            withAnimation(.easeOut(duration: 0.25)) {
                setActiveBanner(nil)
            }
        }
    }

    func cancel(setActiveBanner: (PenaltyEvent?) -> Void) {
        scheduler.cancel()
        setActiveBanner(nil)
    }
}

/// タイマー停止理由と復帰条件を一元管理するヘルパー
final class GamePauseController {
    private(set) var isTimerPausedForMenu = false
    private(set) var isTimerPausedForScenePhase = false
    private(set) var shouldPresentPauseMenuAfterScenePhaseResume = false
    private(set) var isTimerPausedForPreparationOverlay = false

    func reset() {
        isTimerPausedForMenu = false
        isTimerPausedForScenePhase = false
        shouldPresentPauseMenuAfterScenePhaseResume = false
        isTimerPausedForPreparationOverlay = false
    }

    func handleScenePhaseChange(
        _ newPhase: ScenePhase,
        supportsTimerPausing: Bool,
        progress: GameProgress,
        pauseTimer: () -> Void,
        presentPauseMenu: () -> Void
    ) {
        guard supportsTimerPausing else { return }

        switch newPhase {
        case .inactive, .background:
            guard !isTimerPausedForScenePhase, progress == .playing else { return }
            pauseTimer()
            isTimerPausedForScenePhase = true
            shouldPresentPauseMenuAfterScenePhaseResume = true

        case .active:
            guard isTimerPausedForScenePhase else {
                shouldPresentPauseMenuAfterScenePhaseResume = false
                return
            }

            guard shouldPresentPauseMenuAfterScenePhaseResume else { return }

            guard progress == .playing else {
                shouldPresentPauseMenuAfterScenePhaseResume = false
                isTimerPausedForScenePhase = false
                return
            }

            guard !isTimerPausedForMenu, !isTimerPausedForPreparationOverlay else {
                return
            }

            shouldPresentPauseMenuAfterScenePhaseResume = false
            presentPauseMenu()

        @unknown default:
            break
        }
    }

    func handlePreparationOverlayChange(
        isVisible: Bool,
        supportsTimerPausing: Bool,
        progress: GameProgress,
        pauseTimer: () -> Void,
        resumeTimer: () -> Void,
        presentPauseMenu: () -> Void
    ) {
        guard supportsTimerPausing else { return }

        if isVisible {
            guard !isTimerPausedForPreparationOverlay else { return }
            isTimerPausedForPreparationOverlay = true

            guard !isTimerPausedForMenu, !isTimerPausedForScenePhase, progress == .playing else { return }
            pauseTimer()
        } else {
            guard isTimerPausedForPreparationOverlay else { return }
            isTimerPausedForPreparationOverlay = false

            if isTimerPausedForScenePhase,
               shouldPresentPauseMenuAfterScenePhaseResume,
               progress == .playing {
                presentPauseMenu()
                return
            }

            guard !isTimerPausedForMenu, !isTimerPausedForScenePhase, progress == .playing else { return }
            resumeTimer()
        }
    }

    func handlePauseMenuVisibilityChange(
        isPresented: Bool,
        supportsTimerPausing: Bool,
        progress: GameProgress,
        pauseTimer: () -> Void,
        resumeTimer: () -> Void
    ) {
        guard supportsTimerPausing else { return }

        if isPresented {
            guard progress == .playing else { return }
            guard !isTimerPausedForMenu else { return }
            if !isTimerPausedForScenePhase {
                pauseTimer()
            }
            isTimerPausedForMenu = true
        } else {
            guard isTimerPausedForMenu else { return }
            let wasMenuPauseActive = isTimerPausedForMenu
            isTimerPausedForMenu = false
            let wasScenePhasePauseActive = isTimerPausedForScenePhase
            isTimerPausedForScenePhase = false
            shouldPresentPauseMenuAfterScenePhaseResume = false
            guard !isTimerPausedForPreparationOverlay else { return }
            guard progress == .playing else { return }
            guard wasScenePhasePauseActive || wasMenuPauseActive else { return }
            resumeTimer()
        }
    }
}

/// リザルト表示とキャンペーン進捗更新の責務をまとめたヘルパー
@MainActor
final class GameFlowCoordinator {
    struct ClearOutcome {
        let latestCampaignClearRecord: CampaignStageClearRecord?
        let newlyUnlockedStages: [CampaignStage]
        let shouldShowResult: Bool
    }

    private let campaignLibrary = CampaignLibrary.shared

    func handleClearedProgress(
        mode: GameMode,
        core: GameCore,
        isGameCenterAuthenticated: Bool,
        gameCenterService: GameCenterServiceProtocol,
        onRequestGameCenterSignIn: ((GameCenterSignInPromptReason) -> Void)?,
        campaignProgressStore: CampaignProgressStore
    ) -> ClearOutcome {
        if mode.isLeaderboardEligible {
            if isGameCenterAuthenticated {
                gameCenterService.submitScore(core.score, for: mode.identifier)
            } else {
                debugLog("GameViewModel: Game Center 未認証のためスコア送信をスキップしました")
                onRequestGameCenterSignIn?(.scoreSubmissionSkipped)
            }
        }

        guard let metadata = mode.campaignMetadataSnapshot,
              let stage = campaignLibrary.stage(with: metadata.stageID) else {
            return ClearOutcome(
                latestCampaignClearRecord: nil,
                newlyUnlockedStages: [],
                shouldShowResult: true
            )
        }

        let unlockedStageIDsBefore = Set(
            campaignLibrary.allStages
                .filter { campaignProgressStore.isStageUnlocked($0) }
                .map(\.id)
        )

        let metrics = CampaignStageClearMetrics(
            moveCount: core.moveCount,
            penaltyCount: core.penaltyCount,
            elapsedSeconds: core.elapsedSeconds,
            totalMoveCount: core.totalMoveCount,
            score: core.score,
            hasRevisitedTile: core.hasRevisitedTile
        )

        let record = campaignProgressStore.registerClear(for: stage, metrics: metrics)
        let unlockedStagesAfter = campaignLibrary.allStages.filter { campaignProgressStore.isStageUnlocked($0) }
        let unlockedDiff = unlockedStagesAfter.filter { !unlockedStageIDsBefore.contains($0.id) }

        let newlyUnlockedStages: [CampaignStage]
        if unlockedDiff.isEmpty {
            newlyUnlockedStages = campaignLibrary.allStages.filter { stage in
                campaignProgressStore.isStageUnlocked(stage) &&
                    (campaignProgressStore.progress(for: stage.id)?.earnedStars ?? 0) == 0
            }
        } else {
            newlyUnlockedStages = unlockedDiff
        }

        return ClearOutcome(
            latestCampaignClearRecord: record,
            newlyUnlockedStages: newlyUnlockedStages,
            shouldShowResult: true
        )
    }
}
