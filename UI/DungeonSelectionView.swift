import Game
import SwiftUI

/// 塔ダンジョンのフロアを選んで開始する入口。
/// 旧キャンペーン一覧は互換 UI として残し、タイトルのキャンペーン導線だけをこちらへ向ける。
struct DungeonSelectionView: View {
    let dungeonLibrary: DungeonLibrary
    @ObservedObject var dungeonGrowthStore: DungeonGrowthStore
    let onClose: () -> Void
    let onStartDungeon: (DungeonDefinition, Int) -> Void

    private let theme = AppTheme()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                header
                growthSection

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
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("戻る", action: onClose)
                    .accessibilityIdentifier("dungeon_selection_close_button")
            }
        }
        .accessibilityIdentifier("dungeon_selection_view")
    }

    private var growthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("成長")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.textPrimary)
                Spacer()
                Text("ポイント \(dungeonGrowthStore.points)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(theme.accentPrimary)
            }

            ForEach(DungeonGrowthUpgrade.allCases) { upgrade in
                growthUpgradeRow(upgrade)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.backgroundElevated.opacity(0.86))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.statisticBadgeBorder, lineWidth: 1)
        )
        .accessibilityIdentifier("dungeon_growth_section")
    }

    private func growthUpgradeRow(_ upgrade: DungeonGrowthUpgrade) -> some View {
        let isUnlocked = dungeonGrowthStore.isUnlocked(upgrade)
        let canUnlock = dungeonGrowthStore.points >= upgrade.cost && !isUnlocked

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(upgrade.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.textPrimary)
                Text(upgrade.summary)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button {
                _ = dungeonGrowthStore.unlock(upgrade)
            } label: {
                Text(isUnlocked ? "取得済" : "\(upgrade.cost)pt")
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

            VStack(spacing: 8) {
                ForEach(startFloorNumbers(for: dungeon), id: \.self) { floorNumber in
                    Button {
                        onStartDungeon(dungeon, floorNumber - 1)
                    } label: {
                        Label("\(floorNumber)Fから開始", systemImage: floorNumber == 1 ? "figure.stairs" : "flag.checkered")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accentPrimary)
                    .foregroundColor(theme.accentOnPrimary)
                    .controlSize(.large)
                    .accessibilityIdentifier("dungeon_start_button_\(dungeon.id)_\(floorNumber)f")
                    .accessibilityHint("この塔を\(floorNumber)階から連続で開始します")
                }
            }

            VStack(spacing: 10) {
                ForEach(Array(dungeon.floors.enumerated()), id: \.element.id) { index, floor in
                    floorInfoRow(dungeon: dungeon, floor: floor, floorNumber: index + 1)
                }
            }
        }
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

    private func floorInfoRow(
        dungeon: DungeonDefinition,
        floor: DungeonFloorDefinition,
        floorNumber: Int
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(spacing: 2) {
                Text("\(floorNumber)")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(theme.accentOnPrimary)
                Text("F")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(theme.accentOnPrimary.opacity(0.82))
            }
            .frame(width: 44, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.accentPrimary)
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(floor.title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(2)

                Text(floorSummary(floor))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
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
        .accessibilityIdentifier("dungeon_floor_info_\(floor.id)")
        .accessibilityLabel("\(dungeon.title) \(floorNumber)階 \(floor.title)")
        .accessibilityHint("この階のルール概要です。塔は1階から開始します")
    }

    private func floorSummary(_ floor: DungeonFloorDefinition) -> String {
        var items = [
            "HP \(floor.failureRule.initialHP)",
            floor.failureRule.turnLimit.map { "手数 \($0)" } ?? "手数制限なし",
            "出口 \(pointText(floor.exitPoint))"
        ]

        if !floor.enemies.isEmpty {
            items.append("敵 \(floor.enemies.count)")
        }
        if !floor.hazards.isEmpty {
            items.append("床ギミック \(floor.hazards.count)")
        }

        return items.joined(separator: " / ")
    }

    private func pointText(_ point: GridPoint) -> String {
        "(\(point.x),\(point.y))"
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
