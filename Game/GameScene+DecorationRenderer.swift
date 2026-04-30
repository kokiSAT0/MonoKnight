#if canImport(SpriteKit)
    import SpriteKit
    import SharedSupport

    final class GameSceneDecorationRenderer {
        private struct WarpVisualStyle {
            let color: SKColor
            let circleCount: Int
        }

        private enum MultiVisitTriangle: CaseIterable {
            case top
            case right
            case bottom
            case left

            var nodeName: String {
                switch self {
                case .top: return "multiVisitTriangleTop"
                case .right: return "multiVisitTriangleRight"
                case .bottom: return "multiVisitTriangleBottom"
                case .left: return "multiVisitTriangleLeft"
                }
            }

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

        private struct MultiVisitDecorationCache {
            let container: SKNode
            let segments: [MultiVisitTriangle: SKShapeNode]
            let primaryDiagonal: SKShapeNode
            let secondaryDiagonal: SKShapeNode
        }

        private enum ToggleDecorationTriangle {
            case topLeft
            case bottomRight

            var nodeName: String {
                switch self {
                case .topLeft: return "toggleTriangleTopLeft"
                case .bottomRight: return "toggleTriangleBottomRight"
                }
            }

            func path(tileSize: CGFloat) -> CGPath {
                let half = tileSize / 2
                let path = CGMutablePath()

                switch self {
                case .topLeft:
                    path.move(to: CGPoint(x: -half, y: half))
                    path.addLine(to: CGPoint(x: half, y: half))
                    path.addLine(to: CGPoint(x: -half, y: -half))
                case .bottomRight:
                    path.move(to: CGPoint(x: half, y: -half))
                    path.addLine(to: CGPoint(x: -half, y: -half))
                    path.addLine(to: CGPoint(x: half, y: half))
                }

                path.closeSubpath()
                return path
            }
        }

        private struct ToggleDecorationCache {
            let container: SKNode
            let cover: SKShapeNode
            let topLeftTriangle: SKShapeNode
            let bottomRightTriangle: SKShapeNode
            let diagonal: SKShapeNode
        }

        private struct TileEffectDecorationCache {
            let container: SKNode
            var effect: TileEffect
            var strokeNodes: [SKShapeNode]
            var fillNodes: [SKShapeNode]
        }

        private(set) var tileNodes: [GridPoint: SKShapeNode] = [:]
        private var tileMultiVisitDecorations: [GridPoint: MultiVisitDecorationCache] = [:]
        private var tileToggleDecorations: [GridPoint: ToggleDecorationCache] = [:]
        private var tileEffectDecorations: [GridPoint: TileEffectDecorationCache] = [:]
        private var warpVisualStyles: [String: WarpVisualStyle] = [:]
        private let maxWarpCircleLayers = 4

        func reset() {
            removeAllNodes()
            warpVisualStyles = [:]
        }

        func refreshWarpVisualStyles(board: Board, palette: GameScenePalette) {
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
                let color = warpAccentColor(for: index, palette: palette)
                let circleCount = max(1, min(maxWarpCircleLayers, index + 1))
                updatedStyles[pairID] = WarpVisualStyle(color: color, circleCount: circleCount)
            }
            warpVisualStyles = updatedStyles
        }

        func setupGrid(
            in scene: SKScene,
            board: Board,
            palette: GameScenePalette,
            layout: GameSceneLayoutSupport,
            showsVisitedTileFill: Bool
        ) {
            guard layout.tileSize > 0 else { return }

            for y in 0..<board.size {
                for x in 0..<board.size {
                    let node = SKShapeNode(
                        rectOf: CGSize(width: layout.tileSize, height: layout.tileSize))
                    node.isAntialiased = false
                    node.lineJoin = .miter
                    let point = GridPoint(x: x, y: y)
                    node.position = layout.position(for: point)
                    scene.addChild(node)
                    tileNodes[point] = node
                    configureTileNodeAppearance(
                        node,
                        at: point,
                        board: board,
                        palette: palette,
                        layout: layout,
                        showsVisitedTileFill: showsVisitedTileFill
                    )
                }
            }

            debugLog(
                "GameScene.setupGrid: 生成タイル数=\(tileNodes.count), tileSize=\(layout.tileSize)"
            )
        }

        func relayoutTileNodes(
            board: Board,
            palette: GameScenePalette,
            layout: GameSceneLayoutSupport,
            showsVisitedTileFill: Bool
        ) {
            guard layout.tileSize > 0 else { return }

            for (point, node) in tileNodes {
                let rect = CGRect(
                    x: -layout.tileSize / 2,
                    y: -layout.tileSize / 2,
                    width: layout.tileSize,
                    height: layout.tileSize
                )
                node.path = CGPath(rect: rect, transform: nil)
                node.position = layout.position(for: point)
                configureTileNodeAppearance(
                    node,
                    at: point,
                    board: board,
                    palette: palette,
                    layout: layout,
                    showsVisitedTileFill: showsVisitedTileFill
                )
            }
        }

        func removeAllNodes() {
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
        }

        func updateBoardAppearance(
            board: Board,
            palette: GameScenePalette,
            layout: GameSceneLayoutSupport,
            showsVisitedTileFill: Bool
        ) {
            guard layout.tileSize > 0 else { return }

            for (point, node) in tileNodes {
                configureTileNodeAppearance(
                    node,
                    at: point,
                    board: board,
                    palette: palette,
                    layout: layout,
                    showsVisitedTileFill: showsVisitedTileFill
                )
            }
        }

        func warpAccentColor(
            at point: GridPoint,
            board: Board,
            palette: GameScenePalette
        ) -> SKColor {
            if case .warp(let pairID, _) = board.effect(at: point) {
                return warpVisualStyle(for: pairID, palette: palette).color
            }
            return palette.boardTileEffectWarp
        }

        private func warpAccentColor(for pairIndex: Int, palette: GameScenePalette) -> SKColor {
            if pairIndex < palette.warpPairAccentColors.count {
                return palette.warpPairAccentColors[pairIndex]
            }

            let fallbackBase = palette.warpPairAccentColors.last ?? palette.boardTileEffectWarp
            let attenuationStep = 0.12 * CGFloat(pairIndex - palette.warpPairAccentColors.count + 1)
            let attenuation = max(0.4, 1.0 - attenuationStep)
            return fallbackBase.withAlphaComponent(attenuation)
        }

        private func warpVisualStyle(for pairID: String, palette: GameScenePalette) -> WarpVisualStyle
        {
            if let cached = warpVisualStyles[pairID] {
                return cached
            }
            let fallback = WarpVisualStyle(color: palette.boardTileEffectWarp, circleCount: 1)
            warpVisualStyles[pairID] = fallback
            return fallback
        }

        private func configureTileNodeAppearance(
            _ node: SKShapeNode,
            at point: GridPoint,
            board: Board,
            palette: GameScenePalette,
            layout: GameSceneLayoutSupport,
            showsVisitedTileFill: Bool
        ) {
            node.fillColor = tileFillColor(
                for: point,
                board: board,
                palette: palette,
                showsVisitedTileFill: showsVisitedTileFill
            )

            guard let state = board.state(at: point) else {
                applySingleVisitStyle(to: node, palette: palette)
                removeMultiVisitDecoration(for: point)
                removeToggleDecoration(for: point)
                removeEffectDecoration(for: point)
                return
            }

            switch state.visitBehavior {
            case .multi:
                applyMultiVisitStyle(
                    to: node,
                    state: state,
                    at: point,
                    palette: palette,
                    layout: layout
                )
                removeToggleDecoration(for: point)
            case .toggle:
                applyToggleStyle(
                    to: node,
                    state: state,
                    at: point,
                    palette: palette,
                    layout: layout
                )
                removeMultiVisitDecoration(for: point)
            case .impassable:
                applyImpassableStyle(to: node)
                removeMultiVisitDecoration(for: point)
                removeToggleDecoration(for: point)
            case .single:
                applySingleVisitStyle(to: node, palette: palette)
                removeMultiVisitDecoration(for: point)
                removeToggleDecoration(for: point)
            }

            updateEffectDecoration(
                for: point,
                parentNode: node,
                effect: state.effect ?? board.effect(at: point),
                palette: palette,
                layout: layout
            )
        }

        private func tileFillColor(
            for point: GridPoint,
            board: Board,
            palette: GameScenePalette,
            showsVisitedTileFill: Bool
        ) -> SKColor {
            guard let state = board.state(at: point) else { return palette.boardTileUnvisited }
            return tileFillColor(
                for: state,
                palette: palette,
                showsVisitedTileFill: showsVisitedTileFill
            )
        }

        private func tileFillColor(
            for state: TileState,
            palette: GameScenePalette,
            showsVisitedTileFill: Bool
        ) -> SKColor {
            switch state.visitBehavior {
            case .impassable:
                return palette.boardTileImpassable
            case .toggle:
                return .clear
            case .multi:
                return .clear
            case .single:
                return state.isVisited && showsVisitedTileFill
                    ? palette.boardTileVisited
                    : palette.boardTileUnvisited
            }
        }

        private func applySingleVisitStyle(to node: SKShapeNode, palette: GameScenePalette) {
            node.strokeColor = palette.boardGridLine
            node.lineWidth = 1
        }

        private func applyMultiVisitStyle(
            to node: SKShapeNode,
            state: TileState,
            at point: GridPoint,
            palette: GameScenePalette,
            layout: GameSceneLayoutSupport
        ) {
            node.strokeColor = palette.boardTileMultiStroke
            node.lineWidth = 1
            updateMultiVisitDecoration(
                for: point,
                parentNode: node,
                state: state,
                palette: palette,
                layout: layout
            )
        }

        private func applyToggleStyle(
            to node: SKShapeNode,
            state: TileState,
            at point: GridPoint,
            palette: GameScenePalette,
            layout: GameSceneLayoutSupport
        ) {
            node.strokeColor = palette.boardTileMultiStroke
            node.lineWidth = 1
            updateToggleDecoration(
                for: point,
                parentNode: node,
                state: state,
                palette: palette,
                layout: layout
            )
        }

        private func applyImpassableStyle(to node: SKShapeNode) {
            node.strokeColor = .clear
            node.lineWidth = 0
            node.glowWidth = 0
        }

        private func updateMultiVisitDecoration(
            for point: GridPoint,
            parentNode: SKShapeNode,
            state: TileState,
            palette: GameScenePalette,
            layout: GameSceneLayoutSupport
        ) {
            let decoration: MultiVisitDecorationCache

            if let cached = tileMultiVisitDecorations[point] {
                decoration = cached
            } else {
                let container = SKNode()
                container.name = "multiVisitDecorationContainer"
                container.zPosition = 0.14

                var segments: [MultiVisitTriangle: SKShapeNode] = [:]
                for triangle in MultiVisitTriangle.allCases {
                    let segmentNode = SKShapeNode()
                    segmentNode.name = triangle.nodeName
                    segmentNode.strokeColor = .clear
                    segmentNode.lineWidth = 0
                    segmentNode.isAntialiased = true
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

            decoration.container.position = .zero

            for triangle in MultiVisitTriangle.allCases {
                decoration.segments[triangle]?.path = triangle.path(tileSize: layout.tileSize)
            }

            let totalSegmentCount = MultiVisitTriangle.allCases.count
            let requiredVisits = max(0, state.requiredVisitCount)
            if requiredVisits > totalSegmentCount {
                debugLog(
                    "GameScene.updateMultiVisitDecoration 警告: 対応上限を超える踏破回数を検出 point=\(point) required=\(requiredVisits)"
                )
            }

            let clampedRemaining = max(0, min(state.remainingVisits, totalSegmentCount))
            let filledSegmentCount = max(
                0, min(totalSegmentCount, totalSegmentCount - clampedRemaining))
            let activeSegmentCount = totalSegmentCount
            let isCompleted = state.isVisited || clampedRemaining == 0
            let shouldShowProgress = requiredVisits > 1

            if !shouldShowProgress {
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

            decoration.container.isHidden = false
            decoration.primaryDiagonal.isHidden = false
            decoration.secondaryDiagonal.isHidden = false

            let completedColor = palette.boardTileVisited
            let pendingColor = palette.boardTileUnvisited

            for (index, triangle) in MultiVisitTriangle.allCases.enumerated() {
                guard let segmentNode = decoration.segments[triangle] else { continue }
                segmentNode.fillColor = index < filledSegmentCount ? completedColor : pendingColor
                segmentNode.alpha = 1.0
                segmentNode.isHidden = index >= activeSegmentCount
            }

            let half = layout.tileSize / 2
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

        private func removeMultiVisitDecoration(for point: GridPoint) {
            guard let decoration = tileMultiVisitDecorations.removeValue(forKey: point) else {
                return
            }
            decoration.container.removeAllActions()
            decoration.container.removeFromParent()
        }

        private func removeToggleDecoration(for point: GridPoint) {
            guard let decoration = tileToggleDecorations.removeValue(forKey: point) else { return }
            decoration.container.removeAllActions()
            decoration.container.removeFromParent()
        }

        private func removeEffectDecoration(for point: GridPoint) {
            guard let decoration = tileEffectDecorations.removeValue(forKey: point) else { return }
            decoration.container.removeAllActions()
            decoration.container.removeFromParent()
        }

        private func updateToggleDecoration(
            for point: GridPoint,
            parentNode: SKShapeNode,
            state: TileState,
            palette: GameScenePalette,
            layout: GameSceneLayoutSupport
        ) {
            let decoration: ToggleDecorationCache

            if let cached = tileToggleDecorations[point] {
                decoration = cached
            } else {
                let container = SKNode()
                container.name = "toggleDecorationContainer"
                container.zPosition = 0.13

                let cover = SKShapeNode(rectOf: CGSize(width: layout.tileSize, height: layout.tileSize))
                cover.name = "toggleCover"
                cover.strokeColor = .clear
                cover.isAntialiased = false
                cover.blendMode = .alpha
                cover.zPosition = -0.01
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

            decoration.container.position = .zero
            decoration.container.isHidden = false

            let coverRect = CGRect(
                x: -layout.tileSize / 2,
                y: -layout.tileSize / 2,
                width: layout.tileSize,
                height: layout.tileSize
            )
            decoration.cover.path = CGPath(rect: coverRect, transform: nil)
            decoration.cover.fillColor = .clear
            decoration.cover.alpha = 0.0
            decoration.cover.isHidden = false

            decoration.topLeftTriangle.path = ToggleDecorationTriangle.topLeft.path(
                tileSize: layout.tileSize)
            decoration.bottomRightTriangle.path = ToggleDecorationTriangle.bottomRight.path(
                tileSize: layout.tileSize)

            decoration.bottomRightTriangle.fillColor = palette.boardTileVisited
            decoration.bottomRightTriangle.alpha = 1.0
            decoration.bottomRightTriangle.isHidden = false

            decoration.topLeftTriangle.fillColor =
                state.isVisited ? palette.boardTileVisited : palette.boardTileUnvisited
            decoration.topLeftTriangle.alpha = 1.0
            decoration.topLeftTriangle.isHidden = false

            let half = layout.tileSize / 2
            let diagonalPath = CGMutablePath()
            diagonalPath.move(to: CGPoint(x: half, y: half))
            diagonalPath.addLine(to: CGPoint(x: -half, y: -half))
            decoration.diagonal.path = diagonalPath
            decoration.diagonal.strokeColor = palette.boardTileMultiStroke
            decoration.diagonal.lineWidth = 1
            decoration.diagonal.alpha = 1.0
            decoration.diagonal.isHidden = false
        }

        private func updateEffectDecoration(
            for point: GridPoint,
            parentNode: SKShapeNode,
            effect: TileEffect?,
            palette: GameScenePalette,
            layout: GameSceneLayoutSupport
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
            decoration.container.zPosition = 0.16
            decoration.container.isHidden = false

            configureEffectDecorationGeometry(
                &decoration,
                effect: effect,
                point: point,
                palette: palette,
                layout: layout
            )
            applyEffectDecorationColors(&decoration, effect: effect, palette: palette)
            decoration.effect = effect
            tileEffectDecorations[point] = decoration
        }

        private func makeEffectDecoration(for effect: TileEffect) -> TileEffectDecorationCache {
            let container = SKNode()
            container.name = "tileEffectDecorationContainer"
            container.isHidden = false

            switch effect {
            case .warp:
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
            case .boost:
                let outerChevron = SKShapeNode()
                outerChevron.name = "tileEffectBoostOuterChevron"
                outerChevron.strokeColor = .clear
                outerChevron.fillColor = .clear
                outerChevron.lineWidth = 0
                outerChevron.isAntialiased = true
                outerChevron.blendMode = .alpha

                let innerChevron = SKShapeNode()
                innerChevron.name = "tileEffectBoostInnerChevron"
                innerChevron.strokeColor = .clear
                innerChevron.fillColor = .clear
                innerChevron.lineWidth = 0
                innerChevron.isAntialiased = true
                innerChevron.blendMode = .alpha

                container.addChild(outerChevron)
                container.addChild(innerChevron)
                return TileEffectDecorationCache(
                    container: container,
                    effect: effect,
                    strokeNodes: [],
                    fillNodes: [outerChevron, innerChevron]
                )
            case .slow:
                let stopBar = SKShapeNode()
                stopBar.name = "tileEffectSlowStopBar"
                stopBar.strokeColor = .clear
                stopBar.fillColor = .clear
                stopBar.lineWidth = 0
                stopBar.isAntialiased = true
                stopBar.blendMode = .alpha

                let chevron = SKShapeNode()
                chevron.name = "tileEffectSlowChevron"
                chevron.strokeColor = .clear
                chevron.fillColor = .clear
                chevron.lineWidth = 0
                chevron.isAntialiased = true
                chevron.blendMode = .alpha

                container.addChild(stopBar)
                container.addChild(chevron)
                return TileEffectDecorationCache(
                    container: container,
                    effect: effect,
                    strokeNodes: [],
                    fillNodes: [stopBar, chevron]
                )
            case .nextRefresh:
                let ring = SKShapeNode()
                ring.name = "tileEffectNextRefreshRing"
                ring.strokeColor = .clear
                ring.fillColor = .clear
                ring.lineWidth = 1
                ring.isAntialiased = true
                ring.blendMode = .alpha

                let arrow = SKShapeNode()
                arrow.name = "tileEffectNextRefreshArrow"
                arrow.strokeColor = .clear
                arrow.fillColor = .clear
                arrow.lineWidth = 0
                arrow.isAntialiased = true
                arrow.blendMode = .alpha

                container.addChild(ring)
                container.addChild(arrow)
                return TileEffectDecorationCache(
                    container: container,
                    effect: effect,
                    strokeNodes: [ring],
                    fillNodes: [arrow]
                )
            case .freeFocus:
                let outerRing = SKShapeNode()
                outerRing.name = "tileEffectFreeFocusOuterRing"
                outerRing.strokeColor = .clear
                outerRing.fillColor = .clear
                outerRing.lineWidth = 1
                outerRing.isAntialiased = true
                outerRing.blendMode = .alpha

                let innerDot = SKShapeNode()
                innerDot.name = "tileEffectFreeFocusDot"
                innerDot.strokeColor = .clear
                innerDot.fillColor = .clear
                innerDot.lineWidth = 0
                innerDot.isAntialiased = true
                innerDot.blendMode = .alpha

                container.addChild(outerRing)
                container.addChild(innerDot)
                return TileEffectDecorationCache(
                    container: container,
                    effect: effect,
                    strokeNodes: [outerRing],
                    fillNodes: [innerDot]
                )
            case .preserveCard:
                let card = SKShapeNode()
                card.name = "tileEffectPreserveCardBody"
                card.strokeColor = .clear
                card.fillColor = .clear
                card.lineWidth = 1
                card.isAntialiased = true
                card.blendMode = .alpha

                let notch = SKShapeNode()
                notch.name = "tileEffectPreserveCardNotch"
                notch.strokeColor = .clear
                notch.fillColor = .clear
                notch.lineWidth = 0
                notch.isAntialiased = true
                notch.blendMode = .alpha

                container.addChild(card)
                container.addChild(notch)
                return TileEffectDecorationCache(
                    container: container,
                    effect: effect,
                    strokeNodes: [card],
                    fillNodes: [notch]
                )
            case .draft:
                let rearCard = SKShapeNode()
                rearCard.name = "tileEffectDraftRearCard"
                rearCard.strokeColor = .clear
                rearCard.fillColor = .clear
                rearCard.lineWidth = 1
                rearCard.isAntialiased = true
                rearCard.blendMode = .alpha

                let frontCard = SKShapeNode()
                frontCard.name = "tileEffectDraftFrontCard"
                frontCard.strokeColor = .clear
                frontCard.fillColor = .clear
                frontCard.lineWidth = 1
                frontCard.isAntialiased = true
                frontCard.blendMode = .alpha

                let arrow = SKShapeNode()
                arrow.name = "tileEffectDraftArrow"
                arrow.strokeColor = .clear
                arrow.fillColor = .clear
                arrow.lineWidth = 0
                arrow.isAntialiased = true
                arrow.blendMode = .alpha

                container.addChild(rearCard)
                container.addChild(frontCard)
                container.addChild(arrow)
                return TileEffectDecorationCache(
                    container: container,
                    effect: effect,
                    strokeNodes: [rearCard, frontCard],
                    fillNodes: [arrow]
                )
            case .overload:
                let ring = SKShapeNode()
                ring.name = "tileEffectOverloadRing"
                ring.strokeColor = .clear
                ring.fillColor = .clear
                ring.lineWidth = 1
                ring.isAntialiased = true
                ring.blendMode = .alpha

                let bolt = SKShapeNode()
                bolt.name = "tileEffectOverloadBolt"
                bolt.strokeColor = .clear
                bolt.fillColor = .clear
                bolt.lineWidth = 0
                bolt.isAntialiased = true
                bolt.blendMode = .alpha

                container.addChild(ring)
                container.addChild(bolt)
                return TileEffectDecorationCache(
                    container: container,
                    effect: effect,
                    strokeNodes: [ring],
                    fillNodes: [bolt]
                )
            case .targetSwap:
                let currentTarget = SKShapeNode()
                currentTarget.name = "tileEffectTargetSwapCurrent"
                currentTarget.strokeColor = .clear
                currentTarget.fillColor = .clear
                currentTarget.lineWidth = 1
                currentTarget.isAntialiased = true
                currentTarget.blendMode = .alpha

                let nextTarget = SKShapeNode()
                nextTarget.name = "tileEffectTargetSwapNext"
                nextTarget.strokeColor = .clear
                nextTarget.fillColor = .clear
                nextTarget.lineWidth = 1
                nextTarget.isAntialiased = true
                nextTarget.blendMode = .alpha

                let arrow = SKShapeNode()
                arrow.name = "tileEffectTargetSwapArrow"
                arrow.strokeColor = .clear
                arrow.fillColor = .clear
                arrow.lineWidth = 0
                arrow.isAntialiased = true
                arrow.blendMode = .alpha

                container.addChild(currentTarget)
                container.addChild(nextTarget)
                container.addChild(arrow)
                return TileEffectDecorationCache(
                    container: container,
                    effect: effect,
                    strokeNodes: [currentTarget, nextTarget],
                    fillNodes: [arrow]
                )
            case .openGate:
                let frame = SKShapeNode()
                frame.name = "tileEffectOpenGateFrame"
                frame.strokeColor = .clear
                frame.fillColor = .clear
                frame.lineWidth = 1
                frame.isAntialiased = true
                frame.blendMode = .alpha

                let door = SKShapeNode()
                door.name = "tileEffectOpenGateDoor"
                door.strokeColor = .clear
                door.fillColor = .clear
                door.lineWidth = 1
                door.isAntialiased = true
                door.blendMode = .alpha

                let keyhole = SKShapeNode()
                keyhole.name = "tileEffectOpenGateKeyhole"
                keyhole.strokeColor = .clear
                keyhole.fillColor = .clear
                keyhole.lineWidth = 0
                keyhole.isAntialiased = true
                keyhole.blendMode = .alpha

                container.addChild(frame)
                container.addChild(door)
                container.addChild(keyhole)
                return TileEffectDecorationCache(
                    container: container,
                    effect: effect,
                    strokeNodes: [frame, door],
                    fillNodes: [keyhole]
                )
            }
        }

        private func configureEffectDecorationGeometry(
            _ decoration: inout TileEffectDecorationCache,
            effect: TileEffect,
            point: GridPoint,
            palette: GameScenePalette,
            layout: GameSceneLayoutSupport
        ) {
            switch effect {
            case .warp(let pairID, _):
                let style = warpVisualStyle(for: pairID, palette: palette)
                let desiredCircleCount = max(1, style.circleCount)

                if !decoration.fillNodes.isEmpty {
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

                let baseRadius = layout.tileSize * 0.34
                let spacing = layout.tileSize * 0.06
                for (index, circle) in decoration.strokeNodes.enumerated() {
                    let radius = max(layout.tileSize * 0.14, baseRadius - CGFloat(index) * spacing)
                    let rect = CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
                    circle.path = CGPath(ellipseIn: rect, transform: nil)
                    circle.lineWidth = max(1.0, layout.tileSize * 0.035)
                    circle.position = .zero
                }
            case .shuffleHand:
                guard let diamond = decoration.strokeNodes.first,
                      decoration.fillNodes.count >= 2
                else { return }

                let diamondRadius = layout.tileSize * 0.34
                let diamondPath = CGMutablePath()
                diamondPath.move(to: CGPoint(x: 0, y: diamondRadius))
                diamondPath.addLine(to: CGPoint(x: diamondRadius, y: 0))
                diamondPath.addLine(to: CGPoint(x: 0, y: -diamondRadius))
                diamondPath.addLine(to: CGPoint(x: -diamondRadius, y: 0))
                diamondPath.closeSubpath()
                diamond.path = diamondPath
                diamond.lineWidth = max(1.0, layout.tileSize * 0.05)

                let arrowLength = layout.tileSize * 0.24
                let arrowWidth = layout.tileSize * 0.16

                let leftArrow = decoration.fillNodes[0]
                let leftPath = CGMutablePath()
                leftPath.move(to: CGPoint(x: -arrowLength / 2, y: 0))
                leftPath.addLine(to: CGPoint(x: arrowLength / 2, y: arrowWidth / 2))
                leftPath.addLine(to: CGPoint(x: arrowLength / 2, y: -arrowWidth / 2))
                leftPath.closeSubpath()
                leftArrow.path = leftPath
                leftArrow.position = CGPoint(x: -layout.tileSize * 0.08, y: 0)
                leftArrow.zRotation = .pi / 4

                let rightArrow = decoration.fillNodes[1]
                let rightPath = CGMutablePath()
                rightPath.move(to: CGPoint(x: arrowLength / 2, y: 0))
                rightPath.addLine(to: CGPoint(x: -arrowLength / 2, y: arrowWidth / 2))
                rightPath.addLine(to: CGPoint(x: -arrowLength / 2, y: -arrowWidth / 2))
                rightPath.closeSubpath()
                rightArrow.path = rightPath
                rightArrow.position = CGPoint(x: layout.tileSize * 0.08, y: 0)
                rightArrow.zRotation = -.pi / 4
            case .boost:
                guard decoration.fillNodes.count >= 2 else { return }

                let outerChevron = decoration.fillNodes[0]
                outerChevron.path = boostChevronPath(tileSize: layout.tileSize, scale: 1.0)
                outerChevron.position = CGPoint(x: 0, y: layout.tileSize * 0.08)

                let innerChevron = decoration.fillNodes[1]
                innerChevron.path = boostChevronPath(tileSize: layout.tileSize, scale: 0.72)
                innerChevron.position = CGPoint(x: 0, y: -layout.tileSize * 0.08)
            case .slow:
                guard decoration.fillNodes.count >= 2 else { return }

                let stopBar = decoration.fillNodes[0]
                let barWidth = layout.tileSize * 0.46
                let barHeight = max(layout.tileSize * 0.09, 2.0)
                stopBar.path = CGPath(
                    roundedRect: CGRect(
                        x: -barWidth / 2,
                        y: -barHeight / 2,
                        width: barWidth,
                        height: barHeight
                    ),
                    cornerWidth: barHeight * 0.35,
                    cornerHeight: barHeight * 0.35,
                    transform: nil
                )
                stopBar.position = CGPoint(x: 0, y: layout.tileSize * 0.16)

                let chevron = decoration.fillNodes[1]
                chevron.path = boostChevronPath(tileSize: layout.tileSize, scale: 0.82)
                chevron.position = CGPoint(x: 0, y: -layout.tileSize * 0.10)
                chevron.zRotation = .pi
            case .nextRefresh:
                guard let ring = decoration.strokeNodes.first,
                      let arrow = decoration.fillNodes.first
                else { return }

                let radius = layout.tileSize * 0.26
                ring.path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), transform: nil)
                ring.lineWidth = max(1.0, layout.tileSize * 0.045)
                ring.position = .zero

                arrow.path = trianglePath(width: layout.tileSize * 0.20, height: layout.tileSize * 0.18)
                arrow.position = CGPoint(x: layout.tileSize * 0.20, y: layout.tileSize * 0.05)
                arrow.zRotation = -.pi / 5
            case .freeFocus:
                guard let outerRing = decoration.strokeNodes.first,
                      let innerDot = decoration.fillNodes.first
                else { return }

                let radius = layout.tileSize * 0.30
                outerRing.path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), transform: nil)
                outerRing.lineWidth = max(1.0, layout.tileSize * 0.045)
                outerRing.position = .zero

                let dotRadius = layout.tileSize * 0.095
                innerDot.path = CGPath(ellipseIn: CGRect(x: -dotRadius, y: -dotRadius, width: dotRadius * 2, height: dotRadius * 2), transform: nil)
                innerDot.position = .zero
            case .preserveCard:
                guard let card = decoration.strokeNodes.first,
                      let notch = decoration.fillNodes.first
                else { return }

                let cardWidth = layout.tileSize * 0.42
                let cardHeight = layout.tileSize * 0.54
                let rect = CGRect(x: -cardWidth / 2, y: -cardHeight / 2, width: cardWidth, height: cardHeight)
                card.path = CGPath(roundedRect: rect, cornerWidth: layout.tileSize * 0.04, cornerHeight: layout.tileSize * 0.04, transform: nil)
                card.lineWidth = max(1.0, layout.tileSize * 0.045)
                card.position = .zero

                notch.path = CGPath(
                    roundedRect: CGRect(
                        x: -layout.tileSize * 0.15,
                        y: -layout.tileSize * 0.035,
                        width: layout.tileSize * 0.30,
                        height: layout.tileSize * 0.07
                    ),
                    cornerWidth: layout.tileSize * 0.02,
                    cornerHeight: layout.tileSize * 0.02,
                    transform: nil
                )
                notch.position = CGPoint(x: 0, y: layout.tileSize * 0.12)
            case .draft:
                guard decoration.strokeNodes.count >= 2,
                      let arrow = decoration.fillNodes.first
                else { return }

                let cardWidth = layout.tileSize * 0.34
                let cardHeight = layout.tileSize * 0.44
                let corner = layout.tileSize * 0.035
                let rect = CGRect(x: -cardWidth / 2, y: -cardHeight / 2, width: cardWidth, height: cardHeight)

                let rearCard = decoration.strokeNodes[0]
                rearCard.path = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
                rearCard.lineWidth = max(1.0, layout.tileSize * 0.04)
                rearCard.position = CGPoint(x: -layout.tileSize * 0.10, y: layout.tileSize * 0.05)
                rearCard.zRotation = -.pi / 14

                let frontCard = decoration.strokeNodes[1]
                frontCard.path = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
                frontCard.lineWidth = max(1.0, layout.tileSize * 0.045)
                frontCard.position = CGPoint(x: layout.tileSize * 0.08, y: -layout.tileSize * 0.04)
                frontCard.zRotation = .pi / 16

                arrow.path = trianglePath(width: layout.tileSize * 0.18, height: layout.tileSize * 0.16)
                arrow.position = CGPoint(x: layout.tileSize * 0.22, y: layout.tileSize * 0.17)
                arrow.zRotation = -.pi / 7
            case .overload:
                guard let ring = decoration.strokeNodes.first,
                      let bolt = decoration.fillNodes.first
                else { return }

                let radius = layout.tileSize * 0.31
                ring.path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), transform: nil)
                ring.lineWidth = max(1.0, layout.tileSize * 0.045)
                ring.position = .zero

                bolt.path = overloadBoltPath(tileSize: layout.tileSize)
                bolt.position = CGPoint(x: layout.tileSize * 0.01, y: .zero)
            case .targetSwap:
                guard decoration.strokeNodes.count >= 2,
                      let arrow = decoration.fillNodes.first
                else { return }

                let diamondSize = layout.tileSize * 0.23
                let currentTarget = decoration.strokeNodes[0]
                currentTarget.path = diamondPath(size: diamondSize)
                currentTarget.lineWidth = max(1.0, layout.tileSize * 0.04)
                currentTarget.position = CGPoint(x: -layout.tileSize * 0.15, y: -layout.tileSize * 0.05)

                let nextTarget = decoration.strokeNodes[1]
                nextTarget.path = diamondPath(size: diamondSize)
                nextTarget.lineWidth = max(1.0, layout.tileSize * 0.04)
                nextTarget.position = CGPoint(x: layout.tileSize * 0.15, y: layout.tileSize * 0.05)

                arrow.path = boostChevronPath(tileSize: layout.tileSize, scale: 0.52)
                arrow.position = .zero
                arrow.zRotation = -.pi / 4
            case .openGate:
                guard decoration.strokeNodes.count >= 2,
                      let keyhole = decoration.fillNodes.first
                else { return }

                let frameWidth = layout.tileSize * 0.44
                let frameHeight = layout.tileSize * 0.52
                let frameRect = CGRect(
                    x: -frameWidth / 2,
                    y: -frameHeight / 2,
                    width: frameWidth,
                    height: frameHeight
                )
                let frame = decoration.strokeNodes[0]
                frame.path = CGPath(roundedRect: frameRect, cornerWidth: layout.tileSize * 0.04, cornerHeight: layout.tileSize * 0.04, transform: nil)
                frame.lineWidth = max(1.0, layout.tileSize * 0.045)
                frame.position = .zero

                let doorWidth = layout.tileSize * 0.28
                let doorHeight = layout.tileSize * 0.46
                let doorRect = CGRect(
                    x: -doorWidth / 2,
                    y: -doorHeight / 2,
                    width: doorWidth,
                    height: doorHeight
                )
                let door = decoration.strokeNodes[1]
                door.path = CGPath(roundedRect: doorRect, cornerWidth: layout.tileSize * 0.035, cornerHeight: layout.tileSize * 0.035, transform: nil)
                door.lineWidth = max(1.0, layout.tileSize * 0.04)
                door.position = CGPoint(x: layout.tileSize * 0.12, y: 0)
                door.zRotation = -.pi / 12

                keyhole.path = keyholePath(tileSize: layout.tileSize)
                keyhole.position = CGPoint(x: layout.tileSize * 0.15, y: -layout.tileSize * 0.02)
                keyhole.zRotation = -.pi / 12
            }
        }

        private func applyEffectDecorationColors(
            _ decoration: inout TileEffectDecorationCache,
            effect: TileEffect,
            palette: GameScenePalette
        ) {
            switch effect {
            case .warp(let pairID, _):
                let style = warpVisualStyle(for: pairID, palette: palette)
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
            case .boost:
                let fillColor = palette.boardTileEffectBoost
                for (index, node) in decoration.fillNodes.enumerated() {
                    node.fillColor = fillColor.withAlphaComponent(index == 0 ? 0.92 : 0.64)
                    node.strokeColor = .clear
                    node.alpha = 1.0
                }
            case .slow:
                let fillColor = palette.boardTileEffectSlow
                for (index, node) in decoration.fillNodes.enumerated() {
                    node.fillColor = fillColor.withAlphaComponent(index == 0 ? 0.92 : 0.72)
                    node.strokeColor = .clear
                    node.alpha = 1.0
                }
            case .nextRefresh:
                let accent = palette.boardTileEffectNextRefresh
                for node in decoration.strokeNodes {
                    node.strokeColor = accent
                    node.fillColor = .clear
                    node.alpha = 1.0
                }
                for node in decoration.fillNodes {
                    node.fillColor = accent.withAlphaComponent(0.9)
                    node.strokeColor = .clear
                    node.alpha = 1.0
                }
            case .freeFocus:
                let accent = palette.boardTileEffectFreeFocus
                for node in decoration.strokeNodes {
                    node.strokeColor = accent
                    node.fillColor = .clear
                    node.alpha = 1.0
                }
                for node in decoration.fillNodes {
                    node.fillColor = accent.withAlphaComponent(0.86)
                    node.strokeColor = .clear
                    node.alpha = 1.0
                }
            case .preserveCard:
                let accent = palette.boardTileEffectPreserveCard
                for node in decoration.strokeNodes {
                    node.strokeColor = accent
                    node.fillColor = .clear
                    node.alpha = 1.0
                }
                for node in decoration.fillNodes {
                    node.fillColor = accent.withAlphaComponent(0.88)
                    node.strokeColor = .clear
                    node.alpha = 1.0
                }
            case .draft:
                let accent = palette.boardTileEffectDraft
                for (index, node) in decoration.strokeNodes.enumerated() {
                    node.strokeColor = accent.withAlphaComponent(index == 0 ? 0.62 : 1.0)
                    node.fillColor = accent.withAlphaComponent(index == 0 ? 0.14 : 0.20)
                    node.alpha = 1.0
                }
                for node in decoration.fillNodes {
                    node.fillColor = accent.withAlphaComponent(0.92)
                    node.strokeColor = .clear
                    node.alpha = 1.0
                }
            case .overload:
                let accent = palette.boardTileEffectOverload
                for node in decoration.strokeNodes {
                    node.strokeColor = accent.withAlphaComponent(0.82)
                    node.fillColor = accent.withAlphaComponent(0.10)
                    node.alpha = 1.0
                }
                for node in decoration.fillNodes {
                    node.fillColor = accent.withAlphaComponent(0.95)
                    node.strokeColor = .clear
                    node.alpha = 1.0
                }
            case .targetSwap:
                let accent = palette.boardTileEffectTargetSwap
                for (index, node) in decoration.strokeNodes.enumerated() {
                    node.strokeColor = accent.withAlphaComponent(index == 0 ? 0.72 : 1.0)
                    node.fillColor = accent.withAlphaComponent(index == 0 ? 0.10 : 0.18)
                    node.alpha = 1.0
                }
                for node in decoration.fillNodes {
                    node.fillColor = accent.withAlphaComponent(0.92)
                    node.strokeColor = .clear
                    node.alpha = 1.0
                }
            case .openGate:
                let accent = palette.boardTileEffectOpenGate
                for (index, node) in decoration.strokeNodes.enumerated() {
                    node.strokeColor = accent.withAlphaComponent(index == 0 ? 0.9 : 1.0)
                    node.fillColor = accent.withAlphaComponent(index == 0 ? 0.08 : 0.18)
                    node.alpha = 1.0
                }
                for node in decoration.fillNodes {
                    node.fillColor = accent.withAlphaComponent(0.95)
                    node.strokeColor = .clear
                    node.alpha = 1.0
                }
            }
        }

        private func trianglePath(width: CGFloat, height: CGFloat) -> CGPath {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: width / 2, y: 0))
            path.addLine(to: CGPoint(x: -width / 2, y: height / 2))
            path.addLine(to: CGPoint(x: -width / 2, y: -height / 2))
            path.closeSubpath()
            return path
        }

        private func boostChevronPath(tileSize: CGFloat, scale: CGFloat) -> CGPath {
            let width = tileSize * 0.34 * scale
            let height = tileSize * 0.22 * scale
            let thickness = tileSize * 0.09 * scale
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: height))
            path.addLine(to: CGPoint(x: width, y: -height * 0.15))
            path.addLine(to: CGPoint(x: width - thickness, y: -height))
            path.addLine(to: CGPoint(x: 0, y: height * 0.2))
            path.addLine(to: CGPoint(x: -width + thickness, y: -height))
            path.addLine(to: CGPoint(x: -width, y: -height * 0.15))
            path.closeSubpath()
            return path
        }

        private func diamondPath(size: CGFloat) -> CGPath {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: size / 2))
            path.addLine(to: CGPoint(x: size / 2, y: 0))
            path.addLine(to: CGPoint(x: 0, y: -size / 2))
            path.addLine(to: CGPoint(x: -size / 2, y: 0))
            path.closeSubpath()
            return path
        }

        private func keyholePath(tileSize: CGFloat) -> CGPath {
            let radius = tileSize * 0.045
            let stemWidth = tileSize * 0.045
            let stemHeight = tileSize * 0.12
            let path = CGMutablePath()
            path.addEllipse(in: CGRect(x: -radius, y: radius * 0.15, width: radius * 2, height: radius * 2))
            path.addRect(CGRect(x: -stemWidth / 2, y: -stemHeight, width: stemWidth, height: stemHeight))
            return path
        }

        private func overloadBoltPath(tileSize: CGFloat) -> CGPath {
            let scale = tileSize * 0.50
            let path = CGMutablePath()
            path.move(to: CGPoint(x: scale * 0.06, y: scale * 0.50))
            path.addLine(to: CGPoint(x: -scale * 0.30, y: scale * 0.02))
            path.addLine(to: CGPoint(x: -scale * 0.06, y: scale * 0.02))
            path.addLine(to: CGPoint(x: -scale * 0.18, y: -scale * 0.50))
            path.addLine(to: CGPoint(x: scale * 0.30, y: -scale * 0.02))
            path.addLine(to: CGPoint(x: scale * 0.06, y: -scale * 0.02))
            path.closeSubpath()
            return path
        }
    }
#endif
