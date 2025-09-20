import SwiftUI

/// ゲームの遊び方を段階的に説明するビュー
/// カード挙動の例や勝利条件・ペナルティの概要をまとめ、初見でも流れを理解しやすくする
struct HowToPlayView: View {
    /// モーダル表示時に閉じるボタンを出すかどうかのフラグ
    /// - Note: タイトル画面からシートで開く場合のみ true を渡す
    let showsCloseButton: Bool
    /// 画面を閉じるための環境変数
    @Environment(\.dismiss) private var dismiss

    /// デフォルト引数付きのイニシャライザ
    /// - Parameter showsCloseButton: ナビゲーションバーに「閉じる」ボタンを表示するか
    init(showsCloseButton: Bool = false) {
        self.showsCloseButton = showsCloseButton
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // MARK: - 導入文
                Text("MonoKnight は移動カードを使って 5×5 の盤面を踏破するパズルです。以下の流れを押さえておけば、すぐにプレイを始められます。")
                    .font(.body)
                    .padding(.bottom, 8)

                // MARK: - 基本移動の説明
                HowToPlaySectionView(
                    title: "1. カードを 1 枚選んで駒を動かす",
                    description: "手札に並ぶカードから 1 枚を選び、描かれた方向へ騎士を移動させます。",
                    card: .kingUp,
                    tips: [
                        "カードの矢印が示す方向に 1 マス進みます。",
                        "白い丸が現在位置、黒い丸が移動先を表します。"
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
                        "移動先が未踏破マスであればカウントが増え、全マス踏破でクリアです。"
                    ]
                )

                // MARK: - 勝利条件の説明
                HowToPlaySectionView(
                    title: "4. 勝利条件",
                    description: "25 マスすべてを一度ずつ踏破するとクリアとなり、手数がスコアとして記録されます。",
                    card: nil,
                    tips: [
                        "踏破済みマスはグレー表示になり、未踏破との区別がつきます。",
                        "最小の手数でクリアを目指し、Game Center ランキング上位を狙いましょう。"
                    ]
                )

                // MARK: - ペナルティの説明
                HowToPlaySectionView(
                    title: "5. 行き詰まったときはペナルティ",
                    description: "手札 3 枚すべてが盤外で使えない場合、手数に +5 のペナルティが加算され、手札が引き直されます。",
                    card: nil,
                    tips: [
                        "ペナルティ後は新しい手札で再挑戦できますが、スコアには不利です。",
                        "盤外になりやすいカードを連続で消費しないよう計画的にプレイしましょう。"
                    ]
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 28)
        }
        .background(Color(UIColor.systemBackground))
        .navigationTitle("遊び方")
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
