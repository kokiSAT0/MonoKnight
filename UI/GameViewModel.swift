import Combine  // Combine を利用して GameCore の更新を ViewModel 経由で伝搬する
import Foundation
import Game
import SharedSupport
import SwiftUI
import UIKit

// MARK: - ペナルティバナー制御専用ユーティリティ

/// ペナルティバナーの表示時間とキャンセル操作を抽象化するためのプロトコル
/// - Important: テストではスパイ実装を注入し、`scheduleAutoDismiss` / `cancel` が期待通り呼ばれたか検証できるようにする。
protocol PenaltyBannerScheduling: AnyObject {
    /// バナーの自動クローズ処理を一定時間後に実行する
    /// - Parameters:
    ///   - delay: 自動的に閉じるまでの待機秒数
    ///   - handler: 遅延実行したい処理本体
    func scheduleAutoDismiss(after delay: TimeInterval, handler: @escaping () -> Void)

    /// 保持している自動クローズ処理を破棄する
    func cancel()
}

/// ペナルティ発生時に表示するバナーの自動クローズを一元管理するためのヘルパークラス
/// - Note: `DispatchWorkItem` のライフサイクル管理を ViewModel 本体から切り離し、
///   将来的にバナー表示の継続時間やディスパッチキューを差し替える際の影響範囲を最小化する狙いがある。
final class PenaltyBannerScheduler: PenaltyBannerScheduling {
    /// 自動クローズを担当する WorkItem。複数回表示された際にキャンセル漏れが起こらないよう保持する
    private var dismissWorkItem: DispatchWorkItem?
    /// 非同期実行に利用するディスパッチキュー
    private let queue: DispatchQueue

    /// - Parameter queue: デフォルトでメインキューを利用するが、テスト時に差し替えられるように引数化している
    init(queue: DispatchQueue = .main) {
        self.queue = queue
    }

    /// バナーを一定時間後に非表示へ戻すスケジュールを登録する
    /// - Parameters:
    ///   - delay: 非表示へ切り替えるまでの待ち時間（秒）
    ///   - handler: 非表示へ切り替える際に実行するクロージャ
    func scheduleAutoDismiss(after delay: TimeInterval, handler: @escaping () -> Void) {
        cancel()

        // WorkItem が完了したタイミングで自身の参照を解放し、再表示時に新しい WorkItem を安全に登録できるようにする
        let workItem = DispatchWorkItem { [weak self] in
            defer { self?.dismissWorkItem = nil }
            handler()
        }
        dismissWorkItem = workItem
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    /// 登録済みの WorkItem をキャンセルし、リセットする
    func cancel() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
    }
}

