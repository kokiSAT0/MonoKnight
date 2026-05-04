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
            dungeonGrowthStore: dungeonGrowthStore,
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
            onStartGame: { mode, context in
                startGamePreparation(for: mode, context: context)
            },
            onReturnToTitle: {
                handleReturnToTitleRequest()
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
        .environmentObject(gameSettingsStore)
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
    }

    /// GeometryReader から得たレイアウト情報を引き受け、RootView 全体を構築する補助ビュー
    struct RootContentView: View {
        let theme: AppTheme
        let layoutContext: RootLayoutContext
        let gameInterfaces: GameModuleInterfaces
        let gameCenterService: GameCenterServiceProtocol
        let adsService: AdsServiceProtocol
        @ObservedObject var dungeonGrowthStore: DungeonGrowthStore
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
        let onStartGame: (GameMode, GamePreparationContext) -> Void
        let onReturnToTitle: () -> Void
        let onConfirmGameStart: () -> Void
        let onOpenSettings: () -> Void
        @State var layoutObservationState = RootShellLayoutObservationState()

        var body: some View {
            ZStack {
                backgroundLayer
                foregroundLayer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                topStatusInset
            }
            .background(layoutDiagnosticOverlay)
            .onAppear {
                debugLog(
                    "RootView.onAppear: size=\(layoutContext.geometrySize), safeArea(top=\(layoutContext.safeAreaTop), bottom=\(layoutContext.safeAreaBottom)), horizontalSizeClass=\(String(describing: layoutContext.horizontalSizeClass)), authenticated=\(isAuthenticated)"
                )
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
                    dungeonGrowthStore: dungeonGrowthStore,
                    isPreparationOverlayVisible: $isPreparingGame,
                    isGameCenterAuthenticated: isAuthenticated,
                    onRequestReturnToTitle: {
                        onReturnToTitle()
                    },
                    onRequestStartDungeonFloor: { mode in
                        onStartGame(mode, .dungeonContinuation)
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
                let shouldReturnToDungeonSelection =
                    lastPreparationContext?.isDungeonDerived ?? activeMode.usesDungeonExit

                GamePreparationOverlayView(
                    mode: activeMode,
                    isReady: isGameReadyForManualStart,
                    isDungeonContext: shouldReturnToDungeonSelection,
                    onReturnToDungeonSelection: {
                        if shouldReturnToDungeonSelection {
                            pendingTitleNavigationTarget = .dungeon
                            onReturnToTitle()
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
                    dungeonGrowthStore: dungeonGrowthStore,
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
    }
}
