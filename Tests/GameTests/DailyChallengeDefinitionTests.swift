import XCTest
@testable import Game

/// 日替わりチャレンジは凍結コンテンツのため、詳細バランスではなく互換 smoke だけを確認する。
final class DailyChallengeDefinitionTests: XCTestCase {
    func testDailyModesRemainDeterministicForSavedSeeds() {
        let seed: UInt64 = 0x1234_5678_ABCD_EF01

        XCTAssertEqual(
            DailyChallengeDefinition.makeMode(for: .fixed, baseSeed: seed),
            DailyChallengeDefinition.makeFixedMode(baseSeed: seed)
        )
        XCTAssertEqual(
            DailyChallengeDefinition.makeMode(for: .random, baseSeed: seed),
            DailyChallengeDefinition.makeRandomMode(baseSeed: seed)
        )
        XCTAssertEqual(
            DailyChallengeDefinition.makeRandomMode(baseSeed: seed),
            DailyChallengeDefinition.makeRandomMode(baseSeed: seed)
        )
    }

    func testDailyFrozenModesStillCreatePlayableTargetCollectionModes() {
        let seed: UInt64 = 0xDEAD_BEEF_0000_0001
        let fixedMode = DailyChallengeDefinition.makeFixedMode(baseSeed: seed)
        let randomMode = DailyChallengeDefinition.makeRandomMode(baseSeed: seed)

        XCTAssertTrue(fixedMode.usesTargetCollection)
        XCTAssertTrue(randomMode.usesTargetCollection)
        XCTAssertNotEqual(fixedMode.deckSeed, randomMode.deckSeed)
    }
}
