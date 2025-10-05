import Foundation

/// カードプレイ時に算出した移動経路と副次効果の結果を保持する構造体
/// - Important: UI とゲームロジックの双方で同じ情報を参照できるよう、スタック識別子や選択ベクトルに加えて
///   経路上の座標配列や検出済みタイル効果もまとめて保持する
public struct MovementResolution: Hashable {
    /// 対象スタックの一意な識別子
    public let stackID: UUID
    /// `handStacks` 内でのインデックス
    public let stackIndex: Int
    /// 実際に使用可能なカード（`DealtCard`）
    public let card: DealtCard
    /// ユーザーが選択した移動ベクトル
    public let moveVector: MoveVector
    /// 始点を除外した移動経路（順序通りに訪問するマス）
    public let path: [GridPoint]
    /// 最終的に到達する座標（ワープ等で変化する場合も考慮）
    public let finalPosition: GridPoint
    /// 経路上で発動するタイル効果一覧（順序は発生順）
    public let appliedEffects: [TileEffect]

    /// カード種別へアクセスするためのヘルパー
    public var moveCard: MoveCard { card.move }

    /// 公開イニシャライザ
    /// - Parameters:
    ///   - stackID: スタックを識別する UUID
    ///   - stackIndex: `handStacks` 内での位置
    ///   - card: 使用対象の `DealtCard`
    ///   - moveVector: 適用する移動ベクトル
    ///   - path: 始点を除外した移動経路
    ///   - finalPosition: タイル効果を含めて決定した最終座標
    ///   - appliedEffects: 経路上で検出されたタイル効果（存在しない場合は空配列）
    public init(
        stackID: UUID,
        stackIndex: Int,
        card: DealtCard,
        moveVector: MoveVector,
        path: [GridPoint],
        finalPosition: GridPoint,
        appliedEffects: [TileEffect] = []
    ) {
        self.stackID = stackID
        self.stackIndex = stackIndex
        self.card = card
        self.moveVector = moveVector
        self.path = path
        self.finalPosition = finalPosition
        self.appliedEffects = appliedEffects
    }

    /// `Hashable` 準拠用の実装
    /// - Note: `DealtCard` 自体は `Hashable` へ準拠していないため、識別子と MoveCard を組み合わせて同一性を判定する
    public func hash(into hasher: inout Hasher) {
        hasher.combine(stackID)
        hasher.combine(stackIndex)
        hasher.combine(card.id)
        hasher.combine(card.move)
        hasher.combine(moveVector)
        hasher.combine(path)
        hasher.combine(finalPosition)
        hasher.combine(appliedEffects)
    }

    /// `Equatable` 準拠用の比較演算子
    /// - Parameters:
    ///   - lhs: 比較元の値
    ///   - rhs: 比較先の値
    /// - Returns: 主要フィールドが一致する場合に true
    public static func == (lhs: MovementResolution, rhs: MovementResolution) -> Bool {
        lhs.stackID == rhs.stackID &&
        lhs.stackIndex == rhs.stackIndex &&
        lhs.card.id == rhs.card.id &&
        lhs.card.move == rhs.card.move &&
        lhs.moveVector == rhs.moveVector &&
        lhs.path == rhs.path &&
        lhs.finalPosition == rhs.finalPosition &&
        lhs.appliedEffects == rhs.appliedEffects
    }
}
