import Foundation

/// 山札から配られたカードを UI で一意に識別するための薄いラッパー構造体
/// - Note: アニメーションや SwiftUI の `Identifiable` に準拠させるため、UUID を別途付与する。

public struct DealtCard: Identifiable, Equatable {
    /// SwiftUI の差分計算とアニメーションで利用する一意な識別子
    public let id: UUID
    /// 移動カードまたは補助カードを表すカード本体
    public let playable: PlayableCard
    /// 固定ワープカード専用の目的地（それ以外のカードでは nil）
    /// - Note: カードごとに固有のワープ先を持たせるためのメタデータを保持し、GameCore からも参照できるようにする
    public let fixedWarpDestination: GridPoint?

    /// 移動カードの場合のみ MoveCard を返す
    public var moveCard: MoveCard? { playable.move }

    /// 補助カードの場合のみ SupportCard を返す
    public var supportCard: SupportCard? { playable.support }

    /// 既存の移動カード向けコードとの互換用アクセサ
    /// - Important: 補助カードでは利用せず、`moveCard` で分岐してから参照する
    public var move: MoveCard {
        guard let move = moveCard else {
            preconditionFailure("補助カードには MoveCard がありません")
        }
        return move
    }

    public var displayName: String { playable.displayName }

    /// 新しいカードを生成する
    /// - Parameters:
    ///   - id: 既存カードからラップし直す場合に利用する識別子（省略時は新規採番）
    ///   - move: 実際の移動ロジックを担う `MoveCard`
    public init(id: UUID = UUID(), move: MoveCard, fixedWarpDestination: GridPoint? = nil) {
        self.id = id
        self.playable = .move(move)
        self.fixedWarpDestination = fixedWarpDestination
    }

    /// 補助カードを生成する
    /// - Parameters:
    ///   - id: 既存カードからラップし直す場合に利用する識別子
    ///   - support: 実際の補助効果を担うカード
    public init(id: UUID = UUID(), support: SupportCard) {
        self.id = id
        self.playable = .support(support)
        self.fixedWarpDestination = nil
    }

    /// 任意のカード種別から生成する
    public init(id: UUID = UUID(), playable: PlayableCard, fixedWarpDestination: GridPoint? = nil) {
        self.id = id
        self.playable = playable
        self.fixedWarpDestination = fixedWarpDestination
    }
}
