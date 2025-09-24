import Combine  // Combine を利用して GameCore の更新を ViewModel 経由で伝搬する
import Foundation
import Game
import SharedSupport
import SwiftUI
import UIKit

/// GameView のロジックとサービス連携を担う ViewModel
/// 描画に直接関係しない処理を SwiftUI View から切り離し、責務を明確化する
@MainActor
final class GameViewModel: ObservableObject {
    /// ゲームモードごとの設定
    let mode: GameMode
    /// Game パッケージが提供するファクトリセット
    let gameInterfaces: GameModuleInterfaces
    /// Game Center 連携を担当するサービス
    let gameCenterService: GameCenterServiceProtocol
    /// 広告表示の状態管理を担当するサービス
    let adsService: AdsServiceProtocol
    /// タイトル復帰時に親へ伝えるためのクロージャ
    let onRequestReturnToTitle: (() -> Void)?

    /// SwiftUI から観測するゲームロジック本体
    @Published private(set) var core: GameCore
    /// SpriteKit のシーン。UIViewRepresentable から再利用するため定数として保持する
    let scene: GameScene

    /// 結果画面表示フラグ
    @Published var showingResult = false
    /// 手詰まりバナーの表示可否
    @Published var isShowingPenaltyBanner = false
    /// ペナルティバナーを自動的に閉じるためのワークアイテム
    var penaltyDismissWorkItem: DispatchWorkItem?
    /// メニューで確認待ちのアクション
    @Published var pendingMenuAction: GameMenuAction?
    /// ポーズメニューの表示状態
    @Published var isPauseMenuPresented = false
    /// 統計バッジ領域の高さ
    @Published var statisticsHeight: CGFloat = 0
    /// 手札セクションの高さ
    @Published var handSectionHeight: CGFloat = 0
    /// 画面に表示している経過秒数
    @Published var displayedElapsedSeconds: Int = 0
    /// 暫定スコア
    var displayedScore: Int {
        core.totalMoveCount * 10 + displayedElapsedSeconds
    }
    /// 現在アニメーション中のカード
    @Published var animatingCard: DealtCard?
    /// アニメーション対象スタックの ID
    @Published var animatingStackID: UUID?
    /// アニメーション演出の都合で一時的に隠すカード ID 集合
    @Published var hiddenCardIDs: Set<UUID> = []
    /// スタックごとに追跡しているトップカード ID
    @Published var topCardIDsByStack: [UUID: UUID] = [:]
    /// カードアニメーションの状態
    @Published var animationState: CardAnimationPhase = .idle
    /// 盤面アンカー
    @Published var boardAnchor: Anchor<CGRect>?
    /// カード演出中に利用する座標
    @Published var animationTargetGridPoint: GridPoint?
    /// デッドロック中に退避しておく手札情報
    @Published var pendingGuideHand: [HandStack]?
    /// デッドロック中に退避する現在地
    @Published var pendingGuideCurrent: GridPoint?
    /// レイアウト診断用のスナップショット
    @Published var lastLoggedLayoutSnapshot: BoardLayoutSnapshot?
    /// 経過秒数を 1 秒刻みで更新するためのタイマーパブリッシャ
    let elapsedTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Combine の購読を保持するセット
    private var cancellables = Set<AnyCancellable>()

