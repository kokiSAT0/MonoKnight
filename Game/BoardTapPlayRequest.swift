import Foundation

/// 盤面タップでカードを再生するときに UI へ伝える要求内容
/// - Note: SwiftUI 側でアニメーションを開始し、完了後に `playCard` を呼び出すための情報をまとめる
public struct BoardTapPlayRequest: Identifiable, Equatable {
    /// 要求ごとに一意な識別子を払い出して、複数回のタップでも確実に区別できるようにする
    public let id: UUID
    /// 盤面タップ時に対象となった手札スタックの識別子
    public let stackID: UUID
    /// `GameCore.playCard(at:)` に渡すスタックインデックス
    public let stackIndex: Int
    /// アニメーションで参照する先頭カード情報
    public let topCard: DealtCard

    /// UI 側で参照しやすいよう公開イニシャライザを用意
    /// - Parameters:
    ///   - id: 外部で識別子を指定したい場合に使用（省略時は自動採番）
    ///   - stackID: 手札スタックの識別子
    ///   - stackIndex: タップ時点でのスタック位置
    ///   - topCard: 盤面タップと対応する先頭カード
    public init(id: UUID = UUID(), stackID: UUID, stackIndex: Int, topCard: DealtCard) {
        self.id = id
        self.stackID = stackID
        self.stackIndex = stackIndex
        self.topCard = topCard
    }

    /// Equatable は識別子のみで比較し、カード更新が挟まってもリクエスト自体は同一とみなす
    public static func == (lhs: BoardTapPlayRequest, rhs: BoardTapPlayRequest) -> Bool {
        lhs.id == rhs.id
    }
}
