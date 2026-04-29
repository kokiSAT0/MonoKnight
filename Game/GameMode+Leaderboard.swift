import Foundation

public extension GameMode.Identifier {
    /// スコア送信やリーダーボード参照で利用する識別子
    /// - Note: 日替わりプレイ用 ID と Game Center 用 ID を分けて扱い、呼び出し側が rawValue ベースで分岐しないようにする。
    var scoreSubmissionIdentifier: Self? {
        switch self {
        case .standard5x5, .classicalChallenge, .dailyFixedChallenge, .dailyRandomChallenge:
            return self
        case .dailyFixed:
            return .dailyFixedChallenge
        case .dailyRandom:
            return .dailyRandomChallenge
        case .freeCustom, .campaignStage, .targetLab:
            return nil
        }
    }

    /// 実際のプレイモードとして扱う識別子
    /// - Note: Game Center 用の内部 ID から UI/プレイ文脈へ戻したいときの正規化に利用する。
    var playModeIdentifier: Self {
        switch self {
        case .dailyFixedChallenge:
            return .dailyFixed
        case .dailyRandomChallenge:
            return .dailyRandom
        case .standard5x5, .classicalChallenge, .targetLab, .freeCustom, .campaignStage, .dailyFixed, .dailyRandom:
            return self
        }
    }
}
