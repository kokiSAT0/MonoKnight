import Foundation

struct BoardTouchLocation: Equatable {
    let x: Double
    let y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    func distance(to other: BoardTouchLocation) -> Double {
        let deltaX = x - other.x
        let deltaY = y - other.y
        return (deltaX * deltaX + deltaY * deltaY).squareRoot()
    }
}

struct BoardLongPressTracker {
    enum EndAction: Equatable {
        case tap(GridPoint)
        case longPress(GridPoint)
        case none
    }

    private struct ActiveTouch {
        let point: GridPoint
        let location: BoardTouchLocation
        let timestamp: TimeInterval
        var didFireLongPress = false
    }

    let minimumDuration: TimeInterval
    let movementTolerance: Double

    private var activeTouch: ActiveTouch?

    init(minimumDuration: TimeInterval, movementTolerance: Double) {
        self.minimumDuration = minimumDuration
        self.movementTolerance = movementTolerance
    }

    mutating func begin(at point: GridPoint?, location: BoardTouchLocation, timestamp: TimeInterval) {
        guard let point else {
            activeTouch = nil
            return
        }
        activeTouch = ActiveTouch(point: point, location: location, timestamp: timestamp)
    }

    @discardableResult
    mutating func updateLocation(to point: GridPoint?, location: BoardTouchLocation) -> Bool {
        guard let activeTouch else { return false }
        guard point == activeTouch.point,
              activeTouch.location.distance(to: location) <= movementTolerance
        else {
            self.activeTouch = nil
            return false
        }
        return true
    }

    mutating func fireIfReady(at timestamp: TimeInterval) -> GridPoint? {
        guard var activeTouch,
              !activeTouch.didFireLongPress,
              timestamp - activeTouch.timestamp + .ulpOfOne >= minimumDuration
        else { return nil }

        activeTouch.didFireLongPress = true
        self.activeTouch = activeTouch
        return activeTouch.point
    }

    mutating func end(at point: GridPoint?, location: BoardTouchLocation, timestamp: TimeInterval) -> EndAction {
        defer { activeTouch = nil }
        guard let activeTouch else { return .none }
        guard !activeTouch.didFireLongPress else { return .none }
        guard point == activeTouch.point,
              activeTouch.location.distance(to: location) <= movementTolerance
        else {
            return .none
        }
        if timestamp - activeTouch.timestamp + .ulpOfOne >= minimumDuration {
            return .longPress(activeTouch.point)
        }
        return .tap(activeTouch.point)
    }

    mutating func cancel() {
        activeTouch = nil
    }
}
