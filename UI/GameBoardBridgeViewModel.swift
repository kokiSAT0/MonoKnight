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
        /// 複数マス移動カード（レイ型）が到達できる座標集合
        var multiStepDestinations: Set<GridPoint>
        /// ワープ系カード専用の座標集合（紫枠で強調する）
        var warpDestinations: Set<GridPoint>

        /// すべて空集合の初期値を返すヘルパー
        static let empty = GuideHighlightBuckets(
            singleVectorDestinations: [],
            multipleVectorDestinations: [],
            multiStepDestinations: [],
            warpDestinations: []
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
            requiredVisitOverrides: mode.additionalVisitRequirements,
            togglePoints: mode.toggleTilePoints,
            impassablePoints: mode.impassableTilePoints,
            tileEffects: mode.tileEffects
        )
        preparedScene.scaleMode = .resizeFill
        preparedScene.gameCore = core
        self.scene = preparedScene

        bindGameCore()
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

    /// 現在保持しているハイライト状態を SpriteKit シーンへ反映する
    /// - Note: 種類ごとの集合を辞書にまとめ、`GameScene` 側の一括更新 API と齟齬なく連携する
    private func pushHighlightsToScene() {
        let highlights: [BoardHighlightKind: Set<GridPoint>] = [
            .guideSingleCandidate: guideHighlightBuckets.singleVectorDestinations,
            .guideMultipleCandidate: guideHighlightBuckets.multipleVectorDestinations,
            .guideMultiStepCandidate: guideHighlightBuckets.multiStepDestinations,
            .guideWarpCandidate: guideHighlightBuckets.warpDestinations,
            .forcedSelection: forcedSelectionHighlightPoints
        ]
        scene.updateHighlights(highlights)
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
        let multiStepCount = buckets.multiStepDestinations.count
        let warpCount = buckets.warpDestinations.count
        let totalCount = singleCount + multipleCount + multiStepCount + warpCount

        // --- 呼び出し側で使うログ文面を一括生成する ---
        let logMessage = (
            "\(logPrefix) 単一=\(singleCount) 複数=\(multipleCount) " +
            "連続=\(multiStepCount) ワープ=\(warpCount) 合計=\(totalCount)"
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
        for moves in groupedByCard.values {
            guard let representative = moves.first else { continue }
            let destinations = moves.map { $0.destination }
            let move = representative.card.move

            if move == .superWarp {
                // スーパーワープは盤面全域が候補となりガイドが画面を覆ってしまうため、あえて登録しない
                continue
            }

            if move == .fixedWarp {
                // 固定ワープのみ紫枠で視認性を高めるため専用バケットへ分類する
                computedBuckets.warpDestinations.formUnion(destinations)
                continue
            }

            if move.kind == .multiStep {
                // 連続移動カードは専用のシアン枠で描画するため、別バケットへ振り分ける
                computedBuckets.multiStepDestinations.formUnion(destinations)
            } else if move.movementVectors.count > 1 {
                // 複数方向カードは従来どおりオレンジ枠で強調する
                computedBuckets.multipleVectorDestinations.formUnion(destinations)
            } else {
                // 単方向カードは落ち着いたグレー枠へ分類する
                computedBuckets.singleVectorDestinations.formUnion(destinations)
            }
        }

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
        guard animatingCard == nil else {
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
        let targetPoint = moveForExecution.destination
        animationTargetGridPoint = targetPoint
        hiddenCardIDs.insert(topCard.id)
        animatingCard = topCard
        animatingStackID = stack.id
        animationState = .idle

        debugLog(
            "スタック演出開始: stackID=\(stack.id) card=\(topCard.move.displayName) dest=\(targetPoint) vector=(dx:\(moveForExecution.moveVector.dx), dy:\(moveForExecution.moveVector.dy)) 残枚数=\(stack.count)"
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
                self.scene.updateBoard(newBoard)
                self.refreshGuideHighlights()
            }
            .store(in: &cancellables)

        core.$lastMovementResolution
            .receive(on: RunLoop.main)
            .sink { [weak self] resolution in
                // ワープ演出などを current 更新と同期させるため、最新の移動結果を控えておく
                self?.latestMovementResolution = resolution
            }
            .store(in: &cancellables)

        core.$current
            .receive(on: RunLoop.main)
            .sink { [weak self] newPoint in
                guard let self else { return }
                if let destination = newPoint,
                   let resolution = self.latestMovementResolution,
                   resolution.finalPosition == destination,
                   resolution.appliedEffects.contains(where: { appliedEffect in
                       if case .warp = appliedEffect.effect { return true }
                       return false
                   }) {
                    // ワープ効果が含まれている場合は専用演出を再生し、より没入感のある挙動に切り替える
                    self.scene.playWarpTransition(using: resolution)
                } else {
                    // 条件を満たさない場合は従来の単純移動を行う
                    self.scene.moveKnight(to: newPoint)
                }
                // 一度利用した解決情報は破棄し、次の移動に備える
                self.latestMovementResolution = nil
                self.refreshGuideHighlights(currentOverride: newPoint)
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
