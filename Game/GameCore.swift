import Foundation
#if canImport(Combine)
import Combine
#else
/// Linux など Combine が存在しない環境向けの簡易定義
protocol ObservableObject {}
@propertyWrapper
struct Published<Value> {
    var wrappedValue: Value
    init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}
#endif

/// ゲーム進行を統括するクラス
/// - 盤面操作・手札管理・ペナルティ処理・スコア計算を担当する
final class GameCore: ObservableObject {
    /// 盤面情報
    @Published private(set) var board = Board()
    /// 駒の現在位置
    @Published private(set) var current = GridPoint.center
    /// 手札（常に 3 枚保持）
    @Published private(set) var hand: [MoveCard] = []
    /// 次に引かれるカード（先読み 1 枚）
    @Published private(set) var next: MoveCard?
    /// ゲームの進行状態
    @Published private(set) var progress: GameProgress = .playing

    /// 実際に移動した回数
    private(set) var moveCount: Int = 0
    /// ペナルティによる加算手数
    private(set) var penaltyCount: Int = 0
    /// 合計スコア（小さいほど良い）
    var score: Int { moveCount + penaltyCount }

    /// 山札管理（`Deck.swift` に定義された構造体を使用）
    private var deck = Deck()

    /// 初期化時に手札と次カードを用意
    init() {
        hand = deck.draw(count: 3)
        next = deck.draw()
        // 初期状態で手詰まりの場合をケア
        checkDeadlockAndApplyPenaltyIfNeeded()
    }

    /// 指定インデックスのカードで駒を移動させる
    /// - Parameter index: 手札配列の位置（0〜2）
    func playCard(at index: Int) {
        // クリア済みや手詰まり中は操作不可
        guard progress == .playing else { return }
        // インデックスが範囲内か確認
        guard hand.indices.contains(index) else { return }
        let card = hand[index]
        let target = current.offset(dx: card.dx, dy: card.dy)
        // UI 側で無効カードを弾く想定だが、念のため安全確認
        guard board.contains(target) else { return }

        // 移動処理
        current = target
        board.markVisited(target)
        moveCount += 1

        // 使用カードを捨札へ送り、手札から削除
        deck.discard(card)
        hand.remove(at: index)

        // 手札補充: 先読みカードを手札へ移動し、新たに 1 枚先読み
        if let nextCard = next {
            hand.insert(nextCard, at: index)
        } else if let drawn = deck.draw() {
            // next が無い場合は山札から直接補充
            hand.insert(drawn, at: index)
        }
        next = deck.draw()

        // クリア判定
        if board.isCleared {
            progress = .cleared
            return
        }

        // 手詰まりチェック（全カード盤外ならペナルティ）
        checkDeadlockAndApplyPenaltyIfNeeded()
    }

    /// 手札がすべて盤外となる場合にペナルティを課し、手札を引き直す
    private func checkDeadlockAndApplyPenaltyIfNeeded() {
        let allUnusable = hand.allSatisfy { card in
            let dest = current.offset(dx: card.dx, dy: card.dy)
            return !board.contains(dest)
        }
        guard allUnusable else { return }

        // ペナルティ加算 (+5 手数)
        penaltyCount += 5
        progress = .deadlock

        // デッキに全カードを戻してからまとめて引き直す
        // 既存の手札と先読みカードを一括で捨札へ送り、新しいカードを引く
        let result = deck.fullRedraw(hand: hand, next: next)
        hand = result.hand
        next = result.next

        // 引き直し後も詰みの場合があるので再チェック
        progress = .playing
        checkDeadlockAndApplyPenaltyIfNeeded()
    }

    /// ゲームを最初からやり直す
    func reset() {
        board = Board()
        current = .center
        moveCount = 0
        penaltyCount = 0
        progress = .playing
        deck.reset()
        hand = deck.draw(count: 3)
        next = deck.draw()
        checkDeadlockAndApplyPenaltyIfNeeded()
    }
}

#if canImport(SpriteKit)
// MARK: - GameScene からのタップ入力に対応
extension GameCore: GameCoreProtocol {
    /// 盤面上のマスがタップされた際に呼び出される
    /// - Parameter point: タップされたマスの座標
    func handleTap(at point: GridPoint) {
        // ゲーム進行中でなければ入力を無視
        guard progress == .playing else { return }

        // タップされたマスと現在位置の差分を計算
        let dx = point.x - current.x
        let dy = point.y - current.y

        // 差分に一致するカードを手札から検索
        if let index = hand.firstIndex(where: { $0.dx == dx && $0.dy == dy }) {
            // 該当カードがあればそのカードで移動処理を実行
            playCard(at: index)
        }
        // 該当カードが無い場合は何もしない（無効タップ）
    }
}
#endif

