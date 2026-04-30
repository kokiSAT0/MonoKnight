import SwiftUI
import Game // MoveCard 型を利用するためゲームロジックモジュールを読み込む

/// ゲームの遊び方を段階的に説明するビュー
/// カード挙動の例や勝利条件・ペナルティの概要をまとめ、初見でも流れを理解しやすくする
struct HowToPlayView: View {
    /// ヘルプ内で表示するページ
    private enum HelpPage: String, CaseIterable, Identifiable {
        case guide = "遊び方"
        case cardDictionary = "カード辞典"
        case tileDictionary = "マス辞典"

        var id: HelpPage { self }
    }

    /// モーダル表示時に閉じるボタンを出すかどうかのフラグ
    /// - Note: タイトル画面からシートで開く場合のみ true を渡す
    let showsCloseButton: Bool
    /// 説明に用いる基準モード（スタンダード）を保持し、手札スロット数などを文字列に反映する
    private let referenceMode: GameMode = .standard
    /// 画面を閉じるための環境変数
    @Environment(\.dismiss) private var dismiss
    /// iPad などレギュラー幅の端末でレイアウトを最適化するためのサイズクラス
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// ヘルプ内の表示ページ
    @State private var selectedPage: HelpPage = .guide

    /// デフォルト引数付きのイニシャライザ
    /// - Parameter showsCloseButton: ナビゲーションバーに「閉じる」ボタンを表示するか
    init(showsCloseButton: Bool = false) {
        self.showsCloseButton = showsCloseButton
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Picker("ヘルプ表示", selection: $selectedPage) {
                    ForEach(HelpPage.allCases) { page in
                        Text(page.rawValue).tag(page)
                    }
                }
                .pickerStyle(.segmented)

                switch selectedPage {
                case .guide:
                    guideContent
                case .cardDictionary:
                    cardDictionaryContent
                case .tileDictionary:
                    tileDictionaryContent
                }
            }
            // MARK: - サイズクラスに応じた余白調整
            // iPad では左右の余白を広めに確保し、中央揃えで読みやすくする。iPhone では従来の余白を維持。
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 28)
            .frame(maxWidth: contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollIndicators(.hidden)
        .background(Color(UIColor.systemBackground))
        .navigationTitle(selectedPage.rawValue)
        .toolbar {
            // MARK: - モーダル用の閉じるボタン
            if showsCloseButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - ページ本文
private extension HowToPlayView {
    /// 初心者向けの遊び方本文
    var guideContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            // MARK: - 導入文
            Text("MonoKnight は移動カードを使って、盤面上の目的地を連続で取るパズルです。手札スロットは最大 \(referenceMode.handSize) 種類まで保持でき、\(referenceMode.stackingRuleDetailText)以下の流れを押さえておけば、すぐにプレイを始められます。")
                .font(.body)
                .padding(.bottom, 8)

            // MARK: - 基本移動の説明
            HowToPlaySectionView(
                title: "1. カードを 1 枚選んで駒を動かす",
                description: "手札スロットに並ぶカードから 1 枚を選び、描かれた方向へ騎士を移動させます。",
                card: .kingUp,
                tips: [
                    "カードの矢印が示す方向に 1 マス進みます。",
                    "白い丸が現在位置、黒い丸が移動先を表します。",
                    stackingTip
                ]
            )

            // MARK: - ナイト移動の例
            HowToPlaySectionView(
                title: "2. ナイト型カードで L 字に跳ぶ",
                description: "一部のカードはチェスのナイトと同じく L 字に移動します。盤面を広く踏破する鍵になります。",
                card: .knightUp2Right1,
                tips: [
                    "2 マス進んだ後に 1 マス横へ曲がります。",
                    "行き止まりを回避するために温存しておく戦略も重要です。"
                ]
            )

            // MARK: - 遠距離カードの例
            HowToPlaySectionView(
                title: "3. 2 マス先まで届くカード",
                description: "直線や斜めに 2 マス進むカードもあります。使えるマスが限られるため、盤外判定に注意しましょう。",
                card: .straightUp2,
                tips: [
                    "盤外へ出るカードは自動で選べなくなり、半透明表示になります。",
                    "表示中の目的地に到達すると獲得数が増え、新しい目的地が補充されます。"
                ]
            )

            // MARK: - 勝利条件の説明
            HowToPlaySectionView(
                title: "4. 勝利条件",
                description: "目的地を \(referenceMode.targetGoalCount) 個獲得するとクリアとなり、移動手数・時間・フォーカス回数からスコアが記録されます。",
                card: nil,
                tips: [
                    "目的地マーカーは、どれからでも獲得できる表示中の目的地です。",
                    "移動候補は枠で表示されるため、目的地マーカーとは分けて見られます。",
                    "最小の手数でクリアを目指し、Game Center ランキング上位を狙いましょう。"
                ]
            )

            // MARK: - ペナルティの説明
            HowToPlaySectionView(
                title: "5. 目的地へ近づくフォーカス",
                description: "必要なカードが遠いときはフォーカスを使うと、表示中の目的地へ近づきやすいカードを優先して手札を整えられます。",
                card: nil,
                tips: [
                    "フォーカスは手数を増やさず、スコアに15ポイント加算されます。",
                    "手詰まり時も、目的地へ近づきやすい再配布が自動で行われます。"
                ]
            )
        }
    }

    /// カード辞典本文
    var cardDictionaryContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("カードの種類と動きを代表的な系統ごとに確認できます。")
                .font(.body)

            ForEach(cardCategoryOrder, id: \.self) { category in
                let entries = cardEntries(for: category)
                if !entries.isEmpty {
                    EncyclopediaGroupView(title: category) {
                        ForEach(entries) { entry in
                            CardEncyclopediaRow(entry: entry)
                        }
                    }
                }
            }
        }
    }

    /// マス辞典本文
    var tileDictionaryContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("盤面に登場するマスやマーカーの効果を確認できます。")
                .font(.body)

            ForEach(tileCategoryOrder, id: \.self) { category in
                let entries = tileEntries(for: category)
                if !entries.isEmpty {
                    EncyclopediaGroupView(title: category) {
                        ForEach(entries) { entry in
                            TileEncyclopediaRow(entry: entry)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - レイアウト調整用のヘルパー
private extension HowToPlayView {
    var cardCategoryOrder: [String] {
        ["キング", "ナイト", "直線2マス", "斜め2マス", "レイ", "選択キング", "選択ナイト", "ワープ", "目的地補助", "特殊マス補助"]
    }

    var tileCategoryOrder: [String] {
        ["基本", "目的地", "踏破", "障害物", "特殊効果"]
    }

    func cardEntries(for category: String) -> [MoveCardEncyclopediaEntry] {
        MoveCard.encyclopediaEntries.filter { $0.category == category }
    }

    func tileEntries(for category: String) -> [TileEncyclopediaEntry] {
        TileEncyclopediaEntry.allEntries.filter { $0.category == category }
    }

    /// スタック仕様を説明する文言。スタンダード以外に差し替えた場合でも整合が取れるようにする
    var stackingTip: String {
        if referenceMode.allowsCardStacking {
            return "同じ種類のカードは手札スロット内で重なり、消費するとまとめて補充されます。"
        } else {
            return "同じ種類のカードでも別スロットを占有するため、空き枠を意識した立ち回りが重要です。"
        }
    }

    /// 横幅に応じた最大コンテンツ幅を返す
    var contentMaxWidth: CGFloat? {
        horizontalSizeClass == .regular ? 640 : nil
    }

    /// 端末に合わせて適切な横方向パディングを返す
    var horizontalPadding: CGFloat {
        horizontalSizeClass == .regular ? 36 : 20
    }
}

// MARK: - 辞典グループ
private struct EncyclopediaGroupView<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 10) {
                content
            }
        }
    }
}

// MARK: - カード辞典行
private struct CardEncyclopediaRow: View {
    let entry: MoveCardEncyclopediaEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MoveCardIllustrationView(card: entry.card, mode: .next)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(entry.displayName)
                    .font(.headline)
                Text(entry.description)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - マス辞典行
private struct TileEncyclopediaRow: View {
    let entry: TileEncyclopediaEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.displayName)
                .font(.headline)
            Text(entry.description)
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 共通セクション描画用サブビュー
private struct HowToPlaySectionView: View {
    /// セクションタイトル
    let title: String
    /// 説明文
    let description: String
    /// 例示するカード（任意）
    let card: MoveCard?
    /// 補足のポイント一覧
    let tips: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: - タイトル
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)

            // MARK: - 説明文
            Text(description)
                .font(.body)

            // MARK: - カード挙動の例
            if let card {
                MoveCardIllustrationView(card: card)
                    .frame(height: 180)
                    .padding(.vertical, 4)
            }

            // MARK: - 補足事項のリスト
            VStack(alignment: .leading, spacing: 6) {
                ForEach(tips.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                            .padding(.top, 2)
                        Text(tips[index])
                            .font(.callout)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }
}

#Preview {
    NavigationStack {
        HowToPlayView()
    }
}