    /// ViewModel の初期化
    /// - Parameters:
    ///   - mode: 選択されたゲームモード
    ///   - gameInterfaces: GameCore を生成するためのファクトリ
    ///   - gameCenterService: スコア送信に利用するサービス
    ///   - adsService: 広告表示制御を担うサービス
    ///   - onRequestReturnToTitle: タイトルへ戻る際に呼び出すクロージャ
    init(
        mode: GameMode,
        gameInterfaces: GameModuleInterfaces,
        gameCenterService: GameCenterServiceProtocol,
        adsService: AdsServiceProtocol,
        onRequestReturnToTitle: (() -> Void)?
    ) {
        self.mode = mode
        self.gameInterfaces = gameInterfaces
        self.gameCenterService = gameCenterService
        self.adsService = adsService
        self.onRequestReturnToTitle = onRequestReturnToTitle

        // GameCore を生成し、ViewModel 経由で観測できるようにする
        let generatedCore = gameInterfaces.makeGameCore(mode)
        self.core = generatedCore

        // SpriteKit シーンを組み立ててゲームロジックと接続する
        let preparedScene = GameScene(
            initialBoardSize: mode.boardSize,
            initialVisitedPoints: mode.initialVisitedPoints
        )
        preparedScene.scaleMode = .resizeFill
        preparedScene.gameCore = generatedCore
        self.scene = preparedScene

        // GameCore の変更を ViewModel 経由で SwiftUI へ伝える
        generatedCore.objectWillChange
            .sink { [weak self] _ in
                guard let self else { return }
                self.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    /// ユーザー設定から手札の並び替え戦略を復元する
    /// - Parameter rawValue: UserDefaults に保存されている文字列値
    func restoreHandOrderingStrategy(from rawValue: String) {
        guard let strategy = HandOrderingStrategy(rawValue: rawValue) else { return }
        core.updateHandOrderingStrategy(strategy)
    }

    /// 手札表示の並び替え設定を即座に反映する
    /// - Parameter rawValue: AppStorage から得た値
    func applyHandOrderingStrategy(rawValue: String) {
        let strategy = HandOrderingStrategy(rawValue: rawValue) ?? .insertionOrder
        core.updateHandOrderingStrategy(strategy)
    }

    /// 結果画面を閉じた際の後処理
    func finalizeResultDismissal() {
        showingResult = false
    }

    /// SpriteKit シーンの配色を更新する
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

    /// ハイライト表示を最新の状態へ更新する
    func refreshGuideHighlights(
        guideModeEnabled: Bool,
        handOverride: [HandStack]? = nil,
        currentOverride: GridPoint? = nil,
        progressOverride: GameProgress? = nil
    ) {
        let handStacks = handOverride ?? core.handStacks
        let progress = progressOverride ?? core.progress

        guard let current = currentOverride ?? core.current else {
            scene.updateGuideHighlights([])
            pendingGuideHand = nil
            pendingGuideCurrent = nil
            debugLog("ガイド更新を中断: 現在地が未確定 状態=\(String(describing: progress)) スタック数=\(handStacks.count)")
            return
        }

        var candidatePoints: Set<GridPoint> = []
        for stack in handStacks {
            guard let card = stack.topCard else { continue }
            let destination = current.offset(dx: card.move.dx, dy: card.move.dy)
            if core.board.contains(destination) {
                candidatePoints.insert(destination)
            }
        }

        guard guideModeEnabled else {
            scene.updateGuideHighlights([])
            pendingGuideHand = nil
            pendingGuideCurrent = nil
            debugLog("ガイドを消灯: ガイドモードが無効 候補=\(candidatePoints.count)")
            return
        }

        guard progress == .playing else {
            pendingGuideHand = handStacks
            pendingGuideCurrent = current
            debugLog("ガイド更新を保留: 状態=\(String(describing: progress)) 候補=\(candidatePoints.count)")
            return
        }

        pendingGuideHand = nil
        pendingGuideCurrent = nil
        scene.updateGuideHighlights(candidatePoints)
        debugLog("ガイド描画: 候補=\(candidatePoints.count)")
    }

    /// 表示用の経過時間を再計算する
    func updateDisplayedElapsedTime() {
        displayedElapsedSeconds = core.elapsedSeconds
    }

    /// 指定スタックのカードが現在位置から使用可能か判定する
    func isCardUsable(_ stack: HandStack) -> Bool {
        guard let card = stack.topCard else { return false }
        guard let current = core.current else { return false }
        let target = current.offset(dx: card.move.dx, dy: card.move.dy)
        return core.board.contains(target)
    }

    /// 手札スタックのトップカードを盤面へ送るアニメーションを準備する
    @discardableResult
    func animateCardPlay(for stack: HandStack, at index: Int, hapticsEnabled: Bool) -> Bool {
        guard animatingCard == nil else { return false }
        guard let current = core.current else { return false }
        guard let topCard = stack.topCard, isCardUsable(stack) else { return false }

        animationTargetGridPoint = current
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
                self.core.playCard(at: index)
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

    /// 盤面タップに応じたプレイ要求を処理する
    func handleBoardTapPlayRequest(_ request: BoardTapPlayRequest, hapticsEnabled: Bool) {
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

        _ = animateCardPlay(for: stack, at: resolvedIndex, hapticsEnabled: hapticsEnabled)
    }

    /// ゲームの進行状況に応じた操作をまとめて処理する
    func performMenuAction(_ action: GameMenuAction) {
        pendingMenuAction = nil
        switch action {
        case .manualPenalty:
            penaltyDismissWorkItem?.cancel()
            penaltyDismissWorkItem = nil
            isShowingPenaltyBanner = false
            core.applyManualPenaltyRedraw()

        case .reset:
            penaltyDismissWorkItem?.cancel()
            penaltyDismissWorkItem = nil
            isShowingPenaltyBanner = false
            showingResult = false
            core.reset()
            adsService.resetPlayFlag()

        case .returnToTitle:
            penaltyDismissWorkItem?.cancel()
            penaltyDismissWorkItem = nil
            isShowingPenaltyBanner = false
            showingResult = false
            core.reset()
            adsService.resetPlayFlag()
            onRequestReturnToTitle?()
        }
    }

    /// 盤面サイズや踏破状況などを初期化する
    func prepareForAppear(
        colorScheme: ColorScheme,
        guideModeEnabled: Bool,
        handOrderingStrategy: HandOrderingStrategy
    ) {
        scene.gameCore = core
        applyScenePalette(for: colorScheme)
        refreshGuideHighlights(guideModeEnabled: guideModeEnabled)
        updateDisplayedElapsedTime()
        core.updateHandOrderingStrategy(handOrderingStrategy)
    }

    /// ペナルティイベントを受信した際の処理
    func handlePenaltyEvent(hapticsEnabled: Bool) {
        penaltyDismissWorkItem?.cancel()
        penaltyDismissWorkItem = nil

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8, blendDuration: 0.2)) {
            isShowingPenaltyBanner = true
        }

        if hapticsEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                self.isShowingPenaltyBanner = false
            }
            self.penaltyDismissWorkItem = nil
        }
        penaltyDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: workItem)
    }

    /// 盤面レイアウト関連のアンカー情報を更新する
    func updateBoardAnchor(_ anchor: Anchor<CGRect>?) {
        boardAnchor = anchor
    }
}

