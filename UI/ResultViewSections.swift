import Game
import SwiftUI
import UIKit

struct ResultSummarySection: View {
    let presentation: ResultSummaryPresentation

    var body: some View {
        VStack(spacing: 12) {
            Text(presentation.resultTitle)
                .font(.title)
                .padding(.top, 16)

            if let subtitle = presentation.resultSubtitle {
                Text(subtitle)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

        }
    }
}

struct ResultDetailsSection: View {
    let presentation: ResultSummaryPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("リザルト詳細")
                .font(.headline)
                .padding(.top, 8)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("合計手数")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(presentation.totalMoves) 手")
                        .font(.body)
                        .monospacedDigit()
                }

                GridRow {
                    Text("移動回数")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(presentation.moveCount) 手")
                        .font(.body)
                        .monospacedDigit()
                }

                GridRow {
                    Text(presentation.usesTargetCollection ? "フォーカス" : "ペナルティ合計")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(presentation.penaltySummaryText)
                        .font(.body)
                        .monospacedDigit()
                }

                if presentation.usesTargetCollection {
                    GridRow {
                        Text("フォーカス加点")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(presentation.focusPoints) pt")
                            .font(.body)
                            .monospacedDigit()
                    }
                }

                if presentation.usesDungeonExit {
                    if let dungeonRunFloorText = presentation.dungeonRunFloorText {
                        GridRow {
                            Text("到達階")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(dungeonRunFloorText)
                                .font(.body)
                        }
                    }

                    if let dungeonRunTotalMoveCount = presentation.dungeonRunTotalMoveCount {
                        GridRow {
                            Text("塔累計手数")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("\(dungeonRunTotalMoveCount) 手")
                                .font(.body)
                                .monospacedDigit()
                        }
                    }

                    GridRow {
                        Text("残HP")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(presentation.dungeonHP ?? 0)")
                            .font(.body)
                            .monospacedDigit()
                    }

                    GridRow {
                        Text("残り手数")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(presentation.remainingDungeonTurns.map { "\($0) 手" } ?? "-")
                            .font(.body)
                            .monospacedDigit()
                    }

                    if !presentation.dungeonRewardInventoryEntries.isEmpty {
                        GridRow {
                            Text("手札")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(presentation.dungeonRewardInventoryText)
                                .font(.body)
                        }
                    }

                }

                GridRow {
                    Text("所要時間")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(presentation.formattedElapsedTime)
                        .font(.body)
                        .monospacedDigit()
                }

                if !presentation.usesDungeonExit && !presentation.isFailed {
                    Divider()
                        .gridCellColumns(2)

                    GridRow {
                        Text("手数ポイント")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("10pt × \(presentation.totalMoves)手 = \(presentation.movePoints) pt")
                            .font(.body)
                            .monospacedDigit()
                    }

                    GridRow {
                        Text("時間ポイント")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(presentation.elapsedSeconds)秒 = \(presentation.timePoints) pt")
                            .font(.body)
                            .monospacedDigit()
                    }

                    Divider()
                        .gridCellColumns(2)

                    GridRow {
                        Text("合計ポイント")
                            .font(.subheadline.weight(.semibold))
                        Text("\(presentation.movePoints) + \(presentation.timePoints) = \(presentation.points) pt")
                            .font(.body.weight(.semibold))
                            .monospacedDigit()
                    }
                }
            }
        }
    }
}

struct DungeonGrowthAwardSection: View {
    let award: DungeonGrowthAward
    private var theme = AppTheme()

    init(award: DungeonGrowthAward) {
        self.award = award
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("成長ポイント +\(award.points)", systemImage: "sparkles")
                .font(.headline)
                .foregroundColor(theme.textPrimary)

            Text(rewardSummaryText)
                .font(.subheadline)
                .foregroundColor(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.backgroundElevated.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.statisticBadgeBorder, lineWidth: 1)
        )
        .accessibilityIdentifier("dungeon_growth_award_section")
    }

    private var rewardSummaryText: String {
        if let floorNumber = award.milestoneFloorNumber {
            return "\(floorNumber)Fの区切りに到達しました。成長塔カードの成長から、初期HPや報酬候補を強化できます。"
        }
        return "成長塔カードの成長から、初期HPや報酬候補を強化できます。"
    }
}

