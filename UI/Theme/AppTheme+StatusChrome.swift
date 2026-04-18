import SwiftUI

extension AppTheme {
    /// NEXT バッジの文字色
    var nextBadgeText: Color { cardContentPrimary }

    /// NEXT バッジの背景色
    var nextBadgeBackground: Color { schemeColor(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.18)) }

    /// NEXT バッジの枠線色
    var nextBadgeBorder: Color { schemeColor(light: Color.black.opacity(0.35), dark: Color.white.opacity(0.7)) }
}
