import Foundation
#if canImport(Combine)
import Combine
#else
/// Linux など Combine が存在しない環境向けの簡易定義
public protocol ObservableObject {}
@propertyWrapper
public struct Published<Value> {

    /// ラップされている実際の値
    public var wrappedValue: Value
    /// 初期化で保持する値を受け取る

    public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}
#endif
#if canImport(UIKit)
import UIKit
#endif

/// 盤面タップでカードを再生するときに UI へ伝える要求内容
/// - Note: SwiftUI 側でアニメーションを開始し、完了後に `playCard` を呼び出すための情報をまとめる
public struct BoardTapPlayRequest: Identifiable, Equatable {
    /// 要求ごとに一意な識別子を払い出して、複数回のタップでも確実に区別できるようにする
    public let id: UUID
    /// アニメーション対象となる手札カード
    public let card: DealtCard
    /// `GameCore.playCard(at:)` に渡すインデックス
    public let index: Int

    /// UI 側で参照しやすいよう公開イニシャライザを用意
    /// - Parameters:
    ///   - id: 外部で識別子を指定したい場合に使用（省略時は自動採番）
    ///   - card: 盤面タップに対応する手札カード
    ///   - index: 手札配列上の添字
    public init(id: UUID = UUID(), card: DealtCard, index: Int) {
        self.id = id
        self.card = card
        self.index = index
    }
}

/// ゲーム進行を統括するクラス
/// - 盤面操作・手札管理・ペナルティ処理・スコア計算を担当する

public final class GameCore: ObservableObject {
    /// 現在適用中のゲームモード
    public let mode: GameMode
    /// 手札枚数を統一的に扱うための定数（今回は 5 枚で固定）
    private let handSize: Int
    /// 先読み表示に用いるカード枚数（NEXT 表示は 3 枚先まで）
    private let nextPreviewCount: Int
    /// 盤面情報
    @Published public private(set) var board = Board(
        size: GameMode.standard.boardSize,
        initialVisitedPoints: GameMode.standard.initialVisitedPoints
    )
    /// 駒の現在位置
    @Published public private(set) var current: GridPoint? = GameMode.standard.initialSpawnPoint
    /// 手札（常に 5 枚保持）。UI での識別用に `DealtCard` へラップする
    @Published public private(set) var hand: [DealtCard] = []
    /// 次に引かれるカード群（先読み 3 枚分を保持）
    @Published public private(set) var nextCards: [DealtCard] = []
    /// ゲームの進行状態
    @Published public private(set) var progress: GameProgress = .playing
    /// 手詰まりペナルティが発生したことを UI 側へ伝えるイベント識別子
    /// - Note: Optional とすることで初期化直後の誤通知を防ぎ、実際にペナルティが起きたタイミングで UUID を更新する
    @Published public private(set) var penaltyEventID: UUID?

    /// 盤面タップでカード使用を依頼された際のアニメーション要求
    /// - Note: UI 側がこの値を受け取ったら演出を実行し、完了後に `clearBoardTapPlayRequest` を呼び出してリセットする
    @Published public private(set) var boardTapPlayRequest: BoardTapPlayRequest?

    /// 実際に移動した回数（UI へ即時反映させるため @Published を付与）
    @Published public private(set) var moveCount: Int = 0
    /// ペナルティによる加算手数（手詰まり通知に利用するため公開）
    @Published public private(set) var penaltyCount: Int = 0
    /// クリアまでに要した経過秒数
    /// - Note: クリア確定時に計測し、リセット時に 0 へ戻す
    @Published public private(set) var elapsedSeconds: Int = 0
    /// 直近で加算されたペナルティ手数
    @Published public private(set) var lastPenaltyAmount: Int = 0

    /// 合計手数（移動 + ペナルティ）の計算プロパティ
    /// - Note: 将来的に別レギュレーションで利用する可能性があるため個別に保持
    public var totalMoveCount: Int { moveCount + penaltyCount }

