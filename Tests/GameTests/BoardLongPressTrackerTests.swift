import XCTest
@testable import Game

final class BoardLongPressTrackerTests: XCTestCase {
    private let point = GridPoint(x: 1, y: 2)
    private let startLocation = BoardTouchLocation(x: 10, y: 20)

    func testFiresOnceWhenMinimumDurationPassesWithinTolerance() {
        var tracker = makeTracker()
        tracker.begin(at: point, location: startLocation, timestamp: 1.0)
        tracker.updateLocation(to: point, location: BoardTouchLocation(x: 14, y: 24))

        XCTAssertNil(tracker.fireIfReady(at: 1.44))
        XCTAssertEqual(tracker.fireIfReady(at: 1.45), point)
        XCTAssertNil(tracker.fireIfReady(at: 1.90))
    }

    func testEndingBeforeMinimumDurationReturnsTap() {
        var tracker = makeTracker()
        tracker.begin(at: point, location: startLocation, timestamp: 1.0)

        XCTAssertEqual(
            tracker.end(at: point, location: BoardTouchLocation(x: 11, y: 21)),
            .tap(point)
        )
    }

    func testEndingAfterLongPressFiresDoesNotReturnTap() {
        var tracker = makeTracker()
        tracker.begin(at: point, location: startLocation, timestamp: 1.0)

        XCTAssertEqual(tracker.fireIfReady(at: 1.45), point)
        XCTAssertEqual(tracker.end(at: point, location: startLocation), .none)
    }

    func testMovingBeyondToleranceCancelsLongPressAndTap() {
        var tracker = makeTracker()
        tracker.begin(at: point, location: startLocation, timestamp: 1.0)

        tracker.updateLocation(to: point, location: BoardTouchLocation(x: 23, y: 20))

        XCTAssertNil(tracker.fireIfReady(at: 1.45))
        XCTAssertEqual(
            tracker.end(at: point, location: BoardTouchLocation(x: 23, y: 20)),
            .none
        )
    }

    func testMovingToDifferentPointCancelsLongPressAndTap() {
        var tracker = makeTracker()
        let otherPoint = GridPoint(x: 2, y: 2)
        tracker.begin(at: point, location: startLocation, timestamp: 1.0)

        tracker.updateLocation(to: otherPoint, location: startLocation)

        XCTAssertNil(tracker.fireIfReady(at: 1.45))
        XCTAssertEqual(tracker.end(at: otherPoint, location: startLocation), .none)
    }

    private func makeTracker() -> BoardLongPressTracker {
        BoardLongPressTracker(minimumDuration: 0.45, movementTolerance: 12)
    }
}
