#if canImport(SpriteKit)
    import SpriteKit
    #if canImport(UIKit)
        import UIKit
    #endif
    import SharedSupport  // debugLog を利用するため共有モジュールを読み込む

    /// 盤面ハイライトの種類を列挙するための型
    /// - Note: ガイド表示の中でも単一候補と複数候補を分け、枠線の重なり順や色分けを柔軟に制御する
    public enum BoardHighlightKind: CaseIterable, Hashable {
        /// 単一ベクトルカードを示す控えめなガイド枠
        case guideSingleCandidate
        /// 複数候補カードや選択肢を強調するためのガイド枠
        case guideMultipleCandidate
        /// 連続移動カード専用のシアン枠
        case guideMultiStepCandidate
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
        /// 初期化時に設定する移動不可マス集合
        /// - NOTE: ギミックよりも優先して障害物を固定し、レイアウト再構築時にも確実に反映する
        private let initialImpassablePoints: Set<GridPoint>
        /// 初期化時に設定するタイル効果一覧
        /// - NOTE: SpriteKit ノード再生成時にも同じ効果を復元できるよう保持する
        private let initialTileEffects: [GridPoint: TileEffect]

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

        /// 複数回踏破マスの進捗表示に利用するコンテナと子ノードのキャッシュ
        /// - NOTE: 対角線と四分割三角形をまとめて保持し、盤面更新時に再利用できるようにする
        private var tileMultiVisitDecorations: [GridPoint: MultiVisitDecorationCache] = [:]

        /// トグルマス専用の装飾ノードキャッシュ
        /// - NOTE: トグル演出は複数マスで共有するため、生成コストを抑える目的で辞書に再利用可能なノードを保持する
        private var tileToggleDecorations: [GridPoint: ToggleDecorationCache] = [:]
        /// タイル効果ごとの装飾ノードキャッシュ
        /// - NOTE: ワープや手札シャッフルなど効果別の見た目を保持し、サイズ変更時にも再利用する
        private var tileEffectDecorations: [GridPoint: TileEffectDecorationCache] = [:]

        /// ワープ効果ごとの視覚スタイルを記録するための構造体
        private struct WarpVisualStyle {
            /// 基本となるアクセントカラー
            let color: SKColor
            /// 描画する同心円の層数（色覚サポート用）
            let circleCount: Int
        }

        /// ワープペア ID をキーにした視覚スタイルキャッシュ
        private var warpVisualStyles: [String: WarpVisualStyle] = [:]
        /// 同時に重ねる同心円の最大層数
        private let maxWarpCircleLayers: Int = 4

        /// ハイライト種類ごとのノードキャッシュ
        /// - Important: 種類ごとに辞書を分けることで、描画の上書き順とスタイルを柔軟に切り替えられる
        private var highlightNodes: [BoardHighlightKind: [GridPoint: SKShapeNode]] = [:]
        /// ワープ演出など一時的に表示するエフェクトをまとめるためのコンテナ
        /// - Note: 盤面タイルより前面・騎士ノードより僅かに背面へ配置し、演出が主役を奪いすぎないよう調整する
        private let transientEffectContainer = SKNode()

        /// 単一ガイドの最新表示座標集合を保持
        /// - NOTE: 複数ガイドと重なる位置を判定する際の参照として利用する
        private var latestSingleGuidePoints: Set<GridPoint> = []

        /// 複数ガイドの最新表示座標集合を保持
        /// - NOTE: 将来的な整合性チェックやレイアウト調整時の参照に活用する
        private var latestMultipleGuidePoints: Set<GridPoint> = []
        /// 連続移動ガイドの最新座標集合を保持
        /// - NOTE: 複数ガイドや単一ガイドとの重なり調整に利用し、枠が視覚的に衝突しないようにする
        private var latestMultiStepGuidePoints: Set<GridPoint> = []

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

        /// 複数踏破マスの三角形セグメントを表す識別子
        /// - Note: 上→右→下→左の順に時計回りで並べ、塗り分けの進行順序を一定に保つ
        private enum MultiVisitTriangle: CaseIterable {
            case top
            case right
            case bottom
            case left

            /// 子ノードへアクセスするための一意な名前
            var nodeName: String {
                switch self {
                case .top: return "multiVisitTriangleTop"
                case .right: return "multiVisitTriangleRight"
                case .bottom: return "multiVisitTriangleBottom"
                case .left: return "multiVisitTriangleLeft"
                }
            }

            /// 現在のタイルサイズに応じた三角形パスを生成する
            /// - Parameter tileSize: マス一辺の長さ
            /// - Returns: センター原点で構成した CGPath
            func path(tileSize: CGFloat) -> CGPath {
                let half = tileSize / 2
                let path = CGMutablePath()
                path.move(to: .zero)

                switch self {
                case .top:
                    path.addLine(to: CGPoint(x: -half, y: half))
                    path.addLine(to: CGPoint(x: half, y: half))
                case .right:
                    path.addLine(to: CGPoint(x: half, y: half))
                    path.addLine(to: CGPoint(x: half, y: -half))
                case .bottom:
                    path.addLine(to: CGPoint(x: half, y: -half))
                    path.addLine(to: CGPoint(x: -half, y: -half))
                case .left:
                    path.addLine(to: CGPoint(x: -half, y: -half))
                    path.addLine(to: CGPoint(x: -half, y: half))
                }

                path.closeSubpath()
                return path
            }
        }

        /// 複数踏破マスの進捗装飾をまとめたキャッシュ構造体
        /// - Important: 子ノードは参照型のため構造体でも共有され、辞書から取り出して直接更新できる
        private struct MultiVisitDecorationCache {
            let container: SKNode
            let segments: [MultiVisitTriangle: SKShapeNode]
            let primaryDiagonal: SKShapeNode
            let secondaryDiagonal: SKShapeNode
        }

        /// トグルマス装飾をまとめたキャッシュ構造体
        /// - NOTE: 三角形 2 枚と対角線 1 本のみを保持し、不要なノードが残らないようにする
        private struct ToggleDecorationCache {
            let container: SKNode
            let cover: SKShapeNode
            let topLeftTriangle: SKShapeNode
            let bottomRightTriangle: SKShapeNode
            let diagonal: SKShapeNode
        }

        /// タイル効果の描画に利用するノードキャッシュ
        /// - Note: 効果種別ごとに線画と塗りのノードを分けて保持し、テーマ変更時に色をまとめて更新しやすくする
        private struct TileEffectDecorationCache {
            let container: SKNode
            var effect: TileEffect
            var strokeNodes: [SKShapeNode]
            var fillNodes: [SKShapeNode]
        }

        /// トグルマスの三角形形状を識別するための列挙体
        /// - NOTE: 盤面中央原点で扱いやすいよう、左上・右下の 2 種類に限定する
        private enum ToggleDecorationTriangle {
            case topLeft
            case bottomRight

            /// 生成したノードへ命名する際の識別子
            var nodeName: String {
                switch self {
                case .topLeft: return "toggleTriangleTopLeft"
                case .bottomRight: return "toggleTriangleBottomRight"
                }
            }

            /// 現在のタイルサイズに合わせたパスを生成する
            /// - Parameter tileSize: マス一辺の長さ
            /// - Returns: SpriteKit のローカル座標に合わせた CGPath
            func path(tileSize: CGFloat) -> CGPath {
                let half = tileSize / 2
                let path = CGMutablePath()

                switch self {
                case .topLeft:
                    // 左上三角形は右上→左下の対角線を基準にタイル上部を覆う
                    path.move(to: CGPoint(x: -half, y: half))
                    path.addLine(to: CGPoint(x: half, y: half))
                    path.addLine(to: CGPoint(x: -half, y: -half))
                case .bottomRight:
                    // 右下三角形は同じ対角線に沿ってタイル下部を塗り分ける
                    path.move(to: CGPoint(x: half, y: -half))
                    path.addLine(to: CGPoint(x: -half, y: -half))
                    path.addLine(to: CGPoint(x: half, y: half))
                }

                path.closeSubpath()
                return path
            }
        }

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
                togglePoints: initialTogglePoints,
                impassablePoints: initialImpassablePoints,
                tileEffects: initialTileEffects
            )
            // テーマもデフォルトへ戻し、SpriteKit 専用の配色が未設定のままでも破綻しないようフォールバックを適用
            palette = GameScenePalette.fallback
            // ワープ装飾スタイルのキャッシュをリセットし、現在の盤面とテーマから再計算する
            warpVisualStyles = [:]
            refreshWarpVisualStyles()
            // レイアウト関連の値をゼロクリアしておくことで、サイズ確定後の `calculateLayout` が必ず最新値を算出できる
            tileSize = 0
            gridOrigin = .zero
            // SpriteKit ノード系のキャッシュは全て空に戻し、不要なノードが残らないようにする
            tileNodes = [:]
            tileMultiVisitDecorations = [:]
            tileToggleDecorations = [:]
            for decoration in tileEffectDecorations.values {
                decoration.container.removeFromParent()
            }
            tileEffectDecorations = [:]
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
            // 一時演出コンテナもリセットして、前回のリング等が新しいゲームへ持ち越されないようにする
            transientEffectContainer.removeAllActions()
            transientEffectContainer.removeAllChildren()
            transientEffectContainer.position = .zero
            transientEffectContainer.zPosition = 1.7
            transientEffectContainer.isHidden = false
            if transientEffectContainer.parent !== self {
                addChild(transientEffectContainer)
            }
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
                initialVisitedPoints: BoardGeometry.defaultInitialVisitedPoints(
                    for: BoardGeometry.standardSize)
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
            togglePoints: Set<GridPoint> = [],
            impassablePoints: Set<GridPoint> = [],
            tileEffects: [GridPoint: TileEffect] = [:]
        ) {
            let resolvedVisitedPoints =
                initialVisitedPoints
                ?? BoardGeometry.defaultInitialVisitedPoints(for: initialBoardSize)
            self.initialBoardSize = initialBoardSize
            self.initialVisitedPoints = resolvedVisitedPoints
            self.initialRequiredVisitOverrides = requiredVisitOverrides
            self.initialTogglePoints = togglePoints
            self.initialImpassablePoints = impassablePoints
            self.initialTileEffects = tileEffects
            self.board = Board(
                size: initialBoardSize,
                initialVisitedPoints: resolvedVisitedPoints,
                requiredVisitOverrides: requiredVisitOverrides,
                togglePoints: togglePoints,
                impassablePoints: impassablePoints,
                tileEffects: tileEffects
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
            let defaultVisitedPoints = BoardGeometry.defaultInitialVisitedPoints(
                for: BoardGeometry.standardSize)
            self.initialVisitedPoints = defaultVisitedPoints
            self.initialRequiredVisitOverrides = [:]
            self.initialTogglePoints = []
            self.initialImpassablePoints = []
            self.initialTileEffects = [:]
            self.board = Board(
                size: BoardGeometry.standardSize,
                initialVisitedPoints: defaultVisitedPoints,
                requiredVisitOverrides: [:],
                togglePoints: [],
                impassablePoints: [],
                tileEffects: [:]
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
                // 盤面原点が中央の座標系を維持するため、中心起点の矩形パスを再生成する
                let rect = CGRect(
                    x: -tileSize / 2,
                    y: -tileSize / 2,
                    width: tileSize,
                    height: tileSize
                )
                node.path = CGPath(rect: rect, transform: nil)
                // 原点移動後もタイル中心へ揃うよう座標を再計算して適用する
                node.position = position(for: point)
                // NOTE: サイズ変更に合わせて枠線の太さや進捗リングの半径も更新する
                configureTileNodeAppearance(node, at: point)
            }

            // 駒ノードも新しいレイアウト上の中心座標へ移動し、半径をタイル比率に合わせて補正する
            if let knightNode, let knightPosition {
                // 駒が存在する場合のみ新しいレイアウトに合わせて再配置する
                knightNode.position = position(for: knightPosition)
                let radius = tileSize * 0.4
                let circleRect = CGRect(
                    x: -radius, y: -radius, width: radius * 2, height: radius * 2)
                knightNode.path = CGPath(ellipseIn: circleRect, transform: nil)
            } else if let knightNode {
                // スポーン未確定などで現在位置が無い場合は描画だけ更新して非表示のまま維持する
                let radius = tileSize * 0.4
                let circleRect = CGRect(
                    x: -radius, y: -radius, width: radius * 2, height: radius * 2)
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

            for decoration in tileMultiVisitDecorations.values {
                decoration.container.removeFromParent()
            }
            tileMultiVisitDecorations.removeAll()

            for decoration in tileToggleDecorations.values {
                decoration.container.removeFromParent()
            }
            tileToggleDecorations.removeAll()

            for decoration in tileEffectDecorations.values {
                decoration.container.removeFromParent()
            }
            tileEffectDecorations.removeAll()

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
                    // 各タイルは中心原点で扱いたいため `rectOf:` を利用して生成する
                    let node = SKShapeNode(rectOf: CGSize(width: tileSize, height: tileSize))
                    // NOTE: グリッド線はくっきり表示したいためアンチエイリアスを無効化し、直線的な輪郭を維持する
                    node.isAntialiased = false
                    node.lineJoin = .miter
                    let point = GridPoint(x: x, y: y)
                    // 原点が中心となるよう、グリッド座標に応じた位置を改めて設定する
                    node.position = position(for: point)
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
            debugLog(
                "GameScene.setupKnight: radius=\(radius), position=\(node.position), hidden=\(node.isHidden)"
            )
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
            refreshWarpVisualStyles()

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
            case .impassable:
                // 移動不可マスは踏破進捗に関係なく専用色で塗り潰し、盤面上で障害物がひと目で分かるようにする
                return palette.boardTileImpassable
            case .toggle:
                // トグルマスは踏破状態に関わらず専用色で固定し、ギミックの存在を明確に示す
                return .clear
            case .multi:
                // 四分割セグメント自体が最終的な色味を司るため、ベースの塗りは透明にして干渉を避ける
                return .clear
            case .single:
                // 通常マスは従来通りの配色で未踏破と踏破済みを切り替える
                return state.isVisited ? palette.boardTileVisited : palette.boardTileUnvisited
            }
        }

        /// 既存色のアルファ値へ倍率を掛けた結果を返す
        /// - Parameters:
        ///   - color: 基準となる色
        ///   - factor: 掛け合わせたい係数（0.0〜1.0 を想定）
        /// - Returns: 元の色味を保ったままアルファ値だけを調整した色
        private func colorByScalingAlpha(of color: SKColor, factor: CGFloat) -> SKColor {
            // SKColor は UIColor を基底にしているため、cgColor.alpha から現在のアルファを取得できる
            let currentAlpha = color.cgColor.alpha
            // 係数が範囲外でも描画が破綻しないよう、0.0〜1.0 に収めてから適用する
            let clampedAlpha = max(0.0, min(1.0, currentAlpha * factor))
            return color.withAlphaComponent(clampedAlpha)
        }

        /// 現在の盤面構成とテーマに合わせてワープ装飾のスタイルを再計算する
        private func refreshWarpVisualStyles() {
            var detectedPairIDs: Set<String> = []
            for y in 0..<board.size {
                for x in 0..<board.size {
                    let point = GridPoint(x: x, y: y)
                    if case .warp(let pairID, _) = board.effect(at: point) {
                        detectedPairIDs.insert(pairID)
                    }
                }
            }

            let sortedPairIDs = detectedPairIDs.sorted()
            var updatedStyles: [String: WarpVisualStyle] = [:]
            for (index, pairID) in sortedPairIDs.enumerated() {
                let color = warpAccentColor(for: index)
                let circleCount = max(1, min(maxWarpCircleLayers, index + 1))
                updatedStyles[pairID] = WarpVisualStyle(color: color, circleCount: circleCount)
            }
            warpVisualStyles = updatedStyles
        }

        /// ペアの表示順に応じたアクセントカラーを取得する
        /// - Parameter pairIndex: ソート済み配列内でのインデックス
        /// - Returns: SpriteKit で利用する SKColor
        private func warpAccentColor(for pairIndex: Int) -> SKColor {
            if pairIndex < palette.warpPairAccentColors.count {
                return palette.warpPairAccentColors[pairIndex]
            }

            // 用意した色数を超える場合は最後の色を基準にアルファで差を付ける
            let fallbackBase = palette.warpPairAccentColors.last ?? palette.boardTileEffectWarp
            let attenuationStep = 0.12 * CGFloat(pairIndex - palette.warpPairAccentColors.count + 1)
            let attenuation = max(0.4, 1.0 - attenuationStep)
            return fallbackBase.withAlphaComponent(attenuation)
        }

        /// 指定されたペア ID に対応する視覚スタイルを返す
        /// - Parameter pairID: ワープペアの識別子
        /// - Returns: 色と同心円数を内包したスタイル情報
        private func warpVisualStyle(for pairID: String) -> WarpVisualStyle {
            if let cached = warpVisualStyles[pairID] {
                return cached
            }
            let fallback = WarpVisualStyle(color: palette.boardTileEffectWarp, circleCount: 1)
            warpVisualStyles[pairID] = fallback
            return fallback
        }

        /// 指定マスの塗り色・枠線・オーバーレイをまとめて適用する
        /// - Parameters:
        ///   - node: 対象となるタイルノード
        ///   - point: 対応する盤面座標
        private func configureTileNodeAppearance(_ node: SKShapeNode, at point: GridPoint) {
            node.fillColor = tileFillColor(for: point)

            guard let state = board.state(at: point) else {
                applySingleVisitStyle(to: node)
                removeMultiVisitDecoration(for: point)
                removeToggleDecoration(for: point)
                removeEffectDecoration(for: point)
                return
            }

            switch state.visitBehavior {
            case .multi:
                applyMultiVisitStyle(to: node, state: state, at: point)
                removeToggleDecoration(for: point)
            case .toggle:
                applyToggleStyle(to: node, state: state, at: point)
                removeMultiVisitDecoration(for: point)
            case .impassable:
                applyImpassableStyle(to: node)
                removeMultiVisitDecoration(for: point)
                removeToggleDecoration(for: point)
            case .single:
                applySingleVisitStyle(to: node)
                removeMultiVisitDecoration(for: point)
                removeToggleDecoration(for: point)
            }

            updateEffectDecoration(
                for: point,
                parentNode: node,
                effect: state.effect ?? board.effect(at: point)
            )
        }

        /// 通常マス向けの細いグリッド線を適用する
        /// - Parameter node: 対象ノード
        private func applySingleVisitStyle(to node: SKShapeNode) {
            node.strokeColor = palette.boardGridLine
            node.lineWidth = 1
        }

        /// 複数回踏破マス用に太い枠線と進捗オーバーレイを適用する
        /// - Parameters:
        ///   - node: 対象ノード
        ///   - state: 現在のマス状態
        ///   - point: 盤面座標
        private func applyMultiVisitStyle(
            to node: SKShapeNode, state: TileState, at point: GridPoint
        ) {
            node.strokeColor = palette.boardTileMultiStroke
            // NOTE: 盤面全体の視覚的一貫性を優先し、複数踏破マスでも通常グリッドと同じ線幅 (1pt) を採用する
            node.lineWidth = 1
            updateMultiVisitDecoration(for: point, parentNode: node, state: state)
        }

        /// トグルマス専用の枠線・装飾を適用する
        /// - Parameters:
        ///   - node: 対象ノード
        ///   - state: 現在のマス状態
        ///   - point: 盤面座標
        private func applyToggleStyle(to node: SKShapeNode, state: TileState, at point: GridPoint) {
            // トグルマスはギミックとして視認しやすいよう高コントラストな線色を採用する
            node.strokeColor = palette.boardTileMultiStroke
            node.lineWidth = 1
            updateToggleDecoration(for: point, parentNode: node, state: state)
        }

        /// 移動不可マス専用のシンプルな塗りのみを適用する
        /// - Parameter node: 対象ノード
        private func applyImpassableStyle(to node: SKShapeNode) {
            // 障害物は塗りのみで情報が伝わるよう枠線を取り除き、余計な装飾を付けない
            node.strokeColor = .clear
            node.lineWidth = 0
            node.glowWidth = 0
        }

        /// 複数回踏破マスの対角線と四分割三角形をまとめて更新する
        /// - Parameters:
        ///   - point: 対象マスの座標
        ///   - parentNode: 親となるタイルノード
        ///   - state: 現在のマス状態
        private func updateMultiVisitDecoration(
            for point: GridPoint,
            parentNode: SKShapeNode,
            state: TileState
        ) {
            let decoration: MultiVisitDecorationCache

            if let cached = tileMultiVisitDecorations[point] {
                decoration = cached
            } else {
                // NOTE: 初回はコンテナと子ノードをまとめて生成し、以降は辞書キャッシュ経由で再利用する
                let container = SKNode()
                container.name = "multiVisitDecorationContainer"
                container.zPosition = 0.14  // グリッド塗りより前面、ハイライトより背面に配置する

                var segments: [MultiVisitTriangle: SKShapeNode] = [:]
                for triangle in MultiVisitTriangle.allCases {
                    let segmentNode = SKShapeNode()
                    segmentNode.name = triangle.nodeName
                    segmentNode.strokeColor = .clear
                    segmentNode.lineWidth = 0
                    segmentNode.isAntialiased = true
                    // NOTE: ベース塗りとのアルファ合成を避け、セグメントの色をそのまま反映させる
                    segmentNode.blendMode = .alpha
                    segmentNode.zPosition = 0
                    container.addChild(segmentNode)
                    segments[triangle] = segmentNode
                }

                let primaryDiagonal = SKShapeNode()
                primaryDiagonal.name = "multiVisitDiagonalPrimary"
                primaryDiagonal.fillColor = .clear
                primaryDiagonal.lineJoin = .round
                primaryDiagonal.lineCap = .round
                primaryDiagonal.isAntialiased = true
                primaryDiagonal.zPosition = 0.05
                container.addChild(primaryDiagonal)

                let secondaryDiagonal = SKShapeNode()
                secondaryDiagonal.name = "multiVisitDiagonalSecondary"
                secondaryDiagonal.fillColor = .clear
                secondaryDiagonal.lineJoin = .round
                secondaryDiagonal.lineCap = .round
                secondaryDiagonal.isAntialiased = true
                secondaryDiagonal.zPosition = 0.05
                container.addChild(secondaryDiagonal)

                let cache = MultiVisitDecorationCache(
                    container: container,
                    segments: segments,
                    primaryDiagonal: primaryDiagonal,
                    secondaryDiagonal: secondaryDiagonal
                )
                tileMultiVisitDecorations[point] = cache
                decoration = cache
            }

            if decoration.container.parent !== parentNode {
                decoration.container.removeFromParent()
                parentNode.addChild(decoration.container)
            }

            // タイルノードのローカル原点が中心となるため、装飾も原点ゼロで重ねる
            decoration.container.position = .zero

            // タイルサイズが変わった場合に備え、毎回パスを生成し直しておく
            for triangle in MultiVisitTriangle.allCases {
                decoration.segments[triangle]?.path = triangle.path(tileSize: tileSize)
            }

            // NOTE: 複数踏破マスの視覚化は四分割（三角形 4 つ）で統一しているため、配列数をそのまま進捗計算に利用する
            let totalSegmentCount = MultiVisitTriangle.allCases.count
            let requiredVisits = max(0, state.requiredVisitCount)
            if requiredVisits > totalSegmentCount {
                debugLog(
                    "GameScene.updateMultiVisitDecoration 警告: 対応上限を超える踏破回数を検出 point=\(point) required=\(requiredVisits)"
                )
            }

            // NOTE: 塗り分けは 4 セグメントを上限として扱うため、残踏破回数も同じ範囲で丸める
            let clampedRemaining = max(0, min(state.remainingVisits, totalSegmentCount))
            // 仕様変更: 残踏破回数を 4 セグメントに割り当て、未踏破分から塗りつぶしを進める方式へ統一する
            // NOTE: 進捗可視化は「残り踏破数」が基準となるため、踏破済みセグメント数は残量から逆算する
            let filledSegmentCount = max(
                0, min(totalSegmentCount, totalSegmentCount - clampedRemaining))
            // NOTE: アクティブなセグメントは常に 4 つ描画し、残量に応じて塗り分けだけを変更する
            let activeSegmentCount = totalSegmentCount

            // 進捗の有無に応じてオーバーレイの表示/非表示を切り替える
            // - NOTE: 「未踏破」「全踏破」の状態では通常マスと同じ見た目に揃えたいため、
            //         四分割セグメントと対角線はまとめて隠す
            let isCompleted = state.isVisited || clampedRemaining == 0
            // NOTE: 必要踏破回数が 2 以上であれば、踏破済み/未踏破を問わず進捗オーバーレイを常時表示する
            //       （1 回のみのタイルは従来通り通常マスと同じ見た目を維持する）
            let shouldShowProgress = requiredVisits > 1

            if !shouldShowProgress {
                // 進捗が無い or 既に完了した場合はオーバーレイ全体を非表示にし、
                // 再度表示するタイミングでの色ズレを防ぐため塗り色だけ基準色に揃えておく
                // NOTE: 進捗オーバーレイを出さない場合でも、再表示直後に未踏破/踏破済みの色味へ即時切り替わるよう
                //       パレットの基準色（未踏破 or 踏破済み）を事前にセットしておく
                let baseColor = isCompleted ? palette.boardTileVisited : palette.boardTileUnvisited
                decoration.container.isHidden = true

                for triangle in MultiVisitTriangle.allCases {
                    guard let segmentNode = decoration.segments[triangle] else { continue }
                    segmentNode.fillColor = baseColor
                    segmentNode.isHidden = true
                }

                decoration.primaryDiagonal.isHidden = true
                decoration.secondaryDiagonal.isHidden = true
                return
            }

            // 部分踏破中は従来のステージ別カラーリングを維持しつつオーバーレイを表示する
            decoration.container.isHidden = false
            decoration.primaryDiagonal.isHidden = false
            decoration.secondaryDiagonal.isHidden = false

            // 部分踏破の残量を視覚的に把握しやすいよう、塗り色は踏破済み/未踏破の 2 種類に統一する
            // NOTE: 進捗セグメントの色は通常タイルと同じ値を採用し、ゲーム中に色味が破綻しないよう統一する
            // NOTE: 踏破済みセグメントの塗りつぶしは通常マスと完全に同じグレーを共有し、表示差異を無くす
            let completedColor = palette.boardTileVisited
            // NOTE: 未踏破領域も通常マスの未踏破色をそのまま転用し、段階演出を純粋な面積差で伝える
            let pendingColor = palette.boardTileUnvisited

            for (index, triangle) in MultiVisitTriangle.allCases.enumerated() {
                guard let segmentNode = decoration.segments[triangle] else { continue }

                let isFilled = index < filledSegmentCount

                // NOTE: 仕様変更により常時 4 セグメントを描画し、残踏破数に応じて踏破色/未踏破色を切り替える
                segmentNode.fillColor = isFilled ? completedColor : pendingColor
                // NOTE: 過去にアルファ調整を行ったノードが残っても色味が変わらないよう、毎回不透明度をリセットする
                segmentNode.alpha = 1.0
                // NOTE: 現仕様では全セグメントが有効となるが、将来のセグメント数増減にも対応できるよう判定を残している
                segmentNode.isHidden = index >= activeSegmentCount
            }

            let half = tileSize / 2
            // NOTE: オーバーレイの対角線もグリッド線に揃えて 1pt へ統一し、余計な強調を避ける
            let diagonalWidth: CGFloat = 1.0
            let diagonalAlpha: CGFloat = 0.9

            let primaryPath = CGMutablePath()
            primaryPath.move(to: CGPoint(x: -half, y: -half))
            primaryPath.addLine(to: CGPoint(x: half, y: half))
            decoration.primaryDiagonal.path = primaryPath
            decoration.primaryDiagonal.strokeColor = palette.boardTileMultiStroke
            decoration.primaryDiagonal.lineWidth = diagonalWidth
            decoration.primaryDiagonal.alpha = diagonalAlpha

            let secondaryPath = CGMutablePath()
            secondaryPath.move(to: CGPoint(x: -half, y: half))
            secondaryPath.addLine(to: CGPoint(x: half, y: -half))
            decoration.secondaryDiagonal.path = secondaryPath
            decoration.secondaryDiagonal.strokeColor = palette.boardTileMultiStroke
            decoration.secondaryDiagonal.lineWidth = diagonalWidth
            decoration.secondaryDiagonal.alpha = diagonalAlpha
        }

        /// 複数回踏破マス用に生成した装飾ノードを安全に破棄する
        /// - Parameter point: 対象マスの座標
        private func removeMultiVisitDecoration(for point: GridPoint) {
            guard let decoration = tileMultiVisitDecorations.removeValue(forKey: point) else {
                return
            }
            decoration.container.removeAllActions()
            decoration.container.removeFromParent()
        }

        /// トグルマス装飾を安全に破棄する
        /// - Parameter point: 対象マスの座標
        private func removeToggleDecoration(for point: GridPoint) {
            guard let decoration = tileToggleDecorations.removeValue(forKey: point) else { return }
            decoration.container.removeAllActions()
            decoration.container.removeFromParent()
        }

        /// タイル効果装飾を安全に破棄する
        /// - Parameter point: 対象マスの座標
        private func removeEffectDecoration(for point: GridPoint) {
            guard let decoration = tileEffectDecorations.removeValue(forKey: point) else { return }
            decoration.container.removeAllActions()
            decoration.container.removeFromParent()
        }

        /// トグルマスの三角形と対角線装飾を生成・更新する
        /// - Parameters:
        ///   - point: 対象マスの座標
        ///   - parentNode: 装飾を載せる親ノード
        ///   - state: 現在のマス状態
        private func updateToggleDecoration(
            for point: GridPoint,
            parentNode: SKShapeNode,
            state: TileState
        ) {
            let decoration: ToggleDecorationCache

            if let cached = tileToggleDecorations[point] {
                decoration = cached
            } else {
                // NOTE: 初回のみノードを生成し、以降は辞書経由で再利用する
                let container = SKNode()
                container.name = "toggleDecorationContainer"
                container.zPosition = 0.13  // グリッド塗りより前面に置き、ガイド枠より背面に揃える

                let cover = SKShapeNode(rectOf: CGSize(width: tileSize, height: tileSize))
                cover.name = "toggleCover"
                cover.strokeColor = .clear
                cover.isAntialiased = false
                cover.blendMode = .alpha
                cover.zPosition = -0.01  // 三角形よりわずかに背面
                container.addChild(cover)

                let topLeftTriangle = SKShapeNode()
                topLeftTriangle.name = ToggleDecorationTriangle.topLeft.nodeName
                topLeftTriangle.strokeColor = .clear
                topLeftTriangle.lineWidth = 0
                topLeftTriangle.isAntialiased = true
                topLeftTriangle.blendMode = .alpha
                container.addChild(topLeftTriangle)

                let bottomRightTriangle = SKShapeNode()
                bottomRightTriangle.name = ToggleDecorationTriangle.bottomRight.nodeName
                bottomRightTriangle.strokeColor = .clear
                bottomRightTriangle.lineWidth = 0
                bottomRightTriangle.isAntialiased = true
                bottomRightTriangle.blendMode = .alpha
                container.addChild(bottomRightTriangle)

                let diagonal = SKShapeNode()
                diagonal.name = "toggleDecorationDiagonal"
                diagonal.fillColor = .clear
                diagonal.strokeColor = palette.boardTileMultiStroke
                diagonal.lineWidth = 1
                diagonal.lineJoin = .round
                diagonal.lineCap = .round
                diagonal.isAntialiased = true
                diagonal.blendMode = .alpha
                container.addChild(diagonal)

                let cache = ToggleDecorationCache(
                    container: container,
                    cover: cover,
                    topLeftTriangle: topLeftTriangle,
                    bottomRightTriangle: bottomRightTriangle,
                    diagonal: diagonal
                )
                tileToggleDecorations[point] = cache
                decoration = cache
            }

            if decoration.container.parent !== parentNode {
                decoration.container.removeFromParent()
                parentNode.addChild(decoration.container)
            }

            // タイルノード中心を原点とする座標系に合わせて装飾を再配置する
            decoration.container.position = .zero
            decoration.container.isHidden = false

            // --- cover を毎回サイズ・色を更新して下層を完全に覆う ---
            let coverRect = CGRect(
                x: -tileSize / 2, y: -tileSize / 2,
                width: tileSize, height: tileSize)
            decoration.cover.path = CGPath(rect: coverRect, transform: nil)
            decoration.cover.fillColor = .clear
            decoration.cover.alpha = 0.0
            decoration.cover.isHidden = false

            // タイルサイズ変化へ追従できるよう、描画の度にパスを更新する
            decoration.topLeftTriangle.path = ToggleDecorationTriangle.topLeft.path(
                tileSize: tileSize)
            decoration.bottomRightTriangle.path = ToggleDecorationTriangle.bottomRight.path(
                tileSize: tileSize)

            // 右下三角形は常に踏破済みカラーで塗りつぶし、ギミック方向を固定表示する
            decoration.bottomRightTriangle.fillColor = palette.boardTileVisited
            decoration.bottomRightTriangle.alpha = 1.0
            decoration.bottomRightTriangle.isHidden = false

            // 左上三角形は現在の踏破状態に応じて未踏破/踏破色をトグルさせる
            decoration.topLeftTriangle.fillColor =
                state.isVisited
                ? palette.boardTileVisited
                : palette.boardTileUnvisited
            decoration.topLeftTriangle.alpha = 1.0
            decoration.topLeftTriangle.isHidden = false

            // 右上→左下の対角線で視線誘導し、トグル方向を明示する
            let half = tileSize / 2
            let diagonalPath = CGMutablePath()
            diagonalPath.move(to: CGPoint(x: half, y: half))
            diagonalPath.addLine(to: CGPoint(x: -half, y: -half))
            decoration.diagonal.path = diagonalPath
            decoration.diagonal.strokeColor = palette.boardTileMultiStroke
            decoration.diagonal.lineWidth = 1
            decoration.diagonal.alpha = 1.0
            decoration.diagonal.isHidden = false
        }

        /// タイル効果用の装飾ノードを生成・更新する
        /// - Parameters:
        ///   - point: 対象マスの座標
        ///   - parentNode: 装飾を追加する親タイルノード
        ///   - effect: 適用するタイル効果（nil の場合は装飾を取り除く）
        private func updateEffectDecoration(
            for point: GridPoint,
            parentNode: SKShapeNode,
            effect: TileEffect?
        ) {
            guard let effect else {
                removeEffectDecoration(for: point)
                return
            }

            var decoration: TileEffectDecorationCache
            if let cached = tileEffectDecorations[point], cached.effect == effect {
                decoration = cached
            } else {
                removeEffectDecoration(for: point)
                decoration = makeEffectDecoration(for: effect)
            }

            if decoration.container.parent !== parentNode {
                decoration.container.removeFromParent()
                parentNode.addChild(decoration.container)
            }

            decoration.container.position = .zero
            decoration.container.zPosition = 0.16  // トグル/マルチ装飾より前面に配置する
            decoration.container.isHidden = false

            configureEffectDecorationGeometry(&decoration, effect: effect, point: point)
            applyEffectDecorationColors(&decoration, effect: effect)
            decoration.effect = effect
            tileEffectDecorations[point] = decoration
        }

        /// 効果種別に応じた装飾ノードを生成する
        /// - Parameter effect: 描画対象のタイル効果
        /// - Returns: 生成したキャッシュ情報
        private func makeEffectDecoration(for effect: TileEffect) -> TileEffectDecorationCache {
            let container = SKNode()
            container.name = "tileEffectDecorationContainer"
            container.isHidden = false

            switch effect {
            case .warp:
                // NOTE: ワープマスは多重円のみで視覚化し、旧 SDK でも動作するシンプルな線画に統一する
                return TileEffectDecorationCache(
                    container: container,
                    effect: effect,
                    strokeNodes: [],
                    fillNodes: []
                )
            case .shuffleHand:
                let diamond = SKShapeNode()
                diamond.name = "tileEffectShuffleDiamond"
                diamond.strokeColor = .clear
                diamond.fillColor = .clear
                diamond.lineWidth = 1
                diamond.isAntialiased = false
                diamond.blendMode = .alpha

                let leftArrow = SKShapeNode()
                leftArrow.name = "tileEffectShuffleLeftArrow"
                leftArrow.strokeColor = .clear
                leftArrow.fillColor = .clear
                leftArrow.lineWidth = 0
                leftArrow.isAntialiased = true
                leftArrow.blendMode = .alpha

                let rightArrow = SKShapeNode()
                rightArrow.name = "tileEffectShuffleRightArrow"
                rightArrow.strokeColor = .clear
                rightArrow.fillColor = .clear
                rightArrow.lineWidth = 0
                rightArrow.isAntialiased = true
                rightArrow.blendMode = .alpha

                container.addChild(diamond)
                container.addChild(leftArrow)
                container.addChild(rightArrow)
                return TileEffectDecorationCache(
                    container: container,
                    effect: effect,
                    strokeNodes: [diamond],
                    fillNodes: [leftArrow, rightArrow]
                )
            }
        }

        /// 効果装飾の図形・サイズを現在のタイルサイズに合わせて更新する
        /// - Parameters:
        ///   - decoration: 更新対象のキャッシュ
        ///   - effect: 適用するタイル効果
        ///   - point: 対象マスの座標（ワープ先の方向計算に利用する）
        private func configureEffectDecorationGeometry(
            _ decoration: inout TileEffectDecorationCache,
            effect: TileEffect,
            point: GridPoint
        ) {
            switch effect {
            case .warp(let pairID, _):
                let style = warpVisualStyle(for: pairID)
                let desiredCircleCount = max(1, style.circleCount)

                if !decoration.fillNodes.isEmpty {
                    // NOTE: 多重円のみを残すため、旧バージョンの三角形ノードがあれば除去する
                    for node in decoration.fillNodes {
                        node.removeFromParent()
                    }
                    decoration.fillNodes.removeAll()
                }

                if decoration.strokeNodes.count > desiredCircleCount {
                    let surplus = decoration.strokeNodes.count - desiredCircleCount
                    for node in decoration.strokeNodes.suffix(surplus) {
                        node.removeFromParent()
                    }
                    decoration.strokeNodes.removeLast(surplus)
                }

                while decoration.strokeNodes.count < desiredCircleCount {
                    let circleNode = SKShapeNode()
                    circleNode.name = "tileEffectWarpCircle\(decoration.strokeNodes.count)"
                    circleNode.strokeColor = .clear
                    circleNode.fillColor = .clear
                    circleNode.lineWidth = 0
                    circleNode.isAntialiased = true
                    circleNode.blendMode = .alpha
                    circleNode.zPosition = -CGFloat(decoration.strokeNodes.count) * 0.01
                    decoration.container.addChild(circleNode)
                    decoration.strokeNodes.append(circleNode)
                }

                let baseRadius = tileSize * 0.34
                let spacing = tileSize * 0.06
                for (index, circle) in decoration.strokeNodes.enumerated() {
                    let radius = max(tileSize * 0.14, baseRadius - CGFloat(index) * spacing)
                    let rect = CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
                    circle.path = CGPath(ellipseIn: rect, transform: nil)
                    circle.lineWidth = max(1.0, tileSize * 0.035)
                    circle.position = .zero
                }
            case .shuffleHand:
                guard let diamond = decoration.strokeNodes.first,
                      decoration.fillNodes.count >= 2 else { return }

                let diamondRadius = tileSize * 0.34
                let diamondPath = CGMutablePath()
                diamondPath.move(to: CGPoint(x: 0, y: diamondRadius))
                diamondPath.addLine(to: CGPoint(x: diamondRadius, y: 0))
                diamondPath.addLine(to: CGPoint(x: 0, y: -diamondRadius))
                diamondPath.addLine(to: CGPoint(x: -diamondRadius, y: 0))
                diamondPath.closeSubpath()
                diamond.path = diamondPath
                diamond.lineWidth = max(1.0, tileSize * 0.05)

                let arrowLength = tileSize * 0.24
                let arrowWidth = tileSize * 0.16

                let leftArrow = decoration.fillNodes[0]
                let leftPath = CGMutablePath()
                leftPath.move(to: CGPoint(x: -arrowLength / 2, y: 0))
                leftPath.addLine(to: CGPoint(x: arrowLength / 2, y: arrowWidth / 2))
                leftPath.addLine(to: CGPoint(x: arrowLength / 2, y: -arrowWidth / 2))
                leftPath.closeSubpath()
                leftArrow.path = leftPath
                leftArrow.position = CGPoint(x: -tileSize * 0.08, y: 0)
                leftArrow.zRotation = .pi / 4

                let rightArrow = decoration.fillNodes[1]
                let rightPath = CGMutablePath()
                rightPath.move(to: CGPoint(x: arrowLength / 2, y: 0))
                rightPath.addLine(to: CGPoint(x: -arrowLength / 2, y: arrowWidth / 2))
                rightPath.addLine(to: CGPoint(x: -arrowLength / 2, y: -arrowWidth / 2))
                rightPath.closeSubpath()
                rightArrow.path = rightPath
                rightArrow.position = CGPoint(x: tileSize * 0.08, y: 0)
                rightArrow.zRotation = -.pi / 4
            }
        }

        /// 効果装飾の色を現在のパレットに合わせて更新する
        /// - Parameters:
        ///   - decoration: 対象となる装飾キャッシュ
        ///   - effect: カラーリングの元となる効果種別
        private func applyEffectDecorationColors(
            _ decoration: inout TileEffectDecorationCache,
            effect: TileEffect
        ) {
            switch effect {
            case .warp(let pairID, _):
                let style = warpVisualStyle(for: pairID)
                for (index, node) in decoration.strokeNodes.enumerated() {
                    let attenuation = max(0.5, 1.0 - CGFloat(index) * 0.15)
                    node.strokeColor = style.color.withAlphaComponent(attenuation)
                    node.fillColor = .clear
                    node.alpha = 1.0
                }
            case .shuffleHand:
                let strokeColor = palette.boardTileEffectShuffle
                for node in decoration.strokeNodes {
                    node.strokeColor = strokeColor
                    node.fillColor = .clear
                    node.alpha = 1.0
                }
                guard decoration.fillNodes.count >= 2 else { return }
                let primaryFill = strokeColor.withAlphaComponent(0.88)
                let secondaryFill = strokeColor.withAlphaComponent(0.6)
                decoration.fillNodes[0].fillColor = primaryFill
                decoration.fillNodes[0].strokeColor = .clear
                decoration.fillNodes[0].alpha = 1.0
                decoration.fillNodes[1].fillColor = secondaryFill
                decoration.fillNodes[1].strokeColor = .clear
                decoration.fillNodes[1].alpha = 1.0
            }
        }

        /// 盤面ハイライトの種類ごとの集合をまとめて更新する
        /// - Parameter highlights: 種類をキーとした盤面座標集合
        /// - NOTE: 将来ハイライト種別が増えても呼び出し側の構造を保てるよう辞書引数を採用している
        public func updateHighlights(_ highlights: [BoardHighlightKind: Set<GridPoint>]) {
            // キーが存在しない場合は空集合として扱い、不要なノードが残らないようにする
            var sanitized: [BoardHighlightKind: Set<GridPoint>] = [:]
            for kind in BoardHighlightKind.allCases {
                let requestedPoints = highlights[kind] ?? []
                // 盤面内の移動可能マスのみ残し、障害物を視覚的にも除外する
                let validPoints = Set(
                    requestedPoints.filter { point in
                        board.contains(point) && board.isTraversable(point)
                    }
                )
                sanitized[kind] = validPoints
                pendingHighlightPoints[kind] = validPoints
            }

            // 正規化済みの集合を保持し、描画更新前後で最新状態を参照できるようにする
            latestSingleGuidePoints = sanitized[.guideSingleCandidate] ?? []
            latestMultipleGuidePoints = sanitized[.guideMultipleCandidate] ?? []
            latestMultiStepGuidePoints = sanitized[.guideMultiStepCandidate] ?? []
            latestForcedSelectionPoints = sanitized[.forcedSelection] ?? []

            let countsDescription =
                sanitized
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
                .guideMultipleCandidate: points,
                .guideMultiStepCandidate: [],
            ])
        }

        /// 辞書で受け取ったハイライト情報を即座にノードへ反映する
        /// - Parameter highlights: 種類ごとの有効な盤面座標集合
        private func applyHighlightsImmediately(_ highlights: [BoardHighlightKind: Set<GridPoint>])
        {
            // 即時反映時も最新集合を保持し、ノード再構成時に参照できるようにする
            latestSingleGuidePoints = highlights[.guideSingleCandidate] ?? []
            latestMultipleGuidePoints = highlights[.guideMultipleCandidate] ?? []
            latestMultiStepGuidePoints = highlights[.guideMultiStepCandidate] ?? []
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
        private func rebuildHighlightNodes(
            for kind: BoardHighlightKind, using points: Set<GridPoint>
        ) {
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
        private func configureHighlightNode(
            _ node: SKShapeNode, for point: GridPoint, kind: BoardHighlightKind
        ) {
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
                // 連続移動ガイドと重なる場合も、シアン枠と干渉しないよう軽く内側へ寄せる
                if latestMultiStepGuidePoints.contains(point) {
                    overlapInset = max(overlapInset, strokeWidth * 0.9)
                }
                zPosition = 1.02
            case .guideMultiStepCandidate:
                baseColor = palette.boardMultiStepHighlight
                strokeAlpha = 0.9
                strokeWidth = sharedGuideStrokeWidth
                // 単一枠と重なる場合はさらに内側に寄せ、グレーとの重なりを避ける
                if latestSingleGuidePoints.contains(point) {
                    overlapInset = max(overlapInset, strokeWidth * 2.0)
                }
                // 複数枠と重なる場合もインセットを強め、枠線が判別しやすいようにする
                if latestMultipleGuidePoints.contains(point) {
                    overlapInset = max(overlapInset, strokeWidth * 1.4)
                }
                zPosition = 1.04
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
            refreshWarpVisualStyles()

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
            debugLog(
                "GameScene.moveKnight 要求: current=\(String(describing: knightPosition)), target=\(String(describing: point)), tileSize=\(tileSize)"
            )

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

        /// ワープ効果を伴う移動を専用演出で再生する
        /// - Parameter resolution: GameCore 側で確定した移動経路と効果履歴
        /// - Note: レイアウトが未確定の場合など、演出が成立しないケースでは従来の `moveKnight(to:)` を呼び出す
        public func playWarpTransition(using resolution: MovementResolution) {
            guard isLayoutReady, let knightNode else {
                // 駒ノードが存在しない状況では安全のため既存アニメーションへフォールバックする
                moveKnight(to: resolution.finalPosition)
                return
            }

            // 経路中にワープ効果が含まれているか確認し、見つからなければ通常移動を採用する
            guard let warpEvent = resolution.appliedEffects.first(where: { applied in
                if case .warp = applied.effect { return true }
                return false
            }) else {
                moveKnight(to: resolution.finalPosition)
                return
            }

            // 効果の内容からワープ先を取り出す。ここで解析できなければ従来挙動に戻す。
            guard case .warp(_, let destination) = warpEvent.effect else {
                moveKnight(to: resolution.finalPosition)
                return
            }

            // 経路のうち、ワープ発動マスへ到達するまでの点列を抽出する
            var approachPoints: [GridPoint] = []
            for point in resolution.path {
                approachPoints.append(point)
                if point == warpEvent.point { break }
            }
            guard approachPoints.contains(warpEvent.point) else {
                moveKnight(to: resolution.finalPosition)
                return
            }

            knightNode.removeAllActions()
            knightNode.isHidden = false

            // タイミング調整しやすいよう所要時間を定数化する
            let approachDuration: TimeInterval = 0.18
            let warpOutDuration: TimeInterval = 0.14
            let warpInDuration: TimeInterval = 0.14

            var sequence: [SKAction] = []

            if !approachPoints.isEmpty {
                let stepDuration = approachDuration / Double(max(1, approachPoints.count))
                for point in approachPoints {
                    let move = SKAction.move(to: position(for: point), duration: stepDuration)
                    move.timingMode = .easeInEaseOut
                    let updateState = SKAction.run { [weak self] in
                        guard let self else { return }
                        self.knightPosition = point
                        self.updateAccessibilityElements()
                    }
                    sequence.append(SKAction.sequence([move, updateState]))
                }
            }

            // ワープ発動時のリング演出と矢印回転を同時に開始する
            sequence.append(SKAction.run { [weak self] in
                guard let self else { return }
                self.emitWarpRing(at: warpEvent.point, expanding: true)
                self.animateWarpArrow(at: warpEvent.point)
            })

            let warpOut = SKAction.group([
                SKAction.scale(to: 0.2, duration: warpOutDuration),
                SKAction.fadeOut(withDuration: warpOutDuration),
            ])
            warpOut.timingMode = .easeIn
            sequence.append(warpOut)

            // 縮小・消失後にワープ先へ瞬間移動し、再出現演出の初期状態を整える
            sequence.append(SKAction.run { [weak self] in
                guard let self, let knightNode = self.knightNode else { return }
                knightNode.position = self.position(for: destination)
                knightNode.setScale(0.2)
                knightNode.alpha = 0.0
                self.emitWarpRing(at: destination, expanding: false)
            })

            let warpIn = SKAction.group([
                SKAction.fadeIn(withDuration: warpInDuration),
                SKAction.scale(to: 1.0, duration: warpInDuration),
            ])
            warpIn.timingMode = .easeOut
            sequence.append(warpIn)

            // 最終的な位置・アクセシビリティ情報を確定させる
            sequence.append(SKAction.run { [weak self] in
                guard let self, let knightNode = self.knightNode else { return }
                knightNode.alpha = 1.0
                knightNode.setScale(1.0)
                self.knightPosition = destination
                self.updateAccessibilityElements()
            })

            knightNode.run(SKAction.sequence(sequence))
        }

        /// ワープ演出用のリングを生成し、膨張または収縮させる
        /// - Parameters:
        ///   - point: 表示位置にしたい盤面座標
        ///   - expanding: true の場合は膨張（消える側）、false の場合は収縮（現れる側）
        private func emitWarpRing(at point: GridPoint, expanding: Bool) {
            guard isLayoutReady else { return }

            let radius = tileSize * 0.36
            let ring = SKShapeNode(circleOfRadius: radius)
            ring.name = "transientWarpRing"
            ring.lineWidth = max(1.0, tileSize * 0.06)
            let baseColor: SKColor
            if case .warp(let pairID, _) = board.effect(at: point) {
                baseColor = warpVisualStyle(for: pairID).color
            } else {
                baseColor = palette.boardTileEffectWarp
            }
            ring.strokeColor = baseColor
            ring.fillColor = baseColor.withAlphaComponent(0.18)
            ring.isAntialiased = true
            ring.position = position(for: point)
            ring.zPosition = 0
            ring.alpha = expanding ? 0.9 : 0.8
            let startScale: CGFloat = expanding ? 0.4 : 1.4
            let targetScale: CGFloat = expanding ? 1.55 : 0.55
            ring.setScale(startScale)
            transientEffectContainer.addChild(ring)

            let duration: TimeInterval = 0.2
            let scale = SKAction.scale(to: targetScale, duration: duration)
            scale.timingMode = .easeOut
            let fade = SKAction.fadeOut(withDuration: duration)
            fade.timingMode = .easeOut
            ring.run(SKAction.sequence([SKAction.group([scale, fade]), SKAction.removeFromParent()]))
        }

        /// ワープタイルの魔法陣装飾は静止表示とし、不要なアニメーションを抑制する
        /// - Parameter point: 魔法陣が存在する盤面座標
        private func animateWarpArrow(at point: GridPoint) {
            // 仕様変更によりアニメーションは実施しないため、念のため残存アクションのみ停止する
            tileEffectDecorations[point]?.fillNodes.first?.removeAllActions()
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
                    .forcedSelection: latestForcedSelectionPoints,
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
                debugLog(
                    "GameScene.updateBoard: visited=\(visitedCount), remaining=\(board.remainingCount), tileNodes=\(tileNodes.count)"
                )
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
                            if state.isImpassable {
                                // 障害物は踏破対象外であることを明確に伝える
                                statusText = "移動不可"
                            } else if state.isVisited {
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
                            element.accessibilityLabel = "駒あり・" + statusText
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
                set {}
            }
        #else
            // UIKit が利用できない環境では空実装
            private func updateAccessibilityElements() {}
        #endif
    }

    /// タイル色を滑らかに補間するためのユーティリティ
    extension SKColor {
        /// 2 色間を線形補間した結果を返す
        /// - Parameters:
        ///   - other: 補間したい相手色
        ///   - fraction: 0.0〜1.0 の補間係数
        fileprivate func interpolated(to other: SKColor, fraction: CGFloat) -> SKColor {
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
