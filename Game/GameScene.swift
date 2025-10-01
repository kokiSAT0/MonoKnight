#if canImport(SpriteKit)
import SpriteKit
#if canImport(UIKit)
import UIKit
#endif
import SharedSupport // debugLog を利用するため共有モジュールを読み込む

/// 盤面ハイライトの種類を列挙するための型
/// - Note: ガイド表示の中でも単一候補と複数候補を分け、枠線の重なり順や色分けを柔軟に制御する
public enum BoardHighlightKind: CaseIterable, Hashable {
    /// 単一ベクトルカードを示す控えめなガイド枠
    case guideSingleCandidate
    /// 複数候補カードや選択肢を強調するためのガイド枠
    case guideMultipleCandidate
    /// チュートリアルやカード選択で強制的に表示するハイライト
    case forcedSelection
}

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

    /// 初期化時に設定された盤面サイズ
    /// - NOTE: 盤面サイズの拡張に備えて外部から指定できるよう保持する
    private let initialBoardSize: Int

    /// 初期化時に踏破済みにしておくマス集合
    /// - NOTE: 固定スポーンのモードでは中央など既定開始地点を踏破済みとして扱う
    private let initialVisitedPoints: [GridPoint]

    /// 初期化時に設定する追加踏破回数（複数回踏む必要があるマス）
    private let initialRequiredVisitOverrides: [GridPoint: Int]

    /// 初期化時に設定するトグルマス集合
    /// - NOTE: ギミックの再生成で情報が失われないよう、初期値として保持しておく
    private let initialTogglePoints: Set<GridPoint>

    /// 現在の盤面状態
    private var board: Board

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

    /// 複数回踏破マスの進捗リングを保持
    /// - NOTE: `tileNodes` と併せて管理し、盤面更新時に残り踏破回数を即座に反映できるようにする
    private var tileOverlayNodes: [GridPoint: SKShapeNode] = [:]

    /// ハイライト種類ごとのノードキャッシュ
    /// - Important: 種類ごとに辞書を分けることで、描画の上書き順とスタイルを柔軟に切り替えられる
    private var highlightNodes: [BoardHighlightKind: [GridPoint: SKShapeNode]] = [:]

    /// 単一ガイドの最新表示座標集合を保持
    /// - NOTE: 複数ガイドと重なる位置を判定する際の参照として利用する
    private var latestSingleGuidePoints: Set<GridPoint> = []

    /// 複数ガイドの最新表示座標集合を保持
    /// - NOTE: 将来的な整合性チェックやレイアウト調整時の参照に活用する
    private var latestMultipleGuidePoints: Set<GridPoint> = []

    /// 強制表示ハイライトの最新座標集合を保持
    /// - NOTE: 「リセット」などでガイドが空になっていない限り、直近状態を復元するためのソースとして利用する
    private var latestForcedSelectionPoints: Set<GridPoint> = []

    /// レイアウト未確定時に受け取ったハイライト要求の待ち行列
    /// - Note: キーごとに候補座標を保持し、レイアウト確定後にまとめて構築する
    private var pendingHighlightPoints: [BoardHighlightKind: Set<GridPoint>] =
        Dictionary(uniqueKeysWithValues: BoardHighlightKind.allCases.map { ($0, []) })

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
        // 盤面情報は初期化パラメータに基づいて常に再構築し、モードごとの盤面サイズ変更にも確実に対応する
        board = Board(
            size: initialBoardSize,
            initialVisitedPoints: initialVisitedPoints,
            requiredVisitOverrides: initialRequiredVisitOverrides,
            togglePoints: initialTogglePoints
        )
        // テーマもデフォルトへ戻し、SpriteKit 専用の配色が未設定のままでも破綻しないようフォールバックを適用
        palette = GameScenePalette.fallback
        // レイアウト関連の値をゼロクリアしておくことで、サイズ確定後の `calculateLayout` が必ず最新値を算出できる
        tileSize = 0
        gridOrigin = .zero
        // SpriteKit ノード系のキャッシュは全て空に戻し、不要なノードが残らないようにする
        tileNodes = [:]
        tileOverlayNodes = [:]
        highlightNodes = [:]
        latestSingleGuidePoints = []
        latestMultipleGuidePoints = []
        latestForcedSelectionPoints = []
        pendingHighlightPoints = Dictionary(
            uniqueKeysWithValues: BoardHighlightKind.allCases.map { ($0, []) }
        )
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

    /// コードから GameScene を生成する際のデフォルト初期化処理
    /// - NOTE: 既存仕様と同じ 5×5・中央踏破で生成するためのコンビニエンスイニシャライザ
    public override convenience init() {
        self.init(
            initialBoardSize: BoardGeometry.standardSize,
            initialVisitedPoints: BoardGeometry.defaultInitialVisitedPoints(for: BoardGeometry.standardSize)
        )
    }

    /// 任意の盤面サイズ・初期踏破設定で GameScene を生成するための指定イニシャライザ
    /// - Parameters:
    ///   - initialBoardSize: 初期盤面サイズ（N×N）
    ///   - initialVisitedPoints: 生成直後に踏破済みとして扱うマス集合。省略時は中央 1 マスのみを踏破する。
    public init(
        initialBoardSize: Int,
        initialVisitedPoints: [GridPoint]? = nil,
        requiredVisitOverrides: [GridPoint: Int] = [:],
        togglePoints: Set<GridPoint> = []
    ) {
        let resolvedVisitedPoints = initialVisitedPoints ?? BoardGeometry.defaultInitialVisitedPoints(for: initialBoardSize)
        self.initialBoardSize = initialBoardSize
        self.initialVisitedPoints = resolvedVisitedPoints
        self.initialRequiredVisitOverrides = requiredVisitOverrides
        self.initialTogglePoints = togglePoints
        self.board = Board(
            size: initialBoardSize,
            initialVisitedPoints: resolvedVisitedPoints,
            requiredVisitOverrides: requiredVisitOverrides,
            togglePoints: togglePoints
        )
        super.init(size: .zero)
        // 共通初期化で各種プロパティを統一的にリセットし、生成経路による差異を排除する
        commonInit()
        // 必要に応じて `calculateLayout()` などを明示的に呼び出し、シーンのサイズが既に確定している場合にも対応できるようにする
    }

    /// Interface Builder（Storyboard や XIB）経由の生成に対応するための初期化処理
    /// - NOTE: Apple の推奨に従い `super.init(coder:)` を呼び出し、アーカイブ復元時でも同じ初期状態を確保する
    public required init?(coder aDecoder: NSCoder) {
        self.initialBoardSize = BoardGeometry.standardSize
        let defaultVisitedPoints = BoardGeometry.defaultInitialVisitedPoints(for: BoardGeometry.standardSize)
        self.initialVisitedPoints = defaultVisitedPoints
        self.initialRequiredVisitOverrides = [:]
        self.initialTogglePoints = []
        self.board = Board(
            size: BoardGeometry.standardSize,
            initialVisitedPoints: defaultVisitedPoints,
            requiredVisitOverrides: [:],
            togglePoints: []
        )
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
            // NOTE: サイズ変更に合わせて枠線の太さや進捗リングの半径も更新する
            configureTileNodeAppearance(node, at: point)
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
        updateHighlightColors()

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

        for overlay in tileOverlayNodes.values {
            overlay.removeFromParent()
        }
        tileOverlayNodes.removeAll()

        for nodes in highlightNodes.values {
            for node in nodes.values {
                node.removeFromParent()
            }
        }
        highlightNodes.removeAll()
        pendingHighlightPoints = Dictionary(
            uniqueKeysWithValues: BoardHighlightKind.allCases.map { ($0, []) }
        )

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
                // NOTE: グリッド線はくっきり表示したいためアンチエイリアスを無効化し、直線的な輪郭を維持する
                node.isAntialiased = false
                node.lineJoin = .miter
                let point = GridPoint(x: x, y: y)
                addChild(node)
                tileNodes[point] = node
                // 生成直後に最新テーマへ沿った塗り色・枠線・オーバーレイ設定を適用して見た目を整える
                configureTileNodeAppearance(node, at: point)
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
            // NOTE: タイルごとに塗り色・枠線・オーバーレイを一括適用し、進捗表示を最新状態へ反映する
            configureTileNodeAppearance(node, at: point)
        }
        // タイル色が変わった際もガイドハイライトの色味を再評価して自然なバランスを保つ
        updateHighlightColors()
    }

    /// 指定座標の状態に応じたタイル色を計算する
    /// - Parameter point: 対象の盤面座標
    /// - Returns: 残り踏破回数に応じて補間した色
    private func tileFillColor(for point: GridPoint) -> SKColor {
        guard let state = board.state(at: point) else { return palette.boardTileUnvisited }
        return tileFillColor(for: state)
    }

    /// タイルの踏破状態から描画色を算出する
    /// - Parameter state: 現在のマス状態
    /// - Returns: 未踏破〜踏破済みまでの進捗に応じて補間された色
    private func tileFillColor(for state: TileState) -> SKColor {
        switch state.visitBehavior {
        case .toggle:
            // トグルマスは踏破状態に関わらず専用色で固定し、ギミックの存在を明確に示す
            return palette.boardTileToggle
        case .multi(required: _):
            // 複数回踏む必要があるマスは進捗率に応じて基準色→踏破済み色へ補間し、残回数の把握を助ける
            let progress = CGFloat(state.completionProgress)
            return palette.boardTileMultiBase.interpolated(to: palette.boardTileVisited, fraction: progress)
        case .single:
            // 通常マスは従来通りの配色で未踏破と踏破済みを切り替える
            return state.isVisited ? palette.boardTileVisited : palette.boardTileUnvisited
        }
    }

    /// 指定マスの塗り色・枠線・オーバーレイをまとめて適用する
    /// - Parameters:
    ///   - node: 対象となるタイルノード
    ///   - point: 対応する盤面座標
    private func configureTileNodeAppearance(_ node: SKShapeNode, at point: GridPoint) {
        node.fillColor = tileFillColor(for: point)

        guard let state = board.state(at: point) else {
            applySingleVisitStyle(to: node)
            removeMultiVisitOverlay(for: point)
            return
        }

        switch state.visitBehavior {
        case .multi:
            applyMultiVisitStyle(to: node, state: state, at: point)
        default:
            applySingleVisitStyle(to: node)
            removeMultiVisitOverlay(for: point)
        }
    }

    /// 通常マス向けの細いグリッド線を適用する
    /// - Parameter node: 対象ノード
    private func applySingleVisitStyle(to node: SKShapeNode) {
        node.strokeColor = palette.boardGridLine
        node.lineWidth = 1
    }

    /// 複数回踏破マス用に太い枠線と進捗リングを適用する
    /// - Parameters:
    ///   - node: 対象ノード
    ///   - state: 現在のマス状態
    ///   - point: 盤面座標
    private func applyMultiVisitStyle(to node: SKShapeNode, state: TileState, at point: GridPoint) {
        node.strokeColor = palette.boardTileMultiStroke
        let emphasizedLineWidth = max(tileSize * 0.06, 2.0)
        node.lineWidth = emphasizedLineWidth
        updateMultiVisitOverlay(
            for: point,
            parentNode: node,
            state: state,
            emphasizedLineWidth: emphasizedLineWidth
        )
    }

    /// 複数回踏破マスの残り回数に応じたリング表示を更新する
    /// - Parameters:
    ///   - point: 対象マスの座標
    ///   - parentNode: タイル本体のノード
    ///   - state: 現在のマス状態
    ///   - emphasizedLineWidth: タイル枠線の太さ（リングの内径算出に利用）
    private func updateMultiVisitOverlay(
        for point: GridPoint,
        parentNode: SKShapeNode,
        state: TileState,
        emphasizedLineWidth: CGFloat
    ) {
        let overlayNode: SKShapeNode
        if let cached = tileOverlayNodes[point] {
            overlayNode = cached
        } else {
            // NOTE: 進捗リングは円弧のみ描画するため、塗りを完全透過にしジャギーが出ないようアンチエイリアスも無効化する
            let newOverlay = SKShapeNode()
            newOverlay.name = "multiVisitOverlay"
            newOverlay.fillColor = .clear
            newOverlay.isAntialiased = false
            newOverlay.lineCap = .round
            newOverlay.lineJoin = .round
            newOverlay.zPosition = 0.12  // グリッド塗りより前面、ハイライトより背面に置く
            tileOverlayNodes[point] = newOverlay
            overlayNode = newOverlay
        }

        if overlayNode.parent !== parentNode {
            overlayNode.removeFromParent()
            parentNode.addChild(overlayNode)
        }

        overlayNode.strokeColor = palette.boardTileMultiStroke
        overlayNode.alpha = 0.95
        overlayNode.lineWidth = max(tileSize * 0.09, 1.6)
        overlayNode.zRotation = -.pi / 2  // 北側を起点に減少していくイメージを統一（円形表示時の基準）
        overlayNode.position = CGPoint(x: tileSize / 2, y: tileSize / 2)

        let radius = max(tileSize / 2 - emphasizedLineWidth * 0.65, tileSize * 0.28)
        let pathRect = CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
        let circularPath = CGPath(ellipseIn: pathRect, transform: nil)

        let requirement = max(state.requiredVisitCount, 1)
        let remaining = max(0, min(requirement, state.remainingVisits))
        let remainingFraction = requirement == 0
            ? 0
            : CGFloat(remaining) / CGFloat(requirement)

        if remaining == 0 {
            // 残り回数がゼロの場合はリングを完全に非表示にし、古いパスをクリアして次回再利用時のゴースト描画を防ぐ
            overlayNode.isHidden = true
            overlayNode.path = nil
            return
        }

        overlayNode.isHidden = false

        if remainingFraction < 1 {
            // 部分的な残量表示では開始角度を統一するため円弧パスを構築し、SpriteKit の回転起点をゼロに戻しておく
            let partialPath = CGMutablePath()
            partialPath.addArc(
                center: .zero,
                radius: radius,
                startAngle: -.pi / 2,
                endAngle: -.pi / 2 + 2 * .pi * remainingFraction,
                clockwise: false
            )
            overlayNode.path = partialPath
            overlayNode.zRotation = 0
        } else {
            // 全量残っている場合は従来の円形パスをそのまま利用し、余計なパス生成を避ける
            overlayNode.path = circularPath
            overlayNode.zRotation = -.pi / 2
        }

        if requirement > 1 {
            // 残り回数を視覚化するため、円周を回数分のセグメントへ分割する
            let circumference = max(2 * .pi * radius, 0.1)
            let segmentLength = circumference / CGFloat(requirement)
            let dashLength = max(segmentLength * 0.7, overlayNode.lineWidth * 0.9)
            let gapLength = max(segmentLength - dashLength, overlayNode.lineWidth * 0.6)
            overlayNode.lineDashPattern = [
                NSNumber(value: Double(dashLength)),
                NSNumber(value: Double(gapLength))
            ]
            overlayNode.lineDashPhase = 0
        } else {
            overlayNode.lineDashPattern = nil
        }
    }

    /// 複数回踏破マス用に生成したリングノードを安全に破棄する
    /// - Parameter point: 対象マスの座標
    private func removeMultiVisitOverlay(for point: GridPoint) {
        guard let overlay = tileOverlayNodes.removeValue(forKey: point) else { return }
        overlay.removeFromParent()
    }

    /// 盤面ハイライトの種類ごとの集合をまとめて更新する
    /// - Parameter highlights: 種類をキーとした盤面座標集合
    /// - NOTE: 将来ハイライト種別が増えても呼び出し側の構造を保てるよう辞書引数を採用している
    public func updateHighlights(_ highlights: [BoardHighlightKind: Set<GridPoint>]) {
        // キーが存在しない場合は空集合として扱い、不要なノードが残らないようにする
        var sanitized: [BoardHighlightKind: Set<GridPoint>] = [:]
        for kind in BoardHighlightKind.allCases {
            let requestedPoints = highlights[kind] ?? []
            let validPoints = Set(requestedPoints.filter { board.contains($0) })
            sanitized[kind] = validPoints
            pendingHighlightPoints[kind] = validPoints
        }

        // 正規化済みの集合を保持し、描画更新前後で最新状態を参照できるようにする
        latestSingleGuidePoints = sanitized[.guideSingleCandidate] ?? []
        latestMultipleGuidePoints = sanitized[.guideMultipleCandidate] ?? []
        latestForcedSelectionPoints = sanitized[.forcedSelection] ?? []

        let countsDescription = sanitized
            .map { "\($0.key)=\($0.value.count)" }
            .joined(separator: ", ")
        debugLog("GameScene ハイライト更新要求: \(countsDescription), レイアウト確定=\(isLayoutReady)")

        guard isLayoutReady else { return }

        applyHighlightsImmediately(sanitized)
        // 即時反映が完了したため、保留分はここで初期化しておく
        for kind in BoardHighlightKind.allCases {
            pendingHighlightPoints[kind] = []
        }
    }

    /// 既存 API との後方互換のため、ガイド種別だけを更新するコンビニエンスメソッド
    /// - Parameter points: ガイド表示したい盤面座標集合
    public func updateGuideHighlights(_ points: Set<GridPoint>) {
        // 既存 API から呼び出された場合は複数候補ガイド扱いとし、従来のオレンジ枠を維持する
        updateHighlights([
            .guideSingleCandidate: [],
            .guideMultipleCandidate: points
        ])
    }

    /// 辞書で受け取ったハイライト情報を即座にノードへ反映する
    /// - Parameter highlights: 種類ごとの有効な盤面座標集合
    private func applyHighlightsImmediately(_ highlights: [BoardHighlightKind: Set<GridPoint>]) {
        // 即時反映時も最新集合を保持し、ノード再構成時に参照できるようにする
        latestSingleGuidePoints = highlights[.guideSingleCandidate] ?? []
        latestMultipleGuidePoints = highlights[.guideMultipleCandidate] ?? []
        latestForcedSelectionPoints = highlights[.forcedSelection] ?? []

        for kind in BoardHighlightKind.allCases {
            let points = highlights[kind] ?? []
            rebuildHighlightNodes(for: kind, using: points)
        }
    }

    /// 指定された集合に合わせてハイライトノード群を再構築する
    /// - Parameters:
    ///   - kind: 更新対象となるハイライト種別
    ///   - points: 表示したい盤面座標の集合
    private func rebuildHighlightNodes(for kind: BoardHighlightKind, using points: Set<GridPoint>) {
        var nodesForKind = highlightNodes[kind] ?? [:]

        // 既存ハイライトのうち対象外になったものを削除
        for (point, node) in nodesForKind where !points.contains(point) {
            node.removeFromParent()
            nodesForKind.removeValue(forKey: point)
        }

        // 必要なマスへハイライトを再構成
        for point in points {
            if let node = nodesForKind[point] {
                // 既存ノードを再利用する際は親子関係が途切れていないか必ず確認する
                if node.parent !== self {
                    // SKView の再生成時に親を失ったノードを確実に再接続するため
                    addChild(node)
                }
                configureHighlightNode(node, for: point, kind: kind)
            } else {
                let node = SKShapeNode()
                configureHighlightNode(node, for: point, kind: kind)
                addChild(node)
                nodesForKind[point] = node
            }
        }

        highlightNodes[kind] = nodesForKind
    }

    /// 既存のハイライトノードを現在のテーマとマスサイズに合わせて更新
    private func updateHighlightColors() {
        // レイアウトが未確定のまま再描画しても意味が無いため、適切なサイズが得られるまで待機する
        guard isLayoutReady else { return }

        for (kind, nodes) in highlightNodes {
            for (point, node) in nodes {
                configureHighlightNode(node, for: point, kind: kind)
            }
        }
    }

    /// ハイライトノードへ共通のスタイルと位置を適用する
    /// - Parameters:
    ///   - node: 更新対象のノード
    ///   - point: 対応する盤面座標
    ///   - kind: 表示中のハイライト種別
    private func configureHighlightNode(_ node: SKShapeNode, for point: GridPoint, kind: BoardHighlightKind) {
        // SpriteKit の座標系ではノード中心が (0,0) なので、原点からタイル半分を引いた矩形を起点にする
        let baseRect = CGRect(
            x: -tileSize / 2,
            y: -tileSize / 2,
            width: tileSize,
            height: tileSize
        )
        let baseColor: SKColor
        let strokeAlpha: CGFloat
        let zPosition: CGFloat
        let strokeWidth: CGFloat
        // 単一・複数ガイドの双方で共有する線幅を定義し、視覚的一貫性を保つ
        let sharedGuideStrokeWidth = max(tileSize * 0.055, 2.0)
        // 複数ガイドが単一ガイドと重なった際に追加で内側へ寄せる量
        var overlapInset: CGFloat = 0
        switch kind {
        case .guideSingleCandidate:
            // 単一候補カードは落ち着いたグレートーンで表示し、重なった際に複数候補の枠が目立つようにする
            baseColor = palette.boardTileVisited
            strokeAlpha = 0.9
            strokeWidth = sharedGuideStrokeWidth
            zPosition = 0.95
        case .guideMultipleCandidate:
            baseColor = palette.boardGuideHighlight
            strokeAlpha = 0.88
            strokeWidth = sharedGuideStrokeWidth
            // 単一ガイドと重なる場合は枠線が密着しないよう更に内側へ寄せる
            if latestSingleGuidePoints.contains(point) {
                overlapInset = strokeWidth * 1.5
            }
            zPosition = 1.02
        case .forcedSelection:
            // NOTE: 現段階ではガイドと同じ色を使用しつつ、将来のカスタマイズ余地を残すため分岐を設けている
            baseColor = palette.boardGuideHighlight
            strokeAlpha = 1.0
            strokeWidth = max(tileSize * 0.07, 2.4)
            zPosition = 1.1
        }

        // rect.insetBy を用い、線幅の半分だけ内側に寄せて外周がグリッド線とぴったり接するよう調整
        // 複数ガイドで単一ガイドと重なった場合は追加の inset を適用し、オレンジ枠がグレー枠の内側に沿うよう微調整する
        let adjustedRect = baseRect.insetBy(
            dx: strokeWidth / 2 + overlapInset,
            dy: strokeWidth / 2 + overlapInset
        )
        node.path = CGPath(rect: adjustedRect, transform: nil)

        // 充填色は透過させ、枠線のみに集中させて過度な塗りつぶしを避ける
        node.fillColor = SKColor.clear
        node.strokeColor = baseColor.withAlphaComponent(strokeAlpha)
        node.lineWidth = strokeWidth
        node.glowWidth = 0

        // 角をシャープに保つために角丸設定を無効化し、SpriteKit のデフォルトより明示的にミタージョインを指定する
        node.lineJoin = .miter
        // lineJoin をミターにした際にエッジが過度に尖らないよう、適度な上限値を設ける
        node.miterLimit = 2.5
        // 終端も角を丸めず、グリッドの直線的な印象を優先する

        node.lineCap = .square
        node.position = position(for: point)
        node.zPosition = zPosition  // 種類ごとに重なり順を調整し、強制表示が埋もれないようにする
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

        // 駒の塗り色はテーマ切り替えの度に同期する
        knightNode?.fillColor = palette.boardKnight

        // レイアウトが確定していればその場で再描画し、未確定なら後で flush 時に反映する
        if isLayoutReady {
            updateTileColors()
        } else {
            for (point, node) in tileNodes {
                configureTileNodeAppearance(node, at: point)
            }
            updateHighlightColors()
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

    /// 保留中のハイライト情報があれば、レイアウト確定後に反映する
    private func applyPendingHighlightsIfNeeded() {
        guard isLayoutReady else { return }

        var snapshot: [BoardHighlightKind: Set<GridPoint>] = [:]
        for kind in BoardHighlightKind.allCases {
            snapshot[kind] = pendingHighlightPoints[kind] ?? []
        }

        let hasPendingValues = snapshot.values.contains { !$0.isEmpty }
        let hasRenderedHighlights = highlightNodes.values.contains { !$0.isEmpty }
        guard hasPendingValues || hasRenderedHighlights else { return }

        if hasPendingValues {
            // 未処理のハイライトが存在する場合はそのまま反映する
            applyHighlightsImmediately(snapshot)
        } else if hasRenderedHighlights {
            // pending が空でも既存ガイドを維持するため、直近状態を組み直して適用する
            let latestSnapshot: [BoardHighlightKind: Set<GridPoint>] = [
                .guideSingleCandidate: latestSingleGuidePoints,
                .guideMultipleCandidate: latestMultipleGuidePoints,
                .forcedSelection: latestForcedSelectionPoints
            ]
            let hasLatestValues = latestSnapshot.values.contains { !$0.isEmpty }
            if hasLatestValues {
                applyHighlightsImmediately(latestSnapshot)
            } else {
                // 直近状態も空であれば、既存ノードを確実に破棄するため空集合で再適用する
                applyHighlightsImmediately(snapshot)
            }
        }

        // `flushPendingUpdatesIfNeeded` から呼び出された際も、再構成が完了した時点で保留分をクリアする
        for kind in BoardHighlightKind.allCases {
            pendingHighlightPoints[kind] = []
        }
    }

    /// レイアウト確定後に盤面・駒・ガイドの保留更新をまとめて反映する
    private func flushPendingUpdatesIfNeeded() {
        guard isLayoutReady else {
            debugLog(
                "GameScene.flushPendingUpdatesIfNeeded: レイアウト未確定のため保留 updates を維持"
            )
            return
        }

        let pendingHighlightCount = pendingHighlightPoints.reduce(0) { $0 + $1.value.count }
        debugLog(
            "GameScene.flushPendingUpdatesIfNeeded: pendingBoard=\(pendingBoard != nil), pendingKnight=\(pendingKnightState != nil), pendingHighlights=\(pendingHighlightCount)"
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
        applyPendingHighlightsIfNeeded()
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
        // Optional のまま出力すると `Optional(...)` という表記になって読みにくいため、nil と座標で明確に分岐させて文字列化する
        let positionDescription = knightPosition.map { "\($0)" } ?? "nil"
        debugLog("GameScene.moveKnight 完了: 現在位置=\(positionDescription)")
    }

    // MARK: - タップ処理

    #if canImport(UIKit)
    /// SpriteKit 上でのタップ終了時に呼び出され、UIKit のタッチイベントをゲームロジックへ受け渡す
    /// - NOTE: UIKit が利用できるプラットフォーム（iOS / tvOS）専用の実装とし、他プラットフォームではコンパイル対象外にする
    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        guard let point = gridPoint(from: location) else { return }
        gameCore?.handleTap(at: point)
    }
    #else
    // UIKit が利用できないプラットフォームでは SpriteKit のタップ入力を提供していない。
    // - NOTE: 想定外のターゲットでビルドした際にタッチ系 API を誤って利用しないよう明示しておく。
    #endif

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
                let statusText: String
                if let state = board.state(at: point) {
                    if state.isVisited {
                        statusText = "踏破済み"
                    } else if state.requiresMultipleVisits {
                        statusText = "踏破まであと\(state.remainingVisits)回"
                    } else {
                        statusText = "未踏破"
                    }
                } else {
                    statusText = "未踏破"
                }

                if let knightPosition, point == knightPosition {
                    element.accessibilityLabel = "駒あり " + statusText
                } else {
                    element.accessibilityLabel = statusText
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

/// タイル色を滑らかに補間するためのユーティリティ
private extension SKColor {
    /// 2 色間を線形補間した結果を返す
    /// - Parameters:
    ///   - other: 補間したい相手色
    ///   - fraction: 0.0〜1.0 の補間係数
    func interpolated(to other: SKColor, fraction: CGFloat) -> SKColor {
        let clamped = max(0.0, min(1.0, fraction))
        let first = rgbaComponents()
        let second = other.rgbaComponents()
        return SKColor(
            red: first.r + (second.r - first.r) * clamped,
            green: first.g + (second.g - first.g) * clamped,
            blue: first.b + (second.b - first.b) * clamped,
            alpha: first.a + (second.a - first.a) * clamped
        )
    }

    /// SKColor から sRGB 前提の RGBA 値を取得する
    private func rgbaComponents() -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        #if canImport(UIKit)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
        #else
        let converted = usingColorSpace(.extendedSRGB) ?? self
        return (
            converted.redComponent,
            converted.greenComponent,
            converted.blueComponent,
            converted.alphaComponent
        )
        #endif
    }
}
#endif

