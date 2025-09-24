import Game  // 手札並び順の設定列挙体を利用するために追加
import StoreKit
import SwiftUI

struct SettingsView: View {
    // MARK: - プレゼンテーション制御
    // フルスクリーンカバーで表示された設定画面を明示的に閉じられるよう、dismiss アクションを取得しておく。
    @Environment(\.dismiss) private var dismiss

    // MARK: - ストア連携
    // 広告除去 IAP の購入／復元状態を UI に反映するため、環境オブジェクトとして渡された Store サービスを監視する。
    @EnvironmentObject private var storeService: AnyStoreService

    // 購入ボタンを複数回タップできないようにするための進行状況フラグ。
    @State private var isPurchaseInProgress = false

    // 復元処理の重複実行を避けるためのフラグ。
    @State private var isRestoreInProgress = false

    // ストア処理の完了通知をアラートで表示するための状態。
    @State private var storeAlert: StoreAlert?

    // MARK: - テーマ設定
    // ユーザーが任意に選択したカラースキームを保持する。初期値はシステム依存の `.system`。
    @AppStorage("preferred_color_scheme") private var preferredColorSchemeRawValue: String = ThemePreference.system.rawValue

    // MARK: - ハプティクス設定
    // ユーザーのハプティクス利用有無を永続化する。デフォルトは有効。
    @AppStorage("haptics_enabled") private var hapticsEnabled: Bool = true

    // MARK: - ガイドモード設定
    // 盤面の移動候補ハイライトを保存し、GameView 側の @AppStorage と連動させる。
    @AppStorage("guide_mode_enabled") private var guideModeEnabled: Bool = true

    // MARK: - 手札並び設定
    // 手札の並び替え方式を永続化し、GameView 側の @AppStorage と同期させる。
    @AppStorage(HandOrderingStrategy.storageKey) private var handOrderingRawValue: String = HandOrderingStrategy.insertionOrder.rawValue

    // MARK: - 戦績管理
    // ベストポイントを UserDefaults から取得・更新する。未設定時は Int.max で初期化しておく。
    @AppStorage("best_points_5x5") private var bestPoints: Int = .max

    // 戦績リセット確認用のアラート表示フラグ。ユーザーが誤操作しないよう明示的に確認する。
    @State private var isResetAlertPresented = false

    // MARK: - 定義
    // ストア関連の通知内容をまとめ、`Identifiable` 化して SwiftUI の `.alert(item:)` に乗せる。
    private enum StoreAlert: Identifiable {
        case purchaseCompleted
        case restoreFinished
        case restoreFailed

        var id: String {
            switch self {
            case .purchaseCompleted:
                return "purchaseCompleted"
            case .restoreFinished:
                return "restoreFinished"
            case .restoreFailed:
                return "restoreFailed"
            }
        }

        var title: String {
            switch self {
            case .purchaseCompleted:
                return "広告除去を適用しました"
            case .restoreFinished:
                return "購入内容を確認しました"
            case .restoreFailed:
                return "復元に失敗しました"
            }
        }

        var message: String {
            switch self {
            case .purchaseCompleted:
                return "広告の表示が無効化されました。アプリを再起動する必要はありません。"
            case .restoreFinished:
                return "App Store と同期しました。購入済みの場合は自動で広告除去が反映されます。"
            case .restoreFailed:
                return "通信状況や Apple ID を確認のうえ、時間を置いて再度お試しください。"
            }
        }
    }

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

                // 手札の並び順を切り替える設定セクション
                Section {
                    Picker("手札の並び順", selection: Binding<HandOrderingStrategy>(
                        get: { HandOrderingStrategy(rawValue: handOrderingRawValue) ?? .insertionOrder },
                        set: { handOrderingRawValue = $0.rawValue }
                    )) {
                        ForEach(HandOrderingStrategy.allCases, id: \.self) { strategy in
                            Text(strategy.displayName)
                                .tag(strategy)
                        }
                    }
                } header: {
                    Text("手札の並び")
                } footer: {
                    // 並び替えロジックの違いを具体的に示し、意図した使い分けができるよう説明する
                    Text("""
手札を引いた順番のまま維持するか、移動方向に応じて自動整列するかを選べます。方向ソートでは左への移動量が大きいカードが左側に、同じ左右移動量なら上方向のカードが優先されます。
""")
                }

