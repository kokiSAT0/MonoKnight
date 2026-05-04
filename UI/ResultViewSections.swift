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

            if presentation.isNewBest {
                TimelineView(.animation) { context in
                    let progress = sin(context.date.timeIntervalSinceReferenceDate * 2.6)
                    let scale = 1.0 + 0.08 * progress

                    Text("新記録！")
                        .font(.headline.weight(.bold))
                        .foregroundColor(.yellow)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.yellow.opacity(0.18))
                                .overlay(
                                    Capsule()
                                        .stroke(Color.yellow.opacity(0.55), lineWidth: 1)
                                )
                        )
                        .scaleEffect(scale)
                        .accessibilityLabel("新記録を達成")
                }
                .transition(.scale.combined(with: .opacity))
            }

            if !presentation.usesDungeonExit && !presentation.isFailed {
                Text("ベストポイント: \(presentation.bestPointsText)")
                    .font(.headline)
            }

            if let description = presentation.bestComparisonDescription {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
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
                            Text("報酬カード")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(presentation.dungeonRewardInventoryText)
                                .font(.body)
                        }
                    }

                    if !presentation.dungeonPickupInventoryEntries.isEmpty {
                        GridRow {
                            Text("床カード")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(presentation.dungeonPickupInventoryText)
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
            return "\(floorNumber)Fの区切りに到達しました。塔選択の成長から、初期HPや報酬候補を強化できます。"
        }
        return "塔選択の成長から、初期HPや報酬候補を強化できます。"
    }
}

struct ResultActionSection: View {
    let presentation: ResultSummaryPresentation
    let modeIdentifier: GameMode.Identifier
    let nextDungeonFloorTitle: String?
    let dungeonRewardMoveCards: [MoveCard]
    let dungeonRewardInventoryEntries: [DungeonInventoryEntry]
    let dungeonPickupCarryoverEntries: [DungeonInventoryEntry]
    let dungeonRewardAddUses: Int
    let showsLeaderboardButton: Bool
    let isGameCenterAuthenticated: Bool
    let onRequestGameCenterSignIn: ((GameCenterSignInPromptReason) -> Void)?
    let onSelectNextDungeonFloor: (() -> Void)?
    let onSelectDungeonRewardMoveCard: ((MoveCard) -> Void)?
    let onSelectDungeonReward: ((DungeonRewardSelection) -> Void)?
    let onRemoveDungeonRewardCard: ((MoveCard) -> Void)?
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

