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
                ruleSummary: "5×5 盤・中央開始・手詰まり時は手数+3（手動引き直しは +2）。テンポよくスコア更新を狙える定番ルールです。",
                difficultyLabel: "難易度: ノーマル",
                accessibilityIdentifier: "high_score_mode_standard"
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
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
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
    private func modeCardButton(for data: ModeCardData) -> some View {
        Button {
            // タップされたモードをタイトル画面へ返し、即時開始のトリガーへつなげる
            onSelect(data.mode)
        } label: {
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
        .buttonStyle(.plain)
        .accessibilityIdentifier(data.accessibilityIdentifier)
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
