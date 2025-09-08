import Foundation

/// 駒を移動させるカードの種類を定義する列挙型
/// - Note: ナイト型 8 種と距離 2 の直線/斜め 8 種の計 16 種をサポート
enum MoveCard: CaseIterable {
    // MARK: - ケース定義
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
    var dx: Int {
        switch self {
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
    var dy: Int {
        switch self {
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
    var displayName: String {
        switch self {
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

    // MARK: - 利用判定
    /// 指定した座標からこのカードが使用可能か判定する
    /// - Parameter from: 現在位置
    /// - Returns: 盤内に移動できる場合は true
    func canUse(from: GridPoint) -> Bool {
        let destination = from.offset(dx: dx, dy: dy)
        return destination.isInside
    }
}

// MARK: - Identifiable への適合
extension MoveCard: Identifiable {
    /// `Identifiable` 準拠のための一意な識別子
    /// ここでは単純に UUID を生成して返す
    /// - Note: 山札で同種カードが複数枚存在するため
    ///         各カードインスタンスを区別する目的で利用する
    var id: UUID { UUID() }
}

