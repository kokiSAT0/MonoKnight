import SwiftUI

struct SettingsView: View {
    var body: some View {
        List {
            Button("プライバシー設定を更新") {
                Task { await AdsService.shared.refreshConsentStatus() }
            }
            Button("同意取得フローをやり直す") {
                Task {
                    await AdsService.shared.requestTrackingAuthorization()
                    await AdsService.shared.requestConsentIfNeeded()
                }
            }
        }
        .navigationTitle("設定")
    }
}
