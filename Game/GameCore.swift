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
#if canImport(UIKit)
import UIKit
#endif

/// ゲーム進行を統括するクラス
/// - 盤面操作・手札管理・ペナルティ処理・スコア計算を担当する
final class GameCore: ObservableObject {
    /// 手札枚数を統一的に扱うための定数（今回は 5 枚で固定）
    private let handSize: Int = 5
    /// 盤面情報
    @Published private(set) var board = Board()
    /// 駒の現在位置
    @Published private(set) var current = GridPoint.center
    /// 手札（常に 5 枚保持）
    @Published private(set) var hand: [MoveCard] = []
    /// 次に引かれるカード（先読み 1 枚）
    @Published private(set) var next: MoveCard?
    /// ゲームの進行状態
    @Published private(set) var progress: GameProgress = .playing

    /// 実際に移動した回数（UI へ即時反映させるため @Published を付与）
    @Published private(set) var moveCount: Int = 0
    /// ペナルティによる加算手数（手詰まり通知に利用するため公開）
    @Published private(set) var penaltyCount: Int = 0
    /// 合計スコア（小さいほど良い）
    var score: Int { moveCount + penaltyCount }
    /// 未踏破マスの残り数を UI へ公開する計算プロパティ
    var remainingTiles: Int { board.remainingCount }

    /// 山札管理（`Deck.swift` に定義された構造体を使用）
    private var deck = Deck()

    /// 初期化時に手札と次カードを用意
    init() {
        // 定数 handSize を用いて初期手札を引き切る
        hand = deck.draw(count: handSize)
        next = deck.draw()
        // 初期状態で手詰まりの場合をケア
        checkDeadlockAndApplyPenaltyIfNeeded()
        // 初期状態の残り踏破数を読み上げ
        announceRemainingTiles()
        // デバッグ: 初期盤面を表示して状態を確認
        board.debugDump(current: current)
    }

    /// 指定インデックスのカードで駒を移動させる
    /// - Parameter index: 手札配列の位置（0〜4）
    func playCard(at index: Int) {
        // クリア済みや手詰まり中は操作不可
        guard progress == .playing else { return }
        // インデックスが範囲内か確認（0〜4 の範囲を想定）
        guard hand.indices.contains(index) else { return }
        let card = hand[index]
        let target = current.offset(dx: card.dx, dy: card.dy)
        // UI 側で無効カードを弾く想定だが、念のため安全確認
        guard board.contains(target) else { return }

        // デバッグログ: 使用カードと移動先を出力
        debugLog("カード \(card) を使用し \(current) -> \(target) へ移動")

        // 移動処理
        current = target
        board.markVisited(target)
        moveCount += 1

        // 盤面更新に合わせて残り踏破数を読み上げ
        announceRemainingTiles()

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
            // デバッグ: クリア時の盤面を表示
            board.debugDump(current: current)
            return
        }

        // 手詰まりチェック（全カード盤外ならペナルティ）
        checkDeadlockAndApplyPenaltyIfNeeded()

        // デバッグ: 現在の盤面を表示
        board.debugDump(current: current)
    }

    /// 手札がすべて盤外となる場合にペナルティを課し、手札を引き直す
    private func checkDeadlockAndApplyPenaltyIfNeeded() {
        let allUnusable = hand.allSatisfy { card in
            let dest = current.offset(dx: card.dx, dy: card.dy)
            return !board.contains(dest)
        }
        guard allUnusable else { return }

        // デバッグログ: 手札詰まりの発生を通知
        debugLog("手札が全て使用不可のためペナルティを適用")

        // ペナルティ加算 (+5 手数)
        penaltyCount += 5
        progress = .deadlock

        // デッキに全カードを戻してからまとめて引き直す
        // 既存の手札と先読みカードを一括で捨札へ送り、新しいカードを引く
        let result = deck.fullRedraw(hand: hand, next: next)
        hand = result.hand
        next = result.next

        // デバッグログ: 引き直し後の手札を表示
        debugLog("引き直し後の手札: \(hand)")
        // デバッグ: 引き直し後の盤面を表示
        board.debugDump(current: current)

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
        // リセット時も handSize を用いて手札を補充
        hand = deck.draw(count: handSize)
        next = deck.draw()
        checkDeadlockAndApplyPenaltyIfNeeded()
        // リセット後の残り踏破数を読み上げ
        announceRemainingTiles()

        // デバッグログ: リセット後の状態を表示
        let nextText = next.map { "\($0)" } ?? "なし"
        debugLog("ゲームをリセット: 手札 \(hand), 次カード \(nextText)")
        // デバッグ: リセット直後の盤面を表示
        board.debugDump(current: current)
    }

    /// 現在の残り踏破数を VoiceOver で通知する
    private func announceRemainingTiles() {
#if canImport(UIKit)
        let remaining = board.remainingCount
        let message = "残り踏破数は\(remaining)です"
        UIAccessibility.post(notification: .announcement, argument: message)
#endif
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

        // デバッグログ: タップされたマスを表示
        debugLog("マス \(point) をタップ")

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

#if DEBUG
/// テスト専用のユーティリティ拡張
extension GameCore {
    /// 任意のデッキと現在位置を指定して GameCore を生成する
    /// - Parameters:
    ///   - deck: テスト用に並び順を制御した山札
    ///   - current: 駒の初期位置（省略時は中央）
    static func makeTestInstance(deck: Deck, current: GridPoint = .center) -> GameCore {
        let core = GameCore()
        // デッキと各種状態を初期化し直す
        core.deck = deck
        core.board = Board()
        core.current = current
        core.moveCount = 0
        core.penaltyCount = 0
        core.progress = .playing
        // 手札と先読みカードを指定デッキから取得
        // テストでも handSize 分の手札を確実に引き直す
        core.hand = core.deck.draw(count: core.handSize)
        core.next = core.deck.draw()
        // 初期状態での手詰まりをチェック
        core.checkDeadlockAndApplyPenaltyIfNeeded()
        return core
    }
}
#endif
