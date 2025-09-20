import SwiftUI
import UIKit  // ハプティクス用フレームワーク

/// ゲーム終了時の結果を表示するビュー
/// 手数・ベスト記録・各種ボタンをまとめて配置する
struct ResultView: View {
    /// 今回のプレイで実際に移動した回数
    let moveCount: Int

    /// ペナルティで加算された手数
    let penaltyCount: Int

    /// 再戦処理を外部から受け取るクロージャ
    let onRetry: () -> Void

    /// Game Center 連携を扱うサービス（プロトコル型で受け取る）
    /// `init` 時にのみ代入し、以後は再代入しないがテスト用に差し替えられるよう `var` で定義
    private var gameCenterService: GameCenterServiceProtocol
    /// 広告表示を扱うサービス（プロトコル型で受け取る）
    /// 上記と同じく `init` で注入し、必要に応じてモックに差し替え可能にする
    private var adsService: AdsServiceProtocol

    /// ベスト手数を `UserDefaults` に保存する
    @AppStorage("best_moves_5x5") private var bestMoves: Int = .max
    /// ハプティクスを有効にするかどうかの設定値
    @AppStorage("haptics_enabled") private var hapticsEnabled: Bool = true

    /// 新記録を達成したかどうかを管理するステート
    @State private var isNewBest: Bool = false

    /// 新記録達成時に比較用として保持する旧ベスト値（存在しない場合は nil）
    @State private var previousBest: Int?

    init(
        moveCount: Int,
        penaltyCount: Int,
        onRetry: @escaping () -> Void,
        gameCenterService: GameCenterServiceProtocol = GameCenterService.shared,  // ない場合は GameCenterService()
        adsService: AdsServiceProtocol = AdsService.shared  // ない場合は AdsService()
    ) {
        self.moveCount = moveCount
        self.penaltyCount = penaltyCount
        self.onRetry = onRetry
        self.gameCenterService = gameCenterService
        self.adsService = adsService
    }

    var body: some View {
        VStack(spacing: 24) {
            // MARK: - 合計手数と新記録バッジ
            VStack(spacing: 12) {
                Text("合計手数: \(totalMoves)")
                    .font(.title)
                    .padding(.top, 32)

                // 新記録時のみアニメーション付きのバッジを表示
                if isNewBest {
                    TimelineView(.animation) { context in
                        // TimelineView の時刻から簡易的な脈動アニメーションを生成
                        let progress = sin(context.date.timeIntervalSinceReferenceDate * 2.6)
                        let scale = 1.0 + 0.08 * progress

                        Text("新記録！")
                            .font(.headline.weight(.bold))
                            .foregroundColor(.yellow)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color.yellow.opacity(0.18))
                                    .overlay(
                                        Capsule()
                                            .stroke(Color.yellow.opacity(0.55), lineWidth: 1)
                                    )
                            )
                            .scaleEffect(scale)
                            .accessibilityLabel("新記録を達成")
                    }
                    .transition(.scale.combined(with: .opacity))
                }

                // MARK: - ベスト記録表示（未記録の場合は '-'）
                Text("ベスト: \(bestMovesText)")
                    .font(.headline)

                // 新旧の比較説明を追加し、振り返りの文脈を与える
                if let description = bestComparisonDescription {
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }
            }

            // MARK: - リトライボタン
            Button(action: {
                // 設定が有効なら成功フィードバックを発火
                if hapticsEnabled {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                onRetry()
            }) {
                Text("リトライ")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            // MARK: - Game Center ランキングボタン
            Button(action: {
                // 設定が有効なら成功フィードバックを発火
                if hapticsEnabled {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                gameCenterService.showLeaderboard()
            }) {
                Text("ランキング")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            // MARK: - 手数の内訳テーブル
            VStack(alignment: .leading, spacing: 12) {
                Text("手数の内訳")
                    .font(.headline)
                    .padding(.top, 8)

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("移動回数")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(moveCount) 手")
                            .font(.body)
                    }

                    GridRow {
                        Text("ペナルティ加算")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(penaltyCount) 手")
                            .font(.body)
                    }

                    Divider()
                        .gridCellColumns(2)

                    GridRow {
                        Text("合計")
                            .font(.subheadline.weight(.semibold))
                        Text("\(totalMoves) 手")
                            .font(.body.weight(.semibold))
                    }
                }
            }

            // MARK: - ShareLink で結果共有を促す
            ShareLink(item: shareMessage) {
                Label("結果を共有", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            // MARK: - 広告の読み込み表示
            // 実広告はインタースティシャルで別画面表示されるため、ここでは状況のみを示す
            Text("広告を読み込んでいます…")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .padding()
        .onAppear {
            // ビュー表示時に広告表示をトリガー
            adsService.showInterstitial()
            // ベスト記録の更新を判定
            updateBest()
        }
    }

    /// ベスト記録を表示用の文字列に変換
    private var bestMovesText: String {
        bestMoves == .max ? "-" : String(bestMoves)
    }

    /// 合計手数を計算するヘルパー
    private var totalMoves: Int {
        moveCount + penaltyCount
    }

    /// ShareLink へ渡す共有メッセージを生成
    private var shareMessage: String {
        let penaltyText = penaltyCount == 0 ? "ペナルティなし" : "ペナルティ +\(penaltyCount) 手"
        return "MonoKnight 5x5 クリア！合計 \(totalMoves) 手（移動 \(moveCount) 手 / \(penaltyText)）"
    }

    /// 新記録達成時の説明文を生成（旧ベストと比較する）
    private var bestComparisonDescription: String? {
        guard isNewBest else { return nil }

        if let previousBest {
            let diff = previousBest - totalMoves
            // 旧ベストより何手短縮できたのかを明示
            return "これまでのベスト \(previousBest) 手 → 今回 \(totalMoves) 手（\(diff) 手 更新）"
        } else {
            // 初回登録時は比較対象が無いため、その旨を明示
            return "初めてのベスト記録が登録されました"
        }
    }

    /// ベスト記録を更新する
    private func updateBest() {
        // 更新前のベストを保持して比較テキストに利用
        previousBest = bestMoves == .max ? nil : bestMoves

        // 今回の合計手数と既存ベストを比較して更新するか判定
        if totalMoves < bestMoves {
            bestMoves = totalMoves

            // 視覚的なアニメーションとハプティクスを新記録時に限定して発火
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                isNewBest = true
            }
            if hapticsEnabled {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                isNewBest = false
            }
        }
    }
}

struct ResultView_Previews: PreviewProvider {
    static var previews: some View {
        ResultView(
            moveCount: 24,
            penaltyCount: 6,
            onRetry: {},
            gameCenterService: GameCenterService.shared,
            adsService: AdsService.shared
        )
    }
}


#Preview {
    ResultView(moveCount: 24, penaltyCount: 6, onRetry: {})
}