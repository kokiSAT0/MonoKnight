import Foundation

/// ゲームルールを変えず、モノの移動を描き分けるための表示分類。
public enum PlayerMotionStyle: String, CaseIterable, Equatable, Sendable {
    case waddle
    case bellySlide
    case flutterJump
    case warp
    case fall
    case forcedSlide
}

public extension MoveCard {
    /// カードの移動規則から表示上の動きを決める。
    var playerMotionStyle: PlayerMotionStyle {
        switch self {
        case .rayUp, .rayUpRight, .rayRight, .rayDownRight,
             .rayDown, .rayDownLeft, .rayLeft, .rayUpLeft,
             .straightUp2, .straightDown2, .straightRight2, .straightLeft2,
             .diagonalUpRight2, .diagonalDownRight2, .diagonalDownLeft2, .diagonalUpLeft2:
            return .bellySlide
        case .knightUp2Right1, .knightUp2Left1, .knightUp1Right2, .knightUp1Left2,
             .knightDown2Right1, .knightDown2Left1, .knightDown1Right2, .knightDown1Left2,
             .knightUpwardChoice, .knightRightwardChoice, .knightDownwardChoice, .knightLeftwardChoice:
            return .flutterJump
        case .kingUpRight, .kingDownRight, .kingDownLeft, .kingUpLeft,
             .kingUpwardDiagonalChoice, .kingRightDiagonalChoice,
             .kingDownwardDiagonalChoice, .kingLeftDiagonalChoice,
             .straightUp1, .straightDown1, .straightRight1, .straightLeft1:
            return .waddle
        }
    }
}

public extension ResolvedCardMove {
    var playerMotionStyle: PlayerMotionStyle { moveCard.playerMotionStyle }
}
