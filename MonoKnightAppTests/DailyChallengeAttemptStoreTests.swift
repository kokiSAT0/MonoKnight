import Foundation
import Testing
@testable import MonoKnightApp

@MainActor
struct DailyChallengeAttemptStoreTests {
    /// UTC 基準で日付が変わった際に挑戦回数がリセットされることを確認する
    @Test
    func resetOccursWhenUtcDateChanges() {
        let suiteName = "daily_challenge_store_test_reset"
        let defaults = makeIsolatedDefaults(suiteName: suiteName)
        defer { clearDefaults(defaults, suiteName: suiteName) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2024, month: 6, day: 1, hour: 10))!
        var now = start

        let store = DailyChallengeAttemptStore(userDefaults: defaults, nowProvider: { now })
        #expect(store.remainingAttempts == 1)

        _ = store.consumeAttempt()
        #expect(store.remainingAttempts == 0)

        now = calendar.date(byAdding: .day, value: 1, to: start)!
        store.refreshForCurrentDate()
        #expect(store.remainingAttempts == 1)
    }

    /// 無料 1 回 + リワード広告 3 回の計 4 回を超えて消費できないことを検証する
    @Test
    func rejectsConsumptionBeyondDailyLimit() {
        let suiteName = "daily_challenge_store_test_limit"
        let defaults = makeIsolatedDefaults(suiteName: suiteName)
        defer { clearDefaults(defaults, suiteName: suiteName) }

        let store = DailyChallengeAttemptStore(userDefaults: defaults)
        for _ in 0..<3 {
            #expect(store.grantRewardedAttempt())
        }
        #expect(store.remainingAttempts == 4)

        for _ in 0..<4 {
            #expect(store.consumeAttempt())
        }
        #expect(store.remainingAttempts == 0)
        #expect(store.consumeAttempt() == false)
    }

    /// リワード広告成功時に残り挑戦回数が増加することを確認する
    @Test
    func rewardedGrantRestoresAttemptsAfterConsumption() {
        let suiteName = "daily_challenge_store_test_reward"
        let defaults = makeIsolatedDefaults(suiteName: suiteName)
        defer { clearDefaults(defaults, suiteName: suiteName) }

        let store = DailyChallengeAttemptStore(userDefaults: defaults)
        _ = store.consumeAttempt()
        #expect(store.remainingAttempts == 0)

        #expect(store.grantRewardedAttempt())
        #expect(store.remainingAttempts == 1)
    }

    /// デバッグ無制限モードが永続化され、挑戦回数を消費しても減らないことを検証する
    @Test
    func debugUnlimitedPersistsAndSkipsConsumptionLimit() {
        let suiteName = "daily_challenge_store_test_debug_unlimited"
        let defaults = makeIsolatedDefaults(suiteName: suiteName)
        defer { clearDefaults(defaults, suiteName: suiteName) }

        var now = Date()
        let store = DailyChallengeAttemptStore(userDefaults: defaults, nowProvider: { now })
        #expect(store.isDebugUnlimitedEnabled == false)

        store.enableDebugUnlimited()
        #expect(store.isDebugUnlimitedEnabled == true)

        // 再生成してもフラグが保持されることを確認する
        let restoredStore = DailyChallengeAttemptStore(userDefaults: defaults, nowProvider: { now })
        #expect(restoredStore.isDebugUnlimitedEnabled == true)

        let initialRemaining = restoredStore.remainingAttempts
        // 複数回消費しても残量が変化しない（上限スキップ）ことを確かめる
        for _ in 0..<5 {
            #expect(restoredStore.consumeAttempt())
            #expect(restoredStore.remainingAttempts == initialRemaining)
        }
    }

    // MARK: - ヘルパー
    private func makeIsolatedDefaults(suiteName: String) -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("UserDefaults suite (\(suiteName)) の生成に失敗しました")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func clearDefaults(_ defaults: UserDefaults, suiteName: String) {
        defaults.removePersistentDomain(forName: suiteName)
        defaults.synchronize()
    }
}
