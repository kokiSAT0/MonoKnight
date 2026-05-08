import SwiftUI
import Game // MoveCard 型を利用するためゲームロジックモジュールを読み込む

/// ゲームの遊び方を段階的に説明するビュー
/// 塔攻略の流れ、カード、盤面マーカーをまとめ、初見でも出口到達の判断を理解しやすくする
struct HowToPlayView: View {
    /// ヘルプ内で表示するページ
    private enum HelpPage: String, CaseIterable, Identifiable {
        case guide = "遊び方"
        case cardDictionary = "カード辞典"
        case enemyDictionary = "敵辞典"
        case tileDictionary = "マス辞典"

        var id: HelpPage { self }
    }

    /// モーダル表示時に閉じるボタンを出すかどうかのフラグ
    /// - Note: タイトル画面からシートで開く場合のみ true を渡す
    let showsCloseButton: Bool
    /// 説明に用いる基準モードを保持し、手札スロット数などを文字列に反映する
    private let referenceMode: GameMode = .dungeonPlaceholder
    /// 画面を閉じるための環境変数
    @Environment(\.dismiss) private var dismiss
    /// iPad などレギュラー幅の端末でレイアウトを最適化するためのサイズクラス
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// ヘルプ内の表示ページ
    @State private var selectedPage: HelpPage = .guide

