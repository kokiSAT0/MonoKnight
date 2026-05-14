import SwiftUI  // SwiftUI の View/Geometry を利用するため読み込む
import Game  // GameCore / HandStack などゲームロジックの型を参照するため読み込む

/// GameView から切り出した手札+NEXT 表示専用ビュー
/// - Note: View 本体の肥大化を防ぎ、UI レイヤーの責務を細分化することで保守性を高める。
struct GameHandSectionView: View {
    /// 共通のテーマ配色
    let theme: AppTheme
    /// ゲーム状態を管理する ViewModel
    @ObservedObject var viewModel: GameViewModel
    /// SpriteKit との橋渡しを担う ViewModel
    @ObservedObject var boardBridge: GameBoardBridgeViewModel
    /// 手札カードと盤面アニメーションを同期させるための名前空間
    let cardAnimationNamespace: Namespace.ID
    /// 手札スロットの固定数（5 種類分の枠を常に確保する）
    let handSlotCount: Int
    /// 現在のデバイスが持つ下方向セーフエリア
    let bottomInset: CGFloat
    /// GeometryReader 側で算出した推奨下パディング
    let bottomPadding: CGFloat
    /// 詳細表示中の遺物
    @State private var inspectedRelic: DungeonRelicEntry?
    /// 詳細表示中の呪い遺物
    @State private var inspectedCurse: DungeonCurseEntry?

    /// 横幅のサイズクラス（iPhone / iPad での余白計算に利用）
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// ViewModel が保持する GameCore へのショートカット
    private var core: GameCore { viewModel.core }

    var body: some View {
        // MARK: - セーフエリアと追加マージンの再計算
        let expectedPadding = max(
            GameViewLayoutMetrics.handSectionBasePadding,
            bottomInset
                + GameViewLayoutMetrics.handSectionSafeAreaAdditionalPadding
                + (horizontalSizeClass == .regular ? GameViewLayoutMetrics.handSectionRegularAdditionalBottomPadding : 0)
        )
        // GeometryReader で算出した値と比較し、大きい方を採用して余白不足を防ぐ
        let finalBottomPadding = max(bottomPadding, expectedPadding)

        return VStack(spacing: 8) {
            if core.isAwaitingManualDiscardSelection {
                discardSelectionNotice
                    .transition(.opacity)
            }

            handSlotsSection

            if !core.dungeonRelicEntries.isEmpty || !core.dungeonCurseEntries.isEmpty {
                relicStrip
            }

            // NEXT 表示が存在する場合にのみ案内を表示
            if !core.nextCards.isEmpty {
                nextCardsSection
            }

        }
        // PreferenceKey へ手札セクションの高さを伝搬し、GameView 側のレイアウト計算に利用する
        .overlay(alignment: .topLeading) {
            HeightPreferenceReporter<HandSectionHeightPreferenceKey>()
        }
        // 下方向の余白をまとめて適用し、ホームインジケータとの干渉を避ける
        .padding(.bottom, finalBottomPadding)
        .padding(.horizontal, horizontalSizeClass == .regular ? 24 : 0)
        .frame(maxWidth: horizontalSizeClass == .regular ? 760 : nil)
        .frame(maxWidth: .infinity)
        .sheet(item: $inspectedRelic) { relic in
            DungeonRelicDetailView(theme: theme, relic: relic)
                .presentationDetents([.medium])
        }
        .sheet(item: $inspectedCurse) { curse in
            DungeonCurseDetailView(theme: theme, curse: curse)
                .presentationDetents([.medium])
        }
    }
}

private extension GameHandSectionView {
    /// 先読みカードの案内とカード本体をまとめたセクション
    private var nextCardsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("次のカード")
                .font(.caption)
                .foregroundColor(theme.textSecondary)
                .accessibilityHidden(true)

