import Foundation

/// ヘルプ内のカード辞典で表示する 1 件分の情報
public struct MoveCardEncyclopediaEntry: Identifiable, Equatable {
    public let id: Int
    public let card: MoveCard
    public let displayName: String
    public let category: String
    public let description: String

    public init(id: Int, card: MoveCard, displayName: String, category: String, description: String) {
        self.id = id
        self.card = card
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
        case .targetAssist:
            return "目的地補助"
        case .effectAssist:
            return "特殊マス補助"
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
        case .targetStep:
            return "表示中の目的地へ近づく 1 マス移動候補だけを表示します。"
        case .targetKnight:
            return "表示中の目的地へ近づくナイト移動候補だけを表示します。"
        case .targetLine:
            return "表示中の目的地方向へ通りやすい直線候補だけを表示します。"
        case .effectStep:
            return "最寄りの特殊マスへ近づく 1 マス移動候補だけを表示します。"
        case .effectKnight:
            return "最寄りの特殊マスへ近づくナイト移動候補だけを表示します。"
        case .effectLine:
            return "最寄りの特殊マス方向へ通りやすい直線候補だけを表示します。"
        }
    }

    /// カード辞典に表示する全カード
    static var encyclopediaEntries: [MoveCardEncyclopediaEntry] {
        allCases.enumerated().map { index, card in
            MoveCardEncyclopediaEntry(
                id: index,
                card: card,
                displayName: card.displayName,
                category: card.encyclopediaCategory,
                description: card.encyclopediaDescription
            )
        }
    }
}
