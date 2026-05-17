import SwiftUI

extension AppTheme {
    /// NEXT バッジの文字色
    var nextBadgeText: Color { cardContentPrimary }

    /// NEXT バッジの背景色
    var nextBadgeBackground: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.18))
        case .starChartSurveyTower:
            return boardGuideHighlight.opacity(0.20)
        }
    }

    /// NEXT バッジの枠線色
    var nextBadgeBorder: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Color.black.opacity(0.35), dark: Color.white.opacity(0.7))
        case .starChartSurveyTower:
            return boardGuideHighlight.opacity(0.72)
        }
    }
}
