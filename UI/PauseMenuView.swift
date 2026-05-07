import SwiftUI
import Game  // ゲームパッケージ内の HandOrderingStrategy などを利用するために読み込む

/// ポーズメニュー本体。プレイ中によく調整する項目をリスト形式でまとめる
/// - Note: フルスクリーンカバーとして再利用できるよう、`GameView` から切り出して独立させた。
struct PauseMenuView: View {
    /// カラーテーマを共有し、背景色やボタン色を統一する
    private var theme = AppTheme()
    /// ポーズメニューに並べるペナルティ説明文の一覧
    let penaltyItems: [String]
    /// プレイ再開ボタン押下時の処理
    let onResume: () -> Void
    /// リセット確定時の処理
    let onConfirmReset: () -> Void
    /// タイトルへ戻る確定時の処理
    let onConfirmReturnToTitle: () -> Void

    /// GameView 側から利用できるようアクセスレベルを明示したカスタムイニシャライザ
    /// - Parameters:
    ///   - onResume: ポーズ解除時に実行するクロージャ
    ///   - onConfirmReset: ゲームリセット確定時に実行するクロージャ
    ///   - onConfirmReturnToTitle: タイトル復帰確定時に実行するクロージャ
    init(
        penaltyItems: [String] = [],
        onResume: @escaping () -> Void,
        onConfirmReset: @escaping () -> Void,
        onConfirmReturnToTitle: @escaping () -> Void
    ) {
        self.penaltyItems = penaltyItems
        self.onResume = onResume
        self.onConfirmReset = onConfirmReset
        self.onConfirmReturnToTitle = onConfirmReturnToTitle
    }

    /// シートを閉じるための環境ディスミス
    @Environment(\.dismiss) private var dismiss
    /// 共通設定ストア
    @EnvironmentObject private var gameSettingsStore: GameSettingsStore

    /// 破壊的操作の確認用ステート
    @State private var pendingAction: PauseConfirmationAction?

    var body: some View {
        NavigationStack {
            List {
                // MARK: - ペナルティ一覧
                if !penaltyItems.isEmpty {
                    Section {
                        ForEach(penaltyItems, id: \.self) { item in
                            Text(item)
                                .accessibilityLabel(Text("ペナルティ項目: \(item)"))
                        }
                    } header: {
                        Text("ペナルティ")
                    }
                }
                // MARK: - プレイ再開ボタン
                Section {
                    Button {
                        // フルスクリーンカバーを閉じて直ちにプレイへ戻る
                        onResume()
                        dismiss()
                    } label: {
                        Label("プレイを再開", systemImage: "play.fill")
                    }
                    .accessibilityHint("ポーズを解除してゲームを続けます")
                }

                // MARK: - 操作セクション
                Section {
                    Button(role: .destructive) {
                        pendingAction = .reset
                    } label: {
                        Label("ゲームをリセット", systemImage: "arrow.counterclockwise")
                    }

                    Button(role: .destructive) {
                        pendingAction = .returnToTitle
                    } label: {
                        Label("タイトルへ戻る", systemImage: "house")
                    }
                } header: {
                    Text("操作")
                } footer: {
                    Text("リセットやタイトル復帰は確認ダイアログを経由して実行します。")
                }

                // MARK: - ゲーム設定セクション
                Section {
                    Picker(
                        "テーマ",
                        selection: Binding<ThemePreference>(
                            get: { gameSettingsStore.preferredColorScheme },
                            set: { gameSettingsStore.preferredColorScheme = $0 }
                        )
                    ) {
                        ForEach(ThemePreference.allCases) { preference in
                            Text(preference.displayName)
                                .tag(preference)
                        }
                    }

                    Toggle("ハプティクスを有効にする", isOn: $gameSettingsStore.hapticsEnabled)
                    Toggle("ガイドモード（移動候補をハイライト）", isOn: $gameSettingsStore.guideModeEnabled)

                    Picker(
                        "手札の並び順",
                        selection: Binding<HandOrderingStrategy>(
                            get: { gameSettingsStore.handOrderingStrategy },
                            set: { gameSettingsStore.handOrderingStrategy = $0 }
                        )
                    ) {
                        ForEach(HandOrderingStrategy.allCases, id: \.self) { strategy in
                            Text(strategy.displayName)
                                .tag(strategy)
                        }
                    }
                } header: {
                    Text("ゲーム設定")
                } footer: {
                    Text("テーマやハプティクス、ガイド表示を素早く切り替えられます。これらの項目はタイトル画面の設定からも調整できます。")
                }

                // MARK: - 詳細設定についての案内
                Section {
                    Text("広告やプライバシー設定などの詳細はタイトル画面右上のギアアイコンから確認できます。")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } header: {
                    Text("詳細設定")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("ポーズ")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        onResume()
                        dismiss()
                    }
                }
            }
            .background(theme.backgroundPrimary)
        }
        // 破壊的操作の確認ダイアログ
        .confirmationDialog(
            "操作の確認",
            // item: バインディングが iOS 17 以降で非推奨となったため、
            // Bool バインディング + presenting の組み合わせで明示的に制御する
            isPresented: Binding(
                get: {
                    // pendingAction が存在する場合のみダイアログを表示
                    pendingAction != nil
                },
                set: { isPresented in
                    // ユーザー操作でダイアログが閉じられたら状態を初期化
                    if !isPresented {
                        pendingAction = nil
                    }
                }
            ),
            presenting: pendingAction
        ) { action in
            // 確認用の破壊的操作ボタン
            Button(action.confirmationButtonTitle, role: .destructive) {
                handleConfirmation(action)
            }
            // キャンセルボタンは常に閉じるだけで状態を破棄
            Button("キャンセル", role: .cancel) {
                pendingAction = nil
            }
        } message: { action in
            Text(action.message)
        }
    }

    /// 確認ダイアログで選ばれたアクションを実行する
    /// - Parameter action: ユーザーが確定した操作種別
    private func handleConfirmation(_ action: PauseConfirmationAction) {
        switch action {
        case .reset:
            onConfirmReset()
            dismiss()
        case .returnToTitle:
            onConfirmReturnToTitle()
            dismiss()
        }
        pendingAction = nil
    }
}

private extension PauseMenuView {
    /// ポーズメニュー内で扱う確認対象の列挙体
    enum PauseConfirmationAction: Identifiable {
        case reset
        case returnToTitle

        var id: Int {
            switch self {
            case .reset: return 0
            case .returnToTitle: return 1
            }
        }

        var confirmationButtonTitle: String {
            switch self {
            case .reset: return "リセットする"
            case .returnToTitle: return "タイトルへ戻る"
            }
        }

        var message: String {
            switch self {
            case .reset:
                return "現在の進行状況を破棄して最初からやり直します。よろしいですか？"
            case .returnToTitle:
                return "ゲームを中断してタイトル画面へ戻ります。塔攻略中は続きから再開できます。"
            }
        }
    }
}
