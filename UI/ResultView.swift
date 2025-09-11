import SwiftUI
import UIKit  // ハプティクス用フレームワーク

/// ゲーム終了時の結果を表示するビュー
/// 手数・ベスト記録・各種ボタンをまとめて配置する
struct ResultView: View {
    /// 今回のプレイで消費した手数
    let moves: Int

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

    init(
        moves: Int,
        onRetry: @escaping () -> Void,
        gameCenterService: GameCenterServiceProtocol = GameCenterService.shared,  // ない場合は GameCenterService()
        adsService: AdsServiceProtocol = AdsService.shared  // ない場合は AdsService()
    ) {
        self.moves = moves
        self.onRetry = onRetry
        self.gameCenterService = gameCenterService
        self.adsService = adsService
    }

    var body: some View {
        VStack(spacing: 24) {
            // MARK: - 手数表示
            Text("手数: \(moves)")
                .font(.title)
                .padding(.top, 32)

            // MARK: - ベスト記録表示（未記録の場合は '-'）
            Text("ベスト: \(bestMovesText)")
                .font(.headline)

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

            // MARK: - 広告プレースホルダー
            // 実際のインタースティシャル広告の代わりにダミービューを表示
            DummyInterstitialAdView()
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

    /// ベスト記録を更新する
    private func updateBest() {
        if moves < bestMoves {
            bestMoves = moves
        }
    }
}

struct ResultView_Previews: PreviewProvider {
    static var previews: some View {
        ResultView(
            moves: 30,
            onRetry: {},
            gameCenterService: GameCenterService.shared,
            adsService: AdsService.shared
        )
    }
}


#Preview {
    ResultView(moves: 30, onRetry: {})
}