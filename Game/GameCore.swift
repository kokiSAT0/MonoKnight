import Foundation
#if canImport(SharedSupport)
import SharedSupport // デバッグログ系ユーティリティを共有ターゲットから利用する
#endif
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

/// 手札の並べ替え設定を Game モジュール側でも利用できるように定義
/// - Note: UI 層とゲームロジックの双方から参照されるため、SPM ターゲットに確実に含まれる GameCore.swift 内で定義している
public enum HandOrderingStrategy: String, CaseIterable {
    /// 山札から引いた順番をそのまま保持する方式
    case insertionOrder
    /// 移動方向に基づいて常にソートする方式
    case directionSorted

    /// UserDefaults / @AppStorage で共有するためのキー
    public static let storageKey = "hand_ordering_strategy"

    /// 設定画面などに表示する日本語名称
    public var displayName: String {
        switch self {
        case .insertionOrder:
            return "引いた順に並べる"
        case .directionSorted:
            return "移動方向で並べ替える"
        }
    }

    /// 詳細説明文。フッター表示などで再利用する
    public var detailDescription: String {
        switch self {
        case .insertionOrder:
            return "山札から引いた順番で手札スロットへ補充します。消費した位置へ新しいカードが入ります。"
        case .directionSorted:
            return "左への移動量が大きいカードほど左側に、同じ左右移動量なら上方向へ進むカードを優先して並べます。"
        }
    }
}

/// ゲーム進行を統括するクラス
/// - 盤面操作・手札管理・ペナルティ処理・スコア計算を担当する

