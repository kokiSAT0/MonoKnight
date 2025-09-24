import Foundation

/// カード演出の進行度を表現するステート
/// GameView と GameViewModel の双方で共有し、状態に応じた UI 反映を行う
enum CardAnimationPhase: Equatable {
    /// 待機中（アニメーションなし）の状態
    case idle
    /// カードが盤面へ移動している状態
    case movingToBoard
}
