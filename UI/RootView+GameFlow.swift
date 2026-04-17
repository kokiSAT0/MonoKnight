import SwiftUI
import SharedSupport
import Game

extension RootView {
    func startGamePreparation(for mode: GameMode, context: GamePreparationContext) {
        cancelPendingGameActivationWorkItem()

        debugLog("RootView: ゲーム準備開始リクエストを処理 選択モード=\(mode.identifier.rawValue) context=\(context.logIdentifier)")

        stateStore.activeMode = mode
        stateStore.lastPreparationContext = context

        stateStore.gameSessionID = UUID()
        let scheduledSessionID = stateStore.gameSessionID
        debugLog("RootView: 新規ゲームセッションを割り当て sessionID=\(scheduledSessionID)")

        stateStore.isGameReadyForManualStart = false

        withAnimation(.easeInOut(duration: 0.25)) {
            stateStore.isShowingTitleScreen = false
            stateStore.isPreparingGame = true
        }

        scheduleGameActivationCompletion(for: scheduledSessionID)
    }

    func handleReturnToTitleRequest() {
        debugLog("RootView: タイトル画面表示要求を受信 現在モード=\(stateStore.activeMode.identifier.rawValue)")

        cancelPendingGameActivationWorkItem()

        if stateStore.isPreparingGame {
            debugLog("RootView: ローディング表示中にタイトルへ戻るため強制的に解除します")
        }

        stateStore.isPreparingGame = false
        stateStore.isGameReadyForManualStart = false

        withAnimation(.easeInOut(duration: 0.25)) {
            stateStore.isShowingTitleScreen = true
        }
    }

    func handleReturnToCampaignStageSelectionRequest() {
        let contextDescription = stateStore.lastPreparationContext?.logIdentifier ?? "unknown"
        debugLog("RootView: キャンペーンステージ選択へ戻る要求を受信 lastContext=\(contextDescription)")

        stateStore.pendingTitleNavigationTarget = .campaign
        handleReturnToTitleRequest()
    }

    func scheduleGameActivationCompletion(for sessionID: UUID) {
        let workItem = DispatchWorkItem { [weak stateStore, sessionID] in
            guard let stateStore else {
                debugLog("RootView: 状態ストアが解放済みのためゲーム準備ワークアイテムを終了 sessionID=\(sessionID)")
                return
            }

            guard stateStore.pendingGameActivationWorkItem != nil else {
                debugLog("RootView: ゲーム準備ワークアイテムが実行前に破棄されました sessionID=\(sessionID)")
                return
            }

            guard sessionID == stateStore.gameSessionID else {
                debugLog("RootView: ゲーム準備完了通知を破棄 scheduled=\(sessionID) current=\(stateStore.gameSessionID)")
                return
            }

            debugLog("RootView: ゲーム準備完了 手動開始待ちへ移行 sessionID=\(sessionID)")

            stateStore.isGameReadyForManualStart = true
            stateStore.pendingGameActivationWorkItem = nil
        }

        stateStore.pendingGameActivationWorkItem = workItem

        DispatchQueue.main.asyncAfter(
            deadline: .now() + RootLayoutMetrics.gamePreparationMinimumDelay,
            execute: workItem
        )
    }

    func cancelPendingGameActivationWorkItem() {
        guard let workItem = stateStore.pendingGameActivationWorkItem else { return }
        debugLog("RootView: 保留中のゲーム準備ワークアイテムをキャンセル sessionID=\(stateStore.gameSessionID)")
        workItem.cancel()
        stateStore.pendingGameActivationWorkItem = nil
        stateStore.isGameReadyForManualStart = false
    }

    func finishGamePreparationAndStart() {
        guard stateStore.isPreparingGame else { return }

        debugLog("RootView: ユーザー操作によりゲームを開始")

        withAnimation(.easeInOut(duration: 0.25)) {
            stateStore.isPreparingGame = false
        }
        stateStore.isGameReadyForManualStart = false
    }

    func handleGameCenterAuthenticationRequest(completion: @escaping (Bool) -> Void) {
        gameCenterService.authenticateLocalPlayer { success in
            Task { @MainActor in
                stateStore.isAuthenticated = success
                completion(success)
            }
        }
    }
}
