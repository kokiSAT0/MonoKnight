import Game
import SwiftUI

@MainActor
struct SettingsView: View {
    let adsService: AdsServiceProtocol
    let gameCenterService: GameCenterServiceProtocol

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var storeService: AnyStoreService
    @EnvironmentObject var campaignProgressStore: CampaignProgressStore
    @EnvironmentObject var dailyChallengeAttemptStore: AnyDailyChallengeAttemptStore
    @EnvironmentObject private var gameSettingsStore: GameSettingsStore

    @State var presentationState = SettingsPresentationState()
    @State var debugUnlockState = SettingsDebugUnlockState()
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
                SettingsGameCenterSection(
                    isAuthenticated: isGameCenterAuthenticated,
                    isAuthenticationInProgress: presentationState.isGameCenterAuthenticationInProgress,
                    onAuthenticate: authenticateGameCenter
                )
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
                SettingsStatsSection(onResetBestPoints: presentResetAlert)
                SettingsDebugSection(
                    debugUnlockInput: $debugUnlockState.debugUnlockInput,
                    isDebugOverrideActive: isDebugOverrideActive,
                    isCampaignDebugUnlockEnabled: campaignProgressStore.isDebugUnlockEnabled,
                    isDailyChallengeDebugUnlimitedEnabled: dailyChallengeAttemptStore
                        .isDebugUnlimitedEnabled,
                    onDebugUnlockInputChange: handleDebugUnlockInputChange(_:),
                    onDisableDebugUnlock: disableDebugOverrides
                )
                if isDiagnosticsMenuAvailable {
                    SettingsDiagnosticsSection()
                }
            }
            .alert("ベスト記録をリセット", isPresented: $presentationState.isResetAlertPresented) {
                Button("リセットする", role: .destructive) {
                    gameSettingsStore.resetBestPoints()
                }
                Button("キャンセル", role: .cancel) { }
            } message: {
                Text("現在保存されているベストポイントを初期状態に戻します。この操作は取り消せません。")
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
        .alert("全ステージを解放しました", isPresented: $presentationState.isDebugUnlockSuccessAlertPresented) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("キャンペーンモードの検証用として全てのステージが解放された状態になりました。")
        }
        .alert(item: $presentationState.gameCenterAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
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