            HStack(spacing: 12) {
                ForEach(Array(core.nextCards.enumerated()), id: \.element.id) { index, dealtCard in
                    ZStack {
                        cardIllustration(for: dealtCard, mode: .next)
                            .opacity(boardBridge.hiddenCardIDs.contains(dealtCard.id) ? 0.0 : 1.0)
                            .matchedGeometryEffect(id: dealtCard.id, in: cardAnimationNamespace)
                            .anchorPreference(key: CardPositionPreferenceKey.self, value: .bounds) { [dealtCard.id: $0] }
                        NextCardOverlayView(order: index)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text("次のカード\(index == 0 ? "" : "+\(index)"): \(dealtCard.displayName)"))
                    .accessibilityHint(Text("この順番で手札に補充されます"))
                    .allowsHitTesting(false)
                }
            }
        }
    }

    /// 手札スロット一覧。通常の 5 枠は従来通り固定表示し、塔の 10 種類所持は 5 枚ずつ 2 行に並べる。
    @ViewBuilder
    private var handSlotsSection: some View {
        if handSlotCount > 5 {
            VStack(spacing: GameViewLayoutMetrics.handCardSpacing) {
                ForEach(Self.handSlotRowRanges(for: handSlotCount), id: \.lowerBound) { range in
                    handSlotsRow(range: range)
                }
            }
        } else {
            handSlotsRow
        }
    }

    private var handSlotsRow: some View {
        handSlotsRow(range: 0..<handSlotCount)
    }

    private func handSlotsRow(range: Range<Int>) -> some View {
        HStack(spacing: GameViewLayoutMetrics.handCardSpacing) {
            ForEach(range, id: \.self) { index in
                handSlotView(for: index)
            }
        }
    }

    private var relicStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(core.dungeonRelicEntries) { relic in
                    Button {
                        inspectedRelic = relic
                    } label: {
                        DungeonRelicIconView(theme: theme, relic: relic)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(Self.dungeonRelicAccessibilityIdentifier(for: relic))
                    .accessibilityLabel(Text(Self.dungeonRelicAccessibilityLabel(for: relic)))
                    .accessibilityHint(Text(Self.dungeonRelicAccessibilityHint(for: relic)))
                }
                ForEach(core.dungeonCurseEntries) { curse in
                    Button {
                        inspectedCurse = curse
                    } label: {
                        DungeonCurseIconView(theme: theme, curse: curse)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(Self.dungeonCurseAccessibilityIdentifier(for: curse))
                    .accessibilityLabel(Text(Self.dungeonCurseAccessibilityLabel(for: curse)))
                    .accessibilityHint(Text(Self.dungeonCurseAccessibilityHint(for: curse)))
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
        .frame(minHeight: 54)
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
                Text("捨て札を選ぶ")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.textPrimary)
                Text(penaltyDescription)
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

    /// 指定スロットに対応する `HandStack` を取得
    private func handCard(at index: Int) -> HandStack? {
        guard viewModel.displayedHandStacks.indices.contains(index) else {
            return nil
        }
        return viewModel.displayedHandStacks[index]
    }

    /// 手札スロット 1 枠を描画するビュー
    private func handSlotView(for index: Int) -> some View {
        ZStack {
            if viewModel.presentsBasicMoveCard, index == GameViewModel.dungeonBasicMoveSlotIndex {
                basicMoveCardView()
            } else if let stack = handCard(at: index), let card = stack.topCard {
                let isHidden = boardBridge.hiddenCardIDs.contains(card.id)
                let isUsable = viewModel.isCardUsable(stack)
                let isSelectingDiscard = core.isAwaitingManualDiscardSelection
                let isSelectingDungeonPickup = core.isAwaitingDungeonPickupChoice
                // 現在のスタックが ViewModel で選択済みかどうか（通常プレイ時のみハイライトを出す）
                let isSelected = viewModel.selectedHandStackID == stack.id
                let shouldShowSelectionHighlight = isSelected && !isHidden && !isSelectingDiscard && !isSelectingDungeonPickup
                let isChoosingReplacement = isSelectingDiscard || isSelectingDungeonPickup
                let shouldShowConflictHighlight = viewModel.isBoardTapSelectionWarningHighlighting(stack)
                    && !isHidden
                    && !isChoosingReplacement
                    && !shouldShowSelectionHighlight
                let shouldShowAdditionEffect = viewModel.recentlyAddedHandStackIDs.contains(stack.id)
                    && !isHidden
                    && !isChoosingReplacement
                    && !shouldShowSelectionHighlight
                    && !shouldShowConflictHighlight

                HandStackCardView(stackCount: stack.count) {
                    cardIllustration(for: card, mode: .hand)
                        .matchedGeometryEffect(id: card.id, in: cardAnimationNamespace)
                        .anchorPreference(key: CardPositionPreferenceKey.self, value: .bounds) { [card.id: $0] }
                }
                .scaleEffect((shouldShowAdditionEffect || shouldShowConflictHighlight) ? 1.04 : 1.0)
                .opacity(
                    isHidden ? 0.0 : (isChoosingReplacement ? 1.0 : (isUsable ? 1.0 : 0.4))
                )
                .allowsHitTesting(!isHidden)
                // 選択中のカードは背景に淡いオレンジ色を敷き、捨て札モードとの視覚差を確保する
                .background {
                    if shouldShowConflictHighlight {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(theme.accentPrimary.opacity(0.18))
                            .accessibilityHidden(true)
                    } else if shouldShowSelectionHighlight {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(theme.accentPrimary.opacity(0.12))
                            .accessibilityHidden(true)
                    }
                }
                .overlay {
                    if isChoosingReplacement && !isHidden {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(theme.accentPrimary.opacity(0.75), lineWidth: 3)
                            .shadow(color: theme.accentPrimary.opacity(0.45), radius: 6, x: 0, y: 3)
                            .accessibilityHidden(true)
                    } else if shouldShowSelectionHighlight {
                        // 通常選択時は細いストロークと控えめな影でオレンジ色を強調しつつも捨て札モードと差別化する
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(theme.accentPrimary, lineWidth: 2)
                            .shadow(color: theme.accentPrimary.opacity(0.25), radius: 5, x: 0, y: 2)
                            .accessibilityHidden(true)
                    } else if shouldShowConflictHighlight {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(theme.accentPrimary, lineWidth: 3)
                            .shadow(color: theme.accentPrimary.opacity(0.45), radius: 7, x: 0, y: 0)
                            .accessibilityHidden(true)
                    } else if shouldShowAdditionEffect {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(theme.accentPrimary.opacity(0.85), lineWidth: 3)
                            .shadow(color: theme.accentPrimary.opacity(0.55), radius: 8, x: 0, y: 0)
                            .accessibilityHidden(true)
                    }
                }
                .onTapGesture {
                    viewModel.handleHandSlotTap(at: index)
                }
                .onLongPressGesture {
                    viewModel.showSupportCardInspection(for: stack)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(accessibilityLabel(for: stack)))
                .accessibilityHint(Text(accessibilityHint(for: stack, isUsable: isUsable, isDiscardMode: isSelectingDiscard, isDungeonPickupChoiceMode: isSelectingDungeonPickup, isSelected: isSelected)))
                .accessibilityAction(named: Text("効果を確認")) {
                    viewModel.showSupportCardInspection(for: stack)
                }
                .accessibilityValue(Text(shouldShowConflictHighlight ? "選択候補" : (isSelected ? "選択中" : "")))
                .accessibilityAddTraits(.isButton)
            } else {
                placeholderCardView()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("カードなしのスロット"))
                    .accessibilityHint(Text("このスロットには現在カードがありません"))
            }
        }
        .accessibilityIdentifier(Self.handSlotAccessibilityIdentifier(for: index))
    }

    private func basicMoveCardView() -> some View {
        let isSelected = viewModel.isBasicMoveCardSelected
        let isSelectingDiscard = core.isAwaitingManualDiscardSelection
        let isSelectingDungeonPickup = core.isAwaitingDungeonPickupChoice
        let isUsable = core.progress == .playing
            && !isSelectingDiscard
            && !isSelectingDungeonPickup
            && !core.availableBasicOrthogonalMoves().isEmpty

        return HandStackCardView(stackCount: 1) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.cardBackgroundHand)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(theme.cardBorderHand, lineWidth: 1.5)
                    )

                VStack(spacing: 7) {
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(theme.cardContentPrimary)
                        .accessibilityHidden(true)
                    Text("基本移動")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(theme.cardContentPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text("消費なし")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .padding(.horizontal, 5)
            }
            .frame(width: GameViewLayoutMetrics.handCardWidth, height: GameViewLayoutMetrics.handCardHeight)
        }
        .opacity(isUsable ? 1.0 : 0.4)
        .background {
            if isSelected && !isSelectingDungeonPickup {
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.accentPrimary.opacity(0.12))
                    .accessibilityHidden(true)
            }
        }
        .overlay {
            if isSelected && !isSelectingDungeonPickup {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(theme.accentPrimary, lineWidth: 2)
                    .shadow(color: theme.accentPrimary.opacity(0.25), radius: 5, x: 0, y: 2)
                    .accessibilityHidden(true)
            }
        }
        .onTapGesture {
            viewModel.handleHandSlotTap(at: GameViewModel.dungeonBasicMoveSlotIndex)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("基本移動、上下左右1マス、消費なし"))
        .accessibilityHint(Text(isSelectingDungeonPickup ? "拾得カードの取捨選択中は基本移動を選べません。" : (isUsable ? "ダブルタップで基本移動を選択し、盤面で移動先を決めてください。" : "\(viewModel.unusableBasicMoveReason() ?? "現在使える基本移動候補がありません")。")))
        .accessibilityValue(Text(isSelected ? "選択中" : ""))
        .accessibilityAddTraits(.isButton)
    }

    /// 手札が空の際に表示するプレースホルダビュー
    private func placeholderCardView() -> some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(theme.placeholderStroke, style: StrokeStyle(lineWidth: 1, dash: [4]))
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.placeholderBackground)
            )
            .frame(width: GameViewLayoutMetrics.handCardWidth, height: GameViewLayoutMetrics.handCardHeight)
            .overlay(
                Image(systemName: "questionmark")
                    .font(.caption)
                    .foregroundColor(theme.placeholderIcon)
            )
    }

    /// VoiceOver 向けに手札スタックの説明文を生成する
    private func accessibilityLabel(for stack: HandStack) -> String {
        if let support = stack.topCard?.supportCard {
            return "補助カード、\(support.displayName)、残り \(stack.count) 枚"
        }
        if core.isIlluded, stack.topCard?.moveCard != nil {
            return "幻惑中の移動カード、内容不明、残り \(stack.count) 枚"
        }
        guard let move = stack.topCard?.move else {
            return "カードなしのスロット"
        }
        return "\(directionPhrase(for: move))、残り \(stack.count) 枚"
    }

    /// VoiceOver のヒント文を生成する
    private func accessibilityHint(for stack: HandStack, isUsable: Bool, isDiscardMode: Bool, isDungeonPickupChoiceMode: Bool, isSelected: Bool) -> String {
        // MARK: - 候補数と残枚数の算出
        let candidateCount = stack.representativeVectors?.count ?? 0
        if isDiscardMode {
            return "ダブルタップでこの種類のカードをすべて捨て札にし、新しいカードを補充します。"
        }
        if isDungeonPickupChoiceMode {
            return Self.dungeonPickupReplacementAccessibilityHint(for: stack)
        }
        if !isUsable, let reason = viewModel.unusableReason(for: stack) {
            return "\(reason)。スタックの \(stack.count) 枚はそのまま保持されます。"
        }
        if let support = stack.topCard?.supportCard {
            switch support {
            case .refillEmptySlots:
                return "ダブルタップで 1 手使い、空いている手札枠を移動カードで補給します。"
            case .singleAnnihilationSpell:
                return "ダブルタップで呪文を選び、消滅させる敵を盤面から選びます。"
            case .annihilationSpell:
                return "ダブルタップで 1 手使い、このフロアの敵をすべて消滅させます。"
            case .freezeSpell:
                return "ダブルタップで 1 手使い、3回分の敵ターンを止めます。"
            case .barrierSpell:
                return "ダブルタップで 1 手使い、3回分のHPダメージを無効化します。"
            case .darknessSpell:
                return "ダブルタップで 1 手使い、この階の見張りと回転見張りのレーザー攻撃を封じます。"
            case .railBreakSpell:
                return "ダブルタップで 1 手使い、この階の巡回兵のレール移動を封じます。"
            case .antidote:
                return "ダブルタップで 1 手使い、毒状態を解除します。"
            case .panacea:
                return "ダブルタップで 1 手使い、毒、足枷、幻惑状態を解除します。"
            }
        }

        if core.isIlluded, stack.topCard?.moveCard != nil {
            return "ダブルタップで現在使える移動カードからランダムに1枚を消費し、合法な移動先へ進みます。基本移動と補助カードは通常どおり使えます。"
        }

        // 通常操作時に読み上げる基本説明文を状況ごとに作成する
        var baseMessage: String
        if isUsable {
            // 候補が複数ある場合は盤面で方向を選択する必要があることを強調する
            if candidateCount > 1 {
                let remainingDescription: String
                if stack.count > 1 {
                    remainingDescription = "残り \(stack.count - 1) 枚も同じ候補を共有します。"
                } else {
                    remainingDescription = "スタックは 1 枚だけです。"
                }
                let instruction = "ダブルタップでカードを選択し、盤面で移動方向を決めてください。候補は \(candidateCount) 方向です。"
                baseMessage = instruction + remainingDescription
            } else {
                if stack.count > 1 {
                    baseMessage = "ダブルタップで先頭カードを使用します。スタックの残り \(stack.count - 1) 枚は同じ方向で待機します。"
                } else {
                    baseMessage = "ダブルタップでこの方向に移動します。スタックは 1 枚だけです。"
                }
            }
        } else {
            // 使用不可時も候補数に応じて状況を具体的に伝える
            if candidateCount > 1 {
                baseMessage = "盤外のため使用できません。候補は \(candidateCount) 方向ありますが、いずれも盤面外です。スタックの \(stack.count) 枚はそのまま保持されます。"
            } else if candidateCount == 1 {
                baseMessage = "盤外のため使用できません。スタックの \(stack.count) 枚はそのまま保持されます。"
            } else {
                baseMessage = "盤外のため使用できません。移動候補が未設定のカードです。スタックの \(stack.count) 枚はそのまま保持されます。"
            }
        }

        // 選択済みである場合は解除方法も併せて伝え、状態変化が分かるよう配慮する
        if isSelected {
            return baseMessage + "現在このカードを選択中です。別の手札を選ぶか、もう一度ダブルタップすると解除されます。"
        } else {
            return baseMessage
        }
    }

    @ViewBuilder
    private func cardIllustration(for card: DealtCard, mode: MoveCardIllustrationView.Mode) -> some View {
        if let support = card.supportCard {
            SupportCardIllustrationView(card: support, mode: mode)
        } else if let move = card.moveCard {
            if mode == .hand, core.isIlluded {
                IllusionMoveCardIllustrationView(mode: mode)
            } else {
                MoveCardIllustrationView(
                    card: move,
                    mode: mode
                )
            }
        }
    }

    /// MoveCard を読み上げ用の日本語へ変換する
    private func directionPhrase(for move: MoveCard) -> String {
        switch move {
        case .kingUpRight:
            return "右上へ 1"
        case .kingDownRight:
            return "右下へ 1"
        case .kingDownLeft:
            return "左下へ 1"
        case .kingUpLeft:
            return "左上へ 1"
        // キング型の選択式カードは斜め方向の 2 択であることを明確に伝える
        case .kingUpwardDiagonalChoice:
            return "右上または左上へ 1 (選択)"
        case .kingRightDiagonalChoice:
            return "右上または右下へ 1 (選択)"
        case .kingDownwardDiagonalChoice:
            return "右下または左下へ 1 (選択)"
        case .kingLeftDiagonalChoice:
            return "左上または左下へ 1 (選択)"
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
        // ナイト型の選択式カードは組み合わせをセットで読み上げ、迷わないよう配慮する
        case .knightUpwardChoice:
            return "上へ 2、右へ 1 または 上へ 2、左へ 1 (選択)"
        case .knightRightwardChoice:
            return "上へ 1、右へ 2 または 下へ 1、右へ 2 (選択)"
        case .knightDownwardChoice:
            return "下へ 2、右へ 1 または 下へ 2、左へ 1 (選択)"
        case .knightLeftwardChoice:
            return "上へ 1、左へ 2 または 下へ 1、左へ 2 (選択)"
        case .straightUp2:
            return "上へ 2"
        case .straightDown2:
            return "下へ 2"
        case .straightRight2:
            return "右へ 2"
        case .straightLeft2:
            return "左へ 2"
        case .straightUp1:
            return "上へ 1"
        case .straightDown1:
            return "下へ 1"
        case .straightRight1:
            return "右へ 1"
        case .straightLeft1:
            return "左へ 1"
        case .diagonalUpRight2:
            return "右上へ 2"
        case .diagonalUpLeft2:
            return "左上へ 2"
        case .diagonalDownRight2:
            return "右下へ 2"
        case .diagonalDownLeft2:
            return "左下へ 2"
        // レイ型カードは止まるまで進む特性があるため、連続移動であることを強調して伝える
        case .rayUp:
            return "上方向へ連続移動"
        case .rayUpRight:
            return "右上方向へ連続移動"
        case .rayRight:
            return "右方向へ連続移動"
        case .rayDownRight:
            return "右下方向へ連続移動"
        case .rayDown:
            return "下方向へ連続移動"
        case .rayDownLeft:
            return "左下方向へ連続移動"
        case .rayLeft:
            return "左方向へ連続移動"
        case .rayUpLeft:
            return "左上方向へ連続移動"
        }
    }
}

