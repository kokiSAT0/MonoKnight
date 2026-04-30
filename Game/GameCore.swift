import Foundation
import SharedSupport // ログユーティリティを利用するため追加
#if canImport(Combine)
import Combine
#endif
#if canImport(UIKit)
import UIKit
#endif

/// ペナルティ通知をまとめて表現するイベント構造体
/// - Note: Combine の差分検知に利用する ID とペナルティ量、発火トリガーを束ねて UI へ提供する
public struct PenaltyEvent: Identifiable, Equatable {
    /// ペナルティを引き起こした種別を区別する列挙体
    public enum Trigger: Equatable {
        case automaticDeadlock
        case manualRedraw
        case automaticFreeRedraw
    }

    /// イベント識別子（UI 側での removeDuplicates 用）
    public let id: UUID
    /// 案内すべきペナルティ量
    public let penaltyAmount: Int
    /// ペナルティトリガー
    public let trigger: Trigger

    /// イベントの初期化
    /// - Parameters:
    ///   - id: 既存の UUID を使いたい場合に指定（省略時は新規採番）
    ///   - penaltyAmount: 表示するペナルティ量
    ///   - trigger: 発火元を識別する列挙値
    public init(id: UUID = UUID(), penaltyAmount: Int, trigger: Trigger) {
        self.id = id
        self.penaltyAmount = penaltyAmount
        self.trigger = trigger
    }
}

