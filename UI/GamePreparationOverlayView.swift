import SwiftUI
import Game

struct GamePreparationOverlayPresentation: Equatable {
    struct FeatureChip: Equatable {
        let label: String
        let isNew: Bool

        var displayText: String {
            isNew ? "NEW \(label)" : label
        }
    }

    let primaryObjectiveText: String
    let clearConditionText: String
    let shortRuleSummaryText: String
    let detailsTitle: String
    let featureChips: [FeatureChip]
    let featuredChips: [FeatureChip]
    let prioritizesFeatureSpotlight: Bool

    init(mode: GameMode, campaignStage: CampaignStage?) {
        if mode.usesTargetCollection {
            primaryObjectiveText = "目的地を \(mode.targetGoalCount) 個取ればクリア"
            clearConditionText = "クリア: 目的地 \(mode.targetGoalCount) 個"
            shortRuleSummaryText = "スコア: 手数 + 時間 + フォーカス。スターはやり込み目標です。"
        } else {
            primaryObjectiveText = "盤面の必要マスを踏破すればクリア"
            clearConditionText = "クリア: 必要マスを踏破"
            shortRuleSummaryText = "ペナルティを抑えながら、使えるカードで盤面を埋めましょう。"
        }

        detailsTitle = campaignStage == nil ? "ルール詳細を見る" : "スター条件・記録を見る"
        let resolvedChips = campaignStage.map(CampaignStageFeatureResolver.chips(for:)) ?? []
        featureChips = resolvedChips
        featuredChips = resolvedChips.filter(\.isNew) + resolvedChips.filter { !$0.isNew }
        prioritizesFeatureSpotlight = campaignStage != nil && !resolvedChips.isEmpty
    }
}

private enum CampaignStageFeatureKey: Hashable {
    case kingCards
    case knightCards
    case standardDeck
    case orthogonalChoice
    case diagonalChoice
    case knightChoice
    case allChoice
    case rayCards
    case fixedWarpCard
    case superWarp
    case warpCards
    case spawnChoice
    case obstacles
    case warpTile
    case shuffleHand
    case boost
    case slow
    case nextRefresh
    case freeFocus
    case preserveCard
    case draft
    case overload
    case targetSwap
    case openGate

    var label: String {
        switch self {
        case .kingCards: return "王将カード"
        case .knightCards: return "桂馬カード"
        case .standardDeck: return "標準カード"
        case .orthogonalChoice: return "選択カード"
        case .diagonalChoice: return "斜め選択"
        case .knightChoice: return "桂馬選択"
        case .allChoice: return "全選択カード"
        case .rayCards: return "レイカード"
        case .fixedWarpCard: return "固定ワープ"
        case .superWarp: return "全域ワープ"
        case .warpCards: return "ワープカード"
        case .spawnChoice: return "開始位置選び"
        case .obstacles: return "障害物"
        case .warpTile: return "ワープタイル"
        case .shuffleHand: return "シャッフル"
        case .boost: return "加速"
        case .slow: return "減速"
        case .nextRefresh: return "NEXT更新"
        case .freeFocus: return "無料フォーカス"
        case .preserveCard: return "カード温存"
        case .draft: return "ドラフト"
        case .overload: return "過負荷"
        case .targetSwap: return "目的地入替"
        case .openGate: return "開門"
        }
    }
}

private enum CampaignStageFeatureResolver {
    static func chips(for stage: CampaignStage) -> [GamePreparationOverlayPresentation.FeatureChip] {
        let currentKeys = featureKeys(for: stage)
        let previousKeys = Set(
            CampaignLibrary.shared.allStages
                .filter { isBefore($0.id, stage.id) }
                .flatMap(featureKeys(for:))
        )

        return currentKeys.map { key in
            GamePreparationOverlayPresentation.FeatureChip(
                label: key.label,
                isNew: !previousKeys.contains(key)
            )
        }
    }

    private static func isBefore(_ lhs: CampaignStageID, _ rhs: CampaignStageID) -> Bool {
        lhs.chapter < rhs.chapter || (lhs.chapter == rhs.chapter && lhs.index < rhs.index)
    }

    private static func featureKeys(for stage: CampaignStage) -> [CampaignStageFeatureKey] {
        var keys = deckFeatureKeys(for: stage.regulation.deckPreset)

        if stage.regulation.spawnRule == .chooseAnyAfterPreview {
            keys.append(.spawnChoice)
        }
        if !stage.regulation.impassableTilePoints.isEmpty {
            keys.append(.obstacles)
        }
        if !stage.regulation.warpTilePairs.isEmpty {
            keys.append(.warpTile)
        }
        if !stage.regulation.fixedWarpCardTargets.isEmpty {
            keys.append(.fixedWarpCard)
        }
        keys.append(contentsOf: tileFeatureKeys(for: stage.regulation.tileEffectOverrides.values))

        return unique(keys)
    }

