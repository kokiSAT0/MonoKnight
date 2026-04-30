import SwiftUI
import Game

/// ハイスコアチャレンジで挑戦できるモードを一覧表示する画面
/// タイトル画面から遷移し、各カードをタップするとゲーム開始用のクロージャが呼び出される
struct HighScoreChallengeSelectionView: View {
    /// 選択されたモードをタイトル画面へ引き渡すクロージャ
    /// - Note: triggerImmediateStart を呼び出す側から受け取る
    let onSelect: (GameMode) -> Void
    /// ナビゲーションスタックを戻すためのクロージャ
    let onClose: () -> Void
    /// スタンダードモードのベストスコアを案内する文字列
    let bestScoreDescription: String

    /// 共通の配色を扱うテーマ
    private let theme = AppTheme()
    @StateObject private var targetLabSettingsStore = TargetLabExperimentSettingsStore()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// 画面表示に必要な依存関係を受け取りプロパティへ格納する
    /// - Parameters:
    ///   - onSelect: モード選択時にタイトル画面へ通知するクロージャ
    ///   - onClose: ナビゲーションを戻すためのクロージャ
    ///   - bestScoreDescription: 直近のベストスコアを案内する文字列
    init(
        onSelect: @escaping (GameMode) -> Void,
        onClose: @escaping () -> Void,
        bestScoreDescription: String
    ) {
        // 外部から渡された依存関係をそのまま保持して画面内で利用する
        self.onSelect = onSelect
        self.onClose = onClose
        self.bestScoreDescription = bestScoreDescription
    }

