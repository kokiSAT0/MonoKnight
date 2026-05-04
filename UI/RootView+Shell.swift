import Game
import SharedSupport
import SwiftUI

extension RootView {
    struct RootShellLayoutObservationState {
        var loggedSnapshotCache: RootLayoutSnapshot?
        var hasObservedPositiveTopBarHeight = false
    }

    struct RootShellToastState {
        var message: String?
        var dismissWorkItem: DispatchWorkItem?

        mutating func cancelTimer() {
            dismissWorkItem?.cancel()
            dismissWorkItem = nil
        }
    }

    /// RootView 本体の `body` から切り離したメソッドで、サブビュー生成ロジックを共通化する
    /// - Parameter layoutContext: GeometryReader から構築したレイアウト情報
    /// - Returns: 依存サービスや状態をバインディングした `RootContentView`
    func makeRootContentView(with layoutContext: RootLayoutContext) -> RootContentView {
        RootContentView(
            theme: theme,
            layoutContext: layoutContext,
            gameInterfaces: gameInterfaces,
            gameCenterService: gameCenterService,
            adsService: adsService,
            campaignLibrary: campaignLibrary,
            campaignProgressStore: campaignProgressStore,
            dungeonGrowthStore: dungeonGrowthStore,
            dailyChallengeDefinitionService: dailyChallengeDefinitionService,
            dailyChallengeAttemptStore: dailyChallengeAttemptStore,
            isAuthenticated: stateStore.binding(for: \.isAuthenticated),
            isShowingTitleScreen: stateStore.binding(for: \.isShowingTitleScreen),
            isPreparingGame: stateStore.binding(for: \.isPreparingGame),
            isGameReadyForManualStart: stateStore.binding(for: \.isGameReadyForManualStart),
            activeMode: stateStore.binding(for: \.activeMode),
            gameSessionID: stateStore.binding(for: \.gameSessionID),
            topBarHeight: stateStore.binding(for: \.topBarHeight),
            lastLoggedLayoutSnapshot: stateStore.binding(for: \.lastLoggedLayoutSnapshot),
            lastPreparationContext: stateStore.binding(for: \.lastPreparationContext),
            pendingTitleNavigationTarget: stateStore.binding(for: \.pendingTitleNavigationTarget),
            onRequestGameCenterSignInPrompt: handleGameCenterSignInRequest,
            onStartGame: { mode, context in
                startGamePreparation(for: mode, context: context)
            },
            onReturnToTitle: {
                handleReturnToTitleRequest()
            },
            onReturnToCampaignStageSelection: {
                handleReturnToCampaignStageSelectionRequest()
            },
            onConfirmGameStart: {
                finishGamePreparationAndStart()
            },
            onOpenSettings: {
                titleFlowCoordinator.presentSettings(stateStore: stateStore)
            }
        )
    }

    func handleTopBarHeightPreferenceChange(_ newHeight: CGFloat) {
        guard stateStore.topBarHeight != newHeight else { return }
        DispatchQueue.main.async {
            stateStore.topBarHeight = newHeight
        }
    }

    func makeSettingsView() -> some View {
        SettingsView(
            adsService: adsService,
            gameCenterService: gameCenterService,
            isGameCenterAuthenticated: stateStore.binding(for: \.isAuthenticated)
        )
        .environmentObject(campaignProgressStore)
        .environmentObject(dailyChallengeAttemptStore)
        .environmentObject(gameSettingsStore)
    }

    func makeGameCenterSignInAlert(for prompt: GameCenterSignInPrompt) -> Alert {
        Alert(
            title: Text("Game Center"),
            message: Text(prompt.reason.message),
            primaryButton: .default(Text("再試行")) {
                stateStore.gameCenterSignInPrompt = nil
                gameCenterPromptPresenter.requestAuthentication(
                    stateStore: stateStore,
                    gameCenterService: gameCenterService
                ) { success in
                    if !success {
                        gameCenterPromptPresenter.presentPrompt(
                            for: .retryFailed,
                            stateStore: stateStore
                        )
                    }
                }
            },
            secondaryButton: .cancel(Text("閉じる"))
        )
    }

    /// `body` 末尾に連なっていた状態監視やシート表示を 1 つの修飾子へ集約し、型推論を単純化する
    /// - Parameter content: 観測対象となるコンテンツ
    /// - Returns: 各種ロギング・シート表示を適用したビュー
    func attachRootStateObservers<Content: View>(to content: Content) -> some View {
        content
            .onPreferenceChange(TopBarHeightPreferenceKey.self) { newHeight in
                handleTopBarHeightPreferenceChange(newHeight)
            }
            .onChange(of: horizontalSizeClass) { _, newValue in
                stateStore.logHorizontalSizeClassChange(newValue)
            }
            .fullScreenCover(isPresented: stateStore.binding(for: \.isPresentingTitleSettings)) {
                makeSettingsView()
            }
            .alert(item: stateStore.binding(for: \.gameCenterSignInPrompt)) { prompt in
                makeGameCenterSignInAlert(for: prompt)
            }
    }

