#if canImport(SpriteKit)
    import SpriteKit
    import SharedSupport

    final class GameSceneHighlightRenderer {
        private(set) var highlightNodes: [BoardHighlightKind: [GridPoint: SKShapeNode]] = [:]
        private var latestSingleGuidePoints: Set<GridPoint> = []
        private var latestMultipleGuidePoints: Set<GridPoint> = []
        private var latestMultiStepGuidePoints: Set<GridPoint> = []
        private var latestWarpGuidePoints: Set<GridPoint> = []
        private var latestTargetApproachPoints: Set<GridPoint> = []
        private var latestTargetCapturePoints: Set<GridPoint> = []
        private var latestForcedSelectionPoints: Set<GridPoint> = []
        private var latestCurrentTargetPoints: Set<GridPoint> = []
        private var latestUpcomingTargetPoints: Set<GridPoint> = []
        private var pendingHighlightPoints: [BoardHighlightKind: Set<GridPoint>] = [:]

        init() {
            reset()
        }

        func reset() {
            for nodes in highlightNodes.values {
                for node in nodes.values {
                    node.removeFromParent()
                }
            }
            highlightNodes = [:]
            latestSingleGuidePoints = []
            latestMultipleGuidePoints = []
            latestMultiStepGuidePoints = []
            latestWarpGuidePoints = []
            latestTargetApproachPoints = []
            latestTargetCapturePoints = []
            latestForcedSelectionPoints = []
            latestCurrentTargetPoints = []
            latestUpcomingTargetPoints = []
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
                        board.contains(point) && board.isTraversable(point)
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
            guard hasPendingValues || hasRenderedHighlights else { return }

            if hasPendingValues {
                applyHighlightsImmediately(snapshot, scene: scene, layout: layout, palette: palette)
            } else if hasRenderedHighlights {
                let latestSnapshot: [BoardHighlightKind: Set<GridPoint>] = [
                    .guideSingleCandidate: latestSingleGuidePoints,
                    .guideMultipleCandidate: latestMultipleGuidePoints,
                    .guideMultiStepCandidate: latestMultiStepGuidePoints,
                    .guideWarpCandidate: latestWarpGuidePoints,
                    .targetApproachCandidate: latestTargetApproachPoints,
                    .targetCaptureCandidate: latestTargetCapturePoints,
                    .forcedSelection: latestForcedSelectionPoints,
                    .currentTarget: latestCurrentTargetPoints,
                    .upcomingTarget: latestUpcomingTargetPoints,
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
            latestMultiStepGuidePoints = highlights[.guideMultiStepCandidate] ?? []
            latestWarpGuidePoints = highlights[.guideWarpCandidate] ?? []
            latestTargetApproachPoints = highlights[.targetApproachCandidate] ?? []
            latestTargetCapturePoints = highlights[.targetCaptureCandidate] ?? []
            latestForcedSelectionPoints = highlights[.forcedSelection] ?? []
            latestCurrentTargetPoints = highlights[.currentTarget] ?? []
            latestUpcomingTargetPoints = highlights[.upcomingTarget] ?? []
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
            case .guideMultiStepCandidate:
                baseColor = palette.boardMultiStepHighlight
                strokeAlpha = 0.9
                strokeWidth = sharedGuideStrokeWidth
                fillColor = baseColor.withAlphaComponent(0.12)
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
            node.isAntialiased = kind == .currentTarget || kind == .upcomingTarget
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
            case .upcomingTarget:
                return targetMarkerPath(
                    center: CGPoint(x: rect.midX, y: rect.midY),
                    tileSize: tileSize,
                    scale: 1.0
                )
            case .guideSingleCandidate,
                 .guideMultipleCandidate,
                 .guideMultiStepCandidate,
                 .guideWarpCandidate,
                 .targetApproachCandidate,
                 .targetCaptureCandidate,
                 .forcedSelection:
                return CGPath(rect: rect, transform: nil)
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
    }
#endif
