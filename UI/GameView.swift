import SwiftUI
import SpriteKit

/// SpriteKit の `GameScene` を SwiftUI に埋め込み、
/// 画面下に手札3枚と先読み1枚を表示するビュー
struct GameView: View {
    // MARK: - 状態
    /// ゲームロジックのインスタンス
    @StateObject private var core = GameCore()

    /// SpriteKit のシーンを生成
    /// - 備考: サイズは仮の 300×300。実装が進んだら端末サイズに応じて調整する
    private var scene: SKScene {
        GameScene(size: CGSize(width: 300, height: 300), core: core)
    }

    // MARK: - ビュー本体
    var body: some View {
        VStack(spacing: 0) {
            // ゲーム盤面（SpriteKit）
            SpriteView(scene: scene)
                .ignoresSafeArea()
                .frame(minHeight: 300)

            // 手札表示エリア
            cardArea
                .padding()
                .background(Color(white: 0.2))
        }
    }

    /// 手札3枚と先読み1枚を並べるエリア
    private var cardArea: some View {
        HStack(alignment: .center, spacing: 16) {
            // 手札3枚をボタンとして表示
            ForEach(core.hand.indices, id: \.self) { index in
                let card = core.hand[index]
                Button {
                    // カードを選択したら GameCore に処理を依頼
                    core.playCard(at: index)
                } label: {
                    cardView(card)
                }
            }

            // 手札との間に適度なスペースを挟む
            Spacer(minLength: 24)

            // 先読みカードは押下不可のプレースホルダーとして表示
            cardView(core.nextCard)
                .opacity(0.5)
        }
    }

    /// 共通のカード表示ビュー
    /// - Parameter card: 表示したいカード
    /// - Returns: 60x90pt の角丸矩形にラベルを載せたビュー
    private func cardView(_ card: MoveCard) -> some View {
        Text(card.label)
            .frame(width: 60, height: 90)
            .background(Color.white)
            .foregroundColor(.black)
            .cornerRadius(8)
    }
}

// MARK: - プレビュー
#Preview {
    GameView()
}
