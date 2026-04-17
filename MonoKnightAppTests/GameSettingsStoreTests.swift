import Foundation
import Game
import Testing
@testable import MonoKnightApp

struct GameSettingsStoreTests {
    @MainActor
    @Test func restoresExistingSettingsFromUserDefaults() {
        let suiteName = "GameSettingsStoreTests.restore"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(ThemePreference.dark.rawValue, forKey: StorageKey.AppStorage.preferredColorScheme)
        defaults.set(false, forKey: StorageKey.AppStorage.hapticsEnabled)
        defaults.set(false, forKey: StorageKey.AppStorage.guideModeEnabled)
        defaults.set(123, forKey: StorageKey.AppStorage.bestPoints5x5)
        defaults.set(
            HandOrderingStrategy.directionSorted.rawValue,
            forKey: HandOrderingStrategy.storageKey
        )

        let store = GameSettingsStore(userDefaults: defaults)

        #expect(store.preferredColorScheme == .dark)
        #expect(store.hapticsEnabled == false)
        #expect(store.guideModeEnabled == false)
        #expect(store.bestPoints == 123)
        #expect(store.handOrderingStrategy == .directionSorted)
    }

    @MainActor
    @Test func persistsUpdatesAndBestPointRules() {
        let suiteName = "GameSettingsStoreTests.persist"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = GameSettingsStore(userDefaults: defaults)
        store.preferredColorScheme = .light
        store.hapticsEnabled = false
        store.guideModeEnabled = false
        store.handOrderingStrategy = .directionSorted

        let previousBest = store.updateBestPointsIfNeeded(80)
        let unchangedBest = store.updateBestPointsIfNeeded(120)

        #expect(previousBest == nil)
        #expect(unchangedBest == 80)
        #expect(store.bestPoints == 80)
        #expect(defaults.string(forKey: StorageKey.AppStorage.preferredColorScheme) == ThemePreference.light.rawValue)
        #expect(defaults.bool(forKey: StorageKey.AppStorage.hapticsEnabled) == false)
        #expect(defaults.bool(forKey: StorageKey.AppStorage.guideModeEnabled) == false)
        #expect(
            defaults.string(forKey: HandOrderingStrategy.storageKey)
                == HandOrderingStrategy.directionSorted.rawValue
        )
        #expect(defaults.integer(forKey: StorageKey.AppStorage.bestPoints5x5) == 80)

        store.resetBestPoints()
        #expect(store.bestPoints == .max)
        #expect(defaults.integer(forKey: StorageKey.AppStorage.bestPoints5x5) == .max)
    }
}
