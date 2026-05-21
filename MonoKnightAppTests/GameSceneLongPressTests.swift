#if canImport(SpriteKit) && canImport(UIKit)
import Foundation
import SpriteKit
import UIKit
import XCTest
@testable import Game

@MainActor
final class GameSceneLongPressTests: XCTestCase {
    func testLongPressTimerRecognizesPointWhileTouchIsHeld() {
        let scene = GameScene(initialBoardSize: 5, initialVisitedPoints: [GridPoint(x: 0, y: 0)])
        let point = GridPoint(x: 1, y: 1)
        var recognizedPoints: [GridPoint] = []
        scene.onLongPressGridPoint = { recognizedPoints.append($0) }

        scene.beginLongPressRecognitionForTesting(at: point, timestamp: 10)
        XCTAssertTrue(scene.isLongPressTimerScheduledForTesting())

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.55))

        XCTAssertEqual(recognizedPoints, [point])
        XCTAssertFalse(scene.isLongPressTimerScheduledForTesting())
    }

    func testLongPressTimerCancelsWhenTouchMovesBeyondTolerance() {
        let scene = GameScene(initialBoardSize: 5, initialVisitedPoints: [GridPoint(x: 0, y: 0)])
        let point = GridPoint(x: 1, y: 1)
        var recognizedPoints: [GridPoint] = []
        scene.onLongPressGridPoint = { recognizedPoints.append($0) }

        scene.beginLongPressRecognitionForTesting(at: point, timestamp: 10)
        XCTAssertFalse(
            scene.updateLongPressRecognitionForTesting(
                to: point,
                location: BoardTouchLocation(x: 13, y: 0)
            )
        )

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.55))

        XCTAssertTrue(recognizedPoints.isEmpty)
        XCTAssertFalse(scene.isLongPressTimerScheduledForTesting())
    }
}
#endif