struct ResultActionSection: View {
    let presentation: ResultSummaryPresentation
    let modeIdentifier: GameMode.Identifier
    let nextDungeonFloorTitle: String?
    let retryButtonTitle: String
    let dungeonRewardCards: [PlayableCard]
    let dungeonRewardMoveCards: [MoveCard]
    let dungeonRewardSupportCards: [SupportCard]
    let dungeonRewardInventoryEntries: [DungeonInventoryEntry]
    let dungeonPickupCarryoverEntries: [DungeonInventoryEntry]
    let dungeonRewardAddUses: Int
    let disabledDungeonRewardMoveCards: Set<MoveCard>
    let disabledDungeonRewardSupportCards: Set<SupportCard>
    let showsLeaderboardButton: Bool
    let isGameCenterAuthenticated: Bool
    let onRequestGameCenterSignIn: ((GameCenterSignInPromptReason) -> Void)?
    let onSelectNextDungeonFloor: (() -> Void)?
    let onSelectDungeonRewardMoveCard: ((MoveCard) -> Void)?
    let onSelectDungeonReward: ((DungeonRewardSelection) -> Void)?
    let onRemoveDungeonRewardCard: ((MoveCard) -> Void)?
    let onRemoveDungeonRewardSupportCard: ((SupportCard) -> Void)?
    let onInspectFailedBoard: (() -> Void)?
    let onRetry: () -> Void
    let onReturnToTitle: (() -> Void)?
    let gameCenterService: GameCenterServiceProtocol
    let hapticsEnabled: Bool

