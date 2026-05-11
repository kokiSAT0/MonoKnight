import Combine  // Combine を利用して GameCore の更新を監視するために読み込む
import Foundation
import Game
import SharedSupport
import SwiftUI
import UIKit

/// SpriteKit の GameScene と SwiftUI 側レイアウトを仲介する ViewModel
/// GameViewModel から盤面演出に関わる責務を切り出し、描画更新とゲーム全体の状態管理を分離する
/// - Important: 盤面タップ入力の一次受けは GameViewModel 側で統括しており、本クラスはアニメーション制御のみに専念する
@MainActor
final class GameBoardBridgeViewModel: ObservableObject {
    /// 表示対象のゲームロジック
    let core: GameCore
    /// 現在のゲームモード（初期レイアウトや盤面サイズの復元に利用）
    let mode: GameMode
    /// SwiftUI から参照する SpriteKit シーン
    let scene: GameScene

    /// アニメーション中のカード
    @Published var animatingCard: DealtCard?
    /// アニメーション対象のスタック ID
    @Published var animatingStackID: UUID?
    /// 表示を一時的に隠すカード ID 集合
    @Published var hiddenCardIDs: Set<UUID> = []
    /// カード演出の状態管理
    @Published var animationState: CardAnimationPhase = .idle
    /// 敵ターンの可視化演出中かどうか
    @Published private(set) var isEnemyTurnAnimationActive = false
    /// 盤面アンカーのキャッシュ
    @Published var boardAnchor: Anchor<CGRect>?
    /// 演出ターゲットとなる座標
    @Published var animationTargetGridPoint: GridPoint?
    /// 退避している手札情報（進行状態によっては保留する）
    @Published var pendingGuideHand: [HandStack]?
    /// 退避している現在地
    @Published var pendingGuideCurrent: GridPoint?
    /// プレイ再開時に再適用したいガイド候補の退避先
    /// - Important: 進行状態が一時停止している間に計算した候補を保持し、`.playing` 復帰後に即座へ戻せるようにする
    private var pendingGuideBuckets: GuideHighlightBuckets?
    /// ガイド表示で扱う盤面座標を単一候補・複数候補に分類したコンテナ
    struct GuideHighlightBuckets: Equatable {
        /// 単一ベクトルカードが到達できる座標集合
        var singleVectorDestinations: Set<GridPoint>
        /// 複数ベクトルカードが到達できる座標集合
        var multipleVectorDestinations: Set<GridPoint>
        /// 複数マス移動カード（レイ型）が移動中に踏む座標集合
        var multiStepPathPoints: Set<GridPoint>
        /// 複数マス移動カード（レイ型）が最終的に到達できる座標集合
        var multiStepDestinations: Set<GridPoint>
        /// ワープ系カード専用の座標集合（紫枠で強調する）
        var warpDestinations: Set<GridPoint>
        /// 塔ダンジョンでカードなしに歩ける上下左右 1 マス候補
        var basicMoveDestinations: Set<GridPoint>

        /// すべて空集合の初期値を返すヘルパー
        static let empty = GuideHighlightBuckets(
            singleVectorDestinations: [],
            multipleVectorDestinations: [],
            multiStepPathPoints: [],
            multiStepDestinations: [],
            warpDestinations: [],
            basicMoveDestinations: []
        )
    }

    /// ガイド種別で保持している盤面ハイライト集合
    /// - Note: ガイドモードのオン/オフに関わらず最新候補を記録し、再描画時に即座に Scene へ伝搬できるようにする
    private(set) var guideHighlightBuckets: GuideHighlightBuckets = .empty
    /// ガイド設定に関係なく強制表示したいハイライト集合
    /// - Important: チュートリアルやカード選択 UI からの明示的な指示を反映し、ガイド無効時でもユーザーへ候補マスを提示する
    /// - Note: テストから現在のハイライト状況を検証できるように `private(set)` で公開する。
    private(set) var forcedSelectionHighlightPoints: Set<GridPoint> = []
    /// 直近に受信した移動解決情報
    /// - Note: Combine で current が更新される前に GameScene へ渡すため、一時的に保持するバッファとして利用する
    private var latestMovementResolution: MovementResolution?
    /// Core の最終状態通知が先に届いても、移動リプレイ開始までは初期表示を維持するための解決情報
    private var preparedMovementReplayResolution: MovementResolution?
    /// 再生済みの解決情報を保持し、後続の敵ターンなどで古い移動を再準備しないようにする
    private var completedMovementReplayResolution: MovementResolution?
    /// 移動演出の開始を GameViewModel 側へ伝える
    var onMovementPresentationStarted: ((MovementResolution) -> Void)?
    /// 移動演出の各ステップを GameViewModel 側へ伝える
    var onMovementPresentationStep: ((MovementResolution.PresentationStep) -> Void)?
    /// 移動演出の完了を GameViewModel 側へ伝える
    var onMovementPresentationFinished: (() -> Void)?
    /// 敵ターン中にプレイヤーへダメージが入った瞬間を GameViewModel 側へ伝える
    var onEnemyTurnDamageResolved: ((DungeonEnemyTurnEvent) -> Void)?
    /// 敵ターン演出の完了を GameViewModel 側へ伝える
    var onEnemyTurnAnimationFinished: ((DungeonEnemyTurnEvent) -> Void)?
    /// 移動演出中だけ拾得カード消失を段階表示するための上書き
    private var presentationCollectedDungeonCardPickupIDs: Set<String>?
    /// 移動演出中だけ宝箱消失を段階表示するための上書き
    private var presentationCollectedDungeonRelicPickupIDs: Set<String>?
    /// 移動演出中だけ敵表示を段階表示するための上書き
    private var presentationEnemyStates: [EnemyState]?
    /// 移動演出中だけひび割れ床を段階表示するための上書き
    private var presentationCrackedFloorPoints: Set<GridPoint>?
    /// 移動演出中だけ崩落床を段階表示するための上書き
    private var presentationCollapsedFloorPoints: Set<GridPoint>?
    /// 移動演出中の拾得カード消失差分を検出するための直前値
    private var presentationPreviousCollectedDungeonCardPickupIDs: Set<String>?
    /// 移動演出中の宝箱消失差分を検出するための直前値
    private var presentationPreviousCollectedDungeonRelicPickupIDs: Set<String>?
    /// 通常更新で拾得カードが増えた時だけ演出するための直前値
    private var observedCollectedDungeonCardPickupIDs: Set<String>?
    /// 通常更新で宝箱が増えた時だけ演出するための直前値
    private var observedCollectedDungeonRelicPickupIDs: Set<String>?
    /// 経路移動の再生中かどうか
    @Published private(set) var isMovementReplayActive = false
    /// スタックごとのトップカード ID を追跡し、レイアウト同期を最適化する
    @Published var topCardIDsByStack: [UUID: UUID] = [:]

