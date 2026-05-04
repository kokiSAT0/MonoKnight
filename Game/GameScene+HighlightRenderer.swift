#if canImport(SpriteKit)
    import SpriteKit
    import SharedSupport

    final class GameSceneHighlightRenderer {
        private(set) var highlightNodes: [BoardHighlightKind: [GridPoint: SKShapeNode]] = [:]
        private(set) var patrolMovementArrowNodes: [String: SKShapeNode] = [:]
        private var latestSingleGuidePoints: Set<GridPoint> = []
        private var latestMultipleGuidePoints: Set<GridPoint> = []
        private var latestMultiStepPathPoints: Set<GridPoint> = []
        private var latestMultiStepGuidePoints: Set<GridPoint> = []
        private var latestWarpGuidePoints: Set<GridPoint> = []
        private var latestDungeonBasicMovePoints: Set<GridPoint> = []
        private var latestTargetApproachPoints: Set<GridPoint> = []
        private var latestTargetCapturePoints: Set<GridPoint> = []
        private var latestForcedSelectionPoints: Set<GridPoint> = []
        private var latestCurrentTargetPoints: Set<GridPoint> = []
        private var latestUpcomingTargetPoints: Set<GridPoint> = []
        private var latestDungeonExitPoints: Set<GridPoint> = []
        private var latestDungeonExitLockedPoints: Set<GridPoint> = []
        private var latestDungeonKeyPoints: Set<GridPoint> = []
        private var latestDungeonEnemyPoints: Set<GridPoint> = []
        private var latestDungeonDangerPoints: Set<GridPoint> = []
        private var latestDungeonCardPickupPoints: Set<GridPoint> = []
        private var latestDungeonDamageTrapPoints: Set<GridPoint> = []
        private var latestDungeonCrackedFloorPoints: Set<GridPoint> = []
        private var latestDungeonCollapsedFloorPoints: Set<GridPoint> = []
        private var latestPatrolMovementPreviews: [ScenePatrolMovementPreview] = []
        private var pendingPatrolMovementPreviews: [ScenePatrolMovementPreview] = []
        private var hasPendingPatrolMovementPreviewUpdate = false
        private var pendingHighlightPoints: [BoardHighlightKind: Set<GridPoint>] = [:]

        var patrolMovementArrowCount: Int { patrolMovementArrowNodes.count }

        init() {
            reset()
        }

        func reset() {
            for nodes in highlightNodes.values {
                for node in nodes.values {
                    node.removeFromParent()
                }
            }
            for node in patrolMovementArrowNodes.values {
                node.removeFromParent()
            }
            highlightNodes = [:]
            patrolMovementArrowNodes = [:]
            latestSingleGuidePoints = []
            latestMultipleGuidePoints = []
            latestMultiStepPathPoints = []
            latestMultiStepGuidePoints = []
            latestWarpGuidePoints = []
            latestDungeonBasicMovePoints = []
            latestTargetApproachPoints = []
            latestTargetCapturePoints = []
            latestForcedSelectionPoints = []
            latestCurrentTargetPoints = []
            latestUpcomingTargetPoints = []
            latestDungeonExitPoints = []
            latestDungeonExitLockedPoints = []
            latestDungeonKeyPoints = []
            latestDungeonEnemyPoints = []
            latestDungeonDangerPoints = []
            latestDungeonCardPickupPoints = []
            latestDungeonDamageTrapPoints = []
            latestDungeonCrackedFloorPoints = []
            latestDungeonCollapsedFloorPoints = []
            latestPatrolMovementPreviews = []
            pendingPatrolMovementPreviews = []
            hasPendingPatrolMovementPreviewUpdate = false
            pendingHighlightPoints = Dictionary(
                uniqueKeysWithValues: BoardHighlightKind.allCases.map { ($0, []) }
            )
        }

        func updateHighlights(
            _ highlights: [BoardHighlightKind: Set<GridPoint>],
            board: Board,
            scene: SKScene,
            layout: GameSceneLayoutSupport,
            palette: GameScenePalette,
            isLayoutReady: Bool
        ) {
            var sanitized: [BoardHighlightKind: Set<GridPoint>] = [:]
            for kind in BoardHighlightKind.allCases {
                let requestedPoints = highlights[kind] ?? []
                let validPoints = Set(
                    requestedPoints.filter { point in
                        guard board.contains(point) else { return false }
                        if kind == .dungeonCollapsedFloor {
                            return true
                        }
                        return board.isTraversable(point)
                    }
                )
                sanitized[kind] = validPoints
                pendingHighlightPoints[kind] = validPoints
            }

            updateLatestPoints(using: sanitized)

            let countsDescription = sanitized.map { "\($0.key)=\($0.value.count)" }.joined(
                separator: ", ")
            debugLog(
                "GameScene ハイライト更新要求: \(countsDescription), レイアウト確定=\(isLayoutReady)"
            )

            guard isLayoutReady else { return }

            applyHighlightsImmediately(
                sanitized,
                scene: scene,
                layout: layout,
                palette: palette
            )
            clearPending()
        }

        func updatePatrolMovementPreviews(
            _ previews: [ScenePatrolMovementPreview],
            scene: SKScene,
            layout: GameSceneLayoutSupport,
            palette: GameScenePalette,
            isLayoutReady: Bool
        ) {
            latestPatrolMovementPreviews = previews
            pendingPatrolMovementPreviews = previews
            hasPendingPatrolMovementPreviewUpdate = true

            debugLog(
                "GameScene 巡回プレビュー更新要求: count=\(previews.count), レイアウト確定=\(isLayoutReady)"
            )

            guard isLayoutReady else { return }
            applyPatrolMovementPreviews(previews, scene: scene, layout: layout, palette: palette)
            hasPendingPatrolMovementPreviewUpdate = false
        }

        func refreshAppearance(
            layout: GameSceneLayoutSupport,
            palette: GameScenePalette
        ) {
            guard layout.tileSize > 0 else { return }

            for (kind, nodes) in highlightNodes {
                for (point, node) in nodes {
                    configureHighlightNode(
                        node,
                        for: point,
                        kind: kind,
                        layout: layout,
                        palette: palette
                    )
                }
            }

            for preview in latestPatrolMovementPreviews {
                guard let node = patrolMovementArrowNodes[preview.enemyID] else { continue }
                configurePatrolMovementArrowNode(
                    node,
                    preview: preview,
                    layout: layout
                )
            }
        }

        func removeAllNodes() {
            reset()
        }

        func applyPendingIfNeeded(
            scene: SKScene,
            layout: GameSceneLayoutSupport,
            palette: GameScenePalette,
            isLayoutReady: Bool
        ) {
            guard isLayoutReady else { return }

            var snapshot: [BoardHighlightKind: Set<GridPoint>] = [:]
            for kind in BoardHighlightKind.allCases {
                snapshot[kind] = pendingHighlightPoints[kind] ?? []
            }

            let hasPendingValues = snapshot.values.contains { !$0.isEmpty }
            let hasRenderedHighlights = highlightNodes.values.contains { !$0.isEmpty }
            let hasRenderedPatrolPreviews = !patrolMovementArrowNodes.isEmpty
            guard hasPendingValues
                    || hasRenderedHighlights
                    || hasPendingPatrolMovementPreviewUpdate
                    || hasRenderedPatrolPreviews
                    || !latestPatrolMovementPreviews.isEmpty
            else { return }

            if hasPendingValues {
                applyHighlightsImmediately(snapshot, scene: scene, layout: layout, palette: palette)
            } else if hasRenderedHighlights {
                let latestSnapshot: [BoardHighlightKind: Set<GridPoint>] = [
                    .guideSingleCandidate: latestSingleGuidePoints,
                    .guideMultipleCandidate: latestMultipleGuidePoints,
                    .guideMultiStepPath: latestMultiStepPathPoints,
                    .guideMultiStepCandidate: latestMultiStepGuidePoints,
                    .guideWarpCandidate: latestWarpGuidePoints,
                    .dungeonBasicMove: latestDungeonBasicMovePoints,
                    .targetApproachCandidate: latestTargetApproachPoints,
                    .targetCaptureCandidate: latestTargetCapturePoints,
                    .forcedSelection: latestForcedSelectionPoints,
                    .currentTarget: latestCurrentTargetPoints,
                    .upcomingTarget: latestUpcomingTargetPoints,
                    .dungeonExit: latestDungeonExitPoints,
                    .dungeonExitLocked: latestDungeonExitLockedPoints,
                    .dungeonKey: latestDungeonKeyPoints,
                    .dungeonEnemy: latestDungeonEnemyPoints,
                    .dungeonDanger: latestDungeonDangerPoints,
                    .dungeonCardPickup: latestDungeonCardPickupPoints,
                    .dungeonDamageTrap: latestDungeonDamageTrapPoints,
                    .dungeonCrackedFloor: latestDungeonCrackedFloorPoints,
                    .dungeonCollapsedFloor: latestDungeonCollapsedFloorPoints,
                ]
                let hasLatestValues = latestSnapshot.values.contains { !$0.isEmpty }
                if hasLatestValues {
                    applyHighlightsImmediately(
                        latestSnapshot,
                        scene: scene,
                        layout: layout,
                        palette: palette
                    )
                } else {
                    applyHighlightsImmediately(snapshot, scene: scene, layout: layout, palette: palette)
                }
            }

            if hasPendingPatrolMovementPreviewUpdate {
                applyPatrolMovementPreviews(
                    pendingPatrolMovementPreviews,
                    scene: scene,
                    layout: layout,
                    palette: palette
                )
                hasPendingPatrolMovementPreviewUpdate = false
            } else if hasRenderedPatrolPreviews || !latestPatrolMovementPreviews.isEmpty {
                applyPatrolMovementPreviews(
                    latestPatrolMovementPreviews,
                    scene: scene,
                    layout: layout,
                    palette: palette
                )
            }

            clearPending()
        }

        private func clearPending() {
            for kind in BoardHighlightKind.allCases {
                pendingHighlightPoints[kind] = []
            }
        }

        private func updateLatestPoints(using highlights: [BoardHighlightKind: Set<GridPoint>]) {
            latestSingleGuidePoints = highlights[.guideSingleCandidate] ?? []
            latestMultipleGuidePoints = highlights[.guideMultipleCandidate] ?? []
            latestMultiStepPathPoints = highlights[.guideMultiStepPath] ?? []
            latestMultiStepGuidePoints = highlights[.guideMultiStepCandidate] ?? []
            latestWarpGuidePoints = highlights[.guideWarpCandidate] ?? []
            latestDungeonBasicMovePoints = highlights[.dungeonBasicMove] ?? []
            latestTargetApproachPoints = highlights[.targetApproachCandidate] ?? []
            latestTargetCapturePoints = highlights[.targetCaptureCandidate] ?? []
            latestForcedSelectionPoints = highlights[.forcedSelection] ?? []
            latestCurrentTargetPoints = highlights[.currentTarget] ?? []
            latestUpcomingTargetPoints = highlights[.upcomingTarget] ?? []
            latestDungeonExitPoints = highlights[.dungeonExit] ?? []
            latestDungeonExitLockedPoints = highlights[.dungeonExitLocked] ?? []
            latestDungeonKeyPoints = highlights[.dungeonKey] ?? []
            latestDungeonEnemyPoints = highlights[.dungeonEnemy] ?? []
            latestDungeonDangerPoints = highlights[.dungeonDanger] ?? []
            latestDungeonCardPickupPoints = highlights[.dungeonCardPickup] ?? []
            latestDungeonDamageTrapPoints = highlights[.dungeonDamageTrap] ?? []
            latestDungeonCrackedFloorPoints = highlights[.dungeonCrackedFloor] ?? []
            latestDungeonCollapsedFloorPoints = highlights[.dungeonCollapsedFloor] ?? []
        }

        private func applyHighlightsImmediately(
            _ highlights: [BoardHighlightKind: Set<GridPoint>],
            scene: SKScene,
            layout: GameSceneLayoutSupport,
            palette: GameScenePalette
        ) {
            updateLatestPoints(using: highlights)

            for kind in BoardHighlightKind.allCases {
                let points = highlights[kind] ?? []
                rebuildHighlightNodes(
                    for: kind,
                    using: points,
                    scene: scene,
                    layout: layout,
                    palette: palette
                )
            }
        }

        private func rebuildHighlightNodes(
            for kind: BoardHighlightKind,
            using points: Set<GridPoint>,
            scene: SKScene,
            layout: GameSceneLayoutSupport,
            palette: GameScenePalette
        ) {
            var nodesForKind = highlightNodes[kind] ?? [:]

            for (point, node) in nodesForKind where !points.contains(point) {
                node.removeFromParent()
                nodesForKind.removeValue(forKey: point)
            }

            for point in points {
                if let node = nodesForKind[point] {
                    if node.parent !== scene {
                        scene.addChild(node)
                    }
                    configureHighlightNode(
                        node,
                        for: point,
                        kind: kind,
                        layout: layout,
                        palette: palette
                    )
                } else {
                    let node = SKShapeNode()
                    configureHighlightNode(
                        node,
                        for: point,
                        kind: kind,
                        layout: layout,
                        palette: palette
                    )
                    scene.addChild(node)
                    nodesForKind[point] = node
                }
            }

            highlightNodes[kind] = nodesForKind
        }

        private func applyPatrolMovementPreviews(
            _ previews: [ScenePatrolMovementPreview],
            scene: SKScene,
            layout: GameSceneLayoutSupport,
            palette: GameScenePalette
        ) {
            latestPatrolMovementPreviews = previews

            let previewIDs = Set(previews.map(\.enemyID))
            let staleEnemyIDs = patrolMovementArrowNodes.keys.filter { !previewIDs.contains($0) }
            for enemyID in staleEnemyIDs {
                guard let node = patrolMovementArrowNodes[enemyID] else { continue }
                node.removeFromParent()
                patrolMovementArrowNodes.removeValue(forKey: enemyID)
            }

            for preview in previews {
                if let node = patrolMovementArrowNodes[preview.enemyID] {
                    if node.parent !== scene {
                        scene.addChild(node)
                    }
                    configurePatrolMovementArrowNode(
                        node,
                        preview: preview,
                        layout: layout
                    )
                } else {
                    let node = SKShapeNode()
                    configurePatrolMovementArrowNode(
                        node,
                        preview: preview,
                        layout: layout
                    )
                    scene.addChild(node)
                    patrolMovementArrowNodes[preview.enemyID] = node
                }
            }
        }

        private func configurePatrolMovementArrowNode(
            _ node: SKShapeNode,
            preview: ScenePatrolMovementPreview,
            layout: GameSceneLayoutSupport
        ) {
            let baseColor = patrolMovementArrowColor()
            node.path = patrolMovementArrowPath(vector: preview.vector, tileSize: layout.tileSize)
            node.fillColor = SKColor.clear
            node.strokeColor = baseColor
            node.lineWidth = max(layout.tileSize * 0.045, 2.0)
            node.glowWidth = max(layout.tileSize * 0.025, 1.0)
            node.lineJoin = .round
            node.lineCap = .round
            node.position = layout.position(for: preview.current)
            node.zPosition = 1.24
            node.isAntialiased = true
            node.blendMode = .alpha
        }

        private func configureHighlightNode(
            _ node: SKShapeNode,
            for point: GridPoint,
            kind: BoardHighlightKind,
            layout: GameSceneLayoutSupport,
            palette: GameScenePalette
        ) {
            let baseRect = CGRect(
                x: -layout.tileSize / 2,
                y: -layout.tileSize / 2,
                width: layout.tileSize,
                height: layout.tileSize
            )
            let sharedGuideStrokeWidth = max(layout.tileSize * 0.055, 2.0)
            var baseColor = palette.boardGuideHighlight
            var strokeAlpha: CGFloat = 1.0
            var zPosition: CGFloat = 1.0
            var strokeWidth: CGFloat = sharedGuideStrokeWidth
            var fillColor = SKColor.clear
            var overlapInset: CGFloat = 0

            switch kind {
            case .guideSingleCandidate:
                baseColor = palette.boardTileVisited
                strokeAlpha = 0.9
                strokeWidth = sharedGuideStrokeWidth
                zPosition = 0.95
            case .guideMultipleCandidate:
                baseColor = palette.boardGuideHighlight
                strokeAlpha = 0.88
                strokeWidth = sharedGuideStrokeWidth
                if latestSingleGuidePoints.contains(point) {
                    overlapInset = strokeWidth * 1.5
                }
                if latestMultiStepGuidePoints.contains(point) {
                    overlapInset = max(overlapInset, strokeWidth * 0.9)
                }
                if latestWarpGuidePoints.contains(point) {
                    overlapInset = max(overlapInset, strokeWidth * 1.1)
                }
                zPosition = 1.02
            case .guideMultiStepPath:
                baseColor = palette.boardMultiStepHighlight
                strokeAlpha = 0
                strokeWidth = 0
                fillColor = baseColor.withAlphaComponent(0.12)
                zPosition = 1.03
            case .guideMultiStepCandidate:
                baseColor = palette.boardMultiStepHighlight
                strokeAlpha = 0.9
                strokeWidth = sharedGuideStrokeWidth
                if latestSingleGuidePoints.contains(point) {
                    overlapInset = max(overlapInset, strokeWidth * 2.0)
                }
                if latestMultipleGuidePoints.contains(point) {
                    overlapInset = max(overlapInset, strokeWidth * 1.4)
                }
                if latestWarpGuidePoints.contains(point) {
                    overlapInset = max(overlapInset, strokeWidth * 1.1)
                }
                zPosition = 1.04
            case .guideWarpCandidate:
                baseColor = palette.boardWarpHighlight
                strokeAlpha = 0.92
                strokeWidth = sharedGuideStrokeWidth
                if latestSingleGuidePoints.contains(point) {
                    overlapInset = max(overlapInset, strokeWidth * 1.6)
                }
                if latestMultipleGuidePoints.contains(point) {
                    overlapInset = max(overlapInset, strokeWidth * 1.3)
                }
                if latestMultiStepGuidePoints.contains(point) {
                    overlapInset = max(overlapInset, strokeWidth * 1.2)
                }
                zPosition = 1.06
            case .dungeonBasicMove:
                baseColor = SKColor.black
                strokeAlpha = 1.0
                strokeWidth = sharedGuideStrokeWidth
                fillColor = SKColor.clear
                zPosition = 1.01
            case .targetApproachCandidate:
                baseColor = palette.boardGuideHighlight
                strokeAlpha = 0.95
                strokeWidth = max(layout.tileSize * 0.045, 2.0)
                fillColor = baseColor.withAlphaComponent(0.10)
                overlapInset = max(layout.tileSize * 0.16, strokeWidth * 2.2)
                zPosition = 1.08
            case .targetCaptureCandidate:
                baseColor = palette.boardWarpHighlight
                strokeAlpha = 0.98
                strokeWidth = max(layout.tileSize * 0.075, 2.6)
                fillColor = baseColor.withAlphaComponent(0.20)
                overlapInset = max(layout.tileSize * 0.08, strokeWidth * 1.2)
                zPosition = 1.16
            case .forcedSelection:
                baseColor = palette.boardWarpHighlight
                strokeAlpha = 0.82
                strokeWidth = max(layout.tileSize * 0.07, 2.4)
                fillColor = baseColor.withAlphaComponent(0.16)
                zPosition = 1.1
            case .currentTarget:
                baseColor = palette.boardWarpHighlight
                strokeAlpha = 0
                strokeWidth = 0
                fillColor = baseColor.withAlphaComponent(0.94)
                zPosition = 1.2
            case .upcomingTarget:
                baseColor = palette.boardWarpHighlight
                strokeAlpha = 0
                strokeWidth = 0
                fillColor = baseColor.withAlphaComponent(0.94)
                zPosition = 1.12
            case .dungeonExit:
                baseColor = palette.boardWarpHighlight
                strokeAlpha = 0.98
                strokeWidth = max(layout.tileSize * 0.065, 2.4)
                fillColor = baseColor.withAlphaComponent(0.20)
                zPosition = 1.18
            case .dungeonExitLocked:
                baseColor = SKColor(red: 0.45, green: 0.47, blue: 0.50, alpha: 1.0)
                strokeAlpha = 0.98
                strokeWidth = max(layout.tileSize * 0.06, 2.2)
                fillColor = baseColor.withAlphaComponent(0.28)
                zPosition = 1.18
            case .dungeonKey:
                baseColor = SKColor(red: 0.96, green: 0.73, blue: 0.18, alpha: 1.0)
                strokeAlpha = 0
                strokeWidth = 0
                fillColor = baseColor.withAlphaComponent(0.88)
                zPosition = 1.16
            case .dungeonEnemy:
                baseColor = SKColor(red: 0.86, green: 0.18, blue: 0.16, alpha: 1.0)
                strokeAlpha = 0.95
                strokeWidth = max(layout.tileSize * 0.055, 2.2)
                fillColor = baseColor.withAlphaComponent(0.32)
                zPosition = 1.17
            case .dungeonDanger:
                baseColor = SKColor(red: 0.90, green: 0.16, blue: 0.12, alpha: 1.0)
                strokeAlpha = 0
                strokeWidth = 0
                fillColor = baseColor.withAlphaComponent(0.16)
                zPosition = 1.05
            case .dungeonCardPickup:
                baseColor = SKColor(red: 0.10, green: 0.62, blue: 0.52, alpha: 1.0)
                strokeAlpha = 0
                strokeWidth = 0
                fillColor = baseColor.withAlphaComponent(0.78)
                zPosition = 1.14
            case .dungeonDamageTrap:
                baseColor = SKColor(red: 0.82, green: 0.10, blue: 0.08, alpha: 1.0)
                strokeAlpha = 0
                strokeWidth = 0
                fillColor = baseColor.withAlphaComponent(0.70)
                zPosition = 1.13
            case .dungeonCrackedFloor:
                baseColor = SKColor(red: 0.95, green: 0.60, blue: 0.12, alpha: 1.0)
                strokeAlpha = 0
                strokeWidth = 0
                fillColor = baseColor.withAlphaComponent(0.18)
                zPosition = 1.07
            case .dungeonCollapsedFloor:
                baseColor = SKColor(red: 0.20, green: 0.22, blue: 0.24, alpha: 1.0)
                strokeAlpha = 0
                strokeWidth = 0
                fillColor = baseColor.withAlphaComponent(0.58)
                zPosition = 1.09
            }

            let adjustedRect = baseRect.insetBy(
                dx: strokeWidth / 2 + overlapInset,
                dy: strokeWidth / 2 + overlapInset
            )
            node.path = highlightPath(
                for: kind,
                in: adjustedRect,
                tileSize: layout.tileSize
            )
            node.fillColor = fillColor
            node.strokeColor = baseColor.withAlphaComponent(strokeAlpha)
            node.lineWidth = strokeWidth
            node.glowWidth = 0
            node.lineJoin = .miter
            node.miterLimit = 2.5
            node.lineCap = .square
            node.position = layout.position(for: point)
            node.zPosition = zPosition
            node.isAntialiased = kind == .currentTarget
                || kind == .upcomingTarget
                || kind == .dungeonExit
                || kind == .dungeonExitLocked
                || kind == .dungeonKey
                || kind == .dungeonEnemy
                || kind == .dungeonCardPickup
                || kind == .dungeonDamageTrap
            node.blendMode = .alpha
        }

        private func highlightPath(
            for kind: BoardHighlightKind,
            in rect: CGRect,
            tileSize: CGFloat
        ) -> CGPath {
            switch kind {
            case .currentTarget:
                return targetMarkerPath(
                    center: CGPoint(x: rect.midX, y: rect.midY),
                    tileSize: tileSize,
                    scale: 1.0
                )
            case .dungeonExit:
                return staircaseMarkerPath(
                    center: CGPoint(x: rect.midX, y: rect.midY),
                    tileSize: tileSize
                )
            case .dungeonExitLocked:
                return lockedStaircaseMarkerPath(
                    center: CGPoint(x: rect.midX, y: rect.midY),
                    tileSize: tileSize
                )
            case .dungeonKey:
                return dungeonKeyMarkerPath(
                    center: CGPoint(x: rect.midX, y: rect.midY),
                    tileSize: tileSize
                )
            case .upcomingTarget, .dungeonEnemy:
                return targetMarkerPath(
                    center: CGPoint(x: rect.midX, y: rect.midY),
                    tileSize: tileSize,
                    scale: 1.0
                )
            case .guideSingleCandidate,
                 .guideMultipleCandidate,
                 .guideMultiStepPath,
                 .guideMultiStepCandidate,
                 .guideWarpCandidate,
                 .dungeonBasicMove,
                 .targetApproachCandidate,
                 .targetCaptureCandidate,
                 .forcedSelection,
                 .dungeonDanger,
                 .dungeonCollapsedFloor:
                return CGPath(rect: rect, transform: nil)
            case .dungeonCardPickup:
                return cardPickupMarkerPath(center: CGPoint(x: rect.midX, y: rect.midY), tileSize: tileSize)
            case .dungeonDamageTrap:
                return damageTrapMarkerPath(center: CGPoint(x: rect.midX, y: rect.midY), tileSize: tileSize)
            case .dungeonCrackedFloor:
                return crackedFloorFillPath(in: rect)
            }
        }

        private func targetMarkerPath(center: CGPoint, tileSize: CGFloat, scale: CGFloat) -> CGPath {
            let radius = tileSize * 0.26 * scale
            let path = CGMutablePath()
            path.move(to: CGPoint(x: center.x, y: center.y + radius))
            path.addLine(to: CGPoint(x: center.x + radius, y: center.y))
            path.addLine(to: CGPoint(x: center.x, y: center.y - radius))
            path.addLine(to: CGPoint(x: center.x - radius, y: center.y))
            path.closeSubpath()
            return path
        }

        private func staircaseMarkerPath(center: CGPoint, tileSize: CGFloat) -> CGPath {
            let stepWidth = tileSize * 0.15
            let stepHeight = tileSize * 0.12
            let start = CGPoint(
                x: center.x - stepWidth * 1.5,
                y: center.y - stepHeight * 1.5
            )
            let path = CGMutablePath()
            path.move(to: start)
            for index in 0..<3 {
                let x = start.x + CGFloat(index + 1) * stepWidth
                let y = start.y + CGFloat(index) * stepHeight
                path.addLine(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x, y: y + stepHeight))
            }
            path.addLine(to: CGPoint(x: start.x + stepWidth * 3.4, y: start.y + stepHeight * 3))
            return path
        }

        private func lockedStaircaseMarkerPath(center: CGPoint, tileSize: CGFloat) -> CGPath {
            let path = CGMutablePath()
            path.addPath(staircaseMarkerPath(center: center, tileSize: tileSize))

            let bodyWidth = tileSize * 0.27
            let bodyHeight = tileSize * 0.20
            let bodyRect = CGRect(
                x: center.x - bodyWidth / 2,
                y: center.y - tileSize * 0.33,
                width: bodyWidth,
                height: bodyHeight
            )
            path.addRoundedRect(
                in: bodyRect,
                cornerWidth: max(tileSize * 0.025, 1.0),
                cornerHeight: max(tileSize * 0.025, 1.0)
            )

            let shackleRect = CGRect(
                x: center.x - bodyWidth * 0.32,
                y: bodyRect.maxY - bodyHeight * 0.12,
                width: bodyWidth * 0.64,
                height: tileSize * 0.22
            )
            path.addArc(
                center: CGPoint(x: shackleRect.midX, y: shackleRect.minY),
                radius: shackleRect.width / 2,
                startAngle: .pi,
                endAngle: 0,
                clockwise: false
            )
            return path
        }

        private func dungeonKeyMarkerPath(center: CGPoint, tileSize: CGFloat) -> CGPath {
            let path = CGMutablePath()
            let bowRadius = tileSize * 0.12
            let bowCenter = CGPoint(x: center.x - tileSize * 0.13, y: center.y + tileSize * 0.04)
            path.addEllipse(
                in: CGRect(
                    x: bowCenter.x - bowRadius,
                    y: bowCenter.y - bowRadius,
                    width: bowRadius * 2,
                    height: bowRadius * 2
                )
            )

            let shaftHeight = max(tileSize * 0.075, 2.0)
            let shaftRect = CGRect(
                x: bowCenter.x + bowRadius * 0.65,
                y: bowCenter.y - shaftHeight / 2,
                width: tileSize * 0.34,
                height: shaftHeight
            )
            path.addRect(shaftRect)

            let toothWidth = tileSize * 0.075
            let toothHeight = tileSize * 0.14
            path.addRect(
                CGRect(
                    x: shaftRect.maxX - toothWidth,
                    y: shaftRect.minY - toothHeight * 0.75,
                    width: toothWidth,
                    height: toothHeight
                )
            )
            path.addRect(
                CGRect(
                    x: shaftRect.maxX - toothWidth * 2.0,
                    y: shaftRect.minY - toothHeight * 0.45,
                    width: toothWidth,
                    height: toothHeight * 0.7
                )
            )
            return path
        }

        private func cardPickupMarkerPath(center: CGPoint, tileSize: CGFloat) -> CGPath {
            let width = tileSize * 0.28
            let height = tileSize * 0.36
            let rect = CGRect(
                x: center.x - width / 2,
                y: center.y - height / 2,
                width: width,
                height: height
            )
            let radius = max(tileSize * 0.025, 1.0)
            let path = CGMutablePath()
            path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
            return path
        }

        private func damageTrapMarkerPath(center: CGPoint, tileSize: CGFloat) -> CGPath {
            let radius = tileSize * 0.28
            let path = CGMutablePath()
            path.move(to: CGPoint(x: center.x, y: center.y + radius))
            path.addLine(to: CGPoint(x: center.x + radius, y: center.y - radius * 0.55))
            path.addLine(to: CGPoint(x: center.x - radius, y: center.y - radius * 0.55))
            path.closeSubpath()
            return path
        }

        private func crackedFloorFillPath(in rect: CGRect) -> CGPath {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.closeSubpath()
            return path
        }

        private func patrolMovementArrowPath(vector: MoveVector, tileSize: CGFloat) -> CGPath {
            let dx = CGFloat(vector.dx)
            let dy = CGFloat(vector.dy)
            let length = max(sqrt(dx * dx + dy * dy), 1.0)
            let unitX = dx / length
            let unitY = dy / length
            let perpendicularX = -unitY
            let perpendicularY = unitX

            let startDistance = tileSize * 0.03
            let endDistance = tileSize * 0.31
            let headLength = tileSize * 0.11
            let headSpread = tileSize * 0.075

            let start = CGPoint(x: unitX * startDistance, y: unitY * startDistance)
            let tip = CGPoint(x: unitX * endDistance, y: unitY * endDistance)
            let headBase = CGPoint(
                x: tip.x - unitX * headLength,
                y: tip.y - unitY * headLength
            )
            let leftHead = CGPoint(
                x: headBase.x + perpendicularX * headSpread,
                y: headBase.y + perpendicularY * headSpread
            )
            let rightHead = CGPoint(
                x: headBase.x - perpendicularX * headSpread,
                y: headBase.y - perpendicularY * headSpread
            )

            let path = CGMutablePath()
            path.move(to: start)
            path.addLine(to: tip)
            path.move(to: leftHead)
            path.addLine(to: tip)
            path.addLine(to: rightHead)
            return path
        }

        private func patrolMovementArrowColor() -> SKColor {
            return SKColor(red: 1.0, green: 0.82, blue: 0.24, alpha: 0.96)
        }
    }
#endif
