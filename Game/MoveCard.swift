import Foundation

/// 移動カードを表す構造体
/// - 備考: dx, dy で移動量を表現するシンプルなデータモデル
struct MoveCard: Hashable {
    /// x 方向の移動量
    let dx: Int
    /// y 方向の移動量
    let dy: Int

    /// すべてのカードパターンを列挙した配列
    /// - 計16種類の移動が定義されている
    static let all: [MoveCard] = {
        // ナイト型の 8 種
        let knights = [
            MoveCard(dx: 1, dy: 2),
            MoveCard(dx: 2, dy: 1),
            MoveCard(dx: -1, dy: 2),
            MoveCard(dx: -2, dy: 1),
            MoveCard(dx: 1, dy: -2),
            MoveCard(dx: 2, dy: -1),
            MoveCard(dx: -1, dy: -2),
            MoveCard(dx: -2, dy: -1)
        ]
        // 直線および斜めに 2 マス進む 8 種
        let longs = [
            MoveCard(dx: 2, dy: 0),
            MoveCard(dx: -2, dy: 0),
            MoveCard(dx: 0, dy: 2),
            MoveCard(dx: 0, dy: -2),
            MoveCard(dx: 2, dy: 2),
            MoveCard(dx: -2, dy: 2),
            MoveCard(dx: 2, dy: -2),
            MoveCard(dx: -2, dy: -2)
        ]
        return knights + longs
    }()
}

