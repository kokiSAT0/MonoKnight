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

/// 通常遺物の効果が実際に発動したことを UI へ知らせるイベント
public struct DungeonRelicActivationEvent: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let relicID: DungeonRelicID

    public init(id: UUID = UUID(), relicID: DungeonRelicID) {
        self.id = id
        self.relicID = relicID
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
    let enemyID: String
    let category: DungeonDamageCategory
    let amount: Int
    let source: String
    let isMarker: Bool
}

private struct DungeonEnemyMovementResolution {
    let finalPoint: GridPoint
    let warpPoint: GridPoint?
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
    var resolvedEnemyDamageSourceIDs: Set<String>
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
        self.support = support.normalizedForInventory
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
    /// すでに発動して安全になった撒菱
    @Published public private(set) var consumedDamageTrapPoints: Set<GridPoint> = []
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
    /// 通常遺物の発動を UI で短く強調するための単発イベント
    @Published public private(set) var dungeonRelicActivationEvent: DungeonRelicActivationEvent?
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
    /// 暗闇スカウト系レリックで視界外でも見える撒菱
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
        guard mode.dungeonRules?.cardAcq