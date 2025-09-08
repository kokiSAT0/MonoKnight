import SwiftUI
import SpriteKit
import Game

/// SwiftUI から SpriteKit の盤面を表示するビュー
/// 画面下部に手札 3 枚と次に引かれるカードを表示し、
/// タップで GameCore を更新する
struct GameView: View {
    /// ゲームロジックを保持する ObservableObject
    /// - NOTE: `StateObject` は init 内で明示的に生成し、GameScene に渡す
    @StateObject private var core: GameCore
    /// 結果画面を表示するかどうかのフラグ
    /// - NOTE: クリア時に true となり ResultView をシート表示する
    @State private var showingResult = false
    /// SpriteKit のシーン。初期化時に一度だけ生成して再利用する
    private let scene: GameScene

    /// 初期化で GameCore と GameScene を連結する
    init() {
        // GameCore の生成。StateObject へ包んで保持する
        let core = GameCore()
        _core = StateObject(wrappedValue: core)

        // GameScene はインスタンス生成後にサイズとスケールを指定
        let scene = GameScene()
        scene.scaleMode = .resizeFill
        // GameScene から GameCore へタップイベントを伝えるため参照を渡す
        scene.gameCore = core
        self.scene = scene
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 16) {
                // MARK: SpriteKit 表示領域
                SpriteView(scene: scene)
                    // 正方形で表示したいため幅に合わせる
                    .frame(width: geometry.size.width, height: geometry.size.width)
                    .onAppear {
                        // サイズと初期状態を反映
                        scene.size = CGSize(width: geometry.size.width, height: geometry.size.width)
                        scene.updateBoard(core.board)
                        scene.moveKnight(to: core.current)
                    }
                    // board が更新されたら色を反映
                    .onChange(of: core.board) { newBoard in
                        scene.updateBoard(newBoard)
                    }
                    // current が更新されたら駒を移動
                    .onChange(of: core.current) { newPoint in
                        scene.moveKnight(to: newPoint)
                    }

                // MARK: 手札と先読みカードの表示
                VStack(spacing: 8) {
                    // 手札 3 枚を横並びで表示
                    HStack(spacing: 12) {
                        // MoveCard は Identifiable に準拠していないため、enumerated の offset を id として利用
                        ForEach(Array(core.hand.enumerated()), id: \.offset) { index, card in
                            cardView(for: card)
                                // 盤外に出るカードは薄く表示し、タップを無効化
                                .opacity(isCardUsable(card) ? 1.0 : 0.4)
                                .onTapGesture {
                                    // 列挙型 MoveCard の使用可否を確認してから GameCore へ伝達
                                    guard isCardUsable(card) else { return }
                                    // 選択されたカードで GameCore を更新（index は手札位置）
                                    core.playCard(at: index)
                                }
                        }
                    }

                    // 先読みカードが存在する場合に表示
                    if let next = core.next {
                        HStack(spacing: 4) {
                            Text("次のカード")
                                .font(.caption)
                            cardView(for: next)
                                .opacity(0.6) // 先読みは操作不可なので半透明
                        }
                    }
                }
                .padding(.bottom, 16)
            }
            // 画面全体を黒背景に統一
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        }
        // progress が .cleared へ変化したタイミングで結果画面を表示
        .onChange(of: core.progress) { newValue in
            guard newValue == .cleared else { return }
            // Game Center へスコア送信
            GameCenterService.shared.submitScore(core.score)
            // 結果画面を開く
            showingResult = true
        }
        // シートで結果画面を表示
        .sheet(isPresented: $showingResult) {
            ResultView(moves: core.score) {
                // リトライ時はゲームを初期化して再開
                core.reset()
                // シートを閉じる
                showingResult = false
            }
        }
    }

    /// 指定カードが現在位置から盤内に収まるか判定
    /// - Note: MoveCard は列挙型であり、dx/dy プロパティから移動量を取得する
    private func isCardUsable(_ card: MoveCard) -> Bool {
        // 現在位置に MoveCard の移動量を加算して目的地を算出
        let target = core.current.offset(dx: card.dx, dy: card.dy)
        // 目的地が盤面内に含まれているかどうかを判定
        return core.board.contains(target)
    }

    /// カードの簡易表示ビュー
    /// - Parameter card: 表示対象の MoveCard（列挙型）
    private func cardView(for card: MoveCard) -> some View {
        ZStack {
            // 枠付きの白いカードを描画
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white, lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                )
            // MoveCard に定義された displayName を表示（例: 上2右1）
            Text(card.displayName)
                .font(.caption)
                .foregroundColor(.white)
        }
        .frame(width: 60, height: 80)
    }
}

// MARK: - プレビュー
#Preview {
    // Xcode の Canvas で GameView を表示するためのプレビュー
    GameView()
}