    /// デフォルト引数付きのイニシャライザ
    /// - Parameter showsCloseButton: ナビゲーションバーに「閉じる」ボタンを表示するか
    init(showsCloseButton: Bool = false) {
        self.showsCloseButton = showsCloseButton
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Picker("ヘルプ表示", selection: $selectedPage) {
                    ForEach(HelpPage.allCases) { page in
                        Text(page.rawValue).tag(page)
                    }
                }
                .pickerStyle(.segmented)

                switch selectedPage {
                case .guide:
                    guideContent
                case .cardDictionary:
                    cardDictionaryContent
                case .enemyDictionary:
                    enemyDictionaryContent
                case .tileDictionary:
                    tileDictionaryContent
                }
            }
            // MARK: - サイズクラスに応じた余白調整
            // iPad では左右の余白を広めに確保し、中央揃えで読みやすくする。iPhone では従来の余白を維持。
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 28)
            .frame(maxWidth: contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollIndicators(.hidden)
        .background(Color(UIColor.systemBackground))
        .navigationTitle(selectedPage.rawValue)
        .toolbar {
            // MARK: - モーダル用の閉じるボタン
            if showsCloseButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - ページ本文
private extension HowToPlayView {
    /// 初心者向けの遊び方本文
    var guideContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            // MARK: - 導入文
            Text("MonoKnight は、カードで騎士を動かして塔の出口を目指すダンジョンです。HP、敵の危険範囲、床ギミックを読みながら、残り手数に少し余裕を残して階段までの道を作ります。")
                .font(.body)
                .padding(.bottom, 8)

            // MARK: - 基本移動の説明
            HowToPlaySectionView(
                title: "1. 塔を選んで階段を目指す",
                description: "塔選択から基礎塔、成長塔、試練塔を選び、各フロアの出口や階段へ到達すると次の階へ進みます。",
                card: .kingUpRight,
                tips: [
                    "基礎塔は基本を学ぶ短い塔です。",
                    "成長塔は周回成長と報酬カードで少しずつ登りやすくなる本編塔です。",
                    "試練塔は永続成長を持ち込まず、その場のカードで突破する高難度塔です。"
                ]
            )

            // MARK: - ナイト移動の例
            HowToPlaySectionView(
                title: "2. 基本移動とカードを使い分ける",
                description: "基本移動が使える塔では、上下左右 1 マスへカードを消費せずに歩けます。移動カードは危険な場所を避けたり、階段までの手数を短くしたいときに使います。",
                card: .knightUp2Right1,
                tips: [
                    "基本移動も 1 手として数えられ、敵や床ギミックが反応します。",
                    "ナイト型カードは途中のマスを通らず、敵の危険範囲や罠を飛び越えやすいカードです。",
                    stackingTip
                ]
            )

            // MARK: - 遠距離カードの例
            HowToPlaySectionView(
                title: "3. 床カードと報酬を持ち越す",
                description: "床に落ちているカードは、踏むだけで拾えます。拾ったカードもフロア報酬も同じ手札として扱い、残り使用回数を同じ区間の次の階へ持ち越せます。",
                card: .straightUp2,
                tips: [
                    "カードは通常 9 種類まで持てます。同じカードは種類枠を増やさず、残り回数としてまとまります。",
                    "報酬では新しいカードの追加や、持っているカードの使用回数強化を選べます。",
                    "補給カードは空いた枠を一時カードで埋める強力な報酬です。"
                ]
            )

            // MARK: - 勝利条件の説明
            HowToPlaySectionView(
                title: "4. 敵と床ギミックを読む",
                description: "塔では敵の危険範囲、見えている罠、鍵、ワープ床、ひび割れ床などを読みながらルートを選びます。",
                card: nil,
                tips: [
                    "危険範囲へ入ると HP を失います。敵によって動き方や警告の出方が違います。",
                    "敵の形で種類を見分け、詳しい読み方は敵辞典で確認できます。",
                    "鍵がある階では、鍵マスを踏むまで階段が施錠されています。",
                    "ひび割れ床はもう一度踏むと崩れ、HP を失って下の階へ落ちることがあります。"
                ]
            )

            // MARK: - ペナルティの説明
            HowToPlaySectionView(
                title: "5. 失敗しても成長塔で伸ばす",
                description: "HP が 0 になると失敗です。残り手数 0 も失敗ですが、通常ルートには余裕があります。成長塔では区切り階の初回クリアで成長ポイントを得て、次の挑戦を少し有利にできます。",
                card: nil,
                tips: [
                    "失敗したときは現在の区間開始階から再挑戦します。",
                    "成長塔は 5F、10F、15F、20F の初回クリアで成長ポイントを得ます。",
                    "成長は成長塔だけに反映され、基礎塔と試練塔には持ち込みません。"
                ]
            )
        }
    }

    /// カード辞典本文
    var cardDictionaryContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("塔攻略で使うカードの動きと、階段までのルート作りでの役割を確認できます。")
                .font(.body)

            ForEach(cardCategoryOrder, id: \.self) { category in
                let entries = cardEntries(for: category)
                if !entries.isEmpty {
                    EncyclopediaGroupView(title: category) {
                        ForEach(entries) { entry in
                            CardEncyclopediaRow(entry: entry)
                        }
                    }
                }
            }

            EncyclopediaGroupView(title: "補助カード") {
                ForEach(SupportCard.encyclopediaEntries) { entry in
                    SupportCardEncyclopediaRow(entry: entry)
                }
            }
        }
    }

    /// 敵辞典本文
    var enemyDictionaryContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("塔に出る敵の見た目と、危険範囲の読み方を確認できます。")
                .font(.body)

            EncyclopediaGroupView(title: "敵") {
                ForEach(EnemyEncyclopediaEntry.allEntries) { entry in
                    EnemyEncyclopediaRow(entry: entry)
                }
            }
        }
    }

    /// マス辞典本文
    var tileDictionaryContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("塔攻略中に盤面へ出るマスやマーカーの効果を確認できます。")
                .font(.body)

            ForEach(tileCategoryOrder, id: \.self) { category in
                let entries = tileEntries(for: category)
                if !entries.isEmpty {
                    EncyclopediaGroupView(title: category) {
                        ForEach(entries) { entry in
                            TileEncyclopediaRow(entry: entry)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - レイアウト調整用のヘルパー
private extension HowToPlayView {
    var cardCategoryOrder: [String] {
        ["キング", "ナイト", "直線2マス", "斜め2マス", "レイ", "選択キング", "選択ナイト", "ワープ"]
    }

    var tileCategoryOrder: [String] {
        ["基本", "攻略", "危険", "障害物", "特殊効果"]
    }

    func cardEntries(for category: String) -> [MoveCardEncyclopediaEntry] {
        MoveCard.encyclopediaEntries.filter { $0.category == category }
    }

    func tileEntries(for category: String) -> [TileEncyclopediaEntry] {
        TileEncyclopediaEntry.allEntries.filter { $0.category == category }
    }

    /// スタック仕様を説明する文言。塔の所持カード枠と整合が取れるようにする
    var stackingTip: String {
        if referenceMode.allowsCardStacking {
            return "同じ種類のカードは所持枠内でまとまり、残り使用回数として表示されます。"
        } else {
            return "同じ種類のカードでも別スロットを占有するため、空き枠を意識した立ち回りが重要です。"
        }
    }

    /// 横幅に応じた最大コンテンツ幅を返す
    var contentMaxWidth: CGFloat? {
        horizontalSizeClass == .regular ? 640 : nil
    }

    /// 端末に合わせて適切な横方向パディングを返す
    var horizontalPadding: CGFloat {
        horizontalSizeClass == .regular ? 36 : 20
    }
}

// MARK: - 辞典グループ
private struct EncyclopediaGroupView<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 10) {
                content
            }
        }
    }
}

