import XCTest
@testable import Game

final class MoveCardPresentationTests: XCTestCase {
    func testPresentationMetadataRemainsStableAfterExtraction() {
        XCTAssertEqual(MoveCard.kingUp.displayName, "上1")
        XCTAssertEqual(MoveCard.knightRightwardChoice.displayName, "右桂 (選択)")
        XCTAssertEqual(MoveCard.superWarp.displayName, "全域ワープ")

        XCTAssertEqual(MoveCard.kingUp.kind, .normal)
        XCTAssertEqual(MoveCard.knightLeftwardChoice.kind, .choice)
        XCTAssertEqual(MoveCard.rayDown.kind, .multiStep)
        XCTAssertEqual(MoveCard.rayDown.multiStepUnitVector, MoveVector(dx: 0, dy: -1))
    }

    func testRegistrySetsRemainStableAfterExtraction() {
        XCTAssertEqual(MoveCard.directionalRayCards.count, 8)
        XCTAssertEqual(MoveCard.standardSet.count, 32)
        XCTAssertTrue(MoveCard.allCases.contains(.fixedWarp))
        XCTAssertTrue(MoveCard.allCases.contains(.superWarp))
    }
}