    /// ポイント計算結果（小さいほど良い）
    /// - Note: 「手数×10 + 所要秒数」の規則に基づく
    public var score: Int { totalMoveCount * 10 + elapsedSeconds }
    /// プレイ中の経過秒数をリアルタイムで取得する計算プロパティ
    /// - Note: クリア済みで `endDate` が存在する場合は確定値を返し、それ以外は現在時刻との差分を都度算出する
    public var liveElapsedSeconds: Int {
        // 終了時刻が設定済みならそれを参照し、未クリアなら現在時刻を用いる
        let referenceDate = endDate ?? Date()
        // 負値を避けるため timeIntervalSince の結果に max を適用し、四捨五入した整数秒を返す
        let duration = max(0, referenceDate.timeIntervalSince(startDate))
        return max(0, Int(duration.rounded()))
    }
    /// 未踏破マスの残り数を UI へ公開する計算プロパティ

    public var remainingTiles: Int { board.remainingCount }

    /// 山札管理（`Deck.swift` に定義された重み付き無限山札を使用）
    private var deck = Deck(configuration: .standard)
    /// プレイ開始時刻（リセットのたびに現在時刻へ更新）
    private var startDate = Date()
    /// クリア確定時刻（未クリアの場合は nil のまま保持）
    private var endDate: Date?

    /// 初期化時にモードを指定して各種状態を構築する
    /// - Parameter mode: 適用したいゲームモード（省略時はスタンダード）
    public init(mode: GameMode = .standard) {
        self.mode = mode
        handSize = mode.handSize
        nextPreviewCount = mode.nextPreviewCount
        board = Board(size: mode.boardSize, initialVisitedPoints: mode.initialVisitedPoints)
        current = mode.initialSpawnPoint
        deck = Deck(configuration: mode.deckConfiguration)
        progress = mode.requiresSpawnSelection ? .awaitingSpawn : .playing
        // 実際の山札と手札の構成は共通処理に集約
        configureForNewSession(regenerateDeck: false)
    }

    /// 指定インデックスのカードで駒を移動させる
    /// - Parameter index: 手札配列の位置（0〜4）

    public func playCard(at index: Int) {
        // スポーン待ちやクリア済み・ペナルティ中は操作不可
        guard progress == .playing, let currentPosition = current else { return }
        // インデックスが範囲内か確認（0〜4 の範囲を想定）
        guard hand.indices.contains(index) else { return }
        let card = hand[index]
        let target = currentPosition.offset(dx: card.move.dx, dy: card.move.dy)
        // UI 側で無効カードを弾く想定だが、念のため安全確認
        guard board.contains(target) else { return }

        // 盤面タップからのリクエストが残っている場合に備え、念のためここでクリアしておく
        boardTapPlayRequest = nil

        // デバッグログ: 使用カードと移動先を出力
        debugLog("カード \(card.move) を使用し \(currentPosition) -> \(target) へ移動")

        let revisiting = board.isVisited(target)

        // 移動処理
        current = target
        board.markVisited(target)
        moveCount += 1

        // 既踏マスへの再訪ペナルティを加算
        if revisiting && mode.revisitPenaltyCost > 0 {
            penaltyCount += mode.revisitPenaltyCost
            debugLog("既踏マス再訪ペナルティ: +\(mode.revisitPenaltyCost)")
        }

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
            // クリア時点の経過秒数を確定させる
            finalizeElapsedTimeIfNeeded()
            progress = .cleared
            // デバッグ: クリア時の盤面を表示
#if DEBUG
            // デバッグ目的でのみ盤面を出力する
            board.debugDump(current: current)
#endif
            return
        }

        // 手詰まりチェック（全カード盤外ならペナルティ）
        checkDeadlockAndApplyPenaltyIfNeeded()

