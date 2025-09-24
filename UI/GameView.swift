import Combine  // 経過時間更新で Combine のタイマーパブリッシャを活用するため読み込む
import Game  // GameCore や DealtCard、手札並び設定を利用するためゲームロジックモジュールを読み込む
import SharedSupport // debugLog / debugError など共通ロギングユーティリティを利用するため読み込む
import SpriteKit
import SwiftUI
import UIKit  // ハプティクス用のフレームワークを追加

/// SwiftUI から SpriteKit の盤面を表示するビュー
/// 画面下部に手札スロット（最大種類数を保持できるスタック枠）と次に引かれるカードを表示し、
/// タップで GameCore を更新する
/// SwiftUI ビューは UI 操作のため常にメインアクター上で処理する必要があるため、
/// `@MainActor` を付与してサービスのシングルトンへ安全にアクセスできるようにする
@MainActor
struct GameView: View {
    /// カラーテーマを生成し、ビュー全体で共通の配色を利用できるようにする
    private var theme = AppTheme()
    /// 現在プレイしているゲームモード
    private let mode: GameMode
    /// 現在のライト/ダーク設定を環境から取得し、SpriteKit 側の色にも反映する
    @Environment(\.colorScheme) private var colorScheme
    /// デバイスの横幅サイズクラスを取得し、iPad などレギュラー幅でのモーダル挙動を調整する
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// RootView 側で挿入したトップバーの高さ。safeAreaInsets.top から減算して余分な余白を除去する
    /// - Note: Swift 6 では独自 EnvironmentKey の値型が明示されていないと推論に失敗するため、CGFloat 型で注釈を付けている
    @Environment(\.topOverlayHeight) private var topOverlayHeight: CGFloat
    /// ルートビューの GeometryReader で得たシステム由来セーフエリアの上端量
    /// - Note: safeAreaInset により増加した分を差し引くための基準値として利用する
    @Environment(\.baseTopSafeAreaInset) private var baseTopSafeAreaInset: CGFloat
    /// 手札スロットの数（常に 5 スロット分の枠を確保してレイアウトを安定させる）
    private let handSlotCount = 5
    /// ゲームロジックを保持する ObservableObject
    /// - NOTE: `StateObject` は init 内で明示的に生成し、GameScene に渡す
    @StateObject private var core: GameCore
    /// 結果画面を表示するかどうかのフラグ
    /// - NOTE: クリア時に true となり ResultView をシート表示する
    @State private var showingResult = false
    /// 手詰まりペナルティのバナー表示を制御するフラグ
    @State private var isShowingPenaltyBanner = false
    /// バナーを自動的に閉じるためのディスパッチワークアイテムを保持
    @State private var penaltyDismissWorkItem: DispatchWorkItem?
    /// SpriteKit のシーン。`@State` で保持し、SwiftUI による再描画でも同一インスタンスを再利用する
    @State private var scene: GameScene
    /// Game Center 連携を扱うサービス（プロトコル型で受け取る）
    private let gameCenterService: GameCenterServiceProtocol
    /// 広告表示を扱うサービス（プロトコル型で受け取る）
    private let adsService: AdsServiceProtocol
    /// ハプティクスを有効にするかどうかの設定値
    @AppStorage("haptics_enabled") private var hapticsEnabled: Bool = true
    /// ガイドモードのオン/オフを永続化し、盤面ハイライト表示を制御する
    @AppStorage("guide_mode_enabled") private var guideModeEnabled: Bool = true
    /// 手札の並び替え方式。設定変更時に GameCore へ伝搬する
    @AppStorage(HandOrderingStrategy.storageKey) private var handOrderingRawValue: String = HandOrderingStrategy.insertionOrder.rawValue
    /// タイトル画面へ戻るアクションを親から注入する（未指定なら nil で何もしない）
    private let onRequestReturnToTitle: (() -> Void)?
    /// メニューからの操作確認ダイアログで使用する一時的なアクション保持
    /// - NOTE: iPad（レギュラー幅）ではシート、iPhone（コンパクト幅）では確認ダイアログと表示方法が異なるため、
    ///         どちらのモーダルでも共通して参照できるよう単一の状態として管理する
    @State private var pendingMenuAction: GameMenuAction?
    /// ポーズメニューを表示するかどうかのフラグ
    /// - NOTE: BGM やハプティクスなどプレイ中に確認したい設定をまとめる
    @State private var isPauseMenuPresented: Bool = false
    /// 統計バッジ領域の高さを計測し、盤面の縦寸法計算へ反映する
    @State private var statisticsHeight: CGFloat = 0
    /// 手札セクション全体の高さを計測し、利用可能な縦寸法を把握する
    @State private var handSectionHeight: CGFloat = 0
    /// 表示中の経過秒数を保持し、バッジの更新トリガーとして利用する
    @State private var displayedElapsedSeconds: Int = 0
    /// 表示用のスコアを算出するときに利用する計算プロパティ
    /// - Note: 手数×10に経過秒数を加えた現在の暫定スコアを求める
    private var displayedScore: Int {
        core.totalMoveCount * 10 + displayedElapsedSeconds
    }
    /// 手札や NEXT の位置をマッチングさせるための名前空間
    @Namespace private var cardAnimationNamespace
    /// 現在アニメーション中のカード（存在しない場合は nil）
    @State private var animatingCard: DealtCard?
    /// アニメーション対象となっている手札スタック ID（カードだけでなくどの山を消費中かも追跡する）
    @State private var animatingStackID: UUID?
    /// アニメーション中に手札/NEXT から一時的に非表示にするカード ID 集合
    @State private var hiddenCardIDs: Set<UUID> = []
    /// 各手札スタックが直近で表示しているトップカード ID を記録し、スタック構成が変化した際の差分検知に活用する
    @State private var topCardIDsByStack: [UUID: UUID] = [:]
    /// カードが盤面へ向かって移動中かどうかの状態管理
    @State private var animationState: CardAnimationPhase = .idle
    /// 盤面 SpriteView のアンカーを保持し、移動先座標の算出に利用する
    @State private var boardAnchor: Anchor<CGRect>?
    /// カード移動アニメーションの目標とする駒位置（nil の場合は最新の現在地を使用）
    @State private var animationTargetGridPoint: GridPoint?
    /// デッドロック中に一時退避しておくガイド表示用の手札スタック情報
    @State private var pendingGuideHand: [HandStack]?
    /// 一時退避中の現在位置（nil なら GameCore の最新値を利用する）
    @State private var pendingGuideCurrent: GridPoint?
    /// 盤面レイアウトに異常が発生した際のスナップショットを記録し、重複ログを避ける
    @State private var lastLoggedLayoutSnapshot: BoardLayoutSnapshot?
    /// 経過時間の表示を 1 秒ごとに更新するためのタイマーパブリッシャ
    private let elapsedTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// デフォルトのサービスを利用して `GameView` を生成するコンビニエンスイニシャライザ
    /// - Parameter onRequestReturnToTitle: タイトル画面への遷移要求クロージャ（省略可）
    init(
        mode: GameMode = .standard,
        onRequestReturnToTitle: (() -> Void)? = nil
    ) {
        // Swift 6 のコンカレンシールールではデフォルト引数で `@MainActor` なシングルトンへ
        // 直接アクセスできないため、明示的に同一型の別イニシャライザへ委譲する。
        // ここで `GameCenterService.shared` / `AdsService.shared` を取得することで、
        // メインアクター上から安全に依存を解決できるようにする。
        self.init(
            mode: mode,
            gameCenterService: GameCenterService.shared,
            adsService: AdsService.shared,
            onRequestReturnToTitle: onRequestReturnToTitle
        )
    }

    /// 初期化で GameCore と GameScene を連結する
    /// 依存するサービスを外部から注入できるようにする初期化処理
    /// - Parameters:
    ///   - gameCenterService: Game Center 連携用サービス
    ///   - adsService: 広告表示用サービス
    init(
        mode: GameMode,
        gameCenterService: GameCenterServiceProtocol,
        adsService: AdsServiceProtocol,
        onRequestReturnToTitle: (() -> Void)? = nil
    ) {
        self.mode = mode

        // GameCore の生成。StateObject へ包んで保持する
        let core = GameCore(mode: mode)
        // UserDefaults に保存済みの手札並び設定を復元し、初期表示から反映する
        if let savedValue = UserDefaults.standard.string(forKey: HandOrderingStrategy.storageKey),
           let strategy = HandOrderingStrategy(rawValue: savedValue) {
            core.updateHandOrderingStrategy(strategy)
        }
        _core = StateObject(wrappedValue: core)

        // GameScene は再利用したいのでローカルで準備し、最後に State プロパティへ格納する
        // 盤面サイズと初期踏破マスはモード定義から引き継ぎ、異なる盤面でも中心位置が正しく選ばれるようにする
        let preparedScene = GameScene(
            initialBoardSize: mode.boardSize,
            initialVisitedPoints: mode.initialVisitedPoints
        )
        preparedScene.scaleMode = .resizeFill
        // GameScene から GameCore へタップイベントを伝えるため参照を渡す
        // StateObject へ格納した同一インスタンスを直接渡し、wrappedValue へ触れず安全に保持する
        preparedScene.gameCore = core
        _scene = State(initialValue: preparedScene)
        // サービスを保持
        self.gameCenterService = gameCenterService
        self.adsService = adsService
        self.onRequestReturnToTitle = onRequestReturnToTitle
    }

    var body: some View {
        applyGameViewObservers(to:
            GeometryReader { geometry in
                // 専用メソッドへ委譲し、レイアウト計算と描画処理の責務を明示的に分離する
                mainContent(for: geometry)
            }
        )
        // ポーズメニューをフルスクリーンで重ね、端末サイズに左右されずに全項目を視認できるようにする
        .fullScreenCover(isPresented: $isPauseMenuPresented) {
            PauseMenuView(
                onResume: {
                    // フルスクリーンカバーを閉じてプレイへ戻る
                    isPauseMenuPresented = false
                },
                onConfirmReset: {
                    // リセット確定後はフルスクリーンカバーを閉じてから共通処理を呼び出す
                    isPauseMenuPresented = false
                    performMenuAction(.reset)
                },
                onConfirmReturnToTitle: {
                    // タイトル復帰時もポーズメニューを閉じてから処理を実行する
                    isPauseMenuPresented = false
                    performMenuAction(.returnToTitle)
                }
            )
        }
        // シートで結果画面を表示
        .sheet(isPresented: $showingResult) {
            ResultView(
                moveCount: core.moveCount,
                penaltyCount: core.penaltyCount,
                elapsedSeconds: core.elapsedSeconds,
                modeIdentifier: mode.identifier,
                onRetry: {
                    // リトライ時はゲームを初期状態に戻して再開する
                    core.reset()
                    // 新しいプレイで広告を再度表示できるようにフラグをリセット
                    adsService.resetPlayFlag()
                    // 結果画面のシートを閉じてゲーム画面へ戻る
                    showingResult = false
                },
                gameCenterService: gameCenterService,
                adsService: adsService
            )
            // MARK: - iPad 向けのモーダル最適化
            // レギュラー幅（iPad など）では初期状態から `.large` を採用し、全要素が確実に表示されるようにする。
            // Compact 幅（iPhone）では従来通り medium/large を切り替えられるよう配慮し、片手操作でも扱いやすく保つ。
            .presentationDetents(
                horizontalSizeClass == .regular ? [.large] : [.medium, .large]
            )
            .presentationDragIndicator(.visible)
        }
        // MARK: - レギュラー幅では確認をシートで提示
        // iPad では confirmationDialog だと文字が途切れやすいため、十分な横幅を確保できるシートで詳細文を表示する
        .sheet(item: regularWidthPendingActionBinding) { action in
            GameMenuActionConfirmationSheet(
                action: action,
                onConfirm: { confirmedAction in
                    // performMenuAction 内でも pendingMenuAction を破棄しているが、
                    // 明示的に nil を代入しておくことでバインディング由来のシート閉鎖と状態初期化を二重に保証する
                    performMenuAction(confirmedAction)
                    pendingMenuAction = nil
                },
                onCancel: {
                    // キャンセル時はダイアログと同じ挙動になるように pendingMenuAction を破棄する
                    pendingMenuAction = nil
                }
            )
            // iPad では高さに余裕があるため medium/large の選択肢を用意し、読みやすさを優先する
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        // メニュー選択後に確認ダイアログを表示し、誤操作を防ぐ
        .confirmationDialog(
            "操作の確認",
            isPresented: Binding(
                get: {
                    // レギュラー幅ではシート側で確認を行うため、コンパクト幅のときだけダイアログを表示する
                    horizontalSizeClass != .regular && pendingMenuAction != nil
                },
                set: { isPresented in
                    // キャンセル操作で閉じられた場合もステートを初期化する
                    if !isPresented {
                        pendingMenuAction = nil
                    }
                }
            ),
            presenting: pendingMenuAction
        ) { action in
            Button(action.confirmationButtonTitle, role: action.buttonRole) {
                // ユーザーの確認後に実際の処理を実行
                performMenuAction(action)
            }
        } message: { action in
            Text(action.confirmationMessage)
        }
    }

    /// GeometryReader 内部のレイアウト調整と描画処理をまとめたメインコンテンツ
    /// - Parameter geometry: 外側から渡される GeometryProxy（親ビューのサイズや安全領域を把握するために利用）
    /// - Returns: レイアウト計算結果を反映したゲームプレイ画面全体のビュー階層
    @ViewBuilder
    private func mainContent(for geometry: GeometryProxy) -> some View {
        // MARK: - レイアウト関連の計算結果を専用コンテキストへ集約
        // 単一メソッドで値を求めておくことで ViewBuilder の複雑さを抑え、コンパイラの型推論負荷を軽減する。
        let layoutContext = makeLayoutContext(from: geometry)
        // 監視用の不可視オーバーレイも先に生成し、View ビルダー内でのネストを浅く保つ
        let diagnosticsOverlay = layoutDiagnosticOverlay(using: layoutContext)

        ZStack(alignment: .top) {
            VStack(spacing: 16) {
                boardSection(width: layoutContext.boardWidth)
                handSection(
                    bottomInset: layoutContext.bottomInset,
                    bottomPadding: layoutContext.handSectionBottomPadding
                )
            }
            // 統計バッジ＋操作ボタンを上部へ寄せ、ノッチやステータスバーと干渉しないように余白を加算
            .padding(.top, layoutContext.controlRowTopPadding)
            // MARK: - 手詰まりペナルティ通知バナー
            penaltyBannerOverlay(contentTopInset: layoutContext.overlayAdjustedTopInset)
        }
        // 画面全体の背景もテーマで制御し、システム設定と調和させる
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.backgroundPrimary)
        // 盤面が表示されない不具合を切り分けるため、レイアウト関連の値をウォッチする不可視ビューを重ねる
        .background(diagnosticsOverlay)
    }

