#if canImport(SpriteKit)
    import SpriteKit
    #if canImport(UIKit)
        import UIKit
    #endif
    import SharedSupport

    public enum BoardHighlightKind: CaseIterable, Hashable {
        case guideSingleCandidate
        case guideMultipleCandidate
        case guideMultiStepPath
        case guideMultiStepCandidate
        case guideWarpCandidate
        case dungeonBasicMove
        case targetApproachCandidate
        case targetCaptureCandidate
        case forcedSelection
        case currentTarget
        case upcomingTarget
        case dungeonExit
        case dungeonExitLocked
        case dungeonKey
        case dungeonEnemy
        case dungeonDanger
        case dungeonEnemyWarning
        case dungeonCardPickup
        case dungeonDamageTrap
        case dungeonCrackedFloor
        case dungeonCollapsedFloor
    }

    public struct ScenePatrolMovementPreview: Identifiable, Equatable {
        public let enemyID: String
        public let current: GridPoint
        public let next: GridPoint
        public let vector: MoveVector

        public var id: String { enemyID }

        public init(enemyID: String, current: GridPoint, next: GridPoint, vector: MoveVector) {
            self.enemyID = enemyID
            self.current = current
            self.next = next
            self.vector = vector
        }

        public init(_ preview: EnemyPatrolMovementPreview) {
            self.init(
                enemyID: preview.enemyID,
                current: preview.current,
                next: preview.next,
                vector: preview.vector
            )
        }

        public init(_ preview: EnemyRotatingWatcherDirectionPreview) {
            self.init(
                enemyID: preview.enemyID,
                current: preview.current,
                next: preview.current.offset(dx: preview.vector.dx, dy: preview.vector.dy),
                vector: preview.vector
            )
        }
    }

    public struct ScenePatrolRailPreview: Identifiable, Equatable {
        public let enemyID: String
        public let path: [GridPoint]

        public var id: String { enemyID }

        public init(enemyID: String, path: [GridPoint]) {
            self.enemyID = enemyID
            self.path = path
        }

        public init(_ preview: EnemyPatrolRailPreview) {
            self.init(enemyID: preview.enemyID, path: preview.path)
        }
    }

    public protocol GameCoreProtocol: AnyObject {
        func handleTap(at point: GridPoint)
    }

    public final class GameScene: SKScene {
        public weak var gameCore: GameCoreProtocol?

        private let initialBoardSize: Int
        private let initialVisitedPoints: [GridPoint]
        private let initialRequiredVisitOverrides: [GridPoint: Int]
        private let initialTogglePoints: Set<GridPoint>
        private let initialImpassablePoints: Set<GridPoint>
        private let initialTileEffects: [GridPoint: TileEffect]

        private var board: Board
        private var palette = GameScenePalette.fallback
        private let layoutSupport = GameSceneLayoutSupport()
        private let decorationRenderer = GameSceneDecorationRenderer()
        private let highlightRenderer = GameSceneHighlightRenderer()
        private let knightAnimator = GameSceneKnightAnimator()
        private var pendingBoard: Board?
        private var currentTargetPoints: Set<GridPoint> = []
        private var upcomingTargetPoints: Set<GridPoint> = []
        private var targetApproachCandidatePoints: Set<GridPoint> = []
        private var targetCaptureCandidatePoints: Set<GridPoint> = []
        private var latestHighlightPoints: [BoardHighlightKind: Set<GridPoint>] = [:]
        private var latestPatrolRailPreviews: [ScenePatrolRailPreview] = []
        private var latestPatrolMovementPreviews: [ScenePatrolMovementPreview] = []
        private var showsVisitedTileFill = true

        #if canImport(UIKit)
            private let accessibilitySupport = GameSceneAccessibilitySupport()
        #endif

        private var isLayoutReady: Bool {
            layoutSupport.tileSize > 0
                && decorationRenderer.tileNodes.count == board.size * board.size
                && knightAnimator.knightNode != nil
        }

        private func commonInit() {
            board = Board(
                size: initialBoardSize,
                initialVisitedPoints: initialVisitedPoints,
                requiredVisitOverrides: initialRequiredVisitOverrides,
                togglePoints: initialTogglePoints,
                impassablePoints: initialImpassablePoints,
                tileEffects: initialTileEffects
            )
            palette = GameScenePalette.fallback
            layoutSupport.reset()
            decorationRenderer.reset()
            decorationRenderer.refreshWarpVisualStyles(board: board, palette: palette)
            highlightRenderer.reset()
            knightAnimator.reset(in: self)
            pendingBoard = nil
            currentTargetPoints = []
            upcomingTargetPoints = []
            targetApproachCandidatePoints = []
            targetCaptureCandidatePoints = []
            latestHighlightPoints = [:]
            latestPatrolRailPreviews = []
            latestPatrolMovementPreviews = []
            showsVisitedTileFill = true
            #if canImport(UIKit)
                accessibilitySupport.reset()
            #endif
        }

        public override convenience init() {
            self.init(
                initialBoardSize: BoardGeometry.standardSize,
                initialVisitedPoints: BoardGeometry.defaultInitialVisitedPoints(
                    for: BoardGeometry.standardSize)
            )
        }

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
            commonInit()
        }

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
            commonInit()
        }

        public override func didMove(to view: SKView) {
            super.didMove(to: view)

            debugLog("GameScene.didMove: view.bounds=\(view.bounds.size), scene.size=\(size)")

            calculateLayout(trigger: .didMove)
            applyTheme(palette)
            updateAccessibilityElements()
            flushPendingUpdatesIfNeeded()
        }

        public override func didChangeSize(_ oldSize: CGSize) {
            super.didChangeSize(oldSize)

            debugLog("GameScene.didChangeSize: oldSize=\(oldSize), newSize=\(size)")

            calculateLayout(trigger: .didChangeSize)
            decorationRenderer.relayoutTileNodes(
                board: board,
                palette: palette,
                layout: layoutSupport,
                showsVisitedTileFill: showsVisitedTileFill
            )
            knightAnimator.relayoutKnight(layout: layoutSupport)
            highlightRenderer.refreshAppearance(layout: layoutSupport, palette: palette)
            updateAccessibilityElements()
            prepareLayoutIfNeeded()
        }

        public func updateBoard(_ board: Board) {
            let previousSize = self.board.size
            self.board = board
            decorationRenderer.refreshWarpVisualStyles(board: board, palette: palette)

            if previousSize != board.size {
                pendingBoard = board
                calculateLayout(trigger: .manual)
                rebuildNodesForBoardSizeChange()
                return
            }

            guard isLayoutReady else {
                pendingBoard = board
                debugLog(
                    "GameScene.updateBoard: レイアウト未確定のため盤面更新を保留 tileNodes=\(decorationRenderer.tileNodes.count)"
                )
                return
            }

            pendingBoard = nil
            applyCurrentBoardStateToNodes(shouldLog: true)
        }

        public func updateShowsVisitedTileFill(_ isEnabled: Bool) {
            guard showsVisitedTileFill != isEnabled else { return }
            showsVisitedTileFill = isEnabled
            applyCurrentBoardStateToNodes(shouldLog: false)
        }

        public func updateHighlights(_ highlights: [BoardHighlightKind: Set<GridPoint>]) {
            var visibleHighlights = highlights
            visibleHighlights[.targetCaptureCandidate] = []
            latestHighlightPoints = visibleHighlights
            currentTargetPoints = visibleHighlights[.currentTarget] ?? []
            upcomingTargetPoints = visibleHighlights[.upcomingTarget] ?? []
            targetApproachCandidatePoints = visibleHighlights[.targetApproachCandidate] ?? []
            targetCaptureCandidatePoints = visibleHighlights[.targetCaptureCandidate] ?? []
            highlightRenderer.updateHighlights(
                visibleHighlights,
                board: board,
                scene: self,
                layout: layoutSupport,
                palette: palette,
                isLayoutReady: isLayoutReady
            )
            updateAccessibilityElements()
        }

        public func updatePatrolMovementPreviews(_ previews: [ScenePatrolMovementPreview]) {
            let visiblePreviews = previews.filter { preview in
                board.contains(preview.current)
                    && board.contains(preview.next)
                    && board.isTraversable(preview.current)
                    && board.isTraversable(preview.next)
                    && preview.current != preview.next
            }
            latestPatrolMovementPreviews = visiblePreviews
            highlightRenderer.updatePatrolMovementPreviews(
                visiblePreviews,
                scene: self,
                layout: layoutSupport,
                palette: palette,
                isLayoutReady: isLayoutReady
            )
        }

        public func updatePatrolRailPreviews(_ previews: [ScenePatrolRailPreview]) {
            let visiblePreviews = previews.compactMap { preview -> ScenePatrolRailPreview? in
                let validPath = preview.path.filter { point in
                    board.contains(point) && board.isTraversable(point)
                }
                guard validPath.count > 1 else { return nil }
                return ScenePatrolRailPreview(enemyID: preview.enemyID, path: validPath)
            }
            latestPatrolRailPreviews = visiblePreviews
            highlightRenderer.updatePatrolRailPreviews(
                visiblePreviews,
                scene: self,
                layout: layoutSupport,
                palette: palette,
                isLayoutReady: isLayoutReady
            )
        }

        public func latestPatrolRailPreviewsForTesting() -> [ScenePatrolRailPreview] {
            latestPatrolRailPreviews
        }

        public func latestPatrolMovementPreviewsForTesting() -> [ScenePatrolMovementPreview] {
            latestPatrolMovementPreviews
        }

        func patrolRailCountForTesting() -> Int {
            highlightRenderer.patrolRailCount
        }

        func patrolMovementArrowCountForTesting() -> Int {
            highlightRenderer.patrolMovementArrowCount
        }

        public func latestHighlightPoints(for kind: BoardHighlightKind) -> Set<GridPoint> {
            latestHighlightPoints[kind] ?? []
        }

        func highlightStyleForTesting(
            kind: BoardHighlightKind,
            at point: GridPoint
        ) -> (fillColor: SKColor, strokeColor: SKColor, lineWidth: CGFloat)? {
            guard let node = highlightRenderer.highlightNodes[kind]?[point] else {
                return nil
            }
            return (node.fillColor, node.strokeColor, node.lineWidth)
        }

        func highlightPathBoundsForTesting(
            kind: BoardHighlightKind,
            at point: GridPoint
        ) -> CGRect? {
            highlightRenderer.highlightNodes[kind]?[point]?.path?.boundingBox
        }

        func highlightPathElementCountForTesting(
            kind: BoardHighlightKind,
            at point: GridPoint
        ) -> Int? {
            guard let path = highlightRenderer.highlightNodes[kind]?[point]?.path else {
                return nil
            }
            var count = 0
            path.applyWithBlock { _ in
                count += 1
            }
            return count
        }

        func tileFillColorForTesting(at point: GridPoint) -> SKColor? {
            decorationRenderer.tileNodes[point]?.fillColor
        }

        func boardIsImpassableForTesting(at point: GridPoint) -> Bool {
            board.isImpassable(point)
        }