        // デバッグ: 現在の盤面を表示
#if DEBUG
        // デバッグ目的でのみ盤面を出力する
        board.debugDump(current: current)
#endif
    }

    /// 盤面タップ由来のアニメーション要求を UI 側で処理したあとに呼び出す
    /// - Parameter id: 消したいリクエストの識別子（不一致の場合は何もしない）
    public func clearBoardTapPlayRequest(_ id: UUID) {
        // リクエスト ID が一致している場合のみ nil へ戻して次のタップを受け付ける
        guard boardTapPlayRequest?.id == id else { return }
        boardTapPlayRequest = nil
    }

    /// ペナルティ発生時の共通処理で利用する原因の区別
    /// - Note: デバッグログや VoiceOver の文言を分岐させるためだけの軽量な列挙体
    private enum PenaltyTrigger {
        case automatic
        case manual
        case automaticFreeRedraw

        /// デバッグログ向けの説明文
        var debugDescription: String {
            switch self {
            case .automatic:
                return "自動検出"
            case .manual:
                return "ユーザー操作"
            case .automaticFreeRedraw:
                return "連続手詰まり対応"
            }
        }

        /// VoiceOver で読み上げる案内文を用意
        /// - Parameter penalty: 加算された手数（0 の場合は増加無し）
        func voiceOverMessage(penalty: Int) -> String {
            switch self {
            case .automatic:
                if penalty > 0 {
                    return "手詰まりのため手札を引き直しました。手数が\(penalty)増加します。"
                } else {
                    return "手詰まりのためペナルティなしで手札を引き直しました。"
                }
            case .manual:
                if penalty > 0 {
                    return "ペナルティを使用して手札を引き直しました。手数が\(penalty)増加します。"
                } else {
                    return "ペナルティを使用して手札を引き直しました。手数の増加はありません。"
                }
            case .automaticFreeRedraw:
                return "手詰まりが続いたためペナルティなしで手札を引き直しました。"
            }
        }
    }

    /// UI 側から手動でペナルティを支払い、手札を引き直すための公開メソッド
    /// - Note: 既にゲームが終了している場合や、ペナルティ中は何もしない
    public func applyManualPenaltyRedraw() {
        // クリア済み・ペナルティ処理中は無視し、進行中のみ受け付ける
        guard progress == .playing || progress == .awaitingSpawn else { return }

        // デバッグログ: ユーザー操作による引き直しを記録
        debugLog("ユーザー操作でペナルティ引き直しを実行")

        // 共通処理を用いて手札を入れ替える
        applyPenaltyRedraw(
            trigger: .manual,
            penaltyAmount: mode.manualRedrawPenaltyCost,
            shouldAddPenalty: true
        )

        // 引き直し後も盤外カードしか無いケースをケア
        checkDeadlockAndApplyPenaltyIfNeeded(hasAlreadyPaidPenalty: true)
    }

    /// 手札がすべて盤外となる場合にペナルティを課し、手札を引き直す
    private func checkDeadlockAndApplyPenaltyIfNeeded(hasAlreadyPaidPenalty: Bool = false) {
        // スポーン待機中は判定不要
        guard progress != .awaitingSpawn, let current = current else { return }

        let allUnusable = hand.allSatisfy { card in
            let dest = current.offset(dx: card.move.dx, dy: card.move.dy)
            return !board.contains(dest)
        }
        guard allUnusable else { return }

        if hasAlreadyPaidPenalty {
            // デバッグログ: 連続手詰まりを通知し、追加ペナルティ無しで再抽選する
            debugLog("手詰まりが継続したため追加ペナルティ無しで自動引き直しを実施")

            // 共通処理を呼び出して手札・先読みを更新（追加ペナルティ無し）
            applyPenaltyRedraw(trigger: .automaticFreeRedraw, penaltyAmount: 0, shouldAddPenalty: false)
        } else {
            // デバッグログ: 手札詰まりの発生を通知
            debugLog("手札が全て使用不可のためペナルティを適用")

            // 共通処理を呼び出して手札・先読みを更新
            applyPenaltyRedraw(
                trigger: .automatic,
                penaltyAmount: mode.deadlockPenaltyCost,
                shouldAddPenalty: true
            )
        }

        // 引き直し後も詰みの場合があるので再チェック（以降はペナルティ支払い済み扱い）
        checkDeadlockAndApplyPenaltyIfNeeded(hasAlreadyPaidPenalty: true)
    }

    /// ペナルティ適用に伴う手札再構成・通知処理を一箇所へ集約する
    /// - Parameter trigger: 自動検出か手動操作かを識別するフラグ
    /// - Parameter shouldAddPenalty: 追加ペナルティを課す必要があるかどうか
    private func applyPenaltyRedraw(trigger: PenaltyTrigger, penaltyAmount: Int, shouldAddPenalty: Bool) {
        // ペナルティ処理中は .deadlock 状態として UI 側の入力を抑制する
        progress = .deadlock

        // 手札が一新されるため、盤面タップからの保留リクエストも破棄して整合性を保つ
        boardTapPlayRequest = nil

        // ペナルティ加算。追加ペナルティが不要な場合や加算量 0 の場合はカウント維持
        if shouldAddPenalty && penaltyAmount > 0 {
            penaltyCount += penaltyAmount
            debugLog("ペナルティ加算: +\(penaltyAmount)")
        }
        lastPenaltyAmount = shouldAddPenalty ? penaltyAmount : 0

        // 現在の手札・先読みカードはそのまま破棄し、新しいカードを引き直す
        hand = deck.draw(count: handSize)
        nextCards = deck.draw(count: nextPreviewCount)
        replenishNextPreview()

        // UI へ手詰まりの発生を知らせ、演出やフィードバックを促す
        penaltyEventID = UUID()

#if canImport(UIKit)
        // VoiceOver 利用者向けにペナルティ内容をアナウンス
        let announcedPenalty = shouldAddPenalty ? penaltyAmount : 0
        UIAccessibility.post(notification: .announcement, argument: trigger.voiceOverMessage(penalty: announcedPenalty))
#endif

        // デバッグログ: 引き直し後の状態を詳細に記録
        debugLog("ペナルティ引き直しを実行（トリガー: \(trigger.debugDescription)）")
        let handDescription = hand.map { "\($0.move)" }.joined(separator: ", ")
        debugLog("引き直し後の手札: [\(handDescription)]")
        // デバッグ: 引き直し後の盤面を表示
#if DEBUG
        // デバッグ目的でのみ盤面を出力する
        board.debugDump(current: current)
#endif

        // 手札更新が完了したら適切な進行状態へ戻す
        if mode.requiresSpawnSelection && current == nil {
            progress = .awaitingSpawn
        } else {
            progress = .playing
        }
    }

    /// ゲームを最初からやり直す
    /// - Parameter startNewGame: `true` の場合は乱数シードも新規採番して完全に新しいゲームを開始する。
    ///                           `false` の場合は同じシードを用いて同一展開を再現する。
    public func reset(startNewGame: Bool = true) {
        configureForNewSession(regenerateDeck: startNewGame)
    }

    /// 指定モードに応じた初期状態を再構築する
    /// - Parameter regenerateDeck: `true` の場合は新しいシードで山札を生成する
    private func configureForNewSession(regenerateDeck: Bool) {
        if regenerateDeck {
            deck = Deck(configuration: mode.deckConfiguration)
        } else {
            deck.reset()
        }

        board = Board(size: mode.boardSize, initialVisitedPoints: mode.initialVisitedPoints)
        current = mode.initialSpawnPoint
        moveCount = 0
        penaltyCount = 0
        elapsedSeconds = 0
        lastPenaltyAmount = 0
        penaltyEventID = nil
        boardTapPlayRequest = nil
        endDate = nil
        progress = mode.requiresSpawnSelection ? .awaitingSpawn : .playing

        hand = deck.draw(count: handSize)
        nextCards = deck.draw(count: nextPreviewCount)
        replenishNextPreview()

        resetTimer()

        if !mode.requiresSpawnSelection {
            checkDeadlockAndApplyPenaltyIfNeeded()
            announceRemainingTiles()
        } else {
            debugLog("スポーン位置選択待ち: 盤面サイズ=\(mode.boardSize)")
        }

        let nextText = nextCards.isEmpty ? "なし" : nextCards.map { "\($0.move)" }.joined(separator: ", ")
        let handMoves = hand.map { "\($0.move)" }.joined(separator: ", ")
        debugLog("ゲームをリセット: 手札 [\(handMoves)], 次カード \(nextText)")
#if DEBUG
        board.debugDump(current: current)
#endif
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

    /// 所要時間カウントを現在時刻へリセットする
    private func resetTimer() {
        // 開始時刻と終了時刻を初期化し、経過秒数を 0 に戻す
        startDate = Date()
        endDate = nil
        elapsedSeconds = 0
    }

    /// クリア時点の経過時間を確定させる
    /// - Parameter referenceDate: テスト時などに任意の終了時刻を指定したい場合に利用
    private func finalizeElapsedTimeIfNeeded(referenceDate: Date = Date()) {
        // 既に終了時刻が記録されている場合は再計算を避ける
        if endDate != nil { return }

        // タイムスタンプを保持し、最小値 0 を保証した整数秒を算出
        let finishDate = referenceDate
        endDate = finishDate
        let duration = max(0, finishDate.timeIntervalSince(startDate))
        elapsedSeconds = max(0, Int(duration.rounded()))

        // デバッグ目的で計測結果をログに残す
        debugLog("クリア所要時間: \(elapsedSeconds) 秒")
    }
}

