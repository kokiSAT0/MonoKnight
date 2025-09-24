#if canImport(SpriteKit)
import SpriteKit
#if canImport(UIKit)
import UIKit
#endif

/// GameCore とのやり取りのためのプロトコル
/// - ゲームロジック側で実装し、タップされたマスに対する移動処理を担当する
public protocol GameCoreProtocol: AnyObject {
    /// 指定されたマスをタップした際に呼び出される
    /// - Parameter point: タップされたマスの座標
    func handleTap(at point: GridPoint)
}

/// 盤面と駒を描画し、タップ入力を GameCore に渡すシーン
public final class GameScene: SKScene {
    /// ゲームロジックを保持する参照
    public weak var gameCore: GameCoreProtocol?

    /// 現在の盤面状態
    private var board = Board(size: 5, initialVisitedPoints: [GridPoint.center(of: 5)])

    /// SpriteKit 内で利用する配色セット
    /// - 備考: SwiftUI の `AppTheme` とは分離し、SpriteKit 専用の色情報のみを保持する
    /// - NOTE: テーマ未設定時でも見た目が破綻しないよう共通フォールバックを適用しておく
    private var palette = GameScenePalette.fallback

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

    /// レイアウト未確定時に渡された盤面情報を一時保存し、後でまとめて適用する
    private var pendingBoard: Board?

    /// レイアウト未確定時に要求された駒移動の内容
    private enum PendingKnightState {
        case show(GridPoint)
        case hide
    }
    private var pendingKnightState: PendingKnightState?

    /// グリッド生成と駒配置が完了し、SpriteKit のノード更新を安全に行えるかどうか
    private var isLayoutReady: Bool {
        tileSize > 0 && tileNodes.count == board.size * board.size && knightNode != nil
    }

    /// レイアウト再計算がどのイベントで行われたのかを識別するための列挙体
    /// - NOTE: デバッグログへ明示的に理由を残すことで、想定外のタイミングでサイズ変更が発生していないかを分析しやすくする
    private enum LayoutTrigger: String {
        case didMove
        case didChangeSize
        case manual
    }

    /// 駒を表すノード
    private var knightNode: SKShapeNode?

    /// 現在の駒の位置
    /// - NOTE: アクセシビリティ情報更新時に参照する
    private var knightPosition: GridPoint?

    /// シーンサイズがゼロのままのため初期レイアウトを保留しているかどうか
    /// - NOTE: SpriteView がまだレイアウト前の段階では `size` が `.zero` になるため、
    ///   その状態でノード生成を進めると盤面が描画されない不具合に直結する。
    ///   このフラグで「サイズ確定待ち」かどうかを把握し、後続ログと併せて状況確認をしやすくする。
    private var awaitingValidSceneSize = false

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

    /// 初期化時に共通で呼び出す内部処理
    /// - NOTE: 盤面・テーマ・ノード・アクセシビリティ関連の初期値をまとめてリセットし、コード生成と Storyboard 復元の両方で同一状態からスタートできるようにする
    private func commonInit() {
        // 盤面情報は常に中央スタートへ戻すことで、テストや再生成時も確実に同じ条件を再現できるようにする
        board = Board(size: 5, initialVisitedPoints: [GridPoint.center(of: 5)])
        // テーマもデフォルトへ戻し、SpriteKit 専用の配色が未設定のままでも破綻しないようフォールバックを適用
        palette = GameScenePalette.fallback
        // レイアウト関連の値をゼロクリアしておくことで、サイズ確定後の `calculateLayout` が必ず最新値を算出できる
        tileSize = 0
        gridOrigin = .zero
        // SpriteKit ノード系のキャッシュは全て空に戻し、不要なノードが残らないようにする
        tileNodes = [:]
        guideHighlightNodes = [:]
        pendingGuideHighlightPoints = []
        pendingBoard = nil
        pendingKnightState = nil
        knightNode = nil
        knightPosition = nil
        // シーンサイズ待ちフラグも初期化し、Storyboard/SwiftUI 双方で初回レイアウトの判定が正しく行われるようにする
        awaitingValidSceneSize = false
        #if canImport(UIKit)
        // VoiceOver 用キャッシュを空に戻し、アクセシビリティ情報が stale にならないよう都度再生成を促す
        accessibilityElementsCache = []
        #endif
    }

