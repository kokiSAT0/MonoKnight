#if canImport(SpriteKit)
    import SpriteKit
    import SharedSupport

    final class GameSceneKnightAnimator {
        static let movementReplayStepDuration: TimeInterval = 0.16
        static let movementReplayHoldDuration: TimeInterval = 0.06
        static let movementReplayDamageHoldDuration: TimeInterval = 0.16
        static let movementReplayWarpOutDuration: TimeInterval = 0.14
        static let movementReplayWarpInDuration: TimeInterval = 0.14

        enum PendingKnightState {
            case show(GridPoint)
            case hide
        }

        private(set) var knightNode: SKShapeNode?
        private(set) var knightPosition: GridPoint?
        private(set) var pendingKnightState: PendingKnightState?
        private var knightBaseFillColor = SKColor.white
        private var currentPalette = GameScenePalette.fallback
        private var currentTileSize: CGFloat = 0
        private let damageFlashActionKey = "damageFlash"
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
            currentPalette = palette
            currentTileSize = layout.tileSize
            let node = SKShapeNode()
            knightBaseFillColor = palette.boardKnight
            configurePenguinAppearance(node, tileSize: layout.tileSize, palette: palette)
            let initialPoint = knightPosition ?? GridPoint.center(of: boardSize)
            node.position = layout.position(for: initialPoint)
            node.zPosition = 2
            node.isHidden = knightPosition == nil
            scene.addChild(node)
            knightNode = node

            debugLog("GameScene.setupKnight: モノを配置 position=\(node.position), hidden=\(node.isHidden)")
        }

        func relayoutKnight(layout: GameSceneLayoutSupport) {
            guard let knightNode else { return }

            if let knightPosition {
                knightNode.position = layout.position(for: knightPosition)
            }

            currentTileSize = layout.tileSize
            configurePenguinAppearance(knightNode, tileSize: layout.tileSize, palette: currentPalette)
        }

        func applyTheme(_ palette: GameScenePalette) {
            currentPalette = palette
            knightBaseFillColor = palette.boardKnight
            if let knightNode {
                configurePenguinAppearance(knightNode, tileSize: currentTileSize, palette: palette)
            }
        }

        func removeKnight() {
            stopKnightActionsRestoringFill()
            knightNode?.removeFromParent()
            knightNode = nil
            knightPosition = nil
            pendingKnightState = nil
        }

        func moveKnight(
            to point: GridPoint?,
            motionStyle: PlayerMotionStyle = .waddle,
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
                    motionStyle: motionStyle,
                    updateAccessibility: updateAccessibility
                )
            } else {
                stopKnightActionsRestoringFill()
                knightNode.isHidden = true
                knightPosition = nil
                updateAccessibility()
                debugLog("GameScene.moveKnight: 駒を非表示にしました")
            }
        }

        func placeKnightForMovementReplayStart(
            at point: GridPoint?,
            layout: GameSceneLayoutSupport,
            isLayoutReady: Bool,
            updateAccessibility: @escaping () -> Void
        ) {
            guard isLayoutReady, let knightNode else {
                if let point {
                    pendingKnightState = .show(point)
                    knightPosition = point
                } else {
                    pendingKnightState = .hide
                    knightPosition = nil
                }
                return
            }

            if let point {
                knightNode.isHidden = false
                performKnightPlacement(
                    to: point,
                    layout: layout,
                    animated: false,
                    motionStyle: .waddle,
                    updateAccessibility: updateAccessibility
                )
            } else {
                stopKnightActionsRestoringFill()
                knightNode.isHidden = true
                knightPosition = nil
                updateAccessibility()
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
                switch applied.effect {
                case .warp, .returnWarp:
                    return true
                default:
                    return false
                }
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

            let destination: GridPoint
            switch warpEvent.effect {
            case .warp(_, let point), .returnWarp(let point):
                destination = point
            default:
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

            stopKnightActionsRestoringFill()
            knightNode.isPaused = false
            knightNode.speed = 1
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

        func playMovementTransition(
            using resolution: MovementResolution,
            motionStyle: PlayerMotionStyle,
            in scene: SKScene,
            layout: GameSceneLayoutSupport,
            isLayoutReady: Bool,
            warpColor: @escaping (GridPoint) -> SKColor,
            updateAccessibility: @escaping () -> Void,
            onStep: @escaping (MovementResolution.PresentationStep) -> Void = { _ in },
            onCompletion: @escaping () -> Void = {}
        ) {
            guard isLayoutReady, let knightNode, !resolution.path.isEmpty else {
                moveKnight(
                    to: resolution.finalPosition,
                    in: scene,
                    layout: layout,
                    isLayoutReady: isLayoutReady,
                    updateAccessibility: updateAccessibility
                )
                resolution.presentationSteps.forEach(onStep)
                onCompletion()
                return
            }

            if let skView = scene.view, skView.isPaused {
                skView.isPaused = false
            }
            if scene.isPaused {
                scene.isPaused = false
            }

            stopKnightActionsRestoringFill()
            knightNode.isPaused = false
            knightNode.isHidden = false

            let stepDuration = Self.movementReplayStepDuration
            var sequence: [SKAction] = []

            if let warpReplay = warpReplayContext(for: resolution) {
                for index in 0...warpReplay.sourceIndex {
                    let point = resolution.path[index]
                    let move = movementAction(
                        to: layout.position(for: point),
                        duration: stepDuration,
                        style: motionStyle
                    )
                    let step = resolution.presentationSteps.indices.contains(index)
                        ? resolution.presentationSteps[index]
                        : nil
                    let updateState = SKAction.run { [weak self] in
                        guard let self else { return }
                        self.knightPosition = point
                        updateAccessibility()
                        if let step {
                            onStep(step)
                        }
                    }
                    var stepActions: [SKAction] = [move, updateState]
                    let holdDuration = Self.holdDuration(after: step, isLastStep: false)
                    if holdDuration > 0 {
                        stepActions.append(SKAction.wait(forDuration: holdDuration))
                    }
                    sequence.append(SKAction.sequence(stepActions))
                }

                sequence.append(SKAction.run { [weak self] in
                    guard let self else { return }
                    self.emitWarpRing(
                        at: warpReplay.source,
                        layout: layout,
                        color: warpColor(warpReplay.source),
                        expanding: true
                    )
                    self.animateWarpArrow(at: warpReplay.source)
                })

                let warpOut = SKAction.group([
                    SKAction.scale(to: 0.2, duration: Self.movementReplayWarpOutDuration),
                    SKAction.fadeOut(withDuration: Self.movementReplayWarpOutDuration),
                ])
                warpOut.timingMode = .easeIn
                sequence.append(warpOut)

                sequence.append(SKAction.run { [weak self] in
                    guard let self, let knightNode = self.knightNode else { return }
                    knightNode.position = layout.position(for: warpReplay.destination)
                    knightNode.setScale(0.2)
                    knightNode.alpha = 0.0
                    self.emitWarpRing(
                        at: warpReplay.destination,
                        layout: layout,
                        color: warpColor(warpReplay.destination),
                        expanding: false
                    )
                })

                let warpIn = SKAction.group([
                    SKAction.fadeIn(withDuration: Self.movementReplayWarpInDuration),
                    SKAction.scale(to: 1.0, duration: Self.movementReplayWarpInDuration),
                ])
                warpIn.timingMode = .easeOut
                sequence.append(warpIn)

                sequence.append(SKAction.run { [weak self] in
                    guard let self, let knightNode = self.knightNode else { return }
                    knightNode.alpha = 1.0
                    knightNode.setScale(1.0)
                    self.knightPosition = warpReplay.destination
                    updateAccessibility()
                    if let destinationStep = warpReplay.destinationStep {
                        onStep(destinationStep)
                    }
                })

                let destinationHoldDuration = Self.holdDuration(
                    after: warpReplay.destinationStep,
                    isLastStep: true
                )
                if destinationHoldDuration > 0 {
                    sequence.append(SKAction.wait(forDuration: destinationHoldDuration))
                }
                sequence.append(SKAction.run(onCompletion))

                knightNode.run(SKAction.sequence(sequence))
                return
            }

            for (index, point) in resolution.path.enumerated() {
                let move = movementAction(
                    to: layout.position(for: point),
                    duration: stepDuration,
                    style: motionStyle
                )
                let step = resolution.presentationSteps.indices.contains(index)
                    ? resolution.presentationSteps[index]
                    : nil
                let updateState = SKAction.run { [weak self] in
                    guard let self else { return }
                    self.knightPosition = point
                    updateAccessibility()
                    if let step {
                        onStep(step)
                    }
                }
                var stepActions: [SKAction] = [move, updateState]
                let holdDuration = Self.holdDuration(
                    after: step,
                    isLastStep: index == resolution.path.count - 1
                )
                if holdDuration > 0 {
                    stepActions.append(SKAction.wait(forDuration: holdDuration))
                }
                sequence.append(SKAction.sequence(stepActions))
            }
            sequence.append(SKAction.run(onCompletion))

            knightNode.run(SKAction.sequence(sequence))
        }

        func playMovementReplaySegment(
            to point: GridPoint,
            motionStyle: PlayerMotionStyle,
            step: MovementResolution.PresentationStep?,
            isLastStep: Bool,
            warpSource: GridPoint?,
            in scene: SKScene,
            layout: GameSceneLayoutSupport,
            isLayoutReady: Bool,
            warpColor: @escaping (GridPoint) -> SKColor,
            updateAccessibility: @escaping () -> Void,
            onStep: @escaping (MovementResolution.PresentationStep) -> Void,
            onCompletion: @escaping () -> Void
        ) {
            guard isLayoutReady, let knightNode else {
                moveKnight(
                    to: point,
                    in: scene,
                    layout: layout,
                    isLayoutReady: isLayoutReady,
                    updateAccessibility: updateAccessibility
                )
                if let step {
                    onStep(step)
                }
                onCompletion()
                return
            }

            if let skView = scene.view, skView.isPaused {
                skView.isPaused = false
            }
            if scene.isPaused {
                scene.isPaused = false
            }

            stopKnightActionsRestoringFill()
            knightNode.isPaused = false
            knightNode.speed = 1
            knightNode.isHidden = false

            let holdDuration = Self.holdDuration(after: step, isLastStep: isLastStep)
            var sequence: [SKAction] = []
            if let warpSource {
                sequence.append(SKAction.run { [weak self] in
                    guard let self else { return }
                    self.emitWarpRing(
                        at: warpSource,
                        layout: layout,
                        color: warpColor(warpSource),
                        expanding: true
                    )
                    self.animateWarpArrow(at: warpSource)
                })

                let warpOut = SKAction.group([
                    SKAction.scale(to: 0.2, duration: Self.movementReplayWarpOutDuration),
                    SKAction.fadeOut(withDuration: Self.movementReplayWarpOutDuration),
                ])
                warpOut.timingMode = .easeIn
                sequence.append(warpOut)

                sequence.append(SKAction.run { [weak self] in
                    guard let self, let knightNode = self.knightNode else { return }
                    knightNode.position = layout.position(for: point)
                    knightNode.setScale(0.2)
                    knightNode.alpha = 0.0
                    self.emitWarpRing(
                        at: point,
                        layout: layout,
                        color: warpColor(point),
                        expanding: false
                    )
                })

                let warpIn = SKAction.group([
                    SKAction.fadeIn(withDuration: Self.movementReplayWarpInDuration),
                    SKAction.scale(to: 1.0, duration: Self.movementReplayWarpInDuration),
                ])
                warpIn.timingMode = .easeOut
                sequence.append(warpIn)
            } else {
                if motionStyle == .bellySlide || motionStyle == .forcedSlide {
                    emitSnowTrail(at: knightNode.position, tileSize: layout.tileSize)
                }
                let move = movementAction(
                    to: layout.position(for: point),
                    duration: Self.movementReplayStepDuration,
                    style: motionStyle
                )
                sequence.append(move)
            }

            sequence.append(SKAction.run { [weak self] in
                guard let self, let knightNode = self.knightNode else { return }
                knightNode.alpha = 1.0
                knightNode.setScale(1.0)
                self.knightPosition = point
                updateAccessibility()
                if let step {
                    onStep(step)
                }
            })
            if holdDuration > 0 {
                sequence.append(SKAction.wait(forDuration: holdDuration))
            }
            sequence.append(SKAction.run(onCompletion))

            knightNode.run(SKAction.sequence(sequence))
        }

        func pauseMovementTransitionForOverlay() {
            knightNode?.speed = 0
        }

        func resumeMovementTransitionAfterOverlay() {
            knightNode?.isPaused = false
            knightNode?.speed = 1
        }

        func movementTransitionSpeedForTesting() -> CGFloat? {
            knightNode?.speed
        }

#if DEBUG
        func knightFillColorForTesting() -> SKColor? {
            knightNode?.fillColor
        }
#endif

        private struct WarpReplayContext {
            let source: GridPoint
            let sourceIndex: Int
            let destination: GridPoint
            let destinationStep: MovementResolution.PresentationStep?
        }

        private func warpReplayContext(for resolution: MovementResolution) -> WarpReplayContext? {
            guard let warpEvent = resolution.appliedEffects.first(where: { applied in
                switch applied.effect {
                case .warp, .returnWarp:
                    return true
                default:
                    return false
                }
            }),
                  let sourceIndex = resolution.path.firstIndex(of: warpEvent.point)
            else {
                return nil
            }
            let destination: GridPoint
            switch warpEvent.effect {
            case .warp(_, let point), .returnWarp(let point):
                destination = point
            default:
                return nil
            }

            let destinationIndex = resolution.path[(sourceIndex + 1)...]
                .firstIndex(of: destination)
            let destinationStep = destinationIndex.flatMap { index in
                resolution.presentationSteps.indices.contains(index)
                    ? resolution.presentationSteps[index]
                    : nil
            }

            return WarpReplayContext(
                source: warpEvent.point,
                sourceIndex: sourceIndex,
                destination: destination,
                destinationStep: destinationStep
            )
        }

        static func holdDuration(
            after step: MovementResolution.PresentationStep?,
            isLastStep: Bool
        ) -> TimeInterval {
            if step?.tookDamage == true {
                return movementReplayDamageHoldDuration
            }
            return isLastStep ? 0 : movementReplayHoldDuration
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
                    motionStyle: .waddle,
                    updateAccessibility: updateAccessibility
                )
            case .hide:
                stopKnightActionsRestoringFill()
                knightNode.isHidden = true
                knightPosition = nil
                updateAccessibility()
            }
        }

        func playDungeonFallEffect(
            at point: GridPoint,
            in scene: SKScene,
            layout: GameSceneLayoutSupport,
            isLayoutReady: Bool
        ) {
            guard isLayoutReady, layout.tileSize > 0 else { return }
            if transientEffectContainer.parent !== scene {
                scene.addChild(transientEffectContainer)
            }

            let center = layout.position(for: point)
            let shadowRadius = layout.tileSize * 0.30
            let shadow = SKShapeNode(ellipseOf: CGSize(width: shadowRadius * 2.2, height: shadowRadius * 0.8))
            shadow.name = "transientDungeonFallShadow"
            shadow.position = center
            shadow.fillColor = SKColor.black.withAlphaComponent(0.28)
            shadow.strokeColor = .clear
            shadow.zPosition = 0.05
            shadow.setScale(0.45)
            transientEffectContainer.addChild(shadow)

            let ring = SKShapeNode(circleOfRadius: layout.tileSize * 0.34)
            ring.name = "transientDungeonFallRing"
            ring.position = center
            ring.strokeColor = SKColor.black.withAlphaComponent(0.36)
            ring.fillColor = SKColor.clear
            ring.lineWidth = max(1.0, layout.tileSize * 0.045)
            ring.zPosition = 0.06
            ring.setScale(0.35)
            transientEffectContainer.addChild(ring)

            if let knightNode {
                stopKnightActionsRestoringFill()
                let sink = SKAction.group([
                    SKAction.scale(to: 0.52, duration: 0.12),
                    SKAction.fadeAlpha(to: 0.45, duration: 0.12)
                ])
                sink.timingMode = .easeIn
                let restore = SKAction.group([
                    SKAction.scale(to: 1.0, duration: 0.12),
                    SKAction.fadeAlpha(to: 1.0, duration: 0.12)
                ])
                restore.timingMode = .easeOut
                knightNode.run(.sequence([sink, restore]))
            }

            let expandShadow = SKAction.group([
                SKAction.scale(to: 1.1, duration: 0.22),
                SKAction.fadeOut(withDuration: 0.22)
            ])
            expandShadow.timingMode = .easeOut
            shadow.run(.sequence([expandShadow, .removeFromParent()]))

            let expandRing = SKAction.group([
                SKAction.scale(to: 1.35, duration: 0.22),
                SKAction.fadeOut(withDuration: 0.22)
            ])
            expandRing.timingMode = .easeOut
            ring.run(.sequence([expandRing, .removeFromParent()]))
        }

        func playDamageEffect(
            in scene: SKScene,
            palette: GameScenePalette,
            layout: GameSceneLayoutSupport,
            isLayoutReady: Bool
        ) {
            guard isLayoutReady,
                  layout.tileSize > 0,
                  let knightNode,
                  !knightNode.isHidden
            else { return }

            if transientEffectContainer.parent !== scene {
                scene.addChild(transientEffectContainer)
            }

            let impact = SKShapeNode(circleOfRadius: layout.tileSize * 0.32)
            impact.name = "transientDamageImpact"
            impact.position = knightNode.position
            impact.strokeColor = SKColor.systemRed.withAlphaComponent(0.72)
            impact.fillColor = SKColor.systemRed.withAlphaComponent(0.18)
            impact.lineWidth = max(1.5, layout.tileSize * 0.055)
            impact.glowWidth = max(2.0, layout.tileSize * 0.08)
            impact.zPosition = 0.12
            impact.setScale(0.72)
            transientEffectContainer.addChild(impact)

            let flashColor = SKColor.systemRed
            knightBaseFillColor = palette.boardKnight
            knightNode.removeAction(forKey: damageFlashActionKey)
            knightNode.fillColor = flashColor
            let restore = SKAction.run { [weak knightNode] in
                knightNode?.fillColor = palette.boardKnight
            }
            let flash = SKAction.sequence([
                SKAction.wait(forDuration: 0.08),
                restore,
                SKAction.wait(forDuration: 0.07),
                SKAction.run { [weak knightNode] in
                    knightNode?.fillColor = flashColor
                },
                SKAction.wait(forDuration: 0.06),
                restore
            ])
            knightNode.run(flash, withKey: damageFlashActionKey)

            let pulse = SKAction.group([
                SKAction.scale(to: 1.26, duration: 0.24),
                SKAction.fadeOut(withDuration: 0.24)
            ])
            pulse.timingMode = .easeOut
            impact.run(.sequence([pulse, .removeFromParent()]))
        }

        func playLandingEffect(
            at point: GridPoint,
            in scene: SKScene,
            palette: GameScenePalette,
            layout: GameSceneLayoutSupport,
            isLayoutReady: Bool
        ) {
            guard isLayoutReady, layout.tileSize > 0 else { return }
            ensureTransientContainer(in: scene)

            let ring = SKShapeNode(circleOfRadius: layout.tileSize * 0.28)
            ring.name = "transientLandingPulse"
            ring.position = layout.position(for: point)
            ring.strokeColor = palette.boardKnight.withAlphaComponent(0.72)
            ring.fillColor = palette.boardKnight.withAlphaComponent(0.10)
            ring.lineWidth = max(1.2, layout.tileSize * 0.038)
            ring.glowWidth = max(1.0, layout.tileSize * 0.035)
            ring.zPosition = 0.10
            ring.isAntialiased = true
            ring.setScale(0.72)
            transientEffectContainer.addChild(ring)

            let pulse = SKAction.group([
                SKAction.scale(to: 1.28, duration: 0.18),
                SKAction.fadeOut(withDuration: 0.18)
            ])
            pulse.timingMode = .easeOut
            ring.run(.sequence([pulse, .removeFromParent()]))
        }

        func playInvalidSelectionFeedback(
            at point: GridPoint?,
            in scene: SKScene,
            palette: GameScenePalette,
            layout: GameSceneLayoutSupport,
            isLayoutReady: Bool
        ) {
            guard isLayoutReady, layout.tileSize > 0 else { return }
            ensureTransientContainer(in: scene)

            if let point {
                let size = layout.tileSize * 0.74
                let marker = SKShapeNode(rectOf: CGSize(width: size, height: size), cornerRadius: layout.tileSize * 0.08)
                marker.name = "transientInvalidSelectionPulse"
                marker.position = layout.position(for: point)
                marker.strokeColor = SKColor.systemRed.withAlphaComponent(0.70)
                marker.fillColor = SKColor.systemRed.withAlphaComponent(0.10)
                marker.lineWidth = max(1.4, layout.tileSize * 0.04)
                marker.glowWidth = max(1.0, layout.tileSize * 0.03)
                marker.zPosition = 1.42
                marker.isAntialiased = true
                transientEffectContainer.addChild(marker)

                let nudge = layout.tileSize * 0.045
                let shake = SKAction.sequence([
                    .moveBy(x: -nudge, y: 0, duration: 0.035),
                    .moveBy(x: nudge * 2, y: 0, duration: 0.07),
                    .moveBy(x: -nudge, y: 0, duration: 0.035)
                ])
                let fade = SKAction.fadeOut(withDuration: 0.18)
                marker.run(.sequence([.group([shake, fade]), .removeFromParent()]))
            } else if let knightNode, !knightNode.isHidden {
                let nudge = layout.tileSize * 0.05
                let shake = SKAction.sequence([
                    .moveBy(x: -nudge, y: 0, duration: 0.035),
                    .moveBy(x: nudge * 2, y: 0, duration: 0.07),
                    .moveBy(x: -nudge, y: 0, duration: 0.035)
                ])
                knightNode.run(shake, withKey: "invalidSelectionShake")
            }
        }

        func playPickupCollectionEffect(
            at point: GridPoint,
            isRelic: Bool,
            in scene: SKScene,
            palette: GameScenePalette,
            layout: GameSceneLayoutSupport,
            isLayoutReady: Bool
        ) {
            guard isLayoutReady, layout.tileSize > 0 else { return }
            ensureTransientContainer(in: scene)

            let color = isRelic ? palette.boardTileEffectPreserveCard : palette.boardGuideHighlight
            let center = layout.position(for: point)
            let radius = layout.tileSize * (isRelic ? 0.30 : 0.24)

            let sparkle = SKShapeNode(circleOfRadius: radius)
            sparkle.name = isRelic ? "transientRelicPickupPulse" : "transientCardPickupPulse"
            sparkle.position = center
            sparkle.strokeColor = color.withAlphaComponent(0.88)
            sparkle.fillColor = color.withAlphaComponent(isRelic ? 0.20 : 0.14)
            sparkle.lineWidth = max(1.2, layout.tileSize * 0.04)
            sparkle.glowWidth = max(1.5, layout.tileSize * 0.05)
            sparkle.zPosition = 1.45
            sparkle.isAntialiased = true
            transientEffectContainer.addChild(sparkle)

            let lift = SKAction.moveBy(x: 0, y: layout.tileSize * 0.16, duration: 0.22)
            lift.timingMode = .easeOut
            let scale = SKAction.scale(to: isRelic ? 1.34 : 1.22, duration: 0.22)
            scale.timingMode = .easeOut
            let fade = SKAction.fadeOut(withDuration: 0.22)
            sparkle.run(.sequence([.group([lift, scale, fade]), .removeFromParent()]))
        }

        private func performKnightPlacement(
            to point: GridPoint,
            layout: GameSceneLayoutSupport,
            animated: Bool,
            motionStyle: PlayerMotionStyle,
            updateAccessibility: @escaping () -> Void
        ) {
            guard let knightNode else { return }

            let destination = layout.position(for: point)
            stopKnightActionsRestoringFill()

            if animated {
                if motionStyle == .bellySlide || motionStyle == .forcedSlide {
                    emitSnowTrail(at: knightNode.position, tileSize: layout.tileSize)
                }
                knightNode.run(movementAction(to: destination, duration: 0.2, style: motionStyle))
            } else {
                knightNode.position = destination
            }

            knightPosition = point
            updateAccessibility()

            let positionDescription = knightPosition.map { "\($0)" } ?? "nil"
            debugLog("GameScene.moveKnight 完了: 現在位置=\(positionDescription)")
        }

        private func stopKnightActionsRestoringFill() {
            knightNode?.removeAllActions()
            restoreKnightFillColor()
        }

        private func restoreKnightFillColor() {
            knightNode?.fillColor = knightBaseFillColor
        }

        private func movementAction(
            to destination: CGPoint,
            duration: TimeInterval,
            style: PlayerMotionStyle
        ) -> SKAction {
            let move = SKAction.move(to: destination, duration: duration)
            move.timingMode = style == .bellySlide ? .easeOut : .easeInEaseOut

            switch style {
            case .waddle:
                let sway = SKAction.sequence([
                    .rotate(toAngle: -0.10, duration: duration * 0.25, shortestUnitArc: true),
                    .rotate(toAngle: 0.10, duration: duration * 0.50, shortestUnitArc: true),
                    .rotate(toAngle: 0, duration: duration * 0.25, shortestUnitArc: true)
                ])
                return .group([move, sway])
            case .bellySlide:
                let posture = SKAction.sequence([
                    .scaleY(to: 0.76, duration: duration * 0.25),
                    .scaleY(to: 0.84, duration: duration * 0.50),
                    .scaleY(to: 1.0, duration: duration * 0.25)
                ])
                return .group([move, posture])
            case .flutterJump:
                let jump = SKAction.sequence([
                    .group([
                        .scaleX(to: 1.14, duration: duration * 0.5),
                        .scaleY(to: 1.22, duration: duration * 0.5)
                    ]),
                    .scale(to: 1.0, duration: duration * 0.5)
                ])
                return .group([move, jump])
            case .forcedSlide:
                let stumble = SKAction.sequence([
                    .rotate(toAngle: 0.22, duration: duration * 0.35, shortestUnitArc: true),
                    .rotate(toAngle: -0.12, duration: duration * 0.35, shortestUnitArc: true),
                    .rotate(toAngle: 0, duration: duration * 0.30, shortestUnitArc: true)
                ])
                return .group([move, stumble])
            case .warp, .fall:
                return move
            }
        }

        private func configurePenguinAppearance(
            _ node: SKShapeNode,
            tileSize: CGFloat,
            palette: GameScenePalette
        ) {
            guard tileSize > 0 else { return }
            node.removeAllChildren()
            let bodyRect = CGRect(
                x: -tileSize * 0.30,
                y: -tileSize * 0.37,
                width: tileSize * 0.60,
                height: tileSize * 0.74
            )
            node.path = CGPath(ellipseIn: bodyRect, transform: nil)
            node.fillColor = palette.boardKnight
            node.strokeColor = SKColor.white.withAlphaComponent(0.88)
            node.lineWidth = max(1.0, tileSize * 0.035)
            node.name = "monoPenguin"

            let wingSize = CGSize(width: tileSize * 0.18, height: tileSize * 0.42)
            for side in [-1.0, 1.0] {
                let wing = SKShapeNode(ellipseOf: wingSize)
                wing.name = side < 0 ? "monoLeftWing" : "monoRightWing"
                wing.fillColor = palette.boardKnight
                wing.strokeColor = SKColor.white.withAlphaComponent(0.45)
                wing.lineWidth = max(0.8, tileSize * 0.022)
                wing.position = CGPoint(x: CGFloat(side) * tileSize * 0.27, y: -tileSize * 0.02)
                wing.zRotation = CGFloat(side) * -0.24
                wing.zPosition = 0.1
                node.addChild(wing)
            }

            let belly = SKShapeNode(ellipseOf: CGSize(width: tileSize * 0.38, height: tileSize * 0.48))
            belly.name = "monoBelly"
            belly.fillColor = SKColor(white: 0.96, alpha: 1)
            belly.strokeColor = .clear
            belly.position = CGPoint(x: 0, y: -tileSize * 0.06)
            belly.zPosition = 0.2
            node.addChild(belly)

            for x in [-0.10, 0.10] {
                let eye = SKShapeNode(circleOfRadius: tileSize * 0.035)
                eye.fillColor = SKColor(white: 0.06, alpha: 1)
                eye.strokeColor = .clear
                eye.position = CGPoint(x: tileSize * CGFloat(x), y: tileSize * 0.16)
                eye.zPosition = 0.4
                node.addChild(eye)
            }

            let beakPath = CGMutablePath()
            beakPath.move(to: CGPoint(x: -tileSize * 0.07, y: tileSize * 0.10))
            beakPath.addLine(to: CGPoint(x: tileSize * 0.07, y: tileSize * 0.10))
            beakPath.addLine(to: CGPoint(x: 0, y: tileSize * 0.01))
            beakPath.closeSubpath()
            let beak = SKShapeNode(path: beakPath)
            beak.name = "monoBeak"
            beak.fillColor = SKColor(red: 1.0, green: 0.62, blue: 0.18, alpha: 1)
            beak.strokeColor = .clear
            beak.zPosition = 0.5
            node.addChild(beak)

            let helmet = SKShapeNode(rectOf: CGSize(width: tileSize * 0.36, height: tileSize * 0.12), cornerRadius: tileSize * 0.05)
            helmet.name = "monoIceHelmet"
            helmet.fillColor = SKColor(red: 0.62, green: 0.91, blue: 1.0, alpha: 0.95)
            helmet.strokeColor = SKColor.white.withAlphaComponent(0.9)
            helmet.lineWidth = max(0.8, tileSize * 0.02)
            helmet.position = CGPoint(x: 0, y: tileSize * 0.30)
            helmet.zPosition = 0.6
            node.addChild(helmet)

            let scarf = SKShapeNode(rectOf: CGSize(width: tileSize * 0.46, height: tileSize * 0.075), cornerRadius: tileSize * 0.03)
            scarf.name = "monoScarf"
            scarf.fillColor = SKColor(red: 0.17, green: 0.56, blue: 0.92, alpha: 1)
            scarf.strokeColor = .clear
            scarf.position = CGPoint(x: 0, y: tileSize * 0.01)
            scarf.zPosition = 0.55
            node.addChild(scarf)
        }

        private func emitSnowTrail(at position: CGPoint, tileSize: CGFloat) {
            guard tileSize > 0 else { return }
            for index in 0..<3 {
                let particle = SKShapeNode(circleOfRadius: tileSize * CGFloat(0.025 + Double(index) * 0.006))
                particle.name = "transientMonoSnowTrail"
                particle.position = CGPoint(
                    x: position.x - tileSize * CGFloat(0.10 + Double(index) * 0.07),
                    y: position.y - tileSize * CGFloat(0.18 - Double(index) * 0.03)
                )
                particle.fillColor = SKColor.white.withAlphaComponent(0.84)
                particle.strokeColor = .clear
                particle.zPosition = 0.08
                transientEffectContainer.addChild(particle)
                particle.run(.sequence([
                    .group([
                        .moveBy(x: -tileSize * 0.08, y: tileSize * 0.05, duration: 0.22),
                        .fadeOut(withDuration: 0.22),
                        .scale(to: 1.6, duration: 0.22)
                    ]),
                    .removeFromParent()
                ]))
            }
        }

        private func ensureTransientContainer(in scene: SKScene) {
            if transientEffectContainer.parent !== scene {
                scene.addChild(transientEffectContainer)
            }
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
#endif