#if canImport(SpriteKit)
// MARK: - GameScene からのタップ入力に対応
extension GameCore: GameCoreProtocol {
    /// 盤面上のマスがタップされた際に呼び出される
    /// - Parameter point: タップされたマスの座標
    public func handleTap(at point: GridPoint) {
        if progress == .awaitingSpawn {
            // スポーン位置選択中はカード判定ではなく初期位置を確定する
            handleSpawnSelection(at: point)
            return
        }

        // ゲーム進行中でなければ入力を無視
        guard progress == .playing, let current = current else { return }

        // デバッグログ: タップされたマスを表示
        debugLog("マス \(point) をタップ")

        // タップされたマスと現在位置の差分を計算
        let dx = point.x - current.x
        let dy = point.y - current.y

        // 差分に一致するカードを手札から検索
        if let index = hand.firstIndex(where: { $0.move.dx == dx && $0.move.dy == dy }) {
            // UI 側でカード移動アニメーションを行うため、手札情報を要求として公開する
            boardTapPlayRequest = BoardTapPlayRequest(card: hand[index], index: index)
        }
        // 該当カードが無い場合は何もしない（無効タップ）
    }
}
#endif

private extension GameCore {
    /// スポーン位置選択時の処理
    /// - Parameter point: プレイヤーが選んだ座標
    func handleSpawnSelection(at point: GridPoint) {
        guard mode.requiresSpawnSelection, progress == .awaitingSpawn else { return }
        guard board.contains(point) else { return }

        debugLog("スポーン位置を \(point) に確定")
        current = point
        board.markVisited(point)
        progress = .playing
        announceRemainingTiles()
        checkDeadlockAndApplyPenaltyIfNeeded()
    }
}

