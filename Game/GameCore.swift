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
public struct DungeonExitUnlockEvent: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let exitPoint: GridPoint
    public let unlockPoint: GridPoint

    public init(id: UUID = UUID(), exitPoint: GridPoint, unlockPoint: GridPoint) {
        self.id = id
        self.exitPoint = exitPoint
        self.unlockPoint = unlockPoint
    }
}

/// 鍵を持たずに施錠中の階段へ到達したことを UI へ知らせるイベント
public struct DungeonLockedExitReachEvent: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let exitPoint: GridPoint

    public init(id: UUID = UUID(), exitPoint: GridPoint) {
        self.id = id
        self.exitPoint = exitPoint
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

/// 致死ダメージを受けた時、過去階層へ復活することを UI へ知らせるイベント
public struct DungeonRewindReviveEvent: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let sourceFloorIndex: Int
    public let destinationFloorIndex: Int
    public let hpAfterRevive: Int

    public init(
        id: UUID = UUID(),
        sourceFloorIndex: Int,
        destinationFloorIndex: Int,
        hpAfterRevive: Int = 1
    ) {
        self.id = id
        self.sourceFloorIndex = max(sourceFloorIndex, 0)
        self.destinationFloorIndex = max(destinationFloorIndex, 0)
        self.hpAfterRevive = max(hpAfterRevive, 1)
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

private enum RelicBreakTrapTarget {
    case relic(Int)
    case curse(Int)
}

private enum DungeonDamageCategory: Equatable {
    case trap
    case lava
    case fall
    case watcher
    case patrol
    case chaser
    case meteor
    case other
}

private struct DungeonEnemyDamageComponent {
    let category: DungeonDamageCategory
    let amount: Int
    let source: String
    let isMarker: Bool
}

private let poisonTrapDamageTicks = 3
private let poisonTrapActionsPerDamage = 3
private let staggerTrapForcedMoveCount = 2
private let staggerAutoMoveLimitPerAction = 32

private extension EnemyBehavior {
    var isMeteorWarningBehavior: Bool {
        switch self {
        case .marker, .targetedMarker:
            return true
        case .guardPost, .patrol, .watcher, .rotatingWatcher, .chaser:
            return false
        }
    }
}

private extension TileEffect {
    var isDarknessScoutHiddenTrap: Bool {
        switch self {
        case .slow, .shackleTrap, .poisonTrap, .illusionTrap, .staggerTrap, .relicBreakTrap,
             .discardRandomHand, .discardAllMoveCards, .discardAllSupportCards, .discardAllHands:
            return true
        case .warp, .returnWarp, .shuffleHand, .blast, .swamp, .preserveCard:
            return false
        }
    }
}

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
    var remainingPathAfterPickupChoice: [GridPoint]?
    var postMoveTileEffect: PostMoveTileEffect?
    var preservesPlayedCard: Bool
    var paralysisTrapPoint: GridPoint?
    var triggeredPoisonTrap: Bool
}

/// 盤面表示用に切り出した見張り系レーザーの現在状態
public struct WatcherLaserDisplay: Equatable, Identifiable, Sendable {
    public let enemyID: String
    public let origin: GridPoint
    public let direction: MoveVector
    public let dangerPoints: [GridPoint]

    public var id: String { enemyID }

    public init(enemyID: String, origin: GridPoint, direction: MoveVector, dangerPoints: [GridPoint]) {
        self.enemyID = enemyID
        self.origin = origin
        self.direction = direction
        self.dangerPoints = dangerPoints
    }
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

public struct DungeonFatigueIndicatorState: Equatable {
    public let filledCount: Int
    public let totalCount: Int
    public let isDamageStep: Bool

    public init(filledCount: Int, totalCount: Int, isDamageStep: Bool) {
        self.totalCount = max(totalCount, 1)
        self.filledCount = min(max(filledCount, 0), self.totalCount)
        self.isDamageStep = isDamageStep
    }
}

/// ゲーム進行を統括するクラス
/// - 盤面操作・手札管理・ペナルティ処理・スコア計算を担当する

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public final class GameCore: ObservableObject {
    private static let overtimeFatigueInterval = 3

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
    /// 塔インベントリ同期時にも適用する現在の手札並び順
    private var handOrderingStrategy: HandOrderingStrategy = .insertionOrder

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
    /// ダークネスの呪文で見張り系レーザーを封じているかどうか
    @Published public private(set) var isWatcherLaserSuppressed: Bool = false
    /// レール破壊の呪文で巡回兵のレール移動を封じているかどうか
    @Published public private(set) var isPatrolRailDestroyed: Bool = false
    /// フライの呪文で危険床系ギミックを無効化しているかどうか
    @Published public private(set) var isFlySpellActive: Bool = false
    /// 足枷罠を踏み、その階の間だけ敵ターンが重くなっているかどうか
    @Published public private(set) var isShackled: Bool = false
    /// 幻惑罠を踏み、その階の間だけ移動カードの正体が分からなくなっているかどうか
    @Published public private(set) var isIlluded: Bool = false
    /// 千鳥足罠により、敵ターン後に強制ランダム移動する残り回数
    @Published public private(set) var staggerForcedMovesRemaining: Int = 0
    /// このフロアで溶岩マスへ実際に踏み込んだかどうか
    @Published public private(set) var didStepOnLavaThisFloor: Bool = false
    /// このフロアでプレイヤー行動によって倒した敵数
    @Published public private(set) var currentFloorDefeatedEnemyCount: Int = 0
    /// このフロア開始時点で敵がいたかどうか
    @Published public private(set) var didStartCurrentFloorWithEnemies: Bool = false
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
    /// 取得済みのフロア内専用アイテム ID
    @Published public private(set) var collectedDungeonSpecialPickupIDs: Set<String> = []
    /// 塔ラン中だけ有効な遺物一覧
    @Published public private(set) var dungeonRelicEntries: [DungeonRelicEntry] = []
    /// 塔ラン中だけ有効な呪い遺物一覧
    @Published public private(set) var dungeonCurseEntries: [DungeonCurseEntry] = []
    /// 取得済みの宝箱 ID
    @Published public private(set) var collectedDungeonRelicPickupIDs: Set<String> = []
    /// 通常遺物と呪い遺物の効果を現在のラン解決へ反映するかどうか
    @Published public private(set) var areDungeonRelicAndCurseEffectsEnabled: Bool = true
    /// UI へ提示するレリック/呪い遺物/宝箱結果の取得イベント
    @Published public private(set) var dungeonRelicAcquisitionPresentations: [DungeonRelicAcquisitionPresentation] = []
    /// プレイヤーが死因や回復、遺物取得を振り返るためのラン履歴
    @Published public private(set) var dungeonRunLogEntries: [DungeonRunLogEntry] = []
    /// 所持枠が満杯で床落ちカードの取捨選択を待っている状態
    @Published public private(set) var pendingDungeonPickupChoice: PendingDungeonPickupChoice?
    private var pendingDungeonMovementContinuation: PendingDungeonMovementContinuation?
    /// 怪しい宝箱の選択を待っている状態
    @Published public private(set) var pendingDungeonRelicPickupChoice: PendingDungeonRelicPickupChoice?
    private var pendingDefeatEnemyTurnSkip = false
    private var currentDungeonInventoryKindLimit: Int?
    /// 塔ダンジョン出口が現在有効かどうか
    @Published public private(set) var isDungeonExitUnlocked: Bool = true
    /// 出口解錠演出用の単発イベント
    @Published public private(set) var dungeonExitUnlockEvent: DungeonExitUnlockEvent?
    /// 施錠中の出口へ到達したことを知らせる単発イベント
    @Published public private(set) var dungeonLockedExitReachEvent: DungeonLockedExitReachEvent?
    /// ひび割れ床崩落による下階落下イベント
    @Published public private(set) var dungeonFallEvent: DungeonFallEvent?
    /// 逆巻きの砂時計による過去階層復活イベント
    @Published public private(set) var dungeonRewindReviveEvent: DungeonRewindReviveEvent?
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

    public func updateDungeonRelicAndCurseEffects(enabled: Bool) {
        guard areDungeonRelicAndCurseEffectsEnabled != enabled else { return }
        areDungeonRelicAndCurseEffectsEnabled = enabled
        if !enabled, moveCount == 0 {
            enemyFreezeTurnsRemaining = 0
            damageBarrierTurnsRemaining = 0
            isFlySpellActive = false
        }
    }

    /// 塔ダンジョンの疲労インジケーター表示状態
    public var dungeonFatigueIndicatorState: DungeonFatigueIndicatorState? {
        guard mode.usesDungeonExit else { return nil }
        guard let turnLimit = effectiveDungeonTurnLimit else { return nil }
        guard moveCount >= turnLimit else { return nil }

        let overtime = max(moveCount - turnLimit, 0)
        guard overtime > 0 else {
            return DungeonFatigueIndicatorState(
                filledCount: 0,
                totalCount: Self.overtimeFatigueInterval,
                isDamageStep: false
            )
        }

        let isDamageStep = overtime == 1 || (overtime - 1).isMultiple(of: Self.overtimeFatigueInterval)
        let filledCount = isDamageStep ? Self.overtimeFatigueInterval : (overtime - 1) % Self.overtimeFatigueInterval
        return DungeonFatigueIndicatorState(
            filledCount: filledCount,
            totalCount: Self.overtimeFatigueInterval,
            isDamageStep: isDamageStep
        )
    }
    /// 遺物補正を反映した現在フロアの手数上限
    public var effectiveDungeonTurnLimit: Int? {
        guard let baseTurnLimit = mode.dungeonRules?.failureRule.turnLimit else { return nil }
        var adjustment = 0
        if hasDungeonRelic(.chippedHourglass) {
            adjustment += 3
        }
        if hasDungeonRelic(.copperHourglass) {
            adjustment += 2
        }
        if hasDungeonRelic(.stargazerHourglass) {
            adjustment += 5
        }
        if hasDungeonRelic(.travelerBoots) {
            adjustment += 1
        }
        if hasDungeonCurse(.rustyChain) {
            adjustment -= 2
        }
        if hasDungeonCurse(.cursedCrown) {
            adjustment -= 5
        }
        if hasDungeonCurse(.crackedCompass) {
            adjustment -= 3
        }
        if hasDungeonCurse(.contractCodex) {
            adjustment -= 5
        }
        if hasDungeonCurse(.lastStandShield) {
            adjustment -= 4
        }
        if hasDungeonCurse(.oilSoakedBoots) {
            adjustment += 3
        }
        if mode.dungeonRules?.exitLock != nil,
           isDungeonExitUnlocked,
           hasDungeonCurse(.upsideDownKey) {
            adjustment -= 2
        }
        return max(baseTurnLimit + adjustment, 1)
    }
    /// 敵本体を除く、現在の敵状態を基準にした攻撃範囲マス
    public var enemyDangerPoints: Set<GridPoint> {
        enemyDangerPoints(forDisplayedEnemyStates: enemyStates)
    }
    /// 敵本体を除く、現在表示する攻撃範囲マス
    public var enemyDangerDisplayPoints: Set<GridPoint> {
        enemyDangerDisplayPoints(forDisplayedEnemyStates: enemyStates)
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
    /// 表示中の敵状態を基準にした現在の攻撃範囲マス
    public func enemyDangerDisplayPoints(forDisplayedEnemyStates enemyStates: [EnemyState]) -> Set<GridPoint> {
        guard !isEnemyFreezeActive else { return [] }
        return dangerPoints(for: enemyStates)
    }
    /// 表示中の敵状態を基準にした見張り系レーザーのみの危険範囲
    public func watcherLaserDangerDisplayPoints(forDisplayedEnemyStates enemyStates: [EnemyState]) -> Set<GridPoint> {
        guard !isEnemyFreezeActive else { return [] }
        let watcherStates = enemyStates.filter { enemy in
            switch enemy.behavior {
            case .watcher, .rotatingWatcher:
                return true
            case .guardPost, .patrol, .chaser, .marker, .targetedMarker:
                return false
            }
        }
        return dangerPoints(for: watcherStates)
    }
    /// 表示中の敵状態を基準にした見張り系以外の現在の攻撃範囲マス
    public func nonWatcherEnemyDangerDisplayPoints(forDisplayedEnemyStates enemyStates: [EnemyState]) -> Set<GridPoint> {
        guard !isEnemyFreezeActive else { return [] }
        let nonWatcherStates = enemyStates.filter { enemy in
            switch enemy.behavior {
            case .watcher, .rotatingWatcher:
                return false
            case .guardPost, .patrol, .chaser, .marker, .targetedMarker:
                return true
            }
        }
        return dangerPoints(for: nonWatcherStates)
    }
    /// 表示中の敵状態を基準にした見張り系レーザーの描画情報
    public func watcherLaserDisplays(forDisplayedEnemyStates enemyStates: [EnemyState]) -> [WatcherLaserDisplay] {
        guard !isEnemyFreezeActive, !isWatcherLaserSuppressed else { return [] }
        return enemyStates.compactMap { enemy in
            let direction: MoveVector
            switch enemy.behavior {
            case .watcher(let watcherDirection, _):
                direction = watcherDirection
            case .rotatingWatcher:
                guard let rotatingDirection = rotatingWatcherDirection(for: enemy) else { return nil }
                direction = rotatingDirection
            case .guardPost, .patrol, .chaser, .marker, .targetedMarker:
                return nil
            }
            let dangerPoints = lineOfSightDangerPoints(from: enemy.position, direction: direction)
            guard !dangerPoints.isEmpty else { return nil }
            return WatcherLaserDisplay(
                enemyID: enemy.id,
                origin: enemy.position,
                direction: normalizedLaserDirection(direction),
                dangerPoints: dangerPoints
            )
        }
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
        guard !isPatrolRailDestroyed else { return [] }
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
        guard !isPatrolRailDestroyed else { return [] }
        return enemyStates.compactMap { patrolRailPreview(for: $0) }
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
    /// ダークネスの呪文で見張り/回転見張りの射線が消えているかどうか
    public var isDarknessSpellActive: Bool {
        isWatcherLaserSuppressed
    }
    /// レール破壊の呪文で巡回兵のレール移動が止まっているかどうか
    public var isRailBreakSpellActive: Bool {
        isPatrolRailDestroyed
    }
    /// フライの呪文で危険床系ギミックが無効化されているかどうか
    public var isFlySpellSuppressionActive: Bool {
        isFlySpellActive
    }
    /// フライの呪文が対象にする危険床系ギミックが現在フロアに存在するかどうか
    public var hasFlySpellTargetTiles: Bool {
        hasFlySpellTargetHazard || mode.tileEffects.values.contains { $0.isBlockedByFlySpell }
    }
    /// 暗闇フロアの視界制限が現在有効かどうか
    public var isDungeonDarknessActive: Bool {
        mode.dungeonRules?.isDarknessEnabled == true
    }
    /// 予備のたいまつを持っている暗闇フロアでは視界を少し広げる
    public var dungeonDarknessVisionRadius: Int {
        let relicBonus =
            (hasDungeonRelic(.spareTorch) ? 1 : 0) +
            (hasDungeonRelic(.smallLantern) ? 1 : 0)
        let cursePenalty = hasDungeonCurse(.wetTinder) ? 1 : 0
        return max(min(1 + relicBonus, 3) - cursePenalty, 1)
    }
    /// 暗闇スカウト系レリックで視界外でも見える未取得拾得カード
    public var darknessRevealedDungeonCardPickupPoints: Set<GridPoint> {
        guard hasDungeonRelic(.nightCardLens) else { return [] }
        return Set(activeDungeonCardPickups.map(\.point))
    }
    /// 暗闇スカウト系レリックで視界外でも見えるトゲ床
    public var darknessRevealedThornTrapPoints: Set<GridPoint> {
        guard hasDungeonRelic(.thornScoutLens) else { return [] }
        return damageTrapPoints
    }
    /// 暗闇スカウト系レリックで視界外でも見える溶岩
    public var darknessRevealedLavaTilePoints: Set<GridPoint> {
        guard hasDungeonRelic(.magmaScoutLens) else { return [] }
        return lavaTilePoints
    }
    /// 暗闇スカウト系レリックで視界外でも見える隠し罠
    public var darknessRevealedHiddenTrapPoints: Set<GridPoint> {
        guard hasDungeonRelic(.trapScoutLens) else { return [] }
        let tileEffectTrapPoints = mode.tileEffectOverrides.reduce(into: Set<GridPoint>()) { result, entry in
            guard entry.value.isDarknessScoutHiddenTrap else { return }
            result.insert(entry.key)
        }
        return hpHalvingTrapPoints.union(tileEffectTrapPoints)
    }
    /// 暗闇スカウト系レリックで視界外でも見える敵
    public var darknessRevealedEnemyPoints: Set<GridPoint> {
        guard hasDungeonRelic(.enemyScoutLens) else { return [] }
        return Set(enemyStates.map(\.position))
    }
    /// 現在の行動で消費する手数
    private var currentActionMoveCost: Int {
        hasDungeonCurse(.heavyBell) && moveCount == 0 ? 2 : 1
    }
    /// 足枷状態で進む敵ターン数
    private var currentShackleEnemyTurnCount: Int {
        guard isShackled else { return 1 }
        return hasDungeonCurse(.ironShackle) ? 3 : 2
    }
    private var hasFlySpellTargetHazard: Bool {
        (mode.dungeonRules?.hazards ?? []).contains { hazard in
            switch hazard {
            case .brittleFloor, .damageTrap, .hpHalvingTrap, .lavaTile:
                return true
            case .healingTile:
                return false
            }
        }
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
        guard mode.dungeonRules?.difficulty == .growth || mode.dungeonRules?.difficulty == .roguelike,
              let relicPickups = mode.dungeonRules?.relicPickups
        else { return [] }
        return relicPickups.filter { !collectedDungeonRelicPickupIDs.contains($0.id) }
    }
    /// まだ盤面上に残っている塔専用アイテム
    public var activeDungeonSpecialPickups: [DungeonSpecialPickupDefinition] {
        guard mode.dungeonRules?.difficulty == .roguelike,
              let specialPickups = mode.dungeonRules?.specialPickups
        else { return [] }
        return specialPickups.filter { !collectedDungeonSpecialPickupIDs.contains($0.id) }
    }
    public var isAwaitingDungeonPickupChoice: Bool {
        pendingDungeonPickupChoice != nil || pendingDungeonRelicPickupChoice != nil
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
    /// 基本移動固定枠を除いた、塔ラン中の通常カード所持上限
    public var dungeonInventoryKindLimit: Int {
        effectiveDungeonInventoryKindLimit
    }
    /// 呪い遺物などの一時効果を反映した通常カード所持上限
    public var effectiveDungeonInventoryKindLimit: Int {
        guard usesDungeonInventoryCards else { return 0 }
        let baseLimit = min(max(currentDungeonInventoryKindLimit ?? mode.dungeonMetadataSnapshot?.runState?.dungeonInventoryKindLimit ?? 9, 1), 9)
        let curseBonus = hasDungeonCurse(.ploverContract) ? 1 : 0
        return min(baseLimit + curseBonus, 10)
    }
    /// 基本移動を現在のランで使えるかどうか
    public var allowsCurrentBasicMove: Bool {
        mode.dungeonRules?.allowsBasicOrthogonalMove == true && !hasDungeonCurse(.ploverContract)
    }
    /// 千鳥の契約により手札0枚の自動千鳥足が発動する状態かどうか
    public var isEmptyHandStaggerAutoActive: Bool {
        guard mode.usesDungeonExit, hasDungeonCurse(.ploverContract) else { return false }
        return usesDungeonInventoryCards
            ? dungeonInventoryEntries.filter(\.hasUsesRemaining).isEmpty
            : handStacks.isEmpty
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
            isWatcherLaserSuppressed: isWatcherLaserSuppressed,
            isPatrolRailDestroyed: isPatrolRailDestroyed,
            isFlySpellActive: isFlySpellActive,
            isShackled: isShackled,
            isIlluded: isIlluded,
            staggerForcedMovesRemaining: staggerForcedMovesRemaining,
            didStepOnLavaThisFloor: didStepOnLavaThisFloor,
            poisonDamageTicksRemaining: poisonDamageTicksRemaining,
            poisonActionsUntilNextDamage: poisonActionsUntilNextDamage,
            enemyStates: enemyStates,
            crackedFloorPoints: crackedFloorPoints,
            collapsedFloorPoints: collapsedFloorPoints,
            consumedHealingTilePoints: consumedHealingTilePoints,
            dungeonInventoryEntries: dungeonInventoryEntries,
            collectedDungeonCardPickupIDs: collectedDungeonCardPickupIDs,
            collectedDungeonSpecialPickupIDs: collectedDungeonSpecialPickupIDs,
            dungeonRelicEntries: dungeonRelicEntries,
            dungeonCurseEntries: dungeonCurseEntries,
            collectedDungeonRelicPickupIDs: collectedDungeonRelicPickupIDs,
            dungeonRunLogEntries: dungeonRunLogEntries,
            isDungeonExitUnlocked: isDungeonExitUnlocked,
            pendingDungeonPickupChoice: pendingDungeonPickupChoice,
            pendingDungeonMovementContinuation: pendingDungeonMovementContinuation,
            pendingDungeonRelicPickupChoice: pendingDungeonRelicPickupChoice
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
        isWatcherLaserSuppressed = snapshot.isWatcherLaserSuppressed
        isPatrolRailDestroyed = snapshot.isPatrolRailDestroyed
        isFlySpellActive = snapshot.isFlySpellActive
        isShackled = snapshot.isShackled
        isIlluded = snapshot.isIlluded
        staggerForcedMovesRemaining = snapshot.staggerForcedMovesRemaining
        didStepOnLavaThisFloor = snapshot.didStepOnLavaThisFloor
        poisonDamageTicksRemaining = snapshot.poisonDamageTicksRemaining
        poisonActionsUntilNextDamage = snapshot.poisonActionsUntilNextDamage
        enemyStates = snapshot.enemyStates
        let restoredCollapsedFloorPoints = initialCollapsedBrittleFloorPoints.union(validCollapsedPoints)
        crackedFloorPoints = initialCrackedBrittleFloorPoints
            .union(snapshot.crackedFloorPoints)
            .subtracting(restoredCollapsedFloorPoints)
        collapsedFloorPoints = restoredCollapsedFloorPoints
        consumedHealingTilePoints = validConsumedHealingPoints
        dungeonInventoryEntries = snapshot.dungeonInventoryEntries
        collectedDungeonCardPickupIDs = snapshot.collectedDungeonCardPickupIDs
        collectedDungeonSpecialPickupIDs = snapshot.collectedDungeonSpecialPickupIDs
        let restoredBaseInventoryLimit = mode.dungeonMetadataSnapshot?.runState?.dungeonInventoryKindLimit ?? 9
        currentDungeonInventoryKindLimit = min(
            restoredBaseInventoryLimit + (collectedDungeonSpecialPickupIDs.contains { $0.contains("-hand-expansion") } ? 1 : 0),
            9
        )
        dungeonRelicEntries = snapshot.dungeonRelicEntries
        dungeonCurseEntries = snapshot.dungeonCurseEntries
        collectedDungeonRelicPickupIDs = snapshot.collectedDungeonRelicPickupIDs
        dungeonRelicAcquisitionPresentations = []
        dungeonRunLogEntries = snapshot.dungeonRunLogEntries
        pendingDungeonPickupChoice = snapshot.pendingDungeonPickupChoice
        pendingDungeonMovementContinuation = snapshot.pendingDungeonMovementContinuation
        pendingDungeonRelicPickupChoice = snapshot.pendingDungeonRelicPickupChoice
        isDungeonExitUnlocked = snapshot.isDungeonExitUnlocked
        dungeonExitUnlockEvent = nil
        dungeonLockedExitReachEvent = nil
        dungeonFallEvent = nil
        dungeonRewindReviveEvent = nil
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
        logDungeonPlayEvent(
            "session_restore",
            [
                ("snapshotFloor", String(snapshot.floorIndex + 1)),
                ("visited", String(validVisitedPoints.count)),
                ("inventory", diagnosticInventoryDescription),
                ("pendingPickup", pendingDungeonPickupChoice?.pickup.playable.displayName ?? "nil")
            ]
        )
        return true
    }

    /// 手札の並び順設定を更新し、必要であれば再ソートする
    /// - Parameter newStrategy: ユーザーが選択した並び替え方式
    public func updateHandOrderingStrategy(_ newStrategy: HandOrderingStrategy) {
        handOrderingStrategy = newStrategy
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
        case .singleAnnihilationSpell, .freezeSpell:
            return !enemyStates.isEmpty
        case .annihilationSpell:
            return true
        case .barrierSpell:
            return true
        case .darknessSpell:
            return hasWatcherLaserEnemy && !isWatcherLaserSuppressed
        case .railBreakSpell:
            return hasPatrolRailEnemy && !isPatrolRailDestroyed
        case .flySpell:
            return hasFlySpellTargetTiles && !isFlySpellActive
        case .antidote:
            return poisonDamageTicksRemaining > 0
        case .panacea:
            return poisonDamageTicksRemaining > 0 || isShackled || isIlluded || staggerForcedMovesRemaining > 0
        }
    }

    public func beginTargetedSupportCardSelection(at index: Int) -> Bool {
        guard progress == .playing, handStacks.indices.contains(index), current != nil else { return false }
        guard pendingDungeonPickupChoice == nil else { return false }
        guard pendingDungeonRelicPickupChoice == nil else { return false }
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
              pendingDungeonRelicPickupChoice == nil,
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
        let previousMoveCount = consumeSupportCard(at: stackIndex)
        let defeatedEnemy = enemyStates.remove(at: enemyIndex)
        registerDungeonEnemyDefeats([defeatedEnemy])
        finishSupportCardTurn(
            initialMarkerDamagePoints: pendingMarkerDamagePoints,
            previousMoveCount: previousMoveCount
        )
        checkDeadlockAndApplyPenaltyIfNeeded()
        debugLog("補助カード 消滅の呪文: \(point) の敵を消滅")
        return true
    }

    /// 手札インデックスの補助カードを使用する
    public func playSupportCard(at index: Int) {
        guard progress == .playing, handStacks.indices.contains(index), current != nil else { return }
        guard pendingDungeonPickupChoice == nil else { return }
        guard pendingDungeonRelicPickupChoice == nil else { return }
        guard !isAwaitingManualDiscardSelection else { return }
        guard let card = handStacks[index].topCard, let support = card.supportCard else { return }
        guard isSupportCardUsable(in: handStacks[index]) else { return }

        switch support {
        case .refillEmptySlots:
            let pendingMarkerDamagePoints = enemyWarningPoints
            let wasDungeonInventoryFull = isDungeonInventoryFullForRefill
            let previousMoveCount = consumeSupportCard(at: index)
            if !wasDungeonInventoryFull {
                refillDungeonEmptySlotsWithRandomMoveCards()
            }
            finishSupportCardTurn(
                initialMarkerDamagePoints: pendingMarkerDamagePoints,
                previousMoveCount: previousMoveCount
            )
            checkDeadlockAndApplyPenaltyIfNeeded()
            debugLog("補助カード 補給: 空き手札枠へ移動カードを補給")
        case .singleAnnihilationSpell:
            _ = beginTargetedSupportCardSelection(at: index)
        case .annihilationSpell:
            let pendingMarkerDamagePoints = enemyWarningPoints
            let previousMoveCount = consumeSupportCard(at: index)
            let defeatedEnemies = enemyStates
            enemyStates.removeAll()
            registerDungeonEnemyDefeats(defeatedEnemies)
            removeMimicRelicPickupsForAnnihilationSpell()
            finishSupportCardTurn(
                initialMarkerDamagePoints: pendingMarkerDamagePoints,
                previousMoveCount: previousMoveCount
            )
            checkDeadlockAndApplyPenaltyIfNeeded()
            debugLog("補助カード 全滅の呪文: 現在フロアの敵をすべて消滅")
        case .freezeSpell:
            guard !enemyStates.isEmpty else { return }
            let pendingMarkerDamagePoints = enemyWarningPoints
            let previousMoveCount = consumeSupportCard(at: index)
            enemyFreezeTurnsRemaining = max(enemyFreezeTurnsRemaining, 3)
            finishSupportCardTurn(
                initialMarkerDamagePoints: pendingMarkerDamagePoints,
                previousMoveCount: previousMoveCount
            )
            checkDeadlockAndApplyPenaltyIfNeeded()
            debugLog("補助カード 凍結の呪文: 敵ターンを3回停止")
        case .barrierSpell:
            let pendingMarkerDamagePoints = enemyWarningPoints
            let previousMoveCount = consumeSupportCard(at: index)
            damageBarrierTurnsRemaining = max(damageBarrierTurnsRemaining, 3)
            finishSupportCardTurn(
                initialMarkerDamagePoints: pendingMarkerDamagePoints,
                previousMoveCount: previousMoveCount
            )
            checkDeadlockAndApplyPenaltyIfNeeded()
            debugLog("補助カード 障壁の呪文: HPダメージを3回無効化")
        case .darknessSpell:
            guard hasWatcherLaserEnemy, !isWatcherLaserSuppressed else { return }
            let pendingMarkerDamagePoints = enemyWarningPoints
            let previousMoveCount = consumeSupportCard(at: index)
            isWatcherLaserSuppressed = true
            finishSupportCardTurn(
                initialMarkerDamagePoints: pendingMarkerDamagePoints,
                previousMoveCount: previousMoveCount
            )
            checkDeadlockAndApplyPenaltyIfNeeded()
            debugLog("補助カード ダークネスの呪文: 見張り系レーザーをこの階で無効化")
        case .railBreakSpell:
            guard hasPatrolRailEnemy, !isPatrolRailDestroyed else { return }
            let pendingMarkerDamagePoints = enemyWarningPoints
            let previousMoveCount = consumeSupportCard(at: index)
            isPatrolRailDestroyed = true
            finishSupportCardTurn(
                initialMarkerDamagePoints: pendingMarkerDamagePoints,
                previousMoveCount: previousMoveCount
            )
            checkDeadlockAndApplyPenaltyIfNeeded()
            debugLog("補助カード レール破壊の呪文: 巡回兵のレール移動をこの階で無効化")
        case .flySpell:
            guard hasFlySpellTargetTiles, !isFlySpellActive else { return }
            let pendingMarkerDamagePoints = enemyWarningPoints
            let previousMoveCount = consumeSupportCard(at: index)
            isFlySpellActive = true
            finishSupportCardTurn(
                initialMarkerDamagePoints: pendingMarkerDamagePoints,
                previousMoveCount: previousMoveCount
            )
            checkDeadlockAndApplyPenaltyIfNeeded()
            debugLog("補助カード フライの呪文: 危険床系ギミックをこの階で無効化")
        case .antidote:
            let pendingMarkerDamagePoints = enemyWarningPoints
            let previousMoveCount = consumeSupportCard(at: index)
            clearPoisonStatus()
            finishSupportCardTurn(
                initialMarkerDamagePoints: pendingMarkerDamagePoints,
                previousMoveCount: previousMoveCount
            )
            checkDeadlockAndApplyPenaltyIfNeeded()
            debugLog("補助カード 解毒薬: 毒状態を解除")
        case .panacea:
            let pendingMarkerDamagePoints = enemyWarningPoints
            let previousMoveCount = consumeSupportCard(at: index)
            clearPoisonStatus()
            isShackled = false
            isIlluded = false
            staggerForcedMovesRemaining = 0
            finishSupportCardTurn(
                initialMarkerDamagePoints: pendingMarkerDamagePoints,
                previousMoveCount: previousMoveCount
            )
            checkDeadlockAndApplyPenaltyIfNeeded()
            debugLog("補助カード 万能薬: 状態異常を解除")
        }
    }

    /// 幻惑中に `？` として押された移動カードを、現在合法な候補だけからランダムに解決する
    public func randomIllusionMove() -> ResolvedCardMove? {
        guard isIlluded, progress == .playing, current != nil else { return nil }
        let moveCandidates = availableMoves()
        guard !moveCandidates.isEmpty else { return nil }

        let groupedByCard = Dictionary(grouping: moveCandidates, by: { $0.card.id })
        let cardGroups = groupedByCard.values
            .compactMap { moves -> [ResolvedCardMove]? in
                guard moves.first?.card.moveCard != nil else { return nil }
                return moves
            }
            .sorted { lhs, rhs in
                guard let left = lhs.first, let right = rhs.first else { return lhs.count < rhs.count }
                if left.stackIndex != right.stackIndex { return left.stackIndex < right.stackIndex }
                return left.card.id.uuidString < right.card.id.uuidString
            }
        guard !cardGroups.isEmpty else { return nil }

        var generator = DungeonRefillRandomGenerator(seed: illusionMoveSeed())
        let groupIndex = Int(generator.next() % UInt64(cardGroups.count))
        let moves = cardGroups[groupIndex].sorted { lhs, rhs in
            if lhs.destination.y != rhs.destination.y { return lhs.destination.y < rhs.destination.y }
            if lhs.destination.x != rhs.destination.x { return lhs.destination.x < rhs.destination.x }
            if lhs.moveVector.dy != rhs.moveVector.dy { return lhs.moveVector.dy < rhs.moveVector.dy }
            return lhs.moveVector.dx < rhs.moveVector.dx
        }
        let moveIndex = Int(generator.next() % UInt64(moves.count))
        return moves[moveIndex]
    }

    private func clearPoisonStatus() {
        poisonDamageTicksRemaining = 0
        poisonActionsUntilNextDamage = 0
    }

    private func finishSupportCardTurn(
        initialMarkerDamagePoints: Set<GridPoint>,
        previousMoveCount: Int
    ) {
        dungeonEnemyTurnEvent = nil
        guard progress == .playing else { return }
        if applyLavaWaitDamageIfNeeded() { return }
        _ = applyDungeonPostMoveChecks(
            along: [],
            initialMarkerDamagePoints: initialMarkerDamagePoints,
            paralysisTrapPoint: nil,
            skipsPoisonTick: false,
            previousMoveCount: previousMoveCount
        )
    }

    private func consumeSupportCard(at index: Int) -> Int {
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
        let previousMoveCount = moveCount
        moveCount += currentActionMoveCost
        if !usesDungeonInventoryCards {
            rebuildHandAndNext(preferredInsertionIndices: removedIndex.map { [$0] } ?? [])
        }
        return previousMoveCount
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
        guard pendingDungeonRelicPickupChoice == nil else { return }
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
        logDungeonPlayEvent(
            "move_start",
            [
                ("input", "card"),
                ("card", cardMove.displayName),
                ("stack", String(validatedMove.stackIndex)),
                ("from", PlayDiagnosticLog.describe(currentPosition)),
                ("path", PlayDiagnosticLog.describe(validatedMove.path)),
                ("to", PlayDiagnosticLog.describe(validatedMove.destination)),
                ("vector", diagnosticVectorDescription(validatedMove.moveVector))
            ]
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
        publishImmediateMovementPresentationEventsIfNeeded(
            from: presentationSteps,
            actualTraversedPath: actualTraversedPath
        )
        let previousMoveCount = moveCount
        moveCount += currentActionMoveCost
        if let remainingPath = movementResult.remainingPathAfterPickupChoice {
            pendingDungeonMovementContinuation = PendingDungeonMovementContinuation(
                inputKind: .card,
                playedMoveCard: cardMove,
                remainingPath: remainingPath,
                traversedPath: actualTraversedPath,
                encounteredRevisit: encounteredRevisit,
                detectedEffects: detectedEffects,
                postMoveTileEffect: tileEffect(from: postMoveTileEffect),
                preservesPlayedCard: preservesPlayedCard,
                initialMarkerDamagePoints: pendingMarkerDamagePoints,
                paralysisTrapPoint: paralysisTrapPoint,
                triggeredPoisonTrap: movementResult.triggeredPoisonTrap,
                previousMoveCount: previousMoveCount
            )
            return
        }

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
            if usesDungeonInventoryCards {
                syncDungeonInventoryHandStacks()
            } else {
                refreshHandStateFromManager()
            }
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
        logDungeonPlayEvent(
            "move_resolved",
            [
                ("input", "card"),
                ("card", cardMove.displayName),
                ("from", PlayDiagnosticLog.describe(currentPosition)),
                ("path", PlayDiagnosticLog.describe(actualTraversedPath)),
                ("to", PlayDiagnosticLog.describe(finalPosition)),
                ("effects", diagnosticEffectDescription(detectedEffects)),
                ("preserved", String(shouldPreservePlayedCard)),
                ("revisit", String(encounteredRevisit))
            ]
        )

        if progress == .playing, dungeonFallEvent == nil {
            applyPostMoveTileEffect(postMoveTileEffect, preserving: preservedCard)
        }

        if applyDungeonPostMoveChecks(
            along: actualTraversedPath,
            initialMarkerDamagePoints: pendingMarkerDamagePoints,
            paralysisTrapPoint: paralysisTrapPoint,
            skipsPoisonTick: movementResult.triggeredPoisonTrap,
            previousMoveCount: previousMoveCount
        ) { return }
        if resolveAutomaticStaggerMoveIfNeeded() { return }

        // 手詰まりチェック（全カード盤外ならペナルティ）
        checkDeadlockAndApplyPenaltyIfNeeded()

        // デバッグ: 現在の盤面を表示
#if DEBUG
        // デバッグ目的でのみ盤面を出力する
        board.debugDump(current: current)
#endif
    }

    private func logDungeonPlayEvent(
        _ event: String,
        _ fields: [(String, String)] = [],
        file: String = #file,
        line: Int = #line,
        function: String = #function
    ) {
        guard mode.usesDungeonExit else { return }
        PlayDiagnosticLog.emit(
            event: event,
            fields: diagnosticBaseFields + fields,
            file: file,
            line: line,
            function: function
        )
    }

    private var diagnosticBaseFields: [(String, String)] {
        [
            ("dungeon", mode.dungeonMetadataSnapshot?.dungeonID ?? mode.identifier.rawValue),
            ("floor", diagnosticFloorDescription),
            ("turn", String(moveCount)),
            ("hp", String(dungeonHP)),
            ("pos", PlayDiagnosticLog.describe(current)),
            ("progress", String(describing: progress)),
            ("hand", handStacks.debugSummaryJoined(emptyPlaceholder: "none")),
            ("relics", diagnosticRelicDescription),
            ("curses", diagnosticCurseDescription)
        ]
    }

    private var diagnosticFloorDescription: String {
        guard let floorIndex = mode.dungeonMetadataSnapshot?.runState?.currentFloorIndex else { return "nil" }
        return String(floorIndex + 1)
    }

    private var dungeonRunLogFloorNumber: Int {
        (mode.dungeonMetadataSnapshot?.runState?.currentFloorIndex ?? 0) + 1
    }

    private func appendDungeonRunLog(
        kind: DungeonRunLogEntry.Kind,
        point: GridPoint? = nil,
        hpBefore: Int? = nil,
        hpAfter: Int? = nil,
        message: String
    ) {
        guard mode.usesDungeonExit else { return }
        let nextSequence = (dungeonRunLogEntries.last?.sequence ?? -1) + 1
        let entry = DungeonRunLogEntry(
            sequence: nextSequence,
            floorNumber: dungeonRunLogFloorNumber,
            turn: moveCount,
            point: point ?? current,
            kind: kind,
            hpBefore: hpBefore,
            hpAfter: hpAfter,
            message: message
        )
        dungeonRunLogEntries = DungeonRunLogEntry.trimmed(dungeonRunLogEntries + [entry])
    }

    private func appendDungeonHPChangeLog(
        kind: DungeonRunLogEntry.Kind,
        source: String,
        point: GridPoint? = nil,
        hpBefore: Int,
        hpAfter: Int
    ) {
        let delta = hpAfter - hpBefore
        guard delta != 0 else { return }
        let sign = delta > 0 ? "+" : ""
        appendDungeonRunLog(
            kind: kind,
            point: point,
            hpBefore: hpBefore,
            hpAfter: hpAfter,
            message: "\(source)でHP \(sign)\(delta)（HP \(hpBefore)→\(hpAfter)）"
        )
    }

    private var diagnosticSeedDescription: String {
        if let seed = mode.dungeonMetadataSnapshot?.runState?.cardVariationSeed {
            return String(seed)
        }
        if let seed = mode.deckSeed {
            return String(seed)
        }
        return "nil"
    }

    private var diagnosticInventoryDescription: String {
        let entries = dungeonInventoryEntries.filter(\.hasUsesRemaining)
        guard !entries.isEmpty else { return "none" }
        return entries.map { entry in
            "\(entry.playable.displayName):\(entry.totalUses)"
        }.joined(separator: ",")
    }

    private var diagnosticRelicDescription: String {
        guard !dungeonRelicEntries.isEmpty else { return "none" }
        return dungeonRelicEntries.map { entry in
            "\(entry.relicID.rawValue):\(entry.remainingUses)"
        }.joined(separator: ",")
    }

    private var diagnosticCurseDescription: String {
        guard !dungeonCurseEntries.isEmpty else { return "none" }
        return dungeonCurseEntries.map { entry in
            "\(entry.curseID.rawValue):\(entry.remainingUses)"
        }.joined(separator: ",")
    }

    private func diagnosticEffectDescription(_ effects: [MovementResolution.AppliedEffect]) -> String {
        guard !effects.isEmpty else { return "none" }
        return effects.map { effect in
            "\(String(describing: effect.effect))@\(PlayDiagnosticLog.describe(effect.point))"
        }.joined(separator: ",")
    }

    private func diagnosticEnemyDescription(_ enemies: [EnemyState]) -> String {
        guard !enemies.isEmpty else { return "none" }
        return enemies.map { enemy in
            "\(enemy.id)@\(PlayDiagnosticLog.describe(enemy.position))"
        }.joined(separator: ",")
    }

    private func diagnosticVectorDescription(_ vector: MoveVector) -> String {
        "(\(vector.dx),\(vector.dy))"
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
        guard pendingDungeonRelicPickupChoice == nil else { return }
        guard !isAwaitingManualDiscardSelection else { return }
        guard allowsCurrentBasicMove else { return }
        guard availableBasicOrthogonalMoves().contains(where: { candidate in
            candidate.moveVector == basicMove.moveVector &&
                candidate.path == basicMove.path &&
                candidate.destination == basicMove.destination
        }) else { return }

        boardTapBasicMoveRequest = nil
        debugLog(
            "基本移動 \(currentPosition) -> \(basicMove.destination) (vector=\(basicMove.moveVector))"
        )
        logDungeonPlayEvent(
            "move_start",
            [
                ("input", "basic"),
                ("from", PlayDiagnosticLog.describe(currentPosition)),
                ("path", PlayDiagnosticLog.describe(basicMove.path)),
                ("to", PlayDiagnosticLog.describe(basicMove.destination)),
                ("vector", diagnosticVectorDescription(basicMove.moveVector))
            ]
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
        publishImmediateMovementPresentationEventsIfNeeded(
            from: presentationSteps,
            actualTraversedPath: actualTraversedPath
        )
        let previousMoveCount = moveCount
        moveCount += currentActionMoveCost
        if let remainingPath = movementResult.remainingPathAfterPickupChoice {
            pendingDungeonMovementContinuation = PendingDungeonMovementContinuation(
                inputKind: .basic,
                remainingPath: remainingPath,
                traversedPath: actualTraversedPath,
                encounteredRevisit: encounteredRevisit,
                detectedEffects: detectedEffects,
                postMoveTileEffect: tileEffect(from: postMoveTileEffect),
                preservesPlayedCard: false,
                initialMarkerDamagePoints: pendingMarkerDamagePoints,
                paralysisTrapPoint: paralysisTrapPoint,
                triggeredPoisonTrap: movementResult.triggeredPoisonTrap,
                previousMoveCount: previousMoveCount
            )
            return
        }

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
        logDungeonPlayEvent(
            "move_resolved",
            [
                ("input", "basic"),
                ("from", PlayDiagnosticLog.describe(currentPosition)),
                ("path", PlayDiagnosticLog.describe(actualTraversedPath)),
                ("to", PlayDiagnosticLog.describe(finalPosition)),
                ("effects", diagnosticEffectDescription(detectedEffects)),
                ("preserved", "false"),
                ("revisit", String(encounteredRevisit))
            ]
        )

        if applyDungeonPostMoveChecks(
            along: actualTraversedPath,
            initialMarkerDamagePoints: pendingMarkerDamagePoints,
            paralysisTrapPoint: paralysisTrapPoint,
            skipsPoisonTick: movementResult.triggeredPoisonTrap,
            previousMoveCount: previousMoveCount
        ) { return }
        _ = resolveAutomaticStaggerMoveIfNeeded()
    }

    @discardableResult
    private func resolveAutomaticStaggerMoveIfNeeded(depth: Int = 0) -> Bool {
        guard mode.usesDungeonExit,
              progress == .playing,
              pendingDungeonPickupChoice == nil,
              pendingDungeonRelicPickupChoice == nil,
              dungeonFallEvent == nil,
              current != nil
        else { return false }
        guard depth < staggerAutoMoveLimitPerAction else {
            finalizeElapsedTimeIfNeeded()
            progress = .failed
            appendDungeonRunLog(kind: .blocked, message: "千鳥足が止まらず攻略に失敗")
            return true
        }

        let hasForcedMove = staggerForcedMovesRemaining > 0
        let hasNoPlayableCards = isEmptyHandStaggerAutoActive
        guard hasForcedMove || hasNoPlayableCards else { return false }

        if hasForcedMove {
            staggerForcedMovesRemaining = max(staggerForcedMovesRemaining - 1, 0)
        }
        playAutomaticStaggerMove(reason: hasForcedMove ? "trap" : "emptyHand", depth: depth)
        return true
    }

    private func playAutomaticStaggerMove(reason: String, depth: Int) {
        guard progress == .playing, let currentPosition = current else { return }
        let moves = availableStaggerMoves()
        guard !moves.isEmpty else {
            finalizeElapsedTimeIfNeeded()
            progress = .failed
            appendDungeonRunLog(kind: .blocked, point: currentPosition, message: "千鳥足で動けるマスがなく攻略に失敗")
            logDungeonPlayEvent(
                "run_end",
                [
                    ("reason", "staggerNoDestination"),
                    ("point", PlayDiagnosticLog.describe(currentPosition))
                ]
            )
            return
        }

        var generator = DungeonRefillRandomGenerator(seed: staggerMoveSeed(reason: reason, depth: depth))
        let move = moves[Int(generator.next() % UInt64(moves.count))]
        let pendingMarkerDamagePoints = enemyWarningPoints
        guard let movementResult = processMovementPath(move.path, startingAt: currentPosition) else { return }
        let finalPosition = movementResult.finalPosition
        let actualTraversedPath = movementResult.actualTraversedPath
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
        publishImmediateMovementPresentationEventsIfNeeded(
            from: presentationSteps,
            actualTraversedPath: actualTraversedPath
        )

        let previousMoveCount = moveCount
        moveCount += currentActionMoveCost
        if let remainingPath = movementResult.remainingPathAfterPickupChoice {
            pendingDungeonMovementContinuation = PendingDungeonMovementContinuation(
                inputKind: .basic,
                remainingPath: remainingPath,
                traversedPath: actualTraversedPath,
                encounteredRevisit: movementResult.encounteredRevisit,
                detectedEffects: detectedEffects,
                postMoveTileEffect: tileEffect(from: postMoveTileEffect),
                preservesPlayedCard: false,
                initialMarkerDamagePoints: pendingMarkerDamagePoints,
                paralysisTrapPoint: paralysisTrapPoint,
                triggeredPoisonTrap: movementResult.triggeredPoisonTrap,
                previousMoveCount: previousMoveCount
            )
            return
        }
        if movementResult.encounteredRevisit {
            hasRevisitedTile = true
            if mode.revisitPenaltyCost > 0 {
                penaltyCount += mode.revisitPenaltyCost
            }
        }
        announceRemainingTiles()
        if progress == .playing, dungeonFallEvent == nil {
            applyPostMoveTileEffect(postMoveTileEffect, preserving: nil)
        }
        logDungeonPlayEvent(
            "move_resolved",
            [
                ("input", "stagger"),
                ("reason", reason),
                ("from", PlayDiagnosticLog.describe(currentPosition)),
                ("path", PlayDiagnosticLog.describe(actualTraversedPath)),
                ("to", PlayDiagnosticLog.describe(finalPosition)),
                ("effects", diagnosticEffectDescription(detectedEffects)),
                ("revisit", String(movementResult.encounteredRevisit))
            ]
        )
        if applyDungeonPostMoveChecks(
            along: actualTraversedPath,
            initialMarkerDamagePoints: pendingMarkerDamagePoints,
            paralysisTrapPoint: paralysisTrapPoint,
            skipsPoisonTick: movementResult.triggeredPoisonTrap,
            previousMoveCount: previousMoveCount
        ) { return }
        if !resolveAutomaticStaggerMoveIfNeeded(depth: depth + 1) {
            checkDeadlockAndApplyPenaltyIfNeeded()
        }
    }

    public func availableStaggerMoves(current currentOverride: GridPoint? = nil) -> [BasicOrthogonalMove] {
        guard let origin = currentOverride ?? current else { return [] }
        let vectors = [
            MoveVector(dx: -1, dy: 1),
            MoveVector(dx: 0, dy: 1),
            MoveVector(dx: 1, dy: 1),
            MoveVector(dx: -1, dy: 0),
            MoveVector(dx: 1, dy: 0),
            MoveVector(dx: -1, dy: -1),
            MoveVector(dx: 0, dy: -1),
            MoveVector(dx: 1, dy: -1)
        ]
        return vectors.compactMap { vector in
            let destination = origin.offset(dx: vector.dx, dy: vector.dy)
            guard board.contains(destination), board.isTraversable(destination) else { return nil }
            return BasicOrthogonalMove(
                moveVector: vector,
                resolution: MovementResolution(path: [destination], finalPosition: destination)
            )
        }
        .sorted { lhs, rhs in
            if lhs.destination.y != rhs.destination.y {
                return lhs.destination.y < rhs.destination.y
            }
            return lhs.destination.x < rhs.destination.x
        }
    }

    private func continuePendingDungeonMovementIfNeeded() {
        guard let continuation = pendingDungeonMovementContinuation,
              pendingDungeonPickupChoice == nil,
              pendingDungeonRelicPickupChoice == nil,
              progress == .playing,
              let currentPosition = current
        else { return }

        pendingDungeonMovementContinuation = nil
        var combinedTraversedPath = continuation.traversedPath
        var combinedEncounteredRevisit = continuation.encounteredRevisit
        var combinedDetectedEffects = continuation.detectedEffects
        var combinedPostMoveTileEffect = postMoveTileEffect(from: continuation.postMoveTileEffect)
        var combinedPreservesPlayedCard = continuation.preservesPlayedCard
        var combinedParalysisTrapPoint = continuation.paralysisTrapPoint
        var combinedTriggeredPoisonTrap = continuation.triggeredPoisonTrap

        if !continuation.remainingPath.isEmpty {
            guard let movementResult = processMovementPath(continuation.remainingPath, startingAt: currentPosition) else { return }
            let actualTraversedPath = movementResult.actualTraversedPath
            let finalPosition = movementResult.finalPosition
            let presentationSteps = movementResult.presentationSteps
            lastMovementResolution = MovementResolution(
                path: actualTraversedPath,
                finalPosition: finalPosition,
                appliedEffects: movementResult.detectedEffects,
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
            publishImmediateMovementPresentationEventsIfNeeded(
                from: presentationSteps,
                actualTraversedPath: actualTraversedPath
            )

            combinedTraversedPath += actualTraversedPath
            combinedEncounteredRevisit = combinedEncounteredRevisit || movementResult.encounteredRevisit
            combinedDetectedEffects += movementResult.detectedEffects
            combinedPostMoveTileEffect = mergedPostMoveTileEffect(
                combinedPostMoveTileEffect,
                movementResult.postMoveTileEffect
            )
            combinedPreservesPlayedCard = combinedPreservesPlayedCard || movementResult.preservesPlayedCard
            combinedParalysisTrapPoint = movementResult.paralysisTrapPoint ?? combinedParalysisTrapPoint
            combinedTriggeredPoisonTrap = combinedTriggeredPoisonTrap || movementResult.triggeredPoisonTrap

            if let remainingPath = movementResult.remainingPathAfterPickupChoice {
                pendingDungeonMovementContinuation = PendingDungeonMovementContinuation(
                    inputKind: continuation.inputKind,
                    playedMoveCard: continuation.playedMoveCard,
                    remainingPath: remainingPath,
                    traversedPath: combinedTraversedPath,
                    encounteredRevisit: combinedEncounteredRevisit,
                    detectedEffects: combinedDetectedEffects,
                    postMoveTileEffect: tileEffect(from: combinedPostMoveTileEffect),
                    preservesPlayedCard: combinedPreservesPlayedCard,
                    initialMarkerDamagePoints: continuation.initialMarkerDamagePoints,
                    paralysisTrapPoint: combinedParalysisTrapPoint,
                    triggeredPoisonTrap: combinedTriggeredPoisonTrap,
                    previousMoveCount: continuation.previousMoveCount
                )
                return
            }
        }

        if combinedEncounteredRevisit {
            hasRevisitedTile = true
            if mode.revisitPenaltyCost > 0 {
                penaltyCount += mode.revisitPenaltyCost
            }
        }

        announceRemainingTiles()
        if continuation.inputKind == .card,
           let playedMoveCard = continuation.playedMoveCard,
           !combinedPreservesPlayedCard {
            consumeDungeonInventoryCard(playedMoveCard)
        } else if continuation.inputKind == .card, combinedPreservesPlayedCard {
            syncDungeonInventoryHandStacks()
        }

        let preservedCard = combinedPreservesPlayedCard
            ? continuation.playedMoveCard.map { DealtCard(move: $0) }
            : nil
        if progress == .playing, dungeonFallEvent == nil {
            applyPostMoveTileEffect(combinedPostMoveTileEffect, preserving: preservedCard)
        }

        logResolvedDungeonMovementContinuation(
            continuation,
            traversedPath: combinedTraversedPath,
            detectedEffects: combinedDetectedEffects,
            preservesPlayedCard: combinedPreservesPlayedCard,
            encounteredRevisit: combinedEncounteredRevisit
        )

        if applyDungeonPostMoveChecks(
            along: combinedTraversedPath,
            initialMarkerDamagePoints: continuation.initialMarkerDamagePoints,
            paralysisTrapPoint: combinedParalysisTrapPoint,
            skipsPoisonTick: combinedTriggeredPoisonTrap,
            previousMoveCount: continuation.previousMoveCount
        ) { return }
        if resolveAutomaticStaggerMoveIfNeeded() { return }

        checkDeadlockAndApplyPenaltyIfNeeded()
    }

    private func logResolvedDungeonMovementContinuation(
        _ continuation: PendingDungeonMovementContinuation,
        traversedPath: [GridPoint],
        detectedEffects: [MovementResolution.AppliedEffect],
        preservesPlayedCard: Bool,
        encounteredRevisit: Bool
    ) {
        var fields: [(String, String)] = [
            ("input", continuation.inputKind.rawValue),
            ("path", PlayDiagnosticLog.describe(traversedPath)),
            ("to", PlayDiagnosticLog.describe(current)),
            ("effects", diagnosticEffectDescription(detectedEffects)),
            ("preserved", String(preservesPlayedCard)),
            ("revisit", String(encounteredRevisit))
        ]
        if let playedMoveCard = continuation.playedMoveCard {
            fields.insert(("card", playedMoveCard.displayName), at: 1)
        }
        logDungeonPlayEvent("move_resolved", fields)
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
        var remainingPathAfterPickupChoice: [GridPoint]?
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
            defeatDungeonEnemy(at: stepPoint)
            if applyDungeonHazard(at: stepPoint) {
                collectDungeonCardPickup(at: stepPoint)
                if pendingDungeonPickupChoice != nil {
                    presentationSteps.append(
                        movementPresentationStep(
                            at: stepPoint,
                            hpBeforeStep: hpBeforeStep,
                            stopReason: .pickupChoice
                        )
                    )
                    remainingPathAfterPickupChoice = Array(pendingPath.dropFirst(stepIndex + 1))
                    break
                }
                collectDungeonSpecialPickup(at: stepPoint)
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
            if pendingDungeonPickupChoice != nil {
                presentationSteps.append(
                    movementPresentationStep(
                        at: stepPoint,
                        hpBeforeStep: hpBeforeStep,
                        stopReason: .pickupChoice
                    )
                )
                remainingPathAfterPickupChoice = Array(pendingPath.dropFirst(stepIndex + 1))
                break
            }
            collectDungeonSpecialPickup(at: stepPoint)
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

            let exitUnlockEvent = updateDungeonExitLockIfNeeded(at: stepPoint, publishesEvent: false)
            let lockedExitReachEvent = pendingLockedDungeonExitReachEvent(
                at: stepPoint,
                isFinalPathStep: stepIndex == pendingPath.count - 1
            )
            if shouldStopDungeonMovementAtExit(at: stepPoint) {
                presentationSteps.append(
                    movementPresentationStep(
                        at: stepPoint,
                        hpBeforeStep: hpBeforeStep,
                        stopReason: .exit,
                        dungeonExitUnlockEvent: exitUnlockEvent,
                        dungeonLockedExitReachEvent: lockedExitReachEvent
                    )
                )
                break
            }

            var stopReason: MovementResolution.PresentationStep.StopReason?
            if let effect = board.effect(at: stepPoint) {
                detectedEffects.append(.init(point: stepPoint, effect: effect))
                switch effect {
                case .warp(_, let destination), .returnWarp(let destination):
                    if board.contains(destination), board.isTraversable(destination) {
                        if hasDungeonCurse(.laughingDoor) {
                            registerPostMoveTileEffect(
                                .discardRandomHand,
                                postMoveTileEffect: &postMoveTileEffect,
                                preservesPlayedCard: &preservesPlayedCard
                            )
                        }
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
                            if pendingDungeonPickupChoice != nil {
                                presentationSteps.append(
                                    movementPresentationStep(
                                        at: destination,
                                        hpBeforeStep: hpBeforeWarpDestination,
                                        stopReason: .pickupChoice
                                    )
                                )
                                remainingPathAfterPickupChoice = []
                                stepIndex = pendingPath.count
                                break
                            }
                            collectDungeonSpecialPickup(at: destination)
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
                        if pendingDungeonPickupChoice != nil {
                            presentationSteps.append(
                                movementPresentationStep(
                                    at: destination,
                                    hpBeforeStep: hpBeforeWarpDestination,
                                    stopReason: .pickupChoice
                                )
                            )
                            remainingPathAfterPickupChoice = []
                            stepIndex = pendingPath.count
                            break
                        }
                        collectDungeonSpecialPickup(at: destination)
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
                        let destinationExitUnlockEvent = updateDungeonExitLockIfNeeded(
                            at: destination,
                            publishesEvent: false
                        )
                        presentationSteps.append(
                            movementPresentationStep(
                                at: destination,
                                hpBeforeStep: hpBeforeWarpDestination,
                                stopReason: .warp,
                                dungeonExitUnlockEvent: destinationExitUnlockEvent,
                                dungeonLockedExitReachEvent: pendingLockedDungeonExitReachEvent(
                                    at: destination,
                                    isFinalPathStep: true
                                )
                            )
                        )
                        stepIndex = pendingPath.count
                    } else {
                        debugLog("ワープ先 \(destination) が盤面外または移動不可のため無視しました")
                    }
                    stopReason = .warp
                case let effect where isFlySpellActive && effect.isBlockedByFlySpell:
                    debugLog("フライの呪文でタイル効果を無効化: \(effect) @\(stepPoint)")
                case .shuffleHand, .preserveCard, .discardRandomHand, .discardAllMoveCards, .discardAllSupportCards, .discardAllHands:
                    registerPostMoveTileEffect(
                        effect,
                        postMoveTileEffect: &postMoveTileEffect,
                        preservesPlayedCard: &preservesPlayedCard
                    )
                case .staggerTrap:
                    if consumePurifyingRelicUse() != nil {
                        debugLog("清めの護符で千鳥足罠を無効化")
                        break
                    }
                    staggerForcedMovesRemaining = max(staggerForcedMovesRemaining, staggerTrapForcedMoveCount)
                    triggerTrapperGlovesIfNeeded(reason: "千鳥足罠")
                    debugLog("千鳥足罠を踏みました: 強制移動残り\(staggerForcedMovesRemaining)回")
                case .swamp:
                    stepIndex = pendingPath.count
                    break
                case .poisonTrap:
                    applyPoisonTrap()
                    if poisonDamageTicksRemaining > 0 {
                        triggerTrapperGlovesIfNeeded(reason: "毒罠")
                        triggeredPoisonTrap = true
                    }
                case .relicBreakTrap:
                    applyRelicBreakTrap(at: stepPoint)
                case .illusionTrap:
                    if consumePurifyingRelicUse() != nil {
                        debugLog("清めの護符で幻惑罠を無効化")
                        break
                    }
                    isIlluded = true
                    if hasDungeonCurse(.foolsMask) {
                        registerPostMoveTileEffect(
                            .discardRandomHand,
                            postMoveTileEffect: &postMoveTileEffect,
                            preservesPlayedCard: &preservesPlayedCard
                        )
                    }
                    triggerTrapperGlovesIfNeeded(reason: "幻惑罠")
                    debugLog("幻惑罠を踏みました: この階の移動カードが？表示になります")
                case .shackleTrap:
                    if consumePurifyingRelicUse() != nil {
                        debugLog("清めの護符で足枷罠を無効化")
                        break
                    }
                    isShackled = true
                    triggerTrapperGlovesIfNeeded(reason: "足枷罠")
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
                    if consumePurifyingRelicUse() != nil {
                        debugLog("清めの護符で麻痺罠を無効化")
                        break
                    }
                    paralysisTrapPoint = stepPoint
                    triggerTrapperGlovesIfNeeded(reason: "麻痺罠")
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
            if remainingPathAfterPickupChoice != nil {
                break
            }
            if stopReason == nil {
                presentationSteps.append(
                    movementPresentationStep(
                        at: stepPoint,
                        hpBeforeStep: hpBeforeStep,
                        dungeonExitUnlockEvent: exitUnlockEvent,
                        dungeonLockedExitReachEvent: lockedExitReachEvent
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
            remainingPathAfterPickupChoice: remainingPathAfterPickupChoice,
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
        case .warp, .returnWarp, .blast, .slow, .shackleTrap, .poisonTrap, .illusionTrap, .staggerTrap, .relicBreakTrap, .swamp:
            break
        }
    }

    private func postMoveTileEffect(from effect: TileEffect?) -> PostMoveTileEffect? {
        guard let effect else { return nil }
        switch effect {
        case .shuffleHand:
            return .shuffleHand
        case .discardRandomHand:
            return .discardRandomHand
        case .discardAllMoveCards:
            return .discardAllMoveCards
        case .discardAllSupportCards:
            return .discardAllSupportCards
        case .discardAllHands:
            return .discardAllHands
        case .warp, .returnWarp, .blast, .slow, .shackleTrap, .poisonTrap, .illusionTrap, .staggerTrap, .relicBreakTrap, .swamp, .preserveCard:
            return nil
        }
    }

    private func tileEffect(from effect: PostMoveTileEffect?) -> TileEffect? {
        guard let effect else { return nil }
        switch effect {
        case .shuffleHand:
            return .shuffleHand
        case .discardRandomHand:
            return .discardRandomHand
        case .discardAllMoveCards:
            return .discardAllMoveCards
        case .discardAllSupportCards:
            return .discardAllSupportCards
        case .discardAllHands:
            return .discardAllHands
        }
    }

    private func mergedPostMoveTileEffect(
        _ first: PostMoveTileEffect?,
        _ second: PostMoveTileEffect?
    ) -> PostMoveTileEffect? {
        var merged = first
        var preservesPlayedCard = false
        if let second, let tileEffect = tileEffect(from: second) {
            registerPostMoveTileEffect(
                tileEffect,
                postMoveTileEffect: &merged,
                preservesPlayedCard: &preservesPlayedCard
            )
        }
        return merged
    }

    private func applyPostMoveTileEffect(_ effect: PostMoveTileEffect?, preserving preservedCard: DealtCard?) {
        guard let effect else { return }
        if let relicID = consumePurifyingRelicUse() {
            debugLog("清めの護符で手札喪失罠を無効化")
            logDungeonPlayEvent(
                "tile_effect_blocked",
                [
                    ("effect", String(describing: effect)),
                    ("reason", relicID.rawValue),
                    ("preservedCard", preservedCard?.playable.displayName ?? "nil")
                ]
            )
            return
        }

        logDungeonPlayEvent(
            "tile_effect_apply",
            [
                ("effect", String(describing: effect)),
                ("preservedCard", preservedCard?.playable.displayName ?? "nil")
            ]
        )
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
        guard hasDungeonCurse(.frayedMemory) else { return }
        switch effect {
        case .discardRandomHand, .discardAllMoveCards, .discardAllSupportCards, .discardAllHands:
            applyTileEffectHandDiscardAllowsNextPreservation(.random)
        case .shuffleHand:
            break
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

    private func applyRelicBreakTrap(at point: GridPoint) {
        if let purifyingCharmIndex = dungeonRelicEntries.firstIndex(where: { [.purifyingCharm, .greatPurifyingCharm].contains($0.relicID) }) {
            let relicID = dungeonRelicEntries[purifyingCharmIndex].relicID
            dungeonRelicEntries.remove(at: purifyingCharmIndex)
            appendDungeonRunLog(kind: .blocked, point: point, message: "\(relicID.displayName)が身代わりになり、レリック破壊罠を防いだ")
            debugLog("レリック破壊罠: \(relicID.displayName)を身代わりに破壊 @\(point)")
            logDungeonPlayEvent(
                "relic_break_trap_blocked",
                [
                    ("point", PlayDiagnosticLog.describe(point)),
                    ("relic", relicID.rawValue)
                ]
            )
            return
        }

        guard let target = deterministicRelicBreakTrapTarget() else {
            appendDungeonRunLog(kind: .blocked, point: point, message: "レリック破壊罠: 壊れるレリック/呪いなし")
            debugLog("レリック破壊罠: 壊れるレリック/呪いなし @\(point)")
            logDungeonPlayEvent(
                "relic_break_trap_empty",
                [("point", PlayDiagnosticLog.describe(point))]
            )
            return
        }

        switch target {
        case .relic(let index):
            let removed = dungeonRelicEntries.remove(at: index)
            appendDungeonRunLog(kind: .damage, point: point, message: "レリック破壊罠で「\(removed.displayName)」が壊れた")
            debugLog("レリック破壊罠: レリック \(removed.displayName) を破壊 @\(point)")
            logDungeonPlayEvent(
                "relic_break_trap_apply",
                [
                    ("point", PlayDiagnosticLog.describe(point)),
                    ("kind", "relic"),
                    ("id", removed.relicID.rawValue)
                ]
            )
        case .curse(let index):
            let removed = dungeonCurseEntries.remove(at: index)
            appendDungeonRunLog(kind: .damage, point: point, message: "レリック破壊罠で呪い「\(removed.displayName)」が壊れた")
            debugLog("レリック破壊罠: 呪い \(removed.displayName) を破壊 @\(point)")
            logDungeonPlayEvent(
                "relic_break_trap_apply",
                [
                    ("point", PlayDiagnosticLog.describe(point)),
                    ("kind", "curse"),
                    ("id", removed.curseID.rawValue)
                ]
            )
        }
    }

    private func deterministicRelicBreakTrapTarget() -> RelicBreakTrapTarget? {
        var candidates: [RelicBreakTrapTarget] = []
        candidates.append(contentsOf: dungeonRelicEntries.indices.map { .relic($0) })
        candidates.append(contentsOf: dungeonCurseEntries.indices.map { .curse($0) })
        guard !candidates.isEmpty else { return nil }
        var generator = DungeonRefillRandomGenerator(seed: relicBreakTrapSeed())
        let offset = Int(generator.next() % UInt64(candidates.count))
        return candidates[offset]
    }

    private func relicBreakTrapSeed() -> UInt64 {
        var seed = mode.dungeonMetadataSnapshot?.runState?.cardVariationSeed ?? mode.deckSeed ?? 1
        seed ^= UInt64(board.size + 73) &* 0xD6E8_FD9A_57A1_4C15
        seed ^= UInt64(max(moveCount, 0) + 1) &* 0xA24B_AED4_963E_E407
        if let current {
            seed ^= UInt64(current.x + 71) &* 1099511628211
            seed ^= UInt64(current.y + 79) &* 1469598103934665603
        }
        for entry in dungeonRelicEntries.sorted(by: { $0.relicID.rawValue < $1.relicID.rawValue }) {
            seed = seed &* 1099511628211 &+ UInt64(entry.remainingUses + 11)
            for scalar in entry.relicID.rawValue.unicodeScalars {
                seed = seed &* 1469598103934665603 &+ UInt64(scalar.value)
            }
        }
        for entry in dungeonCurseEntries.sorted(by: { $0.curseID.rawValue < $1.curseID.rawValue }) {
            seed = seed &* 1099511628211 &+ UInt64(entry.remainingUses + 17)
            for scalar in entry.curseID.rawValue.unicodeScalars {
                seed = seed &* 1469598103934665603 &+ UInt64(scalar.value)
            }
        }
        return seed == 0 ? 1 : seed
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

    private func illusionMoveSeed() -> UInt64 {
        var seed = mode.dungeonMetadataSnapshot?.runState?.cardVariationSeed ?? mode.deckSeed ?? 1
        seed ^= UInt64(board.size + 41) &* 0xD6E8_FD9A_57A1_4C15
        seed ^= UInt64(max(moveCount, 0) + 1) &* 0xA24B_AED4_963E_E407
        seed ^= UInt64(handStacks.count + 29) &* 0x9FB2_1C65_1E98_DF25
        if let current {
            seed ^= UInt64(current.x + 53) &* 1099511628211
            seed ^= UInt64(current.y + 59) &* 1469598103934665603
        }
        for stack in handStacks {
            seed = seed &* 1099511628211 &+ UInt64(stack.count + 7)
            if let scalar = stack.topCard?.playable.identityText.unicodeScalars.first {
                seed = seed &* 1469598103934665603 &+ UInt64(scalar.value)
            }
        }
        return seed == 0 ? 1 : seed
    }

    private func staggerMoveSeed(reason: String, depth: Int) -> UInt64 {
        var seed = mode.dungeonMetadataSnapshot?.runState?.cardVariationSeed ?? mode.deckSeed ?? 1
        seed ^= UInt64(board.size + 89) &* 0xD6E8_FD9A_57A1_4C15
        seed ^= UInt64(max(moveCount, 0) + depth + 1) &* 0xA24B_AED4_963E_E407
        seed ^= UInt64(staggerForcedMovesRemaining + 43) &* 0x9FB2_1C65_1E98_DF25
        if let current {
            seed ^= UInt64(current.x + 83) &* 1099511628211
            seed ^= UInt64(current.y + 97) &* 1469598103934665603
        }
        for scalar in reason.unicodeScalars {
            seed = seed &* 1099511628211 &+ UInt64(scalar.value)
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
            effectAt: { [isFlySpellActive] point in
                let effect = activeBoard.effect(at: point)
                guard isFlySpellActive, effect?.isBlockedByFlySpell == true else { return effect }
                return nil
            }
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
        guard board.effect(at: origin) != .swamp || isFlySpellActive else { return [] }

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
        guard allowsCurrentBasicMove else { return [] }
        guard let origin = currentOverride ?? current else { return [] }

        let vectors = mode.dungeonRules?.movementStyle.basicMoveVectors ?? DungeonMovementStyle.orthogonal.basicMoveVectors

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
        isWatcherLaserSuppressed = false
        isPatrolRailDestroyed = false
        isFlySpellActive = false
        isShackled = false
        isIlluded = false
        staggerForcedMovesRemaining = 0
        didStepOnLavaThisFloor = false
        currentFloorDefeatedEnemyCount = 0
        pendingDefeatEnemyTurnSkip = false
        poisonDamageTicksRemaining = 0
        poisonActionsUntilNextDamage = 0
        enemyStates = mode.dungeonRules?.enemies.map(EnemyState.init(definition:)) ?? []
        didStartCurrentFloorWithEnemies = !enemyStates.isEmpty
        let currentFloorIndex = mode.dungeonMetadataSnapshot?.runState?.currentFloorIndex ?? 0
        let savedCrackedFloorPoints = mode.dungeonMetadataSnapshot?.runState?.crackedFloorPoints(for: currentFloorIndex) ?? []
        let savedCollapsedFloorPoints = mode.dungeonMetadataSnapshot?.runState?.collapsedFloorPoints(for: currentFloorIndex) ?? []
        let initialAndSavedCollapsedFloorPoints = initialCollapsedBrittleFloorPoints.union(savedCollapsedFloorPoints)
        crackedFloorPoints = initialCrackedBrittleFloorPoints
            .union(savedCrackedFloorPoints)
            .subtracting(initialAndSavedCollapsedFloorPoints)
        collapsedFloorPoints = initialAndSavedCollapsedFloorPoints
        consumedHealingTilePoints = []
        dungeonInventoryEntries = mode.dungeonMetadataSnapshot?.runState?.rewardInventoryEntries ?? []
        collectedDungeonCardPickupIDs = []
        collectedDungeonSpecialPickupIDs = []
        currentDungeonInventoryKindLimit = mode.dungeonMetadataSnapshot?.runState?.dungeonInventoryKindLimit
        dungeonRelicEntries = mode.dungeonMetadataSnapshot?.runState?.relicEntries ?? []
        dungeonCurseEntries = mode.dungeonMetadataSnapshot?.runState?.curseEntries ?? []
        applyFloorStartDungeonRelicStatusEffects()
        applyFloorStartDungeonCurseStatusEffects()
        collectedDungeonRelicPickupIDs = mode.dungeonMetadataSnapshot?.runState?.collectedDungeonRelicPickupIDs ?? []
        dungeonRelicAcquisitionPresentations = []
        dungeonRunLogEntries = mode.dungeonMetadataSnapshot?.runState?.runLogEntries ?? []
        pendingDungeonPickupChoice = nil
        pendingDungeonMovementContinuation = nil
        pendingDungeonRelicPickupChoice = nil
        isDungeonExitUnlocked = mode.dungeonRules?.exitLock == nil
        dungeonExitUnlockEvent = nil
        dungeonLockedExitReachEvent = nil
        dungeonFallEvent = nil
        dungeonRewindReviveEvent = nil
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
        logDungeonPlayEvent(
            "session_start",
            [
                ("seed", diagnosticSeedDescription),
                ("exit", PlayDiagnosticLog.describe(mode.dungeonExitPoint)),
                ("turnLimit", effectiveDungeonTurnLimit.map(String.init) ?? "nil"),
                ("inventory", diagnosticInventoryDescription),
                ("next", nextCards.map(\.displayName).joined(separator: ","))
            ]
        )
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
        let liveEntries = HandDisplayOrdering.orderedDungeonInventoryEntries(
            Array(dungeonInventoryEntries.filter(\.hasUsesRemaining).prefix(dungeonInventoryKindLimit)),
            strategy: handOrderingStrategy
        )
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
        if let index = dungeonInventoryEntries.firstIndex(where: { $0.playable == playable }) {
            dungeonInventoryEntries[index].rewardUses += normalizedPickupUses + normalizedRewardUses
            dungeonInventoryEntries[index].pickupUses = 0
            syncDungeonInventoryHandStacks()
            return true
        }

        guard dungeonInventoryEntries.filter(\.hasUsesRemaining).count < dungeonInventoryKindLimit else { return false }
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
        continuePendingDungeonMovementIfNeeded()
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
        continuePendingDungeonMovementIfNeeded()
        return true
    }

    @discardableResult
    public func selectPendingDungeonRelicPickupOption(id optionID: String) -> Bool {
        guard let choice = pendingDungeonRelicPickupChoice,
              let option = choice.options.first(where: { $0.id == optionID }),
              !collectedDungeonRelicPickupIDs.contains(choice.pickup.id)
        else { return false }

        pendingDungeonRelicPickupChoice = nil
        collectedDungeonRelicPickupIDs.insert(choice.pickup.id)
        var presentationItems: [DungeonRelicAcquisitionPresentation.Item] = []
        var outcome: DungeonRelicPickupOutcome = .relic

        if let relicID = option.relicID,
           let relic = grantDungeonRelic(relicID) {
            presentationItems.append(.relic(relic))
        }
        if let curseID = option.curseID {
            outcome = .curse
            presentationItems.append(contentsOf: grantDungeonCurse(curseID, from: choice.pickup, salt: option.id))
        }
        if option.hpPenalty > 0 {
            let hpBefore = dungeonHP
            applyDungeonHPDamage(option.hpPenalty)
            presentationItems.append(.hpPenalty(option.hpPenalty))
            appendDungeonHPChangeLog(
                kind: .damage,
                source: "怪しい宝箱",
                point: choice.pickup.point,
                hpBefore: hpBefore,
                hpAfter: dungeonHP
            )
            if shouldFailDungeonRun() {
                finalizeElapsedTimeIfNeeded()
                progress = .failed
            }
        }

        logDungeonPlayEvent(
            "pickup_relic_choice",
            [
                ("pickup", choice.pickup.id),
                ("point", PlayDiagnosticLog.describe(choice.pickup.point)),
                ("option", option.title),
                ("items", presentationItems.map(\.diagnosticDescription).joined(separator: ",")),
                ("relics", diagnosticRelicDescription),
                ("curses", diagnosticCurseDescription)
            ]
        )
        publishDungeonRelicAcquisitionPresentationIfNeeded(outcome: outcome, items: presentationItems)
        debugLog("怪しい宝箱の選択を確定: \(choice.pickup.id) \(option.title)")
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
    private func collectDungeonSpecialPickup(at point: GridPoint) -> Bool {
        guard let pickup = activeDungeonSpecialPickups.first(where: { $0.point == point }) else { return false }
        switch pickup.kind {
        case .handExpansion:
            guard mode.dungeonRules?.difficulty == .roguelike else { return false }
            let oldLimit = currentDungeonInventoryKindLimit
                ?? mode.dungeonMetadataSnapshot?.runState?.dungeonInventoryKindLimit
                ?? 5
            let newLimit = min(max(oldLimit, 1) + 1, 9)
            collectedDungeonSpecialPickupIDs.insert(pickup.id)
            currentDungeonInventoryKindLimit = newLimit
            appendDungeonRunLog(
                kind: .acquisition,
                point: pickup.point,
                message: "手札拡張を取得（所持枠 \(oldLimit)→\(newLimit)）"
            )
            logDungeonPlayEvent(
                "pickup_hand_expansion",
                [
                    ("pickup", pickup.id),
                    ("point", PlayDiagnosticLog.describe(pickup.point)),
                    ("limit", "\(oldLimit)->\(newLimit)")
                ]
            )
            syncDungeonInventoryHandStacks()
            return true
        }
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
        guard pendingDungeonRelicPickupChoice == nil else { return false }
        let pickupUses = adjustedDungeonPickupUses(pickup.uses)
        if addDungeonInventoryPlayable(pickup.playable, pickupUses: pickupUses) {
            collectedDungeonCardPickupIDs.insert(pickup.id)
            debugLog("拾得カードを取得: \(pickup.playable.displayName) 残り+\(pickupUses) @\(pickup.point)")
            logDungeonPlayEvent(
                "pickup_card",
                [
                    ("pickup", pickup.id),
                    ("point", PlayDiagnosticLog.describe(pickup.point)),
                    ("card", pickup.playable.displayName),
                    ("uses", String(pickupUses)),
                    ("inventory", diagnosticInventoryDescription)
                ]
            )
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
        if hasDungeonRelic(.sageCodex) {
            adjustment += 1
        }
        if hasDungeonCurse(.greedyBag) {
            adjustment += 4
        }
        if hasDungeonCurse(.poisonVial) {
            adjustment += 2
        }
        if hasDungeonCurse(.contractCodex) {
            adjustment += 3
        }
        if hasDungeonCurse(.bottomlessPack) {
            adjustment += 5
        }
        if hasDungeonCurse(.relicHunterBrand) {
            adjustment -= 1
        }
        if hasDungeonCurse(.supportOath) {
            adjustment -= 1
        }
        return max(uses + adjustment, 1)
    }

    @discardableResult
    private func collectDungeonRelicPickupDefinition(_ pickup: DungeonRelicPickupDefinition) -> Bool {
        guard mode.dungeonRules?.difficulty == .growth else { return false }
        guard pendingDungeonRelicPickupChoice == nil else { return false }
        guard !collectedDungeonRelicPickupIDs.contains(pickup.id) else { return false }

        if pickup.kind.isSuspicious {
            if let choice = makePendingDungeonRelicPickupChoice(for: pickup), choice.options.count >= 2 {
                pendingDungeonRelicPickupChoice = choice
                debugLog("怪しい宝箱の選択を開始: \(pickup.id) @\(pickup.point)")
                logDungeonPlayEvent(
                    "pickup_relic_choice_start",
                    [
                        ("pickup", pickup.id),
                        ("point", PlayDiagnosticLog.describe(pickup.point)),
                        ("options", choice.options.map(\.title).joined(separator: ","))
                    ]
                )
                return false
            }
            collectedDungeonRelicPickupIDs.insert(pickup.id)
            let hpBefore = dungeonHP
            dungeonHP += 1
            clampDungeonHPForGildedSealIfNeeded()
            let presentationItems: [DungeonRelicAcquisitionPresentation.Item] = [.hpCompensation(1)]
            appendDungeonHPChangeLog(
                kind: .healing,
                source: "宝箱補填",
                point: pickup.point,
                hpBefore: hpBefore,
                hpAfter: dungeonHP
            )
            logDungeonPlayEvent(
                "pickup_relic",
                [
                    ("pickup", pickup.id),
                    ("point", PlayDiagnosticLog.describe(pickup.point)),
                    ("outcome", "compensation"),
                    ("items", presentationItems.map(\.diagnosticDescription).joined(separator: ",")),
                    ("relics", diagnosticRelicDescription),
                    ("curses", diagnosticCurseDescription)
                ]
            )
            publishDungeonRelicAcquisitionPresentationIfNeeded(outcome: .relic, items: presentationItems)
            debugLog("怪しい宝箱の選択候補が不足したためHP補填: \(pickup.id) @\(pickup.point), HP=\(dungeonHP)")
            return true
        }

        collectedDungeonRelicPickupIDs.insert(pickup.id)

        let outcome = selectedRelicPickupOutcome(for: pickup)
        var presentationItems: [DungeonRelicAcquisitionPresentation.Item] = []

        switch outcome {
        case .relic:
            if let relic = grantDungeonRelic(from: pickup, salt: "relic") {
                presentationItems.append(.relic(relic))
            } else if pickup.kind == .safe {
                let hpBefore = dungeonHP
                dungeonHP += 1
                clampDungeonHPForGildedSealIfNeeded()
                presentationItems.append(.hpCompensation(1))
                appendDungeonHPChangeLog(
                    kind: .healing,
                    source: "宝箱補填",
                    point: pickup.point,
                    hpBefore: hpBefore,
                    hpAfter: dungeonHP
                )
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
        logDungeonPlayEvent(
            "pickup_relic",
            [
                ("pickup", pickup.id),
                ("point", PlayDiagnosticLog.describe(pickup.point)),
                ("outcome", String(describing: outcome)),
                ("items", presentationItems.map(\.diagnosticDescription).joined(separator: ",")),
                ("relics", diagnosticRelicDescription),
                ("curses", diagnosticCurseDescription)
            ]
        )
        publishDungeonRelicAcquisitionPresentationIfNeeded(outcome: outcome, items: presentationItems)
        return true
    }

    private func removeMimicRelicPickupsForAnnihilationSpell() {
        // 怪しい宝箱は選択式になったため、未開封ミミックの事前消滅は発生しない。
    }

    private func makePendingDungeonRelicPickupChoice(for pickup: DungeonRelicPickupDefinition) -> PendingDungeonRelicPickupChoice? {
        let stableRelicID = selectedRelicID(
            from: availableRelicCandidates(for: pickup),
            rarityWeights: pickup.kind.relicRarityWeights,
            pickupID: pickup.id,
            salt: "choice-stable"
        )
        let stableOption = stableRelicID.map {
            PendingDungeonRelicPickupChoice.Option(
                id: "stable",
                title: "通常遺物",
                kind: .stableRelic,
                relicID: $0
            )
        }

        let riskOption: PendingDungeonRelicPickupChoice.Option?
        switch pickup.kind {
        case .safe:
            riskOption = nil
        case .suspiciousLight:
            riskOption = selectedCurseID(
                from: availableCurseCandidates(for: pickup),
                pickupID: pickup.id,
                salt: "choice-curse"
            ).map {
                PendingDungeonRelicPickupChoice.Option(
                    id: "curse",
                    title: "呪い遺物",
                    kind: .curseRelic,
                    curseID: $0
                )
            }
        case .suspiciousDeep:
            riskOption = selectedRelicID(
                from: availableRelicCandidates(for: pickup).filter { $0 != stableRelicID },
                rarityWeights: [(.common, 20), (.rare, 55), (.legendary, 25)],
                pickupID: pickup.id,
                salt: "choice-risky"
            ).map {
                PendingDungeonRelicPickupChoice.Option(
                    id: "risky",
                    title: "HP -1",
                    kind: .riskyRelicWithDamage,
                    relicID: $0,
                    hpPenalty: 1
                )
            }
        }

        let options = [stableOption, riskOption].compactMap { $0 }
        guard options.count >= 2 else { return nil }
        return PendingDungeonRelicPickupChoice(pickup: pickup, options: options)
    }

    @discardableResult
    private func grantDungeonRelic(from pickup: DungeonRelicPickupDefinition, salt: String) -> DungeonRelicEntry? {
        let candidates = availableRelicCandidates(for: pickup)
        guard let relicID = selectedRelicID(
            from: candidates,
            rarityWeights: pickup.kind.relicRarityWeights,
            pickupID: pickup.id,
            salt: salt
        ) else {
            debugLog("宝箱は空でした: \(pickup.id) @\(pickup.point)")
            return nil
        }

        let entry = DungeonRelicEntry(relicID: relicID)
        dungeonRelicEntries.append(entry)
        let hpBefore = dungeonHP
        applyImmediateDungeonRelicEffect(relicID)
        appendDungeonRunLog(kind: .acquisition, point: pickup.point, message: "レリック「\(relicID.displayName)」を取得")
        appendDungeonHPChangeLog(
            kind: .healing,
            source: relicID.displayName,
            point: pickup.point,
            hpBefore: hpBefore,
            hpAfter: dungeonHP
        )
        debugLog("遺物を取得: \(relicID.displayName) @\(pickup.point)")
        return entry
    }

    @discardableResult
    private func grantDungeonRelic(_ relicID: DungeonRelicID) -> DungeonRelicEntry? {
        guard !dungeonRelicEntries.contains(where: { $0.relicID == relicID }) else { return nil }
        let entry = DungeonRelicEntry(relicID: relicID)
        dungeonRelicEntries.append(entry)
        let hpBefore = dungeonHP
        applyImmediateDungeonRelicEffect(relicID)
        appendDungeonRunLog(kind: .acquisition, message: "レリック「\(relicID.displayName)」を取得")
        appendDungeonHPChangeLog(
            kind: .healing,
            source: relicID.displayName,
            hpBefore: hpBefore,
            hpAfter: dungeonHP
        )
        debugLog("遺物を取得: \(relicID.displayName)")
        return entry
    }

    @discardableResult
    private func grantDungeonCurse(from pickup: DungeonRelicPickupDefinition, salt: String) -> [DungeonRelicAcquisitionPresentation.Item] {
        let candidates = availableCurseCandidates(for: pickup)
        guard let curseID = selectedCurseID(from: candidates, pickupID: pickup.id, salt: salt) else { return [] }
        return grantDungeonCurse(curseID, from: pickup, salt: salt)
    }

    @discardableResult
    private func grantDungeonCurse(
        _ curseID: DungeonCurseID,
        from pickup: DungeonRelicPickupDefinition,
        salt: String
    ) -> [DungeonRelicAcquisitionPresentation.Item] {
        guard !dungeonCurseEntries.contains(where: { $0.curseID == curseID }) else { return [] }
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
        let hpBefore = dungeonHP
        applyImmediateDungeonCurseEffect(curseID)
        appendDungeonRunLog(kind: .acquisition, point: pickup.point, message: "呪い「\(curseID.displayName)」を取得")
        appendDungeonHPChangeLog(
            kind: .healing,
            source: curseID.displayName,
            point: pickup.point,
            hpBefore: hpBefore,
            hpAfter: dungeonHP
        )
        debugLog("呪い遺物を取得: \(curseID.displayName) @\(pickup.point)")
        return [.curse(entry)]
    }

    @discardableResult
    private func applyDungeonMimicTrap(from pickup: DungeonRelicPickupDefinition) -> Int {
        let damage = hasDungeonCurse(.redChalice) ? 2 : 1
        let hpBefore = dungeonHP
        applyDungeonHPDamage(damage)
        debugLog("ミミックが出現: \(pickup.id) @\(pickup.point), HP=\(dungeonHP)")
        appendDungeonHPChangeLog(
            kind: .damage,
            source: "ミミック",
            point: pickup.point,
            hpBefore: hpBefore,
            hpAfter: dungeonHP
        )
        if shouldFailDungeonRun() {
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
        return pickup.candidateRelics.filter {
            $0.isAvailableForNewAcquisition && !ownedRelics.contains($0)
        }
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

    private func selectedRelicID(
        from candidates: [DungeonRelicID],
        rarityWeights: [(DungeonRelicRarity, Int)],
        pickupID: String,
        salt: String
    ) -> DungeonRelicID? {
        let eligibleCandidates: [DungeonRelicID]
        if hasDungeonCurse(.gildedSeal) {
            let rareOrBetter = candidates.filter { $0.rarity != .common }
            guard !rareOrBetter.isEmpty else { return nil }
            eligibleCandidates = rareOrBetter
        } else {
            eligibleCandidates = candidates
        }
        guard !eligibleCandidates.isEmpty else { return nil }
        var generator = DungeonRefillRandomGenerator(seed: pickupSeed(pickupID: pickupID, salt: salt))
        let weightedCandidates = eligibleCandidates.compactMap { relic -> (DungeonRelicID, Int)? in
            let rawWeight = rarityWeights.first { $0.0 == relic.rarity }?.1 ?? 0
            let weight = hasDungeonCurse(.gildedSeal) && relic.rarity == .common ? 0 : rawWeight
            return weight > 0 ? (relic, weight) : nil
        }
        guard !weightedCandidates.isEmpty else {
            return eligibleCandidates[Int(generator.next() % UInt64(eligibleCandidates.count))]
        }
        let totalWeight = weightedCandidates.reduce(0) { $0 + $1.1 }
        var roll = Int(generator.next() % UInt64(totalWeight))
        for (relic, weight) in weightedCandidates {
            if roll < weight {
                return relic
            }
            roll -= weight
        }
        return weightedCandidates[0].0
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
        guard areDungeonRelicAndCurseEffectsEnabled else { return }
        switch relicID {
        case .crackedShield:
            break
        case .glowingHeart:
            dungeonHP += 2
            clampDungeonHPForGildedSealIfNeeded()
        case .woodenAmulet:
            dungeonHP += 1
            clampDungeonHPForGildedSealIfNeeded()
        case .heavyCrown, .oldMap, .blackFeather, .chippedHourglass, .travelerBoots, .silverNeedle,
             .starCup, .distantStarCup, .crackedStarCup, .explorerBag, .moonMirror, .victoryBanner:
            break
        case .windcutFeather, .guardianIncense, .trapperGloves, .whiteChalk, .spareTorch, .oldRope, .twinPouch, .gamblerCoin:
            break
        case .royalCrown, .immortalHeart, .guardianAegis, .stargazerHourglass:
            break
        case .copperHourglass, .travelerRation, .travelerCanteen, .moonDewCanteen,
             .smallLantern, .dullNeedle, .patchedRope,
             .fieldMedkit, .scoutCompass, .quickSheath, .purifyingCharm, .greatPurifyingCharm, .phoenixFeather, .sageCodex,
             .lavaCharm, .lavaLantern, .watcherMask, .railWedge, .railSign, .smokeDecoy, .chaserWhistle, .starVeil,
             .trapSole, .emberCloak, .watcherMonocle, .railCharm, .chaserDecoy, .antidoteStone, .greaterAntidoteStone,
             .starUmbrella, .guardianCloak, .fallAnchor, .foldingMap, .phantomTicket, .campfireCoal, .merchantsScale,
             .barrierCharm, .barrierTalisman, .frostBell, .rewindingHourglass,
             .slayerPouch, .hunterBanner, .intimidationHorn, .slayerMedal,
             .nightCardLens, .thornScoutLens, .magmaScoutLens, .trapScoutLens, .enemyScoutLens:
            break
        }
    }

    private func applyFloorStartDungeonRelicStatusEffects() {
        guard areDungeonRelicAndCurseEffectsEnabled else { return }
        let barrierTurns = dungeonRelicEntries
            .map { $0.relicID.floorStartDamageBarrierTurns }
            .max() ?? 0
        let freezeTurns = dungeonRelicEntries
            .map { $0.relicID.floorStartEnemyFreezeTurns }
            .max() ?? 0
        damageBarrierTurnsRemaining = max(damageBarrierTurnsRemaining, barrierTurns)
        enemyFreezeTurnsRemaining = max(enemyFreezeTurnsRemaining, freezeTurns)
    }

    private func applyFloorStartDungeonCurseStatusEffects() {
        guard areDungeonRelicAndCurseEffectsEnabled else { return }
        if hasDungeonCurse(.swarmcallingTalisman) {
            damageBarrierTurnsRemaining = max(damageBarrierTurnsRemaining, 5)
        }
        if hasDungeonCurse(.quartermasterBell), !isDungeonInventoryFullForRefill {
            refillDungeonEmptySlotsWithRandomMoveCards()
        }
        clampDungeonHPForGildedSealIfNeeded()
    }

    private func applyImmediateDungeonCurseEffect(_ curseID: DungeonCurseID) {
        guard areDungeonRelicAndCurseEffectsEnabled else { return }
        switch curseID {
        case .rustyChain, .thornMark:
            dungeonHP += 1
        case .bloodPact:
            dungeonHP += 2
        case .obsidianHeart:
            dungeonHP += 6
        case .redChalice:
            dungeonHP += 8
        case .heavyBell:
            dungeonHP += 2
        case .crackedShoes:
            dungeonHP += 3
        case .watchersBrand, .glassAnklet, .wetTinder:
            dungeonHP += 2
        case .meteorRod, .ironShackle:
            dungeonHP += 3
        case .cursedCrown, .warpedHourglass, .greedyBag, .crackedCompass:
            break
        case .cloudedMirror, .patrolBell, .chaserScent, .trapMagnet, .oilSoakedBoots, .poisonVial, .foolsMask, .frayedMemory:
            break
        case .laughingDoor, .upsideDownKey, .taxCollector, .flickeringCampfire:
            break
        case .contractCodex, .royalIou, .bottomlessPack, .relicHunterBrand, .supportOath, .ashHeart,
             .hasteArmor, .scorchedCloak, .lastStandShield, .firewalkingTalisman, .tinkersToolbox,
             .expressTicket, .ploverContract, .quartermasterBell, .sleepingWarDrum, .swarmcallingTalisman:
            break
        case .gildedSeal:
            clampDungeonHPForGildedSealIfNeeded()
        }
        clampDungeonHPForGildedSealIfNeeded()
    }

    private func movementPresentationStep(
        at point: GridPoint,
        hpBeforeStep: Int,
        stopReason: MovementResolution.PresentationStep.StopReason? = nil,
        dungeonExitUnlockEvent: DungeonExitUnlockEvent? = nil,
        dungeonLockedExitReachEvent: DungeonLockedExitReachEvent? = nil
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
            stopReason: stopReason,
            dungeonExitUnlockEvent: dungeonExitUnlockEvent,
            dungeonLockedExitReachEvent: dungeonLockedExitReachEvent
        )
    }

    private func defeatDungeonEnemies(along traversedPath: [GridPoint]) {
        guard mode.usesDungeonExit, !enemyStates.isEmpty else { return }
        let stompedPoints = Set(traversedPath)
        guard !stompedPoints.isEmpty else { return }

        let defeatedEnemies = enemyStates.filter { stompedPoints.contains($0.position) }
        guard !defeatedEnemies.isEmpty else { return }

        enemyStates.removeAll { stompedPoints.contains($0.position) }
        registerDungeonEnemyDefeats(defeatedEnemies)
        let summary = defeatedEnemies.map { "\($0.name)@\($0.position)" }.joined(separator: ", ")
        debugLog("敵を踏みつけ撃破: \(summary)")
    }

    private func defeatDungeonEnemy(at point: GridPoint) {
        defeatDungeonEnemies(along: [point])
    }

    private func registerDungeonEnemyDefeats(_ defeatedEnemies: [EnemyState]) {
        guard !defeatedEnemies.isEmpty else { return }
        currentFloorDefeatedEnemyCount += defeatedEnemies.count
        if hasDungeonRelic(.intimidationHorn), !enemyStates.isEmpty {
            pendingDefeatEnemyTurnSkip = true
        }
        applySlayerMedalProgress(defeatedCount: defeatedEnemies.count)
        logDungeonPlayEvent(
            "enemy_defeated",
            [
                ("count", String(defeatedEnemies.count)),
                ("floorTotal", String(currentFloorDefeatedEnemyCount)),
                ("skipEnemyTurn", String(pendingDefeatEnemyTurnSkip))
            ]
        )
    }

    private func applySlayerMedalProgress(defeatedCount: Int) {
        guard defeatedCount > 0,
              areDungeonRelicAndCurseEffectsEnabled,
              let medalIndex = dungeonRelicEntries.firstIndex(where: { $0.relicID == .slayerMedal })
        else { return }

        dungeonRelicEntries[medalIndex].enemyDefeatProgress += defeatedCount
        var grantedItems: [DungeonRelicAcquisitionPresentation.Item] = []
        var awardIndex = 0
        while dungeonRelicEntries[medalIndex].enemyDefeatProgress >= 10 {
            dungeonRelicEntries[medalIndex].enemyDefeatProgress -= 10
            if let relicID = selectedSlayerMedalCommonRelic(awardIndex: awardIndex),
               let relic = grantDungeonRelic(relicID) {
                grantedItems.append(.relic(relic))
            } else {
                appendDungeonRunLog(kind: .acquisition, message: "討伐者の勲章: 未所持のコモンレリック候補なし")
            }
            awardIndex += 1
        }

        guard !grantedItems.isEmpty else { return }
        dungeonRelicAcquisitionPresentations.append(
            DungeonRelicAcquisitionPresentation(
                source: .reward,
                outcome: .relic,
                items: grantedItems
            )
        )
    }

    private func selectedSlayerMedalCommonRelic(awardIndex: Int) -> DungeonRelicID? {
        let ownedRelics = Set(dungeonRelicEntries.map(\.relicID))
        let candidates = DungeonRelicID.newAcquisitionCases.filter {
            $0.rarity == .common && !ownedRelics.contains($0)
        }
        guard !candidates.isEmpty else { return nil }
        let pickupID = "slayer-medal-\(diagnosticFloorDescription)-\(currentFloorDefeatedEnemyCount)-\(awardIndex)"
        var generator = DungeonRefillRandomGenerator(seed: pickupSeed(pickupID: pickupID, salt: "common-relic"))
        return candidates[Int(generator.next() % UInt64(candidates.count))]
    }

    private func beginPendingDungeonPickupChoiceIfNeeded(for pickup: DungeonCardPickupDefinition) -> Bool {
        let liveEntries = Array(dungeonInventoryEntries.filter(\.hasUsesRemaining).prefix(dungeonInventoryKindLimit))
        guard liveEntries.count >= dungeonInventoryKindLimit,
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
        logDungeonPlayEvent(
            "pickup_card_pending_choice",
            [
                ("pickup", pickup.id),
                ("point", PlayDiagnosticLog.describe(pickup.point)),
                ("card", pickup.playable.displayName),
                ("candidates", liveEntries.map { $0.playable.displayName }.joined(separator: ","))
            ]
        )
        return true
    }

    private func refillDungeonEmptySlotsWithRandomMoveCards() {
        guard usesDungeonInventoryCards else { return }
        let occupiedCount = dungeonInventoryEntries.filter(\.hasUsesRemaining).count
        let emptySlotCount = max(0, dungeonInventoryKindLimit - occupiedCount)
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

    private var isDungeonInventoryFullForRefill: Bool {
        usesDungeonInventoryCards && dungeonInventoryEntries.filter(\.hasUsesRemaining).count >= dungeonInventoryKindLimit
    }

    private func clampDungeonHPForGildedSealIfNeeded() {
        guard hasDungeonCurse(.gildedSeal) else { return }
        dungeonHP = min(dungeonHP, 2)
    }

    private func dungeonRefillMoveCardPool() -> [MoveCard] {
        let cards: [MoveCard]
        if mode.dungeonRules?.movementStyle == .knight {
            cards = MoveCard.allCases.map(\.cardForKnightMovementStyle)
        } else {
            cards = MoveCard.allCases.filter { !$0.isOrthogonalStepType }
        }

        var seen: Set<MoveCard> = []
        return cards.filter { seen.insert($0).inserted }
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

    public var hiddenWeakBrittleFloorPoints: Set<GridPoint> {
        brittleFloorPoints(initialState: .hiddenWeak)
    }

    public var initialCrackedBrittleFloorPoints: Set<GridPoint> {
        brittleFloorPoints(initialState: .cracked)
    }

    public var initialCollapsedBrittleFloorPoints: Set<GridPoint> {
        brittleFloorPoints(initialState: .collapsed)
    }

    private var brittleFloorPoints: Set<GridPoint> {
        var points: Set<GridPoint> = []
        for hazard in mode.dungeonRules?.hazards ?? [] {
            switch hazard {
            case .brittleFloor(let floorPoints, _):
                points.formUnion(floorPoints)
            case .damageTrap, .hpHalvingTrap(_), .lavaTile, .healingTile:
                break
            }
        }
        return points
    }

    private func brittleFloorPoints(initialState: BrittleFloorInitialState) -> Set<GridPoint> {
        var points: Set<GridPoint> = []
        for hazard in mode.dungeonRules?.hazards ?? [] {
            switch hazard {
            case .brittleFloor(let floorPoints, let state) where state == initialState:
                points.formUnion(floorPoints)
            case .brittleFloor, .damageTrap, .hpHalvingTrap(_), .lavaTile, .healingTile:
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
            case .brittleFloor, .hpHalvingTrap(_), .lavaTile, .healingTile:
                break
            }
        }
        return points
    }

    public var strongDamageTrapPoints: Set<GridPoint> {
        var points: Set<GridPoint> = []
        for hazard in mode.dungeonRules?.hazards ?? [] {
            switch hazard {
            case .damageTrap(let trapPoints, let damage) where damage >= 2:
                points.formUnion(trapPoints)
            case .brittleFloor, .damageTrap, .hpHalvingTrap(_), .lavaTile, .healingTile:
                break
            }
        }
        return points
    }

    public var hpHalvingTrapPoints: Set<GridPoint> {
        var points: Set<GridPoint> = []
        for hazard in mode.dungeonRules?.hazards ?? [] {
            switch hazard {
            case .hpHalvingTrap(let trapPoints):
                points.formUnion(trapPoints)
            case .brittleFloor, .damageTrap, .lavaTile, .healingTile:
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
            case .brittleFloor, .damageTrap, .hpHalvingTrap(_), .healingTile:
                break
            }
        }
        return points
    }

    public var strongLavaTilePoints: Set<GridPoint> {
        var points: Set<GridPoint> = []
        for hazard in mode.dungeonRules?.hazards ?? [] {
            switch hazard {
            case .lavaTile(let lavaPoints, let damage) where damage >= 2:
                points.formUnion(lavaPoints)
            case .brittleFloor, .damageTrap, .hpHalvingTrap(_), .lavaTile, .healingTile:
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
            case .brittleFloor, .damageTrap, .hpHalvingTrap(_), .lavaTile:
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
            if isFlySpellActive {
                debugLog("フライの呪文で脆い床/崩落床を無効化: \(point)")
            } else if collapsedFloorPoints.contains(point) {
                debugLog("崩落済みの床へ落下: \(point)")
                return triggerDungeonFall(at: point)
            } else if crackedFloorPoints.contains(point)
                        || initialCrackedBrittleFloorPoints.contains(point)
                        || hiddenWeakBrittleFloorPoints.contains(point) {
                crackedFloorPoints.remove(point)
                collapsedFloorPoints.insert(point)
                debugLog("脆い床が崩落穴化: \(point)")
            } else {
                collapsedFloorPoints.insert(point)
                debugLog("脆い床が崩落穴化: \(point)")
            }
        }

        for hazard in mode.dungeonRules?.hazards ?? [] {
            switch hazard {
            case .damageTrap(let trapPoints, let damage) where trapPoints.contains(point):
                guard !isFlySpellActive else {
                    debugLog("フライの呪文で罠を無効化: \(point)")
                    break
                }
                applyDungeonHazardDamage(max(damage, 1), category: .trap, at: point, logLabel: "罠")
                if shouldStopDungeonActionAfterDamage() {
                    guard shouldFailDungeonRun() else { return true }
                    finalizeElapsedTimeIfNeeded()
                    progress = .failed
                    return true
                }
            case .hpHalvingTrap(let trapPoints) where trapPoints.contains(point):
                guard !isFlySpellActive else {
                    debugLog("フライの呪文で衰弱罠を無効化: \(point)")
                    break
                }
                let targetHP = max((dungeonHP + 1) / 2, 1)
                let damage = max(dungeonHP - targetHP, 0)
                if damage > 0 {
                    applyDungeonHazardDamage(damage, category: .trap, at: point, logLabel: "罠")
                    if shouldStopDungeonActionAfterDamage() {
                        guard shouldFailDungeonRun() else { return true }
                        finalizeElapsedTimeIfNeeded()
                        progress = .failed
                        return true
                    }
                }
            case .lavaTile(let lavaPoints, let damage) where lavaPoints.contains(point):
                guard !isFlySpellActive else {
                    debugLog("フライの呪文で溶岩を無効化: \(point)")
                    break
                }
                didStepOnLavaThisFloor = true
                applyDungeonHazardDamage(max(damage, 1), category: .lava, at: point, logLabel: "溶岩")
                if shouldStopDungeonActionAfterDamage() {
                    guard shouldFailDungeonRun() else { return true }
                    finalizeElapsedTimeIfNeeded()
                    progress = .failed
                    return true
                }
            case .healingTile(let healingPoints, let amount) where healingPoints.contains(point):
                guard !consumedHealingTilePoints.contains(point) else { break }
                let appliedHealing = max(amount, 1)
                    + (hasDungeonRelic(.fieldMedkit) ? 1 : 0)
                    + (hasDungeonCurse(.flickeringCampfire) ? 3 : 0)
                let hpBefore = dungeonHP
                dungeonHP += appliedHealing
                clampDungeonHPForGildedSealIfNeeded()
                consumedHealingTilePoints.insert(point)
                if hasDungeonRelic(.campfireCoal) {
                    poisonDamageTicksRemaining = 0
                    poisonActionsUntilNextDamage = 0
                    isShackled = false
                    isIlluded = false
                    staggerForcedMovesRemaining = 0
                }
                if hasDungeonCurse(.flickeringCampfire) {
                    isIlluded = true
                }
                debugLog("回復マスを踏みました: \(point), +\(appliedHealing), HP=\(dungeonHP)")
                appendDungeonHPChangeLog(
                    kind: .healing,
                    source: "回復マス",
                    point: point,
                    hpBefore: hpBefore,
                    hpAfter: dungeonHP
                )
            case .brittleFloor, .damageTrap, .hpHalvingTrap(_), .lavaTile, .healingTile:
                break
            }
        }
        return false
    }

    private func applyDungeonHazardDamage(
        _ damage: Int,
        category: DungeonDamageCategory,
        at point: GridPoint,
        logLabel: String
    ) {
        if isDamageBarrierActive {
            debugLog("\(logLabel)ダメージを障壁で無効化: \(point), 残り=\(damageBarrierTurnsRemaining)")
            appendDungeonRunLog(kind: .blocked, point: point, message: "\(logLabel)ダメージを障壁で無効化")
            logDungeonPlayEvent(
                "damage_blocked",
                [
                    ("source", logLabel),
                    ("point", PlayDiagnosticLog.describe(point)),
                    ("reason", "barrier"),
                    ("incoming", String(damage)),
                    ("barrier", String(damageBarrierTurnsRemaining))
                ]
            )
        } else if consumeDungeonHazardDamageMitigation() {
            debugLog("\(logLabel)ダメージを成長効果で無効化: \(point), 残り=\(hazardDamageMitigationsRemaining)")
            appendDungeonRunLog(kind: .blocked, point: point, message: "\(logLabel)ダメージを成長効果で無効化")
            logDungeonPlayEvent(
                "damage_blocked",
                [
                    ("source", logLabel),
                    ("point", PlayDiagnosticLog.describe(point)),
                    ("reason", "growth"),
                    ("incoming", String(damage)),
                    ("mitigations", String(hazardDamageMitigationsRemaining))
                ]
            )
        } else if consumeDungeonDamageNullifyRelic(for: category) {
            debugLog("\(logLabel)ダメージをレリックで無効化: \(point), HP=\(dungeonHP)")
            appendDungeonRunLog(kind: .blocked, point: point, message: "\(logLabel)ダメージをレリックで無効化")
            logDungeonPlayEvent(
                "damage_blocked",
                [
                    ("source", logLabel),
                    ("point", PlayDiagnosticLog.describe(point)),
                    ("reason", "relic"),
                    ("incoming", String(damage))
                ]
            )
        } else {
            var adjustedDamage = max(damage, 1)
            if logLabel == "罠", hasDungeonCurse(.trapMagnet) {
                adjustedDamage += 1
            }
            if logLabel.hasPrefix("溶岩"), hasDungeonCurse(.oilSoakedBoots) {
                adjustedDamage += 1
            }
            if logLabel == "溶岩滞在", hasDungeonCurse(.firewalkingTalisman) {
                adjustedDamage += 1
            }
            if hasDungeonCurse(.scorchedCloak),
               logLabel == "罠" || logLabel.hasPrefix("溶岩") {
                adjustedDamage = max(adjustedDamage - 1, 0)
            }
            adjustedDamage = applyPersistentDungeonDamageReductionIfNeeded(to: adjustedDamage, category: category)
            let finalDamage = applyRelicDamageReductionIfNeeded(to: adjustedDamage)
            let hpBefore = dungeonHP
            applyDungeonHPDamage(finalDamage)
            if logLabel == "罠", finalDamage > 0 {
                triggerTrapperGlovesIfNeeded(reason: "ダメージ罠")
            }
            debugLog("\(logLabel)ダメージ: \(point), -\(finalDamage), HP=\(dungeonHP)")
            if finalDamage > 0 {
                appendDungeonHPChangeLog(
                    kind: .damage,
                    source: logLabel,
                    point: point,
                    hpBefore: hpBefore,
                    hpAfter: dungeonHP
                )
            } else {
                appendDungeonRunLog(kind: .blocked, point: point, message: "\(logLabel)ダメージを無効化")
            }
            logDungeonPlayEvent(
                "damage_applied",
                [
                    ("source", logLabel),
                    ("point", PlayDiagnosticLog.describe(point)),
                    ("base", String(damage)),
                    ("adjusted", String(adjustedDamage)),
                    ("final", String(finalDamage))
                ]
            )
        }
    }

    private func applyLavaWaitDamageIfNeeded() -> Bool {
        guard mode.usesDungeonExit, progress == .playing, let current else { return false }
        guard !isFlySpellActive else { return false }
        for hazard in mode.dungeonRules?.hazards ?? [] {
            guard case .lavaTile(let lavaPoints, let damage) = hazard, lavaPoints.contains(current) else { continue }
            applyDungeonHazardDamage(max(damage, 1), category: .lava, at: current, logLabel: "溶岩滞在")
            if shouldStopDungeonActionAfterDamage() {
                guard shouldFailDungeonRun() else { return true }
                finalizeElapsedTimeIfNeeded()
                progress = .failed
                return true
            }
            return false
        }
        return false
    }

    private func applyPoisonTrap() {
        if consumePurifyingRelicUse() != nil {
            debugLog("清めの護符で毒罠を無効化")
            return
        }
        let poisonTicks = poisonTrapDamageTicks + (hasDungeonCurse(.poisonVial) ? 1 : 0) - antidotePoisonTickReduction()
        poisonDamageTicksRemaining = max(poisonTicks, 1)
        poisonActionsUntilNextDamage = poisonTrapActionsPerDamage
        debugLog("毒罠を踏みました: 残り\(poisonDamageTicksRemaining)回, 次ダメージまで\(poisonActionsUntilNextDamage)行動")
        logDungeonPlayEvent(
            "poison_start",
            [
                ("ticks", String(poisonDamageTicksRemaining)),
                ("actionsUntilDamage", String(poisonActionsUntilNextDamage))
            ]
        )
    }

    private func applyPoisonTickAfterAction(skipsPoisonTick: Bool) -> Bool {
        guard poisonDamageTicksRemaining > 0 else { return false }
        if skipsPoisonTick {
            logDungeonPlayEvent(
                "poison_tick_skipped",
                [
                    ("ticks", String(poisonDamageTicksRemaining)),
                    ("actionsUntilDamage", String(poisonActionsUntilNextDamage))
                ]
            )
            return false
        }
        poisonActionsUntilNextDamage = max(poisonActionsUntilNextDamage - 1, 0)
        logDungeonPlayEvent(
            "poison_tick",
            [
                ("ticks", String(poisonDamageTicksRemaining)),
                ("actionsUntilDamage", String(poisonActionsUntilNextDamage))
            ]
        )
        guard poisonActionsUntilNextDamage == 0 else { return false }

        let damagePoint = current ?? GridPoint(x: 0, y: 0)
        applyDungeonHazardDamage(1, category: .other, at: damagePoint, logLabel: "毒")
        poisonDamageTicksRemaining = max(poisonDamageTicksRemaining - 1, 0)
        poisonActionsUntilNextDamage = poisonDamageTicksRemaining > 0 ? poisonTrapActionsPerDamage : 0
        if shouldStopDungeonActionAfterDamage() {
            guard shouldFailDungeonRun() else { return true }
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
        guard areDungeonRelicAndCurseEffectsEnabled else { return false }
        return dungeonRelicEntries.contains { $0.relicID == relicID }
    }

    private func hasDungeonCurse(_ curseID: DungeonCurseID) -> Bool {
        guard areDungeonRelicAndCurseEffectsEnabled else { return false }
        return dungeonCurseEntries.contains { $0.curseID == curseID }
    }

    private func consumeDungeonRelicUse(_ relicID: DungeonRelicID) -> Bool {
        guard areDungeonRelicAndCurseEffectsEnabled else { return false }
        guard let index = dungeonRelicEntries.firstIndex(where: { $0.relicID == relicID && $0.remainingUses > 0 }) else {
            return false
        }
        dungeonRelicEntries[index].remainingUses -= 1
        return true
    }

    private func consumePurifyingRelicUse() -> DungeonRelicID? {
        for relicID in [DungeonRelicID.purifyingCharm, .greatPurifyingCharm] where consumeDungeonRelicUse(relicID) {
            return relicID
        }
        return nil
    }

    private func antidotePoisonTickReduction() -> Int {
        var reduction = 0
        if hasDungeonRelic(.antidoteStone) {
            reduction += 1
        }
        if hasDungeonRelic(.greaterAntidoteStone) {
            reduction += 2
        }
        return reduction
    }

    private func consumeDungeonDamageNullifyRelic(for category: DungeonDamageCategory) -> Bool {
        if let relic = oneTimeDamageNullifyRelic(for: category), consumeDungeonRelicUse(relic) {
            return true
        }
        if category == .fall, consumeDungeonRelicUse(.blackFeather) {
            return true
        }
        if let relic = floorDamageNullifyRelic(for: category), consumeDungeonRelicUse(relic) {
            return true
        }
        return false
    }

    private func oneTimeDamageNullifyRelic(for category: DungeonDamageCategory) -> DungeonRelicID? {
        switch category {
        case .trap:
            return .silverNeedle
        case .lava:
            return .lavaCharm
        case .fall:
            return .oldRope
        case .watcher:
            return .watcherMask
        case .patrol:
            return .railWedge
        case .chaser:
            return .smokeDecoy
        case .meteor:
            return .starVeil
        case .other:
            return nil
        }
    }

    private func floorDamageNullifyRelic(for category: DungeonDamageCategory) -> DungeonRelicID? {
        switch category {
        case .trap:
            return .dullNeedle
        case .lava:
            return .lavaLantern
        case .fall:
            return .patchedRope
        case .watcher:
            return .guardianIncense
        case .patrol:
            return .railSign
        case .chaser:
            return .chaserWhistle
        case .meteor:
            return .guardianAegis
        case .other:
            return nil
        }
    }

    private func applyPersistentDungeonDamageReductionIfNeeded(to damage: Int, category: DungeonDamageCategory) -> Int {
        guard damage > 0, let relic = persistentDamageReductionRelic(for: category), hasDungeonRelic(relic) else {
            return damage
        }
        return max(damage - 1, 0)
    }

    private func persistentDamageReductionRelic(for category: DungeonDamageCategory) -> DungeonRelicID? {
        switch category {
        case .trap:
            return .trapSole
        case .lava:
            return .emberCloak
        case .fall:
            return .fallAnchor
        case .watcher:
            return .watcherMonocle
        case .patrol:
            return .railCharm
        case .chaser:
            return .chaserDecoy
        case .meteor:
            return .starUmbrella
        case .other:
            return nil
        }
    }

    private func triggerTrapperGlovesIfNeeded(reason: String) {
        guard areDungeonRelicAndCurseEffectsEnabled else { return }
        guard let index = dungeonRelicEntries.firstIndex(where: { $0.relicID == .trapperGloves && $0.remainingUses == 2 }) else {
            return
        }
        dungeonRelicEntries[index].remainingUses = 1
        debugLog("罠師の手袋が反応: \(reason), 次のクリア報酬の補助カード出現率+5pt")
    }

    private func consumeDungeonCurseUse(_ curseID: DungeonCurseID) -> Bool {
        guard areDungeonRelicAndCurseEffectsEnabled else { return false }
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
        if consumeDungeonCurseUse(.lastStandShield) {
            adjustedDamage = max(adjustedDamage - 3, 0)
        }
        if consumeDungeonRelicUse(.guardianAegis) {
            return max(adjustedDamage - 1, 0)
        }
        guard consumeDungeonRelicUse(.crackedShield) else { return adjustedDamage }
        return max(adjustedDamage - 1, 0)
    }

    private func applyDungeonHPDamage(_ damage: Int) {
        guard damage > 0 else { return }
        let nextHP = dungeonHP - damage
        if nextHP <= 0, consumeDungeonRelicUse(.phoenixFeather) {
            dungeonHP = 1
        } else {
            dungeonHP = max(nextHP, 0)
            if dungeonHP <= 0 {
                _ = triggerDungeonRewindReviveIfNeeded()
            }
        }
    }

    @discardableResult
    private func triggerDungeonRewindReviveIfNeeded() -> Bool {
        guard mode.usesDungeonExit,
              progress == .playing,
              dungeonRewindReviveEvent == nil,
              consumeDungeonRelicUse(.rewindingHourglass)
        else { return false }

        let sourceFloorIndex = mode.dungeonMetadataSnapshot?.runState?.currentFloorIndex ?? 0
        let destinationFloorIndex = selectedRewindReviveDestinationFloorIndex(from: sourceFloorIndex)
        dungeonHP = 1
        appendDungeonRunLog(
            kind: .healing,
            hpBefore: 0,
            hpAfter: dungeonHP,
            message: "逆巻きの砂時計で\(destinationFloorIndex + 1)Fへ復活（HP1）"
        )
        dungeonRewindReviveEvent = DungeonRewindReviveEvent(
            sourceFloorIndex: sourceFloorIndex,
            destinationFloorIndex: destinationFloorIndex,
            hpAfterRevive: dungeonHP
        )
        logDungeonPlayEvent(
            "rewind_revive",
            [
                ("sourceFloor", String(sourceFloorIndex + 1)),
                ("destinationFloor", String(destinationFloorIndex + 1))
            ]
        )
        return true
    }

    private func selectedRewindReviveDestinationFloorIndex(from sourceFloorIndex: Int) -> Int {
        guard sourceFloorIndex > 0 else { return 0 }
        var generator = DungeonRefillRandomGenerator(
            seed: rewindReviveSeed(sourceFloorIndex: sourceFloorIndex)
        )
        return Int(generator.next() % UInt64(sourceFloorIndex))
    }

    private func rewindReviveSeed(sourceFloorIndex: Int) -> UInt64 {
        var seed = mode.dungeonMetadataSnapshot?.runState?.cardVariationSeed
            ?? mode.dungeonMetadataSnapshot?.runState?.rogueTowerSeed
            ?? mode.deckSeed
            ?? 1
        seed ^= UInt64(sourceFloorIndex + 1) &* 0x9E37_79B9_7F4A_7C15
        seed ^= UInt64(max(moveCount, 0) + 1) &* 0xBF58_476D_1CE4_E5B9
        if let current {
            seed ^= UInt64(current.x + 31) &* 1099511628211
            seed ^= UInt64(current.y + 37) &* 1469598103934665603
        }
        for entry in dungeonRelicEntries {
            seed = seed &* 1099511628211 &+ UInt64(entry.remainingUses + 17)
            for scalar in entry.relicID.rawValue.unicodeScalars {
                seed = seed &* 1469598103934665603 &+ UInt64(scalar.value)
            }
        }
        return seed == 0 ? 1 : seed
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
        skipsPoisonTick: Bool,
        previousMoveCount: Int
    ) -> Bool {
        guard mode.usesDungeonExit else { return false }
        guard progress == .playing, dungeonFallEvent == nil else { return true }
        logDungeonPlayEvent(
            "post_action_start",
            [
                ("traversed", PlayDiagnosticLog.describe(traversedPoints)),
                ("markerWarnings", PlayDiagnosticLog.describe(initialMarkerDamagePoints ?? enemyWarningPoints)),
                ("paralysis", PlayDiagnosticLog.describe(paralysisTrapPoint)),
                ("enemyTurns", String(max(currentShackleEnemyTurnCount, paralysisTrapPoint == nil ? 1 : 2))),
                ("skipPoison", String(skipsPoisonTick))
            ]
        )
        updateDungeonExitLockIfNeeded()
        if current == mode.dungeonExitPoint, isDungeonExitUnlocked {
            finalizeElapsedTimeIfNeeded()
            progress = .cleared
            logDungeonPlayEvent("run_end", [("reason", "exit")])
            return true
        }
        if traversedPoints.count <= 1, traversedPoints.last == mode.dungeonExitPoint {
            publishLockedDungeonExitReachEventIfNeeded()
        }
        if applyPoisonTickAfterAction(skipsPoisonTick: skipsPoisonTick) {
            return true
        }

        var phases: [DungeonEnemyTurnPhase] = []
        let baseEnemyTurnCount = max(currentShackleEnemyTurnCount, paralysisTrapPoint == nil ? 1 : 2)
        let enemyTurnCount = shouldSkipSleepingWarDrumEnemyTurn() ? 0 : baseEnemyTurnCount
        for turnIndex in 0..<enemyTurnCount {
            let pendingMarkerDamagePoints = turnIndex == 0
                ? initialMarkerDamagePoints ?? enemyWarningPoints
                : enemyWarningPoints
            if consumeDefeatEnemyTurnSkipIfNeeded() {
                continue
            }
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
            if shouldStopDungeonActionAfterDamage() {
                publishDungeonEnemyTurnEventIfNeeded(
                    phases: phases,
                    paralysisTrapPoint: paralysisTrapPoint
                )
                guard shouldFailDungeonRun() else { return true }
                finalizeElapsedTimeIfNeeded()
                progress = .failed
                logDungeonPlayEvent(
                    "run_end",
                    [
                        ("reason", "enemyDamage"),
                        ("phases", String(phases.count))
                    ]
                )
                return true
            }
        }
        publishDungeonEnemyTurnEventIfNeeded(
            phases: phases,
            paralysisTrapPoint: paralysisTrapPoint
        )
        consumeDamageBarrierTurnIfNeeded()
        if applyDungeonFatigueDamageIfNeeded(previousMoveCount: previousMoveCount) {
            guard shouldFailDungeonRun() else { return true }
            finalizeElapsedTimeIfNeeded()
            progress = .failed
            logDungeonPlayEvent("run_end", [("reason", "fatigue")])
            return true
        }
        return false
    }

    private func shouldSkipSleepingWarDrumEnemyTurn() -> Bool {
        hasDungeonCurse(.sleepingWarDrum) && moveCount % 2 == 1
    }

    @discardableResult
    private func triggerDungeonFall(at point: GridPoint) -> Bool {
        if isDamageBarrierActive {
            debugLog("床崩落ダメージを障壁で無効化: \(point), HP=\(dungeonHP), 残り=\(damageBarrierTurnsRemaining)")
            appendDungeonRunLog(kind: .blocked, point: point, message: "床崩落ダメージを障壁で無効化")
        } else if consumeDungeonHazardDamageMitigation() {
            debugLog("床崩落ダメージを成長効果で無効化: \(point), HP=\(dungeonHP), 残り=\(hazardDamageMitigationsRemaining)")
            appendDungeonRunLog(kind: .blocked, point: point, message: "床崩落ダメージを成長効果で無効化")
        } else if consumeDungeonDamageNullifyRelic(for: .fall) {
            debugLog("レリックで床崩落ダメージを無効化: \(point), HP=\(dungeonHP)")
            appendDungeonRunLog(kind: .blocked, point: point, message: "床崩落ダメージをレリックで無効化")
        } else {
            var baseFallDamage = 1 + (hasDungeonCurse(.glassAnklet) ? 1 : 0)
            if hasDungeonCurse(.scorchedCloak) {
                baseFallDamage = max(baseFallDamage - 1, 0)
            }
            let adjustedFallDamage = applyPersistentDungeonDamageReductionIfNeeded(to: baseFallDamage, category: .fall)
            let fallDamage = applyRelicDamageReductionIfNeeded(to: adjustedFallDamage)
            let hpBefore = dungeonHP
            applyDungeonHPDamage(fallDamage)
            debugLog("床崩落で下階へ落下: \(point), HP=\(dungeonHP)")
            if fallDamage > 0 {
                appendDungeonHPChangeLog(
                    kind: .damage,
                    source: "床崩落",
                    point: point,
                    hpBefore: hpBefore,
                    hpAfter: dungeonHP
                )
            } else {
                appendDungeonRunLog(kind: .blocked, point: point, message: "床崩落ダメージを無効化")
            }
        }
        if shouldStopDungeonActionAfterDamage() {
            guard shouldFailDungeonRun() else { return true }
            finalizeElapsedTimeIfNeeded()
            progress = .failed
            logDungeonPlayEvent("run_end", [("reason", "fallDamage"), ("point", PlayDiagnosticLog.describe(point))])
            return true
        }

        let sourceFloorIndex = mode.dungeonMetadataSnapshot?.runState?.currentFloorIndex ?? 0
        guard sourceFloorIndex > 0 else {
            finalizeElapsedTimeIfNeeded()
            progress = .failed
            debugLog("床崩落の落下先がないため失敗: \(point), sourceFloorIndex=\(sourceFloorIndex)")
            logDungeonPlayEvent(
                "run_end",
                [
                    ("reason", "fallNoDestination"),
                    ("point", PlayDiagnosticLog.describe(point)),
                    ("sourceFloor", String(sourceFloorIndex + 1))
                ]
            )
            return true
        }
        dungeonFallEvent = DungeonFallEvent(
            point: point,
            sourceFloorIndex: sourceFloorIndex,
            destinationFloorIndex: sourceFloorIndex - 1,
            hpAfterDamage: dungeonHP
        )
        logDungeonPlayEvent(
            "fall",
            [
                ("point", PlayDiagnosticLog.describe(point)),
                ("sourceFloor", String(sourceFloorIndex + 1)),
                ("destinationFloor", String(sourceFloorIndex))
            ]
        )
        consumeDamageBarrierTurnIfNeeded()
        return true
    }

    public func clearDungeonFallEvent(_ id: UUID) {
        guard dungeonFallEvent?.id == id else { return }
        dungeonFallEvent = nil
    }

    public func clearDungeonRewindReviveEvent(_ id: UUID) {
        guard dungeonRewindReviveEvent?.id == id else { return }
        dungeonRewindReviveEvent = nil
    }

    public func clearDungeonLockedExitReachEvent(_ id: UUID) {
        guard dungeonLockedExitReachEvent?.id == id else { return }
        dungeonLockedExitReachEvent = nil
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

        if isFlySpellActive {
            debugLog("フライの呪文で落下先の脆い床/崩落床を無効化: \(point)")
            return false
        } else if collapsedFloorPoints.contains(point) {
            debugLog("崩落済みの落下先から連鎖落下: \(point)")
            return triggerDungeonFall(at: point)
        } else if crackedFloorPoints.contains(point)
                    || initialCrackedBrittleFloorPoints.contains(point)
                    || hiddenWeakBrittleFloorPoints.contains(point) {
            crackedFloorPoints.remove(point)
            collapsedFloorPoints.insert(point)
            debugLog("落下先の脆い床が崩落穴化: \(point)")
            return false
        } else {
            collapsedFloorPoints.insert(point)
            debugLog("落下先の脆い床が崩落穴化: \(point)")
            return false
        }
    }

    @discardableResult
    private func updateDungeonExitLockIfNeeded(
        at point: GridPoint? = nil,
        publishesEvent: Bool = true
    ) -> DungeonExitUnlockEvent? {
        guard mode.usesDungeonExit,
              !isDungeonExitUnlocked,
              let exitLock = mode.dungeonRules?.exitLock,
              (point ?? current) == exitLock.unlockPoint
        else { return nil }

        isDungeonExitUnlocked = true
        var event: DungeonExitUnlockEvent?
        if let exitPoint = mode.dungeonExitPoint {
            event = DungeonExitUnlockEvent(
                exitPoint: exitPoint,
                unlockPoint: exitLock.unlockPoint
            )
            if publishesEvent {
                dungeonExitUnlockEvent = event
            }
        }
        debugLog("ダンジョン出口を解錠: key=\(exitLock.unlockPoint)")
        return event
    }

    private func publishLockedDungeonExitReachEventIfNeeded() {
        guard mode.usesDungeonExit,
              progress == .playing,
              !isDungeonExitUnlocked,
              let exitPoint = mode.dungeonExitPoint,
              current == exitPoint
        else { return }

        if dungeonLockedExitReachEvent == nil {
            dungeonLockedExitReachEvent = DungeonLockedExitReachEvent(exitPoint: exitPoint)
        }
        debugLog("施錠中の階段へ到達: \(exitPoint)")
    }

    private func pendingLockedDungeonExitReachEvent(
        at point: GridPoint,
        isFinalPathStep: Bool
    ) -> DungeonLockedExitReachEvent? {
        guard isFinalPathStep,
              mode.usesDungeonExit,
              progress == .playing,
              !isDungeonExitUnlocked,
              point == mode.dungeonExitPoint
        else { return nil }
        return DungeonLockedExitReachEvent(exitPoint: point)
    }

    private func publishImmediateMovementPresentationEventsIfNeeded(
        from steps: [MovementResolution.PresentationStep],
        actualTraversedPath: [GridPoint]
    ) {
        guard actualTraversedPath.count <= 1 else { return }
        for step in steps {
            if let event = step.dungeonExitUnlockEvent {
                dungeonExitUnlockEvent = event
            }
            if let event = step.dungeonLockedExitReachEvent, dungeonLockedExitReachEvent == nil {
                dungeonLockedExitReachEvent = event
            }
        }
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

        let before = enemyStates
        var occupiedPoints = Set(enemyStates.map(\.position))
        var defeatedEnemyIDs: Set<String> = []
        for index in enemyStates.indices {
            guard !defeatedEnemyIDs.contains(enemyStates[index].id) else { continue }
            switch enemyStates[index].behavior {
            case .guardPost, .watcher:
                break
            case .patrol(let path):
                guard !isPatrolRailDestroyed else { continue }
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
                guard !shouldMovingEnemyAttackBeforeMoving(enemyStates[index]) else { continue }
                enemyStates[index].rotationIndex = (enemyStates[index].rotationIndex + 1) % 4
            case .chaser:
                guard !shouldMovingEnemyAttackBeforeMoving(enemyStates[index]) else { continue }
                guard let current,
                      let nextPoint = chaserNextStep(
                        from: enemyStates[index].position,
                        toward: current,
                        avoiding: occupiedPoints
                      )
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
                if isEnemyLethalHazardPoint(nextPoint) {
                    defeatedEnemyIDs.insert(enemyStates[index].id)
                    occupiedPoints.remove(nextPoint)
                }
            case .marker, .targetedMarker:
                if enemyStates[index].rotationIndex == Int.max {
                    enemyStates[index].rotationIndex = 0
                } else {
                    enemyStates[index].rotationIndex += 1
                }
            }
        }
        if !defeatedEnemyIDs.isEmpty {
            enemyStates.removeAll { defeatedEnemyIDs.contains($0.id) }
        }
        logDungeonPlayEvent(
            "enemy_turn",
            [
                ("before", diagnosticEnemyDescription(before)),
                ("after", diagnosticEnemyDescription(enemyStates)),
                ("warnings", PlayDiagnosticLog.describe(enemyWarningPoints)),
                ("freeze", String(enemyFreezeTurnsRemaining)),
                ("shackled", String(isShackled))
            ]
        )
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
            case .guardPost, .watcher, .rotatingWatcher, .marker, .targetedMarker:
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
              let nextPoint = chaserNextStep(
                from: enemy.position,
                toward: current,
                avoiding: occupiedPoints
              ),
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

        let source = dungeonEnemyDamageSourceText(damage)

        if isDamageBarrierActive {
            debugLog("敵/メテオダメージを障壁で無効化: 敵=\(damage.enemy), メテオ=\(damage.marker), 残り=\(damageBarrierTurnsRemaining)")
            appendDungeonRunLog(kind: .blocked, message: "\(source)ダメージを障壁で無効化")
            return 0
        }

        if damage.enemy > 0, consumeDungeonEnemyDamageMitigation() {
            totalDamage -= damage.enemy
            debugLog("敵ダメージを成長効果で無効化: -\(damage.enemy), 残り=\(enemyDamageMitigationsRemaining)")
            appendDungeonRunLog(kind: .blocked, message: "\(dungeonEnemySourceListText(damage.enemySources))ダメージを成長効果で無効化")
        }
        if damage.marker > 0, consumeDungeonMarkerDamageMitigation() {
            totalDamage -= damage.marker
            debugLog("メテオ着弾ダメージを成長効果で無効化: -\(damage.marker), 残り=\(markerDamageMitigationsRemaining)")
            appendDungeonRunLog(kind: .blocked, message: "\(dungeonMarkerSourceListText(damage.markerSources))を成長効果で無効化")
        }
        if totalDamage > 0 {
            totalDamage = applyEnemyDamageNullifications(
                to: totalDamage,
                components: damage.components,
                includeEnemy: damage.enemy > 0,
                includeMarker: damage.marker > 0
            )
        }

        let finalDamage = applyRelicDamageReductionIfNeeded(to: totalDamage)
        guard finalDamage > 0 else {
            appendDungeonRunLog(kind: .blocked, message: "\(source)ダメージを無効化")
            return 0
        }
        let hpBefore = dungeonHP
        applyDungeonHPDamage(finalDamage)
        debugLog("敵の攻撃を受けました: -\(finalDamage), HP=\(dungeonHP)")
        appendDungeonHPChangeLog(
            kind: .damage,
            source: source,
            hpBefore: hpBefore,
            hpAfter: dungeonHP
        )
        logDungeonPlayEvent(
            "enemy_damage",
            [
                ("enemy", String(damage.enemy)),
                ("marker", String(damage.marker)),
                ("final", String(finalDamage)),
                ("markerWarnings", PlayDiagnosticLog.describe(markerDamagePoints))
            ]
        )
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
        let source = dungeonEnemyDamageActorText(damage)
        if isDamageBarrierActive {
            debugLog("敵の攻撃範囲通過ダメージを障壁で無効化: \(point), 残り=\(damageBarrierTurnsRemaining)")
            appendDungeonRunLog(kind: .blocked, point: point, message: "\(source)の攻撃範囲通過を障壁で無効化")
            return false
        }
        if damage.enemy > 0, consumeDungeonEnemyDamageMitigation() {
            totalDamage -= damage.enemy
            debugLog("敵の攻撃範囲通過ダメージを成長効果で無効化: \(point), 残り=\(enemyDamageMitigationsRemaining)")
            appendDungeonRunLog(kind: .blocked, point: point, message: "\(source)の攻撃範囲通過を成長効果で無効化")
        }
        if totalDamage > 0 {
            totalDamage = applyEnemyDamageNullifications(
                to: totalDamage,
                components: damage.components,
                includeEnemy: damage.enemy > 0,
                includeMarker: false
            )
        }
        let finalDamage = applyRelicDamageReductionIfNeeded(to: totalDamage)
        guard finalDamage > 0 else {
            appendDungeonRunLog(kind: .blocked, point: point, message: "\(source)の攻撃範囲通過を無効化")
            return false
        }
        let hpBefore = dungeonHP
        applyDungeonHPDamage(finalDamage)
        debugLog("敵の攻撃範囲を通過しました: \(point), -\(finalDamage), HP=\(dungeonHP)")
        appendDungeonHPChangeLog(
            kind: .damage,
            source: "\(source)の攻撃範囲通過",
            point: point,
            hpBefore: hpBefore,
            hpAfter: dungeonHP
        )
        logDungeonPlayEvent(
            "enemy_danger_crossed",
            [
                ("point", PlayDiagnosticLog.describe(point)),
                ("enemy", String(damage.enemy)),
                ("marker", String(damage.marker)),
                ("final", String(finalDamage))
            ]
        )
        if shouldStopDungeonActionAfterDamage() {
            guard shouldFailDungeonRun() else { return true }
            finalizeElapsedTimeIfNeeded()
            progress = .failed
            logDungeonPlayEvent("run_end", [("reason", "dangerCrossing")])
            return true
        }
        return false
    }

    private func dungeonEnemyDamage(
        at point: GridPoint,
        markerDamagePoints: Set<GridPoint>,
        includesContact: Bool,
        includesMarkerWarning: Bool,
        rotatingWatcherOffset: Int = 0
    ) -> (
        enemy: Int,
        marker: Int,
        enemySources: [String],
        markerSources: [String],
        components: [DungeonEnemyDamageComponent]
    ) {
        guard !isEnemyFreezeActive else { return (0, 0, [], [], []) }
        var enemyDamage = 0
        var markerDamage = 0
        var enemySources: [String] = []
        var markerSources: [String] = []
        var components: [DungeonEnemyDamageComponent] = []

        for enemy in enemyStates {
            if enemyDangerPoints(for: enemy, rotatingWatcherOffset: rotatingWatcherOffset).contains(point) {
                let sourceDamage = adjustedEnemySourceDamage(for: enemy, isMarkerWarning: false)
                enemyDamage += sourceDamage
                if sourceDamage > 0 {
                    let source = enemy.behavior.presentationKind.displayName
                    enemySources.append(source)
                    components.append(
                        DungeonEnemyDamageComponent(
                            category: damageCategory(for: enemy.behavior, isMarkerWarning: false),
                            amount: sourceDamage,
                            source: source,
                            isMarker: false
                        )
                    )
                }
            } else if includesContact, enemy.position == point {
                let sourceDamage = adjustedEnemySourceDamage(for: enemy, isMarkerWarning: false)
                enemyDamage += sourceDamage
                if sourceDamage > 0 {
                    let source = enemy.behavior.presentationKind.displayName
                    enemySources.append(source)
                    components.append(
                        DungeonEnemyDamageComponent(
                            category: damageCategory(for: enemy.behavior, isMarkerWarning: false),
                            amount: sourceDamage,
                            source: source,
                            isMarker: false
                        )
                    )
                }
            } else if includesMarkerWarning, enemy.behavior.isMeteorWarningBehavior, markerDamagePoints.contains(point) {
                let sourceDamage = adjustedEnemySourceDamage(for: enemy, isMarkerWarning: true)
                markerDamage += sourceDamage
                if sourceDamage > 0 {
                    let source = enemy.behavior.presentationKind.displayName
                    markerSources.append(source)
                    components.append(
                        DungeonEnemyDamageComponent(
                            category: damageCategory(for: enemy.behavior, isMarkerWarning: true),
                            amount: sourceDamage,
                            source: source,
                            isMarker: true
                        )
                    )
                }
            }
        }
        return (enemyDamage, markerDamage, enemySources, markerSources, components)
    }

    private func dungeonEnemyDamageActorText(
        _ damage: (
            enemy: Int,
            marker: Int,
            enemySources: [String],
            markerSources: [String],
            components: [DungeonEnemyDamageComponent]
        )
    ) -> String {
        if damage.enemy > 0 {
            let uniqueSources = uniqueDungeonDamageSources(damage.enemySources)
            return uniqueSources.isEmpty ? "敵" : uniqueSources.joined(separator: "・")
        }
        if damage.marker > 0 {
            return dungeonMarkerSourceListText(damage.markerSources)
        }
        return "敵"
    }

    private func dungeonEnemyDamageSourceText(
        _ damage: (
            enemy: Int,
            marker: Int,
            enemySources: [String],
            markerSources: [String],
            components: [DungeonEnemyDamageComponent]
        )
    ) -> String {
        if damage.enemy > 0, damage.marker > 0 {
            return "\(dungeonEnemySourceListText(damage.enemySources)) + \(dungeonMarkerSourceListText(damage.markerSources))"
        }
        if damage.marker > 0 {
            return dungeonMarkerSourceListText(damage.markerSources)
        }
        return dungeonEnemySourceListText(damage.enemySources)
    }

    private func dungeonEnemySourceListText(_ sources: [String]) -> String {
        let uniqueSources = uniqueDungeonDamageSources(sources)
        guard !uniqueSources.isEmpty else { return "敵攻撃" }
        return uniqueSources.joined(separator: "・") + "の攻撃"
    }

    private func dungeonMarkerSourceListText(_ sources: [String]) -> String {
        let uniqueSources = uniqueDungeonDamageSources(sources)
        guard !uniqueSources.isEmpty else { return "メテオ" }
        return uniqueSources.joined(separator: "・") + "のメテオ"
    }

    private func uniqueDungeonDamageSources(_ sources: [String]) -> [String] {
        var seen: Set<String> = []
        var uniqueSources: [String] = []
        for source in sources where !seen.contains(source) {
            seen.insert(source)
            uniqueSources.append(source)
        }
        return uniqueSources
    }

    private func applyEnemyDamageNullifications(
        to totalDamage: Int,
        components: [DungeonEnemyDamageComponent],
        includeEnemy: Bool,
        includeMarker: Bool
    ) -> Int {
        var remainingDamage = totalDamage
        var consumedCategories: Set<DungeonDamageCategory> = []
        for component in components where component.amount > 0 {
            guard component.isMarker ? includeMarker : includeEnemy else { continue }
            guard !consumedCategories.contains(component.category) else { continue }
            guard consumeDungeonDamageNullifyRelic(for: component.category) else { continue }
            consumedCategories.insert(component.category)
            remainingDamage = max(remainingDamage - component.amount, 0)
            debugLog("\(component.source)ダメージをレリックで無効化: -\(component.amount), 残り=\(remainingDamage)")
            appendDungeonRunLog(kind: .blocked, message: "\(component.source)ダメージをレリックで無効化")
        }
        return remainingDamage
    }

    private func adjustedEnemySourceDamage(for enemy: EnemyState, isMarkerWarning: Bool) -> Int {
        var damage = enemy.damage + curseDamageBonus(for: enemy.behavior, isMarkerWarning: isMarkerWarning)
        if hasDungeonCurse(.sleepingWarDrum) {
            damage *= 3
        }
        damage -= curseDamageReductionBonus(for: enemy.behavior, isMarkerWarning: isMarkerWarning)
        damage -= persistentDamageReductionBonus(for: enemy.behavior, isMarkerWarning: isMarkerWarning)
        return max(damage, 0)
    }

    private func damageCategory(for behavior: EnemyBehavior, isMarkerWarning: Bool) -> DungeonDamageCategory {
        switch behavior {
        case .watcher, .rotatingWatcher:
            return .watcher
        case .patrol:
            return .patrol
        case .chaser:
            return .chaser
        case .marker, .targetedMarker:
            return isMarkerWarning ? .meteor : .other
        case .guardPost:
            return .other
        }
    }

    private func curseDamageBonus(for behavior: EnemyBehavior, isMarkerWarning: Bool) -> Int {
        switch behavior {
        case .watcher, .rotatingWatcher:
            return hasDungeonCurse(.watchersBrand) ? 1 : 0
        case .patrol:
            return hasDungeonCurse(.patrolBell) ? 1 : 0
        case .chaser:
            return hasDungeonCurse(.chaserScent) ? 1 : 0
        case .marker, .targetedMarker:
            return isMarkerWarning && hasDungeonCurse(.meteorRod) ? 1 : 0
        case .guardPost:
            return 0
        }
    }

    private func curseDamageReductionBonus(for behavior: EnemyBehavior, isMarkerWarning: Bool) -> Int {
        guard hasDungeonCurse(.hasteArmor) else { return 0 }
        switch behavior {
        case .watcher, .rotatingWatcher, .patrol, .chaser:
            return 1
        case .marker, .targetedMarker:
            return isMarkerWarning ? 1 : 0
        case .guardPost:
            return 0
        }
    }

    private func persistentDamageReductionBonus(for behavior: EnemyBehavior, isMarkerWarning: Bool) -> Int {
        let category = damageCategory(for: behavior, isMarkerWarning: isMarkerWarning)
        if let relic = persistentDamageReductionRelic(for: category), hasDungeonRelic(relic) {
            return 1
        }
        guard hasDungeonRelic(.guardianCloak) else { return 0 }
        switch behavior {
        case .watcher, .rotatingWatcher, .patrol, .chaser, .marker, .targetedMarker:
            return 1
        case .guardPost:
            return 0
        }
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
        return false
    }

    private func shouldStopDungeonActionAfterDamage() -> Bool {
        dungeonRewindReviveEvent != nil || shouldFailDungeonRun()
    }

    private func applyDungeonFatigueDamageIfNeeded(previousMoveCount: Int) -> Bool {
        guard mode.usesDungeonExit, progress == .playing else { return false }
        guard let turnLimit = effectiveDungeonTurnLimit else { return false }
        let previousOvertime = max(previousMoveCount - turnLimit, 0)
        let currentOvertime = max(moveCount - turnLimit, 0)
        guard currentOvertime > previousOvertime else { return false }

        let fatigueDamagePerStep = 1 + dungeonFatigueDamageBonus()
        let damage = (previousOvertime + 1...currentOvertime).reduce(0) { partialResult, overtimeTurn in
            guard overtimeTurn == 1 || (overtimeTurn - 1).isMultiple(of: Self.overtimeFatigueInterval) else {
                return partialResult
            }
            return partialResult + fatigueDamagePerStep
        }
        guard damage > 0 else { return false }

        let hpBefore = dungeonHP
        applyDungeonHPDamage(damage)
        debugLog("手数超過の疲労ダメージ: 超過=\(currentOvertime), -\(damage), HP=\(dungeonHP)")
        appendDungeonHPChangeLog(
            kind: .damage,
            source: "疲労",
            hpBefore: hpBefore,
            hpAfter: dungeonHP
        )
        logDungeonPlayEvent(
            "fatigue_damage",
            [
                ("turnLimit", String(turnLimit)),
                ("previousOvertime", String(previousOvertime)),
                ("currentOvertime", String(currentOvertime)),
                ("damage", String(damage))
            ]
        )
        return shouldStopDungeonActionAfterDamage()
    }

    private func dungeonFatigueDamageBonus() -> Int {
        var bonus = 0
        if hasDungeonCurse(.hasteArmor) {
            bonus += 1
        }
        if hasDungeonCurse(.scorchedCloak) {
            bonus += 1
        }
        if hasDungeonCurse(.expressTicket) {
            bonus += 1
        }
        return bonus
    }

    private func consumeEnemyFreezeTurnIfNeeded() -> Bool {
        guard enemyFreezeTurnsRemaining > 0 else { return false }
        enemyFreezeTurnsRemaining -= 1
        debugLog("凍結中のため敵ターンを停止: 残り=\(enemyFreezeTurnsRemaining)")
        logDungeonPlayEvent("enemy_turn_skipped", [("reason", "freeze"), ("freeze", String(enemyFreezeTurnsRemaining))])
        return true
    }

    private func consumeDefeatEnemyTurnSkipIfNeeded() -> Bool {
        guard pendingDefeatEnemyTurnSkip else { return false }
        pendingDefeatEnemyTurnSkip = false
        debugLog("威圧の角笛で敵ターンを停止")
        logDungeonPlayEvent("enemy_turn_skipped", [("reason", "defeat_relic")])
        return true
    }

    private func consumeDamageBarrierTurnIfNeeded() {
        guard damageBarrierTurnsRemaining > 0 else { return }
        damageBarrierTurnsRemaining -= 1
        debugLog("障壁の残り回数を消費: 残り=\(damageBarrierTurnsRemaining)")
        logDungeonPlayEvent("barrier_tick", [("barrier", String(damageBarrierTurnsRemaining))])
    }

    private func attackOrContactPoints(for enemy: EnemyState) -> Set<GridPoint> {
        var points = enemyDangerPoints(for: enemy)
        points.insert(enemy.position)
        return points
    }

    private func enemyDangerPoints(for enemy: EnemyState, rotatingWatcherOffset: Int = 0) -> Set<GridPoint> {
        guard !isEnemyFreezeActive else { return [] }
        return dangerPoints(for: [enemy], rotatingWatcherOffset: rotatingWatcherOffset)
    }

    private var hasWatcherLaserEnemy: Bool {
        enemyStates.contains { enemy in
            switch enemy.behavior {
            case .watcher, .rotatingWatcher:
                return true
            case .guardPost, .patrol, .chaser, .marker, .targetedMarker:
                return false
            }
        }
    }

    private var hasPatrolRailEnemy: Bool {
        enemyStates.contains { enemy in
            if case .patrol = enemy.behavior { return true }
            return false
        }
    }

    private func dangerPoints(for enemies: [EnemyState], rotatingWatcherOffset: Int = 0) -> Set<GridPoint> {
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
                guard !isWatcherLaserSuppressed else { break }
                insertLineOfSightDanger(
                    from: enemy.position,
                    direction: direction,
                    into: &danger
                )
            case .rotatingWatcher:
                guard !isWatcherLaserSuppressed else { break }
                guard let direction = rotatingWatcherDirection(for: enemy, offset: rotatingWatcherOffset) else { break }
                insertLineOfSightDanger(
                    from: enemy.position,
                    direction: direction,
                    into: &danger
                )
            case .marker, .targetedMarker:
                break
            }
        }
        return danger
    }

    private func markerWarningPoints(for enemies: [EnemyState]) -> Set<GridPoint> {
        var warning: Set<GridPoint> = []
        for enemy in enemies {
            switch enemy.behavior {
            case .marker(_, let range):
                warning.formUnion(meteorWarningPoints(for: enemy, targetCount: range, enemyStates: enemies))
            case .targetedMarker(_, let range):
                var targetedWarning = meteorWarningPoints(for: enemy, targetCount: range, enemyStates: enemies)
                if let current, board.isTraversable(current), !collapsedFloorPoints.contains(current) {
                    targetedWarning.insert(current)
                }
                warning.formUnion(targetedWarning)
            case .guardPost, .patrol, .watcher, .rotatingWatcher, .chaser:
                continue
            }
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

    private func chaserNextStep(
        from origin: GridPoint,
        toward target: GridPoint,
        avoiding blockedPoints: Set<GridPoint> = []
    ) -> GridPoint? {
        let lethalHazardPoints = enemyLethalHazardPoints
        return chaserNextStep(
            from: origin,
            toward: target,
            avoiding: blockedPoints,
            avoidingHazards: lethalHazardPoints
        ) ?? chaserNextStep(
            from: origin,
            toward: target,
            avoiding: blockedPoints,
            avoidingHazards: []
        )
    }

    private func chaserNextStep(
        from origin: GridPoint,
        toward target: GridPoint,
        avoiding blockedPoints: Set<GridPoint>,
        avoidingHazards hazardPoints: Set<GridPoint>
    ) -> GridPoint? {
        guard origin != target,
              board.contains(origin),
              board.contains(target),
              isEnemyTraversable(target)
        else {
            return nil
        }

        func canChaserEnter(_ point: GridPoint) -> Bool {
            isEnemyTraversable(point)
                && (!blockedPoints.contains(point) || point == origin || point == target)
                && (!hazardPoints.contains(point) || point == origin || point == target)
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
                guard canChaserEnter(next),
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

    private var enemyLethalHazardPoints: Set<GridPoint> {
        damageTrapPoints.union(lavaTilePoints)
    }

    private func isEnemyLethalHazardPoint(_ point: GridPoint) -> Bool {
        enemyLethalHazardPoints.contains(point)
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
        danger.formUnion(lineOfSightDangerPoints(from: origin, direction: direction))
    }

    private func lineOfSightDangerPoints(from origin: GridPoint, direction: MoveVector) -> [GridPoint] {
        let dx = direction.dx == 0 ? 0 : (direction.dx > 0 ? 1 : -1)
        let dy = direction.dy == 0 ? 0 : (direction.dy > 0 ? 1 : -1)
        guard dx != 0 || dy != 0 else { return [] }

        var points: [GridPoint] = []
        var step = 1
        while true {
            let point = origin.offset(dx: dx * step, dy: dy * step)
            guard isEnemyTraversable(point) else { break }
            points.append(point)
            step += 1
        }
        return points
    }

    private func normalizedLaserDirection(_ direction: MoveVector) -> MoveVector {
        MoveVector(
            dx: direction.dx == 0 ? 0 : (direction.dx > 0 ? 1 : -1),
            dy: direction.dy == 0 ? 0 : (direction.dy > 0 ? 1 : -1)
        )
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
        guard pendingDungeonRelicPickupChoice == nil else { return }

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

    /// GameCore 単体では長押し説明を扱わない。UI 側の ViewModel が辞典表示へ解決する。
    public func handleLongPress(at point: GridPoint) {}
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
        core.isWatcherLaserSuppressed = false
        core.isPatrolRailDestroyed = false
        core.isFlySpellActive = false
        core.isIlluded = false
        core.staggerForcedMovesRemaining = 0
        core.enemyStates = mode.dungeonRules?.enemies.map(EnemyState.init(definition:)) ?? []
        core.didStartCurrentFloorWithEnemies = !core.enemyStates.isEmpty
        let currentFloorIndex = mode.dungeonMetadataSnapshot?.runState?.currentFloorIndex ?? 0
        let savedCrackedFloorPoints = mode.dungeonMetadataSnapshot?.runState?.crackedFloorPoints(for: currentFloorIndex) ?? []
        let savedCollapsedFloorPoints = mode.dungeonMetadataSnapshot?.runState?.collapsedFloorPoints(for: currentFloorIndex) ?? []
        let initialAndSavedCollapsedFloorPoints = core.initialCollapsedBrittleFloorPoints.union(savedCollapsedFloorPoints)
        core.crackedFloorPoints = core.initialCrackedBrittleFloorPoints
            .union(savedCrackedFloorPoints)
            .subtracting(initialAndSavedCollapsedFloorPoints)
        core.collapsedFloorPoints = initialAndSavedCollapsedFloorPoints
        core.consumedHealingTilePoints = []
        core.isDungeonExitUnlocked = mode.dungeonRules?.exitLock == nil
        core.dungeonExitUnlockEvent = nil
        core.dungeonLockedExitReachEvent = nil
        core.dungeonFallEvent = nil
        core.dungeonRewindReviveEvent = nil
        core.dungeonEnemyTurnEvent = nil
        core.pendingTargetedSupportCard = nil
        core.progress = (resolvedCurrent == nil && mode.requiresSpawnSelection) ? .awaitingSpawn : .playing
        core.dungeonRelicEntries = mode.dungeonMetadataSnapshot?.runState?.relicEntries ?? []
        core.dungeonCurseEntries = mode.dungeonMetadataSnapshot?.runState?.curseEntries ?? []
        core.applyFloorStartDungeonRelicStatusEffects()
        core.applyFloorStartDungeonCurseStatusEffects()

        if core.usesDungeonInventoryCards {
            core.dungeonInventoryEntries = mode.dungeonMetadataSnapshot?.runState?.rewardInventoryEntries ?? []
            core.collectedDungeonCardPickupIDs = []
            core.collectedDungeonSpecialPickupIDs = []
            core.currentDungeonInventoryKindLimit = mode.dungeonMetadataSnapshot?.runState?.dungeonInventoryKindLimit
            core.pendingDungeonPickupChoice = nil
            core.pendingDungeonRelicPickupChoice = nil
            core.dungeonRelicEntries = mode.dungeonMetadataSnapshot?.runState?.relicEntries ?? []
            core.dungeonCurseEntries = mode.dungeonMetadataSnapshot?.runState?.curseEntries ?? []
            core.applyFloorStartDungeonRelicStatusEffects()
            core.applyFloorStartDungeonCurseStatusEffects()
            core.collectedDungeonRelicPickupIDs = mode.dungeonMetadataSnapshot?.runState?.collectedDungeonRelicPickupIDs ?? []
            core.dungeonRelicAcquisitionPresentations = []
            core.dungeonRunLogEntries = mode.dungeonMetadataSnapshot?.runState?.runLogEntries ?? []
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