    /// PreferenceKey や Combine パブリッシャによる状態監視モディファイアをひとまとめに適用する
    /// - Parameter content: 監視対象となるベースビュー
    /// - Returns: 各種監視モディファイアを適用済みのビュー
    private func applyGameViewObservers<Content: View>(to content: Content) -> some View {
        content
        // PreferenceKey で伝搬した各セクションの高さを受け取り、レイアウト計算に利用する
            .onPreferenceChange(StatisticsHeightPreferenceKey.self) { newHeight in
                // 統計バッジ領域の計測値が変わったタイミングで旧値と比較し、変化量をログへ残して原因調査を容易にする
                let previousHeight = statisticsHeight
                guard previousHeight != newHeight else { return }
                debugLog("GameView.statisticsHeight 更新: 旧値=\(previousHeight), 新値=\(newHeight)")
                statisticsHeight = newHeight
            }
            .onPreferenceChange(HandSectionHeightPreferenceKey.self) { newHeight in
                // 手札セクションの高さ変化も逐次観測し、ホームインジケータ付近での余白不足を切り分けられるようにする
                let previousHeight = handSectionHeight
                guard previousHeight != newHeight else { return }
                debugLog("GameView.handSectionHeight 更新: 旧値=\(previousHeight), 新値=\(newHeight)")
                handSectionHeight = newHeight
            }
            // 盤面 SpriteView のアンカー更新を監視し、アニメーションの移動先として保持
            .onPreferenceChange(BoardAnchorPreferenceKey.self) { anchor in
                boardAnchor = anchor
            }
            // 初回表示時に SpriteKit の背景色もテーマに合わせて更新
            .onAppear {
                // ビュー再表示時に GameScene へ GameCore の参照を再連結し、弱参照が nil にならないよう保証
                scene.gameCore = core
                applyScenePalette(for: colorScheme)
                // 初期状態でもガイド表示のオン/オフに応じてハイライトを更新
                refreshGuideHighlights()
                // タイマー起動直後に経過時間を一度読み取って初期表示のずれを防ぐ
                updateDisplayedElapsedTime()
                // 表示開始時点で最新の手札並び設定を反映する
                core.updateHandOrderingStrategy(resolveHandOrderingStrategy())
            }
            // ライト/ダーク切り替えが発生した場合も SpriteKit 側へ反映
            .onChange(of: colorScheme) { _, newScheme in
                applyScenePalette(for: newScheme)
                // カラースキーム変更時はガイドの色味も再描画して視認性を確保
                refreshGuideHighlights()
            }
            // 手札の並び設定が変わったら即座にゲームロジックへ伝え、UI の並びも更新する
            .onChange(of: handOrderingRawValue) { _, _ in
                core.updateHandOrderingStrategy(resolveHandOrderingStrategy())
            }
            // progress が .cleared へ変化したタイミングで結果画面を表示
            .onChange(of: core.progress) { _, newValue in
                guard newValue == .cleared else { return }
                // ゲームモードごとのテスト用リーダーボードへスコアを送信できるように識別子を渡す
                gameCenterService.submitScore(core.score, for: mode.identifier)
                showingResult = true
            }

            // 手詰まりペナルティ発生時のバナー表示を制御
            .onReceive(core.$penaltyEventID) { eventID in
                guard eventID != nil else { return }

                // 既存の自動クローズ処理があればキャンセルして状態をリセット
                penaltyDismissWorkItem?.cancel()
                penaltyDismissWorkItem = nil

                // バナーをアニメーション付きで表示
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8, blendDuration: 0.2)) {
                    isShowingPenaltyBanner = true
                }

                // ペナルティ発生を触覚で知らせる（設定で有効な場合のみ）
                if hapticsEnabled {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                }

