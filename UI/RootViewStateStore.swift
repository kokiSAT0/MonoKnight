import Game
import SharedSupport
import SwiftUI

// MARK: - 画面状態ストア
@MainActor
final class RootViewStateStore: ObservableObject {
    private struct PlayFlowState {
        var isShowingTitleScreen: Bool
        var isPreparingGame: Bool
        var isGameReadyForManualStart: Bool
        var activeMode: GameMode
        var gameSessionID: UUID
        var lastPreparationContext: GamePreparationContext?
    }

    private struct PresentationState {
        var topBarHeight: CGFloat
        var lastLoggedLayoutSnapshot: RootView.RootLayoutSnapshot?
        var isPresentingTitleSettings: Bool
        var pendingTitleNavigationTarget: TitleNavigationTarget?
    }

    private struct AuthPromptState {
        var isAuthenticated: Bool
        var gameCenterSignInPrompt: GameCenterSignInPrompt?
        var hasAttemptedInitialAuthentication: Bool
    }

    @Published private var playFlowState: PlayFlowState
    @Published private var presentationState: PresentationState
    @Published private var authPromptState: AuthPromptState

    var isAuthenticated: Bool {
        get { authPromptState.isAuthenticated }
        set {
            guard authPromptState.isAuthenticated != newValue else { return }
            authPromptState.isAuthenticated = newValue
            debugLog("RootView.isAuthenticated 更新: \(newValue)")
        }
    }

    var isShowingTitleScreen: Bool {
        get { playFlowState.isShowingTitleScreen }
        set {
            guard playFlowState.isShowingTitleScreen != newValue else { return }
            playFlowState.isShowingTitleScreen = newValue
            debugLog("RootView.isShowingTitleScreen 更新: \(newValue)")
        }
    }

    var isPreparingGame: Bool {
        get { playFlowState.isPreparingGame }
        set {
            guard playFlowState.isPreparingGame != newValue else { return }
            playFlowState.isPreparingGame = newValue
            debugLog("RootView.isPreparingGame 更新: \(newValue)")
        }
    }

    var isGameReadyForManualStart: Bool {
        get { playFlowState.isGameReadyForManualStart }
        set {
            guard playFlowState.isGameReadyForManualStart != newValue else { return }
            playFlowState.isGameReadyForManualStart = newValue
            debugLog("RootView.isGameReadyForManualStart 更新: \(newValue)")
        }
    }

    var activeMode: GameMode {
        get { playFlowState.activeMode }
        set {
            guard playFlowState.activeMode != newValue else { return }
            playFlowState.activeMode = newValue
            debugLog("RootView.activeMode 更新: \(newValue.identifier.rawValue)")
        }
    }

    var gameSessionID: UUID {
        get { playFlowState.gameSessionID }
        set {
            guard playFlowState.gameSessionID != newValue else { return }
            playFlowState.gameSessionID = newValue
            debugLog("RootView.gameSessionID 更新: \(newValue)")
        }
    }

    var topBarHeight: CGFloat {
        get { presentationState.topBarHeight }
        set {
            guard presentationState.topBarHeight != newValue else { return }
            let oldValue = presentationState.topBarHeight
            presentationState.topBarHeight = newValue
            debugLog("RootView.topBarHeight 更新: 旧値=\(oldValue), 新値=\(newValue)")
        }
    }

    var lastLoggedLayoutSnapshot: RootView.RootLayoutSnapshot? {
        get { presentationState.lastLoggedLayoutSnapshot }
        set { presentationState.lastLoggedLayoutSnapshot = newValue }
    }

    var isPresentingTitleSettings: Bool {
        get { presentationState.isPresentingTitleSettings }
        set {
            guard presentationState.isPresentingTitleSettings != newValue else { return }
            presentationState.isPresentingTitleSettings = newValue
            debugLog("RootView.isPresentingTitleSettings 更新: \(newValue)")
        }
    }