// MARK: - カード辞典行
private struct CardEncyclopediaRow: View {
    let entry: MoveCardEncyclopediaEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MoveCardIllustrationView(card: entry.card, mode: .next)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(entry.displayName)
                    .font(.headline)
                Text(entry.description)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
        )
        .accessibilityElement(children: .combine)
    }
}

private struct SupportCardEncyclopediaRow: View {
    let entry: SupportCardEncyclopediaEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(width: 66, height: 90)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(UIColor.tertiarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.accentColor.opacity(0.45), lineWidth: 1)
                        )
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(entry.displayName)
                    .font(.headline)
                Text(entry.description)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
        )
        .accessibilityElement(children: .combine)
    }

    private var symbolName: String {
        switch entry.card {
        case .refillEmptySlots:
            return "square.grid.3x3.fill"
        }
    }
}

// MARK: - 敵辞典行
private struct EnemyEncyclopediaRow: View {
    let entry: EnemyEncyclopediaEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            EnemyMarkerPreviewView(kind: entry.kind)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.displayName)
                    .font(.headline)
                Text(entry.behaviorSummary)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(entry.dangerSummary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 敵辞典用プレビュー
private struct EnemyMarkerPreviewView: View {
    let kind: EnemyPresentationKind

    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppTheme {
        AppTheme(colorScheme: colorScheme)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(theme.boardTileUnvisited)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(theme.boardGridLine.opacity(0.72), lineWidth: 1)
                )

            marker
                .frame(width: markerFrameSize.width, height: markerFrameSize.height)
        }
        .frame(width: 48, height: 48)
        .fixedSize()
    }

    @ViewBuilder
    private var marker: some View {
        switch kind {
        case .guardPost:
            ShieldMarkerShape()
                .fill(fill)
                .overlay(ShieldMarkerShape().stroke(stroke, lineWidth: 2))
        case .patrol:
            DiamondShape()
                .fill(fill)
                .overlay(DiamondShape().stroke(stroke, lineWidth: 2))
                .overlay(
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .black))
                        .foregroundColor(stroke)
                )
        case .watcher:
            EyeMarkerShape()
                .fill(fill)
                .overlay(EyeMarkerShape().stroke(stroke, lineWidth: markerStrokeWidth))
                .overlay(Circle().fill(stroke).frame(width: 8, height: 8))
        case .rotatingWatcher:
            EyeMarkerShape()
                .fill(fill)
                .overlay(EyeMarkerShape().stroke(stroke, lineWidth: markerStrokeWidth))
                .overlay(
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(stroke)
                )
        case .chaser:
            ChaserMarkerShape()
                .fill(fill)
                .overlay(ChaserMarkerShape().stroke(stroke, lineWidth: 2))
        case .marker:
            TriangleShape()
                .fill(fill)
                .overlay(TriangleShape().stroke(stroke, lineWidth: 2))
                .overlay(
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 15, weight: .black))
                        .foregroundColor(stroke)
                )
        }
    }

    private var markerFrameSize: CGSize {
        switch kind {
        case .rotatingWatcher:
            return CGSize(width: 40, height: 38)
        default:
            return CGSize(width: 31, height: 31)
        }
    }

    private var markerStrokeWidth: CGFloat {
        kind == .rotatingWatcher ? 1.6 : 2
    }

    private var fill: Color {
        switch kind {
        case .guardPost:
            return Color.red.opacity(0.24)
        case .patrol:
            return Color.orange.opacity(0.24)
        case .watcher:
            return Color.pink.opacity(0.22)
        case .rotatingWatcher:
            return .clear
        case .chaser:
            return Color.teal.opacity(0.24)
        case .marker:
            return Color.yellow.opacity(0.28)
        }
    }

    private var stroke: Color {
        switch kind {
        case .guardPost:
            return .red
        case .patrol:
            return .orange
        case .watcher:
            return .pink
        case .rotatingWatcher:
            return .indigo
        case .chaser:
            return .teal
        case .marker:
            return .yellow
        }
    }
}