#if DEBUG
        func impassableMarkerCountForTesting() -> Int {
            decorationRenderer.impassableMarkerCountForTesting()
        }
#endif

        public func updateGuideHighlights(_ points: Set<GridPoint>) {
            updateHighlights([
                .guideSingleCandidate: [],
                .guideMultipleCandidate: points,
                .guideMultiStepPath: [],
                .guideMultiStepCandidate: [],
                .targetApproachCandidate: [],
                .targetCaptureCandidate: [],
            ])
        }

        public func applyTheme(_ palette: GameScenePalette) {
            self.palette = palette
            decorationRenderer.refreshWarpVisualStyles(board: board, palette: palette)
            backgroundColor = palette.boardBackground
            knightAnimator.applyTheme(palette)
            decorationRenderer.updateBoardAppearance(
                board: board,
                palette: palette,
                layout: layoutSupport,
                showsVisitedTileFill: showsVisitedTileFill
            )
            highlightRenderer.refreshAppearance(layout: layoutSupport, palette: palette)
        }

        public func moveKnight(to point: GridPoint?) {
            knightAnimator.moveKnight(
                to: point,
                in: self,
                layout: layoutSupport,
                isLayoutReady: isLayoutReady,
                updateAccessibility: { [weak self] in self?.updateAccessibilityElements() }
            )
        }

        public func playWarpTransition(using resolution: MovementResolution) {
            knightAnimator.playWarpTransition(
                using: resolution,
                in: self,
                layout: layoutSupport,
                isLayoutReady: isLayoutReady,
                warpColor: { [weak self] point in
                    guard let self else { return GameScenePalette.fallback.boardTileEffectWarp }
                    return self.decorationRenderer.warpAccentColor(
                        at: point,
                        board: self.board,
                        palette: self.palette
                    )
                },
                updateAccessibility: { [weak self] in self?.updateAccessibilityElements() }
            )
        }

        public func playDungeonExitUnlockEffect(at point: GridPoint) {
            guard isLayoutReady, board.contains(point) else { return }

            let ring = SKShapeNode(circleOfRadius: layoutSupport.tileSize * 0.28)
            ring.position = layoutSupport.position(for: point)
            ring.strokeColor = palette.boardWarpHighlight
            ring.fillColor = .clear
            ring.lineWidth = max(layoutSupport.tileSize * 0.045, 2.0)
            ring.glowWidth = max(layoutSupport.tileSize * 0.08, 3.0)
            ring.zPosition = 1.35
            ring.alpha = 0.95
            ring.isAntialiased = true
            addChild(ring)

            let expand = SKAction.group([
                SKAction.scale(to: 1.55, duration: 0.32),
                SKAction.fadeOut(withDuration: 0.32)
            ])
            expand.timingMode = .easeOut
            ring.run(.sequence([expand, .removeFromParent()]))
        }

        public func playDungeonFallEffect(at point: GridPoint) {
            knightAnimator.playDungeonFallEffect(
                at: point,
                in: self,
                layout: layoutSupport,
                isLayoutReady: isLayoutReady
            )
        }

        @discardableResult
        public func playDungeonEnemyTurn(_ event: DungeonEnemyTurnEvent) -> TimeInterval {
            guard isLayoutReady else { return 0 }

            let movingTransitions = event.transitions.filter(\.didMove)
            let stationaryTransitions = event.transitions.filter { !$0.didMove && $0.didRotate }
            let stepDuration: TimeInterval = 0.22
            let flashDuration: TimeInterval = 0.22

            for (index, transition) in movingTransitions.enumerated() {
                guard board.contains(transition.before.position),
                      board.contains(transition.after.position)
                else { continue }
                let marker = makeEnemyTurnMarker(at: transition.before.position)
                marker.alpha = 0
                addChild(marker)

                let wait = SKAction.wait(forDuration: stepDuration * Double(index))
                let fadeIn = SKAction.fadeAlpha(to: 0.95, duration: 0.04)
                let move = SKAction.move(
                    to: layoutSupport.position(for: transition.after.position),
                    duration: stepDuration
                )
                move.timingMode = .easeInEaseOut
                let fadeOut = SKAction.fadeOut(withDuration: 0.08)
                marker.run(.sequence([wait, fadeIn, move, fadeOut, .removeFromParent()]))
            }

            for transition in stationaryTransitions {
                pulseEnemyTurnPoint(transition.after.position, duration: flashDuration)
            }

            let dangerDelay = stepDuration * Double(movingTransitions.count)
            let dangerPoints = (latestHighlightPoints[.dungeonDanger] ?? [])
                .union(latestHighlightPoints[.dungeonEnemyWarning] ?? [])
            for point in dangerPoints {
                guard board.contains(point) else { continue }
                let wait = SKAction.wait(forDuration: dangerDelay)
                let pulse = makeDangerPulse(at: point)
                pulse.alpha = 0
                addChild(pulse)
                pulse.run(.sequence([
                    wait,
                    .fadeAlpha(to: 0.5, duration: 0.06),
                    .fadeOut(withDuration: flashDuration),
                    .removeFromParent()
                ]))
            }

            return dangerDelay + flashDuration
        }

        public func playDamageEffect() {
            knightAnimator.playDamageEffect(
                in: self,
                palette: palette,
                layout: layoutSupport,
                isLayoutReady: isLayoutReady
            )
        }

        private func makeEnemyTurnMarker(at point: GridPoint) -> SKShapeNode {
            let marker = SKShapeNode(circleOfRadius: layoutSupport.tileSize * 0.24)
            marker.position = layoutSupport.position(for: point)
            marker.fillColor = palette.boardGuideHighlight.withAlphaComponent(0.82)
            marker.strokeColor = palette.boardGridLine.withAlphaComponent(0.92)
            marker.lineWidth = max(layoutSupport.tileSize * 0.035, 1.5)
            marker.glowWidth = max(layoutSupport.tileSize * 0.04, 2.0)
            marker.zPosition = 1.55
            marker.isAntialiased = true
            return marker
        }

        private func makeDangerPulse(at point: GridPoint) -> SKShapeNode {
            let size = layoutSupport.tileSize * 0.72
            let rect = CGRect(x: -size / 2, y: -size / 2, width: size, height: size)
            let pulse = SKShapeNode(rect: rect, cornerRadius: layoutSupport.tileSize * 0.1)
            pulse.position = layoutSupport.position(for: point)
            pulse.fillColor = SKColor.systemRed.withAlphaComponent(0.36)
            pulse.strokeColor = SKColor.systemRed.withAlphaComponent(0.7)
            pulse.lineWidth = max(layoutSupport.tileSize * 0.03, 1.5)
            pulse.zPosition = 1.32
            pulse.isAntialiased = true
            return pulse
        }

        private func pulseEnemyTurnPoint(_ point: GridPoint, duration: TimeInterval) {
            guard board.contains(point) else { return }
            let marker = makeEnemyTurnMarker(at: point)
            marker.alpha = 0
            addChild(marker)
            marker.run(.sequence([
                .fadeAlpha(to: 0.75, duration: 0.05),
                .fadeOut(withDuration: duration),
                .removeFromParent()
            ]))
        }