public final class GameCore: ObservableObject {
    /// 現在適用中のゲームモード
    public let mode: GameMode
    /// 手札スロット数を統一的に扱うための定数（今回は 5 スロットで固定）
    private let handSize: Int
    /// 先読み表示に用いるカード枚数（NEXT 表示は 3 枚先まで）
    private let nextPreviewCount: Int
    /// 同種カードをスタックできるかどうかの設定
    private let allowsCardStacking: Bool
    /// 盤面情報
    @Published public private(set) var board = Board(
        size: GameMode.standard.boardSize,
        initialVisitedPoints: GameMode.standard.initialVisitedPoints
    )
    /// 駒の現在位置
    @Published public private(set) var current: GridPoint? = GameMode.standard.initialSpawnPoint
    /// 手札スロット（最大 handSize 種類）をスタック形式で保持する配列
    @Published public private(set) var handStacks: [HandStack] = []
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
    /// 捨て札ペナルティの対象選択を待っているかどうか
    /// - Note: UI のハイライト切り替えや操作制御に利用する
    @Published public private(set) var isAwaitingManualDiscardSelection: Bool = false

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
    /// 手札の並び順を制御するユーザー設定。初期値は従来の挿入順
    private var handOrderingStrategy: HandOrderingStrategy = .insertionOrder
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
        allowsCardStacking = mode.allowsCardStacking
        progress = mode.requiresSpawnSelection ? .awaitingSpawn : .playing
        // 実際の山札と手札の構成は共通処理に集約
        configureForNewSession(regenerateDeck: false)
    }

    /// 手札の並び順設定を更新し、必要であれば再ソートする
    /// - Parameter newStrategy: ユーザーが選択した並び替え方式
    public func updateHandOrderingStrategy(_ newStrategy: HandOrderingStrategy) {
        guard handOrderingStrategy != newStrategy else { return }
        handOrderingStrategy = newStrategy
        reorderHandIfNeeded()
    }

    /// 指定インデックスのカードで駒を移動させる
    /// - Parameter index: 手札配列の位置（0〜4）

    public func playCard(at index: Int) {
        // スポーン待ちやクリア済み・ペナルティ中は操作不可
        guard progress == .playing, let currentPosition = current else { return }
        // 捨て札モード中は移動を開始せず安全に抜ける
        guard !isAwaitingManualDiscardSelection else { return }
        // インデックスが範囲内か確認（0〜handSize-1 の範囲を想定）
        guard handStacks.indices.contains(index) else { return }
        var stack = handStacks[index]
        guard let card = stack.topCard else { return }
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

        // 使用済みカードは即座に破棄し、スタックから除去（残数がゼロになったらスタックごと取り除く）
        stack.removeTopCard()
        // 空きスロットの位置を記録しておき、補充時に同じ位置へ挿入できるようにする
        let removedIndex: Int?
        if stack.isEmpty {
            handStacks.remove(at: index)
            removedIndex = index
        } else {
            handStacks[index] = stack
            removedIndex = nil
        }

        // スロットの空きを埋めるため、NEXT キューを優先して補充し、足りなければ山札から引く
        refillHandStacks(from: &nextCards, preferredInsertionIndices: removedIndex.map { [$0] } ?? [])
        // 並び順設定に応じて手札全体を調整
        reorderHandIfNeeded()
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
        isAwaitingManualDiscardSelection = false
        endDate = nil
        progress = mode.requiresSpawnSelection ? .awaitingSpawn : .playing

        handStacks.removeAll(keepingCapacity: true)
        nextCards.removeAll(keepingCapacity: true)
        refillHandStacks(from: &nextCards)
        // 新しい手札も設定値に沿って並べ替える
        reorderHandIfNeeded()
        replenishNextPreview()

        resetTimer()

        if !mode.requiresSpawnSelection {
            checkDeadlockAndApplyPenaltyIfNeeded()
            announceRemainingTiles()
        } else {
            debugLog("スポーン位置選択待ち: 盤面サイズ=\(mode.boardSize)")
        }

        let nextText = nextCards.isEmpty ? "なし" : nextCards.map { "\($0.move)" }.joined(separator: ", ")
        let handMoves = handStacks.map(stackSummary).joined(separator: ", ")
        debugLog("ゲームをリセット: 手札 [\(handMoves)], 次カード \(nextText)")
#if DEBUG
        board.debugDump(current: current)
#endif
    }

    /// 手札スロットが空いている場合に、NEXT キューや山札からカードを補充する
    /// - Parameters:
    ///   - sourceCards: 先読みキューなど優先的に消費したいカード配列
    ///   - preferredInsertionIndices: 使用済みスロットに新しいカードを差し戻したい場合の挿入候補インデックス
    func refillHandStacks(from sourceCards: inout [DealtCard], preferredInsertionIndices: [Int] = []) {
        // 既にスロットが埋まっており、指定された補充位置も無ければ何もしない
        guard handStacks.count < handSize || !preferredInsertionIndices.isEmpty else { return }

        // 補充すべきスロット位置は昇順に並べ替えて先頭から処理する
        var pendingInsertionIndices = preferredInsertionIndices.sorted()

        // 無限ループを避けるための安全カウンタ（異常時にはログを残して抜ける）
        var drawAttempts = 0
        while handStacks.count < handSize || !pendingInsertionIndices.isEmpty {
            let nextCard: DealtCard?
            if !sourceCards.isEmpty {
                nextCard = sourceCards.removeFirst()
            } else {
                nextCard = deck.draw()
            }

            guard let card = nextCard else { break }

            if allowsCardStacking,
               let index = handStacks.firstIndex(where: { $0.representativeMove == card.move }) {
                // 既存スタックへ積み増した場合でも空きスロットが残ることがあるため、
                // pendingInsertionIndices は消費せず次のカードドローを継続する
                var existing = handStacks[index]
                existing.append(card)
                handStacks[index] = existing
            } else {
                // 空きスロット位置が指定されていればそこへ挿入し、無ければ末尾へ追加する
                if let preferredIndex = pendingInsertionIndices.first {
                    let insertionIndex = min(preferredIndex, handStacks.count)
                    handStacks.insert(HandStack(cards: [card]), at: insertionIndex)
                    pendingInsertionIndices.removeFirst()
                    // 1 つ挿入すると後続のインデックスは 1 つずれるため、影響範囲のみ +1 して整合性を取る
                    for candidateIndex in 0..<pendingInsertionIndices.count {
                        if pendingInsertionIndices[candidateIndex] >= insertionIndex {
                            pendingInsertionIndices[candidateIndex] += 1
                        }
                    }
                } else {
                    handStacks.append(HandStack(cards: [card]))
                }
            }

            drawAttempts += 1
            if drawAttempts > 512 {
                debugLog("refillHandStacks が安全カウンタに到達: handStacks=\(handStacks.count), source残=\(sourceCards.count)")
                break
            }
        }
    }

    /// 先読み表示用のカードが不足している場合に山札から補充する
    /// - Note: デッキは重み付き抽選の無限山札化されたため、枯渇を気にせず呼び出せる
    func replenishNextPreview() {
        while nextCards.count < nextPreviewCount {
            guard let drawn = deck.draw() else { break }
            nextCards.append(drawn)
        }
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

        // 差分に一致するカードを手札スタックから検索
        if let (index, stack) = handStacks.enumerated().first(where: { _, stack in
            guard let card = stack.topCard else { return false }
            return card.move.dx == dx && card.move.dy == dy
        }) {
            if let topCard = stack.topCard {
                // UI 側でカード移動アニメーションを行うため、手札情報を要求として公開する
                boardTapPlayRequest = BoardTapPlayRequest(stackID: stack.id, stackIndex: index, topCard: topCard)
            }
        }
        // 該当カードが無い場合は何もしない（無効タップ）
    }
}
#endif

