import SwiftUI

/// 盤面上部に統計バッジと操作ボタンを並べる補助ビュー
/// - Note: `GameView` 本体の肥大化を防ぐため、細かな UI パーツを専用ファイルへ分離している。
struct GameBoardControlRowView: View {
    /// 共通のテーマ配色を保持し、子ビューで統一したスタイルを適用する
    let theme: AppTheme
    /// ゲーム進行とサービス連携を管理する ViewModel
    @ObservedObject var viewModel: GameViewModel
    /// iPad などレギュラー幅では統計と操作を中央のプレイ領域へまとめる
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ViewThatFits(in: .horizontal) {
            singleLineLayout
            stackedLayout
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: contentMaxWidth)
        .frame(maxWidth: .infinity)
        // PreferenceKey へ高さを伝搬し、GeometryReader 側のレイアウト計算へ反映する
        .overlay(alignment: .topLeading) {
            HeightPreferenceReporter<StatisticsHeightPreferenceKey>()
        }
    }
}

private extension GameBoardControlRowView {
    var contentMaxWidth: CGFloat? {
        horizontalSizeClass == .regular ? 760 : nil
    }

    /// 横幅に余裕がある場合に利用する 1 行構成
    var singleLineLayout: some View {
        HStack(alignment: .center, spacing: 12) {
            flexibleStatisticsContainer()
            controlButtonCluster()
        }
    }

    /// 横幅不足時に統計とボタンを 2 行へ分割するレイアウト
    var stackedLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            flexibleStatisticsContainer()