/// ポーズメニューへ渡すキャンペーン進捗のサマリー
/// - Note: ステージ定義と保存済み進捗をまとめて保持し、View 側でのアンラップ処理を簡潔にする
struct CampaignPauseSummary {
    /// 対象ステージの定義
    let stage: CampaignStage
    /// 保存済みの進捗（まだプレイしていない場合は nil）
    let progress: CampaignStageProgress?
}

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
    /// キャンペーン進捗ストア
    let campaignProgressStore: CampaignProgressStore
    /// Game Center サインインを再度促す要求を親へ伝えるクロージャ
    let onRequestGameCenterSignIn: ((GameCenterSignInPromptReason) -> Void)?
    /// タイトル復帰時に親へ伝えるためのクロージャ
    let onRequestReturnToTitle: (() -> Void)?
    /// クリア後に別のキャンペーンステージへ遷移したい場合のリクエストクロージャ
    /// - Note: ルート側でゲーム準備フローを再実行するため、`GameView` から直接モードを差し替えずに委譲する
    let onRequestStartCampaignStage: ((CampaignStage) -> Void)?

    /// SwiftUI から観測するゲームロジック本体
    @Published private(set) var core: GameCore
    /// SpriteKit と SwiftUI を仲介するための ViewModel
    let boardBridge: GameBoardBridgeViewModel
    /// 現在選択中の手札スタック ID
    /// - Important: 手札スロットの選択状態を SwiftUI から装飾できるよう公開し、候補マス確定後にリセットする。
    @Published private(set) var selectedHandStackID: UUID?

    /// 結果画面表示フラグ
    @Published var showingResult = false
    /// 直近のキャンペーンステージクリア記録
    /// - Note: リザルト画面でリワード進捗を可視化するため、`registerCampaignResultIfNeeded` で更新する
    @Published private(set) var latestCampaignClearRecord: CampaignStageClearRecord?
    /// 今回のクリアで新たに解放されたステージ一覧
    /// - Important: ユーザーをそのまま次の挑戦へ誘導するため、`ResultView` 側へ渡してボタン表示を制御する
    @Published private(set) var newlyUnlockedStages: [CampaignStage] = []
    /// 手詰まりバナーの表示可否
    @Published var isShowingPenaltyBanner = false
    /// ペナルティバナー表示のスケジューリングを管理するユーティリティ
    /// - Note: `DispatchWorkItem` を直接保持せずに済むため、リセット処理の抜け漏れを防ぎやすくなる
    private let penaltyBannerScheduler: PenaltyBannerScheduling
    /// メニューで確認待ちのアクション
    @Published var pendingMenuAction: GameMenuAction?
    /// ポーズメニューの表示状態
    @Published var isPauseMenuPresented = false {
        didSet {
            handlePauseMenuVisibilityChange(isPresented: isPauseMenuPresented)
        }
    }
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
    /// 現在の移動回数
    /// - Note: 統計バッジ表示で利用し、View 側から GameCore への直接依存を減らす
    var moveCount: Int { core.moveCount }
    /// 累計ペナルティ手数
    /// - Note: ペナルティバナーや統計表示の数値として再利用する
    var penaltyCount: Int { core.penaltyCount }
    /// クリア確定時点の経過秒数
    /// - Note: 結果画面や統計表示で参照するための公開プロパティ
    var elapsedSeconds: Int { core.elapsedSeconds }
    /// 未踏破マスの残数
    /// - Note: 進行状況バッジに表示するために用意する
    var remainingTiles: Int { core.remainingTiles }
    /// ポーズメニューで表示するキャンペーン情報
    /// - Note: モードに紐付くステージ ID からライブラリを引き、保存済み進捗をまとめて返す
    var campaignPauseSummary: CampaignPauseSummary? {
        guard let metadata = mode.campaignMetadataSnapshot else {
            return nil
        }
        let stageID = metadata.stageID
        guard let stage = campaignLibrary.stage(with: stageID) else {
            debugLog("GameViewModel: キャンペーンステージ定義が見つかりません stageID=\(stageID.displayCode)")
            return nil
        }
        let progress = campaignProgressStore.progress(for: stage.id)
        return CampaignPauseSummary(stage: stage, progress: progress)
    }
    /// ポーズメニューで再利用するペナルティ説明文の一覧
    /// - Important: RootView の事前案内と文言・順序を揃え、体験の一貫性を保つ
    var pauseMenuPenaltyItems: [String] {
        [
            mode.deadlockPenaltyCost > 0 ? "手詰まり +\(mode.deadlockPenaltyCost) 手" : "手詰まり ペナルティなし",
            mode.manualRedrawPenaltyCost > 0 ? "引き直し +\(mode.manualRedrawPenaltyCost) 手" : "引き直し ペナルティなし",
            mode.manualDiscardPenaltyCost > 0 ? "捨て札 +\(mode.manualDiscardPenaltyCost) 手" : "捨て札 ペナルティなし",
            mode.revisitPenaltyCost > 0 ? "再訪 +\(mode.revisitPenaltyCost) 手" : "再訪ペナルティなし"
        ]
    }
    /// 現在のゲーム進行状態
    /// - Note: GameView 側でオーバーレイ表示を切り替える際に利用する
    var progress: GameProgress { core.progress }
    /// 直近で加算されたペナルティ量
    /// - Note: バナー表示のテキストへ反映する
    var lastPenaltyAmount: Int { core.lastPenaltyAmount }
    /// 捨て札選択待機中かどうか
    /// - Note: ボタンのスタイル切り替えに必要な状態をカプセル化する
    var isAwaitingManualDiscardSelection: Bool { core.isAwaitingManualDiscardSelection }
    /// 現在の駒位置
    /// - Note: カード移動演出でフォールバック座標として参照する
    var currentPosition: GridPoint? { core.current }
    /// ランキング送信対象かどうか
    var isLeaderboardEligible: Bool { mode.isLeaderboardEligible }
    /// レイアウト診断用のスナップショット
    @Published var lastLoggedLayoutSnapshot: BoardLayoutSnapshot?
    /// 経過秒数を 1 秒刻みで更新するためのタイマーパブリッシャ
    let elapsedTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    /// ハプティクスの有効/無効設定
    private(set) var hapticsEnabled = true
    /// ガイドモードの有効/無効設定
    private(set) var guideModeEnabled = true
    /// Game Center 認証済みかどうかを UI と共有するフラグ
    @Published private(set) var isGameCenterAuthenticated: Bool
    /// 盤面タップ時にカード選択が必要なケースを利用者へ知らせるための警告状態
    /// - Important: `Identifiable` なペイロードを保持し、SwiftUI 側で `.alert(item:)` を使って監視できるようにする
    @Published var boardTapSelectionWarning: BoardTapSelectionWarning?

    /// Combine の購読を保持するセット
    private var cancellables = Set<AnyCancellable>()
    /// キャンペーン定義
    private let campaignLibrary = CampaignLibrary.shared
    /// 手札選択の内部状態
    private var selectedCardSelection: SelectedCardSelection?
    /// 現在時刻を取得するためのクロージャ。テストでは任意の値へ差し替える
    private let currentDateProvider: () -> Date
    /// ポーズメニューによってタイマーを停止しているかどうか
    private var isTimerPausedForMenu = false
    /// scenePhase 変化によってタイマーを停止しているかどうか
    private var isTimerPausedForScenePhase = false
    /// ゲーム準備オーバーレイ表示によってタイマーを停止しているかどうか
    /// - Note: RootView のローディング表示中はポーズメニューや scenePhase とは独立して停止を維持するため、
    ///         理由ごとに個別のフラグを持ち、復帰条件を正しく判定できるようにする。
    private var isTimerPausedForPreparationOverlay = false

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
        // `CampaignProgressStore` は @MainActor 隔離のため、デフォルト引数で直接生成すると
        // ビルドエラーが発生する。そこで `@autoclosure` 付きのファクトリを受け取り、
        // メインアクター上で初期化処理を実行するようにする。
        campaignProgressStore: @MainActor @autoclosure () -> CampaignProgressStore = CampaignProgressStore(),
        onRequestGameCenterSignIn: ((GameCenterSignInPromptReason) -> Void)?,
        onRequestReturnToTitle: (() -> Void)?,
        onRequestStartCampaignStage: ((CampaignStage) -> Void)?,
        penaltyBannerScheduler: PenaltyBannerScheduling = PenaltyBannerScheduler(),
        initialHandOrderingRawValue: String? = nil,
        initialGameCenterAuthenticationState: Bool = false,
        currentDateProvider: @escaping () -> Date = Date.init
    ) {
        self.mode = mode
        self.gameInterfaces = gameInterfaces
        self.gameCenterService = gameCenterService
        self.adsService = adsService
        // 上記のファクトリをここで評価し、@MainActor コンテキストから安全にインスタンス化する
        self.campaignProgressStore = campaignProgressStore()
        self.onRequestGameCenterSignIn = onRequestGameCenterSignIn
        self.onRequestReturnToTitle = onRequestReturnToTitle
        self.onRequestStartCampaignStage = onRequestStartCampaignStage
        self.penaltyBannerScheduler = penaltyBannerScheduler
        self.isGameCenterAuthenticated = initialGameCenterAuthenticationState
        self.currentDateProvider = currentDateProvider

        // GameCore を生成し、ViewModel 経由で観測できるようにする
        let generatedCore = gameInterfaces.makeGameCore(mode)
        self.core = generatedCore
        self.boardBridge = GameBoardBridgeViewModel(core: generatedCore, mode: mode)

        // GameCore の変更を ViewModel 経由で SwiftUI へ伝える
        generatedCore.objectWillChange
            .sink { [weak self] _ in
                guard let self else { return }
                self.objectWillChange.send()
            }
            .store(in: &cancellables)

        // BoardBridge の描画更新も ViewModel 経由で伝播し、GameView 側が単一の監視対象で済むようにする
        boardBridge.objectWillChange
            .sink { [weak self] _ in
                guard let self else { return }
                self.objectWillChange.send()
            }
            .store(in: &cancellables)

        // GameCore が公開する各種状態を監視し、SwiftUI 側の責務を軽量化する
        bindGameCore()

        // ユーザー設定から手札並び順を復元する
        if let rawValue = initialHandOrderingRawValue {
            restoreHandOrderingStrategy(from: rawValue)
        }
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

    /// Game Center 認証状態を更新し、必要に応じてログへ記録する
    /// - Parameter newValue: 最新の認証可否
    func updateGameCenterAuthenticationStatus(_ newValue: Bool) {
        guard isGameCenterAuthenticated != newValue else { return }
        debugLog("GameViewModel: Game Center 認証状態が更新されました -> \(newValue)")
        isGameCenterAuthenticated = newValue
    }

    /// 盤面タップ時に提示する警告ペイロード
    /// - Note: View 層で扱いやすいよう `Identifiable` を満たし、メッセージや対象マスなどの情報をまとめて保持する
    struct BoardTapSelectionWarning: Identifiable, Equatable {
        /// 識別子。複数回同じ警告を表示するケースに備えて毎回新規 ID を採番する
        let id = UUID()
        /// 利用者へ表示する本文
        let message: String
        /// 競合が発生した座標。デバッグ用途で参照できるようにしておく
        let destination: GridPoint
    }

    /// 手札選択を表す内部モデル
    private struct SelectedCardSelection {
        /// 選択中のスタック識別子
        let stackID: UUID
        /// 選択時点のトップカード識別子
        let cardID: UUID
    }

    /// ガイドモードの設定値を更新し、必要に応じてハイライトを再描画する
    /// - Parameter enabled: 新しいガイドモード設定
    func updateGuideMode(enabled: Bool) {
        guideModeEnabled = enabled
        boardBridge.updateGuideMode(enabled: enabled)
    }

    /// ハプティクスの設定を更新する
    /// - Parameter isEnabled: ユーザー設定から得たハプティクス有効フラグ
    func updateHapticsSetting(isEnabled: Bool) {
        hapticsEnabled = isEnabled
        boardBridge.updateHapticsSetting(isEnabled: isEnabled)
    }

    /// 盤面タップ警告を外部からクリアしたい場合のユーティリティ
    /// - Important: トースト表示の自動消滅と同期させるため、View 層から明示的に呼び出せるよう公開する
    func clearBoardTapSelectionWarning() {
        boardTapSelectionWarning = nil
    }

    /// 結果画面を閉じた際の後処理
    func finalizeResultDismissal() {
        showingResult = false
    }

    /// SpriteKit シーンの配色を更新する
    /// - Parameter scheme: 現在のカラースキーム
    func applyScenePalette(for scheme: ColorScheme) {
        boardBridge.applyScenePalette(for: scheme)
    }

    /// ハイライト表示を最新の状態へ更新する
    func refreshGuideHighlights(
        handOverride: [HandStack]? = nil,
        currentOverride: GridPoint? = nil,
        progressOverride: GameProgress? = nil
    ) {
        boardBridge.refreshGuideHighlights(
            handOverride: handOverride,
            currentOverride: currentOverride,
            progressOverride: progressOverride
        )
    }

    /// カード選択 UI から強制的に盤面ハイライトを表示したい場合のエントリポイント
    /// - Parameter points: ユーザーに示したい候補座標集合。空集合を渡すと強制表示を解除する。
    /// - Note: チュートリアルやヒント UI で特定マスを指示したいケースを想定し、View 層から直接 `GameScene` へ触れずに更新できるようにする。
    func updateForcedSelectionHighlight(points: Set<GridPoint>) {
        boardBridge.updateForcedSelectionHighlights(points)
    }

    /// 特定の手札スタックに応じた強制ハイライトを更新するユーティリティ
    /// - Parameter stack: ハイライトしたいスタック。nil や未使用カードの場合は解除を行う。
    /// - Important: カード選択 UI でフォーカスが移動した際に呼び出し、解除時は `nil` を渡す運用を想定している。
    func updateForcedSelectionHighlight(for stack: HandStack?) {
        guard
            let stack,
            let current = core.current,
            let card = stack.topCard
        else {
            boardBridge.updateForcedSelectionHighlights([])
            return
        }

        // MoveCard.movementVectors を現在地へ適用し、盤面内の候補座標をハイライトへ変換する
        boardBridge.updateForcedSelectionHighlights(
            [],
            origin: current,
            movementVectors: card.move.movementVectors
        )
    }

    /// 表示用の経過時間を再計算する
    func updateDisplayedElapsedTime() {
        // GameCore 側では経過秒数をリアルタイム計測しつつ、クリア確定時に `elapsedSeconds` へ確定値を格納する。
        // プレイ中に UI で使用する値は `liveElapsedSeconds` を参照することで、
        // ストップウォッチのように 1 秒刻みで増加し続ける体験を提供できるようにする。
        displayedElapsedSeconds = core.liveElapsedSeconds
    }

    /// 指定スタックのカードが現在位置から使用可能か判定する
    func isCardUsable(_ stack: HandStack) -> Bool {
        boardBridge.isCardUsable(stack)
    }

    /// 手札スタックのトップカードを盤面へ送るアニメーションを準備する
    @discardableResult
    func animateCardPlay(for stack: HandStack, at index: Int) -> Bool {
        boardBridge.animateCardPlay(for: stack, at: index)
    }

    /// 手札スロットがタップされた際の挙動を集約する
    /// - Parameter index: ユーザーが操作したスロットの添字
    func handleHandSlotTap(at index: Int) {
        // 既に別カードの移動アニメーションが進行している場合は受け付けない
        guard boardBridge.animatingCard == nil else { return }
        // 範囲外アクセスを避けるため、安全にインデックスの存在を確認する
        guard core.handStacks.indices.contains(index) else { return }

        let latestStack = core.handStacks[index]

        if core.isAwaitingManualDiscardSelection {
            clearSelectedCardSelection()
            // 捨て札モード中は対象スタックを破棄して新しいカードへ差し替える
            withAnimation(.easeInOut(duration: 0.2)) {
                let success = core.discardHandStack(withID: latestStack.id)
                if success, hapticsEnabled {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                }
            }
            return
        }

        guard let topCard = latestStack.topCard else {
            clearSelectedCardSelection()
            return
        }

        // 同じスタックを再度タップした場合は選択解除として扱い、候補ハイライトを消去する
        if selectedCardSelection?.stackID == latestStack.id {
            clearSelectedCardSelection()
            return
        }

        guard core.progress == .playing else {
            clearSelectedCardSelection()
            return
        }

        guard isCardUsable(latestStack) else {
            clearSelectedCardSelection()
            if hapticsEnabled {
                // 無効カードをタップした場合は警告ハプティクスのみ発生させる
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
            return
        }

        // 候補マス一覧を GameCore.availableMoves() から抽出し、選択状態を更新する
        let resolvedMoves = core.availableMoves().filter { candidate in
            candidate.stackID == latestStack.id && candidate.card.id == topCard.id
        }

        // 候補が存在しない場合は選択状態をクリアして安全に終了する
        guard !resolvedMoves.isEmpty else {
            clearSelectedCardSelection()
            return
        }

        if resolvedMoves.count == 1, let singleMove = resolvedMoves.first {
            // 単一候補カードは盤面タップを挟まずに即座にプレイし、ハイライト更新をスキップする
            clearSelectedCardSelection()
            _ = boardBridge.animateCardPlay(using: singleMove)
            return
        }

        let selection = SelectedCardSelection(stackID: latestStack.id, cardID: topCard.id)
        selectedCardSelection = selection
        selectedHandStackID = latestStack.id
        applyHighlights(for: selection, using: resolvedMoves)
    }

    /// 盤面タップに応じたプレイ要求を処理する
    /// - Important: BoardTapPlayRequest の受付は GameViewModel が単一窓口となる。描画橋渡し層や View 側で同様の処理を複製しないこと
    func handleBoardTapPlayRequest(_ request: BoardTapPlayRequest) {
        defer { core.clearBoardTapPlayRequest(request.id) }

        // 既存の演出が継続中であれば、次の入力が完了するまで待機する
        guard boardBridge.animatingCard == nil else { return }

        // 選択済みカードが存在しない場合は、GameCore 側で確定済みの移動候補をそのまま採用する
        guard let selection = selectedCardSelection else {
            // GameCore.availableMoves() を再評価し、タップ座標へ進める候補が複数カードで競合していないかを確認する
            let availableMoves = core.availableMoves()
            let destinationCandidates = availableMoves.filter { $0.destination == request.destination }
            // 同一座標に到達できる候補へ単一ベクトルカードが混在しているかを判定し、警告要否の判断材料にする
            let containsSingleVectorCard = destinationCandidates.contains { candidate in
                // movementVectors.count が 1 の場合は単一方向専用カードとみなし、自動プレイを許可する
                candidate.card.move.movementVectors.count == 1
            }
            // 同一座標へ移動可能なスタック集合を直接求め、純粋にスタック数だけで競合を判断する
            let conflictingStackIDs = Set(destinationCandidates.map(\.stackID))

            if conflictingStackIDs.count >= 2 && !containsSingleVectorCard {
                // 候補スタックが 2 件以上存在する場合は必ず警告し、意図しない自動プレイを防ぐ
                boardTapSelectionWarning = BoardTapSelectionWarning(
                    message: "複数のカードが同じマスを指定しています。手札から使いたいカードを選んでからマスをタップしてください。",
                    destination: request.destination
                )

                if hapticsEnabled {
                    // 視覚だけでなく触覚でも注意喚起できるように、警告ハプティクスを同じ分岐へまとめて呼び出す
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                }

                // 警告を提示した場合はここで処理を終了し、後続のアニメーション開始を確実に抑止する
                return
            }

            // request.resolvedMove は BoardTap 発生時点での最適候補なので、そのまま演出へ渡す
            let didStart = boardBridge.animateCardPlay(using: request.resolvedMove)
            if didStart {
                // 選択状態が無くてもハイライトが残存している可能性があるため、必ず初期化する
                clearSelectedCardSelection()
            }
            return
        }

        // 選択中カードに対応する候補のみを抽出し、盤面ハイライトと同期を取る
        let matchingMoves = core.availableMoves().filter { candidate in
            candidate.stackID == selection.stackID && candidate.card.id == selection.cardID
        }

        guard !matchingMoves.isEmpty else {
            clearSelectedCardSelection()
            return
        }

        // タップされた座標に一致する候補が無ければ、ハイライトのみ更新して待機する
        guard let chosenMove = matchingMoves.first(where: { $0.destination == request.destination }) else {
            applyHighlights(for: selection, using: matchingMoves)
            return
        }

        // 一致する候補が見つかった場合は演出を開始する。失敗時はハイライトを維持して再選択に備える
        let didStart = boardBridge.animateCardPlay(using: chosenMove)
        if didStart {
            clearSelectedCardSelection()
        } else {
            applyHighlights(for: selection, using: matchingMoves)
        }
    }

    // MARK: - 手動操作ボタンのサポート

    /// 捨て札ボタンを操作可能かどうか判定する
    /// - Returns: 進行中かつ手札が 1 種類以上存在する場合に true
    var isManualDiscardButtonEnabled: Bool {
        core.progress == .playing && !core.handStacks.isEmpty
    }

    /// 捨て札ボタンに設定するアクセシビリティ説明文
    /// - Returns: 選択モード中かどうか、およびペナルティの有無に応じた説明テキスト
    var manualDiscardAccessibilityHint: String {
        let penaltyCost = core.mode.manualDiscardPenaltyCost

        if core.isAwaitingManualDiscardSelection {
            return "捨て札モードを終了します。カードを選ばずに通常操作へ戻ります。"
        }

        if penaltyCost > 0 {
            return "手数を\(penaltyCost)消費して、選択した手札 1 種類をまとめて捨て札にし、新しいカードを補充します。"
        } else {
            return "手数を消費せずに、選択した手札 1 種類をまとめて捨て札にし、新しいカードを補充します。"
        }
    }

    /// 捨て札モードの開始/終了をトグルする
    /// - Note: ボタンが無効な状態では開始せず、選択中であれば常に終了させる
    func toggleManualDiscardSelection() {
        clearSelectedCardSelection()
        if core.isAwaitingManualDiscardSelection {
            core.cancelManualDiscardSelection()
            return
        }

        guard isManualDiscardButtonEnabled else { return }
        core.beginManualDiscardSelection()
    }

    /// 手動ペナルティボタンを操作可能かどうか判定する
    /// - Returns: プレイ中であれば true
    var isManualPenaltyButtonEnabled: Bool {
        core.progress == .playing
    }

    /// 手動ペナルティボタンのアクセシビリティ説明文
    /// - Returns: 手数消費量とスタック仕様を含めた説明テキスト
    var manualPenaltyAccessibilityHint: String {
        let cost = core.mode.manualRedrawPenaltyCost
        let stackingDetail = core.mode.stackingRuleDetailText
        let refillDescription = "手札スロットを全て空にし、新しいカードを最大 \(core.mode.handSize) 種類まで補充します。"

        if cost > 0 {
            return "手数を\(cost)消費して\(refillDescription)\(stackingDetail)"
        } else {
            return "手数を消費せずに\(refillDescription)\(stackingDetail)"
        }
    }

    /// 手動ペナルティの確認ダイアログを表示するようリクエストする
    /// - Note: ゲームが進行中でない場合は無視し、誤操作によるダイアログ表示を防ぐ
    func requestManualPenalty() {
        guard isManualPenaltyButtonEnabled else { return }
        pendingMenuAction = .manualPenalty(penaltyCost: core.mode.manualRedrawPenaltyCost)
    }

    /// ホームボタンの押下をトリガーに、タイトルへ戻る確認ダイアログを表示する
    /// - Note: 直接リセットを実行せず、一度 pendingMenuAction へ格納して既存の確認フローを流用する
    func requestReturnToTitle() {
        pendingMenuAction = .returnToTitle
    }

    /// ポーズメニューを表示する
    /// - Note: ログ出力もここでまとめて行い、UI 側の責務を軽量化する
    func presentPauseMenu() {
        debugLog("GameViewModel: ポーズメニュー表示要求")
        isPauseMenuPresented = true
    }

    /// scenePhase の変化に応じてタイマーの停止/再開を制御する
    /// - Parameter newPhase: 画面のアクティブ状態
    func handleScenePhaseChange(_ newPhase: ScenePhase) {
        guard supportsTimerPausing else { return }

        switch newPhase {
        case .inactive, .background:
            // 既に一時停止済みであれば重複して pauseTimer を呼ばない
            guard !isTimerPausedForScenePhase, core.progress == .playing else { return }
            core.pauseTimer(referenceDate: currentDateProvider())
            isTimerPausedForScenePhase = true

        case .active:
            guard isTimerPausedForScenePhase else { return }
            isTimerPausedForScenePhase = false
            // ポーズメニュー表示中は再開しない
            guard !isPauseMenuPresented else { return }
            // ローディングオーバーレイ表示中も再開しない
            guard !isTimerPausedForPreparationOverlay else { return }
            core.resumeTimer(referenceDate: currentDateProvider())

        @unknown default:
            break
        }
    }

    /// ゲーム準備オーバーレイの表示/非表示を受け取り、タイマー制御を統合する
    /// - Parameter isVisible: 現在のローディング表示状態
    func handlePreparationOverlayChange(isVisible: Bool) {
        guard supportsTimerPausing else { return }

        if isVisible {
            // 既に他要因で停止している場合でも理由を保持し、復帰条件の判定に利用する
            guard !isTimerPausedForPreparationOverlay else { return }
            isTimerPausedForPreparationOverlay = true

            // 実際にプレイ中であればタイマーを停止させ、ローディング表示中の時間加算を防ぐ
            guard !isTimerPausedForMenu, !isTimerPausedForScenePhase, core.progress == .playing else { return }
            core.pauseTimer(referenceDate: currentDateProvider())
        } else {
            guard isTimerPausedForPreparationOverlay else { return }
            isTimerPausedForPreparationOverlay = false

            // 他の理由で停止している場合は再開を保留し、復帰条件が揃ったタイミングまで待つ
            guard !isTimerPausedForMenu, !isTimerPausedForScenePhase, core.progress == .playing else { return }
            core.resumeTimer(referenceDate: currentDateProvider())
        }
    }

    /// ゲームの進行状況に応じた操作をまとめて処理する
    func performMenuAction(_ action: GameMenuAction) {
        pendingMenuAction = nil
        clearSelectedCardSelection()
        switch action {
        case .manualPenalty:
            cancelPenaltyBannerDisplay()
            core.applyManualPenaltyRedraw()

        case .reset:
            resetSessionForNewPlay()

        case .returnToTitle:
            prepareForReturnToTitle()
            onRequestReturnToTitle?()
        }
    }

    /// 盤面サイズや踏破状況などを初期化する
    func prepareForAppear(
        colorScheme: ColorScheme,
        guideModeEnabled: Bool,
        hapticsEnabled: Bool,
        handOrderingStrategy: HandOrderingStrategy,
        isPreparationOverlayVisible: Bool
    ) {
        boardBridge.prepareForAppear(
            colorScheme: colorScheme,
            guideModeEnabled: guideModeEnabled,
            hapticsEnabled: hapticsEnabled
        )
        updateHapticsSetting(isEnabled: hapticsEnabled)
        self.guideModeEnabled = guideModeEnabled
        updateDisplayedElapsedTime()
        core.updateHandOrderingStrategy(handOrderingStrategy)
        // GameView の表示前にローディングオーバーレイの状態を反映し、表示直後のタイマー暴走を防ぐ
        handlePreparationOverlayChange(isVisible: isPreparationOverlayVisible)
    }

    /// ペナルティイベントを受信した際の処理
    func handlePenaltyEvent() {
        // 新しいバナー表示を開始する前に既存スケジュールを破棄し、二重実行を避ける
        penaltyBannerScheduler.cancel()

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8, blendDuration: 0.2)) {
            isShowingPenaltyBanner = true
        }

        if hapticsEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }

        penaltyBannerScheduler.scheduleAutoDismiss(after: 2.6) { [weak self] in
            guard let self else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                self.isShowingPenaltyBanner = false
            }
        }
    }

    /// 盤面レイアウト関連のアンカー情報を更新する
    func updateBoardAnchor(_ anchor: Anchor<CGRect>?) {
        boardBridge.updateBoardAnchor(anchor)
    }

    /// 結果画面からリトライを選択した際の共通処理
    func handleResultRetry() {
        resetSessionForNewPlay()
    }

    /// リザルト画面からホームへ戻るリクエストを受け取った際の共通処理
    /// - Note: リトライ時と同じ初期化を行った上で、ルートビューへ遷移要求を転送する
    func handleResultReturnToTitle() {
        prepareForReturnToTitle()
        onRequestReturnToTitle?()
    }

    /// 手札選択状態を初期化し、盤面ハイライトを消去する
    private func clearSelectedCardSelection() {
        // 選択状態だけでなく、強制ハイライトが残っているケースも初期化対象とする
        let hasSelection = selectedCardSelection != nil || selectedHandStackID != nil
        let hasForcedHighlights = !boardBridge.forcedSelectionHighlightPoints.isEmpty
        guard hasSelection || hasForcedHighlights else { return }

        selectedCardSelection = nil
        selectedHandStackID = nil
        boardBridge.updateForcedSelectionHighlights([])
    }

    /// 現在の選択状態に基づいて候補マスのハイライトを適用する
    /// - Parameters:
    ///   - selection: 選択中のスタック情報
    ///   - resolvedMoves: 事前に算出済みの候補があれば指定する（省略時は再評価する）
    private func applyHighlights(
        for selection: SelectedCardSelection,
        using resolvedMoves: [ResolvedCardMove]? = nil
    ) {
        guard let current = core.current else {
            clearSelectedCardSelection()
            return
        }

        let moves = resolvedMoves ?? core.availableMoves().filter { candidate in
            candidate.stackID == selection.stackID && candidate.card.id == selection.cardID
        }

        guard !moves.isEmpty else {
            clearSelectedCardSelection()
            return
        }

        let destinations = Set(moves.map(\.destination))
        let vectors = moves.map(\.moveVector)
        boardBridge.updateForcedSelectionHighlights(destinations, origin: current, movementVectors: vectors)
    }

    /// 手札更新後も選択状態が維持できるか検証し、必要に応じてリセットする
    /// - Parameter handStacks: 最新の手札スタック一覧
    private func refreshSelectionIfNeeded(with handStacks: [HandStack]) {
        guard let selection = selectedCardSelection else { return }

        guard let stack = handStacks.first(where: { $0.id == selection.stackID }),
              let topCard = stack.topCard,
              topCard.id == selection.cardID else {
            clearSelectedCardSelection()
            return
        }

        applyHighlights(for: selection)
    }

    /// ペナルティバナー表示に関連する状態とワークアイテムをまとめて破棄する
    /// - Note: 手動ペナルティやリセット操作後にバナーが残存しないよう、共通処理として切り出している
    private func cancelPenaltyBannerDisplay() {
        penaltyBannerScheduler.cancel()
        isShowingPenaltyBanner = false
    }

    /// ホーム画面へ戻る際に共通で必要となる状態リセットをひとまとめにする
    /// - Important: タイトルへ戻る場合はプレイ内容を保持したまま、UI 状態のみを初期化したいので `core.reset()` は呼び出さない
    private func prepareForReturnToTitle() {
        clearSelectedCardSelection()
        cancelPenaltyBannerDisplay()
        showingResult = false
        adsService.resetPlayFlag()
        isTimerPausedForMenu = false
        isTimerPausedForScenePhase = false
        isTimerPausedForPreparationOverlay = false
    }

    /// 新しいプレイを始める際に必要な初期化処理を共通化する
    /// - Note: リザルトからのリトライやリセット操作で重複していた処理を一本化し、将来的な初期化追加にも対応しやすくする
    private func resetSessionForNewPlay() {
        prepareForReturnToTitle()
        core.reset()
        isTimerPausedForMenu = false
        isTimerPausedForScenePhase = false
        isTimerPausedForPreparationOverlay = false
    }

    /// GameCore のストリームを監視し、UI 更新に必要な副作用を引き受ける
    private func bindGameCore() {
        core.$penaltyEventID
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] eventID in
                guard let self, eventID != nil else { return }
                self.handlePenaltyEvent()
            }
            .store(in: &cancellables)

        core.$handStacks
            .receive(on: RunLoop.main)
            .sink { [weak self] newHandStacks in
                self?.refreshSelectionIfNeeded(with: newHandStacks)
            }
            .store(in: &cancellables)

        core.$boardTapPlayRequest
            .receive(on: RunLoop.main)
            .sink { [weak self] request in
                guard let self, let request else { return }
                self.handleBoardTapPlayRequest(request)
            }
            .store(in: &cancellables)

        core.$progress
            .receive(on: RunLoop.main)
            .sink { [weak self] progress in
                guard let self else { return }
                self.handleProgressChange(progress)
            }
            .store(in: &cancellables)

        core.$elapsedSeconds
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateDisplayedElapsedTime()
            }
            .store(in: &cancellables)
    }

    /// 進行状態の変化に応じた副作用をまとめる
    /// - Parameter progress: GameCore が提供する現在の進行状態
    private func handleProgressChange(_ progress: GameProgress) {
        debugLog("進行状態の更新を受信: 状態=\(String(describing: progress))")

        updateDisplayedElapsedTime()
        boardBridge.handleProgressChange(progress)

        if progress != .playing {
            clearSelectedCardSelection()
        }

        switch progress {
        case .cleared:
            if mode.isLeaderboardEligible {
                if isGameCenterAuthenticated {
                    gameCenterService.submitScore(core.score, for: mode.identifier)
                } else {
                    debugLog("GameViewModel: Game Center 未認証のためスコア送信をスキップしました")
                    onRequestGameCenterSignIn?(.scoreSubmissionSkipped)
                }
            }
            registerCampaignResultIfNeeded()
            showingResult = true
        default:
            break
        }
    }

    /// キャンペーンステージの進捗を更新する
    private func registerCampaignResultIfNeeded() {
        guard let metadata = mode.campaignMetadataSnapshot,
              let stage = campaignLibrary.stage(with: metadata.stageID) else {
            // キャンペーン以外のモードではリザルト用データを初期化しておき、前回の値が残らないようにする
            latestCampaignClearRecord = nil
            newlyUnlockedStages = []
            return
        }

        // クリア登録前の解放状況を控えておき、解放済みフラグの差分から新規解放ステージを特定する
        let unlockedStageIDsBefore = Set(
            campaignLibrary.allStages
                .filter { campaignProgressStore.isStageUnlocked($0) }
                .map(\.id)
        )

        let metrics = CampaignStageClearMetrics(
            moveCount: core.moveCount,
            penaltyCount: core.penaltyCount,
            elapsedSeconds: core.elapsedSeconds,
            totalMoveCount: core.totalMoveCount,
            score: core.score,
            hasRevisitedTile: core.hasRevisitedTile
        )

        let record = campaignProgressStore.registerClear(for: stage, metrics: metrics)

        // リザルト画面で利用するため、更新後の記録を公開プロパティへ格納する
        latestCampaignClearRecord = record

        // 更新後の解放状況を再評価し、今回のクリアで新たに解放されたステージのみ抽出する
        let unlockedStagesAfter = campaignLibrary.allStages.filter { campaignProgressStore.isStageUnlocked($0) }
        let unlockedDiff = unlockedStagesAfter.filter { !unlockedStageIDsBefore.contains($0.id) }

        if unlockedDiff.isEmpty {
            // 差分が空の場合は「既に解放済みだが未クリアのステージ」を再提示し、ResultView のボタンが消えないようにする
            newlyUnlockedStages = campaignLibrary.allStages.filter { stage in
                // earnedStars が 0 のままなら未クリア扱いなので、ユーザーに次の行き先として案内する
                campaignProgressStore.isStageUnlocked(stage) &&
                    (campaignProgressStore.progress(for: stage.id)?.earnedStars ?? 0) == 0
            }
        } else {
            // 通常ケースでは今回のクリアで解放されたステージのみを提示する
            newlyUnlockedStages = unlockedDiff
        }
    }

    /// 新しく解放されたキャンペーンステージへ遷移するリクエストを処理する
    /// - Parameter stage: 遷移先のステージ
    func handleCampaignStageAdvance(to stage: CampaignStage) {
        // バナー表示などの残留状態を片付けつつリザルトを閉じ、新規ステージへ進む準備を整える
        cancelPenaltyBannerDisplay()
        showingResult = false
        adsService.resetPlayFlag()

        // ルートビュー側へ遷移要求を転送し、ゲーム準備フローを再利用する
        if campaignProgressStore.isStageUnlocked(stage) {
            onRequestStartCampaignStage?(stage)
        }
    }
}

