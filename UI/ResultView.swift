import SwiftUI

/// ゲーム終了時の結果を表示するビュー
/// 手数・ベスト記録・各種ボタンをまとめて配置する
struct ResultView: View {
    /// 今回のプレイで消費した手数
    let moves: Int
    /// Game Center サービス（ランキング表示に利用）
    let gameCenterService: GameCenterServiceProtocol
    /// 広告サービス（結果表示時に広告表示）
    let adsService: AdsServiceProtocol

    /// 再戦処理を外部から受け取るクロージャ
    let onRetry: () -> Void

    /// ベスト手数を `UserDefaults` に保存する
    @AppStorage("best_moves_5x5") private var bestMoves: Int = .max

    /// 依存性を注入するための初期化子
    /// - Parameters:
    ///   - moves: 今回の手数
    ///   - gameCenterService: Game Center サービス
    ///   - adsService: 広告サービス
    ///   - onRetry: リトライ時に呼び出す処理
    init(
        moves: Int,
        gameCenterService: GameCenterServiceProtocol = GameCenterService.shared,
        adsService: AdsServiceProtocol = AdsService.shared,
        onRetry: @escaping () -> Void
    ) {
        self.moves = moves
        self.gameCenterService = gameCenterService
        self.adsService = adsService
        self.onRetry = onRetry
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
                onRetry()
            }) {
                Text("リトライ")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            
            // MARK: - Game Center ランキングボタン
            Button(action: {
                gameCenterService.showLeaderboard()
            }) {
                Text("ランキング")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
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
        ResultView(moves: 30, onRetry: {})
    }
}
