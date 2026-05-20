#if canImport(SpriteKit)
    import SpriteKit
    import SharedSupport

    final class GameSceneHighlightRenderer {
        private(set) var highlightNodes: [BoardHighlightKind: [GridPoint: SKShapeNode]] = [:]
        private(set) var dungeonEnemyMarkerNodes: [String: SKShapeNode] = [:]
        private(set) var watcherLaserNodes: [String: SKShapeNode] = [:]
        private(set) var patrolRailNodes: [String: SKShapeNode] = [:]
        private(set) var patrolMovementArrowNodes: [String: SKShapeNode] = [:]
        private var latestSingleGuidePoints: Set<GridPoint> = []
        private var latestDirectTwoStepGuidePoints: Set<GridPoint> = []
        private var latestMultipleGuidePoints: Set<GridPoint> = []
        private var latestMultiStepPathPoints: Set<GridPoint> = []
        private var latestMultiStepGuidePoints: Set<GridPoint> = []
        private var latestWarpGuidePoints: Set<GridPoint> = []
        private var latestDungeonBasicMovePoints: Set<GridPoint> = []
        private var latestForcedSelectionPoints: Set<GridPoint> = []
        private var latestDungeonExitPoints: Set<GridPoint> = []
        private var latestDungeonExitLockedPoints: Set<GridPoint> = []
        private var latestDungeonKeyPoints: Set<GridPoint> = []
        private var latestDungeonFloorStartExitTargetPoints: Set<GridPoint> = []
        private var latestDungeonFloorStartKeyTargetPoints: Set<GridPoint> = []
        private var latestDungeonEnemyPoints: Set<GridPoint> = []
        private var latestDungeonDangerPoints: Set<GridPoint> = []
        private var latestDungeonEnemyWarningPoints: Set<GridPoint> = []
        private var latestDungeonCardPickupPoints: Set<GridPoint> = []
        private var latestDungeonRelicPickupPoints: Set<GridPoint> = []
        private var latestDungeonSuspiciousRelicPickupPoints: Set<GridPoint> = []
        private var latestDungeonDamageTrapPoints: Set<GridPoint> = []
        private var latestDungeonStrongDamageTrapPoints: Set<GridPoint> = []
        private var latestDungeonHpHalvingTrapPoints: Set<GridPoint> = []
        private var latestDungeonLavaTilePoints: Set<GridPoint> = []
        private var latestDungeonStrongLavaTilePoints: Set<GridPoint> = []
        private var latestDungeonHealingTilePoints: Set<GridPoint> = []
        private var latestDungeonCrackedFloorPoints: Set<GridPoint> = []
        private var latestDungeonCollapsedFloorPoints: Set<GridPoint> = []
        private var latestDungeonEnemyMarkers: [SceneDungeonEnemyMarker] = []
        private var pendingDungeonEnemyMarkers: [SceneDungeonEnemyMarker] = []
        private var hasPendingDungeonEnemyMarkerUpdate = false
        private var latestWatcherLaserPreviews: [SceneWatcherLaserPreview] = []
        private var pendingWatcherLaserPreviews: [SceneWatcherLaserPreview] = []
        private var hasPendingWatcherLaserUpdate = false
        private var latestPatrolRailPreviews: [ScenePatrolRailPreview] = []
        private var pendingPatrolRailPreviews: [ScenePatrolRailPreview] = []
        private var hasPendingPatrolRailUpdate = false
        private var latestPatrolMovementPreviews: [ScenePatrolMovementPreview] = []
        private var pendingPatrolMovementPreviews: [ScenePatrolMovementPreview] = []
        private var hasPendingPatrolMovementPreviewUpdate = false
        private var pendingHighlightPoints: [BoardHighlightKind: Set<GridPoint>] = [:]
        private var areFlySuppressedDungeonHazardsMuted = false

        var patrolRailCount: Int { patrolRailNodes.count }
        var patrolMovementArrowCount: Int { patrolMovementArrowNodes.count }
        var watcherLaserCount: Int { watcherLaserNodes.count }

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
            for node in watcherLaserNodes.values {
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
            watcherLaserNodes = [:]
            patrolRailNodes = [:]
            patrolMovementArrowNodes = [:]
            latestSingleGuidePoints = []
            latestDirectTwoStepGuidePoints = []
            latestMultipleGuidePoints = []
            latestMultiStepPathPoints = []
            latestMultiStepGuidePoints = []
            latestWarpGuidePoints = []
            latestDungeonBasicMovePoints = []
            latestForcedSelectionPoints = []
            latestDungeonExitPoints = []
            latestDungeonExitLockedPoints = []
            latestDungeonKeyPoints = []
            latestDungeonFloorStartExitTargetPoints = []
            latestDungeonFloorStartKeyTargetPoints = []
            latestDungeonEnemyPoints = []
            latestDungeonDangerPoints = []
            latestDungeonEnemyWarningPoints = []
            latestDungeonCardPickupPoints = []
            latestDungeonRelicPickupPoints = []
            latestDungeonSuspiciousRelicPickupPoints = []
            latestDungeonDamageTrapPoints = []
            latestDungeonHpHalvingTrapPoints = []
            latestDungeonLavaTilePoints = []
            latestDungeonHealingTilePoints = []
            latestDungeonCrackedFloorPoints = []
            latestDungeonCollapsedFloorPoints = []
            latestDungeonEnemyMarkers = []
            pendingDungeonEnemyMarkers = []
            hasPendingDungeonEnemyMarkerUpdate = false
            latestWatcherLaserPreviews = []
            pendingWatcherLaserPreviews = []
            hasPendingWatcherLaserUpdate = false
            latestPatrolRailPreviews = []
            pendingPatrolRailPreviews = []
            hasPendingPatrolRailUpdate = false
            latestPatrolMovementPreviews = []
            pendingPatrolMovementPreviews = []
            hasPendingPatrolMovementPreviewUpdate = false
            areFlySuppressedDungeonHazardsMuted = false
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
            visiblePoints: Set<GridPoint>?,
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
                palette: palette,
                visiblePoints: visiblePoints
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

        func updateWatcherLaserPreviews(
            _ previews: [SceneWatcherLaserPreview],
            scene: SKScene,
            layout: GameSceneLayoutSupport,
            palette: GameScenePalette,
            isLayoutReady: Bool
        ) {
            latestWatcherLaserPreviews = previews
            pendingWatcherLaserPreviews = previews
            hasPendingWatcherLaserUpdate = true

            debugLog(
                "GameScene 見張りレーザー更新要求: count=\(previews.count), レイアウト確定=\(isLayoutReady)"
            )

            guard isLayoutReady else { return }
            applyWatcherLaserPreviews(previews, scene: scene, layout: layout, palette: palette)
            hasPendingWatcherLaserUpdate = false
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
            palette: GameScenePalette,
            visiblePoints: Set<GridPoint>?
        ) {
            guard layout.tileSize > 0 else { return }

            for (kind, nodes) in highlightNodes {
                for (point, node) in nodes {
                    configureHighlightNode(
                        node,
                        for: point,
                        kind: kind,
                        layout: layout,
                        palette: palette,
                        visiblePoints: visiblePoints
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

            for preview in latestWatcherLaserPreviews {
                guard let node = watcherLaserNodes[preview.enemyID] else { continue }
                configureWatcherLaserNode(
                    node,
                    preview: preview,
                    layout: layout,
                    palette: palette
                )
            }

            for preview in latestPatrolRailPreviews {
                guard let node = patrolRailNodes[preview.enemyID] else { continue }
                configurePatrolRailNode(
                    node,
                    preview: preview,
                    layout: layout,
                    palette: palette
                )
            }

            for preview in latestPatrolMovementPreviews {
                guard let node = patrolMovementArrowNodes[preview.enemyID] else { continue }
                configurePatrolMovementArrowNode(
                    node,
                    preview: preview,
                    layout: layout,
                    palette: palette
                )
            }
        }

        func updateFlySuppressedDungeonHazardsMuted(
            _ isMuted: Bool,
            layout: GameSceneLayoutSupport,
            palette: GameScenePalette,
            visiblePoints: Set<GridPoint>?
        ) {
            guard areFlySuppressedDungeonHazardsMuted != isMuted else { return }
            areFlySuppressedDungeonHazardsMuted = isMuted
            refreshAppearance(layout: layout, palette: palette, visiblePoints: visiblePoints)
        }

        func removeAllNodes() {
            reset()
        }

        func applyPendingIfNeeded(
            scene: SKScene,
            layout: GameSceneLayoutSupport,
            palette: GameScenePalette,
            visiblePoints: Set<GridPoint>?,
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
            let hasRenderedWatcherLasers = !watcherLaserNodes.isEmpty
            let hasRenderedPatrolRails = !patrolRailNodes.isEmpty
            let hasRenderedPatrolPreviews = !patrolMovementArrowNodes.isEmpty
            guard hasPendingValues
                    || hasRenderedHighlights
                    || hasPendingDungeonEnemyMarkerUpdate
                    || hasRenderedEnemyMarkers
                    || !latestDungeonEnemyMarkers.isEmpty
                    || hasPendingWatcherLaserUpdate
                    || hasRenderedWatcherLasers
                    || !latestWatcherLaserPreviews.isEmpty
                    || hasPendingPatrolRailUpdate
                    || hasRenderedPatrolRails
                    || !latestPatrolRailPreviews.isEmpty
                    || hasPendingPatrolMovementPreviewUpdate
                    || hasRenderedPatrolPreviews
                    || !latestPatrolMovementPreviews.isEmpty
            else { return }

            if hasPendingValues {
                applyHighlightsImmediately(
                    snapshot,
                    scene: scene,
                    layout: layout,
                    palette: palette,
                    visiblePoints: visiblePoints
                )
            } else if hasRenderedHighlights {
                let latestSnapshot: [BoardHighlightKind: Set<GridPoint>] = [
                    .guideSingleCandidate: latestSingleGuidePoints,
                    .guideDirectTwoStepCandidate: latestDirectTwoStepGuidePoints,
                    .guideMultipleCandidate: latestMultipleGuidePoints,
                    .guideMultiStepPath: latestMultiStepPathPoints,
                    .guideMultiStepCandidate: latestMultiStepGuidePoints,
                    .guideWarpCandidate: latestWarpGuidePoints,
                    .dungeonBasicMove: latestDungeonBasicMovePoints,
                    .forcedSelection: latestForcedSelectionPoints,
                    .dungeonExit: latestDungeonExitPoints,
                    .dungeonExitLocked: latestDungeonExitLockedPoints,
                    .dungeonKey: latestDungeonKeyPoints,
                    .dungeonFloorStartExitTarget: latestDungeonFloorStartExitTargetPoints,
                    .dungeonFloorStartKeyTarget: latestDungeonFloorStartKeyTargetPoints,
                    .dungeonEnemy: latestDungeonEnemyPoints,
                    .dungeonDanger: latestDungeonDangerPoints,
                    .dungeonEnemyWarning: latestDungeonEnemyWarningPoints,
                    .dungeonCardPickup: latestDungeonCardPickupPoints,
                    .dungeonRelicPickup: latestDungeonRelicPickupPoints,
                    .dungeonSuspiciousRelicPickup: latestDungeonSuspiciousRelicPickupPoints,
                    .dungeonDamageTrap: latestDungeonDamageTrapPoints,
                    .dungeonStrongDamageTrap: latestDungeonStrongDamageTrapPoints,
                    .dungeonHpHalvingTrap: latestDungeonHpHalvingTrapPoints,
                    .dungeonLavaTile: latestDungeonLavaTilePoints,
                    .dungeonStrongLavaTile: latestDungeonStrongLavaTilePoints,
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
                        palette: palette,
                        visiblePoints: visiblePoints
                    )
                } else {
                    applyHighlightsImmediately(
                        snapshot,
                        scene: scene,
                        layout: layout,
                        palette: palette,
                        visiblePoints: visiblePoints
                    )
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

            if hasPendingWatcherLaserUpdate {
                applyWatcherLaserPreviews(
                    pendingWatcherLaserPreviews,
                    scene: scene,
                    layout: layout,
                    palette: palette
                )
                hasPendingWatcherLaserUpdate = false
            } else if hasRenderedWatcherLasers || !latestWatcherLaserPreviews.isEmpty {
                applyWatcherLaserPreviews(
                    latestWatcherLaserPreviews,
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
            latestDirectTwoStepGuidePoints = highlights[.guideDirectTwoStepCandidate] ?? []
            latestMultipleGuidePoints = highlights[.guideMultipleCandidate] ?? []
            latestMultiStepPathPoints = highlights[.guideMultiStepPath] ?? []
            latestMultiStepGuidePoints = highlights[.guideMultiStepCandidate] ?? []
            latestWarpGuidePoints = highlights[.guideWarpCandidate] ?? []
            latestDungeonBasicMovePoints = highlights[.dungeonBasicMove] ?? []
            latestForcedSelectionPoints = highlights[.forcedSelection] ?? []
            latestDungeonExitPoints = highlights[.dungeonExit] ?? []
            latestDungeonExitLockedPoints = highlights[.dungeonExitLocked] ?? []
            latestDungeonKeyPoints = highlights[.dungeonKey] ?? []
            latestDungeonFloorStartExitTargetPoints = highlights[.dungeonFloorStartExitTarget] ?? []
            latestDungeonFloorStartKeyTargetPoints = highlights[.dungeonFloorStartKeyTarget] ?? []
            latestDungeonEnemyPoints = highlights[.dungeonEnemy] ?? []
            latestDungeonDangerPoints = highlights[.dungeonDanger] ?? []
            latestDungeonEnemyWarningPoints = highlights[.dungeonEnemyWarning] ?? []
            latestDungeonCardPickupPoints = highlights[.dungeonCardPickup] ?? []
            latestDungeonRelicPickupPoints = highlights[.dungeonRelicPickup] ?? []
            latestDungeonSuspiciousRelicPickupPoints = highlights[.dungeonSuspiciousRelicPickup] ?? []
            latestDungeonDamageTrapPoints = highlights[.dungeonDamageTrap] ?? []
            latestDungeonStrongDamageTrapPoints = highlights[.dungeonStrongDamageTrap] ?? []
            latestDungeonHpHalvingTrapPoints = highlights[.dungeonHpHalvingTrap] ?? []
            latestDungeonLavaTilePoints = highlights[.dungeonLavaTile] ?? []
            latestDungeonStrongLavaTilePoints = highlights[.dungeonStrongLavaTile] ?? []
            latestDungeonHealingTilePoints = highlights[.dungeonHealingTile] ?? []
            latestDungeonCrackedFloorPoints = highlights[.dungeonCrackedFloor] ?? []
            latestDungeonCollapsedFloorPoints = highlights[.dungeonCollapsedFloor] ?? []
        }

        private func applyHighlightsImmediately(
            _ highlights: [BoardHighlightKind: Set<GridPoint>],
            scene: SKScene,
            layout: GameSceneLayoutSupport,
            palette: GameScenePalette,
            visiblePoints: Set<GridPoint>?
        ) {
            updateLatestPoints(using: highlights)

            for kind in BoardHighlightKind.allCases {
                let points = highlights[kind] ?? []
                rebuildHighlightNodes(
                    for: kind,
                    using: points,
                    scene: scene,
                    layout: layout,
                    palette: palette,
                    visiblePoints: visiblePoints
                )
            }
        }

        private func rebuildHighlightNodes(
            for kind: BoardHighlightKind,
            using points: Set<GridPoint>,
            scene: SKScene,
            layout: GameSceneLayoutSupport,
            palette: GameScenePalette,
            visiblePoints: Set<GridPoint>?
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
                        palette: palette,
                        visiblePoints: visiblePoints
                    )
                } else {
                    let node = SKShapeNode()
                    configureHighlightNode(
                        node,
                        for: point,
                        kind: kind,
                        layout: layout,
                        palette: palette,
                        visiblePoints: visiblePoints
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
            let style = dungeonEnemyMarkerStyle(
                for: marker.kind,
                damage: marker.damage,
                palette: palette
            )
            node.path = dungeonEnemyMarkerPath(marker: marker, tileSize: layout.tileSize)
            node.fillColor = style.fill
            node.strokeColor = style.stroke
            node.lineWidth = dungeonEnemyMarkerLineWidth(for: marker.kind, tileSize: layout.tileSize)
            node.glowWidth = usesNeonGridTheme(palette)
                ? max(layout.tileSize * 0.026, 0.9)
                : max(layout.tileSize * 0.012, 0.5)
            node.lineJoin = .round
            node.lineCap = .round
            node.position = layout.position(for: marker.point)
            node.zPosition = 1.19
            node.isAntialiased = true
            node.blendMode = .alpha
        }

        private func dungeonEnemyMarkerStyle(
            for kind: EnemyPresentationKind,
            damage: Int,
            palette: GameScenePalette
        ) -> (fill: SKColor, stroke: SKColor) {
            if damage >= 3 {
                return (
                    SKColor(red: 0.60, green: 0.04, blue: 0.18, alpha: 0.40),
                    SKColor(red: 0.96, green: 0.08, blue: 0.28, alpha: 0.98)
                )
            }
            if damage >= 2 {
                return (
                    SKColor(red: 0.92, green: 0.24, blue: 0.08, alpha: 0.36),
                    SKColor(red: 1.00, green: 0.34, blue: 0.12, alpha: 0.98)
                )
            }

            if usesNeonGridTheme(palette) {
                switch kind {
                case .guardPost:
                    return (
                        palette.boardDungeonEnemy.withAlphaComponent(0.18),
                        palette.boardDungeonEnemy.withAlphaComponent(0.96)
                    )
                case .patrol:
                    return (
                        palette.boardDungeonWarning.withAlphaComponent(0.16),
                        palette.boardDungeonWarning.withAlphaComponent(0.98)
                    )
                case .watcher:
                    return (
                        palette.boardDungeonDamageTrap.withAlphaComponent(0.15),
                        palette.boardDungeonDamageTrap.withAlphaComponent(0.96)
                    )
                case .rotatingWatcher:
                    return (
                        SKColor.clear,
                        palette.boardDungeonHpHalvingTrap.withAlphaComponent(0.98)
                    )
                case .chaser:
                    return (
                        palette.boardDungeonCardPickup.withAlphaComponent(0.16),
                        palette.boardDungeonCardPickup.withAlphaComponent(0.98)
                    )
                case .marker, .starReader:
                    return (
                        palette.boardDungeonWarning.withAlphaComponent(0.18),
                        palette.boardDungeonWarning.withAlphaComponent(0.98)
                    )
                }
            }

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
            case .marker, .starReader:
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
            case .marker, .starReader:
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
                if marker.kind == .starReader {
                    path.move(to: CGPoint(x: radius * 0.70, y: radius * 0.60))
                    path.addLine(to: CGPoint(x: radius * 0.70, y: radius * 0.98))
                    path.move(to: CGPoint(x: radius * 0.51, y: radius * 0.79))
                    path.addLine(to: CGPoint(x: radius * 0.89, y: radius * 0.79))
                }
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
                path.move(to: CGPoint(
                    x: cos(.pi * 0.12) * arcRadius,
                    y: sin(.pi * 0.12) * arcRadius
                ))
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
                path.move(to: CGPoint(
                    x: cos(.pi * 0.88) * arcRadius,
                    y: sin(.pi * 0.88) * arcRadius
                ))
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
                (CGPoint(x: -radius * 0.32, y: radius * 0.26), -.pi * 0.15),
                (CGPoint(x: radius * 0.32, y: -radius * 0.26), .pi * 0.15)
            ]

            for footprint in footprints {
                var transform = CGAffineTransform(translationX: footprint.center.x, y: footprint.center.y)
                    .rotated(by: footprint.angle)
                path.addEllipse(
                    in: CGRect(
                        x: -radius * 0.20,
                        y: -radius * 0.36,
                        width: radius * 0.40,
                        height: radius * 0.62
                    ),
                    transform: transform
                )

                let toes: [(x: CGFloat, y: CGFloat, size: CGFloat)] = [
                    (-radius * 0.20, radius * 0.31, radius * 0.12),
                    (-radius * 0.07, radius * 0.37, radius * 0.14),
                    (radius * 0.07, radius * 0.37, radius * 0.13),
                    (radius * 0.19, radius * 0.31, radius * 0.105)
                ]
                for toe in toes {
                    transform = CGAffineTransform(translationX: footprint.center.x, y: footprint.center.y)
                        .rotated(by: footprint.angle)
                    path.addEllipse(
                        in: CGRect(
                            x: toe.x - toe.size / 2,
                            y: toe.y - toe.size / 2,
                            width: toe.size,
                            height: toe.size
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

        private func applyWatcherLaserPreviews(
            _ previews: [SceneWatcherLaserPreview],
            scene: SKScene,
            layout: GameSceneLayoutSupport,
            palette: GameScenePalette
        ) {
            latestWatcherLaserPreviews = previews

            let previewIDs = Set(previews.map(\.enemyID))
            let staleEnemyIDs = watcherLaserNodes.keys.filter { !previewIDs.contains($0) }
            for enemyID in staleEnemyIDs {
                guard let node = watcherLaserNodes[enemyID] else { continue }
                node.removeFromParent()
                watcherLaserNodes.removeValue(forKey: enemyID)
            }

            for preview in previews {
                if let node = watcherLaserNodes[preview.enemyID] {
                    if node.parent !== scene {
                        scene.addChild(node)
                    }
                    configureWatcherLaserNode(
                        node,
                        preview: preview,
                        layout: layout,
                        palette: palette
                    )
                } else {
                    let node = SKShapeNode()
                    configureWatcherLaserNode(
                        node,
                        preview: preview,
                        layout: layout,
                        palette: palette
                    )
                    scene.addChild(node)
                    watcherLaserNodes[preview.enemyID] = node
                }
            }
        }

        private func configureWatcherLaserNode(
            _ node: SKShapeNode,
            preview: SceneWatcherLaserPreview,
            layout: GameSceneLayoutSupport,
            palette: GameScenePalette
        ) {
            let baseColor = watcherLaserColor(palette: palette)
            node.path = watcherLaserPath(preview: preview, layout: layout)
            node.fillColor = SKColor.clear
            node.strokeColor = baseColor.withAlphaComponent(0.94)
            node.lineWidth = max(layout.tileSize * 0.070, 3.0)
            node.glowWidth = max(layout.tileSize * 0.060, 2.2)
            node.lineJoin = .round
            node.lineCap = .round
            node.position = .zero
            node.zPosition = 1.115
            node.isAntialiased = true
            node.blendMode = .alpha
        }

        private func watcherLaserPath(
            preview: SceneWatcherLaserPreview,
            layout: GameSceneLayoutSupport
        ) -> CGPath {
            let path = CGMutablePath()
            guard let lastPoint = preview.dangerPoints.max(by: {
                laserProjection($0, origin: preview.origin, direction: preview.direction)
                    < laserProjection($1, origin: preview.origin, direction: preview.direction)
            }) else {
                return path
            }

            let unit = normalizedLaserUnit(preview.direction)
            let originCenter = layout.position(for: preview.origin)
            let lastCenter = layout.position(for: lastPoint)
            let start = CGPoint(
                x: originCenter.x + unit.x * layout.tileSize * 0.18,
                y: originCenter.y + unit.y * layout.tileSize * 0.18
            )
            let end = CGPoint(
                x: lastCenter.x + unit.x * layout.tileSize * 0.38,
                y: lastCenter.y + unit.y * layout.tileSize * 0.38
            )
            path.move(to: start)
            path.addLine(to: end)
            return path
        }

        private func laserProjection(
            _ point: GridPoint,
            origin: GridPoint,
            direction: MoveVector
        ) -> Int {
            (point.x - origin.x) * direction.dx + (point.y - origin.y) * direction.dy
        }

        private func normalizedLaserUnit(_ direction: MoveVector) -> CGPoint {
            let dx = CGFloat(direction.dx == 0 ? 0 : (direction.dx > 0 ? 1 : -1))
            let dy = CGFloat(direction.dy == 0 ? 0 : (direction.dy > 0 ? 1 : -1))
            let length = max(sqrt(dx * dx + dy * dy), 1)
            return CGPoint(x: dx / length, y: dy / length)
        }

        private func watcherLaserColor(palette: GameScenePalette) -> SKColor {
            usesNeonGridTheme(palette)
                ? palette.boardDungeonDamageTrap
                : SKColor(red: 1.00, green: 0.14, blue: 0.34, alpha: 1.0)
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
                        layout: layout,
                        palette: palette
                    )
                } else {
                    let node = SKShapeNode()
                    configurePatrolRailNode(
                        node,
                        preview: preview,
                        layout: layout,
                        palette: palette
                    )
                    scene.addChild(node)
                    patrolRailNodes[preview.enemyID] = node
                }
            }
        }

        private func configurePatrolRailNode(
            _ node: SKShapeNode,
            preview: ScenePatrolRailPreview,
            layout: GameSceneLayoutSupport,
            palette: GameScenePalette
        ) {
            node.path = patrolRailPath(points: preview.path, layout: layout)
            node.fillColor = SKColor.clear
            node.strokeColor = patrolRailColor(palette: palette)
            node.lineWidth = patrolRailLineWidth(tileSize: layout.tileSize)
            node.glowWidth = usesNeonGridTheme(palette) ? max(layout.tileSize * 0.012, 0.5) : 0
            node.lineJoin = usesNeonGridTheme(palette) ? .round : .miter
            node.lineCap = usesNeonGridTheme(palette) ? .round : .square
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
                        layout: layout,
                        palette: palette
                    )
                } else {
                    let node = SKShapeNode()
                    configurePatrolMovementArrowNode(
                        node,
                        preview: preview,
                        layout: layout,
                        palette: palette
                    )
                    scene.addChild(node)
                    patrolMovementArrowNodes[preview.enemyID] = node
                }
            }
        }

        private func configurePatrolMovementArrowNode(
            _ node: SKShapeNode,
            preview: ScenePatrolMovementPreview,
            layout: GameSceneLayoutSupport,
            palette: GameScenePalette
        ) {
            let baseColor = patrolMovementArrowColor(palette: palette)
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
            palette: GameScenePalette,
            visiblePoints: Set<GridPoint>?
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
            var glowWidth: CGFloat = 0
            var usesDarknessCandidateStyle = false

            switch kind {
            case .guideSingleCandidate:
                baseColor = directMoveGuideColor(palette)
                strokeAlpha = 0.9
                strokeWidth = sharedGuideStrokeWidth
                zPosition = 0.95
            case .guideDirectTwoStepCandidate:
                baseColor = directMoveGuideColor(palette)
                strokeAlpha = 0.9
                strokeWidth = sharedGuideStrokeWidth
                if latestSingleGuidePoints.contains(point) {
                    overlapInset = max(overlapInset, strokeWidth * 1.5)
                }
                if latestMultipleGuidePoints.contains(point) {
                    overlapInset = max(overlapInset, strokeWidth * 1.2)
                }
                if latestMultiStepGuidePoints.contains(point) {
                    overlapInset = max(overlapInset, strokeWidth * 0.9)
                }
                if latestWarpGuidePoints.contains(point) {
                    overlapInset = max(overlapInset, strokeWidth * 1.1)
                }
                zPosition = 1.025
            case .guideMultipleCandidate:
                baseColor = directMoveGuideColor(palette)
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
                baseColor = directMoveGuideColor(palette)
                strokeAlpha = 1.0
                strokeWidth = sharedGuideStrokeWidth
                fillColor = SKColor.clear
                glowWidth = usesNeonGridTheme(palette) ? max(layout.tileSize * 0.010, 0.5) : 0
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
                glowWidth = max(layout.tileSize * 0.018, 0.8)
                zPosition = 1.18
            case .dungeonExitLocked:
                baseColor = usesNeonGridTheme(palette)
                    ? SKColor(red: 0.18, green: 0.23, blue: 0.28, alpha: 1.0)
                    : SKColor(red: 0.45, green: 0.47, blue: 0.50, alpha: 1.0)
                strokeAlpha = 0.98
                strokeWidth = max(layout.tileSize * 0.06, 2.2)
                fillColor = baseColor.withAlphaComponent(0.28)
                glowWidth = max(layout.tileSize * 0.012, 0.6)
                zPosition = 1.18
            case .dungeonKey:
                baseColor = palette.boardDungeonKey
                strokeAlpha = 0
                strokeWidth = 0
                fillColor = baseColor.withAlphaComponent(0.88)
                glowWidth = max(layout.tileSize * 0.012, 0.5)
                zPosition = 1.16
            case .dungeonFloorStartExitTarget:
                baseColor = palette.boardWarpHighlight
                strokeAlpha = 0.98
                strokeWidth = max(layout.tileSize * 0.070, 2.6)
                fillColor = baseColor.withAlphaComponent(0.10)
                glowWidth = max(layout.tileSize * 0.085, 3.0)
                zPosition = 1.28
            case .dungeonFloorStartKeyTarget:
                baseColor = palette.boardDungeonKey
                strokeAlpha = 0.98
                strokeWidth = max(layout.tileSize * 0.070, 2.6)
                fillColor = baseColor.withAlphaComponent(0.10)
                glowWidth = max(layout.tileSize * 0.085, 3.0)
                zPosition = 1.28
            case .dungeonEnemy:
                baseColor = palette.boardDungeonEnemy
                strokeAlpha = 0.95
                strokeWidth = max(layout.tileSize * 0.055, 2.2)
                fillColor = baseColor.withAlphaComponent(0.32)
                zPosition = 1.17
            case .dungeonDanger:
                baseColor = palette.boardDungeonDanger
                strokeAlpha = 0
                strokeWidth = 0
                fillColor = baseColor.withAlphaComponent(0.16)
                zPosition = 1.05
            case .dungeonEnemyWarning:
                baseColor = palette.boardDungeonWarning
                strokeAlpha = 0.94
                strokeWidth = max(layout.tileSize * 0.052, 1.7)
                fillColor = baseColor.withAlphaComponent(0.18)
                glowWidth = max(layout.tileSize * 0.018, 0.8)
                zPosition = 1.06
            case .dungeonCardPickup:
                baseColor = palette.boardDungeonCardPickup
                strokeAlpha = 0
                strokeWidth = 0
                fillColor = baseColor.withAlphaComponent(0.82)
                glowWidth = max(layout.tileSize * 0.010, 0.5)
                zPosition = 1.14
            case .dungeonSpecialPickup:
                baseColor = palette.boardDungeonCardPickup
                strokeAlpha = 0.88
                strokeWidth = max(layout.tileSize * 0.038, 1.2)
                fillColor = baseColor.withAlphaComponent(0.72)
                glowWidth = max(layout.tileSize * 0.014, 0.6)
                zPosition = 1.145
            case .dungeonRelicPickup:
                baseColor = palette.boardDungeonRelicPickup
                strokeAlpha = 0.92
                strokeWidth = max(layout.tileSize * 0.035, 1.2)
                fillColor = baseColor.withAlphaComponent(0.82)
                glowWidth = max(layout.tileSize * 0.014, 0.6)
                zPosition = 1.15
            case .dungeonSuspiciousRelicPickup:
                baseColor = palette.boardDungeonSuspiciousRelicPickup
                strokeAlpha = 0.96
                strokeWidth = max(layout.tileSize * 0.045, 1.4)
                fillColor = baseColor.withAlphaComponent(0.78)
                glowWidth = max(layout.tileSize * 0.016, 0.7)
                zPosition = 1.155
            case .dungeonDamageTrap, .dungeonStrongDamageTrap:
                baseColor = palette.boardDungeonDamageTrap
                if kind == .dungeonStrongDamageTrap {
                    baseColor = SKColor(red: 0.98, green: 0.05, blue: 0.03, alpha: 1.0)
                }
                strokeAlpha = 0
                strokeWidth = 0
                fillColor = baseColor.withAlphaComponent(kind == .dungeonStrongDamageTrap ? 0.90 : 0.76)
                glowWidth = max(layout.tileSize * (kind == .dungeonStrongDamageTrap ? 0.018 : 0.010), 0.5)
                zPosition = 1.13
            case .dungeonHpHalvingTrap:
                baseColor = palette.boardDungeonHpHalvingTrap
                strokeAlpha = 0.88
                strokeWidth = max(layout.tileSize * 0.035, 1.2)
                fillColor = baseColor.withAlphaComponent(0.66)
                glowWidth = max(layout.tileSize * 0.012, 0.5)
                zPosition = 1.132
            case .dungeonLavaTile, .dungeonStrongLavaTile:
                baseColor = palette.boardDungeonLavaTile
                if kind == .dungeonStrongLavaTile {
                    baseColor = SKColor(red: 1.0, green: 0.10, blue: 0.00, alpha: 1.0)
                }
                strokeAlpha = kind == .dungeonStrongLavaTile ? 0.94 : 0.82
                strokeWidth = max(layout.tileSize * (kind == .dungeonStrongLavaTile ? 0.045 : 0.035), 1.2)
                fillColor = baseColor.withAlphaComponent(kind == .dungeonStrongLavaTile ? 0.92 : 0.80)
                glowWidth = max(layout.tileSize * (kind == .dungeonStrongLavaTile ? 0.022 : 0.014), 0.6)
                zPosition = 1.135
            case .dungeonHealingTile:
                baseColor = palette.boardDungeonHealingTile
                strokeAlpha = 0
                strokeWidth = 0
                fillColor = baseColor.withAlphaComponent(0.72)
                glowWidth = max(layout.tileSize * 0.010, 0.5)
                zPosition = 1.13
            case .dungeonCrackedFloor:
                baseColor = usesNeonGridTheme(palette)
                    ? palette.boardDungeonWarning
                    : SKColor(red: 0.95, green: 0.60, blue: 0.12, alpha: 1.0)
                strokeAlpha = 0.92
                strokeWidth = max(layout.tileSize * 0.045, 1.4)
                fillColor = SKColor.clear
                zPosition = 1.07
            case .dungeonCollapsedFloor:
                baseColor = usesNeonGridTheme(palette)
                    ? SKColor(red: 0.08, green: 0.16, blue: 0.22, alpha: 1.0)
                    : SKColor(red: 0.94, green: 0.88, blue: 0.72, alpha: 1.0)
                strokeAlpha = 0.92
                strokeWidth = max(layout.tileSize * 0.045, 1.4)
                fillColor = usesNeonGridTheme(palette)
                    ? SKColor(red: 0.02, green: 0.05, blue: 0.07, alpha: 0.70)
                    : SKColor(red: 0.03, green: 0.035, blue: 0.045, alpha: 0.86)
                zPosition = 1.09
            }

            if usesNeonGridTheme(palette) {
                applyNeonPictogramTuning(
                    kind: kind,
                    tileSize: layout.tileSize,
                    baseColor: &baseColor,
                    strokeAlpha: &strokeAlpha,
                    strokeWidth: &strokeWidth,
                    fillColor: &fillColor,
                    glowWidth: &glowWidth
                )
            }

            if isHiddenDarknessCandidate(kind: kind, point: point, visiblePoints: visiblePoints) {
                usesDarknessCandidateStyle = true
                switch kind {
                case .dungeonBasicMove:
                    baseColor = SKColor(red: 1.0, green: 0.78, blue: 0.34, alpha: 1.0)
                    fillColor = baseColor.withAlphaComponent(0.11)
                case .guideSingleCandidate,
                     .guideDirectTwoStepCandidate,
                     .guideMultipleCandidate,
                     .guideMultiStepCandidate,
                     .guideWarpCandidate:
                    if fillColor.isClearForHighlightRendering {
                        fillColor = baseColor.withAlphaComponent(0.08)
                    }
                default:
                    break
                }
                strokeAlpha = max(strokeAlpha, 0.96)
                strokeWidth = max(strokeWidth * 1.18, sharedGuideStrokeWidth + 0.7)
                glowWidth = max(layout.tileSize * 0.045, 1.6)
                zPosition += 0.03
            }

            if areFlySuppressedDungeonHazardsMuted && isFlySuppressedDungeonHazard(kind) {
                fillColor = fillColor.withAlphaComponent(0.22)
                strokeAlpha = min(strokeAlpha, 0.35)
                glowWidth = 0
                zPosition -= 0.02
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
            node.glowWidth = glowWidth
            node.lineJoin = usesDarknessCandidateStyle ? .round : .miter
            node.miterLimit = 2.5
            node.lineCap = usesDarknessCandidateStyle
                || kind == .dungeonCrackedFloor
                || kind == .dungeonEnemyWarning ? .round : .square
            node.position = layout.position(for: point)
            node.zPosition = zPosition
            node.isAntialiased = usesDarknessCandidateStyle
                || kind == .dungeonExit
                || kind == .dungeonExitLocked
                || kind == .dungeonKey
                || kind == .dungeonFloorStartExitTarget
                || kind == .dungeonFloorStartKeyTarget
                || kind == .dungeonEnemy
                || kind == .dungeonEnemyWarning
                || kind == .dungeonCardPickup
                || kind == .dungeonRelicPickup
                || kind == .dungeonSuspiciousRelicPickup
                || kind == .dungeonDamageTrap
                || kind == .dungeonStrongDamageTrap
                || kind == .dungeonHpHalvingTrap
                || kind == .dungeonLavaTile
                || kind == .dungeonStrongLavaTile
                || kind == .dungeonHealingTile
                || kind == .dungeonCrackedFloor
                || kind == .dungeonCollapsedFloor
            node.blendMode = .alpha
        }

        private func isFlySuppressedDungeonHazard(_ kind: BoardHighlightKind) -> Bool {
            switch kind {
            case .dungeonDamageTrap,
                 .dungeonStrongDamageTrap,
                 .dungeonHpHalvingTrap,
                 .dungeonLavaTile,
                 .dungeonStrongLavaTile,
                 .dungeonCrackedFloor,
                 .dungeonCollapsedFloor:
                return true
            default:
                return false
            }
        }

        private func isHiddenDarknessCandidate(
            kind: BoardHighlightKind,
            point: GridPoint,
            visiblePoints: Set<GridPoint>?
        ) -> Bool {
            guard let visiblePoints, !visiblePoints.contains(point) else { return false }
            switch kind {
            case .guideSingleCandidate,
                 .guideDirectTwoStepCandidate,
                 .guideMultipleCandidate,
                 .guideMultiStepCandidate,
                 .guideWarpCandidate,
                 .dungeonBasicMove:
                return true
            default:
                return false
            }
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
            case .dungeonFloorStartExitTarget, .dungeonFloorStartKeyTarget:
                return CGPath(ellipseIn: rect.insetBy(dx: tileSize * 0.04, dy: tileSize * 0.04), transform: nil)
            case .dungeonEnemy:
                return targetMarkerPath(
                    center: CGPoint(x: rect.midX, y: rect.midY),
                    tileSize: tileSize,
                    scale: 1.0
                )
            case .guideSingleCandidate,
                 .guideDirectTwoStepCandidate,
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
            case .dungeonSpecialPickup:
                return handExpansionPickupMarkerPath(center: CGPoint(x: rect.midX, y: rect.midY), tileSize: tileSize)
            case .dungeonRelicPickup:
                return relicPickupMarkerPath(center: CGPoint(x: rect.midX, y: rect.midY), tileSize: tileSize)
            case .dungeonSuspiciousRelicPickup:
                return suspiciousRelicPickupMarkerPath(center: CGPoint(x: rect.midX, y: rect.midY), tileSize: tileSize)
            case .dungeonDamageTrap, .dungeonStrongDamageTrap:
                return damageTrapMarkerPath(center: CGPoint(x: rect.midX, y: rect.midY), tileSize: tileSize)
            case .dungeonHpHalvingTrap:
                return hpHalvingTrapMarkerPath(center: CGPoint(x: rect.midX, y: rect.midY), tileSize: tileSize)
            case .dungeonLavaTile, .dungeonStrongLavaTile:
                return lavaTileMarkerPath(center: CGPoint(x: rect.midX, y: rect.midY), tileSize: tileSize)
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
            let size = min(rect.width, rect.height)
            let coreRadius = size * 0.20
            let streakLength = size * 0.24
            let streakOffset = size * 0.18

            path.move(to: CGPoint(x: center.x, y: center.y + coreRadius))
            path.addLine(to: CGPoint(x: center.x + coreRadius, y: center.y))
            path.addLine(to: CGPoint(x: center.x, y: center.y - coreRadius))
            path.addLine(to: CGPoint(x: center.x - coreRadius, y: center.y))
            path.closeSubpath()

            path.move(to: CGPoint(x: center.x - streakOffset, y: center.y + streakOffset + streakLength))
            path.addLine(to: CGPoint(x: center.x - coreRadius * 0.36, y: center.y + coreRadius * 0.36))
            path.move(to: CGPoint(x: center.x, y: center.y + streakOffset + streakLength * 0.82))
            path.addLine(to: CGPoint(x: center.x, y: center.y + coreRadius * 0.52))
            path.move(to: CGPoint(x: center.x + streakOffset, y: center.y + streakOffset + streakLength))
            path.addLine(to: CGPoint(x: center.x + coreRadius * 0.36, y: center.y + coreRadius * 0.36))

            path.move(to: CGPoint(x: center.x - coreRadius * 0.48, y: center.y - coreRadius * 0.28))
            path.addLine(to: CGPoint(x: center.x + coreRadius * 0.48, y: center.y - coreRadius * 0.28))
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
            return neonDataPanelPath(
                center: center,
                size: CGSize(width: width, height: height),
                cornerCut: tileSize * 0.055
            )
        }

        private func relicPickupMarkerPath(center: CGPoint, tileSize: CGFloat) -> CGPath {
            let width = tileSize * 0.56
            let height = tileSize * 0.34
            let bodyHeight = height * 0.70
            let lidHeight = height * 0.28
            let body = CGRect(x: center.x - width / 2, y: center.y - height * 0.34, width: width, height: bodyHeight)
            let lid = CGRect(x: center.x - width * 0.44, y: body.maxY - height * 0.05, width: width * 0.88, height: lidHeight)
            let path = CGMutablePath()
            path.addPath(neonDataPanelPath(
                center: CGPoint(x: body.midX, y: body.midY),
                size: body.size,
                cornerCut: tileSize * 0.045
            ))
            path.addRoundedRect(
                in: lid,
                cornerWidth: max(tileSize * 0.035, 1.0),
                cornerHeight: max(tileSize * 0.035, 1.0)
            )
            path.addRect(CGRect(x: center.x - width * 0.06, y: body.minY, width: width * 0.12, height: body.height * 0.88))
            path.move(to: CGPoint(x: center.x - width * 0.30, y: lid.midY))
            path.addLine(to: CGPoint(x: center.x + width * 0.30, y: lid.midY))
            path.move(to: CGPoint(x: center.x - width * 0.37, y: body.minY + body.height * 0.28))
            path.addLine(to: CGPoint(x: center.x - width * 0.22, y: body.minY + body.height * 0.28))
            path.move(to: CGPoint(x: center.x + width * 0.22, y: body.minY + body.height * 0.28))
            path.addLine(to: CGPoint(x: center.x + width * 0.37, y: body.minY + body.height * 0.28))
            return path
        }

        private func handExpansionPickupMarkerPath(center: CGPoint, tileSize: CGFloat) -> CGPath {
            let path = CGMutablePath()
            let backSize = CGSize(width: tileSize * 0.30, height: tileSize * 0.38)
            let frontSize = CGSize(width: tileSize * 0.34, height: tileSize * 0.42)
            let cornerCut = tileSize * 0.045
            path.addPath(neonDataPanelPath(
                center: CGPoint(x: center.x - tileSize * 0.07, y: center.y + tileSize * 0.03),
                size: backSize,
                cornerCut: cornerCut
            ))
            path.addPath(neonDataPanelPath(
                center: CGPoint(x: center.x + tileSize * 0.04, y: center.y - tileSize * 0.01),
                size: frontSize,
                cornerCut: cornerCut
            ))
            let plusLength = tileSize * 0.18
            path.move(to: CGPoint(x: center.x, y: center.y - plusLength / 2))
            path.addLine(to: CGPoint(x: center.x, y: center.y + plusLength / 2))
            path.move(to: CGPoint(x: center.x - plusLength / 2, y: center.y))
            path.addLine(to: CGPoint(x: center.x + plusLength / 2, y: center.y))
            return path
        }

        private func suspiciousRelicPickupMarkerPath(center: CGPoint, tileSize: CGFloat) -> CGPath {
            let path = CGMutablePath()
            path.addPath(relicPickupMarkerPath(center: center, tileSize: tileSize))
            let warning = neonWarningChevronPath(center: CGPoint(x: center.x, y: center.y + tileSize * 0.02), tileSize: tileSize)
            path.addPath(warning)
            path.move(to: CGPoint(x: center.x, y: center.y + tileSize * 0.11))
            path.addLine(to: CGPoint(x: center.x, y: center.y - tileSize * 0.04))
            path.move(to: CGPoint(x: center.x, y: center.y - tileSize * 0.09))
            path.addLine(to: CGPoint(x: center.x, y: center.y - tileSize * 0.105))
            return path
        }

        private func damageTrapMarkerPath(center: CGPoint, tileSize: CGFloat) -> CGPath {
            let halfWidth = tileSize * 0.34
            let topY = center.y + tileSize * 0.24
            let midY = center.y - tileSize * 0.02
            let bottomY = center.y - tileSize * 0.26
            let path = CGMutablePath()
            path.move(to: CGPoint(x: center.x - halfWidth, y: bottomY))
            path.addLine(to: CGPoint(x: center.x - halfWidth * 0.78, y: topY))
            path.addLine(to: CGPoint(x: center.x - halfWidth * 0.28, y: midY))
            path.addLine(to: CGPoint(x: center.x, y: topY))
            path.addLine(to: CGPoint(x: center.x + halfWidth * 0.28, y: midY))
            path.addLine(to: CGPoint(x: center.x + halfWidth * 0.78, y: topY))
            path.addLine(to: CGPoint(x: center.x + halfWidth, y: bottomY))
            path.addLine(to: CGPoint(x: center.x + halfWidth * 0.42, y: bottomY + tileSize * 0.07))
            path.addLine(to: CGPoint(x: center.x, y: bottomY - tileSize * 0.02))
            path.addLine(to: CGPoint(x: center.x - halfWidth * 0.42, y: bottomY + tileSize * 0.07))
            path.closeSubpath()
            path.move(to: CGPoint(x: center.x - halfWidth * 0.72, y: center.y + tileSize * 0.06))
            path.addLine(to: CGPoint(x: center.x - halfWidth * 0.44, y: center.y - tileSize * 0.04))
            path.move(to: CGPoint(x: center.x + halfWidth * 0.72, y: center.y + tileSize * 0.06))
            path.addLine(to: CGPoint(x: center.x + halfWidth * 0.44, y: center.y - tileSize * 0.04))
            return path
        }

        private func hpHalvingTrapMarkerPath(center: CGPoint, tileSize: CGFloat) -> CGPath {
            let radius = tileSize * 0.31
            let path = CGMutablePath()
            path.move(to: CGPoint(x: center.x, y: center.y + radius))
            path.addLine(to: CGPoint(x: center.x + radius, y: center.y))
            path.addLine(to: CGPoint(x: center.x, y: center.y - radius))
            path.addLine(to: CGPoint(x: center.x - radius, y: center.y))
            path.closeSubpath()
            path.move(to: CGPoint(x: center.x - radius * 0.42, y: center.y + radius * 0.52))
            path.addLine(to: CGPoint(x: center.x + radius * 0.42, y: center.y - radius * 0.52))
            path.move(to: CGPoint(x: center.x - radius * 0.16, y: center.y + radius * 0.18))
            path.addLine(to: CGPoint(x: center.x + radius * 0.16, y: center.y - radius * 0.18))
            return path
        }

        private func neonDataPanelPath(center: CGPoint, size: CGSize, cornerCut: CGFloat) -> CGPath {
            let rect = CGRect(
                x: center.x - size.width / 2,
                y: center.y - size.height / 2,
                width: size.width,
                height: size.height
            )
            let cut = min(cornerCut, min(rect.width, rect.height) * 0.32)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cut))
            path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cut))
            path.closeSubpath()
            return path
        }

        private func neonWarningChevronPath(center: CGPoint, tileSize: CGFloat) -> CGPath {
            let width = tileSize * 0.30
            let height = tileSize * 0.28
            let path = CGMutablePath()
            path.move(to: CGPoint(x: center.x, y: center.y + height / 2))
            path.addLine(to: CGPoint(x: center.x + width / 2, y: center.y - height / 2))
            path.addLine(to: CGPoint(x: center.x - width / 2, y: center.y - height / 2))
            path.closeSubpath()
            return path
        }

        private func lavaTileMarkerPath(center: CGPoint, tileSize: CGFloat) -> CGPath {
            let path = CGMutablePath()
            let baseY = center.y - tileSize * 0.25
            let topY = center.y + tileSize * 0.26
            let halfWidth = tileSize * 0.34
            path.move(to: CGPoint(x: center.x - halfWidth, y: baseY))
            path.addCurve(
                to: CGPoint(x: center.x - tileSize * 0.13, y: topY),
                control1: CGPoint(x: center.x - tileSize * 0.34, y: center.y - tileSize * 0.04),
                control2: CGPoint(x: center.x - tileSize * 0.18, y: center.y + tileSize * 0.06)
            )
            path.addCurve(
                to: CGPoint(x: center.x + tileSize * 0.04, y: center.y + tileSize * 0.05),
                control1: CGPoint(x: center.x - tileSize * 0.06, y: center.y + tileSize * 0.18),
                control2: CGPoint(x: center.x - tileSize * 0.03, y: center.y + tileSize * 0.12)
            )
            path.addCurve(
                to: CGPoint(x: center.x + tileSize * 0.18, y: topY),
                control1: CGPoint(x: center.x + tileSize * 0.18, y: center.y + tileSize * 0.13),
                control2: CGPoint(x: center.x + tileSize * 0.23, y: center.y + tileSize * 0.18)
            )
            path.addCurve(
                to: CGPoint(x: center.x + halfWidth, y: baseY),
                control1: CGPoint(x: center.x + tileSize * 0.36, y: center.y + tileSize * 0.02),
                control2: CGPoint(x: center.x + tileSize * 0.34, y: center.y - tileSize * 0.12)
            )
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

        private func applyNeonPictogramTuning(
            kind: BoardHighlightKind,
            tileSize: CGFloat,
            baseColor: inout SKColor,
            strokeAlpha: inout CGFloat,
            strokeWidth: inout CGFloat,
            fillColor: inout SKColor,
            glowWidth: inout CGFloat
        ) {
            let softGlow = max(tileSize * 0.020, 0.7)
            let strongGlow = max(tileSize * 0.030, 1.0)
            switch kind {
            case .dungeonBasicMove:
                strokeAlpha = 0.98
                glowWidth = max(glowWidth, softGlow)
            case .guideMultiStepPath:
                fillColor = baseColor.withAlphaComponent(0.10)
            case .dungeonExit, .dungeonExitLocked:
                strokeAlpha = 1.0
                fillColor = baseColor.withAlphaComponent(0.18)
                glowWidth = max(glowWidth, strongGlow)
            case .dungeonFloorStartExitTarget, .dungeonFloorStartKeyTarget:
                strokeAlpha = 1.0
                fillColor = baseColor.withAlphaComponent(0.08)
                glowWidth = max(glowWidth, max(tileSize * 0.095, 3.2))
            case .dungeonKey, .dungeonCardPickup, .dungeonSpecialPickup, .dungeonDamageTrap, .dungeonStrongDamageTrap, .dungeonHealingTile:
                strokeAlpha = 0
                strokeWidth = 0
                fillColor = baseColor.withAlphaComponent(
                    kind == .dungeonDamageTrap || kind == .dungeonStrongDamageTrap ? 0.84 : 0.78
                )
                glowWidth = max(glowWidth, softGlow)
            case .dungeonRelicPickup, .dungeonSuspiciousRelicPickup:
                strokeAlpha = 0.96
                fillColor = baseColor.withAlphaComponent(0.66)
                glowWidth = max(glowWidth, softGlow)
            case .dungeonHpHalvingTrap, .dungeonLavaTile, .dungeonStrongLavaTile, .dungeonEnemyWarning:
                strokeAlpha = 0.96
                fillColor = baseColor.withAlphaComponent(0.34)
                glowWidth = max(glowWidth, softGlow)
            case .dungeonDanger:
                fillColor = baseColor.withAlphaComponent(0.13)
            case .dungeonEnemy:
                strokeAlpha = 0.96
                fillColor = baseColor.withAlphaComponent(0.20)
                glowWidth = max(glowWidth, softGlow)
            case .dungeonCrackedFloor:
                strokeAlpha = 0.96
                glowWidth = max(glowWidth, max(tileSize * 0.012, 0.5))
            case .dungeonCollapsedFloor:
                glowWidth = max(glowWidth, max(tileSize * 0.010, 0.5))
            case .guideSingleCandidate,
                 .guideDirectTwoStepCandidate,
                 .guideMultipleCandidate,
                 .guideMultiStepCandidate,
                 .guideWarpCandidate,
                 .forcedSelection:
                glowWidth = max(glowWidth, max(tileSize * 0.014, 0.6))
            }
        }

        private func patrolMovementArrowColor(palette: GameScenePalette) -> SKColor {
            if usesNeonGridTheme(palette) {
                return palette.boardDungeonWarning.withAlphaComponent(0.96)
            }
            return SKColor(red: 1.0, green: 0.82, blue: 0.24, alpha: 0.96)
        }

        private func patrolRailColor(palette: GameScenePalette) -> SKColor {
            if usesNeonGridTheme(palette) {
                return palette.boardDungeonWarning.withAlphaComponent(0.58)
            }
            return SKColor(white: 0.48, alpha: 0.86)
        }

        private func patrolRailLineWidth(tileSize: CGFloat) -> CGFloat {
            return min(max(tileSize * 0.024, 2.0), 2.2)
        }
    }

    private extension SKColor {
        var isClearForHighlightRendering: Bool {
            cgColor.alpha <= 0.01
        }
    }

    private func usesNeonGridTheme(_ palette: GameScenePalette) -> Bool {
        palette.isNeonGridTheme
    }

    private func directMoveGuideColor(_ palette: GameScenePalette) -> SKColor {
        usesNeonGridTheme(palette)
            ? SKColor(white: 0.74, alpha: 1.0)
            : palette.boardTileVisited
    }
#endif