    /// ガイド表示が有効かどうか
    private(set) var guideModeEnabled = true
    /// ハプティクスを利用するかどうか
    private(set) var hapticsEnabled = true

    /// 現在の駒の位置
    /// - Note: GameView 側で盤面アニメーションのフォールバック地点として参照するため公開する
    var currentPosition: GridPoint? { core.current }

    /// 現在の盤面サイズ
    /// - Note: 盤面座標を SwiftUI 座標へ変換する際に必要となるため、専用プロパティとして切り出す
    var boardSize: Int { core.board.size }

    /// Combine の購読を保持するためのセット
    private var cancellables = Set<AnyCancellable>()
    /// 敵ターン演出完了予定を保持し、連続イベント時に古い解除を無効化する
    private var enemyTurnAnimationCompletionWorkItem: DispatchWorkItem?
    /// 敵ターン演出中に盤面へ表示する敵の前後状態
    private var activeEnemyTurnEvent: DungeonEnemyTurnEvent?
    /// 移動リプレイ完了まで再生を待つ敵ターンイベント
    private(set) var pendingEnemyTurnEventAfterMovementReplay: DungeonEnemyTurnEvent?
    /// 再生済みの敵ターンイベントを保持し、通常更新時に古いイベントを再利用しないようにする
    private var completedEnemyTurnEventID: UUID?

    /// 初期化で GameScene を構築し、GameCore と紐付ける
    /// - Parameters:
    ///   - core: 共有するゲームロジック
    ///   - mode: 現在プレイ中のモード
    init(core: GameCore, mode: GameMode) {
        self.core = core
        self.mode = mode

        let preparedScene = GameScene(
            initialBoardSize: mode.boardSize,
            initialVisitedPoints: mode.initialVisitedPoints,
            impassablePoints: mode.impassableTilePoints,
            tileEffects: mode.tileEffects
        )
        preparedScene.scaleMode = .resizeFill
        preparedScene.gameCore = core
        preparedScene.updateShowsVisitedTileFill(!mode.usesDungeonExit)
        self.scene = preparedScene

        bindGameCore()
        handleHandStacksUpdate(core.handStacks)
    }

    /// 表示直前にシーン設定を整え、必要な状態を初期化する
    /// - Parameters:
    ///   - colorScheme: 現在のライト/ダーク設定
    ///   - guideModeEnabled: ガイド表示の初期値
    ///   - hapticsEnabled: ハプティクス有効状態
    func prepareForAppear(
        colorScheme: ColorScheme,
        guideModeEnabled: Bool,
        hapticsEnabled: Bool
    ) {
        scene.gameCore = core
        updateHapticsSetting(isEnabled: hapticsEnabled)
        updateGuideMode(enabled: guideModeEnabled)
        applyScenePalette(for: colorScheme)
        updateForcedSelectionHighlights()
        refreshGuideHighlights()
    }

    /// SpriteView が表示されたタイミングでサイズと表示内容を同期する
    /// - Parameter width: 正方形表示に利用する幅
    func configureSceneOnAppear(width: CGFloat) {
        debugLog("SpriteBoardBridge.onAppear: width=\(width), scene.size=\(scene.size)")
        if width <= 0 {
            debugLog("SpriteBoardBridge.onAppear 警告: 盤面幅がゼロ以下です")
        }
        scene.size = CGSize(width: width, height: width)
        scene.updateBoard(core.board)
        scene.moveKnight(to: core.current)
        refreshGuideHighlights()
    }

    /// レイアウト変更に合わせて SpriteKit シーンのサイズを更新する
    /// - Parameter newWidth: 更新後の幅
    func updateSceneSize(to newWidth: CGFloat) {
        debugLog("SpriteBoardBridge.width 更新: newWidth=\(newWidth)")
        if newWidth <= 0 {
            debugLog("SpriteBoardBridge.width 警告: newWidth がゼロ以下です")
        }
        scene.size = CGSize(width: newWidth, height: newWidth)
    }

    /// シーンの配色をアプリテーマに合わせて更新する
    /// - Parameter scheme: 現在のカラースキーム
    func applyScenePalette(for scheme: ColorScheme) {
        let appTheme = AppTheme(colorScheme: scheme)
        let palette = GameScenePalette(
            boardBackground: appTheme.skBoardBackground,
            boardGridLine: appTheme.skBoardGridLine,
            boardTileVisited: appTheme.skBoardTileVisited,
            boardTileUnvisited: appTheme.skBoardTileUnvisited,
            // NOTE: 特殊マスが視覚的に分かるよう、SwiftUI 側で決めた配色をそのまま転写する
            boardTileMultiBase: appTheme.skBoardTileMultiBase,
            // NOTE: マルチ踏破マスの枠線もテーマ側で厳選したハイコントラスト色を適用する
            boardTileMultiStroke: appTheme.skBoardTileMultiStroke,
            boardTileToggle: appTheme.skBoardTileToggle,
            // NOTE: 移動不可マスは専用トーンで塗り潰し、SpriteKit 側でも障害物が即座に伝わるようにする
            boardTileImpassable: appTheme.skBoardTileImpassable,
            boardKnight: appTheme.skBoardKnight,
            boardGuideHighlight: appTheme.skBoardGuideHighlight,
            boardMultiStepHighlight: appTheme.skBoardMultiStepHighlight,
            boardWarpHighlight: appTheme.skBoardWarpHighlight,
            boardTileEffectWarp: appTheme.skBoardTileEffectWarp,
            boardTileEffectShuffle: appTheme.skBoardTileEffectShuffle,
            boardTileEffectBlast: appTheme.skBoardTileEffectBlast,
            boardTileEffectSlow: appTheme.skBoardTileEffectSlow,
            boardTileEffectSwamp: appTheme.skBoardTileEffectSwamp,
            boardTileEffectPreserveCard: appTheme.skBoardTileEffectPreserveCard,
            boardTileEffectDiscardHand: appTheme.skBoardTileEffectDiscardHand,
            // NOTE: ワープペアの配色セットを SpriteKit へ渡し、色と形の両面で組み合わせを識別させる
            warpPairAccentColors: appTheme.skWarpPairAccentColors
        )
        scene.applyTheme(palette)
    }

    /// ガイド表示モードを切り替える
    /// - Parameter enabled: 新しいモード設定
    func updateGuideMode(enabled: Bool) {
        guideModeEnabled = enabled
        if enabled {
            refreshGuideHighlights()
        } else {
            guideHighlightBuckets = .empty
            pushHighlightsToScene()
            pendingGuideHand = nil
            pendingGuideCurrent = nil
            pendingGuideBuckets = nil
            debugLog("ガイドを消灯: ガイドモードが無効")
        }
    }