#if DEBUG || canImport(XCTest)
extension GameViewModel {
    /// テスト専用ラッパー: プライベートな進行状態ハンドラを直接呼び出し、リザルト挙動を検証する
    func handleProgressChangeForTesting(_ progress: GameProgress) {
        handleProgressChange(progress)
    }

    /// テスト専用にポーズメニュー表示状態を直接切り替えるユーティリティ
    /// - Parameter isPresented: 新しい表示状態
    func setPauseMenuPresentedForTesting(_ isPresented: Bool) {
        isPauseMenuPresented = isPresented
    }
}
#endif

private extension GameViewModel {
    /// キャンペーンモードでタイマー制御を行うべきかどうか
    var supportsTimerPausing: Bool {
        !mode.isLeaderboardEligible && mode.campaignMetadataSnapshot != nil
    }

    /// ポーズメニューの開閉に応じてタイマーの停止/再開を制御する
    /// - Parameter isPresented: 現在のポーズメニュー表示状態
    func handlePauseMenuVisibilityChange(isPresented: Bool) {
        guard supportsTimerPausing else { return }

        if isPresented {
            guard core.progress == .playing else { return }
            // 既にメニュー由来で停止済みなら何もしない
            guard !isTimerPausedForMenu else { return }
            core.pauseTimer(referenceDate: currentDateProvider())
            isTimerPausedForMenu = true
        } else {
            guard isTimerPausedForMenu else { return }
            isTimerPausedForMenu = false
            // scenePhase 由来で停止している場合は復帰しない
            guard !isTimerPausedForScenePhase else { return }
            // ローディングオーバーレイ表示中は復帰を保留する
            guard !isTimerPausedForPreparationOverlay else { return }
            core.resumeTimer(referenceDate: currentDateProvider())
        }
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
