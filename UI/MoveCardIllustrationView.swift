import SwiftUI
import Game // Game モジュールから MoveCard 型などを利用するために読み込む

/// 移動カードの内容を視覚的に表現するビュー
/// プレイヤー位置から目的地までの長方形グリッドと矢印のみを描画し、方向を直感的に把握できるようにする
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

            // MARK: - グリッドと矢印のみで移動方向を表現する
            GeometryReader { geometry in
                // MARK: - 使用するマス目のサイズ（移動量から決定）
                let gridSize = gridSize(for: card)
                // MARK: - 枠との余白を確保した上でグリッド全体のレイアウトを算出
                let layout = gridLayout(for: geometry.size, columns: gridSize.columns, rows: gridSize.rows, inset: 6)
                let cellSize = layout.cellSize
                let origin = layout.origin

                // MARK: - 始点と終点のセル位置を算出
                let startIndex = startCellIndex(for: card, gridSize: gridSize)
                let destinationIndex = destinationCellIndex(for: card, gridSize: gridSize)

                // MARK: - セル中心座標を矢印の描画基準として利用
                let startPoint = cellCenter(origin: origin, cellSize: cellSize, column: startIndex.column, row: startIndex.row)
                let destinationPoint = cellCenter(origin: origin, cellSize: cellSize, column: destinationIndex.column, row: destinationIndex.row)

                // MARK: - 矢印の太さ・矢じり寸法をセルサイズから計算
                // 細身でも視認性を維持できるよう、線幅はセルサイズに対する比率をやや抑えつつ最小値を 1.5pt 程度に設定
                let arrowLineWidth = max(cellSize * 0.22, 1.5)
                let vector = CGVector(dx: destinationPoint.x - startPoint.x, dy: destinationPoint.y - startPoint.y)
                let arrowLength = hypot(vector.dx, vector.dy)
                // 矢じりはカード全体のバランスを崩さないよう、長さ・幅ともに控えめな比率へ見直す
                let arrowHeadLength = min(cellSize * 0.6, arrowLength * 0.35)
                let arrowHeadWidth = arrowHeadLength * 0.55
                let arrowHeadVertices = arrowHeadPoints(
                    startPoint: startPoint,
                    destinationPoint: destinationPoint,
                    arrowHeadLength: arrowHeadLength,
                    arrowHeadWidth: arrowHeadWidth
                )

                ZStack {
                    // MARK: グリッド線（縦横）
                    Path { path in
                        // 縦線を描画
                        for column in 0...gridSize.columns {
                            let x = origin.x + CGFloat(column) * cellSize
                            path.move(to: CGPoint(x: x, y: origin.y))
                            path.addLine(to: CGPoint(x: x, y: origin.y + CGFloat(gridSize.rows) * cellSize))
                        }
                        // 横線を描画
                        for row in 0...gridSize.rows {
                            let y = origin.y + CGFloat(row) * cellSize
                            path.move(to: CGPoint(x: origin.x, y: y))
                            path.addLine(to: CGPoint(x: origin.x + CGFloat(gridSize.columns) * cellSize, y: y))
                        }
                    }
                    .stroke(mode.gridLineColor(using: theme), lineWidth: max(cellSize * 0.05, 0.5))

                    // MARK: 移動方向を示す矢印（線 + 矢じり）
                    Path { path in
                        path.move(to: startPoint)
                        path.addLine(to: destinationPoint)
                    }
                    .stroke(mode.arrowColor(using: theme), style: StrokeStyle(lineWidth: arrowLineWidth, lineCap: .round))

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
    /// カードの移動量から最小限のグリッドサイズを算出する
    /// - Parameter card: 描画対象の移動カード
    /// - Returns: 列数と行数をまとめたタプル（最低 1）
    func gridSize(for card: MoveCard) -> (columns: Int, rows: Int) {
        let columns = max(1, abs(card.dx) + 1)
        let rows = max(1, abs(card.dy) + 1)
        return (columns, rows)
    }

    /// 利用可能領域からグリッド全体のレイアウト情報を算出する
    /// - Parameters:
    ///   - size: GeometryReader が提供する領域のサイズ
    ///   - columns: グリッドの列数
    ///   - rows: グリッドの行数
    ///   - inset: 角丸枠との距離を保つための余白
    /// - Returns: セルサイズと描画原点をまとめたタプル
    func gridLayout(for size: CGSize, columns: Int, rows: Int, inset: CGFloat) -> (cellSize: CGFloat, origin: CGPoint) {
        let availableWidth = max(size.width - inset * 2.0, 0)
        let availableHeight = max(size.height - inset * 2.0, 0)
        let cellSize = min(availableWidth / CGFloat(columns), availableHeight / CGFloat(rows))
        let gridWidth = cellSize * CGFloat(columns)
        let gridHeight = cellSize * CGFloat(rows)
        let originX = (size.width - gridWidth) / 2.0
        let originY = (size.height - gridHeight) / 2.0
        return (cellSize, CGPoint(x: originX, y: originY))
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

    /// 始点セルの添字を取得する
    /// - Parameters:
    ///   - card: 描画対象の移動カード
    ///   - gridSize: 列数・行数の情報
    /// - Returns: 始点セルの列・行添字
    func startCellIndex(for card: MoveCard, gridSize: (columns: Int, rows: Int)) -> (column: Int, row: Int) {
        let startColumn = card.dx >= 0 ? 0 : gridSize.columns - 1
        let startRow = card.dy >= 0 ? gridSize.rows - 1 : 0
        return (startColumn, startRow)
    }

    /// 目的地セルの添字を取得する
    /// - Parameters:
    ///   - card: 描画対象の移動カード
    ///   - gridSize: 列数・行数の情報
    /// - Returns: 目的地セルの列・行添字
    func destinationCellIndex(for card: MoveCard, gridSize: (columns: Int, rows: Int)) -> (column: Int, row: Int) {
        let start = startCellIndex(for: card, gridSize: gridSize)
        let destinationColumn = gridSize.columns - 1 - start.column
        let destinationRow = gridSize.rows - 1 - start.row
        return (destinationColumn, destinationRow)
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
