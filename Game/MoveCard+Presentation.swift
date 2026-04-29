import Foundation

public extension MoveCard {
    /// UI に表示する日本語の名前
    var displayName: String {
        switch self {
        case .kingUp:
            return "上1"
        case .kingUpRight:
            return "右上1"
        case .kingRight:
            return "右1"
        case .kingDownRight:
            return "右下1"
        case .kingDown:
            return "下1"
        case .kingDownLeft:
            return "左下1"
        case .kingLeft:
            return "左1"
        case .kingUpLeft:
            return "左上1"
        case .kingUpOrDown:
            return "上下1 (選択)"
        case .kingLeftOrRight:
            return "左右1 (選択)"
        case .kingUpwardDiagonalChoice:
            return "上斜め1 (選択)"
        case .kingRightDiagonalChoice:
            return "右斜め1 (選択)"
        case .kingDownwardDiagonalChoice:
            return "下斜め1 (選択)"
        case .kingLeftDiagonalChoice:
            return "左斜め1 (選択)"
        case .knightUp2Right1: return "上2右1"
        case .knightUp2Left1: return "上2左1"
        case .knightUp1Right2: return "上1右2"
        case .knightUp1Left2: return "上1左2"
        case .knightDown2Right1: return "下2右1"
        case .knightDown2Left1: return "下2左1"
        case .knightDown1Right2: return "下1右2"
        case .knightDown1Left2: return "下1左2"
        case .knightUpwardChoice: return "上桂 (選択)"
        case .knightRightwardChoice: return "右桂 (選択)"
        case .knightDownwardChoice: return "下桂 (選択)"
        case .knightLeftwardChoice: return "左桂 (選択)"
        case .straightUp2: return "上2"
        case .straightDown2: return "下2"
        case .straightRight2: return "右2"
        case .straightLeft2: return "左2"
        case .diagonalUpRight2: return "右上2"
        case .diagonalDownRight2: return "右下2"
        case .diagonalDownLeft2: return "左下2"
        case .diagonalUpLeft2: return "左上2"
        case .rayUp: return "上連続"
        case .rayUpRight: return "右上連続"
        case .rayRight: return "右連続"
        case .rayDownRight: return "右下連続"
        case .rayDown: return "下連続"
        case .rayDownLeft: return "左下連続"
        case .rayLeft: return "左連続"
        case .rayUpLeft: return "左上連続"
        case .superWarp: return "全域ワープ"
        case .fixedWarp: return "固定ワープ"
        case .targetStep: return "目的地ステップ"
        case .targetKnight: return "目的地ナイト"
        case .targetLine: return "目的地ライン"
        case .effectStep: return "特殊ステップ"
        case .effectKnight: return "特殊ナイト"
        case .effectLine: return "特殊ライン"
        }
    }

    /// カード種別の分類を返す
    var kind: MoveCardKind {
        switch self {
        case .kingUpOrDown,
             .kingLeftOrRight,
             .kingUpwardDiagonalChoice,
             .kingRightDiagonalChoice,
             .kingDownwardDiagonalChoice,
             .kingLeftDiagonalChoice,
             .knightUpwardChoice,
             .knightRightwardChoice,
             .knightDownwardChoice,
             .knightLeftwardChoice:
            return .choice
        case .targetStep,
             .targetKnight,
             .targetLine:
            return .targetAssist
        case .effectStep,
             .effectKnight,
             .effectLine:
            return .effectAssist
        default:
            return MoveCard.directionalRayCards.contains(self) ? .multiStep : .normal
        }
    }

    /// 連続直進カードが持つ単位方向ベクトルを返す
    var multiStepUnitVector: MoveVector? {
        guard kind == .multiStep else { return nil }
        switch self {
        case .rayUp:
            return MoveVector(dx: 0, dy: 1)
        case .rayUpRight:
            return MoveVector(dx: 1, dy: 1)
        case .rayRight:
            return MoveVector(dx: 1, dy: 0)
        case .rayDownRight:
            return MoveVector(dx: 1, dy: -1)
        case .rayDown:
            return MoveVector(dx: 0, dy: -1)
        case .rayDownLeft:
            return MoveVector(dx: -1, dy: -1)
        case .rayLeft:
            return MoveVector(dx: -1, dy: 0)
        case .rayUpLeft:
            return MoveVector(dx: -1, dy: 1)
        default:
            return nil
        }
    }

    /// 王将型（キング型）に該当するかを判定するフラグ
    var isKingType: Bool {
        switch self {
        case .kingUp,
             .kingUpRight,
             .kingRight,
             .kingDownRight,
             .kingDown,
             .kingDownLeft,
             .kingLeft,
             .kingUpLeft,
             .kingUpOrDown,
             .kingLeftOrRight,
             .kingUpwardDiagonalChoice,
             .kingRightDiagonalChoice,
             .kingDownwardDiagonalChoice,
             .kingLeftDiagonalChoice:
            return true
        default:
            return false
        }
    }

    /// ナイト型カードかどうかを判定するフラグ
    var isKnightType: Bool {
        switch self {
        case .knightUp2Right1,
             .knightUp2Left1,
             .knightUp1Right2,
             .knightUp1Left2,
             .knightDown2Right1,
             .knightDown2Left1,
             .knightDown1Right2,
             .knightDown1Left2,
             .knightUpwardChoice,
             .knightRightwardChoice,
             .knightDownwardChoice,
             .knightLeftwardChoice:
            return true
        default:
            return false
        }
    }

    /// 斜め 2 マス（マンハッタン距離 4）の長距離斜めカードかどうかを判定する
    var isDiagonalDistanceFour: Bool {
        switch self {
        case .diagonalUpRight2,
             .diagonalDownRight2,
             .diagonalDownLeft2,
             .diagonalUpLeft2:
            return true
        default:
            return false
        }
    }

    /// 盤端や障害物まで連続で進むレイ型カードかどうかを判定する
    var isDirectionalRay: Bool {
        switch self {
        case .rayUp,
             .rayUpRight,
             .rayRight,
             .rayDownRight,
             .rayDown,
             .rayDownLeft,
             .rayLeft,
             .rayUpLeft:
            return true
        default:
            return false
        }
    }
}

extension MoveCard: CustomStringConvertible {
    public var description: String { displayName }
}

extension MoveCard: Identifiable {
    public var id: UUID { UUID() }
}