/// NEXT バッジを重ねて視覚的な段階を示す補助ビュー
private struct NextCardOverlayView: View {
    /// 表示中のカードが何枚目の先読みか
    let order: Int
    /// 配色を統一するためのテーマ
    private let theme = AppTheme()

    var body: some View {
        ZStack {
            VStack {
                HStack {
                    Text(order == 0 ? "NEXT" : "NEXT+\(order)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .foregroundColor(theme.nextBadgeText)
                        .background(
                            Capsule()
                                .strokeBorder(theme.nextBadgeBorder, lineWidth: 1)
                                .background(Capsule().fill(theme.nextBadgeBackground))
                        )
                        .padding([.top, .leading], 6)
                        .accessibilityHidden(true)
                    Spacer()
                }
                Spacer()
            }
        }
        .allowsHitTesting(false)
    }
}

extension GameHandSectionView {
    static func handSlotRowRanges(for slotCount: Int) -> [Range<Int>] {
        guard slotCount > 5 else {
            return [0..<slotCount]
        }

        let columnsPerRow = 5
        return stride(from: 0, to: slotCount, by: columnsPerRow).map { start in
            start..<min(start + columnsPerRow, slotCount)
        }
    }

    static func handSlotAccessibilityIdentifier(for index: Int) -> String {
        "hand_slot_\(index)"
    }

