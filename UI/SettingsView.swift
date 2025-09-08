import SwiftUI
import UIKit
import UserMessagingPlatform

/// アプリ全体の設定をまとめたビュー
/// 課金やプライバシー設定への導線を提供する
struct SettingsView: View {
    /// 課金処理を扱う `StoreService` を参照
    @StateObject private var store = StoreService.shared
    /// プライバシー設定フォーム表示時のエラー文言
    @State private var privacyErrorMessage: String = ""
    /// プライバシー設定フォームでエラーが起きたかどうか
    @State private var showPrivacyError: Bool = false
    /// BGM を再生するかどうかの設定値
    @AppStorage("bgm_enabled") private var bgmEnabled: Bool = true
    /// 効果音を再生するかどうかの設定値
    @AppStorage("se_enabled") private var seEnabled: Bool = true
    /// ハプティクスを有効にするかどうかの設定値
    @AppStorage("haptics_enabled") private var hapticsEnabled: Bool = true

    var body: some View {
        NavigationStack {
            List {
                // MARK: - サウンド設定セクション
                Section("サウンド") {
                    // BGM のオン・オフを切り替えるトグル
                    Toggle("BGMを再生", isOn: $bgmEnabled)
                    // 効果音のオン・オフを切り替えるトグル
                    Toggle("効果音を再生", isOn: $seEnabled)
                }

                // MARK: - フィードバック設定セクション
                Section("操作フィードバック") {
                    // ハプティクスのオン・オフを切り替えるトグル
                    Toggle("ハプティクスを有効にする", isOn: $hapticsEnabled)
                }

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
                    // UMP のプライバシー設定フォームを再表示するボタン
                    Button(action: {
                        // 現在表示中のルートビューコントローラを取得
                        if let root = UIApplication.shared.connectedScenes
                            .compactMap({ $0 as? UIWindowScene })
                            .first?.windows.first?.rootViewController {
                            // 取得したコントローラからプライバシー設定フォームを表示
                            UMPConsentForm.presentPrivacyOptionsForm(from: root) { error in
                                if let error {
                                    // エラー内容を保持しアラートを表示する
                                    privacyErrorMessage = error.localizedDescription
                                    showPrivacyError = true
                                } else {
                                    // フォーム閉鎖後に同意状況を再取得し広告設定を更新
                                    Task {
                                        await AdsService.shared.refreshConsentStatus()
                                    }
                                }
                            }
                        }
                    }) {
                        Text("プライバシー設定")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }

                // MARK: - 開発者連絡先セクション
                Section("お問い合わせ") {
                    // メールアプリを起動して開発者へ問い合わせるリンク
                    Link("メールで問い合わせ", destination: URL(string: "mailto:developer@example.com")!)
                }
            }
            // 画面タイトルをナビゲーションバーに表示
            .navigationTitle("設定")
            // プライバシー設定フォーム表示失敗時のアラート
            .alert("エラー", isPresented: $showPrivacyError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(privacyErrorMessage)
            }
        }
    }
}

// MARK: - プレビュー
#Preview {
    SettingsView()
}

