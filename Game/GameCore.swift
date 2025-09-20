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
    /// 先読み表示に用いるカード枚数（NEXT 表示は 3 枚先まで）
    private let nextPreviewCount: Int = 3
    /// 盤面情報
    @Published private(set) var board = Board()
    /// 駒の現在位置
    @Published private(set) var current = GridPoint.center
    /// 手札（常に 5 枚保持）。UI での識別用に `DealtCard` へラップする
    @Published private(set) var hand: [DealtCard] = []
    /// 次に引かれるカード群（先読み 3 枚分を保持）
    @Published private(set) var nextCards: [DealtCard] = []
    /// ゲームの進行状態
    @Published private(set) var progress: GameProgress = .playing
    /// 手詰まりペナルティが発生したことを UI 側へ伝えるイベント識別子
    /// - Note: Optional とすることで初期化直後の誤通知を防ぎ、実際にペナルティが起きたタイミングで UUID を更新する
    @Published private(set) var penaltyEventID: UUID?

    /// 実際に移動した回数（UI へ即時反映させるため @Published を付与）
    @Published private(set) var moveCount: Int = 0
    /// ペナルティによる加算手数（手詰まり通知に利用するため公開）
    @Published private(set) var penaltyCount: Int = 0
    /// 合計スコア（小さいほど良い）
    var score: Int { moveCount + penaltyCount }
    /// 未踏破マスの残り数を UI へ公開する計算プロパティ
    var remainingTiles: Int { board.remainingCount }

    /// 山札管理（`Deck.swift` に定義された重み付き無限山札を使用）
    private var deck = Deck()

    /// 初期化時に手札と次カードを用意
    init() {
        // 定数 handSize を用いて初期手札を引き切る
        hand = deck.draw(count: handSize)
        nextCards = deck.draw(count: nextPreviewCount)
        replenishNextPreview()
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
        let target = current.offset(dx: card.move.dx, dy: card.move.dy)
        // UI 側で無効カードを弾く想定だが、念のため安全確認
        guard board.contains(target) else { return }

        // デバッグログ: 使用カードと移動先を出力
        debugLog("カード \(card.move) を使用し \(current) -> \(target) へ移動")

        // 移動処理
        current = target
        board.markVisited(target)
        moveCount += 1

        // 盤面更新に合わせて残り踏破数を読み上げ
        announceRemainingTiles()

        // 使用済みカードは即座に破棄し、手札から除去（捨札管理は不要になった）
        hand.remove(at: index)

        // 手札補充: 先読みカードを手札へ移動し、新たに 1 枚先読み
        // 先読みキューから 1 枚取り出して補充する。空の場合のみ山札から直接補充
        if !nextCards.isEmpty {
            let upcoming = nextCards.removeFirst()
            hand.insert(upcoming, at: index)
        } else if let drawn = deck.draw() {
            // 先読みが枯渇した異常系でもプレイ継続できるよう直接ドロー
            hand.insert(drawn, at: index)
        }
        // 先読み枠が不足していれば必要枚数まで補充する
        replenishNextPreview()

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

    /// ペナルティ発生時の共通処理で利用する原因の区別
    /// - Note: デバッグログや VoiceOver の文言を分岐させるためだけの軽量な列挙体
    private enum PenaltyTrigger {
        case automatic
        case manual

        /// デバッグログ向けの説明文
        var debugDescription: String {
            switch self {
            case .automatic:
                return "自動検出"
            case .manual:
                return "ユーザー操作"
            }
        }

        /// VoiceOver で読み上げる案内文を用意
        var voiceOverMessage: String {
            switch self {
            case .automatic:
                return "手詰まりのため手札を引き直しました。手数が5増加します。"
            case .manual:
                return "ペナルティを使用して手札を引き直しました。手数が5増加します。"
            }
        }
    }

    /// UI 側から手動でペナルティを支払い、手札を引き直すための公開メソッド
    /// - Note: 既にゲームが終了している場合や、ペナルティ中は何もしない
    func applyManualPenaltyRedraw() {
        // クリア済み・ペナルティ処理中は無視し、進行中のみ受け付ける
        guard progress == .playing else { return }

        // デバッグログ: ユーザー操作による引き直しを記録
        debugLog("ユーザー操作でペナルティ引き直しを実行")

        // 共通処理を用いて手札を入れ替える
        applyPenaltyRedraw(trigger: .manual)

        // 引き直し後も盤外カードしか無いケースをケア
        checkDeadlockAndApplyPenaltyIfNeeded()
    }

    /// 手札がすべて盤外となる場合にペナルティを課し、手札を引き直す
    private func checkDeadlockAndApplyPenaltyIfNeeded() {
        let allUnusable = hand.allSatisfy { card in
            let dest = current.offset(dx: card.move.dx, dy: card.move.dy)
            return !board.contains(dest)
        }
        guard allUnusable else { return }

        // デバッグログ: 手札詰まりの発生を通知
        debugLog("手札が全て使用不可のためペナルティを適用")

        // 共通処理を呼び出して手札・先読みを更新
        applyPenaltyRedraw(trigger: .automatic)

        // 引き直し後も詰みの場合があるので再チェック
        checkDeadlockAndApplyPenaltyIfNeeded()
    }

    /// ペナルティ適用に伴う手札再構成・通知処理を一箇所へ集約する
    /// - Parameter trigger: 自動検出か手動操作かを識別するフラグ
    private func applyPenaltyRedraw(trigger: PenaltyTrigger) {
        // ペナルティ処理中は .deadlock 状態として UI 側の入力を抑制する
        progress = .deadlock

        // ペナルティ加算 (+5 手数)
        penaltyCount += 5

        // 現在の手札・先読みカードはそのまま破棄し、新しいカードを引き直す
        hand = deck.draw(count: handSize)
        nextCards = deck.draw(count: nextPreviewCount)
        replenishNextPreview()

        // UI へ手詰まりの発生を知らせ、演出やフィードバックを促す
        penaltyEventID = UUID()

#if canImport(UIKit)
        // VoiceOver 利用者向けにペナルティ内容をアナウンス
        UIAccessibility.post(notification: .announcement, argument: trigger.voiceOverMessage)
#endif

        // デバッグログ: 引き直し後の状態を詳細に記録
        debugLog("ペナルティ引き直しを実行（トリガー: \(trigger.debugDescription)）")
        let handDescription = hand.map { "\($0.move)" }.joined(separator: ", ")
        debugLog("引き直し後の手札: [\(handDescription)]")
        // デバッグ: 引き直し後の盤面を表示
        board.debugDump(current: current)

        // 手札更新が完了したら再びプレイ状態へ戻す
        progress = .playing
    }

    /// ゲームを最初からやり直す
    func reset() {
        board = Board()
        current = .center
        moveCount = 0
        penaltyCount = 0
        progress = .playing
        penaltyEventID = nil
        deck.reset()
        // リセット時も handSize を用いて手札を補充
        hand = deck.draw(count: handSize)
        nextCards = deck.draw(count: nextPreviewCount)
        replenishNextPreview()
        checkDeadlockAndApplyPenaltyIfNeeded()
        // リセット後の残り踏破数を読み上げ
        announceRemainingTiles()

        // デバッグログ: リセット後の状態を表示
        let nextText: String
        if nextCards.isEmpty {
            nextText = "なし"
        } else {
            nextText = nextCards.map { "\($0.move)" }.joined(separator: ", ")
        }
        let handMoves = hand.map { "\($0.move)" }.joined(separator: ", ")
        debugLog("ゲームをリセット: 手札 [\(handMoves)], 次カード \(nextText)")
        // デバッグ: リセット直後の盤面を表示
        board.debugDump(current: current)
    }

    /// 先読み表示用のカードが不足している場合に山札から補充する
    /// - Note: デッキは重み付き抽選の無限山札化されたため、枯渇を気にせず呼び出せる
    private func replenishNextPreview() {
        while nextCards.count < nextPreviewCount {
            guard let drawn = deck.draw() else { break }
            nextCards.append(drawn)
        }
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
        if let index = hand.firstIndex(where: { $0.move.dx == dx && $0.move.dy == dy }) {
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
        core.nextCards = core.deck.draw(count: core.nextPreviewCount)
        core.replenishNextPreview()
        // 初期状態での手詰まりをチェック
        core.checkDeadlockAndApplyPenaltyIfNeeded()
        return core
    }
}
#endif
