import Foundation

/// カード演出の段階を共有するための列挙型
/// GameView と GameViewModel の両方で利用し、演出の状態遷移を同期する
enum CardAnimationPhase: Equatable {
    /// 演出が発生していない待機状態
    case idle
    /// 手札から盤面へ移動するアニメーションを実行中
    case movingToBoard
}