    static func dungeonPickupReplacementAccessibilityHint(for stack: HandStack) -> String {
        guard let playable = stack.representativePlayable else {
            return "このスロットは取捨選択の対象外です。"
        }
        return "ダブルタップで \(playable.displayName) をすべて捨て、拾ったカードを取得します。"
    }

    static func dungeonRelicAccessibilityIdentifier(for relic: DungeonRelicEntry) -> String {
        "dungeon_relic_\(relic.relicID.rawValue)"
    }

    static func dungeonRelicAccessibilityLabel(for relic: DungeonRelicEntry) -> String {
        let usedText = relic.isUsedUpLimitedRelic ? "、使用済み" : ""
        return "\(relic.rarity.displayName)\(usedText)、\(relic.displayName)"
    }

    static func dungeonRelicAccessibilityHint(for relic: DungeonRelicEntry) -> String {
        let remainingText = relic.hasLimitedUses ? "残り \(relic.remainingUses) 回。" : ""
        let usedText = relic.isUsedUpLimitedRelic ? "使用済み。" : ""
        if let note = relic.noteDescription {
            return "ダブルタップで効果を確認します。\(relic.rarity.displayName)。\(usedText)\(relic.effectDescription)\(remainingText)\(note)"
        }
        return "ダブルタップで効果を確認します。\(relic.rarity.displayName)。\(usedText)\(relic.effectDescription)\(remainingText)"
    }

