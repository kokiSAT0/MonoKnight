import Foundation
import Game
import SwiftUI

/// アプリ全体で共有するユーザー設定を読み書きするストア
/// - Note: UI 層が `@AppStorage` へ直接依存しないようにし、設定の参照経路を 1 箇所へ集約する。
@MainActor
final class GameSettingsStore: ObservableObject {
    /// 設定の永続化先
    private let userDefaults: UserDefaults

    /// テーマ設定
    @Published var preferredColorScheme: ThemePreference {
        didSet {
            guard oldValue != preferredColorScheme else { return }
            userDefaults.set(
                preferredColorScheme.rawValue,
                forKey: StorageKey.AppStorage.preferredColorScheme
            )
        }
    }

    /// ハプティクス設定
    @Published var hapticsEnabled: Bool {
        didSet {
            guard oldValue != hapticsEnabled else { return }
            userDefaults.set(hapticsEnabled, forKey: StorageKey.AppStorage.hapticsEnabled)
        }
    }

    /// 盤面ガイド表示設定
    @Published var guideModeEnabled: Bool {
        didSet {
            guard oldValue != guideModeEnabled else { return }
            userDefaults.set(guideModeEnabled, forKey: StorageKey.AppStorage.guideModeEnabled)
        }
    }

    /// 開発者向けに遊び方辞典の未発見項目もすべて表示する設定
    @Published var showsAllEncyclopediaEntriesForDeveloper: Bool {
        didSet {
            guard oldValue != showsAllEncyclopediaEntriesForDeveloper else { return }
            userDefaults.set(
                showsAllEncyclopediaEntriesForDeveloper,
                forKey: StorageKey.AppStorage.showsAllEncyclopediaEntriesForDeveloper
            )
        }
    }

    /// 手札並び順設定
    @Published var handOrderingStrategy: HandOrderingStrategy {
        didSet {
            guard oldValue != handOrderingStrategy else { return }
            userDefaults.set(handOrderingStrategy.rawValue, forKey: HandOrderingStrategy.storageKey)
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.preferredColorScheme =
            ThemePreference(
                rawValue: userDefaults.string(forKey: StorageKey.AppStorage.preferredColorScheme)
                    ?? ThemePreference.system.rawValue
            ) ?? .system
        self.hapticsEnabled =
            userDefaults.object(forKey: StorageKey.AppStorage.hapticsEnabled) as? Bool ?? true
        self.guideModeEnabled =
            userDefaults.object(forKey: StorageKey.AppStorage.guideModeEnabled) as? Bool ?? true
        self.showsAllEncyclopediaEntriesForDeveloper =
            userDefaults.object(forKey: StorageKey.AppStorage.showsAllEncyclopediaEntriesForDeveloper) as? Bool ?? false
        self.handOrderingStrategy =
            HandOrderingStrategy(
                rawValue: userDefaults.string(forKey: HandOrderingStrategy.storageKey)
                    ?? HandOrderingStrategy.insertionOrder.rawValue
            ) ?? .insertionOrder
    }

}

/// 遊び方辞典の発見済み項目を保存するストア
@MainActor
final class EncyclopediaDiscoveryStore: ObservableObject {
    private let userDefaults: UserDefaults
    private let storageKey: String

    @Published private(set) var discoveredRawIDs: Set<String>

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = StorageKey.UserDefaults.encyclopediaDiscovery
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.discoveredRawIDs = Set(userDefaults.stringArray(forKey: storageKey) ?? [])
    }

    var discoveredIDs: Set<EncyclopediaDiscoveryID> {
        Set(discoveredRawIDs.compactMap(EncyclopediaDiscoveryID.init(rawValue:)))
    }

    func isDiscovered(_ id: EncyclopediaDiscoveryID) -> Bool {
        discoveredRawIDs.contains(id.rawValue)
    }

    func discover(_ id: EncyclopediaDiscoveryID) {
        discover([id])
    }

    func discover(_ ids: some Sequence<EncyclopediaDiscoveryID>) {
        var updatedIDs = discoveredRawIDs
        for id in ids {
            updatedIDs.insert(id.rawValue)
        }
        saveIfChanged(updatedIDs)
    }

    func reset() {
        saveIfChanged([])
    }

    func discoveredCount(in ids: some Sequence<EncyclopediaDiscoveryID>) -> Int {
        ids.reduce(0) { count, id in
            count + (isDiscovered(id) ? 1 : 0)
        }
    }

    private func saveIfChanged(_ updatedIDs: Set<String>) {
        guard updatedIDs != discoveredRawIDs else { return }
        discoveredRawIDs = updatedIDs
        userDefaults.set(Array(updatedIDs).sorted(), forKey: storageKey)
    }
}
