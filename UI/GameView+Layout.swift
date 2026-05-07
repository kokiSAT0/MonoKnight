import Game
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
            if viewModel.progress == .awaitingSpawn, isSpawnSelectionHintVisible {
                spawnSelectionBanner
                    .padding(Edge.Set.horizontal, 20)
                    .padding(.top, spawnSelectionBannerTopPadding(using: layoutContext))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .zIndex(1)
            }
            if let pendingChoice = viewModel.pendingDungeonPickupChoice {
                DungeonPickupChoiceOverlayView(
                    theme: theme,
                    choice: pendingChoice,
                    onDiscardPickup: {
                        viewModel.discardPendingDungeonPickupCard()
                    },
                    onDiscardExisting: { playable in
                        viewModel.replaceDungeonInventoryEntryForPendingPickup(discarding: playable)
                    }
                )
                .transition(.opacity)
                .zIndex(3)
            }
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

    /// スポーン位置選択中に盤面へ重ねて表示する案内バナー
    var spawnSelectionBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("開始マスを選択")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Text("手札、先読み、目的地を確認してから、目的地以外のマスをタップしてください。")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)
            Button {
                isSpawnSelectionHintVisible = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(theme.textSecondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("spawn_selection_banner_close_button")
            .accessibilityLabel(Text("開始位置の案内を閉じる"))
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("spawn_selection_banner")
        .accessibilityLabel(Text("開始位置を選択してください。手札、次のカード、目的地を見てから、目的地以外のマスをタップできます。"))
    }

    /// 開始位置案内を盤面上部に重ねるための上余白
    func spawnSelectionBannerTopPadding(using layoutContext: GameViewLayoutContext) -> CGFloat {
        layoutContext.controlRowTopPadding
            + layoutContext.resolvedStatisticsHeight
            + GameViewLayoutMetrics.spacingBetweenStatisticsAndBoard
            + 12
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
                if let banner = viewModel.activePenaltyBanner {
                    HStack {
                        Spacer(minLength: 0)
                        PenaltyBannerView(event: banner)
                            .padding(Edge.Set.horizontal, 20)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .accessibilityIdentifier("penalty_banner")
                            .allowsHitTesting(false)
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
                            .allowsHitTesting(false)
                        Spacer(minLength: 0)
                    }
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, resolvedTopPadding)
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

struct DungeonPickupChoiceOverlayView: View {
    let theme: AppTheme
    let choice: PendingDungeonPickupChoice
    let onDiscardPickup: () -> Void
    let onDiscardExisting: (PlayableCard) -> Void

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 96, maximum: 128), spacing: 10, alignment: .top)]
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                VStack(spacing: 4) {
                    Text("手札がいっぱいです")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(theme.textPrimary)
                    Text("拾ったカードか、手札の 1 種類を選んで捨てます")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(theme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        pickupChoiceButton
                        ForEach(Array(choice.discardCandidates.enumerated()), id: \.element.id) { index, entry in
                            existingChoiceButton(entry: entry, index: index)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 330)
            }
            .padding(14)
            .frame(maxWidth: 560)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(theme.spawnOverlayBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(theme.spawnOverlayBorder, lineWidth: 1)
                    )
            )
            .shadow(color: theme.spawnOverlayShadow, radius: 20, x: 0, y: 10)
            .padding(.horizontal, 18)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dungeon_pickup_choice_overlay")
    }

    private var pickupChoiceButton: some View {
        Button(action: onDiscardPickup) {
            DungeonPickupChoiceCardView(
                theme: theme,
                playable: .move(choice.pickup.card),
                uses: choice.pickup.uses,
                badgeText: "拾ったカード",
                actionText: "取得しない",
                isPickupCandidate: true
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("dungeon_pickup_choice_discard_new")
        .accessibilityLabel(Text("拾ったカード、\(choice.pickup.card.displayName)、取得しない"))
    }

    private func existingChoiceButton(entry: DungeonInventoryEntry, index: Int) -> some View {
        Button {
            onDiscardExisting(entry.playable)
        } label: {
            DungeonPickupChoiceCardView(
                theme: theme,
                playable: entry.playable,
                uses: entry.totalUses,
                badgeText: "手札",
                actionText: "この種類を捨てる",
                isPickupCandidate: false
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("dungeon_pickup_choice_discard_existing_\(index)")
        .accessibilityLabel(Text("手札、\(entry.playable.displayName)、残り \(entry.totalUses)、この種類を捨てる"))
    }
}

private struct DungeonPickupChoiceCardView: View {
    let theme: AppTheme
    let playable: PlayableCard
    let uses: Int
    let badgeText: String
    let actionText: String
    let isPickupCandidate: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text(badgeText)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(isPickupCandidate ? theme.accentOnPrimary : theme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(isPickupCandidate ? theme.accentPrimary : theme.cardBackgroundNext)
                )

            cardArtwork
                .scaleEffect(0.86)
                .frame(width: 76, height: 104)

            Text(playable.displayName)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text("残り \(uses)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(theme.textSecondary)

            Text(actionText)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(isPickupCandidate ? theme.textSecondary : theme.accentPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(8)
        .frame(width: 104)
        .frame(minHeight: 178)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.cardBackgroundHand)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isPickupCandidate ? theme.accentPrimary.opacity(0.65) : theme.cardBorderHand, lineWidth: 1.5)
                )
        )
    }

    @ViewBuilder
    private var cardArtwork: some View {
        if let move = playable.move {
            MoveCardIllustrationView(card: move, mode: .hand)
        } else if let support = playable.support {
            SupportPickupChoiceIllustrationView(card: support, theme: theme)
        }
    }
}

private struct SupportPickupChoiceIllustrationView: View {
    let card: SupportCard
    let theme: AppTheme

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbolName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(theme.accentPrimary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(theme.accentPrimary.opacity(0.14)))

            Text(card.displayName)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(theme.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)

            Text("補助")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(theme.textSecondary)
        }
        .padding(8)
        .frame(width: MoveCardIllustrationView.defaultWidth, height: MoveCardIllustrationView.defaultHeight)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.cardBackgroundHand)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(theme.cardBorderHand, lineWidth: 1.5)
                )
        )
    }

    private var symbolName: String {
        switch card {
        case .nextRefresh:
            return "arrow.triangle.2.circlepath"
        case .swapOne:
            return "arrow.left.arrow.right"
        case .guidance:
            return "scope"
        case .refillEmptySlots:
            return "square.grid.3x3.fill"
        }
    }
}
