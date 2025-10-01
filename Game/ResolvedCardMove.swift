import Foundation

/// カードの移動量を表すベクトル構造体
/// - Note: `dx` / `dy` をまとめて扱うことで、ログ出力やテストでの比較を簡略化する。
public struct MoveVector: Hashable, Codable {
    /// x 方向の移動量
    public let dx: Int
    /// y 方向の移動量
    public let dy: Int

    /// 公開イニシャライザ
    /// - Parameters:
    ///   - dx: x 方向へ加算する値
    ///   - dy: y 方向へ加算する値
    public init(dx: Int, dy: Int) {
        self.dx = dx
        self.dy = dy
    }
}

/// 手札スタックから盤面へ移動可能なカード情報を解決した結果を保持する構造体
/// - Note: スタック識別子・インデックス・カード種別・移動後座標など、UI とロジック双方で共有したい情報を 1 箇所へ集約する。
public struct ResolvedCardMove: Hashable {
    /// 対象スタックの一意な識別子
    public let stackID: UUID
    /// `handStacks` 内でのインデックス
    public let stackIndex: Int
    /// 実際に使用可能なカード（`DealtCard`）
    public let card: DealtCard
    /// 移動量をベクトルとして表現した値
    public let moveVector: MoveVector
    /// カード適用後に到達する座標
    public let destination: GridPoint

    /// カード種別を直接参照したいケース向けのヘルパー
    public var moveCard: MoveCard { card.move }

    /// 公開イニシャライザ
    /// - Parameters:
    ///   - stackID: スタックを識別する UUID
    ///   - stackIndex: `handStacks` 内での位置
    ///   - card: 使用対象の `DealtCard`
    ///   - moveVector: カードが持つ移動ベクトル
    ///   - destination: カード適用後の座標
    public init(
        stackID: UUID,
        stackIndex: Int,
        card: DealtCard,
        moveVector: MoveVector,
        destination: GridPoint
    ) {
        self.stackID = stackID
        self.stackIndex = stackIndex
        self.card = card
        self.moveVector = moveVector
        self.destination = destination
    }

    /// `Hashable` 準拠用の実装
    /// - Note: `DealtCard` 自体は `Hashable` へ準拠していないため、識別子と MoveCard を組み合わせて同一性を判定する。
    public func hash(into hasher: inout Hasher) {
        hasher.combine(stackID)
        hasher.combine(stackIndex)
        hasher.combine(card.id)
        hasher.combine(card.move)
        hasher.combine(moveVector)
        hasher.combine(destination)
    }

    /// `Equatable` 準拠用の比較演算子
    /// - Parameters:
    ///   - lhs: 比較元の値
    ///   - rhs: 比較先の値
    /// - Returns: 主要フィールドが一致する場合に true
    public static func == (lhs: ResolvedCardMove, rhs: ResolvedCardMove) -> Bool {
        lhs.stackID == rhs.stackID &&
        lhs.stackIndex == rhs.stackIndex &&
        lhs.card.id == rhs.card.id &&
        lhs.card.move == rhs.card.move &&
        lhs.moveVector == rhs.moveVector &&
        lhs.destination == rhs.destination
    }
}

