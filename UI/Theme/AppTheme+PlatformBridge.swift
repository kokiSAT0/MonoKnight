import SwiftUI
#if canImport(SpriteKit)
import SpriteKit
#endif
#if canImport(UIKit)
import UIKit
#endif

extension AppTheme {
    #if canImport(UIKit)
    /// 指定したライト/ダークそれぞれの Color から動的 UIColor を生成するユーティリティ
    private func dynamicUIColor(light: Color, dark: Color) -> UIColor {
        let lightColor = UIColor(light)
        let darkColor = UIColor(dark)
        return UIColor { traitCollection in
            let interfaceStyle: UIUserInterfaceStyle
            if let overrideColorScheme {
                interfaceStyle = overrideColorScheme == .dark ? .dark : .light
            } else {
                interfaceStyle = traitCollection.userInterfaceStyle
            }
            switch interfaceStyle {
            case .dark:
                return darkColor
            default:
                return lightColor
            }
        }
    }

    /// カラースキームごとに AppTheme を生成して Color を取り出すヘルパー
    private func color(for scheme: ColorScheme, keyPath: KeyPath<AppTheme, Color>) -> Color {
        AppTheme(colorScheme: scheme)[keyPath: keyPath]
    }

    var uiBoardBackground: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardBackground),
            dark: color(for: .dark, keyPath: \.boardBackground)
        )
    }

    var uiBoardGridLine: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardGridLine),
            dark: color(for: .dark, keyPath: \.boardGridLine)
        )
    }

    var uiBoardTileVisited: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardTileVisited),
            dark: color(for: .dark, keyPath: \.boardTileVisited)
        )
    }

    var uiBoardTileUnvisited: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardTileUnvisited),
            dark: color(for: .dark, keyPath: \.boardTileUnvisited)
        )
    }

    var uiBoardTileMultiBase: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardTileMultiBase),
            dark: color(for: .dark, keyPath: \.boardTileMultiBase)
        )
    }

    var uiBoardTileMultiStroke: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardTileMultiStroke),
            dark: color(for: .dark, keyPath: \.boardTileMultiStroke)
        )
    }

    var uiBoardTileToggle: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardTileToggle),
            dark: color(for: .dark, keyPath: \.boardTileToggle)
        )
    }

    var uiBoardTileImpassable: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardTileImpassable),
            dark: color(for: .dark, keyPath: \.boardTileImpassable)
        )
    }

    var uiBoardKnight: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardKnight),
            dark: color(for: .dark, keyPath: \.boardKnight)
        )
    }

    var uiBoardGuideHighlight: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardGuideHighlight),
            dark: color(for: .dark, keyPath: \.boardGuideHighlight)
        )
    }

    var uiBoardMultiStepHighlight: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardMultiStepHighlight),
            dark: color(for: .dark, keyPath: \.boardMultiStepHighlight)
        )
    }

    var uiBoardWarpHighlight: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardWarpHighlight),
            dark: color(for: .dark, keyPath: \.boardWarpHighlight)
        )
    }

    var uiBoardTileEffectWarp: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardTileEffectWarp),
            dark: color(for: .dark, keyPath: \.boardTileEffectWarp)
        )
    }

    /// ワープペア識別用アクセントカラー群（UIColor 配列）
    var uiWarpPairAccentColors: [UIColor] {
        switch resolvedColorScheme {
        case .dark:
            return [
                UIColor(red: 0.56, green: 0.78, blue: 1.0, alpha: 1.0),
                UIColor(red: 0.36, green: 0.88, blue: 0.82, alpha: 1.0),
                UIColor(red: 0.83, green: 0.66, blue: 1.0, alpha: 1.0),
                UIColor(red: 1.0, green: 0.80, blue: 0.54, alpha: 1.0),
                UIColor(red: 1.0, green: 0.70, blue: 0.88, alpha: 1.0),
                UIColor(red: 0.72, green: 0.94, blue: 0.78, alpha: 1.0),
            ]
        default:
            return [
                UIColor(red: 0.38, green: 0.68, blue: 1.0, alpha: 1.0),
                UIColor(red: 0.26, green: 0.82, blue: 0.78, alpha: 1.0),
                UIColor(red: 0.74, green: 0.54, blue: 0.96, alpha: 1.0),
                UIColor(red: 0.99, green: 0.68, blue: 0.46, alpha: 1.0),
                UIColor(red: 0.98, green: 0.60, blue: 0.80, alpha: 1.0),
                UIColor(red: 0.64, green: 0.88, blue: 0.68, alpha: 1.0),
            ]
        }
    }

    var uiBoardTileEffectShuffle: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardTileEffectShuffle),
            dark: color(for: .dark, keyPath: \.boardTileEffectShuffle)
        )
    }
    #endif

    #if canImport(SpriteKit) && canImport(UIKit)
    var skBoardBackground: SKColor { SKColor(cgColor: uiBoardBackground.cgColor) }
    var skBoardGridLine: SKColor { SKColor(cgColor: uiBoardGridLine.cgColor) }
    var skBoardTileVisited: SKColor { SKColor(cgColor: uiBoardTileVisited.cgColor) }
    var skBoardTileUnvisited: SKColor { SKColor(cgColor: uiBoardTileUnvisited.cgColor) }
    var skBoardTileMultiBase: SKColor { SKColor(cgColor: uiBoardTileMultiBase.cgColor) }
    var skBoardTileMultiStroke: SKColor { SKColor(cgColor: uiBoardTileMultiStroke.cgColor) }
    var skBoardTileToggle: SKColor { SKColor(cgColor: uiBoardTileToggle.cgColor) }
    var skBoardTileImpassable: SKColor { SKColor(cgColor: uiBoardTileImpassable.cgColor) }
    var skBoardKnight: SKColor { SKColor(cgColor: uiBoardKnight.cgColor) }
    var skBoardGuideHighlight: SKColor { SKColor(cgColor: uiBoardGuideHighlight.cgColor) }
    var skBoardMultiStepHighlight: SKColor { SKColor(cgColor: uiBoardMultiStepHighlight.cgColor) }
    var skBoardWarpHighlight: SKColor { SKColor(cgColor: uiBoardWarpHighlight.cgColor) }
    var skBoardTileEffectWarp: SKColor { SKColor(cgColor: uiBoardTileEffectWarp.cgColor) }
    var skBoardTileEffectShuffle: SKColor { SKColor(cgColor: uiBoardTileEffectShuffle.cgColor) }
    var skWarpPairAccentColors: [SKColor] { uiWarpPairAccentColors.map { SKColor(cgColor: $0.cgColor) } }
    #endif
}
