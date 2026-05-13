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

struct GameBoardTapSelectionWarning: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let destination: GridPoint
    let highlightedStackIDs: Set<UUID>

    init(message: String, destination: GridPoint, highlightedStackIDs: Set<UUID> = []) {
        self.message = message
        self.destination = destination
        self.highlightedStackIDs = highlightedStackIDs
    }
}

enum GameInlineInspection: Identifiable, Equatable {
    case tile(TileEncyclopediaEntry, point: GridPoint)
    case support(SupportCardEncyclopediaEntry, stackID: UUID)

    var id: String {
        switch self {
        case .tile(let entry, let point):
            return "tile-\(entry.id)-\(point.x)-\(point.y)"
        case .support(let entry, let stackID):
            return "support-\(entry.card.rawValue)-\(stackID.uuidString)"
        }
    }

    var displayName: String {
        switch self {
        case .tile(let entry, _):
            return entry.displayName
        case .support(let entry, _):
            return entry.displayName
        }
    }

    var category: String {
        switch self {
        case .tile(let entry, _):
            return entry.category
        case .support(let entry, _):
            return entry.category
        }
    }

    var description: String {
        switch self {
        case .tile(let entry, _):
            return entry.description
        case .support(let entry, _):
            return entry.description
        }
    }

    var systemImageName: String {
        switch self {
        case .tile(let entry, _):
            switch entry.previewKind {
            case .dungeonExit, .lockedDungeonExit:
                return "stairs"
            case .dungeonKey:
                return "key.fill"
            case .cardPickup:
                return "rectangle.stack.fill"
            case .dungeonRelicPickup:
                return "shippingbox.fill"
            case .damageTrap, .lavaTile, .brittleFloor, .collapsedFloor, .enemyDanger, .enemyWarning, .effect:
                return "exclamationmark.triangle.fill"
            case .healingTile:
                return "cross.case.fill"
            case .impassable:
                return "mountain.2.fill"
            case .normal, .spawn:
                return "square.fill"
            }
        case .support(let entry, _):
            switch entry.card {
            case .refillEmptySlots:
                return "square.grid.3x3.fill"
            case .singleAnnihilationSpell:
                return "sparkle.magnifyingglass"
            case .annihilationSpell:
                return "sparkles"
            case .freezeSpell:
                return "snowflake"
            case .barrierSpell:
                return "shield.fill"
            case .darknessSpell:
                return "moon.fill"
            case .railBreakSpell:
                return "point.topleft.down.to.point.bottomright.curvepath"
            case .antidote:
                return "cross.case.fill"
            case .panacea:
                return "pills.fill"
            }
        }
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
            if cost > 0 {
                return "手数を\(cost)増やして手札スロットを引き直します。現在の手札スロットは空になります。よろしいですか？"
            } else {
                return "手数を増やさずに手札スロットを引き直します。現在の手札スロットは空になります。よろしいですか？"
            }
        case .reset:
            return "現在の進行状況を破棄して、最初からやり直します。よろしいですか？"
        case .returnToTitle:
            return "ゲームを中断してタイトル画面へ戻ります。塔攻略中は続きから再開できます。"
        }
    }

    var buttonRole: ButtonRole? {
        switch self {
        default:
            return .destructive
        }
    }
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

    mutating func applyClearOutcome(_ outcome: GameFlowCoordinator.ClearOutcome) {
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
