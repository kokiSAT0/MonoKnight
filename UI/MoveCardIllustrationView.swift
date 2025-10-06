import SwiftUI
import Game // Game モジュールから MoveCard 型などを利用するために読み込む

/// 移動カードの内容を視覚的に表現するビュー
/// 5×5 のグリッドと現在地・目的地・矢印を描画し、カードの効果を直感的に伝える
struct MoveCardIllustrationView: View {
    /// 表示モード。手札表示と先読み表示で配色やアクセシビリティ設定を切り替えるための列挙体
    enum Mode {
        case hand
        case next

        /// 背景色（RoundedRectangle 内部）をモードごとに返す
        /// - Parameter theme: アプリ共通のテーマから色を取得
        func backgroundColor(using theme: AppTheme) -> Color {
            switch self {
            case .hand:
                return theme.cardBackgroundHand
            case .next:
                return theme.cardBackgroundNext
            }
        }

        /// 枠線の色をモードに応じて返す
        /// - Parameter theme: アプリ共通テーマ
        func borderColor(using theme: AppTheme) -> Color {
            switch self {
            case .hand:
                return theme.cardBorderHand
            case .next:
                return theme.cardBorderNext
            }
        }

        /// 枠線の太さ。先読みはやや太めにして区別しやすくする
        var borderLineWidth: CGFloat {
            switch self {
            case .hand:
                return 1
            case .next:
                return 1.4
            }
        }

        /// 盤面中央セルのハイライト色
        /// - Parameter theme: アプリ共通テーマ
        func centerHighlightColor(using theme: AppTheme) -> Color {
            switch self {
            case .hand:
                return theme.centerHighlightHand
            case .next:
                return theme.centerHighlightNext
            }
        }

        /// グリッド線の色（手札よりもコントラストを強める）
        /// - Parameter theme: アプリ共通テーマ
        func gridLineColor(using theme: AppTheme) -> Color {
            switch self {
            case .hand:
                return theme.gridLineHand
            case .next:
                return theme.gridLineNext
            }
        }

        /// 矢印や目的地マーカーの色（モード共通）
        /// - Parameter theme: アプリ共通テーマ
        func arrowColor(using theme: AppTheme) -> Color {
            theme.cardContentPrimary
        }

        /// VoiceOver で追加説明が必要な場合の末尾テキスト
        /// - Parameter candidateCount: 移動候補の数
        /// - Returns: 候補数に応じた補足テキスト
        func accessibilitySuffix(forCandidateCount candidateCount: Int) -> String {
            switch self {
            case .hand:
                // 手札表示では複数候補がある際にだけ補足を入れて注意を促す
                return candidateCount > 1 ? "（複数方向の候補あり）" : ""
            case .next:
                // 先読み表示では従来の文言に候補情報を足して状況を明確にする
                return candidateCount > 1
                    ? "（次に補充されるカード／複数方向）"
                    : "（次に補充されるカード）"
            }
        }

        /// VoiceOver のヒント文（モード別に内容を分けて案内する）
        /// - Parameter candidateCount: 移動候補の数
        /// - Returns: 候補数に応じて読み上げる説明文
        func accessibilityHint(forCandidateCount candidateCount: Int) -> String {
            switch self {
            case .hand:
                switch candidateCount {
                case ..<1:
                    // 想定外ケースでもクラッシュせず説明できるようにする
                    return "ダブルタップでカードを選択しますが、移動候補が未設定です"
                case 1:
                    return "ダブルタップでこの方向に移動します"
                default:
                    return "ダブルタップでカードを選択し、盤面で移動方向を決めてください。候補は \(candidateCount) 方向です。"
                }
            case .next:
                switch candidateCount {
                case ..<1:
                    return "閲覧のみ: このカードは移動候補が未設定です。手札が消費された後に補充されます"
                case 1:
                    return "閲覧のみ: このカードは手札が消費された後に補充されます"
                default:
                    return "閲覧のみ: 手札が消費された後に補充され、最大 \(candidateCount) 方向から選択して移動できます"
                }
            }
        }

