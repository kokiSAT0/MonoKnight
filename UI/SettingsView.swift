import SwiftUI
import UIKit
import UserMessagingPlatform

/// アプリ全体の設定をまとめたビュー
/// 課金やプライバシー設定への導線を提供する
struct SettingsView: View {
    /// 課金処理を扱う `StoreService` を参照
    @StateObject private var store = StoreService.shared
    /// BGM のオン/オフ設定を保持
    @AppStorage("bgm_enabled") private var bgmEnabled: Bool = true
    /// 効果音のオン/オフ設定を保持
    @AppStorage("se_enabled") private var seEnabled: Bool = true
    /// ハプティクスのオン/オフ設定を保持
    @AppStorage("enable_haptics") private var enableHaptics: Bool = true

    var body: some View {
        NavigationStack {
            List {
                // MARK: - サウンド設定セクション
                Section("サウンド") {
                    // BGM の再生を切り替えるトグル
                    Toggle("BGM", isOn: $bgmEnabled)
                    // 効果音の再生を切り替えるトグル
                    Toggle("効果音", isOn: $seEnabled)
                    // ハプティクスの発生を切り替えるトグル
                    Toggle("ハプティクス", isOn: $enableHaptics)
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
                                    // フォーム表示に失敗した場合の処理
                                    // TODO: ユーザーへのエラー表示などを実装
                                } else {
                                    // フォーム表示に成功した場合の処理
                                    // TODO: 必要に応じて同意状況の再評価を実装
                                }
                            }
                        }
                    }) {
                        Text("プライバシー設定")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }

                // MARK: - 開発者連絡セクション
                Section("開発者へ連絡") {
                    // メールアプリを起動して問い合わせ
                    Link("メールで問い合わせ", destination: URL(string: "mailto:developer@example.com")!)
                        .frame(maxWidth: .infinity, alignment: .center)
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

