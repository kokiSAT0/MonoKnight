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

/// 巡回兵が次に進む向きを UI へ渡すためのプレビュー情報
public struct EnemyPatrolMovementPreview: Identifiable, Equatable {
    public let enemyID: String
    public let current: GridPoint
    public let next: GridPoint
    public let vector: MoveVector

    public var id: String { enemyID }

    public init(enemyID: String, current: GridPoint, next: GridPoint, vector: MoveVector) {
        self.enemyID = enemyID
        self.current = current
        self.next = next
        self.vector = vector
    }
}

/// 回転見張りが次に向く方向を UI へ渡すためのプレビュー情報
public struct EnemyRotatingWatcherDirectionPreview: Identifiable, Equatable {
    public let enemyID: String
    public let current: GridPoint
    public let vector: MoveVector

    public var id: String { enemyID }

    public init(enemyID: String, current: GridPoint, vector: MoveVector) {
        self.enemyID = enemyID
        self.current = current
        self.vector = vector
    }
}

/// 鍵取得によってダンジョン出口が解錠されたことを UI へ知らせるイベント
public struct DungeonExitUnlockEvent: Identifiable, Equatable {
    public let id: UUID
    public let exitPoint: GridPoint
    public let unlockPoint: GridPoint

    public init(id: UUID = UUID(), exitPoint: GridPoint, unlockPoint: GridPoint) {
        self.id = id
        self.exitPoint = exitPoint
        self.unlockPoint = unlockPoint
    }
}

/// ひび割れ床が崩落し、下階へ落下することを UI へ知らせるイベント
public struct DungeonFallEvent: Identifiable, Equatable {
    public let id: UUID
    public let point: GridPoint
    public let sourceFloorIndex: Int
    public let destinationFloorIndex: Int
    public let hpAfterDamage: Int

