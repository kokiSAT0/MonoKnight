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
        private var warpVisualStyles: [String: WarpVisualStyle] = [:]
        private let maxWarpCircleLayers = 4
        private let impassableMarkerNodeName = "impassableRockMarker"

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
                removeImpassableDecoration(from: node)
                removeEffectDecoration(for: point)
                return
            }

            switch state.visitBehavior {
            case .impassable:
                applyImpassableStyle(to: node, layout: layout, palette: palette)
            case .single:
                applySingleVisitStyle(to: node, palette: palette)
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
            marker.fillColor = palette.boardTileUnvisited.withAlphaComponent(0.65)
            marker.strokeColor = palette.boardGridLine.withAlphaComponent(0.95)
            marker.lineWidth = max(1.0, layout.tileSize * 0.035)
            marker.position = .zero
            marker.isHidden = false
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
                guard decoration.fillNodes.count >= 2 else { return }
                let primaryFill = strokeColor.withAlphaComponent(0.88)
                let secondaryFill = strokeColor.withAlphaComponent(0.6)
                decoration.fillNodes[0].fillColor = primaryFill
                decoration.fillNodes[0].strokeColor = .clear
                decoration.fillNodes[0].alpha = 1.0
                decoration.fillNodes[1].fillColor = secondaryFill
                decoration.fillNodes[1].strokeColor = .clear
                decoration.fillNodes[1].alpha = 1.0
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
            let rect = CGRect(x: -cardWidth / 2, y: -cardHeight / 2, width: cardWidth, height: cardHeight)
            return CGPath(
                roundedRect: rect,
                cornerWidth: tileSize * 0.04 * scale,
                cornerHeight: tileSize * 0.04 * scale,
                transform: nil
            )
        }

        private func brokenCardCrackPath(tileSize: CGFloat, scale: CGFloat) -> CGPath {
            let s = tileSize * scale
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -s * 0.06, y: s * 0.25))
            path.addLine(to: CGPoint(x: s * 0.02, y: s * 0.08))
            path.addLine(to: CGPoint(x: -s * 0.04, y: -s * 0.02))
            path.addLine(to: CGPoint(x: s * 0.07, y: -s * 0.24))
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
#endif
