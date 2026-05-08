import Game
import SwiftUI

/// 塔ダンジョンのフロアを選んで開始する入口。
/// タイトルから入る塔攻略専用の選択画面。
struct DungeonSelectionView: View {
    let dungeonLibrary: DungeonLibrary
    @ObservedObject var dungeonGrowthStore: DungeonGrowthStore
    @ObservedObject var dungeonRunResumeStore: DungeonRunResumeStore
    let onResumeDungeon: (DungeonRunResumeSnapshot) -> Void
    let onStartDungeon: (DungeonDefinition, Int) -> Void

    private let theme = AppTheme()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isGrowthSectionExpanded = false

    init(
        dungeonLibrary: DungeonLibrary,
        dungeonGrowthStore: DungeonGrowthStore,
        dungeonRunResumeStore: DungeonRunResumeStore = DungeonRunResumeStore(),
        onResumeDungeon: @escaping (DungeonRunResumeSnapshot) -> Void = { _ in },
        onStartDungeon: @escaping (DungeonDefinition, Int) -> Void
    ) {
        self.dungeonLibrary = dungeonLibrary
        self._dungeonGrowthStore = ObservedObject(wrappedValue: dungeonGrowthStore)
        self._dungeonRunResumeStore = ObservedObject(wrappedValue: dungeonRunResumeStore)
        self.onResumeDungeon = onResumeDungeon
        self.onStartDungeon = onStartDungeon
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                header

                ForEach(dungeonLibrary.dungeons) { dungeon in
                    dungeonSection(dungeon)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 28)
            .padding(.bottom, 40)
            .frame(maxWidth: contentMaxWidth)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(theme.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("塔ダンジョン")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("dungeon_selection_view")
    }

    private func growthBranchSection(_ branch: DungeonGrowthBranch) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(branch.title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(theme.textSecondary)

            ForEach(DungeonGrowthUpgrade.allCases.filter { $0.branch == branch }) { upgrade in
                growthUpgradeRow(upgrade)
            }
        }
        .padding(.top, 4)
    }

    private func growthUpgradeRow(_ upgrade: DungeonGrowthUpgrade) -> some View {
        let isUnlocked = dungeonGrowthStore.isUnlocked(upgrade)
        let canUnlock = dungeonGrowthStore.canUnlock(upgrade)
        let lockReason = dungeonGrowthStore.lockReason(for: upgrade)

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(upgrade.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.textPrimary)
                Text(upgrade.summary)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let lockReason {
                    Text(lockReason)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.textSecondary.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            Button {
                _ = dungeonGrowthStore.unlock(upgrade)
            } label: {
                Text(isUnlocked ? "取得済" : canUnlock ? "\(upgrade.cost)pt" : "ロック")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .frame(minWidth: 58)
            }
            .buttonStyle(.bordered)
            .disabled(!canUnlock)
            .accessibilityIdentifier("dungeon_growth_unlock_\(upgrade.rawValue)")
        }
        .padding(.vertical, 4)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("キャンペーン")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(theme.textSecondary)

            Text("出口を目指して塔を登る")
                .font(.system(size: 25, weight: .heavy, design: .rounded))
                .foregroundColor(theme.textPrimary)

            Text("カード移動で敵の警戒範囲や床ギミックをかわし、フロアごとの出口へ向かいます。")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func dungeonSection(_ dungeon: DungeonDefinition) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                let growthStatuses = DungeonGrowthRewardStatusPresentation.make(
                    dungeon: dungeon,
                    growthStore: dungeonGrowthStore
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(dungeon.title)
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.textPrimary)

                    HStack(alignment: .center, spacing: 8) {
                        Text(difficultyText(dungeon.difficulty))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(theme.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(theme.textSecondary.opacity(0.14)))

                        ForEach(growthStatuses, id: \.accessibilityIdentifier) { growthStatus in
                            growthStatusBadge(growthStatus)
                        }
                    }
                }

