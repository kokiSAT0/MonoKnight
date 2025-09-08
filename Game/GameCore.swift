import Foundation
import Combine

/// ゲーム全体の進行と状態を管理するクラス
/// - 備考: SwiftUI から監視するため `ObservableObject` に準拠
final class GameCore: ObservableObject {
    // MARK: - 公開プロパティ
    /// プレイヤーの現在位置
    @Published private(set) var position: GridPoint = .center
    /// 盤面情報（踏破状態など）
    @Published private(set) var board = Board()
    /// 手札3枚
    @Published private(set) var hand: [MoveCard] = []
    /// 先読み1枚
    @Published private(set) var nextCard: MoveCard = MoveCard.all.first!

    // MARK: - 内部プロパティ
    /// 残りの山札
    private var deck: [MoveCard] = []

    // MARK: - 初期化
    init() {
        // 山札を初期化して手札・先読みを配る
        resetDeck()
        hand = (0..<3).map { _ in drawCard() }
        nextCard = drawCard()
    }

    // MARK: - 山札管理
    /// 山札が空になったら全カードをシャッフルし直す
    private func resetDeck() {
        deck = MoveCard.all.shuffled()
    }

    /// 山札から1枚引く
    private func drawCard() -> MoveCard {
        if deck.isEmpty { resetDeck() }
        return deck.removeFirst()
    }

    // MARK: - カード選択処理
    /// 手札からカードを選んだ際の処理
    /// - Parameter index: 選択したカードの手札インデックス
    func playCard(at index: Int) {
        guard hand.indices.contains(index) else { return }
        let card = hand[index]

        // 移動後の座標を計算
        let target = position.offset(dx: card.dx, dy: card.dy)

        // 盤面内であれば移動を反映
        if board.contains(target) {
            position = target
            board.markVisited(target)
        }

        // 使用したスロットを先読みカードで埋める
        hand[index] = nextCard
        // 次の先読みカードを引く
        nextCard = drawCard()
    }
}