// MARK: - マス辞典行
private struct TileEncyclopediaRow: View {
    let entry: TileEncyclopediaEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TileMarkerPreviewView(kind: entry.previewKind)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.displayName)
                    .font(.headline)
                Text(entry.description)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - マス辞典用プレビュー
private struct TileMarkerPreviewView: View {
    let kind: TileMarkerPreviewKind

    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppTheme {
        AppTheme(colorScheme: colorScheme)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(tileFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(theme.boardGridLine.opacity(0.72), lineWidth: 1)
                )

            marker
        }
        .frame(width: 48, height: 48)
        .fixedSize()
    }

    private var tileFill: Color {
        switch kind {
        case .normal,
             .spawn,
             .target,
             .nextTarget,
             .multiVisit,
             .dungeonExit,
             .lockedDungeonExit,
             .dungeonKey,
             .cardPickup,
             .damageTrap,
             .healingTile,
             .brittleFloor,
             .enemyDanger,
             .enemyWarning,
             .effect:
            return theme.boardTileUnvisited
        case .toggle:
            return theme.boardTileToggle
        case .impassable,
             .collapsedFloor:
            return theme.boardTileImpassable
        }
    }

    @ViewBuilder
    private var marker: some View {
        switch kind {
        case .normal:
            EmptyView()
        case .spawn:
            Circle()
                .fill(theme.boardKnight)
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(theme.startMarkerStroke, lineWidth: 2))
        case .target,
             .nextTarget:
            DiamondShape()
                .fill(theme.boardWarpHighlight.opacity(0.94))
                .frame(width: 26, height: 26)
        case .multiVisit:
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(theme.boardTileMultiStroke, lineWidth: 2)
                    .padding(5)
                Text("2")
                    .font(.caption.weight(.bold))
                    .foregroundColor(theme.boardTileMultiStroke)
            }
        case .toggle:
            ZStack {
                DiagonalHalfShape(isTopLeft: true)
                    .fill(theme.boardTileUnvisited)
                DiagonalHalfShape(isTopLeft: false)
                    .fill(theme.boardTileVisited)
                DiagonalLineShape()
                    .stroke(theme.boardTileMultiStroke, lineWidth: 1.4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        case .dungeonExit:
            VStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(theme.boardKnight.opacity(0.88))
                        .frame(width: CGFloat(12 + index * 6), height: 4)
                }
            }
        case .lockedDungeonExit:
            ZStack {
                VStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(theme.boardKnight.opacity(0.42))
                            .frame(width: CGFloat(12 + index * 6), height: 4)
                    }
                }
                Image(systemName: "lock.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(theme.boardTileEffectPreserveCard)
                    .offset(y: -11)
            }
        case .dungeonKey:
            Image(systemName: "key.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(theme.boardTileEffectPreserveCard)
        case .cardPickup:
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(theme.cardBackgroundHand)
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(theme.cardBorderHand.opacity(0.8), lineWidth: 1.5)
                )
                .frame(width: 22, height: 30)
                .overlay(
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(theme.cardContentPrimary)
                )
        case .damageTrap:
            ZStack {
                TriangleShape()
                    .fill(theme.boardTileEffectSlow.opacity(0.22))
                    .frame(width: 32, height: 28)
                    .rotationEffect(.degrees(180))
                Image(systemName: "exclamationmark")
                    .font(.system(size: 19, weight: .black))
                    .foregroundColor(theme.boardTileEffectSlow)
            }
        case .healingTile:
            ZStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.green)
                    .frame(width: 9, height: 30)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.green)
                    .frame(width: 30, height: 9)
            }
        case .brittleFloor:
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 17, y: 10))
                    path.addLine(to: CGPoint(x: 23, y: 20))
                    path.addLine(to: CGPoint(x: 18, y: 28))
                    path.addLine(to: CGPoint(x: 26, y: 38))
                }
                .stroke(theme.boardTileMultiStroke, lineWidth: 2)
                Path { path in
                    path.move(to: CGPoint(x: 32, y: 13))
                    path.addLine(to: CGPoint(x: 27, y: 23))
                    path.addLine(to: CGPoint(x: 33, y: 33))
                }
                .stroke(theme.boardTileMultiStroke.opacity(0.72), lineWidth: 1.6)
            }
        case .collapsedFloor:
            Image(systemName: "xmark")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white.opacity(0.78))
        case .enemyDanger:
            Circle()
                .fill(theme.boardTileEffectSlow.opacity(0.18))
                .overlay(Circle().stroke(theme.boardTileEffectSlow, lineWidth: 2))
                .frame(width: 31, height: 31)
                .overlay(
                    Image(systemName: "eye.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(theme.boardTileEffectSlow)
                )
        case .enemyWarning:
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(theme.boardTileEffectPreserveCard.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(theme.boardTileEffectPreserveCard, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                )
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(theme.boardTileEffectPreserveCard)
                )
        case .impassable:
            Image(systemName: "xmark")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white.opacity(0.78))
        case .effect(let effect):
            TileEffectMarkerView(effect: effect, theme: theme)
        }
    }
}

