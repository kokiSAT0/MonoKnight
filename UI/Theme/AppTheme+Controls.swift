import SwiftUI

extension AppTheme {
    /// 手札が空の時に表示する枠線色
    var placeholderStroke: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Color.black.opacity(0.2), dark: Color.white.opacity(0.25))
        case .starChartSurveyTower:
            return cardBorderNext.opacity(0.55)
        }
    }

    /// 手札プレースホルダの背景色
    var placeholderBackground: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Color.black.opacity(0.03), dark: Color.white.opacity(0.05))
        case .starChartSurveyTower:
            return cardBackgroundNext.opacity(0.62)
        }
    }

    /// 手札プレースホルダのアイコン色
    var placeholderIcon: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Color.black.opacity(0.35), dark: Color.white.opacity(0.4))
        case .starChartSurveyTower:
            return cardContentPrimary.opacity(0.48)
        }
    }

    /// 右上メニューアイコンの前景色
    var menuIconForeground: Color { cardContentPrimary }

    /// 右上メニューアイコンの背景色
    var menuIconBackground: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.12))
        case .starChartSurveyTower:
            return cardBackgroundNext.opacity(0.86)
        }
    }

    /// 右上メニューアイコンの枠線色
    var menuIconBorder: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Color.black.opacity(0.12), dark: Color.white.opacity(0.25))
        case .starChartSurveyTower:
            return cardBorderNext.opacity(0.64)
        }
    }

    /// ダミー広告の背景色。実広告導入まで視認性を保つプレースホルダ用
    var adPlaceholderBackground: Color { schemeColor(light: Color.black.opacity(0.05), dark: Color.white.opacity(0.1)) }
}
