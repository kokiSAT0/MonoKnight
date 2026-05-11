import XCTest
@testable import Game
@testable import MonoKnightApp

@MainActor
final class EncyclopediaDiscoveryStoreTests: XCTestCase {
    func testDiscoveryStorePersistsKnownIDsAndIgnoresUnknownsForTypedView() {
        let defaults = makeDefaults()
        let knownID = MoveCard.straightRight2.encyclopediaDiscoveryID
        defaults.set([knownID.rawValue, "futureCategory:futureItem"], forKey: StorageKey.UserDefaults.encyclopediaDiscovery)

        let store = EncyclopediaDiscoveryStore(userDefaults: defaults)

        XCTAssertTrue(store.isDiscovered(knownID))
        XCTAssertEqual(store.discoveredRawIDs.count, 2)
        XCTAssertEqual(store.discoveredIDs, [knownID])
    }

    func testDiscoveryStoreCountsIndividualCardIDsForCompletion() {
        let defaults = makeDefaults()
        let store = EncyclopediaDiscoveryStore(userDefaults: defaults)
        let entry = MoveCard.encyclopediaEntries.first { $0.displayName == "ナイト" }!

        store.discover(entry.includedCards[0].encyclopediaDiscoveryID)

        XCTAssertEqual(store.discoveredCount(in: entry.includedCards.map(\.encyclopediaDiscoveryID)), 1)
        XCTAssertTrue(entry.includedCards.contains { store.isDiscovered($0.encyclopediaDiscoveryID) })
    }

    func testGameSettingsStorePersistsDeveloperEncyclopediaToggle() {
        let defaults = makeDefaults()
        let store = GameSettingsStore(userDefaults: defaults)

        XCTAssertFalse(store.showsAllEncyclopediaEntriesForDeveloper)
        store.showsAllEncyclopediaEntriesForDeveloper = true

        let restored = GameSettingsStore(userDefaults: defaults)
        XCTAssertTrue(restored.showsAllEncyclopediaEntriesForDeveloper)
    }

    func testLockedPresentationHidesUndiscoveredText() {
        XCTAssertEqual(
            EncyclopediaLockedPresentation.title("割れた盾", isUnlocked: false),
            "？？？"
        )
        XCTAssertEqual(
            EncyclopediaLockedPresentation.description("効果説明", isUnlocked: false),
            "まだ発見していません"
        )
        XCTAssertEqual(
            EncyclopediaLockedPresentation.title("割れた盾", isUnlocked: true),
            "割れた盾"
        )
    }

    func testGameViewModelRecordsInitialVisibleDiscoveries() {
        let defaults = makeDefaults()
        let discoveryStore = EncyclopediaDiscoveryStore(userDefaults: defaults)
        let mode = GameMode.dungeonPlaceholder
        let core = GameCore(mode: mode)
        let interfaces = GameModuleInterfaces { _ in core }

        _ = GameViewModel(
            mode: mode,
            gameInterfaces: interfaces,
            gameCenterService: MockGameCenterService(),
            adsService: MockAdsService(),
            dungeonRunResumeStore: makeIsolatedDungeonRunResumeStore(),
            encyclopediaDiscoveryStore: discoveryStore,
            onRequestGameCenterSignIn: nil,
            onRequestReturnToTitle: nil
        )

        XCTAssertTrue(discoveryStore.isDiscovered(EncyclopediaDiscoveryID(category: .tile, itemID: "normal")))
        XCTAssertTrue(discoveryStore.isDiscovered(EncyclopediaDiscoveryID(category: .tile, itemID: "spawn")))
        XCTAssertTrue(discoveryStore.isDiscovered(EncyclopediaDiscoveryID(category: .tile, itemID: "dungeonExit")))
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "MonoKnightAppTests.encyclopedia.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeIsolatedDungeonRunResumeStore() -> DungeonRunResumeStore {
        let suiteName = "MonoKnightAppTests.resume.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return DungeonRunResumeStore(userDefaults: defaults)
    }
}
