import SwiftUI

/// 移動カードの内容を視覚的に表現するビュー
/// 5×5 のグリッドと現在地・目的地・移動方向を描画してカード効果を直感的に把握できるようにする
struct MoveCardIllustrationView: View {
    /// 表示対象の移動カード
    let card: MoveCard

    var body: some View {
        ZStack {
            // MARK: - カードの背景枠
            // 既存のカードスタイル（角丸の枠付き）を踏襲して統一感を保つ
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white, lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
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
                            .fill(Color.white.opacity(0.12))
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
                        .stroke(Color.white.opacity(0.4), lineWidth: 0.5)

                        // MARK: 現在地・目的地のマーカー
                        Circle()
                            .fill(Color.white)
                            .frame(width: cellSize * 0.4, height: cellSize * 0.4)
                            .overlay(
                                Circle()
                                    .stroke(Color.black.opacity(0.8), lineWidth: 1)
                            )
                            .position(startPoint)

                        Circle()
                            .fill(Color.black)
                            .frame(width: cellSize * 0.4, height: cellSize * 0.4)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 1)
                            )
                            .position(destinationPoint)

                        // MARK: 移動方向を示す矢印（線 + 矢じり）
                        Path { path in
                            path.move(to: startPoint)
                            path.addLine(to: destinationPoint)
                        }
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

                        if let (leftPoint, rightPoint) = arrowHeadVertices {
                            Path { path in
                                path.move(to: destinationPoint)
                                path.addLine(to: leftPoint)
                                path.addLine(to: rightPoint)
                                path.closeSubpath()
                            }
                            .fill(Color.white)
                        }
                    }
                }
                .aspectRatio(1, contentMode: .fit)

                // MARK: - カード名の補助ラベル
                // テキストでも方向が確認できるよう小さめのフォントで表示
                Text(card.displayName)
                    .font(.caption2)
                    .foregroundColor(.white)
            }
            .padding(8)
        }
        .frame(width: 60, height: 80)
        // VoiceOver で方向が伝わるよう既存のラベルを継承
        .accessibilityLabel(Text(card.displayName))
        // カード操作のヒントも旧仕様を維持
        .accessibilityHint(Text("ダブルタップでこの方向に移動します"))
        // VoiceOver 上でボタンとして扱えるようトレイトを付与
        .accessibilityAddTraits(.isButton)
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
        MoveCardIllustrationView(card: .knightUp2Right1)
        MoveCardIllustrationView(card: .diagonalDownLeft2)
    }
    .padding()
    .background(Color.black)
}
