import Combine  // 経過時間更新で Combine のタイマーパブリッシャを活用するため読み込む
import Game  // GameCore や DealtCard、手札並び設定を利用するためゲームロジックモジュールを読み込む
import SharedSupport // debugLog / debugError を利用するため共有ターゲットを追加
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
    /// View とロジックの橋渡しを担う ViewModel
    @StateObject private var viewModel: GameViewModel
    /// SpriteKit との仲介を担う BoardBridge
    @ObservedObject private var boardBridge: GameBoardBridgeViewModel
    /// ハプティクスを有効にするかどうかの設定値
    @AppStorage("haptics_enabled") private var hapticsEnabled: Bool = true
    /// ガイドモードのオン/オフを永続化し、盤面ハイライト表示を制御する
    @AppStorage("guide_mode_enabled") private var guideModeEnabled: Bool = true
    /// 手札の並び替え方式。設定変更時に GameCore へ伝搬する
    @AppStorage(HandOrderingStrategy.storageKey) private var handOrderingRawValue: String = HandOrderingStrategy.insertionOrder.rawValue
    /// 手札や NEXT の位置をマッチングさせるための名前空間
    @Namespace private var cardAnimationNamespace
    /// ViewModel が管理する GameCore へのアクセスを簡潔にするための計算プロパティ
    private var core: GameCore { viewModel.core }
    /// SpriteKit シーンへのショートカット
    private var scene: GameScene { boardBridge.scene }

    /// デフォルトのサービスを利用して `GameView` を生成するコンビニエンスイニシャライザ
    /// - Parameters:
    ///   - mode: 表示したいゲームモード
    ///   - gameInterfaces: GameCore 生成を担当するファクトリセット（省略時は `.live`）
    ///   - onRequestReturnToTitle: タイトル画面への遷移要求クロージャ（省略可）
    init(
        mode: GameMode = .standard,
        gameInterfaces: GameModuleInterfaces = .live,
        onRequestReturnToTitle: (() -> Void)? = nil
    ) {
        self.init(
            mode: mode,
            gameInterfaces: gameInterfaces,
            gameCenterService: GameCenterService.shared,
            adsService: AdsService.shared,
            onRequestReturnToTitle: onRequestReturnToTitle
        )
    }

    /// 初期化で ViewModel を組み立て、GameCore と GameScene を橋渡しする
    init(
        mode: GameMode,
        gameInterfaces: GameModuleInterfaces,
        gameCenterService: GameCenterServiceProtocol,
        adsService: AdsServiceProtocol,
        onRequestReturnToTitle: (() -> Void)? = nil
    ) {
        let viewModel = GameViewModel(
            mode: mode,
            gameInterfaces: gameInterfaces,
            gameCenterService: gameCenterService,
            adsService: adsService,
            onRequestReturnToTitle: onRequestReturnToTitle
        )

        if let savedValue = UserDefaults.standard.string(forKey: HandOrderingStrategy.storageKey) {
            viewModel.restoreHandOrderingStrategy(from: savedValue)
        }

        _viewModel = StateObject(wrappedValue: viewModel)
        _boardBridge = ObservedObject(wrappedValue: viewModel.boardBridge)
    }

    var body: some View {
        applyGameViewObservers(to:
            GeometryReader { geometry in
                // 専用メソッドへ委譲し、レイアウト計算と描画処理の責務を明示的に分離する
                mainContent(for: geometry)
            }
        )
        // ポーズメニューをフルスクリーンで重ね、端末サイズに左右されずに全項目を視認できるようにする
        .fullScreenCover(isPresented: $viewModel.isPauseMenuPresented) {
            PauseMenuView(
                onResume: {
                    // フルスクリーンカバーを閉じてプレイへ戻る
                    viewModel.isPauseMenuPresented = false
                },
                onConfirmReset: {
                    // リセット確定後はフルスクリーンカバーを閉じてから共通処理を呼び出す
                    viewModel.isPauseMenuPresented = false
                    performMenuAction(.reset)
                },
                onConfirmReturnToTitle: {
                    // タイトル復帰時もポーズメニューを閉じてから処理を実行する
                    viewModel.isPauseMenuPresented = false
                    performMenuAction(.returnToTitle)
                }
            )
        }
        // シートで結果画面を表示
        .sheet(isPresented: $viewModel.showingResult) {
            ResultView(
                moveCount: core.moveCount,
                penaltyCount: core.penaltyCount,
                elapsedSeconds: core.elapsedSeconds,
                modeIdentifier: viewModel.mode.identifier,
                onRetry: {
                    // ViewModel 側でリセットと広告フラグの再設定をまとめて処理する
                    viewModel.handleResultRetry()
                },
                gameCenterService: viewModel.gameCenterService,
                adsService: viewModel.adsService
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
                    // performMenuAction 内でも viewModel.pendingMenuAction を破棄しているが、
                    // 明示的に nil を代入しておくことでバインディング由来のシート閉鎖と状態初期化を二重に保証する
                    performMenuAction(confirmedAction)
                    viewModel.pendingMenuAction = nil
                },
                onCancel: {
                    // キャンセル時はダイアログと同じ挙動になるように viewModel.pendingMenuAction を破棄する
                    viewModel.pendingMenuAction = nil
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
                    horizontalSizeClass != .regular && viewModel.pendingMenuAction != nil
                },
                set: { isPresented in
                    // キャンセル操作で閉じられた場合もステートを初期化する
                    if !isPresented {
                        viewModel.pendingMenuAction = nil
                    }
                }
            ),
            presenting: viewModel.pendingMenuAction
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
        let layoutCalculator = GameViewLayoutCalculator(
            geometry: geometry,
            horizontalSizeClass: horizontalSizeClass,
            topOverlayHeight: topOverlayHeight,
            baseTopSafeAreaInset: baseTopSafeAreaInset,
            statisticsHeight: viewModel.statisticsHeight,
            handSectionHeight: viewModel.handSectionHeight
        )
        let layoutContext = layoutCalculator.makeContext()
        // 監視用の不可視オーバーレイも先に生成し、View ビルダー内でのネストを浅く保つ
        let diagnosticsOverlay = layoutDiagnosticOverlay(using: layoutContext)

        ZStack(alignment: .top) {
            VStack(spacing: GameViewLayoutMetrics.spacingBetweenBoardAndHand) {
                boardSection(width: layoutContext.boardWidth)
                GameHandSectionView(
                    theme: theme,
                    viewModel: viewModel,
                    boardBridge: boardBridge,
                    cardAnimationNamespace: cardAnimationNamespace,
                    handSlotCount: handSlotCount,
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
                let previousHeight = viewModel.statisticsHeight
                guard previousHeight != newHeight else { return }
                debugLog("GameView.viewModel.statisticsHeight 更新: 旧値=\(previousHeight), 新値=\(newHeight)")
                viewModel.statisticsHeight = newHeight
            }
            .onPreferenceChange(HandSectionHeightPreferenceKey.self) { newHeight in
                // 手札セクションの高さ変化も逐次観測し、ホームインジケータ付近での余白不足を切り分けられるようにする
                let previousHeight = viewModel.handSectionHeight
                guard previousHeight != newHeight else { return }
                debugLog("GameView.viewModel.handSectionHeight 更新: 旧値=\(previousHeight), 新値=\(newHeight)")
                viewModel.handSectionHeight = newHeight
            }
            // 盤面 SpriteView のアンカー更新を監視し、アニメーションの移動先として保持
            .onPreferenceChange(BoardAnchorPreferenceKey.self) { anchor in
                viewModel.updateBoardAnchor(anchor)
            }
            // 初回表示時に SpriteKit の背景色もテーマに合わせて更新
            .onAppear {
                viewModel.prepareForAppear(
                    colorScheme: colorScheme,
                    guideModeEnabled: guideModeEnabled,
                    hapticsEnabled: hapticsEnabled,
                    handOrderingStrategy: resolveHandOrderingStrategy()
                )
            }
            // ライト/ダーク切り替えが発生した場合も SpriteKit 側へ反映
            .onChange(of: colorScheme) { _, newScheme in
                viewModel.applyScenePalette(for: newScheme)
                // カラースキーム変更時はガイドの色味も再描画して視認性を確保
                viewModel.refreshGuideHighlights()
            }
            // 手札の並び設定が変わったら即座にゲームロジックへ伝え、UI の並びも更新する
            .onChange(of: handOrderingRawValue) { _, _ in
                viewModel.applyHandOrderingStrategy(rawValue: handOrderingRawValue)
            }
            // ガイドモードのオン/オフを切り替えたら即座に ViewModel 側へ委譲する
            .onChange(of: guideModeEnabled) { _, isEnabled in
                viewModel.updateGuideMode(enabled: isEnabled)
            }
            // ハプティクス設定が切り替わった際も ViewModel へ伝え、サービス呼び出しを統一する
            .onChange(of: hapticsEnabled) { _, isEnabled in
                viewModel.updateHapticsSetting(isEnabled: isEnabled)
            }
            // 経過時間を 1 秒ごとに再計算し、リアルタイム表示へ反映
            .onReceive(viewModel.elapsedTimer) { _ in
                viewModel.updateDisplayedElapsedTime()
            }
            // カードが盤面へ移動中は UI 全体を操作不可とし、状態の齟齬を防ぐ
            .disabled(boardBridge.animatingCard != nil)
            // Preference から取得したアンカー情報を用いて、カードが盤面中央へ吸い込まれる演出を重ねる
            .overlayPreferenceValue(CardPositionPreferenceKey.self) { anchors in
                GameCardAnimationOverlay(
                    anchors: anchors,
                    boardBridge: boardBridge,
                    core: core,
                    cardAnimationNamespace: cardAnimationNamespace
                )
            }
    }

    /// レギュラー幅（iPad）向けにシート表示へ切り替えるためのバインディング
    /// - Returns: iPad では viewModel.pendingMenuAction を返し、それ以外では常に nil を返すバインディング
    private var regularWidthPendingActionBinding: Binding<GameMenuAction?> {
        Binding(
            get: {
                // 横幅が十分でない場合はシート表示を抑制し、確認ダイアログ側に処理を委ねる
                guard horizontalSizeClass == .regular else {
                    return nil
                }
                return viewModel.pendingMenuAction
            },
            set: { newValue in
                // シートを閉じたときに SwiftUI から nil が渡されるため、そのまま状態へ反映しておく
                viewModel.pendingMenuAction = newValue
            }
        )
    }

    /// 盤面の統計と SpriteKit ボードをまとめて描画する
    /// - Parameter width: GeometryReader で算出した盤面の幅（正方形表示の基準）
    /// - Returns: 統計バッジと SpriteView を縦に並べた領域
    private func boardSection(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: GameViewLayoutMetrics.spacingBetweenStatisticsAndBoard) {
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
                value: formattedElapsedTime(viewModel.displayedElapsedSeconds),
                accessibilityLabel: "経過時間",
                accessibilityValue: accessibilityElapsedTimeDescription(viewModel.displayedElapsedSeconds)
            )

            // 総合スコアはリアルタイムで計算した値を表示し、結果画面で確定値と一致させる
            statisticBadge(
                title: "総合スコア",
                value: "\(viewModel.displayedScore)",
                accessibilityLabel: "総合スコア",
                accessibilityValue: accessibilityScoreDescription(viewModel.displayedScore)
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
                // BoardBridge 側で SpriteKit シーンと GameCore の同期をまとめて実施
                boardBridge.configureSceneOnAppear(width: width)
            }
            // ジオメトリの変化に追従できるよう、SpriteKit シーンのサイズも都度更新する
            .onChange(of: width) { _, newWidth in
                boardBridge.updateSceneSize(to: newWidth)
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

    /// 手動ペナルティ（手札引き直し）のショートカットボタン
    /// - Note: 統計バッジの右側に円形アイコンとして配置し、盤面上部の横並びレイアウトに収める
    private var manualPenaltyButton: some View {
        // ゲームが進行中でない場合は無効化し、リザルト表示中などの誤操作を回避
        let isDisabled = core.progress != .playing

        return Button {
            // 実行前に必ず確認ダイアログを挟むため、既存のメニューアクションを再利用
            viewModel.pendingMenuAction = .manualPenalty(penaltyCost: core.mode.manualRedrawPenaltyCost)
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
        // contentTopInset が 0 でも GameViewLayoutMetrics.penaltyBannerBaseTopPadding だけは必ず確保し、
        // 非ゼロのインセットが得られた場合は追加マージンを加えて矢印付きダイアログとの干渉を避ける。
        let resolvedTopPadding = max(
            GameViewLayoutMetrics.penaltyBannerBaseTopPadding,
            contentTopInset + GameViewLayoutMetrics.penaltyBannerSafeAreaAdditionalPadding
        )

        return VStack {
            if viewModel.isShowingPenaltyBanner {
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

    /// レイアウトに関する最新の実測値をログに残すための不可視ビューを生成
    /// - Parameter context: GeometryReader から抽出したレイアウト情報コンテキスト
    /// - Returns: 画面上には表示されない監視用ビュー
    private func layoutDiagnosticOverlay(using context: GameViewLayoutContext) -> some View {
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
        if viewModel.lastLoggedLayoutSnapshot == snapshot { return }
        viewModel.lastLoggedLayoutSnapshot = snapshot

        // 盤面縮小ロジックのどこで値が想定外になっているか突き止められるよう、多段の詳細ログを整形して出力する
        let message = """
        GameView.layout 観測: 理由=\(reason)
          geometry=\(snapshot.geometrySize)
          safeArea(rawTop=\(snapshot.rawTopInset), baseTop=\(snapshot.baseTopSafeAreaInset), rawBottom=\(snapshot.rawBottomInset), resolvedTop=\(snapshot.resolvedTopInset), overlayAdjustedTop=\(snapshot.overlayAdjustedTopInset), resolvedBottom=\(snapshot.resolvedBottomInset), fallbackTop=\(snapshot.usedTopSafeAreaFallback), fallbackBottom=\(snapshot.usedBottomSafeAreaFallback), overlayTop=\(snapshot.topOverlayHeight))
          sections(statistics=\(snapshot.statisticsHeight), resolvedStatistics=\(snapshot.resolvedStatisticsHeight), hand=\(snapshot.handSectionHeight), resolvedHand=\(snapshot.resolvedHandSectionHeight))
          paddings(controlTop=\(snapshot.controlRowTopPadding), handBottom=\(snapshot.handSectionBottomPadding), regularExtra=\(snapshot.regularAdditionalBottomPadding))
          fallbacks(statistics=\(snapshot.usedStatisticsFallback), hand=\(snapshot.usedHandSectionFallback), topSafeArea=\(snapshot.usedTopSafeAreaFallback), bottomSafeArea=\(snapshot.usedBottomSafeAreaFallback))
          boardBases(horizontal=\(snapshot.horizontalBoardBase), vertical=\(snapshot.verticalBoardBase), resolved=\(snapshot.boardBaseSize)) availableHeight=\(snapshot.availableHeight) boardScale=\(GameViewLayoutMetrics.boardScale) boardWidth=\(snapshot.boardWidth)
        """

        debugLog(message)

        if snapshot.availableHeight <= 0 || snapshot.boardWidth <= 0 {
            // 盤面がゼロサイズになる条件を明確化するため、異常時は追加で警告ログを残す
            debugLog(
                "GameView.layout 警告: availableHeight=\(snapshot.availableHeight), horizontalBase=\(snapshot.horizontalBoardBase), verticalBase=\(snapshot.verticalBoardBase), boardBase=\(snapshot.boardBaseSize), boardWidth=\(snapshot.boardWidth)"
            )
        }
    }

}

/// GameViewLayoutContext から BoardLayoutSnapshot を組み立てるための補助イニシャライザ
/// - Note: GameView 内部のみで利用するためアクセスレベルは private extension とする
private extension BoardLayoutSnapshot {
    init(context: GameViewLayoutContext) {
        // GeometryReader から取得した実測値を丸ごとコピーし、ViewModel からも参照できる形へ変換
        self.init(
            geometrySize: context.geometrySize,
            availableHeight: context.availableHeightForBoard,
            horizontalBoardBase: context.horizontalBoardBase,
            verticalBoardBase: context.verticalBoardBase,
            boardBaseSize: context.boardBaseSize,
            boardWidth: context.boardWidth,
            rawTopInset: context.rawTopInset,
            rawBottomInset: context.rawBottomInset,
            baseTopSafeAreaInset: context.baseTopSafeAreaInset,
            resolvedTopInset: context.topInset,
            overlayAdjustedTopInset: context.overlayAdjustedTopInset,
            resolvedBottomInset: context.bottomInset,
            statisticsHeight: context.statisticsHeight,
            resolvedStatisticsHeight: context.resolvedStatisticsHeight,
            handSectionHeight: context.handSectionHeight,
            resolvedHandSectionHeight: context.resolvedHandSectionHeight,
            regularAdditionalBottomPadding: context.regularAdditionalBottomPadding,
            handSectionBottomPadding: context.handSectionBottomPadding,
            usedTopSafeAreaFallback: context.usedTopFallback,
            usedBottomSafeAreaFallback: context.usedBottomFallback,
            usedStatisticsFallback: context.usedStatisticsFallback,
            usedHandSectionFallback: context.usedHandSectionFallback,
            controlRowTopPadding: context.controlRowTopPadding,
            topOverlayHeight: context.topOverlayHeight
        )
    }
}

private extension GameView {
    /// AppStorage から読み出した文字列を安全に列挙体へ変換する
    /// - Returns: 有効な設定値。未知の値は従来方式へフォールバックする
    func resolveHandOrderingStrategy() -> HandOrderingStrategy {
        HandOrderingStrategy(rawValue: handOrderingRawValue) ?? .insertionOrder
    }
}

// MARK: - カード移動演出用オーバーレイ
/// SpriteView と手札スロットの間を移動するカードのアニメーションを担当する補助ビュー
/// - Note: GameView 本体のメソッドから切り出し、責務を明確にして可読性を高める。
private struct GameCardAnimationOverlay: View {
    /// 手札側で計測したアンカー情報の辞書
    let anchors: [UUID: Anchor<CGRect>]
    /// SpriteKit との橋渡しを担う ViewModel
    @ObservedObject var boardBridge: GameBoardBridgeViewModel
    /// 現在のゲーム状態。駒位置や盤面サイズを参照する
    let core: GameCore
    /// MatchedGeometryEffect の名前空間
    let cardAnimationNamespace: Namespace.ID

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.clear
                overlayContent(using: proxy)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// GeometryProxy を用いてカードの移動演出を構築する
    /// - Parameter proxy: 手札・盤面それぞれの CGRect を解決するための GeometryProxy
    @ViewBuilder
    private func overlayContent(using proxy: GeometryProxy) -> some View {
        if let animatingCard = boardBridge.animatingCard,
           let sourceAnchor = anchors[animatingCard.id],
           let boardAnchor = boardBridge.boardAnchor,
           let targetGridPoint = boardBridge.animationTargetGridPoint ?? core.current,
           boardBridge.animationState != .idle || boardBridge.hiddenCardIDs.contains(animatingCard.id) {
            let cardFrame = proxy[sourceAnchor]
            let boardFrame = proxy[boardAnchor]
            let startCenter = CGPoint(x: cardFrame.midX, y: cardFrame.midY)
            let boardDestination = Self.boardCoordinate(
                for: targetGridPoint,
                boardSize: core.board.size,
                in: boardFrame
            )

            MoveCardIllustrationView(card: animatingCard.move)
                .matchedGeometryEffect(id: animatingCard.id, in: cardAnimationNamespace)
                .frame(width: cardFrame.width, height: cardFrame.height)
                .position(boardBridge.animationState == .movingToBoard ? boardDestination : startCenter)
                .scaleEffect(boardBridge.animationState == .movingToBoard ? 0.55 : 1.0)
                .opacity(boardBridge.animationState == .movingToBoard ? 0.0 : 1.0)
                .allowsHitTesting(false)
        }
    }

    /// 盤面座標を SwiftUI 座標系へ変換し、MatchedGeometryEffect の移動先を算出する
    /// - Parameters:
    ///   - gridPoint: 盤面上のマス座標（原点は左下）
    ///   - boardSize: 現在の盤面一辺サイズ
    ///   - frame: SwiftUI における盤面矩形
    /// - Returns: SwiftUI 座標系での中心位置
    private static func boardCoordinate(for gridPoint: GridPoint, boardSize: Int, in frame: CGRect) -> CGPoint {
        // 盤面サイズが 0 以下になることは想定していないが、安全のため 1 以上へ補正する
        let safeBoardSize = max(1, boardSize)
        let tileLength = frame.width / CGFloat(safeBoardSize)
        let centerX = frame.minX + tileLength * (CGFloat(gridPoint.x) + 0.5)
        // SwiftUI 座標では上方向がマイナス値となるため、盤面上端からの距離で算出する
        let centerY = frame.maxY - tileLength * (CGFloat(gridPoint.y) + 0.5)
        return CGPoint(x: centerX, y: centerY)
    }
}

// MARK: - コントロールバーの操作要素
private extension GameView {
    /// ゲームを一時停止して各種設定やリセット操作をまとめて案内するボタン
    private var pauseButton: some View {
        Button {
            debugLog("GameView: ポーズメニュー表示要求")
            viewModel.isPauseMenuPresented = true
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

    /// メニュー操作を実際に実行する共通処理
    /// - Parameter action: ユーザーが選択した操作種別
    private func performMenuAction(_ action: GameMenuAction) {
        viewModel.performMenuAction(action)
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

// MARK: - カード演出用の状態と PreferenceKey
/// 手札・NEXT に配置されたカードのアンカーを UUID 単位で収集する PreferenceKey
/// - Note: `GameHandSectionView` からも参照するためファイル外からアクセス可能にしている。
struct CardPositionPreferenceKey: PreferenceKey {
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
/// 統計バッジ領域の高さを親ビューへ伝搬するための PreferenceKey
private struct StatisticsHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        // 毎フレームで統計領域の最新高さへ更新し、ジオメトリ変化に即応できるよう最大値ではなく直近の値を採用する
        value = nextValue()
    }
}

/// 手札セクションの高さを親ビューへ伝搬するための PreferenceKey
/// - Note: 手札専用ビューでも利用するため internal 扱いとする。
struct HandSectionHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        // 手札レイアウトのジオメトリ変化へ滑らかに追従するため、最大値の保持ではなく常に最新高さへ更新する
        value = nextValue()
    }
}

/// 任意の PreferenceKey へ高さを伝搬するゼロサイズのオーバーレイ
/// - Note: GeometryReader を直接レイアウトへ配置すると親ビューいっぱいまで広がり、想定外の値になるため
///         あえて Color.clear を 0 サイズへ縮めて高さだけを測定する。
///         `GameHandSectionView` からも再利用するため internal 扱いとする。
struct HeightPreferenceReporter<Key: PreferenceKey>: View where Key.Value == CGFloat {
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