private struct TileEffectMarkerView: View {
    let effect: TileEffect
    let theme: AppTheme

    var body: some View {
        switch effect {
        case .warp:
            ZStack {
                Circle()
                    .stroke(accent, lineWidth: 2.2)
                    .frame(width: 31, height: 31)
                Circle()
                    .stroke(accent.opacity(0.75), lineWidth: 1.8)
                    .frame(width: 21, height: 21)
            }
        case .shuffleHand:
            ZStack {
                DiamondShape()
                    .stroke(accent, lineWidth: 2.2)
                    .frame(width: 31, height: 31)
                TriangleShape()
                    .fill(accent.opacity(0.88))
                    .frame(width: 12, height: 10)
                    .rotationEffect(.degrees(45))
                    .offset(x: -4, y: 0)
                TriangleShape()
                    .fill(accent.opacity(0.62))
                    .frame(width: 12, height: 10)
                    .rotationEffect(.degrees(225))
                    .offset(x: 6, y: 0)
            }
        case .blast(let direction):
            ZStack {
                BlastArrowShape()
                    .fill(accent.opacity(0.92))
                    .frame(width: 24, height: 30)
                BlastArrowShape()
                    .fill(accent.opacity(0.64))
                    .frame(width: 16, height: 22)
                    .offset(y: -5)
            }
            .rotationEffect(blastArrowRotation(for: direction))
        case .slow:
            ZStack {
                DiamondShape()
                    .fill(accent.opacity(0.14))
                    .frame(width: 31, height: 31)
                DiamondShape()
                    .stroke(accent.opacity(0.88), lineWidth: 2.1)
                    .frame(width: 31, height: 31)
                BoltShape()
                    .fill(accent.opacity(0.94))
                    .frame(width: 17, height: 25)
                BoltShape()
                    .fill(accent.opacity(0.68))
                    .frame(width: 8, height: 13)
                    .rotationEffect(.degrees(-18))
                    .offset(x: -11, y: 0)
                BoltShape()
                    .fill(accent.opacity(0.62))
                    .frame(width: 7, height: 12)
                    .rotationEffect(.degrees(162))
                    .offset(x: 12, y: 1)
            }
        case .preserveCard:
            ZStack {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(accent, lineWidth: 2)
                    .frame(width: 20, height: 26)
                Capsule()
                    .fill(accent.opacity(0.88))
                    .frame(width: 14, height: 4)
                    .offset(y: -5)
            }
        }
    }

    private var accent: Color {
        switch effect {
        case .warp:
            return theme.boardTileEffectWarp
        case .shuffleHand:
            return theme.boardTileEffectShuffle
        case .blast:
            return theme.boardTileEffectBlast
        case .slow:
            return theme.boardTileEffectSlow
        case .preserveCard:
            return theme.boardTileEffectPreserveCard
        }
    }
}

private struct DiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

