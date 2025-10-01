import Combine  // Combine を利用して GameCore の更新を監視するために読み込む
import Foundation
import Game
import SharedSupport
import SwiftUI
import UIKit

/// SpriteKit の GameScene と SwiftUI 側レイアウトを仲介する ViewModel
/// GameViewModel から盤面演出に関わる責務を切り出し、描画更新とゲーム全体の状態管理を分離する
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
    /// ガイド種別で保持している盤面ハイライト集合
    /// - Note: ガイドモードのオン/オフに関わらず最新候補を記録し、再描画時に即座に Scene へ伝搬できるようにする
    private var guideHighlightPoints: Set<GridPoint> = []
    /// ガイド設定に関係なく強制表示したいハイライト集合
    /// - Important: チュートリアルやカード選択 UI からの明示的な指示を反映し、ガイド無効時でもユーザーへ候補マスを提示する
    private var forcedSelectionHighlightPoints: Set<GridPoint> = []
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
            requiredVisitOverrides: mode.additionalVisitRequirements
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
        updateForcedSelectionHighlights([])
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
            guideHighlightPoints = []
            pushHighlightsToScene()
            pendingGuideHand = nil
            pendingGuideCurrent = nil
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
            .guide: guideHighlightPoints,
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
            guideHighlightPoints = []
            pushHighlightsToScene()
            pendingGuideHand = nil
            pendingGuideCurrent = nil
            debugLog("ガイド更新を中断: 現在地が未確定 状態=\(String(describing: progress)) スタック数=\(handStacks.count)")
            return
        }

        // GameCore.availableMoves() 内で primaryVector が評価されるため、複数候補カード追加後もここから同じインターフェースで受け取れる
        let resolvedMoves = core.availableMoves(handStacks: handStacks, current: current)
        let candidatePoints = Set(resolvedMoves.map { $0.destination })

        guard guideModeEnabled else {
            guideHighlightPoints = []
            pushHighlightsToScene()
            pendingGuideHand = nil
            pendingGuideCurrent = nil
            debugLog("ガイドを消灯: ガイドモードが無効 候補=\(candidatePoints.count)")
            return
        }

        guard progress == .playing else {
            pendingGuideHand = handStacks
            pendingGuideCurrent = current
            guideHighlightPoints = []
            pushHighlightsToScene()
            debugLog("ガイド更新を保留: 状態=\(String(describing: progress)) 候補=\(candidatePoints.count)")
            return
        }

        pendingGuideHand = nil
        pendingGuideCurrent = nil
        guideHighlightPoints = candidatePoints
        pushHighlightsToScene()
        debugLog("ガイド描画: 候補=\(candidatePoints.count)")
    }

    /// 強制的に表示したいハイライト集合を更新する
    /// - Parameter points: ガイド設定に依存せず提示したい盤面座標集合
    /// - Important: チュートリアルやカード選択 UI が「このマスを必ず選んでほしい」という意図を伝えるための経路
    func updateForcedSelectionHighlights(_ points: Set<GridPoint>) {
        let validPoints = Set(points.filter { core.board.contains($0) })
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
    @discardableResult
    func animateCardPlay(for stack: HandStack, at index: Int) -> Bool {
        guard animatingCard == nil else { return false }
        guard core.current != nil else { return false }
        guard let topCard = stack.topCard else { return false }

        // 現在の手札状況に基づく使用可能カードを検索し、該当スタックの候補を取得する
        // - Note: availableMoves() がカード内の全ベクトルを展開しているため、複数候補カードでもここから 1 件を選ぶだけで良い
        guard let resolvedMove = core.availableMoves().first(where: { candidate in
            candidate.stackID == stack.id && candidate.card.id == topCard.id
        }) else {
            debugLog("スタック演出を中止: 使用可能リストに該当カードなし stackID=\(stack.id)")
            return false
        }

        if !forcedSelectionHighlightPoints.isEmpty {
            // 強制ハイライトが点灯したまま演出へ移行しないよう、開始前に必ずリセットする
            updateForcedSelectionHighlights([])
        }

        // 現在位置からカードの移動量を適用し、演出で目指す盤面座標を算出する
        // ここをプレイ前の現在地で固定してしまうと、カードが正しいマスへ移動しないため注意する
        let targetPoint = resolvedMove.destination
        animationTargetGridPoint = targetPoint
        hiddenCardIDs.insert(topCard.id)
        animatingCard = topCard
        animatingStackID = stack.id
        animationState = .idle

        debugLog("スタック演出開始: stackID=\(stack.id) card=\(topCard.move.displayName) 残枚数=\(stack.count)")

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
                self.core.playCard(using: resolvedMove)
            }
            self.hiddenCardIDs.remove(cardID)
            if self.animatingCard?.id == cardID {
                self.animatingCard = nil
            }
            self.animatingStackID = nil
            self.animationState = .idle
            self.animationTargetGridPoint = nil
            debugLog("スタック演出完了: index=\(index) cardID=\(cardID)")
        }

        return true
    }

    /// ボードタップによるプレイ要求を処理する
    /// - Parameter request: GameCore から渡されるリクエスト
    func handleBoardTapPlayRequest(_ request: BoardTapPlayRequest) {
        defer { core.clearBoardTapPlayRequest(request.id) }

        guard animatingCard == nil else {
            debugLog("BoardTapPlayRequest を無視: 別演出が進行中 requestID=\(request.id)")
            return
        }

        let resolvedIndex: Int
        if core.handStacks.indices.contains(request.stackIndex),
           core.handStacks[request.stackIndex].id == request.stackID {
            resolvedIndex = request.stackIndex
        } else if let fallbackIndex = core.handStacks.firstIndex(where: { $0.id == request.stackID }) {
            resolvedIndex = fallbackIndex
        } else {
            debugLog("BoardTapPlayRequest を無視: 対象 stack が見つからない stackID=\(request.stackID)")
            return
        }

        let stack = core.handStacks[resolvedIndex]
        guard let currentTop = stack.topCard else {
            debugLog("BoardTapPlayRequest を無視: トップカードなし stackID=\(stack.id)")
            return
        }

        let sameID = currentTop.id == request.topCard.id
        let sameMove = currentTop.move == request.topCard.move
        debugLog(
            "BoardTapPlayRequest 受信: requestID=\(request.id) 要求index=\(request.stackIndex) 解決index=\(resolvedIndex) sameID=\(sameID) sameMove=\(sameMove)"
        )

        guard sameID || sameMove else {
            debugLog("BoardTapPlayRequest を無視: トップカードが変化")
            return
        }

        _ = animateCardPlay(for: stack, at: resolvedIndex)
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
            guideHighlightPoints = []
            updateForcedSelectionHighlights([])
        default:
            guideHighlightPoints = []
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

        core.$boardTapPlayRequest
            .receive(on: RunLoop.main)
            .sink { [weak self] request in
                guard let self, let request else { return }
                self.handleBoardTapPlayRequest(request)
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
