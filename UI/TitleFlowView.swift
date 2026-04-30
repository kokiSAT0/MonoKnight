import SwiftUI
import Game
import SharedSupport

/// タイトル画面での開始導線がどこから来たかを表す文脈
enum GamePreparationContext: Equatable {
    case campaignStageSelection
    case campaignContinuation
    case highScoreSelection
    case dailyChallenge
    case other

    var logIdentifier: String {
        switch self {
        case .campaignStageSelection:
            return "campaign_stage_selection"
        case .campaignContinuation:
            return "campaign_continuation"
        case .highScoreSelection:
            return "high_score_selection"
        case .dailyChallenge:
            return "daily_challenge"
        case .other:
            return "other"
        }
    }

    var isCampaignDerived: Bool {
        switch self {
        case .campaignStageSelection, .campaignContinuation:
            return true
        case .highScoreSelection, .dailyChallenge, .other:
            return false
        }
    }
}

/// タイトル画面での NavigationStack 先を外部から指示するためのターゲット
enum TitleNavigationTarget: String, Hashable, Codable {
    case campaign
    case highScore
    case dailyChallenge
}

// MARK: - タイトル画面（リニューアル）
struct TitleScreenView: View {
    @ObservedObject var campaignProgressStore: CampaignProgressStore
    @ObservedObject var dailyChallengeAttemptStore: AnyDailyChallengeAttemptStore
    @Binding private var pendingNavigationTarget: TitleNavigationTarget?
    let dailyChallengeDefinitionService: DailyChallengeDefinitionProviding
    let adsService: AdsServiceProtocol
    let gameCenterService: GameCenterServiceProtocol
    let onStart: (GameMode, GamePreparationContext) -> Void
    let onOpenSettings: () -> Void

    private var theme = AppTheme()
    private let campaignLibrary = CampaignLibrary.shared
    @State private var isPresentingHowToPlay: Bool = false
    @State private var navigationPath: [TitleNavigationTarget] = []
    @State private var highlightedCampaignStageID: CampaignStageID?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var gameSettingsStore: GameSettingsStore
    private let instanceIdentifier = UUID()

    /// ゲーム開始要求がどこから届いたかを判定するための文脈列挙
    private enum StartTriggerContext: String {
        case campaignStageSelection = "campaign_stage_selection"
        case highScoreSelection = "high_score_selection"
        case dailyChallenge = "daily_challenge"

        var logDescription: String {
            switch self {
            case .campaignStageSelection:
                return "キャンペーン一覧から開始"
            case .highScoreSelection:
                return "ハイスコア選択から開始"
            case .dailyChallenge:
                return "デイリーチャレンジ詳細から開始"
            }
        }

        var preparationContext: GamePreparationContext {
            switch self {
            case .campaignStageSelection:
                return .campaignStageSelection
            case .highScoreSelection:
                return .highScoreSelection
            case .dailyChallenge:
                return .dailyChallenge
            }
        }
    }

