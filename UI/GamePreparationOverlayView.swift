import Game
import SwiftUI

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

    init(mode: GameMode) {
        let exitText = mode.dungeonExitPoint.map { "(\($0.x),\($0.y))" } ?? "-"
        let hpLabel = mode.dungeonMetadataSnapshot?.runState?.currentFloorIndex ?? 0 > 0 ? "引き継ぎHP" : "HP"
        let hpText = mode.dungeonRules.map { "\(hpLabel) \($0.failureRule.initialHP)" } ?? "HPあり"
        let turnText = mode.dungeonRules?.failureRule.turnLimit.map { "残り手数 \($0)" } ?? "手数制限なし"
        let rewardEntries = mode.dungeonMetadataSnapshot?.runState?.rewardInventoryEntries ?? []
        let rewardText = rewardEntries.isEmpty
            ? nil
            : "報酬カード \(rewardEntries.map { "\($0.playable.displayName)×\($0.rewardUses)" }.joined(separator: "、"))"

        primaryObjectiveText = "出口へ到達すればクリア"
        clearConditionText = "クリア: 出口 \(exitText)"
        shortRuleSummaryText = [hpText, turnText, rewardText]
            .compactMap { $0 }
            .joined(separator: " / ") + "。床のカードは1回使い切り、報酬カードは持ち越せます。"
        detailsTitle = "塔のルールを見る"

        let chips = DungeonFeatureResolver.chips(for: mode)
        featureChips = chips
        featuredChips = chips.filter(\.isNew) + chips.filter { !$0.isNew }
        prioritizesFeatureSpotlight = !chips.isEmpty
    }
}

private enum DungeonFeatureResolver {
    static func chips(for mode: GameMode) -> [GamePreparationOverlayPresentation.FeatureChip] {
        guard let rules = mode.dungeonRules else { return [] }
        let hpLabel = mode.dungeonMetadataSnapshot?.runState?.currentFloorIndex ?? 0 > 0 ? "引継ぎHP" : "HP"
        var chips: [GamePreparationOverlayPresentation.FeatureChip] = [
            .init(label: "出口到達", isNew: true),
            .init(label: "\(hpLabel) \(rules.failureRule.initialHP)", isNew: false)
        ]

        if let turnLimit = rules.failureRule.turnLimit {
            chips.append(.init(label: "手数 \(turnLimit)", isNew: false))
        }
        if rules.allowsBasicOrthogonalMove {
            chips.append(.init(label: "基本移動", isNew: true))
        }
        if !rules.enemies.isEmpty {
            chips.append(.init(label: "敵 \(rules.enemies.count)", isNew: false))
        }
        if !rules.hazards.isEmpty {
            chips.append(.init(label: "床ギミック", isNew: false))
        }
        let rewardEntries = mode.dungeonMetadataSnapshot?.runState?.rewardInventoryEntries ?? []
        if !rewardEntries.isEmpty {
            chips.append(.init(label: "報酬カード \(rewardEntries.count)", isNew: false))
        }
        return chips
    }
}

extension RootView {
    struct GamePreparationOverlayView: View {
        let mode: GameMode
        let isReady: Bool
        let isDungeonContext: Bool
        let onReturnToDungeonSelection: () -> Void
        let onStart: () -> Void

        private let theme = AppTheme()
        @State private var isDetailsExpanded = false
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass

        private var presentation: GamePreparationOverlayPresentation {
            GamePreparationOverlayPresentation(mode: mode)
        }

        var body: some View {
            ZStack {
                Color.black.opacity(0.48).ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection
                        featureSection
                        detailsSection
                        controlSection
                    }
                    .padding(contentPadding)
                }
                .frame(maxWidth: contentMaxWidth)
                .background(theme.spawnOverlayBackground.blur(radius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(theme.spawnOverlayBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .shadow(color: theme.spawnOverlayShadow, radius: 20, x: 0, y: 10)
                .padding(.horizontal, 20)
                .accessibilityIdentifier("game_preparation_overlay")
            }
            .transition(.opacity)
        }

        private var contentMaxWidth: CGFloat {
            horizontalSizeClass == .regular ? 520 : 420
        }

        private var contentPadding: CGFloat {
            horizontalSizeClass == .regular ? 28 : 22
        }

        private var headerSection: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text("塔ダンジョン")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(theme.textSecondary.opacity(0.14)))

