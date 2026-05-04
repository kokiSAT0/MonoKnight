import Foundation

/// AppStorage と UserDefaults のキーを一元管理する定数群
/// - Note: 文字列リテラルの分散を避け、設定追加やキー変更時の変更箇所を減らす。
enum StorageKey {
    enum AppStorage {
        static let hasCompletedConsentFlow = "has_completed_consent_flow"
        static let preferredColorScheme = "preferred_color_scheme"
        static let hapticsEnabled = "haptics_enabled"
        static let guideModeEnabled = "guide_mode_enabled"
        static let bestPoints5x5 = "best_points_5x5"
        static let removeAdsPurchased = "remove_ads_mk"
        static let adsShouldUseNPA = "ads_should_use_npa"
        static let interstitialClearCounter = "interstitial_clear_counter"
    }

    enum UserDefaults {
        static let freeModeRegulation = "free_mode_regulation_v1"
        static let campaignProgress = "campaign_progress_v1"
        static let campaignDebugUnlock = "campaign_debug_unlock_enabled"
        static let dailyChallengeAttemptState = "daily_challenge_attempt_state_v2"
        static let dailyChallengeDebugUnlimited = "daily_challenge_debug_unlimited_v1"
        static let gameCenterHasSubmittedByLeaderboard = "gc_has_submitted_by_leaderboard"
        static let gameCenterLastScoreByLeaderboard = "gc_last_score_by_leaderboard"
        static let campaignTutorialSeenSteps = "campaign_tutorial_seen_steps_v1"
        static let targetLabExperimentSettings = "target_lab_experiment_settings_v1"
        static let dungeonGrowth = "dungeon_growth_v2"
    }
}
