import SwiftUI
import Game  // GridPoint 型を利用するためゲームロジックモジュールを読み込む

/// SpriteView と手札スロット間のカード移動演出を担当するビュー
/// - Note: レイアウト処理とアニメーション処理を分離し、`GameView` の見通しを良くする。
struct GameCardAnimationOverlay: View {
    /// 手札側で計測したアンカー情報の辞書
    let anchors: [UUID: Anchor<CGRect>]
    /// SpriteKit との橋渡しを担う ViewModel
    @ObservedObject var boardBridge: GameBoardBridgeViewModel
    /// フォールバック用に保持しておく現在地（アニメーションターゲット未設定時に利用）
    let fallbackCurrentPosition: GridPoint?
    /// MatchedGeometryEffect の名前空間
    let cardAnimationNamespace: Namespace.ID

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.clear
                overlayContent(using: proxy)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private extension GameCardAnimationOverlay {
    /// GeometryProxy を用いてカードの移動演出を構築する
    /// - Parameter proxy: 手札・盤面それぞれの CGRect を解決するための GeometryProxy
    @ViewBuilder
    func overlayContent(using proxy: GeometryProxy) -> some View {
        if let animatingCard = boardBridge.animatingCard,
           let sourceAnchor = anchors[animatingCard.id],
           let boardAnchor = boardBridge.boardAnchor,
           let targetGridPoint = boardBridge.animationTargetGridPoint ?? fallbackCurrentPosition,
           boardBridge.animationState != .idle || boardBridge.hiddenCardIDs.contains(animatingCard.id) {
            let cardFrame = proxy[sourceAnchor]
            let boardFrame = proxy[boardAnchor]
            let startCenter = CGPoint(x: cardFrame.midX, y: cardFrame.midY)
            let boardDestination = Self.boardCoordinate(
                for: targetGridPoint,
                boardSize: boardBridge.boardSize,
                in: boardFrame
            )

            MoveCardIllustrationView(card: animatingCard.move)
                .matchedGeometryEffect(id: animatingCard.id, in: cardAnimationNamespace)
                .frame(width: cardFrame.width, height: cardFrame.height)
                .position(boardBridge.animationState == .movingToBoard ? boardDestination : startCenter)
                .scaleEffect(boardBridge.animationState == .movingToBoard ? 0.55 : 1.0)
                .opacity(boardBridge.animationState == .movingToBoard ? 0.0 : 1.0)
                .allowsHitTesting(false)
        }
    }

    /// 盤面座標を SwiftUI 座標系へ変換し、MatchedGeometryEffect の移動先を算出する
    /// - Parameters:
    ///   - gridPoint: 盤面上のマス座標（原点は左下）
    ///   - boardSize: 現在の盤面一辺サイズ
    ///   - frame: SwiftUI における盤面矩形
    /// - Returns: SwiftUI 座標系での中心位置
    static func boardCoordinate(for gridPoint: GridPoint, boardSize: Int, in frame: CGRect) -> CGPoint {
        // 盤面サイズが 0 以下になることは想定していないが、安全のため 1 以上へ補正する
        let safeBoardSize = max(1, boardSize)
        let tileLength = frame.width / CGFloat(safeBoardSize)
        let centerX = frame.minX + tileLength * (CGFloat(gridPoint.x) + 0.5)
        // SwiftUI 座標では上方向がマイナス値となるため、盤面上端からの距離で算出する
        let centerY = frame.maxY - tileLength * (CGFloat(gridPoint.y) + 0.5)
        return CGPoint(x: centerX, y: centerY)
    }
}