    /// コードから GameScene を生成する際の初期化処理
    /// - NOTE: `super.init(size:)` を呼び出し、基本状態をゼロリセットしてからレイアウト計算やノード生成を `didMove(to:)` で行う
    public override init() {
        super.init(size: .zero)
        // 共通初期化で各種プロパティを統一的にリセットし、生成経路による差異を排除する
        commonInit()
        // 必要に応じて `calculateLayout()` などを明示的に呼び出し、シーンのサイズが既に確定している場合にも対応できるようにする
    }

    /// Interface Builder（Storyboard や XIB）経由の生成に対応するための初期化処理
    /// - NOTE: Apple の推奨に従い `super.init(coder:)` を呼び出し、アーカイブ復元時でも同じ初期状態を確保する
    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        // デコード後も共通初期化を実行し、Storyboard/SwiftUI どちらからでも同じ見た目・挙動となるようにする
        commonInit()
        // Interface Builder でサイズが事前に与えられている場合は、シーンの親ビュー設定後に `calculateLayout()` を呼ぶとレイアウトが整う
    }

    public override func didMove(to view: SKView) {
        super.didMove(to: view)

        // デバッグ目的: シーンがビューへアタッチされたタイミングでサイズを記録しておき、盤面が描画されない不具合の手掛かりにする
        debugLog("GameScene.didMove: view.bounds=\(view.bounds.size), scene.size=\(size)")

        /// マスのサイズと原点を計算
        calculateLayout(trigger: .didMove)

        /// 現在保持しているテーマを適用し、初期色を決定
        applyTheme(palette)

        /// アクセシビリティ情報を初期化
        updateAccessibilityElements()

        /// 初期化中に保留された各種更新（盤面/ガイド/駒位置）をまとめて反映する
        flushPendingUpdatesIfNeeded()
    }

    /// 画面サイズからマスのサイズと原点を算出する
    /// - Parameter trigger: レイアウト再計算を要求したイベント（ログ用）
    private func calculateLayout(trigger: LayoutTrigger) {
        let length = min(size.width, size.height)

        guard length > 0 else {
            // `.zero` のままノード生成を進めると盤面が描画されないため、ここで一旦処理を保留する
            if awaitingValidSceneSize {
                debugLog(
                    "GameScene.calculateLayout: trigger=\(trigger.rawValue) サイズ未確定のため待機継続 size=\(size)"
                )
            } else {
                debugLog(
                    "GameScene.calculateLayout: trigger=\(trigger.rawValue) シーンサイズがゼロのため初期レイアウトを延期 size=\(size)"
                )
            }
            awaitingValidSceneSize = true
            tileSize = 0
            gridOrigin = .zero
            return
        }

        let wasAwaiting = awaitingValidSceneSize
        awaitingValidSceneSize = false

        let boardSize = CGFloat(board.size)
        tileSize = length / boardSize
        let offsetX = (size.width - tileSize * boardSize) / 2
        let offsetY = (size.height - tileSize * boardSize) / 2
        gridOrigin = CGPoint(x: offsetX, y: offsetY)

        // レイアウト計算の結果をログ出力し、tileSize が 0 付近になる異常を検知できるようにする
        debugLog(
            "GameScene.calculateLayout: trigger=\(trigger.rawValue), size=\(size), tileSize=\(tileSize), gridOrigin=\(gridOrigin)"
        )

        if wasAwaiting {
            // `size == .zero` で待機していたケースが復旧したことを明示的に記録する
            debugLog("GameScene.calculateLayout: 待機していた初期レイアウトを実行しました")
        }

        // レイアウト確定状況をチェックし、グリッドや駒ノードの生成が済んでいなければ補完する
        prepareLayoutIfNeeded()
    }

    /// シーンのサイズ変更に追従してレイアウトを再計算
    /// - Parameter oldSize: 変更前のシーンサイズ（未使用だがデバッグ時の参考用に保持）
    public override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)

        // サイズ変更イベントの発生をログへ残し、どのタイミングで SpriteKit 側の寸法が確定したか追跡できるようにする
        debugLog("GameScene.didChangeSize: oldSize=\(oldSize), newSize=\(size)")

        // 端末の回転や親ビューのリサイズに合わせ、マスの基準サイズと原点を再計算する
        calculateLayout(trigger: .didChangeSize)

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
        if let knightNode, let knightPosition {
            // 駒が存在する場合のみ新しいレイアウトに合わせて再配置する
            knightNode.position = position(for: knightPosition)
            let radius = tileSize * 0.4
            let circleRect = CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
            knightNode.path = CGPath(ellipseIn: circleRect, transform: nil)
        } else if let knightNode {
            // スポーン未確定などで現在位置が無い場合は描画だけ更新して非表示のまま維持する
            let radius = tileSize * 0.4
            let circleRect = CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
            knightNode.path = CGPath(ellipseIn: circleRect, transform: nil)
        }

        // ハイライトは専用メソッドで再構成し、テーマ色とサイズを同時にリフレッシュする
        updateGuideHighlightColors()

        // VoiceOver 用の読み上げ領域も新しい座標に合わせ直す
        updateAccessibilityElements()

        // サイズ変更後も保留していた更新があれば忘れずに復元する
        prepareLayoutIfNeeded()
    }

    /// レイアウト情報が揃っているかを確認し、不足していればグリッド・駒ノードを生成する
    private func prepareLayoutIfNeeded() {
        // tileSize がゼロのままではノード生成ができないため、その場合は次回以降へ処理を委ねる
        guard tileSize > 0 else {
            debugLog("GameScene.prepareLayoutIfNeeded: tileSize 未確定のため後続処理を延期")
            return
        }

        // 現在のノード状況を記録して、想定外の未初期化ケースを早期に検知できるようにする
        debugLog(
            "GameScene.prepareLayoutIfNeeded: tileNodes=\(tileNodes.count), knightExists=\(knightNode != nil)"
        )

        if tileNodes.isEmpty {
            // グリッド未生成であればここでまとめて構築し、didMove 以外の経路でも盤面を成立させる
            debugLog("GameScene.prepareLayoutIfNeeded: グリッド未生成のため setupGrid/setupKnight を実行")
            setupGrid()
            setupKnight()
        } else if knightNode == nil {
            // まれに駒ノードのみ失われた場合の保険として再生成する
            debugLog("GameScene.prepareLayoutIfNeeded: 駒ノード欠落を検知したため再生成")
            setupKnight()
        }

        // ここまででレイアウトが安全に扱える状態まで整っていれば、保留中の更新を即座に適用する
        if isLayoutReady {
            debugLog(
                "GameScene.prepareLayoutIfNeeded: レイアウト準備完了、保留更新を flush します"
            )
            flushPendingUpdatesIfNeeded()
        } else {
            // グリッド構築中などで条件が揃わなかった場合は状況を記録して後続の手掛かりにする
            debugLog(
                "GameScene.prepareLayoutIfNeeded: レイアウト未完了 tileNodes=\(tileNodes.count), knightExists=\(knightNode != nil)"
            )
        }
    }

    /// 盤面サイズ変更時に既存ノードを破棄して再構築する
    private func rebuildNodesForBoardSizeChange() {
        debugLog("GameScene.rebuildNodesForBoardSizeChange: newSize=\(board.size)")

        for node in tileNodes.values {
            node.removeFromParent()
        }
        tileNodes.removeAll()

        for node in guideHighlightNodes.values {
            node.removeFromParent()
        }
        guideHighlightNodes.removeAll()
        pendingGuideHighlightPoints.removeAll()

        if let knightNode {
            knightNode.removeAllActions()
            knightNode.removeFromParent()
        }
        knightNode = nil
        knightPosition = nil
        pendingKnightState = nil

        prepareLayoutIfNeeded()
    }

    /// 5×5 のグリッドを描画
    private func setupGrid() {
        for y in 0..<board.size {
            for x in 0..<board.size {
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

        // タイル生成結果を記録し、想定どおり 25 個のノードが確保されているかを後で検証できるようにする
        debugLog("GameScene.setupGrid: 生成タイル数=\(tileNodes.count), tileSize=\(tileSize)")
    }

    /// 駒を生成して中央に配置
    private func setupKnight() {
        let radius = tileSize * 0.4
        let node = SKShapeNode(circleOfRadius: radius)
        node.fillColor = palette.boardKnight
        node.strokeColor = .clear
        let initialPoint = knightPosition ?? GridPoint.center(of: board.size)
        node.position = position(for: initialPoint)
        node.zPosition = 2  // ガイドハイライトより前面に表示して駒が埋もれないようにする
        node.isHidden = knightPosition == nil
        addChild(node)
        knightNode = node

        // 駒ノードの初期化状況を記録して、盤面非表示時に駒だけ描画されていないか切り分けやすくする
        debugLog("GameScene.setupKnight: radius=\(radius), position=\(node.position), hidden=\(node.isHidden)")
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
    /// - NOTE: SwiftUI モジュールからも参照するため `public` で公開する
    public func updateBoard(_ board: Board) {
        // 盤面そのものの状態は常に保持し、描画が間に合っていなくてもゲームロジックとの整合を取っておく
        let previousSize = self.board.size
        self.board = board

        if previousSize != board.size {
            pendingBoard = board
            calculateLayout(trigger: .manual)
            rebuildNodesForBoardSizeChange()
            return
        }

        // レイアウトが未確定でマスノードがまだ生成されていない場合は、一旦保留しておき確定後に反映する
        guard isLayoutReady else {
            pendingBoard = board
            debugLog("GameScene.updateBoard: レイアウト未確定のため盤面更新を保留 tileNodes=\(tileNodes.count)")
            return
        }

        // レイアウトが整っている場合は即座に色とアクセシビリティ情報を更新する
        pendingBoard = nil
        applyCurrentBoardStateToNodes(shouldLog: true)
    }

    /// 各マスの色を踏破状態に合わせて更新する
    private func updateTileColors() {
        // レイアウトが整っていない段階で呼ばれても意味が無いため、安全側に倒して何もしない
        guard isLayoutReady else { return }

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
    /// - NOTE: ガイド表示の更新を SwiftUI 側から呼び出せるよう公開する
    public func updateGuideHighlights(_ points: Set<GridPoint>) {
        // 盤外座標が渡されても安全に無視できるよう、盤面内に限定した集合を用意
        let validPoints = Set(points.filter { board.contains($0) })

        // 最新の要求内容を常に保持し、レイアウト完了後に再構成できるようにする
        pendingGuideHighlightPoints = validPoints

        // SwiftUI 側からのリクエストが途絶えていないか確認するため、受け取ったマス数とレイアウト状態を記録
        debugLog("GameScene ハイライト更新要求: 有効マス数=\(validPoints.count), レイアウト確定=\(isLayoutReady)")

        // レイアウトが未確定の場合はノード生成を保留し、確定後に再試行する
        guard isLayoutReady else { return }

        rebuildGuideHighlightNodes(using: validPoints)
        // レイアウト確定後に最新情報で再構成できたため、保留集合はここで必ず消費しておく
        pendingGuideHighlightPoints.removeAll()
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
                // 既存ノードを再利用する際は親子関係が途切れていないか必ず確認する
                if node.parent !== self {
                    // SKView の再生成時に親を失ったノードを確実に再接続するため
                    addChild(node)
                }
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
        guard isLayoutReady else { return }

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
    /// - NOTE: パッケージ外からテーマを適用するため `public` を付与
    public func applyTheme(_ palette: GameScenePalette) {
        // SwiftUI 側で生成されたテーマから変換されたパレットを保持し、今後の色更新にも使えるようにする
        self.palette = palette

        // シーン全体の背景色を更新
        backgroundColor = palette.boardBackground

        // 既存のグリッド線や駒の色を一括で更新
        for node in tileNodes.values {
            node.strokeColor = palette.boardGridLine
        }
        knightNode?.fillColor = palette.boardKnight

        // レイアウトが確定していればその場で再描画し、未確定なら後で flush 時に反映する
        if isLayoutReady {
            updateTileColors()
            updateGuideHighlightColors()
        }
    }

    /// 駒を指定座標へ移動する
    /// - Parameter point: 移動先の座標
    /// - NOTE: 駒の移動をゲームロジック外部から制御するため公開メソッドにする
    public func moveKnight(to point: GridPoint?) {
        // 駒移動前に現在のレイアウト情報を記録し、移動要求が届いているかどうかを判別できるようにする
        debugLog("GameScene.moveKnight 要求: current=\(String(describing: knightPosition)), target=\(String(describing: point)), tileSize=\(tileSize)")

        // レイアウト未確定の間は駒ノード自体が存在しない可能性があるため、確定後に反映するよう保留する
        guard isLayoutReady, let knightNode else {
            if let point {
                pendingKnightState = .show(point)
                knightPosition = point
            } else {
                pendingKnightState = .hide
                knightPosition = nil
            }
            debugLog("GameScene.moveKnight: レイアウト未確定のため移動を保留")
            return
        }

        if let point {
            // タイトル画面に遷移した直後など、SpriteKit 側の SKView が一時停止状態になっていると
            // SKAction がまったく再生されず駒が移動しないため、ここで毎回再開を保証する。
            if let skView = view, skView.isPaused {
                skView.isPaused = false
            }
            if isPaused {
                isPaused = false
            }

            knightNode.isHidden = false
            performKnightPlacement(to: point, animated: true)
        } else {
            // 駒を非表示にする要求
            knightNode.removeAllActions()
            knightNode.isHidden = true
            knightPosition = nil
            updateAccessibilityElements()
            debugLog("GameScene.moveKnight: 駒を非表示にしました")
        }
    }

    /// 保留中のガイド枠があれば、レイアウト確定後に反映する
    private func applyPendingGuideHighlightsIfNeeded() {
        guard isLayoutReady, !pendingGuideHighlightPoints.isEmpty else { return }
        rebuildGuideHighlightNodes(using: pendingGuideHighlightPoints)
        // `flushPendingUpdatesIfNeeded` から呼び出された際も、再構成が完了した時点で保留分をクリアする
        pendingGuideHighlightPoints.removeAll()
    }

    /// レイアウト確定後に盤面・駒・ガイドの保留更新をまとめて反映する
    private func flushPendingUpdatesIfNeeded() {
        guard isLayoutReady else {
            debugLog(
                "GameScene.flushPendingUpdatesIfNeeded: レイアウト未確定のため保留 updates を維持"
            )
            return
        }

        debugLog(
            "GameScene.flushPendingUpdatesIfNeeded: pendingBoard=\(pendingBoard != nil), pendingKnight=\(pendingKnightState != nil), pendingGuide=\(pendingGuideHighlightPoints.count)"
        )

        if let boardToApply = pendingBoard {
            // 盤面更新を保留していた場合は、このタイミングでノードに反映する
            pendingBoard = nil
            self.board = boardToApply
            applyCurrentBoardStateToNodes(shouldLog: true)
        } else {
            // 盤面保留が無くても、レイアウト再構築後は最新状態をもう一度転写して不整合を避ける
            applyCurrentBoardStateToNodes(shouldLog: false)
        }

        if let pendingKnightState {
            self.pendingKnightState = nil
            switch pendingKnightState {
            case .show(let point):
                knightNode?.isHidden = false
                performKnightPlacement(to: point, animated: false)
            case .hide:
                knightNode?.removeAllActions()
                knightNode?.isHidden = true
                knightPosition = nil
                updateAccessibilityElements()
            }
        }

        // ハイライトの再生成は専用メソッドに委譲
        applyPendingGuideHighlightsIfNeeded()
    }

    /// 現在保持している盤面情報を SpriteKit ノードへ反映する
    /// - Parameter shouldLog: デバッグログを残すかどうか
    private func applyCurrentBoardStateToNodes(shouldLog: Bool) {
        guard isLayoutReady else { return }

        updateTileColors()
        updateAccessibilityElements()

        if shouldLog {
            let visitedCount = board.size * board.size - board.remainingCount
            debugLog("GameScene.updateBoard: visited=\(visitedCount), remaining=\(board.remainingCount), tileNodes=\(tileNodes.count)")
        }
    }

    /// 駒ノードの位置を更新し、必要に応じてアニメーションさせる
    /// - Parameters:
    ///   - point: 配置したい盤面座標
    ///   - animated: アニメーションを伴うかどうか
    private func performKnightPlacement(to point: GridPoint, animated: Bool) {
        guard let knightNode else { return }

        let destination = position(for: point)
        knightNode.removeAllActions()

        if animated {
            let move = SKAction.move(to: destination, duration: 0.2)
            knightNode.run(move)
        } else {
            knightNode.position = destination
        }

        // 現在位置を保持し、アクセシビリティ情報を更新
        knightPosition = point
        updateAccessibilityElements()

        // 駒移動後の最終結果も残しておき、位置更新が反映されたかコンソールで追跡できるようにする
        debugLog("GameScene.moveKnight 完了: 現在位置=\(knightPosition)")
    }

    // MARK: - タップ処理

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
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
        // レイアウト未確定の場合は座標計算ができないため、VoiceOver 要素を一旦クリアする
        guard tileSize > 0 else {
            accessibilityElementsCache = []
            return
        }

        var elements: [UIAccessibilityElement] = []
        for y in 0..<board.size {
            for x in 0..<board.size {
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
                if let knightPosition, point == knightPosition {
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
    public override var accessibilityElements: [Any]? {
        get { accessibilityElementsCache }
        set { }
    }
    #else
    // UIKit が利用できない環境では空実装
    private func updateAccessibilityElements() {}
    #endif
}
#endif

