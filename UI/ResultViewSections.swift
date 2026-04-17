import Game
import SwiftUI

struct ResultSummarySection: View {
    let presentation: ResultSummaryPresentation

    var body: some View {
        VStack(spacing: 12) {
            Text("総合ポイント: \(presentation.points)")
                .font(.title)
                .padding(.top, 16)

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

            Text("ベストポイント: \(presentation.bestPointsText)")
                .font(.headline)

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
                    Text("ペナルティ合計")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(presentation.penaltySummaryText)
                        .font(.body)
                        .monospacedDigit()
                }

                GridRow {
                    Text("所要時間")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(presentation.formattedElapsedTime)
                        .font(.body)
                        .monospacedDigit()
                }

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

struct ResultActionSection: View {
    let presentation: ResultSummaryPresentation
    let modeIdentifier: GameMode.Identifier
    let showsLeaderboardButton: Bool
    let isGameCenterAuthenticated: Bool
    let onRequestGameCenterSignIn: ((GameCenterSignInPromptReason) -> Void)?
    let onRetry: () -> Void
    let onReturnToTitle: (() -> Void)?
    let gameCenterService: GameCenterServiceProtocol
    let hapticsEnabled: Bool

    var body: some View {
        VStack(spacing: 16) {
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
                Text("リトライ")
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
        showsLeaderboardButton: Bool,
        isGameCenterAuthenticated: Bool,
        onRequestGameCenterSignIn: ((GameCenterSignInPromptReason) -> Void)?,
        onRetry: @escaping () -> Void,
        onReturnToTitle: (() -> Void)?,
        gameCenterService: GameCenterServiceProtocol,
        hapticsEnabled: Bool
    ) {
        self.presentation = presentation
        self.modeIdentifier = modeIdentifier
        self.modeDisplayName = modeDisplayName
        self.showsLeaderboardButton = showsLeaderboardButton
        self.isGameCenterAuthenticated = isGameCenterAuthenticated
        self.onRequestGameCenterSignIn = onRequestGameCenterSignIn
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
