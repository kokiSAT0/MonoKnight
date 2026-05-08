import SharedSupport
import SwiftUI

struct SettingsPresentationState {
    var isPurchaseInProgress = false
    var isRestoreInProgress = false
    var storeAlert: StoreAlert?

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

    mutating func handleRemoveAdsPurchaseChange(oldValue: Bool, newValue: Bool) {
        if !oldValue && newValue {
            storeAlert = .purchaseCompleted
        }
    }

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

@MainActor
enum SettingsActionCoordinator {
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

    func handleRemoveAdsPurchaseChange(oldValue: Bool, newValue: Bool) {
        var updatedState = presentationState
        updatedState.handleRemoveAdsPurchaseChange(oldValue: oldValue, newValue: newValue)
        presentationState = updatedState
    }
}
