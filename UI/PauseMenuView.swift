import Game  // ゲームパッケージ内の HandOrderingStrategy などを利用するために読み込む
import SwiftUI

/// ポーズメニュー本体。プレイ画面上にゲーム内パネルとして重ねる
/// - Note: フルスクリーンカバーとして再利用できるよう、`GameView` から切り出して独立させた。
struct PauseMenuView: View {
    /// カラーテーマを共有し、背景色やボタン色を統一する
    private var theme = AppTheme()
    /// プレイ再開ボタン押下時の処理
    let onResume: () -> Void
    /// タイトルへ戻る確定時の処理
    let onConfirmReturnToTitle: () -> Void
    /// 内部テスター向け共有レポートを生成するクロージャ
    let diagnosticReportText: (() -> String)?

    /// GameView 側から利用できるようアクセスレベルを明示したカスタムイニシャライザ
    /// - Parameters:
    ///   - onResume: ポーズ解除時に実行するクロージャ
    ///   - onConfirmReturnToTitle: タイトル復帰確定時に実行するクロージャ
    init(
        onResume: @escaping () -> Void,
        onConfirmReturnToTitle: @escaping () -> Void,
        diagnosticReportText: (() -> String)? = nil
    ) {
        self.onResume = onResume
        self.onConfirmReturnToTitle = onConfirmReturnToTitle
        self.diagnosticReportText = diagnosticReportText
    }

    /// シートを閉じるための環境ディスミス
    @Environment(\.dismiss) private var dismiss
    /// 共通設定ストア
    @EnvironmentObject private var gameSettingsStore: GameSettingsStore

    /// 破壊的操作の確認用ステート
    @State private var pendingAction: PauseConfirmationAction?
    /// 設定項目の開閉状態。ポーズ時の主操作を先に見せるため初期状態は閉じる
    @State private var isSettingsExpanded = false
    /// ポーズ中に遊び方・辞典を確認するためのヘルプ表示状態
    @State private var isHelpPresented = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    header
                    primaryActions
                    settingsDisclosure
                }
                .padding(18)
                .frame(maxWidth: 420)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(theme.spawnOverlayBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(theme.spawnOverlayBorder, lineWidth: 1)
                        )
                )
                .shadow(color: theme.spawnOverlayShadow.opacity(0.86), radius: 22, x: 0, y: 12)
                .padding(.horizontal, 22)
                .padding(.vertical, 36)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(PauseMenuAccessibilityIdentifier.panel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityIdentifier(PauseMenuAccessibilityIdentifier.panel)
        .fullScreenCover(isPresented: $isHelpPresented) {
            NavigationStack {
                HowToPlayView(showsCloseButton: true)
            }
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
        case .returnToTitle:
            onConfirmReturnToTitle()
            dismiss()
        }
        pendingAction = nil
    }
}

private extension PauseMenuView {
    var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(theme.accentPrimary)
                .accessibilityHidden(true)

            Text("ポーズ")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundColor(theme.textPrimary)
                .multilineTextAlignment(.center)

            Text("休憩中です。設定は必要な時だけ開けます。")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    var primaryActions: some View {
        VStack(spacing: 10) {
            Button {
                // フルスクリーンカバーを閉じて直ちにプレイへ戻る
                onResume()
                dismiss()
            } label: {
                Label("プレイを再開", systemImage: "play.fill")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accentPrimary)
            .accessibilityIdentifier(PauseMenuAccessibilityIdentifier.resumeButton)

            Button {
                isHelpPresented = true
            } label: {
                Label("ヘルプを見る", systemImage: "questionmark.circle")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .foregroundColor(theme.textPrimary)
            .accessibilityIdentifier(PauseMenuAccessibilityIdentifier.helpButton)

            if let diagnosticReportText {
                ShareLink(item: diagnosticReportText()) {
                    Label("問題を報告", systemImage: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .foregroundColor(theme.textPrimary)
                .accessibilityIdentifier(PauseMenuAccessibilityIdentifier.reportIssueButton)
            }

            Button {
                pendingAction = .returnToTitle
            } label: {
                Label("タイトルへ戻る", systemImage: "house")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .foregroundColor(theme.textPrimary)
            .accessibilityIdentifier(PauseMenuAccessibilityIdentifier.returnToTitleButton)
        }
    }

    var settingsDisclosure: some View {
        DisclosureGroup(isExpanded: $isSettingsExpanded) {
            settingsContent
                .padding(.top, 12)
        } label: {
            Label("ゲーム設定", systemImage: "slider.horizontal.3")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(theme.textPrimary)
        }
        .tint(theme.accentPrimary)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.backgroundElevated.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.spawnOverlayBorder.opacity(0.82), lineWidth: 1)
        )
        .accessibilityIdentifier(PauseMenuAccessibilityIdentifier.settingsDisclosure)
    }

    var settingsContent: some View {
        VStack(spacing: 12) {
            settingsPicker(
                title: "テーマ",
                selection: Binding<ThemePreference>(
                    get: { gameSettingsStore.preferredColorScheme },
                    set: { gameSettingsStore.preferredColorScheme = $0 }
                ),
                options: ThemePreference.allCases,
                displayName: \.displayName
            )

            settingsToggle(
                title: "ハプティクス",
                subtitle: "操作時の反応",
                isOn: $gameSettingsStore.hapticsEnabled
            )

            settingsToggle(
                title: "ガイドモード",
                subtitle: "移動候補をハイライト",
                isOn: $gameSettingsStore.guideModeEnabled
            )

            settingsPicker(
                title: "手札の並び順",
                selection: Binding<HandOrderingStrategy>(
                    get: { gameSettingsStore.handOrderingStrategy },
                    set: { gameSettingsStore.handOrderingStrategy = $0 }
                ),
                options: HandOrderingStrategy.allCases,
                displayName: \.displayName
            )
        }
    }

    func settingsToggle(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            settingText(title: title, subtitle: subtitle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 14, weight: .semibold, design: .rounded))
        .tint(theme.accentPrimary)
    }

    func settingsPicker<Value: Hashable>(
        title: String,
        selection: Binding<Value>,
        options: [Value],
        displayName: KeyPath<Value, String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            settingText(title: title, subtitle: nil)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer(minLength: 0)

                Picker(title, selection: selection) {
                    ForEach(options, id: \.self) { option in
                        Text(option[keyPath: displayName])
                            .tag(option)
                    }
                }
                .pickerStyle(.menu)
                .tint(theme.accentPrimary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func settingText(title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// ポーズメニュー内で扱う確認対象の列挙体
    enum PauseConfirmationAction: Identifiable {
        case returnToTitle

        var id: Int {
            switch self {
            case .returnToTitle: return 0
            }
        }

        var confirmationButtonTitle: String {
            switch self {
            case .returnToTitle: return "タイトルへ戻る"
            }
        }

        var message: String {
            switch self {
            case .returnToTitle:
                return "ゲームを中断してタイトル画面へ戻ります。塔攻略中は続きから再開できます。"
            }
        }
    }
}

enum PauseMenuAccessibilityIdentifier {
    static let panel = "pause_menu_panel"
    static let resumeButton = "pause_resume_button"
    static let helpButton = "pause_help_button"
    static let reportIssueButton = "pause_report_issue_button"
    static let returnToTitleButton = "pause_return_to_title_button"
    static let settingsDisclosure = "pause_settings_disclosure"
}
