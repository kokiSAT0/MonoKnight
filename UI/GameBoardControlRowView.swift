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

extension GameBoardControlRowView {
    static func isCriticalDungeonHP(_ hp: Int) -> Bool {
        hp <= 1
    }

    static func dungeonHPAccessibilityValue(for hp: Int) -> String {
        isCriticalDungeonHP(hp) ? "\(hp)、瀕死" : "\(hp)"
    }

    static func dungeonTurnProgress(remaining: Int?, limit: Int?) -> Double? {
        guard let limit, limit > 0, let remaining else { return nil }
        return Double(max(0, min(remaining, limit))) / Double(limit)
    }

    static func isCriticalDungeonTurns(remaining: Int?, limit: Int?) -> Bool {
        guard let progress = dungeonTurnProgress(remaining: remaining, limit: limit) else { return false }
        return progress <= 0.25
    }

    static func dungeonTurnValueText(remaining: Int?, limit: Int?) -> String {
        guard let limit, let remaining else { return "制限なし" }
        return "残り \(max(remaining, 0)) / \(limit)"
    }

    static func dungeonTurnAccessibilityValue(remaining: Int?, limit: Int?) -> String {
        guard let limit, let remaining else { return "制限なし" }
        return "\(limit)手中\(max(remaining, 0))手残り"
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
            if viewModel.usesDungeonExit {
                dungeonStatisticsGroup()
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

            statisticBadge(
                title: "ペナルティ",
                value: "\(viewModel.penaltyCount)",
                accessibilityLabel: "ペナルティ合計",
                accessibilityValue: penaltyAccessibilityValue
            )

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
            statisticBadge(
                title: "残りマス",
                value: "\(viewModel.remainingTiles)",
                accessibilityLabel: "残りマス数",
                accessibilityValue: "残り\(viewModel.remainingTiles)マス"
            )
        }
    }

    func dungeonStatisticsGroup() -> some View {
        statisticsBadgeGroup {
            if let floorText = viewModel.dungeonRunFloorText {
                statisticBadge(
                    title: "階層",
                    value: floorText,
                    accessibilityLabel: "現在の階層",
                    accessibilityValue: floorText
                )
            }

            statisticBadge(
                title: "HP",
                value: "\(viewModel.dungeonHP)",
                accessibilityLabel: "残りHP",
                accessibilityValue: Self.dungeonHPAccessibilityValue(for: viewModel.dungeonHP),
                valueColor: Self.isCriticalDungeonHP(viewModel.dungeonHP) ? .red : nil,
                isHighlighted: Self.isCriticalDungeonHP(viewModel.dungeonHP)
            )

            dungeonTurnStatisticBadge(
                remaining: viewModel.remainingDungeonTurns,
                limit: viewModel.dungeonTurnLimit
            )

            if viewModel.enemyFreezeTurnsRemaining > 0 {
                statisticBadge(
                    title: "凍結",
                    value: "残り\(viewModel.enemyFreezeTurnsRemaining)",
                    accessibilityLabel: "敵凍結",
                    accessibilityValue: "残り\(viewModel.enemyFreezeTurnsRemaining)ターン"
                )
            }

            if viewModel.damageBarrierTurnsRemaining > 0 {
                statisticBadge(
                    title: "障壁",
                    value: "残り\(viewModel.damageBarrierTurnsRemaining)",
                    accessibilityLabel: "障壁",
                    accessibilityValue: "残り\(viewModel.damageBarrierTurnsRemaining)ターン、HPダメージを無効化"
                )
            }

            if viewModel.isShackled {
                statisticBadge(
                    title: "足枷",
                    value: "手数2",
                    accessibilityLabel: "足枷状態",
                    accessibilityValue: "全行動の手数が2になり、敵ターンも2回進みます"
                )
            }

            if viewModel.isIlluded {
                statisticBadge(
                    title: "幻惑",
                    value: "階内",
                    accessibilityLabel: "幻惑状態",
                    accessibilityValue: "この階にいる間、移動カードの正体が分からずランダムに使用されます"
                )
            }

            if viewModel.poisonDamageTicksRemaining > 0 {
                statisticBadge(
                    title: "毒",
                    value: "次\(viewModel.poisonActionsUntilNextDamage)",
                    accessibilityLabel: "毒状態",
                    accessibilityValue: "次の毒ダメージまで\(viewModel.poisonActionsUntilNextDamage)行動、残り\(viewModel.poisonDamageTicksRemaining)回"
                )
            }
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

    func dungeonTurnStatisticBadge(remaining: Int?, limit: Int?) -> some View {
        let progress = Self.dungeonTurnProgress(remaining: remaining, limit: limit)
        let isCritical = Self.isCriticalDungeonTurns(remaining: remaining, limit: limit)
        let valueColor: Color = isCritical ? .red : theme.statisticValueText

        return VStack(alignment: .leading, spacing: 5) {
            Text("残り手数")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(theme.statisticTitleText)

            Text(Self.dungeonTurnValueText(remaining: remaining, limit: limit))
                .font(.headline)
                .foregroundColor(valueColor)

            if let progress {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(theme.statisticBadgeBorder.opacity(0.7))
                        Capsule(style: .continuous)
                            .fill(valueColor)
                            .frame(width: geometry.size.width * CGFloat(progress))
                    }
                }
                .frame(width: 118, height: 7)
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, isCritical ? 8 : 0)
        .padding(.vertical, isCritical ? 4 : 0)
        .background {
            if isCritical {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.red.opacity(0.12))
            }
        }
        .overlay {
            if isCritical {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.red.opacity(0.56), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("残り手数")
        .accessibilityValue(Self.dungeonTurnAccessibilityValue(remaining: remaining, limit: limit))
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

    /// 操作ボタン群
    func controlButtonCluster() -> some View {
        HStack(spacing: 12) {
            if !viewModel.usesDungeonExit {
                manualDiscardButton
                manualPenaltyButton
            }
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
        accessibilityValue: String,
        valueColor: Color? = nil,
        isHighlighted: Bool = false
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
        .padding(.horizontal, isHighlighted ? 8 : 0)
        .padding(.vertical, isHighlighted ? 4 : 0)
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.red.opacity(0.12))
            }
        }
        .overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.red.opacity(0.56), lineWidth: 1)
            }
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
