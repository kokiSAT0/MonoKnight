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
    @State private var selectedGrowthUpgrade: DungeonGrowthUpgrade?

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
                    let treePresentation = DungeonGrowthTreePresentation.make(growthStore: dungeonGrowthStore)
                    growthTree(treePresentation)
                }
            }
            .accessibilityIdentifier(presentation.sectionAccessibilityIdentifier)
        }
    }

    private func growthTree(_ presentation: DungeonGrowthTreePresentation) -> some View {
        let selectedUpgrade = selectedGrowthUpgrade ?? presentation.defaultSelectedUpgrade
        let selectedNode = presentation.node(for: selectedUpgrade)

        return VStack(alignment: .leading, spacing: 14) {
            growthTreeGrid(presentation, selectedUpgrade: selectedUpgrade)

            if let selectedNode {
                growthNodeDetail(selectedNode)
            }
        }
        .onAppear {
            if selectedGrowthUpgrade == nil {
                selectedGrowthUpgrade = presentation.defaultSelectedUpgrade
            }
        }
        .onChange(of: presentation.defaultSelectedUpgrade) { _, defaultUpgrade in
            if selectedGrowthUpgrade == nil {
                selectedGrowthUpgrade = defaultUpgrade
            }
        }
        .accessibilityIdentifier("dungeon_growth_tree")
    }

    private func growthTreeGrid(
        _ presentation: DungeonGrowthTreePresentation,
        selectedUpgrade: DungeonGrowthUpgrade?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text("階")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(theme.textSecondary)
                    .frame(width: 34, alignment: .leading)

                ForEach(presentation.lanes) { lane in
                    Label(lane.branchTitle, systemImage: lane.iconSystemName)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(lane.tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                }
            }

            ForEach(0..<presentation.tierCount, id: \.self) { tier in
                HStack(alignment: .center, spacing: 8) {
                    Text(presentation.gateText(forTier: tier))
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundColor(theme.textSecondary)
                        .frame(width: 34, alignment: .leading)

                    ForEach(presentation.lanes) { lane in
                        VStack(spacing: 6) {
                            if let node = lane.node(atTier: tier) {
                                growthNodeButton(node, isSelected: node.upgrade == selectedUpgrade)
                            } else {
                                Color.clear
                                    .frame(height: 58)
                            }

                            if lane.hasConnector(afterTier: tier) {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(lane.connectorColor(afterTier: tier))
                                    .frame(width: 4, height: 16)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.backgroundPrimary.opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.statisticBadgeBorder.opacity(0.7), lineWidth: 1)
        )
    }

    private func growthNodeButton(
        _ node: DungeonGrowthTreeNodePresentation,
        isSelected: Bool
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedGrowthUpgrade = node.upgrade
            }
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Circle()
                        .fill(node.fillColor)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle()
                                .stroke(
                                    isSelected ? theme.textPrimary : node.strokeColor,
                                    lineWidth: isSelected ? 3 : node.strokeWidth
                                )
                        )
                        .shadow(
                            color: node.glowColor,
                            radius: node.glowRadius,
                            x: 0,
                            y: 3
                        )

                    Image(systemName: node.iconSystemName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(node.iconColor)
                        .frame(width: 44, height: 44)

                    if let badgeText = node.badgeText {
                        Text(badgeText)
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .foregroundColor(node.badgeForegroundColor)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(node.badgeBackgroundColor))
                            .offset(x: 6, y: -4)
                    }
                }

                Text(node.shortTitle)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(node.titleColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.66)
            }
            .frame(minHeight: 58)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(node.accessibilityLabel)
        .accessibilityIdentifier(node.accessibilityIdentifier)
    }

    private func growthNodeDetail(_ node: DungeonGrowthTreeNodePresentation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: node.iconSystemName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(node.iconColor)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(node.fillColor))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(node.title)
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundColor(theme.textPrimary)
                        Text(node.statusText)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(node.statusForegroundColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(node.statusBackgroundColor))
                    }

                    Text(node.summary)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let lockReason = node.lockReason {
                Label(lockReason, systemImage: "lock.fill")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if node.isUnlocked {
                Toggle(
                    node.isActive ? "有効" : "オフ",
                    isOn: Binding(
                        get: { dungeonGrowthStore.isActive(node.upgrade) },
                        set: { _ = dungeonGrowthStore.setActive(node.upgrade, isActive: $0) }
                    )
                )
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .toggleStyle(.switch)
                .accessibilityLabel("\(node.title)を有効化")
                .accessibilityIdentifier("dungeon_growth_active_\(node.upgrade.rawValue)")
            } else {
                Button {
                    if dungeonGrowthStore.unlock(node.upgrade) {
                        selectedGrowthUpgrade = node.upgrade
                    }
                } label: {
                    Label(node.canUnlock ? "\(node.cost)ptで取得" : "ロック中", systemImage: node.canUnlock ? "sparkles" : "lock.fill")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(node.canUnlock ? theme.accentPrimary : theme.textSecondary.opacity(0.35))
                .disabled(!node.canUnlock)
                .accessibilityIdentifier("dungeon_growth_unlock_\(node.upgrade.rawValue)")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.backgroundPrimary.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(node.strokeColor.opacity(0.7), lineWidth: 1)
        )
        .accessibilityIdentifier("dungeon_growth_detail_\(node.upgrade.rawValue)")
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

enum DungeonGrowthTreeNodeState: String, Equatable {
    case locked
    case unlockable
    case active
    case inactive

    var isUnlocked: Bool {
        self == .active || self == .inactive
    }
}

struct DungeonGrowthTreePresentation {
    let lanes: [DungeonGrowthTreeLanePresentation]

    var tierCount: Int {
        lanes.map { $0.nodes.count }.max() ?? 0
    }

    var defaultSelectedUpgrade: DungeonGrowthUpgrade? {
        lanes
            .flatMap(\.nodes)
            .first { !$0.state.isUnlocked }?
            .upgrade
            ?? lanes.flatMap(\.nodes).first?.upgrade
    }

    @MainActor
    static func make(growthStore: DungeonGrowthStore) -> DungeonGrowthTreePresentation {
        DungeonGrowthTreePresentation(
            lanes: DungeonGrowthBranch.allCases.map { branch in
                let nodes = DungeonGrowthUpgrade.allCases
                    .filter { $0.branch == branch }
                    .enumerated()
                    .map { tier, upgrade in
                        DungeonGrowthTreeNodePresentation.make(
                            upgrade: upgrade,
                            tier: tier,
                            growthStore: growthStore
                        )
                    }
                return DungeonGrowthTreeLanePresentation(branch: branch, nodes: nodes)
            }
        )
    }

    func node(for upgrade: DungeonGrowthUpgrade?) -> DungeonGrowthTreeNodePresentation? {
        guard let upgrade else { return nil }
        return lanes.flatMap(\.nodes).first { $0.upgrade == upgrade }
    }

    func gateText(forTier tier: Int) -> String {
        switch tier {
        case 0:
            return "5F"
        case 1:
            return "10F"
        case 2:
            return "15F"
        case 3:
            return "20F"
        default:
            return ""
        }
    }
}

struct DungeonGrowthTreeLanePresentation: Identifiable {
    let branch: DungeonGrowthBranch
    let nodes: [DungeonGrowthTreeNodePresentation]

    var id: DungeonGrowthBranch { branch }
    var branchTitle: String { branch.title }
    var iconSystemName: String { branch.iconSystemName }
    var tint: Color { branch.tintColor }

    func node(atTier tier: Int) -> DungeonGrowthTreeNodePresentation? {
        guard nodes.indices.contains(tier) else { return nil }
        return nodes[tier]
    }

    func hasConnector(afterTier tier: Int) -> Bool {
        nodes.indices.contains(tier) && nodes.indices.contains(tier + 1)
    }

    func connectorColor(afterTier tier: Int) -> Color {
        guard let current = node(atTier: tier),
              let next = node(atTier: tier + 1)
        else { return Color.clear }

        if current.state.isUnlocked && next.state.isUnlocked {
            return branch.tintColor.opacity(0.85)
        }
        if current.state.isUnlocked || next.state == .unlockable {
            return branch.tintColor.opacity(0.42)
        }
        return Color.secondary.opacity(0.22)
    }
}

struct DungeonGrowthTreeNodePresentation: Identifiable {
    let upgrade: DungeonGrowthUpgrade
    let tier: Int
    let state: DungeonGrowthTreeNodeState
    let lockReason: String?

    var id: DungeonGrowthUpgrade { upgrade }
    var title: String { upgrade.title }
    var shortTitle: String { upgrade.shortTitle }
    var summary: String { upgrade.summary }
    var cost: Int { upgrade.cost }
    var isUnlocked: Bool { state.isUnlocked }
    var isActive: Bool { state == .active }
    var canUnlock: Bool { state == .unlockable }
    var iconSystemName: String { upgrade.iconSystemName }

    var statusText: String {
        switch state {
        case .locked:
            return "ロック"
        case .unlockable:
            return "\(cost)pt"
        case .active:
            return "ON"
        case .inactive:
            return "OFF"
        }
    }

    var badgeText: String? {
        switch state {
        case .locked:
            return "鍵"
        case .unlockable:
            return "\(cost)pt"
        case .active:
            return "ON"
        case .inactive:
            return "OFF"
        }
    }

    var accessibilityIdentifier: String {
        "dungeon_growth_node_\(upgrade.rawValue)"
    }

    var accessibilityLabel: String {
        let reason = lockReason.map { "、\($0)" } ?? ""
        return "\(upgrade.branch.title)、\(title)、\(statusText)\(reason)"
    }

    var fillColor: Color {
        switch state {
        case .locked:
            return Color.secondary.opacity(0.12)
        case .unlockable:
            return upgrade.branch.tintColor.opacity(0.18)
        case .active:
            return upgrade.branch.tintColor
        case .inactive:
            return upgrade.branch.tintColor.opacity(0.10)
        }
    }

    var strokeColor: Color {
        switch state {
        case .locked:
            return Color.secondary.opacity(0.35)
        case .unlockable:
            return upgrade.branch.tintColor
        case .active:
            return upgrade.branch.tintColor.opacity(0.95)
        case .inactive:
            return upgrade.branch.tintColor.opacity(0.58)
        }
    }

    var strokeWidth: CGFloat {
        state == .unlockable ? 2.5 : 1.4
    }

    var iconColor: Color {
        switch state {
        case .active:
            return Color.white
        case .locked:
            return Color.secondary.opacity(0.68)
        case .unlockable, .inactive:
            return upgrade.branch.tintColor
        }
    }

    var titleColor: Color {
        state == .locked ? Color.secondary.opacity(0.82) : Color.primary
    }

    var badgeForegroundColor: Color {
        switch state {
        case .active:
            return Color.white
        case .locked:
            return Color.secondary
        case .unlockable, .inactive:
            return upgrade.branch.tintColor
        }
    }

    var badgeBackgroundColor: Color {
        switch state {
        case .active:
            return upgrade.branch.tintColor
        case .locked:
            return Color.secondary.opacity(0.16)
        case .unlockable, .inactive:
            return upgrade.branch.tintColor.opacity(0.16)
        }
    }

    var statusForegroundColor: Color {
        badgeForegroundColor
    }

    var statusBackgroundColor: Color {
        badgeBackgroundColor
    }

    var glowColor: Color {
        state == .unlockable ? upgrade.branch.tintColor.opacity(0.32) : Color.clear
    }

    var glowRadius: CGFloat {
        state == .unlockable ? 7 : 0
    }

    @MainActor
    static func make(
        upgrade: DungeonGrowthUpgrade,
        tier: Int,
        growthStore: DungeonGrowthStore
    ) -> DungeonGrowthTreeNodePresentation {
        let state: DungeonGrowthTreeNodeState
        if growthStore.isActive(upgrade) {
            state = .active
        } else if growthStore.isUnlocked(upgrade) {
            state = .inactive
        } else if growthStore.canUnlock(upgrade) {
            state = .unlockable
        } else {
            state = .locked
        }

        return DungeonGrowthTreeNodePresentation(
            upgrade: upgrade,
            tier: tier,
            state: state,
            lockReason: growthStore.lockReason(for: upgrade)
        )
    }
}

private extension DungeonGrowthBranch {
    var iconSystemName: String {
        switch self {
        case .preparation:
            return "bag.fill"
        case .reward:
            return "sparkles"
        case .hazard:
            return "shield.lefthalf.filled"
        }
    }

    var tintColor: Color {
        switch self {
        case .preparation:
            return Color(red: 0.04, green: 0.58, blue: 0.50)
        case .reward:
            return Color(red: 0.90, green: 0.54, blue: 0.06)
        case .hazard:
            return Color(red: 0.36, green: 0.56, blue: 0.98)
        }
    }
}

private extension DungeonGrowthUpgrade {
    var shortTitle: String {
        switch self {
        case .rewardScout:
            return "目利き"
        case .cardPreservation:
            return "温存"
        case .widerRewardRead:
            return "見立て"
        case .supportScout:
            return "補助"
        case .footingRead:
            return "足場"
        case .secondStep:
            return "踏み直し"
        case .enemyRead:
            return "警戒"
        case .meteorRead:
            return "着弾"
        default:
            return title
        }
    }

    var iconSystemName: String {
        switch self {
        case .toolPouch:
            return "bag.fill"
        case .climbingKit:
            return "figure.stairs"
        case .shortcutKit:
            return "arrow.up.right"
        case .refillCharm:
            return "plus.rectangle.on.rectangle"
        case .rewardScout:
            return "eye.fill"
        case .cardPreservation:
            return "rectangle.stack.fill"
        case .widerRewardRead:
            return "square.grid.2x2.fill"
        case .supportScout:
            return "cross.case.fill"
        case .footingRead:
            return "shoeprints.fill"
        case .secondStep:
            return "2.circle.fill"
        case .enemyRead:
            return "exclamationmark.shield.fill"
        case .meteorRead:
            return "flame.fill"
        }
    }
}
