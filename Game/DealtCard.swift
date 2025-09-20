import Foundation

/// 山札から配られたカードを UI で一意に識別するための薄いラッパー構造体
/// - Note: アニメーションや SwiftUI の `Identifiable` に準拠させるため、UUID を別途付与する。
public struct DealtCard: Identifiable, Equatable {
    /// SwiftUI の差分計算とアニメーションで利用する一意な識別子
    public let id: UUID
    /// これまでのロジックが扱っていた移動カード本体
    public let move: MoveCard

    /// 新しいカードを生成する
    /// - Parameters:
    ///   - id: 既存カードからラップし直す場合に利用する識別子（省略時は新規採番）
    ///   - move: 実際の移動ロジックを担う `MoveCard`
    public init(id: UUID = UUID(), move: MoveCard) {
        self.id = id
        self.move = move
    }
}
