import SwiftUI

/// アプリ全体の設定をまとめたビュー
/// 課金やプライバシー設定への導線を提供する
struct SettingsView: View {
    /// 課金処理を扱う `StoreService` を参照
    @StateObject private var store = StoreService.shared

    var body: some View {
        NavigationStack {
            List {
                // MARK: - 課金関連セクション
                Section("課金") {
                    // 広告除去を購入するボタン
                    Button(action: {
                        Task {
                            // 非同期で購入処理を呼び出す
                            await store.purchaseRemoveAds()
                        }
                    }) {
                        Text("広告除去を購入")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }

                    // 購入済みのアイテムを復元するボタン
                    Button(action: {
                        Task {
                            await store.restorePurchases()
                        }
                    }) {
                        Text("購入を復元")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }

                // MARK: - プライバシー設定セクション
                Section("プライバシー") {
                    // UMP のプライバシー設定を再表示するボタン
                    Button(action: {
                        // 実際の UMP SDK 呼び出しは未実装のためログ出力のみ
                        print("プライバシー設定を表示")
                    }) {
                        Text("プライバシー設定")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            // 画面タイトルをナビゲーションバーに表示
            .navigationTitle("設定")
        }
    }
}

// MARK: - プレビュー
#Preview {
    SettingsView()
}