        /// 連続直進カード専用の VoiceOver ヒント
        /// - Returns: 手札と先読みで内容を切り替えた説明文
        func multiStepAccessibilityHint() -> String {
            switch self {
            case .hand:
                return "ダブルタップでカードを選択すると、盤外や障害物の手前で停止するまで直進します。通過したマスも踏破されます"
            case .next:
                return "閲覧のみ: 手札が補充される際に使用でき、盤外や障害物の手前で停止するまで直進します"
            }
        }

        /// 追加で付与するアクセシビリティトレイト
        var traitsToAdd: AccessibilityTraits {
            switch self {
            case .hand:
                return .isButton
            case .next:
                return .isStaticText
            }
        }

        /// 除外したいアクセシビリティトレイト
        var traitsToRemove: AccessibilityTraits {
            switch self {
            case .hand:
                return .isStaticText
            case .next:
                return .isButton
            }
        }
    }

    /// 表示対象の移動カード
    let card: MoveCard
    /// 現在の表示モード（デフォルトは手札表示）
    var mode: Mode = .hand
    /// カラースキームに応じて派生色を提供するテーマ
    private var theme = AppTheme()
    /// カラースキームを直接参照し、アクセント記号の明度調整などへ利用する
    @Environment(\.colorScheme) private var colorScheme
    /// 手札やプレースホルダで共有する標準幅（カードを少し大きくするため 66pt に設定）
    static let defaultWidth: CGFloat = 66
    /// 標準の高さ。幅とのバランスを保ちつつ視認性を高める
    static let defaultHeight: CGFloat = 90

    /// HowToPlayView など別ファイルからの生成時にアクセス保護レベルの問題が発生しないよう、明示的なイニシャライザを用意する
    /// - Parameters:
    ///   - card: 描画対象となる移動カード
    ///   - mode: 手札表示か先読み表示かのモード（既定値は手札表示）
    ///   - theme: テーマカラー（基本的には既定値をそのまま使用）
    init(card: MoveCard, mode: Mode = .hand, theme: AppTheme = AppTheme()) {
        // MARK: - ストアドプロパティの初期化
        // 日本語コメントを多めに配置して可読性を高める
        self.card = card
        self.mode = mode
        self.theme = theme
    }

    var body: some View {
        // MARK: - 描画に利用する移動候補の事前計算
        // movementVectors をローカル定数へ保持し、アクセシビリティと描画の両方で使い回す
        let movementVectors = card.movementVectors
        let candidateCount = movementVectors.count
        let isMultiStepCard = card.kind == .multiStep
        let multiStepDirection = card.multiStepUnitVector
        // MARK: - 枠線色の決定（選択カードや複数マス移動カードで個別に色を差し替える）
        let isSelectionCard = card.kind == .choice
        let borderColor: Color
        if isMultiStepCard {
            // 複数マス移動カードはシアン系アクセントを枠線へ適用し、盤面ハイライトと一貫した印象を持たせる
            borderColor = theme.multiStepAccent
        } else if isSelectionCard {
            // 選択式カードは既存仕様通りオレンジ枠を優先する
            borderColor = theme.boardGuideHighlight
        } else {
            // 通常カードはモード別の標準枠色を利用する
            borderColor = mode.borderColor(using: theme)
        }

        // MARK: - アクセシビリティ文言の組み立て
        let accessibilityLabelText: Text
        let accessibilityHintText: Text
        if isMultiStepCard, let direction = multiStepDirection {
            let directionName = multiStepDirectionDisplayName(for: direction)
            accessibilityLabelText = Text("複数マス移動カード、方向：\(directionName)。進めなくなるまで直進")
            accessibilityHintText = Text(mode.multiStepAccessibilityHint())
        } else {
            accessibilityLabelText = Text(card.displayName + mode.accessibilitySuffix(forCandidateCount: candidateCount))
            accessibilityHintText = Text(mode.accessibilityHint(forCandidateCount: candidateCount))
        }

        // すべてのカードで共通の余白設定を用い、シアン枠を含めた視認性を確保する
        let paddingInsets = EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)

