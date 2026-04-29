import Foundation

public extension MoveCard {
    /// 盤端まで伸びるレイ型カード 8 種の集合
    /// - Important: デッキ構築や重み設定でも頻繁に参照するため、定数として公開する
    static let directionalRayCards: [MoveCard] = [
        .rayUp,
        .rayUpRight,
        .rayRight,
        .rayDownRight,
        .rayDown,
        .rayDownLeft,
        .rayLeft,
        .rayUpLeft
    ]

    /// 標準デッキで採用している 32 種類のカード集合
    /// - Important: 選択式カードは含めず、単方向カードと連続レイ型カードのみで構成する
    static let standardSet: [MoveCard] = [
        .kingUp,
        .kingUpRight,
        .kingRight,
        .kingDownRight,
        .kingDown,
        .kingDownLeft,
        .kingLeft,
        .kingUpLeft,
        .knightUp2Right1,
        .knightUp2Left1,
        .knightUp1Right2,
        .knightUp1Left2,
        .knightDown2Right1,
        .knightDown2Left1,
        .knightDown1Right2,
        .knightDown1Left2,
        .straightUp2,
        .straightDown2,
        .straightRight2,
        .straightLeft2,
        .diagonalUpRight2,
        .diagonalDownRight2,
        .diagonalDownLeft2,
        .diagonalUpLeft2
    ] + directionalRayCards

    /// 目的地制モードでのみ候補を出す補助カード
    static let targetAssistCards: [MoveCard] = [
        .targetStep,
        .targetKnight,
        .targetLine
    ]

    /// 実験場向けに特殊効果マスへ近づく補助カード
    static let effectAssistCards: [MoveCard] = [
        .effectStep,
        .effectKnight,
        .effectLine
    ]

    /// `CaseIterable` の自動生成は internal となるため、外部モジュールからも全種類を参照できるよう明示的に公開配列を定義する
    /// - Note: スタンダードセットに複数方向カードを加えた順序で公開する
    static let allCases: [MoveCard] = standardSet + [
        .kingUpOrDown,
        .kingLeftOrRight,
        .kingUpwardDiagonalChoice,
        .kingRightDiagonalChoice,
        .kingDownwardDiagonalChoice,
        .kingLeftDiagonalChoice,
        .knightUpwardChoice,
        .knightRightwardChoice,
        .knightDownwardChoice,
        .knightLeftwardChoice,
        .superWarp,
        .fixedWarp
    ] + targetAssistCards + effectAssistCards
}
