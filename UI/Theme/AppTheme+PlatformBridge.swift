import SwiftUI
#if canImport(SpriteKit)
import SpriteKit
#endif
#if canImport(UIKit)
import UIKit
#endif

extension AppTheme {
    #if canImport(UIKit)
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

    var uiBoardDarknessHiddenTile: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardDarknessHiddenTile),
            dark: color(for: .dark, keyPath: \.boardDarknessHiddenTile)
        )
    }

    var uiBoardDarknessBoundary: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardDarknessBoundary),
            dark: color(for: .dark, keyPath: \.boardDarknessBoundary)
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

    var uiBoardTileEffectShuffle: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardTileEffectShuffle),
            dark: color(for: .dark, keyPath: \.boardTileEffectShuffle)
        )
    }

    var uiBoardTileEffectBlast: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardTileEffectBlast),
            dark: color(for: .dark, keyPath: \.boardTileEffectBlast)
        )
    }

    var uiBoardTileEffectSlow: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardTileEffectSlow),
            dark: color(for: .dark, keyPath: \.boardTileEffectSlow)
        )
    }

    var uiBoardTileEffectSwamp: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardTileEffectSwamp),
            dark: color(for: .dark, keyPath: \.boardTileEffectSwamp)
        )
    }

    var uiBoardTileEffectPreserveCard: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardTileEffectPreserveCard),
            dark: color(for: .dark, keyPath: \.boardTileEffectPreserveCard)
        )
    }

    var uiBoardTileEffectDiscardHand: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardTileEffectDiscardHand),
            dark: color(for: .dark, keyPath: \.boardTileEffectDiscardHand)
        )
    }
    #endif

    #if canImport(SpriteKit) && canImport(UIKit)
    var skBoardBackground: SKColor { SKColor(cgColor: uiBoardBackground.cgColor) }
    var skBoardGridLine: SKColor { SKColor(cgColor: uiBoardGridLine.cgColor) }
    var skBoardTileVisited: SKColor { SKColor(cgColor: uiBoardTileVisited.cgColor) }
    var skBoardTileUnvisited: SKColor { SKColor(cgColor: uiBoardTileUnvisited.cgColor) }
    var skBoardDarknessHiddenTile: SKColor { SKColor(cgColor: uiBoardDarknessHiddenTile.cgColor) }
    var skBoardDarknessBoundary: SKColor { SKColor(cgColor: uiBoardDarknessBoundary.cgColor) }
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
    var skBoardTileEffectBlast: SKColor { SKColor(cgColor: uiBoardTileEffectBlast.cgColor) }
    var skBoardTileEffectSlow: SKColor { SKColor(cgColor: uiBoardTileEffectSlow.cgColor) }
    var skBoardTileEffectSwamp: SKColor { SKColor(cgColor: uiBoardTileEffectSwamp.cgColor) }
    var skBoardTileEffectPreserveCard: SKColor { SKColor(cgColor: uiBoardTileEffectPreserveCard.cgColor) }
    var skBoardTileEffectDiscardHand: SKColor { SKColor(cgColor: uiBoardTileEffectDiscardHand.cgColor) }
    #endif
}
