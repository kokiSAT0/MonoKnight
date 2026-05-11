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
                        let isVisible = owner.dungeonVisiblePointsForAccessibility()?.contains(point) ?? true
                        let element = TileAccessibilityElement(point: point, owner: owner)
                        element.accessibilityFrameInContainerSpace = CGRect(
                            x: layout.gridOrigin.x + CGFloat(x) * layout.tileSize,
                            y: layout.gridOrigin.y + CGFloat(y) * layout.tileSize,
                            width: layout.tileSize,
                            height: layout.tileSize
                        )

                        let statusText: String
                        if !isVisible {
                            statusText = "暗闇"
                        } else if let state = board.state(at: point) {
                            if state.isImpassable {
                                statusText = "移動不可"
                            } else if state.isVisited {
                                statusText = "踏破済み"
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
                        if isVisible, let effect = board.effect(at: point) {
                            labelParts.append(effect.accessibilityLabel)
                        }
                        if owner.latestHighlightPoints(for: .dungeonRelicPickup).contains(point) {
                            labelParts.append("宝箱")
                        }
                        if owner.latestHighlightPoints(for: .dungeonSuspiciousRelicPickup).contains(point) {
                            labelParts.append("怪しい宝箱")
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
                case .returnWarp:
                    return "帰還ワープ"
                case .shuffleHand:
                    return "シャッフルマス"
                case .blast:
                    return "吹き飛ばしマス"
                case .slow:
                    return "麻痺罠"
                case .shackleTrap:
                    return "足枷罠"
                case .poisonTrap:
                    return "毒罠"
                case .illusionTrap:
                    return "幻惑罠"
                case .swamp:
                    return "沼"
                case .preserveCard:
                    return "カード温存マス"
                case .discardRandomHand:
                    return "手札喪失罠"
                case .discardAllMoveCards:
                    return "移動カード喪失罠"
                case .discardAllSupportCards:
                    return "補助カード喪失罠"
                case .discardAllHands:
                    return "全手札喪失罠"
                }
            }
        }
    #endif
#endif
