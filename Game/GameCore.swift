import Foundation
import SharedSupport // ログユーティリティを利用するため追加
#if canImport(Combine)
import Combine
#endif
#if canImport(UIKit)
import UIKit
#endif

/// ゲーム進行を統括するクラス
/// - 盤面操作・手札管理・ペナルティ処理・スコア計算を担当する

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public final class GameCore: ObservableObject {
    /// 現在適用中のゲームモード
    public let mode: GameMode
    /// 盤面情報
    @Published public private(set) var board = Board(
        size: BoardGeometry.standardSize,
        initialVisitedPoints: BoardGeometry.defaultInitialVisitedPoints(for: BoardGeometry.standardSize)
    )
    /// 駒の現在位置
    /// - Note: 盤面ユーティリティ経由で中央マスを導出し、ハードコードしていた 5×5 の依存を取り除いている。
    @Published public private(set) var current: GridPoint? = BoardGeometry.defaultSpawnPoint(for: BoardGeometry.standardSize)
    /// 手札と先読みカードの管理を委譲するハンドマネージャ
    /// - Note: 外部モジュールから直接操作させず、公開用プロパティ経由で状態を把握できるようにする
    let handManager: HandManager

    /// 外部レイヤーへ公開する手札スロット
    /// - Important: `@Published` を介して ViewModel が変更通知を受け取れるようにする
    @Published public private(set) var handStacks: [HandStack] = []
    /// NEXT 表示カードの公開用スナップショット
    /// - Note: HandManager の内部実装を意識せずに UI が参照できるよう保持する
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
    /// プレイ中に一度でも既踏マスへ戻ったかどうか
    /// - Note: キャンペーンの追加リワード条件「同じマスを踏まない」を判定するための状態
    @Published public private(set) var hasRevisitedTile: Bool = false
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
    /// - Note: クリア済みかどうかに応じて `GameSessionTimer` へ計算を委譲する。
    public var liveElapsedSeconds: Int {
        sessionTimer.liveElapsedSeconds()
    }
    /// 未踏破マスの残り数を UI へ公開する計算プロパティ

    public var remainingTiles: Int { board.remainingCount }

    /// 山札管理（`Deck.swift` に定義された重み付き無限山札を使用）
    private var deck = Deck(configuration: .standard)
    /// 経過時間を管理する専用タイマー
    /// - Note: GameCore の責務を整理するために専用構造体へ委譲する
    private var sessionTimer = GameSessionTimer()

    /// 初期化時にモードを指定して各種状態を構築する
    /// - Parameter mode: 適用したいゲームモード（省略時はスタンダード）
    public init(mode: GameMode = .standard) {
        self.mode = mode
        // BoardGeometry を介することで盤面サイズ拡張時も初期化処理を共通化できる
        board = Board(
            size: mode.boardSize,
            initialVisitedPoints: mode.initialVisitedPoints,
            requiredVisitOverrides: mode.additionalVisitRequirements,
            togglePoints: mode.toggleTilePoints,
            impassablePoints: mode.impassableTilePoints
        )
        current = mode.initialSpawnPoint ?? BoardGeometry.defaultSpawnPoint(for: mode.boardSize)
        deck = Deck(configuration: mode.deckConfiguration)
        progress = mode.requiresSpawnSelection ? .awaitingSpawn : .playing
        handManager = HandManager(
            handSize: mode.handSize,
            nextPreviewCount: mode.nextPreviewCount,
            allowsCardStacking: mode.allowsCardStacking,
            initialOrderingStrategy: .insertionOrder
        )
        // 実際の山札と手札の構成は共通処理に集約
        configureForNewSession(regenerateDeck: false)
    }

    /// 手札の並び順設定を更新し、必要であれば再ソートする
    /// - Parameter newStrategy: ユーザーが選択した並び替え方式
    public func updateHandOrderingStrategy(_ newStrategy: HandOrderingStrategy) {
        handManager.updateHandOrderingStrategy(newStrategy)
        refreshHandStateFromManager()
    }

    /// 指定インデックスのカードで駒を移動させる
    /// - Parameters:
    ///   - index: 手札配列の位置（0〜4）
    ///   - moveVector: 複数候補カードから特定方向を選びたい場合に指定する移動ベクトル
    ///                （`nil` の場合は候補が 1 件のときのみ自動で採用）
    public func playCard(at index: Int, selecting moveVector: MoveVector? = nil) {
        // --- 入力検証 ---
        // index が手札配列の範囲外なら即座に終了
        guard handStacks.indices.contains(index) else { return }
        // 現在地やスタックのトップカードが存在しなければ処理できない
        guard current != nil, handStacks[index].topCard != nil else { return }

        // --- 利用可能な候補の抽出 ---
        // availableMoves() は盤面内へ移動できる ResolvedCardMove 一覧を返すため、
        // 指定スタックに該当する候補だけを抽出してから方向選択を行う。
        let candidates = availableMoves().filter { $0.stackIndex == index }

        // moveVector が指定された場合は完全一致する候補を探し、
        // 指定がない場合は候補が単一のときだけ自動で採用する。
        let resolvedMove: ResolvedCardMove?
        if let targetVector = moveVector {
            resolvedMove = candidates.first { $0.moveVector == targetVector }
        } else if candidates.count == 1 {
            resolvedMove = candidates.first
        } else {
            // 複数候補があるのに moveVector が未指定であれば安全に中断する
            resolvedMove = nil
        }

        // 適切な候補が見つかった場合のみ playCard(using:) へ委譲する
        guard let resolvedMove else { return }
        playCard(using: resolvedMove)
    }

    /// ResolvedCardMove で指定されたベクトルを用いてカードをプレイする
    /// - Parameter resolvedMove: `availableMoves()` が返す候補の 1 つ
    public func playCard(using resolvedMove: ResolvedCardMove) {
        // スポーン待ちやクリア済み・ペナルティ中は操作不可
        guard progress == .playing, let currentPosition = current else { return }
        // 捨て札モード中は移動を開始せず安全に抜ける
        guard !isAwaitingManualDiscardSelection else { return }
        // UI 側で保持していた情報が古くなっていないかを安全確認
        guard handStacks.indices.contains(resolvedMove.stackIndex) else { return }
        let stack = handStacks[resolvedMove.stackIndex]
        guard stack.id == resolvedMove.stackID else { return }
        guard let card = stack.topCard, card.id == resolvedMove.card.id, card.move == resolvedMove.card.move else { return }
        // 候補ベクトルが現在のカードに含まれているか検証し、不正な入力を排除する
        guard card.move.movementVectors.contains(resolvedMove.moveVector) else { return }

        let computedDestination = currentPosition.offset(dx: resolvedMove.moveVector.dx, dy: resolvedMove.moveVector.dy)
        // ResolvedCardMove が古い現在地から算出された場合は破棄する（UI との同期ズレ対策）
        guard computedDestination == resolvedMove.destination else { return }
        // UI 側で無効カードを弾く想定だが、念のため安全確認
        guard board.contains(computedDestination) else { return }

        // 盤面タップからのリクエストが残っている場合に備え、念のためここでクリアしておく
        boardTapPlayRequest = nil

        // デバッグログ: 使用カードと移動先を出力（複数候補カードでも選択ベクトルを追跡できるよう詳細を含める）
        debugLog(
            "カード \(card.move) を使用し \(currentPosition) -> \(computedDestination) へ移動 (vector=\(resolvedMove.moveVector))"
        )

        // トグルマスでも「訪問前に踏破済みかどうか」で再訪を判定する。
        // - Note: 踏破済み状態から踏むと未踏破へ戻るため、次回訪問時はペナルティなしになる。
        let revisiting = board.isVisited(computedDestination)

        // 移動処理
        current = computedDestination
        board.markVisited(computedDestination)
        moveCount += 1

        // 既踏マスへ戻った場合はフラグを立て、必要に応じてペナルティを加算する
        if revisiting {
            hasRevisitedTile = true

            if mode.revisitPenaltyCost > 0 {
                penaltyCount += mode.revisitPenaltyCost
                debugLog("既踏マス再訪ペナルティ: +\(mode.revisitPenaltyCost)")
            }
        }

        // 盤面更新に合わせて残り踏破数を読み上げ
        announceRemainingTiles()

        // 使用済みカードは即座に破棄し、スタックから除去（残数がゼロになったらスタックごと取り除く）
        let removedIndex = handManager.consumeTopCard(at: resolvedMove.stackIndex)

        // スロットの空きを埋めた上で並び順・先読みを整える
        rebuildHandAndNext(preferredInsertionIndices: removedIndex.map { [$0] } ?? [])

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

    /// 現在の状態から使用可能なカード移動候補を列挙する
    /// - Parameters:
    ///   - handStacksOverride: 手札スタックを差し替えたい場合に指定（省略時は `self.handStacks` を利用）
    ///   - currentOverride: 現在地を差し替えたい場合に指定（省略時は `self.current` を利用）
    /// - Returns: 盤面内へ移動できるカードの詳細情報
    public func availableMoves(
        handStacks handStacksOverride: [HandStack]? = nil,
        current currentOverride: GridPoint? = nil
    ) -> [ResolvedCardMove] {
        // 引数が未指定の場合は現在の GameCore 状態を採用する
        let referenceHandStacks = handStacksOverride ?? handStacks
        guard let origin = currentOverride ?? current else { return [] }

        // 盤面境界を参照するためローカル変数として保持しておく
        let activeBoard = board

        // 列挙中に同じ座標へ向かうカードを検出しやすいよう、結果は座標→スタック順でソートする
        var resolved: [ResolvedCardMove] = []
        resolved.reserveCapacity(referenceHandStacks.count)

        for (index, stack) in referenceHandStacks.enumerated() {
            // トップカードが存在しなければスキップ
            guard let topCard = stack.topCard else { continue }

            // MoveCard.movementVectors が保持する全候補を展開し、1 ベクトルずつ ResolvedCardMove に変換する
            for vector in topCard.move.movementVectors {
                let destination = origin.offset(dx: vector.dx, dy: vector.dy)
                // 盤面外や移動不可マスへの移動は候補から除外
                guard activeBoard.contains(destination) else { continue }
                guard !mode.impassableTilePoints.contains(destination) else { continue }

                resolved.append(
                    ResolvedCardMove(
                        stackID: stack.id,
                        stackIndex: index,
                        card: topCard,
                        moveVector: vector,
                        destination: destination
                    )
                )
            }
        }

        // y→x→スタック順で並び替えることで、同一座標のカードが隣接する形で得られる
        resolved.sort { lhs, rhs in
            if lhs.destination.y != rhs.destination.y {
                return lhs.destination.y < rhs.destination.y
            }
            if lhs.destination.x != rhs.destination.x {
                return lhs.destination.x < rhs.destination.x
            }
            return lhs.stackIndex < rhs.stackIndex
        }

        return resolved
    }

    /// 盤面タップ時に使用する移動候補を優先順位付きで選び出す
    /// - Parameter point: ユーザーがタップした盤面座標
    /// - Returns: 優先順位ロジックを適用した `ResolvedCardMove`（該当なしの場合は nil）
    func resolvedMoveForBoardTap(at point: GridPoint) -> ResolvedCardMove? {
        // availableMoves() からタップ地点へ到達できる候補だけを抽出する
        let matchingMoves = availableMoves().filter { $0.destination == point }

        // 候補が存在しない場合は nil を返して終了する
        guard !matchingMoves.isEmpty else { return nil }

        // moveVector の候補数が 1 つだけのカード（通常カード）を優先する
        // - Important: 複数候補カードが存在しても、ユーザーの想定に近い通常カードを優先して消費する
        if let singleVectorMove = matchingMoves.first(where: { $0.card.move.movementVectors.count == 1 }) {
            return singleVectorMove
        }

        // 通常カードが存在しない場合は availableMoves() の並び順（座標→スタック順）に従って最初の候補を返す
        return matchingMoves.first
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

        board = Board(
            size: mode.boardSize,
            initialVisitedPoints: mode.initialVisitedPoints,
            requiredVisitOverrides: mode.additionalVisitRequirements,
            togglePoints: mode.toggleTilePoints
        )
        current = mode.initialSpawnPoint
        moveCount = 0
        penaltyCount = 0
        hasRevisitedTile = false
        elapsedSeconds = 0
        lastPenaltyAmount = 0
        penaltyEventID = nil
        boardTapPlayRequest = nil
        isAwaitingManualDiscardSelection = false
        progress = mode.requiresSpawnSelection ? .awaitingSpawn : .playing

        handManager.resetAll(using: &deck)
        refreshHandStateFromManager()

        resetTimer()

        if !mode.requiresSpawnSelection {
            checkDeadlockAndApplyPenaltyIfNeeded()
            announceRemainingTiles()
        } else {
            debugLog("スポーン位置選択待ち: 盤面サイズ=\(mode.boardSize)")
        }

        let nextText = nextCards.isEmpty ? "なし" : nextCards.map { "\($0.move)" }.joined(separator: ", ")
        let handMoves = handStacks.debugSummaryJoined(emptyPlaceholder: "なし")
        debugLog("ゲームをリセット: 手札 [\(handMoves)], 次カード \(nextText)")
#if DEBUG
        board.debugDump(current: current)
#endif
    }

    /// 所要時間カウントを現在時刻へリセットする
    private func resetTimer() {
        // 開始時刻と終了時刻を初期化し、経過秒数を 0 に戻す
        sessionTimer.reset()
        elapsedSeconds = sessionTimer.elapsedSeconds
    }

    /// クリア時点の経過時間を確定させる
    /// - Parameter referenceDate: テスト時などに任意の終了時刻を指定したい場合に利用
    private func finalizeElapsedTimeIfNeeded(referenceDate: Date = Date()) {
        // 既に終了時刻が記録されている場合は再計算を避ける
        if sessionTimer.isFinalized { return }

        // タイマーへ確定処理を委譲し、結果を @Published プロパティへ反映する
        let finalized = sessionTimer.finalize(referenceDate: referenceDate)
        elapsedSeconds = finalized

        // デバッグ目的で計測結果をログに残す
        debugLog("クリア所要時間: \(elapsedSeconds) 秒")
    }
}

#if canImport(SpriteKit)
// MARK: - GameScene からのタップ入力に対応
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
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
        guard progress == .playing else { return }

        // デバッグログ: タップされたマスを表示
        debugLog("マス \(point) をタップ")

        // 優先順位付きの候補を算出し、該当するものがあればアニメーション要求を発行する
        guard let resolved = resolvedMoveForBoardTap(at: point) else { return }

        boardTapPlayRequest = BoardTapPlayRequest(
            stackID: resolved.stackID,
            stackIndex: resolved.stackIndex,
            topCard: resolved.card,
            destination: resolved.destination,
            moveVector: resolved.moveVector
        )
    }
}
#endif

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension GameCore {
    /// HandManager が保持する最新状態を公開用プロパティへ反映する
    /// - Note: Combine 非対応環境でも確実に配列が更新されるよう、明示的に値をコピーする
    func refreshHandStateFromManager() {
        handStacks = handManager.handStacks
        nextCards = handManager.nextCards
    }

    /// HandManager を用いて手札と先読み表示を一括再構築する
    /// - Parameter preferredInsertionIndices: 使用済みスロットへ差し戻したい位置（未指定なら末尾補充）
    func rebuildHandAndNext(preferredInsertionIndices: [Int] = []) {
        handManager.rebuildHandAndPreview(using: &deck, preferredInsertionIndices: preferredInsertionIndices)
        refreshHandStateFromManager()
    }

    /// スポーン位置選択時の処理
    /// - Parameter point: プレイヤーが選んだ座標
    func handleSpawnSelection(at point: GridPoint) {
        guard mode.requiresSpawnSelection, progress == .awaitingSpawn else { return }
        guard board.contains(point) else { return }
        guard !mode.impassableTilePoints.contains(point) else { return }

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

    /// ペナルティ通知用のイベント ID を更新する
    /// - Parameter id: 設定したい識別子（nil でリセット）
    func updatePenaltyEventID(_ id: UUID?) {
        penaltyEventID = id
    }
}

#if DEBUG
/// テスト専用のユーティリティ拡張
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
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
            core.board = Board(
                size: mode.boardSize,
                initialVisitedPoints: [resolvedCurrent],
                requiredVisitOverrides: mode.additionalVisitRequirements,
                togglePoints: mode.toggleTilePoints,
                impassablePoints: mode.impassableTilePoints
            )
        } else {
            core.board = Board(
                size: mode.boardSize,
                requiredVisitOverrides: mode.additionalVisitRequirements,
                togglePoints: mode.toggleTilePoints,
                impassablePoints: mode.impassableTilePoints
            )
        }
        core.current = resolvedCurrent
        core.moveCount = 0
        core.penaltyCount = 0
        core.hasRevisitedTile = false
        core.progress = (resolvedCurrent == nil && mode.requiresSpawnSelection) ? .awaitingSpawn : .playing

        core.handManager.resetAll(using: &core.deck)
        core.refreshHandStateFromManager()

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
    ///   - hasRevisitedTile: 既踏マスへ戻ったことがあるかどうか（追加リワード条件の検証に使用）
    func overrideMetricsForTesting(moveCount: Int, penaltyCount: Int, elapsedSeconds: Int, hasRevisitedTile: Bool = false) {
        self.moveCount = moveCount
        self.penaltyCount = penaltyCount
        self.elapsedSeconds = elapsedSeconds
        self.hasRevisitedTile = hasRevisitedTile
        sessionTimer.overrideFinalizedElapsedSecondsForTesting(elapsedSeconds)
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

    /// テスト時に任意の開始時刻へ調整し、`liveElapsedSeconds` の計算結果を制御する
    /// - Parameter newStartDate: 擬似的に設定したい開始時刻
    func setStartDateForTesting(_ newStartDate: Date) {
        // リアルタイム計測は GameSessionTimer を経由して算出されるため、テストから開始時刻を操作可能にしておく。
        sessionTimer.overrideStartDateForTesting(newStartDate)
    }
}
#endif
