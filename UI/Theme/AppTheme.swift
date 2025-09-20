import SwiftUI

/// アプリ全体で共通利用する配色をまとめたテーマコンポーネント
/// DynamicProperty を採用することで、ダークモード切り替え時にも自動的に再評価される
struct AppTheme: DynamicProperty {
    /// 現在のカラースキームを環境から取得し、明暗で派生色を出し分ける
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - ベースカラー（Assets.xcassets から取得）

    /// 画面全体の背景色。ライトでは淡いグレー、ダークでは限りなく黒に近いトーンを採用
    var backgroundPrimary: Color { Color("backgroundPrimary") }

    /// カードやモーダルなど一段高いレイヤー用の背景色
    var backgroundElevated: Color { Color("backgroundElevated") }

    /// 標準の文字色。本文や主要なラベルで利用する
    var textPrimary: Color { Color("textPrimary") }

    /// サブ情報用の文字色。キャプションや補足テキスト向け
    var textSecondary: Color { Color("textSecondary") }

    /// ボタンなど強調表示する要素の背景色
    var accentPrimary: Color { Color("accentPrimary") }

    /// アクセント背景上で使用する文字色
    var accentOnPrimary: Color { Color("accentOnPrimary") }

    // MARK: - バッジ／統計表示向けカラー

    /// 統計バッジの背景色。盤面上でも視認性を損なわない半透明トーン
    var statisticBadgeBackground: Color {
        switch colorScheme {
        case .dark:
            return Color.black.opacity(0.8)
        default:
            return Color.white.opacity(0.9)
        }
    }

    /// 統計バッジの枠線色。ライトでは黒系、ダークでは白系で薄く縁取る
    var statisticBadgeBorder: Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.25)
        default:
            return Color.black.opacity(0.1)
        }
    }

    /// 統計バッジの補助ラベルに使う文字色
    var statisticTitleText: Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.65)
        default:
            return Color.black.opacity(0.6)
        }
    }

    /// 統計バッジのメイン数値に使う文字色
    var statisticValueText: Color {
        switch colorScheme {
        case .dark:
            return Color.white
        default:
            return Color.black
        }
    }

    // MARK: - カード表示向けカラー

    /// 手札カードの背景色。淡いトーンで盤面との差を演出
    var cardBackgroundHand: Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.08)
        default:
            return Color.black.opacity(0.05)
        }
    }

    /// 先読みカードの背景色。手札よりわずかに明るくして注目度を上げる
    var cardBackgroundNext: Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.12)
        default:
            return Color.black.opacity(0.08)
        }
    }

    /// 手札カードの枠線色
    var cardBorderHand: Color {
        switch colorScheme {
        case .dark:
            return Color.white
        default:
            return Color.black.opacity(0.85)
        }
    }

    /// 先読みカードの枠線色
    var cardBorderNext: Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.8)
        default:
            return Color.black.opacity(0.9)
        }
    }

    /// 盤面中央セルのハイライト色（手札用）
    var centerHighlightHand: Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.12)
        default:
            return Color.black.opacity(0.08)
        }
    }

    /// 盤面中央セルのハイライト色（先読み用）
    var centerHighlightNext: Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.25)
        default:
            return Color.black.opacity(0.12)
        }
    }

    /// グリッド線の色（手札用）
    var gridLineHand: Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.4)
        default:
            return Color.black.opacity(0.3)
        }
    }

    /// グリッド線の色（先読み用）
    var gridLineNext: Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.55)
        default:
            return Color.black.opacity(0.4)
        }
    }

    /// 矢印やラベルなどカード上の主要要素の色
    var cardContentPrimary: Color {
        switch colorScheme {
        case .dark:
            return Color.white
        default:
            return Color.black
        }
    }

    /// カード上で白黒を反転して利用する際の色
    var cardContentInverted: Color {
        switch colorScheme {
        case .dark:
            return Color.black
        default:
            return Color.white
        }
    }

    /// 現在位置マーカーの縁取り色
    var startMarkerStroke: Color {
        switch colorScheme {
        case .dark:
            return Color.black.opacity(0.8)
        default:
            return Color.white.opacity(0.8)
        }
    }

    /// 目的地マーカーの縁取り色
    var destinationMarkerStroke: Color {
        switch colorScheme {
        case .dark:
            return Color.white
        default:
            return Color.black
        }
    }

    // MARK: - プレースホルダ／メニュー等の付随 UI

    /// 手札が空の時に表示する枠線色
    var placeholderStroke: Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.25)
        default:
            return Color.black.opacity(0.2)
        }
    }

    /// 手札プレースホルダの背景色
    var placeholderBackground: Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.05)
        default:
            return Color.black.opacity(0.03)
        }
    }

    /// 手札プレースホルダのアイコン色
    var placeholderIcon: Color {
        switch colorScheme {
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
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.12)
        default:
            return Color.black.opacity(0.08)
        }
    }

    /// 右上メニューアイコンの枠線色
    var menuIconBorder: Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.25)
        default:
            return Color.black.opacity(0.12)
        }
    }

    /// ダミー広告の背景色。実広告導入まで視認性を保つプレースホルダ用
    var adPlaceholderBackground: Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.1)
        default:
            return Color.black.opacity(0.05)
        }
    }

    // MARK: - ペナルティバナー／先読みオーバーレイ

    /// ペナルティバナーの背景色
    var penaltyBannerBackground: Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.18)
        default:
            return Color.black.opacity(0.08)
        }
    }

    /// ペナルティバナーの枠線色
    var penaltyBannerBorder: Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.35)
        default:
            return Color.black.opacity(0.15)
        }
    }

    /// ペナルティバナーの影色
    var penaltyBannerShadow: Color {
        switch colorScheme {
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
        switch colorScheme {
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
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.18)
        default:
            return Color.black.opacity(0.08)
        }
    }

    /// NEXT バッジの枠線色
    var nextBadgeBorder: Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.7)
        default:
            return Color.black.opacity(0.35)
        }
    }

    /// 先読みインジケータの枠線色
    var nextIndicatorStroke: Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.7)
        default:
            return Color.black.opacity(0.35)
        }
    }

    /// 先読みインジケータ内側の塗り色
    var nextIndicatorFill: Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.85)
        default:
            return Color.black.opacity(0.65)
        }
    }

    /// 先読みインジケータの発光色
    var nextIndicatorShadow: Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.6)
        default:
            return Color.black.opacity(0.3)
        }
    }
}
