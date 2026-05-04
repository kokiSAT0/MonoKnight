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

            Text("塔選択の成長から、初期HPや報酬候補を強化できます。")
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
}

struct ResultActionSection: View {
    let presentation: ResultSummaryPresentation
    let modeIdentifier: GameMode.Identifier
    let nextDungeonFloorTitle: String?
    let dungeonRewardMoveCards: [MoveCard]
    let dungeonRewardInventoryEntries: [DungeonInventoryEntry]
    let showsLeaderboardButton: Bool
    let isGameCenterAuthenticated: Bool
    let onRequestGameCenterSignIn: ((GameCenterSignInPromptReason) -> Void)?
    let onSelectNextDungeonFloor: (() -> Void)?
    let onSelectDungeonRewardMoveCard: ((MoveCard) -> Void)?
    let onSelectDungeonReward: ((DungeonRewardSelection) -> Void)?
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
               dungeonRewardMoveCards.isEmpty {
                Button {
                    triggerSuccessHapticIfNeeded()
                    onSelectNextDungeonFloor()
                } label: {
                    Label("次の階へ: \(nextDungeonFloorTitle)", systemImage: "arrow.up.forward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            if let onSelectDungeonRewardMoveCard,
               presentation.usesDungeonExit,
               !presentation.isFailed,
               !dungeonRewardMoveCards.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("カードを増やす")
                        .font(.headline)

                    HStack(alignment: .top, spacing: 8) {
                        ForEach(dungeonRewardMoveCards, id: \.self) { card in
                            let choice = DungeonRewardCardChoicePresentation(card: card)
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
               presentation.usesDungeonExit,
               !presentation.isFailed,
               !dungeonRewardInventoryEntries.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("持ち越しカードを整える")
                        .font(.headline)

                    VStack(spacing: 8) {
                        ForEach(dungeonRewardInventoryEntries) { entry in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(entry.card.displayName)×\(entry.rewardUses)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)

                                HStack(spacing: 8) {
                                    Button {
                                        triggerSuccessHapticIfNeeded()
                                        onSelectDungeonReward(.upgrade(entry.card))
                                    } label: {
                                        Label("使用回数+1", systemImage: "plus.circle")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .accessibilityIdentifier("dungeon_reward_upgrade_\(entry.card.displayName)")

                                    Button {
                                        triggerSuccessHapticIfNeeded()
                                        onSelectDungeonReward(.remove(entry.card))
                                    } label: {
                                        Label("持ち越しから外す", systemImage: "minus.circle")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .accessibilityIdentifier("dungeon_reward_remove_\(entry.card.displayName)")
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(UIColor.secondarySystemBackground))
                            )
                        }
                    }
                }
            }

            if let onReturnToTitle {
                Button {
                    triggerSuccessHapticIfNeeded()
                    onReturnToTitle()
                } label: {
                    Label("ホームへ戻る", systemImage: "house")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Button {
                triggerSuccessHapticIfNeeded()
                onRetry()
            } label: {
                Text(presentation.usesDungeonExit ? "もう一度挑戦" : "リトライ")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            if showsLeaderboardButton {
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

            ShareLink(item: presentation.shareMessage(modeDisplayName: modeDisplayName)) {
                Label("結果を共有", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private let modeDisplayName: String

    init(
        presentation: ResultSummaryPresentation,
        modeIdentifier: GameMode.Identifier,
        modeDisplayName: String,
        nextDungeonFloorTitle: String?,
        dungeonRewardMoveCards: [MoveCard] = [],
        dungeonRewardInventoryEntries: [DungeonInventoryEntry] = [],
        showsLeaderboardButton: Bool,
        isGameCenterAuthenticated: Bool,
        onRequestGameCenterSignIn: ((GameCenterSignInPromptReason) -> Void)?,
        onSelectNextDungeonFloor: (() -> Void)?,
        onSelectDungeonRewardMoveCard: ((MoveCard) -> Void)? = nil,
        onSelectDungeonReward: ((DungeonRewardSelection) -> Void)? = nil,
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
        self.showsLeaderboardButton = showsLeaderboardButton
        self.isGameCenterAuthenticated = isGameCenterAuthenticated
        self.onRequestGameCenterSignIn = onRequestGameCenterSignIn
        self.onSelectNextDungeonFloor = onSelectNextDungeonFloor
        self.onSelectDungeonRewardMoveCard = onSelectDungeonRewardMoveCard
        self.onSelectDungeonReward = onSelectDungeonReward
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

struct DungeonRewardCardChoicePresentation: Equatable {
    let card: MoveCard

    var title: String { card.displayName }
    var description: String { card.encyclopediaDescription }
    var usesBadgeText: String { "3回使える" }
    var accessibilityIdentifier: String { "dungeon_reward_card_\(card.displayName)" }
    var accessibilityLabel: String {
        "\(card.displayName)、報酬カード、3回使える。\(card.encyclopediaDescription)"
    }
}

private struct DungeonRewardCardChoiceView: View {
    let choice: DungeonRewardCardChoicePresentation
    private var theme = AppTheme()

    init(choice: DungeonRewardCardChoicePresentation) {
        self.choice = choice
    }

    var body: some View {
        VStack(spacing: 8) {
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

            Text(choice.description)
                .font(.caption)
                .foregroundColor(theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .frame(minHeight: 30, alignment: .top)
        }
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .top)
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
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