    static func dungeonCurseAccessibilityIdentifier(for curse: DungeonCurseEntry) -> String {
        "dungeon_curse_\(curse.curseID.rawValue)"
    }

    static func dungeonCurseAccessibilityLabel(for curse: DungeonCurseEntry) -> String {
        "\(curse.displayKind.displayName)遺物、\(curse.displayName)"
    }

    static func dungeonCurseAccessibilityHint(for curse: DungeonCurseEntry) -> String {
        "ダブルタップで効果を確認します。\(curse.displayKind.displayName)。利点: \(curse.upsideDescription) 代償: \(curse.downsideDescription) \(curse.releaseDescription)"
    }
}

private extension DungeonCurseDisplayKind {
    var tintColor: Color {
        switch self {
        case .temporary:
            return Color(red: 0.82, green: 0.16, blue: 0.22)
        case .persistent:
            return Color(red: 0.50, green: 0.22, blue: 0.78)
        }
    }
}

private extension DungeonRelicDisplayKind {
    func tintColor(theme: AppTheme) -> Color {
        switch self {
        case .temporary:
            return Color(red: 0.91, green: 0.46, blue: 0.10)
        case .persistent:
            return theme.accentPrimary
        }
    }
}

private extension DungeonRelicRarity {
    func tintColor(theme: AppTheme) -> Color {
        switch self {
        case .common:
            return theme.textSecondary
        case .rare:
            return Color(red: 0.18, green: 0.48, blue: 0.74)
        case .legendary:
            return Color(red: 0.78, green: 0.54, blue: 0.10)
        }
    }
}

private extension DungeonRelicEntry {
    var isUsedUpLimitedRelic: Bool {
        hasLimitedUses && remainingUses == 0
    }
}

private struct DungeonRelicIconView: View {
    let theme: AppTheme
    let relic: DungeonRelicEntry
    private var isUsedUp: Bool { relic.isUsedUpLimitedRelic }
    private var tint: Color {
        isUsedUp ? theme.textSecondary : relic.displayKind.tintColor(theme: theme)
    }
    private var rarityTint: Color {
        isUsedUp ? theme.textSecondary : relic.rarity.tintColor(theme: theme)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.cardBackgroundHand)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(tint.opacity(isUsedUp ? 0.42 : 0.72), lineWidth: 1.5)
                )

