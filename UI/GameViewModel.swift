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
    /// SpriteKit と SwiftUI を仲介するための ViewModel
    let boardBridge: GameBoardBridgeViewModel

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
    /// レイアウト診断用のスナップショット
    @Published var lastLoggedLayoutSnapshot: BoardLayoutSnapshot?
    /// 経過秒数を 1 秒刻みで更新するためのタイマーパブリッシャ
    let elapsedTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    /// ハプティクスの有効/無効設定
    private(set) var hapticsEnabled = true
    /// ガイドモードの有効/無効設定
    private(set) var guideModeEnabled = true

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
        self.boardBridge = GameBoardBridgeViewModel(core: generatedCore, mode: mode)

        // GameCore の変更を ViewModel 経由で SwiftUI へ伝える
        generatedCore.objectWillChange
            .sink { [weak self] _ in
                guard let self else { return }
                self.objectWillChange.send()
            }
            .store(in: &cancellables)

        // GameCore が公開する各種状態を監視し、SwiftUI 側の責務を軽量化する
        bindGameCore()
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

    /// 盤面タップに応じたプレイ要求を処理する
    func handleBoardTapPlayRequest(_ request: BoardTapPlayRequest) {
        boardBridge.handleBoardTapPlayRequest(request)
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
            // 捨て札モード中は対象スタックを破棄して新しいカードへ差し替える
            withAnimation(.easeInOut(duration: 0.2)) {
                let success = core.discardHandStack(withID: latestStack.id)
                if success, hapticsEnabled {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                }
            }
            return
        }

        // 使用可能なカードであれば盤面アニメーションとプレイ処理を実行
        if isCardUsable(latestStack) {
            _ = animateCardPlay(for: latestStack, at: index)
        } else if hapticsEnabled {
            // 無効カードをタップした場合は警告ハプティクスのみ発生させる
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
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

    /// ポーズメニューを表示する
    /// - Note: ログ出力もここでまとめて行い、UI 側の責務を軽量化する
    func presentPauseMenu() {
        debugLog("GameViewModel: ポーズメニュー表示要求")
        isPauseMenuPresented = true
    }

    /// ゲームの進行状況に応じた操作をまとめて処理する
    func performMenuAction(_ action: GameMenuAction) {
        pendingMenuAction = nil
        switch action {
        case .manualPenalty:
            cancelPenaltyBannerDisplay()
            core.applyManualPenaltyRedraw()

        case .reset:
            resetSessionForNewPlay()

        case .returnToTitle:
            resetSessionForNewPlay()
            onRequestReturnToTitle?()
        }
    }

    /// 盤面サイズや踏破状況などを初期化する
    func prepareForAppear(
        colorScheme: ColorScheme,
        guideModeEnabled: Bool,
        hapticsEnabled: Bool,
        handOrderingStrategy: HandOrderingStrategy
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
    }

    /// ペナルティイベントを受信した際の処理
    func handlePenaltyEvent() {
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
        boardBridge.updateBoardAnchor(anchor)
    }

    /// 結果画面からリトライを選択した際の共通処理
    func handleResultRetry() {
        resetSessionForNewPlay()
    }

    /// ペナルティバナー表示に関連する状態とワークアイテムをまとめて破棄する
    /// - Note: 手動ペナルティやリセット操作後にバナーが残存しないよう、共通処理として切り出している
    private func cancelPenaltyBannerDisplay() {
        penaltyDismissWorkItem?.cancel()
        penaltyDismissWorkItem = nil
        isShowingPenaltyBanner = false
    }

    /// 新しいプレイを始める際に必要な初期化処理を共通化する
    /// - Note: リザルトからのリトライやリセット操作で重複していた処理を一本化し、将来的な初期化追加にも対応しやすくする
    private func resetSessionForNewPlay() {
        cancelPenaltyBannerDisplay()
        showingResult = false
        core.reset()
        adsService.resetPlayFlag()
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

        switch progress {
        case .cleared:
            gameCenterService.submitScore(core.score, for: mode.identifier)
            showingResult = true
        default:
            break
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
