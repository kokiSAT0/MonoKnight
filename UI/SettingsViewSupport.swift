import SharedSupport
import SwiftUI

struct SettingsPresentationState {
    var isPurchaseInProgress = false
    var isRestoreInProgress = false
    var storeAlert: StoreAlert?
    var isGameCenterAuthenticationInProgress = false
    var gameCenterAlert: GameCenterAlert?
    var isResetAlertPresented = false
    var isDebugUnlockSuccessAlertPresented = false

    mutating func beginGameCenterAuthenticationIfNeeded() -> Bool {
        guard !isGameCenterAuthenticationInProgress else { return false }
        isGameCenterAuthenticationInProgress = true
        return true
    }

    mutating func completeGameCenterAuthentication(success: Bool) {
        isGameCenterAuthenticationInProgress = false
        gameCenterAlert = success ? .success : .failure
    }

    mutating func beginPurchaseIfNeeded() -> Bool {
        guard !isPurchaseInProgress else { return false }
        isPurchaseInProgress = true
        return true
    }

    mutating func completePurchase() {
        isPurchaseInProgress = false
    }

    mutating func beginRestoreIfNeeded() -> Bool {
        guard !isRestoreInProgress else { return false }
        isRestoreInProgress = true
        return true
    }

    mutating func completeRestore(success: Bool) {
        isRestoreInProgress = false
        storeAlert = success ? .restoreFinished : .restoreFailed
    }

    mutating func presentResetAlert() {
        isResetAlertPresented = true
    }

    mutating func handleRemoveAdsPurchaseChange(oldValue: Bool, newValue: Bool) {
        if !oldValue && newValue {
            storeAlert = .purchaseCompleted
        }
    }

    mutating func presentDebugUnlockSuccessAlert() {
        isDebugUnlockSuccessAlertPresented = true
    }
}

struct SettingsDebugUnlockState {
    var debugUnlockInput = ""
}

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
enum SettingsActionCoordinator {
    static func authenticateGameCenter(
        presentationState: Binding<SettingsPresentationState>,
        isGameCenterAuthenticated: Binding<Bool>,
        gameCenterService: GameCenterServiceProtocol
    ) {
        var shouldStartAuthentication = false
        mutate(presentationState) {
            shouldStartAuthentication = $0.beginGameCenterAuthenticationIfNeeded()
        }
        guard shouldStartAuthentication else { return }

        gameCenterService.authenticateLocalPlayer { success in
            Task { @MainActor in
                isGameCenterAuthenticated.wrappedValue = success
                mutate(presentationState) {
                    $0.completeGameCenterAuthentication(success: success)
                }
            }
        }
    }

    static func purchaseRemoveAds(
        presentationState: Binding<SettingsPresentationState>,
        storeService: AnyStoreService
    ) {
        var shouldStartPurchase = false
        mutate(presentationState) {
            shouldStartPurchase = $0.beginPurchaseIfNeeded()
        }
        guard shouldStartPurchase else { return }

        Task {
            if storeService.removeAdsPriceText == nil {
                await storeService.refreshProducts()
            }
            await storeService.purchaseRemoveAds()
            await MainActor.run {
                mutate(presentationState) {
                    $0.completePurchase()
                }
            }
        }
    }

    static func restorePurchases(
        presentationState: Binding<SettingsPresentationState>,
        storeService: AnyStoreService
    ) {
        var shouldStartRestore = false
        mutate(presentationState) {
            shouldStartRestore = $0.beginRestoreIfNeeded()
        }
        guard shouldStartRestore else { return }

        Task {
            let success = await storeService.restorePurchases()
            await MainActor.run {
                mutate(presentationState) {
                    $0.completeRestore(success: success)
                }
            }
        }
    }

    static func refreshPrivacySettings(adsService: AdsServiceProtocol) {
        Task { await adsService.refreshConsentStatus() }
    }

    static func restartConsentFlow(adsService: AdsServiceProtocol) {
        Task {
            await adsService.requestTrackingAuthorization()
            await adsService.requestConsentIfNeeded()
        }
    }
}

@MainActor
enum SettingsDebugUnlockCoordinator {
    static func isDebugOverrideActive(
        campaignProgressStore: CampaignProgressStore,
        dailyChallengeAttemptStore: AnyDailyChallengeAttemptStore
    ) -> Bool {
        campaignProgressStore.isDebugUnlockEnabled || dailyChallengeAttemptStore.isDebugUnlimitedEnabled
    }

