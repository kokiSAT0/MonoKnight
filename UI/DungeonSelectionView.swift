import Game
import SwiftUI

/// 塔ダンジョンのフロアを選んで開始する入口。
/// タイトルから入る塔攻略専用の選択画面。
struct DungeonSelectionView: View {
    let dungeonLibrary: DungeonLibrary
    @ObservedObject var dungeonGrowthStore: DungeonGrowthStore
    @ObservedObject var gameSettingsStore: GameSettingsStore
    @ObservedObject var dungeonRunResumeStore: DungeonRunResumeStore
    @ObservedObject var rogueTowerRecordStore: RogueTowerRecordStore
    @ObservedObject var tutorialTowerProgressStore: TutorialTowerProgressStore
    let onResumeDungeon: (DungeonRunResumeSnapshot) -> Void
    let onStartDungeon: (DungeonDefinition, Int, DungeonGrowthPreparationChoice?, DungeonMovementStyle) -> Void

    private let theme = AppTheme()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isGrowthSectionExpanded = false
    @State private var selectedGrowthUpgrade: DungeonGrowthUpgrade?
    @State private var selectedGrowthBranch: DungeonGrowthBranch = .preparation
    @State private var isShowingAllGrowthBranches = false
    @State private var selectedGrowthForecastStartFloorNumber: Int?
    @State private var selectedGrowthMovementStyle: DungeonMovementStyle = .orthogonal
    @State private var selectedGrowthPreparationChoiceIDs: [String: String] = [:]
    @State private var pendingGrowthTowerIntroStart: PendingDungeonStart?

    @MainActor
    init(
        dungeonLibrary: DungeonLibrary,
        dungeonGrowthStore: DungeonGrowthStore,
        gameSettingsStore: GameSettingsStore,
        dungeonRunResumeStore: DungeonRunResumeStore = DungeonRunResumeStore(),
        rogueTowerRecordStore: RogueTowerRecordStore? = nil,
        tutorialTowerProgressStore: TutorialTowerProgressStore? = nil,
        onResumeDungeon: @escaping (DungeonRunResumeSnapshot) -> Void = { _ in },
        onStartDungeon: @escaping (DungeonDefinition, Int, DungeonGrowthPreparationChoice?, DungeonMovementStyle) -> Void
    ) {
        self.dungeonLibrary = dungeonLibrary
        self._dungeonGrowthStore = ObservedObject(wrappedValue: dungeonGrowthStore)
        self._gameSettingsStore = ObservedObject(wrappedValue: gameSettingsStore)
        self._dungeonRunResumeStore = ObservedObject(wrappedValue: dungeonRunResumeStore)
        self._rogueTowerRecordStore = ObservedObject(wrappedValue: rogueTowerRecordStore ?? RogueTowerRecordStore())
        self._tutorialTowerProgressStore = ObservedObject(wrappedValue: tutorialTowerProgressStore ?? TutorialTowerProgressStore())
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
        .alert(item: $pendingGrowthTowerIntroStart) { pendingStart in
            Alert(
                title: Text("基礎塔から始めますか？"),
                message: Text("基礎塔では成長塔の入口で使う読みを順に確認できます。"),
                primaryButton: .default(Text("基礎塔から始める")) {
                    tutorialTowerProgressStore.markGrowthTowerIntroPromptSeen()
                    if let tutorialTower = dungeonLibrary.dungeon(with: "tutorial-tower") {
                        onStartDungeon(tutorialTower, 0, nil, .orthogonal)
                    } else {
                        onStartDungeon(
                            pendingStart.dungeon,
                            pendingStart.floorIndex,
                            pendingStart.preparationChoice,
                            pendingStart.movementStyle
                        )
                    }
                },
                secondaryButton: .default(Text("成長塔へ進む")) {
                    tutorialTowerProgressStore.markGrowthTowerIntroPromptSeen()
                    onStartDungeon(
                        pendingStart.dungeon,
                        pendingStart.floorIndex,
                        pendingStart.preparationChoice,
                        pendingStart.movementStyle
                    )
                }
            )
        }
        .accessibilityIdentifier("dungeon_selection_view")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("キャンペーン")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(theme.textSecondary)

            Text("塔を登る")
                .font(.system(size: 25, weight: .heavy, design: .rounded))
                .foregroundColor(theme.textPrimary)

            Text("敵と床を読み、出口へ。")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func dungeonSection(_ dungeon: DungeonDefinition) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
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

                        if let tutorialStatus = TutorialTowerStatusPresentation.make(
                            dungeon: dungeon,
                            progressStore: tutorialTowerProgressStore
                        ) {
                            tutorialStatusBadge(tutorialStatus)
                        }

                        if let recordText = rogueTowerRecordStore.highestFloorText(for: dungeon) {
                            Text(recordText)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(theme.accentPrimary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(theme.accentPrimary.opacity(0.14)))
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                                .accessibilityIdentifier("dungeon_rogue_record_\(dungeon.id)")
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
            growthMovementStyleSection(for: dungeon)
            growthForecastSection(for: dungeon)
            growthPreparationChoiceSection(for: dungeon)
            startButtons(for: dungeon)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(dungeonCardBackgroundOpacity(for: dungeon))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(dungeonCardBorderColor(for: dungeon), lineWidth: dungeonCardBorderWidth(for: dungeon))
        )
        .accessibilityIdentifier("dungeon_card_\(dungeon.id)")
    }

