import Foundation

/// 駒を移動させるカードの種類を定義する列挙型
/// - Note: 周囲 1 マスのキング型 8 種、ナイト型 8 種、距離 2 の直線/斜め 8 種の計 24 種に加え、キャンペーン専用の複数方向カードをサポート
/// - Note: SwiftUI モジュールからも扱うため `public` とし、全ケース配列も公開する
public enum MoveCard: CaseIterable {
    // MARK: - 定義済みセット
    /// 標準デッキで採用している 24 種類のカード集合
    /// - Important: 新しいカードを追加した際もスタンダード構成へ混入しないよう、この配列を基準に管理する
    public static let standardSet: [MoveCard] = [
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

    // MARK: - 全ケース一覧
    /// `CaseIterable` の自動生成は internal となるため、外部モジュールからも全種類を参照できるよう明示的に公開配列を定義する
    /// - Note: スタンダードセットに複数方向カードを加えた順序で公開する
    public static let allCases: [MoveCard] = standardSet + [
        .kingUpOrDown,
        .kingLeftOrRight,
        .kingUpwardDiagonalChoice,
        .kingRightDiagonalChoice,
        .kingDownwardDiagonalChoice,
        .kingLeftDiagonalChoice,
        .knightUpwardChoice,
        .knightRightwardChoice,
        .knightDownwardChoice,
        .knightLeftwardChoice
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
    /// キング型: 上下いずれか 1 マスの選択移動
    case kingUpOrDown
    /// キング型: 左右いずれか 1 マスの選択移動
    case kingLeftOrRight
    /// キング型: 上方向の斜め 2 方向（右上・左上）から選択するカード
    case kingUpwardDiagonalChoice
    /// キング型: 右方向の斜め 2 方向（右上・右下）から選択するカード
    case kingRightDiagonalChoice
    /// キング型: 下方向の斜め 2 方向（右下・左下）から選択するカード
    case kingDownwardDiagonalChoice
    /// キング型: 左方向の斜め 2 方向（左上・左下）から選択するカード
    case kingLeftDiagonalChoice

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
    /// ナイト型: 上方向 2 種（上2右1/上2左1）から選択するカード
    case knightUpwardChoice
    /// ナイト型: 右方向 2 種（上1右2/下1右2）から選択するカード
    case knightRightwardChoice
    /// ナイト型: 下方向 2 種（下2右1/下2左1）から選択するカード
    case knightDownwardChoice
    /// ナイト型: 左方向 2 種（上1左2/下1左2）から選択するカード
    case knightLeftwardChoice

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

    // MARK: - 移動ベクトル
    /// カードが持つ移動候補一覧を返す
    /// - Important: 現行カードは 1 要素のみだが、今後複数候補を持つカード追加時に拡張しやすいよう配列で保持する
    /// テスト向けに movementVectors を差し替えるためのオーバーライド辞書
    /// - Note: テスト完了後は必ず nil を指定してクリーンアップし、副作用を残さないようにする
    static var testMovementVectorOverrides: [MoveCard: [MoveVector]] = [:]

    /// movementVectors を一時的に差し替えるヘルパー
    /// - Parameters:
    ///   - vectors: 差し替え後の移動ベクトル配列。nil を渡すと元の定義に戻す。
    ///   - card: 対象となるカード種別
    static func setTestMovementVectors(_ vectors: [MoveVector]?, for card: MoveCard) {
        if let vectors {
            testMovementVectorOverrides[card] = vectors
        } else {
            testMovementVectorOverrides.removeValue(forKey: card)
        }
    }

    public var movementVectors: [MoveVector] {
        if let override = MoveCard.testMovementVectorOverrides[self] {
            return override
        }
        switch self {
        case .kingUp:
            return [MoveVector(dx: 0, dy: 1)]
        case .kingUpRight:
            return [MoveVector(dx: 1, dy: 1)]
        case .kingRight:
            return [MoveVector(dx: 1, dy: 0)]
        case .kingDownRight:
            return [MoveVector(dx: 1, dy: -1)]
        case .kingDown:
            return [MoveVector(dx: 0, dy: -1)]
        case .kingDownLeft:
            return [MoveVector(dx: -1, dy: -1)]
        case .kingLeft:
            return [MoveVector(dx: -1, dy: 0)]
        case .kingUpLeft:
            return [MoveVector(dx: -1, dy: 1)]
        case .kingUpOrDown:
            // 上下方向のいずれかを後から選択するため 2 候補を返す
            return [
                MoveVector(dx: 0, dy: 1),
                MoveVector(dx: 0, dy: -1)
            ]
        case .kingLeftOrRight:
            // 左右方向のいずれかを後から選択するため 2 候補を返す
            return [
                MoveVector(dx: 1, dy: 0),
                MoveVector(dx: -1, dy: 0)
            ]
        case .kingUpwardDiagonalChoice:
            // 上方向の斜め 2 方向（右上・左上）をまとめて扱うカード
            return [
                MoveVector(dx: 1, dy: 1),
                MoveVector(dx: -1, dy: 1)
            ]
        case .kingRightDiagonalChoice:
            // 右方向へ伸びる斜め 2 方向（右上・右下）をまとめて扱うカード
            return [
                MoveVector(dx: 1, dy: 1),
                MoveVector(dx: 1, dy: -1)
            ]
        case .kingDownwardDiagonalChoice:
            // 下方向の斜め 2 方向（右下・左下）をまとめて扱うカード
            return [
                MoveVector(dx: 1, dy: -1),
                MoveVector(dx: -1, dy: -1)
            ]
        case .kingLeftDiagonalChoice:
            // 左方向の斜め 2 方向（左上・左下）をまとめて扱うカード
            return [
                MoveVector(dx: -1, dy: 1),
                MoveVector(dx: -1, dy: -1)
            ]
        case .knightUp2Right1:
            return [MoveVector(dx: 1, dy: 2)]
        case .knightUp2Left1:
            return [MoveVector(dx: -1, dy: 2)]
        case .knightUp1Right2:
            return [MoveVector(dx: 2, dy: 1)]
        case .knightUp1Left2:
            return [MoveVector(dx: -2, dy: 1)]
        case .knightDown2Right1:
            return [MoveVector(dx: 1, dy: -2)]
        case .knightDown2Left1:
            return [MoveVector(dx: -1, dy: -2)]
        case .knightDown1Right2:
            return [MoveVector(dx: 2, dy: -1)]
        case .knightDown1Left2:
            return [MoveVector(dx: -2, dy: -1)]
        case .knightUpwardChoice:
            // 上方向の桂馬 2 種をまとめた特別カード
            return [
                MoveVector(dx: 1, dy: 2),
                MoveVector(dx: -1, dy: 2)
            ]
        case .knightRightwardChoice:
            // 右方向の桂馬 2 種をまとめた特別カード
            return [
                MoveVector(dx: 2, dy: 1),
                MoveVector(dx: 2, dy: -1)
            ]
        case .knightDownwardChoice:
            // 下方向の桂馬 2 種をまとめた特別カード
            return [
                MoveVector(dx: 1, dy: -2),
                MoveVector(dx: -1, dy: -2)
            ]
        case .knightLeftwardChoice:
            // 左方向の桂馬 2 種をまとめた特別カード
            return [
                MoveVector(dx: -2, dy: 1),
                MoveVector(dx: -2, dy: -1)
            ]
        case .straightUp2:
            return [MoveVector(dx: 0, dy: 2)]
        case .straightDown2:
            return [MoveVector(dx: 0, dy: -2)]
        case .straightRight2:
            return [MoveVector(dx: 2, dy: 0)]
        case .straightLeft2:
            return [MoveVector(dx: -2, dy: 0)]
        case .diagonalUpRight2:
            return [MoveVector(dx: 2, dy: 2)]
        case .diagonalDownRight2:
            return [MoveVector(dx: 2, dy: -2)]
        case .diagonalDownLeft2:
            return [MoveVector(dx: -2, dy: -2)]
        case .diagonalUpLeft2:
            return [MoveVector(dx: -2, dy: 2)]
        }
    }

    /// 既存コードとの互換性を維持するための代表ベクトル
    /// - Note: 候補が複数化した際は UI 側での選択ロジックを追加しやすいよう、先頭要素を共通の入口として公開する
    public var primaryVector: MoveVector {
        guard let vector = movementVectors.first else {
            assertionFailure("MoveCard.movementVectors は最低 1 要素を想定している")
            return MoveVector(dx: 0, dy: 0)
        }
        return vector
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
        case .kingUpOrDown:
            // キング型: 上下のどちらか 1 マスを選択する特別カード
            return "上下1 (選択)"
        case .kingLeftOrRight:
            // キング型: 左右のどちらか 1 マスを選択する特別カード
            return "左右1 (選択)"
        case .kingUpwardDiagonalChoice:
            // キング型: 左右の上斜めから好みの方向を選ぶ特別カード
            return "上斜め1 (選択)"
        case .kingRightDiagonalChoice:
            // キング型: 上下の右斜めから好みの方向を選ぶ特別カード
            return "右斜め1 (選択)"
        case .kingDownwardDiagonalChoice:
            // キング型: 左右の下斜めから好みの方向を選ぶ特別カード
            return "下斜め1 (選択)"
        case .kingLeftDiagonalChoice:
            // キング型: 上下の左斜めから好みの方向を選ぶ特別カード
            return "左斜め1 (選択)"
        case .knightUp2Right1: return "上2右1"
        case .knightUp2Left1: return "上2左1"
        case .knightUp1Right2: return "上1右2"
        case .knightUp1Left2: return "上1左2"
        case .knightDown2Right1: return "下2右1"
        case .knightDown2Left1: return "下2左1"
        case .knightDown1Right2: return "下1右2"
        case .knightDown1Left2: return "下1左2"
        case .knightUpwardChoice:
            // 桂馬型: 上方向 2 種から好みを選べる特別カード
            return "上桂 (選択)"
        case .knightRightwardChoice:
            // 桂馬型: 右方向 2 種から好みを選べる特別カード
            return "右桂 (選択)"
        case .knightDownwardChoice:
            // 桂馬型: 下方向 2 種から好みを選べる特別カード
            return "下桂 (選択)"
        case .knightLeftwardChoice:
            // 桂馬型: 左方向 2 種から好みを選べる特別カード
            return "左桂 (選択)"
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
    /// - Parameters:
    ///   - from: 現在位置
    ///   - boardSize: 判定対象となる盤面サイズ
    /// - Returns: 盤内に移動できる場合は true
    public func canUse(from: GridPoint, boardSize: Int) -> Bool {
        // 複数候補ベクトルのいずれかが盤内に入れば使用可能とみなす
        // - Note: 既存カードは 1 要素だが、将来カードの拡張で順不同のベクトルが混在しても安全に判定できるようにする
        return movementVectors.contains { vector in
            // 各ベクトルで移動した先が盤内に収まるか逐一確認する
            let destination = from.offset(dx: vector.dx, dy: vector.dy)
            return destination.isInside(boardSize: boardSize)
        }
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
