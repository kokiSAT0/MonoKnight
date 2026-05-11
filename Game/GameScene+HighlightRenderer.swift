#if canImport(SpriteKit)
    import SpriteKit
    import SharedSupport

    final class GameSceneHighlightRenderer {
        private(set) var highlightNodes: [BoardHighlightKind: [GridPoint: SKShapeNode]] = [:]
        private(set) var dungeonEnemyMarkerNodes: [String: SKShapeNode] = [:]
        private(set) var patrolRailNodes: [String: SKShapeNode] = [:]
        private(set) var patrolMovementArrowNodes: [String: SKShapeNode] = [:]
        private var latestSingleGuidePoints: Set<GridPoint> = []
        private var latestMultipleGuidePoints: Set<GridPoint> = []
        private var latestMultiStepPathPoints: Set<GridPoint> = []
        private var latestMultiStepGuidePoints: Set<GridPoint> = []
        private var latestWarpGuidePoints: Set<GridPoint> = []
        private var latestDungeonBasicMovePoints: Set<GridPoint> = []
        private var latestForcedSelectionPoints: Set<GridPoint> = []
        private var latestDungeonExitPoints: Set<GridPoint> = []
        private var latestDungeonExitLockedPoints: Set<GridPoint> = []
        private var latestDungeonKeyPoints: Set<GridPoint> = []
        private var latestDungeonEnemyPoints: Set<GridPoint> = []
        private var latestDungeonDangerPoints: Set<GridPoint> = []
        private var latestDungeonEnemyWarningPoints: Set<GridPoint> = []
        private var latestDungeonCardPickupPoints: Set<GridPoint> = []
        private var latestDungeonRelicPickupPoints: Set<GridPoint> = []
        private var latestDungeonSuspiciousRelicPickupPoints: Set<GridPoint> = []
        private var latestDungeonDamageTrapPoints: Set<GridPoint> = []
        private var latestDungeonHealingTilePoints: Set<GridPoint> = []
        private var latestDungeonCrackedFloorPoints: Set<GridPoint> = []
        private var latestDungeonCollapsedFloorPoints: Set<GridPoint> = []
        private var latestDungeonEnemyMarkers: [SceneDungeonEnemyMarker] = []
        private var pendingDungeonEnemyMarkers: [SceneDungeonEnemyMarker] = []
        private var hasPendingDungeonEnemyMarkerUpdate = false
        private var latestPatrolRailPreviews: [ScenePatrolRailPreview] = []
        private var pendingPatrolRailPreviews: [ScenePatrolRailPreview] = []
        private var hasPendingPatrolRailUpdate = false
        private var latestPatrolMovementPreviews: [ScenePatrolMovementPreview] = []
        private var pendingPatrolMovementPreviews: [ScenePatrolMovementPreview] = []
        private var hasPendingPatrolMovementPreviewUpdate = false
        private var pendingHighlightPoints: [BoardHighlightKind: Set<GridPoint>] = [:]

        var patrolRailCount: Int { patrolRailNodes.count }
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
            for node in dungeonEnemyMarkerNodes.values {
                node.removeFromParent()
            }
            for node in patrolMovementArrowNodes.values {
                node.removeFromParent()
            }
            for node in patrolRailNodes.values {
                node.removeFromParent()
            }
            highlightNodes = [:]
            dungeonEnemyMarkerNodes = [:]
            patrolRailNodes = [:]
            patrolMovementArrowNodes = [:]
            latestSingleGuidePoints = []
            latestMultipleGuidePoints = []
            latestMultiStepPathPoints = []
            latestMultiStepGuidePoints = []
            latestWarpGuidePoints = []
            latestDungeonBasicMovePoints = []
            latestForcedSelectionPoints = []
            latestDungeonExitPoints = []
            latestDungeonExitLockedPoints = []
            latestDungeonKeyPoints = []
            latestDungeonEnemyPoints = []
            latestDungeonDangerPoints = []
            latestDungeonEnemyWarningPoints = []
            latestDungeonCardPickupPoints = []
            latestDungeonRelicPickupPoints = []
            latestDungeonSuspiciousRelicPickupPoints = []
            latestDungeonDamageTrapPoints = []
            latestDungeonHealingTilePoints = []
            latestDungeonCrackedFloorPoints = []
            latestDungeonCollapsedFloorPoints = []
            latestDungeonEnemyMarkers = []
            pendingDungeonEnemyMarkers = []
            hasPendingDungeonEnemyMarkerUpdate = false
            latestPatrolRailPreviews = []
            pendingPatrolRailPreviews = []
            hasPendingPatrolRailUpdate = false
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

        func updateDungeonEnemyMarkers(
            _ markers: [SceneDungeonEnemyMarker],
            scene: SKScene,
            layout: GameSceneLayoutSupport,
            palette: GameScenePalette,
            isLayoutReady: Bool
        ) {
            latestDungeonEnemyMarkers = markers
            pendingDungeonEnemyMarkers = markers
            hasPendingDungeonEnemyMarkerUpdate = true

            debugLog(
                "GameScene 敵マーカー更新要求: count=\(markers.count), レイアウト確定=\(isLayoutReady)"
            )

            guard isLayoutReady else { return }
            applyDungeonEnemyMarkers(markers, scene: scene, layout: layout, palette: palette)
            hasPendingDungeonEnemyMarkerUpdate = false
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

        func updatePatrolRailPreviews(
            _ previews: [ScenePatrolRailPreview],
            scene: SKScene,
            layout: GameSceneLayoutSupport,
            palette: GameScenePalette,
            isLayoutReady: Bool
        ) {
            latestPatrolRailPreviews = previews
            pendingPatrolRailPreviews = previews
            hasPendingPatrolRailUpdate = true

            debugLog(
                "GameScene 巡回レール更新要求: count=\(previews.count), レイアウト確定=\(isLayoutReady)"
            )

            guard isLayoutReady else { return }
            applyPatrolRailPreviews(previews, scene: scene, layout: layout, palette: palette)
            hasPendingPatrolRailUpdate = false
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

            for marker in latestDungeonEnemyMarkers {
                guard let node = dungeonEnemyMarkerNodes[marker.enemyID] else { continue }
                configureDungeonEnemyMarkerNode(
                    node,
                    marker: marker,
                    layout: layout,
                    palette: palette
                )
            }

            for preview in latestPatrolRailPreviews {
                guard let node = patrolRailNodes[preview.enemyID] else { continue }
                configurePatrolRailNode(
                    node,
                    preview: preview,
                    layout: layout
                )
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
            let hasRenderedEnemyMarkers = !dungeonEnemyMarkerNodes.isEmpty
            let hasRenderedPatrolRails = !patrolRailNodes.isEmpty
            let hasRenderedPatrolPreviews = !patrolMovementArrowNodes.isEmpty
            guard hasPendingValues
                    || hasRenderedHighlights
                    || hasPendingDungeonEnemyMarkerUpdate
                    || hasRenderedEnemyMarkers
                    || !latestDungeonEnemyMarkers.isEmpty
                    || hasPendingPatrolRailUpdate
                    || hasRenderedPatrolRails
                    || !latestPatrolRailPreviews.isEmpty
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
                    .forcedSelection: latestForcedSelectionPoints,
                    .dungeonExit: latestDungeonExitPoints,
                    .dungeonExitLocked: latestDungeonExitLockedPoints,
                    .dungeonKey: latestDungeonKeyPoints,
                    .dungeonEnemy: latestDungeonEnemyPoints,
                    .dungeonDanger: latestDungeonDangerPoints,
                    .dungeonEnemyWarning: latestDungeonEnemyWarningPoints,
                    .dungeonCardPickup: latestDungeonCardPickupPoints,
                    .dungeonRelicPickup: latestDungeonRelicPickupPoints,
                    .dungeonSuspiciousRelicPickup: latestDungeonSuspiciousRelicPickupPoints,
                    .dungeonDamageTrap: latestDungeonDamageTrapPoints,
                    .dungeonHealingTile: latestDungeonHealingTilePoints,
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

            if hasPendingDungeonEnemyMarkerUpdate {
                applyDungeonEnemyMarkers(
                    pendingDungeonEnemyMarkers,
                    scene: scene,
                    layout: layout,
                    palette: palette
                )
                hasPendingDungeonEnemyMarkerUpdate = false
            } else if hasRenderedEnemyMarkers || !latestDungeonEnemyMarkers.isEmpty {
                applyDungeonEnemyMarkers(
                    latestDungeonEnemyMarkers,
                    scene: scene,
                    layout: layout,
                    palette: palette
                )
            }

            if hasPendingPatrolRailUpdate {
                applyPatrolRailPreviews(
                    pendingPatrolRailPreviews,
                    scene: scene,
                    layout: layout,
                    palette: palette
                )
                hasPendingPatrolRailUpdate = false
            } else if hasRenderedPatrolRails || !latestPatrolRailPreviews.isEmpty {
                applyPatrolRailPreviews(
                    latestPatrolRailPreviews,
                    scene: scene,
                    layout: layout,
                    palette: palette
                )
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
            latestForcedSelectionPoints = highlights[.forcedSelection] ?? []
            latestDungeonExitPoints = highlights[.dungeonExit] ?? []
            latestDungeonExitLockedPoints = highlights[.dungeonExitLocked] ?? []
            latestDungeonKeyPoints = highlights[.dungeonKey] ?? []
            latestDungeonEnemyPoints = highlights[.dungeonEnemy] ?? []
            latestDungeonDangerPoints = highlights[.dungeonDanger] ?? []
            latestDungeonEnemyWarningPoints = highlights[.dungeonEnemyWarning] ?? []
            latestDungeonCardPickupPoints = highlights[.dungeonCardPickup] ?? []
            latestDungeonRelicPickupPoints = highlights[.dungeonRelicPickup] ?? []
            latestDungeonSuspiciousRelicPickupPoints = highlights[.dungeonSuspiciousRelicPickup] ?? []
            latestDungeonDamageTrapPoints = highlights[.dungeonDamageTrap] ?? []
            latestDungeonHealingTilePoints = highlights[.dungeonHealingTile] ?? []
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
            if kind == .dungeonEnemy {
                if let existingNodes = highlightNodes[kind]?.values {
                    for node in existingNodes {
                        node.removeFromParent()
                    }
                }
                highlightNodes[kind] = [:]
                return
            }

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

        private func applyDungeonEnemyMarkers(
            _ markers: [SceneDungeonEnemyMarker],
            scene: SKScene,
            layout: GameSceneLayoutSupport,
            palette: GameScenePalette
        ) {
            latestDungeonEnemyMarkers = markers

            let markerIDs = Set(markers.map(\.enemyID))
            let staleEnemyIDs = dungeonEnemyMarkerNodes.keys.filter { !markerIDs.contains($0) }
            for enemyID in staleEnemyIDs {
                guard let node = dungeonEnemyMarkerNodes[enemyID] else { continue }
                node.removeFromParent()
                dungeonEnemyMarkerNodes.removeValue(forKey: enemyID)
            }

            for marker in markers {
                if let node = dungeonEnemyMarkerNodes[marker.enemyID] {
                    if node.parent !== scene {
                        scene.addChild(node)
                    }
                    configureDungeonEnemyMarkerNode(
                        node,
                        marker: marker,
                        layout: layout,
                        palette: palette
                    )
                } else {
                    let node = SKShapeNode()
                    configureDungeonEnemyMarkerNode(
                        node,
                        marker: marker,
                        layout: layout,
                        palette: palette
                    )
                    scene.addChild(node)
                    dungeonEnemyMarkerNodes[marker.enemyID] = node
                }
            }
        }

        private func configureDungeonEnemyMarkerNode(
            _ node: SKShapeNode,
            marker: SceneDungeonEnemyMarker,
            layout: GameSceneLayoutSupport,
            palette: GameScenePalette
        ) {
            let style = dungeonEnemyMarkerStyle(for: marker.kind)
            node.path = dungeonEnemyMarkerPath(marker: marker, tileSize: layout.tileSize)
            node.fillColor = style.fill
            node.strokeColor = style.stroke
            node.lineWidth = dungeonEnemyMarkerLineWidth(for: marker.kind, tileSize: layout.tileSize)
            node.glowWidth = max(layout.tileSize * 0.012, 0.5)
            node.lineJoin = .round
            node.lineCap = .round
            node.position = layout.position(for: marker.point)
            node.zPosition = 1.19
            node.isAntialiased = true
            node.blendMode = .alpha
        }

        private func dungeonEnemyMarkerStyle(for kind: EnemyPresentationKind) -> (fill: SKColor, stroke: SKColor) {
            switch kind {
            case .guardPost:
                return (
                    SKColor(red: 0.82, green: 0.16, blue: 0.16, alpha: 0.36),
                    SKColor(red: 0.92, green: 0.20, blue: 0.18, alpha: 0.96)
                )
            case .patrol:
                return (
                    SKColor(red: 0.95, green: 0.45, blue: 0.12, alpha: 0.34),
                    SKColor(red: 1.00, green: 0.56, blue: 0.18, alpha: 0.96)
                )
            case .watcher:
                return (
                    SKColor(red: 0.72, green: 0.20, blue: 0.58, alpha: 0.34),
                    SKColor(red: 0.90, green: 0.28, blue: 0.74, alpha: 0.96)
                )
            case .rotatingWatcher:
                return (
                    SKColor(red: 0.42, green: 0.32, blue: 0.84, alpha: 0.0),
                    SKColor(red: 0.62, green: 0.50, blue: 1.00, alpha: 0.96)
                )
            case .chaser:
                return (
                    SKColor(red: 0.10, green: 0.53, blue: 0.52, alpha: 0.34),
                    SKColor(red: 0.13, green: 0.74, blue: 0.70, alpha: 0.96)
                )
            case .marker:
                return (
                    SKColor(red: 0.96, green: 0.30, blue: 0.12, alpha: 0.34),
                    SKColor(red: 1.00, green: 0.46, blue: 0.16, alpha: 0.96)
                )
            }
        }

        private func dungeonEnemyMarkerPath(marker: SceneDungeonEnemyMarker, tileSize: CGFloat) -> CGPath {
            let path = CGMutablePath()
            let radius = dungeonEnemyMarkerRadius(for: marker.kind, tileSize: tileSize)
            switch marker.kind {
            case .guardPost:
                path.move(to: CGPoint(x: 0, y: radius))
                path.addLine(to: CGPoint(x: radius * 0.78, y: radius * 0.55))
                path.addLine(to: CGPoint(x: radius * 0.62, y: -radius * 0.48))
                path.addLine(to: CGPoint(x: 0, y: -radius))
                path.addLine(to: CGPoint(x: -radius * 0.62, y: -radius * 0.48))
                path.addLine(to: CGPoint(x: -radius * 0.78, y: radius * 0.55))
                path.closeSubpath()
            case .patrol:
                path.move(to: CGPoint(x: 0, y: radius))
                path.addLine(to: CGPoint(x: radius, y: 0))
                path.addLine(to: CGPoint(x: 0, y: -radius))
                path.addLine(to: CGPoint(x: -radius, y: 0))
                path.closeSubpath()
                addPatrolFacingGlyph(to: path, radius: radius, vector: marker.facingVector ?? MoveVector(dx: 1, dy: 0))
            case .watcher:
                path.move(to: CGPoint(x: -radius, y: 0))
                path.addQuadCurve(to: CGPoint(x: radius, y: 0), control: CGPoint(x: 0, y: radius * 0.78))
                path.addQuadCurve(to: CGPoint(x: -radius, y: 0), control: CGPoint(x: 0, y: -radius * 0.78))
                path.closeSubpath()
                path.addEllipse(in: CGRect(
                    x: -radius * 0.26,
                    y: -radius * 0.26,
                    width: radius * 0.52,
                    height: radius * 0.52
                ))
            case .rotatingWatcher:
                path.move(to: CGPoint(x: -radius, y: 0))
                path.addQuadCurve(to: CGPoint(x: radius, y: 0), control: CGPoint(x: 0, y: radius * 0.78))
                path.addQuadCurve(to: CGPoint(x: -radius, y: 0), control: CGPoint(x: 0, y: -radius * 0.78))
                path.closeSubpath()
                addRotatingWatcherPupilArrow(
                    to: path,
                    radius: radius,
                    direction: marker.rotationDirection ?? .clockwise
                )
            case .chaser:
                addChaserFootprintGlyph(to: path, radius: radius)
            case .marker:
                path.move(to: CGPoint(x: -radius * 0.88, y: radius * 0.74))
                path.addLine(to: CGPoint(x: -radius * 0.28, y: radius * 0.34))
                path.move(to: CGPoint(x: -radius * 0.98, y: radius * 0.24))
                path.addLine(to: CGPoint(x: -radius * 0.36, y: -radius * 0.02))
                path.addEllipse(in: CGRect(
                    x: -radius * 0.24,
                    y: -radius * 0.52,
                    width: radius * 1.04,
                    height: radius * 1.04
                ))
                path.move(to: CGPoint(x: radius * 0.10, y: -radius * 0.16))
                path.addLine(to: CGPoint(x: radius * 0.62, y: -radius * 0.48))
                path.move(to: CGPoint(x: radius * 0.10, y: -radius * 0.16))
                path.addLine(to: CGPoint(x: radius * 0.38, y: radius * 0.40))
            }
            return path
        }

        private func dungeonEnemyMarkerRadius(for kind: EnemyPresentationKind, tileSize: CGFloat) -> CGFloat {
            switch kind {
            case .rotatingWatcher:
                return tileSize * 0.39
            default:
                return tileSize * 0.28
            }
        }

        private func dungeonEnemyMarkerLineWidth(for kind: EnemyPresentationKind, tileSize: CGFloat) -> CGFloat {
            switch kind {
            case .rotatingWatcher:
                return max(tileSize * 0.036, 1.6)
            default:
                return max(tileSize * 0.045, 1.8)
            }
        }

        private func addRotatingWatcherPupilArrow(
            to path: CGMutablePath,
            radius: CGFloat,
            direction: RotatingWatcherDirection
        ) {
            let arcRadius = radius * 0.32
            switch direction {
            case .clockwise:
                path.addArc(
                    center: .zero,
                    radius: arcRadius,
                    startAngle: .pi * 0.12,
                    endAngle: .pi * 1.64,
                    clockwise: false
                )
                path.move(to: CGPoint(x: radius * 0.27, y: radius * 0.17))
                path.addLine(to: CGPoint(x: radius * 0.41, y: radius * 0.02))
                path.addLine(to: CGPoint(x: radius * 0.21, y: -radius * 0.05))
            case .counterclockwise:
                path.addArc(
                    center: .zero,
                    radius: arcRadius,
                    startAngle: .pi * 0.88,
                    endAngle: -.pi * 0.64,
                    clockwise: true
                )
                path.move(to: CGPoint(x: -radius * 0.27, y: radius * 0.17))
                path.addLine(to: CGPoint(x: -radius * 0.41, y: radius * 0.02))
                path.addLine(to: CGPoint(x: -radius * 0.21, y: -radius * 0.05))
            }
        }

        private func addChaserFootprintGlyph(to path: CGMutablePath, radius: CGFloat) {
            let footprints: [(center: CGPoint, angle: CGFloat)] = [
                (CGPoint(x: -radius * 0.34, y: radius * 0.28), -.pi * 0.10),
                (CGPoint(x: radius * 0.34, y: -radius * 0.22), .pi * 0.10)
            ]

            for footprint in footprints {
                var transform = CGAffineTransform(translationX: footprint.center.x, y: footprint.center.y)
                    .rotated(by: footprint.angle)
                path.addEllipse(
                    in: CGRect(
                        x: -radius * 0.22,
                        y: -radius * 0.38,
                        width: radius * 0.44,
                        height: radius * 0.56
                    ),
                    transform: transform
                )

                let toeY = radius * 0.30
                let toeOffsets: [CGFloat] = [-radius * 0.18, 0, radius * 0.18]
                for offset in toeOffsets {
                    transform = CGAffineTransform(translationX: footprint.center.x, y: footprint.center.y)
                        .rotated(by: footprint.angle)
                    path.addEllipse(
                        in: CGRect(
                            x: offset - radius * 0.07,
                            y: toeY - radius * 0.07,
                            width: radius * 0.14,
                            height: radius * 0.14
                        ),
                        transform: transform
                    )
                }
            }
        }

        private func addPatrolFacingGlyph(to path: CGMutablePath, radius: CGFloat, vector: MoveVector) {
            let dx = CGFloat(vector.dx)
            let dy = CGFloat(vector.dy)
            let length = max(sqrt(dx * dx + dy * dy), 1.0)
            let unitX = dx / length
            let unitY = dy / length
            let perpendicularX = -unitY
            let perpendicularY = unitX

            let tailDistance = radius * 0.54
            let tipDistance = radius * 0.54
            let headBackDistance = radius * 0.32
            let headSpread = radius * 0.26
            let tail = CGPoint(x: -unitX * tailDistance, y: -unitY * tailDistance)
            let tip = CGPoint(x: unitX * tipDistance, y: unitY * tipDistance)
            let headBase = CGPoint(
                x: tip.x - unitX * headBackDistance,
                y: tip.y - unitY * headBackDistance
            )
            let leftHead = CGPoint(
                x: headBase.x + perpendicularX * headSpread,
                y: headBase.y + perpendicularY * headSpread
            )
            let rightHead = CGPoint(
                x: headBase.x - perpendicularX * headSpread,
                y: headBase.y - perpendicularY * headSpread
            )

            path.move(to: tail)
            path.addLine(to: tip)
            path.move(to: leftHead)
            path.addLine(to: tip)
            path.addLine(to: rightHead)
        }

        private func applyPatrolRailPreviews(
            _ previews: [ScenePatrolRailPreview],
            scene: SKScene,
            layout: GameSceneLayoutSupport,
            palette: GameScenePalette
        ) {
            latestPatrolRailPreviews = previews

            let previewIDs = Set(previews.map(\.enemyID))
            let staleEnemyIDs = patrolRailNodes.keys.filter { !previewIDs.contains($0) }
            for enemyID in staleEnemyIDs {
                guard let node = patrolRailNodes[enemyID] else { continue }
                node.removeFromParent()
                patrolRailNodes.removeValue(forKey: enemyID)
            }

            for preview in previews {
                if let node = patrolRailNodes[preview.enemyID] {
                    if node.parent !== scene {
                        scene.addChild(node)
                    }
                    configurePatrolRailNode(
                        node,
                        preview: preview,
                        layout: layout
                    )
                } else {
                    let node = SKShapeNode()
                    configurePatrolRailNode(
                        node,
                        preview: preview,
                        layout: layout
                    )
                    scene.addChild(node)
                    patrolRailNodes[preview.enemyID] = node
                }
            }
        }

        private func configurePatrolRailNode(
            _ node: SKShapeNode,
            preview: ScenePatrolRailPreview,
            layout: GameSceneLayoutSupport
        ) {
            node.path = patrolRailPath(points: preview.path, layout: layout)
            node.fillColor = SKColor.clear
            node.strokeColor = patrolRailColor()
            node.lineWidth = patrolRailLineWidth(tileSize: layout.tileSize)
            node.glowWidth = 0
            node.lineJoin = .miter
            node.lineCap = .square
            node.position = .zero
            node.zPosition = 1.04
            node.isAntialiased = true
            node.blendMode = .alpha
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
            case .forcedSelection:
                baseColor = palette.boardWarpHighlight
                strokeAlpha = 0.82
                strokeWidth = max(layout.tileSize * 0.07, 2.4)
                fillColor = baseColor.withAlphaComponent(0.16)
                zPosition = 1.1
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
            case .dungeonEnemyWarning:
                baseColor = SKColor(red: 1.0, green: 0.34, blue: 0.10, alpha: 1.0)
                strokeAlpha = 0.86
                strokeWidth = max(layout.tileSize * 0.045, 1.4)
                fillColor = baseColor.withAlphaComponent(0.16)
                zPosition = 1.06
            case .dungeonCardPickup:
                baseColor = SKColor(red: 0.10, green: 0.62, blue: 0.52, alpha: 1.0)
                strokeAlpha = 0
                strokeWidth = 0
                fillColor = baseColor.withAlphaComponent(0.78)
                zPosition = 1.14
            case .dungeonRelicPickup:
                baseColor = SKColor(red: 0.96, green: 0.68, blue: 0.16, alpha: 1.0)
                strokeAlpha = 0.92
                strokeWidth = max(layout.tileSize * 0.035, 1.2)
                fillColor = baseColor.withAlphaComponent(0.82)
                zPosition = 1.15
            case .dungeonSuspiciousRelicPickup:
                baseColor = SKColor(red: 0.82, green: 0.12, blue: 0.12, alpha: 1.0)
                strokeAlpha = 0.96
                strokeWidth = max(layout.tileSize * 0.045, 1.4)
                fillColor = baseColor.withAlphaComponent(0.78)
                zPosition = 1.155
            case .dungeonDamageTrap:
                baseColor = SKColor(red: 0.82, green: 0.10, blue: 0.08, alpha: 1.0)
                strokeAlpha = 0
                strokeWidth = 0
                fillColor = baseColor.withAlphaComponent(0.70)
                zPosition = 1.13
            case .dungeonHealingTile:
                baseColor = SKColor(red: 0.10, green: 0.62, blue: 0.34, alpha: 1.0)
                strokeAlpha = 0
                strokeWidth = 0
                fillColor = baseColor.withAlphaComponent(0.72)
                zPosition = 1.13
            case .dungeonCrackedFloor:
                baseColor = SKColor(red: 0.95, green: 0.60, blue: 0.12, alpha: 1.0)
                strokeAlpha = 0.92
                strokeWidth = max(layout.tileSize * 0.045, 1.4)
                fillColor = SKColor.clear
                zPosition = 1.07
            case .dungeonCollapsedFloor:
                baseColor = SKColor(red: 0.08, green: 0.09, blue: 0.10, alpha: 1.0)
                strokeAlpha = 0
                strokeWidth = 0
                fillColor = baseColor.withAlphaComponent(0.72)
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
            node.lineCap = kind == .dungeonCrackedFloor || kind == .dungeonEnemyWarning ? .round : .square
            node.position = layout.position(for: point)
            node.zPosition = zPosition
            node.isAntialiased = kind == .dungeonExit
                || kind == .dungeonExitLocked
                || kind == .dungeonKey
                || kind == .dungeonEnemy
                || kind == .dungeonEnemyWarning
                || kind == .dungeonCardPickup
                || kind == .dungeonRelicPickup
                || kind == .dungeonSuspiciousRelicPickup
                || kind == .dungeonDamageTrap
                || kind == .dungeonHealingTile
                || kind == .dungeonCrackedFloor
                || kind == .dungeonCollapsedFloor
            node.blendMode = .alpha
        }

        private func highlightPath(
            for kind: BoardHighlightKind,
            in rect: CGRect,
            tileSize: CGFloat
        ) -> CGPath {
            switch kind {
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
            case .dungeonEnemy:
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
                 .forcedSelection,
                 .dungeonDanger:
                return CGPath(rect: rect, transform: nil)
            case .dungeonEnemyWarning:
                return meteorWarningMarkerPath(in: rect)
            case .dungeonCardPickup:
                return cardPickupMarkerPath(center: CGPoint(x: rect.midX, y: rect.midY), tileSize: tileSize)
            case .dungeonRelicPickup:
                return relicPickupMarkerPath(center: CGPoint(x: rect.midX, y: rect.midY), tileSize: tileSize)
            case .dungeonSuspiciousRelicPickup:
                return suspiciousRelicPickupMarkerPath(center: CGPoint(x: rect.midX, y: rect.midY), tileSize: tileSize)
            case .dungeonDamageTrap:
                return damageTrapMarkerPath(center: CGPoint(x: rect.midX, y: rect.midY), tileSize: tileSize)
            case .dungeonHealingTile:
                return healingTileMarkerPath(center: CGPoint(x: rect.midX, y: rect.midY), tileSize: tileSize)
            case .dungeonCrackedFloor:
                return crackedFloorMarkerPath(in: rect)
            case .dungeonCollapsedFloor:
                return collapsedFloorHolePath(in: rect)
            }
        }

        private func meteorWarningMarkerPath(in rect: CGRect) -> CGPath {
            let path = CGMutablePath()
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = min(rect.width, rect.height) * 0.34
            path.addEllipse(in: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            path.move(to: CGPoint(x: center.x - radius * 0.38, y: center.y))
            path.addLine(to: CGPoint(x: center.x + radius * 0.38, y: center.y))
            path.move(to: CGPoint(x: center.x, y: center.y - radius * 0.38))
            path.addLine(to: CGPoint(x: center.x, y: center.y + radius * 0.38))
            return path
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

        private func relicPickupMarkerPath(center: CGPoint, tileSize: CGFloat) -> CGPath {
            let width = tileSize * 0.52
            let height = tileSize * 0.36
            let body = CGRect(
                x: center.x - width / 2,
                y: center.y - height * 0.32,
                width: width,
                height: height
            )
            let lid = CGRect(
                x: center.x - width * 0.44,
                y: body.maxY - height * 0.10,
                width: width * 0.88,
                height: height * 0.28
            )
            let path = CGMutablePath()
            path.addRoundedRect(in: body, cornerWidth: tileSize * 0.04, cornerHeight: tileSize * 0.04)
            path.addRoundedRect(in: lid, cornerWidth: tileSize * 0.05, cornerHeight: tileSize * 0.05)
            path.move(to: CGPoint(x: center.x - width * 0.10, y: body.minY))
            path.addLine(to: CGPoint(x: center.x - width * 0.10, y: lid.maxY))
            path.move(to: CGPoint(x: center.x + width * 0.10, y: body.minY))
            path.addLine(to: CGPoint(x: center.x + width * 0.10, y: lid.maxY))
            return path
        }

        private func suspiciousRelicPickupMarkerPath(center: CGPoint, tileSize: CGFloat) -> CGPath {
            let path = CGMutablePath()
            path.addPath(relicPickupMarkerPath(center: center, tileSize: tileSize))
            let markHeight = tileSize * 0.25
            path.move(to: CGPoint(x: center.x, y: center.y + markHeight * 0.45))
            path.addLine(to: CGPoint(x: center.x, y: center.y - markHeight * 0.15))
            path.move(to: CGPoint(x: center.x, y: center.y - markHeight * 0.34))
            path.addLine(to: CGPoint(x: center.x, y: center.y - markHeight * 0.36))
            return path
        }

        private func damageTrapMarkerPath(center: CGPoint, tileSize: CGFloat) -> CGPath {
            let halfWidth = tileSize * 0.31
            let baseTopY = center.y - tileSize * 0.18
            let baseBottomY = center.y - tileSize * 0.29
            let leftX = center.x - halfWidth
            let rightX = center.x + halfWidth
            let path = CGMutablePath()
            path.move(to: CGPoint(x: leftX, y: baseBottomY))
            path.addLine(to: CGPoint(x: leftX, y: baseTopY))
            path.addLine(to: CGPoint(x: center.x - tileSize * 0.22, y: center.y + tileSize * 0.18))
            path.addLine(to: CGPoint(x: center.x - tileSize * 0.11, y: baseTopY + tileSize * 0.02))
            path.addLine(to: CGPoint(x: center.x, y: center.y + tileSize * 0.28))
            path.addLine(to: CGPoint(x: center.x + tileSize * 0.11, y: baseTopY + tileSize * 0.02))
            path.addLine(to: CGPoint(x: center.x + tileSize * 0.22, y: center.y + tileSize * 0.18))
            path.addLine(to: CGPoint(x: rightX, y: baseTopY))
            path.addLine(to: CGPoint(x: rightX, y: baseBottomY))
            path.closeSubpath()
            return path
        }

        private func healingTileMarkerPath(center: CGPoint, tileSize: CGFloat) -> CGPath {
            let armLength = tileSize * 0.50
            let armWidth = tileSize * 0.18
            let halfLength = armLength / 2
            let halfWidth = armWidth / 2
            let path = CGMutablePath()
            path.move(to: CGPoint(x: center.x - halfWidth, y: center.y - halfLength))
            path.addLine(to: CGPoint(x: center.x + halfWidth, y: center.y - halfLength))
            path.addLine(to: CGPoint(x: center.x + halfWidth, y: center.y - halfWidth))
            path.addLine(to: CGPoint(x: center.x + halfLength, y: center.y - halfWidth))
            path.addLine(to: CGPoint(x: center.x + halfLength, y: center.y + halfWidth))
            path.addLine(to: CGPoint(x: center.x + halfWidth, y: center.y + halfWidth))
            path.addLine(to: CGPoint(x: center.x + halfWidth, y: center.y + halfLength))
            path.addLine(to: CGPoint(x: center.x - halfWidth, y: center.y + halfLength))
            path.addLine(to: CGPoint(x: center.x - halfWidth, y: center.y + halfWidth))
            path.addLine(to: CGPoint(x: center.x - halfLength, y: center.y + halfWidth))
            path.addLine(to: CGPoint(x: center.x - halfLength, y: center.y - halfWidth))
            path.addLine(to: CGPoint(x: center.x - halfWidth, y: center.y - halfWidth))
            path.closeSubpath()
            return path
        }

        private func crackedFloorMarkerPath(in rect: CGRect) -> CGPath {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.14))
            path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.10, y: rect.midY - rect.height * 0.08))
            path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.08, y: rect.midY + rect.height * 0.06))
            path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.02, y: rect.maxY - rect.height * 0.12))
            path.move(to: CGPoint(x: rect.midX - rect.width * 0.10, y: rect.midY - rect.height * 0.08))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.midY + rect.height * 0.18))
            path.move(to: CGPoint(x: rect.midX + rect.width * 0.08, y: rect.midY + rect.height * 0.06))
            path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.16, y: rect.midY - rect.height * 0.16))
            return path
        }

        private func collapsedFloorHolePath(in rect: CGRect) -> CGPath {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.12))
            path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.minY + rect.height * 0.26))
            path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.28, y: rect.maxY - rect.height * 0.16))
            path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.08, y: rect.maxY - rect.height * 0.10))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.16, y: rect.maxY - rect.height * 0.30))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.midY - rect.height * 0.08))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY + rect.height * 0.18))
            path.closeSubpath()
            return path
        }

        private func patrolRailPath(points: [GridPoint], layout: GameSceneLayoutSupport) -> CGPath {
            let path = CGMutablePath()
            guard points.count > 1 else { return path }

            let centers = points.map { layout.position(for: $0) }
            path.move(to: centers[0])
            for center in centers.dropFirst() {
                path.addLine(to: center)
            }

            if let first = points.first,
               let last = points.last,
               manhattanDistance(from: first, to: last) == 1 {
                path.addLine(to: centers[0])
            }

            return path
        }

        private func manhattanDistance(from a: GridPoint, to b: GridPoint) -> Int {
            abs(a.x - b.x) + abs(a.y - b.y)
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

        private func patrolRailColor() -> SKColor {
            return SKColor(white: 0.48, alpha: 0.86)
        }

        private func patrolRailLineWidth(tileSize: CGFloat) -> CGFloat {
            return min(max(tileSize * 0.024, 2.0), 2.2)
        }
    }
#endif
