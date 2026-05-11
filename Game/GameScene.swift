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
        case forcedSelection
        case dungeonExit
        case dungeonExitLocked
        case dungeonKey
        case dungeonEnemy
        case dungeonDanger
        case dungeonEnemyWarning
        case dungeonCardPickup
        case dungeonRelicPickup
        case dungeonDamageTrap
        case dungeonHealingTile
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

    public struct SceneDungeonEnemyMarker: Identifiable, Equatable {
        public let enemyID: String
        public let point: GridPoint
        public let kind: EnemyPresentationKind
        public let facingVector: MoveVector?
        public let rotationDirection: RotatingWatcherDirection?

        public var id: String { enemyID }

        public init(
            enemyID: String,
            point: GridPoint,
            kind: EnemyPresentationKind,
            facingVector: MoveVector? = nil,
            rotationDirection: RotatingWatcherDirection? = nil
        ) {
            self.enemyID = enemyID
            self.point = point
            self.kind = kind
            self.facingVector = facingVector
            self.rotationDirection = rotationDirection
        }

        public init(
            _ enemy: EnemyDefinition,
            facingVector: MoveVector? = nil,
            rotationDirection: RotatingWatcherDirection? = nil
        ) {
            self.init(
                enemyID: enemy.id,
                point: enemy.position,
                kind: enemy.behavior.presentationKind,
                facingVector: facingVector,
                rotationDirection: rotationDirection ?? enemy.behavior.rotatingWatcherDirection
            )
        }

        public init(
            _ enemy: EnemyState,
            facingVector: MoveVector? = nil,
            rotationDirection: RotatingWatcherDirection? = nil
        ) {
            self.init(
                enemyID: enemy.id,
                point: enemy.position,
                kind: enemy.behavior.presentationKind,
                facingVector: facingVector,
                rotationDirection: rotationDirection ?? enemy.behavior.rotatingWatcherDirection
            )
        }
    }

    public protocol GameCoreProtocol: AnyObject {
        func handleTap(at point: GridPoint)
    }

    public final class GameScene: SKScene {
        public weak var gameCore: GameCoreProtocol?

        private let initialBoardSize: Int
        private let initialVisitedPoints: [GridPoint]
        private let initialImpassablePoints: Set<GridPoint>
        private let initialTileEffects: [GridPoint: TileEffect]

        private var board: Board
        private var palette = GameScenePalette.fallback
        private let layoutSupport = GameSceneLayoutSupport()
        private let decorationRenderer = GameSceneDecorationRenderer()
        private let highlightRenderer = GameSceneHighlightRenderer()
        private let knightAnimator = GameSceneKnightAnimator()
        private var pendingBoard: Board?
        private var latestHighlightPoints: [BoardHighlightKind: Set<GridPoint>] = [:]
        private var latestDungeonEnemyMarkers: [SceneDungeonEnemyMarker] = []
        private var latestPatrolRailPreviews: [ScenePatrolRailPreview] = []
        private var latestPatrolMovementPreviews: [ScenePatrolMovementPreview] = []
        private var showsVisitedTileFill = true
        public private(set) var latestMovementPathForTesting: [GridPoint] = []
        public private(set) var latestMovementStepDurationForTesting: TimeInterval = 0
        public private(set) var latestMovementHoldDurationForTesting: TimeInterval = 0
        public private(set) var latestMovementDamageHoldDurationForTesting: TimeInterval = 0
        public private(set) var latestMovementTotalDurationForTesting: TimeInterval = 0
        public private(set) var latestEnemyTurnDangerPulsePointsForTesting: Set<GridPoint> = []
        public private(set) var latestEnemyTurnWarningPulsePointsForTesting: Set<GridPoint> = []

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
            latestHighlightPoints = [:]
            latestDungeonEnemyMarkers = []
            latestPatrolRailPreviews = []
            latestPatrolMovementPreviews = []
            showsVisitedTileFill = true
            latestMovementPathForTesting = []
            latestMovementStepDurationForTesting = 0
            latestMovementHoldDurationForTesting = 0
            latestMovementDamageHoldDurationForTesting = 0
            latestMovementTotalDurationForTesting = 0
            latestEnemyTurnDangerPulsePointsForTesting = []
            latestEnemyTurnWarningPulsePointsForTesting = []
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
            impassablePoints: Set<GridPoint> = [],
            tileEffects: [GridPoint: TileEffect] = [:]
        ) {
            let resolvedVisitedPoints =
                initialVisitedPoints
                ?? BoardGeometry.defaultInitialVisitedPoints(for: initialBoardSize)
            self.initialBoardSize = initialBoardSize
            self.initialVisitedPoints = resolvedVisitedPoints
            self.initialImpassablePoints = impassablePoints
            self.initialTileEffects = tileEffects
            self.board = Board(
                size: initialBoardSize,
                initialVisitedPoints: resolvedVisitedPoints,
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
            self.initialImpassablePoints = []
            self.initialTileEffects = [:]
            self.board = Board(
                size: BoardGeometry.standardSize,
                initialVisitedPoints: defaultVisitedPoints,
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
            latestHighlightPoints = highlights
            highlightRenderer.updateHighlights(
                highlights,
                board: board,
                scene: self,
                layout: layoutSupport,
                palette: palette,
                isLayoutReady: isLayoutReady
            )
            updateAccessibilityElements()
        }

        public func updateDungeonEnemyMarkers(_ markers: [SceneDungeonEnemyMarker]) {
            let visibleMarkers = markers.filter { marker in
                board.contains(marker.point) && board.isTraversable(marker.point)
            }
            latestDungeonEnemyMarkers = visibleMarkers
            highlightRenderer.updateDungeonEnemyMarkers(
                visibleMarkers,
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

        public func latestDungeonEnemyMarkersForTesting() -> [SceneDungeonEnemyMarker] {
            latestDungeonEnemyMarkers
        }

        func patrolRailCountForTesting() -> Int {
            highlightRenderer.patrolRailCount
        }

        func patrolMovementArrowCountForTesting() -> Int {
            highlightRenderer.patrolMovementArrowCount
        }

        func patrolRailStyleForTesting(
            enemyID: String
        ) -> (strokeColor: SKColor, lineWidth: CGFloat)? {
            guard let node = highlightRenderer.patrolRailNodes[enemyID] else {
                return nil
            }
            return (node.strokeColor, node.lineWidth)
        }

        func patrolMovementArrowStyleForTesting(
            enemyID: String
        ) -> (strokeColor: SKColor, lineWidth: CGFloat)? {
            guard let node = highlightRenderer.patrolMovementArrowNodes[enemyID] else {
                return nil
            }
            return (node.strokeColor, node.lineWidth)
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

        func boardIsVisitedForTesting(at point: GridPoint) -> Bool {
            board.isVisited(point)
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
            latestMovementPathForTesting = resolution.path
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

        public func playMovementTransition(
            using resolution: MovementResolution,
            onStep: @escaping (MovementResolution.PresentationStep) -> Void = { _ in },
            onCompletion: @escaping () -> Void = {}
        ) {
            latestMovementPathForTesting = resolution.path
            latestMovementStepDurationForTesting = GameSceneKnightAnimator.movementReplayStepDuration
            latestMovementHoldDurationForTesting = GameSceneKnightAnimator.movementReplayHoldDuration
            latestMovementDamageHoldDurationForTesting = GameSceneKnightAnimator.movementReplayDamageHoldDuration
            latestMovementTotalDurationForTesting = movementReplayTotalDuration(for: resolution)
            knightAnimator.playMovementTransition(
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
                updateAccessibility: { [weak self] in self?.updateAccessibilityElements() },
                onStep: onStep,
                onCompletion: onCompletion
            )
        }

        private func movementReplayTotalDuration(for resolution: MovementResolution) -> TimeInterval {
            if let warpEvent = resolution.appliedEffects.first(where: { applied in
                if case .warp = applied.effect { return true }
                return false
            }),
               case .warp(_, let destination) = warpEvent.effect,
               let sourceIndex = resolution.path.firstIndex(of: warpEvent.point) {
                let approachDuration =
                    Double(sourceIndex + 1) * GameSceneKnightAnimator.movementReplayStepDuration
                    + (0...sourceIndex).reduce(TimeInterval(0)) { total, index in
                        let step = resolution.presentationSteps.indices.contains(index)
                            ? resolution.presentationSteps[index]
                            : nil
                        return total + GameSceneKnightAnimator.holdDuration(
                            after: step,
                            isLastStep: false
                        )
                    }
                let destinationIndex = resolution.path[(sourceIndex + 1)...]
                    .firstIndex(of: destination)
                let destinationStep = destinationIndex.flatMap { index in
                    resolution.presentationSteps.indices.contains(index)
                        ? resolution.presentationSteps[index]
                        : nil
                }
                return approachDuration
                    + GameSceneKnightAnimator.movementReplayWarpOutDuration
                    + GameSceneKnightAnimator.movementReplayWarpInDuration
                    + GameSceneKnightAnimator.holdDuration(after: destinationStep, isLastStep: true)
            }

            return Double(resolution.path.count) * GameSceneKnightAnimator.movementReplayStepDuration
                + resolution.path.enumerated().reduce(TimeInterval(0)) { total, item in
                    let step = resolution.presentationSteps.indices.contains(item.offset)
                        ? resolution.presentationSteps[item.offset]
                        : nil
                    return total + GameSceneKnightAnimator.holdDuration(
                        after: step,
                        isLastStep: item.offset == resolution.path.count - 1
                    )
                }
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
        public func playDungeonEnemyTurn(
            _ event: DungeonEnemyTurnEvent,
            dangerPoints: Set<GridPoint>,
            warningPoints: Set<GridPoint>
        ) -> TimeInterval {
            latestEnemyTurnDangerPulsePointsForTesting = []
            latestEnemyTurnWarningPulsePointsForTesting = Set(warningPoints.filter(board.contains))
            guard isLayoutReady else { return 0 }

            let stepDuration: TimeInterval = 0.22
            let flashDuration: TimeInterval = 0.22
            var phaseOffset: TimeInterval = 0

            if event.isParalysisRest, let point = event.paralysisTrapPoint {
                pulseParalysisTrap(at: point, delay: 0)
                phaseOffset += 0.16
            }

            for phase in event.phases {
                let movingTransitions = phase.transitions.filter(\.didMove)
                let stationaryTransitions = phase.transitions.filter { !$0.didMove && $0.didRotate }

                for (index, transition) in movingTransitions.enumerated() {
                    animateDungeonEnemyHighlight(
                        enemyID: transition.enemyID,
                        from: transition.before.position,
                        to: transition.after.position,
                        after: phaseOffset + stepDuration * Double(index),
                        duration: stepDuration
                    )
                }

                for transition in stationaryTransitions {
                    pulseEnemyTurnDangerPoint(transition.after.position, delay: phaseOffset, duration: flashDuration)
                }

                phaseOffset += stepDuration * Double(movingTransitions.count)
                if phase.attackedPlayer && phase.hpAfter < phase.hpBefore {
                    playParalysisRestEffectIfNeeded(for: event, at: phaseOffset)
                }
                phaseOffset += flashDuration
            }

            let dangerDelay = max(phaseOffset - flashDuration, 0)
            for point in warningPoints {
                pulseEnemyTurnWarningPoint(point, delay: dangerDelay, duration: flashDuration)
            }

            return phaseOffset + (warningPoints.isEmpty ? 0 : flashDuration)
        }

        private func playParalysisRestEffectIfNeeded(for event: DungeonEnemyTurnEvent, at delay: TimeInterval) {
            guard event.isParalysisRest, let point = event.paralysisTrapPoint else { return }
            pulseParalysisTrap(at: point, delay: delay)
        }

        public func playDamageEffect() {
            knightAnimator.playDamageEffect(
                in: self,
                palette: palette,
                layout: layoutSupport,
                isLayoutReady: isLayoutReady
            )
        }

        private func animateDungeonEnemyHighlight(
            enemyID: String,
            from before: GridPoint,
            to after: GridPoint,
            after delay: TimeInterval,
            duration: TimeInterval
        ) {
            guard board.contains(before),
                  board.contains(after),
                  let node = highlightRenderer.dungeonEnemyMarkerNodes[enemyID]
            else { return }

            let wait = SKAction.wait(forDuration: delay)
            let move = SKAction.move(to: layoutSupport.position(for: after), duration: duration)
            move.timingMode = .easeInEaseOut
            node.run(.sequence([wait, move]))
        }

        private func makeEnemyTurnDangerPulse(at point: GridPoint) -> SKShapeNode {
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

        private func makeEnemyTurnWarningPulse(at point: GridPoint) -> SKShapeNode {
            let size = layoutSupport.tileSize * 0.72
            let rect = CGRect(x: -size / 2, y: -size / 2, width: size, height: size)
            let pulse = SKShapeNode(rect: rect, cornerRadius: layoutSupport.tileSize * 0.1)
            pulse.position = layoutSupport.position(for: point)
            pulse.fillColor = palette.boardTileEffectPreserveCard.withAlphaComponent(0.20)
            pulse.strokeColor = .clear
            pulse.lineWidth = 0
            pulse.zPosition = 1.32
            pulse.isAntialiased = true
            let stroke = SKShapeNode(path: enemyTurnWarningPulseDashPath(size: size))
            stroke.strokeColor = palette.boardTileEffectPreserveCard.withAlphaComponent(0.82)
            stroke.fillColor = .clear
            stroke.lineWidth = max(layoutSupport.tileSize * 0.03, 1.5)
            stroke.lineCap = .round
            stroke.lineJoin = .round
            stroke.isAntialiased = true
            pulse.addChild(stroke)
            return pulse
        }

        private func enemyTurnWarningPulseDashPath(size: CGFloat) -> CGPath {
            let half = size / 2
            let dashLength = max(size * 0.18, 5)
            let gapLength = max(size * 0.12, 3)
            let path = CGMutablePath()

            func addDashedLine(from start: CGPoint, to end: CGPoint) {
                let vector = CGPoint(x: end.x - start.x, y: end.y - start.y)
                let length = hypot(vector.x, vector.y)
                guard length > 0 else { return }
                let unit = CGPoint(x: vector.x / length, y: vector.y / length)
                var offset: CGFloat = 0

                while offset < length {
                    let segmentEnd = min(offset + dashLength, length)
                    path.move(to: CGPoint(
                        x: start.x + unit.x * offset,
                        y: start.y + unit.y * offset
                    ))
                    path.addLine(to: CGPoint(
                        x: start.x + unit.x * segmentEnd,
                        y: start.y + unit.y * segmentEnd
                    ))
                    offset += dashLength + gapLength
                }
            }

            addDashedLine(from: CGPoint(x: -half, y: -half), to: CGPoint(x: half, y: -half))
            addDashedLine(from: CGPoint(x: half, y: -half), to: CGPoint(x: half, y: half))
            addDashedLine(from: CGPoint(x: half, y: half), to: CGPoint(x: -half, y: half))
            addDashedLine(from: CGPoint(x: -half, y: half), to: CGPoint(x: -half, y: -half))
            return path
        }

        private func pulseEnemyTurnDangerPoint(
            _ point: GridPoint,
            delay: TimeInterval,
            duration: TimeInterval
        ) {
            guard board.contains(point) else { return }
            latestEnemyTurnDangerPulsePointsForTesting.insert(point)
            let pulse = makeEnemyTurnDangerPulse(at: point)
            runEnemyTurnPulse(pulse, delay: delay, duration: duration)
        }

        private func pulseEnemyTurnWarningPoint(
            _ point: GridPoint,
            delay: TimeInterval,
            duration: TimeInterval
        ) {
            guard board.contains(point) else { return }
            latestEnemyTurnWarningPulsePointsForTesting.insert(point)
            let pulse = makeEnemyTurnWarningPulse(at: point)
            runEnemyTurnPulse(pulse, delay: delay, duration: duration)
        }

        private func pulseParalysisTrap(at point: GridPoint, delay: TimeInterval) {
            guard board.contains(point) else { return }
            let size = layoutSupport.tileSize * 0.86
            let pulse = SKShapeNode(rectOf: CGSize(width: size, height: size), cornerRadius: layoutSupport.tileSize * 0.12)
            pulse.position = layoutSupport.position(for: point)
            pulse.fillColor = palette.boardTileEffectSlow.withAlphaComponent(0.22)
            pulse.strokeColor = palette.boardTileEffectSlow.withAlphaComponent(0.9)
            pulse.lineWidth = max(layoutSupport.tileSize * 0.035, 1.5)
            pulse.zPosition = 1.34
            pulse.isAntialiased = true

            let bolt = SKShapeNode(path: paralysisBoltPath(tileSize: layoutSupport.tileSize, scale: 0.9))
            bolt.fillColor = palette.boardTileEffectSlow.withAlphaComponent(0.92)
            bolt.strokeColor = .clear
            bolt.zPosition = 0.1
            bolt.isAntialiased = true
            pulse.addChild(bolt)

            runEnemyTurnPulse(pulse, delay: delay, duration: 0.28)
        }

        private func runEnemyTurnPulse(
            _ pulse: SKShapeNode,
            delay: TimeInterval,
            duration: TimeInterval
        ) {
            pulse.alpha = 0
            addChild(pulse)
            pulse.run(.sequence([
                .wait(forDuration: delay),
                .fadeAlpha(to: 0.75, duration: 0.05),
                .fadeOut(withDuration: duration),
                .removeFromParent()
            ]))
        }

        private func paralysisBoltPath(tileSize: CGFloat, scale: CGFloat) -> CGPath {
            let width = tileSize * 0.38 * scale
            let height = tileSize * 0.56 * scale
            let path = CGMutablePath()
            path.move(to: CGPoint(x: width * 0.10, y: height / 2))
            path.addLine(to: CGPoint(x: -width * 0.38, y: height * 0.02))
            path.addLine(to: CGPoint(x: -width * 0.08, y: height * 0.02))
            path.addLine(to: CGPoint(x: -width * 0.30, y: -height / 2))
            path.addLine(to: CGPoint(x: width * 0.42, y: -height * 0.05))
            path.addLine(to: CGPoint(x: width * 0.12, y: -height * 0.05))
            path.closeSubpath()
            return path
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