private struct BlastArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let shaftWidth = rect.width * 0.34
        let shaftLeft = rect.midX - shaftWidth / 2
        let shaftRight = rect.midX + shaftWidth / 2
        let shaftTop = rect.minY + rect.height * 0.52

        path.move(to: CGPoint(x: shaftLeft, y: rect.maxY))
        path.addLine(to: CGPoint(x: shaftRight, y: rect.maxY))
        path.addLine(to: CGPoint(x: shaftRight, y: shaftTop))
        path.addLine(to: CGPoint(x: rect.maxX, y: shaftTop))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: shaftTop))
        path.addLine(to: CGPoint(x: shaftLeft, y: shaftTop))
        path.closeSubpath()
        return path
    }
}

private func blastArrowRotation(for direction: MoveVector) -> Angle {
    if direction.dx > 0 { return .degrees(90) }
    if direction.dx < 0 { return .degrees(-90) }
    if direction.dy < 0 { return .degrees(180) }
    return .degrees(0)
}

private struct ShieldMarkerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX * 0.86, y: rect.minY + rect.height * 0.22))
        path.addLine(to: CGPoint(x: rect.maxX * 0.76, y: rect.minY + rect.height * 0.72))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.24, y: rect.minY + rect.height * 0.72))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.14, y: rect.minY + rect.height * 0.22))
        path.closeSubpath()
        return path
    }
}

private struct EyeMarkerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control: CGPoint(x: rect.midX, y: rect.minY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.midY),
            control: CGPoint(x: rect.midX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

private struct ChaserMarkerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        addFootprint(
            to: &path,
            center: CGPoint(x: rect.minX + rect.width * 0.34, y: rect.minY + rect.height * 0.38),
            size: rect.size
        )
        addFootprint(
            to: &path,
            center: CGPoint(x: rect.minX + rect.width * 0.66, y: rect.minY + rect.height * 0.62),
            size: rect.size
        )
        return path
    }

    private func addFootprint(to path: inout Path, center: CGPoint, size: CGSize) {
        let baseWidth = size.width * 0.18
        let baseHeight = size.height * 0.25
        path.addEllipse(in: CGRect(
            x: center.x - baseWidth / 2,
            y: center.y - baseHeight / 2,
            width: baseWidth,
            height: baseHeight
        ))

        let toeY = center.y - size.height * 0.18
        for offset in [-size.width * 0.08, 0, size.width * 0.08] {
            let toeSize = size.width * 0.06
            path.addEllipse(in: CGRect(
                x: center.x + offset - toeSize / 2,
                y: toeY - toeSize / 2,
                width: toeSize,
                height: toeSize
            ))
        }
    }
}

private struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct ChevronShape: Shape {
    func path(in rect: CGRect) -> Path {
        let thickness = rect.height * 0.38
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - thickness))
        path.addLine(to: CGPoint(x: rect.maxX - thickness, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + thickness))
        path.addLine(to: CGPoint(x: rect.minX + thickness, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - thickness))
        path.closeSubpath()
        return path
    }
}

private struct BoltShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX + rect.width * 0.05, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.04, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.34, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.14, y: rect.midY - rect.height * 0.05))
        path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.08, y: rect.midY - rect.height * 0.05))
        path.closeSubpath()
        return path
    }
}

private struct DiagonalHalfShape: Shape {
    let isTopLeft: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if isTopLeft {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        path.closeSubpath()
        return path
    }
}

private struct DiagonalLineShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return path
    }
}

// MARK: - 共通セクション描画用サブビュー
private struct HowToPlaySectionView: View {
    /// セクションタイトル
    let title: String
    /// 説明文
    let description: String
    /// 例示するカード（任意）
    let card: MoveCard?
    /// 補足のポイント一覧
    let tips: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: - タイトル
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)

            // MARK: - 説明文
            Text(description)
                .font(.body)

            // MARK: - カード挙動の例
            if let card {
                MoveCardIllustrationView(card: card)
                    .frame(height: 180)
                    .padding(.vertical, 4)
            }

            // MARK: - 補足事項のリスト
            VStack(alignment: .leading, spacing: 6) {
                ForEach(tips.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                            .padding(.top, 2)
                        Text(tips[index])
                            .font(.callout)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }
}

#Preview {
    NavigationStack {
        HowToPlayView()
    }
}