    private static func deckFeatureKeys(for preset: GameDeckPreset) -> [CampaignStageFeatureKey] {
        switch preset {
        case .kingOnly:
            return [.kingCards]
        case .kingPlusKnightOnly, .kingAndKnightBasic:
            return [.knightCards]
        case .standard, .standardLight:
            return [.standardDeck]
        case .directionChoice, .kingAndKnightWithOrthogonalChoices, .standardWithOrthogonalChoices, .kingOrthogonalChoiceOnly:
            return [.orthogonalChoice]
        case .kingAndKnightWithDiagonalChoices, .standardWithDiagonalChoices, .kingDiagonalChoiceOnly:
            return [.diagonalChoice]
        case .kingAndKnightWithKnightChoices, .standardWithKnightChoices, .knightChoiceOnly:
            return [.knightChoice]
        case .kingAndKnightWithAllChoices, .standardWithAllChoices, .allChoiceMixed:
            return [.allChoice]
        case .directionalRayFocus, .extendedWithMultiStepMoves:
            return [.rayCards]
        case .fixedWarpSpecialized:
            return [.fixedWarpCard]
        case .superWarpHighFrequency:
            return [.superWarp]
        case .standardWithWarpCards:
            return [.warpCards]
        case .targetLabAllIn:
            return [.allChoice, .rayCards, .warpCards]
        case .supportToolkit:
            return []
        case .classicalChallenge:
            return [.knightCards]
        }
    }

    private static func tileFeatureKeys(for effects: Dictionary<GridPoint, TileEffect>.Values) -> [CampaignStageFeatureKey] {
        effects.map { effect in
            switch effect {
            case .warp:
                return .warpTile
            case .shuffleHand:
                return .shuffleHand
            case .boost:
                return .boost
            case .slow:
                return .slow
            case .nextRefresh:
                return .nextRefresh
            case .freeFocus:
                return .freeFocus
            case .preserveCard:
                return .preserveCard
            case .draft:
                return .draft
            case .overload:
                return .overload
            case .targetSwap:
                return .targetSwap
            case .openGate:
                return .openGate
            }
        }
    }