    public init(
        id: UUID = UUID(),
        point: GridPoint,
        sourceFloorIndex: Int,
        destinationFloorIndex: Int,
        hpAfterDamage: Int
    ) {
        self.id = id
        self.point = point
        self.sourceFloorIndex = sourceFloorIndex
        self.destinationFloorIndex = destinationFloorIndex
        self.hpAfterDamage = hpAfterDamage
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
    /// 盤面タップでカードなし基本移動を依頼された際の要求
    @Published public private(set) var boardTapBasicMoveRequest: BoardTapBasicMoveRequest?
    /// スポーン位置選択中に選べないマスをタップした際の警告イベント
    /// - Note: UI 側が表示へ変換したら `clearSpawnSelectionWarning` でリセットする。
    @Published public private(set) var spawnSelectionWarning: SpawnSelectionWarning?
    /// 捨て札ペナルティの対象選択を待っているかどうか
    /// - Note: UI のハイライト切り替えや操作制御に利用する
    @Published public private(set) var isAwaitingManualDiscardSelection: Bool = false
    /// 補助カード「入替」の対象選択を待っているかどうか
    @Published public private(set) var isAwaitingSupportSwapSelection: Bool = false
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
    /// 塔ダンジョンで利用する現在 HP
    @Published public private(set) var dungeonHP: Int = 0
    /// 成長塔の区間内で罠/床崩落ダメージを無効化できる残り回数
    @Published public private(set) var hazardDamageMitigationsRemaining: Int = 0
    /// 塔ダンジョンで利用する敵状態
    @Published public private(set) var enemyStates: [EnemyState] = []
    /// ひび割れ状態の床
    @Published public private(set) var crackedFloorPoints: Set<GridPoint> = []
    /// 崩落して通行不能になった床
    @Published public private(set) var collapsedFloorPoints: Set<GridPoint> = []
    /// 塔ダンジョンの所持カード一覧
    @Published public private(set) var dungeonInventoryEntries: [DungeonInventoryEntry] = []
    /// 取得済みのフロア内カード ID
    @Published public private(set) var collectedDungeonCardPickupIDs: Set<String> = []
    /// 所持枠が満杯で床落ちカードの取捨選択を待っている状態
    @Published public private(set) var pendingDungeonPickupChoice: PendingDungeonPickupChoice?
    /// 塔ダンジョン出口が現在有効かどうか
    @Published public private(set) var isDungeonExitUnlocked: Bool = true
    /// 出口解錠演出用の単発イベント
    @Published public private(set) var dungeonExitUnlockEvent: DungeonExitUnlockEvent?
    /// ひび割れ床崩落による下階落下イベント
    @Published public private(set) var dungeonFallEvent: DungeonFallEvent?
    /// プレイヤー行動後に発生した敵ターンの可視化用イベント
    @Published public private(set) var dungeonEnemyTurnEvent: DungeonEnemyTurnEvent?
    /// 入替カードを使用するために選択中の補助カードスタック
    private var pendingSupportSwapStackID: UUID?
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
    /// 塔ダンジョンの残り手数
    public var remainingDungeonTurns: Int? {
        guard let turnLimit = mode.dungeonRules?.failureRule.turnLimit else { return nil }
        return max(turnLimit - moveCount, 0)
    }
    /// 敵が次に攻撃または接触判定を持つ危険マス
    public var enemyDangerPoints: Set<GridPoint> {
        dangerPoints(for: enemyStates)
    }
    /// 予告兵が次の敵ターンに攻撃するマス
    public var enemyWarningPoints: Set<GridPoint> {
        markerWarningPoints(for: enemyStates)
    }
    /// 巡回兵ごとの次移動方向
    public var enemyPatrolMovementPreviews: [EnemyPatrolMovementPreview] {
        enemyStates.compactMap { patrolMovementPreview(for: $0) }
    }
    /// 追跡兵ごとの次移動方向
    public var enemyChaserMovementPreviews: [EnemyPatrolMovementPreview] {
        enemyStates.compactMap { chaserMovementPreview(for: $0) }
    }
    /// 回転見張りごとの次視線方向
    public var enemyRotatingWatcherDirectionPreviews: [EnemyRotatingWatcherDirectionPreview] {
        enemyStates.compactMap { rotatingWatcherDirectionPreview(for: $0) }
    }
    /// まだ盤面上に残っている拾得カード
    public var activeDungeonCardPickups: [DungeonCardPickupDefinition] {
        guard mode.dungeonRules?.cardAcquisitionMode == .inventoryOnly,
              let cardPickups = mode.dungeonRules?.cardPickups
        else { return [] }
        return cardPickups.filter { !collectedDungeonCardPickupIDs.contains($0.id) }
    }
    public var isAwaitingDungeonPickupChoice: Bool {
        pendingDungeonPickupChoice != nil
    }
    /// 未取得の塔鍵マス。階段が解錠されたら盤面表示から消える。
    public var dungeonKeyPoints: Set<GridPoint> {
        guard mode.usesDungeonExit,
              !isDungeonExitUnlocked,
              let unlockPoint = mode.dungeonRules?.exitLock?.unlockPoint
        else { return [] }
        return [unlockPoint]
    }
    /// 塔専用の拾得/報酬インベントリを使うかどうか
    var usesDungeonInventoryCards: Bool {
        mode.dungeonRules?.cardAcquisitionMode == .inventoryOnly
    }

    /// 山札管理（`Deck.swift` に定義された重み付き無限山札を使用）
    private var deck: Deck
    /// 経過時間を管理する専用タイマー
    /// - Note: GameCore の責務を整理するために専用構造体へ委譲する
    private var sessionTimer = GameSessionTimer()
    /// 目的地制で同時に表示・獲得可能にする目的地数
    private let activeTargetDisplayCount = 3

    /// 初期化時にモードを指定して各種状態を構築する
    /// - Parameter mode: 適用したいゲームモード（省略時は塔プレースホルダー）
    public init(mode: GameMode = .dungeonPlaceholder) {
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

    /// 現在の塔攻略を中断復帰用スナップショットへ変換する
    public func makeDungeonResumeSnapshot() -> DungeonRunResumeSnapshot? {
        guard mode.usesDungeonExit,
              progress == .playing,
              let metadata = mode.dungeonMetadataSnapshot,
              let runState = metadata.runState,
              let current
        else { return nil }

        return DungeonRunResumeSnapshot(
            dungeonID: metadata.dungeonID,
            floorIndex: runState.currentFloorIndex,
            runState: runState,
            currentPoint: current,
            visitedPoints: Set(board.visitedPoints),
            moveCount: moveCount,
            elapsedSeconds: liveElapsedSeconds,
            dungeonHP: dungeonHP,
            hazardDamageMitigationsRemaining: hazardDamageMitigationsRemaining,
            enemyStates: enemyStates,
            crackedFloorPoints: crackedFloorPoints,
            collapsedFloorPoints: collapsedFloorPoints,
            dungeonInventoryEntries: dungeonInventoryEntries,
            collectedDungeonCardPickupIDs: collectedDungeonCardPickupIDs,
            isDungeonExitUnlocked: isDungeonExitUnlocked,
            pendingDungeonPickupChoice: pendingDungeonPickupChoice
        )
    }

    /// 保存済みの塔攻略スナップショットを現在の `GameMode` へ復元する
    @discardableResult
    public func restoreDungeonResumeSnapshot(_ snapshot: DungeonRunResumeSnapshot) -> Bool {
        guard snapshot.version == DungeonRunResumeSnapshot.currentVersion,
              mode.usesDungeonExit,
              let metadata = mode.dungeonMetadataSnapshot,
              let runState = metadata.runState,
              metadata.dungeonID == snapshot.dungeonID,
              runState.currentFloorIndex == snapshot.floorIndex,
              runState.dungeonID == snapshot.runState.dungeonID,
              snapshot.currentPoint.isInside(boardSize: mode.boardSize)
        else { return false }

        let validVisitedPoints = snapshot.visitedPoints.filter { $0.isInside(boardSize: mode.boardSize) }
        let validCollapsedPoints = snapshot.collapsedFloorPoints.filter { $0.isInside(boardSize: mode.boardSize) }
        guard validVisitedPoints.count == snapshot.visitedPoints.count,
              validCollapsedPoints.count == snapshot.collapsedFloorPoints.count
        else { return false }

        board = Board(
            size: mode.boardSize,
            initialVisitedPoints: Array(validVisitedPoints),
            requiredVisitOverrides: mode.additionalVisitRequirements,
            togglePoints: mode.toggleTilePoints,
            impassablePoints: mode.impassableTilePoints,
            tileEffects: mode.tileEffects
        )
        for point in validCollapsedPoints {
            board.collapseFloor(at: point)
        }
        guard board.isTraversable(snapshot.currentPoint) else { return false }

        current = snapshot.currentPoint
        moveCount = snapshot.moveCount
        penaltyCount = 0
        hasRevisitedTile = false
        capturedTargetCount = 0
        focusCount = 0
        isOverloadCharged = false
        dungeonHP = snapshot.dungeonHP
        hazardDamageMitigationsRemaining = snapshot.hazardDamageMitigationsRemaining
        enemyStates = snapshot.enemyStates
        crackedFloorPoints = snapshot.crackedFloorPoints
        collapsedFloorPoints = validCollapsedPoints
        dungeonInventoryEntries = snapshot.dungeonInventoryEntries
        collectedDungeonCardPickupIDs = snapshot.collectedDungeonCardPickupIDs
        pendingDungeonPickupChoice = snapshot.pendingDungeonPickupChoice
        isDungeonExitUnlocked = snapshot.isDungeonExitUnlocked
        dungeonExitUnlockEvent = nil
        dungeonFallEvent = nil
        penaltyEvent = nil
        boardTapPlayRequest = nil
        boardTapBasicMoveRequest = nil
        spawnSelectionWarning = nil
        isAwaitingManualDiscardSelection = false
        isAwaitingSupportSwapSelection = false
        pendingSupportSwapStackID = nil
        lastMovementResolution = nil
        progress = .playing
        sessionTimer.resumeFromElapsedSeconds(snapshot.elapsedSeconds)
        elapsedSeconds = sessionTimer.elapsedSeconds

        if usesDungeonInventoryCards {
            syncDungeonInventoryHandStacks()
        } else {
            handManager.resetAll(using: &deck)
            refreshHandStateFromManager()
        }
        announceRemainingTiles()
        return true
    }

    /// 手札の並び順設定を更新し、必要であれば再ソートする
    /// - Parameter newStrategy: ユーザーが選択した並び替え方式
    public func updateHandOrderingStrategy(_ newStrategy: HandOrderingStrategy) {
        handManager.updateHandOrderingStrategy(newStrategy)
        if usesDungeonInventoryCards {
            syncDungeonInventoryHandStacks()
            return
        }
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
        guard current != nil, let topCard = handStacks[index].topCard else { return }

        if topCard.supportCard != nil {
            playSupportCard(at: index)
            return
        }

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

    /// 補助カードが現在使用できるかを返す
    public func isSupportCardUsable(in stack: HandStack) -> Bool {
        guard progress == .playing, stack.topCard?.supportCard != nil else { return false }
        if stack.topCard?.supportCard == .swapOne {
            return handStacks.contains { candidate in
                candidate.id != stack.id && candidate.topCard != nil
            }
        }
        return true
    }

    /// 手札インデックスの補助カードを使用する
    public func playSupportCard(at index: Int) {
        guard progress == .playing, handStacks.indices.contains(index), current != nil else { return }
        guard pendingDungeonPickupChoice == nil else { return }
        guard !isAwaitingManualDiscardSelection, !isAwaitingSupportSwapSelection else { return }
        guard let card = handStacks[index].topCard, let support = card.supportCard else { return }
        guard isSupportCardUsable(in: handStacks[index]) else { return }

        switch support {
        case .nextRefresh:
            consumeSupportCard(at: index)
            handManager.redrawNextPreview(using: &deck)
            refreshHandStateFromManager()
            checkDeadlockAndApplyPenaltyIfNeeded()
            debugLog("補助カード NEXT更新: NEXTのみ再配布")
        case .guidance:
            consumeSupportCard(at: index)
            let previousFocusCount = focusCount
            rebuildFocusedHandAndNext()
            focusCount = previousFocusCount
            checkDeadlockAndApplyPenaltyIfNeeded()
            debugLog("補助カード 導き: フォーカス回数を増やさず手札とNEXTを再配布")
        case .refillEmptySlots:
            let canRefillExistingEmptySlots = !usesDungeonInventoryCards ||
                dungeonInventoryEntries.filter(\.hasUsesRemaining).count < 9
            consumeSupportCard(at: index)
            if canRefillExistingEmptySlots {
                refillDungeonEmptySlotsWithRandomMoveCards()
            }
            checkDeadlockAndApplyPenaltyIfNeeded()
            debugLog("補助カード 補給: 空き手札枠へ移動カードを補給")
        case .swapOne:
            pendingSupportSwapStackID = handStacks[index].id
            isAwaitingSupportSwapSelection = true
            resetBoardTapPlayRequestForPenalty()
            debugLog("補助カード 入替: 対象スタック選択待ち")
        }
    }

    /// 入替カードの対象選択をキャンセルする
    public func cancelSupportSwapSelection() {
        guard isAwaitingSupportSwapSelection || pendingSupportSwapStackID != nil else { return }
        isAwaitingSupportSwapSelection = false
        pendingSupportSwapStackID = nil
        debugLog("補助カード 入替の対象選択をキャンセル")
    }

    /// 入替カードで指定した手札スタックを捨てて補充する
    @discardableResult
    public func applySupportSwap(toTargetStackID targetStackID: UUID) -> Bool {
        guard progress == .playing, isAwaitingSupportSwapSelection else { return false }
        guard let supportStackID = pendingSupportSwapStackID else { return false }
        if supportStackID == targetStackID {
            cancelSupportSwapSelection()
            return false
        }
        guard let supportIndex = handStacks.firstIndex(where: { $0.id == supportStackID }),
              handStacks[supportIndex].topCard?.supportCard == .swapOne,
              let targetIndex = handStacks.firstIndex(where: { $0.id == targetStackID })
        else {
            cancelSupportSwapSelection()
            return false
        }

        isAwaitingSupportSwapSelection = false
        pendingSupportSwapStackID = nil
        resetBoardTapPlayRequestForPenalty()

        let removalIndices = [supportIndex, targetIndex].sorted(by: >)
        var preferredInsertionIndices: [Int] = []
        for removalIndex in removalIndices {
            if removalIndex == supportIndex {
                if let emptiedIndex = handManager.consumeTopCard(at: removalIndex) {
                    preferredInsertionIndices.append(emptiedIndex)
                }
            } else {
                _ = handManager.removeStack(at: removalIndex)
                preferredInsertionIndices.append(removalIndex)
            }
        }

        moveCount += 1
        rebuildHandAndNext(preferredInsertionIndices: preferredInsertionIndices.sorted())
        checkDeadlockAndApplyPenaltyIfNeeded()
        debugLog("補助カード 入替: 対象スタックを破棄して補充")
        return true
    }

    private func consumeSupportCard(at index: Int) {
        isAwaitingSupportSwapSelection = false
        pendingSupportSwapStackID = nil
        cancelManualDiscardSelection()
        resetBoardTapPlayRequestForPenalty()
        let support = handStacks.indices.contains(index) ? handStacks[index].topCard?.supportCard : nil
        let removedIndex: Int?
        if usesDungeonInventoryCards, let support {
            consumeDungeonInventorySupportCard(support)
            removedIndex = nil
        } else {
            removedIndex = handManager.consumeTopCard(at: index)
        }
        moveCount += 1
        if !usesDungeonInventoryCards {
            rebuildHandAndNext(preferredInsertionIndices: removedIndex.map { [$0] } ?? [])
        }
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
        // --- 指定されたカード ID とカード種別が一致するか二重で確認する ---
        guard topCard.id == resolvedMove.card.id, topCard.playable == resolvedMove.card.playable else {
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
        guard pendingDungeonPickupChoice == nil else { return }
        // 捨て札モード中は移動を開始せず安全に抜ける
        guard !isAwaitingManualDiscardSelection else { return }
        // UI 側で保持していた情報が古くなっていないかを安全確認
        // - Note: validatedResolvedMove(_: ) が index 補正とカード一致チェックを共通化する
        guard let (validatedMove, latestStack) = validatedResolvedMove(resolvedMove),
              let card = latestStack.topCard else {
            return
        }
        guard let cardMove = card.moveCard else { return }
        // MovePattern から算出した経路が現時点でも有効かを検証し、不正な入力を排除する
        let snapshotBoard = board
        let validPaths = resolvedPaths(for: card, from: currentPosition, on: snapshotBoard)

        let isStillValid: Bool
        if cardMove == .fixedWarp {
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
            "カード \(cardMove) を使用し \(currentPosition) -> \(validatedMove.destination) へ移動予定 (vector=\(validatedMove.moveVector))"
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

            updateDungeonExitLockIfNeeded(at: stepPoint)
            if shouldStopDungeonMovementAtExit(at: stepPoint) {
                break
            }

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
                        updateDungeonExitLockIfNeeded(at: destination)
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
                        updateDungeonExitLockIfNeeded(at: boostedPoint)
                        if shouldStopDungeonMovementAtExit(at: boostedPoint) {
                            stepIndex = pathPoints.count
                            break
                        }

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
                                    updateDungeonExitLockIfNeeded(at: destination)
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
            if usesDungeonInventoryCards {
                consumeDungeonInventoryCard(cardMove)
            } else {
                // 使用済みカードは即座に破棄し、スタックから除去（残数がゼロになったらスタックごと取り除く）
                let removedIndex = handManager.consumeTopCard(at: validatedMove.stackIndex)

                // スロットの空きを埋めた上で並び順・先読みを整える
                rebuildHandAndNext(preferredInsertionIndices: removedIndex.map { [$0] } ?? [])
            }
        }

        collectDungeonCardPickups(along: actualTraversedPath)

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

        if applyDungeonPostMoveChecks(along: actualTraversedPath) { return }

        if !mode.usesTargetCollection, !mode.usesDungeonExit, board.isCleared {
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

private struct DungeonRefillRandomGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x4d595df4d0f33173 : seed
    }

    mutating func next() -> UInt64 {
        state = 6364136223846793005 &* state &+ 1442695040888963407
        return state
    }
}

    /// 塔ダンジョン用のカードなし基本移動を実行する
    public func playBasicOrthogonalMove(using basicMove: BasicOrthogonalMove) {
        guard progress == .playing, let currentPosition = current else { return }
        guard pendingDungeonPickupChoice == nil else { return }
        guard !isAwaitingManualDiscardSelection, !isAwaitingSupportSwapSelection else { return }
        guard mode.dungeonRules?.allowsBasicOrthogonalMove == true else { return }
        guard availableBasicOrthogonalMoves().contains(where: { candidate in
            candidate.moveVector == basicMove.moveVector &&
                candidate.path == basicMove.path &&
                candidate.destination == basicMove.destination
        }) else { return }

        boardTapBasicMoveRequest = nil
        debugLog(
            "基本移動 \(currentPosition) -> \(basicMove.destination) (vector=\(basicMove.moveVector))"
        )

        let pathPoints = basicMove.path
        var finalPosition = currentPosition
        var actualTraversedPath: [GridPoint] = []
        var encounteredRevisit = false
        var detectedEffects: [MovementResolution.AppliedEffect] = []
        var postMoveTileEffect: PostMoveTileEffect?
        var appliesTargetSwap = false
        var openGateTargets: [GridPoint] = []
        var ignoresPreserveCard = false

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

            updateDungeonExitLockIfNeeded(at: stepPoint)
            if shouldStopDungeonMovementAtExit(at: stepPoint) {
                break
            }

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
                        updateDungeonExitLockIfNeeded(at: destination)
                        stepIndex = pathPoints.count
                    }
                case .shuffleHand, .nextRefresh, .freeFocus, .preserveCard, .draft, .overload, .targetSwap, .openGate:
                    registerPostMoveTileEffect(
                        effect,
                        postMoveTileEffect: &postMoveTileEffect,
                        appliesTargetSwap: &appliesTargetSwap,
                        openGateTargets: &openGateTargets,
                        preservesPlayedCard: &ignoresPreserveCard
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
                        updateDungeonExitLockIfNeeded(at: boostedPoint)
                        if shouldStopDungeonMovementAtExit(at: boostedPoint) {
                            stepIndex = pathPoints.count
                        }
                    }
                }
            }

            stepIndex += 1
        }

        if actualTraversedPath.isEmpty {
            actualTraversedPath.append(finalPosition)
        }
        lastMovementResolution = MovementResolution(
            path: actualTraversedPath,
            finalPosition: finalPosition,
            appliedEffects: detectedEffects
        )
        current = finalPosition
        moveCount += 1

        if encounteredRevisit {
            hasRevisitedTile = true
            if mode.revisitPenaltyCost > 0 {
                penaltyCount += mode.revisitPenaltyCost
            }
        }

        collectDungeonCardPickups(along: actualTraversedPath)
        announceRemainingTiles()
        applyPostMoveTileEffect(postMoveTileEffect, preserving: nil)

        for target in openGateTargets {
            applyTileEffectOpenGate(target: target)
        }

        if appliesTargetSwap {
            applyTileEffectTargetSwap()
        }

        _ = applyDungeonPostMoveChecks(along: actualTraversedPath)
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
        guard !usesDungeonInventoryCards else { return }
        cancelManualDiscardSelection()
        resetBoardTapPlayRequestForPenalty()
        handManager.redrawNextPreview(using: &deck)
        refreshHandStateFromManager()
        debugLog("NEXT更新マス効果でNEXTのみ再配布")
    }

