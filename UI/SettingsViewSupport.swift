import SharedSupport
import SwiftUI

enum StoreAlert: Identifiable {
    case purchaseCompleted
    case restoreFinished
    case restoreFailed

    var id: String {
        switch self {
        case .purchaseCompleted:
            "purchaseCompleted"
        case .restoreFinished:
            "restoreFinished"
        case .restoreFailed:
            "restoreFailed"
        }
    }

    var title: String {
        switch self {
        case .purchaseCompleted:
            "広告除去を適用しました"
        case .restoreFinished:
            "購入内容を確認しました"
        case .restoreFailed:
            "復元に失敗しました"
        }
    }

    var message: String {
        switch self {
        case .purchaseCompleted:
            "広告の表示が無効化されました。アプリを再起動する必要はありません。"
        case .restoreFinished:
            "App Store と同期しました。購入済みの場合は自動で広告除去が反映されます。"
        case .restoreFailed:
            "通信状況や Apple ID を確認のうえ、時間を置いて再度お試しください。"
        }
    }
}

enum GameCenterAlert: Identifiable {
    case success
    case failure

    var id: String {
        switch self {
        case .success:
            "gc_success"
        case .failure:
            "gc_failure"
        }
    }

    var title: String { "Game Center" }

    var message: String {
        switch self {
        case .success:
            "Game Center へのサインインが完了しました。ランキングとスコア送信が利用可能です。"
        case .failure:
            "サインインに失敗しました。通信環境を確認し、時間を置いて再度お試しください。"
        }
    }
}

private enum SettingsDebugConfiguration {
    static let unlockPassword = "6031"
}

@MainActor
extension SettingsView {
    var isDiagnosticsMenuAvailable: Bool {
        DebugLogHistory.shared.isFrontEndViewerEnabled
    }

    func isDebugOverrideActive(
        campaignProgressStore: CampaignProgressStore,
        dailyChallengeAttemptStore: AnyDailyChallengeAttemptStore
    ) -> Bool {
        campaignProgressStore.isDebugUnlockEnabled || dailyChallengeAttemptStore.isDebugUnlimitedEnabled
    }

    func authenticateGameCenter() {
        guard !isGameCenterAuthenticationInProgress else { return }
        isGameCenterAuthenticationInProgress = true
        gameCenterService.authenticateLocalPlayer { success in
            Task { @MainActor in
                isGameCenterAuthenticationInProgress = false
                isGameCenterAuthenticated = success
                gameCenterAlert = success ? .success : .failure
            }
        }
    }

    func purchaseRemoveAds() {
        guard !isPurchaseInProgress else { return }
        isPurchaseInProgress = true
        Task {
            if storeService.removeAdsPriceText == nil {
                await storeService.refreshProducts()
            }
            await storeService.purchaseRemoveAds()
            await MainActor.run {
                isPurchaseInProgress = false
            }
        }
    }

    func restorePurchases() {
        guard !isRestoreInProgress else { return }
        isRestoreInProgress = true
        Task {
            let success = await storeService.restorePurchases()
            await MainActor.run {
                isRestoreInProgress = false
                storeAlert = success ? .restoreFinished : .restoreFailed
            }
        }
    }

    func refreshPrivacySettings() {
        Task { await adsService.refreshConsentStatus() }
    }

    func restartConsentFlow() {
        Task {
            await adsService.requestTrackingAuthorization()
            await adsService.requestConsentIfNeeded()
        }
    }

    func disableDebugOverrides() {
        campaignProgressStore.disableDebugUnlock()
        dailyChallengeAttemptStore.disableDebugUnlimited()
    }

    func handleDebugUnlockInputChange(_ newValue: String) {
        let digitsOnly = newValue.filter { $0.isNumber }
        let trimmed = String(digitsOnly.prefix(SettingsDebugConfiguration.unlockPassword.count))

        if trimmed != newValue {
            debugUnlockInput = trimmed
            return
        }

        guard !isDebugOverrideActive(
            campaignProgressStore: campaignProgressStore,
            dailyChallengeAttemptStore: dailyChallengeAttemptStore
        ) else {
            debugUnlockInput = ""
            return
        }

        guard trimmed.count == SettingsDebugConfiguration.unlockPassword.count else { return }

        if trimmed == SettingsDebugConfiguration.unlockPassword {
            campaignProgressStore.enableDebugUnlock()
            dailyChallengeAttemptStore.enableDebugUnlimited()
            debugUnlockInput = ""
            isDebugUnlockSuccessAlertPresented = true
        } else {
            debugUnlockInput = ""
        }
    }
}