extension GameCore {
    /// MoveCard ごとの列挙順をキャッシュし、並べ替え時の安定ソートに利用する
    private static let moveCardOrderingIndex: [MoveCard: Int] = {
        var mapping: [MoveCard: Int] = [:]
        mapping.reserveCapacity(MoveCard.allCases.count)
        for (index, card) in MoveCard.allCases.enumerated() {
            mapping[card] = index
        }
        return mapping
    }()

    /// 現在の手札をユーザー設定に従って並び替える
    /// - Note: 従来モードでは何もしない
    func reorderHandIfNeeded() {
        guard handOrderingStrategy == .directionSorted else { return }

        // 左方向への移動量が大きいものから順に並べ、同値なら上方向を優先
        handStacks.sort { lhs, rhs in
            guard let leftCard = lhs.topCard, let rightCard = rhs.topCard else {
                return lhs.topCard != nil
            }
            let leftDX = leftCard.move.dx
            let rightDX = rightCard.move.dx
            if leftDX != rightDX {
                return leftDX < rightDX
            }

            let leftDY = leftCard.move.dy
            let rightDY = rightCard.move.dy
            if leftDY != rightDY {
                return leftDY > rightDY
            }

            let leftIndex = GameCore.moveCardOrderingIndex[leftCard.move] ?? 0
            let rightIndex = GameCore.moveCardOrderingIndex[rightCard.move] ?? 0
            return leftIndex < rightIndex
        }
    }

    /// デバッグログで扱いやすいよう、スタック内容を簡潔なテキストへ整形する
    /// - Parameter stack: 対象の `HandStack`
    /// - Returns: 「MoveCard×枚数」の形式（1 枚の場合は枚数省略）
    func stackSummary(_ stack: HandStack) -> String {
        guard let move = stack.representativeMove else {
            return "(空スタック)"
        }
        if stack.count > 1 {
            return "\(move)×\(stack.count)"
        } else {
            return "\(move)"
        }
    }

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

    /// ペナルティ処理で進行状態を一括更新するためのヘルパー
    /// - Parameter newValue: 設定したい進行状態
    func updateProgressForPenaltyFlow(_ newValue: GameProgress) {
        progress = newValue
    }

    /// 捨て札選択待機フラグを共通的に更新する
    /// - Parameter isActive: 選択待機中かどうか
    func setManualDiscardSelectionState(_ isActive: Bool) {
        isAwaitingManualDiscardSelection = isActive
    }

    /// 盤面タップからの保留リクエストを安全に破棄する
    func resetBoardTapPlayRequestForPenalty() {
        boardTapPlayRequest = nil
    }

    /// ペナルティ手数を加算する処理を共通化する
    /// - Parameter amount: 加算したい手数
    func addPenaltyCount(_ amount: Int) {
        penaltyCount += amount
    }

    /// 最後に課したペナルティ量を更新する
    /// - Parameter amount: 記録したい手数
    func setLastPenaltyAmountForPenalty(_ amount: Int) {
        lastPenaltyAmount = amount
    }

    /// 手札と先読みカードを丸ごと初期化する
    func clearHandAndNextForPenalty() {
        handStacks.removeAll(keepingCapacity: true)
        nextCards.removeAll(keepingCapacity: true)
    }

    /// 現在の先読みキューを利用して手札補充を実行する
    /// - Parameter preferredInsertionIndices: 補充したいスロット位置
    func refillHandUsingCurrentNextCards(preferredInsertionIndices: [Int] = []) {
        refillHandStacks(from: &nextCards, preferredInsertionIndices: preferredInsertionIndices)
    }

    /// 指定したスタックを安全に取り除いて返す
    /// - Parameter index: 削除対象のインデックス
    /// - Returns: 取り除いたスタック
    func removeHandStackForPenalty(at index: Int) -> HandStack {
        handStacks.remove(at: index)
    }

    /// ペナルティ通知用のイベント ID を更新する
    /// - Parameter id: 設定したい識別子（nil でリセット）
    func updatePenaltyEventID(_ id: UUID?) {
        penaltyEventID = id
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

        core.handStacks.removeAll(keepingCapacity: true)
        core.nextCards.removeAll(keepingCapacity: true)
        core.refillHandStacks(from: &core.nextCards)
        core.reorderHandIfNeeded()
        core.replenishNextPreview()

        if core.progress == .playing {
            core.checkDeadlockAndApplyPenaltyIfNeeded()
        }
        core.resetTimer()
        core.isAwaitingManualDiscardSelection = false
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
