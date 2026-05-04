import SwiftUI
import Game
import SharedSupport

/// タイトル画面での開始導線がどこから来たかを表す文脈
enum GamePreparationContext: Equatable {
    case dungeonSelection
    case dungeonContinuation
    case other

    var logIdentifier: String {
        switch self {
        case .dungeonSelection:
            return "dungeon_selection"
        case .dungeonContinuation:
            return "dungeon_continuation"
        case .other:
            return "other"
        }
    }

    var isDungeonDerived: Bool {
        switch self {
        case .dungeonSelection, .dungeonContinuation:
            return true
        case .other:
            return false
        }
    }
}

/// タイトル画面での NavigationStack 先を外部から指示するためのターゲット
enum TitleNavigationTarget: String, Hashable, Codable {
    case dungeon
}

// MARK: - タイトル画面（リニューアル）
struct TitleScreenView: View {
    @ObservedObject var dungeonGrowthStore: DungeonGrowthStore
    @Binding private var pendingNavigationTarget: TitleNavigationTarget?
    let onStart: (GameMode, GamePreparationContext) -> Void
    let onOpenSettings: () -> Void

    private var theme = AppTheme()
    private let dungeonLibrary = DungeonLibrary.shared
    @State private var isPresentingHowToPlay: Bool = false
    @State private var navigationPath: [TitleNavigationTarget] = []
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var gameSettingsStore: GameSettingsStore
    private let instanceIdentifier = UUID()

    /// ゲーム開始要求がどこから届いたかを判定するための文脈列挙
    private enum StartTriggerContext: String {
        case dungeonSelection = "dungeon_selection"

        var logDescription: String {
            switch self {
            case .dungeonSelection:
                return "塔選択から開始"
            }
        }

        var preparationContext: GamePreparationContext {
            switch self {
            case .dungeonSelection:
                return .dungeonSelection
            }
        }
    }

    init(dungeonGrowthStore: DungeonGrowthStore,
         pendingNavigationTarget: Binding<TitleNavigationTarget?>,
         onStart: @escaping (GameMode, GamePreparationContext) -> Void,
        onOpenSettings: @escaping () -> Void) {
        self._dungeonGrowthStore = ObservedObject(wrappedValue: dungeonGrowthStore)
        self._pendingNavigationTarget = pendingNavigationTarget
        self.onStart = onStart
        self.onOpenSettings = onOpenSettings
        _isPresentingHowToPlay = State(initialValue: false)
        debugLog("TitleScreenView.init開始: instance=\(instanceIdentifier.uuidString) navigationPathCount=\(_navigationPath.wrappedValue.count)")
    }

    var body: some View {
        debugLog("TitleScreenView.body評価: instance=\(instanceIdentifier.uuidString) navigationPathCount=\(navigationPath.count)")
        return NavigationStack(path: $navigationPath) {
            titleScreenMainContent
                .navigationDestination(for: TitleNavigationTarget.self) { target in
                    let stackDescription = navigationPath
                        .map { $0.rawValue }
                        .joined(separator: ",")
                    let _ = debugLog(
                        "TitleScreenView: NavigationDestination.entry -> instance=\(instanceIdentifier.uuidString) target=\(target.rawValue) targetType=\(String(describing: type(of: target))) stackCount=\(navigationPath.count) stack=[\(stackDescription)]"
                    )
                    navigationDestinationView(for: target)
                }
        }
        .fullScreenCover(isPresented: $isPresentingHowToPlay) {
            howToPlayFullScreenContent
        }
        .onChange(of: isPresentingHowToPlay) { _, newValue in
            debugLog("TitleScreenView.isPresentingHowToPlay 更新: \(newValue)")
        }
        .onChange(of: navigationPath) { oldValue, newValue in
            let stackDescription = newValue
                .map { String(describing: $0) }
                .joined(separator: ",")
            debugLog(
                "TitleScreenView.navigationPath 更新: instance=\(instanceIdentifier.uuidString) 旧=\(oldValue.count) -> 新=\(newValue.count) スタック=[\(stackDescription)]"
            )
        }
        .onChange(of: horizontalSizeClass) { _, newValue in
            debugLog("TitleScreenView.horizontalSizeClass 更新: \(String(describing: newValue))")
        }
        .onAppear {
            processPendingNavigationTargetIfNeeded()
        }
        .onChange(of: pendingNavigationTarget) { _, _ in
            processPendingNavigationTargetIfNeeded()
        }
    }

