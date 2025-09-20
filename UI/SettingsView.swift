import SwiftUI

struct SettingsView: View {
    // MARK: - テーマ設定
    // ユーザーが任意に選択したカラースキームを保持する。初期値はシステム依存の `.system`。
    @AppStorage("preferred_color_scheme") private var preferredColorSchemeRawValue: String = ThemePreference.system.rawValue

    // MARK: - ハプティクス設定
    // ユーザーのハプティクス利用有無を永続化する。デフォルトは有効。
    @AppStorage("haptics_enabled") private var hapticsEnabled: Bool = true

    // MARK: - ガイドモード設定
    // 盤面の移動候補ハイライトを保存し、GameView 側の @AppStorage と連動させる。
    @AppStorage("guide_mode_enabled") private var guideModeEnabled: Bool = true

    // MARK: - 戦績管理
    // ベスト手数を UserDefaults から取得・更新する。未設定時は Int.max で初期化しておく。
    @AppStorage("best_moves_5x5") private var bestMoves: Int = .max

    // 戦績リセット確認用のアラート表示フラグ。ユーザーが誤操作しないよう明示的に確認する。
    @State private var isResetAlertPresented = false

    var body: some View {
        NavigationStack {
            List {
                // MARK: テーマ選択セクション
                Section {
                    // Picker の selection は ThemePreference を直接扱えるように Binding を手動で構築する。
                    Picker("テーマ", selection: Binding<ThemePreference>(
                        get: { ThemePreference(rawValue: preferredColorSchemeRawValue) ?? .system },
                        set: { newValue in preferredColorSchemeRawValue = newValue.rawValue }
                    )) {
                        // ユーザー向けラベルは ThemePreference 側で定義した displayName を利用し、将来のローカライズ変更にも追従しやすくする。
                        ForEach(ThemePreference.allCases) { preference in
                            Text(preference.displayName)
                                .tag(preference)
                        }
                    }
                    // - NOTE: 選択を変更すると即座に `@AppStorage` が更新され、`MonoKnightApp` 側の `.preferredColorScheme` へ反映される。
                } header: {
                    Text("テーマ")
                } footer: {
                    // アプリ全体の見た目が切り替わることと、SpriteKit 側のパレットにも反映されることを説明。
                    Text("ライト／ダークを固定するか、システム設定に合わせるかを選択できます。ゲーム画面の配色も即座に切り替わります。")
                }

                // ハプティクス制御セクション
                Section {
                    Toggle("ハプティクスを有効にする", isOn: $hapticsEnabled)
                } header: {
                    Text("ハプティクス")
                } footer: {
                    // 広告警告などの振動もオフになることを明示
                    Text("ゲーム内操作や広告警告の振動を制御します。オフにすると警告通知でも振動しません。")
                }

                // ガイドモードのオン/オフをユーザーが選択できるようにするセクション
                Section {
                    Toggle("ガイドモード（移動候補をハイライト）", isOn: $guideModeEnabled)
                } header: {
                    Text("ガイド")
                } footer: {
                    // どのような効果があるかを具体的に説明し、不要ならオフにできると案内
                    Text("手札から移動できるマスを盤面上で光らせます。集中して考えたい場合はオフにできます。")
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

                // MARK: - ヘルプセクション
                Section {
                    NavigationLink {
                        // 遊び方の詳細解説をいつでも確認できるようにする
                        HowToPlayView()
                    } label: {
                        Label("遊び方を見る", systemImage: "questionmark.circle")
                    }
                } header: {
                    Text("ヘルプ")
                } footer: {
                    // プレイ中に迷った際の確認先を案内
                    Text("カードの動きや勝利条件をいつでも振り返れます。")
                }

                // MARK: - 戦績セクション
                Section {
                    Button("ベスト記録をリセット") {
                        // いきなり記録を消さず確認ダイアログを出すため、フラグだけ立てる。
                        isResetAlertPresented = true
                    }
                    // VoiceOver ユーザーにも機能が伝わるように補足ラベルを付与。
                    .accessibilityLabel(Text("ベスト記録をリセットする"))
                } header: {
                    Text("戦績")
                } footer: {
                    // ボタンの挙動を補足し、リセットの影響を明確にする。
                    Text("ベスト手数を初期状態に戻します。リセット後は新しいプレイで再び記録されます。")
                }
            }
            // 戦績リセット時に確認ダイアログを表示し、誤操作を防止する。
            .alert("ベスト記録をリセット", isPresented: $isResetAlertPresented) {
                Button("リセットする", role: .destructive) {
                    // ユーザーが確認した場合のみベスト記録を初期化する。
                    // Int.max を再代入することで「未記録」の状態に戻し、次回プレイで新たに更新される。
                    bestMoves = .max
                }
                Button("キャンセル", role: .cancel) {
                    // キャンセル時は何もしない。誤操作で記録が消えることを防ぐため。
                }
            } message: {
                // リセット理由と注意点を明確に伝えるメッセージ。
                Text("現在保存されているベスト手数を初期状態に戻します。この操作は取り消せません。")
            }
            .navigationTitle("設定")
            // - NOTE: プレビューや UI テストでは、この Picker を操作して `GameView` の `applyScenePalette` が呼び直されることを確認する想定。
        }
    }
}