    private static func unique(_ keys: [CampaignStageFeatureKey]) -> [CampaignStageFeatureKey] {
        var seen = Set<CampaignStageFeatureKey>()
        return keys.filter { seen.insert($0).inserted }
    }
}

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
        @State private var isDetailsExpanded = false
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        private var presentation: GamePreparationOverlayPresentation {
            GamePreparationOverlayPresentation(mode: mode, campaignStage: campaignStage)
        }

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
                        if presentation.prioritizesFeatureSpotlight {
                            featureSpotlightSection
                        } else {
                            primaryObjectiveSection
                            featureSection
                        }
                        detailsSection
                        controlSection
                    }
                    .padding(contentPadding)
                }
                .frame(maxWidth: contentMaxWidth)
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

        private var isRegularWidth: Bool {
            horizontalSizeClass == .regular
        }

        private var contentMaxWidth: CGFloat {
            isRegularWidth ? LayoutMetrics.regularWidthMaxContentWidth : LayoutMetrics.compactWidthMaxContentWidth
        }

        private var contentPadding: CGFloat {
            isRegularWidth ? LayoutMetrics.regularWidthContentPadding : LayoutMetrics.compactWidthContentPadding
        }

        private var headerSection: some View {
            VStack(alignment: .leading, spacing: LayoutMetrics.headerSpacing) {
                if let stage = campaignStage {
                    HStack(spacing: 8) {
                        Text(stage.displayCode)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(theme.textSecondary)
                            .accessibilityLabel("ステージ番号 \(stage.displayCode)")

                        Text("キャンペーン")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(theme.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(theme.textSecondary.opacity(0.14))
                            )
                            .accessibilityHidden(true)
                    }

                    Text(stage.title)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.textPrimary)

                    Text(stage.summary)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
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

        private var primaryObjectiveSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("今回やること")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.textSecondary)

                Text(presentation.primaryObjectiveText)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(presentation.shortRuleSummaryText)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(LayoutMetrics.objectivePadding)
            .background(
                RoundedRectangle(cornerRadius: LayoutMetrics.objectiveCornerRadius, style: .continuous)
                    .fill(theme.backgroundElevated.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: LayoutMetrics.objectiveCornerRadius, style: .continuous)
                    .stroke(theme.spawnOverlayBorder, lineWidth: LayoutMetrics.borderWidth)
            )
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("game_preparation_primary_objective")
        }

        private var featureSpotlightSection: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("今回の見どころ")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.textSecondary)

                FlexibleFeatureChipGrid(chips: presentation.featuredChips) { chip, isProminent in
                    featureChipView(chip, isProminent: isProminent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.clearConditionText)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.textPrimary)

                    Text(presentation.shortRuleSummaryText)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(LayoutMetrics.objectivePadding)
            .background(
                RoundedRectangle(cornerRadius: LayoutMetrics.objectiveCornerRadius, style: .continuous)
                    .fill(theme.backgroundElevated.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: LayoutMetrics.objectiveCornerRadius, style: .continuous)
                    .stroke(theme.spawnOverlayBorder, lineWidth: LayoutMetrics.borderWidth)
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("game_preparation_feature_spotlight")
        }

        @ViewBuilder
        private var featureSection: some View {
            if !presentation.featureChips.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("今回の見どころ")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.textSecondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(presentation.featureChips, id: \.displayText) { chip in
                                featureChipView(chip, isProminent: false)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("game_preparation_feature_chips")
            }
        }

        private func featureChipView(
            _ chip: GamePreparationOverlayPresentation.FeatureChip,
            isProminent: Bool
        ) -> some View {
            HStack(spacing: 5) {
                if chip.isNew {
                    Text("NEW")
                        .font(.system(size: isProminent ? 11 : 10, weight: .bold, design: .rounded))
                        .foregroundColor(theme.accentOnPrimary)
                        .padding(.horizontal, isProminent ? 7 : 6)
                        .padding(.vertical, isProminent ? 4 : 3)
                        .background(
                            Capsule()
                                .fill(theme.accentPrimary)
                        )
                }

                Text(chip.label)
                    .font(.system(size: isProminent ? 15 : 12, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .multilineTextAlignment(.leading)
                    .layoutPriority(1)
            }
            .frame(minWidth: isProminent ? 132 : 112, alignment: .leading)
            .padding(.horizontal, isProminent ? 12 : 10)
            .padding(.vertical, isProminent ? 9 : 7)
            .background(
                Capsule()
                    .fill(theme.backgroundElevated.opacity(0.85))
            )
            .overlay(
                Capsule()
                    .stroke(
                        chip.isNew ? theme.accentPrimary.opacity(0.55) : theme.spawnOverlayBorder,
                        lineWidth: LayoutMetrics.borderWidth
                    )
            )
            .accessibilityLabel(Text(chip.displayText))
        }

        private var detailsSection: some View {
            DisclosureGroup(isExpanded: $isDetailsExpanded) {
                VStack(alignment: .leading, spacing: LayoutMetrics.detailGroupSpacing) {
                    if campaignStage != nil {
                        CampaignRewardSummaryView(
                            stage: campaignStage,
                            progress: progress,
                            theme: theme,
                            context: .overlay,
                            showsRecordSection: true
                        )
                    }

                    InfoSection(title: mode.usesTargetCollection ? "スコア要素" : "ペナルティ") {
                        ForEach(ruleCostItems, id: \.self) { item in
                            bulletRow(text: item)
                        }
                    }
                }
                .padding(.top, LayoutMetrics.detailTopPadding)
            } label: {
                Text(presentation.detailsTitle)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.textPrimary)
            }
            .tint(theme.accentPrimary)
            .padding(.vertical, 4)
            .accessibilityIdentifier("game_preparation_details_disclosure")
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

        private struct FlexibleFeatureChipGrid<ChipContent: View>: View {
            let chips: [GamePreparationOverlayPresentation.FeatureChip]
            let chipContent: (GamePreparationOverlayPresentation.FeatureChip, Bool) -> ChipContent
            @Environment(\.horizontalSizeClass) private var horizontalSizeClass

            var body: some View {
                let columns = [
                    GridItem(.adaptive(minimum: chipMinimumWidth), spacing: 8, alignment: .leading)
                ]

                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(Array(chips.enumerated()), id: \.element.displayText) { index, chip in
                        chipContent(chip, index < 2)
                    }
                }
            }

            private var chipMinimumWidth: CGFloat {
                horizontalSizeClass == .regular ? 156 : 132
            }
        }

        private enum LayoutMetrics {
            static let dimmedBackgroundOpacity: Double = 0.45
            static let compactWidthMaxContentWidth: CGFloat = 360
            static let regularWidthMaxContentWidth: CGFloat = 640
            static let compactWidthContentPadding: CGFloat = 24
            static let regularWidthContentPadding: CGFloat = 30
            static let sectionSpacing: CGFloat = 18
            static let sectionContentSpacing: CGFloat = 12
            static let headerSpacing: CGFloat = 6
            static let bulletSpacing: CGFloat = 8
            static let bulletSize: CGFloat = 6
            static let rowSpacing: CGFloat = 12
            static let controlSpacing: CGFloat = 14
            static let objectivePadding: CGFloat = 16
            static let objectiveCornerRadius: CGFloat = 18
            static let detailGroupSpacing: CGFloat = 20
            static let detailTopPadding: CGFloat = 10
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
