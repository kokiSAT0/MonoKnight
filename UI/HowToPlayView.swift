import SwiftUI

/// ゲームの基本的な遊び方を段階的に案内するビュー
/// - NOTE: タイトル画面や設定画面からシート表示して参照できるようにする
struct HowToPlayView: View {
    /// シートを閉じるための環境値
    @Environment(\.dismiss) private var dismiss

    /// チュートリアル内で紹介する移動カードの例（視覚的に理解しやすいよう代表的な 3 種をピックアップ）
    private let sampleCards: [MoveCard] = [
        .kingUp,
        .knightUp2Right1,
        .diagonalDownLeft2
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    // MARK: - ゲームの目的を端的に紹介
                    overviewSection

                    // MARK: - カードを選ぶ流れを具体的に説明
                    cardInstructionSection

                    // MARK: - 勝利条件と失敗時のペナルティを整理
                    goalAndPenaltySection
                }
                .padding(.vertical, 28)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // ダークテーマ前提のため背景も黒系で統一し、タブ全体との一貫性を確保
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("遊び方")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // 閉じるボタンでいつでもシートを閉じられるようにする
                    Button("閉じる") {
                        dismiss()
                    }
                    .accessibilityIdentifier("how_to_play_close_button")
                }
            }
        }
    }
}

// MARK: - セクション別のサブビュー定義
private extension HowToPlayView {
    /// ゲームの全体像を紹介するセクション
    var overviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MonoKnight とは？")
                .font(.title2.bold())
                .foregroundColor(.white)

            Text("5×5 の盤面をすべて踏破するとクリアとなるパズルです。カードで騎士を動かし、踏破済みでないマスを順番に埋めていきましょう。")
                .font(.body)
                .foregroundColor(.white.opacity(0.85))
        }
        .padding()
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    /// カードの選び方や挙動を解説するセクション
    var cardInstructionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("1. カードで移動先を決めよう")
                .font(.title3.bold())
                .foregroundColor(.white)

            Text("手札から 1 枚選ぶと矢印の方向に騎士が移動します。灰色のマスは既に踏破済みです。盤面外へ出るカードは選べません。")
                .font(.body)
                .foregroundColor(.white.opacity(0.85))

            // MoveCardIllustrationView を使い、代表的なカードを視覚的に並べる
            HStack(spacing: 20) {
                ForEach(sampleCards, id: \.self) { card in
                    VStack(spacing: 10) {
                        MoveCardIllustrationView(card: card)
                            // チュートリアルでは少し大きめに見せて操作イメージを掴みやすくする
                            .scaleEffect(1.6)
                        Text(card.displayName)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("カードは 1 度使うと捨て札へ移動し、山札が尽きると自動で再シャッフルされます。先読みカードを確認しながら効率良く巡回しましょう。")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding()
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    /// クリア条件とペナルティの発生タイミングを説明するセクション
    var goalAndPenaltySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("2. クリア条件とペナルティ")
                .font(.title3.bold())
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text("全 25 マスを 1 度ずつ踏めばクリアです。残りマス数は画面上部のカウンターで確認できます。")
                } icon: {
                    Image(systemName: "checkmark.circle")
                        .foregroundColor(.green)
                }
                .font(.body)
                .foregroundColor(.white.opacity(0.85))

                Label {
                    Text("手札 3 枚すべてが盤外で使えない場合は自動で引き直しが入り、手数に +5 のペナルティが加算されます。")
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.yellow)
                }
                .font(.body)
                .foregroundColor(.white.opacity(0.85))

                Label {
                    Text("より少ない手数で全踏破するほどスコアが高く、Game Center のリーダーボードで競えます。")
                } icon: {
                    Image(systemName: "rosette")
                        .foregroundColor(.blue)
                }
                .font(.body)
                .foregroundColor(.white.opacity(0.85))
            }
        }
        .padding()
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - プレビュー
#Preview {
    HowToPlayView()
        .preferredColorScheme(.dark)
}