            Image(systemName: relic.symbolName)
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(tint)
                .opacity(isUsedUp ? 0.58 : 1.0)
                .accessibilityHidden(true)

            Text(relic.rarity.badgeText)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(rarityTint)
                .frame(width: 16, height: 16)
                .background(Circle().fill(theme.cardBackgroundHand))
                .overlay(Circle().stroke(rarityTint.opacity(isUsedUp ? 0.45 : 0.7), lineWidth: 1))
                .offset(x: -28, y: 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .accessibilityHidden(true)

            if isUsedUp {
                Text("0")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(theme.textSecondary)
                    .frame(width: 17, height: 17)
                    .background(Circle().fill(theme.cardBackgroundHand))
                    .overlay(Circle().stroke(theme.textSecondary.opacity(0.55), lineWidth: 1))
                    .offset(x: 4, y: -4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 44, height: 44)
        .opacity(isUsedUp ? 0.78 : 1.0)
    }
}

private struct DungeonRelicDetailView: View {
    let theme: AppTheme
    let relic: DungeonRelicEntry
    @Environment(\.dismiss) private var dismiss
    private var isUsedUp: Bool { relic.isUsedUpLimitedRelic }
    private var tint: Color {
        isUsedUp ? theme.textSecondary : relic.displayKind.tintColor(theme: theme)
    }
    private var rarityTint: Color {
        isUsedUp ? theme.textSecondary : relic.rarity.tintColor(theme: theme)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: relic.symbolName)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(tint)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(tint.opacity(0.14)))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(relic.rarity.displayName)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(rarityTint)
                            if isUsedUp {
                                Text("使用済み")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundColor(theme.textSecondary)
                            }
                        }
                        Text(relic.displayName)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(theme.textPrimary)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label(relic.effectDescription, systemImage: "sparkles")
                    if let note = relic.noteDescription {
                        Label(note, systemImage: "info.circle")
                    }
                    if relic.hasLimitedUses {
                        Label("残り \(relic.remainingUses) 回", systemImage: "number.circle")
                        if isUsedUp {
                            Label("使用済み", systemImage: "checkmark.circle")
                        }
                    }
                }
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(theme.textPrimary)

                Spacer(minLength: 0)
            }
            .padding(22)
            .background(theme.backgroundPrimary)
            .navigationTitle("遺物")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct DungeonCurseIconView: View {
    let theme: AppTheme
    let curse: DungeonCurseEntry
    private var tint: Color { curse.displayKind.tintColor }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.cardBackgroundHand)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(tint.opacity(0.75), lineWidth: 1.5)
                )

            Image(systemName: curse.symbolName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(tint)
                .accessibilityHidden(true)

            Text(curse.displayKind.badgeText)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(tint))
                .offset(x: 4, y: 4)
                .accessibilityHidden(true)
        }
        .frame(width: 44, height: 44)
    }
}