    /// GeometryReader から得たレイアウト情報を引き受け、RootView 全体を構築する補助ビュー
    struct RootContentView: View {
        let theme: AppTheme
        let layoutContext: RootLayoutContext
        let gameInterfaces: GameModuleInterfaces
        let gameCenterService: GameCenterServiceProtocol
        let adsService: AdsServiceProtocol
        let campaignLibrary: CampaignLibrary
        @ObservedObject var campaignProgressStore: CampaignProgressStore
        @ObservedObject var dungeonGrowthStore: DungeonGrowthStore
        let dailyChallengeDefinitionService: DailyChallengeDefinitionProviding
        @ObservedObject var dailyChallengeAttemptStore: AnyDailyChallengeAttemptStore
        @Binding var isAuthenticated: Bool
        @Binding var isShowingTitleScreen: Bool
        @Binding var isPreparingGame: Bool
        @Binding var isGameReadyForManualStart: Bool
        @Binding var activeMode: GameMode
        @Binding var gameSessionID: UUID
        @Binding var topBarHeight: CGFloat
        @Binding var lastLoggedLayoutSnapshot: RootLayoutSnapshot?
        @Binding var lastPreparationContext: GamePreparationContext?
        @Binding var pendingTitleNavigationTarget: TitleNavigationTarget?
        let onRequestGameCenterSignInPrompt: (GameCenterSignInPromptReason) -> Void
        let onStartGame: (GameMode, GamePreparationContext) -> Void
        let onReturnToTitle: () -> Void
        let onReturnToCampaignStageSelection: () -> Void
        let onConfirmGameStart: () -> Void
        let onOpenSettings: () -> Void
        @State var layoutObservationState = RootShellLayoutObservationState()
        @State var toastState = RootShellToastState()
        private let gameCenterToastDisplayDuration: TimeInterval = 4.0

        var body: some View {
            ZStack {
                backgroundLayer
                foregroundLayer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                topStatusInset
            }
            .overlay(alignment: .top) {
                gameCenterUnauthenticatedToast
            }
            .background(layoutDiagnosticOverlay)
            .onAppear {
                debugLog(
                    "RootView.onAppear: size=\(layoutContext.geometrySize), safeArea(top=\(layoutContext.safeAreaTop), bottom=\(layoutContext.safeAreaBottom)), horizontalSizeClass=\(String(describing: layoutContext.horizontalSizeClass)), authenticated=\(isAuthenticated)"
                )
                if !isAuthenticated && isShowingTitleScreen {
                    showGameCenterUnauthenticatedToast()
                }
            }
            .onChange(of: isAuthenticated) { _, newValue in
                if newValue {
                    hideGameCenterUnauthenticatedToast()
                } else if isShowingTitleScreen {
                    showGameCenterUnauthenticatedToast()
                }
            }
            .onChange(of: isShowingTitleScreen) { _, isTitleVisible in
                if isTitleVisible {
                    if !isAuthenticated {
                        showGameCenterUnauthenticatedToast()
                    }
                } else {
                    hideGameCenterUnauthenticatedToast()
                }
            }
            .onDisappear {
                cancelGameCenterToastTimer()
            }
        }

        private var backgroundLayer: some View {
            theme.backgroundPrimary
                .ignoresSafeArea()
        }

        private var foregroundLayer: some View {
            ZStack {
                gameLayer
                loadingOverlay
                titleOverlay
            }
            .animation(.easeInOut(duration: 0.25), value: isShowingTitleScreen)
            .animation(.easeInOut(duration: 0.25), value: isPreparingGame)
        }

        @ViewBuilder
        private var gameLayer: some View {
            if isShowingTitleScreen {
                EmptyView()
            } else {
                GameView(
                    mode: activeMode,
                    gameInterfaces: gameInterfaces,
                    gameCenterService: gameCenterService,
                    adsService: adsService,
                    campaignProgressStore: campaignProgressStore,
                    dungeonGrowthStore: dungeonGrowthStore,
                    isPreparationOverlayVisible: $isPreparingGame,
                    isGameCenterAuthenticated: isAuthenticated,
                    onRequestGameCenterSignIn: onRequestGameCenterSignInPrompt,
                    onRequestReturnToTitle: {
                        onReturnToTitle()
                    },
                    onRequestStartCampaignStage: { stage in
                        onStartGame(stage.makeGameMode(), .campaignContinuation)
                    },
                    onRequestStartDungeonFloor: { mode in
                        onStartGame(mode, .campaignContinuation)
                    }
                )
                .id(gameSessionID)
                .environment(\.topOverlayHeight, topBarHeight)
                .environment(\.baseTopSafeAreaInset, layoutContext.safeAreaTop)
                .opacity(isPreparingGame ? 0 : 1)
                .allowsHitTesting(!isPreparingGame)
            }
        }

