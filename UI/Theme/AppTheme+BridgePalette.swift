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
    func dynamicUIColor(light: Color, dark: Color) -> UIColor {
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
    func color(for scheme: ColorScheme, keyPath: KeyPath<AppTheme, Color>) -> Color {
        AppTheme(colorScheme: scheme)[keyPath: keyPath]
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
    #endif

    #if canImport(SpriteKit) && canImport(UIKit)
    var skWarpPairAccentColors: [SKColor] { uiWarpPairAccentColors.map { SKColor(cgColor: $0.cgColor) } }
    #endif
}
