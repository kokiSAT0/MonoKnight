#if canImport(SpriteKit)
import SpriteKit
#if canImport(UIKit)
import UIKit
#endif
import SwiftUI

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

    /// SpriteKit 内で利用するテーマ（SwiftUI 環境が無いので手動で適用する）
    private var theme = AppTheme(colorScheme: .light)

    /// 1 マスのサイズ
    private var tileSize: CGFloat = 0

    /// グリッドの左下原点
    private var gridOrigin: CGPoint = .zero

    /// 各マスに対応するノードを保持
    private var tileNodes: [GridPoint: SKShapeNode] = [:]

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
        applyTheme(theme)

        /// アクセシビリティ情報を初期化
        updateAccessibilityElements()
    }

    /// 画面サイズからマスのサイズと原点を算出する
    private func calculateLayout() {
        let length = min(size.width, size.height)
        tileSize = length / CGFloat(Board.size)
        let offsetX = (size.width - tileSize * CGFloat(Board.size)) / 2
        let offsetY = (size.height - tileSize * CGFloat(Board.size)) / 2
        gridOrigin = CGPoint(x: offsetX, y: offsetY)
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
                node.strokeColor = theme.skBoardGridLine
                node.lineWidth = 1
                node.fillColor = theme.skBoardTileUnvisited
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
        node.fillColor = theme.skBoardKnight
        node.strokeColor = .clear
        node.position = position(for: GridPoint.center)
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
                node.fillColor = theme.skBoardTileVisited
            } else {
                node.fillColor = theme.skBoardTileUnvisited
            }
        }
    }

    /// テーマを SpriteKit のノードへ適用し、背景や各マスの色を更新する
    /// - Parameter theme: ライト/ダークごとに調整されたアプリ共通テーマ
    func applyTheme(_ theme: AppTheme) {
        // SwiftUI 側で生成されたテーマを保持し、今後の色更新にも使えるようにする
        self.theme = theme

        // シーン全体の背景色を更新
        backgroundColor = theme.skBoardBackground

        // 既存のグリッド線や駒の色を一括で更新
        for node in tileNodes.values {
            node.strokeColor = theme.skBoardGridLine
        }
        knightNode?.fillColor = theme.skBoardKnight

        // 踏破状態による塗り分けもテーマに合わせて再適用
        updateTileColors()
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