    static func disableDebugOverrides(
        campaignProgressStore: CampaignProgressStore,
        dailyChallengeAttemptStore: AnyDailyChallengeAttemptStore
    ) {
        campaignProgressStore.disableDebugUnlock()
        dailyChallengeAttemptStore.disableDebugUnlimited()
    }

    static func handleDebugUnlockInputChange(
        _ newValue: String,
        debugState: Binding<SettingsDebugUnlockState>,
        presentationState: Binding<SettingsPresentationState>,
        campaignProgressStore: CampaignProgressStore,
        dailyChallengeAttemptStore: AnyDailyChallengeAttemptStore
    ) {
        let trimmedInput = String(
            newValue.filter(\.isNumber)
                .prefix(SettingsDebugConfiguration.unlockPassword.count)
        )

        if trimmedInput != newValue {
            mutate(debugState) {
                $0.debugUnlockInput = trimmedInput
            }
            return
        }

        guard !isDebugOverrideActive(
            campaignProgressStore: campaignProgressStore,
            dailyChallengeAttemptStore: dailyChallengeAttemptStore
        ) else {
            mutate(debugState) {
                $0.debugUnlockInput = ""
            }
            return
        }

        guard trimmedInput.count == SettingsDebugConfiguration.unlockPassword.count else { return }

        mutate(debugState) {
            $0.debugUnlockInput = ""
        }

        guard trimmedInput == SettingsDebugConfiguration.unlockPassword else { return }

        campaignProgressStore.enableDebugUnlock()
        dailyChallengeAttemptStore.enableDebugUnlimited()
        mutate(presentationState) {
            $0.presentDebugUnlockSuccessAlert()
        }
    }
}

@MainActor
private func mutate<Value>(_ binding: Binding<Value>, _ update: (inout Value) -> Void) {
    var value = binding.wrappedValue
    update(&value)
    binding.wrappedValue = value
}

@MainActor
extension SettingsView {
    var isDiagnosticsMenuAvailable: Bool {
        DebugLogHistory.shared.isFrontEndViewerEnabled
    }

    var isDebugOverrideActive: Bool {
        SettingsDebugUnlockCoordinator.isDebugOverrideActive(
            campaignProgressStore: campaignProgressStore,
            dailyChallengeAttemptStore: dailyChallengeAttemptStore
        )
    }

    func authenticateGameCenter() {
        SettingsActionCoordinator.authenticateGameCenter(
            presentationState: $presentationState,
            isGameCenterAuthenticated: $isGameCenterAuthenticated,
            gameCenterService: gameCenterService
        )
    }

    func purchaseRemoveAds() {
        SettingsActionCoordinator.purchaseRemoveAds(
            presentationState: $presentationState,
            storeService: storeService
        )
    }

    func restorePurchases() {
        SettingsActionCoordinator.restorePurchases(
            presentationState: $presentationState,
            storeService: storeService
        )
    }

    func refreshPrivacySettings() {
        SettingsActionCoordinator.refreshPrivacySettings(adsService: adsService)
    }

    func restartConsentFlow() {
        SettingsActionCoordinator.restartConsentFlow(adsService: adsService)
    }

    func disableDebugOverrides() {
        SettingsDebugUnlockCoordinator.disableDebugOverrides(
            campaignProgressStore: campaignProgressStore,
            dailyChallengeAttemptStore: dailyChallengeAttemptStore
        )
    }

    func handleDebugUnlockInputChange(_ newValue: String) {
        SettingsDebugUnlockCoordinator.handleDebugUnlockInputChange(
            newValue,
            debugState: $debugUnlockState,
            presentationState: $presentationState,
            campaignProgressStore: campaignProgressStore,
            dailyChallengeAttemptStore: dailyChallengeAttemptStore
        )
    }

    func presentResetAlert() {
        var updatedState = presentationState
        updatedState.presentResetAlert()
        presentationState = updatedState
    }

    func handleRemoveAdsPurchaseChange(oldValue: Bool, newValue: Bool) {
        var updatedState = presentationState
        updatedState.handleRemoveAdsPurchaseChange(oldValue: oldValue, newValue: newValue)
        presentationState = updatedState
    }
}
