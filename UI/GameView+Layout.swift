import SpriteKit
import SwiftUI

// MARK: - レイアウト構築に関する補助実装
@MainActor
extension GameView {
    /// GeometryReader 内部のレイアウト調整と描画処理をまとめたメインコンテンツ
    /// - Parameter geometry: 外側から渡される GeometryProxy（親ビューのサイズや安全領域を把握するために利用）
    /// - Returns: レイアウト計算結果を反映したゲームプレイ画面全体のビュー階層
    @ViewBuilder
    func mainContent(for geometry: GeometryProxy) -> some View {
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

    /// 盤面の統計と SpriteKit ボードをまとめて描画する
    /// - Parameter width: GeometryReader で算出した盤面の幅（正方形表示の基準）
    /// - Returns: 統計バッジと SpriteView を縦に並べた領域
    func boardSection(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: GameViewLayoutMetrics.spacingBetweenStatisticsAndBoard) {
            GameBoardControlRowView(
                theme: theme,
                viewModel: viewModel
            )
            spriteBoard(width: width)
                // 任意スポーン待機時でも盤面全体を常時見せ、ガイドは上部バナーへ退避させる
                // 盤面縮小で生まれた余白を均等にするため、中央寄せで描画する
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    /// SpriteKit の盤面を描画し、ライフサイクルに応じた更新処理をまとめる
    /// - Parameter width: 正方形に保つための辺長
    /// - Returns: onAppear / onReceive を含んだ SpriteView
    func spriteBoard(width: CGFloat) -> some View {
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

    /// スポーン位置選択中にトップ通知スタックへ表示する案内バナー
    var spawnSelectionBanner: some View {
        // トップバナーと整合するサイズ感に調整し、通知スタックへ積めるようにする
        VStack(alignment: .leading, spacing: 6) {
            Text("開始マスを選択")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            Text("手札スロットと先読みを確認してから、好きなマスをタップしてください。")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .multilineTextAlignment(.leading)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(theme.spawnOverlayBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(theme.spawnOverlayBorder, lineWidth: 1)
                )
        )
        .shadow(color: theme.spawnOverlayShadow, radius: 20, x: 0, y: 10)
        .foregroundColor(theme.textPrimary)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("spawn_selection_banner")
        .accessibilityLabel(Text("開始位置を選択してください。手札スロットと次のカードを見てから任意のマスをタップできます。"))
    }

    /// 手詰まりペナルティを知らせるバナーのレイヤーを構成
    func penaltyBannerOverlay(contentTopInset: CGFloat) -> some View {
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
        let stackSpacing = GameViewLayoutMetrics.notificationStackSpacing

        return VStack {
            VStack(spacing: stackSpacing) {
                if viewModel.progress == .awaitingSpawn {
                    // スポーン選択を促す案内を最優先で表示し、ユーザーの視線が最短距離で届くよう中央寄せする
                    HStack {
                        Spacer(minLength: 0)
                        spawnSelectionBanner
                            .padding(Edge.Set.horizontal, 20)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        Spacer(minLength: 0)
                    }
                }

                if let banner = viewModel.activePenaltyBanner {
                    HStack {
                        Spacer(minLength: 0)
                        PenaltyBannerView(event: banner)
                            .padding(Edge.Set.horizontal, 20)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .accessibilityIdentifier("penalty_banner")
                        Spacer(minLength: 0)
                    }
                }

                if let phaseMessage = viewModel.cardSelectionPhaseMessage {
                    HStack {
                        Spacer(minLength: 0)
                        CardSelectionPhaseToastView(theme: theme, message: phaseMessage)
                            .padding(Edge.Set.horizontal, 24)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .accessibilityIdentifier("card_selection_phase_toast")
                        Spacer(minLength: 0)
                    }
                }

                if let warning = viewModel.boardTapSelectionWarning {
                    // 同一点へ移動可能なカード競合を知らせるトーストを積み重ね、視線移動を最小限に抑える
                    HStack {
                        Spacer(minLength: 0)
                        BoardTapSelectionWarningToastView(theme: theme, message: warning.message)
                            .padding(Edge.Set.horizontal, 24)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .accessibilityIdentifier("board_tap_warning_toast")
                        Spacer(minLength: 0)
                    }
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, resolvedTopPadding)
        .allowsHitTesting(false)  // バナーやトーストが表示されていても下の UI を操作可能にする
        .zIndex(2)
    }


    /// レイアウトに関する最新の実測値をログに残すための不可視ビューを生成
    /// - Parameter context: GeometryReader から抽出したレイアウト情報コンテキスト
    /// - Returns: 画面上には表示されない監視用ビュー
    func layoutDiagnosticOverlay(using context: GameViewLayoutContext) -> some View {
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
}