private struct DungeonCurseDetailView: View {
    let theme: AppTheme
    let curse: DungeonCurseEntry
    @Environment(\.dismiss) private var dismiss
    private var tint: Color { curse.displayKind.tintColor }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: curse.symbolName)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(tint)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(tint.opacity(0.14)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(curse.displayKind.displayName)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(tint)
                        Text(curse.displayName)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(theme.textPrimary)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label(curse.upsideDescription, systemImage: "sparkles")
                    Label(curse.downsideDescription, systemImage: "exclamationmark.triangle")
                    Label(curse.releaseDescription, systemImage: "checkmark.circle")
                    if curse.hasLimitedUses {
                        Label("残り \(curse.remainingUses) 回", systemImage: "number.circle")
                    }
                }
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(theme.textPrimary)

                Spacer(minLength: 0)
            }
            .padding(22)
            .background(theme.backgroundPrimary)
            .navigationTitle("呪い遺物")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct SupportCardIllustrationView: View {
    let card: SupportCard
    var mode: MoveCardIllustrationView.Mode = .hand
    private let theme = AppTheme()

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbolName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(theme.accentPrimary)
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(theme.accentPrimary.opacity(0.14))
                )
                .accessibilityHidden(true)

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
                .fill(mode.backgroundColor(using: theme))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(theme.accentPrimary.opacity(0.75), lineWidth: mode.borderLineWidth)
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("補助カード、\(card.displayName)"))
        .accessibilityHint(Text(card.encyclopediaDescription))
    }

    private var symbolName: String {
        switch card {
        case .refillEmptySlots:
            return "square.grid.3x3.fill"
        case .singleAnnihilationSpell:
            return "sparkle.magnifyingglass"
        case .annihilationSpell:
            return "sparkles"
        case .freezeSpell:
            return "snowflake"
        case .barrierSpell:
            return "shield.fill"
        case .darknessSpell:
            return "moon.fill"
        case .railBreakSpell:
            return "point.topleft.down.to.point.bottomright.curvepath"
        case .antidote:
            return "cross.case.fill"
        case .panacea:
            return "pills.fill"
        }
    }
}

private struct IllusionMoveCardIllustrationView: View {
    var mode: MoveCardIllustrationView.Mode = .hand
    private let theme = AppTheme()

    var body: some View {
        VStack(spacing: 8) {
            Text("?")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundColor(theme.cardContentPrimary)
                .frame(width: 42, height: 42)
                .background(
                    Circle()
                        .fill(theme.boardTileEffectSlow.opacity(0.18))
                        .overlay(Circle().stroke(theme.boardTileEffectSlow.opacity(0.75), lineWidth: 1.5))
                )
                .accessibilityHidden(true)

            Text("？")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(theme.textPrimary)
                .lineLimit(1)

            Text("幻惑")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(theme.textSecondary)
        }
        .padding(8)
        .frame(width: MoveCardIllustrationView.defaultWidth, height: MoveCardIllustrationView.defaultHeight)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(mode.backgroundColor(using: theme))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(theme.boardTileEffectSlow.opacity(0.75), lineWidth: mode.borderLineWidth)
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("幻惑中の移動カード、内容不明"))
        .accessibilityHint(Text("使うと現在合法な移動カードと移動先がランダムに決まります。"))
    }
}