/// ゲーム画面のメニュー操作を表す列挙型
enum GameMenuAction: Hashable, Identifiable {
    case manualPenalty(penaltyCost: Int)
    case reset
    case returnToTitle

    /// Identifiable 準拠のための識別子
    var id: Int {
        switch self {
        case .manualPenalty:
            return 0
        case .reset:
            return 1
        case .returnToTitle:
            return 2
        }
    }

    /// 確認ダイアログ用のボタンタイトル
    var confirmationButtonTitle: String {
        switch self {
        case .manualPenalty:
            return "ペナルティを払う"
        case .reset:
            return "リセットする"
        case .returnToTitle:
            return "タイトルへ戻る"
        }
    }

    /// 確認ダイアログで表示する説明文
    var confirmationMessage: String {
        switch self {
        case .manualPenalty(let cost):
            if cost > 0 {
                return "手数を\(cost)増やして手札スロットを引き直します。現在の手札スロットは空になります。よろしいですか？"
            } else {
                return "手数を増やさずに手札スロットを引き直します。現在の手札スロットは空になります。よろしいですか？"
            }
        case .reset:
            return "現在の進行状況を破棄して、最初からやり直します。よろしいですか？"
        case .returnToTitle:
            return "ゲームを終了してタイトル画面へ戻ります。現在のプレイ内容は保存されません。"
        }
    }

    /// ボタンのロール種別
    var buttonRole: ButtonRole? {
        .destructive
    }
}