                Text(dungeonHeaderTitle)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.textPrimary)

                Text(dungeonHeaderSummary)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(theme.textSecondary)
            }
        }

        private var featureSection: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text(presentation.primaryObjectiveText)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.textPrimary)

                Text(presentation.shortRuleSummaryText)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(theme.textSecondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(presentation.featuredChips, id: \.displayText) { chip in
                        chipView(chip)
                    }
                }
            }
        }

        private func chipView(_ chip: GamePreparationOverlayPresentation.FeatureChip) -> some View {
            HStack(spacing: 6) {
                if chip.isNew {
                    Text("NEW")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(theme.accentOnPrimary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(theme.accentPrimary))
                }
                Text(chip.label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Capsule().fill(theme.backgroundElevated.opacity(0.85)))
            .overlay(
                Capsule()
                    .stroke(chip.isNew ? theme.accentPrimary.opacity(0.55) : theme.spawnOverlayBorder, lineWidth: 1)
            )
            .accessibilityLabel(Text(chip.displayText))
        }

        private var detailsSection: some View {
            DisclosureGroup(isExpanded: $isDetailsExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(ruleCostItems, id: \.self) { item in
                        bulletRow(text: item)
                    }
                }
                .padding(.top, 10)
            } label: {
                Text(presentation.detailsTitle)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.textPrimary)
            }
            .tint(theme.accentPrimary)
            .accessibilityIdentifier("game_preparation_details_disclosure")
        }

        private var controlSection: some View {
            VStack(alignment: .leading, spacing: 12) {
                if !isReady {
                    HStack(spacing: 10) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(theme.accentPrimary)
                        Text("初期化中…")
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundColor(theme.textSecondary)
                    }
                }

                Button(action: {
                    if isReady { onStart() }
                }) {
                    Text("この階を開始")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.accentOnPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(theme.accentPrimary.opacity(isReady ? 1 : 0.45))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!isReady)

                Button(action: onReturnToDungeonSelection) {
                    Text(returnButtonTitle)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.accentPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(theme.accentPrimary, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("game_preparation_return_button")
            }
        }

        private var ruleCostItems: [String] {
            let exitText = mode.dungeonExitPoint.map { "出口 (\($0.x),\($0.y)) へ到達でクリア" } ?? "出口へ到達でクリア"
            var items = [exitText]

            if let rules = mode.dungeonRules {
                let hpLabel = mode.dungeonMetadataSnapshot?.runState?.currentFloorIndex ?? 0 > 0 ? "引き継ぎHP" : "HP"
                items.append("\(hpLabel) \(rules.failureRule.initialHP)。0 になると失敗")
                if let turnLimit = rules.failureRule.turnLimit {
                    items.append("残り手数 \(turnLimit)。0 になると失敗")
                } else {
                    items.append("手数制限なし")
                }
                if !rules.enemies.isEmpty {
                    items.append("敵の危険範囲に入ると HP 減少")
                }
                if !rules.hazards.isEmpty {
                    items.append("ひび割れ床や罠は HP とルートに影響")
                }
                if rules.cardAcquisitionMode == .inventoryOnly {
                    items.append("カードは床で拾うか、階層報酬で獲得")
                }
            }

            return items
        }

        private func bulletRow(text: String) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(theme.textSecondary.opacity(0.6))
                    .frame(width: 6, height: 6)
                Text(text)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(theme.textPrimary)
            }
        }

        private var returnButtonTitle: String {
            isDungeonContext ? "塔選択に戻る" : "タイトルへ戻る"
        }

        private var dungeonHeaderTitle: String {
            if let metadata = mode.dungeonMetadataSnapshot,
               let runState = metadata.runState,
               let dungeon = DungeonLibrary.shared.dungeon(with: metadata.dungeonID) {
                return "\(dungeon.title) \(runState.floorNumber)F"
            }
            return mode.displayName
        }

        private var dungeonHeaderSummary: String {
            if let metadata = mode.dungeonMetadataSnapshot,
               let dungeon = DungeonLibrary.shared.dungeon(with: metadata.dungeonID) {
                return "\(dungeon.summary) \(presentation.clearConditionText)"
            }
            return presentation.clearConditionText
        }
    }
}
