import SwiftUI

extension AppTheme {
    /// 手札カードの背景色。淡いトーンで盤面との差を演出
    var cardBackgroundHand: Color { schemeColor(light: Color.white, dark: Color.white.opacity(0.08)) }

    /// 先読みカードの背景色。手札よりわずかに明るくして注目度を上げる
    var cardBackgroundNext: Color { schemeColor(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.12)) }

    /// 手札カードの枠線色
    var cardBorderHand: Color { schemeColor(light: Color.black.opacity(0.85), dark: Color.white) }

    /// 先読みカードの枠線色
    var cardBorderNext: Color { schemeColor(light: Color.black.opacity(0.9), dark: Color.white.opacity(0.8)) }

    /// ワープ系カード全体に使う紫系アクセント色
    var warpCardAccent: Color { schemeColor(light: Self.lightWarpAccent, dark: Self.darkWarpAccent) }

    /// 盤面中央セルのハイライト色（手札用）
    var centerHighlightHand: Color { schemeColor(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.12)) }

    /// 盤面中央セルのハイライト色（先読み用）
    var centerHighlightNext: Color { schemeColor(light: Color.black.opacity(0.12), dark: Color.white.opacity(0.25)) }

    /// グリッド線の色（手札用）
    var gridLineHand: Color { schemeColor(light: Color.black.opacity(0.3), dark: Color.white.opacity(0.4)) }

    /// グリッド線の色（先読み用）
    var gridLineNext: Color { schemeColor(light: Color.black.opacity(0.4), dark: Color.white.opacity(0.55)) }

    /// 矢印やラベルなどカード上の主要要素の色
    var cardContentPrimary: Color { schemeColor(light: Color.black, dark: Color.white) }

    /// カード上で白黒を反転して利用する際の色
    var cardContentInverted: Color { schemeColor(light: Color.white, dark: Color.black) }

    /// 複数マス移動カード専用のアクセントカラー（シアン系）
    var multiStepAccent: Color { schemeColor(light: Self.lightMultiStepAccent, dark: Self.darkMultiStepAccent) }

    /// 現在位置マーカーの縁取り色
    var startMarkerStroke: Color { schemeColor(light: Color.white.opacity(0.8), dark: Color.black.opacity(0.8)) }

    /// 目的地マーカーの縁取り色
    var destinationMarkerStroke: Color { schemeColor(light: Color.black, dark: Color.white) }
}

private extension AppTheme {
    static let lightWarpAccent = Color(red: 0.56, green: 0.42, blue: 0.86)
    static let darkWarpAccent = Color(red: 0.70, green: 0.55, blue: 0.93)
    static let lightMultiStepAccent = Color(red: 0.0, green: 0.68, blue: 0.86)
    static let darkMultiStepAccent = Color(red: 0.35, green: 0.85, blue: 0.95)
}
