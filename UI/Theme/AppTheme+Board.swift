import SwiftUI

extension AppTheme {
    /// SpriteKit で描画する盤面の背景色
    var boardBackground: Color { backgroundPrimary }

    /// グリッド線の色（ライト/ダークでコントラストを調整）
    var boardGridLine: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.75)
        default:
            return Color.black.opacity(0.65)
        }
    }

    /// 踏破済みマスの塗り色
    var boardTileVisited: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.38)
        default:
            return Color.black.opacity(0.30)
        }
    }

    /// 未踏破マスの塗り色
    var boardTileUnvisited: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.05)
        default:
            return Color.black.opacity(0.025)
        }
    }

    /// 複数回踏破マスの基準色
    var boardTileMultiBase: Color { boardTileUnvisited }

    /// 複数回踏破マス専用の枠線色
    var boardTileMultiStroke: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.82)
        default:
            return Color.black.opacity(0.78)
        }
    }

    /// トグルマスの塗り色
    var boardTileToggle: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.5)
        default:
            return Color.black.opacity(0.32)
        }
    }

    /// 移動不可マスの塗り色
    var boardTileImpassable: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.black.opacity(0.92)
        default:
            return Color.black
        }
    }

    /// 駒本体の塗り色
    var boardKnight: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white
        default:
            return Color.black
        }
    }

    /// ガイドモードで候補マスを照らす際の基準色
    var boardGuideHighlight: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color(red: 1.0, green: 0.74, blue: 0.38).opacity(0.9)
        default:
            return Color(red: 0.94, green: 0.41, blue: 0.08).opacity(0.85)
        }
    }

    /// 複数マス移動カード専用のガイド枠色
    var boardMultiStepHighlight: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color(red: 0.35, green: 0.85, blue: 0.95).opacity(0.92)
        default:
            return Color(red: 0.0, green: 0.68, blue: 0.86).opacity(0.88)
        }
    }

    /// ワープカード専用のガイド枠色
    var boardWarpHighlight: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color(red: 0.70, green: 0.55, blue: 0.93).opacity(0.92)
        default:
            return Color(red: 0.56, green: 0.42, blue: 0.86).opacity(0.9)
        }
    }

    /// ワープ効果を描画する際のアクセントカラー
    var boardTileEffectWarp: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color(red: 0.56, green: 0.75, blue: 1.0).opacity(0.95)
        default:
            return Color(red: 0.36, green: 0.56, blue: 0.98).opacity(0.95)
        }
    }

    /// 手札シャッフル効果を描画する際のニュートラルカラー
    var boardTileEffectShuffle: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.9)
        default:
            return Color(red: 0.3, green: 0.3, blue: 0.3).opacity(0.92)
        }
    }
}
