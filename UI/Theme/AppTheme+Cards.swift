import SwiftUI

extension AppTheme {
    /// 手札カードの背景色。淡いトーンで盤面との差を演出
    var cardBackgroundHand: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.08)
        default:
            return Color.white
        }
    }

    /// 先読みカードの背景色。手札よりわずかに明るくして注目度を上げる
    var cardBackgroundNext: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.12)
        default:
            return Color.black.opacity(0.08)
        }
    }

    /// 手札カードの枠線色
    var cardBorderHand: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white
        default:
            return Color.black.opacity(0.85)
        }
    }

    /// 先読みカードの枠線色
    var cardBorderNext: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.8)
        default:
            return Color.black.opacity(0.9)
        }
    }

    /// ワープ系カード全体に使う紫系アクセント色
    var warpCardAccent: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color(red: 0.70, green: 0.55, blue: 0.93)
        default:
            return Color(red: 0.56, green: 0.42, blue: 0.86)
        }
    }

    /// スーパーワープカード専用の明るいアクセント色
    var superWarpCardAccent: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color(red: 0.80, green: 0.62, blue: 0.98)
        default:
            return Color(red: 0.64, green: 0.48, blue: 0.92)
        }
    }

    /// 盤面中央セルのハイライト色（手札用）
    var centerHighlightHand: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.12)
        default:
            return Color.black.opacity(0.08)
        }
    }

    /// 盤面中央セルのハイライト色（先読み用）
    var centerHighlightNext: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.25)
        default:
            return Color.black.opacity(0.12)
        }
    }

    /// グリッド線の色（手札用）
    var gridLineHand: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.4)
        default:
            return Color.black.opacity(0.3)
        }
    }

    /// グリッド線の色（先読み用）
    var gridLineNext: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.55)
        default:
            return Color.black.opacity(0.4)
        }
    }

    /// 矢印やラベルなどカード上の主要要素の色
    var cardContentPrimary: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white
        default:
            return Color.black
        }
    }

    /// カード上で白黒を反転して利用する際の色
    var cardContentInverted: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.black
        default:
            return Color.white
        }
    }

    /// 複数マス移動カード専用のアクセントカラー（シアン系）
    var multiStepAccent: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color(red: 0.35, green: 0.85, blue: 0.95)
        default:
            return Color(red: 0.0, green: 0.68, blue: 0.86)
        }
    }

    /// 現在位置マーカーの縁取り色
    var startMarkerStroke: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.black.opacity(0.8)
        default:
            return Color.white.opacity(0.8)
        }
    }

    /// 目的地マーカーの縁取り色
    var destinationMarkerStroke: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white
        default:
            return Color.black
        }
    }
}
