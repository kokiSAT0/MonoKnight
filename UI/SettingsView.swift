import Game  // 手札並び順の設定列挙体を利用するために追加
import SharedSupport  // DebugLogHistory など診断用ユーティリティを参照するために追加
import StoreKit
import SwiftUI

// MainActor 上で動作させ、AdsServiceProtocol のメソッド呼び出しが常にメインスレッドで完結するよう明示する
@MainActor
struct SettingsView: View {
    // MARK: - サービス依存性
    // AdsServiceProtocol を直接受け取り、UI テストやプレビューでもモックへ差し替えやすくする。
    // これにより SettingsView 内で `AdsService.shared` を参照する必要がなくなり、
    // 共有インスタンスの実装差し替えに伴うビルドエラーを防止する。
    private let adsService: AdsServiceProtocol
    // Game Center 認証を制御するサービス。設定画面からも直接サインインを呼び出せるようプロトコル越しに保持する。
    private let gameCenterService: GameCenterServiceProtocol
    // MARK: - プレゼンテーション制御
    // フルスクリーンカバーで表示された設定画面を明示的に閉じられるよう、dismiss アクションを取得しておく。
    @Environment(\.dismiss) private var dismiss

    // MARK: - ストア連携
    // 広告除去 IAP の購入／復元状態を UI に反映するため、環境オブジェクトとして渡された Store サービスを監視する。
    @EnvironmentObject private var storeService: AnyStoreService

    // キャンペーンモードの進捗を共有し、デバッグ用パスコード入力で全ステージ解放フラグを更新できるようにする。
    @EnvironmentObject private var campaignProgressStore: CampaignProgressStore

    // 日替わりチャレンジの挑戦回数ストアを共有し、デバッグ無制限モードの切り替えにも対応する。
    @EnvironmentObject private var dailyChallengeAttemptStore: AnyDailyChallengeAttemptStore

    // デバッグ解放や無制限モードのいずれかが有効かをまとめて判定するヘルパー。
    // - Note: テキストフィールドを無効化する条件やガード節で共通利用し、解除後に再入力できる状態を保証する。
    private var isDebugOverrideActive: Bool {
        campaignProgressStore.isDebugUnlockEnabled || dailyChallengeAttemptStore.isDebugUnlimitedEnabled
    }

    // 購入ボタンを複数回タップできないようにするための進行状況フラグ。
    @State private var isPurchaseInProgress = false

    // 復元処理の重複実行を避けるためのフラグ。
    @State private var isRestoreInProgress = false

    // ストア処理の完了通知をアラートで表示するための状態。
    @State private var storeAlert: StoreAlert?

    // デバッグ用パスコード入力欄の値を保持する。
    @State private var debugUnlockInput: String = ""

    // 正しいパスコード入力時に確認アラートを表示するためのフラグ。
    @State private var isDebugUnlockSuccessAlertPresented = false

    // デバッグ用パスコードを定義し、値の変更箇所を 1 箇所に集約する。
    private static let debugUnlockPassword = "6031"

    // MARK: - Game Center 連携
    // 設定画面から認証状態を更新するためのバインディング。RootView 側と状態を双方向で同期する。
    @Binding private var isGameCenterAuthenticated: Bool
    // 認証処理が進行中かどうかを管理し、ボタンの連打や二重実行を防ぐ。
    @State private var isGameCenterAuthenticationInProgress = false
    // 認証完了後にユーザーへ結果を案内するためのアラート種別。
    @State private var gameCenterAlert: GameCenterAlert?

