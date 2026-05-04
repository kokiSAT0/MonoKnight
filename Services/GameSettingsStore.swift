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
        self.handOrderingStrategy =
            HandOrderingStrategy(
                rawValue: userDefaults.string(forKey: HandOrderingStrategy.storageKey)
                    ?? HandOrderingStrategy.insertionOrder.rawValue
            ) ?? .insertionOrder
    }

}