                Text(dungeon.summary)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            growthSection(for: dungeon)
            resumeButtonIfNeeded(for: dungeon)
            startButtons(for: dungeon)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.backgroundElevated.opacity(0.86))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.statisticBadgeBorder, lineWidth: 1)
        )
        .accessibilityIdentifier("dungeon_card_\(dungeon.id)")
    }

    @ViewBuilder
    private func growthSection(for dungeon: DungeonDefinition) -> some View {
        if let presentation = DungeonGrowthTreeCardPresentation.make(
            dungeon: dungeon,
            points: dungeonGrowthStore.points
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Divider()
                    .overlay(theme.statisticBadgeBorder.opacity(0.7))

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isGrowthSectionExpanded.toggle()
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Label(
                            presentation.title,
                            systemImage: isGrowthSectionExpanded ? "chevron.down" : "chevron.right"
                        )
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.textPrimary)
                        Spacer()
                        Text(presentation.pointsText)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(theme.accentPrimary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(presentation.toggleAccessibilityIdentifier)
                .accessibilityHint(isGrowthSectionExpanded ? "成長ツリーを閉じます" : "成長ツリーを開きます")

                if isGrowthSectionExpanded {
                    ForEach(DungeonGrowthBranch.allCases) { branch in
                        growthBranchSection(branch)
                    }
                }
            }
            .accessibilityIdentifier(presentation.sectionAccessibilityIdentifier)
        }
    }

    @ViewBuilder
    private func resumeButtonIfNeeded(for dungeon: DungeonDefinition) -> some View {
        if let presentation = DungeonResumePresentation.make(
            dungeon: dungeon,
            snapshot: dungeonRunResumeStore.snapshot
        ) {
            Button {
                onResumeDungeon(presentation.snapshot)
            } label: {
                Label(presentation.buttonTitle, systemImage: "arrow.clockwise.circle.fill")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accentPrimary)
            .foregroundColor(theme.accentOnPrimary)
            .controlSize(.large)
            .accessibilityIdentifier(presentation.accessibilityIdentifier)
            .accessibilityHint(Text(presentation.accessibilityHint))
        }
    }

    @ViewBuilder
    private func startButtons(for dungeon: DungeonDefinition) -> some View {
        let floorNumbers = startFloorNumbers(for: dungeon)
        if floorNumbers.count <= 1, let floorNumber = floorNumbers.first {
            dungeonStartButton(dungeon: dungeon, floorNumber: floorNumber, isCompact: false)
        } else {
            HStack(spacing: 8) {
                ForEach(floorNumbers, id: \.self) { floorNumber in
                    dungeonStartButton(dungeon: dungeon, floorNumber: floorNumber, isCompact: true)
                }
            }
        }
    }

    private func dungeonStartButton(
        dungeon: DungeonDefinition,
        floorNumber: Int,
        isCompact: Bool
    ) -> some View {
        Button {
            onStartDungeon(dungeon, floorNumber - 1)
        } label: {
            Label(
                isCompact ? "\(floorNumber)Fから" : "開始",
                systemImage: floorNumber == 1 ? "figure.stairs" : "flag.checkered"
            )
            .font(.system(size: isCompact ? 14 : 16, weight: .semibold, design: .rounded))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(theme.accentPrimary)
        .foregroundColor(theme.accentOnPrimary)
        .controlSize(isCompact ? .regular : .large)
        .accessibilityIdentifier("dungeon_start_button_\(dungeon.id)_\(floorNumber)f")
        .accessibilityHint("この塔を\(floorNumber)階から連続で開始します")
    }

    private func growthStatusBadge(_ growthStatus: DungeonGrowthRewardStatusPresentation) -> some View {
        Text(growthStatus.text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundColor(
                growthStatus.isRewarded
                    ? theme.textSecondary
                    : theme.accentPrimary
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(
                    growthStatus.isRewarded
                        ? theme.textSecondary.opacity(0.12)
                        : theme.accentPrimary.opacity(0.14)
                )
            )
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .accessibilityIdentifier(growthStatus.accessibilityIdentifier)
    }

    private func difficultyText(_ difficulty: DungeonDifficulty) -> String {
        switch difficulty {
        case .tutorial:
            return "チュートリアル"
        case .growth:
            return "成長あり"
        case .tactical:
            return "中難度"
        case .roguelike:
            return "高難度"
        }
    }

    @MainActor
    private func startFloorNumbers(for dungeon: DungeonDefinition) -> [Int] {
        dungeonGrowthStore.availableGrowthStartFloorNumbers(for: dungeon)
    }

    private var contentMaxWidth: CGFloat? {
        horizontalSizeClass == .regular ? 720 : nil
    }

    private var horizontalPadding: CGFloat {
        horizontalSizeClass == .regular ? 44 : 24
    }
}

struct DungeonResumePresentation: Equatable {
    let snapshot: DungeonRunResumeSnapshot
    let buttonTitle: String
    let accessibilityIdentifier: String
    let accessibilityHint: String

    static func make(dungeon: DungeonDefinition, snapshot: DungeonRunResumeSnapshot?) -> DungeonResumePresentation? {
        guard let snapshot,
              snapshot.dungeonID == dungeon.id,
              dungeon.floors.indices.contains(snapshot.floorIndex)
        else { return nil }
        let floorNumber = snapshot.floorIndex + 1
        return DungeonResumePresentation(
            snapshot: snapshot,
            buttonTitle: "続きから \(floorNumber)F",
            accessibilityIdentifier: "dungeon_resume_button_\(dungeon.id)",
            accessibilityHint: "\(dungeon.title) \(floorNumber)階の続きから再開します"
        )
    }
}

struct DungeonGrowthRewardStatusPresentation: Equatable {
    let text: String
    let accessibilityIdentifier: String
    let isRewarded: Bool

    @MainActor
    static func make(
        dungeon: DungeonDefinition,
        growthStore: DungeonGrowthStore
    ) -> [DungeonGrowthRewardStatusPresentation] {
        growthStore.growthMilestoneIDs(for: dungeon).map { milestoneID in
            let floorNumber = growthStore.growthMilestoneFloorNumber(for: milestoneID) ?? 0
            let isRewarded = growthStore.hasRewardedGrowthMilestone(milestoneID)
            return DungeonGrowthRewardStatusPresentation(
                text: "\(floorNumber)F \(isRewarded ? "獲得済" : "未獲得")",
                accessibilityIdentifier: "dungeon_growth_reward_status_\(milestoneID)",
                isRewarded: isRewarded
            )
        }
    }
}

struct DungeonGrowthTreeCardPresentation: Equatable {
    let title: String
    let pointsText: String
    let sectionAccessibilityIdentifier: String
    let toggleAccessibilityIdentifier: String

    static func make(dungeon: DungeonDefinition, points: Int) -> DungeonGrowthTreeCardPresentation? {
        guard dungeon.difficulty == .growth else { return nil }
        return DungeonGrowthTreeCardPresentation(
            title: "成長",
            pointsText: "ポイント \(max(points, 0))",
            sectionAccessibilityIdentifier: "dungeon_growth_section",
            toggleAccessibilityIdentifier: "dungeon_growth_toggle"
        )
    }
}
