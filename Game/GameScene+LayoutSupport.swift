#if canImport(SpriteKit)
    import SpriteKit
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
#endif
