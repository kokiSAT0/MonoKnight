import Foundation

/// 駒を移動させるカードの種類を定義する列挙型
/// - Note: 周囲 1 マスのキング型 8 種、ナイト型 8 種、距離 2 の直線/斜め 8 種の計 24 種をサポート
public enum MoveCard: CaseIterable {
    /// `CaseIterable` の自動生成は internal となるため、外部モジュールからも全種類を参照できるよう明示的に公開配列を定義する
    public static let allCases: [MoveCard] = [
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
    ]
    // MARK: - ケース定義
    /// キング型: 上に 1
    case kingUp
    /// キング型: 右上に 1
    case kingUpRight
    /// キング型: 右に 1
    case kingRight
    /// キング型: 右下に 1
    case kingDownRight
    /// キング型: 下に 1
    case kingDown
    /// キング型: 左下に 1
    case kingDownLeft
    /// キング型: 左に 1
    case kingLeft
    /// キング型: 左上に 1
    case kingUpLeft

    /// ナイト型: 上に 2、右に 1
    case knightUp2Right1
    /// ナイト型: 上に 2、左に 1
    case knightUp2Left1
    /// ナイト型: 上に 1、右に 2
    case knightUp1Right2
    /// ナイト型: 上に 1、左に 2
    case knightUp1Left2
    /// ナイト型: 下に 2、右に 1
    case knightDown2Right1
    /// ナイト型: 下に 2、左に 1
    case knightDown2Left1
    /// ナイト型: 下に 1、右に 2
    case knightDown1Right2
    /// ナイト型: 下に 1、左に 2
    case knightDown1Left2

    /// 直線: 上に 2
    case straightUp2
    /// 直線: 下に 2
    case straightDown2
    /// 直線: 右に 2
    case straightRight2
    /// 直線: 左に 2
    case straightLeft2

    /// 斜め: 右上に 2
    case diagonalUpRight2
    /// 斜め: 右下に 2
    case diagonalDownRight2
    /// 斜め: 左下に 2
    case diagonalDownLeft2
    /// 斜め: 左上に 2
    case diagonalUpLeft2

    // MARK: - 移動量
    /// x 方向の移動量
    public var dx: Int {
        switch self {
        case .kingUp: return 0
        case .kingUpRight: return 1
        case .kingRight: return 1
        case .kingDownRight: return 1
        case .kingDown: return 0
        case .kingDownLeft: return -1
        case .kingLeft: return -1
        case .kingUpLeft: return -1
        case .knightUp2Right1: return 1
        case .knightUp2Left1: return -1
        case .knightUp1Right2: return 2
        case .knightUp1Left2: return -2
        case .knightDown2Right1: return 1
        case .knightDown2Left1: return -1
        case .knightDown1Right2: return 2
        case .knightDown1Left2: return -2
        case .straightUp2: return 0
        case .straightDown2: return 0
        case .straightRight2: return 2
        case .straightLeft2: return -2
        case .diagonalUpRight2: return 2
        case .diagonalDownRight2: return 2
        case .diagonalDownLeft2: return -2
        case .diagonalUpLeft2: return -2
        }
    }

    /// y 方向の移動量
    public var dy: Int {
        switch self {
        case .kingUp: return 1
        case .kingUpRight: return 1
        case .kingRight: return 0
        case .kingDownRight: return -1
        case .kingDown: return -1
        case .kingDownLeft: return -1
        case .kingLeft: return 0
        case .kingUpLeft: return 1
        case .knightUp2Right1: return 2
        case .knightUp2Left1: return 2
        case .knightUp1Right2: return 1
        case .knightUp1Left2: return 1
        case .knightDown2Right1: return -2
        case .knightDown2Left1: return -2
        case .knightDown1Right2: return -1
        case .knightDown1Left2: return -1
        case .straightUp2: return 2
        case .straightDown2: return -2
        case .straightRight2: return 0
        case .straightLeft2: return 0
        case .diagonalUpRight2: return 2
        case .diagonalDownRight2: return -2
        case .diagonalDownLeft2: return -2
        case .diagonalUpLeft2: return 2
        }
    }