    /// ハプティクス利用有無を更新する
    /// - Parameter isEnabled: ユーザー設定から得た値
    func updateHapticsSetting(isEnabled: Bool) {
        hapticsEnabled = isEnabled
    }

    /// SpriteView のアンカー値を更新する
    /// - Parameter anchor: 新しいアンカー情報
    func updateBoardAnchor(_ anchor: Anchor<CGRect>?) {
        boardAnchor = anchor
    }

    /// ひび割れ床の落下を軽く見せるための盤面演出を再生する
    func playDungeonFallEffect(at point: GridPoint) {
        scene.playDungeonFallEffect(at: point)
    }

    /// HP 減少を軽く伝えるため、盤面上の騎士へ短い被弾演出を再生する
    func playDamageEffect() {
        damageEffectPlayCountForTesting += 1
        scene.playDamageEffect()
    }

    private(set) var damageEffectPlayCountForTesting = 0

    /// 無効な入力を短い盤面フィードバックとして伝える
    func playInvalidSelectionFeedback(at point: GridPoint? = nil) {
        invalidSelectionFeedbackPlayCountForTesting += 1
        scene.playInvalidSelectionFeedback(at: point)
    }

    private(set) var invalidSelectionFeedbackPlayCountForTesting = 0

    private func beginMovementReplay(using resolution: MovementResolution) {
        prepareMovementReplayPresentationIfNeeded(using: resolution)
        isMovementReplayActive = true
        onMovementPresentationStarted?(resolution)
        scene.playMovementTransition(
            using: resolution,
            onStep: { [weak self] step in
                self?.applyMovementPresentationStep(step)
            },
            onCompletion: { [weak self] in
                self?.finishMovementReplay()
            }
        )
    }

    #if DEBUG
        func beginMovementReplayForTesting(using resolution: MovementResolution) {
            beginMovementReplay(using: resolution)
        }

        func setMovementReplayActiveForTesting(_ isActive: Bool) {
            isMovementReplayActive = isActive
        }

        func playPendingEnemyTurnAfterMovementReplayForTesting() {
            playPendingEnemyTurnAfterMovementReplayIfNeeded()
        }
    #endif

    @discardableResult
    private func preparePendingMovementReplayPresentationIfNeeded() -> Bool {
        guard let resolution = latestMovementResolution ?? core.lastMovementResolution,
              resolution.finalPosition == core.current,
              isMovementReplayCandidate(resolution),
              resolution != completedMovementReplayResolution
        else {
            return false
        }
        prepareMovementReplayPresentationIfNeeded(using: resolution)
        return true
    }

    private func prepareMovementReplayPresentationIfNeeded(using resolution: MovementResolution) {
        guard isMovementReplayCandidate(resolution) else { return }
        if preparedMovementReplayResolution == resolution {
            pushHighlightsToScene()
            return
        }
        preparedMovementReplayResolution = resolution
        if let initialBoard = resolution.presentationInitialBoard {
            scene.updateBoard(initialBoard)
        }
        presentationCollectedDungeonCardPickupIDs = resolution.presentationInitialCollectedDungeonCardPickupIDs
        presentationCollectedDungeonRelicPickupIDs = resolution.presentationInitialCollectedDungeonRelicPickupIDs
        presentationPreviousCollectedDungeonCardPickupIDs = resolution.presentationInitialCollectedDungeonCardPickupIDs
        presentationPreviousCollectedDungeonRelicPickupIDs = resolution.presentationInitialCollectedDungeonRelicPickupIDs
        presentationEnemyStates = resolution.presentationInitialEnemyStates
        presentationCrackedFloorPoints = resolution.presentationInitialCrackedFloorPoints
        presentationCollapsedFloorPoints = resolution.presentationInitialCollapsedFloorPoints
        pushHighlightsToScene()
    }

    private func isMovementReplayCandidate(_ resolution: MovementResolution) -> Bool {
        !resolution.presentationSteps.isEmpty || resolution.path.count > 1
    }

    private func applyMovementPresentationStep(_ step: MovementResolution.PresentationStep) {
        if let boardAfter = step.boardAfter {
            scene.updateBoard(boardAfter)
        }
        playCollectionEffectsIfNeeded(
            previousCardIDs: presentationPreviousCollectedDungeonCardPickupIDs,
            nextCardIDs: step.collectedDungeonCardPickupIDsAfter,
            previousRelicIDs: presentationPreviousCollectedDungeonRelicPickupIDs,
            nextRelicIDs: step.collectedDungeonRelicPickupIDsAfter
        )
        presentationCollectedDungeonCardPickupIDs = step.collectedDungeonCardPickupIDsAfter
        presentationCollectedDungeonRelicPickupIDs = step.collectedDungeonRelicPickupIDsAfter
        presentationPreviousCollectedDungeonCardPickupIDs = step.collectedDungeonCardPickupIDsAfter
        presentationPreviousCollectedDungeonRelicPickupIDs = step.collectedDungeonRelicPickupIDsAfter
        presentationEnemyStates = step.enemyStatesAfter
        presentationCrackedFloorPoints = step.crackedFloorPointsAfter
        presentationCollapsedFloorPoints = step.collapsedFloorPointsAfter
        pushHighlightsToScene()
        onMovementPresentationStep?(step)
    }

    private func finishMovementReplay() {
        presentationCollectedDungeonCardPickupIDs = nil
        presentationCollectedDungeonRelicPickupIDs = nil
        presentationEnemyStates = nil
        presentationCrackedFloorPoints = nil
        presentationCollapsedFloorPoints = nil
        presentationPreviousCollectedDungeonCardPickupIDs = nil
        presentationPreviousCollectedDungeonRelicPickupIDs = nil
        completedMovementReplayResolution = preparedMovementReplayResolution
        preparedMovementReplayResolution = nil
        isMovementReplayActive = false
        scene.updateBoard(core.board)
        if let current = core.current {
            scene.playLandingEffect(at: current)
        }
        observedCollectedDungeonCardPickupIDs = core.collectedDungeonCardPickupIDs
        observedCollectedDungeonRelicPickupIDs = core.collectedDungeonRelicPickupIDs
        pushHighlightsToScene()
        onMovementPresentationFinished?()
        playPendingEnemyTurnAfterMovementReplayIfNeeded()
    }

    private func playCollectionEffectsIfNeeded(
        previousCardIDs: Set<String>?,
        nextCardIDs: Set<String>,
        previousRelicIDs: Set<String>?,
        nextRelicIDs: Set<String>
    ) {
        if let previousCardIDs {
            let newlyCollectedCardIDs = nextCardIDs.subtracting(previousCardIDs)
            for id in newlyCollectedCardIDs {
                guard let point = dungeonCardPickupPoint(for: id) else { continue }
                scene.playPickupCollectionEffect(at: point)
            }
        }

        if let previousRelicIDs {
            let newlyCollectedRelicIDs = nextRelicIDs.subtracting(previousRelicIDs)
            for id in newlyCollectedRelicIDs {
                guard let point = dungeonRelicPickupPoint(for: id) else { continue }
                scene.playRelicCollectionEffect(at: point)
            }
        }
    }

