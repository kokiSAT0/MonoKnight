import Foundation
import Game
import SharedSupport
import SwiftUI

@MainActor
final class RootViewPreparationCoordinator: ObservableObject {
    private var pendingGameActivationWorkItem: DispatchWorkItem?

    deinit {
        pendingGameActivationWorkItem?.cancel()
    }

    func startPreparation(
        for mode: GameMode,
        context: GamePreparationContext,
        stateStore: RootViewStateStore
    ) {
        cancelPendingGameActivationWorkItem(stateStore: stateStore)

        debugLog("RootView: ゲーム準備開始リクエストを処理 選択モード=\(mode.identifier.rawValue) context=\(context.logIdentifier)")

        let scheduledSessionID = UUID()
        debugLog("RootView: 新規ゲームセッションを割り当て sessionID=\(scheduledSessionID)")

        withAnimation(.easeInOut(duration: 0.25)) {
            stateStore.beginGamePreparation(
                for: mode,
                context: context,
                sessionID: scheduledSessionID
            )
        }

        scheduleGameActivationCompletion(for: scheduledSessionID, stateStore: stateStore)
    }

    func startImmediately(
        for mode: GameMode,
        context: GamePreparationContext,
        stateStore: RootViewStateStore
    ) {
        cancelPendingGameActivationWorkItem(stateStore: stateStore)

        let sessionID = UUID()
        debugLog("RootView: 準備画面なしでゲーム開始 選択モード=\(mode.identifier.rawValue) context=\(context.logIdentifier) sessionID=\(sessionID)")

        withAnimation(.easeInOut(duration: 0.12)) {
            stateStore.beginGameImmediately(
                for: mode,
                context: context,
                sessionID: sessionID
            )
        }
    }

    func finishPreparationAndStart(stateStore: RootViewStateStore) {
        guard stateStore.isPreparingGame else { return }

        debugLog("RootView: ユーザー操作によりゲームを開始")

        withAnimation(.easeInOut(duration: 0.25)) {
            stateStore.isPreparingGame = false
        }
        stateStore.isGameReadyForManualStart = false
    }

    func cancelPendingGameActivationWorkItem(stateStore: RootViewStateStore) {
        guard let workItem = pendingGameActivationWorkItem else { return }
        debugLog("RootView: 保留中のゲーム準備ワークアイテムをキャンセル sessionID=\(stateStore.gameSessionID)")
        workItem.cancel()
        pendingGameActivationWorkItem = nil
        stateStore.isGameReadyForManualStart = false
    }

    private func scheduleGameActivationCompletion(for sessionID: UUID, stateStore: RootViewStateStore) {
        let workItem = DispatchWorkItem { [weak self, weak stateStore, sessionID] in
            guard let self else { return }

            guard let stateStore else {
                debugLog("RootView: 状態ストアが解放済みのためゲーム準備ワークアイテムを終了 sessionID=\(sessionID)")
                self.pendingGameActivationWorkItem = nil
                return
            }

            guard self.pendingGameActivationWorkItem != nil else {
                debugLog("RootView: ゲーム準備ワークアイテムが実行前に破棄されました sessionID=\(sessionID)")
                return
            }

            guard sessionID == stateStore.gameSessionID else {
                debugLog("RootView: ゲーム準備完了通知を破棄 scheduled=\(sessionID) current=\(stateStore.gameSessionID)")
                self.pendingGameActivationWorkItem = nil
                return
            }

            debugLog("RootView: ゲーム準備完了 手動開始待ちへ移行 sessionID=\(sessionID)")

            stateStore.isGameReadyForManualStart = true
            self.pendingGameActivationWorkItem = nil
        }

        pendingGameActivationWorkItem = workItem

        DispatchQueue.main.asyncAfter(
            deadline: .now() + RootView.RootLayoutMetrics.gamePreparationMinimumDelay,
            execute: workItem
        )
    }
}

@MainActor
struct RootViewTitleFlowCoordinator {
    func handleReturnToTitleRequest(
        stateStore: RootViewStateStore,
        preparationCoordinator: RootViewPreparationCoordinator
    ) {
        debugLog("RootView: タイトル画面表示要求を受信 現在モード=\(stateStore.activeMode.identifier.rawValue)")

        preparationCoordinator.cancelPendingGameActivationWorkItem(stateStore: stateStore)

        if stateStore.isPreparingGame {
            debugLog("RootView: ローディング表示中にタイトルへ戻るため強制的に解除します")
        }

        stateStore.isPreparingGame = false
        stateStore.isGameReadyForManualStart = false

        withAnimation(.easeInOut(duration: 0.25)) {
            stateStore.isShowingTitleScreen = true
        }
    }

    func presentSettings(stateStore: RootViewStateStore) {
        stateStore.isPresentingTitleSettings = true
    }
}

@MainActor
struct RootViewGameCenterPromptPresenter {
    func performInitialAuthenticationIfNeeded(
        stateStore: RootViewStateStore,
        gameCenterService: GameCenterServiceProtocol
    ) {
        guard stateStore.markInitialAuthenticationAttemptedIfNeeded() else { return }

        requestAuthentication(stateStore: stateStore, gameCenterService: gameCenterService) { success in
            if !success {
                self.presentPrompt(for: .initialAuthenticationFailed, stateStore: stateStore)
            }
        }
    }

    func requestAuthentication(
        stateStore: RootViewStateStore,
        gameCenterService: GameCenterServiceProtocol,
        completion: @escaping (Bool) -> Void
    ) {
        gameCenterService.authenticateLocalPlayer { success in
            Task { @MainActor in
                stateStore.isAuthenticated = success
                completion(success)
            }
        }
    }

    func presentPrompt(for reason: GameCenterSignInPromptReason, stateStore: RootViewStateStore) {
        debugLog("RootView: Game Center サインイン促しアラートを要求 reason=\(reason)")
        stateStore.enqueueGameCenterSignInPrompt(reason: reason)
    }
}
