import SwiftUI

extension AppTheme {
    /// スポーン案内の背景色。ライトモードでは白ベース、ダークモードでは黒ベースで適度に透過させる
    var spawnOverlayBackground: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Color.white.opacity(0.92), dark: Color.black.opacity(0.82))
        case .starChartSurveyTower:
            return schemeColor(
                light: Color(red: 0.94, green: 0.99, blue: 1.0).opacity(0.94),
                dark: Color(red: 0.94, green: 0.99, blue: 1.0).opacity(0.94)
            )
        }
    }

    /// スポーン案内の枠線色。背景とのコントラストが強すぎないよう控えめな値に調整
    var spawnOverlayBorder: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Color.black.opacity(0.15), dark: Color.white.opacity(0.25))
        case .starChartSurveyTower:
            return boardGuideHighlight.opacity(0.72)
        }
    }

    /// スポーン案内ボックスのドロップシャドウ色
    var spawnOverlayShadow: Color { schemeColor(light: Color.black.opacity(0.25), dark: Color.black.opacity(0.7)) }

    /// ペナルティバナーの背景色
    var penaltyBannerBackground: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.18))
        case .starChartSurveyTower:
            return spawnOverlayBackground
        }
    }

    /// ペナルティバナーの枠線色
    var penaltyBannerBorder: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Color.black.opacity(0.15), dark: Color.white.opacity(0.35))
        case .starChartSurveyTower:
            return spawnOverlayBorder
        }
    }

    /// ペナルティバナーの影色
    var penaltyBannerShadow: Color { schemeColor(light: Color.black.opacity(0.12), dark: Color.black.opacity(0.35)) }

    /// ペナルティバナーのメインテキスト色
    var penaltyTextPrimary: Color { cardContentPrimary }

    /// ペナルティバナーの補足テキスト色
    var penaltyTextSecondary: Color { schemeColor(light: Color.black.opacity(0.7), dark: Color.white.opacity(0.8)) }

    /// ペナルティバナーのアイコン（シンボル）の色
    var penaltyIconForeground: Color { cardContentInverted }

    /// ペナルティバナーのアイコン背景色
    var penaltyIconBackground: Color { cardContentPrimary }
}