    private func dungeonCardPickupPoint(for id: String) -> GridPoint? {
        mode.dungeonRules?.cardPickups.first { $0.id == id }?.point
    }

    private func dungeonRelicPickupPoint(for id: String) -> GridPoint? {
        mode.dungeonRules?.relicPickups.first { $0.id == id }?.point
    }

    private func scheduleLandingEffect(at point: GridPoint, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.core.current == point else { return }
            self.scene.playLandingEffect(at: point)
        }
    }

    var isInputAnimationActive: Bool {
        animatingCard != nil || isEnemyTurnAnimationActive || isMovementReplayActive
    }

    func playDungeonEnemyTurn(_ event: DungeonEnemyTurnEvent) {
        if isMovementReplayActive {
            pendingEnemyTurnEventAfterMovementReplay = event
            return
        }
        enemyTurnAnimationCompletionWorkItem?.cancel()
        activeEnemyTurnEvent = event
        isEnemyTurnAnimationActive = true
        pushHighlightsToScene()

        let enemyTurnDangerPoints = core.isDungeonDarknessActive
            ? core.watcherLaserDangerDisplayPoints(forDisplayedEnemyStates: core.enemyStates)
            : core.enemyDangerPoints
        let duration = scene.playDungeonEnemyTurn(
            event,
            dangerPoints: enemyTurnDangerPoints,
            warningPoints: core.enemyWarningPoints
        )
        let shouldPlayDamage = event.attackedPlayer && event.hpAfter < event.hpBefore
        let damageDelay = max(duration - 0.08, 0)
        let completionDelay = max(duration, 0.12)

        if shouldPlayDamage {
            DispatchQueue.main.asyncAfter(deadline: .now() + damageDelay) { [weak self] in
                guard let self, self.isEnemyTurnAnimationActive else { return }
                self.onEnemyTurnDamageResolved?(event)
                self.playDamageEffect()
            }
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.completedEnemyTurnEventID = event.id
            self.activeEnemyTurnEvent = nil
            self.isEnemyTurnAnimationActive = false
            self.enemyTurnAnimationCompletionWorkItem = nil
            self.refreshGuideHighlights()
            self.onEnemyTurnAnimationFinished?(event)
        }
        enemyTurnAnimationCompletionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + completionDelay, execute: workItem)
    }

    private func playPendingEnemyTurnAfterMovementReplayIfNeeded() {
        guard let event = pendingEnemyTurnEventAfterMovementReplay else { return }
        pendingEnemyTurnEventAfterMovementReplay = nil
        guard event.id != completedEnemyTurnEventID else { return }
        playDungeonEnemyTurn(event)
    }

    /// 現在保持しているハイライト状態を SpriteKit シーンへ反映する
    /// - Note: 種類ごとの集合を辞書にまとめ、`GameScene` 側の一括更新 API と齟齬なく連携する
    private func pushHighlightsToScene() {
        let shouldHideGuideCandidates = !forcedSelectionHighlightPoints.isEmpty
        let enemyTurnBeforeStates = activeEnemyTurnEvent?.phases.first?.transitions.map(\.before) ?? []
        let activeEnemyTurnDisplayStates = enemyTurnBeforeStates.isEmpty ? core.enemyStates : enemyTurnBeforeStates
        let stepEnemyStates = presentationEnemyStates ?? core.enemyStates
        let displayedEnemyStates = activeEnemyTurnEvent.map { _ in activeEnemyTurnDisplayStates } ?? stepEnemyStates
        let displayedEnemyPoints = Set(displayedEnemyStates.map(\.position))
        let shouldDeferEnemyThreatHighlights = activeEnemyTurnEvent != nil
        let isDarknessEnabled = core.isDungeonDarknessActive
        let displayedEnemyDangerPoints = isDarknessEnabled
            ? core.watcherLaserDangerDisplayPoints(forDisplayedEnemyStates: displayedEnemyStates)
            : core.enemyDangerDisplayPoints(forDisplayedEnemyStates: displayedEnemyStates)
        let displayedEnemyWarningPoints = core.enemyWarningPoints(forDisplayedEnemyStates: displayedEnemyStates)
        let dungeonVisiblePoints = isDarknessEnabled
            ? makeDarknessVisiblePoints(
                current: core.current,
                exitPoint: mode.dungeonExitPoint,
                dangerPoints: shouldDeferEnemyThreatHighlights ? [] : displayedEnemyDangerPoints,
                warningPoints: shouldDeferEnemyThreatHighlights ? [] : displayedEnemyWarningPoints,
                revealedPickupPoints: core.chalkRevealedDungeonCardPickupPoints,
                visionRadius: core.dungeonDarknessVisionRadius
            )
            : nil
        let patrolFacingVectors = patrolFacingVectorsForDisplayedEnemies(displayedEnemyStates)
        let collectedPickupIDs = presentationCollectedDungeonCardPickupIDs ?? core.collectedDungeonCardPickupIDs
        let collectedRelicPickupIDs = presentationCollectedDungeonRelicPickupIDs ?? core.collectedDungeonRelicPickupIDs
        let displayedCardPickupPoints = Set(
            mode.dungeonRules?.cardPickups
                .filter { !collectedPickupIDs.contains($0.id) }
                .map(\.point) ?? []
        )
        let displayedRelicPickups = mode.dungeonRules?.relicPickups
            .filter { !collectedRelicPickupIDs.contains($0.id) } ?? []
        let displayedRelicPickupPoints = Set(
            displayedRelicPickups
                .filter { !$0.kind.isSuspicious }
                .map(\.point)
        )
        let displayedSuspiciousRelicPickupPoints = Set(
            displayedRelicPickups
                .filter(\.kind.isSuspicious)
                .map(\.point)
        )
        let displayedCrackedFloorPoints = presentationCrackedFloorPoints ?? core.crackedFloorPoints
        let displayedCollapsedFloorPoints = presentationCollapsedFloorPoints ?? core.collapsedFloorPoints
        let highlights: [BoardHighlightKind: Set<GridPoint>] = [
            .guideSingleCandidate: shouldHideGuideCandidates ? [] : guideHighlightBuckets.singleVectorDestinations,
            .guideMultipleCandidate: shouldHideGuideCandidates ? [] : guideHighlightBuckets.multipleVectorDestinations,
            .guideMultiStepPath: shouldHideGuideCandidates ? [] : guideHighlightBuckets.multiStepPathPoints,
            .guideMultiStepCandidate: shouldHideGuideCandidates ? [] : guideHighlightBuckets.multiStepDestinations,
            .guideWarpCandidate: shouldHideGuideCandidates ? [] : guideHighlightBuckets.warpDestinations,
            .dungeonBasicMove: shouldHideGuideCandidates ? [] : guideHighlightBuckets.basicMoveDestinations,
            .forcedSelection: forcedSelectionHighlightPoints,
            .dungeonExit: core.isDungeonExitUnlocked ? (mode.dungeonExitPoint.map { Set([$0]) } ?? []) : [],
            .dungeonExitLocked: core.isDungeonExitUnlocked ? [] : (mode.dungeonExitPoint.map { Set([$0]) } ?? []),
            .dungeonKey: visible(displayed: core.dungeonKeyPoints, in: dungeonVisiblePoints),
            .dungeonEnemy: visible(displayed: displayedEnemyPoints, in: dungeonVisiblePoints),
            .dungeonDanger: shouldDeferEnemyThreatHighlights ? [] : displayedEnemyDangerPoints,
            .dungeonEnemyWarning: shouldDeferEnemyThreatHighlights ? [] : displayedEnemyWarningPoints,
            .dungeonCardPickup: visible(displayed: displayedCardPickupPoints, in: dungeonVisiblePoints),
            .dungeonRelicPickup: visible(displayed: displayedRelicPickupPoints, in: dungeonVisiblePoints),
            .dungeonSuspiciousRelicPickup: visible(displayed: displayedSuspiciousRelicPickupPoints, in: dungeonVisiblePoints),
            .dungeonDamageTrap: visible(displayed: core.damageTrapPoints, in: dungeonVisiblePoints),
            .dungeonLavaTile: visible(displayed: core.lavaTilePoints, in: dungeonVisiblePoints),
            .dungeonHealingTile: visible(displayed: core.healingTilePoints, in: dungeonVisiblePoints),
            .dungeonCrackedFloor: visible(displayed: displayedCrackedFloorPoints, in: dungeonVisiblePoints),
            .dungeonCollapsedFloor: visible(displayed: displayedCollapsedFloorPoints, in: dungeonVisiblePoints)
        ]
        scene.updateDungeonVisiblePoints(dungeonVisiblePoints)
        scene.updateHighlights(highlights)
        let visibleEnemyStates = visible(displayed: displayedEnemyStates, in: dungeonVisiblePoints)
        scene.updateDungeonEnemyMarkers(visibleEnemyStates.map { enemy in
            SceneDungeonEnemyMarker(enemy, facingVector: patrolFacingVectors[enemy.id])
        })
        scene.updatePatrolRailPreviews(
            visiblePatrolRailPreviews(
                core.enemyPatrolRailPreviews(forDisplayedEnemyStates: displayedEnemyStates).map(ScenePatrolRailPreview.init),
                in: dungeonVisiblePoints
            )
        )
        let enemyDirectionPreviews = shouldDeferEnemyThreatHighlights ? [] : (
            visibleMovementPreviews(
                core.enemyChaserMovementPreviews(forDisplayedEnemyStates: displayedEnemyStates).map(ScenePatrolMovementPreview.init),
                in: dungeonVisiblePoints
            )
        )
        scene.updatePatrolMovementPreviews(enemyDirectionPreviews)
    }

    private func makeDarknessVisiblePoints(
        current: GridPoint?,
        exitPoint: GridPoint?,
        dangerPoints: Set<GridPoint>,
        warningPoints: Set<GridPoint>,
        revealedPickupPoints: Set<GridPoint>,
        visionRadius: Int
    ) -> Set<GridPoint> {
        var visiblePoints = dangerPoints.union(warningPoints).union(revealedPickupPoints)
        if let current {
            let radius = max(visionRadius, 1)
            for dy in (-radius)...radius {
                for dx in (-radius)...radius {
                    let point = current.offset(dx: dx, dy: dy)
                    if point.isInside(boardSize: boardSize) {
                        visiblePoints.insert(point)
                    }
                }
            }
        }
        if let exitPoint {
            visiblePoints.insert(exitPoint)
        }
        return visiblePoints
    }

    private func visible(displayed points: Set<GridPoint>, in visiblePoints: Set<GridPoint>?) -> Set<GridPoint> {
        guard let visiblePoints else { return points }
        return points.intersection(visiblePoints)
    }

    private func visible(displayed enemies: [EnemyState], in visiblePoints: Set<GridPoint>?) -> [EnemyState] {
        guard let visiblePoints else { return enemies }
        return enemies.filter { visiblePoints.contains($0.position) }
    }

    private func visibleMovementPreviews(
        _ previews: [ScenePatrolMovementPreview],
        in visiblePoints: Set<GridPoint>?
    ) -> [ScenePatrolMovementPreview] {
        guard let visiblePoints else { return previews }
        return previews.filter { visiblePoints.contains($0.current) && visiblePoints.contains($0.next) }
    }

    private func visiblePatrolRailPreviews(
        _ previews: [ScenePatrolRailPreview],
        in visiblePoints: Set<GridPoint>?
    ) -> [ScenePatrolRailPreview] {
        guard let visiblePoints else { return previews }
        return previews.compactMap { preview in
            let visiblePath = preview.path.filter(visiblePoints.contains)
            guard visiblePath.count > 1 else { return nil }
            return ScenePatrolRailPreview(enemyID: preview.enemyID, path: visiblePath)
        }
    }

    private func patrolFacingVectorsForDisplayedEnemies(_ displayedEnemyStates: [EnemyState]) -> [String: MoveVector] {
        if let activeEnemyTurnEvent {
            return Dictionary(
                activeEnemyTurnEvent.phases
                    .flatMap(\.transitions)
                    .compactMap { transition -> (String, MoveVector)? in
                        guard transition.before.behavior.presentationKind == .patrol,
                              transition.before.position != transition.after.position else {
                            return nil
                        }
                        return (
                            transition.enemyID,
                            MoveVector(
                                dx: transition.after.position.x - transition.before.position.x,
                                dy: transition.after.position.y - transition.before.position.y
                            )
                        )
                    },
                uniquingKeysWith: { first, _ in first }
            )
        }

        return Dictionary(
            core.enemyPatrolMovementPreviews(forDisplayedEnemyStates: displayedEnemyStates).map { preview in
                (preview.enemyID, preview.vector)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// ガイド集合の件数をまとめ、ログ用メッセージも同時に生成する
    /// - Parameters:
    ///   - buckets: 直近で計算したガイド候補の集合
    ///   - logPrefix: 呼び出し元で使いたい冒頭のメッセージ
    /// - Returns: 各集合の件数と合計、ならびに debugLog へ渡す整形済み文字列
    /// - Note: 件数計算とログ文言の重複を避け、保守性を高めるために専用ヘルパーへ切り出している
    private func makeGuideHighlightSummary(
        _ buckets: GuideHighlightBuckets,
        logPrefix: String
    ) -> (
        singleCount: Int,
        multipleCount: Int,
        multiStepCount: Int,
        warpCount: Int,
        totalCount: Int,
        logMessage: String
    ) {
        // --- 集計対象それぞれの件数を求める ---
        let singleCount = buckets.singleVectorDestinations.count
        let multipleCount = buckets.multipleVectorDestinations.count
        let multiStepPathCount = buckets.multiStepPathPoints.count
        let multiStepCount = buckets.multiStepDestinations.count
        let warpCount = buckets.warpDestinations.count
        let basicCount = buckets.basicMoveDestinations.count
        let totalCount = singleCount + multipleCount + multiStepPathCount + multiStepCount + warpCount + basicCount

        // --- 呼び出し側で使うログ文面を一括生成する ---
        let logMessage = (
            "\(logPrefix) 単一=\(singleCount) 複数=\(multipleCount) " +
            "連続経路=\(multiStepPathCount) 連続終点=\(multiStepCount) " +
            "ワープ=\(warpCount) 基本移動=\(basicCount) 合計=\(totalCount)"
        )

        return (
            singleCount,
            multipleCount,
            multiStepCount,
            warpCount,
            totalCount,
            logMessage
        )
    }

    /// ガイドハイライトを最新状態へ更新する
    /// - Parameters:
    ///   - handOverride: 手札情報を差し替えたい場合に指定
    ///   - currentOverride: 現在地を差し替えたい場合に指定
    ///   - progressOverride: 進行状態を差し替えたい場合に指定
    func refreshGuideHighlights(
        handOverride: [HandStack]? = nil,
        currentOverride: GridPoint? = nil,
        progressOverride: GameProgress? = nil
    ) {
        let handStacks = handOverride ?? core.handStacks
        let progress = progressOverride ?? core.progress

        guard let current = currentOverride ?? core.current else {
            // 現在地が未確定でも手札は保持しておき、位置確定後に即座へ復元できるようにする
            pendingGuideHand = handStacks
            pendingGuideCurrent = nil
            pendingGuideBuckets = nil
            guideHighlightBuckets = .empty
            pushHighlightsToScene()
            debugLog("ガイド更新を中断: 現在地が未確定 状態=\(String(describing: progress)) スタック数=\(handStacks.count)")
            return
        }

        // GameCore.availableMoves() で得られた候補をカード単位で分類し、単一ベクトルか複数ベクトルかを判定する
        let resolvedMoves = core.availableMoves(handStacks: handStacks, current: current)
        let groupedByCard = Dictionary(grouping: resolvedMoves, by: { $0.card.id })
        var computedBuckets = GuideHighlightBuckets.empty
        computedBuckets.basicMoveDestinations = Set(
            core.availableBasicOrthogonalMoves(current: current).map(\.destination)
        )

        for moves in groupedByCard.values {
            guard let representative = moves.first else { continue }
            let destinations = moves.map { $0.destination }
            let traversedPoints = moves.flatMap(\.traversedPoints)
            let move = representative.card.move

            if move.kind == .multiStep {
                // 連続移動カードは、通過範囲を塗り、終点だけをタップ可能な枠として分けて渡す
                computedBuckets.multiStepPathPoints.formUnion(traversedPoints)
                computedBuckets.multiStepDestinations.formUnion(destinations)
            } else if move.movementVectors.count > 1 {
                // 複数方向カードは従来どおりオレンジ枠で強調する
                computedBuckets.multipleVectorDestinations.formUnion(destinations)
            } else {
                // 単方向カードは落ち着いたグレー枠へ分類する
                computedBuckets.singleVectorDestinations.formUnion(destinations)
            }
        }
        computedBuckets.multiStepPathPoints.subtract(core.enemyDangerDisplayPoints)

        guard guideModeEnabled else {
            guideHighlightBuckets = .empty
            pushHighlightsToScene()
            pendingGuideHand = nil
            pendingGuideCurrent = nil
            pendingGuideBuckets = nil
            let summary = makeGuideHighlightSummary(
                computedBuckets,
                logPrefix: "ガイドを消灯: ガイドモードが無効"
            )
            debugLog(summary.logMessage)
            return
        }

        guard progress == .playing else {
            pendingGuideHand = handStacks
            pendingGuideCurrent = current
            pendingGuideBuckets = computedBuckets
            guideHighlightBuckets = .empty
            pushHighlightsToScene()
            let summary = makeGuideHighlightSummary(
                computedBuckets,
                logPrefix: "ガイド更新を保留: 状態=\(String(describing: progress))"
            )
            debugLog(summary.logMessage)
            return
        }

        pendingGuideHand = nil
        pendingGuideCurrent = nil
        pendingGuideBuckets = nil
        guideHighlightBuckets = computedBuckets
        pushHighlightsToScene()
        let summary = makeGuideHighlightSummary(
            computedBuckets,
            logPrefix: "ガイド描画"
        )
        debugLog(summary.logMessage)
    }

    /// 強制的に表示したいハイライト集合を更新する
    /// - Parameter points: ガイド設定に依存せず提示したい盤面座標集合
    /// - Important: チュートリアルやカード選択 UI が「このマスを必ず選んでほしい」という意図を伝えるための経路
    func updateForcedSelectionHighlights(
        _ points: Set<GridPoint> = [],
        origin: GridPoint? = nil,
        movementVectors: [MoveVector] = []
    ) {
        // movementVectors が指定された場合は現在地からの相対座標を盤面座標へ変換する
        var candidatePoints = points
        if let origin, !movementVectors.isEmpty {
            let convertedPoints = movementVectors.map { vector in
                origin.offset(dx: vector.dx, dy: vector.dy)
            }
            candidatePoints.formUnion(convertedPoints)
        }

        // 盤面内かつ移動可能なマスだけを残し、障害物をハイライト対象から除外する
        let validPoints = Set(
            candidatePoints.filter { point in
                core.board.contains(point) && core.board.isTraversable(point)
            }
        )
        guard forcedSelectionHighlightPoints != validPoints else { return }
        forcedSelectionHighlightPoints = validPoints
        pushHighlightsToScene()
        debugLog("強制ハイライト更新: 候補=\(validPoints.count)")
    }

    /// 指定スタックを盤面演出に乗せる
    /// - Parameters:
    ///   - stack: 対象となる手札スタック
    ///   - index: GameCore に渡すスタックの位置
    /// - Returns: 演出開始に成功したら true
    /// ResolvedCardMove を直接受け取り、カード演出とプレイ処理を実行する
    /// - Parameter resolvedMove: GameCore.availableMoves() で得られた移動候補
    /// - Returns: アニメーションを開始できた場合は true
    @discardableResult
    func animateCardPlay(using resolvedMove: ResolvedCardMove) -> Bool {
        guard !isInputAnimationActive else {
            debugLog(
                "スタック演出を中止: 別演出が進行中 stackID=\(resolvedMove.stackID) dest=\(resolvedMove.destination)"
            )
            return false
        }
        guard core.current != nil else {
            debugLog("スタック演出を中止: 現在地が未確定 stackID=\(resolvedMove.stackID)")
            return false
        }

        // GameCore 側で提供するユーティリティを利用し、スタック位置の補正とカード一致検証を一括で行う
        guard let (validatedMove, stack) = core.validatedResolvedMove(resolvedMove) else {
            debugLog("スタック演出を中止: ResolvedCardMove の検証に失敗 stackID=\(resolvedMove.stackID)")
            return false
        }

        // GameCore 側でインデックス補正済みの ResolvedCardMove をそのまま利用する
        let moveForExecution = validatedMove
        guard let topCard = stack.topCard else {
            debugLog("スタック演出を中止: トップカードなし stackID=\(stack.id)")
            return false
        }

        if !forcedSelectionHighlightPoints.isEmpty {
            // 強制ハイライトが点灯したまま演出へ移行しないよう、開始前に必ずリセットする
            updateForcedSelectionHighlights([])
        }

        // 現在位置からカードの移動量を適用し、演出で目指す盤面座標を算出する
        let destinationPoint = moveForExecution.destination
        animationTargetGridPoint = destinationPoint
        hiddenCardIDs.insert(topCard.id)
        animatingCard = topCard
        animatingStackID = stack.id
        animationState = .idle

        debugLog(
            "スタック演出開始: stackID=\(stack.id) card=\(topCard.move.displayName) dest=\(destinationPoint) vector=(dx:\(moveForExecution.moveVector.dx), dy:\(moveForExecution.moveVector.dy)) 残枚数=\(stack.count)"
        )

        if hapticsEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }

        let travelDuration: TimeInterval = 0.24
        withAnimation(.easeInOut(duration: travelDuration)) {
            animationState = .movingToBoard
        }

        let cardID = topCard.id
        DispatchQueue.main.asyncAfter(deadline: .now() + travelDuration) { [weak self] in
            guard let self else { return }
            withAnimation(.easeInOut(duration: 0.22)) {
                self.core.playCard(using: moveForExecution)
            }
            self.hiddenCardIDs.remove(cardID)
            if self.animatingCard?.id == cardID {
                self.animatingCard = nil
            }
            self.animatingStackID = nil
            self.animationState = .idle
            self.animationTargetGridPoint = nil
            debugLog("スタック演出完了: index=\(moveForExecution.stackIndex) cardID=\(cardID)")
        }

        return true
    }

    @discardableResult
    func animateCardPlay(for stack: HandStack, at index: Int) -> Bool {
        guard let topCard = stack.topCard else { return false }

        // index は API 維持のため受け取るが、実際の処理では ResolvedCardMove 側で再評価する
        _ = index

        // 現在の手札状況に基づく使用可能カードを検索し、該当スタックの候補を取得する
        // - Note: availableMoves() がカード内の全ベクトルを展開しているため、複数候補カードでもここから 1 件を選ぶだけで良い
        guard let resolvedMove = core.availableMoves().first(where: { candidate in
            candidate.stackID == stack.id && candidate.card.id == topCard.id
        }) else {
            debugLog("スタック演出を中止: 使用可能リストに該当カードなし stackID=\(stack.id)")
            return false
        }

        return animateCardPlay(using: resolvedMove)
    }

    /// 進行状態の変更に合わせてガイド表示を管理する
    /// - Parameter progress: 現在のゲーム進行状態
    func handleProgressChange(_ progress: GameProgress) {
        debugLog("進行状態の更新を受信: 状態=\(String(describing: progress)), 退避ハンドあり=\(pendingGuideHand != nil)")

        switch progress {
        case .playing:
            if let bufferedHand = pendingGuideHand {
                refreshGuideHighlights(
                    handOverride: bufferedHand,
                    currentOverride: pendingGuideCurrent,
                    progressOverride: progress
                )
            } else {
                refreshGuideHighlights(progressOverride: progress)
            }
        case .cleared:
            guideHighlightBuckets = .empty
            updateForcedSelectionHighlights([])
            pendingGuideHand = nil
            pendingGuideCurrent = nil
            pendingGuideBuckets = nil
        default:
            guideHighlightBuckets = .empty
            updateForcedSelectionHighlights([])
        }
    }

    /// 指定スタックのトップカードが使用可能かを判定する
    /// - Parameter stack: 判定対象のスタック
    /// - Returns: 使用可能なら true
    func isCardUsable(_ stack: HandStack) -> Bool {
        guard let card = stack.topCard else { return false }
        if card.supportCard != nil {
            return core.isSupportCardUsable(in: stack)
        }
        // availableMoves() が primaryVector を利用しているため、1 候補カードと同じ手続きで拡張に備えられる
        return core.availableMoves().contains { candidate in
            candidate.stackID == stack.id && candidate.card.id == card.id
        }
    }

    /// GameCore の状態変化を監視し、盤面関連の副作用を集約する
    private func bindGameCore() {
        core.$handStacks
            .receive(on: RunLoop.main)
            .sink { [weak self] newHandStacks in
                guard let self else { return }
                self.handleHandStacksUpdate(newHandStacks)
            }
            .store(in: &cancellables)

        core.$board
            .receive(on: RunLoop.main)
            .sink { [weak self] newBoard in
                guard let self else { return }
                if self.isMovementReplayActive || self.preparePendingMovementReplayPresentationIfNeeded() {
                    return
                }
                self.scene.updateBoard(newBoard)
                self.refreshGuideHighlights()
            }
            .store(in: &cancellables)

        core.$lastMovementResolution
            .receive(on: RunLoop.main)
            .sink { [weak self] resolution in
                // ワープ演出などを current 更新と同期させるため、最新の移動結果を控えておく
                guard let self else { return }
                self.latestMovementResolution = resolution
                self.completedMovementReplayResolution = nil
                if let resolution,
                   resolution.finalPosition == self.core.current,
                   self.isMovementReplayCandidate(resolution) {
                    self.prepareMovementReplayPresentationIfNeeded(using: resolution)
                }
            }
            .store(in: &cancellables)

        core.$current
            .receive(on: RunLoop.main)
            .sink { [weak self] newPoint in
                guard let self else { return }
                if let destination = newPoint,
                   let resolution = self.latestMovementResolution ?? self.core.lastMovementResolution,
                   resolution.finalPosition == destination,
                   resolution != self.completedMovementReplayResolution,
                   self.isMovementReplayCandidate(resolution) {
                    // レイ型などの途中処理を持つ移動は、盤面状態も含めて一歩ずつ再生する
                    self.beginMovementReplay(using: resolution)
                } else if let destination = newPoint,
                          let resolution = self.latestMovementResolution ?? self.core.lastMovementResolution,
                          resolution.finalPosition == destination,
                          resolution != self.completedMovementReplayResolution,
                          resolution.appliedEffects.contains(where: { appliedEffect in
                              switch appliedEffect.effect {
                              case .warp, .returnWarp:
                                  return true
                              default:
                                  return false
                              }
                          }) {
                    // 単純なワープだけは従来の専用演出を利用する
                    self.scene.playWarpTransition(using: resolution)
                    self.scheduleLandingEffect(at: destination, after: 0.46)
                } else {
                    // 条件を満たさない場合は従来の単純移動を行う
                    self.scene.moveKnight(to: newPoint)
                    if let newPoint {
                        self.scheduleLandingEffect(at: newPoint, after: 0.20)
                    }
                }
                // 一度利用した解決情報は破棄し、次の移動に備える
                self.latestMovementResolution = nil
                self.refreshGuideHighlights(currentOverride: newPoint)
            }
            .store(in: &cancellables)

        core.$enemyStates
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if let event = self.core.dungeonEnemyTurnEvent,
                   event.id != self.completedEnemyTurnEventID,
                   self.activeEnemyTurnEvent?.id != event.id {
                    if self.isMovementReplayActive || self.preparePendingMovementReplayPresentationIfNeeded() {
                        self.pendingEnemyTurnEventAfterMovementReplay = event
                        self.pushHighlightsToScene()
                        return
                    }
                    self.activeEnemyTurnEvent = event
                    self.isEnemyTurnAnimationActive = true
                }
                if self.isMovementReplayActive || self.preparePendingMovementReplayPresentationIfNeeded() {
                    return
                }
                self.pushHighlightsToScene()
            }
            .store(in: &cancellables)

        core.$dungeonEnemyTurnEvent
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] event in
                guard let self else { return }
                guard event.id != self.completedEnemyTurnEventID else { return }
                self.playDungeonEnemyTurn(event)
            }
            .store(in: &cancellables)

        core.$crackedFloorPoints
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.isMovementReplayActive || self.preparePendingMovementReplayPresentationIfNeeded() {
                    return
                }
                self.pushHighlightsToScene()
            }
            .store(in: &cancellables)

        core.$collapsedFloorPoints
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.isMovementReplayActive || self.preparePendingMovementReplayPresentationIfNeeded() {
                    return
                }
                self.pushHighlightsToScene()
            }
            .store(in: &cancellables)

        core.$consumedHealingTilePoints
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.isMovementReplayActive || self.preparePendingMovementReplayPresentationIfNeeded() {
                    return
                }
                self.pushHighlightsToScene()
            }
            .store(in: &cancellables)

        core.$collectedDungeonCardPickupIDs
            .receive(on: RunLoop.main)
            .sink { [weak self] collectedIDs in
                guard let self else { return }
                if self.isMovementReplayActive || self.preparePendingMovementReplayPresentationIfNeeded() {
                    return
                }
                self.playCollectionEffectsIfNeeded(
                    previousCardIDs: self.observedCollectedDungeonCardPickupIDs,
                    nextCardIDs: collectedIDs,
                    previousRelicIDs: nil,
                    nextRelicIDs: []
                )
                self.observedCollectedDungeonCardPickupIDs = collectedIDs
                self.pushHighlightsToScene()
            }
            .store(in: &cancellables)

        core.$collectedDungeonRelicPickupIDs
            .receive(on: RunLoop.main)
            .sink { [weak self] collectedIDs in
                guard let self else { return }
                if self.isMovementReplayActive || self.preparePendingMovementReplayPresentationIfNeeded() {
                    return
                }
                self.playCollectionEffectsIfNeeded(
                    previousCardIDs: nil,
                    nextCardIDs: [],
                    previousRelicIDs: self.observedCollectedDungeonRelicPickupIDs,
                    nextRelicIDs: collectedIDs
                )
                self.observedCollectedDungeonRelicPickupIDs = collectedIDs
                self.pushHighlightsToScene()
            }
            .store(in: &cancellables)

        core.$isDungeonExitUnlocked
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.isMovementReplayActive || self.preparePendingMovementReplayPresentationIfNeeded() {
                    return
                }
                self.pushHighlightsToScene()
            }
            .store(in: &cancellables)

        core.$dungeonExitUnlockEvent
            .receive(on: RunLoop.main)
            .sink { [weak self] event in
                guard let self, let event else { return }
                self.scene.playDungeonExitUnlockEffect(at: event.exitPoint)
            }
            .store(in: &cancellables)
    }

    /// 手札の更新を受け取り、アニメーションとガイド情報を整理する
    /// - Parameter newHandStacks: 最新の手札スタック一覧
    private func handleHandStacksUpdate(_ newHandStacks: [HandStack]) {
        debugLog("手札更新を受信: スタック数=\(newHandStacks.count), 退避ハンドあり=\(pendingGuideHand != nil)")

        var nextTopCardIDs: [UUID: UUID] = [:]
        for stack in newHandStacks {
            guard let topCard = stack.topCard else { continue }
            let previousTopID = topCardIDsByStack[stack.id]
            if let previousTopID, previousTopID != topCard.id {
                hiddenCardIDs.remove(previousTopID)
                debugLog("スタック先頭カードを更新: stackID=\(stack.id), 旧トップID=\(previousTopID), 新トップID=\(topCard.id), 残枚数=\(stack.count)")
            }
            nextTopCardIDs[stack.id] = topCard.id
        }

        let removedStackIDs = Set(topCardIDsByStack.keys).subtracting(nextTopCardIDs.keys)
        for stackID in removedStackIDs {
            if let previousTopID = topCardIDsByStack[stackID] {
                hiddenCardIDs.remove(previousTopID)
                debugLog("スタック消滅に伴いトップカード ID を解放: stackID=\(stackID), cardID=\(previousTopID)")
            }
        }
        topCardIDsByStack = nextTopCardIDs

        let topCardIDSet = Set(nextTopCardIDs.values)
        let nextPreviewIDs = Set(core.nextCards.map { $0.id })
        let validIDs = topCardIDSet.union(nextPreviewIDs)
        hiddenCardIDs.formIntersection(validIDs)

        if let animatingCard, !validIDs.contains(animatingCard.id) {
            self.animatingCard = nil
            animatingStackID = nil
            animationState = .idle
            animationTargetGridPoint = nil
        }

        refreshGuideHighlights(handOverride: newHandStacks)
    }
}
