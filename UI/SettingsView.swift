import SwiftUI

struct SettingsView: View {
    /// 「遊び方」シートの表示状態
    @State private var isPresentingHowToPlay: Bool = false

    var body: some View {
        NavigationStack {
            List {
                // MARK: - ヘルプセクション
                Section("ヘルプ") {
                    Button {
                        // 設定画面からも遊び方をいつでも確認できるようにする
                        isPresentingHowToPlay = true
                    } label: {
                        Label("遊び方を見る", systemImage: "questionmark.circle")
                    }
                }

                // MARK: - 広告・同意関連セクション
                Section("広告とプライバシー") {
                    Button("プライバシー設定を更新") {
                        // UMP の設定画面を再表示して同意ステータスを更新
                        Task { await AdsService.shared.refreshConsentStatus() }
                    }
                    Button("同意取得フローをやり直す") {
                        // ATT → UMP の順で同意フローを再実行
                        Task {
                            await AdsService.shared.requestTrackingAuthorization()
                            await AdsService.shared.requestConsentIfNeeded()
                        }
                    }
                }
            }
            .navigationTitle("設定")
        }
        // ヘルプボタンから遊び方シートを表示
        .sheet(isPresented: $isPresentingHowToPlay) {
            HowToPlayView()
                .presentationDetents([.medium, .large])
        }
    }
}
