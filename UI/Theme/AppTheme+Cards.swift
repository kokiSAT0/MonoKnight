import SwiftUI

extension AppTheme {
    /// 手札カードの背景色。淡いトーンで盤面との差を演出
    var cardBackgroundHand: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Color.white, dark: Color.white.opacity(0.08))
        case .starChartSurveyTower:
            return schemeColor(
                light: Color(red: 0.96, green: 0.995, blue: 1.0).opacity(0.96),
                dark: Color(red: 0.96, green: 0.995, blue: 1.0).opacity(0.96)
            )
        }
    }

    /// 先読みカードの背景色。手札よりわずかに明るくして注目度を上げる
    var cardBackgroundNext: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.12))
        case .starChartSurveyTower:
            return schemeColor(
                light: Color(red: 0.88, green: 0.97, blue: 1.0).opacity(0.96),
                dark: Color(red: 0.88, green: 0.97, blue: 1.0).opacity(0.96)
            )
        }
    }

    /// 手札カードの枠線色
    var cardBorderHand: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Color.black.opacity(0.85), dark: Color.white)
        case .starChartSurveyTower:
            return schemeColor(
                light: Color(red: 0.0, green: 0.62, blue: 0.88).opacity(0.74),
                dark: Color(red: 0.0, green: 0.62, blue: 0.88).opacity(0.74)
            )
        }
    }

    /// 先読みカードの枠線色
    var cardBorderNext: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Color.black.opacity(0.9), dark: Color.white.opacity(0.8))
        case .starChartSurveyTower:
            return schemeColor(
                light: Color(red: 0.52, green: 0.22, blue: 1.0).opacity(0.62),
                dark: Color(red: 0.52, green: 0.22, blue: 1.0).opacity(0.62)
            )
        }
    }

    /// ワープ系カード全体に使う紫系アクセント色
    var warpCardAccent: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Self.lightWarpAccent, dark: Self.darkWarpAccent)
        case .starChartSurveyTower:
            return schemeColor(
                light: Color(red: 0.48, green: 0.34, blue: 0.84),
                dark: Color(red: 0.78, green: 0.58, blue: 1.0)
            )
        }
    }

    /// 盤面中央セルのハイライト色（手札用）
    var centerHighlightHand: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.12))
        case .starChartSurveyTower:
            return boardGuideHighlight.opacity(0.18)
        }
    }

    /// 盤面中央セルのハイライト色（先読み用）
    var centerHighlightNext: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Color.black.opacity(0.12), dark: Color.white.opacity(0.25))
        case .starChartSurveyTower:
            return boardGuideHighlight.opacity(0.28)
        }
    }

    /// グリッド線の色（手札用）
    var gridLineHand: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Color.black.opacity(0.3), dark: Color.white.opacity(0.4))
        case .starChartSurveyTower:
            return cardBorderHand.opacity(0.58)
        }
    }

    /// グリッド線の色（先読み用）
    var gridLineNext: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Color.black.opacity(0.4), dark: Color.white.opacity(0.55))
        case .starChartSurveyTower:
            return cardBorderNext.opacity(0.68)
        }
    }

    /// 矢印やラベルなどカード上の主要要素の色
    var cardContentPrimary: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Color.black, dark: Color.white)
        case .starChartSurveyTower:
            return schemeColor(light: Color(red: 0.02, green: 0.12, blue: 0.22), dark: Color(red: 0.02, green: 0.12, blue: 0.22))
        }
    }

    /// カード上で白黒を反転して利用する際の色
    var cardContentInverted: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Color.white, dark: Color.black)
        case .starChartSurveyTower:
            return schemeColor(light: Color.white, dark: Color.white)
        }
    }

    /// 複数マス移動カード専用のアクセントカラー（シアン系）
    var multiStepAccent: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Self.lightMultiStepAccent, dark: Self.darkMultiStepAccent)
        case .starChartSurveyTower:
            return schemeColor(
                light: Color(red: 0.0, green: 0.58, blue: 0.72),
                dark: Color(red: 0.34, green: 0.88, blue: 1.0)
            )
        }
    }

    /// 現在位置マーカーの縁取り色
    var startMarkerStroke: Color { schemeColor(light: Color.white.opacity(0.8), dark: Color.black.opacity(0.8)) }

    /// 目的地マーカーの縁取り色
    var destinationMarkerStroke: Color { cardContentPrimary }
}

private extension AppTheme {
    static let lightWarpAccent = Color(red: 0.56, green: 0.42, blue: 0.86)
    static let darkWarpAccent = Color(red: 0.70, green: 0.55, blue: 0.93)
    static let lightMultiStepAccent = Color(red: 0.0, green: 0.68, blue: 0.86)
    static let darkMultiStepAccent = Color(red: 0.35, green: 0.85, blue: 0.95)
}