/// 移動が完了してから手札へ適用するタイル効果
private enum PostMoveTileEffect {
    case shuffleHand
    case nextRefresh
    case freeFocus
    case draft
    case overload
}

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
    /// 手詰まりペナルティ発生を通知するイベント
    /// - Note: 直近のペナルティ内容をまとめて保持し、UI が即座に参照できるようにする
    @Published public private(set) var penaltyEvent: PenaltyEvent?

    /// 盤面タップでカード使用を依頼された際のアニメーション要求
    /// - Note: UI 側がこの値を受け取ったら演出を実行し、完了後に `clearBoardTapPlayRequest` を呼び出してリセットする
    @Published public private(set) var boardTapPlayRequest: BoardTapPlayRequest?
    /// スポーン位置選択中に選べないマスをタップした際の警告イベント
    /// - Note: UI 側が表示へ変換したら `clearSpawnSelectionWarning` でリセットする。
    @Published public private(set) var spawnSelectionWarning: SpawnSelectionWarning?
    /// 捨て札ペナルティの対象選択を待っているかどうか
    /// - Note: UI のハイライト切り替えや操作制御に利用する
    @Published public private(set) var isAwaitingManualDiscardSelection: Bool = false
    /// 直近の移動解決結果
    /// - Important: 盤面演出側がワープ等の専用アニメーションを再生できるよう、効果適用後の経路情報を公開する
    @Published public private(set) var lastMovementResolution: MovementResolution?

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
    /// 現在狙う目的地。目的地制ではこのマスに到達すると獲得数が増える
    @Published public private(set) var targetPoint: GridPoint?
    /// 次に出現する目的地の先読み
    @Published public private(set) var upcomingTargetPoints: [GridPoint] = []
    /// 目的地を獲得した数
    @Published public private(set) var capturedTargetCount: Int = 0
    /// フォーカスを使った回数
    @Published public private(set) var focusCount: Int = 0
    /// 過負荷マスにより、次の 1 手だけ使用カードが温存される状態かどうか
    @Published public private(set) var isOverloadCharged: Bool = false
    /// 合計手数（移動 + ペナルティ）の計算プロパティ
    /// - Note: 将来的に別レギュレーションで利用する可能性があるため個別に保持
    public var totalMoveCount: Int { moveCount + penaltyCount }

    /// ポイント計算結果（小さいほど良い）
    /// - Note: 目的地制ではフォーカス回数を軽く加算し、従来モードでは既存式を維持する
    public var score: Int {
        if mode.usesTargetCollection {
            return moveCount * 10 + elapsedSeconds + focusCount * 15
        }
        return totalMoveCount * 10 + elapsedSeconds
    }
    /// プレイ中の経過秒数をリアルタイムで取得する計算プロパティ
    /// - Note: クリア済みかどうかに応じて `GameSessionTimer` へ計算を委譲する。
    public var liveElapsedSeconds: Int {
        sessionTimer.liveElapsedSeconds()
    }
    /// 未踏破マスの残り数を UI へ公開する計算プロパティ

    public var remainingTiles: Int {
        mode.usesTargetCollection ? remainingTargetCount : board.remainingCount
    }
    /// 目的地制における残り目標数
    public var remainingTargetCount: Int {
        guard mode.usesTargetCollection else { return 0 }
        return max(mode.targetGoalCount - capturedTargetCount, 0)
    }
    /// 目的地制の目標獲得数
    public var targetGoalCount: Int { mode.targetGoalCount }
    /// 表示中で獲得可能な目的地一覧
    public var activeTargetPoints: [GridPoint] {
        guard mode.usesTargetCollection else { return [] }
        return [targetPoint].compactMap { $0 } + upcomingTargetPoints
    }

    /// 山札管理（`Deck.swift` に定義された重み付き無限山札を使用）
    private var deck: Deck
    /// 経過時間を管理する専用タイマー
    /// - Note: GameCore の責務を整理するために専用構造体へ委譲する
    private var sessionTimer = GameSessionTimer()
    /// 目的地制で同時に表示・獲得可能にする目的地数
    private let activeTargetDisplayCount = 3

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
            impassablePoints: mode.impassableTilePoints,
            tileEffects: mode.tileEffects
        )
        current = mode.initialSpawnPoint ?? BoardGeometry.defaultSpawnPoint(for: mode.boardSize)
        // モードに紐付くシードが指定されている場合はそれを利用し、日替わりチャレンジなどの再現性を確保する
        deck = Deck(
            seed: mode.deckSeed,
            configuration: mode.deckConfiguration,
            fixedWarpDestinations: mode.fixedWarpDestinationPool
        )
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
        // availableMoves() は盤面内かつ移動可能なマスだけを列挙するため、
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

    /// ResolvedCardMove が現在の手札情報と一致しているかを検証し、必要ならインデックスを補正する
    /// - Parameter resolvedMove: UI やガイド計算から受け取った移動候補
    /// - Returns: 最新のスタックインデックスへ正規化した `ResolvedCardMove` と対応する `HandStack`
    ///            （不一致が検出された場合は nil を返して早期終了する）
    public func validatedResolvedMove(
        _ resolvedMove: ResolvedCardMove
    ) -> (ResolvedCardMove, HandStack)? {
        // --- まずは提示された index がそのまま利用できるかを確認する ---
        let resolvedIndex: Int
        if handStacks.indices.contains(resolvedMove.stackIndex),
           handStacks[resolvedMove.stackIndex].id == resolvedMove.stackID {
            resolvedIndex = resolvedMove.stackIndex
        } else if let fallbackIndex = handStacks.firstIndex(where: { $0.id == resolvedMove.stackID }) {
            // --- index が変化していた場合は補正し、原因追跡のためにログへ記録する ---
            resolvedIndex = fallbackIndex
            debugLog(
                "ResolvedCardMove を補正: 元index=\(resolvedMove.stackIndex) 新index=\(fallbackIndex) stackID=\(resolvedMove.stackID)"
            )
        } else {
            // --- スタックそのものが見つからなければカード不一致と判断し、nil で通知する ---
            debugLog(
                "ResolvedCardMove 検証失敗: 対象 stack が存在しない stackID=\(resolvedMove.stackID)"
            )
            return nil
        }

        let stack = handStacks[resolvedIndex]
        // --- トップカードが存在しなければ使用不能のため nil を返す ---
        guard let topCard = stack.topCard else {
            debugLog(
                "ResolvedCardMove 検証失敗: トップカードなし stackID=\(stack.id)"
            )
            return nil
        }
        // --- 指定されたカード ID と MoveCard が一致するか二重で確認する ---
        guard topCard.id == resolvedMove.card.id, topCard.move == resolvedMove.card.move else {
            debugLog(
                "ResolvedCardMove 検証失敗: カード不一致 requestID=\(resolvedMove.card.id) currentID=\(topCard.id)"
            )
            return nil
        }

        // --- index 補正が発生した場合は新しい ResolvedCardMove を生成して返す ---
        let normalizedMove: ResolvedCardMove
        if resolvedIndex == resolvedMove.stackIndex {
            normalizedMove = resolvedMove
        } else {
            normalizedMove = ResolvedCardMove(
                stackID: resolvedMove.stackID,
                stackIndex: resolvedIndex,
                card: resolvedMove.card,
                moveVector: resolvedMove.moveVector,
                resolution: resolvedMove.resolution
            )
        }

        return (normalizedMove, stack)
    }

    /// ResolvedCardMove で指定されたベクトルを用いてカードをプレイする
    /// - Parameter resolvedMove: `availableMoves()` が返す候補の 1 つ
    public func playCard(using resolvedMove: ResolvedCardMove) {
        // スポーン待ちやクリア済み・ペナルティ中は操作不可
        guard progress == .playing, let currentPosition = current else { return }
        // 捨て札モード中は移動を開始せず安全に抜ける
        guard !isAwaitingManualDiscardSelection else { return }
        // UI 側で保持していた情報が古くなっていないかを安全確認
        // - Note: validatedResolvedMove(_: ) が index 補正とカード一致チェックを共通化する
        guard let (validatedMove, latestStack) = validatedResolvedMove(resolvedMove),
              let card = latestStack.topCard else {
            return
        }
        // MovePattern から算出した経路が現時点でも有効かを検証し、不正な入力を排除する
        let snapshotBoard = board
        let validPaths = resolvedPaths(for: card, from: currentPosition, on: snapshotBoard)

        let isStillValid: Bool
        if card.move == .fixedWarp {
            // --- 固定ワープカードはカード自身が持つ目的地と一致しているか二重に検証する ---
            guard let target = card.fixedWarpDestination else { return }
            let destination = validatedMove.resolution.finalPosition
            let pathMatches = validatedMove.path == [destination] && destination == target
            let remainsAccessible = destination != currentPosition &&
                snapshotBoard.contains(destination) &&
                snapshotBoard.isTraversable(destination)
            isStillValid = pathMatches && remainsAccessible
        } else {
            isStillValid = validPaths.contains { path in
                path.traversedPoints == validatedMove.path
            }
        }
        guard isStillValid else { return }

        // 盤面タップからのリクエストが残っている場合に備え、念のためここでクリアしておく
        boardTapPlayRequest = nil

        // デバッグログ: 使用カードと移動先を出力（複数候補カードでも選択ベクトルを追跡できるよう詳細を含める）
        debugLog(
            "カード \(card.move) を使用し \(currentPosition) -> \(validatedMove.destination) へ移動予定 (vector=\(validatedMove.moveVector))"
        )

        // 経路ごとの踏破判定と効果適用を順番に処理する
        // アニメーション用に経路を保持し、ワープ時は終点を追加して UI へ伝達する
        let pathPoints = effectivePathPoints(for: validatedMove, from: currentPosition)
        var finalPosition = currentPosition
        var actualTraversedPath: [GridPoint] = []
        var encounteredRevisit = false
        var detectedEffects: [MovementResolution.AppliedEffect] = []
        var postMoveTileEffect: PostMoveTileEffect?
        var appliesTargetSwap = false
        var openGateTargets: [GridPoint] = []
        var preservesPlayedCard = false

        var stepIndex = 0
        while stepIndex < pathPoints.count {
            let stepPoint = pathPoints[stepIndex]
            guard board.contains(stepPoint), board.isTraversable(stepPoint) else { return }
            let previousPosition = finalPosition

            actualTraversedPath.append(stepPoint)

            if board.isVisited(stepPoint) {
                encounteredRevisit = true
            }

            board.markVisited(stepPoint)
            finalPosition = stepPoint

            if let effect = board.effect(at: stepPoint) {
                detectedEffects.append(.init(point: stepPoint, effect: effect))
                switch effect {
                case .warp(_, let destination):
                    if board.contains(destination), board.isTraversable(destination) {
                        if board.isVisited(destination) {
                            encounteredRevisit = true
                        }
                        board.markVisited(destination)
                        finalPosition = destination
                        actualTraversedPath.append(destination)
                        // ワープを適用したら残りの経路処理を終了する
                        stepIndex = pathPoints.count
                    } else {
                        debugLog("ワープ先 \(destination) が盤面外または移動不可のため無視しました")
                    }
                case .shuffleHand, .nextRefresh, .freeFocus, .preserveCard, .draft, .overload, .targetSwap, .openGate:
                    registerPostMoveTileEffect(
                        effect,
                        postMoveTileEffect: &postMoveTileEffect,
                        appliesTargetSwap: &appliesTargetSwap,
                        openGateTargets: &openGateTargets,
                        preservesPlayedCard: &preservesPlayedCard
                    )
                case .slow:
                    stepIndex = pathPoints.count
                case .boost:
                    let direction = normalizedDirection(from: previousPosition, to: stepPoint)
                    let boostedPoint = stepPoint.offset(dx: direction.dx, dy: direction.dy)
                    if direction.dx != 0 || direction.dy != 0,
                       board.contains(boostedPoint),
                       board.isTraversable(boostedPoint) {
                        actualTraversedPath.append(boostedPoint)

                        if board.isVisited(boostedPoint) {
                            encounteredRevisit = true
                        }

                        board.markVisited(boostedPoint)
                        finalPosition = boostedPoint

                        if let boostedEffect = board.effect(at: boostedPoint) {
                            detectedEffects.append(.init(point: boostedPoint, effect: boostedEffect))
                            switch boostedEffect {
                            case .warp(_, let destination):
                                if board.contains(destination), board.isTraversable(destination) {
                                    if board.isVisited(destination) {
                                        encounteredRevisit = true
                                    }
                                    board.markVisited(destination)
                                    finalPosition = destination
                                    actualTraversedPath.append(destination)
                                    stepIndex = pathPoints.count
                                } else {
                                    debugLog("ワープ先 \(destination) が盤面外または移動不可のため無視しました")
                                }
                            case .shuffleHand, .nextRefresh, .freeFocus, .preserveCard, .draft, .overload, .targetSwap, .openGate:
                                registerPostMoveTileEffect(
                                    boostedEffect,
                                    postMoveTileEffect: &postMoveTileEffect,
                                    appliesTargetSwap: &appliesTargetSwap,
                                    openGateTargets: &openGateTargets,
                                    preservesPlayedCard: &preservesPlayedCard
                                )
                            case .boost:
                                break
                            case .slow:
                                stepIndex = pathPoints.count
                            }
                        }

                        while stepIndex + 1 < pathPoints.count, pathPoints[stepIndex + 1] == finalPosition {
                            stepIndex += 1
                        }
                    } else {
                        debugLog("加速先 \(boostedPoint) が盤面外または移動不可のため加速しませんでした")
                    }
                }
            }

            stepIndex += 1
        }

        if actualTraversedPath.isEmpty {
            actualTraversedPath.append(finalPosition)
        }
        // 直近の移動解決結果を更新し、GameScene が効果に応じたアニメーションを選択できるようにする
        lastMovementResolution = MovementResolution(
            path: actualTraversedPath,
            finalPosition: finalPosition,
            appliedEffects: detectedEffects
        )
        // current を更新するのは最後に行い、Combine の通知順序で UI が解決情報を先に受け取れるように配慮する
        current = finalPosition
        moveCount += 1

        if encounteredRevisit {
            hasRevisitedTile = true

            if mode.revisitPenaltyCost > 0 {
                penaltyCount += mode.revisitPenaltyCost
                debugLog("既踏マス再訪ペナルティ: +\(mode.revisitPenaltyCost)")
            }
        }

        if !detectedEffects.isEmpty {
            let summary = detectedEffects.map { "\($0.effect)@\($0.point)" }.joined(separator: ", ")
            debugLog("タイル効果検出: \(summary)")
        }

        // 盤面更新に合わせて残り踏破数を読み上げ
        announceRemainingTiles()

        let consumesOverloadCharge = isOverloadCharged
        let shouldPreservePlayedCard = consumesOverloadCharge || preservesPlayedCard
        let preservedCard = shouldPreservePlayedCard ? validatedMove.card : nil
        if consumesOverloadCharge {
            isOverloadCharged = false
            debugLog("過負荷状態を消費し、使用カードを温存しました")
        }
        if shouldPreservePlayedCard {
            if preservesPlayedCard && !consumesOverloadCharge {
                debugLog("カード温存マス効果で使用カードを消費しませんでした")
            }
            refreshHandStateFromManager()
        } else {
            // 使用済みカードは即座に破棄し、スタックから除去（残数がゼロになったらスタックごと取り除く）
            let removedIndex = handManager.consumeTopCard(at: validatedMove.stackIndex)

            // スロットの空きを埋めた上で並び順・先読みを整える
            rebuildHandAndNext(preferredInsertionIndices: removedIndex.map { [$0] } ?? [])
        }

        applyPostMoveTileEffect(postMoveTileEffect, preserving: preservedCard)

        // クリア判定
        if mode.usesTargetCollection {
            applyTargetCaptureIfNeeded(along: actualTraversedPath, finalPosition: finalPosition)
            if capturedTargetCount >= mode.targetGoalCount {
                finalizeElapsedTimeIfNeeded()
                progress = .cleared
                return
            }
            if appliesTargetSwap {
                applyTileEffectTargetSwap()
            }
        }

        for target in openGateTargets {
            applyTileEffectOpenGate(target: target)
        }

        if !mode.usesTargetCollection, board.isCleared {
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

    private func registerPostMoveTileEffect(
        _ effect: TileEffect,
        postMoveTileEffect: inout PostMoveTileEffect?,
        appliesTargetSwap: inout Bool,
        openGateTargets: inout [GridPoint],
        preservesPlayedCard: inout Bool
    ) {
        switch effect {
        case .shuffleHand:
            if postMoveTileEffect == nil {
                postMoveTileEffect = .shuffleHand
            }
        case .nextRefresh:
            if postMoveTileEffect == nil {
                postMoveTileEffect = .nextRefresh
            }
        case .freeFocus:
            if postMoveTileEffect == nil {
                postMoveTileEffect = .freeFocus
            }
        case .draft:
            if postMoveTileEffect == nil {
                postMoveTileEffect = .draft
            }
        case .overload:
            postMoveTileEffect = .overload
        case .targetSwap:
            appliesTargetSwap = true
        case .openGate(let target):
            openGateTargets.append(target)
        case .preserveCard:
            preservesPlayedCard = true
        case .warp, .boost, .slow:
            break
        }
    }

    private func applyPostMoveTileEffect(_ effect: PostMoveTileEffect?, preserving preservedCard: DealtCard?) {
        guard let effect else { return }

        switch effect {
        case .shuffleHand:
            applyTileEffectHandRedraw(preserving: preservedCard)
        case .nextRefresh:
            applyTileEffectNextRefresh()
        case .freeFocus:
            applyTileEffectFreeFocus(preserving: preservedCard)
        case .draft:
            applyTileEffectDraft()
        case .overload:
            applyTileEffectOverload()
        }
    }

    private func applyTileEffectNextRefresh() {
        cancelManualDiscardSelection()
        resetBoardTapPlayRequestForPenalty()
        handManager.redrawNextPreview(using: &deck)
        refreshHandStateFromManager()
        debugLog("NEXT更新マス効果でNEXTのみ再配布")
    }

    func resetHandAndNextForTileRedraw(preserving preservedCard: DealtCard?) {
        if let preservedCard {
            handManager.resetAll(prioritizing: [preservedCard], using: &deck)
            refreshHandStateFromManager()
        } else {
            handManager.clearAll()
            rebuildHandAndNext()
        }
    }

    private func applyTileEffectFreeFocus(preserving preservedCard: DealtCard?) {
        let previousFocusCount = focusCount
        rebuildFocusedHandAndNext(preserving: preservedCard)
        focusCount = previousFocusCount
        debugLog("無料フォーカスマス効果で手札とNEXTを再配布")
    }

    private func applyTileEffectDraft() {
        let previousFocusCount = focusCount
        rebuildFocusedHandAndNext()
        focusCount = previousFocusCount
        debugLog("ドラフトマス効果で目的地に近づきやすい手札とNEXTを再配布")
    }

    private func applyTileEffectOverload() {
        if mode.usesTargetCollection {
            focusCount += 1
            debugLog("過負荷マスの反動でフォーカス回数を +1")
        } else {
            penaltyCount += 1
            debugLog("過負荷マスの反動でペナルティを +1")
        }
        isOverloadCharged = true
        debugLog("過負荷状態を付与: 次の1手で使用カードを温存")
    }

    private func applyTileEffectTargetSwap() {
        guard mode.usesTargetCollection,
              let currentTarget = targetPoint,
              let firstUpcomingTarget = upcomingTargetPoints.first
        else { return }

        targetPoint = firstUpcomingTarget
        upcomingTargetPoints[0] = currentTarget
        debugLog("転換マス効果で表示中目的地の先頭と次の表示順を入れ替えました")
    }

    private func applyTileEffectOpenGate(target: GridPoint) {
        var updatedBoard = board
        guard updatedBoard.openGate(at: target) else {
            debugLog("開門マス効果: \(target) は障害物ではないため変化なし")
            return
        }
        board = updatedBoard
        debugLog("開門マス効果で \(target) を通行可能にしました")
    }

    /// カードの移動候補を、表示中の複数目的地を考慮して解決する
    private func resolvedPaths(
        for card: DealtCard,
        from origin: GridPoint,
        on activeBoard: Board
    ) -> [MoveCard.MovePattern.Path] {
        let context = moveResolutionContext(
            on: activeBoard,
            targetPoint: mode.usesTargetCollection ? nearestActiveTarget(from: origin) : nil
        )
        return card.move.resolvePaths(from: origin, context: context)
    }

    private func moveResolutionContext(
        on activeBoard: Board,
        targetPoint: GridPoint?
    ) -> MoveCard.MovePattern.ResolutionContext {
        MoveCard.MovePattern.ResolutionContext(
            boardSize: activeBoard.size,
            contains: { point in activeBoard.contains(point) },
            isTraversable: { point in activeBoard.isTraversable(point) },
            isVisited: { point in activeBoard.isVisited(point) },
            targetPoint: targetPoint,
            effectAt: { point in activeBoard.effect(at: point) }
        )
    }

    private func nearestActiveTarget(from origin: GridPoint) -> GridPoint? {
        activeTargetPoints.min { lhs, rhs in
            let lhsDistance = manhattanDistance(from: origin, to: lhs)
            let rhsDistance = manhattanDistance(from: origin, to: rhs)
            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }
            if lhs.y != rhs.y { return lhs.y < rhs.y }
            return lhs.x < rhs.x
        }
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

            // 固定ワープカードはカード自身が保持する目的地のみを候補として提示する
            if topCard.move == .fixedWarp {
                // --- 目的地が未設定の場合は安全のためスキップする（モード側で最低 1 件を想定）---
                guard let destination = topCard.fixedWarpDestination else { continue }
                // --- 既に目的地へいる場合は使用できない仕様のため除外する ---
                guard destination != origin else { continue }
                // --- 盤外や障害物マスへワープしないよう二重チェックする ---
                guard activeBoard.contains(destination), activeBoard.isTraversable(destination) else { continue }

                let vector = MoveVector(dx: destination.x - origin.x, dy: destination.y - origin.y)
                let resolution = MovementResolution(path: [destination], finalPosition: destination)
                resolved.append(
                    ResolvedCardMove(
                        stackID: stack.id,
                        stackIndex: index,
                        card: topCard,
                        moveVector: vector,
                        resolution: resolution
                    )
                )
                // --- 固定ワープは単一候補のみを扱うため、MovePattern による追加解決は行わず次のカードへ進む ---
                continue
            }

            // MoveCard の MovePattern から盤面状況に応じた経路を算出する
            for path in resolvedPaths(for: topCard, from: origin, on: activeBoard) {
                let traversed = path.traversedPoints
                guard let destination = traversed.last else { continue }
                let resolution = MovementResolution(path: traversed, finalPosition: destination)
                resolved.append(
                    ResolvedCardMove(
                        stackID: stack.id,
                        stackIndex: index,
                        card: topCard,
                        moveVector: path.vector,
                        resolution: resolution
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
        let allMoves = availableMoves()
        // availableMoves() からタップ地点へ到達できる候補だけを抽出する
        let destinationMatches = allMoves.filter { $0.destination == point }
        let matchingMoves: [ResolvedCardMove]
        if !destinationMatches.isEmpty {
            matchingMoves = destinationMatches
        } else if mode.usesTargetCollection, activeTargetPoints.contains(point) {
            // 目的地制では、終点ではなく通過途中の表示中目的地タップでも該当カードを選べるようにする
            matchingMoves = allMoves.filter { $0.traversedPoints.contains(point) }
        } else {
            matchingMoves = []
        }

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

    /// スポーン位置選択警告を UI 側で表示したあとに呼び出す
    /// - Parameter id: 消したい警告の識別子（不一致の場合は何もしない）
    public func clearSpawnSelectionWarning(_ id: UUID) {
        guard spawnSelectionWarning?.id == id else { return }
        spawnSelectionWarning = nil
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
            // 新しいゲームを開始する際はモードのシードを再適用してリセットする。
            // シードが nil の場合は Deck 側で自動生成され、従来通りランダムな展開になる。
            deck = Deck(
                seed: mode.deckSeed,
                configuration: mode.deckConfiguration,
                fixedWarpDestinations: mode.fixedWarpDestinationPool
            )
        } else {
            deck.reset()
        }

        board = Board(
            size: mode.boardSize,
            initialVisitedPoints: mode.initialVisitedPoints,
            requiredVisitOverrides: mode.additionalVisitRequirements,
            togglePoints: mode.toggleTilePoints,
            impassablePoints: mode.impassableTilePoints,
            tileEffects: mode.tileEffects
        )
        current = mode.initialSpawnPoint
        moveCount = 0
        penaltyCount = 0
        hasRevisitedTile = false
        elapsedSeconds = 0
        capturedTargetCount = 0
        focusCount = 0
        isOverloadCharged = false
        configureTargetsForNewSession()
        penaltyEvent = nil
        boardTapPlayRequest = nil
        spawnSelectionWarning = nil
        isAwaitingManualDiscardSelection = false
        lastMovementResolution = nil
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

    /// 一時停止ボタンなどからの操作でタイマーを停止する
    /// - Parameter referenceDate: 一時停止が発生した時刻（テスト時に明示指定したい場合に利用）
    public func pauseTimer(referenceDate: Date = Date()) {
        // プレイ中以外では停止させる必要がないため、進行状態を確認した上で処理する
        guard progress == .playing else { return }
        sessionTimer.beginPause(at: referenceDate)
    }

    /// 停止中のタイマーを再開する
    /// - Parameter referenceDate: 再開する時刻（テストでは任意の値を指定できるようにする）
    public func resumeTimer(referenceDate: Date = Date()) {
        sessionTimer.endPause(at: referenceDate)
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

    /// 新規セッション用に目的地制の状態を初期化する
    private func configureTargetsForNewSession() {
        guard mode.usesTargetCollection else {
            targetPoint = nil
            upcomingTargetPoints = []
            return
        }

        let origin = current ?? BoardGeometry.defaultSpawnPoint(for: mode.boardSize)
        let first = chooseNextTarget(from: origin, previousTarget: nil, offset: 0)
        targetPoint = first
        upcomingTargetPoints = makeUpcomingTargets(
            from: origin,
            currentTarget: first,
            count: 2
        )
    }

    /// 表示中目的地へ到達していれば獲得処理と次目的地の更新を行う
    private func applyTargetCaptureIfNeeded(along traversedPoints: [GridPoint], finalPosition: GridPoint) {
        guard mode.usesTargetCollection else { return }

        var visibleTargets = activeTargetPoints
        guard !visibleTargets.isEmpty else { return }

        var capturedTargets: [GridPoint] = []
        for point in traversedPoints {
            guard let capturedIndex = visibleTargets.firstIndex(of: point) else { continue }
            let captured = visibleTargets.remove(at: capturedIndex)
            capturedTargets.append(captured)
            capturedTargetCount += 1
            debugLog("目的地獲得: \(capturedTargetCount)/\(mode.targetGoalCount) @\(captured)")

            if capturedTargetCount >= mode.targetGoalCount {
                break
            }
        }

        guard !capturedTargets.isEmpty else { return }

        guard capturedTargetCount < mode.targetGoalCount else {
            targetPoint = nil
            upcomingTargetPoints = []
            return
        }

        refillVisibleTargets(
            &visibleTargets,
            finalPosition: finalPosition,
            previousTarget: capturedTargets.last
        )
        applyVisibleTargets(visibleTargets)
    }

    private func refillVisibleTargets(
        _ visibleTargets: inout [GridPoint],
        finalPosition: GridPoint,
        previousTarget: GridPoint?
    ) {
        let desiredCount = activeTargetDisplayCount
        while visibleTargets.count < desiredCount {
            let anchor = visibleTargets.last ?? finalPosition
            var excludedTargets = Set(visibleTargets)
            excludedTargets.insert(finalPosition)
            if let previousTarget {
                excludedTargets.insert(previousTarget)
            }
            let next = chooseNextTarget(
                from: anchor,
                previousTarget: visibleTargets.last ?? previousTarget,
                offset: capturedTargetCount + visibleTargets.count + 1,
                avoiding: excludedTargets
            )
            visibleTargets.append(next)
        }
    }

    private func applyVisibleTargets(_ visibleTargets: [GridPoint]) {
        targetPoint = visibleTargets.first
        upcomingTargetPoints = Array(visibleTargets.dropFirst())
    }

    /// 先読み用の目的地列を作る
    private func makeUpcomingTargets(
        from origin: GridPoint,
        currentTarget: GridPoint?,
        count: Int
    ) -> [GridPoint] {
        guard count > 0 else { return [] }
        var result: [GridPoint] = []
        var anchor = currentTarget ?? origin
        var previous = currentTarget
        var used = Set([origin])
        if let currentTarget {
            used.insert(currentTarget)
        }

        while result.count < count {
            var next = chooseNextTarget(
                from: anchor,
                previousTarget: previous,
                offset: result.count + 1,
                avoiding: used
            )
            var retryOffset = result.count + 2
            while used.contains(next), retryOffset < 32 {
                next = chooseNextTarget(
                    from: anchor,
                    previousTarget: previous,
                    offset: retryOffset,
                    avoiding: used
                )
                retryOffset += 1
            }
            result.append(next)
            used.insert(next)
            previous = next
            anchor = next
        }

        return result
    }

    /// 現在地から近すぎず遠すぎない目的地を決定する
    private func chooseNextTarget(
        from origin: GridPoint,
        previousTarget: GridPoint?,
        offset: Int,
        avoiding additionalExcludedPoints: Set<GridPoint> = []
    ) -> GridPoint {
        let allPoints = board.allTraversablePoints.sorted { lhs, rhs in
            if lhs.y != rhs.y { return lhs.y < rhs.y }
            return lhs.x < rhs.x
        }

        let preferredDistanceRange = preferredTargetDistanceRange()
        let preferred = allPoints.filter { point in
            guard point != origin, point != previousTarget else { return false }
            guard !additionalExcludedPoints.contains(point) else { return false }
            let distance = manhattanDistance(from: origin, to: point)
            return preferredDistanceRange.contains(distance)
        }
        let fallback = allPoints.filter { point in
            point != origin && point != previousTarget && !additionalExcludedPoints.contains(point)
        }
        let candidates = preferred.isEmpty ? fallback : preferred
        guard !candidates.isEmpty else { return origin }

        let seed = capturedTargetCount * 7 + origin.x * 3 + origin.y * 5 + offset * 11
        let index = abs(seed) % candidates.count
        return candidates[index]
    }

    private func preferredTargetDistanceRange() -> ClosedRange<Int> {
        guard mode.isCampaignStage, mode.boardSize >= CampaignLibrary.campaignBoardSize else {
            return 2...4
        }
        if let stageID = mode.campaignMetadataSnapshot?.stageID, stageID.chapter <= 1 {
            return 2...4
        }
        return 3...6
    }

    /// フォーカス操作として、目的地に近づきやすいカードを優先して再配布する
    public func applyFocusRedraw() {
        guard mode.usesTargetCollection else {
            applyManualPenaltyRedraw()
            return
        }
        guard progress == .playing || progress == .awaitingSpawn else { return }

        focusCount += 1
        rebuildFocusedHandAndNext()
        checkDeadlockAndApplyPenaltyIfNeeded(lastPaidPenaltyAmount: 0)
    }

    /// 目的地に近づくカードを優先して手札と NEXT を組み直す
    func rebuildFocusedHandAndNext(preserving preservedCard: DealtCard? = nil) {
        let targets = activeTargetPoints
        guard mode.usesTargetCollection, let origin = current, !targets.isEmpty else {
            if let preservedCard {
                handManager.resetAll(prioritizing: [preservedCard], using: &deck)
                refreshHandStateFromManager()
            } else {
                rebuildHandAndNext()
            }
            return
        }

        setManualDiscardSelectionState(false)
        resetBoardTapPlayRequestForPenalty()

        var drawn: [DealtCard] = deck.draw(count: 48)
        if drawn.isEmpty {
            rebuildHandAndNext()
            return
        }

        drawn.sort { lhs, rhs in
            let lhsScore = targetApproachScore(for: lhs, from: origin, targets: targets)
            let rhsScore = targetApproachScore(for: rhs, from: origin, targets: targets)
            if lhsScore.improvement != rhsScore.improvement {
                return lhsScore.improvement > rhsScore.improvement
            }
            if lhsScore.bestDistance != rhsScore.bestDistance {
                return lhsScore.bestDistance < rhsScore.bestDistance
            }
            return lhs.move.displayName < rhs.move.displayName
        }
        if let preservedCard {
            drawn.removeAll { $0.id == preservedCard.id }
            drawn.insert(preservedCard, at: 0)
        }

        handManager.resetAll(prioritizing: drawn, using: &deck)
        refreshHandStateFromManager()
        debugLog("フォーカス再配布: focusCount=\(focusCount), targets=\(targets)")
    }

    /// 指定カードが表示中目的地へどれだけ近づけるかを評価する
    private func targetApproachScore(
        for card: DealtCard,
        from origin: GridPoint,
        targets: [GridPoint]
    ) -> (improvement: Int, bestDistance: Int) {
        targets
            .map { targetApproachScore(for: card, from: origin, target: $0) }
            .max { lhs, rhs in
                if lhs.improvement != rhs.improvement {
                    return lhs.improvement < rhs.improvement
                }
                return lhs.bestDistance > rhs.bestDistance
            } ?? (Int.min, Int.max)
    }

    /// 指定カードが単一目的地へどれだけ近づけるかを評価する
    private func targetApproachScore(
        for card: DealtCard,
        from origin: GridPoint,
        target: GridPoint
    ) -> (improvement: Int, bestDistance: Int) {
        let currentDistance = manhattanDistance(from: origin, to: target)
        let activeBoard = board

        if card.move == .fixedWarp, let destination = card.fixedWarpDestination {
            guard destination != origin,
                  activeBoard.contains(destination),
                  activeBoard.isTraversable(destination) else {
                return (Int.min, Int.max)
            }
            let distance = manhattanDistance(from: destination, to: target)
            return (currentDistance - distance, distance)
        }

        let context = moveResolutionContext(on: activeBoard, targetPoint: target)
        let destinations = card.move.resolvePaths(from: origin, context: context).compactMap(\.traversedPoints.last)
        guard let bestDistance = destinations.map({ manhattanDistance(from: $0, to: target) }).min() else {
            return (Int.min, Int.max)
        }
        return (currentDistance - bestDistance, bestDistance)
    }

    private func manhattanDistance(from lhs: GridPoint, to rhs: GridPoint) -> Int {
        abs(lhs.x - rhs.x) + abs(lhs.y - rhs.y)
    }

    private func normalizedDirection(from origin: GridPoint, to destination: GridPoint) -> MoveVector {
        MoveVector(
            dx: destination.x == origin.x ? 0 : (destination.x > origin.x ? 1 : -1),
            dy: destination.y == origin.y ? 0 : (destination.y > origin.y ? 1 : -1)
        )
    }

    private func effectivePathPoints(for move: ResolvedCardMove, from origin: GridPoint) -> [GridPoint] {
        let rawPath = move.path
        guard rawPath.count == 1,
              shouldExpandForSlowTileResolution(move.card.move),
              let destination = rawPath.first
        else { return rawPath }

        let direction = normalizedDirection(from: origin, to: destination)
        guard direction.dx != 0 || direction.dy != 0 else { return rawPath }

        var current = origin
        var expanded: [GridPoint] = []
        while current != destination {
            current = current.offset(dx: direction.dx, dy: direction.dy)
            expanded.append(current)
        }

        let hasIntermediateSlowTile = expanded.dropLast().contains { point in
            board.effect(at: point) == .slow
        }
        return hasIntermediateSlowTile ? expanded : rawPath
    }

    private func shouldExpandForSlowTileResolution(_ move: MoveCard) -> Bool {
        switch move {
        case .straightUp2,
             .straightDown2,
             .straightRight2,
             .straightLeft2,
             .diagonalUpRight2,
             .diagonalDownRight2,
             .diagonalDownLeft2,
             .diagonalUpLeft2:
            return true
        default:
            return false
        }
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
            moveVector: resolved.moveVector,
            resolution: resolved.resolution
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
        // UI 側ではハイライト生成時点で障害物マスを弾いているが、二重チェックでゲームコアも移動可能かを検証する
        guard board.isTraversable(point) else { return }
        // 任意スポーン前に表示している目的地は、開始時の即獲得や駒との重なりを避けるため選択不可にする
        guard !activeTargetPoints.contains(point) else {
            spawnSelectionWarning = SpawnSelectionWarning(point: point, reason: .targetTile)
            return
        }

        debugLog("スポーン位置を \(point) に確定")
        current = point
        board.markVisited(point)
        if mode.usesTargetCollection, activeTargetPoints.isEmpty {
            configureTargetsForNewSession()
        }
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

    /// ペナルティイベントを外部公開用に更新する
    /// - Parameter event: 公開したいイベント（nil でリセット）
    func publishPenaltyEvent(_ event: PenaltyEvent?) {
        penaltyEvent = event
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
    static func makeTestInstance(
        deck: Deck,
        current: GridPoint? = nil,
        mode: GameMode = .standard,
        initialVisitedPoints: [GridPoint]? = nil
    ) -> GameCore {
        let core = GameCore(mode: mode)
        core.deck = deck
        core.deck.reset()

        let resolvedCurrent = current ?? mode.initialSpawnPoint
        let visitedPoints: [GridPoint]
        if let overrideVisited = initialVisitedPoints {
            visitedPoints = overrideVisited
        } else if let resolvedCurrent {
            visitedPoints = [resolvedCurrent]
        } else {
            visitedPoints = mode.initialVisitedPoints
        }

        if resolvedCurrent != nil {
            core.board = Board(
                size: mode.boardSize,
                initialVisitedPoints: visitedPoints,
                requiredVisitOverrides: mode.additionalVisitRequirements,
                togglePoints: mode.toggleTilePoints,
                impassablePoints: mode.impassableTilePoints,
                tileEffects: mode.tileEffects
            )
        } else {
            core.board = Board(
                size: mode.boardSize,
                initialVisitedPoints: visitedPoints,
                requiredVisitOverrides: mode.additionalVisitRequirements,
                togglePoints: mode.toggleTilePoints,
                impassablePoints: mode.impassableTilePoints,
                tileEffects: mode.tileEffects
            )
        }
        core.current = resolvedCurrent
        core.moveCount = 0
        core.penaltyCount = 0
        core.hasRevisitedTile = false
        core.capturedTargetCount = 0
        core.focusCount = 0
        core.isOverloadCharged = false
        core.configureTargetsForNewSession()
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

    /// テスト用に目的地制の状態を直接差し替える
    func overrideTargetStateForTesting(
        targetPoint: GridPoint?,
        upcomingTargetPoints: [GridPoint] = [],
        capturedTargetCount: Int = 0,
        focusCount: Int = 0
    ) {
        self.targetPoint = targetPoint
        self.upcomingTargetPoints = upcomingTargetPoints
        self.capturedTargetCount = capturedTargetCount
        self.focusCount = focusCount
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

    /// 任意の時刻を基準にライブ計測値を取得するテスト専用ヘルパー
    /// - Parameter referenceDate: 計測に利用したい時刻
    /// - Returns: 指定時点での経過秒数
    func liveElapsedSecondsForTesting(asOf referenceDate: Date) -> Int {
        sessionTimer.liveElapsedSeconds(asOf: referenceDate)
    }
}
#endif
