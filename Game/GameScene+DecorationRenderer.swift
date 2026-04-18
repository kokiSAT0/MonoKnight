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
            layout: GameSceneLayoutSupport
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
                        layout: layout
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
            layout: GameSceneLayoutSupport
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
                    layout: layout
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
            layout: GameSceneLayoutSupport
        ) {
            guard layout.tileSize > 0 else { return }

            for (point, node) in tileNodes {
                configureTileNodeAppearance(
                    node,
                    at: point,
                    board: board,
                    palette: palette,
                    layout: layout
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
            layout: GameSceneLayoutSupport
        ) {
            node.fillColor = tileFillColor(for: point, board: board, palette: palette)

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
            palette: GameScenePalette
        ) -> SKColor {
            guard let state = board.state(at: point) else { return palette.boardTileUnvisited }
            return tileFillColor(for: state, palette: palette)
        }

        private func tileFillColor(for state: TileState, palette: GameScenePalette) -> SKColor {
            switch state.visitBehavior {
            case .impassable:
                return palette.boardTileImpassable
            case .toggle:
                return .clear
            case .multi:
                return .clear
            case .single:
                return state.isVisited ? palette.boardTileVisited : palette.boardTileUnvisited
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
            }
        }
    }
#endif