    var body: some View {
        VStack(spacing: 16) {
            if let nextDungeonFloorTitle,
               let onSelectNextDungeonFloor,
               presentation.usesDungeonExit,
               !presentation.isFailed,
               !hasDungeonRewardChoices {
                Button {
                    triggerSuccessHapticIfNeeded()
                    onSelectNextDungeonFloor()
                } label: {
                    Label("次の階へ: \(nextDungeonFloorTitle)", systemImage: "arrow.up.forward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            if hasDungeonRewardChoices,
               presentation.usesDungeonExit,
               !presentation.isFailed {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("報酬を1つ選ぶ")
                            .font(.headline)
                        Text("選ぶと次の階へ進みます")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !presentedDungeonRewardCards.isEmpty
                        || (onSelectDungeonReward != nil && !dungeonPickupCarryoverEntries.isEmpty) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("カードを手札に追加")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)

                            LazyVGrid(columns: rewardChoiceColumns, alignment: .leading, spacing: 8) {
                                ForEach(presentedDungeonRewardCards, id: \.self) { playable in
                                    let isEnabled = isDungeonRewardPlayableEnabled(playable)
                                    let choice = DungeonRewardCardChoicePresentation(
                                        playable: playable,
                                        rewardUses: dungeonRewardUses(for: playable),
                                        accessibilityIdentifierPrefix: dungeonRewardAccessibilityPrefix(for: playable),
                                        accessibilityRoleText: dungeonRewardAccessibilityRoleText(for: playable),
                                        isEnabled: isEnabled
                                    )
                                    Button {
                                        triggerSuccessHapticIfNeeded()
                                        selectDungeonRewardPlayable(playable)
                                    } label: {
                                        DungeonRewardCardChoiceView(choice: choice)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!isEnabled)
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel(choice.accessibilityLabel)
                                    .accessibilityHint(choice.accessibilityHint)
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityIdentifier(choice.accessibilityIdentifier)
                                }

                                if let onSelectDungeonReward {
                                    ForEach(dungeonPickupCarryoverEntries) { entry in
                                        let choice = DungeonRewardCardChoicePresentation(
                                            card: entry.card,
                                            rewardUses: dungeonRewardAddUses,
                                            sourceText: "このフロアで拾ったカード",
                                            accessibilityIdentifierPrefix: "dungeon_pickup_carryover_card",
                                            accessibilityRoleText: "手札に追加するカード"
                                        )
                                        Button {
                                            triggerSuccessHapticIfNeeded()
                                            onSelectDungeonReward(.carryOverPickup(entry.card))
                                        } label: {
                                            DungeonRewardCardChoiceView(choice: choice)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityElement(children: .ignore)
                                        .accessibilityLabel(choice.accessibilityLabel)
                                        .accessibilityHint("ダブルタップでこのカードを手札に追加し、次の階へ進みます")
                                        .accessibilityAddTraits(.isButton)
                                        .accessibilityIdentifier(choice.accessibilityIdentifier)
                                    }
                                }
                            }
                        }
                    }

                    dungeonInventoryHandSection
                }
            }

            if !hasDungeonRewardChoices,
               presentation.usesDungeonExit,
               !presentation.isFailed {
                dungeonInventoryHandSection
            }

            if displayPolicy.showsInspectFailedBoardButton,
               let onInspectFailedBoard {
                Button {
                    triggerSuccessHapticIfNeeded()
                    onInspectFailedBoard()
                } label: {
                    Label("盤面を見る", systemImage: "square.grid.3x3")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if displayPolicy.showsReturnToTitleButton,
               let onReturnToTitle {
                Button {
                    triggerSuccessHapticIfNeeded()
                    onReturnToTitle()
                } label: {
                    Label("ホームへ戻る", systemImage: "house")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if displayPolicy.showsRetryButton {
                Button {
                    triggerSuccessHapticIfNeeded()
                    onRetry()
                } label: {
                    Text(retryButtonTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            if displayPolicy.showsLeaderboardButton {
                Button {
                    triggerSuccessHapticIfNeeded()
                    if isGameCenterAuthenticated {
                        gameCenterService.showLeaderboard(for: modeIdentifier)
                    } else {
                        onRequestGameCenterSignIn?(.leaderboardRequestedWhileUnauthenticated)
                    }
                } label: {
                    Text(isGameCenterAuthenticated ? "ランキング" : "サインインしてランキングを見る")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                if !isGameCenterAuthenticated {
                    Text("Game Center にサインインするとランキングを表示できます。設定画面からサインインした後に再度お試しください。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
            }

            if displayPolicy.showsShareLink {
                ShareLink(item: presentation.shareMessage(modeDisplayName: modeDisplayName)) {
                    Label("結果を共有", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var hasDungeonRewardChoices: Bool {
        !presentedDungeonRewardCards.isEmpty
            || (onSelectDungeonReward != nil && !dungeonPickupCarryoverEntries.isEmpty)
            || (onSelectDungeonReward != nil && !adjustableDungeonRewardInventoryEntries.isEmpty)
    }

    private var presentedDungeonRewardCards: [PlayableCard] {
        dungeonRewardCards.filter { playable in
            switch playable {
            case .move:
                return onSelectDungeonRewardMoveCard != nil || onSelectDungeonReward != nil
            case .support:
                return onSelectDungeonReward != nil
            }
        }
    }

    private func isDungeonRewardPlayableEnabled(_ playable: PlayableCard) -> Bool {
        switch playable {
        case .move(let card):
            return !disabledDungeonRewardMoveCards.contains(card)
        case .support(let support):
            return !disabledDungeonRewardSupportCards.contains(support)
        }
    }

    private func dungeonRewardUses(for playable: PlayableCard) -> Int {
        switch playable {
        case .move:
            return dungeonRewardAddUses
        case .support(let support):
            return DungeonRunState.rewardUses(for: support)
        }
    }

    private func dungeonRewardAccessibilityPrefix(for playable: PlayableCard) -> String {
        switch playable {
        case .move:
            return "dungeon_reward_card"
        case .support:
            return "dungeon_reward_support_card"
        }
    }

    private func dungeonRewardAccessibilityRoleText(for playable: PlayableCard) -> String {
        switch playable {
        case .move:
            return "手札に追加するカード"
        case .support:
            return "手札に追加する補助カード"
        }
    }

    private func selectDungeonRewardPlayable(_ playable: PlayableCard) {
        switch playable {
        case .move(let card):
            if let onSelectDungeonReward {
                onSelectDungeonReward(.add(card))
            } else {
                onSelectDungeonRewardMoveCard?(card)
            }
        case .support(let support):
            onSelectDungeonReward?(.addSupport(support))
        }
    }

    private var adjustableDungeonRewardInventoryEntries: [DungeonInventoryEntry] {
        dungeonRewardInventoryEntries.filter(\.hasUsesRemaining)
    }

    @ViewBuilder
    private var dungeonInventoryHandSection: some View {
        if !dungeonRewardInventoryEntries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("手札")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: rewardCardGridColumns, alignment: .leading, spacing: 8) {
                    ForEach(dungeonRewardInventoryEntries) { entry in
                        let carriedChoice = DungeonCarriedRewardChoicePresentation(entry: entry)
                        DungeonCarriedRewardCardView(
                            choice: carriedChoice,
                            onUpgrade: upgradeAction(for: entry),
                            onRemove: removeAction(for: entry)
                        )
                    }
                }
            }
        }
    }

    private func upgradeAction(for entry: DungeonInventoryEntry) -> (() -> Void)? {
        guard entry.hasUsesRemaining, let onSelectDungeonReward else { return nil }
        return {
            triggerSuccessHapticIfNeeded()
            if let move = entry.moveCard {
                onSelectDungeonReward(.upgrade(move))
            } else if let support = entry.supportCard {
                onSelectDungeonReward(.upgradeSupport(support))
            }
        }
    }

    private func removeAction(for entry: DungeonInventoryEntry) -> (() -> Void)? {
        guard entry.hasUsesRemaining else { return nil }
        if entry.moveCard != nil {
            guard onRemoveDungeonRewardCard != nil else { return nil }
        } else if entry.supportCard != nil {
            guard onRemoveDungeonRewardSupportCard != nil else { return nil }
        }
        return {
            triggerSuccessHapticIfNeeded()
            if let move = entry.moveCard {
                onRemoveDungeonRewardCard?(move)
            } else if let support = entry.supportCard {
                onRemoveDungeonRewardSupportCard?(support)
            }
        }
    }

    private var rewardCardGridColumns: [GridItem] {
        Self.fixedThreeColumnGridItems(spacing: 8)
    }

    private var rewardChoiceColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 0), spacing: 6, alignment: .top),
            count: 3
        )
    }

    private var displayPolicy: ResultActionDisplayPolicy {
        ResultActionDisplayPolicy(
            usesDungeonExit: presentation.usesDungeonExit,
            isFailed: presentation.isFailed,
            hasNextDungeonFloor: nextDungeonFloorTitle != nil,
            allowsLeaderboardButton: showsLeaderboardButton,
            hasReturnToTitle: onReturnToTitle != nil
        )
    }

    private let modeDisplayName: String

    init(
        presentation: ResultSummaryPresentation,
        modeIdentifier: GameMode.Identifier,
        modeDisplayName: String,
        nextDungeonFloorTitle: String?,
        retryButtonTitle: String,
        dungeonRewardCards: [PlayableCard] = [],
        dungeonRewardMoveCards: [MoveCard] = [],
        dungeonRewardSupportCards: [SupportCard] = [],
        dungeonRewardInventoryEntries: [DungeonInventoryEntry] = [],
        dungeonPickupCarryoverEntries: [DungeonInventoryEntry] = [],
        dungeonRewardAddUses: Int = 2,
        disabledDungeonRewardMoveCards: Set<MoveCard> = [],
        disabledDungeonRewardSupportCards: Set<SupportCard> = [],
        showsLeaderboardButton: Bool,
        isGameCenterAuthenticated: Bool,
        onRequestGameCenterSignIn: ((GameCenterSignInPromptReason) -> Void)?,
        onSelectNextDungeonFloor: (() -> Void)?,
        onSelectDungeonRewardMoveCard: ((MoveCard) -> Void)? = nil,
        onSelectDungeonReward: ((DungeonRewardSelection) -> Void)? = nil,
        onRemoveDungeonRewardCard: ((MoveCard) -> Void)? = nil,
        onRemoveDungeonRewardSupportCard: ((SupportCard) -> Void)? = nil,
        onInspectFailedBoard: (() -> Void)? = nil,
        onRetry: @escaping () -> Void,
        onReturnToTitle: (() -> Void)?,
        gameCenterService: GameCenterServiceProtocol,
        hapticsEnabled: Bool
    ) {
        self.presentation = presentation
        self.modeIdentifier = modeIdentifier
        self.modeDisplayName = modeDisplayName
        self.nextDungeonFloorTitle = nextDungeonFloorTitle
        self.retryButtonTitle = retryButtonTitle
        self.dungeonRewardCards = Self.resolvedDungeonRewardCards(
            dungeonRewardCards,
            moveCards: dungeonRewardMoveCards,
            supportCards: dungeonRewardSupportCards
        )
        self.dungeonRewardMoveCards = dungeonRewardMoveCards
        self.dungeonRewardSupportCards = dungeonRewardSupportCards
        self.dungeonRewardInventoryEntries = dungeonRewardInventoryEntries.filter(\.hasUsesRemaining)
        self.dungeonPickupCarryoverEntries = dungeonPickupCarryoverEntries.filter(\.hasUsesRemaining)
        self.dungeonRewardAddUses = max(dungeonRewardAddUses, 1)
        self.disabledDungeonRewardMoveCards = disabledDungeonRewardMoveCards
        self.disabledDungeonRewardSupportCards = disabledDungeonRewardSupportCards
        self.showsLeaderboardButton = showsLeaderboardButton
        self.isGameCenterAuthenticated = isGameCenterAuthenticated
        self.onRequestGameCenterSignIn = onRequestGameCenterSignIn
        self.onSelectNextDungeonFloor = onSelectNextDungeonFloor
        self.onSelectDungeonRewardMoveCard = onSelectDungeonRewardMoveCard
        self.onSelectDungeonReward = onSelectDungeonReward
        self.onRemoveDungeonRewardCard = onRemoveDungeonRewardCard
        self.onRemoveDungeonRewardSupportCard = onRemoveDungeonRewardSupportCard
        self.onInspectFailedBoard = onInspectFailedBoard
        self.onRetry = onRetry
        self.onReturnToTitle = onReturnToTitle
        self.gameCenterService = gameCenterService
        self.hapticsEnabled = hapticsEnabled
    }

    private static func resolvedDungeonRewardCards(
        _ cards: [PlayableCard],
        moveCards: [MoveCard],
        supportCards: [SupportCard]
    ) -> [PlayableCard] {
        guard cards.isEmpty else { return Array(cards.prefix(3)) }
        return Array((moveCards.map(PlayableCard.move) + supportCards.map(PlayableCard.support)).prefix(3))
    }

    private func triggerSuccessHapticIfNeeded() {
        guard hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

extension ResultActionSection {
    static let resultHandGridColumnCount = 3

    static func fixedThreeColumnGridItems(spacing: CGFloat) -> [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 0), spacing: spacing, alignment: .top),
            count: resultHandGridColumnCount
        )
    }
}

struct ResultActionDisplayPolicy: Equatable {
    let usesDungeonExit: Bool
    let isFailed: Bool
    let hasNextDungeonFloor: Bool
    let allowsLeaderboardButton: Bool
    let hasReturnToTitle: Bool

    var isIntermediateDungeonClear: Bool {
        usesDungeonExit && !isFailed && hasNextDungeonFloor
    }

    var showsReturnToTitleButton: Bool {
        !isIntermediateDungeonClear && hasReturnToTitle
    }

    var showsInspectFailedBoardButton: Bool {
        usesDungeonExit && isFailed
    }

    var showsRetryButton: Bool {
        !isIntermediateDungeonClear
    }

    var showsLeaderboardButton: Bool {
        !isIntermediateDungeonClear && allowsLeaderboardButton
    }

    var showsShareLink: Bool {
        !isIntermediateDungeonClear
    }
}

struct DungeonRewardCardChoicePresentation: Equatable {
    let playable: PlayableCard
    let rewardUses: Int
    let actionText: String
    let sourceText: String?
    let accessibilityIdentifierPrefix: String
    let accessibilityRoleText: String
    let isEnabled: Bool

    init(
        card: MoveCard,
        rewardUses: Int = 2,
        actionText: String = "手札に追加",
        sourceText: String? = nil,
        accessibilityIdentifierPrefix: String = "dungeon_reward_card",
        accessibilityRoleText: String = "手札に追加するカード",
        isEnabled: Bool = true
    ) {
        self.playable = .move(card)
        self.rewardUses = max(rewardUses, 1)
        self.actionText = actionText
        self.sourceText = sourceText
        self.accessibilityIdentifierPrefix = accessibilityIdentifierPrefix
        self.accessibilityRoleText = accessibilityRoleText
        self.isEnabled = isEnabled
    }

    init(
        playable: PlayableCard,
        rewardUses: Int = 2,
        actionText: String = "手札に追加",
        sourceText: String? = nil,
        accessibilityIdentifierPrefix: String = "dungeon_reward_card",
        accessibilityRoleText: String = "手札に追加するカード",
        isEnabled: Bool = true
    ) {
        self.playable = playable
        self.rewardUses = max(rewardUses, 1)
        self.actionText = actionText
        self.sourceText = sourceText
        self.accessibilityIdentifierPrefix = accessibilityIdentifierPrefix
        self.accessibilityRoleText = accessibilityRoleText
        self.isEnabled = isEnabled
    }

    var title: String { playable.displayName }
    var card: MoveCard {
        guard let move = playable.move else {
            preconditionFailure("補助カードには MoveCard がありません")
        }
        return move
    }
    var usesBadgeText: String { "\(rewardUses)回" }
    var accessibilityIdentifier: String { "\(accessibilityIdentifierPrefix)_\(playable.displayName)" }
    var accessibilityLabel: String {
        let sourceDescription = sourceText.map { "、\($0)" } ?? ""
        guard isEnabled else {
            return "\(playable.displayName)、\(accessibilityRoleText)\(sourceDescription)、\(rewardUses)回。手札がいっぱいです。手札から外して空きを作ってください。\(descriptionText)"
        }
        return "\(playable.displayName)、\(accessibilityRoleText)\(sourceDescription)、\(actionText)、\(rewardUses)回。選ぶと次の階へ進みます。\(descriptionText)"
    }
    var accessibilityHint: String {
        if isEnabled {
            return "ダブルタップでこのカードを手札に追加し、次の階へ進みます"
        }
        return "手札がいっぱいです。手札から外して空きを作ってください"
    }

    private var descriptionText: String {
        switch playable {
        case .move(let card):
            return card.encyclopediaDescription
        case .support(let support):
            return support.encyclopediaDescription
        }
    }
}

private struct DungeonRewardCardChoiceView: View {
    let choice: DungeonRewardCardChoicePresentation
    private var theme = AppTheme()

    init(choice: DungeonRewardCardChoicePresentation) {
        self.choice = choice
    }

    var body: some View {
        VStack(spacing: 7) {
            rewardIllustration

            Text(choice.title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(choice.usesBadgeText)
                .font(.caption2.weight(.bold))
                .foregroundColor(theme.accentOnPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule(style: .continuous).fill(theme.accentPrimary))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if let sourceText = choice.sourceText {
                Text(sourceText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 134, alignment: .top)
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.backgroundElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.cardBorderHand.opacity(0.24), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .opacity(choice.isEnabled ? 1 : 0.42)
        .grayscale(choice.isEnabled ? 0 : 0.35)
    }

    @ViewBuilder
    private var rewardIllustration: some View {
        switch choice.playable {
        case .move(let card):
            MoveCardIllustrationView(card: card, mode: .hand)
                .scaleEffect(0.82)
                .frame(
                    width: MoveCardIllustrationView.defaultWidth * 0.82,
                    height: MoveCardIllustrationView.defaultHeight * 0.82
                )
                .accessibilityHidden(true)
        case .support(let support):
            SupportRewardCardIllustrationView(card: support)
                .scaleEffect(0.82)
                .frame(
                    width: MoveCardIllustrationView.defaultWidth * 0.82,
                    height: MoveCardIllustrationView.defaultHeight * 0.82
                )
                .accessibilityHidden(true)
        }
    }
}

struct DungeonCarriedRewardChoicePresentation: Equatable {
    let playable: PlayableCard
    let totalUses: Int
    let isAdjustable: Bool

    init(entry: DungeonInventoryEntry) {
        self.playable = entry.playable
        self.totalUses = max(entry.totalUses, 1)
        self.isAdjustable = entry.hasUsesRemaining
    }

    var title: String { playable.displayName }
    var usesBadgeText: String { "現在\(totalUses)回" }
    var upgradeAccessibilityLabel: String {
        "\(playable.displayName)、手札、現在\(totalUses)回。使用回数+1。選ぶと次の階へ進みます。"
    }
    var removeAccessibilityLabel: String {
        "\(playable.displayName)、手札、現在\(totalUses)回。手札から外す。報酬は消費しません。"
    }
    var upgradeAccessibilityIdentifier: String { "dungeon_reward_upgrade_\(playable.displayName)" }
    var removeAccessibilityIdentifier: String { "dungeon_reward_remove_\(playable.displayName)" }
}

private struct DungeonCarriedRewardCardView: View {
    let choice: DungeonCarriedRewardChoicePresentation
    let onUpgrade: (() -> Void)?
    let onRemove: (() -> Void)?
    private var theme = AppTheme()

    init(
        choice: DungeonCarriedRewardChoicePresentation,
        onUpgrade: (() -> Void)?,
        onRemove: (() -> Void)?
    ) {
        self.choice = choice
        self.onUpgrade = onUpgrade
        self.onRemove = onRemove
    }

    var body: some View {
        VStack(spacing: 7) {
            carriedIllustration

            Text(choice.title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(choice.usesBadgeText)
                .font(.caption2.weight(.bold))
                .foregroundColor(theme.accentOnPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule(style: .continuous).fill(theme.accentPrimary))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if choice.isAdjustable {
                HStack(spacing: 10) {
                    if let onUpgrade {
                        Button {
                            onUpgrade()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3.weight(.semibold))
                                .frame(width: 34, height: 34)
                                .foregroundStyle(theme.accentPrimary)
                                .background(
                                    Circle()
                                        .fill(theme.accentPrimary.opacity(0.12))
                                )
                        }
                        .buttonStyle(.plain)
                        .controlSize(.small)
                        .accessibilityLabel(choice.upgradeAccessibilityLabel)
                        .accessibilityHint("ダブルタップでこのカードの使用回数を増やし、次の階へ進みます")
                        .accessibilityIdentifier(choice.upgradeAccessibilityIdentifier)
                    }

                    if let onRemove {
                        Button {
                            onRemove()
                        } label: {
                            Image(systemName: "trash.circle.fill")
                                .font(.title3.weight(.semibold))
                                .frame(width: 34, height: 34)
                                .foregroundStyle(.red)
                                .background(
                                    Circle()
                                        .fill(Color.red.opacity(0.11))
                                )
                        }
                        .buttonStyle(.plain)
                        .controlSize(.small)
                        .accessibilityLabel(choice.removeAccessibilityLabel)
                        .accessibilityHint("ダブルタップでこのカードを手札から外します")
                        .accessibilityIdentifier(choice.removeAccessibilityIdentifier)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .top)
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.backgroundElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.cardBorderHand.opacity(0.24), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var carriedIllustration: some View {
        switch choice.playable {
        case .move(let card):
            MoveCardIllustrationView(card: card, mode: .hand)
                .scaleEffect(0.92)
                .frame(
                    width: MoveCardIllustrationView.defaultWidth,
                    height: MoveCardIllustrationView.defaultHeight * 0.92
                )
                .accessibilityHidden(true)
        case .support(let support):
            SupportRewardCardIllustrationView(card: support)
                .scaleEffect(0.92)
                .frame(
                    width: MoveCardIllustrationView.defaultWidth,
                    height: MoveCardIllustrationView.defaultHeight * 0.92
                )
                .accessibilityHidden(true)
        }
    }
}

private struct SupportRewardCardIllustrationView: View {
    let card: SupportCard
    private var theme = AppTheme()

    init(card: SupportCard) {
        self.card = card
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbolName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(theme.accentPrimary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(theme.accentPrimary.opacity(0.14)))

            Text(card.displayName)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(theme.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)

            Text("補助")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(theme.textSecondary)
        }
        .padding(8)
        .frame(width: MoveCardIllustrationView.defaultWidth, height: MoveCardIllustrationView.defaultHeight)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.cardBackgroundHand)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(theme.accentPrimary.opacity(0.75), lineWidth: 2)
                )
        )
    }

    private var symbolName: String {
        switch card {
        case .refillEmptySlots:
            return "square.grid.3x3.fill"
        }
    }
}
