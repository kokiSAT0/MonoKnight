import Foundation

/// 塔フロアで参照するカードプール。
/// - Note: 通常プレイは塔専用のため、旧練習モードや実験モード向けプリセットは公開しない。
public enum GameDeckPreset: String, CaseIterable, Codable, Identifiable, Sendable {
    /// 長距離カードの出現頻度を抑えた塔向け標準プール
    case standardLight
    /// キングと桂馬の基本 16 種を収録した序盤塔向けプール
    case kingAndKnightBasic

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .standardLight:
            return "塔標準カード"
        case .kingAndKnightBasic:
            return "塔基礎カード"
        }
    }

    public var summaryText: String {
        configuration.deckSummaryText
    }

    var configuration: Deck.Configuration {
        switch self {
        case .standardLight:
            return .standardLight
        case .kingAndKnightBasic:
            return .kingAndKnightBasic
        }
    }
}
