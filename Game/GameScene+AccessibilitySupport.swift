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
                currentTargetPoints: Set<GridPoint>,
                upcomingTargetPoints: Set<GridPoint>,
                targetApproachCandidatePoints: Set<GridPoint>,
                targetCaptureCandidatePoints: Set<GridPoint>,
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

                        var labelParts: [String] = []
                        if let knightPosition, point == knightPosition {
                            labelParts.append("駒あり")
                        }
                        if currentTargetPoints.contains(point) || upcomingTargetPoints.contains(point) {
                            labelParts.append("表示中の目的地")
                        }
                        if targetCaptureCandidatePoints.contains(point) {
                            labelParts.append("目的地を取れる移動先")
                        } else if targetApproachCandidatePoints.contains(point) {
                            labelParts.append("目的地に近づく移動先")
                        }
                        if let effect = board.effect(at: point) {
                            labelParts.append(effect.accessibilityLabel)
                        }
                        labelParts.append(statusText)
                        element.accessibilityLabel = labelParts.joined(separator: "・")
                        element.accessibilityTraits = [.button]
                        elements.append(element)
                    }
                }
                elementsCache = elements
            }
        }

        private extension TileEffect {
            var accessibilityLabel: String {
                switch self {
                case .warp:
                    return "ワープマス"
                case .shuffleHand:
                    return "シャッフルマス"
                case .boost:
                    return "加速マス"
                case .slow:
                    return "減速マス"
                case .nextRefresh:
                    return "NEXT更新マス"
                case .freeFocus:
                    return "無料フォーカスマス"
                case .preserveCard:
                    return "カード温存マス"
                case .draft:
                    return "ドラフトマス"
                case .overload:
                    return "過負荷マス"
                case .targetSwap:
                    return "転換マス"
                case .openGate:
                    return "開門マス"
                }
            }
        }
    #endif
#endif