    // MARK: - 初期化
    // AdsServiceProtocol を外部から注入できるようにし、未指定の場合はシングルトンを採用する。
    // - Parameter adsService: 広告同意フローや同意状態の再取得を扱うサービス。
    init(
        adsService: AdsServiceProtocol? = nil,
        gameCenterService: GameCenterServiceProtocol? = nil,
        isGameCenterAuthenticated: Binding<Bool> = .constant(false)
    ) {
        // Swift 6 ではデフォルト引数が非分離コンテキストで評価されるため、
        // MainActor 上で安全にシングルトンへアクセスできるようイニシャライザ本体で解決する。
        self.adsService = adsService ?? AdsService.shared
        self.gameCenterService = gameCenterService ?? GameCenterService.shared
        self._isGameCenterAuthenticated = isGameCenterAuthenticated
    }

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

    // MARK: - 開発者向け診断メニュー
    // DebugLogHistory.shared のフラグに応じて設定画面へ開発者向け導線を表示するかどうかを判断する。
    private var isDiagnosticsMenuAvailable: Bool {
        DebugLogHistory.shared.isFrontEndViewerEnabled
    }

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

    // Game Center 認証の成否を通知するためのアラート定義。
    private enum GameCenterAlert: Identifiable {
        case success
        case failure

        var id: String {
            switch self {
            case .success:
                return "gc_success"
            case .failure:
                return "gc_failure"
            }
        }

        var title: String { "Game Center" }

