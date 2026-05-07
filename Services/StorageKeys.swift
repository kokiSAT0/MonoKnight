import Foundation

/// AppStorage と UserDefaults のキーを一元管理する定数群
/// - Note: 文字列リテラルの分散を避け、設定追加やキー変更時の変更箇所を減らす。
enum StorageKey {
    enum AppStorage {
        static let hasCompletedConsentFlow = "has_completed_consent_flow"
        static let preferredColorScheme = "preferred_color_scheme"
        static let hapticsEnabled = "haptics_enabled"
        static let guideModeEnabled = "guide_mode_enabled"
        static let removeAdsPurchased = "remove_ads_mk"
        static let adsShouldUseNPA = "ads_should_use_npa"
        static let interstitialClearCounter = "interstitial_clear_counter"
    }

    enum UserDefaults {
        static let gameCenterHasSubmittedByLeaderboard = "gc_has_submitted_by_leaderboard"
        static let gameCenterLastScoreByLeaderboard = "gc_last_score_by_leaderboard"
        static let dungeonGrowth = "dungeon_growth_v3"
        static let dungeonRunResume = "dungeon_run_resume_v1"
    }
}