    // MARK: - UI 表示名
    /// UI に表示する日本語の名前
    public var displayName: String {
        switch self {
        case .kingUp:
            // キング型: 上方向へ 1 マス移動
            return "上1"
        case .kingUpRight:
            // キング型: 右上方向へ 1 マス移動
            return "右上1"
        case .kingRight:
            // キング型: 右方向へ 1 マス移動
            return "右1"
        case .kingDownRight:
            // キング型: 右下方向へ 1 マス移動
            return "右下1"
        case .kingDown:
            // キング型: 下方向へ 1 マス移動
            return "下1"
        case .kingDownLeft:
            // キング型: 左下方向へ 1 マス移動
            return "左下1"
        case .kingLeft:
            // キング型: 左方向へ 1 マス移動
            return "左1"
        case .kingUpLeft:
            // キング型: 左上方向へ 1 マス移動
            return "左上1"
        case .knightUp2Right1: return "上2右1"
        case .knightUp2Left1: return "上2左1"
        case .knightUp1Right2: return "上1右2"
        case .knightUp1Left2: return "上1左2"
        case .knightDown2Right1: return "下2右1"
        case .knightDown2Left1: return "下2左1"
        case .knightDown1Right2: return "下1右2"
        case .knightDown1Left2: return "下1左2"
        case .straightUp2: return "上2"
        case .straightDown2: return "下2"
        case .straightRight2: return "右2"
        case .straightLeft2: return "左2"
        case .diagonalUpRight2: return "右上2"
        case .diagonalDownRight2: return "右下2"
        case .diagonalDownLeft2: return "左下2"
        case .diagonalUpLeft2: return "左上2"
        }
    }

    // MARK: - 属性判定
    /// 王将型（キング型）に該当するかを判定するフラグ
    /// - Note: デッキ構築時の配分調整に利用する
    public var isKingType: Bool {
        switch self {
        case .kingUp,
             .kingUpRight,
             .kingRight,
             .kingDownRight,
             .kingDown,
             .kingDownLeft,
             .kingLeft,
             .kingUpLeft:
            return true
        default:
            return false
        }
    }

    /// ナイト型カードかどうかを判定するフラグ
    /// - Note: 山札内で桂馬カードの重み付けを計算するために利用する
    public var isKnightType: Bool {
        switch self {
        case .knightUp2Right1,
             .knightUp2Left1,
             .knightUp1Right2,
             .knightUp1Left2,
             .knightDown2Right1,
             .knightDown2Left1,
             .knightDown1Right2,
             .knightDown1Left2:
            return true
        default:
            return false
        }
    }

    /// 斜め 2 マス（マンハッタン距離 4）の長距離斜めカードかどうかを判定する
    /// - Note: 山札の重み調整（桂馬カードの半分の排出確率）に利用する
    public var isDiagonalDistanceFour: Bool {
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

    // MARK: - 利用判定
    /// 指定した座標からこのカードが使用可能か判定する
    /// - Parameter from: 現在位置
    /// - Returns: 盤内に移動できる場合は true
    public func canUse(from: GridPoint) -> Bool {
        let destination = from.offset(dx: dx, dy: dy)
        return destination.isInside
    }
}

// MARK: - デバッグ用表示名
extension MoveCard: CustomStringConvertible {
    /// デバッグログでカード名をわかりやすくするため displayName を返す
    public var description: String { displayName }
}

// MARK: - Identifiable への適合
extension MoveCard: Identifiable {
    /// `Identifiable` 準拠のための一意な識別子
    /// ここでは単純に UUID を生成して返す
    /// - Note: 山札で同種カードが複数枚存在するため
    ///         各カードインスタンスを区別する目的で利用する
    public var id: UUID { UUID() }
}

