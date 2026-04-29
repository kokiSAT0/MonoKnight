import SwiftUI
import Game

extension RootView {
    /// ゲーム開始前のローディング表示を担うオーバーレイビュー
    struct GamePreparationOverlayView: View {
        let mode: GameMode
        let campaignStage: CampaignStage?
        let progress: CampaignStageProgress?
        let isReady: Bool
        let isCampaignContext: Bool
        let onReturnToCampaignSelection: () -> Void
        let onStart: () -> Void

        private let theme: AppTheme

        init(mode: GameMode,
             campaignStage: CampaignStage?,
             progress: CampaignStageProgress?,
             isReady: Bool,
             isCampaignContext: Bool,
             onReturnToCampaignSelection: @escaping () -> Void,
             onStart: @escaping () -> Void) {
            self.mode = mode
            self.campaignStage = campaignStage
            self.progress = progress
            self.isReady = isReady
            self.isCampaignContext = isCampaignContext
            self.onReturnToCampaignSelection = onReturnToCampaignSelection
            self.onStart = onStart
            self.theme = AppTheme()
        }

        var body: some View {
            ZStack {
                Color.black
                    .opacity(LayoutMetrics.dimmedBackgroundOpacity)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                        headerSection
                        ruleCostSection
                        campaignSummarySection
                        controlSection
                    }
                    .padding(LayoutMetrics.contentPadding)
                }
                .frame(maxWidth: LayoutMetrics.maxContentWidth)
                .background(
                    theme.spawnOverlayBackground
                        .blur(radius: LayoutMetrics.backgroundBlur)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: LayoutMetrics.cornerRadius)
                        .stroke(theme.spawnOverlayBorder, lineWidth: LayoutMetrics.borderWidth)
                )
                .clipShape(RoundedRectangle(cornerRadius: LayoutMetrics.cornerRadius))
                .shadow(
                    color: theme.spawnOverlayShadow,
                    radius: LayoutMetrics.shadowRadius,
                    x: 0,
                    y: LayoutMetrics.shadowOffsetY
                )
                .padding(.horizontal, LayoutMetrics.horizontalSafePadding)
                .accessibilityIdentifier("game_preparation_overlay")
            }
            .transition(.opacity)
        }

        private var headerSection: some View {
            VStack(alignment: .leading, spacing: LayoutMetrics.headerSpacing) {
                if let stage = campaignStage {
                    Text(stage.displayCode)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.textSecondary)
                        .accessibilityLabel("ステージ番号 \(stage.displayCode)")

                    Text(stage.title)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.textPrimary)

                    Text(stage.summary)
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundColor(theme.textSecondary)
                } else {
                    Text(mode.displayName)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.textPrimary)

                    Text(mode.primarySummaryText)
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundColor(theme.textSecondary)

                    Text(mode.secondarySummaryText)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(theme.textSecondary)
                }
            }
        }

        private var ruleCostSection: some View {
            InfoSection(title: mode.usesTargetCollection ? "スコア要素" : "ペナルティ") {
                ForEach(ruleCostItems, id: \.self) { item in
                    bulletRow(text: item)
                }
            }
        }

        private var campaignSummarySection: some View {
            CampaignRewardSummaryView(
                stage: campaignStage,
                progress: progress,
                theme: theme,
                context: .overlay,
                showsRecordSection: true
            )
        }

        private var controlSection: some View {
            VStack(alignment: .leading, spacing: LayoutMetrics.controlSpacing) {
                if !isReady {
                    HStack(spacing: LayoutMetrics.rowSpacing) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(theme.accentPrimary)
                        Text("初期化中…")
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundColor(theme.textSecondary)
                    }
                    .accessibilityLabel("初期化中")
                    .accessibilityHint("完了すると開始ボタンが有効になります")
                }

                Button(action: {
                    if isReady {
                        onStart()
                    }
                }) {
                    Text("ステージを開始")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.accentOnPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, LayoutMetrics.buttonVerticalPadding)
                        .background(
                            RoundedRectangle(cornerRadius: LayoutMetrics.buttonCornerRadius)
                                .fill(theme.accentPrimary.opacity(isReady ? 1 : LayoutMetrics.disabledButtonOpacity))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!isReady)
                .accessibilityLabel("ステージを開始")
                .accessibilityHint(isReady ? "ゲームを開始します" : "準備が完了すると押せるようになります")
                .accessibilityAddTraits(.isButton)

                Button(action: {
                    onReturnToCampaignSelection()
                }) {
                    Text(returnButtonTitle)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.accentPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, LayoutMetrics.secondaryButtonVerticalPadding)
                        .background(
                            RoundedRectangle(cornerRadius: LayoutMetrics.buttonCornerRadius)
                                .stroke(theme.accentPrimary, lineWidth: LayoutMetrics.secondaryButtonBorderWidth)
                                .background(
                                    RoundedRectangle(cornerRadius: LayoutMetrics.buttonCornerRadius)
                                        .fill(Color.clear)
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(returnButtonTitle)
                .accessibilityHint(returnButtonHint)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("game_preparation_return_button")
            }
        }

        private var ruleCostItems: [String] {
            if mode.usesTargetCollection {
                return [
                    "目的地 \(mode.targetGoalCount) 個でクリア",
                    "フォーカス 1回につきスコア +15",
                    mode.manualDiscardPenaltyCost > 0 ? "捨て札 +\(mode.manualDiscardPenaltyCost) 手" : "捨て札 ペナルティなし",
                    mode.revisitPenaltyCost > 0 ? "再訪 +\(mode.revisitPenaltyCost) 手" : "再訪ペナルティなし"
                ]
            }

            return [
                mode.deadlockPenaltyCost > 0 ? "手詰まり +\(mode.deadlockPenaltyCost) 手" : "手詰まり ペナルティなし",
                mode.manualRedrawPenaltyCost > 0 ? "引き直し +\(mode.manualRedrawPenaltyCost) 手" : "引き直し ペナルティなし",
                mode.manualDiscardPenaltyCost > 0 ? "捨て札 +\(mode.manualDiscardPenaltyCost) 手" : "捨て札 ペナルティなし",
                mode.revisitPenaltyCost > 0 ? "再訪 +\(mode.revisitPenaltyCost) 手" : "再訪ペナルティなし"
            ]
        }

        private func bulletRow(text: String) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: LayoutMetrics.bulletSpacing) {
                Circle()
                    .fill(theme.textSecondary.opacity(0.6))
                    .frame(width: LayoutMetrics.bulletSize, height: LayoutMetrics.bulletSize)
                    .accessibilityHidden(true)

                Text(text)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(theme.textPrimary)
            }
        }

        private var returnButtonTitle: String {
            isCampaignContext ? "ステージ選択に戻る" : "タイトルへ戻る"
        }

        private var returnButtonHint: String {
            isCampaignContext ? "キャンペーンのステージ選択画面へ戻ります" : "タイトル画面へ戻ります"
        }

        private struct InfoSection<Content: View>: View {
            let title: String
            let content: Content

            init(title: String, @ViewBuilder content: () -> Content) {
                self.title = title
                self.content = content()
            }

            var body: some View {
                VStack(alignment: .leading, spacing: LayoutMetrics.sectionContentSpacing) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme().textSecondary)

                    content
                }
            }
        }

        private enum LayoutMetrics {
            static let dimmedBackgroundOpacity: Double = 0.45
            static let maxContentWidth: CGFloat = 360
            static let contentPadding: CGFloat = 28
            static let sectionSpacing: CGFloat = 24
            static let sectionContentSpacing: CGFloat = 12
            static let headerSpacing: CGFloat = 6
            static let bulletSpacing: CGFloat = 8
            static let bulletSize: CGFloat = 6
            static let rowSpacing: CGFloat = 12
            static let controlSpacing: CGFloat = 14
            static let buttonCornerRadius: CGFloat = 16
            static let buttonVerticalPadding: CGFloat = 14
            static let secondaryButtonVerticalPadding: CGFloat = 12
            static let secondaryButtonBorderWidth: CGFloat = 1
            static let disabledButtonOpacity: Double = 0.45
            static let cornerRadius: CGFloat = 24
            static let borderWidth: CGFloat = 1
            static let shadowRadius: CGFloat = 18
            static let shadowOffsetY: CGFloat = 8
            static let backgroundBlur: CGFloat = 0
            static let horizontalSafePadding: CGFloat = 20
        }
    }
}
