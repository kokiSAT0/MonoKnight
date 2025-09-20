import SwiftUI
import Game // Game モジュールから MoveCard 型などを利用するために読み込む

/// 移動カードの内容を視覚的に表現するビュー
/// 5×5 のグリッドと現在地・目的地・移動方向を描画してカード効果を直感的に把握できるようにする
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

        /// 中央セルのハイライト色
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

        /// カード名ラベルの文字色
        /// - Parameter theme: アプリ共通テーマ
        func labelColor(using theme: AppTheme) -> Color {
            theme.cardContentPrimary
        }

        /// VoiceOver で追加説明が必要な場合の末尾テキスト
        var accessibilitySuffix: String {
            switch self {
            case .hand:
                return ""
            case .next:
                return "（次に補充されるカード）"
            }
        }

        /// VoiceOver のヒント文（モード別に内容を分けて案内する）
        var accessibilityHint: String {
            switch self {
            case .hand:
                return "ダブルタップでこの方向に移動します"
            case .next:
                return "閲覧のみ: このカードは手札が消費された後に補充されます"
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
        ZStack {
            // MARK: - カードの背景枠
            // 既存のカードスタイル（角丸の枠付き）を踏襲して統一感を保つ
            RoundedRectangle(cornerRadius: 8)
                .stroke(mode.borderColor(using: theme), lineWidth: mode.borderLineWidth)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(mode.backgroundColor(using: theme))
                )

            VStack(spacing: 6) {
                // MARK: - 盤面イメージ
                // 正方形の領域に 5×5 グリッドと矢印などを描画する
                GeometryReader { geometry in
                    // MARK: - 座標計算（ヘルパーで分離）
                    // レイアウト情報（正方形サイズ・セルサイズ・原点）をヘルパーから取得
                    let layout = gridLayout(for: geometry.size)
                    let squareSize = layout.squareSize
                    let cellSize = layout.cellSize
                    let origin = layout.origin

                    // 盤面中央とカードに基づいた目的地のセル位置をそれぞれ取得
                    let center = gridCenterIndex
                    let destinationIndex = destinationCellIndex(for: card)

                    // ヘルパーメソッドでセル中心座標を算出
                    let startPoint = cellCenter(origin: origin, cellSize: cellSize, column: center.column, row: center.row)
                    let destinationPoint = cellCenter(origin: origin, cellSize: cellSize, column: destinationIndex.column, row: destinationIndex.row)

                    // 矢印の頭（三角形）の 2 点は専用の計算ロジックに委譲
                    let arrowHeadVertices = arrowHeadPoints(
                        startPoint: startPoint,
                        destinationPoint: destinationPoint,
                        arrowHeadLength: cellSize * 0.5,
                        arrowHeadWidth: cellSize * 0.4
                    )

                    ZStack {
                        // MARK: 中央マスのハイライト
                        Rectangle()
                            .fill(mode.centerHighlightColor(using: theme))
                            .frame(width: cellSize, height: cellSize)
                            .position(startPoint)

                        // MARK: グリッド線（縦横 5 分割）
                        Path { path in
                            // 縦線を描画
                            for index in 0...gridCount {
                                let x = origin.x + CGFloat(index) * cellSize
                                path.move(to: CGPoint(x: x, y: origin.y))
                                path.addLine(to: CGPoint(x: x, y: origin.y + squareSize))
                            }
                            // 横線を描画
                            for index in 0...gridCount {
                                let y = origin.y + CGFloat(index) * cellSize
                                path.move(to: CGPoint(x: origin.x, y: y))
                                path.addLine(to: CGPoint(x: origin.x + squareSize, y: y))
                            }
                        }
                        .stroke(mode.gridLineColor(using: theme), lineWidth: 0.5)

                        // MARK: 現在地・目的地のマーカー
                        Circle()
                            .fill(theme.cardContentPrimary)
                            .frame(width: cellSize * 0.4, height: cellSize * 0.4)
                            .overlay(
                                Circle()
                                    .stroke(theme.startMarkerStroke, lineWidth: 1)
                            )
                            .position(startPoint)

                        Circle()
                            .fill(theme.cardContentInverted)
                            .frame(width: cellSize * 0.4, height: cellSize * 0.4)
                            .overlay(
                                Circle()
                                    .stroke(theme.destinationMarkerStroke, lineWidth: 1)
                            )
                            .position(destinationPoint)

                        // MARK: 移動方向を示す矢印（線 + 矢じり）
                        Path { path in
                            path.move(to: startPoint)
                            path.addLine(to: destinationPoint)
                        }
                        .stroke(mode.arrowColor(using: theme), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

                        if let (leftPoint, rightPoint) = arrowHeadVertices {
                            Path { path in
                                path.move(to: destinationPoint)
                                path.addLine(to: leftPoint)
                                path.addLine(to: rightPoint)
                                path.closeSubpath()
                            }
                            .fill(mode.arrowColor(using: theme))
                        }
                    }
                }
                .aspectRatio(1, contentMode: .fit)

                // MARK: - カード名の補助ラベル
                // テキストでも方向が確認できるよう小さめのフォントで表示
                Text(card.displayName)
                    .font(.caption2)
                    .foregroundColor(mode.labelColor(using: theme))
            }
            .padding(8)
        }
        .frame(width: 60, height: 80)
        // VoiceOver で方向が伝わるようカード名にモード別の説明を付与
        .accessibilityLabel(Text(card.displayName + mode.accessibilitySuffix))
        // カード操作／先読み閲覧それぞれのヒントを案内
        .accessibilityHint(Text(mode.accessibilityHint))
        // モードによって適切なトレイトを付与し、不要なものは除去する
        .accessibilityAddTraits(mode.traitsToAdd)
        .accessibilityRemoveTraits(mode.traitsToRemove)
        // 先読み表示はタップ不要のためヒットテストも無効化
        .allowsHitTesting(mode == .hand)
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

    /// カードの移動量から目的地セルの添字を取得する
    /// - Parameter card: 描画対象の移動カード
    /// - Returns: 中央セル基準で算出した目的地の添字
    func destinationCellIndex(for card: MoveCard) -> (column: Int, row: Int) {
        let center = gridCenterIndex
        // dy は数学的な Y 軸（上方向）基準なので、SwiftUI 座標系へ合わせるために符号を反転する
        return (center.column + card.dx, center.row - card.dy)
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
}

// MARK: - プレビュー
#Preview {
    VStack(spacing: 12) {
        // 手札用と先読み用を並べて配色の差分を確認できるようにする
        MoveCardIllustrationView(card: .knightUp2Right1, mode: .hand)
        MoveCardIllustrationView(card: .diagonalDownLeft2, mode: .next)
    }
    .padding()
    // プレビューでもテーマカラーを利用し、本番画面と同等の見た目を確認する
    .background(Color("backgroundPrimary"))
}
