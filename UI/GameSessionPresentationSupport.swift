import Foundation
import Game
import SwiftUI
import UIKit

protocol PenaltyBannerScheduling: AnyObject {
    func scheduleAutoDismiss(after delay: TimeInterval, handler: @escaping () -> Void)
    func cancel()
}

final class PenaltyBannerScheduler: PenaltyBannerScheduling {
    private var dismissWorkItem: DispatchWorkItem?
    private let queue: DispatchQueue

    init(queue: DispatchQueue = .main) {
        self.queue = queue
    }

    func scheduleAutoDismiss(after delay: TimeInterval, handler: @escaping () -> Void) {
        cancel()

        let workItem = DispatchWorkItem { [weak self] in
            defer { self?.dismissWorkItem = nil }
            handler()
        }
        dismissWorkItem = workItem
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func cancel() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
    }
}

struct CampaignPauseSummary {
    let stage: CampaignStage
    let progress: CampaignStageProgress?
}

struct GameBoardTapSelectionWarning: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let destination: GridPoint
}

struct CampaignTutorialCard: Equatable {
    let title: String
    let message: String
    let instruction: String
}

enum CampaignTutorialEvent: Hashable {
    case stageStart
    case handSelected
    case firstMove
    case targetCaptured
    case focusUsed
    case spawnSelected
}

struct CampaignTutorialStep: Equatable {
    enum StepID: String {
        case currentTarget
        case upcomingTarget
        case movement
        case targetCapture
        case clearGoal
        case focus
        case spawnSelection
        case routePlanning
        case chapterReview
    }

    enum ForcedHighlight: Equatable {
        case none
        case currentTarget
        case upcomingTargets
        case allTargets
    }

    let id: StepID
    let title: String
    let message: String
    let instruction: String
    let completionEvents: Set<CampaignTutorialEvent>
    let forcedHighlight: ForcedHighlight

    init(
        id: StepID,
        title: String,
        message: String,
        instruction: String,
        completionEvent: CampaignTutorialEvent,
        forcedHighlight: ForcedHighlight
    ) {
        self.init(
            id: id,
            title: title,
            message: message,
            instruction: instruction,
            completionEvents: [completionEvent],
            forcedHighlight: forcedHighlight
        )
    }

    init(
        id: StepID,
        title: String,
        message: String,
        instruction: String,
        completionEvents: Set<CampaignTutorialEvent>,
        forcedHighlight: ForcedHighlight
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.instruction = instruction
        self.completionEvents = completionEvents
        self.forcedHighlight = forcedHighlight
    }

    var card: CampaignTutorialCard {
        CampaignTutorialCard(title: title, message: message, instruction: instruction)
    }

    var storageID: String { id.rawValue }
}

final class CampaignTutorialStore {
    private let userDefaults: UserDefaults
    private let storageKey: String

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = StorageKey.UserDefaults.campaignTutorialSeenSteps
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    func hasSeen(stageID: CampaignStageID, stepID: String) -> Bool {
        seenStepKeys.contains(Self.storageKey(for: stageID, stepID: stepID))
    }

    func markSeen(stageID: CampaignStageID, stepID: String) {
        var keys = seenStepKeys
        keys.insert(Self.storageKey(for: stageID, stepID: stepID))
        userDefaults.set(Array(keys).sorted(), forKey: storageKey)
    }

    func resetForTesting() {
        userDefaults.removeObject(forKey: storageKey)
    }

    private var seenStepKeys: Set<String> {
        Set(userDefaults.stringArray(forKey: storageKey) ?? [])
    }

    private static func storageKey(for stageID: CampaignStageID, stepID: String) -> String {
        "\(stageID.displayCode).\(stepID)"
    }
}

@MainActor
final class CampaignTutorialController {
    private let mode: GameMode
    private let store: CampaignTutorialStore
    private let steps: [CampaignTutorialStep]
    private let stageID: CampaignStageID?
    private var activeIndex: Int?

    init(mode: GameMode, store: CampaignTutorialStore) {
        self.mode = mode
        self.store = store
        stageID = mode.campaignMetadataSnapshot?.stageID
        steps = stageID.map(Self.steps(for:)) ?? []
        activeIndex = nil
    }

    var activeStep: CampaignTutorialStep? {
        guard let activeIndex, steps.indices.contains(activeIndex) else { return nil }
        return steps[activeIndex]
    }

    func startIfNeeded() -> CampaignTutorialStep? {
        guard mode.isCampaignStage else { return nil }
        return showNextUnseenStep(startingAt: 0)
    }