    init(campaignProgressStore: CampaignProgressStore,
         dailyChallengeAttemptStore: AnyDailyChallengeAttemptStore,
         dailyChallengeDefinitionService: DailyChallengeDefinitionProviding,
         adsService: AdsServiceProtocol,
         gameCenterService: GameCenterServiceProtocol,
         pendingNavigationTarget: Binding<TitleNavigationTarget?>,
         onStart: @escaping (GameMode, GamePreparationContext) -> Void,
         onOpenSettings: @escaping () -> Void) {
        self._campaignProgressStore = ObservedObject(wrappedValue: campaignProgressStore)
        self._dailyChallengeAttemptStore = ObservedObject(wrappedValue: dailyChallengeAttemptStore)
        self._pendingNavigationTarget = pendingNavigationTarget
        self.dailyChallengeDefinitionService = dailyChallengeDefinitionService
        self.adsService = adsService
        self.gameCenterService = gameCenterService
        self.onStart = onStart
        self.onOpenSettings = onOpenSettings
        _isPresentingHowToPlay = State(initialValue: false)
        dailyChallengeAttemptStore.refreshForCurrentDate()
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
        .onAppear {
            dailyChallengeAttemptStore.refreshForCurrentDate()
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
        .accessibilityLabel("タイトル画面。キャンペーン、ハイスコア、デイリーチャレンジの各カードから詳細へ進めます。")
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            Text("MonoKnight")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundColor(theme.textPrimary)
            Text("カードで騎士を導き、目的地を取り切ろう")
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
            Text("プレイメニュー")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(theme.textPrimary)

            LazyVGrid(columns: featureTileColumns, alignment: .leading, spacing: 14) {
                featureTile(
                    target: .campaign,
                    title: "キャンペーン",
                    systemImage: "flag.checkered",
                    headline: campaignTileHeadline,
                    detail: campaignTileDetail,
                    accessibilityID: "title_tile_campaign",
                    accessibilityHint: "ステージ一覧を表示します"
                )

                featureTile(
                    target: .highScore,
                    title: "ハイスコア",
                    systemImage: "trophy.fill",
                    headline: highScoreTileHeadline,
                    detail: highScoreTileDetail,
                    accessibilityID: "title_tile_high_score",
                    accessibilityHint: "スコアアタックの詳細を確認できます"
                )

                featureTile(
                    target: .dailyChallenge,
                    title: "デイリーチャレンジ",
                    systemImage: "calendar",
                    headline: dailyChallengeTileHeadline,
                    detail: dailyChallengeTileDetail,
                    accessibilityID: "title_tile_daily_challenge",
                    accessibilityHint: "日替わりチャレンジの情報を表示します"
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
        case .campaign:
            let stackDescription = navigationPath
                .map { $0.rawValue }
                .joined(separator: ",")
            let _ = debugLog(
                "TitleScreenView: NavigationDestination.campaign 構築開始 -> instance=\(instanceIdentifier.uuidString) targetType=\(String(describing: type(of: target))) stackCount=\(navigationPath.count) stack=[\(stackDescription)]"
            )
            return AnyView(
                CampaignStageSelectionView(
                    campaignLibrary: campaignLibrary,
                    progressStore: campaignProgressStore,
                    selectedStageID: highlightedCampaignStageID,
                    onClose: { popNavigationStack() },
                    onSelectStage: { stage in
                        handleCampaignStageSelection(stage)
                        let mode = stage.makeGameMode()
                        let context: StartTriggerContext = .campaignStageSelection
                        debugLog(
                            "TitleScreenView: キャンペーンステージ選択後 -> NavigationStack をリセットして即時開始をメインキューへ登録 context=\(context.rawValue)"
                        )
                        resetNavigationStack()
                        DispatchQueue.main.async {
                            triggerImmediateStart(for: mode, context: context)
                        }
                    },
                    showsCloseButton: false
                )
                .onAppear {
                    debugLog("TitleScreenView: NavigationDestination.campaign 表示 -> 現在のスタック数=\(navigationPath.count)")
                }
                .onDisappear {
                    debugLog("TitleScreenView: NavigationDestination.campaign 非表示 -> 現在のスタック数=\(navigationPath.count)")
                }
            )
        case .highScore:
            return AnyView(
                HighScoreChallengeSelectionView(
                    onSelect: { mode in
                        startHighScoreMode(mode)
                    },
                    onClose: { popNavigationStack() },
                    bestScoreDescription: bestPointsDescription
                )
                .onAppear {
                    debugLog("TitleScreenView: NavigationDestination.highScore 表示 -> 現在のスタック数=\(navigationPath.count)")
                }
                .onDisappear {
                    debugLog("TitleScreenView: NavigationDestination.highScore 非表示 -> 現在のスタック数=\(navigationPath.count)")
                }
            )
        case .dailyChallenge:
            let viewModel = DailyChallengeViewModel(
                attemptStore: dailyChallengeAttemptStore,
                definitionService: dailyChallengeDefinitionService,
                adsService: adsService,
                gameCenterService: gameCenterService
            )
            return AnyView(
                DailyChallengeView(
                    viewModel: viewModel,
                    onDismiss: {
                        popNavigationStack()
                    },
                    onStart: { mode in
                        let context: StartTriggerContext = .dailyChallenge
                        debugLog("TitleScreenView: デイリーチャレンジ開始要求 -> mode=\(mode.identifier.rawValue) context=\(context.rawValue)")
                        resetNavigationStack()
                        DispatchQueue.main.async {
                            triggerImmediateStart(for: mode, context: context)
                        }
                    }
                )
                .onAppear {
                    dailyChallengeAttemptStore.refreshForCurrentDate()
                    debugLog("TitleScreenView: NavigationDestination.dailyChallenge 表示 -> 現在のスタック数=\(navigationPath.count)")
                }
                .onDisappear {
                    debugLog("TitleScreenView: NavigationDestination.dailyChallenge 非表示 -> 現在のスタック数=\(navigationPath.count)")
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
        case .campaign:
            logCampaignTileTap()
        case .highScore:
            debugLog("TitleScreenView: ハイスコアカードをタップ -> 詳細ページへ遷移要求")
            logNavigationDepth(prefix: "TitleScreenView: NavigationStack 遷移直前状態")
        case .dailyChallenge:
            debugLog("TitleScreenView: デイリーチャレンジカードをタップ -> 詳細ページへ遷移要求")
            logNavigationDepth(prefix: "TitleScreenView: NavigationStack 遷移直前状態")
        }
    }

    private func logCampaignTileTap() {
        let stageIDDescription = highlightedCampaignStageID?.displayCode ?? "未選択"
        let chaptersCount = campaignLibrary.chapters.count
        let totalStageCount = campaignLibrary.allStages.count
        let unlockedCount = unlockedCampaignStageCount
        debugLog("TitleScreenView: キャンペーンカードタップ -> 章数=\(chaptersCount) 総ステージ数=\(totalStageCount) 最新選択=\(stageIDDescription) 解放済=\(unlockedCount)")
        logNavigationDepth(prefix: "TitleScreenView: NavigationStack 遷移直前状態")
    }

    private func logNavigationDepth(prefix: String) {
        let currentDepth = navigationPath.count
        debugLog("\(prefix) -> 現在のスタック数=\(currentDepth)")
    }

    private func handleCampaignStageSelection(_ stage: CampaignStage) {
        debugLog("TitleScreenView: キャンペーンステージを選択 -> \(stage.id.displayCode)")
        highlightedCampaignStageID = stage.id
        debugLog("TitleScreenView: キャンペーンステージ選択完了 -> 即時開始スケジュールを待機")
    }

    private func startHighScoreMode(_ mode: GameMode) {
        let context: StartTriggerContext = .highScoreSelection
        debugLog(
            "TitleScreenView: ハイスコアチャレンジ開始要求 -> \(mode.identifier.rawValue) context=\(context.rawValue)"
        )
        resetNavigationStack()
        DispatchQueue.main.async {
            triggerImmediateStart(for: mode, context: context)
        }
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
    var highlightedCampaignStage: CampaignStage? {
        highlightedCampaignStageID.flatMap { campaignLibrary.stage(with: $0) }
    }

    var totalCampaignStageCount: Int {
        campaignLibrary.allStages.count
    }

    var unlockedCampaignStageCount: Int {
        campaignLibrary.allStages.filter { campaignProgressStore.isStageUnlocked($0) }.count
    }

    var campaignTileHeadline: String {
        let unlocked = unlockedCampaignStageCount
        let total = totalCampaignStageCount
        let stars = campaignProgressStore.totalStars
        return "解放済み \(unlocked)/\(total) ステージ・スター \(stars)"
    }

    var campaignTileDetail: String {
        if let stage = highlightedCampaignStage {
            return "最新選択: \(stage.displayCode) \(stage.title)"
        } else {
            return "ステージを選んでストーリーを進めましょう"
        }
    }

    var highScoreTileHeadline: String {
        if gameSettingsStore.bestPoints == .max {
            return "ベストスコア: 記録なし"
        } else {
            return "ベストスコア: \(gameSettingsStore.bestPoints) pt"
        }
    }

    var highScoreTileDetail: String {
        "スタンダードで手数・タイム・フォーカスを詰めましょう"
    }

    var dailyChallengeTileHeadline: String {
        let bundle = dailyChallengeBundle
        let fixedRemaining = dailyChallengeAttemptStore.remainingAttempts(for: .fixed)
        let randomRemaining = dailyChallengeAttemptStore.remainingAttempts(for: .random)
        let modeNames = bundle.orderedInfos.map { $0.mode.displayName }.joined(separator: " / ")
        return "\(modeNames) ・ 固定 残り \(fixedRemaining) 回 / ランダム 残り \(randomRemaining) 回"
    }

    var dailyChallengeTileDetail: String {
        let bundle = dailyChallengeBundle
        let fixedGranted = dailyChallengeAttemptStore.rewardedAttemptsGranted(for: .fixed)
        let randomGranted = dailyChallengeAttemptStore.rewardedAttemptsGranted(for: .random)
        let maximumRewarded = dailyChallengeAttemptStore.maximumRewardedAttempts
        let fixedSummary = bundle.fixed.regulationPrimaryText
        let randomSummary = bundle.random.regulationPrimaryText
        return "固定: \(fixedSummary) / ランダム: \(randomSummary) ・ 広告追加 固定 \(fixedGranted)/\(maximumRewarded) ・ ランダム \(randomGranted)/\(maximumRewarded)"
    }

    var dailyChallengeBundle: DailyChallengeDefinitionService.ChallengeBundle {
        dailyChallengeDefinitionService.challengeBundle(for: Date())
    }

    var bestPointsDescription: String {
        if gameSettingsStore.bestPoints == .max {
            return "記録はまだありません"
        } else {
            return "現在のベスト: \(gameSettingsStore.bestPoints) pt（少ないほど上位）"
        }
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
