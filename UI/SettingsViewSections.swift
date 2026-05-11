import SwiftUI
import Game

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
手札を引いた順番のまま維持するか、移動方向に応じて自動整列するかを選べます。方向ソートでは移動カードを先、補助カードを後ろにまとめ、移動カードは左への移動量が大きい順、同じ左右移動量なら上方向が優先されます。
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
            Text("遊び方と辞典を確認できます。塔ダンジョンでは床で拾ったカードと報酬カードを使い、出口到達を目指します。")
        }
    }
}

struct SettingsDiagnosticsSection: View {
    @ObservedObject var gameSettingsStore: GameSettingsStore

    var body: some View {
        Section {
            Toggle(
                "辞典を全表示（開発者用）",
                isOn: $gameSettingsStore.showsAllEncyclopediaEntriesForDeveloper
            )
            NavigationLink {
                DiagnosticsCenterView()
            } label: {
                Label("診断ログを確認", systemImage: "wrench.and.screwdriver")
            }
        } header: {
            Text("開発者向け診断")
        } footer: {
            Text("TestFlight など開発用ビルドでのみ有効化される開発者メニューです。辞典全表示は未発見項目の確認用で、公開版では診断メニューごと非表示にできます。")
        }
    }
}
