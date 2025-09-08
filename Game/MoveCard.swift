import Foundation

/// 駒をどの方向に何マス動かすかを表すカード
/// - 仕様: ナイト移動8種 + 直線/斜めの2マス移動8種の計16種
struct MoveCard: Identifiable {
    /// 一意な識別子（デバッグやリスト表示用）
    let id = UUID()
    /// x方向の移動量（右が正）
    let dx: Int
    /// y方向の移動量（上が正）
    let dy: Int

    /// 表示用ラベル
    /// - 備考: 現状はシンプルに "dx,dy" 形式で返す
    var label: String {
        "\(dx),\(dy)"
    }
}

extension MoveCard {
    /// 16種類のカードをあらかじめ定義した配列
    /// 山札の初期化や再構築で利用する
    static let all: [MoveCard] = [
        // MARK: - ナイト移動 8種
        MoveCard(dx: 1, dy: 2),
        MoveCard(dx: 2, dy: 1),
        MoveCard(dx: -1, dy: 2),
        MoveCard(dx: -2, dy: 1),
        MoveCard(dx: 1, dy: -2),
        MoveCard(dx: 2, dy: -1),
        MoveCard(dx: -1, dy: -2),
        MoveCard(dx: -2, dy: -1),
        // MARK: - 直線/斜めの2マス移動 8種
        MoveCard(dx: 2, dy: 0),
        MoveCard(dx: -2, dy: 0),
        MoveCard(dx: 0, dy: 2),
        MoveCard(dx: 0, dy: -2),
        MoveCard(dx: 2, dy: 2),
        MoveCard(dx: -2, dy: 2),
        MoveCard(dx: 2, dy: -2),
        MoveCard(dx: -2, dy: -2)
    ]
}
