import SwiftUI

extension AppTheme {
    /// 統計バッジの背景色。盤面上でも視認性を損なわない半透明トーン
    var statisticBadgeBackground: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.black.opacity(0.8)
        default:
            return Color.white.opacity(0.9)
        }
    }

    /// 統計バッジの枠線色。ライトでは黒系、ダークでは白系で薄く縁取る
    var statisticBadgeBorder: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.25)
        default:
            return Color.black.opacity(0.1)
        }
    }

    /// 統計バッジの補助ラベルに使う文字色
    var statisticTitleText: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.65)
        default:
            return Color.black.opacity(0.6)
        }
    }

    /// 統計バッジのメイン数値に使う文字色
    var statisticValueText: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white
        default:
            return Color.black
        }
    }
}