    var gameCenterSignInPrompt: GameCenterSignInPrompt? {
        get { authPromptState.gameCenterSignInPrompt }
        set {
            guard authPromptState.gameCenterSignInPrompt?.id != newValue?.id else { return }
            authPromptState.gameCenterSignInPrompt = newValue
            debugLog("RootView.gameCenterSignInPrompt 更新: reason=\(String(describing: newValue?.reason))")
        }
    }

    var lastPreparationContext: GamePreparationContext? {
        get { playFlowState.lastPreparationContext }
        set {
            guard playFlowState.lastPreparationContext != newValue else { return }
            playFlowState.lastPreparationContext = newValue
            debugLog("RootView.lastPreparationContext 更新: \(String(describing: newValue?.logIdentifier))")
        }
    }

    var pendingTitleNavigationTarget: TitleNavigationTarget? {
        get { presentationState.pendingTitleNavigationTarget }
        set {
            guard presentationState.pendingTitleNavigationTarget != newValue else { return }
            presentationState.pendingTitleNavigationTarget = newValue
            debugLog("RootView.pendingTitleNavigationTarget 更新: target=\(String(describing: newValue?.rawValue))")
        }
    }

    private(set) var hasAttemptedInitialAuthentication: Bool {
        get { authPromptState.hasAttemptedInitialAuthentication }
        set { authPromptState.hasAttemptedInitialAuthentication = newValue }
    }

    init(initialIsAuthenticated: Bool) {
        self.playFlowState = PlayFlowState(
            isShowingTitleScreen: true,
            isPreparingGame: false,
            isGameReadyForManualStart: false,
            activeMode: .dungeonPlaceholder,
            gameSessionID: UUID(),
            lastPreparationContext: nil
        )
        self.presentationState = PresentationState(
            topBarHeight: 0,
            lastLoggedLayoutSnapshot: nil,
            isPresentingTitleSettings: false,
            pendingTitleNavigationTarget: nil
        )
        self.authPromptState = AuthPromptState(
            isAuthenticated: initialIsAuthenticated,
            gameCenterSignInPrompt: nil,
            hasAttemptedInitialAuthentication: false
        )
    }

    func beginGamePreparation(for mode: GameMode, context: GamePreparationContext, sessionID: UUID) {
        var updatedState = playFlowState
        updatedState.activeMode = mode
        updatedState.lastPreparationContext = context
        updatedState.gameSessionID = sessionID
        updatedState.isGameReadyForManualStart = false
        updatedState.isShowingTitleScreen = false
        updatedState.isPreparingGame = true
        playFlowState = updatedState
        debugLog(
            "RootView: ゲーム準備状態を一括更新 activeMode=\(mode.identifier.rawValue) sessionID=\(sessionID) context=\(context.logIdentifier)"
        )
    }

    func beginGameImmediately(for mode: GameMode, context: GamePreparationContext, sessionID: UUID) {
        var updatedState = playFlowState
        updatedState.activeMode = mode
        updatedState.lastPreparationContext = context
        updatedState.gameSessionID = sessionID
        updatedState.isGameReadyForManualStart = false
        updatedState.isShowingTitleScreen = false
        updatedState.isPreparingGame = false
        playFlowState = updatedState
        debugLog(
            "RootView: ゲームを即時開始 activeMode=\(mode.identifier.rawValue) sessionID=\(sessionID) context=\(context.logIdentifier)"
        )
    }

    func binding<Value>(for keyPath: ReferenceWritableKeyPath<RootViewStateStore, Value>) -> Binding<Value> {
        Binding(
            get: { self[keyPath: keyPath] },
            set: { self[keyPath: keyPath] = $0 }
        )
    }

    func markInitialAuthenticationAttemptedIfNeeded() -> Bool {
        guard !hasAttemptedInitialAuthentication else { return false }
        hasAttemptedInitialAuthentication = true
        return true
    }

    func enqueueGameCenterSignInPrompt(reason: GameCenterSignInPromptReason) {
        gameCenterSignInPrompt = GameCenterSignInPrompt(reason: reason)
    }

    func logHorizontalSizeClassChange(_ newValue: UserInterfaceSizeClass?) {
        debugLog("RootView.horizontalSizeClass 更新: \(String(describing: newValue))")
    }
}
