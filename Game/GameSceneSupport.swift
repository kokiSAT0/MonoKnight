#if canImport(SpriteKit)
    import SpriteKit
    #if canImport(UIKit)
        import UIKit
    #endif
    import SharedSupport

    enum LayoutTrigger: String {
        case didMove
        case didChangeSize
        case manual
    }

    final class GameSceneLayoutSupport {
        var tileSize: CGFloat = 0
        var gridOrigin: CGPoint = .zero
        private(set) var awaitingValidSceneSize = false

        func reset() {
            tileSize = 0
            gridOrigin = .zero
            awaitingValidSceneSize = false
        }

        func calculateLayout(sceneSize: CGSize, boardSize: Int, trigger: LayoutTrigger) {
            let length = min(sceneSize.width, sceneSize.height)

            guard length > 0 else {
                if awaitingValidSceneSize {
                    debugLog(
                        "GameScene.calculateLayout: trigger=\(trigger.rawValue) サイズ未確定のため待機継続 size=\(sceneSize)"
                    )
                } else {
                    debugLog(
                        "GameScene.calculateLayout: trigger=\(trigger.rawValue) シーンサイズがゼロのため初期レイアウトを延期 size=\(sceneSize)"
                    )
                }
                awaitingValidSceneSize = true
                tileSize = 0
                gridOrigin = .zero
                return
            }

            let wasAwaiting = awaitingValidSceneSize
            awaitingValidSceneSize = false

            let boardLength = CGFloat(boardSize)
            tileSize = length / boardLength
            let offsetX = (sceneSize.width - tileSize * boardLength) / 2
            let offsetY = (sceneSize.height - tileSize * boardLength) / 2
            gridOrigin = CGPoint(x: offsetX, y: offsetY)

            debugLog(
                "GameScene.calculateLayout: trigger=\(trigger.rawValue), size=\(sceneSize), tileSize=\(tileSize), gridOrigin=\(gridOrigin)"
            )

            if wasAwaiting {
                debugLog("GameScene.calculateLayout: 待機していた初期レイアウトを実行しました")
            }
        }

        func position(for point: GridPoint) -> CGPoint {
            let x = gridOrigin.x + CGFloat(point.x) * tileSize + tileSize / 2
            let y = gridOrigin.y + CGFloat(point.y) * tileSize + tileSize / 2
            return CGPoint(x: x, y: y)
        }

        func gridPoint(from location: CGPoint, board: Board) -> GridPoint? {
            guard tileSize > 0 else { return nil }
            let x = Int((location.x - gridOrigin.x) / tileSize)
            let y = Int((location.y - gridOrigin.y) / tileSize)
            let point = GridPoint(x: x, y: y)
            return board.contains(point) ? point : nil
        }
    }

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

    final class GameSceneHighlightRenderer {
        private(set) var highlightNodes: [BoardHighlightKind: [GridPoint: SKShapeNode]] = [:]
        private var latestSingleGuidePoints: Set<GridPoint> = []
        private var latestMultipleGuidePoints: Set<GridPoint> = []
        private var latestMultiStepGuidePoints: Set<GridPoint> = []
        private var latestWarpGuidePoints: Set<GridPoint> = []
        private var latestForcedSelectionPoints: Set<GridPoint> = []
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
            latestForcedSelectionPoints = []
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
                    .forcedSelection: latestForcedSelectionPoints,
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
            latestForcedSelectionPoints = highlights[.forcedSelection] ?? []
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
            case .forcedSelection:
                baseColor = palette.boardWarpHighlight
                strokeAlpha = 0.82
                strokeWidth = max(layout.tileSize * 0.07, 2.4)
                fillColor = baseColor.withAlphaComponent(0.16)
                zPosition = 1.1
            }

            let adjustedRect = baseRect.insetBy(
                dx: strokeWidth / 2 + overlapInset,
                dy: strokeWidth / 2 + overlapInset
            )
            node.path = CGPath(rect: adjustedRect, transform: nil)
            node.fillColor = fillColor
            node.strokeColor = baseColor.withAlphaComponent(strokeAlpha)
            node.lineWidth = strokeWidth
            node.glowWidth = 0
            node.lineJoin = .miter
            node.miterLimit = 2.5
            node.lineCap = .square
            node.position = layout.position(for: point)
            node.zPosition = zPosition
            node.isAntialiased = false
            node.blendMode = .alpha
        }
    }

    final class GameSceneKnightAnimator {
        enum PendingKnightState {
            case show(GridPoint)
            case hide
        }

        private(set) var knightNode: SKShapeNode?
        private(set) var knightPosition: GridPoint?
        private(set) var pendingKnightState: PendingKnightState?
        let transientEffectContainer = SKNode()

        func reset(in scene: SKScene) {
            if let knightNode {
                knightNode.removeAllActions()
                knightNode.removeFromParent()
            }
            knightNode = nil
            knightPosition = nil
            pendingKnightState = nil

            transientEffectContainer.removeAllActions()
            transientEffectContainer.removeAllChildren()
            transientEffectContainer.position = .zero
            transientEffectContainer.zPosition = 1.7
            transientEffectContainer.isHidden = false
            if transientEffectContainer.parent !== scene {
                scene.addChild(transientEffectContainer)
            }
        }

        func setupKnight(
            in scene: SKScene,
            boardSize: Int,
            palette: GameScenePalette,
            layout: GameSceneLayoutSupport
        ) {
            let radius = layout.tileSize * 0.4
            let node = SKShapeNode(circleOfRadius: radius)
            node.fillColor = palette.boardKnight
            node.strokeColor = .clear
            let initialPoint = knightPosition ?? GridPoint.center(of: boardSize)
            node.position = layout.position(for: initialPoint)
            node.zPosition = 2
            node.isHidden = knightPosition == nil
            scene.addChild(node)
            knightNode = node

            debugLog(
                "GameScene.setupKnight: radius=\(radius), position=\(node.position), hidden=\(node.isHidden)"
            )
        }

        func relayoutKnight(layout: GameSceneLayoutSupport) {
            guard let knightNode else { return }

            if let knightPosition {
                knightNode.position = layout.position(for: knightPosition)
            }

            let radius = layout.tileSize * 0.4
            let circleRect = CGRect(
                x: -radius,
                y: -radius,
                width: radius * 2,
                height: radius * 2
            )
            knightNode.path = CGPath(ellipseIn: circleRect, transform: nil)
        }

        func applyTheme(_ palette: GameScenePalette) {
            knightNode?.fillColor = palette.boardKnight
        }

        func removeKnight() {
            knightNode?.removeAllActions()
            knightNode?.removeFromParent()
            knightNode = nil
            knightPosition = nil
            pendingKnightState = nil
        }

        func moveKnight(
            to point: GridPoint?,
            in scene: SKScene,
            layout: GameSceneLayoutSupport,
            isLayoutReady: Bool,
            updateAccessibility: @escaping () -> Void
        ) {
            debugLog(
                "GameScene.moveKnight 要求: current=\(String(describing: knightPosition)), target=\(String(describing: point)), tileSize=\(layout.tileSize)"
            )

            guard isLayoutReady, let knightNode else {
                if let point {
                    pendingKnightState = .show(point)
                    knightPosition = point
                } else {
                    pendingKnightState = .hide
                    knightPosition = nil
                }
                debugLog("GameScene.moveKnight: レイアウト未確定のため移動を保留")
                return
            }

            if let point {
                if let skView = scene.view, skView.isPaused {
                    skView.isPaused = false
                }
                if scene.isPaused {
                    scene.isPaused = false
                }

                knightNode.isHidden = false
                performKnightPlacement(
                    to: point,
                    layout: layout,
                    animated: true,
                    updateAccessibility: updateAccessibility
                )
            } else {
                knightNode.removeAllActions()
                knightNode.isHidden = true
                knightPosition = nil
                updateAccessibility()
                debugLog("GameScene.moveKnight: 駒を非表示にしました")
            }
        }

        func playWarpTransition(
            using resolution: MovementResolution,
            in scene: SKScene,
            layout: GameSceneLayoutSupport,
            isLayoutReady: Bool,
            warpColor: @escaping (GridPoint) -> SKColor,
            updateAccessibility: @escaping () -> Void
        ) {
            guard isLayoutReady, let knightNode else {
                moveKnight(
                    to: resolution.finalPosition,
                    in: scene,
                    layout: layout,
                    isLayoutReady: isLayoutReady,
                    updateAccessibility: updateAccessibility
                )
                return
            }

            guard let warpEvent = resolution.appliedEffects.first(where: { applied in
                if case .warp = applied.effect { return true }
                return false
            }) else {
                moveKnight(
                    to: resolution.finalPosition,
                    in: scene,
                    layout: layout,
                    isLayoutReady: isLayoutReady,
                    updateAccessibility: updateAccessibility
                )
                return
            }

            guard case .warp(_, let destination) = warpEvent.effect else {
                moveKnight(
                    to: resolution.finalPosition,
                    in: scene,
                    layout: layout,
                    isLayoutReady: isLayoutReady,
                    updateAccessibility: updateAccessibility
                )
                return
            }

            var approachPoints: [GridPoint] = []
            for point in resolution.path {
                approachPoints.append(point)
                if point == warpEvent.point { break }
            }
            guard approachPoints.contains(warpEvent.point) else {
                moveKnight(
                    to: resolution.finalPosition,
                    in: scene,
                    layout: layout,
                    isLayoutReady: isLayoutReady,
                    updateAccessibility: updateAccessibility
                )
                return
            }

            knightNode.removeAllActions()
            knightNode.isHidden = false

            let approachDuration: TimeInterval = 0.18
            let warpOutDuration: TimeInterval = 0.14
            let warpInDuration: TimeInterval = 0.14

            var sequence: [SKAction] = []

            if !approachPoints.isEmpty {
                let stepDuration = approachDuration / Double(max(1, approachPoints.count))
                for point in approachPoints {
                    let move = SKAction.move(to: layout.position(for: point), duration: stepDuration)
                    move.timingMode = .easeInEaseOut
                    let updateState = SKAction.run { [weak self] in
                        guard let self else { return }
                        self.knightPosition = point
                        updateAccessibility()
                    }
                    sequence.append(SKAction.sequence([move, updateState]))
                }
            }

            sequence.append(SKAction.run { [weak self] in
                guard let self else { return }
                self.emitWarpRing(
                    at: warpEvent.point,
                    layout: layout,
                    color: warpColor(warpEvent.point),
                    expanding: true
                )
                self.animateWarpArrow(at: warpEvent.point)
            })

            let warpOut = SKAction.group([
                SKAction.scale(to: 0.2, duration: warpOutDuration),
                SKAction.fadeOut(withDuration: warpOutDuration),
            ])
            warpOut.timingMode = .easeIn
            sequence.append(warpOut)

            sequence.append(SKAction.run { [weak self] in
                guard let self, let knightNode = self.knightNode else { return }
                knightNode.position = layout.position(for: destination)
                knightNode.setScale(0.2)
                knightNode.alpha = 0.0
                self.emitWarpRing(
                    at: destination,
                    layout: layout,
                    color: warpColor(destination),
                    expanding: false
                )
            })

            let warpIn = SKAction.group([
                SKAction.fadeIn(withDuration: warpInDuration),
                SKAction.scale(to: 1.0, duration: warpInDuration),
            ])
            warpIn.timingMode = .easeOut
            sequence.append(warpIn)

            sequence.append(SKAction.run { [weak self] in
                guard let self, let knightNode = self.knightNode else { return }
                knightNode.alpha = 1.0
                knightNode.setScale(1.0)
                self.knightPosition = destination
                updateAccessibility()
            })

            knightNode.run(SKAction.sequence(sequence))
        }

        func flushPendingState(
            isLayoutReady: Bool,
            layout: GameSceneLayoutSupport,
            updateAccessibility: @escaping () -> Void
        ) {
            guard isLayoutReady, let knightNode, let pendingKnightState else { return }

            self.pendingKnightState = nil
            switch pendingKnightState {
            case .show(let point):
                knightNode.isHidden = false
                performKnightPlacement(
                    to: point,
                    layout: layout,
                    animated: false,
                    updateAccessibility: updateAccessibility
                )
            case .hide:
                knightNode.removeAllActions()
                knightNode.isHidden = true
                knightPosition = nil
                updateAccessibility()
            }
        }

        private func performKnightPlacement(
            to point: GridPoint,
            layout: GameSceneLayoutSupport,
            animated: Bool,
            updateAccessibility: @escaping () -> Void
        ) {
            guard let knightNode else { return }

            let destination = layout.position(for: point)
            knightNode.removeAllActions()

            if animated {
                let move = SKAction.move(to: destination, duration: 0.2)
                knightNode.run(move)
            } else {
                knightNode.position = destination
            }

            knightPosition = point
            updateAccessibility()

            let positionDescription = knightPosition.map { "\($0)" } ?? "nil"
            debugLog("GameScene.moveKnight 完了: 現在位置=\(positionDescription)")
        }

        private func emitWarpRing(
            at point: GridPoint,
            layout: GameSceneLayoutSupport,
            color: SKColor,
            expanding: Bool
        ) {
            guard layout.tileSize > 0 else { return }

            let radius = layout.tileSize * 0.36
            let ring = SKShapeNode(circleOfRadius: radius)
            ring.name = "transientWarpRing"
            ring.lineWidth = max(1.0, layout.tileSize * 0.06)
            ring.strokeColor = color
            ring.fillColor = color.withAlphaComponent(0.18)
            ring.isAntialiased = true
            ring.position = layout.position(for: point)
            ring.zPosition = 0
            ring.alpha = expanding ? 0.9 : 0.8
            let startScale: CGFloat = expanding ? 0.4 : 1.4
            let targetScale: CGFloat = expanding ? 1.55 : 0.55
            ring.setScale(startScale)
            transientEffectContainer.addChild(ring)

            let duration: TimeInterval = 0.2
            let scale = SKAction.scale(to: targetScale, duration: duration)
            scale.timingMode = .easeOut
            let fade = SKAction.fadeOut(withDuration: duration)
            fade.timingMode = .easeOut
            ring.run(SKAction.sequence([SKAction.group([scale, fade]), SKAction.removeFromParent()]))
        }

        private func animateWarpArrow(at point: GridPoint) {
            _ = point
        }
    }

    #if canImport(UIKit)
        final class GameSceneAccessibilitySupport {
            private var elementsCache: [UIAccessibilityElement] = []

            private final class TileAccessibilityElement: UIAccessibilityElement {
                let point: GridPoint
                weak var owner: GameScene?

                init(point: GridPoint, owner: GameScene) {
                    self.point = point
                    self.owner = owner
                    super.init(accessibilityContainer: owner)
                }

                override func accessibilityActivate() -> Bool {
                    owner?.gameCore?.handleTap(at: point)
                    return true
                }
            }

            var elements: [Any] {
                elementsCache
            }

            func reset() {
                elementsCache = []
            }

            func update(
                board: Board,
                knightPosition: GridPoint?,
                layout: GameSceneLayoutSupport,
                owner: GameScene
            ) {
                guard layout.tileSize > 0 else {
                    elementsCache = []
                    return
                }

                var elements: [UIAccessibilityElement] = []
                for y in 0..<board.size {
                    for x in 0..<board.size {
                        let point = GridPoint(x: x, y: y)
                        let element = TileAccessibilityElement(point: point, owner: owner)
                        element.accessibilityFrameInContainerSpace = CGRect(
                            x: layout.gridOrigin.x + CGFloat(x) * layout.tileSize,
                            y: layout.gridOrigin.y + CGFloat(y) * layout.tileSize,
                            width: layout.tileSize,
                            height: layout.tileSize
                        )

                        let statusText: String
                        if let state = board.state(at: point) {
                            if state.isImpassable {
                                statusText = "移動不可"
                            } else if state.isVisited {
                                statusText = "踏破済み"
                            } else if state.requiresMultipleVisits {
                                statusText = "踏破まであと\(state.remainingVisits)回"
                            } else {
                                statusText = "未踏破"
                            }
                        } else {
                            statusText = "未踏破"
                        }

                        if let knightPosition, point == knightPosition {
                            element.accessibilityLabel = "駒あり・" + statusText
                        } else {
                            element.accessibilityLabel = statusText
                        }
                        element.accessibilityTraits = [.button]
                        elements.append(element)
                    }
                }
                elementsCache = elements
            }
        }
    #endif
#endif
