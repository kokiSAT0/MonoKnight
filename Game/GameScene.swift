#if canImport(SpriteKit)
import SpriteKit
#if canImport(UIKit)
import UIKit
#endif

/// GameCore とのやり取りのためのプロトコル
/// - ゲームロジック側で実装し、タップされたマスに対する移動処理を担当する
protocol GameCoreProtocol: AnyObject {
    /// 指定されたマスをタップした際に呼び出される
    /// - Parameter point: タップされたマスの座標
    func handleTap(at point: GridPoint)
}

/// 盤面と駒を描画し、タップ入力を GameCore に渡すシーン
class GameScene: SKScene {
    /// ゲームロジックを保持する参照
    weak var gameCore: GameCoreProtocol?

    /// 現在の盤面状態
    private var board = Board()

    /// SpriteKit 内で利用する配色セット
    /// - 備考: SwiftUI の `AppTheme` とは分離し、SpriteKit 専用の色情報のみを保持する
    private var palette = GameScenePalette.fallbackLight

    /// 1 マスのサイズ
    private var tileSize: CGFloat = 0

    /// グリッドの左下原点
    private var gridOrigin: CGPoint = .zero

    /// 各マスに対応するノードを保持
    private var tileNodes: [GridPoint: SKShapeNode] = [:]

    /// ガイドモードで使用するハイライトノードのキャッシュ
    private var guideHighlightNodes: [GridPoint: SKShapeNode] = [:]

    /// レイアウト未確定時に受け取ったガイド描画リクエストを一時的に保持
    private var pendingGuideHighlightPoints: Set<GridPoint> = []

    /// 駒を表すノード
    private var knightNode: SKShapeNode?

    /// 現在の駒の位置
    /// - NOTE: アクセシビリティ情報更新時に参照する
    private var knightPosition: GridPoint = .center

    #if canImport(UIKit)
    /// VoiceOver で読み上げるための要素配列
    private var accessibilityElementsCache: [UIAccessibilityElement] = []

    /// VoiceOver 用に各マスを表すクラス
    /// - ダブルタップで該当マスを GameCore に伝達する
    private final class TileAccessibilityElement: UIAccessibilityElement {
        /// 対象マスの座標
        let point: GridPoint
        /// 親となるシーンへの弱参照
        weak var owner: GameScene?
        /// 初期化
        init(point: GridPoint, owner: GameScene) {
            self.point = point
            self.owner = owner
            super.init(accessibilityContainer: owner)
        }
        /// VoiceOver の操作に反応してタップを伝達
        override func accessibilityActivate() -> Bool {
            owner?.gameCore?.handleTap(at: point)
            return true
        }
    }
    #endif

    // MARK: - シーン初期化

    override func didMove(to view: SKView) {
        super.didMove(to: view)

        /// マスのサイズと原点を計算
        calculateLayout()

        /// グリッドと駒を生成
        setupGrid()
        setupKnight()

        /// 現在保持しているテーマを適用し、初期色を決定
        applyTheme(palette)

        /// アクセシビリティ情報を初期化
        updateAccessibilityElements()

        /// シーン初期化後に保留分のガイド枠があれば忘れずに反映する
        applyPendingGuideHighlightsIfNeeded()
    }

    /// 画面サイズからマスのサイズと原点を算出する
    private func calculateLayout() {
        let length = min(size.width, size.height)
        tileSize = length / CGFloat(Board.size)
        let offsetX = (size.width - tileSize * CGFloat(Board.size)) / 2
        let offsetY = (size.height - tileSize * CGFloat(Board.size)) / 2
        gridOrigin = CGPoint(x: offsetX, y: offsetY)

        // レイアウトが確定したタイミングで保留中のガイド枠を復元する
        applyPendingGuideHighlightsIfNeeded()
    }

