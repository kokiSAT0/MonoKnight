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

            // 手札スロットを横並びで描画し、欠番があっても空枠でレイアウトを安定させる
            HStack(spacing: GameViewLayoutMetrics.handCardSpacing) {
                ForEach(0..<handSlotCount, id: \.self) { index in
                    handSlotView(for: index)
                }
            }

            // NEXT 表示が存在する場合にのみ案内を表示
            if !core.nextCards.isEmpty {
                nextCardsSection
            }

            #if DEBUG
            debugResultButton
            #endif
        }
        // PreferenceKey へ手札セクションの高さを伝搬し、GameView 側のレイアウト計算に利用する
        .overlay(alignment: .topLeading) {
            HeightPreferenceReporter<HandSectionHeightPreferenceKey>()
        }
        // 下方向の余白をまとめて適用し、ホームインジケータとの干渉を避ける
        .padding(.bottom, finalBottomPadding)
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
                        MoveCardIllustrationView(card: dealtCard.move, mode: .next)
                            .opacity(boardBridge.hiddenCardIDs.contains(dealtCard.id) ? 0.0 : 1.0)
                            .matchedGeometryEffect(id: dealtCard.id, in: cardAnimationNamespace)
                            .anchorPreference(key: CardPositionPreferenceKey.self, value: .bounds) { [dealtCard.id: $0] }
                        NextCardOverlayView(order: index)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text("次のカード\(index == 0 ? "" : "+\(index)"): \(dealtCard.move.displayName)"))
                    .accessibilityHint(Text("この順番で手札に補充されます"))
                    .allowsHitTesting(false)
                }
            }
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

    /// 指定スロットに対応する `HandStack` を取得
    private func handCard(at index: Int) -> HandStack? {
        guard core.handStacks.indices.contains(index) else {
            return nil
        }
        return core.handStacks[index]
    }

    /// 手札スロット 1 枠を描画するビュー
    private func handSlotView(for index: Int) -> some View {
        ZStack {
            if let stack = handCard(at: index), let card = stack.topCard {
                let isHidden = boardBridge.hiddenCardIDs.contains(card.id)
                let isUsable = viewModel.isCardUsable(stack)
                let isSelectingDiscard = core.isAwaitingManualDiscardSelection
                // 現在のスタックが ViewModel で選択済みかどうか（通常プレイ時のみハイライトを出す）
                let isSelected = viewModel.selectedHandStackID == stack.id
                let shouldShowSelectionHighlight = isSelected && !isHidden && !isSelectingDiscard

                HandStackCardView(stackCount: stack.count) {
                    MoveCardIllustrationView(card: card.move)
                        .matchedGeometryEffect(id: card.id, in: cardAnimationNamespace)
                        .anchorPreference(key: CardPositionPreferenceKey.self, value: .bounds) { [card.id: $0] }
                }
                .opacity(
                    isHidden ? 0.0 : (isSelectingDiscard ? 1.0 : (isUsable ? 1.0 : 0.4))
                )
                .allowsHitTesting(!isHidden)
                // 選択中のカードは背景に淡いオレンジ色を敷き、捨て札モードとの視覚差を確保する
                .background {
                    if shouldShowSelectionHighlight {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(theme.accentPrimary.opacity(0.12))
                            .accessibilityHidden(true)
                    }
                }
                .overlay {
                    if isSelectingDiscard && !isHidden {
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
                    }
                }
                .onTapGesture {
                    viewModel.handleHandSlotTap(at: index)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(accessibilityLabel(for: stack)))
                .accessibilityHint(Text(accessibilityHint(for: stack, isUsable: isUsable, isDiscardMode: isSelectingDiscard, isSelected: isSelected)))
                .accessibilityValue(Text(isSelected ? "選択中" : ""))
                .accessibilityAddTraits(.isButton)
            } else {
                placeholderCardView()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("カードなしのスロット"))
                    .accessibilityHint(Text("このスロットには現在カードがありません"))
            }
        }
        .accessibilityIdentifier("hand_slot_\(index)")
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
        guard let move = stack.topCard?.move else {
            return "カードなしのスロット"
        }
        return "\(directionPhrase(for: move))、残り \(stack.count) 枚"
    }

    /// VoiceOver のヒント文を生成する
    private func accessibilityHint(for stack: HandStack, isUsable: Bool, isDiscardMode: Bool, isSelected: Bool) -> String {
        // MARK: - 候補数と残枚数の算出
        let candidateCount = stack.representativeVectors?.count ?? 0
        if isDiscardMode {
            return "ダブルタップでこの種類のカードをすべて捨て札にし、新しいカードを補充します。"
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

    /// MoveCard を読み上げ用の日本語へ変換する
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
        case .kingUpOrDown:
            return "上下いずれかへ 1"
        case .kingLeftOrRight:
            return "左右いずれかへ 1"
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
        // ワープ系カードは挙動が特殊なので、対象範囲を明確に読み上げて誤操作を防ぐ
        case .superWarp:
            return "未踏マスへ全域ワープ"
        case .fixedWarp:
            return "定められた座標へ固定ワープ"
        }
    }

    #if DEBUG
    /// 結果画面を即座に表示するデバッグ専用ボタン
    private var debugResultButton: some View {
        HStack {
            Spacer(minLength: 0)
            Button("結果へ") {
                viewModel.showingResult = true
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("show_result")
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }
    #endif
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
