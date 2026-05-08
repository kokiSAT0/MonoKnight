import Game
import SwiftUI

@MainActor
struct SettingsView: View {
    let adsService: AdsServiceProtocol
    let gameCenterService: GameCenterServiceProtocol

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var storeService: AnyStoreService
    @EnvironmentObject private var gameSettingsStore: GameSettingsStore

    @State var presentationState = SettingsPresentationState()
    @Binding var isGameCenterAuthenticated: Bool

    init(
        adsService: AdsServiceProtocol? = nil,
        gameCenterService: GameCenterServiceProtocol? = nil,
        isGameCenterAuthenticated: Binding<Bool> = .constant(false)
    ) {
        self.adsService = adsService ?? AdsService.shared
        self.gameCenterService = gameCenterService ?? GameCenterService.shared
        self._isGameCenterAuthenticated = isGameCenterAuthenticated
    }

    var body: some View {
        NavigationStack {
            List {
                SettingsThemeSection(gameSettingsStore: gameSettingsStore)
                SettingsHapticsSection(gameSettingsStore: gameSettingsStore)
                SettingsGuideSection(gameSettingsStore: gameSettingsStore)
                SettingsHandOrderingSection(gameSettingsStore: gameSettingsStore)
                SettingsAdsSection(
                    storeService: storeService,
                    isPurchaseInProgress: presentationState.isPurchaseInProgress,
                    isRestoreInProgress: presentationState.isRestoreInProgress,
                    onPurchase: purchaseRemoveAds,
                    onRestore: restorePurchases
                )
                SettingsPrivacySection(
                    onRefreshPrivacySettings: refreshPrivacySettings,
                    onRestartConsentFlow: restartConsentFlow
                )
                SettingsHelpSection()
                if isDiagnosticsMenuAvailable {
                    SettingsDiagnosticsSection()
                }
            }
            .navigationTitle("設定")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Label("閉じる", systemImage: "xmark")
                    }
                    .accessibilityLabel(Text("設定画面を閉じる"))
                }
            }
            .onChange(of: storeService.isRemoveAdsPurchased) { oldValue, newValue in
                handleRemoveAdsPurchaseChange(oldValue: oldValue, newValue: newValue)
            }
            .preferredColorScheme(
                gameSettingsStore.preferredColorScheme.preferredColorScheme
            )
        }
        .alert(item: $presentationState.storeAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}