    func handle(_ event: CampaignTutorialEvent) -> CampaignTutorialStep? {
        guard mode.isCampaignStage, let stageID else { return nil }

        if let activeStep, activeStep.completionEvents.contains(event) {
            store.markSeen(stageID: stageID, stepID: activeStep.storageID)
            let nextStart = (activeIndex ?? -1) + 1
            return showNextUnseenStep(startingAt: nextStart)
        }

        if activeStep == nil {
            return showNextUnseenStep(startingAt: 0)
        }

        return activeStep
    }

    private func showNextUnseenStep(startingAt startIndex: Int) -> CampaignTutorialStep? {
        guard let stageID else {
            activeIndex = nil
            return nil
        }

        for index in steps.indices where index >= startIndex {
            let step = steps[index]
            if !store.hasSeen(stageID: stageID, stepID: step.storageID) {
                activeIndex = index
                return step
            }
        }

        activeIndex = nil
        return nil
    }

    private static func steps(for stageID: CampaignStageID) -> [CampaignTutorialStep] {
        switch (stageID.chapter, stageID.index) {
        case (1, 1):
            return [
                CampaignTutorialStep(
                    id: .currentTarget,
                    title: "紫の菱形を目指す",
                    message: "盤面の紫の菱形が、いま取りに行く目的地です。",
                    instruction: "まずは目的地の位置を確認して、手札を1枚選びましょう。",
                    completionEvents: [.handSelected, .firstMove, .targetCaptured],
                    forcedHighlight: .none
                ),
                CampaignTutorialStep(
                    id: .upcomingTarget,
                    title: "オレンジ点は次の候補",
                    message: "オレンジの点は、このあと出てくる目的地候補です。今すぐ踏まなくても大丈夫です。",
                    instruction: "紫の目的地へ近づくカードを使って移動しましょう。",
                    completionEvent: .firstMove,
                    forcedHighlight: .none
                ),
                CampaignTutorialStep(
                    id: .movement,
                    title: "枠のマスへ移動",
                    message: "手札カードを選ぶと、移動できるマスが枠で表示されます。目的地とは別の合図です。",
                    instruction: "枠を見ながら紫の目的地まで進みましょう。",
                    completionEvent: .targetCaptured,
                    forcedHighlight: .none
                ),
                CampaignTutorialStep(
                    id: .targetCapture,
                    title: "目的地を取る",
                    message: "紫の目的地に着くと獲得数が増え、次の目的地へ切り替わります。",
                    instruction: "紫のマスに到達して、目的地を1個獲得しましょう。",
                    completionEvent: .targetCaptured,
                    forcedHighlight: .none
                ),
                CampaignTutorialStep(
                    id: .clearGoal,
                    title: "3個取ればクリア",
                    message: "1-1では目的地を3個取るとクリアです。全マスを踏む必要はありません。",
                    instruction: "残りの目的地を取り切りましょう。",
                    completionEvent: .targetCaptured,
                    forcedHighlight: .none
                )
            ]
        case (1, 4):
            return [
                CampaignTutorialStep(
                    id: .focus,
                    title: "困ったらフォーカス",
                    message: "フォーカスは、現在の目的地へ近づきやすいカードを優先して手札を整えます。",
                    instruction: "必要なカードが遠いと感じたら、フォーカスを使ってみましょう。",
                    completionEvent: .focusUsed,
                    forcedHighlight: .none
                )
            ]
        case (1, 6):
            return [
                CampaignTutorialStep(
                    id: .spawnSelection,
                    title: "開始マスを選ぶ",
                    message: "このステージでは、手札と先読みを見てから好きな開始マスを選べます。",
                    instruction: "動きやすそうなマスをタップして開始しましょう。",
                    completionEvent: .spawnSelected,
                    forcedHighlight: .none
                )
            ]
        case (2, 1):
            return [
                CampaignTutorialStep(
                    id: .routePlanning,
                    title: "次の候補も見る",
                    message: "近い目的地だけでなく、オレンジ点の候補も見て、次に動きやすい位置を選びます。",
                    instruction: "紫の目的地へ近づきつつ、次に戻りやすい一手を選びましょう。",
                    completionEvent: .firstMove,
                    forcedHighlight: .none
                )
            ]
        case (2, 8):
            return [
                CampaignTutorialStep(
                    id: .chapterReview,
                    title: "2章の総合演習",
                    message: "フォーカス、先読み、戻り道の判断をまとめて使うステージです。",
                    instruction: "オレンジ点も見ながら、目的地を取り切りましょう。",
                    completionEvent: .targetCaptured,
                    forcedHighlight: .none
                )
            ]
        default:
            return []
        }
    }
}

struct CampaignTutorialBannerView: View {
    let card: CampaignTutorialCard
    let theme: AppTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            Text(card.message)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            Text(card.instruction)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(theme.spawnOverlayBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(theme.spawnOverlayBorder, lineWidth: 1)
                )
        )
        .shadow(color: theme.spawnOverlayShadow, radius: 20, x: 0, y: 10)
        .foregroundColor(theme.textPrimary)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("campaign_tutorial_banner")
        .accessibilityLabel(Text("\(card.title)。\(card.message)。\(card.instruction)"))
    }
}

