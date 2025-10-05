import Foundation

/// 盤面上の移動結果を経路付きで保持する構造体
/// - Important: 移動アニメーションやタイル効果適用後の最終座標を UI へ正確に伝えるため、開始地点を除外した経路情報と
///              効果発動履歴をひとまとめに管理する。
public struct MovementResolution: Equatable {
    /// タイル効果の適用履歴を表現するためのサブ構造体
    /// - Note: 効果が発動した座標と内容を記録し、UI 側で演出を切り替える際に利用することを想定している。
    public struct AppliedEffect: Equatable {
        /// 効果が発動した座標
        public let point: GridPoint
        /// 適用されたタイル効果
        public let effect: TileEffect

        /// イニシャライザ
        /// - Parameters:
        ///   - point: 効果が検出されたマス
        ///   - effect: 発動した効果内容
        public init(point: GridPoint, effect: TileEffect) {
            self.point = point
            self.effect = effect
        }
    }

    /// 始点を除いた経路一覧（移動順）
    public private(set) var path: [GridPoint]
    /// 効果適用後を含む最終到達地点
    public private(set) var finalPosition: GridPoint
    /// 経路中に発生した効果の履歴
    public private(set) var appliedEffects: [AppliedEffect]

    /// 経路を用いて初期化する
    /// - Parameters:
    ///   - path: 始点を除いた通過マス配列（最後の要素が目的地になるように並べる）
    ///   - finalPosition: 効果適用後の最終到達地点
    ///   - appliedEffects: 既に判明している効果履歴（通常は空配列で渡す）
    public init(path: [GridPoint], finalPosition: GridPoint, appliedEffects: [AppliedEffect] = []) {
        self.path = path
        self.finalPosition = finalPosition
        self.appliedEffects = appliedEffects
    }

    /// 経路を拡張し、最新の最終地点へ更新する
    /// - Parameter point: 追加したい座標
    public mutating func appendStep(_ point: GridPoint) {
        path.append(point)
        finalPosition = point
    }

    /// 効果の発動を記録する
    /// - Parameters:
    ///   - effect: 発動した効果
    ///   - point: 効果が検出された座標
    public mutating func recordEffect(_ effect: TileEffect, at point: GridPoint) {
        appliedEffects.append(AppliedEffect(point: point, effect: effect))
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
    /// 解決済みの経路情報
    public let resolution: MovementResolution
    /// 経路解決時点での代表移動ベクトル
    public let moveVector: MoveVector

    /// カード種別を直接参照したいケース向けのヘルパー
    public var moveCard: MoveCard { card.move }
    /// 最終到達地点を返すヘルパー
    public var destination: GridPoint { resolution.finalPosition }
    /// 通過マス一覧（目的地を含む）
    public var traversedPoints: [GridPoint] { resolution.path }
    /// 既存呼び出し互換用に `path` という名前でも公開する
    public var path: [GridPoint] { resolution.path }
    /// 効果履歴を公開する計算プロパティ
    public var appliedEffects: [MovementResolution.AppliedEffect] { resolution.appliedEffects }

    /// 公開イニシャライザ
    /// - Parameters:
    ///   - stackID: スタックを識別する UUID
    ///   - stackIndex: `handStacks` 内での位置
    ///   - card: 使用対象の `DealtCard`
    ///   - moveVector: 経路解決時点での代表ベクトル
    ///   - resolution: 経路および効果情報
    public init(
        stackID: UUID,
        stackIndex: Int,
        card: DealtCard,
        moveVector: MoveVector,
        resolution: MovementResolution
    ) {
        self.stackID = stackID
        self.stackIndex = stackIndex
        self.card = card
        self.moveVector = moveVector
        self.resolution = resolution
    }

    /// `Hashable` 準拠用の実装
    /// - Note: `DealtCard` 自体は `Hashable` へ準拠していないため、識別子と MoveCard を組み合わせて同一性を判定する。
    public func hash(into hasher: inout Hasher) {
        hasher.combine(stackID)
        hasher.combine(stackIndex)
        hasher.combine(card.id)
        hasher.combine(card.move)
        hasher.combine(moveVector.dx)
        hasher.combine(moveVector.dy)
        hasher.combine(resolution.finalPosition.x)
        hasher.combine(resolution.finalPosition.y)
        hasher.combine(resolution.path.count)
        for point in resolution.path {
            hasher.combine(point.x)
            hasher.combine(point.y)
        }
        hasher.combine(resolution.appliedEffects.count)
        for effect in resolution.appliedEffects {
            hasher.combine(effect.point.x)
            hasher.combine(effect.point.y)
            switch effect.effect {
            case .warp(let pairID, let destination):
                hasher.combine("warp")
                hasher.combine(pairID)
                hasher.combine(destination.x)
                hasher.combine(destination.y)
            case .shuffleHand:
                hasher.combine("shuffle")
            }
        }
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
        lhs.resolution == rhs.resolution
    }
}