    @ViewBuilder
    private var titleScreenMainContent: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 28) {
                    headerSection
                    featureTilesSection
                    howToPlayButton
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 72)
                .padding(.bottom, 64)
                .frame(maxWidth: contentMaxWidth)
                .frame(maxWidth: .infinity)
            }
            .background(theme.backgroundPrimary)

            settingsButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.backgroundPrimary)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("タイトル画面。塔ダンジョンからプレイを開始できます。")
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            Text("MonoKnight")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundColor(theme.textPrimary)
            Text("カードで騎士を導き、塔を登ろう")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
    }

    private var howToPlayButton: some View {
        Button {
            debugLog("TitleScreenView: 遊び方シート表示要求")
            isPresentingHowToPlay = true
        } label: {
            Label("遊び方を見る", systemImage: "questionmark.circle")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(theme.accentPrimary)
        .foregroundColor(theme.accentOnPrimary)
        .controlSize(.large)
        .accessibilityIdentifier("title_how_to_play_button")
        .accessibilityHint(Text("MonoKnight の基本ルールを確認できます"))
    }

    private var settingsButton: some View {
        Button {
            debugLog("TitleScreenView: 設定シート表示要求")
            onOpenSettings()
        } label: {
            Image(systemName: "gearshape.fill")
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
        .padding(.top, 16)
        .padding(.trailing, 20)
        .accessibilityLabel("設定")
        .accessibilityHint("広告やプライバシー設定などを確認できます")
    }

    private var featureTilesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("メインコンテンツ")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(theme.textPrimary)

            LazyVGrid(columns: featureTileColumns, alignment: .leading, spacing: 14) {
                featureTile(
                    target: .dungeon,
                    title: "塔ダンジョン",
                    systemImage: "figure.stairs",
                    headline: dungeonTileHeadline,
                    detail: dungeonTileDetail,
                    accessibilityID: "title_tile_dungeon",
                    accessibilityHint: "塔ダンジョンの塔選択を表示します"
                )
            }
        }
    }

    private func featureTile(
        target: TitleNavigationTarget,
        title: String,
        systemImage: String,
        headline: String,
        detail: String,
        accessibilityID: String,
        accessibilityHint: String
    ) -> some View {
        NavigationLink(value: target) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 12) {
                    featureIconTile(systemName: systemImage)
                        .alignmentGuide(.firstTextBaseline) { dimensions in
                            dimensions[VerticalAlignment.center]
                        }

                    Text(title)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.textPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .foregroundColor(theme.textSecondary.opacity(0.7))
                        .font(.system(size: 14, weight: .semibold))
                }

                Text(headline)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(theme.textSecondary)
                Text(detail)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(theme.textSecondary.opacity(0.85))
                    .multilineTextAlignment(.leading)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(theme.backgroundElevated.opacity(0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(theme.statisticBadgeBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            TapGesture().onEnded {
                handleTileTapLogging(for: target)
            }
        )
        .accessibilityIdentifier(accessibilityID)
        .accessibilityLabel(Text("\(title)。\(headline)。\(detail)"))
        .accessibilityHint(Text(accessibilityHint))
    }

    private func navigationDestinationView(for target: TitleNavigationTarget) -> some View {
        switch target {
        case .dungeon:
            let stackDescription = navigationPath
                .map { $0.rawValue }
                .joined(separator: ",")
            let _ = debugLog(
                "TitleScreenView: NavigationDestination.dungeon 構築開始 -> instance=\(instanceIdentifier.uuidString) targetType=\(String(describing: type(of: target))) stackCount=\(navigationPath.count) stack=[\(stackDescription)]"
            )
            return AnyView(
                DungeonSelectionView(
                    dungeonLibrary: dungeonLibrary,
                    dungeonGrowthStore: dungeonGrowthStore,
                    onClose: { popNavigationStack() },
                    onStartDungeon: { dungeon, floorIndex in
                        guard let mode = dungeonLibrary.floorMode(
                            for: dungeon,
                            floorIndex: floorIndex,
                            initialHPBonus: dungeonGrowthStore.initialHPBonus(
                                for: dungeon,
                                startingFloorIndex: floorIndex
                            ),
                            startingRewardEntries: dungeonGrowthStore.startingRewardEntries(
                                for: dungeon,
                                startingFloorIndex: floorIndex
                            ),
                            startingHazardDamageMitigations: dungeonGrowthStore.startingHazardDamageMitigations(
                                for: dungeon
                            )
                        ) else { return }
                        let context: StartTriggerContext = .dungeonSelection
                        debugLog(
                            "TitleScreenView: ダンジョン開始後 -> dungeon=\(dungeon.id) NavigationStack をリセットして即時開始を登録 context=\(context.rawValue)"
                        )
                        resetNavigationStack()
                        DispatchQueue.main.async {
                            triggerImmediateStart(for: mode, context: context)
                        }
                    }
                )
                .onAppear {
                    debugLog("TitleScreenView: NavigationDestination.dungeon 表示 -> 現在のスタック数=\(navigationPath.count)")
                }
                .onDisappear {
                    debugLog("TitleScreenView: NavigationDestination.dungeon 非表示 -> 現在のスタック数=\(navigationPath.count)")
                }
            )
        }
    }

    private func processPendingNavigationTargetIfNeeded() {
        guard let target = pendingNavigationTarget else { return }
        let beforeStack = navigationPath
            .map { $0.rawValue }
            .joined(separator: ",")
        debugLog(
            "TitleScreenView: pendingNavigationTarget 検出 -> target=\(target.rawValue) beforeStack=[\(beforeStack)]"
        )

        if navigationPath != [target] {
            navigationPath = [target]
            let afterStack = navigationPath
                .map { $0.rawValue }
                .joined(separator: ",")
            debugLog(
                "TitleScreenView: pendingNavigationTarget 適用 -> afterStack=[\(afterStack)]"
            )
        } else {
            debugLog("TitleScreenView: pendingNavigationTarget は既に反映済み -> スタック変更なし")
        }

        DispatchQueue.main.async {
            pendingNavigationTarget = nil
        }
    }

    @ViewBuilder
    private var howToPlayFullScreenContent: some View {
        NavigationStack {
            HowToPlayView(showsCloseButton: true)
        }
    }

    private func handleTileTapLogging(for target: TitleNavigationTarget) {
        switch target {
        case .dungeon:
            logDungeonTileTap()
        }
    }

    private func logDungeonTileTap() {
        let dungeonCount = dungeonLibrary.dungeons.count
        let floorCount = dungeonLibrary.allFloors.count
        debugLog("TitleScreenView: 塔ダンジョンカードタップ -> 塔数=\(dungeonCount) フロア数=\(floorCount)")
        logNavigationDepth(prefix: "TitleScreenView: NavigationStack 遷移直前状態")
    }

    private func logNavigationDepth(prefix: String) {
        let currentDepth = navigationPath.count
        debugLog("\(prefix) -> 現在のスタック数=\(currentDepth)")
    }

    private func featureIconTile(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(theme.accentPrimary)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.backgroundPrimary.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(theme.accentPrimary.opacity(0.7), lineWidth: 1)
            )
    }

    private func popNavigationStack() {
        guard navigationPath.count > 0 else { return }
        let currentDepth = navigationPath.count
        let callStackSnippet = Thread.callStackSymbols.prefix(4).joined(separator: " | ")
        debugLog("TitleScreenView: NavigationStack pop実行 -> 現在のスタック数=\(currentDepth) 呼び出し元候補=\(callStackSnippet)")
        navigationPath.removeLast()
        debugLog("TitleScreenView: NavigationStack pop後 -> 変更後のスタック数=\(navigationPath.count)")
    }

    private func resetNavigationStack() {
        guard navigationPath.count > 0 else { return }
        let currentDepth = navigationPath.count
        let callStackSnippet = Thread.callStackSymbols.prefix(4).joined(separator: " | ")
        debugLog("TitleScreenView: NavigationStack reset実行 -> 現在のスタック数=\(currentDepth) 呼び出し元候補=\(callStackSnippet)")
        navigationPath.removeAll()
        debugLog("TitleScreenView: NavigationStack reset後 -> 変更後のスタック数=\(navigationPath.count)")
    }

    private func triggerImmediateStart(for mode: GameMode, context: StartTriggerContext) {
        let stackDescription = navigationPath
            .map { $0.rawValue }
            .joined(separator: ",")
        debugLog(
            "TitleScreenView: triggerImmediateStart 実行 -> context=\(context.rawValue) (\(context.logDescription)) mode=\(mode.identifier.rawValue) navigationDepth=\(navigationPath.count) stack=[\(stackDescription)]"
        )
        onStart(mode, context.preparationContext)
    }
}

private extension TitleScreenView {
    var dungeonTileHeadline: String {
        let primaryDungeon = dungeonLibrary.dungeons.first
        let floorCount = primaryDungeon?.floors.count ?? dungeonLibrary.allFloors.count
        return "\(primaryDungeon?.title ?? "塔") \(floorCount)フロア・出口到達"
    }

    var dungeonTileDetail: String {
        "敵の警戒範囲や床ギミックを読みながら、HPを引き継いで登ります"
    }

    var contentMaxWidth: CGFloat? {
        horizontalSizeClass == .regular ? 760 : nil
    }

    var horizontalPadding: CGFloat {
        horizontalSizeClass == .regular ? 56 : 32
    }

    var featureTileColumns: [GridItem] {
        if horizontalSizeClass == .regular {
            return [GridItem(.adaptive(minimum: 320), spacing: 14, alignment: .top)]
        }
        return [GridItem(.flexible(), spacing: 14, alignment: .top)]
    }
}