        return ZStack {
            // MARK: - カードの背景枠
            // 既存のカードスタイル（角丸の枠付き）を踏襲して統一感を保つ
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: mode.borderLineWidth)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(mode.backgroundColor(using: theme))
                )

            VStack(spacing: 0) {
                // MARK: - 盤面イメージ
                // 正方形の領域に 5×5 グリッドと経路を描画する
                GeometryReader { geometry in
                    let layout = gridLayout(for: geometry.size)
                    let squareSize = layout.squareSize
                    let cellSize = layout.cellSize
                    let origin = layout.origin

                    let center = gridCenterIndex
                    let startPoint = cellCenter(origin: origin, cellSize: cellSize, column: center.column, row: center.row)

                    ZStack {
                        // MARK: 中央マスのハイライト
                        Rectangle()
                            .fill(mode.centerHighlightColor(using: theme))
                            .frame(width: cellSize, height: cellSize)
                            .position(startPoint)

                        // MARK: グリッド線（縦横 5 分割）
                        Path { path in
                            for index in 0...gridCount {
                                let x = origin.x + CGFloat(index) * cellSize
                                path.move(to: CGPoint(x: x, y: origin.y))
                                path.addLine(to: CGPoint(x: x, y: origin.y + squareSize))
                            }
                            for index in 0...gridCount {
                                let y = origin.y + CGFloat(index) * cellSize
                                path.move(to: CGPoint(x: origin.x, y: y))
                                path.addLine(to: CGPoint(x: origin.x + squareSize, y: y))
                            }
                        }
                        .stroke(mode.gridLineColor(using: theme), lineWidth: 0.5)

                        if isMultiStepCard, let direction = multiStepDirection,
                           let route = multiStepRoute(direction: direction, origin: origin, cellSize: cellSize, centerIndex: center) {
                            let accentColor = theme.multiStepAccent
                            let lineWidth = min(max(cellSize * 0.18, 1.8), 2.6)

                            // MARK: 複数マス移動カードの経路ライン
                            Path { path in
                                path.move(to: startPoint)
                                path.addLine(to: route.endPoint)
                            }
                            .stroke(accentColor.opacity(0.82), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                            .shadow(color: accentColor.opacity(0.25), radius: 4)
                            .accessibilityHidden(true)

                            // MARK: 通過マスのドット（終端を除外）
                            let dotDiameter = min(6, cellSize * 0.45)
                            ForEach(Array(route.stepCenters.dropLast().enumerated()), id: \.offset) { _, point in
                                Circle()
                                    .fill(accentColor.opacity(0.75))
                                    .frame(width: dotDiameter, height: dotDiameter)
                                    .position(point)
                                    .accessibilityHidden(true)
                            }

                            // MARK: 終端リングと内部記号
                            let ringDiameter = min(cellSize * 1.3, 18)
                            let ringLineWidth = max(ringDiameter * 0.14, 1.2)
                            Circle()
                                .stroke(accentColor, lineWidth: ringLineWidth)
                                .frame(width: ringDiameter, height: ringDiameter)
                                .position(route.endPoint)
                                .shadow(color: accentColor.opacity(0.28), radius: 3)
                                .accessibilityHidden(true)

                            let crossSize = ringDiameter * 0.55
                            Path { path in
                                path.move(to: CGPoint(x: route.endPoint.x - crossSize / 2, y: route.endPoint.y - crossSize / 2))
                                path.addLine(to: CGPoint(x: route.endPoint.x + crossSize / 2, y: route.endPoint.y + crossSize / 2))
                                path.move(to: CGPoint(x: route.endPoint.x + crossSize / 2, y: route.endPoint.y - crossSize / 2))
                                path.addLine(to: CGPoint(x: route.endPoint.x - crossSize / 2, y: route.endPoint.y + crossSize / 2))
                            }
                            .stroke(Color.white.opacity(colorScheme == .dark ? 0.4 : 0.3), style: StrokeStyle(lineWidth: ringLineWidth * 0.6, lineCap: .round))
                            .accessibilityHidden(true)
                        } else {
                            // MARK: 従来カードの矢印と目的地マーカー
                            let arrowGeometries: [(destination: CGPoint, head: (CGPoint, CGPoint)?)] = movementVectors.map { vector in
                                let destinationIndex = destinationCellIndex(for: vector)
                                let destinationPoint = cellCenter(
                                    origin: origin,
                                    cellSize: cellSize,
                                    column: destinationIndex.column,
                                    row: destinationIndex.row
                                )
                                let headPoints = arrowHeadPoints(
                                    startPoint: startPoint,
                                    destinationPoint: destinationPoint,
                                    arrowHeadLength: cellSize * 0.5,
                                    arrowHeadWidth: cellSize * 0.4
                                )
                                return (destinationPoint, headPoints)
                            }

                            ForEach(Array(arrowGeometries.enumerated()), id: \.offset) { _, geometry in
                                Path { path in
                                    path.move(to: startPoint)
                                    path.addLine(to: geometry.destination)
                                }
                                .stroke(mode.arrowColor(using: theme), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                                .accessibilityHidden(true)

                                if let (leftPoint, rightPoint) = geometry.head {
                                    Path { path in
                                        path.move(to: geometry.destination)
                                        path.addLine(to: leftPoint)
                                        path.addLine(to: rightPoint)
                                        path.closeSubpath()
                                    }
                                    .fill(mode.arrowColor(using: theme))
                                    .accessibilityHidden(true)
                                }

                                Circle()
                                    .fill(theme.cardContentInverted)
                                    .frame(width: cellSize * 0.4, height: cellSize * 0.4)
                                    .overlay(
                                        Circle()
                                            .stroke(theme.destinationMarkerStroke, lineWidth: 1)
                                    )
                                    .position(geometry.destination)
                                    .accessibilityHidden(true)
                            }
                        }

                        // MARK: 現在地マーカー（常に最前面）
                        Circle()
                            .fill(theme.cardContentPrimary)
                            .frame(width: cellSize * 0.4, height: cellSize * 0.4)
                            .overlay(
                                Circle()
                                    .stroke(theme.startMarkerStroke, lineWidth: 1)
                            )
                            .position(startPoint)
                            .accessibilityHidden(true)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
            }
            .padding(paddingInsets)
        }
        .frame(width: Self.defaultWidth, height: Self.defaultHeight)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint(accessibilityHintText)
        .accessibilityAddTraits(mode.traitsToAdd)
        .accessibilityRemoveTraits(mode.traitsToRemove)
        .allowsHitTesting(mode == .hand)
    }
}

/// 手札スタックの視覚表現を担当する補助ビュー
/// 最上段のカード（`content`）をそのまま表示しつつ、残枚数に応じて背景へカードをずらして重ねる
struct HandStackCardView<Content: View>: View {
    /// スタック内のカード枚数
    let stackCount: Int
    /// トップカードの描画内容（`MoveCardIllustrationView` など）
    private let content: Content
    /// カラーテーマを共有し、ライト/ダークで見やすい配色に調整する
    private var theme = AppTheme()

    /// - Parameters:
    ///   - stackCount: スタック内のカード枚数
    ///   - content: 最前面に配置するカードビュー
    init(stackCount: Int, @ViewBuilder content: () -> Content) {
        self.stackCount = stackCount
        self.content = content()
    }

    /// 背景として描画する追加カードの枚数（最大 3 枚まで重ねる）
    private var backgroundLayerCount: Int {
        max(0, min(stackCount - 1, 3))
    }

    /// 枚数に応じてバッジへ表示する文字列
    private var badgeText: String { "×\(stackCount)" }

    var body: some View {
        content
            // 枚数が 2 枚以上のときは右上にバッジを重ねる
            .overlay(alignment: .topTrailing) {
                if stackCount > 1 {
                    stackCountBadge
                        .padding(6)
                        .accessibilityHidden(true)
                }
            }
            // 背景側に重ねるカードを描画し、スタックらしい厚みを演出する
            .background {
                ZStack(alignment: .center) {
                    ForEach(0..<backgroundLayerCount, id: \.self) { index in
                        let offset = CGFloat(index + 1) * 4
                        RoundedRectangle(cornerRadius: 8)
                            .fill(theme.cardBackgroundHand.opacity(0.55))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(theme.cardBorderHand.opacity(0.35), lineWidth: 1)
                            )
                            .shadow(color: theme.cardBorderHand.opacity(0.18), radius: 4, x: 0, y: 2)
                            .offset(x: offset, y: offset)
                            .accessibilityHidden(true)
                    }
                }
            }
            // 影付きの背景と前景をまとめてレンダリングし、合成時のズレを防ぐ
            .compositingGroup()
    }

    /// スタック枚数を知らせるバッジ（角丸カプセル）
    private var stackCountBadge: some View {
        Text(badgeText)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(theme.accentPrimary.opacity(0.92))
            )
            .overlay(
                Capsule()
                    .stroke(theme.cardBorderHand.opacity(0.6), lineWidth: 0.5)
            )
            .foregroundColor(theme.accentOnPrimary)
    }
}

