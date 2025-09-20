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
                    // 利用可能な領域から正方形サイズを算出（縦横いずれか小さい方を採用）
                    let squareSize = min(geometry.size.width, geometry.size.height)
                    let cellSize = squareSize / 5.0
                    // 正方形を中心に配置するため、余白のオフセットを計算
                    let originX = (geometry.size.width - squareSize) / 2.0
                    let originY = (geometry.size.height - squareSize) / 2.0

                    // SwiftUI の座標系は y 軸が下向きなので、盤面の「上」を画面上方向へ合わせるための変換
                    // 盤面中央 (2,2) を基準に目的地セルを求める
                    let centerColumn = 2
                    let centerRow = 2
                    let destinationColumn = centerColumn + card.dx
                    let destinationRow = centerRow - card.dy

                    // 各セルの中心座標を計算するヘルパー
                    func cellCenter(column: Int, row: Int) -> CGPoint {
                        CGPoint(
                            x: originX + (CGFloat(column) + 0.5) * cellSize,
                            y: originY + (CGFloat(row) + 0.5) * cellSize
                        )
                    }

                    // 現在地（中央）と目的地セルの中心座標
                    let startPoint = cellCenter(column: centerColumn, row: centerRow)
                    let destinationPoint = cellCenter(column: destinationColumn, row: destinationRow)

                    // 矢印描画のためのベクトル計算
                    let vector = CGVector(dx: destinationPoint.x - startPoint.x, dy: destinationPoint.y - startPoint.y)
                    let vectorLength = hypot(vector.dx, vector.dy)
                    // 矢印の頭部分のサイズ（カードの大きさに応じて決定）
                    let arrowHeadLength = cellSize * 0.5
                    let arrowHeadWidth = cellSize * 0.4

                    // 矢印の頭（三角形）の 2 点を求める（ベクトルがゼロの場合は描画しない）
                    let arrowHeadPoints: (CGPoint, CGPoint)? = vectorLength > 0
                        ? {
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
                        }() : nil

                    ZStack {
                        // MARK: 中央マスのハイライト
                        Rectangle()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: cellSize, height: cellSize)
                            .position(startPoint)

                        // MARK: グリッド線（縦横 5 分割）
                        Path { path in
                            // 縦線を描画
                            for index in 0...5 {
                                let x = originX + CGFloat(index) * cellSize
                                path.move(to: CGPoint(x: x, y: originY))
                                path.addLine(to: CGPoint(x: x, y: originY + squareSize))
                            }
                            // 横線を描画
                            for index in 0...5 {
                                let y = originY + CGFloat(index) * cellSize
                                path.move(to: CGPoint(x: originX, y: y))
                                path.addLine(to: CGPoint(x: originX + squareSize, y: y))
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

                        if let (leftPoint, rightPoint) = arrowHeadPoints {
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

// MARK: - プレビュー
#Preview {
    VStack(spacing: 12) {
        MoveCardIllustrationView(card: .knightUp2Right1)
        MoveCardIllustrationView(card: .diagonalDownLeft2)
    }
    .padding()
    .background(Color.black)
}
