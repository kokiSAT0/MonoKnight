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

            if let rogueTowerRecordText = presentation.rogueTowerRecordText {
                Text(rogueTowerRecordText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

        }
    }
}

struct ResultDetailsSection: View {
    let presentation: ResultSummaryPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("内訳")
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
                    Text("ペナルティ合計")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(presentation.penaltySummaryText)
                        .font(.body)
                        .monospacedDigit()
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

struct ResultDetailsDisclosureSection: View {
    let presentation: ResultSummaryPresentation
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ResultDetailsSection(presentation: presentation)
                .padding(.top, 8)
        } label: {
            Text("詳細")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground).opacity(0.7))
        )
        .accessibilityIdentifier("result_details_disclosure")
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
    let dungeonRewardOffers: [DungeonRewardOffer]
    let dungeonRewardCards: [PlayableCard]
    let dungeonRewardMoveCards: [MoveCard]
    let dungeonRewardSupportCards: [SupportCard]
    let dungeonRewardInventoryEntries: [DungeonInventoryEntry]
    let dungeonPickupCarryoverEntries: [DungeonInventoryEntry]
    let dungeonRewardAddUses: Int
    let dungeonRewardMoveUsesByCard: [MoveCard: Int]
    let dungeonSupportRewardAddUses: Int
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
    @State private var pendingRelicRewardPresentation: DungeonRelicAcquisitionPresentation?
    @State private var pendingRelicRewardSelection: DungeonRelicID?

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
                        Text("報酬")
                            .font(.headline)
                        Text("1つ選ぶ")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !presentedDungeonRewardOffers.isEmpty
                        || (onSelectDungeonReward != nil && !dungeonPickupCarryoverEntries.isEmpty) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("新規")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)

                            LazyVGrid(columns: rewardChoiceColumns, alignment: .leading, spacing: 8) {
                                ForEach(presentedDungeonRewardOffers, id: \.self) { offer in
                                    let isEnabled = isDungeonRewardOfferEnabled(offer)
                                    let choice = DungeonRewardCardChoicePresentation(
                                        offer: offer,
                                        rewardUses: dungeonRewardUses(for: offer),
                                        accessibilityIdentifierPrefix: dungeonRewardAccessibilityPrefix(for: offer),
                                        accessibilityRoleText: dungeonRewardAccessibilityRoleText(for: offer),
                                        isEnabled: isEnabled
                                    )
                                    Button {
                                        triggerSuccessHapticIfNeeded()
                                        selectDungeonRewardOffer(offer)
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

            if displayPolicy.showsShareLink {
                ShareLink(item: presentation.shareMessage(modeDisplayName: modeDisplayName)) {
                    Label("結果を共有", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .overlay {
            if let pendingRelicRewardPresentation {
                DungeonRelicAcquisitionOverlayView(
                    presentation: pendingRelicRewardPresentation,
                    confirmationTitle: "次の階へ",
                    onConfirm: confirmPendingRelicReward
                )
                .transition(.opacity)
            }
        }
    }

    private var hasDungeonRewardChoices: Bool {
        !presentedDungeonRewardOffers.isEmpty
            || (onSelectDungeonReward != nil && !dungeonPickupCarryoverEntries.isEmpty)
            || (onSelectDungeonReward != nil && !adjustableDungeonRewardInventoryEntries.isEmpty)
    }

    private var presentedDungeonRewardOffers: [DungeonRewardOffer] {
        let offers = dungeonRewardOffers.isEmpty ? dungeonRewardCards.map(DungeonRewardOffer.playable) : dungeonRewardOffers
        return offers.filter { offer in
            switch offer {
            case .playable(.move):
                return onSelectDungeonRewardMoveCard != nil || onSelectDungeonReward != nil
            case .playable(.support), .relic:
                return onSelectDungeonReward != nil
            }
        }
    }

    private func isDungeonRewardOfferEnabled(_ offer: DungeonRewardOffer) -> Bool {
        switch offer {
        case .playable(.move(let card)):
            return !disabledDungeonRewardMoveCards.contains(card)
        case .playable(.support(let support)):
            return !disabledDungeonRewardSupportCards.contains(support)
        case .relic:
            return true
        }
    }

    private func dungeonRewardUses(for offer: DungeonRewardOffer) -> Int {
        switch offer {
        case .playable(.move(let card)):
            return dungeonRewardMoveUsesByCard[card] ?? dungeonRewardAddUses
        case .playable(.support):
            return dungeonSupportRewardAddUses
        case .relic:
            return 0
        }
    }

    private func dungeonRewardAccessibilityPrefix(for offer: DungeonRewardOffer) -> String {
        switch offer {
        case .playable(.move):
            return "dungeon_reward_card"
        case .playable(.support):
            return "dungeon_reward_support_card"
        case .relic:
            return "dungeon_reward_relic"
        }
    }

    private func dungeonRewardAccessibilityRoleText(for offer: DungeonRewardOffer) -> String {
        switch offer {
        case .playable(.move):
            return "手札に追加するカード"
        case .playable(.support):
            return "手札に追加する補助カード"
        case .relic:
            return "獲得する遺物"
        }
    }

    private func selectDungeonRewardOffer(_ offer: DungeonRewardOffer) {
        switch offer {
        case .playable(.move(let card)):
            if let onSelectDungeonReward {
                onSelectDungeonReward(.add(card))
            } else {
                onSelectDungeonRewardMoveCard?(card)
            }
        case .playable(.support(let support)):
            onSelectDungeonReward?(.addSupport(support))
        case .relic(let relic):
            pendingRelicRewardSelection = relic
            pendingRelicRewardPresentation = .rewardRelic(relic)
        }
    }

    private func confirmPendingRelicReward() {
        guard let relic = pendingRelicRewardSelection else {
            pendingRelicRewardPresentation = nil
            return
        }
        pendingRelicRewardSelection = nil
        pendingRelicRewardPresentation = nil
        onSelectDungeonReward?(.addRelic(relic))
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
        dungeonRewardOffers: [DungeonRewardOffer] = [],
        dungeonRewardCards: [PlayableCard] = [],
        dungeonRewardMoveCards: [MoveCard] = [],
        dungeonRewardSupportCards: [SupportCard] = [],
        dungeonRewardInventoryEntries: [DungeonInventoryEntry] = [],
        dungeonPickupCarryoverEntries: [DungeonInventoryEntry] = [],
        dungeonRewardAddUses: Int = 2,
        dungeonRewardMoveUsesByCard: [MoveCard: Int] = [:],
        dungeonSupportRewardAddUses: Int = 1,
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
        self.dungeonRewardOffers = Self.resolvedDungeonRewardOffers(
            dungeonRewardOffers,
            cards: dungeonRewardCards,
            moveCards: dungeonRewardMoveCards,
            supportCards: dungeonRewardSupportCards
        )
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
        self.dungeonRewardMoveUsesByCard = dungeonRewardMoveUsesByCard
        self.dungeonSupportRewardAddUses = max(dungeonSupportRewardAddUses, 1)
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
        guard cards.isEmpty else { return cards }
        return Array((moveCards.map(PlayableCard.move) + supportCards.map(PlayableCard.support)).prefix(3))
    }

    private static func resolvedDungeonRewardOffers(
        _ offers: [DungeonRewardOffer],
        cards: [PlayableCard],
        moveCards: [MoveCard],
        supportCards: [SupportCard]
    ) -> [DungeonRewardOffer] {
        guard offers.isEmpty else { return offers }
        return resolvedDungeonRewardCards(cards, moveCards: moveCards, supportCards: supportCards)
            .map(DungeonRewardOffer.playable)
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
    let offer: DungeonRewardOffer
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
        self.offer = .playable(.move(card))
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
        self.init(
            offer: .playable(playable),
            rewardUses: rewardUses,
            actionText: actionText,
            sourceText: sourceText,
            accessibilityIdentifierPrefix: accessibilityIdentifierPrefix,
            accessibilityRoleText: accessibilityRoleText,
            isEnabled: isEnabled
        )
    }

    init(
        offer: DungeonRewardOffer,
        rewardUses: Int = 2,
        actionText: String = "獲得",
        sourceText: String? = nil,
        accessibilityIdentifierPrefix: String = "dungeon_reward_card",
        accessibilityRoleText: String = "獲得する報酬",
        isEnabled: Bool = true
    ) {
        self.offer = offer
        self.rewardUses = max(rewardUses, 1)
        self.actionText = actionText
        self.sourceText = sourceText
        self.accessibilityIdentifierPrefix = accessibilityIdentifierPrefix
        self.accessibilityRoleText = accessibilityRoleText
        self.isEnabled = isEnabled
    }

    var title: String { offer.displayName }
    var card: MoveCard {
        guard let move = offer.move else {
            preconditionFailure("補助カードには MoveCard がありません")
        }
        return move
    }
    var usesBadgeText: String {
        if let relic = offer.relic {
            return relic.displayKind.displayName
        }
        return "\(rewardUses)回"
    }
    var accessibilityIdentifier: String { "\(accessibilityIdentifierPrefix)_\(offer.displayName)" }
    var accessibilityLabel: String {
        let sourceDescription = sourceText.map { "、\($0)" } ?? ""
        guard isEnabled else {
            return "\(offer.displayName)、\(accessibilityRoleText)\(sourceDescription)、\(usesBadgeText)。手札がいっぱいです。手札から外して空きを作ってください。\(descriptionText)"
        }
        return "\(offer.displayName)、\(accessibilityRoleText)\(sourceDescription)、\(actionText)、\(usesBadgeText)。選ぶと次の階へ進みます。\(descriptionText)"
    }
    var accessibilityHint: String {
        guard isEnabled else {
            return "手札がいっぱいです。手札から外して空きを作ってください"
        }
        if offer.relic != nil {
            return "ダブルタップでこの遺物の詳細を確認します"
        }
        return "ダブルタップでこのカードを手札に追加し、次の階へ進みます"
    }

    private var descriptionText: String {
        switch offer {
        case .playable(.move(let card)):
            return card.encyclopediaDescription
        case .playable(.support(let support)):
            return support.encyclopediaDescription
        case .relic(let relic):
            if let note = relic.noteDescription {
                return "\(relic.rarity.displayName)。\(relic.displayKind.displayName)。\(relic.effectDescription) \(note)"
            }
            return "\(relic.rarity.displayName)。\(relic.displayKind.displayName)。\(relic.effectDescription)"
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
        switch choice.offer {
        case .playable(.move(let card)):
            MoveCardIllustrationView(card: card, mode: .hand)
                .scaleEffect(0.82)
                .frame(
                    width: MoveCardIllustrationView.defaultWidth * 0.82,
                    height: MoveCardIllustrationView.defaultHeight * 0.82
                )
                .accessibilityHidden(true)
        case .playable(.support(let support)):
            SupportRewardCardIllustrationView(card: support)
                .scaleEffect(0.82)
                .frame(
                    width: MoveCardIllustrationView.defaultWidth * 0.82,
                    height: MoveCardIllustrationView.defaultHeight * 0.82
                )
                .accessibilityHidden(true)
        case .relic(let relic):
            DungeonRewardRelicIllustrationView(relic: relic)
                .scaleEffect(0.82)
                .frame(
                    width: MoveCardIllustrationView.defaultWidth * 0.82,
                    height: MoveCardIllustrationView.defaultHeight * 0.82
                )
                .accessibilityHidden(true)
        }
    }
}

private struct DungeonRewardRelicIllustrationView: View {
    let relic: DungeonRelicID
    private var theme = AppTheme()

    init(relic: DungeonRelicID) {
        self.relic = relic
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: relic.symbolName)
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(theme.accentPrimary)
                .frame(width: 42, height: 42)
                .background(Circle().fill(theme.accentPrimary.opacity(0.14)))

            Text(relic.displayName)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(theme.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            HStack(spacing: 4) {
                Text(relic.rarity.displayName)
                    .foregroundColor(relic.rarity.tintColor(theme: theme))
                Text(relic.displayKind.displayName)
                    .foregroundColor(relic.displayKind.tintColor(theme: theme))
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .padding(8)
        .frame(width: MoveCardIllustrationView.defaultWidth, height: MoveCardIllustrationView.defaultHeight)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.cardBackgroundHand)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(theme.cardBorderHand, lineWidth: 1.5)
                )
        )
    }
}

struct DungeonRelicAcquisitionOverlayView: View {
    let presentation: DungeonRelicAcquisitionPresentation
    let confirmationTitle: String?
    let onConfirm: () -> Void
    private let theme = AppTheme()
    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.38)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text(presentation.title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)

                VStack(spacing: 10) {
                    ForEach(presentation.items) { item in
                        DungeonRelicAcquisitionItemRow(item: item, isEmphasized: hasAppeared)
                    }
                }

                Button {
                    onConfirm()
                } label: {
                    Label(confirmationTitle ?? presentation.confirmationTitle, systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("dungeon_relic_acquisition_confirm_button")
            }
            .padding(18)
            .frame(maxWidth: 420)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.backgroundElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.accentPrimary.opacity(0.45), lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.24), radius: 24, x: 0, y: 12)
            .padding(.horizontal, 18)
            .scaleEffect(hasAppeared ? 1 : 0.94)
            .opacity(hasAppeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                hasAppeared = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dungeon_relic_acquisition_overlay")
    }
}

private struct DungeonRelicAcquisitionItemRow: View {
    let item: DungeonRelicAcquisitionPresentation.Item
    let isEmphasized: Bool
    private let theme = AppTheme()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(itemTint.opacity(0.14))
                    .frame(width: 52, height: 52)
                Circle()
                    .stroke(itemTint.opacity(isEmphasized ? 0.42 : 0.1), lineWidth: 2)
                    .frame(width: isEmphasized ? 58 : 48, height: isEmphasized ? 58 : 48)
                Image(systemName: item.symbolName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(iconColor)
                    .scaleEffect(isEmphasized ? 1 : 0.88)
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.7), value: isEmphasized)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(item.displayName)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(theme.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let badgeText {
                        Text(badgeText)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(itemTint)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(itemTint.opacity(0.14))
                            )
                    }
                }

                Text(item.primaryDescription)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(item.secondaryDescriptions, id: \.self) { description in
                    Label(description, systemImage: "sparkles")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.cardBackgroundHand)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.cardBorderHand.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var iconColor: Color {
        itemTint
    }

    private var itemTint: Color {
        switch item {
        case .relic(let relic):
            return relic.rarity.tintColor(theme: theme)
        case .curse(let curse):
            return curse.displayKind.tintColor
        case .mimicDamage:
            return Color(red: 0.82, green: 0.16, blue: 0.22)
        case .hpCompensation:
            return theme.accentPrimary
        }
    }

    private var badgeText: String? {
        switch item {
        case .relic(let relic):
            return "\(relic.rarity.displayName) / \(relic.displayKind.displayName)"
        case .curse(let curse):
            return curse.displayKind.displayName
        case .mimicDamage, .hpCompensation:
            return nil
        }
    }

    private var accessibilityLabel: Text {
        let detail = ([item.primaryDescription] + item.secondaryDescriptions).joined(separator: "。")
        return Text("\(item.displayName)。\(detail)")
    }
}

private extension DungeonCurseDisplayKind {
    var tintColor: Color {
        switch self {
        case .temporary:
            return Color(red: 0.82, green: 0.16, blue: 0.22)
        case .persistent:
            return Color(red: 0.50, green: 0.22, blue: 0.78)
        }
    }
}

private extension DungeonRelicDisplayKind {
    func tintColor(theme: AppTheme) -> Color {
        switch self {
        case .temporary:
            return Color(red: 0.91, green: 0.46, blue: 0.10)
        case .persistent:
            return theme.accentPrimary
        }
    }
}

private extension DungeonRelicRarity {
    func tintColor(theme: AppTheme) -> Color {
        switch self {
        case .common:
            return theme.textSecondary
        case .rare:
            return Color(red: 0.18, green: 0.48, blue: 0.74)
        case .legendary:
            return Color(red: 0.78, green: 0.54, blue: 0.10)
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
