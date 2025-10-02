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

        /// すべて空集合の初期値を返すヘルパー
        static let empty = GuideHighlightBuckets(
            singleVectorDestinations: [],
            multipleVectorDestinations: []
        )
    }

    /// ガイド種別で保持している盤面ハイライト集合
    /// - Note: ガイドモードのオン/オフに関わらず最新候補を記録し、再描画時に即座に Scene へ伝搬できるようにする
    private(set) var guideHighlightBuckets: GuideHighlightBuckets = .empty
    /// ガイド設定に関係なく強制表示したいハイライト集合
    /// - Important: チュートリアルやカード選択 UI からの明示的な指示を反映し、ガイド無効時でもユーザーへ候補マスを提示する
    /// - Note: テストから現在のハイライト状況を検証できるように `private(set)` で公開する。
    private(set) var forcedSelectionHighlightPoints: Set<GridPoint> = []
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
            impassablePoints: mode.impassableTilePoints
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
            boardKnight: appTheme.skBoardKnight,
            boardGuideHighlight: appTheme.skBoardGuideHighlight
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
            .forcedSelection: forcedSelectionHighlightPoints
        ]
        scene.updateHighlights(highlights)
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
            if representative.card.move.movementVectors.count > 1 {
                computedBuckets.multipleVectorDestinations.formUnion(destinations)
            } else {
                computedBuckets.singleVectorDestinations.formUnion(destinations)
            }
        }

        guard guideModeEnabled else {
            guideHighlightBuckets = .empty
            pushHighlightsToScene()
            pendingGuideHand = nil
            pendingGuideCurrent = nil
            pendingGuideBuckets = nil
            let total = computedBuckets.singleVectorDestinations.count + computedBuckets.multipleVectorDestinations.count
            debugLog(
                "ガイドを消灯: ガイドモードが無効 単一=\(computedBuckets.singleVectorDestinations.count) " +
                "複数=\(computedBuckets.multipleVectorDestinations.count) 合計=\(total)"
            )
            return
        }

        guard progress == .playing else {
            pendingGuideHand = handStacks
            pendingGuideCurrent = current
            pendingGuideBuckets = computedBuckets
            guideHighlightBuckets = .empty
            pushHighlightsToScene()
            let total = computedBuckets.singleVectorDestinations.count + computedBuckets.multipleVectorDestinations.count
            debugLog(
                "ガイド更新を保留: 状態=\(String(describing: progress)) 単一=\(computedBuckets.singleVectorDestinations.count) " +
                "複数=\(computedBuckets.multipleVectorDestinations.count) 合計=\(total)"
            )
            return
        }

        pendingGuideHand = nil
        pendingGuideCurrent = nil
        pendingGuideBuckets = nil
        guideHighlightBuckets = computedBuckets
        pushHighlightsToScene()
        let total = computedBuckets.singleVectorDestinations.count + computedBuckets.multipleVectorDestinations.count
        debugLog(
            "ガイド描画: 単一=\(computedBuckets.singleVectorDestinations.count) " +
            "複数=\(computedBuckets.multipleVectorDestinations.count) 合計=\(total)"
        )
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

        let validPoints = Set(candidatePoints.filter { core.board.isTraversable($0) })
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

        // スタック位置が変化している可能性を考慮し、最新のインデックスを再評価する
        let resolvedIndex: Int
        let moveForExecution: ResolvedCardMove
        if core.handStacks.indices.contains(resolvedMove.stackIndex),
           core.handStacks[resolvedMove.stackIndex].id == resolvedMove.stackID {
            resolvedIndex = resolvedMove.stackIndex
            moveForExecution = resolvedMove
        } else if let fallbackIndex = core.handStacks.firstIndex(where: { $0.id == resolvedMove.stackID }) {
            resolvedIndex = fallbackIndex
            moveForExecution = ResolvedCardMove(
                stackID: resolvedMove.stackID,
                stackIndex: fallbackIndex,
                card: resolvedMove.card,
                moveVector: resolvedMove.moveVector,
                destination: resolvedMove.destination
            )
            debugLog(
                "スタック位置を補正: 元index=\(resolvedMove.stackIndex) 新index=\(fallbackIndex) stackID=\(resolvedMove.stackID)"
            )
        } else {
            debugLog("スタック演出を中止: 対象 stack が見つからない stackID=\(resolvedMove.stackID)")
            return false
        }

        let stack = core.handStacks[resolvedIndex]
        guard let topCard = stack.topCard else {
            debugLog("スタック演出を中止: トップカードなし stackID=\(stack.id)")
            return false
        }

        guard topCard.id == moveForExecution.card.id else {
            debugLog(
                "スタック演出を中止: トップカードが変化 requestCardID=\(moveForExecution.card.id) currentID=\(topCard.id)"
            )
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

        core.$current
            .receive(on: RunLoop.main)
            .sink { [weak self] newPoint in
                guard let self else { return }
                self.scene.moveKnight(to: newPoint)
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
