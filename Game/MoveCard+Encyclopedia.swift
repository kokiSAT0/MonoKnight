import Foundation

/// ヘルプ内のカード辞典で表示する 1 件分の情報
public struct MoveCardEncyclopediaEntry: Identifiable, Equatable {
    public let id: Int
    public let card: MoveCard
    public let includedCards: [MoveCard]
    public let displayName: String
    public let category: String
    public let description: String

    public init(
        id: Int,
        card: MoveCard,
        includedCards: [MoveCard]? = nil,
        displayName: String,
        category: String,
        description: String
    ) {
        self.id = id
        self.card = card
        self.includedCards = includedCards ?? [card]
        self.displayName = displayName
        self.category = category
        self.description = description
    }
}

public extension MoveCard {
    /// カード辞典で使う分類名
    var encyclopediaCategory: String {
        switch kind {
        case .choice:
            return isKnightType ? "選択ナイト" : "選択キング"
        case .multiStep:
            return "レイ"
        case .normal:
            if isKingType {
                return "キング"
            } else if isKnightType {
                return "ナイト"
            } else if isDiagonalDistanceFour {
                return "斜め2マス"
            } else if self == .superWarp || self == .fixedWarp {
                return "ワープ"
            } else {
                return "直線2マス"
            }
        }
    }

    /// カード辞典で使う説明文
    var encyclopediaDescription: String {
        switch self {
        case .kingUp, .kingUpRight, .kingRight, .kingDownRight, .kingDown, .kingDownLeft, .kingLeft, .kingUpLeft:
            return "\(displayName)へ 1 マス進みます。小回りが利き、目的地への微調整に使いやすい基本カードです。"
        case .kingUpOrDown:
            return "上か下のどちらか 1 マスを盤面上で選んで進みます。"
        case .kingLeftOrRight:
            return "左か右のどちらか 1 マスを盤面上で選んで進みます。"
        case .kingUpwardDiagonalChoice:
            return "右上か左上のどちらか 1 マスを盤面上で選んで進みます。"
        case .kingRightDiagonalChoice:
            return "右上か右下のどちらか 1 マスを盤面上で選んで進みます。"
        case .kingDownwardDiagonalChoice:
            return "右下か左下のどちらか 1 マスを盤面上で選んで進みます。"
        case .kingLeftDiagonalChoice:
            return "左上か左下のどちらか 1 マスを盤面上で選んで進みます。"
        case .knightUp2Right1, .knightUp2Left1, .knightUp1Right2, .knightUp1Left2,
             .knightDown2Right1, .knightDown2Left1, .knightDown1Right2, .knightDown1Left2:
            return "\(displayName)へ L 字に跳びます。途中のマスは通らず、離れた目的地を狙えます。"
        case .knightUpwardChoice:
            return "上2右1か上2左1のどちらかを盤面上で選んで跳びます。"
        case .knightRightwardChoice:
            return "上1右2か下1右2のどちらかを盤面上で選んで跳びます。"
        case .knightDownwardChoice:
            return "下2右1か下2左1のどちらかを盤面上で選んで跳びます。"
        case .knightLeftwardChoice:
            return "上1左2か下1左2のどちらかを盤面上で選んで跳びます。"
        case .straightUp2, .straightDown2, .straightRight2, .straightLeft2:
            return "\(displayName)へ 2 マス進みます。目的地まで距離を詰めたいときに有効です。"
        case .diagonalUpRight2, .diagonalDownRight2, .diagonalDownLeft2, .diagonalUpLeft2:
            return "\(displayName)へ斜めに 2 マス進みます。大きく位置を変えたい場面で役立ちます。"
        case .rayUp, .rayUpRight, .rayRight, .rayDownRight, .rayDown, .rayDownLeft, .rayLeft, .rayUpLeft:
            return "\(displayName)方向へ、盤端や障害物の手前まで連続で進みます。通過したマスも踏破対象になります。"
        case .superWarp:
            return "盤面上の有効なマスから移動先を選んでワープします。遠い目的地へ一気に届く特殊カードです。"
        case .fixedWarp:
            return "モードで指定された固定座標へワープします。行き先はステージ設定に従います。"
        }
    }

