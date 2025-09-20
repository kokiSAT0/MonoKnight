import SwiftUI

struct SettingsView: View {
    // MARK: - ハプティクス設定
    // ユーザーのハプティクス利用有無を永続化する。デフォルトは有効。
    @AppStorage("haptics_enabled") private var hapticsEnabled: Bool = true

    var body: some View {
        List {
            // ハプティクス制御セクション
            Section {
                Toggle("ハプティクスを有効にする", isOn: $hapticsEnabled)
            } header: {
                Text("ハプティクス")
            } footer: {
                // 広告警告などの振動もオフになることを明示
                Text("ゲーム内操作や広告警告の振動を制御します。オフにすると警告通知でも振動しません。")
            }

            // プライバシー操作セクション
            Section {
                Button("プライバシー設定を更新") {
                    Task { await AdsService.shared.refreshConsentStatus() }
                }
                Button("同意取得フローをやり直す") {
                    Task {
                        await AdsService.shared.requestTrackingAuthorization()
                        await AdsService.shared.requestConsentIfNeeded()
                    }
                }
            } header: {
                Text("プライバシー設定")
            } footer: {
                // ユーザーが何を行えるのかを補足
                Text("広告配信に関するトラッキング許可や同意フォームを再確認できます。")
            }
        }
        .navigationTitle("設定")
    }
}