    /// シーンのサイズ変更に追従してレイアウトを再計算
    /// - Parameter oldSize: 変更前のシーンサイズ（未使用だがデバッグ時の参考用に保持）
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)

        // 端末の回転や親ビューのリサイズに合わせ、マスの基準サイズと原点を再計算する
        calculateLayout()

        // 既存のマスノードを走査し、新しいタイルサイズに沿った矩形パスを再構築する
        for (point, node) in tileNodes {
            let rect = CGRect(
                x: gridOrigin.x + CGFloat(point.x) * tileSize,
                y: gridOrigin.y + CGFloat(point.y) * tileSize,
                width: tileSize,
                height: tileSize
            )
            node.path = CGPath(rect: rect, transform: nil)
        }

        // 駒ノードも新しいレイアウト上の中心座標へ移動し、半径をタイル比率に合わせて補正する
        if let knightNode {
            knightNode.position = position(for: knightPosition)
            let radius = tileSize * 0.4
            let circleRect = CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
            knightNode.path = CGPath(ellipseIn: circleRect, transform: nil)
        }

        // ハイライトは専用メソッドで再構成し、テーマ色とサイズを同時にリフレッシュする
        updateGuideHighlightColors()

        // VoiceOver 用の読み上げ領域も新しい座標に合わせ直す
        updateAccessibilityElements()

        // サイズ変更後も保留していたハイライトを再構築し、見た目の破綻を防ぐ
        applyPendingGuideHighlightsIfNeeded()
    }

    /// 5×5 のグリッドを描画
    private func setupGrid() {
        for y in 0..<Board.size {
            for x in 0..<Board.size {
                let rect = CGRect(
                    x: gridOrigin.x + CGFloat(x) * tileSize,
                    y: gridOrigin.y + CGFloat(y) * tileSize,
                    width: tileSize,
                    height: tileSize
                )
                let node = SKShapeNode(rect: rect)
                node.strokeColor = palette.boardGridLine
                node.lineWidth = 1
                node.fillColor = palette.boardTileUnvisited
                addChild(node)
                let point = GridPoint(x: x, y: y)
                tileNodes[point] = node
                // テストプレイ時の没入感を損なわないよう、デバッグ用の座標ラベルは描画しない
            }
        }
    }

    /// 駒を生成して中央に配置
    private func setupKnight() {
        let radius = tileSize * 0.4
        let node = SKShapeNode(circleOfRadius: radius)
        node.fillColor = palette.boardKnight
        node.strokeColor = .clear
        node.position = position(for: GridPoint.center)
        node.zPosition = 2  // ガイドハイライトより前面に表示して駒が埋もれないようにする
        addChild(node)
        knightNode = node
    }

    /// 指定座標に対応するシーン上の位置を返す
    /// - Parameter point: グリッド座標
    /// - Returns: シーン上の中心座標
    private func position(for point: GridPoint) -> CGPoint {
        let x = gridOrigin.x + CGFloat(point.x) * tileSize + tileSize / 2
        let y = gridOrigin.y + CGFloat(point.y) * tileSize + tileSize / 2
        return CGPoint(x: x, y: y)
    }

    /// 盤面の状態を更新し、踏破済みマスの色を反映する
    /// - Parameter board: 新しい盤面
    func updateBoard(_ board: Board) {
        self.board = board
        updateTileColors()
        // 盤面更新に応じてアクセシビリティ要素も再構築
        updateAccessibilityElements()
    }

    /// 各マスの色を踏破状態に合わせて更新する
    private func updateTileColors() {
        for (point, node) in tileNodes {
            if board.isVisited(point) {
                node.fillColor = palette.boardTileVisited
            } else {
                node.fillColor = palette.boardTileUnvisited
            }
        }
        // タイル色が変わった際もガイドハイライトの色味を再評価して自然なバランスを保つ
        updateGuideHighlightColors()
    }

    /// ガイドモードで指定されたマスにハイライトを表示する
    /// - Parameter points: 発光させたい盤面座標の集合
    func updateGuideHighlights(_ points: Set<GridPoint>) {
        // 盤外座標が渡されても安全に無視できるよう、盤面内に限定した集合を用意
        let validPoints = Set(points.filter { board.contains($0) })

        // 最新の要求内容を常に保持し、レイアウト完了後に再構成できるようにする
        pendingGuideHighlightPoints = validPoints

        // タイルサイズが未確定（0 または負数）の場合はノード生成を保留し、後で再試行する
        guard tileSize > 0 else { return }

        rebuildGuideHighlightNodes(using: validPoints)
    }

    /// 指定された集合に合わせてハイライトノード群を再生成する
    /// - Parameter points: 表示したい盤面座標の集合
    private func rebuildGuideHighlightNodes(using points: Set<GridPoint>) {
        // 既存ハイライトのうち対象外になったものを削除
        for (point, node) in guideHighlightNodes where !points.contains(point) {
            node.removeFromParent()
            guideHighlightNodes.removeValue(forKey: point)
        }

        // 必要なマスへハイライトを再構成
        for point in points {
            if let node = guideHighlightNodes[point] {
                configureGuideHighlightNode(node, for: point)
            } else {
                let node = SKShapeNode()
                configureGuideHighlightNode(node, for: point)
                addChild(node)
                guideHighlightNodes[point] = node
            }
        }
    }

    /// 既存のハイライトノードを現在のテーマとマスサイズに合わせて更新
    private func updateGuideHighlightColors() {
        // レイアウトが未確定のまま再描画しても意味が無いため、適切なサイズが得られるまで待機する
        guard tileSize > 0 else { return }

        if pendingGuideHighlightPoints.isEmpty {
            // 現在表示中のノードを最新テーマへ合わせ直す
            for (point, node) in guideHighlightNodes {
                configureGuideHighlightNode(node, for: point)
            }
        } else {
            // 保留中の座標がある場合はノード自体を再構成して確実に表示する
            rebuildGuideHighlightNodes(using: pendingGuideHighlightPoints)
        }
    }

    /// ハイライトノードへ共通のスタイルと位置を適用する
    /// - Parameters:
    ///   - node: 更新対象のノード
    ///   - point: 対応する盤面座標
    private func configureGuideHighlightNode(_ node: SKShapeNode, for point: GridPoint) {
        // 枠線の外側がマス境界を超えないよう、線幅に応じて矩形を補正する
        let strokeWidth = max(tileSize * 0.06, 2.0)
        // SpriteKit の座標系ではノード中心が (0,0) なので、原点からタイル半分を引いた矩形を起点にする
        let baseRect = CGRect(
            x: -tileSize / 2,
            y: -tileSize / 2,
            width: tileSize,
            height: tileSize
        )
        // rect.insetBy を用い、線幅の半分だけ内側に寄せて外周がグリッド線とぴったり接するよう調整
        let adjustedRect = baseRect.insetBy(dx: strokeWidth / 2, dy: strokeWidth / 2)
        node.path = CGPath(rect: adjustedRect, transform: nil)

        let baseColor = palette.boardGuideHighlight
        // 充填色は透過させ、枠線のみに集中させて過度な塗りつぶしを避ける
        node.fillColor = SKColor.clear
        node.strokeColor = baseColor.withAlphaComponent(0.88)
        node.lineWidth = strokeWidth
        node.glowWidth = 0

        // 角をシャープに保つために角丸設定を無効化し、SpriteKit のデフォルトより明示的にミタージョインを指定する
        node.lineJoin = .miter
        // lineJoin をミターにした際にエッジが過度に尖らないよう、適度な上限値を設ける
        node.miterLimit = 2.5
        // 終端も角を丸めず、グリッドの直線的な印象を優先する

        node.lineCap = .square
        node.position = position(for: point)
        node.zPosition = 1  // タイルより前面、駒より背面で控えめに表示
        // アンチエイリアスを無効化し、ライト/ダーク両テーマで滲まないシャープな輪郭にする
        node.isAntialiased = false
        node.blendMode = .alpha
    }

    /// 受け取った配色パレットを SpriteKit のノードへ適用し、背景や各マスの色を更新する
    /// - Parameter palette: SwiftUI 側で決定されたライト/ダーク用カラーを転写したパレット
    func applyTheme(_ palette: GameScenePalette) {
        // SwiftUI 側で生成されたテーマから変換されたパレットを保持し、今後の色更新にも使えるようにする
        self.palette = palette

        // シーン全体の背景色を更新
        backgroundColor = palette.boardBackground

        // 既存のグリッド線や駒の色を一括で更新
        for node in tileNodes.values {
            node.strokeColor = palette.boardGridLine
        }
        knightNode?.fillColor = palette.boardKnight

        // 踏破状態による塗り分けもテーマに合わせて再適用
        updateTileColors()

        // ガイドハイライトも最新のテーマ色へ刷新
        updateGuideHighlightColors()
    }

    /// 駒を指定座標へ移動する
    /// - Parameter point: 移動先の座標
    func moveKnight(to point: GridPoint) {
        let destination = position(for: point)
        let move = SKAction.move(to: destination, duration: 0.2)
        knightNode?.run(move)
        // 現在位置を保持し、アクセシビリティ情報を更新
        knightPosition = point
        updateAccessibilityElements()
    }

    /// 保留中のガイド枠があれば、レイアウト確定後に反映する
    private func applyPendingGuideHighlightsIfNeeded() {
        guard tileSize > 0, !pendingGuideHighlightPoints.isEmpty else { return }
        rebuildGuideHighlightNodes(using: pendingGuideHighlightPoints)
    }

    // MARK: - タップ処理

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        guard let point = gridPoint(from: location) else { return }
        gameCore?.handleTap(at: point)
    }

    /// シーン上の座標からグリッド座標を算出する
    /// - Parameter location: シーン上のタッチ位置
    /// - Returns: 対応するマスの座標。盤外なら nil。
    private func gridPoint(from location: CGPoint) -> GridPoint? {
        let x = Int((location.x - gridOrigin.x) / tileSize)
        let y = Int((location.y - gridOrigin.y) / tileSize)
        let point = GridPoint(x: x, y: y)
        return board.contains(point) ? point : nil
    }

    #if canImport(UIKit)
    /// VoiceOver 用のアクセシビリティ要素を再構築
    private func updateAccessibilityElements() {
        var elements: [UIAccessibilityElement] = []
        for y in 0..<Board.size {
            for x in 0..<Board.size {
                let point = GridPoint(x: x, y: y)
                let element = TileAccessibilityElement(point: point, owner: self)
                // シーン内でのフレームを設定し、フォーカス位置を合わせる
                element.accessibilityFrameInContainerSpace = CGRect(
                    x: gridOrigin.x + CGFloat(x) * tileSize,
                    y: gridOrigin.y + CGFloat(y) * tileSize,
                    width: tileSize,
                    height: tileSize
                )
                // 状態に応じた読み上げ内容を生成
                if point == knightPosition {
                    let visitedText = board.isVisited(point) ? "踏破済み" : "未踏破"
                    element.accessibilityLabel = "駒あり " + visitedText
                } else {
                    element.accessibilityLabel = board.isVisited(point) ? "踏破済み" : "未踏破"
                }
                element.accessibilityTraits = [.button]
                elements.append(element)
            }
        }
        accessibilityElementsCache = elements
    }

    /// GameScene をアクセシビリティコンテナとして扱う
    override var accessibilityElements: [Any]? {
        get { accessibilityElementsCache }
        set { }
    }
    #else
    // UIKit が利用できない環境では空実装
    private func updateAccessibilityElements() {}
    #endif
}
#endif

