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

    @State var isPurchaseInProgress = false
    @State var isRestoreInProgress = false
    @State var storeAlert: StoreAlert?
    @State var debugUnlockInput: String = ""
    @State var isDebugUnlockSuccessAlertPresented = false
    @Binding var isGameCenterAuthenticated: Bool
    @State var isGameCenterAuthenticationInProgress = false
    @State var gameCenterAlert: GameCenterAlert?
    @State private var isResetAlertPresented = false

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
                    isAuthenticationInProgress: isGameCenterAuthenticationInProgress,
                    onAuthenticate: authenticateGameCenter
                )
                SettingsThemeSection(gameSettingsStore: gameSettingsStore)
                SettingsHapticsSection(gameSettingsStore: gameSettingsStore)
                SettingsGuideSection(gameSettingsStore: gameSettingsStore)
                SettingsHandOrderingSection(gameSettingsStore: gameSettingsStore)
                SettingsAdsSection(
                    storeService: storeService,
                    isPurchaseInProgress: isPurchaseInProgress,
                    isRestoreInProgress: isRestoreInProgress,
                    onPurchase: purchaseRemoveAds,
                    onRestore: restorePurchases
                )
                SettingsPrivacySection(
                    onRefreshPrivacySettings: refreshPrivacySettings,
                    onRestartConsentFlow: restartConsentFlow
                )
                SettingsHelpSection()
                SettingsStatsSection(onResetBestPoints: { isResetAlertPresented = true })
                SettingsDebugSection(
                    debugUnlockInput: $debugUnlockInput,
                    isDebugOverrideActive: isDebugOverrideActive(
                        campaignProgressStore: campaignProgressStore,
                        dailyChallengeAttemptStore: dailyChallengeAttemptStore
                    ),
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
            .alert("ベスト記録をリセット", isPresented: $isResetAlertPresented) {
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
                if !oldValue && newValue {
                    storeAlert = .purchaseCompleted
                }
            }
            .preferredColorScheme(
                gameSettingsStore.preferredColorScheme.preferredColorScheme
            )
        }
        .alert("全ステージを解放しました", isPresented: $isDebugUnlockSuccessAlertPresented) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("キャンペーンモードの検証用として全てのステージが解放された状態になりました。")
        }
        .alert(item: $gameCenterAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert(item: $storeAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}
