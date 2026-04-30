import XCTest
@testable import Game

final class MoveCardResolutionTests: XCTestCase {
    func testSuperWarpFallbackVectorsRemainStableAfterExtraction() {
        let expectedVectors = (-2...2).flatMap { dy in
            (-2...2).compactMap { dx in
                (dx == 0 && dy == 0) ? nil : MoveVector(dx: dx, dy: dy)
            }
        }

        XCTAssertEqual(MoveCard.superWarp.movementVectors, expectedVectors)
    }

    func testDirectionalRayFinalStepResolvesSingleTerminalPath() {
        let origin = GridPoint(x: 1, y: 1)
        let boardSize = BoardGeometry.standardSize
        let context = MoveCard.MovePattern.ResolutionContext(
            boardSize: boardSize,
            contains: { $0.isInside(boardSize: boardSize) },
            isTraversable: { $0.isInside(boardSize: boardSize) }
        )

        let paths = MoveCard.rayUpRight.resolvePaths(from: origin, context: context)

        XCTAssertEqual(paths.count, 1)
        XCTAssertEqual(paths.first?.vector, MoveVector(dx: 3, dy: 3))
        XCTAssertEqual(paths.first?.destination, GridPoint(x: 4, y: 4))
        XCTAssertEqual(
            paths.first?.traversedPoints,
            [GridPoint(x: 2, y: 2), GridPoint(x: 3, y: 3), GridPoint(x: 4, y: 4)]
        )
    }

    func testFixedWarpFallbackVectorAndResolvedPathsRemainCompatible() {
        let origin = GridPoint.center(of: BoardGeometry.standardSize)
        let context = MoveCard.MovePattern.ResolutionContext(
            boardSize: BoardGeometry.standardSize,
            contains: { $0.isInside(boardSize: BoardGeometry.standardSize) },
            isTraversable: { $0.isInside(boardSize: BoardGeometry.standardSize) }
        )

        XCTAssertEqual(MoveCard.fixedWarp.movementVectors, [MoveVector(dx: 0, dy: 0)])
        XCTAssertTrue(MoveCard.fixedWarp.resolvePaths(from: origin, context: context).isEmpty)
    }

    func testMovementVectorOverrideTakesPrecedenceOverRegistryResolution() {
        let origin = GridPoint.center(of: BoardGeometry.standardSize)
        let overrideVector = MoveVector(dx: 1, dy: 0)
        MoveCard.setTestMovementVectors([overrideVector], for: .rayUp)
        defer { MoveCard.setTestMovementVectors(nil, for: .rayUp) }

        let context = MoveCard.MovePattern.ResolutionContext(
            boardSize: BoardGeometry.standardSize,
            contains: { $0.isInside(boardSize: BoardGeometry.standardSize) },
            isTraversable: { $0.isInside(boardSize: BoardGeometry.standardSize) }
        )

        XCTAssertEqual(MoveCard.rayUp.movementVectors, [overrideVector])
        XCTAssertEqual(
            MoveCard.rayUp.resolvePaths(from: origin, context: context),
            [MoveCard.MovePattern.Path(
                vector: overrideVector,
                destination: origin.offset(dx: 1, dy: 0),
                traversedPoints: [origin.offset(dx: 1, dy: 0)]
            )]
        )
    }

}
