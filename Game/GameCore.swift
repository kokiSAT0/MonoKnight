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

/// 巡回兵の巡回範囲を UI へ渡すためのレール情報
public struct EnemyPatrolRailPreview: Identifiable, Equatable {
    public let enemyID: String
    public let path: [GridPoint]

    public var id: String { enemyID }

    public init(enemyID: String, path: [GridPoint]) {
        self.enemyID = enemyID
        self.path = path
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
    case discardRandomHand
    case discardAllMoveCards
    case discardAllSupportCards
    case discardAllHands
}

private let poisonTrapDamageTicks = 3
private let poisonTrapActionsPerDamage = 3

private struct MovementProcessingResult {
    var finalPosition: GridPoint
    var actualTraversedPath: [GridPoint]
    var encounteredRevisit: Bool
    var detectedEffects: [MovementResolution.AppliedEffect]
    var presentationInitialHP: Int
    var presentationInitialHandStacks: [HandStack]
    var presentationInitialCollectedDungeonCardPickupIDs: Set<String>
    var presentationInitialCollectedDungeonRelicPickupIDs: Set<String>
    var presentationInitialEnemyStates: [EnemyState]
    var presentationInitialCrackedFloorPoints: Set<GridPoint>
    var presentationInitialCollapsedFloorPoints: Set<GridPoint>
    var presentationInitialBoard: Board
    var presentationSteps: [MovementResolution.PresentationStep]
    var postMoveTileEffect: PostMoveTileEffect?
    var preservesPlayedCard: Bool
    var paralysisTrapPoint: GridPoint?
    var triggeredPoisonTrap: Bool
}

public struct PendingTargetedSupportCard: Equatable {
    public let stackID: UUID
    public let cardID: UUID
    public let support: SupportCard

    public init(stackID: UUID, cardID: UUID, support: SupportCard) {
        self.stackID = stackID
        self.cardID = cardID
        self.support = support
    }
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
    /// 塔ダンジョンで利用する現在 HP
    @Published public private(set) var dungeonHP: Int = 0
    /// 成長塔の区間内で罠/床崩落ダメージを無効化できる残り回数
    @Published public private(set) var hazardDamageMitigationsRemaining: Int = 0
    /// 成長塔の区間内で敵ダメージを無効化できる残り回数
    @Published public private(set) var enemyDamageMitigationsRemaining: Int = 0
    /// 成長塔の区間内でメテオ着弾ダメージを無効化できる残り回数
    @Published public private(set) var markerDamageMitigationsRemaining: Int = 0
    /// 凍結の呪文で敵ターンを無効化できる残り回数
    @Published public private(set) var enemyFreezeTurnsRemaining: Int = 0
    /// 障壁の呪文で HP ダメージを無効化できる残り回数
    @Published public private(set) var damageBarrierTurnsRemaining: Int = 0
    /// 足枷罠を踏み、その階の間だけ全行動が重くなっているかどうか
    @Published public private(set) var isShackled: Bool = false
    /// 毒状態で残っているダメージ回数
    @Published public private(set) var poisonDamageTicksRemaining: Int = 0
    /// 次の毒ダメージまでに必要な成功行動数
    @Published public private(set) var poisonActionsUntilNextDamage: Int = 0
    /// 塔ダンジョンで利用する敵状態
    @Published public private(set) var enemyStates: [EnemyState] = []
    /// ひび割れ状態の床
    @Published public private(set) var crackedFloorPoints: Set<GridPoint> = []
    /// 崩落して通行不能になった床
    @Published public private(set) var collapsedFloorPoints: Set<GridPoint> = []
    /// すでに回復効果を使い切った回復マス
    @Published public private(set) var consumedHealingTilePoints: Set<GridPoint> = []
    /// 塔ダンジョンの所持カード一覧
    @Published public private(set) var dungeonInventoryEntries: [DungeonInventoryEntry] = []
    /// 取得済みのフロア内カード ID
    @Published public private(set) var collectedDungeonCardPickupIDs: Set<String> = []
    /// 塔ラン中だけ有効な遺物一覧
    @Published public private(set) var dungeonRelicEntries: [DungeonRelicEntry] = []
    /// 塔ラン中だけ有効な呪い遺物一覧
    @Published public private(set) var dungeonCurseEntries: [DungeonCurseEntry] = []
    /// 取得済みの宝箱 ID
    @Published public private(set) var collectedDungeonRelicPickupIDs: Set<String> = []
    /// UI へ提示するレリック/呪い遺物/宝箱結果の取得イベント
    @Published public private(set) var dungeonRelicAcquisitionPresentations: [DungeonRelicAcquisitionPresentation] = []
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
    /// 対象選択型の補助カードが敵選択待ちかどうか
    @Published public private(set) var pendingTargetedSupportCard: PendingTargetedSupportCard?
    /// 合計手数（移動 + ペナルティ）の計算プロパティ
    /// - Note: 将来的に別レギュレーションで利用する可能性があるため個別に保持
    public var totalMoveCount: Int { moveCount + penaltyCount }

    /// ポイント計算結果（小さいほど良い）
    public var score: Int {
        return totalMoveCount * 10 + elapsedSeconds
    }
    /// プレイ中の経過秒数をリアルタイムで取得する計算プロパティ
    /// - Note: クリア済みかどうかに応じて `GameSessionTimer` へ計算を委譲する。
    public var liveElapsedSeconds: Int {
        sessionTimer.liveElapsedSeconds()
    }
    /// 未踏破マスの残り数を UI へ公開する計算プロパティ