#if DEBUG
        func transientEffectNodeCountForTesting() -> Int {
            knightAnimator.transientEffectContainer.children.count
        }
#endif

        private func calculateLayout(trigger: LayoutTrigger) {
            layoutSupport.calculateLayout(
                sceneSize: size,
                boardSize: board.size,
                trigger: trigger
            )
            prepareLayoutIfNeeded()
        }

        private func prepareLayoutIfNeeded() {
            guard layoutSupport.tileSize > 0 else {
                debugLog("GameScene.prepareLayoutIfNeeded: tileSize 未確定のため後続処理を延期")
                return
            }

            debugLog(
                "GameScene.prepareLayoutIfNeeded: tileNodes=\(decorationRenderer.tileNodes.count), knightExists=\(knightAnimator.knightNode != nil)"
            )

            if decorationRenderer.tileNodes.isEmpty {
                debugLog("GameScene.prepareLayoutIfNeeded: グリッド未生成のため setupGrid/setupKnight を実行")
                decorationRenderer.setupGrid(
                    in: self,
                    board: board,
                    palette: palette,
                    layout: layoutSupport,
                    showsVisitedTileFill: showsVisitedTileFill
                )
                knightAnimator.setupKnight(
                    in: self,
                    boardSize: board.size,
                    palette: palette,
                    layout: layoutSupport
                )
            } else if knightAnimator.knightNode == nil {
                debugLog("GameScene.prepareLayoutIfNeeded: 駒ノード欠落を検知したため再生成")
                knightAnimator.setupKnight(
                    in: self,
                    boardSize: board.size,
                    palette: palette,
                    layout: layoutSupport
                )
            }

            if isLayoutReady {
                debugLog("GameScene.prepareLayoutIfNeeded: レイアウト準備完了、保留更新を flush します")
                flushPendingUpdatesIfNeeded()
            } else {
                debugLog(
                    "GameScene.prepareLayoutIfNeeded: レイアウト未完了 tileNodes=\(decorationRenderer.tileNodes.count), knightExists=\(knightAnimator.knightNode != nil)"
                )
            }
        }

        private func rebuildNodesForBoardSizeChange() {
            debugLog("GameScene.rebuildNodesForBoardSizeChange: newSize=\(board.size)")
            decorationRenderer.removeAllNodes()
            highlightRenderer.removeAllNodes()
            knightAnimator.removeKnight()
            prepareLayoutIfNeeded()
        }

        private func flushPendingUpdatesIfNeeded() {
            guard isLayoutReady else {
                debugLog(
                    "GameScene.flushPendingUpdatesIfNeeded: レイアウト未確定のため保留 updates を維持"
                )
                return
            }

            let pendingHighlightCount = highlightRenderer.highlightNodes.reduce(0) { partialResult, entry in
                partialResult + entry.value.count
            }
            debugLog(
                "GameScene.flushPendingUpdatesIfNeeded: pendingBoard=\(pendingBoard != nil), pendingKnight=\(knightAnimator.pendingKnightState != nil), pendingHighlights=\(pendingHighlightCount)"
            )

            if let boardToApply = pendingBoard {
                pendingBoard = nil
                self.board = boardToApply
                applyCurrentBoardStateToNodes(shouldLog: true)
            } else {
                applyCurrentBoardStateToNodes(shouldLog: false)
            }

            knightAnimator.flushPendingState(
                isLayoutReady: isLayoutReady,
                layout: layoutSupport,
                updateAccessibility: { [weak self] in self?.updateAccessibilityElements() }
            )

            highlightRenderer.applyPendingIfNeeded(
                scene: self,
                layout: layoutSupport,
                palette: palette,
                isLayoutReady: isLayoutReady
            )
        }

        private func applyCurrentBoardStateToNodes(shouldLog: Bool) {
            guard isLayoutReady else { return }

            decorationRenderer.updateBoardAppearance(
                board: board,
                palette: palette,
                layout: layoutSupport,
                showsVisitedTileFill: showsVisitedTileFill
            )
            highlightRenderer.refreshAppearance(layout: layoutSupport, palette: palette)
            updateAccessibilityElements()

            if shouldLog {
                let visitedCount = board.size * board.size - board.remainingCount
                debugLog(
                    "GameScene.updateBoard: visited=\(visitedCount), remaining=\(board.remainingCount), tileNodes=\(decorationRenderer.tileNodes.count)"
                )
            }
        }

        #if canImport(UIKit)
            public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
                guard let touch = touches.first else { return }
                let location = touch.location(in: self)
                guard let point = gridPoint(from: location) else { return }
                gameCore?.handleTap(at: point)
            }
        #endif

        private func gridPoint(from location: CGPoint) -> GridPoint? {
            layoutSupport.gridPoint(from: location, board: board)
        }

        #if canImport(UIKit)
            private func updateAccessibilityElements() {
                accessibilitySupport.update(
                    board: board,
                    knightPosition: knightAnimator.knightPosition,
                    currentTargetPoints: currentTargetPoints,
                    upcomingTargetPoints: upcomingTargetPoints,
                    targetApproachCandidatePoints: targetApproachCandidatePoints,
                    targetCaptureCandidatePoints: targetCaptureCandidatePoints,
                    layout: layoutSupport,
                    owner: self
                )
            }

            public override var accessibilityElements: [Any]? {
                get { accessibilitySupport.elements }
                set {}
            }
        #else
            private func updateAccessibilityElements() {}
        #endif
    }

    extension SKColor {
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