#if DEBUG
/// テスト専用のユーティリティ拡張
extension GameCore {
    /// 任意のデッキと現在位置を指定して GameCore を生成する
    /// - Parameters:
    ///   - deck: テスト用に並び順を制御した山札
    ///   - current: 駒の初期位置（モードが固定スポーンの場合はその座標を指定）
    ///   - mode: 検証対象のゲームモード
    static func makeTestInstance(deck: Deck, current: GridPoint? = nil, mode: GameMode = .standard) -> GameCore {
        let core = GameCore(mode: mode)
        core.deck = deck
        core.deck.reset()

        let resolvedCurrent = current ?? mode.initialSpawnPoint
        if let resolvedCurrent {
            core.board = Board(size: mode.boardSize, initialVisitedPoints: [resolvedCurrent])
        } else {
            core.board = Board(size: mode.boardSize)
        }
        core.current = resolvedCurrent
        core.moveCount = 0
        core.penaltyCount = 0
        core.progress = (resolvedCurrent == nil && mode.requiresSpawnSelection) ? .awaitingSpawn : .playing

        core.hand = core.deck.draw(count: core.handSize)
        core.nextCards = core.deck.draw(count: core.nextPreviewCount)
        core.replenishNextPreview()

        if core.progress == .playing {
            core.checkDeadlockAndApplyPenaltyIfNeeded()
        }
        core.resetTimer()
        return core
    }

    /// テスト用に手数・ペナルティ・経過秒数を任意の値へ調整する
    /// - Parameters:
    ///   - moveCount: 設定したい移動回数
    ///   - penaltyCount: 設定したいペナルティ手数
    ///   - elapsedSeconds: 設定したい所要時間（秒）
    func overrideMetricsForTesting(moveCount: Int, penaltyCount: Int, elapsedSeconds: Int) {
        self.moveCount = moveCount
        self.penaltyCount = penaltyCount
        self.elapsedSeconds = elapsedSeconds
    }

    /// テストでクリア時刻を任意指定したい場合に利用する
    /// - Parameter finishDate: 想定する終了時刻
    func finalizeElapsedTimeForTesting(finishDate: Date) {
        finalizeElapsedTimeIfNeeded(referenceDate: finishDate)
    }

    /// スポーン選択をテストから直接実行するためのヘルパー
    /// - Parameter point: 選択したいスポーン座標
    func simulateSpawnSelection(forTesting point: GridPoint) {
        handleSpawnSelection(at: point)
    }
}
#endif
