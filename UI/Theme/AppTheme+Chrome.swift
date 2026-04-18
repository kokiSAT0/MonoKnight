import SwiftUI

extension AppTheme {
    /// 手札が空の時に表示する枠線色
    var placeholderStroke: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.25)
        default:
            return Color.black.opacity(0.2)
        }
    }

    /// 手札プレースホルダの背景色
    var placeholderBackground: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.05)
        default:
            return Color.black.opacity(0.03)
        }
    }

    /// 手札プレースホルダのアイコン色
    var placeholderIcon: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.4)
        default:
            return Color.black.opacity(0.35)
        }
    }

    /// 右上メニューアイコンの前景色
    var menuIconForeground: Color { cardContentPrimary }

    /// 右上メニューアイコンの背景色
    var menuIconBackground: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.12)
        default:
            return Color.black.opacity(0.08)
        }
    }

    /// 右上メニューアイコンの枠線色
    var menuIconBorder: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.25)
        default:
            return Color.black.opacity(0.12)
        }
    }

    /// ダミー広告の背景色。実広告導入まで視認性を保つプレースホルダ用
    var adPlaceholderBackground: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.1)
        default:
            return Color.black.opacity(0.05)
        }
    }

    /// スポーン案内の背景色。ライトモードでは白ベース、ダークモードでは黒ベースで適度に透過させる
    var spawnOverlayBackground: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.black.opacity(0.82)
        default:
            return Color.white.opacity(0.92)
        }
    }

    /// スポーン案内の枠線色。背景とのコントラストが強すぎないよう控えめな値に調整
    var spawnOverlayBorder: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.25)
        default:
            return Color.black.opacity(0.15)
        }
    }

    /// スポーン案内ボックスのドロップシャドウ色
    var spawnOverlayShadow: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.black.opacity(0.7)
        default:
            return Color.black.opacity(0.25)
        }
    }

    /// ペナルティバナーの背景色
    var penaltyBannerBackground: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.18)
        default:
            return Color.black.opacity(0.08)
        }
    }

    /// ペナルティバナーの枠線色
    var penaltyBannerBorder: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.35)
        default:
            return Color.black.opacity(0.15)
        }
    }

    /// ペナルティバナーの影色
    var penaltyBannerShadow: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.black.opacity(0.35)
        default:
            return Color.black.opacity(0.12)
        }
    }

    /// ペナルティバナーのメインテキスト色
    var penaltyTextPrimary: Color { cardContentPrimary }

    /// ペナルティバナーの補足テキスト色
    var penaltyTextSecondary: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.8)
        default:
            return Color.black.opacity(0.7)
        }
    }

    /// ペナルティバナーのアイコン（シンボル）の色
    var penaltyIconForeground: Color { cardContentInverted }

    /// ペナルティバナーのアイコン背景色
    var penaltyIconBackground: Color { cardContentPrimary }

    /// NEXT バッジの文字色
    var nextBadgeText: Color { cardContentPrimary }

    /// NEXT バッジの背景色
    var nextBadgeBackground: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.18)
        default:
            return Color.black.opacity(0.08)
        }
    }

    /// NEXT バッジの枠線色
    var nextBadgeBorder: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.7)
        default:
            return Color.black.opacity(0.35)
        }
    }
}
