import Game
import SwiftUI

struct DailyChallengeHeaderPresentation {
    let challengeDateText: String
    let variantNames: String
    let modeNames: String
}

struct DailyChallengeCardPresentation {
    let info: DailyChallengeDefinitionService.ChallengeInfo
    let status: DailyChallengeViewModel.VariantAttemptStatus?
}

struct DailyChallengeHeaderSection: View {
    let presentation: DailyChallengeHeaderPresentation
    let theme: AppTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(presentation.challengeDateText)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundColor(theme.textPrimary)
                .accessibilityIdentifier("daily_challenge_date_label")

            Text("公開バリアント: \(presentation.variantNames)")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(theme.textSecondary)

            Text("モード名: \(presentation.modeNames)")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(theme.textSecondary.opacity(0.85))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(presentation.challengeDateText)、公開バリアントは \(presentation.variantNames)、モード名は \(presentation.modeNames) です")
    }
}

struct DailyChallengeStageCard: View {
    let presentation: DailyChallengeCardPresentation
    let theme: AppTheme
    let onShowLeaderboard: () -> Void
    let onStart: () -> Void
    let onRequestReward: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(presentation.info.variantDisplayName)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.textPrimary)

                Text(presentation.info.mode.displayName)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.accentPrimary)

                Text(presentation.info.regulationPrimaryText)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(theme.textSecondary)

                Text(presentation.info.regulationSecondaryText)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundColor(theme.textSecondary.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let status = presentation.status {
                VStack(alignment: .leading, spacing: 4) {
                    Text(status.remainingText)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.textPrimary)

                    Text(status.rewardProgressText)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(theme.textSecondary)
                }
                .accessibilityIdentifier("daily_challenge_status_\(status.identifierSuffix)")
            }

            HStack(spacing: 12) {
                Button(action: onShowLeaderboard) {
                    HStack(spacing: 8) {
                        Image(systemName: "trophy")
                        Text("ランキング")
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.accentPrimary)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(theme.accentPrimary, lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("daily_challenge_leaderboard_button_\(presentation.info.identifierSuffix)")

                Button(action: onStart) {
                    Text("挑戦する")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(Color.white)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill((presentation.status?.isStartButtonEnabled ?? false) ? theme.accentPrimary : theme.accentPrimary.opacity(0.45))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!(presentation.status?.isStartButtonEnabled ?? false))
                .accessibilityIdentifier("daily_challenge_start_button_\(presentation.info.identifierSuffix)")
            }

            if let status = presentation.status {
                Button(action: onRequestReward) {
                    HStack {
                        Image(systemName: "gift.fill")
                        Text("広告を視聴して回数を追加")
                    }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.white.opacity(status.isRewardButtonEnabled ? 1 : 0.65))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(theme.accentPrimary.opacity(status.isRewardButtonEnabled ? 0.85 : 0.45))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!status.isRewardButtonEnabled)
                .accessibilityIdentifier("daily_challenge_reward_button_\(status.identifierSuffix)")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(theme.backgroundElevated.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(theme.statisticBadgeBorder.opacity(0.6), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("daily_challenge_stage_card_\(presentation.info.identifierSuffix)")
        .accessibilityLabel("\(presentation.info.variantDisplayName)。モードは \(presentation.info.mode.displayName)。\(presentation.info.regulationPrimaryText)。\(presentation.info.regulationSecondaryText)")
    }
}

struct DailyChallengeAttemptsSection: View {
    let statuses: [DailyChallengeViewModel.VariantAttemptStatus]
    let resetTimeText: String
    let theme: AppTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(statuses) { status in
                VStack(alignment: .leading, spacing: 4) {
                    Text(status.remainingText)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.textPrimary)

                    Text(status.rewardProgressText)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(theme.textSecondary)
                }
                .accessibilityIdentifier("daily_challenge_summary_\(status.identifierSuffix)")
            }

            Text(resetTimeText)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundColor(theme.textSecondary.opacity(0.85))
                .accessibilityIdentifier("daily_challenge_reset_label")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(theme.backgroundElevated.opacity(0.8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(theme.statisticBadgeBorder.opacity(0.5), lineWidth: 1)
        )
    }
}
