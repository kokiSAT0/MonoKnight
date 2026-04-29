import Game
import SwiftUI

struct SettingsGameCenterSection: View {
    let isAuthenticated: Bool
    let isAuthenticationInProgress: Bool
    let onAuthenticate: () -> Void

    var body: some View {
        Section {
            Label {
                Text(isAuthenticated ? "サインイン済み" : "未サインイン")
                    .font(.headline)
            } icon: {
                Image(systemName: isAuthenticated ? "checkmark.circle.fill" : "person.crop.circle.badge.exclamationmark")
            }
            .foregroundStyle(isAuthenticated ? .green : .orange)
            .accessibilityIdentifier("settings_gc_status_label")

            Button(action: onAuthenticate) {
                HStack {
                    Text(isAuthenticated ? "状態を再確認" : "Game Center にサインイン")
                    Spacer()
                    if isAuthenticationInProgress {
                        ProgressView()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isAuthenticationInProgress)
            .accessibilityIdentifier("settings_gc_sign_in_button")
        } header: {
            Text("Game Center")
        } footer: {
            Text("ランキング表示やスコア送信を行うには Game Center へのサインインが必要です。サインイン済みの場合は結果画面から自動で送信されます。")
        }
    }
}

struct SettingsThemeSection: View {
    @ObservedObject var gameSettingsStore: GameSettingsStore

    var body: some View {
        Section {
            Picker("テーマ", selection: Binding<ThemePreference>(
                get: { gameSettingsStore.preferredColorScheme },
                set: { gameSettingsStore.preferredColorScheme = $0 }
            )) {
                ForEach(ThemePreference.allCases) { preference in
                    Text(preference.displayName)
                        .tag(preference)
                }
            }
        } header: {
            Text("テーマ")
        } footer: {
            Text("ライト／ダークを固定するか、システム設定に合わせるかを選択できます。ゲーム画面の配色も即座に切り替わります。")
        }
    }
}

struct SettingsHapticsSection: View {
    @ObservedObject var gameSettingsStore: GameSettingsStore

    var body: some View {
        Section {
            Toggle("ハプティクスを有効にする", isOn: $gameSettingsStore.hapticsEnabled)
        } header: {
            Text("ハプティクス")
        } footer: {
            Text("ゲーム内操作や広告警告の振動を制御します。オフにすると警告通知でも振動しません。")
        }
    }
}

struct SettingsGuideSection: View {
    @ObservedObject var gameSettingsStore: GameSettingsStore

    var body: some View {
        Section {
            Toggle("ガイドモード（移動候補をハイライト）", isOn: $gameSettingsStore.guideModeEnabled)
        } header: {
            Text("ガイド")
        } footer: {
            Text("手札から移動できるマスを盤面上で光らせます。集中して考えたい場合はオフにできます。")
        }
    }
}

struct SettingsHandOrderingSection: View {
    @ObservedObject var gameSettingsStore: GameSettingsStore

    var body: some View {
        Section {
            Picker("手札の並び順", selection: Binding<HandOrderingStrategy>(
                get: { gameSettingsStore.handOrderingStrategy },
                set: { gameSettingsStore.handOrderingStrategy = $0 }
            )) {
                ForEach(HandOrderingStrategy.allCases, id: \.self) { strategy in
                    Text(strategy.displayName)
                        .tag(strategy)
                }
            }
        } header: {
            Text("手札の並び")
        } footer: {
            Text("""
手札を引いた順番のまま維持するか、移動方向に応じて自動整列するかを選べます。方向ソートでは左への移動量が大きいカードが左側に、同じ左右移動量なら上方向のカードが優先されます。
""")
        }
    }
}

struct SettingsAdsSection: View {
    @ObservedObject var storeService: AnyStoreService
    let isPurchaseInProgress: Bool
    let isRestoreInProgress: Bool
    let onPurchase: () -> Void
    let onRestore: () -> Void

    var body: some View {
        Section {
            if storeService.isRemoveAdsPurchased {
                Label {
                    Text("広告は現在表示されません")
                } icon: {
                    Image(systemName: "checkmark.seal.fill")
                }
                .accessibilityLabel(Text("広告除去が適用済みです"))
            } else {
                Button(action: onPurchase) {
                    HStack {
                        Label("広告を非表示にする", systemImage: "hand.raised.slash")
                        Spacer()
                        if isPurchaseInProgress {
                            ProgressView()
                        } else if let price = storeService.removeAdsPriceText {
                            Text(price)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("取得中…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(isPurchaseInProgress)
                .accessibilityLabel(Text("広告を非表示にする購入手続き"))
            }

            Button(action: onRestore) {
                HStack {
                    Label("購入内容を復元", systemImage: "arrow.clockwise.circle")
                    Spacer()
                    if isRestoreInProgress {
                        ProgressView()
                    }
                }
            }
            .disabled(isRestoreInProgress)
            .accessibilityLabel(Text("広告除去の購入履歴を復元する"))
        } header: {
            Text("広告")
        } footer: {
            Text("広告を非表示にする購入手続きや、機種変更時の復元が行えます。購入内容は Apple ID に紐づくため、別の端末でも同じアカウントで復元できます。")
        }
    }
}

struct SettingsPrivacySection: View {
    let onRefreshPrivacySettings: () -> Void
    let onRestartConsentFlow: () -> Void

    var body: some View {
        Section {
            Button("プライバシー設定を更新", action: onRefreshPrivacySettings)
            Button("同意取得フローをやり直す", action: onRestartConsentFlow)
        } header: {
            Text("プライバシー設定")
        } footer: {
            Text("広告配信に関するトラッキング許可や同意フォームを再確認できます。")
        }
    }
}

struct SettingsHelpSection: View {
    var body: some View {
        Section {
            NavigationLink {
                HowToPlayView()
            } label: {
                Label("遊び方を見る", systemImage: "questionmark.circle")
            }
        } header: {
            Text("ヘルプ")
        } footer: {
            Text("遊び方と辞典を確認できます。カードの動きや勝利条件に加えて、手札スロットが最大 \(GameMode.standard.handSize) 種類で\(GameMode.standard.stackingRuleDetailText)という仕様も確認できます。")
        }
    }
}

struct SettingsStatsSection: View {
    let onResetBestPoints: () -> Void

    var body: some View {
        Section {
            Button("ベスト記録をリセット", action: onResetBestPoints)
                .accessibilityLabel(Text("ベスト記録をリセットする"))
        } header: {
            Text("戦績")
        } footer: {
            Text("ベストポイントを初期状態に戻します。リセット後は新しいプレイで再び記録されます。")
        }
    }
}

struct SettingsDebugSection: View {
    @Binding var debugUnlockInput: String
    let isDebugOverrideActive: Bool
    let isCampaignDebugUnlockEnabled: Bool
    let isDailyChallengeDebugUnlimitedEnabled: Bool
    let onDebugUnlockInputChange: (String) -> Void
    let onDisableDebugUnlock: () -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                TextField("デバッグ用パスコード", text: $debugUnlockInput)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .disabled(isDebugOverrideActive)
                    .onChange(of: debugUnlockInput) { _, newValue in
                        onDebugUnlockInputChange(newValue)
                    }

                if isCampaignDebugUnlockEnabled {
                    Label("全てのステージが解放されています（無効化ボタンから解除可能）", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                } else {
                    Text("社内検証で必要な場合のみ入力してください。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if isDailyChallengeDebugUnlimitedEnabled {
                    Label("デイリーチャレンジは無制限モードです", systemImage: "infinity")
                        .foregroundStyle(.blue)
                        .font(.subheadline)
                    Text("デバッグ検証中は挑戦回数の消費と広告視聴がスキップされます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if isDebugOverrideActive {
                    Button(action: onDisableDebugUnlock) {
                        Label("全解放を無効化", systemImage: "lock.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .accessibilityIdentifier("settings_disable_debug_unlock_button")
                }
            }
        } header: {
            Text("デバッグ")
        } footer: {
            Text("正しいパスコードを入力するとキャンペーンモードの全ステージが解放されます。アプリを再起動しても維持されます。")
        }
    }
}

struct SettingsDiagnosticsSection: View {
    var body: some View {
        Section {
            NavigationLink {
                DiagnosticsCenterView()
            } label: {
                Label("診断ログを確認", systemImage: "wrench.and.screwdriver")
            }
        } header: {
            Text("開発者向け診断")
        } footer: {
            Text("TestFlight など開発用ビルドでのみ有効化されるログビューアです。公開版では環境変数やビルド設定で無効化できます。")
        }
    }
}
