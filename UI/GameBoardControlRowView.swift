import SwiftUI

/// 盤面上部に統計バッジと操作ボタンを並べる補助ビュー
/// - Note: `GameView` 本体の肥大化を防ぐため、細かな UI パーツを専用ファイルへ分離している。
struct GameBoardControlRowView: View {
    /// 共通のテーマ配色を保持し、子ビューで統一したスタイルを適用する
    let theme: AppTheme
    /// ゲーム進行とサービス連携を管理する ViewModel
    @ObservedObject var viewModel: GameViewModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            singleLineLayout
            stackedLayout
        }
        .padding(.horizontal, 16)
        // PreferenceKey へ高さを伝搬し、GeometryReader 側のレイアウト計算へ反映する
        .overlay(alignment: .topLeading) {
            HeightPreferenceReporter<StatisticsHeightPreferenceKey>()
        }
    }
}

private extension GameBoardControlRowView {
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

    /// 統計バッジを 2 つのグループに分けて表示
    func statisticsBadgeContainer() -> some View {
        HStack(spacing: 12) {
            scoreStatisticsGroup()
            supplementaryStatisticsGroup()
        }
    }

    /// スコアへ直接影響する指標群
    func scoreStatisticsGroup() -> some View {
        statisticsBadgeGroup {
            statisticBadge(
                title: "移動",
                value: "\(viewModel.moveCount)",
                accessibilityLabel: "移動回数",
                accessibilityValue: "\(viewModel.moveCount)回"
            )

            statisticBadge(
                title: "ペナルティ",
                value: "\(viewModel.penaltyCount)",
                accessibilityLabel: "ペナルティ回数",
                accessibilityValue: "\(viewModel.penaltyCount)手"
            )

            statisticBadge(
                title: "経過時間",
                value: formattedElapsedTime(viewModel.displayedElapsedSeconds),
                accessibilityLabel: "経過時間",
                accessibilityValue: accessibilityElapsedTimeDescription(viewModel.displayedElapsedSeconds)
            )

            statisticBadge(
                title: "総合スア",
                value: "\(viewModel.displayedScore)",
                accessibilityLabel: "総合スコア",
                accessibilityValue: accessibilityScoreDescription(viewModel.displayedScore)
            )
        }
    }

    /// 進行度合いを補足する指標群（残りマスなど）
    func supplementaryStatisticsGroup() -> some View {
        statisticsBadgeGroup {
            statisticBadge(
                title: "残りマス",
                value: "\(viewModel.remainingTiles)",
                accessibilityLabel: "残りマス数",
                accessibilityValue: "残り\(viewModel.remainingTiles)マス"
            )
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
            Image(systemName: "arrow.triangle.2.circlepath")
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
        .accessibilityLabel(Text("ペナルティを払って手札スロットを引き直す"))
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
        accessibilityValue: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(theme.statisticTitleText)

            Text(value)
                .font(.headline)
                .foregroundColor(theme.statisticValueText)
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
}
