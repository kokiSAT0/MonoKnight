import Foundation

/// カードの識別カテゴリを表す列挙体
/// - Important: UI 側での描画分岐やアクセシビリティ文言の差し替えに利用するため、`public` で公開しておく
public enum MoveCardKind {
    /// 単一の移動先を持つ標準カード
    case normal
    /// 盤面上で複数候補から方向を選ぶカード
    case choice
    /// 障害物か盤端まで直進し続ける複数マス移動カード
    case multiStep
    /// 表示中の目的地へ近づく候補を動的に出す補助カード
    case targetAssist
    /// 盤面上の特殊マスへ近づく候補を動的に出す補助カード
    case effectAssist
}

/// 駒を移動させるカードの種類を定義する列挙型
/// - Note: 周囲 1 マスのキング型 8 種、ナイト型 8 種、距離 2 の直線/斜め 8 種の計 24 種に加え、キャンペーン専用の複数方向カードや
///         盤面全域ワープといった特殊カードをサポート
/// - Note: SwiftUI モジュールからも扱うため `public` とし、全ケース配列も公開する
public enum MoveCard: CaseIterable {
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

    /// レイ型: 上方向へ障害物まで連続移動
    case rayUp
    /// レイ型: 右上方向へ障害物まで連続移動
    case rayUpRight
    /// レイ型: 右方向へ障害物まで連続移動
    case rayRight
    /// レイ型: 右下方向へ障害物まで連続移動
    case rayDownRight
    /// レイ型: 下方向へ障害物まで連続移動
    case rayDown
    /// レイ型: 左下方向へ障害物まで連続移動
    case rayDownLeft
    /// レイ型: 左方向へ障害物まで連続移動
    case rayLeft
    /// レイ型: 左上方向へ障害物まで連続移動
    case rayUpLeft

    /// 特殊: 盤面全域から未踏マスを選択して瞬間移動するカード
    case superWarp
    /// 特殊: モードで指定された固定座標へワープするカード
    case fixedWarp

    /// 目的地補助: 表示中の目的地へ近づく隣接 1 マス候補
    case targetStep
    /// 目的地補助: 表示中の目的地へ近づく桂馬候補
    case targetKnight
    /// 目的地補助: 表示中の目的地方向へ通過しやすい直線候補
    case targetLine
    /// 特殊マス補助: 最寄り特殊マスへ近づく隣接 1 マス候補
    case effectStep
    /// 特殊マス補助: 最寄り特殊マスへ近づく桂馬候補
    case effectKnight
    /// 特殊マス補助: 最寄り特殊マス方向へ通過しやすい直線候補
    case effectLine
}