    /// カード辞典に表示する代表項目
    static var encyclopediaEntries: [MoveCardEncyclopediaEntry] {
        [
            MoveCardEncyclopediaEntry(
                id: 0,
                card: .kingUp,
                includedCards: [
                    .kingUp,
                    .kingUpRight,
                    .kingRight,
                    .kingDownRight,
                    .kingDown,
                    .kingDownLeft,
                    .kingLeft,
                    .kingUpLeft
                ],
                displayName: "キング1マス",
                category: "キング",
                description: "上下左右・斜めのいずれかへ 1 マス進みます。小回りが利き、目的地への微調整に使いやすい基本カードです。"
            ),
            MoveCardEncyclopediaEntry(
                id: 1,
                card: .knightUp2Right1,
                includedCards: [
                    .knightUp2Right1,
                    .knightUp2Left1,
                    .knightUp1Right2,
                    .knightUp1Left2,
                    .knightDown2Right1,
                    .knightDown2Left1,
                    .knightDown1Right2,
                    .knightDown1Left2
                ],
                displayName: "ナイト",
                category: "ナイト",
                description: "縦横どちらかへ 2 マス、もう片方へ 1 マスの L 字に跳びます。途中のマスは通らず、離れた目的地を狙えます。"
            ),
            MoveCardEncyclopediaEntry(
                id: 2,
                card: .straightUp2,
                includedCards: [
                    .straightUp2,
                    .straightDown2,
                    .straightRight2,
                    .straightLeft2
                ],
                displayName: "直線2マス",
                category: "直線2マス",
                description: "上下左右のいずれかへ 2 マス進みます。目的地まで距離を詰めたいときに有効です。"
            ),
            MoveCardEncyclopediaEntry(
                id: 3,
                card: .diagonalUpRight2,
                includedCards: [
                    .diagonalUpRight2,
                    .diagonalDownRight2,
                    .diagonalDownLeft2,
                    .diagonalUpLeft2
                ],
                displayName: "斜め2マス",
                category: "斜め2マス",
                description: "斜め4方向のいずれかへ 2 マス進みます。大きく位置を変えたい場面で役立ちます。"
            ),
            MoveCardEncyclopediaEntry(
                id: 4,
                card: .rayUp,
                includedCards: directionalRayCards,
                displayName: "レイ",
                category: "レイ",
                description: "8方向のいずれかへ、盤端や障害物の手前まで連続で進みます。通過したマスも踏破対象になります。"
            ),
            MoveCardEncyclopediaEntry(
                id: 5,
                card: .kingUpOrDown,
                includedCards: [
                    .kingUpOrDown,
                    .kingLeftOrRight,
                    .kingUpwardDiagonalChoice,
                    .kingRightDiagonalChoice,
                    .kingDownwardDiagonalChoice,
                    .kingLeftDiagonalChoice
                ],
                displayName: "選択キング",
                category: "選択キング",
                description: "上下・左右・斜めペアの候補から、盤面上で進む 1 マスを選びます。"
            ),
            MoveCardEncyclopediaEntry(
                id: 6,
                card: .knightUpwardChoice,
                includedCards: [
                    .knightUpwardChoice,
                    .knightRightwardChoice,
                    .knightDownwardChoice,
                    .knightLeftwardChoice
                ],
                displayName: "選択ナイト",
                category: "選択ナイト",
                description: "方向別の 2 つのナイト移動候補から、盤面上で跳ぶ先を選びます。"
            ),
            MoveCardEncyclopediaEntry(
                id: 7,
                card: .superWarp,
                displayName: MoveCard.superWarp.displayName,
                category: MoveCard.superWarp.encyclopediaCategory,
                description: MoveCard.superWarp.encyclopediaDescription
            ),
            MoveCardEncyclopediaEntry(
                id: 8,
                card: .fixedWarp,
                displayName: MoveCard.fixedWarp.displayName,
                category: MoveCard.fixedWarp.encyclopediaCategory,
                description: MoveCard.fixedWarp.encyclopediaDescription
            )
        ]
    }
}