        var message: String {
            switch self {
            case .success:
                return "Game Center へのサインインが完了しました。ランキングとスコア送信が利用可能です。"
            case .failure:
                return "サインインに失敗しました。通信環境を確認し、時間を置いて再度お試しください。"
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: Game Center 認証セクション
                Section {
                    // 現在の認証状態をひと目で分かるようアイコン付きで表示する。
                    Label {
                        Text(isGameCenterAuthenticated ? "サインイン済み" : "未サインイン")
                            .font(.headline)
                    } icon: {
                        Image(systemName: isGameCenterAuthenticated ? "checkmark.circle.fill" : "person.crop.circle.badge.exclamationmark")
                    }
                    .foregroundStyle(isGameCenterAuthenticated ? .green : .orange)
                    .accessibilityIdentifier("settings_gc_status_label")

                    Button {
                        guard !isGameCenterAuthenticationInProgress else { return }
                        isGameCenterAuthenticationInProgress = true
                        // Game Center へのサインインを実行し、完了時にバインディングへ結果を反映する。
                        gameCenterService.authenticateLocalPlayer { success in
                            Task { @MainActor in
                                isGameCenterAuthenticationInProgress = false
                                isGameCenterAuthenticated = success
                                gameCenterAlert = success ? .success : .failure
                            }
                        }
                    } label: {
                        HStack {
                            Text(isGameCenterAuthenticated ? "状態を再確認" : "Game Center にサインイン")
                            Spacer()
                            if isGameCenterAuthenticationInProgress {
                                ProgressView()
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isGameCenterAuthenticationInProgress)
                    .accessibilityIdentifier("settings_gc_sign_in_button")
                } header: {
                    Text("Game Center")
                } footer: {
                    // サインインの目的を明確に伝え、ランキング利用に直結することを説明する。
                    Text("ランキング表示やスコア送信を行うには Game Center へのサインインが必要です。サインイン済みの場合は結果画面から自動で送信されます。")
                }

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
                        // AdsServiceProtocol へ委譲し、広告同意状態の再取得をテストでも再現しやすくする。
                        Task { await adsService.refreshConsentStatus() }
                    }
                    Button("同意取得フローをやり直す") {
                        Task {
                            // ATT と UMP の順番を維持しつつ、注入したサービスを通じて処理する。
                            await adsService.requestTrackingAuthorization()
                            await adsService.requestConsentIfNeeded()
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

                // MARK: - デバッグ用パスコードセクション
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        // 数字以外の入力を取り除き、桁数を固定することで誤入力を防ぎやすくする。
                        TextField("デバッグ用パスコード", text: $debugUnlockInput)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .disabled(isDebugOverrideActive)
                            .onChange(of: debugUnlockInput) { _, newValue in
                                handleDebugUnlockInputChange(newValue)
                            }
                        if campaignProgressStore.isDebugUnlockEnabled {
                            // 有効化後の状態を明示し、解除ボタンを案内する。
                            Label("全てのステージが解放されています（無効化ボタンから解除可能）", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                        } else {
                            Text("社内検証で必要な場合のみ入力してください。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        if dailyChallengeAttemptStore.isDebugUnlimitedEnabled {
                            // 日替わりチャレンジの無制限モードが有効であることを通知し、広告視聴が不要な旨を共有する。
                            Label("デイリーチャレンジは無制限モードです", systemImage: "infinity")
                                .foregroundStyle(.blue)
                                .font(.subheadline)
                            Text("デバッグ検証中は挑戦回数の消費と広告視聴がスキップされます。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        if isDebugOverrideActive {
                            // 解除操作を即座に行えるよう、ボタンを併設する。
                            Button {
                                // ステージ解放と挑戦回数のデバッグモードを同時に無効化し、通常プレイへ戻す。
                                campaignProgressStore.disableDebugUnlock()
                                dailyChallengeAttemptStore.disableDebugUnlimited()
                            } label: {
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
                    // 入力による影響範囲を明確に伝え、誤用を避ける。
                    Text("正しいパスコードを入力するとキャンペーンモードの全ステージが解放されます。アプリを再起動しても維持されます。")
                }

                if isDiagnosticsMenuAvailable {
                    // MARK: - 開発者向け診断セクション
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
            // 設定画面表示中でも `@AppStorage` の更新に合わせてカラースキームを反映させ、閉じる操作を待たずにテーマ変更が視覚化されるようにする。
            .preferredColorScheme(
                ThemePreference(rawValue: preferredColorSchemeRawValue)?.preferredColorScheme
            )
        }
        // デバッグ用パスコード入力成功時に状態を明示するアラートを表示し、検証モードへの切り替えを周知する。
        .alert("全ステージを解放しました", isPresented: $isDebugUnlockSuccessAlertPresented) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("キャンペーンモードの検証用として全てのステージが解放された状態になりました。")
        }
        // Game Center 認証の完了状況をアラートで案内し、ユーザーに結果をフィードバックする。
        .alert(item: $gameCenterAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
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

// MARK: - デバッグ用パスコード処理
private extension SettingsView {
    /// パスコード入力の変化を監視し、正しい値が揃ったときに全ステージ解放フラグを更新する
    /// - Parameter newValue: 入力欄へ反映された最新の文字列
    func handleDebugUnlockInputChange(_ newValue: String) {
        // 入力中に数字以外の文字が含まれた場合は除去し、指定桁数までに制限する
        let digitsOnly = newValue.filter { $0.isNumber }
        let trimmed = String(digitsOnly.prefix(Self.debugUnlockPassword.count))

        // 加工後の値と入力欄の内容が異なる場合はフィールドを更新して処理を終える
        if trimmed != newValue {
            debugUnlockInput = trimmed
            return
        }

        // 既にデバッグモードがアクティブな場合は解除操作を促し、誤入力を防ぐ
        guard !isDebugOverrideActive else {
            debugUnlockInput = ""
            return
        }

        // 桁数が揃うまでは判定を待ち、途中入力での誤作動を防ぐ
        guard trimmed.count == Self.debugUnlockPassword.count else { return }

        if trimmed == Self.debugUnlockPassword {
            // 正しいパスコード入力時は進捗ストアへ通知して永続化し、アラートで完了を知らせる
            campaignProgressStore.enableDebugUnlock()
            // デイリーチャレンジの挑戦回数もデバッグモードへ切り替え、検証を効率化する
            dailyChallengeAttemptStore.enableDebugUnlimited()
            debugUnlockInput = ""
            isDebugUnlockSuccessAlertPresented = true
        } else {
            // 誤入力時はフィールドをクリアし、再入力を促す
            debugUnlockInput = ""
        }
    }
}
