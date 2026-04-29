import Foundation

public extension GameMode.DifficultyRank {
    /// バッジ表示で利用する短いラベル
    var badgeLabel: String {
        switch self {
        case .balanced:
            return "標準"
        case .advanced:
            return "高難度"
        case .custom:
            return "調整可"
        case .scenario:
            return "ステージ"
        }
    }

    /// アクセシビリティ向けの詳細説明
    var accessibilityDescription: String {
        switch self {
        case .balanced:
            return "難易度は標準です"
        case .advanced:
            return "難易度は高難度です"
        case .custom:
            return "難易度はプレイヤーが調整できます"
        case .scenario:
            return "難易度はステージ進行に応じて変化します"
        }
    }
}

public extension GameMode.SpawnRule {
    /// UI 表示用にルールの説明テキストを返す
    var summaryText: String {
        switch self {
        case .fixed:
            return "固定スポーン"
        case .chooseAnyAfterPreview:
            return "任意スポーン"
        }
    }
}

public extension GameMode {
    /// UI 表示用のアイコン名
    /// - Note: SF Symbols のシステム名を返し、SwiftUI から共通の描画を行えるようにする
    var iconSystemName: String {
        switch identifier {
        case .standard5x5:
            return "square.grid.3x3.fill"
        case .classicalChallenge:
            return "checkerboard.rectangle"
        case .dailyFixedChallenge:
            return "calendar"
        case .dailyRandomChallenge:
            return "sparkles"
        case .freeCustom:
            return "slider.horizontal.3"
        case .campaignStage:
            return "map.fill"
        case .dailyFixed:
            return "calendar"
        case .dailyRandom:
            return "sparkles"
        }
    }

    /// モードの難易度ランク
    /// - Note: UI 側でバッジ表示やアクセシビリティ説明に利用する
    var difficultyRank: DifficultyRank {
        switch identifier {
        case .standard5x5:
            return .balanced
        case .classicalChallenge:
            return .advanced
        case .dailyFixedChallenge:
            return .balanced
        case .dailyRandomChallenge:
            return .advanced
        case .freeCustom:
            return .custom
        case .campaignStage:
            return .scenario
        case .dailyFixed:
            return .advanced
        case .dailyRandom:
            return .custom
        }
    }

    /// 難易度バッジで利用する短縮ラベル
    var difficultyBadgeLabel: String { difficultyRank.badgeLabel }

    /// 難易度に関するアクセシビリティ説明
    var difficultyAccessibilityDescription: String { difficultyRank.accessibilityDescription }

    /// 手札スロットと先読み枚数をまとめた説明文
    /// - Note: 同種カードを重ねられるスタック仕様を把握しやすいよう「種類数」で表現する。
    var handSummaryText: String {
        let stacking = allowsCardStacking ? "スタック可" : "スタック不可"
        return "手札スロット \(handSize) 種類 ・ 先読み \(nextPreviewCount) 枚 ・ \(stacking)"
    }

    /// 手動ペナルティの説明文
    var manualPenaltySummaryText: String {
        if usesTargetCollection {
            let focusText = "フォーカス スコア+15"
            let discardText = manualDiscardPenaltyCost > 0 ? "捨て札 +\(manualDiscardPenaltyCost)" : "捨て札 ペナルティなし"
            return "\(focusText) / \(discardText)"
        }

        let redrawText = "引き直し +\(manualRedrawPenaltyCost)"
        let discardText: String
        if manualDiscardPenaltyCost > 0 {
            discardText = "捨て札 +\(manualDiscardPenaltyCost)"
        } else {
            discardText = "捨て札 ペナルティなし"
        }
        return "\(redrawText) / \(discardText)"
    }

    /// 再訪ペナルティの説明文
    var revisitPenaltySummaryText: String {
        if revisitPenaltyCost > 0 {
            return "再訪 +\(revisitPenaltyCost)"
        } else {
            return "再訪ペナルティなし"
        }
    }

    /// 盤面サイズ・スポーン・山札をまとめた要約文
    var primarySummaryText: String {
        "\(boardSize)×\(boardSize) ・ \(spawnRule.summaryText) ・ \(deckSummaryText)"
    }

    /// 手札・先読み・ペナルティ情報をまとめた詳細文
    var secondarySummaryText: String {
        "\(handSummaryText) / \(manualPenaltySummaryText) / \(revisitPenaltySummaryText)"
    }

    /// スタック仕様の詳細説明文
    var stackingRuleDetailText: String {
        if allowsCardStacking {
            return "同じ種類のカードは同じスロット内で重なり、空きスロットがなくても補充できます。"
        } else {
            return "同じ種類のカードは別スロットを占有し、空きスロットが無いと新しいカードを引けません。"
        }
    }
}