                    if let onSelectDungeonRewardMoveCard,
                       !dungeonRewardMoveCards.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("新しいカードを追加")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)

                            LazyVGrid(columns: rewardChoiceColumns, alignment: .leading, spacing: 8) {
                                ForEach(dungeonRewardMoveCards, id: \.self) { card in
                                    let choice = DungeonRewardCardChoicePresentation(
                                        card: card,
                                        rewardUses: dungeonRewardAddUses,
                                        actionText: "追加して持ち越す"
                                    )
                                    Button {
                                        triggerSuccessHapticIfNeeded()
                                        onSelectDungeonRewardMoveCard(card)
                                    } label: {
                                        DungeonRewardCardChoiceView(choice: choice)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel(choice.accessibilityLabel)
                                    .accessibilityHint("ダブルタップでこの報酬を選び、次の階へ進みます")
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityIdentifier(choice.accessibilityIdentifier)
                                }
                            }
                        }
                    }

                    if let onSelectDungeonReward,
                       !dungeonPickupCarryoverEntries.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("床カードを報酬化")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)

                            LazyVGrid(columns: rewardChoiceColumns, alignment: .leading, spacing: 8) {
                                ForEach(dungeonPickupCarryoverEntries) { entry in
                                    let choice = DungeonRewardCardChoicePresentation(
                                        card: entry.card,
                                        rewardUses: dungeonRewardAddUses,
                                        actionText: "報酬カード化して持ち越す",
                                        accessibilityIdentifierPrefix: "dungeon_pickup_carryover_card",
                                        accessibilityRoleText: "床カードを報酬カード化して持ち越し"
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
                                    .accessibilityHint("ダブルタップでこの床カードを報酬カード化し、次の階へ進みます")
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityIdentifier(choice.accessibilityIdentifier)
                                }
                            }
                        }
                    }

                    if let onSelectDungeonReward,
                       let onRemoveDungeonRewardCard,
                       !dungeonRewardInventoryEntries.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("持ち越しカード")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)

                            LazyVGrid(columns: rewardCardGridColumns, alignment: .leading, spacing: 8) {
                                ForEach(dungeonRewardInventoryEntries) { entry in
                                    let carriedChoice = DungeonCarriedRewardChoicePresentation(entry: entry)
                                    DungeonCarriedRewardCardView(
                                        choice: carriedChoice,
                                        onUpgrade: {
                                            triggerSuccessHapticIfNeeded()
                                            onSelectDungeonReward(.upgrade(entry.card))
                                        },
                                        onRemove: {
                                            triggerSuccessHapticIfNeeded()
                                            onRemoveDungeonRewardCard(entry.card)
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
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
                    Text(presentation.usesDungeonExit ? "もう一度挑戦" : "リトライ")
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
        (onSelectDungeonRewardMoveCard != nil && !dungeonRewardMoveCards.isEmpty)
            || (onSelectDungeonReward != nil && !dungeonPickupCarryoverEntries.isEmpty)
            || (onSelectDungeonReward != nil && !dungeonRewardInventoryEntries.isEmpty)
    }

    private var rewardCardGridColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 132, maximum: 180), spacing: 8, alignment: .top)
        ]
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
        dungeonRewardMoveCards: [MoveCard] = [],
        dungeonRewardInventoryEntries: [DungeonInventoryEntry] = [],
        dungeonPickupCarryoverEntries: [DungeonInventoryEntry] = [],
        dungeonRewardAddUses: Int = 3,
        showsLeaderboardButton: Bool,
        isGameCenterAuthenticated: Bool,
        onRequestGameCenterSignIn: ((GameCenterSignInPromptReason) -> Void)?,
        onSelectNextDungeonFloor: (() -> Void)?,
        onSelectDungeonRewardMoveCard: ((MoveCard) -> Void)? = nil,
        onSelectDungeonReward: ((DungeonRewardSelection) -> Void)? = nil,
        onRemoveDungeonRewardCard: ((MoveCard) -> Void)? = nil,
        onRetry: @escaping () -> Void,
        onReturnToTitle: (() -> Void)?,
        gameCenterService: GameCenterServiceProtocol,
        hapticsEnabled: Bool
    ) {
        self.presentation = presentation
        self.modeIdentifier = modeIdentifier
        self.modeDisplayName = modeDisplayName
        self.nextDungeonFloorTitle = nextDungeonFloorTitle
        self.dungeonRewardMoveCards = dungeonRewardMoveCards
        self.dungeonRewardInventoryEntries = dungeonRewardInventoryEntries.filter { $0.rewardUses > 0 }
        self.dungeonPickupCarryoverEntries = dungeonPickupCarryoverEntries.filter { $0.pickupUses > 0 }
        self.dungeonRewardAddUses = max(dungeonRewardAddUses, 1)
        self.showsLeaderboardButton = showsLeaderboardButton
        self.isGameCenterAuthenticated = isGameCenterAuthenticated
        self.onRequestGameCenterSignIn = onRequestGameCenterSignIn
        self.onSelectNextDungeonFloor = onSelectNextDungeonFloor
        self.onSelectDungeonRewardMoveCard = onSelectDungeonRewardMoveCard
        self.onSelectDungeonReward = onSelectDungeonReward
        self.onRemoveDungeonRewardCard = onRemoveDungeonRewardCard
        self.onRetry = onRetry
        self.onReturnToTitle = onReturnToTitle
        self.gameCenterService = gameCenterService
        self.hapticsEnabled = hapticsEnabled
    }

    private func triggerSuccessHapticIfNeeded() {
        guard hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
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
    let card: MoveCard
    let rewardUses: Int
    let actionText: String
    let accessibilityIdentifierPrefix: String
    let accessibilityRoleText: String

    init(
        card: MoveCard,
        rewardUses: Int = 3,
        actionText: String = "追加して持ち越す",
        accessibilityIdentifierPrefix: String = "dungeon_reward_card",
        accessibilityRoleText: String = "報酬カード"
    ) {
        self.card = card
        self.rewardUses = max(rewardUses, 1)
        self.actionText = actionText
        self.accessibilityIdentifierPrefix = accessibilityIdentifierPrefix
        self.accessibilityRoleText = accessibilityRoleText
    }

    var title: String { card.displayName }
    var usesBadgeText: String { "\(rewardUses)回使える" }
    var accessibilityIdentifier: String { "\(accessibilityIdentifierPrefix)_\(card.displayName)" }
    var accessibilityLabel: String {
        "\(card.displayName)、\(accessibilityRoleText)、\(actionText)、\(rewardUses)回使える。選ぶと次の階へ進みます。\(card.encyclopediaDescription)"
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
            MoveCardIllustrationView(card: choice.card, mode: .hand)
                .scaleEffect(0.82)
                .frame(
                    width: MoveCardIllustrationView.defaultWidth * 0.82,
                    height: MoveCardIllustrationView.defaultHeight * 0.82
                )
                .accessibilityHidden(true)

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
    }
}

struct DungeonCarriedRewardChoicePresentation: Equatable {
    let card: MoveCard
    let rewardUses: Int

    init(entry: DungeonInventoryEntry) {
        self.card = entry.card
        self.rewardUses = max(entry.rewardUses, 1)
    }

    var title: String { card.displayName }
    var usesBadgeText: String { "現在\(rewardUses)回" }
    var upgradeAccessibilityLabel: String {
        "\(card.displayName)、持ち越しカード、現在\(rewardUses)回。使用回数+1。選ぶと次の階へ進みます。"
    }
    var removeAccessibilityLabel: String {
        "\(card.displayName)、持ち越しカード、現在\(rewardUses)回。持ち越しから外す。報酬は消費しません。"
    }
    var upgradeAccessibilityIdentifier: String { "dungeon_reward_upgrade_\(card.displayName)" }
    var removeAccessibilityIdentifier: String { "dungeon_reward_remove_\(card.displayName)" }
}

private struct DungeonCarriedRewardCardView: View {
    let choice: DungeonCarriedRewardChoicePresentation
    let onUpgrade: () -> Void
    let onRemove: () -> Void
    private var theme = AppTheme()

    init(
        choice: DungeonCarriedRewardChoicePresentation,
        onUpgrade: @escaping () -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.choice = choice
        self.onUpgrade = onUpgrade
        self.onRemove = onRemove
    }

    var body: some View {
        VStack(spacing: 7) {
            MoveCardIllustrationView(card: choice.card, mode: .hand)
                .scaleEffect(0.92)
                .frame(
                    width: MoveCardIllustrationView.defaultWidth,
                    height: MoveCardIllustrationView.defaultHeight * 0.92
                )
                .accessibilityHidden(true)

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

            HStack(spacing: 10) {
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
                .accessibilityHint("ダブルタップでこのカードを持ち越しから外します")
                .accessibilityIdentifier(choice.removeAccessibilityIdentifier)
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
}