    public var remainingTiles: Int {
        board.remainingCount
    }
    /// 塔ダンジョンの残り手数
    public var remainingDungeonTurns: Int? {
        guard let turnLimit = effectiveDungeonTurnLimit else { return nil }
        return max(turnLimit - moveCount, 0)
    }
    /// 遺物補正を反映した現在フロアの手数上限
    public var effectiveDungeonTurnLimit: Int? {
        guard let baseTurnLimit = mode.dungeonRules?.failureRule.turnLimit else { return nil }
        var adjustment = 0
        if hasDungeonRelic(.chippedHourglass) {
            adjustment += 3
        }
        if hasDungeonRelic(.travelerBoots) {
            adjustment += 1
        }
        if hasDungeonCurse(.rustyChain) {
            adjustment -= 2
        }
        if hasDungeonCurse(.cursedCrown) {
            adjustment -= 4
        }
        if hasDungeonCurse(.warpedHourglass) {
            adjustment += 6
        }
        if hasDungeonCurse(.crackedCompass) {
            adjustment -= 3
        }
        return max(baseTurnLimit + adjustment, 1)
    }
    /// 敵本体を除く、盤面へ表示する攻撃範囲マス
    public var enemyDangerPoints: Set<GridPoint> {
        enemyDangerPoints(forDisplayedEnemyStates: enemyStates)
    }
    /// メテオ兵が次の敵ターンに攻撃する着弾予告マス
    public var enemyWarningPoints: Set<GridPoint> {
        enemyWarningPoints(forDisplayedEnemyStates: enemyStates)
    }
    /// 表示中の敵状態を基準にした攻撃範囲マス
    public func enemyDangerPoints(forDisplayedEnemyStates enemyStates: [EnemyState]) -> Set<GridPoint> {
        guard !isEnemyFreezeActive else { return [] }
        return dangerPoints(for: enemyStates)
    }
    /// 表示中の敵状態を基準にしたメテオ兵の着弾予告マス
    public func enemyWarningPoints(forDisplayedEnemyStates enemyStates: [EnemyState]) -> Set<GridPoint> {
        guard !isEnemyFreezeActive else { return [] }
        return markerWarningPoints(for: enemyStates)
    }
    /// 巡回兵ごとの次移動方向
    public var enemyPatrolMovementPreviews: [EnemyPatrolMovementPreview] {
        enemyPatrolMovementPreviews(forDisplayedEnemyStates: enemyStates)
    }
    /// 表示中の敵状態を基準にした巡回兵ごとの次移動方向
    public func enemyPatrolMovementPreviews(forDisplayedEnemyStates enemyStates: [EnemyState]) -> [EnemyPatrolMovementPreview] {
        guard !isEnemyFreezeActive else { return [] }
        return orderedEnemyMovementPreviews(in: enemyStates) { enemy in
            if case .patrol = enemy.behavior { return true }
            return false
        }
    }
    /// 巡回兵ごとの巡回範囲レール
    public var enemyPatrolRailPreviews: [EnemyPatrolRailPreview] {
        enemyPatrolRailPreviews(forDisplayedEnemyStates: enemyStates)
    }
    /// 表示中の敵状態を基準にした巡回兵ごとの巡回範囲レール
    public func enemyPatrolRailPreviews(forDisplayedEnemyStates enemyStates: [EnemyState]) -> [EnemyPatrolRailPreview] {
        enemyStates.compactMap { patrolRailPreview(for: $0) }
    }
    /// 追跡兵ごとの次移動方向
    public var enemyChaserMovementPreviews: [EnemyPatrolMovementPreview] {
        enemyChaserMovementPreviews(forDisplayedEnemyStates: enemyStates)
    }
    /// 表示中の敵状態を基準にした追跡兵ごとの次移動方向
    public func enemyChaserMovementPreviews(forDisplayedEnemyStates enemyStates: [EnemyState]) -> [EnemyPatrolMovementPreview] {
        guard !isEnemyFreezeActive else { return [] }
        return orderedEnemyMovementPreviews(in: enemyStates) { enemy in
            if case .chaser = enemy.behavior { return true }
            return false
        }
    }
    /// 敵が凍結状態かどうか
    public var isEnemyFreezeActive: Bool {
        enemyFreezeTurnsRemaining > 0
    }
    /// 障壁の呪文で HP ダメージを受けない状態かどうか
    public var isDamageBarrierActive: Bool {
        damageBarrierTurnsRemaining > 0
    }
    /// 現在の行動で消費する手数。足枷状態では全行動が 2 手分になる
    private var currentActionMoveCost: Int {
        isShackled ? 2 : 1
    }
    /// まだ盤面上に残っている拾得カード
    public var activeDungeonCardPickups: [DungeonCardPickupDefinition] {
        guard mode.dungeonRules?.cardAcquisitionMode == .inventoryOnly,
              let cardPickups = mode.dungeonRules?.cardPickups
        else { return [] }
        return cardPickups.filter { !collectedDungeonCardPickupIDs.contains($0.id) }
    }
    /// まだ盤面上に残っている宝箱
    public var activeDungeonRelicPickups: [DungeonRelicPickupDefinition] {
        guard mode.dungeonRules?.difficulty == .growth,
              let relicPickups = mode.dungeonRules?.relicPickups
        else { return [] }
        return relicPickups.filter { !collectedDungeonRelicPickupIDs.contains($0.id) }
    }
    public var isAwaitingDungeonPickupChoice: Bool {
        pendingDungeonPickupChoice != nil
    }
    public var targetedSupportCardTargetPoints: Set<GridPoint> {
        guard pendingTargetedSupportCard?.support == .singleAnnihilationSpell else { return [] }
        return Set(enemyStates.map(\.position))
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
    /// 初期化時にモードを指定して各種状態を構築する
    /// - Parameter mode: 適用したいゲームモード（省略時は塔プレースホルダー）
    public init(mode: GameMode = .dungeonPlaceholder) {
        self.mode = mode
        // BoardGeometry を介することで盤面サイズ拡張時も初期化処理を共通化できる
        board = Board(
            size: mode.boardSize,
            initialVisitedPoints: mode.initialVisitedPoints,
            impassablePoints: mode.impassableTilePoints,
            tileEffects: mode.tileEffects
        )
        current = mode.initialSpawnPoint ?? BoardGeometry.defaultSpawnPoint(for: mode.boardSize)
        // モードに紐付くシードが指定されている場合はそれを利用し、日替わりチャレンジなどの再現性を確保する
        deck = Deck(
            seed: mode.deckSeed,
            configuration: mode.deckConfiguration
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
            enemyDamageMitigationsRemaining: enemyDamageMitigationsRemaining,
            markerDamageMitigationsRemaining: markerDamageMitigationsRemaining,
            enemyFreezeTurnsRemaining: enemyFreezeTurnsRemaining,
            damageBarrierTurnsRemaining: damageBarrierTurnsRemaining,
            isShackled: isShackled,
            poisonDamageTicksRemaining: poisonDamageTicksRemaining,
            poisonActionsUntilNextDamage: poisonActionsUntilNextDamage,
            enemyStates: enemyStates,
            crackedFloorPoints: crackedFloorPoints,
            collapsedFloorPoints: collapsedFloorPoints,
            consumedHealingTilePoints: consumedHealingTilePoints,
            dungeonInventoryEntries: dungeonInventoryEntries,
            collectedDungeonCardPickupIDs: collectedDungeonCardPickupIDs,
            dungeonRelicEntries: dungeonRelicEntries,
            dungeonCurseEntries: dungeonCurseEntries,
            collectedDungeonRelicPickupIDs: collectedDungeonRelicPickupIDs,
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
        let validConsumedHealingPoints = snapshot.consumedHealingTilePoints.filter { $0.isInside(boardSize: mode.boardSize) }
        guard validVisitedPoints.count == snapshot.visitedPoints.count,
              validCollapsedPoints.count == snapshot.collapsedFloorPoints.count,
              validConsumedHealingPoints.count == snapshot.consumedHealingTilePoints.count
        else { return false }

        board = Board(
            size: mode.boardSize,
            initialVisitedPoints: Array(validVisitedPoints),
            impassablePoints: mode.impassableTilePoints,
            tileEffects: mode.tileEffects
        )
        guard board.isTraversable(snapshot.currentPoint) else { return false }

        current = snapshot.currentPoint
        moveCount = snapshot.moveCount
        penaltyCount = 0
        hasRevisitedTile = false
        dungeonHP = snapshot.dungeonHP
        hazardDamageMitigationsRemaining = snapshot.hazardDamageMitigationsRemaining
        enemyDamageMitigationsRemaining = snapshot.enemyDamageMitigationsRemaining
        markerDamageMitigationsRemaining = snapshot.markerDamageMitigationsRemaining
        enemyFreezeTurnsRemaining = snapshot.enemyFreezeTurnsRemaining
        damageBarrierTurnsRemaining = snapshot.damageBarrierTurnsRemaining
        isShackled = snapshot.isShackled
        poisonDamageTicksRemaining = snapshot.poisonDamageTicksRemaining
        poisonActionsUntilNextDamage = snapshot.poisonActionsUntilNextDamage
        enemyStates = snapshot.enemyStates
        crackedFloorPoints = snapshot.crackedFloorPoints
        collapsedFloorPoints = validCollapsedPoints
        consumedHealingTilePoints = validConsumedHealingPoints
        dungeonInventoryEntries = snapshot.dungeonInventoryEntries
        collectedDungeonCardPickupIDs = snapshot.collectedDungeonCardPickupIDs
        dungeonRelicEntries = snapshot.dungeonRelicEntries
        dungeonCurseEntries = snapshot.dungeonCurseEntries
        collectedDungeonRelicPickupIDs = snapshot.collectedDungeonRelicPickupIDs
        dungeonRelicAcquisitionPresentations = []
        pendingDungeonPickupChoice = snapshot.pendingDungeonPickupChoice
        isDungeonExitUnlocked = snapshot.isDungeonExitUnlocked
        dungeonExitUnlockEvent = nil
        dungeonFallEvent = nil
        penaltyEvent = nil
        boardTapPlayRequest = nil
        boardTapBasicMoveRequest = nil
        isAwaitingManualDiscardSelection = false
        pendingTargetedSupportCard = nil
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
        guard progress == .playing, let support = stack.topCard?.supportCard else { return false }
        switch support {
        case .refillEmptySlots:
            return true
        case .singleAnnihilationSpell, .annihilationSpell, .freezeSpell:
            return !enemyStates.isEmpty
        case .barrierSpell:
            return true
        case .antidote:
            return poisonDamageTicksRemaining > 0
        case .panacea:
            return poisonDamageTicksRemaining > 0 || isShackled
        }
    }

    public func beginTargetedSupportCardSelection(at index: Int) -> Bool {
        guard progress == .playing, handStacks.indices.contains(index), current != nil else { return false }
        guard pendingDungeonPickupChoice == nil else { return false }
        guard !isAwaitingManualDiscardSelection else { return false }
        guard let card = handStacks[index].topCard,
              let support = card.supportCard,
              support.requiresEnemyTargetSelection
        else { return false }
        guard isSupportCardUsable(in: handStacks[index]) else { return false }

        pendingTargetedSupportCard = PendingTargetedSupportCard(
            stackID: handStacks[index].id,
            cardID: card.id,
            support: support
        )
        boardTapPlayRequest = nil
        boardTapBasicMoveRequest = nil
        return true
    }

    public func cancelTargetedSupportCardSelection() {
        pendingTargetedSupportCard = nil
    }

    @discardableResult
    public func playTargetedSupportCard(at point: GridPoint) -> Bool {
        guard progress == .playing,
              pendingDungeonPickupChoice == nil,
              !isAwaitingManualDiscardSelection,
              let pending = pendingTargetedSupportCard,
              pending.support == .singleAnnihilationSpell,
              let stackIndex = handStacks.firstIndex(where: { $0.id == pending.stackID }),
              handStacks.indices.contains(stackIndex),
              let topCard = handStacks[stackIndex].topCard,
              topCard.id == pending.cardID,
              topCard.supportCard == pending.support,
              let enemyIndex = enemyStates.firstIndex(where: { $0.position == point })
        else { return false }
        guard isSupportCardUsable(in: handStacks[stackIndex]) else { return false }

        let pendingMarkerDamagePoints = enemyWarningPoints
        consumeSupportCard(at: stackIndex)
        enemyStates.remove(at: enemyIndex)
        finishSupportCardTurn(initialMarkerDamagePoints: pendingMarkerDamagePoints)
        checkDeadlockAndApplyPenaltyIfNeeded()
        debugLog("補助カード 消滅の呪文: \(point) の敵を消滅")
        return true
    }

    /// 手札インデックスの補助カードを使用する
    public func playSupportCard(at index: Int) {
        guard progress == .playing, handStacks.indices.contains(index), current != nil else { return }
        guard pendingDungeonPickupChoice == nil else { return }
        guard !isAwaitingManualDiscardSelection else { return }
        guard let card = handStacks[index].topCard, let support = card.supportCard else { return }
        guard isSupportCardUsable(in: handStacks[index]) else { return }

        switch support {
        case .refillEmptySlots:
            let pendingMarkerDamagePoints = enemyWarningPoints
            let wasDungeonInventoryFull = usesDungeonInventoryCards &&
                dungeonInventoryEntries.filter(\.hasUsesRemaining).count >= 9
            consumeSupportCard(at: index)
            if !wasDungeonInventoryFull {
                refillDungeonEmptySlotsWithRandomMoveCards()
            }
            finishSupportCardTurn(initialMarkerDamagePoints: pendingMarkerDamagePoints)
            checkDeadlockAndApplyPenaltyIfNeeded()
            debugLog("補助カード 補給: 空き手札枠へ移動カードを補給")
        case .singleAnnihilationSpell:
            _ = beginTargetedSupportCardSelection(at: index)
        case .annihilationSpell:
            guard !enemyStates.isEmpty else { return }
            let pendingMarkerDamagePoints = enemyWarningPoints
            consumeSupportCard(at: index)
            enemyStates.removeAll()
            finishSupportCardTurn(initialMarkerDamagePoints: pendingMarkerDamagePoints)
            checkDeadlockAndApplyPenaltyIfNeeded()
            debugLog("補助カード 全滅の呪文: 現在フロアの敵をすべて消滅")
        case .freezeSpell:
            guard !enemyStates.isEmpty else { return }
            let pendingMarkerDamagePoints = enemyWarningPoints
            consumeSupportCard(at: index)
            enemyFreezeTurnsRemaining = max(enemyFreezeTurnsRemaining, 3)
            finishSupportCardTurn(initialMarkerDamagePoints: pendingMarkerDamagePoints)
            checkDeadlockAndApplyPenaltyIfNeeded()
            debugLog("補助カード 凍結の呪文: 敵ターンを3回停止")
        case .barrierSpell:
            let pendingMarkerDamagePoints = enemyWarningPoints
            consumeSupportCard(at: index)
            damageBarrierTurnsRemaining = max(damageBarrierTurnsRemaining, 3)
            finishSupportCardTurn(initialMarkerDamagePoints: pendingMarkerDamagePoints)
            checkDeadlockAndApplyPenaltyIfNeeded()
            debugLog("補助カード 障壁の呪文: HPダメージを3回無効化")
        case .antidote:
            let pendingMarkerDamagePoints = enemyWarningPoints
            consumeSupportCard(at: index)
            clearPoisonStatus()
            finishSupportCardTurn(initialMarkerDamagePoints: pendingMarkerDamagePoints)
            checkDeadlockAndApplyPenaltyIfNeeded()
            debugLog("補助カード 解毒薬: 毒状態を解除")
        case .panacea:
            let pendingMarkerDamagePoints = enemyWarningPoints
            consumeSupportCard(at: index)
            clearPoisonStatus()
            isShackled = false
            finishSupportCardTurn(initialMarkerDamagePoints: pendingMarkerDamagePoints)
            checkDeadlockAndApplyPenaltyIfNeeded()
            debugLog("補助カード 万能薬: 状態異常を解除")
        }
    }

    private func clearPoisonStatus() {
        poisonDamageTicksRemaining = 0
        poisonActionsUntilNextDamage = 0
    }

    private func finishSupportCardTurn(initialMarkerDamagePoints: Set<GridPoint>) {
        dungeonEnemyTurnEvent = nil
        guard progress == .playing else { return }
        if applyLavaWaitDamageIfNeeded() { return }
        _ = applyDungeonPostMoveChecks(
            along: [],
            initialMarkerDamagePoints: initialMarkerDamagePoints,
            paralysisTrapPoint: nil,
            skipsPoisonTick: false
        )
    }

    private func consumeSupportCard(at index: Int) {
        cancelTargetedSupportCardSelection()
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
        moveCount += currentActionMoveCost
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

        let isStillValid = validPaths.contains { path in
            path.traversedPoints == validatedMove.path
        }
        guard isStillValid else { return }

        // 盤面タップからのリクエストが残っている場合に備え、念のためここでクリアしておく
        boardTapPlayRequest = nil

        // デバッグログ: 使用カードと移動先を出力（複数候補カードでも選択ベクトルを追跡できるよう詳細を含める）
        debugLog(
            "カード \(cardMove) を使用し \(currentPosition) -> \(validatedMove.destination) へ移動予定 (vector=\(validatedMove.moveVector))"
        )

        let pendingMarkerDamagePoints = enemyWarningPoints
        // 経路ごとの踏破判定と効果適用を順番に処理する
        // アニメーション用に経路を保持し、ワープ時は終点を追加して UI へ伝達する
        let pathPoints = effectivePathPoints(for: validatedMove, from: currentPosition)
        guard let movementResult = processMovementPath(pathPoints, startingAt: currentPosition) else { return }
        let finalPosition = movementResult.finalPosition
        let actualTraversedPath = movementResult.actualTraversedPath
        let encounteredRevisit = movementResult.encounteredRevisit
        let detectedEffects = movementResult.detectedEffects
        let presentationSteps = movementResult.presentationSteps
        let postMoveTileEffect = movementResult.postMoveTileEffect
        let preservesPlayedCard = movementResult.preservesPlayedCard
        let paralysisTrapPoint = movementResult.paralysisTrapPoint
        // 直近の移動解決結果を更新し、GameScene が効果に応じたアニメーションを選択できるようにする
        lastMovementResolution = MovementResolution(
            path: actualTraversedPath,
            finalPosition: finalPosition,
            appliedEffects: detectedEffects,
            presentationInitialHP: movementResult.presentationInitialHP,
            presentationInitialHandStacks: movementResult.presentationInitialHandStacks,
            presentationInitialCollectedDungeonCardPickupIDs: movementResult.presentationInitialCollectedDungeonCardPickupIDs,
            presentationInitialCollectedDungeonRelicPickupIDs: movementResult.presentationInitialCollectedDungeonRelicPickupIDs,
            presentationInitialEnemyStates: movementResult.presentationInitialEnemyStates,
            presentationInitialCrackedFloorPoints: movementResult.presentationInitialCrackedFloorPoints,
            presentationInitialCollapsedFloorPoints: movementResult.presentationInitialCollapsedFloorPoints,
            presentationInitialBoard: movementResult.presentationInitialBoard,
            presentationSteps: presentationSteps
        )
        // current を更新するのは最後に行い、Combine の通知順序で UI が解決情報を先に受け取れるように配慮する
        current = finalPosition
        moveCount += currentActionMoveCost

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

        let shouldPreservePlayedCard = preservesPlayedCard
        let preservedCard = shouldPreservePlayedCard ? validatedMove.card : nil
        if shouldPreservePlayedCard {
            debugLog("カード温存マス効果で使用カードを消費しませんでした")
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

        if progress == .playing, dungeonFallEvent == nil {
            applyPostMoveTileEffect(postMoveTileEffect, preserving: preservedCard)
        }

        if applyDungeonPostMoveChecks(
            along: actualTraversedPath,
            initialMarkerDamagePoints: pendingMarkerDamagePoints,
            paralysisTrapPoint: paralysisTrapPoint,
            skipsPoisonTick: movementResult.triggeredPoisonTrap
        ) { return }

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
        guard !isAwaitingManualDiscardSelection else { return }
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

        let pendingMarkerDamagePoints = enemyWarningPoints
        let pathPoints = basicMove.path
        guard let movementResult = processMovementPath(pathPoints, startingAt: currentPosition) else { return }
        let finalPosition = movementResult.finalPosition
        let actualTraversedPath = movementResult.actualTraversedPath
        let encounteredRevisit = movementResult.encounteredRevisit
        let detectedEffects = movementResult.detectedEffects
        let presentationSteps = movementResult.presentationSteps
        let postMoveTileEffect = movementResult.postMoveTileEffect
        let paralysisTrapPoint = movementResult.paralysisTrapPoint
        lastMovementResolution = MovementResolution(
            path: actualTraversedPath,
            finalPosition: finalPosition,
            appliedEffects: detectedEffects,
            presentationInitialHP: movementResult.presentationInitialHP,
            presentationInitialHandStacks: movementResult.presentationInitialHandStacks,
            presentationInitialCollectedDungeonCardPickupIDs: movementResult.presentationInitialCollectedDungeonCardPickupIDs,
            presentationInitialCollectedDungeonRelicPickupIDs: movementResult.presentationInitialCollectedDungeonRelicPickupIDs,
            presentationInitialEnemyStates: movementResult.presentationInitialEnemyStates,
            presentationInitialCrackedFloorPoints: movementResult.presentationInitialCrackedFloorPoints,
            presentationInitialCollapsedFloorPoints: movementResult.presentationInitialCollapsedFloorPoints,
            presentationInitialBoard: movementResult.presentationInitialBoard,
            presentationSteps: presentationSteps
        )
        current = finalPosition
        moveCount += currentActionMoveCost

        if encounteredRevisit {
            hasRevisitedTile = true
            if mode.revisitPenaltyCost > 0 {
                penaltyCount += mode.revisitPenaltyCost
            }
        }

        announceRemainingTiles()
        if progress == .playing, dungeonFallEvent == nil {
            applyPostMoveTileEffect(postMoveTileEffect, preserving: nil)
        }

        _ = applyDungeonPostMoveChecks(
            along: actualTraversedPath,
            initialMarkerDamagePoints: pendingMarkerDamagePoints,
            paralysisTrapPoint: paralysisTrapPoint,
            skipsPoisonTick: movementResult.triggeredPoisonTrap
        )
    }

    private func processMovementPath(
        _ pathPoints: [GridPoint],
        startingAt start: GridPoint
    ) -> MovementProcessingResult? {
        var pendingPath = pathPoints
        var finalPosition = start
        var actualTraversedPath: [GridPoint] = []
        var encounteredRevisit = false
        var detectedEffects: [MovementResolution.AppliedEffect] = []
        var presentationSteps: [MovementResolution.PresentationStep] = []
        let presentationInitialHP = dungeonHP
        let presentationInitialHandStacks = handStacks
        let presentationInitialCollectedDungeonCardPickupIDs = collectedDungeonCardPickupIDs
        let presentationInitialCollectedDungeonRelicPickupIDs = collectedDungeonRelicPickupIDs
        let presentationInitialEnemyStates = enemyStates
        let presentationInitialCrackedFloorPoints = crackedFloorPoints
        let presentationInitialCollapsedFloorPoints = collapsedFloorPoints
        let presentationInitialBoard = board
        var postMoveTileEffect: PostMoveTileEffect?
        var preservesPlayedCard = false
        var paralysisTrapPoint: GridPoint?
        var triggeredPoisonTrap = false
        var blastEffectCount = 0
        let blastEffectLimit = max(1, board.size * board.size * 2)

        var stepIndex = 0
        while stepIndex < pendingPath.count {
            let stepPoint = pendingPath[stepIndex]
            guard board.contains(stepPoint), board.isTraversable(stepPoint) else { return nil }

            actualTraversedPath.append(stepPoint)
            let hpBeforeStep = dungeonHP
            if board.isVisited(stepPoint) {
                encounteredRevisit = true
            }
            board.markVisited(stepPoint)
            finalPosition = stepPoint

            defeatDungeonEnemy(at: stepPoint)
            if shouldApplyEnemyDangerDamageDuringMovement(stepIndex: stepIndex, path: pendingPath),
               applyDungeonEnemyDangerDamageIfNeeded(at: stepPoint) {
                presentationSteps.append(
                    movementPresentationStep(
                        at: stepPoint,
                        hpBeforeStep: hpBeforeStep,
                        stopReason: .failed
                    )
                )
                break
            }
            if applyDungeonHazard(at: stepPoint) {
                collectDungeonCardPickup(at: stepPoint)
                collectDungeonRelicPickup(at: stepPoint)
                presentationSteps.append(
                    movementPresentationStep(
                        at: stepPoint,
                        hpBeforeStep: hpBeforeStep,
                        stopReason: dungeonFallEvent == nil ? .failed : .fall
                    )
                )
                break
            }
            collectDungeonCardPickup(at: stepPoint)
            collectDungeonRelicPickup(at: stepPoint)
            if progress == .failed {
                presentationSteps.append(
                    movementPresentationStep(
                        at: stepPoint,
                        hpBeforeStep: hpBeforeStep,
                        stopReason: .failed
                    )
                )
                break
            }

            updateDungeonExitLockIfNeeded(at: stepPoint)
            if shouldStopDungeonMovementAtExit(at: stepPoint) {
                presentationSteps.append(
                    movementPresentationStep(
                        at: stepPoint,
                        hpBeforeStep: hpBeforeStep,
                        stopReason: .exit
                    )
                )
                break
            }

            var stopReason: MovementResolution.PresentationStep.StopReason?
            if let effect = board.effect(at: stepPoint) {
                detectedEffects.append(.init(point: stepPoint, effect: effect))
                switch effect {
                case .warp(_, let destination):
                    if board.contains(destination), board.isTraversable(destination) {
                        presentationSteps.append(
                            movementPresentationStep(
                                at: stepPoint,
                                hpBeforeStep: hpBeforeStep
                            )
                        )
                        let hpBeforeWarpDestination = dungeonHP
                        if board.isVisited(destination) {
                            encounteredRevisit = true
                        }
                        board.markVisited(destination)
                        finalPosition = destination
                        actualTraversedPath.append(destination)
                        defeatDungeonEnemy(at: destination)
                        if applyDungeonHazard(at: destination) {
                            collectDungeonCardPickup(at: destination)
                            collectDungeonRelicPickup(at: destination)
                            presentationSteps.append(
                                movementPresentationStep(
                                    at: destination,
                                    hpBeforeStep: hpBeforeWarpDestination,
                                    stopReason: dungeonFallEvent == nil ? .failed : .fall
                                )
                            )
                            stepIndex = pendingPath.count
                            break
                        }
                        collectDungeonCardPickup(at: destination)
                        collectDungeonRelicPickup(at: destination)
                        if progress == .failed {
                            presentationSteps.append(
                                movementPresentationStep(
                                    at: destination,
                                    hpBeforeStep: hpBeforeWarpDestination,
                                    stopReason: .failed
                                )
                            )
                            stepIndex = pendingPath.count
                            break
                        }
                        updateDungeonExitLockIfNeeded(at: destination)
                        presentationSteps.append(
                            movementPresentationStep(
                                at: destination,
                                hpBeforeStep: hpBeforeWarpDestination,
                                stopReason: .warp
                            )
                        )
                        stepIndex = pendingPath.count
                    } else {
                        debugLog("ワープ先 \(destination) が盤面外または移動不可のため無視しました")
                    }
                    stopReason = .warp
                case .shuffleHand, .preserveCard, .discardRandomHand, .discardAllMoveCards, .discardAllSupportCards, .discardAllHands:
                    registerPostMoveTileEffect(
                        effect,
                        postMoveTileEffect: &postMoveTileEffect,
                        preservesPlayedCard: &preservesPlayedCard
                    )
                case .swamp:
                    stepIndex = pendingPath.count
                    break
                case .poisonTrap:
                    applyPoisonTrap()
                    triggeredPoisonTrap = true
                case .shackleTrap:
                    isShackled = true
                    stopReason = .shackleTrap
                    presentationSteps.append(
                        movementPresentationStep(
                            at: stepPoint,
                            hpBeforeStep: hpBeforeStep,
                            stopReason: .shackleTrap
                        )
                    )
                    stepIndex = pendingPath.count
                case .slow:
                    paralysisTrapPoint = stepPoint
                    stopReason = .slow
                    presentationSteps.append(
                        movementPresentationStep(
                            at: stepPoint,
                            hpBeforeStep: hpBeforeStep,
                            stopReason: .slow
                        )
                    )
                    stepIndex = pendingPath.count
                case .blast(let direction):
                    blastEffectCount += 1
                    guard blastEffectCount <= blastEffectLimit else {
                        debugLog("吹き飛ばしマスの連鎖が上限を超えたため現在地で停止しました")
                        stepIndex = pendingPath.count
                        break
                    }
                    if stepIndex + 1 < pendingPath.count {
                        pendingPath.removeSubrange((stepIndex + 1)..<pendingPath.count)
                    }
                    var blastPoint = stepPoint
                    while true {
                        let nextPoint = blastPoint.offset(dx: direction.dx, dy: direction.dy)
                        guard board.contains(nextPoint), board.isTraversable(nextPoint) else { break }
                        pendingPath.append(nextPoint)
                        blastPoint = nextPoint
                    }
                }
            }
            if stopReason == nil {
                presentationSteps.append(
                    movementPresentationStep(
                        at: stepPoint,
                        hpBeforeStep: hpBeforeStep
                    )
                )
            }

            stepIndex += 1
        }

        if actualTraversedPath.isEmpty {
            actualTraversedPath.append(finalPosition)
        }
        return MovementProcessingResult(
            finalPosition: finalPosition,
            actualTraversedPath: actualTraversedPath,
            encounteredRevisit: encounteredRevisit,
            detectedEffects: detectedEffects,
            presentationInitialHP: presentationInitialHP,
            presentationInitialHandStacks: presentationInitialHandStacks,
            presentationInitialCollectedDungeonCardPickupIDs: presentationInitialCollectedDungeonCardPickupIDs,
            presentationInitialCollectedDungeonRelicPickupIDs: presentationInitialCollectedDungeonRelicPickupIDs,
            presentationInitialEnemyStates: presentationInitialEnemyStates,
            presentationInitialCrackedFloorPoints: presentationInitialCrackedFloorPoints,
            presentationInitialCollapsedFloorPoints: presentationInitialCollapsedFloorPoints,
            presentationInitialBoard: presentationInitialBoard,
            presentationSteps: presentationSteps,
            postMoveTileEffect: postMoveTileEffect,
            preservesPlayedCard: preservesPlayedCard,
            paralysisTrapPoint: paralysisTrapPoint,
            triggeredPoisonTrap: triggeredPoisonTrap
        )
    }

    private func shouldApplyEnemyDangerDamageDuringMovement(
        stepIndex: Int,
        path: [GridPoint]
    ) -> Bool {
        path.count > 1 && stepIndex < path.count - 1
    }

    private func registerPostMoveTileEffect(
        _ effect: TileEffect,
        postMoveTileEffect: inout PostMoveTileEffect?,
        preservesPlayedCard: inout Bool
    ) {
        switch effect {
        case .shuffleHand:
            if postMoveTileEffect == nil {
                postMoveTileEffect = .shuffleHand
            }
        case .discardRandomHand:
            if postMoveTileEffect == nil || postMoveTileEffect == .shuffleHand {
                postMoveTileEffect = .discardRandomHand
            }
        case .discardAllMoveCards:
            switch postMoveTileEffect {
            case .discardAllHands:
                break
            case .discardAllSupportCards:
                postMoveTileEffect = .discardAllHands
            default:
                postMoveTileEffect = .discardAllMoveCards
            }
        case .discardAllSupportCards:
            switch postMoveTileEffect {
            case .discardAllHands:
                break
            case .discardAllMoveCards:
                postMoveTileEffect = .discardAllHands
            default:
                postMoveTileEffect = .discardAllSupportCards
            }
        case .discardAllHands:
            postMoveTileEffect = .discardAllHands
        case .preserveCard:
            preservesPlayedCard = true
        case .warp, .blast, .slow, .shackleTrap, .poisonTrap, .swamp:
            break
        }
    }

    private func applyPostMoveTileEffect(_ effect: PostMoveTileEffect?, preserving preservedCard: DealtCard?) {
        guard let effect else { return }

        switch effect {
        case .shuffleHand:
            applyTileEffectHandRedraw(preserving: preservedCard)
        case .discardRandomHand:
            applyTileEffectHandDiscardAllowsNextPreservation(.random)
        case .discardAllMoveCards:
            applyTileEffectHandDiscardAllowsNextPreservation(.moveCards)
        case .discardAllSupportCards:
            applyTileEffectHandDiscardAllowsNextPreservation(.supportCards)
        case .discardAllHands:
            applyTileEffectHandDiscardAllowsNextPreservation(.all)
        }
    }

    private enum TileEffectHandDiscardScope {
        case random
        case moveCards
        case supportCards
        case all
    }

    private func applyTileEffectHandDiscardAllowsNextPreservation(_ scope: TileEffectHandDiscardScope) {
        updateProgressForPenaltyFlow(.deadlock)
        cancelManualDiscardSelection()
        resetBoardTapPlayRequestForPenalty()

        if usesDungeonInventoryCards {
            applyDungeonInventoryHandDiscard(scope)
        } else {
            applyStandardHandDiscard(scope)
        }

#if canImport(UIKit)
        let message: String
        switch scope {
        case .random:
            message = "手札喪失罠の効果で手札を1つ失いました。"
        case .moveCards:
            message = "移動カード喪失罠の効果で移動カードをすべて失いました。"
        case .supportCards:
            message = "補助カード喪失罠の効果で補助カードをすべて失いました。"
        case .all:
            message = "全手札喪失罠の効果で手札をすべて失いました。"
        }
        UIAccessibility.post(notification: .announcement, argument: message)
#endif

        debugLog("手札喪失罠効果を適用: scope=\(scope), 手札=\(handStacks.count), NEXT=\(nextCards.count)")

        if mode.requiresSpawnSelection && current == nil {
            updateProgressForPenaltyFlow(.awaitingSpawn)
        } else {
            updateProgressForPenaltyFlow(.playing)
        }
    }

    private func applyStandardHandDiscard(_ scope: TileEffectHandDiscardScope) {
        switch scope {
        case .random:
            guard let index = deterministicHandDiscardIndex(candidates: Array(handManager.handStacks.indices)) else {
                refreshHandStateFromManager()
                return
            }
            let removedStack = handManager.removeStack(at: index)
            debugLog("手札喪失罠: stackIndex=\(index), 枚数=\(removedStack.count)")
        case .moveCards:
            let indices = handManager.handStacks.indices.filter { handManager.handStacks[$0].topCard?.moveCard != nil }
            for index in indices.reversed() {
                handManager.removeStack(at: index)
            }
            debugLog("移動カード喪失罠: 通常手札の移動カードを全破棄 count=\(indices.count)")
        case .supportCards:
            let indices = handManager.handStacks.indices.filter { handManager.handStacks[$0].topCard?.supportCard != nil }
            for index in indices.reversed() {
                handManager.removeStack(at: index)
            }
            debugLog("補助カード喪失罠: 通常手札の補助カードを全破棄 count=\(indices.count)")
        case .all:
            handManager.clearHandStacks()
            debugLog("全手札喪失罠: 通常手札を全破棄")
        }
        refreshHandStateFromManager()
    }

    private func applyDungeonInventoryHandDiscard(_ scope: TileEffectHandDiscardScope) {
        let liveIndices = dungeonInventoryEntries.indices.filter { dungeonInventoryEntries[$0].hasUsesRemaining }
        switch scope {
        case .random:
            guard let selectedLiveOffset = deterministicHandDiscardIndex(candidates: Array(liveIndices.indices)) else {
                syncDungeonInventoryHandStacks()
                return
            }
            let entryIndex = liveIndices[selectedLiveOffset]
            let discarded = dungeonInventoryEntries[entryIndex].playable
            dungeonInventoryEntries[entryIndex].rewardUses = 0
            dungeonInventoryEntries[entryIndex].pickupUses = 0
            debugLog("手札喪失罠: 所持枠を破棄 \(discarded.identityText)")
        case .moveCards:
            for index in liveIndices where dungeonInventoryEntries[index].moveCard != nil {
                dungeonInventoryEntries[index].rewardUses = 0
                dungeonInventoryEntries[index].pickupUses = 0
            }
            debugLog("移動カード喪失罠: 所持枠の移動カードを全破棄")
        case .supportCards:
            for index in liveIndices where dungeonInventoryEntries[index].supportCard != nil {
                dungeonInventoryEntries[index].rewardUses = 0
                dungeonInventoryEntries[index].pickupUses = 0
            }
            debugLog("補助カード喪失罠: 所持枠の補助カードを全破棄")
        case .all:
            for index in liveIndices {
                dungeonInventoryEntries[index].rewardUses = 0
                dungeonInventoryEntries[index].pickupUses = 0
            }
            debugLog("全手札喪失罠: 所持枠を全破棄")
        }
        syncDungeonInventoryHandStacks()
    }

    private func deterministicHandDiscardIndex(candidates: [Int]) -> Int? {
        guard !candidates.isEmpty else { return nil }
        var generator = DungeonRefillRandomGenerator(seed: handDiscardSeed())
        let offset = Int(generator.next() % UInt64(candidates.count))
        return candidates[offset]
    }

    private func handDiscardSeed() -> UInt64 {
        var seed = mode.dungeonMetadataSnapshot?.runState?.cardVariationSeed ?? mode.deckSeed ?? 1
        seed ^= UInt64(board.size) &* 0x9E37_79B9_7F4A_7C15
        seed ^= UInt64(max(moveCount, 0) + 1) &* 0xBF58_476D_1CE4_E5B9
        seed ^= UInt64(handStacks.count + 17) &* 0x94D0_49BB_1331_11EB
        if let current {
            seed ^= UInt64(current.x + 31) &* 1099511628211
            seed ^= UInt64(current.y + 37) &* 1469598103934665603
        }
        return seed == 0 ? 1 : seed
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


    /// カードの移動候補を解決する
    private func resolvedPaths(
        for card: DealtCard,
        from origin: GridPoint,
        on activeBoard: Board
    ) -> [MoveCard.MovePattern.Path] {
        guard let move = card.moveCard else { return [] }
        let context = moveResolutionContext(on: activeBoard)
        return move.resolvePaths(from: origin, context: context)
    }

    private func moveResolutionContext(on activeBoard: Board) -> MoveCard.MovePattern.ResolutionContext {
        MoveCard.MovePattern.ResolutionContext(
            boardSize: activeBoard.size,
            contains: { point in activeBoard.contains(point) },
            isTraversable: { point in activeBoard.isTraversable(point) },
            isVisited: { point in activeBoard.isVisited(point) },
            effectAt: { point in activeBoard.effect(at: point) }
        )
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
        guard board.effect(at: origin) != .swamp else { return [] }

        // 盤面境界を参照するためローカル変数として保持しておく
        let activeBoard = board
        // 列挙中に同じ座標へ向かうカードを検出しやすいよう、結果は座標→スタック順でソートする
        var resolved: [ResolvedCardMove] = []
        resolved.reserveCapacity(referenceHandStacks.count)

        for (index, stack) in referenceHandStacks.enumerated() {
            // トップカードが存在しなければスキップ
            guard let topCard = stack.topCard else { continue }
            guard topCard.moveCard != nil else { continue }

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

        // 候補が存在しない場合は nil を返して終了する
        guard !destinationMatches.isEmpty else { return nil }

        // 複数スタックの競合は UI 側で警告するため、ここでは代表候補だけを返す
        return destinationMatches.first
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
                configuration: mode.deckConfiguration
            )
        } else {
            deck.reset()
        }

        board = Board(
            size: mode.boardSize,
            initialVisitedPoints: mode.initialVisitedPoints,
            impassablePoints: mode.impassableTilePoints,
            tileEffects: mode.tileEffects
        )
        current = mode.initialSpawnPoint
        moveCount = 0
        penaltyCount = 0
        hasRevisitedTile = false
        elapsedSeconds = 0
        dungeonHP = mode.dungeonRules?.failureRule.initialHP ?? 0
        hazardDamageMitigationsRemaining = mode.dungeonMetadataSnapshot?.runState?.hazardDamageMitigationsRemaining ?? 0
        enemyDamageMitigationsRemaining = mode.dungeonMetadataSnapshot?.runState?.enemyDamageMitigationsRemaining ?? 0
        markerDamageMitigationsRemaining = mode.dungeonMetadataSnapshot?.runState?.markerDamageMitigationsRemaining ?? 0
        enemyFreezeTurnsRemaining = 0
        damageBarrierTurnsRemaining = 0
        isShackled = false
        poisonDamageTicksRemaining = 0
        poisonActionsUntilNextDamage = 0
        enemyStates = mode.dungeonRules?.enemies.map(EnemyState.init(definition:)) ?? []
        let currentFloorIndex = mode.dungeonMetadataSnapshot?.runState?.currentFloorIndex ?? 0
        crackedFloorPoints = mode.dungeonMetadataSnapshot?.runState?.crackedFloorPoints(for: currentFloorIndex) ?? []
        collapsedFloorPoints = mode.dungeonMetadataSnapshot?.runState?.collapsedFloorPoints(for: currentFloorIndex) ?? []
        consumedHealingTilePoints = []
        dungeonInventoryEntries = mode.dungeonMetadataSnapshot?.runState?.rewardInventoryEntries ?? []
        collectedDungeonCardPickupIDs = []
        dungeonRelicEntries = mode.dungeonMetadataSnapshot?.runState?.relicEntries ?? []
        dungeonCurseEntries = mode.dungeonMetadataSnapshot?.runState?.curseEntries ?? []
        collectedDungeonRelicPickupIDs = mode.dungeonMetadataSnapshot?.runState?.collectedDungeonRelicPickupIDs ?? []
        dungeonRelicAcquisitionPresentations = []
        pendingDungeonPickupChoice = nil
        isDungeonExitUnlocked = mode.dungeonRules?.exitLock == nil
        dungeonExitUnlockEvent = nil
        dungeonFallEvent = nil
        dungeonEnemyTurnEvent = nil
        penaltyEvent = nil
        boardTapPlayRequest = nil
        boardTapBasicMoveRequest = nil
        isAwaitingManualDiscardSelection = false
        pendingTargetedSupportCard = nil
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
            var cards = Array(existingStack?.cards.prefix(entry.totalUses) ?? [])
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
            dungeonInventoryEntries[index].rewardUses += normalizedPickupUses + normalizedRewardUses
            dungeonInventoryEntries[index].pickupUses = 0
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

        if dungeonInventoryEntries[index].rewardUses > 0 {
            dungeonInventoryEntries[index].rewardUses -= 1
        } else if dungeonInventoryEntries[index].pickupUses > 0 {
            dungeonInventoryEntries[index].pickupUses -= 1
        }
        dungeonInventoryEntries[index].pickupUses = 0
        syncDungeonInventoryHandStacks()
    }

    @discardableResult
    public func removeDungeonRewardInventoryCard(_ card: MoveCard) -> Bool {
        guard usesDungeonInventoryCards,
              let index = dungeonInventoryEntries.firstIndex(where: { $0.moveCard == card && $0.hasUsesRemaining })
        else { return false }

        dungeonInventoryEntries[index].rewardUses = 0
        dungeonInventoryEntries[index].pickupUses = 0
        syncDungeonInventoryHandStacks()
        return true
    }

    @discardableResult
    public func removeDungeonRewardInventorySupportCard(_ support: SupportCard) -> Bool {
        guard usesDungeonInventoryCards,
              let index = dungeonInventoryEntries.firstIndex(where: { $0.supportCard == support && $0.hasUsesRemaining })
        else { return false }

        dungeonInventoryEntries[index].rewardUses = 0
        dungeonInventoryEntries[index].pickupUses = 0
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
        debugLog("満杯拾得カードを取得せず破棄: \(choice.pickup.playable.displayName) @\(choice.pickup.point)")
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
        let didAdd = addDungeonInventoryPlayable(choice.pickup.playable, pickupUses: choice.pickupUses)
        guard didAdd else {
            syncDungeonInventoryHandStacks()
            return false
        }

        collectedDungeonCardPickupIDs.insert(choice.pickup.id)
        debugLog("満杯拾得カードを取得: \(choice.pickup.playable.displayName), 破棄=\(playable.displayName)")
        return true
    }

    private func collectDungeonCardPickups(along traversedPath: [GridPoint]) {
        guard usesDungeonInventoryCards else { return }
        let visitedPoints = Set(traversedPath)
        for pickup in activeDungeonCardPickups where visitedPoints.contains(pickup.point) {
            if collectDungeonCardPickupDefinition(pickup) == false {
                break
            }
        }
    }

    @discardableResult
    private func collectDungeonCardPickup(at point: GridPoint) -> Bool {
        guard usesDungeonInventoryCards else { return false }
        guard let pickup = activeDungeonCardPickups.first(where: { $0.point == point }) else { return false }
        return collectDungeonCardPickupDefinition(pickup)
    }

    @discardableResult
    private func collectDungeonRelicPickup(at point: GridPoint) -> Bool {
        guard let pickup = activeDungeonRelicPickups.first(where: { $0.point == point }) else { return false }
        return collectDungeonRelicPickupDefinition(pickup)
    }

    @discardableResult
    private func collectDungeonCardPickupDefinition(_ pickup: DungeonCardPickupDefinition) -> Bool {
        guard usesDungeonInventoryCards else { return false }
        guard pendingDungeonPickupChoice == nil else { return false }
        let pickupUses = adjustedDungeonPickupUses(pickup.uses)
        if addDungeonInventoryPlayable(pickup.playable, pickupUses: pickupUses) {
            collectedDungeonCardPickupIDs.insert(pickup.id)
            debugLog("拾得カードを取得: \(pickup.playable.displayName) 残り+\(pickupUses) @\(pickup.point)")
        } else if beginPendingDungeonPickupChoiceIfNeeded(for: pickup) {
            return false
        }
        syncDungeonInventoryHandStacks()
        return true
    }

    private func adjustedDungeonPickupUses(_ uses: Int) -> Int {
        var adjustment = 0
        if hasDungeonRelic(.explorerBag) {
            adjustment += 1
        }
        if hasDungeonCurse(.greedyBag) {
            adjustment += 2
        }
        if hasDungeonCurse(.warpedHourglass) {
            adjustment -= 1
        }
        return max(uses + adjustment, 1)
    }

    @discardableResult
    private func collectDungeonRelicPickupDefinition(_ pickup: DungeonRelicPickupDefinition) -> Bool {
        guard mode.dungeonRules?.difficulty == .growth else { return false }
        guard !collectedDungeonRelicPickupIDs.contains(pickup.id) else { return false }
        collectedDungeonRelicPickupIDs.insert(pickup.id)

        let outcome = selectedRelicPickupOutcome(for: pickup)
        var presentationItems: [DungeonRelicAcquisitionPresentation.Item] = []

        switch outcome {
        case .relic:
            if let relic = grantDungeonRelic(from: pickup, salt: "relic") {
                presentationItems.append(.relic(relic))
            } else if pickup.kind == .safe {
                dungeonHP += 1
                presentationItems.append(.hpCompensation(1))
                debugLog("宝箱の遺物候補が尽きたためHP補填: \(pickup.id) @\(pickup.point), HP=\(dungeonHP)")
            }
        case .curse:
            presentationItems.append(contentsOf: grantDungeonCurse(from: pickup, salt: "curse"))
        case .mimic:
            let damage = applyDungeonMimicTrap(from: pickup)
            presentationItems.append(.mimicDamage(damage))
        case .pandora:
            if let relic = grantDungeonRelic(from: pickup, salt: "pandora-relic") {
                presentationItems.append(.relic(relic))
            }
            presentationItems.append(contentsOf: grantDungeonCurse(from: pickup, salt: "pandora-curse"))
            debugLog("パンドラの箱が開いた: \(pickup.id) @\(pickup.point)")
        }
        publishDungeonRelicAcquisitionPresentationIfNeeded(outcome: outcome, items: presentationItems)
        return true
    }

    @discardableResult
    private func grantDungeonRelic(from pickup: DungeonRelicPickupDefinition, salt: String) -> DungeonRelicEntry? {
        let candidates = availableRelicCandidates(for: pickup)
        guard let relicID = selectedRelicID(from: candidates, pickupID: pickup.id, salt: salt) else {
            debugLog("宝箱は空でした: \(pickup.id) @\(pickup.point)")
            return nil
        }

        let entry = DungeonRelicEntry(relicID: relicID)
        dungeonRelicEntries.append(entry)
        applyImmediateDungeonRelicEffect(relicID)
        debugLog("遺物を取得: \(relicID.displayName) @\(pickup.point)")
        return entry
    }

    @discardableResult
    private func grantDungeonCurse(from pickup: DungeonRelicPickupDefinition, salt: String) -> [DungeonRelicAcquisitionPresentation.Item] {
        let candidates = availableCurseCandidates(for: pickup)
        guard let curseID = selectedCurseID(from: candidates, pickupID: pickup.id, salt: salt) else { return [] }
        if consumeDungeonRelicUse(.moonMirror) {
            if let relic = grantDungeonRelic(from: pickup, salt: "moon-mirror-\(salt)") {
                debugLog("月の鏡で呪い遺物を通常遺物へ変換: \(curseID.displayName) @\(pickup.point)")
                return [.relic(relic)]
            } else {
                debugLog("月の鏡で呪い遺物を無効化: \(curseID.displayName) @\(pickup.point)")
            }
            return []
        }
        let entry = DungeonCurseEntry(curseID: curseID)
        dungeonCurseEntries.append(entry)
        applyImmediateDungeonCurseEffect(curseID)
        debugLog("呪い遺物を取得: \(curseID.displayName) @\(pickup.point)")
        return [.curse(entry)]
    }

    @discardableResult
    private func applyDungeonMimicTrap(from pickup: DungeonRelicPickupDefinition) -> Int {
        let damage = hasDungeonCurse(.redChalice) ? 3 : 2
        dungeonHP = max(dungeonHP - damage, 0)
        debugLog("ミミックが出現: \(pickup.id) @\(pickup.point), HP=\(dungeonHP)")
        if dungeonHP <= 0 {
            finalizeElapsedTimeIfNeeded()
            progress = .failed
        }
        return damage
    }

    private func publishDungeonRelicAcquisitionPresentationIfNeeded(
        outcome: DungeonRelicPickupOutcome,
        items: [DungeonRelicAcquisitionPresentation.Item]
    ) {
        guard !items.isEmpty else { return }
        dungeonRelicAcquisitionPresentations.append(
            DungeonRelicAcquisitionPresentation(
                source: .pickup,
                outcome: outcome,
                items: items
            )
        )
    }

    private func selectedRelicPickupOutcome(for pickup: DungeonRelicPickupDefinition) -> DungeonRelicPickupOutcome {
        let weights = availableOutcomeWeights(for: pickup)
        let totalWeight = weights.reduce(0) { $0 + max($1.1, 0) }
        guard totalWeight > 0 else { return .relic }
        var generator = DungeonRefillRandomGenerator(seed: pickupSeed(pickupID: pickup.id, salt: "outcome"))
        var roll = Int(generator.next() % UInt64(totalWeight))
        for (outcome, weight) in weights {
            let normalizedWeight = max(weight, 0)
            if roll < normalizedWeight {
                return outcome
            }
            roll -= normalizedWeight
        }
        return .relic
    }

    private func availableRelicCandidates(for pickup: DungeonRelicPickupDefinition) -> [DungeonRelicID] {
        let ownedRelics = Set(dungeonRelicEntries.map(\.relicID))
        return pickup.candidateRelics.filter { !ownedRelics.contains($0) }
    }

    private func availableCurseCandidates(for pickup: DungeonRelicPickupDefinition) -> [DungeonCurseID] {
        let ownedCurses = Set(dungeonCurseEntries.map(\.curseID))
        return pickup.candidateCurses.filter { !ownedCurses.contains($0) }
    }

    private func availableOutcomeWeights(for pickup: DungeonRelicPickupDefinition) -> [(DungeonRelicPickupOutcome, Int)] {
        let hasRelicCandidates = !availableRelicCandidates(for: pickup).isEmpty
        let hasCurseCandidates = !availableCurseCandidates(for: pickup).isEmpty
        return pickup.kind.outcomeWeights.filter { outcome, weight in
            guard weight > 0 else { return false }
            switch outcome {
            case .relic:
                return hasRelicCandidates
            case .curse:
                return hasCurseCandidates
            case .pandora:
                return hasRelicCandidates && hasCurseCandidates
            case .mimic:
                return true
            }
        }
    }

    private func selectedRelicID(from candidates: [DungeonRelicID], pickupID: String, salt: String) -> DungeonRelicID? {
        guard !candidates.isEmpty else { return nil }
        var generator = DungeonRefillRandomGenerator(seed: pickupSeed(pickupID: pickupID, salt: salt))
        return candidates[Int(generator.next() % UInt64(candidates.count))]
    }

    private func selectedCurseID(from candidates: [DungeonCurseID], pickupID: String, salt: String) -> DungeonCurseID? {
        guard !candidates.isEmpty else { return nil }
        var generator = DungeonRefillRandomGenerator(seed: pickupSeed(pickupID: pickupID, salt: salt))
        return candidates[Int(generator.next() % UInt64(candidates.count))]
    }

    private func pickupSeed(pickupID: String, salt: String) -> UInt64 {
        var seed = mode.dungeonMetadataSnapshot?.runState?.cardVariationSeed ?? mode.deckSeed ?? 1
        seed ^= UInt64(max(moveCount, 0) + 1) &* 0x9E37_79B9_7F4A_7C15
        for scalar in pickupID.unicodeScalars {
            seed = seed &* 1099511628211 &+ UInt64(scalar.value)
        }
        for scalar in salt.unicodeScalars {
            seed = seed &* 1469598103934665603 &+ UInt64(scalar.value)
        }
        return seed
    }

    private func applyImmediateDungeonRelicEffect(_ relicID: DungeonRelicID) {
        switch relicID {
        case .crackedShield:
            break
        case .glowingHeart:
            dungeonHP += 2
        case .heavyCrown, .oldMap, .blackFeather, .chippedHourglass, .travelerBoots, .silverNeedle, .starCup, .explorerBag, .moonMirror, .victoryBanner:
            break
        }
    }

    private func applyImmediateDungeonCurseEffect(_ curseID: DungeonCurseID) {
        switch curseID {
        case .rustyChain, .thornMark:
            dungeonHP += 1
        case .bloodPact:
            dungeonHP += 2
        case .obsidianHeart:
            dungeonHP += 4
        case .redChalice:
            dungeonHP += 6
        case .cursedCrown, .warpedHourglass, .greedyBag, .crackedCompass:
            break
        }
    }

    private func movementPresentationStep(
        at point: GridPoint,
        hpBeforeStep: Int,
        stopReason: MovementResolution.PresentationStep.StopReason? = nil
    ) -> MovementResolution.PresentationStep {
        MovementResolution.PresentationStep(
            point: point,
            hpAfter: dungeonHP,
            handStacksAfter: handStacks,
            collectedDungeonCardPickupIDsAfter: collectedDungeonCardPickupIDs,
            collectedDungeonRelicPickupIDsAfter: collectedDungeonRelicPickupIDs,
            enemyStatesAfter: enemyStates,
            crackedFloorPointsAfter: crackedFloorPoints,
            collapsedFloorPointsAfter: collapsedFloorPoints,
            boardAfter: board,
            tookDamage: dungeonHP < hpBeforeStep,
            stopReason: stopReason
        )
    }

    private func defeatDungeonEnemies(along traversedPath: [GridPoint]) {
        guard mode.usesDungeonExit, !enemyStates.isEmpty else { return }
        let stompedPoints = Set(traversedPath)
        guard !stompedPoints.isEmpty else { return }

        let defeatedEnemies = enemyStates.filter { stompedPoints.contains($0.position) }
        guard !defeatedEnemies.isEmpty else { return }

        enemyStates.removeAll { stompedPoints.contains($0.position) }
        let summary = defeatedEnemies.map { "\($0.name)@\($0.position)" }.joined(separator: ", ")
        debugLog("敵を踏みつけ撃破: \(summary)")
    }

    private func defeatDungeonEnemy(at point: GridPoint) {
        defeatDungeonEnemies(along: [point])
    }

    private func beginPendingDungeonPickupChoiceIfNeeded(for pickup: DungeonCardPickupDefinition) -> Bool {
        let liveEntries = Array(dungeonInventoryEntries.filter(\.hasUsesRemaining).prefix(9))
        guard liveEntries.count >= 9,
              !liveEntries.contains(where: { $0.playable == pickup.playable })
        else { return false }

        pendingDungeonPickupChoice = PendingDungeonPickupChoice(
            pickup: pickup,
            pickupUses: adjustedDungeonPickupUses(pickup.uses),
            discardCandidates: liveEntries
        )
        isAwaitingManualDiscardSelection = false
        boardTapPlayRequest = nil
        boardTapBasicMoveRequest = nil
        debugLog("満杯のため拾得カード選択待ち: \(pickup.playable.displayName) @\(pickup.point)")
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
        MoveCard.allCases
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

    private var brittleFloorPoints: Set<GridPoint> {
        var points: Set<GridPoint> = []
        for hazard in mode.dungeonRules?.hazards ?? [] {
            switch hazard {
            case .brittleFloor(let floorPoints):
                points.formUnion(floorPoints)
            case .damageTrap, .lavaTile, .healingTile:
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
            case .brittleFloor, .lavaTile, .healingTile:
                break
            }
        }
        return points
    }

    public var lavaTilePoints: Set<GridPoint> {
        var points: Set<GridPoint> = []
        for hazard in mode.dungeonRules?.hazards ?? [] {
            switch hazard {
            case .lavaTile(let lavaPoints, _):
                points.formUnion(lavaPoints)
            case .brittleFloor, .damageTrap, .healingTile:
                break
            }
        }
        return points
    }

    public var healingTilePoints: Set<GridPoint> {
        var points: Set<GridPoint> = []
        for hazard in mode.dungeonRules?.hazards ?? [] {
            switch hazard {
            case .healingTile(let healingPoints, _):
                points.formUnion(healingPoints)
            case .brittleFloor, .damageTrap, .lavaTile:
                break
            }
        }
        return points.subtracting(consumedHealingTilePoints)
    }

    private func applyDungeonHazards(along traversedPoints: [GridPoint]) -> Bool {
        guard mode.usesDungeonExit else { return false }

        for point in traversedPoints where applyDungeonHazard(at: point) {
            return true
        }
        return false
    }

    private func applyDungeonHazard(at point: GridPoint) -> Bool {
        guard mode.usesDungeonExit else { return false }
        let brittlePoints = brittleFloorPoints

        if brittlePoints.contains(point) {
            if collapsedFloorPoints.contains(point) {
                debugLog("崩落済みの床へ落下: \(point)")
                return triggerDungeonFall(at: point)
            } else if crackedFloorPoints.contains(point) {
                crackedFloorPoints.remove(point)
                collapsedFloorPoints.insert(point)
                debugLog("ひび割れ床が崩落: \(point)")
                return triggerDungeonFall(at: point)
            } else {
                crackedFloorPoints.insert(point)
                debugLog("床にひび割れ: \(point)")
            }
        }

        for hazard in mode.dungeonRules?.hazards ?? [] {
            switch hazard {
            case .damageTrap(let trapPoints, let damage) where trapPoints.contains(point):
                applyDungeonHazardDamage(max(damage, 1), at: point, logLabel: "罠")
                if shouldFailDungeonRun() {
                    finalizeElapsedTimeIfNeeded()
                    progress = .failed
                    return true
                }
            case .lavaTile(let lavaPoints, let damage) where lavaPoints.contains(point):
                applyDungeonHazardDamage(max(damage, 1), at: point, logLabel: "溶岩")
                if shouldFailDungeonRun() {
                    finalizeElapsedTimeIfNeeded()
                    progress = .failed
                    return true
                }
            case .healingTile(let healingPoints, let amount) where healingPoints.contains(point):
                guard !consumedHealingTilePoints.contains(point) else { break }
                let appliedHealing = max(amount, 1)
                dungeonHP += appliedHealing
                consumedHealingTilePoints.insert(point)
                debugLog("回復マスを踏みました: \(point), +\(appliedHealing), HP=\(dungeonHP)")
            case .brittleFloor, .damageTrap, .lavaTile, .healingTile:
                break
            }
        }
        return false
    }

    private func applyDungeonHazardDamage(_ damage: Int, at point: GridPoint, logLabel: String) {
        if isDamageBarrierActive {
            debugLog("\(logLabel)ダメージを障壁で無効化: \(point), 残り=\(damageBarrierTurnsRemaining)")
        } else if consumeDungeonHazardDamageMitigation() {
            debugLog("\(logLabel)ダメージを成長効果で無効化: \(point), 残り=\(hazardDamageMitigationsRemaining)")
        } else if logLabel == "罠", consumeDungeonRelicUse(.silverNeedle) {
            debugLog("銀の針で罠ダメージを無効化: \(point), HP=\(dungeonHP)")
        } else {
            let finalDamage = applyRelicDamageReductionIfNeeded(to: max(damage, 1))
            dungeonHP = max(dungeonHP - finalDamage, 0)
            debugLog("\(logLabel)ダメージ: \(point), -\(finalDamage), HP=\(dungeonHP)")
        }
    }

    private func applyLavaWaitDamageIfNeeded() -> Bool {
        guard mode.usesDungeonExit, progress == .playing, let current else { return false }
        for hazard in mode.dungeonRules?.hazards ?? [] {
            guard case .lavaTile(let lavaPoints, let damage) = hazard, lavaPoints.contains(current) else { continue }
            applyDungeonHazardDamage(max(damage, 1), at: current, logLabel: "溶岩滞在")
            if shouldFailDungeonRun() {
                finalizeElapsedTimeIfNeeded()
                progress = .failed
                return true
            }
            return false
        }
        return false
    }

    private func applyPoisonTrap() {
        poisonDamageTicksRemaining = poisonTrapDamageTicks
        poisonActionsUntilNextDamage = poisonTrapActionsPerDamage
        debugLog("毒罠を踏みました: 残り\(poisonDamageTicksRemaining)回, 次ダメージまで\(poisonActionsUntilNextDamage)行動")
    }

    private func applyPoisonTickAfterAction(skipsPoisonTick: Bool) -> Bool {
        guard poisonDamageTicksRemaining > 0 else { return false }
        if skipsPoisonTick {
            return false
        }
        poisonActionsUntilNextDamage = max(poisonActionsUntilNextDamage - 1, 0)
        guard poisonActionsUntilNextDamage == 0 else { return false }

        let damagePoint = current ?? GridPoint(x: 0, y: 0)
        applyDungeonHazardDamage(1, at: damagePoint, logLabel: "毒")
        poisonDamageTicksRemaining = max(poisonDamageTicksRemaining - 1, 0)
        poisonActionsUntilNextDamage = poisonDamageTicksRemaining > 0 ? poisonTrapActionsPerDamage : 0
        if shouldFailDungeonRun() {
            finalizeElapsedTimeIfNeeded()
            progress = .failed
            return true
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

    private func hasDungeonRelic(_ relicID: DungeonRelicID) -> Bool {
        dungeonRelicEntries.contains { $0.relicID == relicID }
    }

    private func hasDungeonCurse(_ curseID: DungeonCurseID) -> Bool {
        dungeonCurseEntries.contains { $0.curseID == curseID }
    }

    private func consumeDungeonRelicUse(_ relicID: DungeonRelicID) -> Bool {
        guard let index = dungeonRelicEntries.firstIndex(where: { $0.relicID == relicID && $0.remainingUses > 0 }) else {
            return false
        }
        dungeonRelicEntries[index].remainingUses -= 1
        return true
    }

    private func consumeDungeonCurseUse(_ curseID: DungeonCurseID) -> Bool {
        guard let index = dungeonCurseEntries.firstIndex(where: { $0.curseID == curseID && $0.remainingUses > 0 }) else {
            return false
        }
        dungeonCurseEntries[index].remainingUses -= 1
        return true
    }

    private func applyRelicDamageReductionIfNeeded(to damage: Int) -> Int {
        guard damage > 0 else { return 0 }
        var adjustedDamage = damage
        if consumeDungeonCurseUse(.thornMark) {
            adjustedDamage += 1
        }
        if hasDungeonCurse(.redChalice) {
            adjustedDamage += 1
        }
        guard consumeDungeonRelicUse(.crackedShield) else { return adjustedDamage }
        return max(adjustedDamage - 1, 0)
    }

    private func consumeDungeonEnemyDamageMitigation() -> Bool {
        guard mode.dungeonRules?.difficulty == .growth,
              enemyDamageMitigationsRemaining > 0
        else { return false }
        enemyDamageMitigationsRemaining -= 1
        return true
    }

    private func consumeDungeonMarkerDamageMitigation() -> Bool {
        guard mode.dungeonRules?.difficulty == .growth,
              markerDamageMitigationsRemaining > 0
        else { return false }
        markerDamageMitigationsRemaining -= 1
        return true
    }

    @discardableResult
    private func applyDungeonPostMoveChecks(
        along traversedPoints: [GridPoint],
        initialMarkerDamagePoints: Set<GridPoint>? = nil,
        paralysisTrapPoint: GridPoint? = nil,
        skipsPoisonTick: Bool
    ) -> Bool {
        guard mode.usesDungeonExit else { return false }
        guard progress == .playing, dungeonFallEvent == nil else { return true }
        updateDungeonExitLockIfNeeded()
        if current == mode.dungeonExitPoint, isDungeonExitUnlocked {
            finalizeElapsedTimeIfNeeded()
            progress = .cleared
            return true
        }
        if applyPoisonTickAfterAction(skipsPoisonTick: skipsPoisonTick) {
            return true
        }

        var phases: [DungeonEnemyTurnPhase] = []
        let enemyTurnCount = max(isShackled ? 2 : 1, paralysisTrapPoint == nil ? 1 : 2)
        for turnIndex in 0..<enemyTurnCount {
            let pendingMarkerDamagePoints = turnIndex == 0
                ? initialMarkerDamagePoints ?? enemyWarningPoints
                : enemyWarningPoints
            if consumeEnemyFreezeTurnIfNeeded() {
                continue
            }
            let enemyStatesBeforeTurn = enemyStates
            advanceEnemiesForDungeonTurn()
            let hpBeforeEnemyDamage = dungeonHP
            let enemyDamage = applyDungeonEnemyDamageIfNeeded(markerDamagePoints: pendingMarkerDamagePoints)
            if let phase = dungeonEnemyTurnPhase(
                before: enemyStatesBeforeTurn,
                after: enemyStates,
                hpBefore: hpBeforeEnemyDamage,
                hpAfter: dungeonHP,
                damage: enemyDamage
            ) {
                phases.append(phase)
            }
            if shouldFailDungeonRun() {
                publishDungeonEnemyTurnEventIfNeeded(
                    phases: phases,
                    paralysisTrapPoint: paralysisTrapPoint
                )
                finalizeElapsedTimeIfNeeded()
                progress = .failed
                return true
            }
        }
        publishDungeonEnemyTurnEventIfNeeded(
            phases: phases,
            paralysisTrapPoint: paralysisTrapPoint
        )
        consumeDamageBarrierTurnIfNeeded()
        return false
    }

    @discardableResult
    private func triggerDungeonFall(at point: GridPoint) -> Bool {
        if consumeDungeonRelicUse(.blackFeather) {
            debugLog("黒い羽根で落下を無効化: \(point), HP=\(dungeonHP)")
            return false
        }
        if isDamageBarrierActive {
            debugLog("床崩落ダメージを障壁で無効化: \(point), HP=\(dungeonHP), 残り=\(damageBarrierTurnsRemaining)")
        } else if consumeDungeonHazardDamageMitigation() {
            debugLog("床崩落ダメージを成長効果で無効化: \(point), HP=\(dungeonHP), 残り=\(hazardDamageMitigationsRemaining)")
        } else if consumeDungeonRelicUse(.silverNeedle) {
            debugLog("銀の針で床崩落ダメージを無効化: \(point), HP=\(dungeonHP)")
        } else {
            let finalDamage = applyRelicDamageReductionIfNeeded(to: 1)
            dungeonHP = max(dungeonHP - finalDamage, 0)
            debugLog("床崩落で下階へ落下: \(point), HP=\(dungeonHP)")
        }
        if dungeonHP <= 0 {
            finalizeElapsedTimeIfNeeded()
            progress = .failed
            return true
        }

        let sourceFloorIndex = mode.dungeonMetadataSnapshot?.runState?.currentFloorIndex ?? 0
        guard sourceFloorIndex > 0 else {
            finalizeElapsedTimeIfNeeded()
            progress = .failed
            debugLog("床崩落の落下先がないため失敗: \(point), sourceFloorIndex=\(sourceFloorIndex)")
            return true
        }
        dungeonFallEvent = DungeonFallEvent(
            point: point,
            sourceFloorIndex: sourceFloorIndex,
            destinationFloorIndex: sourceFloorIndex - 1,
            hpAfterDamage: dungeonHP
        )
        consumeDamageBarrierTurnIfNeeded()
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
        _ = applyDungeonFallLanding(at: landingPoint)
    }

    @discardableResult
    private func applyDungeonFallLanding(at point: GridPoint) -> Bool {
        guard brittleFloorPoints.contains(point) else { return false }

        if collapsedFloorPoints.contains(point) {
            debugLog("崩落済みの落下先から連鎖落下: \(point)")
            return triggerDungeonFall(at: point)
        } else if crackedFloorPoints.contains(point) {
            crackedFloorPoints.remove(point)
            collapsedFloorPoints.insert(point)
            debugLog("ひび割れ済みの落下先が崩落: \(point)")
            return triggerDungeonFall(at: point)
        } else {
            crackedFloorPoints.insert(point)
            debugLog("落下先の床にひび割れ: \(point)")
            return false
        }
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

    private func shouldMovingEnemyAttackBeforeMoving(_ enemy: EnemyState) -> Bool {
        guard let current else { return false }
        return attackOrContactPoints(for: enemy).contains(current)
    }

    private func advanceEnemiesForDungeonTurn() {
        guard mode.usesDungeonExit, !enemyStates.isEmpty else { return }

        var occupiedPoints = Set(enemyStates.map(\.position))
        for index in enemyStates.indices {
            switch enemyStates[index].behavior {
            case .guardPost, .watcher:
                break
            case .patrol(let path):
                guard !shouldMovingEnemyAttackBeforeMoving(enemyStates[index]) else { continue }
                let validPath = path.filter { isEnemyTraversable($0) }
                guard !validPath.isEmpty else { continue }
                let nextIndex = (enemyStates[index].patrolIndex + 1) % validPath.count
                let nextPoint = validPath[nextIndex]
                guard reserveEnemyDestination(
                    nextPoint,
                    from: enemyStates[index].position,
                    occupiedPoints: &occupiedPoints
                ) else {
                    continue
                }
                enemyStates[index].patrolIndex = nextIndex
                enemyStates[index].position = nextPoint
            case .rotatingWatcher:
                enemyStates[index].rotationIndex = (enemyStates[index].rotationIndex + 1) % 4
            case .chaser:
                guard !shouldMovingEnemyAttackBeforeMoving(enemyStates[index]) else { continue }
                guard let current,
                      let nextPoint = chaserNextStep(from: enemyStates[index].position, toward: current)
                else {
                    continue
                }
                guard reserveEnemyDestination(
                    nextPoint,
                    from: enemyStates[index].position,
                    occupiedPoints: &occupiedPoints
                ) else {
                    continue
                }
                enemyStates[index].position = nextPoint
            case .marker:
                if enemyStates[index].rotationIndex == Int.max {
                    enemyStates[index].rotationIndex = 0
                } else {
                    enemyStates[index].rotationIndex += 1
                }
            }
        }
    }

    private func reserveEnemyDestination(
        _ destination: GridPoint,
        from origin: GridPoint,
        occupiedPoints: inout Set<GridPoint>
    ) -> Bool {
        if destination == origin { return true }
        guard !occupiedPoints.contains(destination) else { return false }
        occupiedPoints.remove(origin)
        occupiedPoints.insert(destination)
        return true
    }

    private func patrolMovementPreview(
        for enemy: EnemyState,
        occupiedPoints: inout Set<GridPoint>
    ) -> EnemyPatrolMovementPreview? {
        guard case .patrol(let path) = enemy.behavior else { return nil }
        let validPath = path.filter { isEnemyTraversable($0) }
        guard !validPath.isEmpty else { return nil }

        let nextIndex = (enemy.patrolIndex + 1) % validPath.count
        let nextPoint = validPath[nextIndex]
        guard nextPoint != enemy.position else { return nil }
        guard reserveEnemyDestination(
            nextPoint,
            from: enemy.position,
            occupiedPoints: &occupiedPoints
        ) else {
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

    private func orderedEnemyMovementPreviews(
        in enemies: [EnemyState],
        matching shouldInclude: (EnemyState) -> Bool
    ) -> [EnemyPatrolMovementPreview] {
        var occupiedPoints = Set(enemies.map(\.position))
        var previews: [EnemyPatrolMovementPreview] = []

        for enemy in enemies {
            let preview: EnemyPatrolMovementPreview?
            switch enemy.behavior {
            case .patrol:
                preview = patrolMovementPreview(for: enemy, occupiedPoints: &occupiedPoints)
            case .chaser:
                preview = chaserMovementPreview(for: enemy, occupiedPoints: &occupiedPoints)
            case .guardPost, .watcher, .rotatingWatcher, .marker:
                preview = nil
            }

            if shouldInclude(enemy), let preview {
                previews.append(preview)
            }
        }

        return previews
    }

    private func patrolRailPreview(for enemy: EnemyState) -> EnemyPatrolRailPreview? {
        guard case .patrol(let path) = enemy.behavior else { return nil }
        let validPath = path.filter { isEnemyTraversable($0) }
        guard validPath.count > 1 else { return nil }
        guard validPath.indices.contains(enemy.patrolIndex),
              validPath[enemy.patrolIndex] == enemy.position
        else {
            return nil
        }

        return EnemyPatrolRailPreview(enemyID: enemy.id, path: validPath)
    }

    private func chaserMovementPreview(
        for enemy: EnemyState,
        occupiedPoints: inout Set<GridPoint>
    ) -> EnemyPatrolMovementPreview? {
        guard case .chaser = enemy.behavior,
              let current,
              let nextPoint = chaserNextStep(from: enemy.position, toward: current),
              nextPoint != enemy.position
        else {
            return nil
        }
        guard reserveEnemyDestination(
            nextPoint,
            from: enemy.position,
            occupiedPoints: &occupiedPoints
        ) else {
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

    @discardableResult
    private func applyDungeonEnemyDamageIfNeeded(markerDamagePoints: Set<GridPoint>) -> Int {
        guard mode.usesDungeonExit, let current else { return 0 }
        let damage = dungeonEnemyDamage(
            at: current,
            markerDamagePoints: markerDamagePoints,
            includesContact: true,
            includesMarkerWarning: true
        )
        var totalDamage = damage.enemy + damage.marker
        guard totalDamage > 0 else { return 0 }

        if isDamageBarrierActive {
            debugLog("敵/メテオダメージを障壁で無効化: 敵=\(damage.enemy), メテオ=\(damage.marker), 残り=\(damageBarrierTurnsRemaining)")
            return 0
        }

        if damage.enemy > 0, consumeDungeonEnemyDamageMitigation() {
            totalDamage -= damage.enemy
            debugLog("敵ダメージを成長効果で無効化: -\(damage.enemy), 残り=\(enemyDamageMitigationsRemaining)")
        }
        if damage.marker > 0, consumeDungeonMarkerDamageMitigation() {
            totalDamage -= damage.marker
            debugLog("メテオ着弾ダメージを成長効果で無効化: -\(damage.marker), 残り=\(markerDamageMitigationsRemaining)")
        }

        let finalDamage = applyRelicDamageReductionIfNeeded(to: totalDamage)
        guard finalDamage > 0 else { return 0 }
        dungeonHP = max(dungeonHP - finalDamage, 0)
        debugLog("敵の攻撃を受けました: -\(finalDamage), HP=\(dungeonHP)")
        return finalDamage
    }

    @discardableResult
    private func applyDungeonEnemyDangerDamageIfNeeded(at point: GridPoint) -> Bool {
        guard mode.usesDungeonExit else { return false }
        let damage = dungeonEnemyDamage(
            at: point,
            markerDamagePoints: [],
            includesContact: false,
            includesMarkerWarning: false
        )
        var totalDamage = damage.enemy + damage.marker

        guard totalDamage > 0 else { return false }
        if isDamageBarrierActive {
            debugLog("敵の攻撃範囲通過ダメージを障壁で無効化: \(point), 残り=\(damageBarrierTurnsRemaining)")
            return false
        }
        if damage.enemy > 0, consumeDungeonEnemyDamageMitigation() {
            totalDamage -= damage.enemy
            debugLog("敵の攻撃範囲通過ダメージを成長効果で無効化: \(point), 残り=\(enemyDamageMitigationsRemaining)")
        }
        let finalDamage = applyRelicDamageReductionIfNeeded(to: totalDamage)
        guard finalDamage > 0 else { return false }
        dungeonHP = max(dungeonHP - finalDamage, 0)
        debugLog("敵の攻撃範囲を通過しました: \(point), -\(finalDamage), HP=\(dungeonHP)")
        if shouldFailDungeonRun() {
            finalizeElapsedTimeIfNeeded()
            progress = .failed
            return true
        }
        return false
    }

    private func dungeonEnemyDamage(
        at point: GridPoint,
        markerDamagePoints: Set<GridPoint>,
        includesContact: Bool,
        includesMarkerWarning: Bool
    ) -> (enemy: Int, marker: Int) {
        guard !isEnemyFreezeActive else { return (0, 0) }
        var enemyDamage = 0
        var markerDamage = 0

        for enemy in enemyStates {
            if enemyDangerPoints(for: enemy).contains(point) {
                enemyDamage += enemy.damage
            } else if includesContact, enemy.position == point {
                enemyDamage += enemy.damage
            } else if includesMarkerWarning, case .marker = enemy.behavior, markerDamagePoints.contains(point) {
                markerDamage += enemy.damage
            }
        }
        return (enemyDamage, markerDamage)
    }

    private func dungeonEnemyTurnPhase(
        before: [EnemyState],
        after: [EnemyState],
        hpBefore: Int,
        hpAfter: Int,
        damage: Int
    ) -> DungeonEnemyTurnPhase? {
        guard mode.usesDungeonExit, (!before.isEmpty || !after.isEmpty) else { return nil }

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

        guard !transitions.isEmpty || damage > 0 else { return nil }
        return DungeonEnemyTurnPhase(
            transitions: transitions,
            attackedPlayer: damage > 0,
            hpBefore: hpBefore,
            hpAfter: hpAfter
        )
    }

    private func publishDungeonEnemyTurnEventIfNeeded(
        phases: [DungeonEnemyTurnPhase],
        paralysisTrapPoint: GridPoint?
    ) {
        guard mode.usesDungeonExit else { return }
        guard !phases.isEmpty || paralysisTrapPoint != nil else { return }
        dungeonEnemyTurnEvent = DungeonEnemyTurnEvent(
            phases: phases,
            isParalysisRest: paralysisTrapPoint != nil,
            paralysisTrapPoint: paralysisTrapPoint
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

    private func consumeEnemyFreezeTurnIfNeeded() -> Bool {
        guard enemyFreezeTurnsRemaining > 0 else { return false }
        enemyFreezeTurnsRemaining -= 1
        debugLog("凍結中のため敵ターンを停止: 残り=\(enemyFreezeTurnsRemaining)")
        return true
    }

    private func consumeDamageBarrierTurnIfNeeded() {
        guard damageBarrierTurnsRemaining > 0 else { return }
        damageBarrierTurnsRemaining -= 1
        debugLog("障壁の残り回数を消費: 残り=\(damageBarrierTurnsRemaining)")
    }

    private func attackOrContactPoints(for enemy: EnemyState) -> Set<GridPoint> {
        var points = enemyDangerPoints(for: enemy)
        points.insert(enemy.position)
        return points
    }

    private func enemyDangerPoints(for enemy: EnemyState) -> Set<GridPoint> {
        guard !isEnemyFreezeActive else { return [] }
        return dangerPoints(for: [enemy])
    }

    private func dangerPoints(for enemies: [EnemyState]) -> Set<GridPoint> {
        var danger: Set<GridPoint> = []
        for enemy in enemies {
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
                    if isEnemyTraversable(point) {
                        danger.insert(point)
                    }
                }
            case .watcher(let direction, _):
                insertLineOfSightDanger(
                    from: enemy.position,
                    direction: direction,
                    into: &danger
                )
            case .rotatingWatcher:
                guard let direction = rotatingWatcherDirection(for: enemy) else { break }
                insertLineOfSightDanger(
                    from: enemy.position,
                    direction: direction,
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
            guard case .marker(_, let range) = enemy.behavior else { continue }
            warning.formUnion(meteorWarningPoints(for: enemy, targetCount: range, enemyStates: enemies))
        }
        return warning
    }

    private func meteorWarningPoints(
        for enemy: EnemyState,
        targetCount: Int,
        enemyStates: [EnemyState]? = nil
    ) -> Set<GridPoint> {
        let enemyStates = enemyStates ?? self.enemyStates
        let occupiedEnemyPoints = Set(enemyStates.map(\.position))
        let protectedPoints = protectedMeteorWarningPoints()
        let clampedTargetCount = max(targetCount, 1)
        var candidates = board.allTraversablePoints.filter { point in
            point != current
                && !occupiedEnemyPoints.contains(point)
                && !protectedPoints.contains(point)
                && !collapsedFloorPoints.contains(point)
        }

        if candidates.count < clampedTargetCount {
            candidates = board.allTraversablePoints.filter { point in
                point != current
                    && !occupiedEnemyPoints.contains(point)
                    && !collapsedFloorPoints.contains(point)
            }
        }

        guard !candidates.isEmpty else { return [] }
        var randomizer = DungeonRefillRandomGenerator(seed: meteorWarningSeed(for: enemy))
        var shuffled = candidates.sorted { lhs, rhs in
            if lhs.y != rhs.y { return lhs.y < rhs.y }
            return lhs.x < rhs.x
        }
        for index in shuffled.indices.reversed() {
            let swapIndex = Int(randomizer.next() % UInt64(index + 1))
            shuffled.swapAt(index, swapIndex)
        }

        var selected = Set(shuffled.prefix(min(clampedTargetCount, shuffled.count)))
        keepAtLeastOneSafeBasicStop(outside: &selected)
        return selected
    }

    private func protectedMeteorWarningPoints() -> Set<GridPoint> {
        var points: Set<GridPoint> = []
        if let exit = mode.dungeonExitPoint {
            points.insert(exit)
        }
        if let unlockPoint = mode.dungeonRules?.exitLock?.unlockPoint, !isDungeonExitUnlocked {
            points.insert(unlockPoint)
        }
        return points
    }

    private func keepAtLeastOneSafeBasicStop(outside warning: inout Set<GridPoint>) {
        let safeStops = availableBasicOrthogonalMoves()
            .map(\.destination)
            .filter { !warning.contains($0) }
        guard safeStops.isEmpty else { return }

        if let rescuePoint = availableBasicOrthogonalMoves()
            .map(\.destination)
            .first(where: { warning.contains($0) }) {
            warning.remove(rescuePoint)
        }
    }

    private func meteorWarningSeed(for enemy: EnemyState) -> UInt64 {
        var seed = mode.dungeonMetadataSnapshot?.runState?.cardVariationSeed ?? mode.deckSeed ?? 1
        seed ^= UInt64(board.size) &* 0x9E37_79B9_7F4A_7C15
        seed ^= UInt64(max(moveCount, 0) + 1) &* 0xBF58_476D_1CE4_E5B9
        seed ^= UInt64(enemy.rotationIndex == Int.max ? Int.max : enemy.rotationIndex + 1) &* 0x94D0_49BB_1331_11EB
        seed ^= UInt64(enemy.position.x + 31) &* 1099511628211
        seed ^= UInt64(enemy.position.y + 37) &* 1469598103934665603
        for scalar in enemy.id.unicodeScalars {
            seed = seed &* 1099511628211 &+ UInt64(scalar.value)
        }
        return seed == 0 ? 1 : seed
    }

    private func chaserNextStep(from origin: GridPoint, toward target: GridPoint) -> GridPoint? {
        guard origin != target,
              board.contains(origin),
              board.contains(target),
              isEnemyTraversable(target)
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
                guard isEnemyTraversable(next),
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

    private func rotatingWatcherDirection(for enemy: EnemyState, offset: Int = 0) -> MoveVector? {
        guard case .rotatingWatcher(let initialDirection, let rotationDirection, _) = enemy.behavior,
              let initial = EnemyBehavior.normalizedOrthogonalDirection(initialDirection),
              let initialIndex = EnemyBehavior.rotatingWatcherClockwiseDirections.firstIndex(of: initial)
        else {
            return nil
        }
        let step = rotationDirection == .clockwise ? 1 : -1
        let rawIndex = initialIndex + (enemy.rotationIndex + offset) * step
        let directions = EnemyBehavior.rotatingWatcherClockwiseDirections
        let wrappedIndex = ((rawIndex % directions.count) + directions.count) % directions.count
        return directions[wrappedIndex]
    }

    private func insertLineOfSightDanger(
        from origin: GridPoint,
        direction: MoveVector,
        into danger: inout Set<GridPoint>
    ) {
        let dx = direction.dx == 0 ? 0 : (direction.dx > 0 ? 1 : -1)
        let dy = direction.dy == 0 ? 0 : (direction.dy > 0 ? 1 : -1)
        guard dx != 0 || dy != 0 else { return }

        var step = 1
        while true {
            let point = origin.offset(dx: dx * step, dy: dy * step)
            guard isEnemyTraversable(point) else { break }
            danger.insert(point)
            step += 1
        }
    }

    private func isEnemyTraversable(_ point: GridPoint) -> Bool {
        board.contains(point) && board.isTraversable(point) && !collapsedFloorPoints.contains(point)
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
              shouldExpandForMovementStoppingTileResolution(moveCard),
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

        let hasIntermediateStoppingTile = expanded.dropLast().contains { point in
            board.effect(at: point)?.stopsMovementCard == true
        }
        return hasIntermediateStoppingTile ? expanded : rawPath
    }

    private func shouldExpandForMovementStoppingTileResolution(_ move: MoveCard) -> Bool {
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

        if pendingTargetedSupportCard != nil {
            _ = playTargetedSupportCard(at: point)
            return
        }

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
        boardTapBasicMoveRequest = nil
        pendingTargetedSupportCard = nil
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
                impassablePoints: mode.impassableTilePoints,
                tileEffects: mode.tileEffects
            )
        } else {
            core.board = Board(
                size: mode.boardSize,
                initialVisitedPoints: visitedPoints,
                impassablePoints: mode.impassableTilePoints,
                tileEffects: mode.tileEffects
            )
        }
        core.current = resolvedCurrent
        core.moveCount = 0
        core.penaltyCount = 0
        core.hasRevisitedTile = false
        core.dungeonHP = mode.dungeonRules?.failureRule.initialHP ?? 0
        core.hazardDamageMitigationsRemaining = mode.dungeonMetadataSnapshot?.runState?.hazardDamageMitigationsRemaining ?? 0
        core.enemyDamageMitigationsRemaining = mode.dungeonMetadataSnapshot?.runState?.enemyDamageMitigationsRemaining ?? 0
        core.markerDamageMitigationsRemaining = mode.dungeonMetadataSnapshot?.runState?.markerDamageMitigationsRemaining ?? 0
        core.enemyFreezeTurnsRemaining = 0
        core.damageBarrierTurnsRemaining = 0
        core.enemyStates = mode.dungeonRules?.enemies.map(EnemyState.init(definition:)) ?? []
        let currentFloorIndex = mode.dungeonMetadataSnapshot?.runState?.currentFloorIndex ?? 0
        core.crackedFloorPoints = mode.dungeonMetadataSnapshot?.runState?.crackedFloorPoints(for: currentFloorIndex) ?? []
        core.collapsedFloorPoints = mode.dungeonMetadataSnapshot?.runState?.collapsedFloorPoints(for: currentFloorIndex) ?? []
        core.consumedHealingTilePoints = []
        core.isDungeonExitUnlocked = mode.dungeonRules?.exitLock == nil
        core.dungeonExitUnlockEvent = nil
        core.dungeonFallEvent = nil
        core.dungeonEnemyTurnEvent = nil
        core.pendingTargetedSupportCard = nil
        core.progress = (resolvedCurrent == nil && mode.requiresSpawnSelection) ? .awaitingSpawn : .playing

        if core.usesDungeonInventoryCards {
        core.dungeonInventoryEntries = mode.dungeonMetadataSnapshot?.runState?.rewardInventoryEntries ?? []
        core.collectedDungeonCardPickupIDs = []
        core.pendingDungeonPickupChoice = nil
        core.dungeonRelicEntries = mode.dungeonMetadataSnapshot?.runState?.relicEntries ?? []
        core.dungeonCurseEntries = mode.dungeonMetadataSnapshot?.runState?.curseEntries ?? []
        core.collectedDungeonRelicPickupIDs = mode.dungeonMetadataSnapshot?.runState?.collectedDungeonRelicPickupIDs ?? []
        core.dungeonRelicAcquisitionPresentations = []
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
        core.boardTapBasicMoveRequest = nil
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

    /// テスト用にダンジョン床状態を直接差し替える
    func overrideDungeonFloorStateForTesting(
        cracked: Set<GridPoint>,
        collapsed: Set<GridPoint>
    ) {
        crackedFloorPoints = cracked
        collapsedFloorPoints = collapsed
    }

    @discardableResult
    func addDungeonInventoryCardForTesting(
        _ card: MoveCard,
        pickupUses: Int = 0,
        rewardUses: Int = 0
    ) -> Bool {
        addDungeonInventoryCard(card, pickupUses: pickupUses, rewardUses: rewardUses)
    }

    @discardableResult
    func addDungeonInventorySupportCardForTesting(
        _ support: SupportCard,
        pickupUses: Int = 0,
        rewardUses: Int = 0
    ) -> Bool {
        addDungeonInventorySupportCard(support, pickupUses: pickupUses, rewardUses: rewardUses)
    }

    /// テスト用にダンジョン HP を直接差し替える
    func overrideDungeonHPForTesting(_ hp: Int) {
        dungeonHP = max(hp, 0)
    }

    /// テスト用に敵凍結ターンを直接差し替える
    func overrideEnemyFreezeTurnsRemainingForTesting(_ turns: Int) {
        enemyFreezeTurnsRemaining = max(turns, 0)
    }

    /// テスト用に障壁ターンを直接差し替える
    func overrideDamageBarrierTurnsRemainingForTesting(_ turns: Int) {
        damageBarrierTurnsRemaining = max(turns, 0)
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