// MARK: - 座標計算ヘルパー
private extension MoveCardIllustrationView {
    /// グリッドの縦横数（5×5 固定）
    var gridCount: Int { 5 }

    /// 盤面中央セルの添字（常に (2,2) ）
    var gridCenterIndex: (column: Int, row: Int) {
        (gridCount / 2, gridCount / 2)
    }

    /// 利用可能領域から正方形のレイアウト情報を算出する
    /// - Parameter size: GeometryReader が提供する領域のサイズ
    /// - Returns: 正方形の一辺・セルサイズ・描画原点をまとめたタプル
    func gridLayout(for size: CGSize) -> (squareSize: CGFloat, cellSize: CGFloat, origin: CGPoint) {
        let squareSize = min(size.width, size.height)
        let cellSize = squareSize / CGFloat(gridCount)
        let originX = (size.width - squareSize) / 2.0
        let originY = (size.height - squareSize) / 2.0
        return (squareSize, cellSize, CGPoint(x: originX, y: originY))
    }

    /// 指定したセルの中心座標を算出する
    /// - Parameters:
    ///   - origin: 正方形レイアウトの左上基準点
    ///   - cellSize: 各セルの一辺
    ///   - column: 対象セルの列添字
    ///   - row: 対象セルの行添字（上方向が小さくなるよう変換済み）
    /// - Returns: 対応する CGPoint 座標
    func cellCenter(origin: CGPoint, cellSize: CGFloat, column: Int, row: Int) -> CGPoint {
        CGPoint(
            x: origin.x + (CGFloat(column) + 0.5) * cellSize,
            y: origin.y + (CGFloat(row) + 0.5) * cellSize
        )
    }