        @ViewBuilder
        private var loadingOverlay: some View {
            if isPreparingGame {
                let stage = campaignStage(for: activeMode)
                let progress = stage.flatMap { campaignProgressStore.progress(for: $0.id) }
                let shouldReturnToCampaignSelection =
                    lastPreparationContext?.isCampaignDerived ?? (stage != nil || activeMode.usesDungeonExit)

                GamePreparationOverlayView(
                    mode: activeMode,
                    campaignStage: stage,
                    progress: progress,
                    isReady: isGameReadyForManualStart,
                    isCampaignContext: shouldReturnToCampaignSelection,
                    onReturnToCampaignSelection: {
                        if shouldReturnToCampaignSelection {
                            onReturnToCampaignStageSelection()
                        } else {
                            onReturnToTitle()
                        }
                    },
                    onStart: {
                        onConfirmGameStart()
                    }
                )
                .transition(.opacity)
            } else {
                EmptyView()
            }
        }

        @ViewBuilder
        private var titleOverlay: some View {
            if isShowingTitleScreen {
                TitleScreenView(
                    campaignProgressStore: campaignProgressStore,
                    dungeonGrowthStore: dungeonGrowthStore,
                    dailyChallengeAttemptStore: dailyChallengeAttemptStore,
                    dailyChallengeDefinitionService: dailyChallengeDefinitionService,
                    adsService: adsService,
                    gameCenterService: gameCenterService,
                    pendingNavigationTarget: $pendingTitleNavigationTarget,
                    onStart: { mode, context in
                        onStartGame(mode, context)
                    },
                    onOpenSettings: {
                        onOpenSettings()
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                EmptyView()
            }
        }

        private var topStatusInset: some View {
            TopStatusInsetView(
                context: layoutContext,
                theme: theme
            )
        }

        @ViewBuilder
        private var gameCenterUnauthenticatedToast: some View {
            if let message = toastState.message {
                Text(message)
                    .font(.footnote)
                    .multilineTextAlignment(.leading)
                    .foregroundColor(theme.textPrimary)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(theme.backgroundElevated.opacity(0.96))
                            .shadow(color: Color.black.opacity(0.2), radius: 14, x: 0, y: 8)
                    )
                    .frame(maxWidth: layoutContext.topBarMaxWidth ?? 440, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, layoutContext.safeAreaTop + 12)
                    .allowsHitTesting(false)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityIdentifier("gc_toast")
            }
        }

        private func showGameCenterUnauthenticatedToast() {
            let message = "Game Center 未サインイン。設定画面からサインインするとランキングを利用できます。"
            cancelGameCenterToastTimer()

            if toastState.message == nil {
                withAnimation(.easeInOut(duration: 0.25)) {
                    toastState.message = message
                }
            } else {
                toastState.message = message
            }

            scheduleGameCenterToastAutoDismiss()
        }

        private func hideGameCenterUnauthenticatedToast() {
            guard toastState.message != nil else { return }
            cancelGameCenterToastTimer()
            withAnimation(.easeInOut(duration: 0.2)) {
                toastState.message = nil
            }
        }

        private func cancelGameCenterToastTimer() {
            toastState.cancelTimer()
        }

        private func scheduleGameCenterToastAutoDismiss() {
            var workItem: DispatchWorkItem?
            workItem = DispatchWorkItem {
                guard let workItem, !workItem.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    toastState.message = nil
                }
                toastState.dismissWorkItem = nil
            }

            guard let workItem else { return }
            toastState.dismissWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + gameCenterToastDisplayDuration, execute: workItem)
        }

        private func campaignStage(for mode: GameMode) -> CampaignStage? {
            resolveCampaignStage(for: mode, campaignLibrary: campaignLibrary)
        }
    }
}

extension RootView.RootContentView {
    func resolveCampaignStage(
        for mode: GameMode,
        campaignLibrary: CampaignLibrary
    ) -> CampaignStage? {
        guard let metadata = mode.campaignMetadataSnapshot else {
            debugLog("RootView: campaignStage(for:) -> キャンペーンメタデータ未設定 mode=\(mode.identifier.rawValue)")
            return nil
        }
        let stageID = metadata.stageID
        let stage = campaignLibrary.stage(with: stageID)
        if let stage {
            debugLog("RootView: campaignStage(for:) -> ステージ取得成功 stageID=\(stageID.displayCode) 章内タイトル=\(stage.title)")
        } else {
            debugLog("RootView: campaignStage(for:) -> ステージ取得失敗 stageID=\(stageID.displayCode) 章定義を確認してください。")
        }
        return stage
    }
}
