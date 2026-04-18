#if canImport(SpriteKit)
    #if canImport(UIKit)
        import SpriteKit
        import UIKit

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