    /// 移動ベクトルから目的地セルの添字を取得する
    /// - Parameter vector: 描画対象となる移動ベクトル
    /// - Returns: 中央セル基準で算出した目的地の添字
    func destinationCellIndex(for vector: MoveVector) -> (column: Int, row: Int) {
        let center = gridCenterIndex
        // dy は数学的な Y 軸（上方向）基準なので、SwiftUI 座標系へ合わせるために符号を反転する
        return (center.column + vector.dx, center.row - vector.dy)
    }

    /// 矢印の先端（三角形）の 2 点を計算する
    /// - Parameters:
    ///   - startPoint: 矢印の始点（現在地）
    ///   - destinationPoint: 矢印の終点（目的地）
    ///   - arrowHeadLength: 矢じりの長さ
    ///   - arrowHeadWidth: 矢じりの幅
    /// - Returns: 左右 2 点の座標（移動量がゼロの場合は nil）
    func arrowHeadPoints(startPoint: CGPoint, destinationPoint: CGPoint, arrowHeadLength: CGFloat, arrowHeadWidth: CGFloat) -> (CGPoint, CGPoint)? {
        let vector = CGVector(dx: destinationPoint.x - startPoint.x, dy: destinationPoint.y - startPoint.y)
        let vectorLength = hypot(vector.dx, vector.dy)

        guard vectorLength > 0 else {
            // 矢印の長さがゼロの場合は矢じりを描画しない
            return nil
        }

        let unit = CGVector(dx: vector.dx / vectorLength, dy: vector.dy / vectorLength)
        let basePoint = CGPoint(
            x: destinationPoint.x - unit.dx * arrowHeadLength,
            y: destinationPoint.y - unit.dy * arrowHeadLength
        )
        let perpendicular = CGVector(dx: -unit.dy, dy: unit.dx)
        let leftPoint = CGPoint(
            x: basePoint.x + perpendicular.dx * arrowHeadWidth / 2.0,
            y: basePoint.y + perpendicular.dy * arrowHeadWidth / 2.0
        )
        let rightPoint = CGPoint(
            x: basePoint.x - perpendicular.dx * arrowHeadWidth / 2.0,
            y: basePoint.y - perpendicular.dy * arrowHeadWidth / 2.0
        )
        return (leftPoint, rightPoint)
    }

