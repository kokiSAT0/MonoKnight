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
        #expect(store.remainingAttempts(for: .fixed) == 1)
        #expect(store.remainingAttempts(for: .random) == 1)

        _ = store.consumeAttempt(for: .fixed)
        #expect(store.remainingAttempts(for: .fixed) == 0)
        #expect(store.remainingAttempts(for: .random) == 1)

        now = calendar.date(byAdding: .day, value: 1, to: start)!
        store.refreshForCurrentDate()
        #expect(store.remainingAttempts(for: .fixed) == 1)
        #expect(store.remainingAttempts(for: .random) == 1)
    }

    /// 無料 1 回 + リワード広告 3 回の計 4 回を超えて消費できないことを検証する（固定バリアント）
    @Test
    func rejectsConsumptionBeyondDailyLimit() {
        let suiteName = "daily_challenge_store_test_limit"
        let defaults = makeIsolatedDefaults(suiteName: suiteName)
        defer { clearDefaults(defaults, suiteName: suiteName) }

        let store = DailyChallengeAttemptStore(userDefaults: defaults)
        for _ in 0..<3 {
            #expect(store.grantRewardedAttempt(for: .fixed))
        }
        #expect(store.remainingAttempts(for: .fixed) == 4)
        #expect(store.remainingAttempts(for: .random) == 1)

        for _ in 0..<4 {
            #expect(store.consumeAttempt(for: .fixed))
        }
        #expect(store.remainingAttempts(for: .fixed) == 0)
        #expect(store.consumeAttempt(for: .fixed) == false)
        // ランダム側は全く影響を受けないことを確認する
        #expect(store.remainingAttempts(for: .random) == 1)
    }

    /// リワード広告成功時に残り挑戦回数が増加することを確認する
    @Test
    func rewardedGrantRestoresAttemptsAfterConsumption() {
        let suiteName = "daily_challenge_store_test_reward"
        let defaults = makeIsolatedDefaults(suiteName: suiteName)
        defer { clearDefaults(defaults, suiteName: suiteName) }

        let store = DailyChallengeAttemptStore(userDefaults: defaults)
        _ = store.consumeAttempt(for: .random)
        #expect(store.remainingAttempts(for: .random) == 0)
        #expect(store.remainingAttempts(for: .fixed) == 1)

        #expect(store.grantRewardedAttempt(for: .random))
        #expect(store.remainingAttempts(for: .random) == 1)
        #expect(store.remainingAttempts(for: .fixed) == 1)
    }

    /// 固定・ランダムの状態が独立していることを検証する
    @Test
    func variantStatesAreIndependent() {
        let suiteName = "daily_challenge_store_test_variant_independence"
        let defaults = makeIsolatedDefaults(suiteName: suiteName)
        defer { clearDefaults(defaults, suiteName: suiteName) }

        let store = DailyChallengeAttemptStore(userDefaults: defaults)
        _ = store.consumeAttempt(for: .fixed)
        #expect(store.remainingAttempts(for: .fixed) == 0)
        #expect(store.remainingAttempts(for: .random) == 1)

        // ランダム側の広告付与が固定側へ影響しないことをチェック
        #expect(store.grantRewardedAttempt(for: .random))
        #expect(store.rewardedAttemptsGranted(for: .random) == 1)
        #expect(store.rewardedAttemptsGranted(for: .fixed) == 0)
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

        let initialFixed = restoredStore.remainingAttempts(for: .fixed)
        let initialRandom = restoredStore.remainingAttempts(for: .random)
        // 複数回消費しても残量が変化しない（上限スキップ）ことを確かめる
        for _ in 0..<5 {
            #expect(restoredStore.consumeAttempt(for: .fixed))
            #expect(restoredStore.consumeAttempt(for: .random))
            #expect(restoredStore.remainingAttempts(for: .fixed) == initialFixed)
            #expect(restoredStore.remainingAttempts(for: .random) == initialRandom)
        }
    }

    /// 無制限モードを無効化すると通常の残量判定へ戻ることを検証する
    @Test
    func debugUnlimitedCanBeDisabled() {
        let suiteName = "daily_challenge_store_test_disable_debug"
        let defaults = makeIsolatedDefaults(suiteName: suiteName)
        defer { clearDefaults(defaults, suiteName: suiteName) }

        let store = DailyChallengeAttemptStore(userDefaults: defaults)
        store.enableDebugUnlimited()
        #expect(store.isDebugUnlimitedEnabled)

        // 解除後は残量が減る通常仕様へ戻るため、連続消費でゼロになることを確認する
        store.disableDebugUnlimited()
        #expect(store.isDebugUnlimitedEnabled == false)
        #expect(store.consumeAttempt(for: .fixed))
        #expect(store.remainingAttempts(for: .fixed) == 0)
        #expect(store.consumeAttempt(for: .fixed) == false)
        // ランダム側は未消費のため 1 回残っている
        #expect(store.remainingAttempts(for: .random) == 1)

        // 再生成しても無制限フラグが false のまま維持されることを確認
        let reloadedStore = DailyChallengeAttemptStore(userDefaults: defaults)
        #expect(reloadedStore.isDebugUnlimitedEnabled == false)
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
