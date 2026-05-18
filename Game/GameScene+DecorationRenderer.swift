#if canImport(SpriteKit)
    import SpriteKit
    import SharedSupport

    final class GameSceneDecorationRenderer {
        private struct WarpVisualStyle {
            let color: SKColor
            let circleCount: Int
        }

        private struct TileEffectDecorationCache {
            let container: SKNode
            var effect: TileEffect
            var strokeNodes: [SKShapeNode]
            var fillNodes: [SKShapeNode]
        }

        private(set) var tileNodes: [GridPoint: SKShapeNode] = [:]
        private var tileEffectDecorations: [GridPoint: TileEffectDecorationCache] = [:]
        private var areFlySuppressedTileEffectsMuted = false
        private var warpVisualStyles: [String: WarpVisualStyle] = [:]
        private var cosmicBackgroundLayer: SKNode?
        private var constellationLayer: SKNode?
        private let maxWarpCircleLayers = 4
        private let cosmicBackgroundLayerNodeName = "boardCosmicBackgroundLayer"
        private let nebulaDepthNodeName = "boardNebulaDepth"
        private let distantStarNodeName = "boardDistantStar"
        private let distantStarTwinkleNodeName = "boardDistantStarTwinkle"
        private let stoneFloorInsetNodeName = "stoneFloorInsetMarker"
        private let stoneFloorSeamNodeName = "stoneFloorSeamMarker"
        private let glassHighlightNodeName = "glassTileHighlightMarker"
        private let tileInnerGlowNodeName = "glassTileInnerGlowMarker"
        private let starChartLineNodeName = "starChartSurveyLineMarker"
        private let starChartNodeNodeName = "starChartSurveyNodeMarker"
        private let constellationLayerNodeName = "boardConstellationLayer"
        private let constellationGlowLineNodeName = "boardConstellationGlowLine"
        private let constellationLineNodeName = "boardConstellationLine"
        private let constellationStarGlowNodeName = "boardConstellationStarGlow"
        private let constellationStarRingNodeName = "boardConstellationStarRing"
        private let constellationStarNodeName = "boardConstellationStar"
        private let starParticleNodeName = "boardStarParticle"
        private let surveyCompassRingNodeName = "boardSurveyCompassRing"
        private let astralCoreGlowNodeName = "boardAstralCoreGlow"
        private let astralCoreRingNodeName = "boardAstralCoreRing"
        private let astralCoreNodeName = "boardAstralCore"
        private let impassableMarkerNodeName = "impassableRockMarker"
        private let impassableVeinNodeName = "impassableRockVeinMarker"

        func reset() {
            removeAllNodes()
            areFlySuppressedTileEffectsMuted = false
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
            showsVisitedTileFill: Bool,
            visiblePoints: Set<GridPoint>?
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
                        showsVisitedTileFill: showsVisitedTileFill,
                        visiblePoints: visiblePoints
                    )
                }
            }

            updateCosmicBackgroundLayer(
                in: scene,
                board: board,
                palette: palette,
                layout: layout,
                visiblePoints: visiblePoints
            )
            updateConstellationLayer(
                in: scene,
                board: board,
                palette: palette,
                layout: layout,
                visiblePoints: visiblePoints
            )

            debugLog(
                "GameScene.setupGrid: 生成タイル数=\(tileNodes.count), tileSize=\(layout.tileSize)"
            )
        }

        func relayoutTileNodes(
            board: Board,
            palette: GameScenePalette,
            layout: GameSceneLayoutSupport,
            showsVisitedTileFill: Bool,
            visiblePoints: Set<GridPoint>?
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
                    showsVisitedTileFill: showsVisitedTileFill,
                    visiblePoints: visiblePoints
                )
            }

            updateCosmicBackgroundLayer(
                in: tileNodes.values.first?.parent,
                board: board,
                palette: palette,
                layout: layout,
                visiblePoints: visiblePoints
            )
            updateConstellationLayer(
                in: tileNodes.values.first?.parent,
                board: board,
                palette: palette,
                layout: layout,
                visiblePoints: visiblePoints
            )
        }

        func removeAllNodes() {
            for node in tileNodes.values {
                node.removeFromParent()
            }
            tileNodes.removeAll()

            for decoration in tileEffectDecorations.values {
                decoration.container.removeFromParent()
            }
            tileEffectDecorations.removeAll()

            cosmicBackgroundLayer?.removeAllActions()
            cosmicBackgroundLayer?.removeFromParent()
            cosmicBackgroundLayer = nil

            constellationLayer?.removeFromParent()
            constellationLayer = nil
        }

        func updateBoardAppearance(
            board: Board,
            palette: GameScenePalette,
            layout: GameSceneLayoutSupport,
            showsVisitedTileFill: Bool,
            visiblePoints: Set<GridPoint>?
        ) {
            guard layout.tileSize > 0 else { return }

            for (point, node) in tileNodes {
                configureTileNodeAppearance(
                    node,
                    at: point,
                    board: board,
                    palette: palette,
                    layout: layout,
                    showsVisitedTileFill: showsVisitedTileFill,
                    visiblePoints: visiblePoints
                )
            }

            updateCosmicBackgroundLayer(
                in: tileNodes.values.first?.parent,
                board: board,
                palette: palette,
                layout: layout,
                visiblePoints: visiblePoints
            )
            updateConstellationLayer(
                in: tileNodes.values.first?.parent,
                board: board,
                palette: palette,
                layout: layout,
                visiblePoints: visiblePoints
            )
        }

        func updateFlySuppressedTileEffectsMuted(
            _ isMuted: Bool,
            board: Board,
            palette: GameScenePalette,
            layout: GameSceneLayoutSupport,
            showsVisitedTileFill: Bool,
            visiblePoints: Set<GridPoint>?
        ) {
            guard areFlySuppressedTileEffectsMuted != isMuted else { return }
            areFlySuppressedTileEffectsMuted = isMuted
            updateBoardAppearance(
                board: board,
                palette: palette,
                layout: layout,
                showsVisitedTileFill: showsVisitedTileFill,
                visiblePoints: visiblePoints
            )
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

#if DEBUG
        func impassableMarkerCountForTesting() -> Int {
            tileNodes.values.reduce(0) { count, node in
                count + (node.childNode(withName: impassableMarkerNodeName) == nil ? 0 : 1)
            }
        }

        func impassableVeinMarkerCountForTesting() -> Int {
            tileNodes.values.reduce(0) { count, node in
                guard let marker = node.childNode(withName: impassableMarkerNodeName) else {
                    return count
                }
                return count
                    + (marker.childNode(withName: impassableVeinNodeName) == nil ? 0 : 1)
            }
        }

        func stoneFloorTextureCountForTesting() -> Int {
            tileNodes.values.reduce(0) { count, node in
                count + (node.childNode(withName: stoneFloorInsetNodeName) == nil ? 0 : 1)
            }
        }

        func starChartTextureCountForTesting() -> Int {
            tileNodes.values.reduce(0) { count, node in
                count + (node.childNode(withName: starChartLineNodeName) == nil ? 0 : 1)
            }
        }

        func glassTileHighlightCountForTesting() -> Int {
            tileNodes.values.reduce(0) { count, node in
                count + (node.childNode(withName: glassHighlightNodeName) == nil ? 0 : 1)
            }
        }

        func tileInnerGlowCountForTesting() -> Int {
            tileNodes.values.reduce(0) { count, node in
                count + (node.childNode(withName: tileInnerGlowNodeName) == nil ? 0 : 1)
            }
        }

        func cosmicBackgroundNodeCountForTesting() -> Int {
            cosmicBackgroundLayer?.children.count ?? 0
        }

        func distantStarNodeCountForTesting() -> Int {
            cosmicBackgroundLayer?.children.reduce(0) { count, node in
                count + (node.name == distantStarNodeName || node.name == distantStarTwinkleNodeName ? 1 : 0)
            } ?? 0
        }

        func twinklingDistantStarNodeCountForTesting() -> Int {
            cosmicBackgroundLayer?.children.reduce(0) { count, node in
                count + (node.name == distantStarTwinkleNodeName && node.hasActions() ? 1 : 0)
            } ?? 0
        }

        func constellationLayerNodeCountForTesting() -> Int {
            constellationLayer?.children.count ?? 0
        }

        func constellationGlowNodeCountForTesting() -> Int {
            constellationLayer?.children.reduce(0) { count, node in
                count + (node.name == constellationGlowLineNodeName || node.name == constellationStarGlowNodeName ? 1 : 0)
            } ?? 0
        }

        func astralCoreNodeCountForTesting() -> Int {
            constellationLayer?.children.reduce(0) { count, node in
                count + (node.name == astralCoreGlowNodeName || node.name == astralCoreRingNodeName || node.name == astralCoreNodeName ? 1 : 0)
            } ?? 0
        }

        func surveyCompassRingCountForTesting() -> Int {
            constellationLayer?.children.reduce(0) { count, node in
                count + (node.name == surveyCompassRingNodeName ? 1 : 0)
            } ?? 0
        }
#endif

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
            showsVisitedTileFill: Bool,
            visiblePoints: Set<GridPoint>?
        ) {
            guard visiblePoints?.contains(point) ?? true else {
                node.fillColor = palette.boardDarknessHiddenTile
                applyHiddenDarknessStyle(
                    to: node,
                    at: point,
                    palette: palette,
                    layout: layout,
                    visiblePoints: visiblePoints
                )
                removeStoneFloorTexture(from: node)
                removeImpassableDecoration(from: node)
                removeEffectDecoration(for: point)
                return
            }

            node.fillColor = tileFillColor(
                for: point,
                board: board,
                palette: palette,
                showsVisitedTileFill: showsVisitedTileFill
            )

            guard let state = board.state(at: point) else {
                applySingleVisitStyle(to: node, palette: palette)
                updateStoneFloorTexture(
                    for: point,
                    on: node,
                    palette: palette,
                    layout: layout
                )
                removeImpassableDecoration(from: node)
                removeEffectDecoration(for: point)
                return
            }

            switch state.visitBehavior {
            case .impassable:
                removeStoneFloorTexture(from: node)
                applyImpassableStyle(to: node, layout: layout, palette: palette)
            case .single:
                applySingleVisitStyle(to: node, palette: palette)
                updateStoneFloorTexture(
                    for: point,
                    on: node,
                    palette: palette,
                    layout: layout
                )
                removeImpassableDecoration(from: node)
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
            case .single:
                return state.isVisited && showsVisitedTileFill
                    ? palette.boardTileVisited
                    : palette.boardTileUnvisited
            }
        }

        private func removeEffectDecoration(for point: GridPoint) {
            guard let decoration = tileEffectDecorations.removeValue(forKey: point) else { return }
            decoration.container.removeAllActions()
            decoration.container.removeFromParent()
        }

        private func applySingleVisitStyle(to node: SKShapeNode, palette: GameScenePalette) {
            node.strokeColor = palette.boardGridLine
            node.lineWidth = 1
        }

        private func updateStoneFloorTexture(
            for point: GridPoint,
            on node: SKShapeNode,
            palette: GameScenePalette,
            layout: GameSceneLayoutSupport
        ) {
            let inset: SKShapeNode
            if let existingInset = node.childNode(withName: stoneFloorInsetNodeName) as? SKShapeNode {
                inset = existingInset
            } else {
                inset = SKShapeNode()
                inset.name = stoneFloorInsetNodeName
                inset.isAntialiased = false
                inset.lineJoin = .miter
                inset.blendMode = .alpha
                node.addChild(inset)
            }

            let seam: SKShapeNode
            if let existingSeam = node.childNode(withName: stoneFloorSeamNodeName) as? SKShapeNode {
                seam = existingSeam
            } else {
                seam = SKShapeNode()
                seam.name = stoneFloorSeamNodeName
                seam.isAntialiased = true
                seam.lineJoin = .round
                seam.lineCap = .round
                seam.blendMode = .alpha
                node.addChild(seam)
            }

            let insetAmount = max(1.0, layout.tileSize * 0.08)
            let rect = CGRect(
                x: -layout.tileSize / 2 + insetAmount,
                y: -layout.tileSize / 2 + insetAmount,
                width: layout.tileSize - insetAmount * 2,
                height: layout.tileSize - insetAmount * 2
            )
            inset.path = CGPath(rect: rect, transform: nil)
            inset.fillColor = .clear
            let usesStarChartTexture = palette.boardStarChartLine.cgColor.alpha > 0.01
            inset.strokeColor = palette.boardGridLine.withAlphaComponent(usesStarChartTexture ? 0.05 : 0.14)
            inset.lineWidth = max(0.5, layout.tileSize * 0.012)
            inset.zPosition = 0.025
            inset.isHidden = false

            seam.path = stoneFloorSeamPath(for: point, tileSize: layout.tileSize)
            seam.fillColor = .clear
            seam.strokeColor = palette.boardGridLine.withAlphaComponent(usesStarChartTexture ? 0.04 : 0.12)
            seam.lineWidth = max(0.5, layout.tileSize * 0.010)
            seam.zPosition = 0.03
            seam.isHidden = false

            updateGlassTileTexture(
                on: node,
                palette: palette,
                tileSize: layout.tileSize
            )
            updateStarChartTexture(
                for: point,
                on: node,
                palette: palette,
                tileSize: layout.tileSize
            )
        }

        private func removeStoneFloorTexture(from node: SKShapeNode) {
            node.childNode(withName: stoneFloorInsetNodeName)?.removeFromParent()
            node.childNode(withName: stoneFloorSeamNodeName)?.removeFromParent()
            node.childNode(withName: glassHighlightNodeName)?.removeFromParent()
            node.childNode(withName: tileInnerGlowNodeName)?.removeFromParent()
            node.childNode(withName: starChartLineNodeName)?.removeFromParent()
            node.childNode(withName: starChartNodeNodeName)?.removeFromParent()
        }

        private func updateGlassTileTexture(
            on node: SKShapeNode,
            palette: GameScenePalette,
            tileSize: CGFloat
        ) {
            guard palette.boardGlassHighlight.cgColor.alpha > 0.01
                    || palette.boardTileInnerGlow.cgColor.alpha > 0.01
            else {
                node.childNode(withName: glassHighlightNodeName)?.removeFromParent()
                node.childNode(withName: tileInnerGlowNodeName)?.removeFromParent()
                return
            }

            if palette.boardGlassHighlight.cgColor.alpha > 0.01 {
                let highlight: SKShapeNode
                if let existingHighlight = node.childNode(withName: glassHighlightNodeName) as? SKShapeNode {
                    highlight = existingHighlight
                } else {
                    highlight = SKShapeNode()
                    highlight.name = glassHighlightNodeName
                    highlight.isAntialiased = true
                    highlight.blendMode = .alpha
                    node.addChild(highlight)
                }
                highlight.path = glassHighlightPath(tileSize: tileSize)
                highlight.fillColor = palette.boardGlassHighlight
                highlight.strokeColor = .clear
                highlight.lineWidth = 0
                highlight.zPosition = 0.040
                highlight.isHidden = false
            } else {
                node.childNode(withName: glassHighlightNodeName)?.removeFromParent()
            }

            if palette.boardTileInnerGlow.cgColor.alpha > 0.01 {
                let innerGlow: SKShapeNode
                if let existingInnerGlow = node.childNode(withName: tileInnerGlowNodeName) as? SKShapeNode {
                    innerGlow = existingInnerGlow
                } else {
                    innerGlow = SKShapeNode()
                    innerGlow.name = tileInnerGlowNodeName
                    innerGlow.isAntialiased = true
                    innerGlow.lineJoin = .round
                    innerGlow.blendMode = .alpha
                    node.addChild(innerGlow)
                }
                let inset = max(1.4, tileSize * 0.105)
                innerGlow.path = CGPath(
                    roundedRect: CGRect(
                        x: -tileSize / 2 + inset,
                        y: -tileSize / 2 + inset,
                        width: tileSize - inset * 2,
                        height: tileSize - inset * 2
                    ),
                    cornerWidth: max(1.0, tileSize * 0.035),
                    cornerHeight: max(1.0, tileSize * 0.035),
                    transform: nil
                )
                innerGlow.fillColor = .clear
                innerGlow.strokeColor = palette.boardTileInnerGlow
                innerGlow.lineWidth = max(0.5, tileSize * 0.010)
                innerGlow.glowWidth = tileSize * 0.018
                innerGlow.zPosition = 0.052
                innerGlow.isHidden = false
            } else {
                node.childNode(withName: tileInnerGlowNodeName)?.removeFromParent()
            }
        }

        private func updateStarChartTexture(
            for point: GridPoint,
            on node: SKShapeNode,
            palette: GameScenePalette,
            tileSize: CGFloat
        ) {
            guard palette.boardStarChartLine.cgColor.alpha > 0.01 else {
                node.childNode(withName: starChartLineNodeName)?.removeFromParent()
                node.childNode(withName: starChartNodeNodeName)?.removeFromParent()
                return
            }

            let line: SKShapeNode
            if let existingLine = node.childNode(withName: starChartLineNodeName) as? SKShapeNode {
                line = existingLine
            } else {
                line = SKShapeNode()
                line.name = starChartLineNodeName
                line.isAntialiased = true
                line.lineJoin = .round
                line.lineCap = .round
                line.blendMode = .alpha
                node.addChild(line)
            }
            line.path = starChartLinePath(for: point, tileSize: tileSize)
            line.fillColor = .clear
            line.strokeColor = palette.boardStarChartLine
            line.lineWidth = max(0.35, tileSize * 0.006)
            line.zPosition = 0.045
            line.isHidden = false

            guard palette.boardStarChartNode.cgColor.alpha > 0.01 else {
                node.childNode(withName: starChartNodeNodeName)?.removeFromParent()
                return
            }

            let mark: SKShapeNode
            if let existingMark = node.childNode(withName: starChartNodeNodeName) as? SKShapeNode {
                mark = existingMark
            } else {
                mark = SKShapeNode()
                mark.name = starChartNodeNodeName
                mark.isAntialiased = true
                mark.blendMode = .alpha
                node.addChild(mark)
            }
            let radius = max(1.2, tileSize * 0.040)
            mark.path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), transform: nil)
            mark.position = starChartNodePosition(for: point, tileSize: tileSize)
            mark.fillColor = palette.boardStarChartNode
            mark.strokeColor = palette.boardStarChartNode.withAlphaComponent(0.22)
            mark.lineWidth = max(0.25, tileSize * 0.004)
            mark.glowWidth = tileSize * 0.012
            mark.zPosition = 0.050
            mark.isHidden = false
        }

        private func updateCosmicBackgroundLayer(
            in parent: SKNode?,
            board: Board,
            palette: GameScenePalette,
            layout: GameSceneLayoutSupport,
            visiblePoints: Set<GridPoint>?
        ) {
            guard visiblePoints == nil,
                  palette.boardNebulaDepth.cgColor.alpha > 0.01,
                  palette.boardDistantStar.cgColor.alpha > 0.01,
                  layout.tileSize > 0,
                  let parent
            else {
                cosmicBackgroundLayer?.removeAllActions()
                cosmicBackgroundLayer?.removeFromParent()
                cosmicBackgroundLayer = nil
                return
            }

            let layer: SKNode
            if let existingLayer = cosmicBackgroundLayer {
                layer = existingLayer
                layer.removeAllChildren()
            } else {
                layer = SKNode()
                layer.name = cosmicBackgroundLayerNodeName
                layer.zPosition = 0.015
                cosmicBackgroundLayer = layer
            }

            if layer.parent !== parent {
                layer.removeFromParent()
                parent.addChild(layer)
            }
            layer.isHidden = false
            layer.alpha = 1

            for (index, field) in nebulaDepthFields(boardSize: board.size, layout: layout).enumerated() {
                let nebula = SKShapeNode(ellipseOf: field.size)
                nebula.name = nebulaDepthNodeName
                nebula.position = field.position
                nebula.zRotation = field.rotation
                nebula.fillColor = palette.boardNebulaDepth.withAlphaComponent(
                    palette.boardNebulaDepth.cgColor.alpha * (index.isMultiple(of: 2) ? 1.0 : 0.62)
                )
                nebula.strokeColor = .clear
                nebula.lineWidth = 0
                nebula.glowWidth = layout.tileSize * 0.22
                nebula.isAntialiased = true
                nebula.blendMode = .alpha
                nebula.zPosition = -0.02
                layer.addChild(nebula)
            }

            for (index, star) in distantStarFields(boardSize: board.size, layout: layout).enumerated() {
                let isTwinkle = index.isMultiple(of: 3)
                let radius = layout.tileSize * star.radiusScale
                let node = SKShapeNode(ellipseOf: CGSize(width: radius * 2, height: radius * 2))
                node.name = isTwinkle ? distantStarTwinkleNodeName : distantStarNodeName
                node.position = star.position
                node.fillColor = (isTwinkle ? palette.boardDistantStarTwinkle : palette.boardDistantStar)
                    .withAlphaComponent(star.alpha)
                node.strokeColor = .clear
                node.lineWidth = 0
                node.glowWidth = isTwinkle ? layout.tileSize * 0.018 : layout.tileSize * 0.006
                node.isAntialiased = true
                node.blendMode = .alpha
                node.zPosition = 0
                if isTwinkle {
                    addTwinkleAction(to: node, index: index)
                }
                layer.addChild(node)
            }
        }

        private func updateConstellationLayer(
            in parent: SKNode?,
            board: Board,
            palette: GameScenePalette,
            layout: GameSceneLayoutSupport,
            visiblePoints: Set<GridPoint>?
        ) {
            guard visiblePoints == nil,
                  palette.boardConstellationLine.cgColor.alpha > 0.01,
                  layout.tileSize > 0,
                  let parent
            else {
                constellationLayer?.removeFromParent()
                constellationLayer = nil
                return
            }

            let layer: SKNode
            if let existingLayer = constellationLayer {
                layer = existingLayer
                layer.removeAllChildren()
            } else {
                layer = SKNode()
                layer.name = constellationLayerNodeName
                layer.zPosition = 0.060
                constellationLayer = layer
            }

            if layer.parent !== parent {
                layer.removeFromParent()
                parent.addChild(layer)
            }
            layer.isHidden = false
            layer.alpha = 1

            addSurveyCompassRings(
                to: layer,
                boardSize: board.size,
                palette: palette,
                layout: layout
            )

            let constellationPath = makeConstellationPath(boardSize: board.size, layout: layout)
            if palette.boardConstellationGlowLine.cgColor.alpha > 0.01 {
                let constellationGlow = SKShapeNode(path: constellationPath)
                constellationGlow.name = constellationGlowLineNodeName
                constellationGlow.strokeColor = palette.boardConstellationGlowLine
                constellationGlow.fillColor = .clear
                constellationGlow.lineWidth = max(0.8, layout.tileSize * 0.026)
                constellationGlow.lineCap = .round
                constellationGlow.lineJoin = .round
                constellationGlow.isAntialiased = true
                constellationGlow.blendMode = .alpha
                constellationGlow.glowWidth = layout.tileSize * 0.010
                constellationGlow.zPosition = -0.02
                layer.addChild(constellationGlow)
            }

            let constellation = SKShapeNode(path: constellationPath)
            constellation.name = constellationLineNodeName
            constellation.strokeColor = palette.boardConstellationLine
            constellation.fillColor = .clear
            constellation.lineWidth = max(0.9, layout.tileSize * 0.012)
            constellation.lineCap = .round
            constellation.lineJoin = .round
            constellation.isAntialiased = true
            constellation.blendMode = .alpha
            constellation.zPosition = 0
            layer.addChild(constellation)

            for (index, point) in constellationStarPoints(boardSize: board.size).enumerated() {
                let position = layout.position(for: point)
                let isMajor = index.isMultiple(of: 3)
                let radius = layout.tileSize * (isMajor ? 0.066 : 0.042)

                if palette.boardConstellationStarGlow.cgColor.alpha > 0.01 {
                    let glowRadius = radius * (isMajor ? 2.7 : 2.2)
                    let glow = SKShapeNode(
                        ellipseOf: CGSize(width: glowRadius * 2, height: glowRadius * 2)
                    )
                    glow.name = constellationStarGlowNodeName
                    glow.position = position
                    glow.fillColor = palette.boardConstellationStarGlow
                    glow.strokeColor = .clear
                    glow.lineWidth = 0
                    glow.glowWidth = layout.tileSize * (isMajor ? 0.026 : 0.018)
                    glow.isAntialiased = true
                    glow.blendMode = .alpha
                    glow.zPosition = 0.005
                    layer.addChild(glow)
                }

                let ringRadius = radius * 1.55
                let ring = SKShapeNode(
                    ellipseOf: CGSize(width: ringRadius * 2, height: ringRadius * 2)
                )
                ring.name = constellationStarRingNodeName
                ring.position = position
                ring.fillColor = .clear
                ring.strokeColor = palette.boardAstralCoreRing.withAlphaComponent(isMajor ? 0.36 : 0.22)
                ring.lineWidth = max(0.3, layout.tileSize * 0.005)
                ring.glowWidth = layout.tileSize * 0.004
                ring.isAntialiased = true
                ring.blendMode = .alpha
                ring.zPosition = 0.008
                layer.addChild(ring)

                let star = SKShapeNode(
                    ellipseOf: CGSize(width: radius * 2, height: radius * 2)
                )
                star.name = constellationStarNodeName
                star.position = position
                star.fillColor = palette.boardConstellationStar
                star.strokeColor = palette.boardConstellationStar.withAlphaComponent(0.32)
                star.lineWidth = max(0.4, layout.tileSize * 0.006)
                star.glowWidth = layout.tileSize * (isMajor ? 0.018 : 0.010)
                star.isAntialiased = true
                star.blendMode = .alpha
                star.zPosition = 0.01
                layer.addChild(star)
            }

            addAstralCore(
                to: layer,
                boardSize: board.size,
                palette: palette,
                layout: layout
            )

            if palette.boardStarParticle.cgColor.alpha > 0.01 {
                for (index, point) in starParticlePoints(boardSize: board.size).enumerated() {
                    let position = layout.position(for: point)
                    let radius = layout.tileSize * (index.isMultiple(of: 4) ? 0.026 : 0.018)
                    let particle = SKShapeNode(
                        ellipseOf: CGSize(width: radius * 2, height: radius * 2)
                    )
                    particle.name = starParticleNodeName
                    particle.position = position
                    let alpha = palette.boardStarParticle.cgColor.alpha
                    let alphaScale: CGFloat = index.isMultiple(of: 5) ? 1.0 : (index.isMultiple(of: 2) ? 0.72 : 0.48)
                    particle.fillColor = palette.boardStarParticle.withAlphaComponent(alpha * alphaScale)
                    particle.strokeColor = .clear
                    particle.lineWidth = 0
                    particle.isAntialiased = true
                    particle.blendMode = .alpha
                    particle.zPosition = -0.01
                    if index.isMultiple(of: 4) {
                        addTwinkleAction(to: particle, index: index + 11)
                    }
                    layer.addChild(particle)
                }
            }
        }

        private func addSurveyCompassRings(
            to layer: SKNode,
            boardSize: Int,
            palette: GameScenePalette,
            layout: GameSceneLayoutSupport
        ) {
            guard palette.boardAstralCoreRing.cgColor.alpha > 0.01 else { return }

            let center = layout.position(for: astralCorePoint(boardSize: boardSize))
            let radii = [
                layout.tileSize * CGFloat(max(boardSize, 1)) * 0.28,
                layout.tileSize * CGFloat(max(boardSize, 1)) * 0.39
            ]

            for (index, radius) in radii.enumerated() {
                let ring = SKShapeNode(ellipseOf: CGSize(width: radius * 2, height: radius * 2))
                ring.name = surveyCompassRingNodeName
                ring.position = center
                ring.fillColor = .clear
                ring.strokeColor = palette.boardAstralCoreRing.withAlphaComponent(index == 0 ? 0.22 : 0.16)
                ring.lineWidth = max(0.5, layout.tileSize * (index == 0 ? 0.007 : 0.005))
                ring.isAntialiased = true
                ring.blendMode = .alpha
                ring.glowWidth = 0
                ring.zPosition = -0.030
                layer.addChild(ring)
            }

            let ticks = SKShapeNode(path: surveyCompassTickPath(boardSize: boardSize, layout: layout))
            ticks.name = surveyCompassRingNodeName
            ticks.position = center
            ticks.fillColor = .clear
            ticks.strokeColor = palette.boardConstellationLine.withAlphaComponent(0.34)
            ticks.lineWidth = max(0.45, layout.tileSize * 0.005)
            ticks.lineCap = .butt
            ticks.isAntialiased = true
            ticks.blendMode = .alpha
            ticks.zPosition = -0.024
            layer.addChild(ticks)
        }

        private func addAstralCore(
            to layer: SKNode,
            boardSize: Int,
            palette: GameScenePalette,
            layout: GameSceneLayoutSupport
        ) {
            guard palette.boardAstralCore.cgColor.alpha > 0.01 else { return }

            let center = astralCorePoint(boardSize: boardSize)
            let position = layout.position(for: center)
            let glowRadius = layout.tileSize * 0.58
            let ringRadius = layout.tileSize * 0.26
            let coreRadius = layout.tileSize * 0.090

            if palette.boardAstralCoreGlow.cgColor.alpha > 0.01 {
                let glow = SKShapeNode(
                    ellipseOf: CGSize(width: glowRadius * 2, height: glowRadius * 2)
                )
                glow.name = astralCoreGlowNodeName
                glow.position = position
                glow.fillColor = palette.boardAstralCoreGlow
                glow.strokeColor = .clear
                glow.lineWidth = 0
                glow.glowWidth = layout.tileSize * 0.040
                glow.isAntialiased = true
                glow.blendMode = .alpha
                glow.zPosition = 0.018
                layer.addChild(glow)
            }

            if palette.boardAstralCorePulse.cgColor.alpha > 0.01 {
                let pulseRadius = layout.tileSize * 0.40
                let pulse = SKShapeNode(
                    ellipseOf: CGSize(width: pulseRadius * 2, height: pulseRadius * 2)
                )
                pulse.name = astralCoreGlowNodeName
                pulse.position = position
                pulse.fillColor = .clear
                pulse.strokeColor = palette.boardAstralCorePulse
                pulse.lineWidth = max(0.7, layout.tileSize * 0.012)
                pulse.glowWidth = layout.tileSize * 0.080
                pulse.isAntialiased = true
                pulse.blendMode = .alpha
                pulse.zPosition = 0.020
                layer.addChild(pulse)
            }

            let outerRing = SKShapeNode(
                ellipseOf: CGSize(width: ringRadius * 2, height: ringRadius * 2)
            )
            outerRing.name = astralCoreRingNodeName
            outerRing.position = position
            outerRing.fillColor = .clear
            outerRing.strokeColor = palette.boardAstralCoreRing
            outerRing.lineWidth = max(0.8, layout.tileSize * 0.014)
            outerRing.glowWidth = layout.tileSize * 0.008
            outerRing.isAntialiased = true
            outerRing.blendMode = .alpha
            outerRing.zPosition = 0.022
            layer.addChild(outerRing)

            let innerRing = SKShapeNode(
                ellipseOf: CGSize(width: ringRadius * 1.12, height: ringRadius * 1.12)
            )
            innerRing.name = astralCoreRingNodeName
            innerRing.position = position
            innerRing.fillColor = .clear
            innerRing.strokeColor = palette.boardConstellationLine.withAlphaComponent(0.58)
            innerRing.lineWidth = max(0.5, layout.tileSize * 0.007)
            innerRing.glowWidth = layout.tileSize * 0.004
            innerRing.isAntialiased = true
            innerRing.blendMode = .alpha
            innerRing.zPosition = 0.024
            layer.addChild(innerRing)

            let crosshair = SKShapeNode(path: astralCoreCrosshairPath(tileSize: layout.tileSize))
            crosshair.name = astralCoreRingNodeName
            crosshair.position = position
            crosshair.fillColor = .clear
            crosshair.strokeColor = palette.boardAstralCoreRing.withAlphaComponent(0.62)
            crosshair.lineWidth = max(0.45, layout.tileSize * 0.006)
            crosshair.lineCap = .round
            crosshair.isAntialiased = true
            crosshair.blendMode = .alpha
            crosshair.zPosition = 0.025
            layer.addChild(crosshair)

            let core = SKShapeNode(
                ellipseOf: CGSize(width: coreRadius * 2, height: coreRadius * 2)
            )
            core.name = astralCoreNodeName
            core.position = position
            core.fillColor = palette.boardAstralCore
            core.strokeColor = palette.boardAstralCoreRing.withAlphaComponent(0.72)
            core.lineWidth = max(0.5, layout.tileSize * 0.008)
            core.glowWidth = layout.tileSize * 0.010
            core.isAntialiased = true
            core.blendMode = .alpha
            core.zPosition = 0.030
            layer.addChild(core)
        }

        private func applyHiddenDarknessStyle(
            to node: SKShapeNode,
            at point: GridPoint,
            palette: GameScenePalette,
            layout: GameSceneLayoutSupport,
            visiblePoints: Set<GridPoint>?
        ) {
            let isBoundary = isAdjacentToVisiblePoint(point, visiblePoints: visiblePoints)
            node.strokeColor = palette.boardDarknessBoundary.withAlphaComponent(isBoundary ? 0.9 : 0.28)
            node.lineWidth = isBoundary ? max(1.5, layout.tileSize * 0.045) : 1
            node.glowWidth = 0
        }

        private func isAdjacentToVisiblePoint(
            _ point: GridPoint,
            visiblePoints: Set<GridPoint>?
        ) -> Bool {
            guard let visiblePoints else { return false }
            let neighbors = [
                point.offset(dx: 0, dy: -1),
                point.offset(dx: 1, dy: 0),
                point.offset(dx: 0, dy: 1),
                point.offset(dx: -1, dy: 0)
            ]
            return neighbors.contains { visiblePoints.contains($0) }
        }

        private func applyImpassableStyle(
            to node: SKShapeNode,
            layout: GameSceneLayoutSupport,
            palette: GameScenePalette
        ) {
            node.strokeColor = .clear
            node.lineWidth = 0
            node.glowWidth = 0

            let marker: SKShapeNode
            if let existingMarker = node.childNode(withName: impassableMarkerNodeName) as? SKShapeNode {
                marker = existingMarker
            } else {
                marker = SKShapeNode()
                marker.name = impassableMarkerNodeName
                marker.isAntialiased = true
                marker.lineJoin = .round
                marker.lineCap = .round
                marker.zPosition = 0.08
                node.addChild(marker)
            }

            marker.path = impassableMarkerPath(tileSize: layout.tileSize)
            marker.fillColor = palette.boardTileUnvisited.withAlphaComponent(0.72)
            marker.strokeColor = palette.boardGridLine.withAlphaComponent(0.95)
            marker.lineWidth = max(1.2, layout.tileSize * 0.04)
            marker.position = .zero
            marker.isHidden = false

            let vein: SKShapeNode
            if let existingVein = marker.childNode(withName: impassableVeinNodeName) as? SKShapeNode {
                vein = existingVein
            } else {
                vein = SKShapeNode()
                vein.name = impassableVeinNodeName
                vein.isAntialiased = true
                vein.lineJoin = .round
                vein.lineCap = .round
                vein.blendMode = .alpha
                marker.addChild(vein)
            }
            vein.path = impassableVeinPath(tileSize: layout.tileSize)
            vein.fillColor = .clear
            vein.strokeColor = palette.boardGridLine.withAlphaComponent(0.72)
            vein.lineWidth = max(0.8, layout.tileSize * 0.018)
            vein.position = .zero
            vein.zPosition = 0.02
            vein.isHidden = false
        }

        private func removeImpassableDecoration(from node: SKShapeNode) {
            node.childNode(withName: impassableMarkerNodeName)?.removeFromParent()
        }

        private func impassableMarkerPath(tileSize: CGFloat) -> CGPath {
            let radius = tileSize * 0.26
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -radius * 0.55, y: radius * 0.75))
            path.addLine(to: CGPoint(x: radius * 0.25, y: radius * 0.92))
            path.addLine(to: CGPoint(x: radius * 0.82, y: radius * 0.35))
            path.addLine(to: CGPoint(x: radius * 0.7, y: -radius * 0.55))
            path.addLine(to: CGPoint(x: radius * 0.05, y: -radius * 0.88))
            path.addLine(to: CGPoint(x: -radius * 0.75, y: -radius * 0.45))
            path.addLine(to: CGPoint(x: -radius * 0.9, y: radius * 0.22))
            path.closeSubpath()
            return path
        }

        private func makeConstellationPath(
            boardSize: Int,
            layout: GameSceneLayoutSupport
        ) -> CGPath {
            let path = CGMutablePath()
            let core = astralCorePoint(boardSize: boardSize)
            let chains = [
                constellationStarPoints(boardSize: boardSize),
                [
                    GridPoint(x: 0, y: max(0, boardSize - 2)),
                    GridPoint(x: min(boardSize - 1, 2), y: max(0, boardSize - 4)),
                    core,
                    GridPoint(x: min(boardSize - 1, 4), y: max(0, boardSize - 3)),
                    GridPoint(x: min(boardSize - 1, 6), y: max(0, boardSize - 6)),
                    GridPoint(x: max(0, boardSize - 1), y: max(0, boardSize - 5))
                ],
                [
                    GridPoint(x: 1, y: 1),
                    core,
                    GridPoint(x: min(boardSize - 1, 5), y: min(boardSize - 1, 2)),
                    GridPoint(x: min(boardSize - 1, 7), y: min(boardSize - 1, 4))
                ]
            ]

            for chain in chains {
                var didMove = false
                for point in chain where isInBounds(point, boardSize: boardSize) {
                    let position = layout.position(for: point)
                    if didMove {
                        path.addLine(to: position)
                    } else {
                        path.move(to: position)
                        didMove = true
                    }
                }
            }
            return path
        }

        private func constellationStarPoints(boardSize: Int) -> [GridPoint] {
            [
                GridPoint(x: 1, y: max(0, boardSize - 2)),
                GridPoint(x: min(boardSize - 1, 3), y: max(0, boardSize - 3)),
                astralCorePoint(boardSize: boardSize),
                GridPoint(x: min(boardSize - 1, 6), y: min(boardSize - 1, 6)),
                GridPoint(x: max(0, boardSize - 2), y: min(boardSize - 1, 4)),
                GridPoint(x: min(boardSize - 1, 5), y: min(boardSize - 1, 2)),
                GridPoint(x: min(boardSize - 1, 2), y: min(boardSize - 1, 2))
            ]
        }

        private func starParticlePoints(boardSize: Int) -> [GridPoint] {
            var points: [GridPoint] = []
            for y in 0..<boardSize {
                for x in 0..<boardSize where abs(x * 17 + y * 31) % 9 == 0 {
                    points.append(GridPoint(x: x, y: y))
                }
            }
            return points
        }

        private func nebulaDepthFields(
            boardSize: Int,
            layout: GameSceneLayoutSupport
        ) -> [(position: CGPoint, size: CGSize, rotation: CGFloat)] {
            let span = layout.tileSize * CGFloat(max(boardSize, 1))
            return [
                (
                    position: layout.position(for: GridPoint(x: max(0, boardSize / 3), y: max(0, boardSize / 3))),
                    size: CGSize(width: span * 0.74, height: span * 0.30),
                    rotation: -0.55
                ),
                (
                    position: layout.position(for: GridPoint(x: max(0, boardSize - 2), y: max(0, boardSize / 2))),
                    size: CGSize(width: span * 0.54, height: span * 0.22),
                    rotation: 0.46
                ),
                (
                    position: layout.position(for: GridPoint(x: max(0, boardSize / 2), y: max(0, boardSize - 2))),
                    size: CGSize(width: span * 0.46, height: span * 0.18),
                    rotation: 0.08
                )
            ]
        }

        private func distantStarFields(
            boardSize: Int,
            layout: GameSceneLayoutSupport
        ) -> [(position: CGPoint, radiusScale: CGFloat, alpha: CGFloat)] {
            var fields: [(position: CGPoint, radiusScale: CGFloat, alpha: CGFloat)] = []
            for y in 0..<boardSize {
                for x in 0..<boardSize {
                    let hash = abs(x * 37 + y * 19 + boardSize * 11)
                    guard hash % 4 == 0 || hash % 11 == 0 else { continue }
                    let base = layout.position(for: GridPoint(x: x, y: y))
                    let offsetX = CGFloat((hash % 5) - 2) * layout.tileSize * 0.12
                    let offsetY = CGFloat(((hash / 5) % 5) - 2) * layout.tileSize * 0.12
                    let scale = CGFloat(hash % 3 == 0 ? 0.018 : 0.012)
                    let alpha: CGFloat = hash % 7 == 0 ? 0.48 : 0.28
                    fields.append((
                        position: CGPoint(x: base.x + offsetX, y: base.y + offsetY),
                        radiusScale: scale,
                        alpha: alpha
                    ))
                }
            }
            return fields
        }

        private func addTwinkleAction(to node: SKNode, index: Int) {
            let dimAlpha: CGFloat = index.isMultiple(of: 2) ? 0.22 : 0.30
            let brightAlpha: CGFloat = index.isMultiple(of: 5) ? 0.74 : 0.58
            let duration = 2.2 + Double(index % 4) * 0.45
            let wait = SKAction.wait(forDuration: Double(index % 5) * 0.16)
            let brighten = SKAction.fadeAlpha(to: brightAlpha, duration: duration)
            let dim = SKAction.fadeAlpha(to: dimAlpha, duration: duration * 0.92)
            let sequence = SKAction.sequence([wait, brighten, dim])
            node.run(.repeatForever(sequence))
        }

        private func addCorePulseAction(to node: SKNode, dimAlpha: CGFloat, brightAlpha: CGFloat) {
            let brighten = SKAction.group([
                SKAction.fadeAlpha(to: brightAlpha, duration: 2.4),
                SKAction.scale(to: 1.04, duration: 2.4)
            ])
            let dim = SKAction.group([
                SKAction.fadeAlpha(to: dimAlpha, duration: 2.8),
                SKAction.scale(to: 0.98, duration: 2.8)
            ])
            node.run(.repeatForever(.sequence([brighten, dim])))
        }

        private func astralCorePoint(boardSize: Int) -> GridPoint {
            GridPoint(x: max(0, boardSize / 2), y: max(0, boardSize / 2))
        }

        private func isInBounds(_ point: GridPoint, boardSize: Int) -> Bool {
            point.x >= 0 && point.y >= 0 && point.x < boardSize && point.y < boardSize
        }

        private func glassHighlightPath(tileSize: CGFloat) -> CGPath {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -tileSize * 0.42, y: tileSize * 0.34))
            path.addLine(to: CGPoint(x: tileSize * 0.16, y: tileSize * 0.46))
            path.addLine(to: CGPoint(x: -tileSize * 0.06, y: tileSize * 0.30))
            path.addLine(to: CGPoint(x: -tileSize * 0.44, y: tileSize * 0.20))
            path.closeSubpath()
            return path
        }

        private func astralCoreCrosshairPath(tileSize: CGFloat) -> CGPath {
            let path = CGMutablePath()
            let inner = tileSize * 0.19
            let outer = tileSize * 0.42
            path.move(to: CGPoint(x: -outer, y: 0))
            path.addLine(to: CGPoint(x: -inner, y: 0))
            path.move(to: CGPoint(x: inner, y: 0))
            path.addLine(to: CGPoint(x: outer, y: 0))
            path.move(to: CGPoint(x: 0, y: -outer))
            path.addLine(to: CGPoint(x: 0, y: -inner))
            path.move(to: CGPoint(x: 0, y: inner))
            path.addLine(to: CGPoint(x: 0, y: outer))
            return path
        }

        private func surveyCompassTickPath(
            boardSize: Int,
            layout: GameSceneLayoutSupport
        ) -> CGPath {
            let path = CGMutablePath()
            let outer = layout.tileSize * CGFloat(max(boardSize, 1)) * 0.39
            let longInner = outer - layout.tileSize * 0.40
            let shortInner = outer - layout.tileSize * 0.22
            for index in 0..<16 {
                let angle = (CGFloat(index) / 16.0) * CGFloat.pi * 2
                let inner = index.isMultiple(of: 4) ? longInner : shortInner
                let start = CGPoint(x: cos(angle) * inner, y: sin(angle) * inner)
                let end = CGPoint(x: cos(angle) * outer, y: sin(angle) * outer)
                path.move(to: start)
                path.addLine(to: end)
            }
            return path
        }

        private func stoneFloorSeamPath(for point: GridPoint, tileSize: CGFloat) -> CGPath {
            let path = CGMutablePath()
            let variant = abs(point.x * 31 + point.y * 17) % 3
            let inset = tileSize * 0.18
            switch variant {
            case 0:
                path.move(to: CGPoint(x: -tileSize * 0.18, y: tileSize * 0.28))
                path.addLine(to: CGPoint(x: tileSize * 0.18, y: tileSize * 0.20))
                path.move(to: CGPoint(x: -tileSize * 0.30, y: -tileSize * 0.18))
                path.addLine(to: CGPoint(x: tileSize * 0.30, y: -tileSize * 0.24))
            case 1:
                path.move(to: CGPoint(x: -tileSize * 0.24, y: tileSize * 0.18))
                path.addLine(to: CGPoint(x: -tileSize * 0.02, y: tileSize * 0.02))
                path.addLine(to: CGPoint(x: tileSize * 0.25, y: tileSize * 0.10))
            default:
                path.move(to: CGPoint(x: -tileSize / 2 + inset, y: -tileSize * 0.02))
                path.addLine(to: CGPoint(x: tileSize / 2 - inset, y: tileSize * 0.04))
            }
            return path
        }

        private func starChartLinePath(for point: GridPoint, tileSize: CGFloat) -> CGPath {
            let path = CGMutablePath()
            let inset = tileSize * 0.22
            let length = tileSize * 0.14
            let minX = -tileSize / 2 + inset
            let maxX = tileSize / 2 - inset
            let minY = -tileSize / 2 + inset
            let maxY = tileSize / 2 - inset
            let corners = [
                (CGPoint(x: minX, y: maxY), CGPoint(x: minX + length, y: maxY), CGPoint(x: minX, y: maxY - length)),
                (CGPoint(x: maxX, y: maxY), CGPoint(x: maxX - length, y: maxY), CGPoint(x: maxX, y: maxY - length)),
                (CGPoint(x: minX, y: minY), CGPoint(x: minX + length, y: minY), CGPoint(x: minX, y: minY + length)),
                (CGPoint(x: maxX, y: minY), CGPoint(x: maxX - length, y: minY), CGPoint(x: maxX, y: minY + length))
            ]

            for (corner, horizontalEnd, verticalEnd) in corners {
                path.move(to: corner)
                path.addLine(to: horizontalEnd)
                path.move(to: corner)
                path.addLine(to: verticalEnd)
            }
            return path
        }

        private func starChartNodePosition(for point: GridPoint, tileSize: CGFloat) -> CGPoint {
            switch abs(point.x * 13 + point.y * 29) % 5 {
            case 0:
                return CGPoint(x: -tileSize * 0.20, y: tileSize * 0.18)
            case 1:
                return CGPoint(x: tileSize * 0.18, y: tileSize * 0.22)
            case 2:
                return CGPoint(x: tileSize * 0.24, y: -tileSize * 0.16)
            case 3:
                return CGPoint(x: -tileSize * 0.26, y: -tileSize * 0.10)
            default:
                return CGPoint(x: tileSize * 0.04, y: -tileSize * 0.24)
            }
        }

        private func impassableVeinPath(tileSize: CGFloat) -> CGPath {
            let radius = tileSize * 0.26
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -radius * 0.42, y: radius * 0.40))
            path.addLine(to: CGPoint(x: -radius * 0.10, y: radius * 0.10))
            path.addLine(to: CGPoint(x: radius * 0.28, y: radius * 0.18))
            path.move(to: CGPoint(x: -radius * 0.18, y: -radius * 0.18))
            path.addLine(to: CGPoint(x: radius * 0.22, y: -radius * 0.46))
            return path
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
            case .returnWarp:
                let ring = SKShapeNode()
                ring.name = "tileEffectReturnWarpRing"
                ring.strokeColor = .clear
                ring.fillColor = .clear
                ring.lineWidth = 1
                ring.isAntialiased = true
                ring.blendMode = .alpha

                let arrow = SKShapeNode()
                arrow.name = "tileEffectReturnWarpArrow"
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
            case .blast:
                let outerArrow = SKShapeNode()
                outerArrow.name = "tileEffectBlastOuterArrow"
                outerArrow.strokeColor = .clear
                outerArrow.fillColor = .clear
                outerArrow.lineWidth = 0
                outerArrow.isAntialiased = true
                outerArrow.blendMode = .alpha

                let innerArrow = SKShapeNode()
                innerArrow.name = "tileEffectBlastInnerArrow"
                innerArrow.strokeColor = .clear
                innerArrow.fillColor = .clear
                innerArrow.lineWidth = 0
                innerArrow.isAntialiased = true
                innerArrow.blendMode = .alpha

                container.addChild(outerArrow)
                container.addChild(innerArrow)
                return TileEffectDecorationCache(
                    container: container,
                    effect: effect,
                    strokeNodes: [],
                    fillNodes: [outerArrow, innerArrow]
                )
            case .slow:
                let trapPlate = SKShapeNode()
                trapPlate.name = "tileEffectParalysisTrapPlate"
                trapPlate.strokeColor = .clear
                trapPlate.fillColor = .clear
                trapPlate.lineWidth = 1
                trapPlate.isAntialiased = true
                trapPlate.blendMode = .alpha

                let bolt = SKShapeNode()
                bolt.name = "tileEffectParalysisBolt"
                bolt.strokeColor = .clear
                bolt.fillColor = .clear
                bolt.lineWidth = 0
                bolt.isAntialiased = true
                bolt.blendMode = .alpha

                let leftSpark = SKShapeNode()
                leftSpark.name = "tileEffectParalysisLeftSpark"
                leftSpark.strokeColor = .clear
                leftSpark.fillColor = .clear
                leftSpark.lineWidth = 0
                leftSpark.isAntialiased = true
                leftSpark.blendMode = .alpha

                let rightSpark = SKShapeNode()
                rightSpark.name = "tileEffectParalysisRightSpark"
                rightSpark.strokeColor = .clear
                rightSpark.fillColor = .clear
                rightSpark.lineWidth = 0
                rightSpark.isAntialiased = true
                rightSpark.blendMode = .alpha

                container.addChild(trapPlate)
                container.addChild(bolt)
                container.addChild(leftSpark)
                container.addChild(rightSpark)
                return TileEffectDecorationCache(
                    container: container,
                    effect: effect,
                    strokeNodes: [trapPlate],
                    fillNodes: [bolt, leftSpark, rightSpark]
                )
            case .poisonTrap:
                let trapPlate = SKShapeNode()
                trapPlate.name = "tileEffectPoisonTrapPlate"
                trapPlate.strokeColor = .clear
                trapPlate.fillColor = .clear
                trapPlate.lineWidth = 1
                trapPlate.isAntialiased = true
                trapPlate.blendMode = .alpha

                let needle = SKShapeNode()
                needle.name = "tileEffectPoisonNeedle"
                needle.strokeColor = .clear
                needle.fillColor = .clear
                needle.lineWidth = 0
                needle.isAntialiased = true
                needle.blendMode = .alpha

                let droplet = SKShapeNode()
                droplet.name = "tileEffectPoisonDroplet"
                droplet.strokeColor = .clear
                droplet.fillColor = .clear
                droplet.lineWidth = 1
                droplet.isAntialiased = true
                droplet.blendMode = .alpha

                container.addChild(trapPlate)
                container.addChild(needle)
                container.addChild(droplet)
                return TileEffectDecorationCache(
                    container: container,
                    effect: effect,
                    strokeNodes: [trapPlate],
                    fillNodes: [needle, droplet]
                )
            case .illusionTrap:
                let trapPlate = SKShapeNode()
                trapPlate.name = "tileEffectIllusionTrapPlate"
                trapPlate.strokeColor = .clear
                trapPlate.fillColor = .clear
                trapPlate.lineWidth = 1
                trapPlate.isAntialiased = true
                trapPlate.blendMode = .alpha

                let question = SKLabelNode(text: "?")
                question.name = "tileEffectIllusionQuestion"
                question.fontName = "AvenirNext-Heavy"
                question.verticalAlignmentMode = .center
                question.horizontalAlignmentMode = .center
                question.blendMode = .alpha

                container.addChild(trapPlate)
                container.addChild(question)
                return TileEffectDecorationCache(
                    container: container,
                    effect: effect,
                    strokeNodes: [trapPlate],
                    fillNodes: []
                )
            case .staggerTrap:
                let trapPlate = SKShapeNode()
                trapPlate.name = "tileEffectStaggerTrapPlate"
                trapPlate.strokeColor = .clear
                trapPlate.fillColor = .clear
                trapPlate.lineWidth = 1
                trapPlate.isAntialiased = true
                trapPlate.blendMode = .alpha

                let branch = SKLabelNode(text: "~")
                branch.name = "tileEffectStaggerMark"
                branch.fontName = "AvenirNext-Heavy"
                branch.verticalAlignmentMode = .center
                branch.horizontalAlignmentMode = .center
                branch.blendMode = .alpha

                container.addChild(trapPlate)
                container.addChild(branch)
                return TileEffectDecorationCache(
                    container: container,
                    effect: effect,
                    strokeNodes: [trapPlate],
                    fillNodes: []
                )
            case .shackleTrap:
                let leftCuff = SKShapeNode()
                leftCuff.name = "tileEffectShackleLeftCuff"
                leftCuff.strokeColor = .clear
                leftCuff.fillColor = .clear
                leftCuff.lineWidth = 1
                leftCuff.isAntialiased = true
                leftCuff.blendMode = .alpha

                let rightCuff = SKShapeNode()
                rightCuff.name = "tileEffectShackleRightCuff"
                rightCuff.strokeColor = .clear
                rightCuff.fillColor = .clear
                rightCuff.lineWidth = 1
                rightCuff.isAntialiased = true
                rightCuff.blendMode = .alpha

                let chain = SKShapeNode()
                chain.name = "tileEffectShackleChain"
                chain.strokeColor = .clear
                chain.fillColor = .clear
                chain.lineWidth = 1
                chain.isAntialiased = true
                chain.blendMode = .alpha

                let weight = SKShapeNode()
                weight.name = "tileEffectShackleWeight"
                weight.strokeColor = .clear
                weight.fillColor = .clear
                weight.lineWidth = 1
                weight.isAntialiased = true
                weight.blendMode = .alpha

                container.addChild(leftCuff)
                container.addChild(rightCuff)
                container.addChild(chain)
                container.addChild(weight)
                return TileEffectDecorationCache(
                    container: container,
                    effect: effect,
                    strokeNodes: [leftCuff, rightCuff, chain, weight],
                    fillNodes: [weight]
                )
            case .swamp:
                let pond = SKShapeNode()
                pond.name = "tileEffectSwampPond"
                pond.strokeColor = .clear
                pond.fillColor = .clear
                pond.lineWidth = 1
                pond.isAntialiased = true
                pond.blendMode = .alpha

                let rippleA = SKShapeNode()
                rippleA.name = "tileEffectSwampRippleA"
                rippleA.strokeColor = .clear
                rippleA.fillColor = .clear
                rippleA.lineWidth = 1
                rippleA.isAntialiased = true
                rippleA.blendMode = .alpha

                let rippleB = SKShapeNode()
                rippleB.name = "tileEffectSwampRippleB"
                rippleB.strokeColor = .clear
                rippleB.fillColor = .clear
                rippleB.lineWidth = 1
                rippleB.isAntialiased = true
                rippleB.blendMode = .alpha

                container.addChild(pond)
                container.addChild(rippleA)
                container.addChild(rippleB)
                return TileEffectDecorationCache(
                    container: container,
                    effect: effect,
                    strokeNodes: [rippleA, rippleB],
                    fillNodes: [pond]
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
            case .discardRandomHand:
                let card = SKShapeNode()
                card.name = "tileEffectDiscardCardBody"
                card.strokeColor = .clear
                card.fillColor = .clear
                card.lineWidth = 1
                card.isAntialiased = true
                card.blendMode = .alpha

                let crack = SKShapeNode()
                crack.name = "tileEffectDiscardCardCrack"
                crack.strokeColor = .clear
                crack.fillColor = .clear
                crack.lineWidth = 1
                crack.isAntialiased = true
                crack.blendMode = .alpha

                container.addChild(card)
                container.addChild(crack)
                return TileEffectDecorationCache(
                    container: container,
                    effect: effect,
                    strokeNodes: [card, crack],
                    fillNodes: []
                )
            case .relicBreakTrap:
                let relic = SKShapeNode()
                relic.name = "tileEffectRelicBreakGem"
                relic.strokeColor = .clear
                relic.fillColor = .clear
                relic.lineWidth = 1
                relic.isAntialiased = true
                relic.blendMode = .alpha

                let crack = SKShapeNode()
                crack.name = "tileEffectRelicBreakCrack"
                crack.strokeColor = .clear
                crack.fillColor = .clear
                crack.lineWidth = 1
                crack.isAntialiased = true
                crack.blendMode = .alpha

                let sparkle = SKShapeNode()
                sparkle.name = "tileEffectRelicBreakSparkle"
                sparkle.strokeColor = .clear
                sparkle.fillColor = .clear
                sparkle.lineWidth = 1
                sparkle.isAntialiased = true
                sparkle.blendMode = .alpha

                container.addChild(relic)
                container.addChild(crack)
                container.addChild(sparkle)
                return TileEffectDecorationCache(
                    container: container,
                    effect: effect,
                    strokeNodes: [relic, crack, sparkle],
                    fillNodes: [relic, sparkle]
                )
            case .discardAllMoveCards, .discardAllSupportCards:
                let card = SKShapeNode()
                card.name = "tileEffectDiscardCategoryCardBody"
                card.strokeColor = .clear
                card.fillColor = .clear
                card.lineWidth = 1
                card.isAntialiased = true
                card.blendMode = .alpha

                let crack = SKShapeNode()
                crack.name = "tileEffectDiscardCategoryCardCrack"
                crack.strokeColor = .clear
                crack.fillColor = .clear
                crack.lineWidth = 1
                crack.isAntialiased = true
                crack.blendMode = .alpha

                let icon = SKShapeNode()
                icon.name = "tileEffectDiscardCategoryIcon"
                icon.strokeColor = .clear
                icon.fillColor = .clear
                icon.lineWidth = 1
                icon.isAntialiased = true
                icon.blendMode = .alpha

                container.addChild(card)
                container.addChild(crack)
                container.addChild(icon)
                return TileEffectDecorationCache(
                    container: container,
                    effect: effect,
                    strokeNodes: [card, crack, icon],
                    fillNodes: []
                )
            case .discardAllHands:
                let outerFrame = SKShapeNode()
                outerFrame.name = "tileEffectDiscardAllFrame"
                outerFrame.strokeColor = .clear
                outerFrame.fillColor = .clear
                outerFrame.lineWidth = 1
                outerFrame.isAntialiased = true
                outerFrame.blendMode = .alpha
                container.addChild(outerFrame)

                var strokeNodes: [SKShapeNode] = [outerFrame]
                for index in 0..<3 {
                    let card = SKShapeNode()
                    card.name = "tileEffectDiscardAllCard\(index)"
                    card.strokeColor = .clear
                    card.fillColor = .clear
                    card.lineWidth = 1
                    card.isAntialiased = true
                    card.blendMode = .alpha

                    let crack = SKShapeNode()
                    crack.name = "tileEffectDiscardAllCrack\(index)"
                    crack.strokeColor = .clear
                    crack.fillColor = .clear
                    crack.lineWidth = 1
                    crack.isAntialiased = true
                    crack.blendMode = .alpha

                    container.addChild(card)
                    container.addChild(crack)
                    strokeNodes.append(card)
                    strokeNodes.append(crack)
                }
                return TileEffectDecorationCache(
                    container: container,
                    effect: effect,
                    strokeNodes: strokeNodes,
                    fillNodes: []
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
            case .returnWarp:
                guard let ring = decoration.strokeNodes.first,
                      let arrow = decoration.fillNodes.first
                else { return }
                let radius = layout.tileSize * 0.31
                ring.path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), transform: nil)
                ring.lineWidth = max(1.0, layout.tileSize * 0.035)
                ring.position = .zero

                let arrowSize = layout.tileSize * 0.34
                let path = CGMutablePath()
                path.move(to: CGPoint(x: -arrowSize * 0.34, y: -arrowSize * 0.42))
                path.addLine(to: CGPoint(x: arrowSize * 0.42, y: 0))
                path.addLine(to: CGPoint(x: -arrowSize * 0.34, y: arrowSize * 0.42))
                path.addLine(to: CGPoint(x: -arrowSize * 0.12, y: 0))
                path.closeSubpath()
                arrow.path = path
                arrow.position = .zero
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
            case .blast(let direction):
                guard decoration.fillNodes.count >= 2 else { return }

                let rotation = blastArrowRotation(for: direction)
                let outerArrow = decoration.fillNodes[0]
                outerArrow.path = blastArrowPath(tileSize: layout.tileSize, scale: 1.0)
                outerArrow.position = .zero
                outerArrow.zRotation = rotation

                let innerArrow = decoration.fillNodes[1]
                innerArrow.path = blastArrowPath(tileSize: layout.tileSize, scale: 0.66)
                innerArrow.position = CGPoint(x: -sin(rotation) * layout.tileSize * 0.13, y: cos(rotation) * layout.tileSize * 0.13)
                innerArrow.zRotation = rotation
            case .slow:
                guard let trapPlate = decoration.strokeNodes.first,
                      decoration.fillNodes.count >= 3
                else { return }

                trapPlate.path = paralysisTrapPlatePath(tileSize: layout.tileSize)
                trapPlate.position = .zero
                trapPlate.lineWidth = max(layout.tileSize * 0.035, 1.4)

                let bolt = decoration.fillNodes[0]
                bolt.path = paralysisBoltPath(tileSize: layout.tileSize, scale: 0.82)
                bolt.position = .zero
                bolt.zRotation = 0

                let leftSpark = decoration.fillNodes[1]
                leftSpark.path = paralysisSparkPath(tileSize: layout.tileSize, scale: 0.58)
                leftSpark.position = CGPoint(x: -layout.tileSize * 0.22, y: layout.tileSize * 0.02)
                leftSpark.zRotation = -.pi / 12

                let rightSpark = decoration.fillNodes[2]
                rightSpark.path = paralysisSparkPath(tileSize: layout.tileSize, scale: 0.48)
                rightSpark.position = CGPoint(x: layout.tileSize * 0.24, y: -layout.tileSize * 0.03)
                rightSpark.zRotation = .pi
            case .poisonTrap:
                guard let trapPlate = decoration.strokeNodes.first,
                      decoration.fillNodes.count >= 2
                else { return }

                trapPlate.path = paralysisTrapPlatePath(tileSize: layout.tileSize)
                trapPlate.position = .zero
                trapPlate.lineWidth = max(layout.tileSize * 0.035, 1.4)

                let needle = decoration.fillNodes[0]
                needle.path = CGPath(
                    roundedRect: CGRect(
                        x: -layout.tileSize * 0.035,
                        y: -layout.tileSize * 0.26,
                        width: layout.tileSize * 0.07,
                        height: layout.tileSize * 0.52
                    ),
                    cornerWidth: layout.tileSize * 0.02,
                    cornerHeight: layout.tileSize * 0.02,
                    transform: nil
                )
                needle.position = CGPoint(x: -layout.tileSize * 0.14, y: layout.tileSize * 0.02)
                needle.zRotation = .pi / 4

                let dropletRadius = layout.tileSize * 0.12
                let droplet = decoration.fillNodes[1]
                droplet.path = CGPath(
                    ellipseIn: CGRect(
                        x: -dropletRadius,
                        y: -dropletRadius,
                        width: dropletRadius * 2,
                        height: dropletRadius * 2
                    ),
                    transform: nil
                )
                droplet.position = CGPoint(x: layout.tileSize * 0.12, y: -layout.tileSize * 0.04)
            case .illusionTrap:
                guard let trapPlate = decoration.strokeNodes.first else { return }
                trapPlate.path = paralysisTrapPlatePath(tileSize: layout.tileSize)
                trapPlate.position = .zero
                trapPlate.lineWidth = max(layout.tileSize * 0.035, 1.4)
                if let question = decoration.container.childNode(withName: "tileEffectIllusionQuestion") as? SKLabelNode {
                    question.fontSize = max(14, layout.tileSize * 0.58)
                    question.position = CGPoint(x: 0, y: -layout.tileSize * 0.02)
                }
            case .staggerTrap:
                guard let trapPlate = decoration.strokeNodes.first else { return }
                trapPlate.path = paralysisTrapPlatePath(tileSize: layout.tileSize)
                trapPlate.position = .zero
                trapPlate.lineWidth = max(layout.tileSize * 0.035, 1.4)
                if let mark = decoration.container.childNode(withName: "tileEffectStaggerMark") as? SKLabelNode {
                    mark.fontSize = max(14, layout.tileSize * 0.62)
                    mark.position = CGPoint(x: 0, y: -layout.tileSize * 0.03)
                    mark.zRotation = -.pi / 10
                }
            case .shackleTrap:
                guard decoration.strokeNodes.count >= 4 else { return }
                let cuffRadius = layout.tileSize * 0.13
                let cuffRect = CGRect(x: -cuffRadius, y: -cuffRadius, width: cuffRadius * 2, height: cuffRadius * 2)
                let leftCuff = decoration.strokeNodes[0]
                leftCuff.path = CGPath(ellipseIn: cuffRect, transform: nil)
                leftCuff.position = CGPoint(x: -layout.tileSize * 0.13, y: layout.tileSize * 0.08)
                leftCuff.lineWidth = max(1.2, layout.tileSize * 0.04)

                let rightCuff = decoration.strokeNodes[1]
                rightCuff.path = CGPath(ellipseIn: cuffRect, transform: nil)
                rightCuff.position = CGPoint(x: layout.tileSize * 0.13, y: layout.tileSize * 0.08)
                rightCuff.lineWidth = max(1.2, layout.tileSize * 0.04)

                let chain = decoration.strokeNodes[2]
                let chainPath = CGMutablePath()
                chainPath.move(to: CGPoint(x: -layout.tileSize * 0.02, y: layout.tileSize * 0.02))
                chainPath.addLine(to: CGPoint(x: layout.tileSize * 0.18, y: -layout.tileSize * 0.18))
                chain.path = chainPath
                chain.position = .zero
                chain.lineWidth = max(1.3, layout.tileSize * 0.04)

                let weightRadius = layout.tileSize * 0.13
                let weight = decoration.strokeNodes[3]
                weight.path = CGPath(
                    ellipseIn: CGRect(x: -weightRadius, y: -weightRadius, width: weightRadius * 2, height: weightRadius * 2),
                    transform: nil
                )
                weight.position = CGPoint(x: layout.tileSize * 0.22, y: -layout.tileSize * 0.23)
                weight.lineWidth = max(1.2, layout.tileSize * 0.04)
            case .swamp:
                guard let pond = decoration.fillNodes.first,
                      decoration.strokeNodes.count >= 2
                else { return }

                let pondRect = CGRect(
                    x: -layout.tileSize * 0.33,
                    y: -layout.tileSize * 0.20,
                    width: layout.tileSize * 0.66,
                    height: layout.tileSize * 0.40
                )
                pond.path = CGPath(ellipseIn: pondRect, transform: nil)
                pond.position = CGPoint(x: -layout.tileSize * 0.01, y: -layout.tileSize * 0.02)

                let rippleA = decoration.strokeNodes[0]
                rippleA.path = CGPath(
                    ellipseIn: CGRect(
                        x: -layout.tileSize * 0.23,
                        y: -layout.tileSize * 0.06,
                        width: layout.tileSize * 0.32,
                        height: layout.tileSize * 0.12
                    ),
                    transform: nil
                )
                rippleA.position = CGPoint(x: -layout.tileSize * 0.08, y: layout.tileSize * 0.02)
                rippleA.lineWidth = max(layout.tileSize * 0.025, 1.0)

                let rippleB = decoration.strokeNodes[1]
                rippleB.path = CGPath(
                    ellipseIn: CGRect(
                        x: -layout.tileSize * 0.13,
                        y: -layout.tileSize * 0.04,
                        width: layout.tileSize * 0.26,
                        height: layout.tileSize * 0.09
                    ),
                    transform: nil
                )
                rippleB.position = CGPoint(x: layout.tileSize * 0.16, y: -layout.tileSize * 0.05)
                rippleB.lineWidth = max(layout.tileSize * 0.02, 1.0)
            case .preserveCard:
                guard let card = decoration.strokeNodes.first,
                      let notch = decoration.fillNodes.first
                else { return }

                let cardWidth = layout.tileSize * 0.42
                let cardHeight = layout.tileSize * 0.54
                card.path = techCardPanelPath(tileSize: layout.tileSize, width: cardWidth, height: cardHeight)
                card.lineWidth = max(1.0, layout.tileSize * 0.045)
                card.position = .zero

                let stripe = CGMutablePath()
                stripe.addRoundedRect(
                    in: CGRect(
                        x: -layout.tileSize * 0.15,
                        y: -layout.tileSize * 0.035,
                        width: layout.tileSize * 0.30,
                        height: layout.tileSize * 0.055
                    ),
                    cornerWidth: layout.tileSize * 0.018,
                    cornerHeight: layout.tileSize * 0.018
                )
                stripe.addRect(CGRect(
                    x: -layout.tileSize * 0.10,
                    y: -layout.tileSize * 0.14,
                    width: layout.tileSize * 0.20,
                    height: layout.tileSize * 0.035
                ))
                notch.path = stripe
                notch.position = CGPoint(x: 0, y: layout.tileSize * 0.12)
            case .discardRandomHand:
                guard decoration.strokeNodes.count >= 2 else { return }
                let card = decoration.strokeNodes[0]
                let crack = decoration.strokeNodes[1]
                card.path = brokenCardPath(tileSize: layout.tileSize, scale: 0.92)
                card.lineWidth = max(1.2, layout.tileSize * 0.045)
                card.position = .zero
                card.zRotation = -.pi / 18

                crack.path = brokenCardCrackPath(tileSize: layout.tileSize, scale: 0.92)
                crack.lineWidth = max(1.2, layout.tileSize * 0.04)
                crack.position = .zero
                crack.zRotation = card.zRotation
            case .relicBreakTrap:
                guard decoration.strokeNodes.count >= 3 else { return }
                let relic = decoration.strokeNodes[0]
                let crack = decoration.strokeNodes[1]
                let sparkle = decoration.strokeNodes[2]

                relic.path = brokenRelicGemPath(tileSize: layout.tileSize, scale: 0.82)
                relic.lineWidth = max(1.3, layout.tileSize * 0.05)
                relic.position = CGPoint(x: -layout.tileSize * 0.02, y: 0)

                crack.path = brokenCardCrackPath(tileSize: layout.tileSize, scale: 0.74)
                crack.lineWidth = max(1.2, layout.tileSize * 0.04)
                crack.position = relic.position

                sparkle.path = paralysisSparkPath(tileSize: layout.tileSize, scale: 0.52)
                sparkle.lineWidth = max(1.0, layout.tileSize * 0.035)
                sparkle.position = CGPoint(x: layout.tileSize * 0.22, y: layout.tileSize * 0.22)
                sparkle.zRotation = .pi / 7
            case .discardAllMoveCards, .discardAllSupportCards:
                guard decoration.strokeNodes.count >= 3 else { return }
                let card = decoration.strokeNodes[0]
                let crack = decoration.strokeNodes[1]
                let icon = decoration.strokeNodes[2]

                card.path = brokenCardPath(tileSize: layout.tileSize, scale: 0.84)
                card.lineWidth = max(1.2, layout.tileSize * 0.04)
                card.position = CGPoint(x: -layout.tileSize * 0.04, y: -layout.tileSize * 0.01)
                card.zRotation = -.pi / 20

                crack.path = brokenCardCrackPath(tileSize: layout.tileSize, scale: 0.84)
                crack.lineWidth = max(1.2, layout.tileSize * 0.035)
                crack.position = card.position
                crack.zRotation = card.zRotation

                switch effect {
                case .discardAllMoveCards:
                    icon.path = blastArrowPath(tileSize: layout.tileSize, scale: 0.42)
                    icon.position = CGPoint(x: layout.tileSize * 0.14, y: layout.tileSize * 0.10)
                    icon.zRotation = -.pi / 2
                    icon.lineWidth = max(1.0, layout.tileSize * 0.035)
                case .discardAllSupportCards:
                    icon.path = supportCrossPath(tileSize: layout.tileSize, scale: 0.38)
                    icon.position = CGPoint(x: layout.tileSize * 0.14, y: layout.tileSize * 0.10)
                    icon.zRotation = 0
                    icon.lineWidth = max(1.0, layout.tileSize * 0.04)
                default:
                    break
                }
            case .discardAllHands:
                guard decoration.strokeNodes.count >= 7 else { return }
                let frame = decoration.strokeNodes[0]
                let frameInset = layout.tileSize * 0.18
                frame.path = CGPath(
                    roundedRect: CGRect(
                        x: -layout.tileSize / 2 + frameInset,
                        y: -layout.tileSize / 2 + frameInset,
                        width: layout.tileSize - frameInset * 2,
                        height: layout.tileSize - frameInset * 2
                    ),
                    cornerWidth: layout.tileSize * 0.08,
                    cornerHeight: layout.tileSize * 0.08,
                    transform: nil
                )
                frame.lineWidth = max(2.0, layout.tileSize * 0.07)
                frame.position = .zero

                let offsets = [
                    CGPoint(x: -layout.tileSize * 0.12, y: layout.tileSize * 0.09),
                    CGPoint(x: layout.tileSize * 0.10, y: -layout.tileSize * 0.02),
                    CGPoint(x: -layout.tileSize * 0.02, y: -layout.tileSize * 0.14)
                ]
                let rotations: [CGFloat] = [-.pi / 10, .pi / 12, -.pi / 30]
                for index in 0..<3 {
                    let card = decoration.strokeNodes[1 + index * 2]
                    let crack = decoration.strokeNodes[2 + index * 2]
                    card.path = brokenCardPath(tileSize: layout.tileSize, scale: 0.55)
                    card.lineWidth = max(1.0, layout.tileSize * 0.035)
                    card.position = offsets[index]
                    card.zRotation = rotations[index]

                    crack.path = brokenCardCrackPath(tileSize: layout.tileSize, scale: 0.55)
                    crack.lineWidth = max(1.0, layout.tileSize * 0.03)
                    crack.position = offsets[index]
                    crack.zRotation = rotations[index]
                }
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
            case .returnWarp:
                let color = palette.boardTileEffectWarp
                for node in decoration.strokeNodes {
                    node.strokeColor = color.withAlphaComponent(0.86)
                    node.fillColor = .clear
                    node.alpha = 1.0
                }
                for node in decoration.fillNodes {
                    node.fillColor = color.withAlphaComponent(0.82)
                    node.strokeColor = .clear
                    node.alpha = 1.0
                }
            case .shuffleHand:
                let strokeColor = palette.boardTileEffectShuffle
                for node in decoration.strokeNodes {
                    node.strokeColor = strokeColor
                    node.fillColor = .clear
                    node.alpha = 1.0
                }
                if decoration.fillNodes.count >= 2 {
                    let primaryFill = strokeColor.withAlphaComponent(0.88)
                    let secondaryFill = strokeColor.withAlphaComponent(0.6)
                    decoration.fillNodes[0].fillColor = primaryFill
                    decoration.fillNodes[0].strokeColor = .clear
                    decoration.fillNodes[0].alpha = 1.0
                    decoration.fillNodes[1].fillColor = secondaryFill
                    decoration.fillNodes[1].strokeColor = .clear
                    decoration.fillNodes[1].alpha = 1.0
                }
            case .blast:
                let fillColor = palette.boardTileEffectBlast
                for (index, node) in decoration.fillNodes.enumerated() {
                    node.fillColor = fillColor.withAlphaComponent(index == 0 ? 0.92 : 0.64)
                    node.strokeColor = .clear
                    node.alpha = 1.0
                }
            case .slow:
                let fillColor = palette.boardTileEffectSlow
                for node in decoration.strokeNodes {
                    node.strokeColor = fillColor.withAlphaComponent(0.88)
                    node.fillColor = fillColor.withAlphaComponent(0.14)
                    node.alpha = 1.0
                }
                for (index, node) in decoration.fillNodes.enumerated() {
                    node.fillColor = fillColor.withAlphaComponent(index == 0 ? 0.94 : 0.68)
                    node.strokeColor = .clear
                    node.alpha = 1.0
                }
            case .poisonTrap:
                let accent = palette.boardTileEffectSlow
                for node in decoration.strokeNodes {
                    node.strokeColor = accent.withAlphaComponent(0.82)
                    node.fillColor = accent.withAlphaComponent(0.10)
                    node.alpha = 1.0
                }
                for (index, node) in decoration.fillNodes.enumerated() {
                    node.fillColor = accent.withAlphaComponent(index == 0 ? 0.88 : 0.72)
                    node.strokeColor = index == 1 ? accent.withAlphaComponent(0.92) : .clear
                    node.alpha = 1.0
                }
            case .illusionTrap:
                let accent = palette.boardTileEffectSlow
                for node in decoration.strokeNodes {
                    node.strokeColor = accent.withAlphaComponent(0.86)
                    node.fillColor = accent.withAlphaComponent(0.12)
                    node.alpha = 1.0
                }
                if let question = decoration.container.childNode(withName: "tileEffectIllusionQuestion") as? SKLabelNode {
                    question.fontColor = accent.withAlphaComponent(0.96)
                    question.alpha = 1.0
                }
            case .staggerTrap:
                let accent = palette.boardTileEffectSlow
                for node in decoration.strokeNodes {
                    node.strokeColor = accent.withAlphaComponent(0.86)
                    node.fillColor = accent.withAlphaComponent(0.12)
                    node.alpha = 1.0
                }
                if let mark = decoration.container.childNode(withName: "tileEffectStaggerMark") as? SKLabelNode {
                    mark.fontColor = accent.withAlphaComponent(0.96)
                    mark.alpha = 1.0
                }
            case .shackleTrap:
                let accent = palette.boardTileEffectSlow
                for (index, node) in decoration.strokeNodes.enumerated() {
                    node.strokeColor = accent.withAlphaComponent(index == 2 ? 0.74 : 0.92)
                    node.fillColor = index == 3 ? accent.withAlphaComponent(0.28) : .clear
                    node.alpha = 1.0
                }
            case .swamp:
                let accent = palette.boardTileEffectSwamp
                for (index, node) in decoration.strokeNodes.enumerated() {
                    node.strokeColor = accent.withAlphaComponent(index == 0 ? 0.72 : 0.56)
                    node.fillColor = .clear
                    node.alpha = 1.0
                }
                for node in decoration.fillNodes {
                    node.fillColor = accent.withAlphaComponent(0.34)
                    node.strokeColor = accent.withAlphaComponent(0.86)
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
            case .discardRandomHand:
                let accent = palette.boardTileEffectDiscardHand
                for (index, node) in decoration.strokeNodes.enumerated() {
                    node.strokeColor = accent.withAlphaComponent(index == 0 ? 0.95 : 0.78)
                    node.fillColor = index == 0 ? accent.withAlphaComponent(0.10) : .clear
                    node.alpha = 1.0
                }
            case .relicBreakTrap:
                let accent = palette.boardTileEffectDiscardHand
                for (index, node) in decoration.strokeNodes.enumerated() {
                    node.strokeColor = accent.withAlphaComponent(index == 1 ? 0.82 : 0.96)
                    node.fillColor = index == 0 ? accent.withAlphaComponent(0.13) : accent.withAlphaComponent(index == 2 ? 0.78 : 0.0)
                    node.alpha = 1.0
                }
            case .discardAllMoveCards, .discardAllSupportCards:
                let accent = palette.boardTileEffectDiscardHand
                for (index, node) in decoration.strokeNodes.enumerated() {
                    node.strokeColor = accent.withAlphaComponent(index == 2 ? 1.0 : 0.86)
                    node.fillColor = index == 0 ? accent.withAlphaComponent(0.10) : .clear
                    node.alpha = 1.0
                }
            case .discardAllHands:
                let accent = palette.boardTileEffectDiscardHand
                for (index, node) in decoration.strokeNodes.enumerated() {
                    node.strokeColor = accent.withAlphaComponent(index == 0 ? 1.0 : 0.88)
                    node.fillColor = index == 0 ? accent.withAlphaComponent(0.10) : accent.withAlphaComponent(0.08)
                    node.alpha = 1.0
                }
            }

            if usesNeonGridTheme(palette) {
                applyNeonTileEffectPictogramTuning(&decoration)
            }

            decoration.container.alpha = areFlySuppressedTileEffectsMuted && effect.isBlockedByFlySpell
                ? 0.32
                : 1.0
        }

        private func applyNeonTileEffectPictogramTuning(_ decoration: inout TileEffectDecorationCache) {
            for node in decoration.strokeNodes {
                node.glowWidth = max(node.glowWidth, max(node.lineWidth * 0.72, 0.55))
                node.lineJoin = .round
                node.lineCap = .round
                node.isAntialiased = true
                node.blendMode = .alpha
            }
            for node in decoration.fillNodes {
                if !node.fillColor.isClearForDecorationRendering {
                    node.glowWidth = max(node.glowWidth, 0.55)
                }
                node.lineJoin = .round
                node.lineCap = .round
                node.isAntialiased = true
                node.blendMode = .alpha
            }
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

        private func paralysisTrapPlatePath(tileSize: CGFloat) -> CGPath {
            let size = tileSize * 0.54
            let half = size / 2
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: half))
            path.addLine(to: CGPoint(x: half, y: 0))
            path.addLine(to: CGPoint(x: 0, y: -half))
            path.addLine(to: CGPoint(x: -half, y: 0))
            path.closeSubpath()
            return path
        }

        private func paralysisBoltPath(tileSize: CGFloat, scale: CGFloat) -> CGPath {
            let width = tileSize * 0.32 * scale
            let height = tileSize * 0.52 * scale
            let path = CGMutablePath()
            path.move(to: CGPoint(x: width * 0.10, y: height / 2))
            path.addLine(to: CGPoint(x: -width * 0.40, y: height * 0.04))
            path.addLine(to: CGPoint(x: -width * 0.08, y: height * 0.04))
            path.addLine(to: CGPoint(x: -width * 0.30, y: -height / 2))
            path.addLine(to: CGPoint(x: width * 0.42, y: -height * 0.05))
            path.addLine(to: CGPoint(x: width * 0.10, y: -height * 0.05))
            path.closeSubpath()
            return path
        }

        private func paralysisSparkPath(tileSize: CGFloat, scale: CGFloat) -> CGPath {
            let width = tileSize * 0.20 * scale
            let height = tileSize * 0.28 * scale
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: height / 2))
            path.addLine(to: CGPoint(x: -width * 0.5, y: 0))
            path.addLine(to: CGPoint(x: -width * 0.12, y: 0))
            path.addLine(to: CGPoint(x: -width * 0.32, y: -height / 2))
            path.addLine(to: CGPoint(x: width * 0.5, y: -height * 0.04))
            path.addLine(to: CGPoint(x: width * 0.12, y: -height * 0.04))
            path.closeSubpath()
            return path
        }

        private func blastArrowPath(tileSize: CGFloat, scale: CGFloat) -> CGPath {
            let shaftWidth = tileSize * 0.12 * scale
            let shaftHeight = tileSize * 0.30 * scale
            let headWidth = tileSize * 0.34 * scale
            let headHeight = tileSize * 0.22 * scale
            let bottomY = -(shaftHeight + headHeight) / 2
            let shaftTopY = bottomY + shaftHeight
            let topY = shaftTopY + headHeight
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -shaftWidth / 2, y: bottomY))
            path.addLine(to: CGPoint(x: shaftWidth / 2, y: bottomY))
            path.addLine(to: CGPoint(x: shaftWidth / 2, y: shaftTopY))
            path.addLine(to: CGPoint(x: headWidth / 2, y: shaftTopY))
            path.addLine(to: CGPoint(x: 0, y: topY))
            path.addLine(to: CGPoint(x: -headWidth / 2, y: shaftTopY))
            path.addLine(to: CGPoint(x: -shaftWidth / 2, y: shaftTopY))
            path.closeSubpath()
            return path
        }

        private func brokenCardPath(tileSize: CGFloat, scale: CGFloat) -> CGPath {
            let cardWidth = tileSize * 0.42 * scale
            let cardHeight = tileSize * 0.56 * scale
            return techCardPanelPath(tileSize: tileSize, width: cardWidth, height: cardHeight)
        }

        private func brokenCardCrackPath(tileSize: CGFloat, scale: CGFloat) -> CGPath {
            let s = tileSize * scale
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -s * 0.14, y: s * 0.24))
            path.addLine(to: CGPoint(x: s * 0.08, y: s * 0.05))
            path.addLine(to: CGPoint(x: -s * 0.02, y: -s * 0.02))
            path.addLine(to: CGPoint(x: s * 0.14, y: -s * 0.24))
            path.move(to: CGPoint(x: -s * 0.15, y: -s * 0.16))
            path.addLine(to: CGPoint(x: -s * 0.02, y: -s * 0.16))
            path.move(to: CGPoint(x: s * 0.03, y: s * 0.18))
            path.addLine(to: CGPoint(x: s * 0.17, y: s * 0.18))
            return path
        }

        private func brokenRelicGemPath(tileSize: CGFloat, scale: CGFloat) -> CGPath {
            let width = tileSize * 0.52 * scale
            let height = tileSize * 0.56 * scale
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: height / 2))
            path.addLine(to: CGPoint(x: width / 2, y: height * 0.10))
            path.addLine(to: CGPoint(x: width * 0.30, y: -height / 2))
            path.addLine(to: CGPoint(x: -width * 0.30, y: -height / 2))
            path.addLine(to: CGPoint(x: -width / 2, y: height * 0.10))
            path.closeSubpath()
            return path
        }

        private func techCardPanelPath(tileSize: CGFloat, width: CGFloat, height: CGFloat) -> CGPath {
            let cut = min(tileSize * 0.055, min(width, height) * 0.32)
            let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
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

        private func supportCrossPath(tileSize: CGFloat, scale: CGFloat) -> CGPath {
            let s = tileSize * scale
            let arm = s * 0.16
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -arm, y: s * 0.30))
            path.addLine(to: CGPoint(x: arm, y: s * 0.30))
            path.addLine(to: CGPoint(x: arm, y: arm))
            path.addLine(to: CGPoint(x: s * 0.30, y: arm))
            path.addLine(to: CGPoint(x: s * 0.30, y: -arm))
            path.addLine(to: CGPoint(x: arm, y: -arm))
            path.addLine(to: CGPoint(x: arm, y: -s * 0.30))
            path.addLine(to: CGPoint(x: -arm, y: -s * 0.30))
            path.addLine(to: CGPoint(x: -arm, y: -arm))
            path.addLine(to: CGPoint(x: -s * 0.30, y: -arm))
            path.addLine(to: CGPoint(x: -s * 0.30, y: arm))
            path.addLine(to: CGPoint(x: -arm, y: arm))
            path.closeSubpath()
            return path
        }

        private func blastArrowRotation(for direction: MoveVector) -> CGFloat {
            if direction.dx > 0 { return -.pi / 2 }
            if direction.dx < 0 { return .pi / 2 }
            if direction.dy < 0 { return .pi }
            return 0
        }

    }

    private extension SKColor {
        var isClearForDecorationRendering: Bool {
            cgColor.alpha <= 0.01
        }
    }

    private func usesNeonGridTheme(_ palette: GameScenePalette) -> Bool {
        palette.isNeonGridTheme
    }
#endif
