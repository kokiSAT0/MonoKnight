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

/// 移動カードを表す構造体
/// - 備考: dx, dy で移動量を表し、16 種のカードを定義する
struct MoveCard: Identifiable {
    /// 一意な識別子（UI バインディング用）
    let id = UUID()
    /// x 方向の移動量
    let dx: Int
    /// y 方向の移動量
    let dy: Int

    /// 16 種のカード一覧
    /// - ナイト型 8 種 + 距離 2 の直線/斜め 8 種
    static let all: [MoveCard] = [
        // ナイト型（±1, ±2）
        MoveCard(dx: 1, dy: 2),
        MoveCard(dx: 2, dy: 1),
        MoveCard(dx: -1, dy: 2),
        MoveCard(dx: -2, dy: 1),
        MoveCard(dx: 1, dy: -2),
        MoveCard(dx: 2, dy: -1),
        MoveCard(dx: -1, dy: -2),
        MoveCard(dx: -2, dy: -1),
        // 距離 2 の直線/斜め
        MoveCard(dx: 2, dy: 0),
        MoveCard(dx: -2, dy: 0),
        MoveCard(dx: 0, dy: 2),
        MoveCard(dx: 0, dy: -2),
        MoveCard(dx: 2, dy: 2),
        MoveCard(dx: -2, dy: 2),
        MoveCard(dx: 2, dy: -2),
        MoveCard(dx: -2, dy: -2)
    ]
}

/// 山札・手札・捨札を管理する構造体
struct Deck {
    /// 山札（上から末尾要素を引く）
    private var drawPile: [MoveCard] = []
    /// 捨札
    private var discardPile: [MoveCard] = []

    /// 初期化時に 80 枚の山札を生成
    init() {
        reset()
    }

    /// 山札を再構築してシャッフルする
    mutating func reset() {
        drawPile.removeAll()
        discardPile.removeAll()
        for _ in 0..<5 { // 各カード 5 枚ずつ
            drawPile.append(contentsOf: MoveCard.all)
        }
        drawPile.shuffle()
    }

    /// 1 枚引く
    mutating func draw() -> MoveCard? {
        if drawPile.isEmpty {
            // 山札が空なら捨札から再構築
            if discardPile.isEmpty { return nil }
            drawPile = discardPile.shuffled()
            discardPile.removeAll()
        }
        return drawPile.popLast()
    }

    /// 複数枚引く
    mutating func draw(count: Int) -> [MoveCard] {
        var result: [MoveCard] = []
        for _ in 0..<count {
            if let card = draw() { result.append(card) }
        }
        return result
    }

    /// 使用済みカードを捨札へ送る
    mutating func discard(_ card: MoveCard) {
        discardPile.append(card)
    }
}

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

    /// 山札管理
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

        // 既存手札と先読みカードをすべて捨札へ
        hand.forEach { deck.discard($0) }
        if let nextCard = next { deck.discard(nextCard) }

        // 新しい手札と先読みを引き直し
        hand = deck.draw(count: 3)
        next = deck.draw()

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