                // 一定時間後に自動でバナーを閉じる処理を登録
                let workItem = DispatchWorkItem {
                    withAnimation(.easeOut(duration: 0.25)) {
                        isShowingPenaltyBanner = false
                    }
                    penaltyDismissWorkItem = nil
                }
                penaltyDismissWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: workItem)
            }
            // 手札内容が変わるたびに移動候補を再計算し、ガイドハイライトを更新
            .onReceive(core.$handStacks) { newHandStacks in
                // 手札ストリームの更新順序を追跡しやすいよう、受信したカードスロット数をログへ残す
                debugLog("手札更新を受信: スタック数=\(newHandStacks.count), 退避ハンドあり=\(pendingGuideHand != nil)")

                // --- トップカード ID の差分を検知して hiddenCardIDs を整合させる ---
                var nextTopCardIDs: [UUID: UUID] = [:]
                for stack in newHandStacks {
                    guard let topCard = stack.topCard else { continue }
                    let previousTopID = topCardIDsByStack[stack.id]
                    if let previousTopID, previousTopID != topCard.id {
                        // アニメーション終了前に別 ID へ差し替わった場合でも即座に非表示リストから除外し、ちらつきを防ぐ
                        hiddenCardIDs.remove(previousTopID)
                        debugLog("スタック先頭カードを更新: stackID=\(stack.id), 旧トップID=\(previousTopID), 新トップID=\(topCard.id), 残枚数=\(stack.count)")
                    }
                    nextTopCardIDs[stack.id] = topCard.id
                }

                // 消滅したスタックに紐付いていたトップカード ID も忘れずに除去し、ゴースト化を避ける
                let removedStackIDs = Set(topCardIDsByStack.keys).subtracting(nextTopCardIDs.keys)
                for stackID in removedStackIDs {
                    if let previousTopID = topCardIDsByStack[stackID] {
                        hiddenCardIDs.remove(previousTopID)
                        debugLog("スタック消滅に伴いトップカード ID を解放: stackID=\(stackID), cardID=\(previousTopID)")
                    }
                }
                topCardIDsByStack = nextTopCardIDs

                // 手札が差し替わった際は非表示リストを実際に存在するカード ID へ限定する（NEXT 表示も含める）
                let topCardIDSet = Set(nextTopCardIDs.values)
                let nextPreviewIDs = Set(core.nextCards.map { $0.id })
                let validIDs = topCardIDSet.union(nextPreviewIDs)
                hiddenCardIDs.formIntersection(validIDs)

                if let animatingCard, !validIDs.contains(animatingCard.id) {
                    // 手札の再配布などで該当カードが消えた場合はアニメーション状態を初期化
                    self.animatingCard = nil
                    animatingStackID = nil
                    animationState = .idle
                    animationTargetGridPoint = nil
                }
                // `core.handStacks` へ反映される前でも最新の手札を使ってハイライトを更新する
                refreshGuideHighlights(handOverride: newHandStacks)
            }
            // 盤面タップで移動を指示された際にもカード演出を統一して実行
            .onReceive(core.$boardTapPlayRequest) { request in
                guard let request else { return }
                handleBoardTapPlayRequest(request)
            }
            // ガイドモードのオン/オフを切り替えたら即座に SpriteKit へ反映
            .onChange(of: guideModeEnabled) { _, _ in
                refreshGuideHighlights()
            }
            // 経過時間を 1 秒ごとに再計算し、リアルタイム表示へ反映
            .onReceive(elapsedTimer) { _ in
                updateDisplayedElapsedTime()
            }
            // 進行状態が変化した際もハイライトを整理（手詰まり・クリア時は消灯）
            .onReceive(core.$progress) { progress in
                // 進行状態が切り替わったタイミングで、デッドロック退避フラグの有無と併せて記録する
                debugLog("進行状態の更新を受信: 状態=\(String(describing: progress)), 退避ハンドあり=\(pendingGuideHand != nil)")

                // 進行状態の変化に合わせて経過時間を再計算し、リセット直後のズレを防ぐ
                updateDisplayedElapsedTime()

                if progress == .playing {
                    if let bufferedHand = pendingGuideHand {
                        // デッドロック解除直後は退避しておいた手札情報を使ってガイドを復元する
                        // refreshGuideHighlights 内で .playing 復帰を確認したタイミングのみバッファが空になる
                        // 仕組みに変更されたため、ここでは復元処理の呼び出しに専念させる
                        refreshGuideHighlights(
                            handOverride: bufferedHand,
                            currentOverride: pendingGuideCurrent,
                            progressOverride: progress
                        )
                    } else {
                        // バッファが無ければ通常通り最新状態から計算する
                        refreshGuideHighlights(progressOverride: progress)
                    }
                } else {
                    scene.updateGuideHighlights([])
                }
            }
            // クリア確定時に GameCore 側で確定した秒数が流れてきたら表示へ反映
            .onReceive(core.$elapsedSeconds) { _ in
                updateDisplayedElapsedTime()
            }
            // カードが盤面へ移動中は UI 全体を操作不可とし、状態の齟齬を防ぐ
            .disabled(animatingCard != nil)
            // Preference から取得したアンカー情報を用いて、カードが盤面中央へ吸い込まれる演出を重ねる
            .overlayPreferenceValue(CardPositionPreferenceKey.self) { anchors in
                GeometryReader { proxy in
                    ZStack {
                        Color.clear
                        if let animatingCard,
                           let sourceAnchor = anchors[animatingCard.id],
                           let boardAnchor,
                           animationState != .idle || hiddenCardIDs.contains(animatingCard.id),
                           let targetGridPoint = animationTargetGridPoint ?? core.current {
                            // --- 元の位置と駒位置の座標を算出 ---
                            let cardFrame = proxy[sourceAnchor]
                            let boardFrame = proxy[boardAnchor]
                            let startCenter = CGPoint(x: cardFrame.midX, y: cardFrame.midY)
                            // 盤面座標 → SwiftUI 座標系への変換を行い、目的位置を計算
                            let boardDestination = boardCoordinate(for: targetGridPoint, in: boardFrame)

                            MoveCardIllustrationView(card: animatingCard.move)
                                .matchedGeometryEffect(id: animatingCard.id, in: cardAnimationNamespace)
                                .frame(width: cardFrame.width, height: cardFrame.height)
                                .position(animationState == .movingToBoard ? boardDestination : startCenter)
                                .scaleEffect(animationState == .movingToBoard ? 0.55 : 1.0)
                                .opacity(animationState == .movingToBoard ? 0.0 : 1.0)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
    }

    /// レギュラー幅（iPad）向けにシート表示へ切り替えるためのバインディング
    /// - Returns: iPad では pendingMenuAction を返し、それ以外では常に nil を返すバインディング
    private var regularWidthPendingActionBinding: Binding<GameMenuAction?> {
        Binding(
            get: {
                // 横幅が十分でない場合はシート表示を抑制し、確認ダイアログ側に処理を委ねる
                guard horizontalSizeClass == .regular else {
                    return nil
                }
                return pendingMenuAction
            },
            set: { newValue in
                // シートを閉じたときに SwiftUI から nil が渡されるため、そのまま状態へ反映しておく
                pendingMenuAction = newValue
            }
        )
    }

    /// GeometryReader から得た値を整理し、盤面レイアウトに関わる各種寸法をひとまとめにしたコンテキストを返す
    /// - Parameter geometry: 画面全体のサイズやセーフエリアを提供するジオメトリープロキシ
    /// - Returns: 盤面サイズ計算や監視オーバーレイで共有するレイアウト情報一式
    private func makeLayoutContext(from geometry: GeometryProxy) -> LayoutComputationContext {
        // MARK: - セーフエリアに対するフォールバック計算
        let rawTopInset = geometry.safeAreaInsets.top
        let rawBottomInset = geometry.safeAreaInsets.bottom
        // RootView から受け取ったバー高さと、GeometryReader の差分から推定した値の双方を利用して補正量を決める
        let overlayFromEnvironment = max(topOverlayHeight, 0)
        let baseSafeAreaTop = max(baseTopSafeAreaInset, 0)
        let overlayFromDifference = max(rawTopInset - baseSafeAreaTop, 0)
        // いずれかで取得できた最大値を採用しつつ、rawTopInset を超えないようにクリップする
        let overlayCompensation = min(max(overlayFromEnvironment, overlayFromDifference), rawTopInset)
        let adjustedTopInset = max(rawTopInset - overlayCompensation, 0)
        // トップバーのぶんだけ画面内容が押し下げられている場合、純粋な安全領域だけを取り出しておく
        // これにより RootView 側で safeAreaInset を挿入した際でも、盤面の上部余白を必要最小限に抑えられる
        let overlayAdjustedTopInset = max(adjustedTopInset - overlayCompensation, 0)
        let usedTopFallback = adjustedTopInset <= 0 && horizontalSizeClass == .regular
        let usedBottomFallback = rawBottomInset <= 0 && horizontalSizeClass == .regular
        let topInset = adjustedTopInset > 0
            ? adjustedTopInset
            : (usedTopFallback ? LayoutMetrics.regularWidthTopSafeAreaFallback : 0)
        let bottomInset = rawBottomInset > 0
            ? rawBottomInset
            : (usedBottomFallback ? LayoutMetrics.regularWidthBottomSafeAreaFallback : 0)

        // MARK: - 盤面上部コントロールバーの余白を決定
        // overlayAdjustedTopInset は「システム由来のセーフエリア（ノッチ・ステータスバー）」のみを表す値なので、
        // トップバーが存在しても余計な空白が生まれないよう、この値に基づいて余白を算出する。
        let controlRowTopPadding = max(
            LayoutMetrics.controlRowBaseTopPadding,
            overlayAdjustedTopInset + LayoutMetrics.controlRowSafeAreaAdditionalPadding
        )

        // MARK: - 手札セクション下部の余白を決定
        let regularAdditionalPadding = horizontalSizeClass == .regular
            ? LayoutMetrics.handSectionRegularAdditionalBottomPadding
            : 0
        let handSectionBottomPadding = max(
            LayoutMetrics.handSectionBasePadding,
            bottomInset
                + LayoutMetrics.handSectionSafeAreaAdditionalPadding
                + regularAdditionalPadding
        )

        // MARK: - 計測が完了していない高さのフォールバック処理
        let isStatisticsHeightMeasured = statisticsHeight > 0
        let resolvedStatisticsHeight = isStatisticsHeightMeasured
            ? statisticsHeight
            : LayoutMetrics.statisticsSectionFallbackHeight
        let isHandSectionHeightMeasured = handSectionHeight > 0
        let resolvedHandSectionHeight = isHandSectionHeightMeasured
            ? handSectionHeight
            : LayoutMetrics.handSectionFallbackHeight

        // MARK: - 盤面に割り当てられる高さと正方形サイズの算出
        let availableHeightForBoard = geometry.size.height
            - resolvedStatisticsHeight
            - resolvedHandSectionHeight
            - LayoutMetrics.spacingBetweenBoardAndHand
            - LayoutMetrics.spacingBetweenStatisticsAndBoard
            - handSectionBottomPadding
        let horizontalBoardBase = max(geometry.size.width, LayoutMetrics.minimumBoardFallbackSize)
        let verticalBoardBase = availableHeightForBoard > 0 ? availableHeightForBoard : horizontalBoardBase
        let boardBaseSize = min(horizontalBoardBase, verticalBoardBase)
        let boardWidth = boardBaseSize * LayoutMetrics.boardScale

        return LayoutComputationContext(
            geometrySize: geometry.size,
            rawTopInset: rawTopInset,
            rawBottomInset: rawBottomInset,
            baseTopSafeAreaInset: baseSafeAreaTop,
            usedTopFallback: usedTopFallback,
            usedBottomFallback: usedBottomFallback,
            topOverlayHeight: overlayCompensation,
            overlayAdjustedTopInset: overlayAdjustedTopInset,
            topInset: topInset,
            bottomInset: bottomInset,
            controlRowTopPadding: controlRowTopPadding,
            regularAdditionalBottomPadding: regularAdditionalPadding,
            handSectionBottomPadding: handSectionBottomPadding,
            statisticsHeight: statisticsHeight,
            resolvedStatisticsHeight: resolvedStatisticsHeight,
            handSectionHeight: handSectionHeight,
            resolvedHandSectionHeight: resolvedHandSectionHeight,
            availableHeightForBoard: availableHeightForBoard,
            horizontalBoardBase: horizontalBoardBase,
            verticalBoardBase: verticalBoardBase,
            boardBaseSize: boardBaseSize,
            boardWidth: boardWidth,
            usedStatisticsFallback: !isStatisticsHeightMeasured,
            usedHandSectionFallback: !isHandSectionHeightMeasured
        )
    }

    /// 盤面の統計と SpriteKit ボードをまとめて描画する
    /// - Parameter width: GeometryReader で算出した盤面の幅（正方形表示の基準）
    /// - Returns: 統計バッジと SpriteView を縦に並べた領域
    private func boardSection(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.spacingBetweenStatisticsAndBoard) {
            boardControlRow()
            ZStack {
                spriteBoard(width: width)
                if core.progress == .awaitingSpawn {
                    spawnSelectionOverlay
                        // 盤面いっぱいに広がりすぎないよう最大幅を制限する
                        .frame(maxWidth: width * 0.9)
                        .padding(.horizontal, 12)
                }
            }
            // 盤面縮小で生まれた余白を均等にするため、中央寄せで描画する
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    /// 盤面上部の統計バッジと操作ボタンをまとめたコントロールバー
    /// - Returns: 統計情報を左側、リセット関連の操作ボタンを右側に揃えた横並びレイアウト
    private func boardControlRow() -> some View {
        ViewThatFits(in: .horizontal) {
            // 可能であれば従来通り 1 行で収める
            singleLineControlRow()
            // 横幅が不足する端末では統計とボタンを上下 2 行へ分離し、情報の重なりを避ける
            stackedControlRow()
        }
        .padding(.horizontal, 16)
        // PreferenceKey へコントロールバー全体の高さを渡し、盤面計算に利用する
        .overlay(alignment: .topLeading) {
            HeightPreferenceReporter<StatisticsHeightPreferenceKey>()
        }
    }

    /// 統計バッジ群とボタン群を 1 行へ並べるレイアウト
    /// - Returns: 余裕がある画面幅で利用する横並びの行
    private func singleLineControlRow() -> some View {
        HStack(alignment: .center, spacing: 12) {
            flexibleStatisticsContainer()

            controlButtonCluster()
        }
    }

    /// 統計バッジ群とボタン群を 2 行へ積み上げるレイアウト
    /// - Returns: iPhone など横幅が足りない場合に利用する上下構成の行
    private func stackedControlRow() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            flexibleStatisticsContainer()

            controlButtonCluster()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    /// 統計バッジ群の描画方法をまとめ、必要に応じてスクロールへフォールバックする
    /// - Returns: ViewThatFits による横幅調整を組み込んだ統計コンテナ
    private func flexibleStatisticsContainer() -> some View {
        ViewThatFits(in: .horizontal) {
            statisticsBadgeContainer()
            ScrollView(.horizontal, showsIndicators: false) {
                statisticsBadgeContainer()
            }
        }
        // 統計情報は優先的に幅を確保したいため高いレイアウト優先度を与える
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }

    /// デッキリセットやポーズなどの操作ボタンをまとめたグループ
    /// - Returns: 3 つの操作を横並びで配置した HStack
    private func controlButtonCluster() -> some View {
        HStack(spacing: 12) {
            manualDiscardButton
            manualPenaltyButton
            pauseButton
        }
    }

    /// 統計バッジ群をスコア関連とその他の 2 枠へ分割し、横並びで表示する
    /// - Returns: それぞれ装飾済みのグループを並べたビュー
    private func statisticsBadgeContainer() -> some View {
        HStack(spacing: 12) {
            scoreStatisticsGroup()
            supplementaryStatisticsGroup()
        }
    }

    /// スコアに直接影響する指標をまとめたグループ
    /// - Returns: 移動回数やスコアを 1 つの枠に収めたビュー
    private func scoreStatisticsGroup() -> some View {
        statisticsBadgeGroup {
            // 手数はペナルティの影響を含めた重要指標のため最初に表示する
            statisticBadge(
                title: "移動",
                value: "\(core.moveCount)",
                accessibilityLabel: "移動回数",
                accessibilityValue: "\(core.moveCount)回"
            )

            // ペナルティが増えると最終スコアも悪化するため、連続して配置して関連性を示す
            statisticBadge(
                title: "ペナルティ",
                value: "\(core.penaltyCount)",
                accessibilityLabel: "ペナルティ回数",
                accessibilityValue: "\(core.penaltyCount)手"
            )

            // 経過時間はスコア算出式の一部なのでここでまとめておく
            statisticBadge(
                title: "経過時間",
                value: formattedElapsedTime(displayedElapsedSeconds),
                accessibilityLabel: "経過時間",
                accessibilityValue: accessibilityElapsedTimeDescription(displayedElapsedSeconds)
            )

            // 総合スコアはリアルタイムで計算した値を表示し、結果画面で確定値と一致させる
            statisticBadge(
                title: "総合スコア",
                value: "\(displayedScore)",
                accessibilityLabel: "総合スコア",
                accessibilityValue: accessibilityScoreDescription(displayedScore)
            )
        }
    }

    /// レギュレーションによって増減する補助情報をまとめるグループ
    /// - Returns: 現状は残りマスのみだが、今後の追加にも対応できる枠
    private func supplementaryStatisticsGroup() -> some View {
        statisticsBadgeGroup {
            // 残りマスはスコアとは独立した進捗情報なので別枠へ分離する
            statisticBadge(
                title: "残りマス",
                value: "\(core.remainingTiles)",
                accessibilityLabel: "残りマス数",
                accessibilityValue: "残り\(core.remainingTiles)マス"
            )
        }
    }

    /// 共通デザインを適用した統計バッジ用コンテナ
    /// - Parameter content: 内部に並べる統計バッジ群
    /// - Returns: 角丸と枠線を持つバッジグループ
    private func statisticsBadgeGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.statisticBadgeBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.statisticBadgeBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    /// SpriteKit の盤面を描画し、ライフサイクルに応じた更新処理をまとめる
    /// - Parameter width: 正方形に保つための辺長
    /// - Returns: onAppear / onReceive を含んだ SpriteView
    private func spriteBoard(width: CGFloat) -> some View {
        SpriteView(scene: scene)
            // 正方形で表示したいため幅に合わせる
            .frame(width: width, height: width)
            // 盤面のアンカーを収集し、カード移動アニメーションの着地点に利用
            .anchorPreference(key: BoardAnchorPreferenceKey.self, value: .bounds) { $0 }
            .onAppear {
                // サイズと初期状態を反映
                debugLog("SpriteBoard.onAppear: width=\(width), scene.size=\(scene.size)")
                if width <= 0 {
                    // 盤面幅がゼロの場合は描画が行われないため、即座にログへ残して追跡する
                    debugLog("SpriteBoard.onAppear 警告: 盤面幅がゼロ以下です")
                }
                scene.size = CGSize(width: width, height: width)
                scene.updateBoard(core.board)
                scene.moveKnight(to: core.current)
                // 盤面の同期が整ったタイミングでガイド表示も更新
                refreshGuideHighlights()
            }
            // ジオメトリの変化に追従できるよう、SpriteKit シーンのサイズも都度更新する
            .onChange(of: width) { _, newWidth in
                // iOS 17 以降の新しいシグネチャに合わせて旧値を受け取るが、現状は利用しない
                debugLog("SpriteBoard.width 更新: newWidth=\(newWidth)")
                if newWidth <= 0 {
                    // レイアウト異常で幅がゼロになったケースを把握するための警告ログ
                    debugLog("SpriteBoard.width 警告: newWidth がゼロ以下です")
                }
                scene.size = CGSize(width: newWidth, height: newWidth)
            }
            // GameCore 側の更新を受け取り、SpriteKit の表示へ同期する
            .onReceive(core.$board) { newBoard in
                scene.updateBoard(newBoard)
                // 盤面の踏破状況が変わっても候補マスの情報を最新化
                refreshGuideHighlights()
            }
            .onReceive(core.$current) { newPoint in
                scene.moveKnight(to: newPoint)
                // 現在位置が変化したら移動候補も追従する
                refreshGuideHighlights(currentOverride: newPoint)
            }
    }

    /// スポーン位置選択中に盤面へ重ねる案内オーバーレイ
    private var spawnSelectionOverlay: some View {
        VStack(spacing: 8) {
            Text("開始マスを選択")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text("手札スロットと先読みを確認してから、好きなマスをタップしてください。")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(theme.spawnOverlayBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(theme.spawnOverlayBorder, lineWidth: 1)
                )
        )
        .shadow(color: theme.spawnOverlayShadow, radius: 18, x: 0, y: 8)
        .foregroundColor(theme.textPrimary)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("開始位置を選択してください。手札スロットと次のカードを見てから任意のマスをタップできます。"))
    }

    /// 手札と先読みカードの表示をまとめた領域
    /// - Parameters:
    ///   - bottomInset: 現在のデバイスが持つ下セーフエリアの量（ホームインジケータ分など）
    ///   - bottomPadding: セーフエリアと端末ごとの追加マージンを合算した推奨余白
    /// - Returns: 下部 UI 全体（余白調整を含む）
    private func handSection(
        bottomInset: CGFloat,
        bottomPadding: CGFloat
    ) -> some View {
        // MARK: - 追加余白の内訳
        // bottomPadding は GeometryReader 側で算出した「セーフエリア + 端末別マージン」を含む値。
        // まずは iPhone 時代から維持してきた 16pt（BasePadding）を常時適用し、
        // それでも不足する場合のみ追加分を足していく。GeometryReader 側から受け取った bottomPadding
        // はセーフエリア（bottomInset）と iPad 向けのマージンを反映済みだが、念のためここでも同じ計算を行い、
        // レイアウトの解釈違いがあっても最大値で丸めておく。
        let expectedPadding = max(
            LayoutMetrics.handSectionBasePadding,
            bottomInset
                + LayoutMetrics.handSectionSafeAreaAdditionalPadding
                + (horizontalSizeClass == .regular ? LayoutMetrics.handSectionRegularAdditionalBottomPadding : 0)
        )
        // GeometryReader から渡された値と再計算した値のうち大きい方を採用し、端末や OS バージョン差による
        // 丸め誤差で余白が不足しないように保険をかける。
        let finalBottomPadding = max(bottomPadding, expectedPadding)

        return VStack(spacing: 8) {
            if core.isAwaitingManualDiscardSelection {
                discardSelectionNotice
                    .transition(.opacity)
            }
            // 手札スロットを横並びで配置し、最大種類数を常に確保する
            // カードを大きくした際も全体幅が画面内に収まるよう、spacing を定数で管理する
            HStack(spacing: LayoutMetrics.handCardSpacing) {
                // 固定長スロットで回し、欠番があっても UI が崩れないようにする
                ForEach(0..<handSlotCount, id: \.self) { index in
                    handSlotView(for: index)
                }
            }

            // 先読みカードが存在する場合に表示（最大 3 枚を横並びで案内）
            if !core.nextCards.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    // MARK: - 先読みカードのラベル
                    // テキストでセクションを明示して VoiceOver からも認識しやすくする
                    Text("次のカード")
                        .font(.caption)
                        // テーマのサブ文字色で読みやすさと一貫性を確保
                        .foregroundColor(theme.textSecondary)
                        .accessibilityHidden(true)  // ラベル自体は MoveCardIllustrationView のラベルに統合する

                    // MARK: - 先読みカード本体
                    // 3 枚までのカードを順番に描画し、それぞれにインジケータを重ねる
                    HStack(spacing: 12) {
                        ForEach(Array(core.nextCards.enumerated()), id: \.element.id) { index, dealtCard in
                            ZStack {
                                MoveCardIllustrationView(card: dealtCard.move, mode: .next)
                                    .opacity(hiddenCardIDs.contains(dealtCard.id) ? 0.0 : 1.0)
                                    .matchedGeometryEffect(id: dealtCard.id, in: cardAnimationNamespace)
                                    .anchorPreference(key: CardPositionPreferenceKey.self, value: .bounds) { [dealtCard.id: $0] }
                                NextCardOverlayView(order: index)
                            }
                            // VoiceOver で順番が伝わるようラベルを上書き
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(Text("次のカード\(index == 0 ? "" : "+\(index)"): \(dealtCard.move.displayName)"))
                            .accessibilityHint(Text("この順番で手札に補充されます"))
                            .allowsHitTesting(false)  // 先読みは閲覧専用
                        }
                    }
                }
            }

#if DEBUG
            // MARK: - デバッグ専用ショートカット
            // 盤面の右上オーバーレイに重ねると UI が窮屈になるため、下部セクションへ移設
            HStack {
                Spacer(minLength: 0)
                debugResultButton
                    .padding(.top, 4)  // 手札との距離を確保して視認性を確保
                Spacer(minLength: 0)
            }
#endif
        }
        // PreferenceKey へ手札セクションの高さを渡し、GeometryReader の計算に活用する
        .overlay(alignment: .topLeading) {
            // 同様に手札全体の高さもゼロサイズのオーバーレイで取得し、親 GeometryReader の計算値を安定させる
            HeightPreferenceReporter<HandSectionHeightPreferenceKey>()
        }
        // BasePadding とセーフエリア・マージンをまとめて適用し、iPad でも指の収まりを良くする
        .padding(.bottom, finalBottomPadding)
    }

    /// 手動ペナルティ（手札引き直し）のショートカットボタン
    /// - Note: 統計バッジの右側に円形アイコンとして配置し、盤面上部の横並びレイアウトに収める
    private var manualDiscardButton: some View {
        // プレイ中かつ手札が存在するときだけ操作可能にする
        let isDisabled = core.progress != .playing || core.handStacks.isEmpty
        let isSelecting = core.isAwaitingManualDiscardSelection

        return Button {
            if isSelecting {
                // もう一度タップされた場合はモードを解除する
                core.cancelManualDiscardSelection()
            } else {
                // 捨て札モードへ移行してカード選択を待つ
                core.beginManualDiscardSelection()
            }
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(isSelecting ? theme.accentOnPrimary : theme.menuIconForeground)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(isSelecting ? theme.accentPrimary : theme.menuIconBackground)
                )
                .overlay(
                    Circle()
                        .stroke(
                            isSelecting ? theme.accentPrimary.opacity(0.55) : theme.menuIconBorder,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .opacity(isDisabled ? 0.45 : 1.0)
        .disabled(isDisabled)
        .accessibilityIdentifier("manual_discard_button")
        .accessibilityLabel(Text("手札を捨て札にする"))
        .accessibilityHint(Text(manualDiscardAccessibilityHint))
    }

    /// 捨て札モードの操作説明を状況に応じて生成する
    private var manualDiscardAccessibilityHint: String {
        let cost = core.mode.manualDiscardPenaltyCost
        if core.isAwaitingManualDiscardSelection {
            return "捨て札モードを終了します。カードを選ばずに通常操作へ戻ります。"
        }

        if cost > 0 {
            return "手数を\(cost)消費して、選択した手札 1 種類をまとめて捨て札にし、新しいカードを補充します。"
        } else {
            return "手数を消費せずに、選択した手札 1 種類をまとめて捨て札にし、新しいカードを補充します。"
        }
    }

    /// 捨て札モード時に表示する案内バナー
    private var discardSelectionNotice: some View {
        let penaltyCost = core.mode.manualDiscardPenaltyCost
        let penaltyDescription: String
        if penaltyCost > 0 {
            penaltyDescription = "ペナルティ +\(penaltyCost)"
        } else {
            penaltyDescription = "ペナルティなし"
        }

        return HStack(spacing: 12) {
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(theme.accentOnPrimary)
                .padding(10)
                .background(
                    Circle()
                        .fill(theme.accentPrimary)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("捨て札するカードを選択中")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.textPrimary)
                Text("タップした手札 1 種類を捨て札にして \(penaltyDescription)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(theme.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.cardBackgroundNext)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(theme.cardBorderHand.opacity(0.35), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("捨て札モードです。手札をタップして \(penaltyDescription)。"))
    }

    /// 手動ペナルティ（手札引き直し）のショートカットボタン
    /// - Note: 統計バッジの右側に円形アイコンとして配置し、盤面上部の横並びレイアウトに収める
    private var manualPenaltyButton: some View {
        // ゲームが進行中でない場合は無効化し、リザルト表示中などの誤操作を回避
        let isDisabled = core.progress != .playing

        return Button {
            // 実行前に必ず確認ダイアログを挟むため、既存のメニューアクションを再利用
            pendingMenuAction = .manualPenalty(penaltyCost: core.mode.manualRedrawPenaltyCost)
        } label: {
            // MARK: - ボタンは 44pt 以上の円形領域で構成し、メニューアイコンとの統一感を持たせる
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(theme.menuIconForeground)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(theme.menuIconBackground)
                )
                .overlay(
                    Circle()
                        .stroke(theme.menuIconBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .opacity(isDisabled ? 0.45 : 1.0)
        .disabled(isDisabled)
        .accessibilityIdentifier("manual_penalty_button")
        // VoiceOver でも「スロット」概念が伝わるように表現を更新
        .accessibilityLabel(Text("ペナルティを払って手札スロットを引き直す"))
        .accessibilityHint(Text(manualPenaltyAccessibilityHint))
    }

    /// 手動ペナルティの操作説明を状況に応じて生成
    /// - Note: スロット制の仕様を理解しやすいよう「種類数」とスタックの挙動を明記する。
    private var manualPenaltyAccessibilityHint: String {
        let cost = core.mode.manualRedrawPenaltyCost
        let stackingDetail = core.mode.stackingRuleDetailText
        let refillDescription = "手札スロットを全て空にし、新しいカードを最大 \(core.mode.handSize) 種類まで補充します。"
        if cost > 0 {
            return "手数を\(cost)消費して\(refillDescription)\(stackingDetail)"
        } else {
            return "手数を消費せずに\(refillDescription)\(stackingDetail)"
        }
    }

    /// 手詰まりペナルティを知らせるバナーのレイヤーを構成
    private func penaltyBannerOverlay(contentTopInset: CGFloat) -> some View {
        // MARK: - ステータスバーとの距離を安全に確保する
        // iPad のフォームシートなどで safeAreaInsets.top が 0 になるケースでは、
        // バナーが画面最上部へ貼り付いてしまうため、フォールバックを交えつつ余白を広げる。
        // contentTopInset にはステータスバー由来の安全領域のみを渡し、RootView のトップバーぶんはすでに差し引いた状態にする。
        // これによりトップバー表示時でもバナーが極端に下へずり落ちることを防ぐ。
        // contentTopInset が 0 でも LayoutMetrics.penaltyBannerBaseTopPadding だけは必ず確保し、
        // 非ゼロのインセットが得られた場合は追加マージンを加えて矢印付きダイアログとの干渉を避ける。
        let resolvedTopPadding = max(
            LayoutMetrics.penaltyBannerBaseTopPadding,
            contentTopInset + LayoutMetrics.penaltyBannerSafeAreaAdditionalPadding
        )

        return VStack {
            if isShowingPenaltyBanner {
                HStack {
                    Spacer(minLength: 0)
                    PenaltyBannerView(penaltyAmount: core.lastPenaltyAmount)
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .accessibilityIdentifier("penalty_banner")
                    Spacer(minLength: 0)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, resolvedTopPadding)
        .allowsHitTesting(false)  // バナーが表示されていても下の UI を操作可能にする
        .zIndex(2)
    }

    /// SpriteKit シーンの配色を現在のテーマに合わせて調整する
    /// - Parameter scheme: ユーザーが選択中のライト/ダーク種別
    private func applyScenePalette(for scheme: ColorScheme) {
        // SwiftUI 環境のカラースキームを明示指定した AppTheme を生成
        let appTheme = AppTheme(colorScheme: scheme)

        // AppTheme から SpriteKit 用のカラーパレットへ値を写し替える
        let palette = GameScenePalette(
            boardBackground: appTheme.skBoardBackground,
            boardGridLine: appTheme.skBoardGridLine,
            boardTileVisited: appTheme.skBoardTileVisited,
            boardTileUnvisited: appTheme.skBoardTileUnvisited,
            boardKnight: appTheme.skBoardKnight,
            boardGuideHighlight: appTheme.skBoardGuideHighlight
        )

        // 変換したパレットを SpriteKit シーンへ適用し、UI と配色を一致させる
        scene.applyTheme(palette)
    }

    /// ガイドモードの設定と現在の手札から移動可能なマスを算出し、SpriteKit 側へ通知する
    /// - Parameters:
    ///   - handOverride: 直近で受け取った最新の手札（`nil` の場合は `core.handStacks` を利用する）
    ///   - currentOverride: 最新の現在地（`nil` の場合は `core.current` を利用する）
    ///   - progressOverride: Combine で受け取った最新進行度（`nil` の場合は `core.progress` を参照）
    private func refreshGuideHighlights(
        handOverride: [HandStack]? = nil,
        currentOverride: GridPoint? = nil,
        progressOverride: GameProgress? = nil
    ) {
        // パラメータで上書き値が渡されていれば優先し、未指定であれば GameCore が保持する最新の状態を利用する
        let handStacks = handOverride ?? core.handStacks
        // Combine から届いた最新の進行度を優先できるよう引数でも受け取り、なければ GameCore の値を参照する
        let progress = progressOverride ?? core.progress

        // スポーン選択中などで現在地が未確定の場合はガイドを消灯し、再開に備えて状態をリセットする
        guard let current = currentOverride ?? core.current else {
            scene.updateGuideHighlights([])
            pendingGuideHand = nil
            pendingGuideCurrent = nil
            debugLog("ガイド更新を中断: 現在地が未確定のためハイライトを消灯 状態=\(String(describing: progress)), スタック数=\(handStacks.count)")
            return
        }

        // 各カードの移動先を列挙し、盤内に収まるマスだけを候補として蓄積する
        var candidatePoints: Set<GridPoint> = []
        for stack in handStacks {
            guard let card = stack.topCard else { continue }
            // 現在位置からカードの移動量を加算し、到達先マスを導出する
            let destination = current.offset(dx: card.move.dx, dy: card.move.dy)
            if core.board.contains(destination) {
                candidatePoints.insert(destination)
            }
        }

        // ガイドモードが無効なときは全てのハイライトを隠し、バッファも不要なので初期化する
        guard guideModeEnabled else {
            scene.updateGuideHighlights([])
            pendingGuideHand = nil
            pendingGuideCurrent = nil
            // ガイドモードを明示的に無効化した場合は、候補数と進行状態をログへ残して挙動を可視化する
            debugLog("ガイド無効化に伴いハイライトを消灯: 状態=\(String(describing: progress)), 候補マス数=\(candidatePoints.count)")
            return
        }

        // 進行状態が .playing 以外（例: .deadlock）のときは手札と位置をバッファへ退避し、再開時に再描画できるようにする
        guard progress == .playing else {
            pendingGuideHand = handStacks
            pendingGuideCurrent = current
            // デッドロックなどで一時停止した場合は、復帰時に備えて候補数と現在地をログに出力する
            debugLog("ガイド更新を保留: 状態=\(String(describing: progress)), 退避候補数=\(candidatePoints.count), 現在地=\(current)")
            return
        }

        // 正常に描画できたらバッファは不要のためリセットする
        pendingGuideHand = nil
        pendingGuideCurrent = nil

        // 算出した集合を SpriteKit へ渡し、視覚的なサポートを行う
        scene.updateGuideHighlights(candidatePoints)
        // ガイドを実際に描画した際も、進行状態と候補数をログに記録して UI 側の追跡を容易にする
        debugLog("ガイドを描画: 状態=\(String(describing: progress)), 描画マス数=\(candidatePoints.count)")
    }

    /// 指定スタックのトップカードが現在位置から盤内に収まるか判定
    /// - Parameter stack: 判定対象とする手札スタック
    /// - Note: MoveCard は列挙型であり、dx/dy プロパティから移動量を取得する
    private func isCardUsable(_ stack: HandStack) -> Bool {
        guard let card = stack.topCard else {
            // スタックが空の場合は使用不可扱いにして安全側へ倒す
            return false
        }
        guard let current = core.current else {
            // スポーン未確定など現在地が無い場合は全てのカードを使用不可とみなす
            return false
        }
        // 現在位置に MoveCard の移動量を加算して目的地を算出
        let target = current.offset(dx: card.move.dx, dy: card.move.dy)
        // 目的地が盤面内に含まれているかどうかを判定
        return core.board.contains(target)
    }

    /// 手札スタックのトップカードを盤面へ送るアニメーションを共通化する
    /// - Parameters:
    ///   - stack: 演出対象の手札スタック
    ///   - index: `GameCore.playCard(at:)` に渡すインデックス
    /// - Returns: アニメーションを開始できた場合は true
    @discardableResult
    private func animateCardPlay(for stack: HandStack, at index: Int) -> Bool {
        // 既に別カードの演出が進行中なら二重再生を避ける
        guard animatingCard == nil else { return false }
        // スポーン未確定時はカードを使用できないため、演出を開始せず安全に抜ける
        guard let current = core.current else { return false }
        // スタックのトップカードを取得し、盤面内へ移動可能かチェックする
        guard let topCard = stack.topCard, isCardUsable(stack) else { return false }

        // アニメーション開始前に現在地を記録しておき、目的地の座標計算に利用する
        animationTargetGridPoint = current
        hiddenCardIDs.insert(topCard.id)
        animatingCard = topCard
        animatingStackID = stack.id
        animationState = .idle

        debugLog("スタック演出開始: stackID=\(stack.id), card=\(topCard.move.displayName), 残枚数=\(stack.count)")

        // 成功操作のフィードバックを統一
        if hapticsEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }

        // 盤面へ吸い込まれていく動きを開始（時間はカードタップ時と同じ 0.24 秒）
        let travelDuration: TimeInterval = 0.24
        withAnimation(.easeInOut(duration: travelDuration)) {
            animationState = .movingToBoard
        }

        let cardID = topCard.id
        // 演出完了後に実際の移動処理を実行し、状態を初期化する
        DispatchQueue.main.asyncAfter(deadline: .now() + travelDuration) {
            withAnimation(.easeInOut(duration: 0.22)) {
                core.playCard(at: index)
            }
            hiddenCardIDs.remove(cardID)
            if animatingCard?.id == cardID {
                animatingCard = nil
            }
            animatingStackID = nil
            animationState = .idle
            animationTargetGridPoint = nil
            debugLog("スタック演出完了: stackIndex=\(index), 消費カードID=\(cardID)")
        }

        return true
    }

    /// GameCore から届いた盤面タップ要求を処理し、必要に応じてカード演出を開始する
    /// - Parameter request: 盤面タップ時に GameCore が公開した手札情報
    private func handleBoardTapPlayRequest(_ request: BoardTapPlayRequest) {
        // 処理の成否にかかわらず必ずリクエストを消費して次のタップを受け付ける
        defer { core.clearBoardTapPlayRequest(request.id) }

        // アニメーション再生中は新しいリクエストを無視する（UI 全体も disabled 済みだが安全策）
        guard animatingCard == nil else {
            debugLog("BoardTapPlayRequest を無視: 別カードが移動中 requestID=\(request.id), 進行中stack=\(String(describing: animatingStackID)))")
            return
        }

        // 指定されたスタックが最新の状態でも存在するか確認する
        let resolvedIndex: Int
        if core.handStacks.indices.contains(request.stackIndex),
           core.handStacks[request.stackIndex].id == request.stackID {
            resolvedIndex = request.stackIndex
        } else if let fallbackIndex = core.handStacks.firstIndex(where: { $0.id == request.stackID }) {
            resolvedIndex = fallbackIndex
        } else {
            debugLog("BoardTapPlayRequest を無視: stackID=\(request.stackID) が見つからない")
            return
        }

        let stack = core.handStacks[resolvedIndex]
        guard let currentTop = stack.topCard else {
            debugLog("BoardTapPlayRequest を無視: スタックにトップカードが存在しない stackID=\(stack.id)")
            return
        }

        let sameID = currentTop.id == request.topCard.id
        let sameMove = currentTop.move == request.topCard.move

        debugLog(
            "BoardTapPlayRequest 受信: requestID=\(request.id), 要求index=\(request.stackIndex), 解決index=\(resolvedIndex), stackID=\(stack.id), requestTopID=\(request.topCard.id), resolvedTopID=\(currentTop.id), sameID=\(sameID), sameMove=\(sameMove), 残枚数=\(stack.count)"
        )

        guard sameID || sameMove else {
            debugLog("BoardTapPlayRequest を無視: トップカードの種類が変わったため最新状態を優先")
            return
        }

        _ = animateCardPlay(for: stack, at: resolvedIndex)
    }

    /// グリッド座標を SpriteView 上の中心座標に変換する
    /// - Parameters:
    ///   - gridPoint: 盤面上のマス座標（原点は左下）
    ///   - frame: SwiftUI における盤面矩形
    /// - Returns: SwiftUI 座標系での中心位置
    private func boardCoordinate(for gridPoint: GridPoint, in frame: CGRect) -> CGPoint {
        // 現在の盤面サイズに応じて 1 マス分の辺長を算出する
        let boardSize = max(1, core.board.size)
        let tileLength = frame.width / CGFloat(boardSize)
        let centerX = frame.minX + tileLength * (CGFloat(gridPoint.x) + 0.5)
        // SwiftUI は上向きがマイナスのため、下端を基準に引き算して y を求める
        let centerY = frame.maxY - tileLength * (CGFloat(gridPoint.y) + 0.5)
        return CGPoint(x: centerX, y: centerY)
    }

    /// 盤面上部に表示する統計テキストの共通レイアウト
    /// - Parameters:
    ///   - title: メトリクスのラベル（例: 移動）
    ///   - value: 表示する数値文字列
    ///   - accessibilityLabel: VoiceOver に読み上げさせる日本語ラベル
    ///   - accessibilityValue: VoiceOver 用の値（単位を含めた文章）
    /// - Returns: モノクロ配色の小型バッジビュー
    private func statisticBadge(
        title: String,
        value: String,
        accessibilityLabel: String,
        accessibilityValue: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // 補助ラベルは控えめなトーンで表示
            Text(title)
                .font(.caption2)
                .fontWeight(.medium)
                // テーマの補助文字色でライト/ダーク双方のコントラストを調整
                .foregroundColor(theme.statisticTitleText)

            // 主数値は視認性を高めるためサイズとコントラストを強調
            Text(value)
                .font(.headline)
                .foregroundColor(theme.statisticValueText)
        }
        // VoiceOver ではカスタムラベルと値を読み上げさせる
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    /// 経過秒数を mm:ss 形式へ整形し、視覚的に読みやすくする
    /// - Parameter seconds: 表示したい経過秒数
    /// - Returns: mm:ss 形式の文字列
    private func formattedElapsedTime(_ seconds: Int) -> String {
        // 60 秒で割った商を分、余りを秒として表示する
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    /// アクセシビリティ向けに経過時間を自然な日本語へ整形する
    /// - Parameter seconds: 読み上げに使用する経過秒数
    /// - Returns: 「X時間Y分Z秒」の形式でまとめた説明文
    private func accessibilityElapsedTimeDescription(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60

        if hours > 0 {
            return "\(hours)時間\(minutes)分\(remainingSeconds)秒"
        } else if minutes > 0 {
            return "\(minutes)分\(remainingSeconds)秒"
        } else {
            return "\(remainingSeconds)秒"
        }
    }

    /// アクセシビリティ向けにスコアを自然な日本語へ整形する
    /// - Parameter score: 読み上げに使用するスコア値
    /// - Returns: 「Xポイント」の形式でまとめた説明文
    private func accessibilityScoreDescription(_ score: Int) -> String {
        "\(score)ポイント"
    }

    /// GameCore が保持する時刻情報から画面表示用の経過秒数を更新する
    /// - Note: 秒単位の差分しか扱わないため、値が変わったときのみ State を更新して不要な再描画を抑制する
    private func updateDisplayedElapsedTime() {
        // クリア済みなら確定値を、プレイ中はリアルタイム計算値を採用する
        let latestSeconds: Int
        if core.progress == .cleared {
            latestSeconds = core.elapsedSeconds
        } else {
            latestSeconds = core.liveElapsedSeconds
        }

        // 値に変化があったときだけ State を更新する
        if displayedElapsedSeconds != latestSeconds {
            displayedElapsedSeconds = latestSeconds
        }
    }

    /// 指定スロットのスタック（存在しない場合は nil）を取得するヘルパー
    /// - Parameter index: 手札スロットの添字
    /// - Returns: 対応する `HandStack` または nil（スロットが空の場合）
    private func handCard(at index: Int) -> HandStack? {
        guard core.handStacks.indices.contains(index) else {
            // スロットにスタックが存在しない場合は nil を返してプレースホルダ表示を促す
            return nil
        }
        return core.handStacks[index]
    }

    /// 手札スロットの描画を担う共通処理
    /// - Parameter index: 対象スロットの添字
    /// - Returns: MoveCardIllustrationView または空枠プレースホルダを含むビュー
    private func handSlotView(for index: Int) -> some View {
        ZStack {
            if let stack = handCard(at: index), let card = stack.topCard {
                let isHidden = hiddenCardIDs.contains(card.id)
                let isUsable = isCardUsable(stack)
                let isSelectingDiscard = core.isAwaitingManualDiscardSelection

                HandStackCardView(stackCount: stack.count) {
                    MoveCardIllustrationView(card: card.move)
                        .matchedGeometryEffect(id: card.id, in: cardAnimationNamespace)
                        .anchorPreference(key: CardPositionPreferenceKey.self, value: .bounds) { [card.id: $0] }
                }
                // 使用不可カードは薄く表示し、アニメーション中は完全に透明化
                .opacity(
                    isHidden ? 0.0 : (isSelectingDiscard ? 1.0 : (isUsable ? 1.0 : 0.4))
                )
                .allowsHitTesting(!isHidden)
                .overlay {
                    if isSelectingDiscard && !isHidden {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(theme.accentPrimary.opacity(0.75), lineWidth: 3)
                            .shadow(color: theme.accentPrimary.opacity(0.45), radius: 6, x: 0, y: 3)
                            .accessibilityHidden(true)
                    }
                }
                .onTapGesture {
                    // 既に別カードが移動中ならタップを無視して多重処理を防止
                    guard animatingCard == nil else { return }

                    guard core.handStacks.indices.contains(index) else { return }
                    let latestStack = core.handStacks[index]

                    if core.isAwaitingManualDiscardSelection {
                        // 捨て札モードではスタックをまとめて破棄する
                        withAnimation(.easeInOut(duration: 0.2)) {
                            let success = core.discardHandStack(withID: latestStack.id)
                            if success, hapticsEnabled {
                                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                            }
                        }
                    } else if isCardUsable(latestStack) {
                        // 共通処理でアニメーションとカード使用をまとめて実行
                        _ = animateCardPlay(for: latestStack, at: index)
                    } else {
                        // 使用不可カードは警告ハプティクスのみ発火
                        if hapticsEnabled {
                            UINotificationFeedbackGenerator()
                                .notificationOccurred(.warning)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(accessibilityLabel(for: stack)))
                .accessibilityHint(Text(accessibilityHint(for: stack, isUsable: isUsable, isDiscardMode: isSelectingDiscard)))
                .accessibilityAddTraits(.isButton)
            } else {
                placeholderCardView()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("カードなしのスロット"))
                    .accessibilityHint(Text("このスロットには現在カードがありません"))
            }
        }
        // 実カードとプレースホルダのどちらでも同じスロット識別子で UI テストしやすくする
        .accessibilityIdentifier("hand_slot_\(index)")
    }

    /// 手札が空の際に表示するプレースホルダビュー
    /// - Note: 実カードと同じサイズを確保してレイアウトのズレを防ぐ
    private func placeholderCardView() -> some View {
        RoundedRectangle(cornerRadius: 8)
            // テーマ由来の枠線色でライト/ダークの差異を吸収
            .stroke(theme.placeholderStroke, style: StrokeStyle(lineWidth: 1, dash: [4]))
            .background(
                RoundedRectangle(cornerRadius: 8)
                    // 枠内もテーマ色で淡く塗りつぶし、背景とのコントラストを確保
                    .fill(theme.placeholderBackground)
            )
            // MoveCardIllustrationView と同寸法を共有し、カードが補充されてもレイアウトが揺れないようにする
            .frame(width: LayoutMetrics.handCardWidth, height: LayoutMetrics.handCardHeight)
            .overlay(
                Image(systemName: "questionmark")
                    .font(.caption)
                    // プレースホルダアイコンもテーマ色で調整
                    .foregroundColor(theme.placeholderIcon)
            )
    }

    /// VoiceOver 向けに方向名と残枚数を組み合わせた説明文を生成する
    /// - Parameter stack: ラベル生成対象の手札スタック
    /// - Returns: 「右上へ 2、残り 3 枚」のような読み上げテキスト
    private func accessibilityLabel(for stack: HandStack) -> String {
        guard let move = stack.topCard?.move else {
            return "カードなしのスロット"
        }
        return "\(directionPhrase(for: move))、残り \(stack.count) 枚"
    }

    /// VoiceOver のヒント文を生成し、スタック消費の挙動を分かりやすく説明する
    /// - Parameters:
    ///   - stack: 対象となる手札スタック
    ///   - isUsable: 現在位置から使用可能かどうか
    /// - Returns: スタック挙動を含む丁寧な説明文
    private func accessibilityHint(for stack: HandStack, isUsable: Bool, isDiscardMode: Bool) -> String {
        if isDiscardMode {
            return "ダブルタップでこの種類のカードをすべて捨て札にし、新しいカードを補充します。"
        }

        if isUsable {
            if stack.count > 1 {
                return "ダブルタップで先頭カードを使用します。スタックの残り \(stack.count - 1) 枚は同じ方向で待機します。"
            } else {
                return "ダブルタップでこの方向に移動します。スタックは 1 枚だけです。"
            }
        } else {
            return "盤外のため使用できません。スタックの \(stack.count) 枚はそのまま保持されます。"
        }
    }

    /// MoveCard を人間向けの方向説明文へ変換する
    /// - Parameter move: 説明したい移動カード
    /// - Returns: 「右上へ 2」「上へ 2、右へ 1」などの読み上げテキスト
    private func directionPhrase(for move: MoveCard) -> String {
        switch move {
        case .kingUp:
            return "上へ 1"
        case .kingUpRight:
            return "右上へ 1"
        case .kingRight:
            return "右へ 1"
        case .kingDownRight:
            return "右下へ 1"
        case .kingDown:
            return "下へ 1"
        case .kingDownLeft:
            return "左下へ 1"
        case .kingLeft:
            return "左へ 1"
        case .kingUpLeft:
            return "左上へ 1"
        case .knightUp2Right1:
            return "上へ 2、右へ 1"
        case .knightUp2Left1:
            return "上へ 2、左へ 1"
        case .knightUp1Right2:
            return "上へ 1、右へ 2"
        case .knightUp1Left2:
            return "上へ 1、左へ 2"
        case .knightDown2Right1:
            return "下へ 2、右へ 1"
        case .knightDown2Left1:
            return "下へ 2、左へ 1"
        case .knightDown1Right2:
            return "下へ 1、右へ 2"
        case .knightDown1Left2:
            return "下へ 1、左へ 2"
        case .straightUp2:
            return "上へ 2"
        case .straightDown2:
            return "下へ 2"
        case .straightRight2:
            return "右へ 2"
        case .straightLeft2:
            return "左へ 2"
        case .diagonalUpRight2:
            return "右上へ 2"
        case .diagonalDownRight2:
            return "右下へ 2"
        case .diagonalDownLeft2:
            return "左下へ 2"
        case .diagonalUpLeft2:
            return "左上へ 2"
        }
    }

    /// レイアウトに関する最新の実測値をログに残すための不可視ビューを生成
    /// - Parameter context: GeometryReader から抽出したレイアウト情報コンテキスト
    /// - Returns: 画面上には表示されない監視用ビュー
    private func layoutDiagnosticOverlay(using context: LayoutComputationContext) -> some View {
        // 現在のレイアウト関連値をひとまとめにして Equatable なスナップショットとして扱い、差分が生じたときだけログを出力する
        let snapshot = BoardLayoutSnapshot(context: context)

        return Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .onAppear {
                // 表示直後にレイアウト情報を記録して初期状態を把握
                logLayoutSnapshot(snapshot, reason: "初期観測")
            }
            .onChange(of: snapshot) { _, newValue in
                // レイアウト値が変動するたびにスナップショットを残し、問題の再現条件を追跡する
                logLayoutSnapshot(newValue, reason: "値更新")
            }
    }

    /// 実測値のスナップショットを比較しつつログへ出力する共通処理
    /// - Parameters:
    ///   - snapshot: 記録したいレイアウト値一式
    ///   - reason: ログ出力の契機（onAppear / 値更新など）
    private func logLayoutSnapshot(_ snapshot: BoardLayoutSnapshot, reason: String) {
        // 同じ値での重複出力を避け、必要なタイミングのみに絞ってログを残す
        if lastLoggedLayoutSnapshot == snapshot { return }
        lastLoggedLayoutSnapshot = snapshot

        // 盤面縮小ロジックのどこで値が想定外になっているか突き止められるよう、多段の詳細ログを整形して出力する
        let message = """
        GameView.layout 観測: 理由=\(reason)
          geometry=\(snapshot.geometrySize)
          safeArea(rawTop=\(snapshot.rawTopInset), baseTop=\(snapshot.baseTopSafeAreaInset), rawBottom=\(snapshot.rawBottomInset), resolvedTop=\(snapshot.resolvedTopInset), overlayAdjustedTop=\(snapshot.overlayAdjustedTopInset), resolvedBottom=\(snapshot.resolvedBottomInset), fallbackTop=\(snapshot.usedTopSafeAreaFallback), fallbackBottom=\(snapshot.usedBottomSafeAreaFallback), overlayTop=\(snapshot.topOverlayHeight))
          sections(statistics=\(snapshot.statisticsHeight), resolvedStatistics=\(snapshot.resolvedStatisticsHeight), hand=\(snapshot.handSectionHeight), resolvedHand=\(snapshot.resolvedHandSectionHeight))
          paddings(controlTop=\(snapshot.controlRowTopPadding), handBottom=\(snapshot.handSectionBottomPadding), regularExtra=\(snapshot.regularAdditionalBottomPadding))
          fallbacks(statistics=\(snapshot.usedStatisticsFallback), hand=\(snapshot.usedHandSectionFallback), topSafeArea=\(snapshot.usedTopSafeAreaFallback), bottomSafeArea=\(snapshot.usedBottomSafeAreaFallback))
          boardBases(horizontal=\(snapshot.horizontalBoardBase), vertical=\(snapshot.verticalBoardBase), resolved=\(snapshot.boardBaseSize)) availableHeight=\(snapshot.availableHeight) boardScale=\(LayoutMetrics.boardScale) boardWidth=\(snapshot.boardWidth)
        """

        debugLog(message)

        if snapshot.availableHeight <= 0 || snapshot.boardWidth <= 0 {
            // 盤面がゼロサイズになる条件を明確化するため、異常時は追加で警告ログを残す
            debugLog(
                "GameView.layout 警告: availableHeight=\(snapshot.availableHeight), horizontalBase=\(snapshot.horizontalBoardBase), verticalBase=\(snapshot.verticalBoardBase), boardBase=\(snapshot.boardBaseSize), boardWidth=\(snapshot.boardWidth)"
            )
        }
    }

    /// GeometryReader から求めたレイアウト値を保持する内部専用の構造体
    private struct LayoutComputationContext {
        let geometrySize: CGSize
        let rawTopInset: CGFloat
        let rawBottomInset: CGFloat
        let baseTopSafeAreaInset: CGFloat
        let usedTopFallback: Bool
        let usedBottomFallback: Bool
        let topOverlayHeight: CGFloat
        let overlayAdjustedTopInset: CGFloat
        let topInset: CGFloat
        let bottomInset: CGFloat
        let controlRowTopPadding: CGFloat
        let regularAdditionalBottomPadding: CGFloat
        let handSectionBottomPadding: CGFloat
        let statisticsHeight: CGFloat
        let resolvedStatisticsHeight: CGFloat
        let handSectionHeight: CGFloat
        let resolvedHandSectionHeight: CGFloat
        let availableHeightForBoard: CGFloat
        let horizontalBoardBase: CGFloat
        let verticalBoardBase: CGFloat
        let boardBaseSize: CGFloat
        let boardWidth: CGFloat
        let usedStatisticsFallback: Bool
        let usedHandSectionFallback: Bool
    }

    /// レイアウト監視で扱う値をひとまとめにした構造体
    /// - Note: Equatable 準拠により onChange での差分検出に利用する
    private struct BoardLayoutSnapshot: Equatable {
        let geometrySize: CGSize
        let availableHeight: CGFloat
        let horizontalBoardBase: CGFloat
        let verticalBoardBase: CGFloat
        let boardBaseSize: CGFloat
        let boardWidth: CGFloat
        let rawTopInset: CGFloat
        let rawBottomInset: CGFloat
        let baseTopSafeAreaInset: CGFloat
        let resolvedTopInset: CGFloat
        let overlayAdjustedTopInset: CGFloat
        let resolvedBottomInset: CGFloat
        let statisticsHeight: CGFloat
        let resolvedStatisticsHeight: CGFloat
        let handSectionHeight: CGFloat
        let resolvedHandSectionHeight: CGFloat
        let regularAdditionalBottomPadding: CGFloat
        let handSectionBottomPadding: CGFloat
        let usedTopSafeAreaFallback: Bool
        let usedBottomSafeAreaFallback: Bool
        let usedStatisticsFallback: Bool
        let usedHandSectionFallback: Bool
        let controlRowTopPadding: CGFloat
        let topOverlayHeight: CGFloat

        /// レイアウト計算で得られたコンテキストからスナップショットを構築するイニシャライザ
        /// - Parameter context: GeometryReader の結果を整理したレイアウトコンテキスト
        init(context: LayoutComputationContext) {
            self.geometrySize = context.geometrySize
            self.availableHeight = context.availableHeightForBoard
            self.horizontalBoardBase = context.horizontalBoardBase
            self.verticalBoardBase = context.verticalBoardBase
            self.boardBaseSize = context.boardBaseSize
            self.boardWidth = context.boardWidth
            self.rawTopInset = context.rawTopInset
            self.rawBottomInset = context.rawBottomInset
            self.baseTopSafeAreaInset = context.baseTopSafeAreaInset
            self.resolvedTopInset = context.topInset
            self.overlayAdjustedTopInset = context.overlayAdjustedTopInset
            self.resolvedBottomInset = context.bottomInset
            self.statisticsHeight = context.statisticsHeight
            self.resolvedStatisticsHeight = context.resolvedStatisticsHeight
            self.handSectionHeight = context.handSectionHeight
            self.resolvedHandSectionHeight = context.resolvedHandSectionHeight
            self.regularAdditionalBottomPadding = context.regularAdditionalBottomPadding
            self.handSectionBottomPadding = context.handSectionBottomPadding
            self.usedTopSafeAreaFallback = context.usedTopFallback
            self.usedBottomSafeAreaFallback = context.usedBottomFallback
            self.usedStatisticsFallback = context.usedStatisticsFallback
            self.usedHandSectionFallback = context.usedHandSectionFallback
            self.controlRowTopPadding = context.controlRowTopPadding
            self.topOverlayHeight = context.topOverlayHeight
        }
    }

}

private extension GameView {
    /// AppStorage から読み出した文字列を安全に列挙体へ変換する
    /// - Returns: 有効な設定値。未知の値は従来方式へフォールバックする
    func resolveHandOrderingStrategy() -> HandOrderingStrategy {
        HandOrderingStrategy(rawValue: handOrderingRawValue) ?? .insertionOrder
    }
}

// MARK: - コントロールバーの操作要素
private extension GameView {
    /// ゲームを一時停止して各種設定やリセット操作をまとめて案内するボタン
    private var pauseButton: some View {
        Button {
            debugLog("GameView: ポーズメニュー表示要求")
            isPauseMenuPresented = true
        } label: {
            Image(systemName: "pause.circle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(theme.menuIconForeground)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(theme.menuIconBackground)
                )
                .overlay(
                    Circle()
                        .stroke(theme.menuIconBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pause_menu_button")
        .accessibilityLabel(Text("ポーズメニュー"))
        .accessibilityHint(Text("プレイを一時停止して設定やリセットを確認します"))
    }

    #if DEBUG
    /// 結果画面を即座に表示するデバッグ向けボタン
    private var debugResultButton: some View {
        Button(action: {
            // 直接結果画面を開き、UI の確認やデバッグを容易にする
            showingResult = true
        }) {
            Text("結果へ")
        }
        .buttonStyle(.bordered)
        // UI テストでボタンを特定できるよう識別子を設定
        .accessibilityIdentifier("show_result")
    }
    #endif

    /// メニュー操作を実際に実行する共通処理
    /// - Parameter action: ユーザーが選択した操作種別
    private func performMenuAction(_ action: GameMenuAction) {
        // ダイアログを閉じるために必ず nil へ戻す
        pendingMenuAction = nil

        switch action {
        case .manualPenalty(_):
            // 既存バナーの自動クローズ処理を停止し、新規イベントに備える
            penaltyDismissWorkItem?.cancel()
            penaltyDismissWorkItem = nil
            isShowingPenaltyBanner = false
            // GameCore の共通処理を呼び出し、手動ペナルティを適用
            core.applyManualPenaltyRedraw()

        case .reset:
            // バナー表示をリセットし、ゲームを初期状態へ戻す
            penaltyDismissWorkItem?.cancel()
            penaltyDismissWorkItem = nil
            isShowingPenaltyBanner = false
            // シートが開いている場合でも即座に閉じる
            showingResult = false
            core.reset()
            adsService.resetPlayFlag()

        case .returnToTitle:
            // リセットと同じ処理を実行した後にタイトル戻りを通知
            penaltyDismissWorkItem?.cancel()
            penaltyDismissWorkItem = nil
            isShowingPenaltyBanner = false
            showingResult = false
            core.reset()
            adsService.resetPlayFlag()
            onRequestReturnToTitle?()
        }
    }
}

// MARK: - レギュラー幅向けのメニュー確認シート
/// iPad で確認文をゆったり表示するためのシートビュー
// MARK: - ファイル内限定で利用する確認用シート
/// `GameMenuAction` が fileprivate な型のため、このシートも fileprivate としておく
fileprivate struct GameMenuActionConfirmationSheet: View {
    /// 共通配色を参照して背景色などを統一する
    private var theme = AppTheme()
    /// 現在確認中のアクション
    let action: GameMenuAction
    /// 確定時に GameView 側で処理を実行するクロージャ
    let onConfirm: (GameMenuAction) -> Void
    /// キャンセル時に状態をリセットするクロージャ
    let onCancel: () -> Void

    /// 明示的なイニシャライザを用意し、`GameMenuAction` が `private` スコープでも呼び出せるようにする
    /// - Parameters:
    ///   - action: 確認対象のメニューアクション
    ///   - onConfirm: 決定時に呼び出すクロージャ
    ///   - onCancel: キャンセル時に呼び出すクロージャ
    fileprivate init(
        action: GameMenuAction,
        onConfirm: @escaping (GameMenuAction) -> Void,
        onCancel: @escaping () -> Void
    ) {
        // メンバーごとに代入し、従来通りの挙動を維持する
        self.action = action
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            // MARK: - 見出しと詳細説明
            VStack(alignment: .leading, spacing: 16) {
                Text("操作の確認")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(action.confirmationMessage)
                    .font(.body)
                    .multilineTextAlignment(.leading)
                    // iPad で視線移動が極端にならないように最大幅を確保しつつ左寄せで表示する
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(theme.textPrimary)
            }

            Spacer(minLength: 0)

            // MARK: - アクションボタン群
            HStack(spacing: 16) {
                Button("キャンセル", role: .cancel) {
                    // ユーザーが操作を取り消した場合はシートを閉じる
                    onCancel()
                }
                .buttonStyle(.bordered)

                Button(action.confirmationButtonTitle, role: action.buttonRole) {
                    // GameView 側で用意した実処理を実行する
                    onConfirm(action)
                }
                .buttonStyle(.borderedProminent)
            }
            // ボタン行を右寄せにして重要ボタンへ視線を誘導する
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        // iPad では余白を広めに確保し、モーダル全体が中央にまとまるようにする
        .padding(32)
        .frame(maxWidth: 520, alignment: .leading)
        .background(theme.backgroundElevated)
    }
}

// MARK: - メニュー操作の定義
private enum GameMenuAction: Hashable, Identifiable {
    case manualPenalty(penaltyCost: Int)
    case reset
    case returnToTitle

    /// Identifiable 準拠のための一意な ID
    var id: Int {
        switch self {
        case .manualPenalty(_):
            return 0
        case .reset:
            return 1
        case .returnToTitle:
            return 2
        }
    }

    /// ダイアログ内で表示するボタンタイトル
    var confirmationButtonTitle: String {
        switch self {
        case .manualPenalty(_):
            return "ペナルティを払う"
        case .reset:
            return "リセットする"
        case .returnToTitle:
            return "タイトルへ戻る"
        }
    }

    /// 操作説明として表示するメッセージ
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

    /// ボタンのロール（破壊的操作は .destructive を指定）
    var buttonRole: ButtonRole? {
        switch self {
        case .manualPenalty(_):
            return .destructive
        case .reset:
            return .destructive
        case .returnToTitle:
            return .destructive
        }
    }
}

/// ポーズメニュー本体。プレイ中によく調整する項目をリスト形式でまとめる
private struct PauseMenuView: View {
    /// カラーテーマを共有し、背景色やボタン色を統一する
    private var theme = AppTheme()
    /// プレイ再開ボタン押下時の処理
    let onResume: () -> Void
    /// リセット確定時の処理
    let onConfirmReset: () -> Void
    /// タイトルへ戻る確定時の処理
    let onConfirmReturnToTitle: () -> Void

    /// GameView 側から利用できるようアクセスレベルを内部公開にしたカスタムイニシャライザ
    /// - Parameters:
    ///   - onResume: ポーズ解除時に実行するクロージャ
    ///   - onConfirmReset: ゲームリセット確定時に実行するクロージャ
    ///   - onConfirmReturnToTitle: タイトル復帰確定時に実行するクロージャ
    /// - Note: `private struct` では自動生成イニシャライザが private になるため、ここで明示的に定義する
    init(
        onResume: @escaping () -> Void,
        onConfirmReset: @escaping () -> Void,
        onConfirmReturnToTitle: @escaping () -> Void
    ) {
        self.onResume = onResume
        self.onConfirmReset = onConfirmReset
        self.onConfirmReturnToTitle = onConfirmReturnToTitle
    }

    /// シートを閉じるための環境ディスミス
    @Environment(\.dismiss) private var dismiss
    /// テーマ設定の永続化キー
    @AppStorage("preferred_color_scheme") private var preferredColorSchemeRawValue: String = ThemePreference.system.rawValue
    /// ハプティクスのオン/オフ
    @AppStorage("haptics_enabled") private var hapticsEnabled: Bool = true
    /// ガイドモードのオン/オフ
    @AppStorage("guide_mode_enabled") private var guideModeEnabled: Bool = true
    /// 手札並び設定
    @AppStorage(HandOrderingStrategy.storageKey) private var handOrderingRawValue: String = HandOrderingStrategy.insertionOrder.rawValue

    /// 破壊的操作の確認用ステート
    @State private var pendingAction: PauseConfirmationAction?

    var body: some View {
        NavigationStack {
            List {
                // MARK: - プレイ再開ボタン
                Section {
                    Button {
                        // フルスクリーンカバーを閉じて直ちにプレイへ戻る
                        onResume()
                        dismiss()
                    } label: {
                        Label("プレイを再開", systemImage: "play.fill")
                    }
                    .accessibilityHint("ポーズを解除してゲームを続けます")
                }

                // MARK: - ゲーム設定セクション
                Section {
                    Picker(
                        "テーマ",
                        selection: Binding<ThemePreference>(
                            get: { ThemePreference(rawValue: preferredColorSchemeRawValue) ?? .system },
                            set: { preferredColorSchemeRawValue = $0.rawValue }
                        )
                    ) {
                        ForEach(ThemePreference.allCases) { preference in
                            Text(preference.displayName)
                                .tag(preference)
                        }
                    }

                    Toggle("ハプティクスを有効にする", isOn: $hapticsEnabled)
                    Toggle("ガイドモード（移動候補をハイライト）", isOn: $guideModeEnabled)

                    Picker(
                        "手札の並び順",
                        selection: Binding<HandOrderingStrategy>(
                            get: { HandOrderingStrategy(rawValue: handOrderingRawValue) ?? .insertionOrder },
                            set: { handOrderingRawValue = $0.rawValue }
                        )
                    ) {
                        ForEach(HandOrderingStrategy.allCases, id: \.self) { strategy in
                            Text(strategy.displayName)
                                .tag(strategy)
                        }
                    }
                } header: {
                    Text("ゲーム設定")
                } footer: {
                    Text("テーマやハプティクス、ガイド表示を素早く切り替えられます。これらの項目はタイトル画面の設定からも調整できます。")
                }

                // MARK: - 操作セクション
                Section {
                    Button(role: .destructive) {
                        pendingAction = .reset
                    } label: {
                        Label("ゲームをリセット", systemImage: "arrow.counterclockwise")
                    }

                    Button(role: .destructive) {
                        pendingAction = .returnToTitle
                    } label: {
                        Label("タイトルへ戻る", systemImage: "house")
                    }
                } header: {
                    Text("操作")
                } footer: {
                    Text("リセットやタイトル復帰は確認ダイアログを経由して実行します。")
                }

                // MARK: - 詳細設定についての案内
                Section {
                    Text("広告やプライバシー設定などの詳細はタイトル画面右上のギアアイコンから確認できます。")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } header: {
                    Text("詳細設定")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("ポーズ")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        onResume()
                        dismiss()
                    }
                }
            }
            .background(theme.backgroundPrimary)
        }
        // 破壊的操作の確認ダイアログ
        .confirmationDialog(
            "操作の確認",
            // item: バインディングが iOS 17 以降で非推奨となったため、
            // Bool バインディング + presenting の組み合わせで明示的に制御する
            isPresented: Binding(
                get: {
                    // pendingAction が存在する場合のみダイアログを表示
                    pendingAction != nil
                },
                set: { isPresented in
                    // ユーザー操作でダイアログが閉じられたら状態を初期化
                    if !isPresented {
                        pendingAction = nil
                    }
                }
            ),
            presenting: pendingAction
        ) { action in
            // 確認用の破壊的操作ボタン
            Button(action.confirmationButtonTitle, role: .destructive) {
                handleConfirmation(action)
            }
            // キャンセルボタンは常に閉じるだけで状態を破棄
            Button("キャンセル", role: .cancel) {
                pendingAction = nil
            }
        } message: { action in
            Text(action.message)
        }
    }

    /// 確認ダイアログで選ばれたアクションを実行する
    /// - Parameter action: ユーザーが確定した操作種別
    private func handleConfirmation(_ action: PauseConfirmationAction) {
        switch action {
        case .reset:
            onConfirmReset()
            dismiss()
        case .returnToTitle:
            onConfirmReturnToTitle()
            dismiss()
        }
        pendingAction = nil
    }

    /// ポーズメニュー内で扱う確認対象の列挙体
    private enum PauseConfirmationAction: Identifiable {
        case reset
        case returnToTitle

        var id: Int {
            switch self {
            case .reset: return 0
            case .returnToTitle: return 1
            }
        }

        var confirmationButtonTitle: String {
            switch self {
            case .reset: return "リセットする"
            case .returnToTitle: return "タイトルへ戻る"
            }
        }

        var message: String {
            switch self {
            case .reset:
                return "現在の進行状況を破棄して最初からやり直します。よろしいですか？"
            case .returnToTitle:
                return "ゲームを終了してタイトル画面へ戻ります。現在のプレイ内容は保存されません。"
            }
        }
    }
}

// MARK: - 手詰まりペナルティ用のバナー表示
/// ペナルティ発生をユーザーに伝えるトップバナーのビュー
private struct PenaltyBannerView: View {
    /// バナー配色を一元管理するテーマ
    private var theme = AppTheme()
    /// 今回加算されたペナルティ手数
    let penaltyAmount: Int

    /// GameView 側から利用しやすいように外部公開されたイニシャライザを明示的に定義
    /// - Parameter penaltyAmount: 今回のペナルティで増加した手数
    init(penaltyAmount: Int) {
        // `theme` はデフォルト値で初期化されるため代入不要。必要な値だけを受け取り保持する
        self.penaltyAmount = penaltyAmount
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // MARK: - 警告アイコン
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20, weight: .semibold))
                // テーマの反転色を利用し、背景とのコントラストを確保
                .foregroundColor(theme.penaltyIconForeground)
                .padding(8)
                .background(
                    Circle()
                        // アイコン背景もテーマ側のアクセントに合わせる
                        .fill(theme.penaltyIconBackground)
                )
                .accessibilityHidden(true)  // アイコンは視覚的アクセントのみ

            // MARK: - メッセージ本文
            VStack(alignment: .leading, spacing: 2) {
                Text(primaryMessage)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    // メインテキストはテーマに合わせた明度で表示
                    .foregroundColor(theme.penaltyTextPrimary)
                Text(secondaryMessage)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(theme.penaltyTextSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                // バナーの背景はテーマ設定で透明感を調整
                .fill(theme.penaltyBannerBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(theme.penaltyBannerBorder, lineWidth: 1)
                )
        )
        .shadow(color: theme.penaltyBannerShadow, radius: 18, x: 0, y: 12)
        .accessibilityIdentifier("penalty_banner_content")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    /// ペナルティ内容に応じたメインメッセージ
    private var primaryMessage: String {
        if penaltyAmount > 0 {
            return "手詰まり → 手札スロットを引き直し (+\(penaltyAmount))"
        } else {
            return "手札スロットを引き直しました (ペナルティなし)"
        }
    }

    /// ペナルティ内容に応じた補足メッセージ
    private var secondaryMessage: String {
        if penaltyAmount > 0 {
            return "使えるカードが無かったため、手数が \(penaltyAmount) 増加しました"
        } else {
            return "使えるカードが無かったため、手数の増加はありません"
        }
    }

    /// アクセシビリティ用の案内文
    private var accessibilityText: String {
        "\(primaryMessage)。\(secondaryMessage)"
    }
}

// MARK: - 先読みカード専用のオーバーレイ
/// 「NEXT」「NEXT+1」などのバッジを重ね、操作不可であることを視覚的に伝える補助ビュー
fileprivate struct NextCardOverlayView: View {
    /// 表示中のカードが何枚目の先読みか（0 が直近、1 以降は +1, +2 ...）
    let order: Int
    /// 先読みオーバーレイの配色を統一するテーマ
    private let theme = AppTheme()

    // MARK: - 初期化
    /// 先読みカードの表示順を受け取り、必要なステートを既定値で初期化する
    /// - Parameter order: 0 始まりでの先読み順序
    fileprivate init(order: Int) {
        self.order = order
    }

    /// バッジに表示する文言を算出するヘルパー
    private var badgeText: String {
        order == 0 ? "NEXT" : "NEXT+\(order)"
    }

    var body: some View {
        ZStack {
            // MARK: - 上部の NEXT バッジ
            VStack {
                HStack {
                    Text(badgeText)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        // テーマ経由でラベル色を取得し、ライトモードでも視認性を保つ
                        .foregroundColor(theme.nextBadgeText)
                        .background(
                            Capsule()
                                .strokeBorder(theme.nextBadgeBorder, lineWidth: 1)
                                .background(Capsule().fill(theme.nextBadgeBackground))
                        )
                        .padding([.top, .leading], 6)
                        .accessibilityHidden(true)  // バッジは視覚的強調のみなので読み上げ対象外にする
                    Spacer()
                }
                Spacer()
            }
        }
        .allowsHitTesting(false)  // 補助ビューはタップ処理に影響させない
    }
}

// MARK: - カード演出用の状態と PreferenceKey
/// カードが移動中かどうかを示すアニメーションフェーズ
private enum CardAnimationPhase: Equatable {
    case idle
    case movingToBoard
}

/// 手札・NEXT に配置されたカードのアンカーを UUID 単位で収集する PreferenceKey
private struct CardPositionPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: Anchor<CGRect>] = [:]

    static func reduce(value: inout [UUID: Anchor<CGRect>], nextValue: () -> [UUID: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// SpriteView（盤面）のアンカーを保持する PreferenceKey
private struct BoardAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

// MARK: - レイアウト定数と PreferenceKey
/// GeometryReader 内での盤面計算に利用する固定値をまとめて管理する
private enum LayoutMetrics {
    /// 盤面セクションと手札セクションの間隔（VStack の spacing と一致させる）
    static let spacingBetweenBoardAndHand: CGFloat = 16
    /// 統計バッジと盤面の間隔（boardSection 内の spacing と一致させる）
    static let spacingBetweenStatisticsAndBoard: CGFloat = 12
    /// 盤面の正方形サイズへ乗算する縮小率（カードへ高さを譲るため 92% に設定）
    static let boardScale: CGFloat = 0.92
    /// 統計や手札によって縦方向が埋まった際でも盤面が消失しないよう確保する下限サイズ
    static let minimumBoardFallbackSize: CGFloat = 220
    /// 統計バッジ領域の最低想定高さ。初回レイアウトで 0 が返っても盤面がはみ出さないよう保険を掛ける
    static let statisticsSectionFallbackHeight: CGFloat = 72
    /// 手札と先読みカードを含めた最低想定高さ。カード 2 段構成とテキストを見越したゆとりを確保する
    static let handSectionFallbackHeight: CGFloat = 220
    /// 手札カード同士の横方向スペース（カード拡大後も全体幅が収まるよう微調整）
    static let handCardSpacing: CGFloat = 10
    /// 手札カードの幅。MoveCardIllustrationView 側の定義と同期させてサイズ差異を防ぐ
    static let handCardWidth: CGFloat = MoveCardIllustrationView.defaultWidth
    /// 手札カードの高さ。幅との比率を保ちながら僅かに拡張する
    static let handCardHeight: CGFloat = MoveCardIllustrationView.defaultHeight
    /// 手札セクションの基本的な下パディング。iPhone での視認性を最優先する基準値
    static let handSectionBasePadding: CGFloat = 16
    /// セーフエリア分の領域に加えて確保したいバッファ。ホームインジケータ直上に余白を置く
    static let handSectionSafeAreaAdditionalPadding: CGFloat = 8
    /// レギュラー幅（主に iPad）で追加する下方向マージン。指の位置とタブバーが干渉しないよう余裕を持たせる
    static let handSectionRegularAdditionalBottomPadding: CGFloat = 24
    /// 盤面上部のコントロールバーをステータスバーと離すための基本マージン
    static let controlRowBaseTopPadding: CGFloat = 16
    /// ステータスバーの高さに応じて追加で確保したい上方向の余白
    static let controlRowSafeAreaAdditionalPadding: CGFloat = 8
    /// ペナルティバナーが画面端に貼り付かないようにするための基準上パディング
    static let penaltyBannerBaseTopPadding: CGFloat = 12
    /// safeAreaInsets.top に加算しておきたいペナルティバナーの追加上マージン
    static let penaltyBannerSafeAreaAdditionalPadding: CGFloat = 6
    /// レギュラー幅端末で safeAreaInsets.top が 0 の場合に用いるフォールバック値
    static let regularWidthTopSafeAreaFallback: CGFloat = 24
    /// レギュラー幅端末で safeAreaInsets.bottom が 0 の場合に用いるフォールバック値
    static let regularWidthBottomSafeAreaFallback: CGFloat = 20
}

/// 統計バッジ領域の高さを親ビューへ伝搬するための PreferenceKey
private struct StatisticsHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        // 毎フレームで統計領域の最新高さへ更新し、ジオメトリ変化に即応できるよう最大値ではなく直近の値を採用する
        value = nextValue()
    }
}

/// 手札セクションの高さを親ビューへ伝搬するための PreferenceKey
private struct HandSectionHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        // 手札レイアウトのジオメトリ変化へ滑らかに追従するため、最大値の保持ではなく常に最新高さへ更新する
        value = nextValue()
    }
}

/// 任意の PreferenceKey へ高さを伝搬するゼロサイズのオーバーレイ
/// - Note: GeometryReader を直接レイアウトへ配置すると親ビューいっぱいまで広がり、想定外の値になるため
///         あえて Color.clear を 0 サイズへ縮めて高さだけを測定する
private struct HeightPreferenceReporter<Key: PreferenceKey>: View where Key.Value == CGFloat {
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .frame(width: 0, height: 0)
                .preference(key: Key.self, value: proxy.size.height)
        }
        .allowsHitTesting(false)  // あくまでレイアウト取得用のダミービューなので操作対象から除外する
    }
}

// MARK: - プレビュー
#Preview {
    // Xcode の Canvas で GameView を表示するためのプレビュー
    GameView()
}