    func resetHandAndNextForTileRedraw(preserving preservedCard: DealtCard?) {
        guard !usesDungeonInventoryCards else { return }
        if let preservedCard {
            handManager.resetAll(prioritizing: [preservedCard], using: &deck)
            refreshHandStateFromManager()
        } else {
            handManager.clearAll()
            rebuildHandAndNext()
        }
    }

    private func applyTileEffectFreeFocus(preserving preservedCard: DealtCard?) {
        guard !usesDungeonInventoryCards else { return }
        let previousFocusCount = focusCount
        rebuildFocusedHandAndNext(preserving: preservedCard)
        focusCount = previousFocusCount
        debugLog("無料フォーカスマス効果で手札とNEXTを再配布")
    }

    private func applyTileEffectDraft() {
        guard !usesDungeonInventoryCards else { return }
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
        guard let move = card.moveCard else { return [] }
        let context = moveResolutionContext(
            on: activeBoard,
            targetPoint: mode.usesTargetCollection ? nearestActiveTarget(from: origin) : nil
        )
        return move.resolvePaths(from: origin, context: context)
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
            guard let moveCard = topCard.moveCard else { continue }

            // 固定ワープカードはカード自身が保持する目的地のみを候補として提示する
            if moveCard == .fixedWarp {
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

    /// 塔ダンジョンで使えるカードなしの上下左右 1 マス移動候補を列挙する
    public func availableBasicOrthogonalMoves(current currentOverride: GridPoint? = nil) -> [BasicOrthogonalMove] {
        guard mode.dungeonRules?.allowsBasicOrthogonalMove == true else { return [] }
        guard let origin = currentOverride ?? current else { return [] }

        let vectors = [
            MoveVector(dx: 0, dy: 1),
            MoveVector(dx: 1, dy: 0),
            MoveVector(dx: 0, dy: -1),
            MoveVector(dx: -1, dy: 0)
        ]

        var moves: [BasicOrthogonalMove] = []
        for vector in vectors {
            let destination = origin.offset(dx: vector.dx, dy: vector.dy)
            guard board.contains(destination), board.isTraversable(destination) else { continue }
            moves.append(
                BasicOrthogonalMove(
                    moveVector: vector,
                    resolution: MovementResolution(path: [destination], finalPosition: destination)
                )
            )
        }

        moves.sort { lhs, rhs in
            if lhs.destination.y != rhs.destination.y {
                return lhs.destination.y < rhs.destination.y
            }
            return lhs.destination.x < rhs.destination.x
        }
        return moves
    }

    /// 盤面タップ時に使用する移動候補を選び出す
    /// - Parameter point: ユーザーがタップした盤面座標
    /// - Returns: タップ地点へ届く代表 `ResolvedCardMove`（該当なしの場合は nil）
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

        // 複数スタックの競合は UI 側で警告するため、ここでは代表候補だけを返す
        return matchingMoves.first
    }

    /// 盤面タップ由来のアニメーション要求を UI 側で処理したあとに呼び出す
    /// - Parameter id: 消したいリクエストの識別子（不一致の場合は何もしない）
    public func clearBoardTapPlayRequest(_ id: UUID) {
        // リクエスト ID が一致している場合のみ nil へ戻して次のタップを受け付ける
        guard boardTapPlayRequest?.id == id else { return }
        boardTapPlayRequest = nil
    }

    /// 盤面タップ由来の基本移動要求を UI 側で処理したあとに呼び出す
    public func clearBoardTapBasicMoveRequest(_ id: UUID) {
        guard boardTapBasicMoveRequest?.id == id else { return }
        boardTapBasicMoveRequest = nil
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
        dungeonHP = mode.dungeonRules?.failureRule.initialHP ?? 0
        hazardDamageMitigationsRemaining = mode.dungeonMetadataSnapshot?.runState?.hazardDamageMitigationsRemaining ?? 0
        enemyStates = mode.dungeonRules?.enemies.map(EnemyState.init(definition:)) ?? []
        let currentFloorIndex = mode.dungeonMetadataSnapshot?.runState?.currentFloorIndex ?? 0
        crackedFloorPoints = mode.dungeonMetadataSnapshot?.runState?.crackedFloorPoints(for: currentFloorIndex) ?? []
        collapsedFloorPoints = mode.dungeonMetadataSnapshot?.runState?.collapsedFloorPoints(for: currentFloorIndex) ?? []
        for point in collapsedFloorPoints {
            board.collapseFloor(at: point)
        }
        dungeonInventoryEntries = mode.dungeonMetadataSnapshot?.runState?.rewardInventoryEntries ?? []
        collectedDungeonCardPickupIDs = []
        pendingDungeonPickupChoice = nil
        isDungeonExitUnlocked = mode.dungeonRules?.exitLock == nil
        dungeonExitUnlockEvent = nil
        dungeonFallEvent = nil
        dungeonEnemyTurnEvent = nil
        configureTargetsForNewSession()
        penaltyEvent = nil
        boardTapPlayRequest = nil
        boardTapBasicMoveRequest = nil
        spawnSelectionWarning = nil
        isAwaitingManualDiscardSelection = false
        isAwaitingSupportSwapSelection = false
        pendingSupportSwapStackID = nil
        lastMovementResolution = nil
        progress = mode.requiresSpawnSelection ? .awaitingSpawn : .playing

        if usesDungeonInventoryCards {
            syncDungeonInventoryHandStacks()
        } else {
            handManager.resetAll(using: &deck)
            refreshHandStateFromManager()
        }

        resetTimer()

        if !mode.requiresSpawnSelection {
            checkDeadlockAndApplyPenaltyIfNeeded()
            announceRemainingTiles()
        } else {
            debugLog("スポーン位置選択待ち: 盤面サイズ=\(mode.boardSize)")
        }

        let nextText = nextCards.isEmpty ? "なし" : nextCards.map { "\($0.displayName)" }.joined(separator: ", ")
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

    /// ダンジョンの所持カード一覧を既存の手札表示/移動候補へ反映する
    private func syncDungeonInventoryHandStacks() {
        guard usesDungeonInventoryCards else { return }
        let existingStacksByPlayable = Dictionary(
            uniqueKeysWithValues: handStacks.compactMap { stack -> (PlayableCard, HandStack)? in
                guard let playable = stack.representativePlayable else { return nil }
                return (playable, stack)
            }
        )
        let inventoryKindLimit = 9
        let liveEntries = Array(dungeonInventoryEntries.filter(\.hasUsesRemaining).prefix(inventoryKindLimit))
        dungeonInventoryEntries = liveEntries
        handStacks = liveEntries.map { entry in
            let existingStack = existingStacksByPlayable[entry.playable]
            var cards: [DealtCard]
            if entry.moveCard == .fixedWarp {
                let destination = mode.fixedWarpDestinationPool.first
                cards = (0..<entry.totalUses).map { _ in
                    DealtCard(move: entry.card, fixedWarpDestination: destination)
                }
            } else {
                cards = Array(existingStack?.cards.prefix(entry.totalUses) ?? [])
            }
            while cards.count < entry.totalUses {
                cards.append(DealtCard(playable: entry.playable))
            }
            return HandStack(id: existingStack?.id ?? UUID(), cards: cards)
        }
        nextCards = []
        handManager.clearAll()
    }

    private func addDungeonInventoryCard(_ card: MoveCard, pickupUses: Int = 0, rewardUses: Int = 0) -> Bool {
        addDungeonInventoryPlayable(.move(card), pickupUses: pickupUses, rewardUses: rewardUses)
    }

    private func addDungeonInventorySupportCard(_ support: SupportCard, pickupUses: Int = 0, rewardUses: Int = 0) -> Bool {
        addDungeonInventoryPlayable(.support(support), pickupUses: pickupUses, rewardUses: rewardUses)
    }

    private func addDungeonInventoryPlayable(_ playable: PlayableCard, pickupUses: Int = 0, rewardUses: Int = 0) -> Bool {
        guard usesDungeonInventoryCards else { return false }
        let normalizedPickupUses = max(pickupUses, 0)
        let normalizedRewardUses = max(rewardUses, 0)
        guard normalizedPickupUses + normalizedRewardUses > 0 else { return false }
        let inventoryKindLimit = 9

        if let index = dungeonInventoryEntries.firstIndex(where: { $0.playable == playable }) {
            dungeonInventoryEntries[index].pickupUses += normalizedPickupUses
            dungeonInventoryEntries[index].rewardUses += normalizedRewardUses
            syncDungeonInventoryHandStacks()
            return true
        }

        guard dungeonInventoryEntries.filter(\.hasUsesRemaining).count < inventoryKindLimit else { return false }
        dungeonInventoryEntries.append(
            DungeonInventoryEntry(
                playable: playable,
                rewardUses: normalizedRewardUses,
                pickupUses: normalizedPickupUses
            )
        )
        syncDungeonInventoryHandStacks()
        return true
    }

    private func consumeDungeonInventoryCard(_ card: MoveCard) {
        consumeDungeonInventoryPlayable(.move(card))
    }

    private func consumeDungeonInventorySupportCard(_ support: SupportCard) {
        consumeDungeonInventoryPlayable(.support(support))
    }

    private func consumeDungeonInventoryPlayable(_ playable: PlayableCard) {
        guard usesDungeonInventoryCards,
              let index = dungeonInventoryEntries.firstIndex(where: { $0.playable == playable })
        else { return }

        if dungeonInventoryEntries[index].pickupUses > 0 {
            dungeonInventoryEntries[index].pickupUses -= 1
        } else if dungeonInventoryEntries[index].rewardUses > 0 {
            dungeonInventoryEntries[index].rewardUses -= 1
        }
        syncDungeonInventoryHandStacks()
    }

    @discardableResult
    public func removeDungeonRewardInventoryCard(_ card: MoveCard) -> Bool {
        guard usesDungeonInventoryCards,
              let index = dungeonInventoryEntries.firstIndex(where: { $0.moveCard == card && $0.rewardUses > 0 })
        else { return false }

        dungeonInventoryEntries[index].rewardUses = 0
        syncDungeonInventoryHandStacks()
        return true
    }

    @discardableResult
    public func removeDungeonRewardInventorySupportCard(_ support: SupportCard) -> Bool {
        guard usesDungeonInventoryCards,
              let index = dungeonInventoryEntries.firstIndex(where: { $0.supportCard == support && $0.rewardUses > 0 })
        else { return false }

        dungeonInventoryEntries[index].rewardUses = 0
        syncDungeonInventoryHandStacks()
        return true
    }

    @discardableResult
    public func discardPendingDungeonPickupCard() -> Bool {
        guard usesDungeonInventoryCards,
              let choice = pendingDungeonPickupChoice
        else { return false }

        collectedDungeonCardPickupIDs.insert(choice.pickup.id)
        pendingDungeonPickupChoice = nil
        syncDungeonInventoryHandStacks()
        debugLog("満杯拾得カードを取得せず破棄: \(choice.pickup.card.displayName) @\(choice.pickup.point)")
        return true
    }

    @discardableResult
    public func replaceDungeonInventoryEntryForPendingPickup(discarding playable: PlayableCard) -> Bool {
        guard usesDungeonInventoryCards,
              let choice = pendingDungeonPickupChoice,
              choice.discardCandidates.contains(where: { $0.playable == playable }),
              dungeonInventoryEntries.contains(where: { $0.playable == playable && $0.hasUsesRemaining })
        else { return false }

        dungeonInventoryEntries.removeAll { $0.playable == playable }
        pendingDungeonPickupChoice = nil
        let didAdd = addDungeonInventoryCard(choice.pickup.card, pickupUses: choice.pickup.uses)
        guard didAdd else {
            syncDungeonInventoryHandStacks()
            return false
        }

        collectedDungeonCardPickupIDs.insert(choice.pickup.id)
        debugLog("満杯拾得カードを取得: \(choice.pickup.card.displayName), 破棄=\(playable.displayName)")
        return true
    }

    private func collectDungeonCardPickups(along traversedPath: [GridPoint]) {
        guard usesDungeonInventoryCards else { return }
        guard pendingDungeonPickupChoice == nil else { return }
        let visitedPoints = Set(traversedPath)
        for pickup in activeDungeonCardPickups where visitedPoints.contains(pickup.point) {
            if addDungeonInventoryCard(pickup.card, pickupUses: pickup.uses) {
                collectedDungeonCardPickupIDs.insert(pickup.id)
                debugLog("拾得カードを取得: \(pickup.card.displayName) 残り+\(pickup.uses) @\(pickup.point)")
            } else if beginPendingDungeonPickupChoiceIfNeeded(for: pickup) {
                break
            }
        }
        syncDungeonInventoryHandStacks()
    }

    private func beginPendingDungeonPickupChoiceIfNeeded(for pickup: DungeonCardPickupDefinition) -> Bool {
        let liveEntries = Array(dungeonInventoryEntries.filter(\.hasUsesRemaining).prefix(9))
        guard liveEntries.count >= 9,
              !liveEntries.contains(where: { $0.moveCard == pickup.card })
        else { return false }

        pendingDungeonPickupChoice = PendingDungeonPickupChoice(
            pickup: pickup,
            discardCandidates: liveEntries
        )
        isAwaitingManualDiscardSelection = false
        cancelSupportSwapSelection()
        boardTapPlayRequest = nil
        boardTapBasicMoveRequest = nil
        debugLog("満杯のため拾得カード選択待ち: \(pickup.card.displayName) @\(pickup.point)")
        return true
    }

    private func refillDungeonEmptySlotsWithRandomMoveCards() {
        guard usesDungeonInventoryCards else { return }
        let inventoryKindLimit = 9
        let occupiedCount = dungeonInventoryEntries.filter(\.hasUsesRemaining).count
        let emptySlotCount = max(0, inventoryKindLimit - occupiedCount)
        guard emptySlotCount > 0 else { return }

        let ownedMoves = Set(dungeonInventoryEntries.compactMap(\.moveCard))
        var candidates = dungeonRefillMoveCardPool().filter { !ownedMoves.contains($0) }
        guard !candidates.isEmpty else { return }

        var generator = DungeonRefillRandomGenerator(seed: dungeonRefillSeed())
        candidates.shuffle(using: &generator)
        for card in candidates.prefix(emptySlotCount) {
            _ = addDungeonInventoryCard(card, pickupUses: 1)
        }
    }

    private func dungeonRefillMoveCardPool() -> [MoveCard] {
        guard let metadata = mode.dungeonMetadataSnapshot,
              let runState = metadata.runState,
              let dungeon = DungeonLibrary.shared.dungeon(with: metadata.dungeonID),
              let floor = dungeon.resolvedFloor(at: runState.currentFloorIndex, runState: runState)
        else { return [] }
        return floor.rewardMoveCardsAfterClear
    }

    private func dungeonRefillSeed() -> UInt64 {
        var seed = mode.dungeonMetadataSnapshot?.runState?.cardVariationSeed ?? mode.deckSeed ?? 1
        let floorIndex = UInt64(mode.dungeonMetadataSnapshot?.runState?.currentFloorIndex ?? 0)
        seed ^= (floorIndex &+ 1) &* 0x9E37_79B9_7F4A_7C15
        seed ^= UInt64(max(moveCount, 0) + 1) &* 0xBF58_476D_1CE4_E5B9
        for entry in dungeonInventoryEntries.sorted(by: { $0.id < $1.id }) {
            for scalar in entry.id.unicodeScalars {
                seed = seed &* 1099511628211 &+ UInt64(scalar.value)
            }
            seed ^= UInt64(entry.totalUses &+ 31)
        }
        return seed == 0 ? 1 : seed
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
        2...4
    }

    private var brittleFloorPoints: Set<GridPoint> {
        var points: Set<GridPoint> = []
        for hazard in mode.dungeonRules?.hazards ?? [] {
            switch hazard {
            case .brittleFloor(let floorPoints):
                points.formUnion(floorPoints)
            case .damageTrap:
                break
            }
        }
        return points
    }

    public var damageTrapPoints: Set<GridPoint> {
        var points: Set<GridPoint> = []
        for hazard in mode.dungeonRules?.hazards ?? [] {
            switch hazard {
            case .damageTrap(let trapPoints, _):
                points.formUnion(trapPoints)
            case .brittleFloor:
                break
            }
        }
        return points
    }

    private func applyDungeonHazards(along traversedPoints: [GridPoint]) -> Bool {
        guard mode.usesDungeonExit else { return false }
        let brittlePoints = brittleFloorPoints

        for point in traversedPoints {
            if brittlePoints.contains(point) {
                if collapsedFloorPoints.contains(point) {
                    debugLog("崩落済みの床へ落下: \(point)")
                    return triggerDungeonFall(at: point)
                } else if crackedFloorPoints.contains(point) {
                    crackedFloorPoints.remove(point)
                    collapsedFloorPoints.insert(point)
                    board.collapseFloor(at: point)
                    debugLog("ひび割れ床が崩落: \(point)")
                    return triggerDungeonFall(at: point)
                } else {
                    crackedFloorPoints.insert(point)
                    debugLog("床にひび割れ: \(point)")
                }
            }

            for hazard in mode.dungeonRules?.hazards ?? [] {
                guard case .damageTrap(let trapPoints, let damage) = hazard,
                      trapPoints.contains(point)
                else { continue }
                let appliedDamage = max(damage, 1)
                if consumeDungeonHazardDamageMitigation() {
                    debugLog("罠ダメージを成長効果で無効化: \(point), 残り=\(hazardDamageMitigationsRemaining)")
                } else {
                    dungeonHP = max(dungeonHP - appliedDamage, 0)
                    debugLog("罠を踏みました: \(point), -\(appliedDamage), HP=\(dungeonHP)")
                }
            }
        }
        return false
    }

    private func consumeDungeonHazardDamageMitigation() -> Bool {
        guard mode.dungeonRules?.difficulty == .growth,
              hazardDamageMitigationsRemaining > 0
        else { return false }
        hazardDamageMitigationsRemaining -= 1
        return true
    }

    @discardableResult
    private func applyDungeonPostMoveChecks(along traversedPoints: [GridPoint]) -> Bool {
        guard mode.usesDungeonExit else { return false }
        if applyDungeonHazards(along: traversedPoints) {
            return true
        }
        updateDungeonExitLockIfNeeded()
        if current == mode.dungeonExitPoint, isDungeonExitUnlocked {
            finalizeElapsedTimeIfNeeded()
            progress = .cleared
            return true
        }
        let pendingMarkerDamagePoints = enemyWarningPoints
        let enemyStatesBeforeTurn = enemyStates
        advanceEnemiesForDungeonTurn()
        let hpBeforeEnemyDamage = dungeonHP
        let enemyDamage = applyDungeonEnemyDamageIfNeeded(markerDamagePoints: pendingMarkerDamagePoints)
        publishDungeonEnemyTurnEventIfNeeded(
            before: enemyStatesBeforeTurn,
            after: enemyStates,
            hpBefore: hpBeforeEnemyDamage,
            hpAfter: dungeonHP,
            damage: enemyDamage
        )
        if shouldFailDungeonRun() {
            finalizeElapsedTimeIfNeeded()
            progress = .failed
            return true
        }
        return false
    }

    @discardableResult
    private func triggerDungeonFall(at point: GridPoint) -> Bool {
        if consumeDungeonHazardDamageMitigation() {
            debugLog("床崩落ダメージを成長効果で無効化: \(point), HP=\(dungeonHP), 残り=\(hazardDamageMitigationsRemaining)")
        } else {
            dungeonHP = max(dungeonHP - 1, 0)
            debugLog("床崩落で下階へ落下: \(point), HP=\(dungeonHP)")
        }
        if dungeonHP <= 0 {
            finalizeElapsedTimeIfNeeded()
            progress = .failed
            return true
        }

        let sourceFloorIndex = mode.dungeonMetadataSnapshot?.runState?.currentFloorIndex ?? 0
        dungeonFallEvent = DungeonFallEvent(
            point: point,
            sourceFloorIndex: sourceFloorIndex,
            destinationFloorIndex: sourceFloorIndex + 1,
            hpAfterDamage: dungeonHP
        )
        return true
    }

    public func clearDungeonFallEvent(_ id: UUID) {
        guard dungeonFallEvent?.id == id else { return }
        dungeonFallEvent = nil
    }

    public func resolvePendingDungeonFallLandingIfNeeded() {
        guard mode.usesDungeonExit,
              let landingPoint = mode.dungeonMetadataSnapshot?.runState?.pendingFallLandingPoint,
              current == landingPoint,
              progress == .playing
        else { return }

        debugLog("落下着地処理を開始: \(landingPoint)")
        collectDungeonCardPickups(along: [landingPoint])
        _ = applyDungeonPostMoveChecks(along: [landingPoint])
    }

    private func updateDungeonExitLockIfNeeded(at point: GridPoint? = nil) {
        guard mode.usesDungeonExit,
              !isDungeonExitUnlocked,
              let exitLock = mode.dungeonRules?.exitLock,
              (point ?? current) == exitLock.unlockPoint
        else { return }

        isDungeonExitUnlocked = true
        if let exitPoint = mode.dungeonExitPoint {
            dungeonExitUnlockEvent = DungeonExitUnlockEvent(
                exitPoint: exitPoint,
                unlockPoint: exitLock.unlockPoint
            )
        }
        debugLog("ダンジョン出口を解錠: key=\(exitLock.unlockPoint)")
    }

    private func shouldStopDungeonMovementAtExit(at point: GridPoint) -> Bool {
        guard mode.usesDungeonExit,
              isDungeonExitUnlocked,
              point == mode.dungeonExitPoint
        else { return false }
        return true
    }

    private func advanceEnemiesForDungeonTurn() {
        guard mode.usesDungeonExit, !enemyStates.isEmpty else { return }

        for index in enemyStates.indices {
            switch enemyStates[index].behavior {
            case .guardPost, .watcher:
                break
            case .patrol(let path):
                let validPath = path.filter { board.contains($0) && board.isTraversable($0) }
                guard !validPath.isEmpty else { continue }
                let nextIndex = (enemyStates[index].patrolIndex + 1) % validPath.count
                enemyStates[index].patrolIndex = nextIndex
                enemyStates[index].position = validPath[nextIndex]
            case .rotatingWatcher(let directions, _):
                let validDirections = normalizedDirections(directions)
                guard !validDirections.isEmpty else { continue }
                enemyStates[index].rotationIndex = (enemyStates[index].rotationIndex + 1) % validDirections.count
            case .chaser:
                guard let current,
                      let nextPoint = chaserNextStep(from: enemyStates[index].position, toward: current)
                else {
                    continue
                }
                enemyStates[index].position = nextPoint
            case .marker(let directions, _):
                let validDirections = normalizedDirections(directions)
                guard !validDirections.isEmpty else { continue }
                enemyStates[index].rotationIndex = (enemyStates[index].rotationIndex + 1) % validDirections.count
            }
        }
    }

    private func patrolMovementPreview(for enemy: EnemyState) -> EnemyPatrolMovementPreview? {
        guard case .patrol(let path) = enemy.behavior else { return nil }
        let validPath = path.filter { board.contains($0) && board.isTraversable($0) }
        guard !validPath.isEmpty else { return nil }

        let nextIndex = (enemy.patrolIndex + 1) % validPath.count
        let nextPoint = validPath[nextIndex]
        guard nextPoint != enemy.position else { return nil }

        let vector = MoveVector(
            dx: nextPoint.x - enemy.position.x,
            dy: nextPoint.y - enemy.position.y
        )
        return EnemyPatrolMovementPreview(
            enemyID: enemy.id,
            current: enemy.position,
            next: nextPoint,
            vector: vector
        )
    }

    private func chaserMovementPreview(for enemy: EnemyState) -> EnemyPatrolMovementPreview? {
        guard case .chaser = enemy.behavior,
              let current,
              let nextPoint = chaserNextStep(from: enemy.position, toward: current),
              nextPoint != enemy.position
        else {
            return nil
        }

        let vector = MoveVector(
            dx: nextPoint.x - enemy.position.x,
            dy: nextPoint.y - enemy.position.y
        )
        return EnemyPatrolMovementPreview(
            enemyID: enemy.id,
            current: enemy.position,
            next: nextPoint,
            vector: vector
        )
    }

    private func rotatingWatcherDirectionPreview(
        for enemy: EnemyState
    ) -> EnemyRotatingWatcherDirectionPreview? {
        guard case .rotatingWatcher(let directions, _) = enemy.behavior else { return nil }
        let validDirections = normalizedDirections(directions)
        guard !validDirections.isEmpty else { return nil }
        let nextIndex = (enemy.rotationIndex + 1) % validDirections.count
        return EnemyRotatingWatcherDirectionPreview(
            enemyID: enemy.id,
            current: enemy.position,
            vector: validDirections[nextIndex]
        )
    }

    @discardableResult
    private func applyDungeonEnemyDamageIfNeeded(markerDamagePoints: Set<GridPoint>) -> Int {
        guard mode.usesDungeonExit, let current else { return 0 }
        var totalDamage = 0

        for enemy in enemyStates {
            if enemy.position == current || dangerPoints(for: [enemy]).contains(current) {
                totalDamage += enemy.damage
            } else if case .marker = enemy.behavior, markerDamagePoints.contains(current) {
                totalDamage += enemy.damage
            }
        }

        guard totalDamage > 0 else { return 0 }
        dungeonHP = max(dungeonHP - totalDamage, 0)
        debugLog("敵の攻撃を受けました: -\(totalDamage), HP=\(dungeonHP)")
        return totalDamage
    }

    private func publishDungeonEnemyTurnEventIfNeeded(
        before: [EnemyState],
        after: [EnemyState],
        hpBefore: Int,
        hpAfter: Int,
        damage: Int
    ) {
        guard mode.usesDungeonExit, (!before.isEmpty || !after.isEmpty) else { return }

        let beforeByID = Dictionary(before.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let transitions = after.compactMap { afterEnemy -> DungeonEnemyTurnTransition? in
            guard let beforeEnemy = beforeByID[afterEnemy.id] else { return nil }
            return DungeonEnemyTurnTransition(
                enemyID: afterEnemy.id,
                name: afterEnemy.name,
                before: beforeEnemy,
                after: afterEnemy
            )
        }

        guard !transitions.isEmpty || damage > 0 else { return }
        dungeonEnemyTurnEvent = DungeonEnemyTurnEvent(
            transitions: transitions,
            attackedPlayer: damage > 0,
            hpBefore: hpBefore,
            hpAfter: hpAfter
        )
    }

    private func shouldFailDungeonRun() -> Bool {
        guard mode.usesDungeonExit else { return false }
        if dungeonHP <= 0 { return true }
        if let remainingDungeonTurns, remainingDungeonTurns <= 0 {
            return true
        }
        return false
    }

    private func dangerPoints(for enemies: [EnemyState]) -> Set<GridPoint> {
        var danger: Set<GridPoint> = []
        for enemy in enemies {
            danger.insert(enemy.position)
            switch enemy.behavior {
            case .guardPost, .patrol, .chaser:
                let offsets = [
                    MoveVector(dx: 0, dy: 1),
                    MoveVector(dx: 1, dy: 0),
                    MoveVector(dx: 0, dy: -1),
                    MoveVector(dx: -1, dy: 0)
                ]
                for offset in offsets {
                    let point = enemy.position.offset(dx: offset.dx, dy: offset.dy)
                    if board.contains(point), board.isTraversable(point) {
                        danger.insert(point)
                    }
                }
            case .watcher(let direction, let range):
                insertWatcherDanger(
                    from: enemy.position,
                    direction: direction,
                    range: range,
                    into: &danger
                )
            case .rotatingWatcher(let directions, let range):
                let validDirections = normalizedDirections(directions)
                guard !validDirections.isEmpty else { break }
                let direction = validDirections[enemy.rotationIndex % validDirections.count]
                insertWatcherDanger(
                    from: enemy.position,
                    direction: direction,
                    range: range,
                    into: &danger
                )
            case .marker:
                break
            }
        }
        return danger
    }

    private func markerWarningPoints(for enemies: [EnemyState]) -> Set<GridPoint> {
        var warning: Set<GridPoint> = []
        for enemy in enemies {
            guard case .marker(let directions, let range) = enemy.behavior else { continue }
            let validDirections = normalizedDirections(directions)
            guard !validDirections.isEmpty else { continue }
            let direction = validDirections[enemy.rotationIndex % validDirections.count]
            insertWatcherDanger(
                from: enemy.position,
                direction: direction,
                range: range,
                into: &warning
            )
        }
        return warning
    }

    private func chaserNextStep(from origin: GridPoint, toward target: GridPoint) -> GridPoint? {
        guard origin != target,
              board.contains(origin),
              board.contains(target),
              board.isTraversable(target)
        else {
            return nil
        }

        var distances: [GridPoint: Int] = [target: 0]
        var queue: [GridPoint] = [target]
        var cursor = 0
        let directions = [
            MoveVector(dx: 1, dy: 0),
            MoveVector(dx: -1, dy: 0),
            MoveVector(dx: 0, dy: 1),
            MoveVector(dx: 0, dy: -1)
        ]

        while cursor < queue.count {
            let point = queue[cursor]
            cursor += 1
            let distance = distances[point] ?? 0

            for direction in directions {
                let next = point.offset(dx: direction.dx, dy: direction.dy)
                guard board.contains(next),
                      board.isTraversable(next),
                      distances[next] == nil
                else {
                    continue
                }
                distances[next] = distance + 1
                queue.append(next)
            }
        }

        guard let originDistance = distances[origin] else { return nil }
        for direction in chaserStepDirections(from: origin, toward: target) {
            let candidate = origin.offset(dx: direction.dx, dy: direction.dy)
            guard let distance = distances[candidate],
                  distance < originDistance
            else {
                continue
            }
            return candidate
        }

        return nil
    }

    private func chaserStepDirections(from origin: GridPoint, toward target: GridPoint) -> [MoveVector] {
        var directions: [MoveVector] = []

        if target.x > origin.x {
            directions.append(MoveVector(dx: 1, dy: 0))
        } else if target.x < origin.x {
            directions.append(MoveVector(dx: -1, dy: 0))
        }

        if target.y > origin.y {
            directions.append(MoveVector(dx: 0, dy: 1))
        } else if target.y < origin.y {
            directions.append(MoveVector(dx: 0, dy: -1))
        }

        let fallbackDirections = [
            MoveVector(dx: 1, dy: 0),
            MoveVector(dx: -1, dy: 0),
            MoveVector(dx: 0, dy: 1),
            MoveVector(dx: 0, dy: -1)
        ]
        for direction in fallbackDirections where !directions.contains(direction) {
            directions.append(direction)
        }

        return directions
    }

    private func normalizedDirections(_ directions: [MoveVector]) -> [MoveVector] {
        directions.compactMap { direction in
            let dx = direction.dx == 0 ? 0 : (direction.dx > 0 ? 1 : -1)
            let dy = direction.dy == 0 ? 0 : (direction.dy > 0 ? 1 : -1)
            guard dx != 0 || dy != 0 else { return nil }
            return MoveVector(dx: dx, dy: dy)
        }
    }

    private func insertWatcherDanger(
        from origin: GridPoint,
        direction: MoveVector,
        range: Int,
        into danger: inout Set<GridPoint>
    ) {
        let dx = direction.dx == 0 ? 0 : (direction.dx > 0 ? 1 : -1)
        let dy = direction.dy == 0 ? 0 : (direction.dy > 0 ? 1 : -1)
        guard dx != 0 || dy != 0 else { return }
        for step in 1...max(range, 1) {
            let point = origin.offset(dx: dx * step, dy: dy * step)
            guard board.contains(point), board.isTraversable(point) else { break }
            danger.insert(point)
        }
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
            return lhs.displayName < rhs.displayName
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

        guard let move = card.moveCard else {
            return (Int.min, Int.max)
        }

        if move == .fixedWarp, let destination = card.fixedWarpDestination {
            guard destination != origin,
                  activeBoard.contains(destination),
                  activeBoard.isTraversable(destination) else {
                return (Int.min, Int.max)
            }
            let distance = manhattanDistance(from: destination, to: target)
            return (currentDistance - distance, distance)
        }

        let context = moveResolutionContext(on: activeBoard, targetPoint: target)
        let destinations = move.resolvePaths(from: origin, context: context).compactMap(\.traversedPoints.last)
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
              let moveCard = move.card.moveCard,
              shouldExpandForSlowTileResolution(moveCard),
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
        guard pendingDungeonPickupChoice == nil else { return }

        // デバッグログ: タップされたマスを表示
        debugLog("マス \(point) をタップ")

        // 基本移動で届くマスはカードより先に扱い、カード消費なしの移動を優先する
        if let basicMove = availableBasicOrthogonalMoves().first(where: { $0.destination == point }) {
            boardTapBasicMoveRequest = BoardTapBasicMoveRequest(move: basicMove)
            return
        }

        // 基本移動で届かないマスだけ、カード候補を算出する
        if let resolved = resolvedMoveForBoardTap(at: point) {
            boardTapPlayRequest = BoardTapPlayRequest(
                stackID: resolved.stackID,
                stackIndex: resolved.stackIndex,
                topCard: resolved.card,
                moveVector: resolved.moveVector,
                resolution: resolved.resolution
            )
            return
        }
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
        boardTapBasicMoveRequest = nil
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
        mode: GameMode = .dungeonPlaceholder,
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
        core.dungeonHP = mode.dungeonRules?.failureRule.initialHP ?? 0
        core.hazardDamageMitigationsRemaining = mode.dungeonMetadataSnapshot?.runState?.hazardDamageMitigationsRemaining ?? 0
        core.enemyStates = mode.dungeonRules?.enemies.map(EnemyState.init(definition:)) ?? []
        let currentFloorIndex = mode.dungeonMetadataSnapshot?.runState?.currentFloorIndex ?? 0
        core.crackedFloorPoints = mode.dungeonMetadataSnapshot?.runState?.crackedFloorPoints(for: currentFloorIndex) ?? []
        core.collapsedFloorPoints = mode.dungeonMetadataSnapshot?.runState?.collapsedFloorPoints(for: currentFloorIndex) ?? []
        for point in core.collapsedFloorPoints {
            core.board.collapseFloor(at: point)
        }
        core.isDungeonExitUnlocked = mode.dungeonRules?.exitLock == nil
        core.dungeonExitUnlockEvent = nil
        core.dungeonFallEvent = nil
        core.dungeonEnemyTurnEvent = nil
        core.configureTargetsForNewSession()
        core.progress = (resolvedCurrent == nil && mode.requiresSpawnSelection) ? .awaitingSpawn : .playing

        if core.usesDungeonInventoryCards {
            core.dungeonInventoryEntries = mode.dungeonMetadataSnapshot?.runState?.rewardInventoryEntries ?? []
            core.collectedDungeonCardPickupIDs = []
            core.pendingDungeonPickupChoice = nil
            core.syncDungeonInventoryHandStacks()
        } else {
            core.handManager.resetAll(using: &core.deck)
            core.refreshHandStateFromManager()
        }

        if core.progress == .playing {
            core.checkDeadlockAndApplyPenaltyIfNeeded()
        }
        core.resetTimer()
        core.isAwaitingManualDiscardSelection = false
        core.isAwaitingSupportSwapSelection = false
        core.pendingSupportSwapStackID = nil
        core.boardTapBasicMoveRequest = nil
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

    /// テスト用にダンジョン床状態を直接差し替える
    func overrideDungeonFloorStateForTesting(
        cracked: Set<GridPoint>,
        collapsed: Set<GridPoint>
    ) {
        crackedFloorPoints = cracked
        collapsedFloorPoints = collapsed
        for point in collapsed {
            board.collapseFloor(at: point)
        }
    }

    @discardableResult
    func addDungeonInventoryCardForTesting(
        _ card: MoveCard,
        pickupUses: Int = 0,
        rewardUses: Int = 0
    ) -> Bool {
        addDungeonInventoryCard(card, pickupUses: pickupUses, rewardUses: rewardUses)
    }

    /// テスト用にダンジョン HP を直接差し替える
    func overrideDungeonHPForTesting(_ hp: Int) {
        dungeonHP = max(hp, 0)
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