enum GameMenuAction: Hashable, Identifiable {
    case manualPenalty(penaltyCost: Int)
    case reset
    case returnToTitle

    var id: Int {
        switch self {
        case .manualPenalty:
            return 0
        case .reset:
            return 1
        case .returnToTitle:
            return 2
        }
    }

    var confirmationButtonTitle: String {
        switch self {
        case .manualPenalty:
            return "実行する"
        case .reset:
            return "リセットする"
        case .returnToTitle:
            return "タイトルへ戻る"
        }
    }

    var confirmationMessage: String {
        switch self {
        case .manualPenalty(let cost):
            if cost < 0 {
                return "フォーカスを使って、現在の目的地へ近づきやすいカードを優先して引き直します。スコアに15ポイント加算されます。"
            }
            if cost > 0 {
                return "手数を\(cost)増やして手札スロットを引き直します。現在の手札スロットは空になります。よろしいですか？"
            } else {
                return "手数を増やさずに手札スロットを引き直します。現在の手札スロットは空になります。よろしいですか？"
            }
        case .reset:
            return "現在の進行状況を破棄して、最初からやり直します。よろしいですか？"
        case .returnToTitle:
            return "ゲームを終了してタイトル画面へ戻ります。現在のプレイ内容は保存されません。"
        }
    }

    var buttonRole: ButtonRole? { .destructive }
}

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

@MainActor
struct ResultPresentationState {
    var showingResult = false
    var latestCampaignClearRecord: CampaignStageClearRecord?
    var newlyUnlockedStages: [CampaignStage] = []

    mutating func applyClearOutcome(_ outcome: GameFlowCoordinator.ClearOutcome) {
        latestCampaignClearRecord = outcome.latestCampaignClearRecord
        newlyUnlockedStages = outcome.newlyUnlockedStages
        showingResult = outcome.shouldShowResult
    }

    mutating func hideResult() {
        showingResult = false
    }
}

@MainActor
struct SessionUIState {
    var activePenaltyBanner: PenaltyEvent?
    var pendingMenuAction: GameMenuAction?
    var isPauseMenuPresented = false
    var displayedElapsedSeconds = 0

    mutating func updateDisplayedElapsedTime(_ seconds: Int) {
        displayedElapsedSeconds = seconds
    }

    mutating func presentPauseMenu() {
        isPauseMenuPresented = true
    }

    mutating func setPauseMenuPresented(_ isPresented: Bool) {
        isPauseMenuPresented = isPresented
    }

    mutating func requestManualPenalty(cost: Int) {
        pendingMenuAction = .manualPenalty(penaltyCost: cost)
    }

    mutating func requestReturnToTitle() {
        pendingMenuAction = .returnToTitle
    }

    mutating func clearPendingMenuAction() {
        pendingMenuAction = nil
    }

    mutating func setActivePenaltyBanner(_ event: PenaltyEvent?) {
        activePenaltyBanner = event
    }

    mutating func resetTransientUIForTitleReturn() {
        activePenaltyBanner = nil
        pendingMenuAction = nil
        isPauseMenuPresented = false
    }

    func isManualDiscardButtonEnabled(progress: GameProgress, handStacks: [HandStack]) -> Bool {
        progress == .playing && !handStacks.isEmpty
    }

    func manualDiscardAccessibilityHint(
        penaltyCost: Int,
        isAwaitingManualDiscardSelection: Bool
    ) -> String {
        if isAwaitingManualDiscardSelection {
            return "捨て札モードを終了します。カードを選ばずに通常操作へ戻ります。"
        }

        if penaltyCost > 0 {
            return "手数を\(penaltyCost)消費して、選択した手札 1 種類をまとめて捨て札にし、新しいカードを補充します。"
        } else {
            return "手数を消費せずに、選択した手札 1 種類をまとめて捨て札にし、新しいカードを補充します。"
        }
    }

    func isManualPenaltyButtonEnabled(progress: GameProgress) -> Bool {
        progress == .playing
    }

    func manualPenaltyAccessibilityHint(
        penaltyCost: Int,
        handSize: Int,
        stackingRuleDetailText: String
    ) -> String {
        let refillDescription = "手札スロットを全て空にし、新しいカードを最大 \(handSize) 種類まで補充します。"

        if penaltyCost > 0 {
            return "手数を\(penaltyCost)消費して\(refillDescription)\(stackingRuleDetailText)"
        } else {
            return "手数を消費せずに\(refillDescription)\(stackingRuleDetailText)"
        }
    }
}