    @ViewBuilder
    private func growthSection(for dungeon: DungeonDefinition) -> some View {
        if let presentation = DungeonGrowthTreeCardPresentation.make(
            dungeon: dungeon,
            growthStore: dungeonGrowthStore
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
                        Text(presentation.summaryText)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(theme.accentPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
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
            growthBranchSelector(presentation)

            if isShowingAllGrowthBranches {
                growthTreeGrid(presentation, selectedUpgrade: selectedUpgrade)
            } else if let lane = presentation.lane(for: selectedGrowthBranch) {
                growthBranchTimeline(lane, selectedUpgrade: selectedUpgrade)
            }

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
        .onChange(of: selectedGrowthBranch) { _, branch in
            guard !isShowingAllGrowthBranches,
                  let lane = presentation.lane(for: branch),
                  !lane.nodes.contains(where: { $0.upgrade == selectedGrowthUpgrade })
            else { return }
            selectedGrowthUpgrade = lane.defaultSelectedUpgrade
        }
        .accessibilityIdentifier("dungeon_growth_tree")
    }

    private func growthBranchSelector(_ presentation: DungeonGrowthTreePresentation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("系統を選ぶ")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundColor(theme.textPrimary)
                    Text("役割ごとに成長を確認。")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isShowingAllGrowthBranches.toggle()
                    }
                } label: {
                    Label(isShowingAllGrowthBranches ? "系統別" : "全体", systemImage: isShowingAllGrowthBranches ? "rectangle.split.1x2.fill" : "square.grid.3x3.fill")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("dungeon_growth_view_mode_toggle")
            }

            LazyVGrid(
                columns: growthBranchColumns,
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(presentation.branchRoles) { role in
                    growthBranchRoleButton(role)
                }
            }
            .padding(.vertical, 1)
            .accessibilityIdentifier("dungeon_growth_branch_grid")
        }
    }

    private var growthBranchColumns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: 132, maximum: 190),
                spacing: 8,
                alignment: .top
            )
        ]
    }

    private func growthBranchRoleButton(_ role: DungeonGrowthBranchRolePresentation) -> some View {
        let isSelected = !isShowingAllGrowthBranches && role.branch == selectedGrowthBranch
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedGrowthBranch = role.branch
                isShowingAllGrowthBranches = false
            }
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: role.iconSystemName)
                        .font(.system(size: 13, weight: .bold))
                    Text(role.title)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                }
                .foregroundColor(role.tint)

                Text(role.summary)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(minHeight: 86, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(role.tint.opacity(isSelected ? 0.16 : 0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? role.tint : theme.statisticBadgeBorder.opacity(0.7), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(role.accessibilityIdentifier)
    }

    private func growthBranchTimeline(
        _ lane: DungeonGrowthTreeLanePresentation,
        selectedUpgrade: DungeonGrowthUpgrade?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: lane.iconSystemName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(lane.tint)
                Text(lane.branchTitle)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundColor(theme.textPrimary)
                Text(lane.branchSummary)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            VStack(spacing: 7) {
                ForEach(lane.nodes) { node in
                    growthTimelineNodeRow(node, isSelected: node.upgrade == selectedUpgrade)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.backgroundPrimary.opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(lane.tint.opacity(0.34), lineWidth: 1)
        )
        .accessibilityIdentifier("dungeon_growth_branch_timeline_\(lane.branch.rawValue)")
    }

    private func growthTimelineNodeRow(
        _ node: DungeonGrowthTreeNodePresentation,
        isSelected: Bool
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedGrowthUpgrade = node.upgrade
            }
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: node.iconSystemName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(node.iconColor)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(node.fillColor))
                    .overlay(Circle().stroke(isSelected ? theme.textPrimary : node.strokeColor, lineWidth: isSelected ? 2.5 : 1))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(node.title)
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundColor(node.titleColor)
                            .lineLimit(1)
                        Text(node.statusText)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(node.statusForegroundColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(node.statusBackgroundColor))
                    }
                    Text(node.summary)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(theme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? node.fillColor.opacity(0.72) : theme.backgroundElevated.opacity(0.46))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? theme.textPrimary.opacity(0.55) : node.strokeColor.opacity(0.34), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(node.accessibilityLabel)
        .accessibilityIdentifier("dungeon_growth_timeline_node_\(node.upgrade.rawValue)")
    }

    private func growthTreeGrid(
        _ presentation: DungeonGrowthTreePresentation,
        selectedUpgrade: DungeonGrowthUpgrade?
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    ForEach(presentation.lanes) { lane in
                        Label(lane.branchTitle, systemImage: lane.iconSystemName)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(lane.tint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(width: 72)
                    }
                }

                ForEach(presentation.stageIndices, id: \.self) { stageIndex in
                    HStack(alignment: .center, spacing: 8) {
                        ForEach(presentation.lanes) { lane in
                            VStack(spacing: 6) {
                                if let node = lane.node(atStageIndex: stageIndex) {
                                    growthNodeButton(node, isSelected: node.upgrade == selectedUpgrade)
                                } else {
                                    Color.clear
                                        .frame(height: 58)
                                }

                                if lane.hasConnector(afterStageIndex: stageIndex) {
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(lane.connectorColor(afterStageIndex: stageIndex))
                                        .frame(width: 4, height: 16)
                                }
                            }
                            .frame(width: 72)
                        }
                    }
                }
            }
            .padding(10)
            .frame(minWidth: CGFloat(presentation.lanes.count) * 80, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.backgroundPrimary.opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.statisticBadgeBorder.opacity(0.7), lineWidth: 1)
        )
        .scrollClipDisabled()
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

                    Text(node.branchFocusText)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(node.strokeColor)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("取得すると: \(node.summary)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ForEach(node.lockDetailTexts, id: \.self) { lockDetailText in
                Label(lockDetailText, systemImage: "lock.fill")
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
    private func growthForecastSection(for dungeon: DungeonDefinition) -> some View {
        let floorNumbers = startFloorNumbers(for: dungeon)
        let forecastFloorNumber = selectedGrowthStartFloorNumber(from: floorNumbers)
        if let presentation = DungeonGrowthForecastPresentation.make(
            dungeon: dungeon,
            startFloorNumber: forecastFloorNumber,
            growthStore: dungeonGrowthStore
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(presentation.title, systemImage: "binoculars.fill")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundColor(theme.textPrimary)
                    Spacer()
                    Text(presentation.floorRangeText)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(theme.accentPrimary)
                }

                if floorNumbers.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(floorNumbers, id: \.self) { floorNumber in
                            Button {
                                selectedGrowthForecastStartFloorNumber = floorNumber
                            } label: {
                                Text("\(floorNumber)F")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .frame(minWidth: 38)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .tint(floorNumber == forecastFloorNumber ? theme.accentPrimary : theme.textSecondary)
                            .accessibilityIdentifier("dungeon_growth_forecast_floor_\(floorNumber)f")
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(presentation.rows) { row in
                        Label {
                            Text(row.text)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: row.iconSystemName)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(theme.accentPrimary)
                                .frame(width: 16)
                        }
                        .accessibilityIdentifier(row.accessibilityIdentifier)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.backgroundPrimary.opacity(0.46))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.accentPrimary.opacity(0.28), lineWidth: 1)
            )
            .accessibilityIdentifier("dungeon_growth_forecast")
        }
    }

    @ViewBuilder
    private func growthPreparationChoiceSection(for dungeon: DungeonDefinition) -> some View {
        let floorNumbers = startFloorNumbers(for: dungeon)
        let floorNumber = selectedGrowthStartFloorNumber(from: floorNumbers)
        let choices = dungeonGrowthStore.preparationChoices(
            for: dungeon,
            startingFloorIndex: floorNumber - 1,
            movementStyle: selectedMovementStyle(for: dungeon)
        )
        if !choices.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label("開始支度", systemImage: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundColor(theme.textPrimary)
                    Spacer()
                    Text("\(floorNumber)F")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(theme.accentPrimary)
                }

                let selectedID = selectedPreparationChoiceID(for: dungeon, floorNumber: floorNumber, choices: choices)
                VStack(spacing: 8) {
                    ForEach(choices) { choice in
                        Button {
                            selectedGrowthPreparationChoiceIDs[preparationChoiceSelectionKey(dungeon: dungeon, floorNumber: floorNumber)] = choice.id
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: choice.iconSystemName)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(choice.id == selectedID ? theme.accentOnPrimary : theme.accentPrimary)
                                    .frame(width: 18, height: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(choice.title)
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                    Text(choice.summary)
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                                if choice.id == selectedID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 14, weight: .bold))
                                }
                            }
                            .foregroundColor(choice.id == selectedID ? theme.accentOnPrimary : theme.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(choice.id == selectedID ? theme.accentPrimary : theme.backgroundPrimary.opacity(0.5))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(choice.id == selectedID ? theme.accentPrimary.opacity(0.9) : theme.statisticBadgeBorder, lineWidth: 1)
                        )
                        .accessibilityIdentifier("dungeon_growth_preparation_choice_\(choice.id)")
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.backgroundPrimary.opacity(0.46))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.accentPrimary.opacity(0.28), lineWidth: 1)
            )
            .accessibilityIdentifier("dungeon_growth_preparation_choices")
        }
    }

    @ViewBuilder
    private func growthMovementStyleSection(for dungeon: DungeonDefinition) -> some View {
        if dungeon.difficulty == .growth {
            let isKnightUnlocked = isKnightMovementStyleSelectable
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label("騎士を選ぶ", systemImage: "person.crop.square.filled.and.at.rectangle")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundColor(theme.textPrimary)
                    Spacer()
                    if !isKnightUnlocked {
                        Text("成長塔50F踏破で解放")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(theme.textSecondary)
                    }
                }

                HStack(spacing: 8) {
                    movementStyleButton(.orthogonal, isUnlocked: true)
                    movementStyleButton(.knight, isUnlocked: isKnightUnlocked)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.backgroundPrimary.opacity(0.46))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.statisticBadgeBorder.opacity(0.7), lineWidth: 1)
            )
            .onChange(of: isKnightUnlocked) { _, unlocked in
                if !unlocked, selectedGrowthMovementStyle == .knight {
                    selectedGrowthMovementStyle = .orthogonal
                }
            }
            .accessibilityIdentifier("dungeon_growth_movement_style_section")
        }
    }

    private func movementStyleButton(_ movementStyle: DungeonMovementStyle, isUnlocked: Bool) -> some View {
        let isSelected = selectedGrowthMovementStyle == movementStyle
        return Button {
            guard isUnlocked else { return }
            selectedGrowthMovementStyle = movementStyle
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: movementStyle == .knight ? "figure.run" : "figure.walk")
                        .font(.system(size: 13, weight: .bold))
                    Text(movementStyle.displayName)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                Text(isUnlocked ? movementStyle.summary : "成長塔50F踏破で解放")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(isSelected ? theme.accentOnPrimary.opacity(0.9) : theme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundColor(isSelected ? theme.accentOnPrimary : (isUnlocked ? theme.textPrimary : theme.textSecondary))
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? theme.accentPrimary : theme.backgroundElevated.opacity(isUnlocked ? 0.58 : 0.32))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? theme.accentPrimary : theme.statisticBadgeBorder.opacity(0.7), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isUnlocked)
        .accessibilityIdentifier("dungeon_growth_movement_style_\(movementStyle.rawValue)")
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
            handleStartDungeon(dungeon, floorIndex: floorNumber - 1)
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

    private func handleStartDungeon(_ dungeon: DungeonDefinition, floorIndex: Int) {
        let movementStyle = selectedMovementStyle(for: dungeon)
        let preparationChoice = selectedPreparationChoice(for: dungeon, floorNumber: floorIndex + 1)
        guard tutorialTowerProgressStore.shouldPresentGrowthTowerIntroPrompt(for: dungeon) else {
            onStartDungeon(dungeon, floorIndex, preparationChoice, movementStyle)
            return
        }
        pendingGrowthTowerIntroStart = PendingDungeonStart(
            dungeon: dungeon,
            floorIndex: floorIndex,
            preparationChoice: preparationChoice,
            movementStyle: movementStyle
        )
    }

    private func dungeonCardBackgroundOpacity(for dungeon: DungeonDefinition) -> Color {
        if dungeon.id == "tutorial-tower",
           !tutorialTowerProgressStore.hasCompletedTutorialTower {
            return theme.backgroundElevated.opacity(0.94)
        }
        return theme.backgroundElevated.opacity(0.86)
    }

    private func dungeonCardBorderColor(for dungeon: DungeonDefinition) -> Color {
        if dungeon.id == "tutorial-tower",
           !tutorialTowerProgressStore.hasCompletedTutorialTower {
            return theme.accentPrimary.opacity(0.62)
        }
        return theme.statisticBadgeBorder
    }

    private func dungeonCardBorderWidth(for dungeon: DungeonDefinition) -> CGFloat {
        dungeon.id == "tutorial-tower" && !tutorialTowerProgressStore.hasCompletedTutorialTower ? 1.5 : 1
    }

    private func tutorialStatusBadge(_ tutorialStatus: TutorialTowerStatusPresentation) -> some View {
        Text(tutorialStatus.text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundColor(tutorialStatus.isCompleted ? theme.textSecondary : theme.accentPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(
                    tutorialStatus.isCompleted
                        ? theme.textSecondary.opacity(0.12)
                        : theme.accentPrimary.opacity(0.14)
                )
            )
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .accessibilityIdentifier(tutorialStatus.accessibilityIdentifier)
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

    private func selectedGrowthStartFloorNumber(from floorNumbers: [Int]) -> Int {
        let fallbackFloorNumber = floorNumbers.last ?? 1
        return floorNumbers.contains(selectedGrowthForecastStartFloorNumber ?? -1)
            ? (selectedGrowthForecastStartFloorNumber ?? fallbackFloorNumber)
            : fallbackFloorNumber
    }

    private func preparationChoiceSelectionKey(dungeon: DungeonDefinition, floorNumber: Int) -> String {
        "\(dungeon.id)-\(floorNumber)f"
    }

    private func selectedPreparationChoiceID(
        for dungeon: DungeonDefinition,
        floorNumber: Int,
        choices: [DungeonGrowthPreparationChoice]
    ) -> String? {
        let key = preparationChoiceSelectionKey(dungeon: dungeon, floorNumber: floorNumber)
        if let selectedID = selectedGrowthPreparationChoiceIDs[key],
           choices.contains(where: { $0.id == selectedID }) {
            return selectedID
        }
        return choices.first?.id
    }

    private func selectedPreparationChoice(
        for dungeon: DungeonDefinition,
        floorNumber: Int
    ) -> DungeonGrowthPreparationChoice? {
        let choices = dungeonGrowthStore.preparationChoices(
            for: dungeon,
            startingFloorIndex: floorNumber - 1,
            movementStyle: selectedMovementStyle(for: dungeon)
        )
        guard !choices.isEmpty else { return nil }
        let selectedID = selectedPreparationChoiceID(for: dungeon, floorNumber: floorNumber, choices: choices)
        return choices.first { $0.id == selectedID } ?? choices.first
    }

    private var isKnightMovementStyleSelectable: Bool {
        dungeonGrowthStore.isKnightMovementStyleUnlocked
            || gameSettingsStore.unlocksKnightMovementStyleForDeveloper
    }

    private func selectedMovementStyle(for dungeon: DungeonDefinition) -> DungeonMovementStyle {
        guard dungeon.difficulty == .growth else { return .orthogonal }
        guard selectedGrowthMovementStyle == .knight else { return .orthogonal }
        return isKnightMovementStyleSelectable ? .knight : .orthogonal
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
              (dungeon.supportsInfiniteFloors || dungeon.floors.indices.contains(snapshot.floorIndex))
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

struct PendingDungeonStart: Identifiable {
    let dungeon: DungeonDefinition
    let floorIndex: Int
    let preparationChoice: DungeonGrowthPreparationChoice?
    let movementStyle: DungeonMovementStyle

    var id: String { "\(dungeon.id)-\(floorIndex)-\(movementStyle.rawValue)" }
}

struct TutorialTowerStatusPresentation: Equatable {
    let text: String
    let accessibilityIdentifier: String
    let isCompleted: Bool

    @MainActor
    static func make(
        dungeon: DungeonDefinition,
        progressStore: TutorialTowerProgressStore
    ) -> TutorialTowerStatusPresentation? {
        guard dungeon.id == "tutorial-tower" else { return nil }
        let isCompleted = progressStore.hasCompletedTutorialTower
        return TutorialTowerStatusPresentation(
            text: isCompleted ? "完了済" : "おすすめ",
            accessibilityIdentifier: "dungeon_tutorial_status_\(dungeon.id)",
            isCompleted: isCompleted
        )
    }
}

struct DungeonGrowthForecastPresentation: Equatable {
    struct Row: Identifiable, Equatable {
        let category: DungeonGrowthForecastCategory
        let text: String
        let iconSystemName: String

        var id: DungeonGrowthForecastCategory { category }
        var accessibilityIdentifier: String {
            "dungeon_growth_forecast_\(category.rawValue)"
        }
    }

    let title: String
    let floorRangeText: String
    let rows: [Row]

    @MainActor
    static func make(
        dungeon: DungeonDefinition,
        startFloorNumber: Int,
        growthStore: DungeonGrowthStore
    ) -> DungeonGrowthForecastPresentation? {
        guard dungeon.difficulty == .growth else { return nil }
        let activeScoutingUpgrades = DungeonGrowthUpgrade.scoutingForecastUpgrades
            .filter { growthStore.isActive($0) }
        guard !activeScoutingUpgrades.isEmpty else { return nil }

        let safeStartFloorNumber = min(max(startFloorNumber, 1), max(dungeon.floors.count, 1))
        let sectionEndFloorNumber = min(((safeStartFloorNumber - 1) / 10 + 1) * 10, dungeon.floors.count)
        let floorRange = safeStartFloorNumber...sectionEndFloorNumber
        let floors = floorRange.compactMap { floorNumber in
            dungeon.floors.indices.contains(floorNumber - 1) ? dungeon.floors[floorNumber - 1] : nil
        }
        guard !floors.isEmpty else { return nil }

        let facts = DungeonGrowthForecastFacts(floors: floors)
        var rows: [Row] = []
        for upgrade in activeScoutingUpgrades {
            guard let row = facts.row(for: upgrade, floorRange: floorRange) else { continue }
            if !rows.contains(where: { $0.category == row.category }) {
                rows.append(row)
            }
        }
        guard !rows.isEmpty else { return nil }

        return DungeonGrowthForecastPresentation(
            title: "次区間の見通し",
            floorRangeText: "\(floorRange.lowerBound)F-\(floorRange.upperBound)F",
            rows: rows
        )
    }
}

enum DungeonGrowthForecastCategory: String, Equatable {
    case floor
    case reward
    case enemy
    case path
    case deep
    case final
}

private struct DungeonGrowthForecastFacts {
    let floorLabels: [String]
    let rewardLabels: [String]
    let enemyLabels: [String]
    let pathLabels: [String]
    let hasDeepComplexity: Bool
    let hasFinalComplexity: Bool

    init(floors: [DungeonFloorDefinition]) {
        floorLabels = Self.collectFloorLabels(from: floors)
        rewardLabels = Self.collectRewardLabels(from: floors)
        enemyLabels = Self.collectEnemyLabels(from: floors)
        pathLabels = Self.collectPathLabels(from: floors)
        hasDeepComplexity = floors.contains { floor in
            floor.isDarknessEnabled
                || !floor.fallSecrets.isEmpty
                || floor.tileEffectOverrides.values.contains(where: \.isDeepStatusEffect)
                || floor.relicPickups.contains { $0.kind != .safe }
        }
        hasFinalComplexity = floors.contains { floor in
            floor.enemies.count >= 3
                || !floor.fallSecrets.isEmpty
                || floor.tileEffectOverrides.values.contains(where: \.isHandLossEffect)
                || floor.relicPickups.contains { $0.kind == .suspiciousDeep }
        }
    }

    func row(
        for upgrade: DungeonGrowthUpgrade,
        floorRange: ClosedRange<Int>
    ) -> DungeonGrowthForecastPresentation.Row? {
        switch upgrade {
        case .floorSense:
            return makeRow(
                category: .floor,
                icon: "square.grid.3x3.fill",
                prefix: "床",
                labels: floorLabels
            )
        case .rewardSense:
            return makeRow(
                category: .reward,
                icon: "gift.fill",
                prefix: "報酬",
                labels: rewardLabels
            )
        case .enemySense:
            return makeRow(
                category: .enemy,
                icon: "eye.trianglebadge.exclamationmark.fill",
                prefix: "敵",
                labels: enemyLabels
            )
        case .pathPreview:
            return makeRow(
                category: .path,
                icon: "point.forward.to.point.capsulepath.fill",
                prefix: "経路",
                labels: pathLabels
            )
        case .deepForecast:
            guard floorRange.upperBound >= 31 else { return nil }
            let text = hasDeepComplexity
                ? "深層: 状態異常、暗闇、宝箱リスクが重なります"
                : "深層: 複合ギミックが増える区間です"
            return DungeonGrowthForecastPresentation.Row(
                category: .deep,
                text: text,
                iconSystemName: "binoculars.fill"
            )
        case .routeForecast:
            guard floorRange.upperBound >= 41 else { return nil }
            let text = hasFinalComplexity
                ? "踏破: 危険・報酬・寄り道をまとめて見て進みます"
                : "踏破: 最終区間の危険と報酬をまとめて確認できます"
            return DungeonGrowthForecastPresentation.Row(
                category: .final,
                text: text,
                iconSystemName: "map.fill"
            )
        default:
            return nil
        }
    }

    private func makeRow(
        category: DungeonGrowthForecastCategory,
        icon: String,
        prefix: String,
        labels: [String]
    ) -> DungeonGrowthForecastPresentation.Row? {
        guard !labels.isEmpty else { return nil }
        return DungeonGrowthForecastPresentation.Row(
            category: category,
            text: "\(prefix): \(labels.prefix(4).joined(separator: "、"))",
            iconSystemName: icon
        )
    }

    private static func collectFloorLabels(from floors: [DungeonFloorDefinition]) -> [String] {
        var labels: [String] = []
        for floor in floors {
            for hazard in floor.hazards {
                switch hazard {
                case .brittleFloor:
                    labels.appendUnique("床割れ")
                case .damageTrap:
                    labels.appendUnique("罠")
                case .lavaTile:
                    labels.appendUnique("溶岩")
                case .healingTile:
                    labels.appendUnique("回復マス")
                }
            }
            if !floor.warpTilePairs.isEmpty {
                labels.appendUnique("ワープ")
            }
            if floor.isDarknessEnabled {
                labels.appendUnique("暗闇")
            }
            for effect in floor.tileEffectOverrides.values {
                if let label = effect.forecastFloorLabel {
                    labels.appendUnique(label)
                }
            }
        }
        return labels
    }

    private static func collectRewardLabels(from floors: [DungeonFloorDefinition]) -> [String] {
        var labels: [String] = []
        if floors.contains(where: { !$0.cardPickups.isEmpty }) {
            labels.appendUnique("拾得カード")
        }
        if floors.contains(where: { !$0.rewardMoveCardsAfterClear.isEmpty }) {
            labels.appendUnique("移動報酬")
        }
        if floors.contains(where: { !$0.rewardSupportCardsAfterClear.isEmpty }) {
            labels.appendUnique("補助報酬")
        }
        if floors.contains(where: { !$0.relicPickups.isEmpty }) {
            labels.appendUnique("宝箱")
        }
        if floors.contains(where: { $0.relicPickups.contains { $0.kind != .safe } }) {
            labels.appendUnique("呪い宝箱")
        }
        return labels
    }

    private static func collectEnemyLabels(from floors: [DungeonFloorDefinition]) -> [String] {
        var labels: [String] = []
        var patrolCount = 0
        for floor in floors {
            for enemy in floor.enemies {
                switch enemy.behavior {
                case .guardPost:
                    labels.appendUnique("番兵")
                case .patrol:
                    patrolCount += 1
                    labels.appendUnique("巡回兵")
                case .watcher:
                    labels.appendUnique("見張り")
                case .rotatingWatcher:
                    labels.appendUnique("回転見張り")
                case .chaser:
                    labels.appendUnique("追跡圧")
                case .marker:
                    labels.appendUnique("メテオ")
                }
            }
        }
        if patrolCount >= 3 {
            labels.removeAll { $0 == "巡回兵" }
            labels.insert("巡回多め", at: 0)
        }
        return labels
    }

    private static func collectPathLabels(from floors: [DungeonFloorDefinition]) -> [String] {
        var labels: [String] = []
        if floors.contains(where: { $0.exitLock != nil }) {
            labels.appendUnique("鍵ルート")
        }
        if floors.contains(where: { !$0.warpTilePairs.isEmpty }) {
            labels.appendUnique("ワープ分岐")
        }
        if floors.contains(where: { !$0.fallSecrets.isEmpty }) {
            labels.appendUnique("落下宝箱")
        }
        if floors.contains(where: { !$0.relicPickups.isEmpty }) {
            labels.appendUnique("寄り道宝箱")
        }
        if floors.contains(where: { !$0.impassableTilePoints.isEmpty }) {
            labels.appendUnique("岩柱で迂回")
        }
        return labels
    }
}

struct DungeonGrowthTreeCardPresentation: Equatable {
    let title: String
    let progressText: String
    let pointsText: String
    let summaryText: String
    let sectionAccessibilityIdentifier: String
    let toggleAccessibilityIdentifier: String

    @MainActor
    static func make(dungeon: DungeonDefinition, growthStore: DungeonGrowthStore) -> DungeonGrowthTreeCardPresentation? {
        guard dungeon.difficulty == .growth else { return nil }
        let milestoneIDs = growthStore.growthMilestoneIDs(for: dungeon)
        let rewardedCount = milestoneIDs.filter { growthStore.hasRewardedGrowthMilestone($0) }.count
        let progressText = "\(rewardedCount)/\(milestoneIDs.count)獲得"
        let pointsText = "ポイント \(max(growthStore.points, 0))"
        return DungeonGrowthTreeCardPresentation(
            title: "成長",
            progressText: progressText,
            pointsText: pointsText,
            summaryText: "\(progressText) · \(pointsText)",
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
    let stageIndices: [Int]

    var branchRoles: [DungeonGrowthBranchRolePresentation] {
        lanes.map { lane in
            DungeonGrowthBranchRolePresentation(branch: lane.branch)
        }
    }

    var tierCount: Int {
        stageIndices.count
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
        let lanes = DungeonGrowthBranch.allCases.map { branch in
            let nodes = DungeonGrowthUpgrade.allCases
                .filter { $0.branch == branch }
                .sorted { lhs, rhs in
                    if lhs.displayTierFloor != rhs.displayTierFloor {
                        return lhs.displayTierFloor < rhs.displayTierFloor
                    }
                    return lhs.rawValue < rhs.rawValue
                }
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
        let stageCount = lanes.map(\.nodes.count).max() ?? 0
        return DungeonGrowthTreePresentation(
            lanes: lanes,
            stageIndices: Array(0..<stageCount)
        )
    }

    func node(for upgrade: DungeonGrowthUpgrade?) -> DungeonGrowthTreeNodePresentation? {
        guard let upgrade else { return nil }
        return lanes.flatMap(\.nodes).first { $0.upgrade == upgrade }
    }

    func lane(for branch: DungeonGrowthBranch) -> DungeonGrowthTreeLanePresentation? {
        lanes.first { $0.branch == branch }
    }

}

struct DungeonGrowthBranchRolePresentation: Identifiable, Equatable {
    let branch: DungeonGrowthBranch

    var id: DungeonGrowthBranch { branch }
    var title: String { branch.title }
    var summary: String { branch.roleSummary }
    var iconSystemName: String { branch.iconSystemName }
    var tint: Color { branch.tintColor }
    var accessibilityIdentifier: String {
        "dungeon_growth_branch_role_\(branch.rawValue)"
    }
}

struct DungeonGrowthTreeLanePresentation: Identifiable {
    let branch: DungeonGrowthBranch
    let nodes: [DungeonGrowthTreeNodePresentation]

    var id: DungeonGrowthBranch { branch }
    var branchTitle: String { branch.title }
    var branchSummary: String { branch.roleSummary }
    var iconSystemName: String { branch.iconSystemName }
    var tint: Color { branch.tintColor }
    var defaultSelectedUpgrade: DungeonGrowthUpgrade? {
        nodes.first { !$0.state.isUnlocked }?.upgrade ?? nodes.first?.upgrade
    }

    func node(atStageIndex stageIndex: Int) -> DungeonGrowthTreeNodePresentation? {
        guard nodes.indices.contains(stageIndex) else { return nil }
        return nodes[stageIndex]
    }

    func hasConnector(afterStageIndex stageIndex: Int) -> Bool {
        nodes.indices.contains(stageIndex) && nodes.indices.contains(stageIndex + 1)
    }

    func connectorColor(afterStageIndex stageIndex: Int) -> Color {
        guard nodes.indices.contains(stageIndex),
              nodes.indices.contains(stageIndex + 1)
        else { return Color.clear }
        let current = nodes[stageIndex]
        let next = nodes[stageIndex + 1]

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
    let tierFloor: Int
    let state: DungeonGrowthTreeNodeState
    let lockReason: String?
    let missingPrerequisiteTitles: [String]
    let isPointShortage: Bool

    var id: DungeonGrowthUpgrade { upgrade }
    var title: String { upgrade.title }
    var shortTitle: String { upgrade.shortTitle }
    var summary: String { upgrade.summary }
    var cost: Int { upgrade.cost }
    var isUnlocked: Bool { state.isUnlocked }
    var isActive: Bool { state == .active }
    var canUnlock: Bool { state == .unlockable }
    var iconSystemName: String { upgrade.iconSystemName }
    var branchFocusText: String { upgrade.branch.detailFocus }
    var lockDetailTexts: [String] {
        var details: [String] = []
        if !missingPrerequisiteTitles.isEmpty {
            details.append("前提スキル: \(missingPrerequisiteTitles.joined(separator: "、"))")
        }
        if isPointShortage {
            details.append("必要ポイント: \(cost)pt")
        }
        if details.isEmpty, let lockReason {
            details.append(lockReason)
        }
        return details
    }

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
            tierFloor: upgrade.displayTierFloor,
            state: state,
            lockReason: growthStore.lockReason(for: upgrade),
            missingPrerequisiteTitles: upgrade.requiredUpgrades
                .filter { !growthStore.isUnlocked($0) }
                .map(\.title)
                .sorted(),
            isPointShortage: !growthStore.isUnlocked(upgrade) && growthStore.points < upgrade.cost
        )
    }
}

private extension DungeonGrowthBranch {
    var roleSummary: String {
        switch self {
        case .preparation:
            return "区間開始前の支度候補"
        case .reward:
            return "クリア後候補とカード運用"
        case .hazard:
            return "危険に合わせた対策支度"
        case .scouting:
            return "次階層帯の見通し"
        case .recovery:
            return "深層チェックポイントと再挑戦支援"
        }
    }

    var detailFocus: String {
        switch self {
        case .preparation:
            return "この系統: 区間開始前の支度候補を増やします"
        case .reward:
            return "この系統: クリア後の選択肢とカード運用を伸ばします"
        case .hazard:
            return "この系統: 見えた危険に合う対策を増やします"
        case .scouting:
            return "この系統: 次の階層帯を読む材料を増やします"
        case .recovery:
            return "この系統: 深層の再挑戦と復帰を助けます"
        }
    }

    var iconSystemName: String {
        switch self {
        case .preparation:
            return "bag.fill"
        case .reward:
            return "sparkles"
        case .hazard:
            return "shield.lefthalf.filled"
        case .scouting:
            return "eye.fill"
        case .recovery:
            return "arrow.clockwise.circle.fill"
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
        case .scouting:
            return Color(red: 0.50, green: 0.36, blue: 0.82)
        case .recovery:
            return Color(red: 0.70, green: 0.18, blue: 0.42)
        }
    }
}

private extension Array where Element: Equatable {
    mutating func appendUnique(_ element: Element) {
        guard !contains(element) else { return }
        append(element)
    }
}

private extension TileEffect {
    var forecastFloorLabel: String? {
        switch self {
        case .warp, .returnWarp:
            return "ワープ"
        case .slow:
            return "鈍足床"
        case .shackleTrap:
            return "足枷"
        case .poisonTrap:
            return "毒"
        case .illusionTrap:
            return "幻惑"
        case .swamp:
            return "沼"
        case .discardRandomHand, .discardAllMoveCards, .discardAllSupportCards, .discardAllHands:
            return "手札喪失"
        case .shuffleHand, .blast, .preserveCard:
            return nil
        }
    }

    var isDeepStatusEffect: Bool {
        switch self {
        case .poisonTrap, .illusionTrap, .shackleTrap, .swamp:
            return true
        case .warp, .returnWarp, .shuffleHand, .blast, .slow, .preserveCard, .discardRandomHand, .discardAllMoveCards, .discardAllSupportCards, .discardAllHands:
            return false
        }
    }

    var isHandLossEffect: Bool {
        switch self {
        case .discardRandomHand, .discardAllMoveCards, .discardAllSupportCards, .discardAllHands:
            return true
        case .warp, .returnWarp, .shuffleHand, .blast, .slow, .shackleTrap, .poisonTrap, .illusionTrap, .swamp, .preserveCard:
            return false
        }
    }
}

private extension DungeonGrowthUpgrade {
    static var scoutingForecastUpgrades: [DungeonGrowthUpgrade] {
        [
            .floorSense,
            .rewardSense,
            .enemySense,
            .pathPreview,
            .deepForecast,
            .routeForecast
        ]
    }

    var displayTierFloor: Int {
        tierFloor ?? 5
    }

    var shortTitle: String {
        switch self {
        case .deepStartKit:
            return "深層"
        case .routeKit:
            return "経路"
        case .deepSupplyCraft:
            return "補給術"
        case .finalPreparation:
            return "踏破"
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
        case .lastStand:
            return "保険"
        case .enemyReadPlus:
            return "警戒+"
        case .fallInsurance:
            return "落下"
        case .dangerForecast:
            return "予報"
        case .finalGuard:
            return "防衛"
        case .floorSense:
            return "床"
        case .rewardSense:
            return "報酬"
        case .enemySense:
            return "敵影"
        case .pathPreview:
            return "経路"
        case .deepForecast:
            return "深層"
        case .routeForecast:
            return "踏破"
        case .retryPreparation:
            return "再挑戦"
        case .sectionRecovery:
            return "立て直し"
        case .deepCheckpointRead:
            return "旗印"
        case .checkpointExpansion:
            return "拡張"
        case .comebackRoute:
            return "復帰路"
        case .finalRecovery:
            return "復帰"
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
        case .deepStartKit:
            return "shield.fill"
        case .routeKit:
            return "point.topleft.down.curvedto.point.bottomright.up"
        case .deepSupplyCraft:
            return "cross.case.fill"
        case .finalPreparation:
            return "flag.checkered"
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
        case .relicScout:
            return "sparkle.magnifyingglass"
        case .rewardUpgradeScout:
            return "arrow.up.square.fill"
        case .rewardRerollRead:
            return "arrow.triangle.2.circlepath"
        case .supportMastery:
            return "wand.and.stars"
        case .rewardCompletion:
            return "rosette"
        case .footingRead:
            return "shoeprints.fill"
        case .secondStep:
            return "2.circle.fill"
        case .enemyRead:
            return "exclamationmark.shield.fill"
        case .meteorRead:
            return "flame.fill"
        case .lastStand:
            return "heart.text.square.fill"
        case .enemyReadPlus:
            return "shield.righthalf.filled"
        case .fallInsurance:
            return "arrow.down.to.line.compact"
        case .dangerForecast:
            return "cloud.bolt.fill"
        case .finalGuard:
            return "shield.checkered"
        case .floorSense:
            return "square.grid.3x3.fill"
        case .rewardSense:
            return "gift.fill"
        case .enemySense:
            return "eye.trianglebadge.exclamationmark.fill"
        case .pathPreview:
            return "point.forward.to.point.capsulepath.fill"
        case .deepForecast:
            return "binoculars.fill"
        case .routeForecast:
            return "map.fill"
        case .retryPreparation:
            return "arrow.counterclockwise.circle.fill"
        case .sectionRecovery:
            return "bandage.fill"
        case .deepCheckpointRead:
            return "flag.fill"
        case .checkpointExpansion:
            return "flag.2.crossed.fill"
        case .comebackRoute:
            return "arrow.uturn.backward.circle.fill"
        case .finalRecovery:
            return "goforward.plus"
        }
    }
}