    /// 連続直進カードの経路を算出する
    /// - Parameters:
    ///   - direction: 1 ステップあたりの方向ベクトル
    ///   - origin: グリッド描画の左上原点
    ///   - cellSize: 各セルの一辺
    ///   - centerIndex: 中央セルの添字
    /// - Returns: 通過セル中心座標と終端座標を含む経路情報
    func multiStepRoute(
        direction: MoveVector,
        origin: CGPoint,
        cellSize: CGFloat,
        centerIndex: (column: Int, row: Int)
    ) -> MultiStepRoute? {
        var stepCenters: [CGPoint] = []
        var step = 1

        while true {
            let column = centerIndex.column + direction.dx * step
            let row = centerIndex.row - direction.dy * step
            guard (0..<gridCount).contains(column), (0..<gridCount).contains(row) else { break }

            let point = cellCenter(origin: origin, cellSize: cellSize, column: column, row: row)
            stepCenters.append(point)
            step += 1
        }

        guard let endPoint = stepCenters.last else { return nil }
        return MultiStepRoute(stepCenters: stepCenters, endPoint: endPoint)
    }

    /// 複数マス移動カードの方向ラベルを返す
    /// - Parameter vector: 1 ステップ分の方向ベクトル
    /// - Returns: 日本語の方位名
    func multiStepDirectionDisplayName(for vector: MoveVector) -> String {
        switch (vector.dx, vector.dy) {
        case (0, 1): return "北"
        case (1, 1): return "北東"
        case (1, 0): return "東"
        case (1, -1): return "南東"
        case (0, -1): return "南"
        case (-1, -1): return "南西"
        case (-1, 0): return "西"
        case (-1, 1): return "北西"
        default: return "直進"
        }
    }

    /// 複数マス移動カードの経路を保持する内部構造体
    struct MultiStepRoute {
        /// 通過セルの中心座標（終端を含む）
        let stepCenters: [CGPoint]
        /// 最終停止地点の座標
        let endPoint: CGPoint
    }
}

// MARK: - プレビュー
#Preview {
    VStack(spacing: 12) {
        // 手札用と先読み用を並べて配色の差分を確認できるようにする
        MoveCardIllustrationView(card: .rayRight, mode: .hand)
        MoveCardIllustrationView(card: .knightUp2Right1, mode: .hand)
        MoveCardIllustrationView(card: .diagonalDownLeft2, mode: .next)
    }
    .padding()
    // プレビューでもテーマカラーを利用し、本番画面と同等の見た目を確認する
    .background(Color("backgroundPrimary"))
}