                // MARK: - 広告除去 IAP セクション
                Section {
                    if storeService.isRemoveAdsPurchased {
                        // すでに広告除去が有効な場合は、状態が維持されていることを明確に示す
                        Label {
                            Text("広告は現在表示されません")
                        } icon: {
                            Image(systemName: "checkmark.seal.fill")
                        }
                        .accessibilityLabel(Text("広告除去が適用済みです"))
                    } else {
                        Button {
                            guard !isPurchaseInProgress else { return }
                            isPurchaseInProgress = true
                            Task {
                                // 商品情報が未取得の場合は先にリクエストをやり直す
                                if storeService.removeAdsPriceText == nil {
                                    await storeService.refreshProducts()
                                }
                                await storeService.purchaseRemoveAds()
                                await MainActor.run {
                                    isPurchaseInProgress = false
                                }
                            }
                        } label: {
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

                    Button {
                        guard !isRestoreInProgress else { return }
                        isRestoreInProgress = true
                        Task {
                            let success = await storeService.restorePurchases()
                            await MainActor.run {
                                isRestoreInProgress = false
                                storeAlert = success ? .restoreFinished : .restoreFailed
                            }
                        }
                    } label: {
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
                    // 購入と復元の使い分けを案内し、トラブルシューティング先を示す
                    Text("広告を非表示にする購入手続きや、機種変更時の復元が行えます。購入内容は Apple ID に紐づくため、別の端末でも同じアカウントで復元できます。")
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
                    Text("カードの動きや勝利条件に加えて、手札スロットが最大 \(GameMode.standard.handSize) 種類で\(GameMode.standard.stackingRuleDetailText)という仕様も確認できます。")
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
                    Text("ベストポイントを初期状態に戻します。リセット後は新しいプレイで再び記録されます。")
                }
            }
            // 戦績リセット時に確認ダイアログを表示し、誤操作を防止する。
            .alert("ベスト記録をリセット", isPresented: $isResetAlertPresented) {
                Button("リセットする", role: .destructive) {
                    // ユーザーが確認した場合のみベスト記録を初期化する。
                    // Int.max を再代入することで「未記録」の状態に戻し、次回プレイで新たに更新される。
                    bestPoints = .max
                }
                Button("キャンセル", role: .cancel) {
                    // キャンセル時は何もしない。誤操作で記録が消えることを防ぐため。
                }
            } message: {
                // リセット理由と注意点を明確に伝えるメッセージ。
                Text("現在保存されているベストポイントを初期状態に戻します。この操作は取り消せません。")
            }
            .navigationTitle("設定")
            // 画面右上に閉じるボタンを設置し、スワイプに頼らず片手でも素早く閉じられるようにする。
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Label("閉じる", systemImage: "xmark")
                    }
                    // 音声読み上げでも役割が伝わるようにアクセシビリティラベルを補強する。
                    .accessibilityLabel(Text("設定画面を閉じる"))
                }
            }
            // - NOTE: プレビューや UI テストでは、この Picker を操作して `GameView` の `applyScenePalette` が呼び直されることを確認する想定。
            // 購入状態の遷移を旧値と新値の両方から判定し、false→true の変化だけを検出する
            .onChange(of: storeService.isRemoveAdsPurchased) { oldValue, newValue in
                // 直前まで未購入で、今回の更新で初めて購入済みになったタイミングのみアラートを掲示する
                if !oldValue && newValue {
                    storeAlert = .purchaseCompleted
                }
            }
        }
        // ストア処理の成否をまとめて通知し、ユーザーに完了状況を伝える
        .alert(item: $storeAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}
