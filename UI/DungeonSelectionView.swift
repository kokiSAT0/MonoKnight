import Game
import SwiftUI

/// 塔ダンジョンのフロアを選んで開始する入口。
/// 旧キャンペーン一覧は互換 UI として残し、タイトルのキャンペーン導線だけをこちらへ向ける。
struct DungeonSelectionView: View {
    let dungeonLibrary: DungeonLibrary
    let onClose: () -> Void
    let onStartDungeon: (DungeonDefinition) -> Void

    private let theme = AppTheme()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("戻る", action: onClose)
                    .accessibilityIdentifier("dungeon_selection_close_button")
            }
        }
        .accessibilityIdentifier("dungeon_selection_view")
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
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(dungeon.title)
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.textPrimary)

                    Text(difficultyText(dungeon.difficulty))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(theme.textSecondary.opacity(0.14)))
                }

                Text(dungeon.summary)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                onStartDungeon(dungeon)
            } label: {
                Label("1Fから開始", systemImage: "figure.stairs")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accentPrimary)
            .foregroundColor(theme.accentOnPrimary)
            .controlSize(.large)
            .accessibilityIdentifier("dungeon_start_button_\(dungeon.id)")
            .accessibilityHint("この塔を1階から連続で開始します")

            VStack(spacing: 10) {
                ForEach(Array(dungeon.floors.enumerated()), id: \.element.id) { index, floor in
                    floorInfoRow(dungeon: dungeon, floor: floor, floorNumber: index + 1)
                }
            }
        }
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
        case .growth:
            return "低難度"
        case .tactical:
            return "中難度"
        case .roguelike:
            return "高難度"
        }
    }

    private var contentMaxWidth: CGFloat? {
        horizontalSizeClass == .regular ? 720 : nil
    }

    private var horizontalPadding: CGFloat {
        horizontalSizeClass == .regular ? 44 : 24
    }
}
