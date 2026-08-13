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
        /// レイではない直線/斜め 2 マスカードが到達できる座標集合
        var directTwoStepDestinations: Set<GridPoint>
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
            directTwoStepDestinations: [],
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
    /// 直近のカードまたは基本移動に対応するモノの表示上の動き。
    private var latestPlayerMotionStyle: PlayerMotionStyle = .waddle
    /// 分割リプレイ中に区間をまたいで維持する表示上の動き。
    private var movementReplayMotionStyle: PlayerMotionStyle = .waddle
    /// Core の最終状態通知が先に届いても、移動リプレイ開始までは初期表示を維持するための解決情報
    private var preparedMovementReplayResolution: MovementResolution?
    /// 再生済みの解決情報を保持し、後続の敵ターンなどで古い移動を再準備しないようにする
    private var completedMovementReplayResolution: MovementResolution?
    /// 移動演出の開始を GameViewModel 側へ伝える
    var onMovementPresentationStarted: ((MovementResolution) -> Void)?
    /// 移動演出の各ステップを GameViewModel 側へ伝える
    var onMovementPresentationStep: ((MovementResolution.PresentationStep) -> Void)?
    /// 移動演出のステップ適用後、オーバーレイ確認のためにリプレイを一時停止するかを問い合わせる
    var shouldPauseMovementPresentationAfterStep: ((MovementResolution.PresentationStep) -> Bool)?
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
    /// 移動演出中だけ暗闇視界の中心に使う表示上の現在地
    private var presentationCurrentPoint: GridPoint?
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
    /// 拾得/宝箱オーバーレイ確認のため、経路移動を意図的に止めているかどうか
    private var isMovementReplayPausedForOverlay = false
    /// 分割再生中に次に再生する経路インデックス
    private var movementReplayNextPathIndex = 0
    /// 区間完了コールバックの古い戻りを無視するための世代番号
    private var movementReplaySegmentGeneration = 0
    /// SpriteKit の完了コールバックが戻らない場合に入力ロックを解除する保険
    private var movementReplayFallbackWorkItem: DispatchWorkItem?
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
    /// フロア開始から初手まで階段と鍵を強調して、重要地点を見失いにくくするための状態
    private var isFloorStartTargetEmphasisActive = false
    /// 強調開始時点の手数。これを超えたら初手が成立したものとして強調を消す。
    private var floorStartTargetEmphasisMoveCount: Int?

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
        hapticsEnabled: Bool,
        visualStyle: AppThemeVisualStyle = .classic
    ) {
        scene.gameCore = core
        updateHapticsSetting(isEnabled: hapticsEnabled)
        updateGuideMode(enabled: guideModeEnabled)
        applyScenePalette(for: colorScheme, visualStyle: visualStyle)
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
        if isMovementReplayActive || preparedMovementReplayResolution != nil {
            pushHighlightsToScene()
            return
        }
        scene.updateBoard(core.board)
        scene.moveKnight(to: core.current)
        refreshGuideHighlights()
        activateFloorStartTargetEmphasisIfNeeded()
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
    func applyScenePalette(
        for scheme: ColorScheme,
        visualStyle: AppThemeVisualStyle = .classic
    ) {
        let appTheme = AppTheme(colorScheme: scheme, visualStyle: visualStyle)
        let palette = GameScenePalette(
            boardBackground: appTheme.skBoardBackground,
            boardGridLine: appTheme.skBoardGridLine,
            isNeonGridTheme: visualStyle == .starChartSurveyTower,
            boardStarChartLine: appTheme.skBoardStarChartLine,
            boardStarChartNode: appTheme.skBoardStarChartNode,
            boardConstellationLine: appTheme.skBoardConstellationLine,
            boardConstellationGlowLine: appTheme.skBoardConstellationGlowLine,
            boardConstellationStar: appTheme.skBoardConstellationStar,
            boardConstellationStarGlow: appTheme.skBoardConstellationStarGlow,
            boardStarParticle: appTheme.skBoardStarParticle,
            boardNebulaDepth: appTheme.skBoardNebulaDepth,
            boardDistantStar: appTheme.skBoardDistantStar,
            boardDistantStarTwinkle: appTheme.skBoardDistantStarTwinkle,
            boardGlassHighlight: appTheme.skBoardGlassHighlight,
            boardTileInnerGlow: appTheme.skBoardTileInnerGlow,
            boardAstralCore: appTheme.skBoardAstralCore,
            boardAstralCoreRing: appTheme.skBoardAstralCoreRing,
            boardAstralCoreGlow: appTheme.skBoardAstralCoreGlow,
            boardAstralCorePulse: appTheme.skBoardAstralCorePulse,
            boardTileVisited: appTheme.skBoardTileVisited,
            boardTileUnvisited: appTheme.skBoardTileUnvisited,
            boardDarknessHiddenTile: appTheme.skBoardDarknessHiddenTile,
            boardDarknessBoundary: appTheme.skBoardDarknessBoundary,
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
            boardTileEffectPoison: appTheme.skBoardTileEffectPoison,
            boardTileEffect