    /// 画面に表示するカード情報の配列
    private var modeCards: [ModeCardData] {
        [
            ModeCardData(
                mode: .standard,
                headline: "スタンダード",
                rewardSummary: "Game Center ランキングの基本カテゴリでスコアを競えます。",
                ruleSummary: "5×5 盤・中央開始・目的地12個でクリア。フォーカスで目的地へ近づくカードを引き寄せ、移動手数・時間・フォーカス回数でスコアを競います。",
                difficultyLabel: "難易度: ノーマル",
                accessibilityIdentifier: "high_score_mode_standard"
            ),
            ModeCardData(
                mode: .targetLab,
                headline: "カード・特殊マス実験場",
                rewardSummary: "ランキング対象外の実験枠です。カードと特殊マス調整のため、Game Center には送信されません。",
                ruleSummary: "8×8 盤・開始位置選択可・目的地20個でクリア。全部入りカードと全種類の特殊マスを1個ずつ試せます。",
                difficultyLabel: "実験",
                accessibilityIdentifier: "high_score_mode_target_lab"
            ),
            ModeCardData(
                mode: .classicalChallenge,
                headline: "クラシカルチャレンジ",
                rewardSummary: "大盤での踏破を目指す上級者向けチャレンジです。ランキングでも差をつけやすい高難度カテゴリです。",
                ruleSummary: "8×8 盤・開始位置選択可。再訪ペナルティや手詰まりコストが軽めで、粘り強いルート構築が求められます。",
                difficultyLabel: "難易度: ハード",
                accessibilityIdentifier: "high_score_mode_classical"
            ),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                introductionSection
                modeListSection
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 28)
            .frame(maxWidth: contentMaxWidth)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(theme.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("ハイスコア")
        .navigationBarTitleDisplayMode(.inline)
        // 標準の戻るボタンを非表示にして、ツールバーの戻る導線へ挙動を統一する
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                backButton
            }
        }
        .accessibilityIdentifier("high_score_selection_view")
    }

    /// 画面冒頭に表示する案内文セクション
    private var introductionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // ハイスコアチャレンジの趣旨を説明するテキスト
            Text("お気に入りのモードでハイスコアを伸ばし、Game Center のランキングに挑戦しましょう。")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            // 現在のベストスコアを共有してモチベーションにつなげる
            Text(bestScoreDescription)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(theme.textPrimary)
        }
    }

    /// モード一覧をカード形式で並べるセクション
    private var modeListSection: some View {
        VStack(spacing: 20) {
            ForEach(modeCards) { card in
                modeCardButton(for: card)
            }
        }
    }

    /// 個々のモードカードをボタンとして構築する
    @ViewBuilder
    private func modeCardButton(for data: ModeCardData) -> some View {
        if data.mode.identifier == .targetLab {
            targetLabModeCard(for: data)
        } else {
            Button {
            // タップされたモードをタイトル画面へ返し、即時開始のトリガーへつなげる
                onSelect(data.mode)
            } label: {
                modeCardContent(for: data)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(data.accessibilityIdentifier)
        }
    }

    private func modeCardContent(for data: ModeCardData) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            headerRow(for: data)
            rewardRow(for: data)
            Divider()
                .overlay(theme.textSecondary.opacity(0.2))
            ruleSummaryRow(for: data)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(theme.backgroundElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(theme.accentPrimary.opacity(0.2), lineWidth: 1)
        )
    }

    private func targetLabModeCard(for data: ModeCardData) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            headerRow(for: data)
            rewardRow(for: data)
            Divider()
                .overlay(theme.textSecondary.opacity(0.2))
            ruleSummaryRow(for: data)
            targetLabSettingsSection
            targetLabStartButton
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(theme.backgroundElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(theme.accentPrimary.opacity(0.2), lineWidth: 1)
        )
        .accessibilityIdentifier(data.accessibilityIdentifier)
    }

    private var targetLabSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("実験設定")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(theme.textSecondary)

            presetRow
            toggleGrid(
                title: "カード種類",
                items: TargetLabCardGroup.allCases,
                isOn: { targetLabSettingsStore.settings.enabledCardGroups.contains($0) },
                toggle: { targetLabSettingsStore.toggleCardGroup($0) }
            )
            toggleGrid(
                title: "特殊マス",
                items: TargetLabTileKind.allCases,
                isOn: { targetLabSettingsStore.settings.enabledTileKinds.contains($0) },
                toggle: { targetLabSettingsStore.toggleTileKind($0) }
            )

            if !targetLabSettingsStore.settings.hasPlayableCards {
                Text("カード種類を1つ以上有効にしてください")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.red)
            }
        }
    }

    private var presetRow: some View {
        HStack(spacing: 8) {
            ForEach(TargetLabSettingsPreset.allCases) { preset in
                Button(preset.displayName) {
                    targetLabSettingsStore.applyPreset(preset)
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(theme.accentPrimary)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(
                    Capsule(style: .continuous)
                        .stroke(theme.accentPrimary.opacity(0.55), lineWidth: 1)
                )
                .buttonStyle(.plain)
            }
        }
    }

    private func toggleGrid<Item: CaseIterable & Hashable>(
        title: String,
        items: Item.AllCases,
        isOn: @escaping (Item) -> Bool,
        toggle: @escaping (Item) -> Void
    ) -> some View where Item.AllCases: RandomAccessCollection {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(theme.textSecondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(Array(items), id: \.self) { item in
                    Toggle(isOn: Binding(
                        get: { isOn(item) },
                        set: { _ in toggle(item) }
                    )) {
                        Text(itemDisplayName(item))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(theme.textPrimary)
                    }
                    .toggleStyle(.switch)
                }
            }
        }
    }

    private func itemDisplayName<Item>(_ item: Item) -> String {
        if let group = item as? TargetLabCardGroup {
            return group.displayName
        }
        if let tile = item as? TargetLabTileKind {
            return tile.displayName
        }
        return String(describing: item)
    }

    private var targetLabStartButton: some View {
        Button {
            guard targetLabSettingsStore.settings.hasPlayableCards else { return }
            onSelect(.targetLab(settings: targetLabSettingsStore.settings))
        } label: {
            Text("この設定で開始")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(theme.accentOnPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(theme.accentPrimary.opacity(targetLabSettingsStore.settings.hasPlayableCards ? 1 : 0.35))
                )
        }
        .buttonStyle(.plain)
        .disabled(!targetLabSettingsStore.settings.hasPlayableCards)
        .accessibilityIdentifier("target_lab_start_button")
    }

    /// カード上部の見出しと難易度バッジを表示する行
    private func headerRow(for data: ModeCardData) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // モード名を太字で表現してカードの主題を明確にする
            Text(data.headline)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(theme.textPrimary)
            Spacer(minLength: 12)
            // 難易度をカプセル表示にして直感的に認識できるようにする
            Text(data.difficultyLabel)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(theme.accentOnPrimary)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(
                    Capsule(style: .continuous)
                        .fill(theme.accentPrimary)
                )
                .accessibilityLabel("難易度ラベル: \(data.difficultyLabel)")
        }
    }

    /// リワード（報酬）に関する要約を表示する行
    private func rewardRow(for data: ModeCardData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // セクション見出しを小さめのフォントで添える
            Text("リワード")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(theme.textSecondary)
            // 実際の説明テキストは読みやすいサイズで記載
            Text(data.rewardSummary)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundColor(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// ルールの要点を説明する行
    private func ruleSummaryRow(for data: ModeCardData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // ルールセクションの見出し
            Text("ルール概要")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(theme.textSecondary)
            // ルールの要約文を複数行で丁寧に説明
            Text(data.ruleSummary)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundColor(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 戻る導線となるツールバーのボタン
    private var backButton: some View {
        Button {
            // ナビゲーションスタックを 1 つ戻してタイトル画面へ戻る
            onClose()
        } label: {
            Label("戻る", systemImage: "chevron.backward")
                .font(.system(size: 15, weight: .medium, design: .rounded))
        }
        .accessibilityIdentifier("high_score_selection_back_button")
    }

    private var contentMaxWidth: CGFloat? {
        horizontalSizeClass == .regular ? 760 : nil
    }

    private var horizontalPadding: CGFloat {
        horizontalSizeClass == .regular ? 32 : 24
    }
}

// MARK: - 補助データモデル

private struct ModeCardData: Identifiable {
    let mode: GameMode
    let headline: String
    let rewardSummary: String
    let ruleSummary: String
    let difficultyLabel: String
    let accessibilityIdentifier: String

    var id: GameMode.Identifier { mode.identifier }
}

enum TargetLabSettingsPreset: String, CaseIterable, Identifiable {
    case allIn
    case cardsOnly
    case tilesOnly
    case minimal

    var id: TargetLabSettingsPreset { self }

    var displayName: String {
        switch self {
        case .allIn: return "全部入り"
        case .cardsOnly: return "カード検証"
        case .tilesOnly: return "マス検証"
        case .minimal: return "最小構成"
        }
    }

    var settings: TargetLabExperimentSettings {
        switch self {
        case .allIn:
            return .default
        case .cardsOnly:
            return TargetLabExperimentSettings(
                enabledCardGroups: Set(TargetLabCardGroup.allCases),
                enabledTileKinds: []
            )
        case .tilesOnly:
            return TargetLabExperimentSettings(
                enabledCardGroups: [.standard],
                enabledTileKinds: Set(TargetLabTileKind.allCases)
            )
        case .minimal:
            return TargetLabExperimentSettings(
                enabledCardGroups: [.standard],
                enabledTileKinds: [.warp, .boost, .slow]
            )
        }
    }
}

@MainActor
final class TargetLabExperimentSettingsStore: ObservableObject {
    private static let storageKey = StorageKey.UserDefaults.targetLabExperimentSettings

    @Published private(set) var settings: TargetLabExperimentSettings
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.settings = Self.load(from: userDefaults)
    }

    func toggleCardGroup(_ group: TargetLabCardGroup) {
        var next = settings
        if next.enabledCardGroups.contains(group) {
            next.enabledCardGroups.remove(group)
        } else {
            next.enabledCardGroups.insert(group)
        }
        update(next)
    }

    func toggleTileKind(_ kind: TargetLabTileKind) {
        var next = settings
        if next.enabledTileKinds.contains(kind) {
            next.enabledTileKinds.remove(kind)
        } else {
            next.enabledTileKinds.insert(kind)
        }
        update(next)
    }

    func applyPreset(_ preset: TargetLabSettingsPreset) {
        update(preset.settings)
    }

    func update(_ next: TargetLabExperimentSettings) {
        guard settings != next else { return }
        settings = next
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        userDefaults.set(data, forKey: Self.storageKey)
    }

    private static func load(from userDefaults: UserDefaults) -> TargetLabExperimentSettings {
        guard let data = userDefaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(TargetLabExperimentSettings.self, from: data)
        else {
            return .default
        }
        return decoded.hasPlayableCards ? decoded : .default
    }
}