            controlButtonCluster()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    /// 統計バッジ群を横幅に合わせてスクロールへフォールバック可能にする
    func flexibleStatisticsContainer() -> some View {
        ViewThatFits(in: .horizontal) {
            statisticsBadgeContainer()
            ScrollView(.horizontal, showsIndicators: false) {
                statisticsBadgeContainer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }

    /// 統計バッジを用途ごとのグループに分けて表示
    func statisticsBadgeContainer() -> some View {
        HStack(spacing: 12) {
            if viewModel.isCampaignStage {
                targetStatisticsGroup()
                if let progress = viewModel.campaignStarScoreProgress {
                    campaignStarGaugeGroup(progress)
                }
            } else {
                scoreStatisticsGroup()
                supplementaryStatisticsGroup()
            }
        }
    }

    /// スコアへ直接影響する指標群
    func scoreStatisticsGroup() -> some View {
        return statisticsBadgeGroup {
            statisticBadge(
                title: "移動",
                value: "\(viewModel.moveCount)",
                accessibilityLabel: "移動回数",
                accessibilityValue: "\(viewModel.moveCount)回"
            )

            if viewModel.usesTargetCollection {
                statisticBadge(
                    title: "フォーカス",
                    value: "\(viewModel.focusCount)",
                    accessibilityLabel: "フォーカス回数",
                    accessibilityValue: "\(viewModel.focusCount)回"
                )
            } else {
                statisticBadge(
                    title: "ペナルティ",
                    value: "\(viewModel.penaltyCount)",
                    accessibilityLabel: "ペナルティ合計",
                    accessibilityValue: penaltyAccessibilityValue
                )
            }

            statisticBadge(
                title: "経過時間",
                value: formattedElapsedTime(viewModel.displayedElapsedSeconds),
                accessibilityLabel: "経過時間",
                accessibilityValue: accessibilityElapsedTimeDescription(viewModel.displayedElapsedSeconds)
            )

            statisticBadge(
                title: "スコア",
                value: "\(viewModel.displayedScore)",
                accessibilityLabel: "スコア",
                accessibilityValue: accessibilityScoreDescription(viewModel.displayedScore)
            )
        }
    }

    /// 進行度合いを補足する指標群（残りマスなど）
    func supplementaryStatisticsGroup() -> some View {
        statisticsBadgeGroup {
            if viewModel.usesTargetCollection {
                targetCountStatisticBadge()
            } else {
                statisticBadge(
                    title: "残りマス",
                    value: "\(viewModel.remainingTiles)",
                    accessibilityLabel: "残りマス数",
                    accessibilityValue: "残り\(viewModel.remainingTiles)マス"
                )
            }

            if viewModel.isOverloadCharged {
                statisticBadge(
                    title: "状態",
                    value: "過負荷",
                    accessibilityLabel: "過負荷状態",
                    accessibilityValue: "次のカードは消費されません"
                )
            }
        }
    }

    func targetStatisticsGroup() -> some View {
        statisticsBadgeGroup {
            targetCountStatisticBadge()
        }
    }

    var penaltyAccessibilityValue: String {
        if viewModel.penaltyCount == 0 {
            return "ペナルティなし"
        } else {
            return "ペナルティ合計 \(viewModel.penaltyCount)"
        }
    }

    /// 共通の装飾を適用した統計バッジコンテナ
    func statisticsBadgeGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.statisticBadgeBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.statisticBadgeBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    /// 目的地獲得数と、獲得直後の軽い +N フィードバックを同じバッジ内へ表示
    func targetCountStatisticBadge() -> some View {
        statisticBadge(
            title: "目的地",
            value: "\(viewModel.capturedTargetCount)/\(viewModel.targetGoalCount)",
            accessibilityLabel: "目的地獲得数",
            accessibilityValue: targetCountAccessibilityValue
        )
        .overlay(alignment: .topTrailing) {
            if let feedback = viewModel.targetCaptureFeedback {
                Text(feedback.incrementText)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundColor(theme.accentOnPrimary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule(style: .continuous).fill(theme.accentPrimary))
                    .shadow(color: theme.spawnOverlayShadow.opacity(0.7), radius: 8, x: 0, y: 4)
                    .offset(x: 16, y: -12)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                    .accessibilityIdentifier("target_capture_increment_badge")
                    .accessibilityLabel(Text("目的地 \(feedback.incrementText)"))
            }
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.74), value: viewModel.targetCaptureFeedback)
    }

    func campaignStarGaugeGroup(_ progress: CampaignStarScoreProgress) -> some View {
        statisticsBadgeGroup {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .center, spacing: 8) {
                    HStack(spacing: 3) {
                        ForEach(1...3, id: \.self) { index in
                            Image(systemName: index <= progress.filledStarCount ? "star.fill" : "star")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(index <= progress.filledStarCount ? .yellow : theme.statisticValueText.opacity(0.55))
                        }
                    }
                    .accessibilityHidden(true)

                    Text(progress.nextStarText)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(theme.statisticTitleText)
                        .lineLimit(1)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(theme.statisticValueText.opacity(0.18))

                        Capsule(style: .continuous)
                            .fill(theme.accentPrimary)
                            .frame(width: geometry.size.width * CGFloat(progress.progressFraction))

                        starGaugeTick(at: progress.twoStarFraction)
                        starGaugeTick(at: 1)
                    }
                }
                .frame(height: 10)
            }
            .frame(minWidth: 148, idealWidth: 180, maxWidth: 220, minHeight: 34, alignment: .leading)
        }
        .accessibilityIdentifier("campaign_star_score_gauge")
        .accessibilityLabel(Text("キャンペーンスター進捗"))
        .accessibilityValue(Text(campaignStarGaugeAccessibilityValue(progress)))
    }

    func starGaugeTick(at fraction: Double) -> some View {
        GeometryReader { geometry in
            Capsule(style: .continuous)
                .fill(theme.statisticValueText.opacity(0.72))
                .frame(width: 2, height: geometry.size.height)
                .offset(x: max(0, min(geometry.size.width - 2, geometry.size.width * CGFloat(fraction) - 1)))
        }
        .allowsHitTesting(false)
    }

    var targetCountAccessibilityValue: String {
        if let feedback = viewModel.targetCaptureFeedback {
            return "\(viewModel.targetGoalCount)個中\(viewModel.capturedTargetCount)個獲得。直前に\(feedback.incrementCount)個獲得"
        }
        return "\(viewModel.targetGoalCount)個中\(viewModel.capturedTargetCount)個獲得"
    }

    /// 操作ボタン群
    func controlButtonCluster() -> some View {
        HStack(spacing: 12) {
            manualDiscardButton
            manualPenaltyButton
            pauseButton
            returnToTitleButton
        }
    }

    /// 捨て札モード切替ボタン
    var manualDiscardButton: some View {
        let isSelecting = viewModel.isAwaitingManualDiscardSelection
        let isDisabled = !viewModel.isManualDiscardButtonEnabled && !isSelecting

        return Button {
            viewModel.toggleManualDiscardSelection()
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(isSelecting ? theme.accentOnPrimary : theme.menuIconForeground)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(isSelecting ? theme.accentPrimary : theme.menuIconBackground)
                )
                .overlay(
                    Circle()
                        .stroke(
                            isSelecting ? theme.accentPrimary.opacity(0.55) : theme.menuIconBorder,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .opacity(isDisabled ? 0.45 : 1.0)
        .disabled(isDisabled)
        .accessibilityIdentifier("manual_discard_button")
        .accessibilityLabel(Text("手札を捨て札にする"))
        .accessibilityHint(Text(viewModel.manualDiscardAccessibilityHint))
    }

    /// 手動ペナルティ発動ボタン
    var manualPenaltyButton: some View {
        let isDisabled = !viewModel.isManualPenaltyButtonEnabled

        return Button {
            viewModel.requestManualPenalty()
        } label: {
            Image(systemName: viewModel.usesTargetCollection ? "scope" : "arrow.triangle.2.circlepath")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(theme.menuIconForeground)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(theme.menuIconBackground)
                )
                .overlay(
                    Circle()
                        .stroke(theme.menuIconBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .opacity(isDisabled ? 0.45 : 1.0)
        .disabled(isDisabled)
        .accessibilityIdentifier("manual_penalty_button")
        .accessibilityLabel(Text(viewModel.usesTargetCollection ? "フォーカスで目的地へ寄せる" : "ペナルティを払って手札スロットを引き直す"))
        .accessibilityHint(Text(viewModel.manualPenaltyAccessibilityHint))
    }

    /// ポーズメニュー表示ボタン
    var pauseButton: some View {
        Button {
            viewModel.presentPauseMenu()
        } label: {
            Image(systemName: "pause.circle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(theme.menuIconForeground)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(theme.menuIconBackground)
                )
                .overlay(
                    Circle()
                        .stroke(theme.menuIconBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pause_menu_button")
        .accessibilityLabel(Text("ポーズメニュー"))
        .accessibilityHint(Text("プレイを一時停止して設定やリセットを確認します"))
    }

    /// タイトルへ戻るボタン
    /// - Note: リセットと同等の破壊的操作になるため、必ず確認ダイアログを経由させる
    var returnToTitleButton: some View {
        Button {
            // 直接終了せず確認ダイアログを表示して誤操作を防ぐ
            viewModel.requestReturnToTitle()
        } label: {
            Image(systemName: "house")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(theme.menuIconForeground)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(theme.menuIconBackground)
                )
                .overlay(
                    Circle()
                        .stroke(theme.menuIconBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("return_to_title_button")
        .accessibilityLabel(Text("ホームへ戻る"))
        .accessibilityHint(Text("プレイを終了してタイトル画面へ戻ります"))
    }

    /// 統計バッジ 1 枚分の共通レイアウト
    func statisticBadge(
        title: String,
        value: String,
        accessibilityLabel: String,
        accessibilityValue: String,
        valueColor: Color? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(theme.statisticTitleText)

            Text(value)
                .font(.headline)
                .foregroundColor(valueColor ?? theme.statisticValueText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    /// 経過時間の表示用フォーマット
    func formattedElapsedTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    /// 経過時間のアクセシビリティ説明
    func accessibilityElapsedTimeDescription(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60

        if hours > 0 {
            return "\(hours)時間\(minutes)分\(remainingSeconds)秒"
        } else if minutes > 0 {
            return "\(minutes)分\(remainingSeconds)秒"
        } else {
            return "\(remainingSeconds)秒"
        }
    }

    /// スコアのアクセシビリティ説明
    func accessibilityScoreDescription(_ score: Int) -> String {
        "\(score)ポイント"
    }

    func campaignStarGaugeAccessibilityValue(_ progress: CampaignStarScoreProgress) -> String {
        "現在\(progress.currentScore)ポイント。\(progress.nextStarText)。2つ目は\(progress.twoStarThreshold)ポイント、3つ目は\(progress.threeStarThreshold)ポイント"
    }
}
