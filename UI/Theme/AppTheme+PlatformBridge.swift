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

    var uiBoardTileEffectBoost: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardTileEffectBoost),
            dark: color(for: .dark, keyPath: \.boardTileEffectBoost)
        )
    }

    var uiBoardTileEffectSlow: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardTileEffectSlow),
            dark: color(for: .dark, keyPath: \.boardTileEffectSlow)
        )
    }

    var uiBoardTileEffectNextRefresh: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardTileEffectNextRefresh),
            dark: color(for: .dark, keyPath: \.boardTileEffectNextRefresh)
        )
    }

    var uiBoardTileEffectFreeFocus: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardTileEffectFreeFocus),
            dark: color(for: .dark, keyPath: \.boardTileEffectFreeFocus)
        )
    }

    var uiBoardTileEffectPreserveCard: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardTileEffectPreserveCard),
            dark: color(for: .dark, keyPath: \.boardTileEffectPreserveCard)
        )
    }

    var uiBoardTileEffectDraft: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardTileEffectDraft),
            dark: color(for: .dark, keyPath: \.boardTileEffectDraft)
        )
    }

    var uiBoardTileEffectOverload: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardTileEffectOverload),
            dark: color(for: .dark, keyPath: \.boardTileEffectOverload)
        )
    }

    var uiBoardTileEffectTargetSwap: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardTileEffectTargetSwap),
            dark: color(for: .dark, keyPath: \.boardTileEffectTargetSwap)
        )
    }

    var uiBoardTileEffectOpenGate: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardTileEffectOpenGate),
            dark: color(for: .dark, keyPath: \.boardTileEffectOpenGate)
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
    var skBoardTileEffectBoost: SKColor { SKColor(cgColor: uiBoardTileEffectBoost.cgColor) }
    var skBoardTileEffectSlow: SKColor { SKColor(cgColor: uiBoardTileEffectSlow.cgColor) }
    var skBoardTileEffectNextRefresh: SKColor { SKColor(cgColor: uiBoardTileEffectNextRefresh.cgColor) }
    var skBoardTileEffectFreeFocus: SKColor { SKColor(cgColor: uiBoardTileEffectFreeFocus.cgColor) }
    var skBoardTileEffectPreserveCard: SKColor { SKColor(cgColor: uiBoardTileEffectPreserveCard.cgColor) }
    var skBoardTileEffectDraft: SKColor { SKColor(cgColor: uiBoardTileEffectDraft.cgColor) }
    var skBoardTileEffectOverload: SKColor { SKColor(cgColor: uiBoardTileEffectOverload.cgColor) }
    var skBoardTileEffectTargetSwap: SKColor { SKColor(cgColor: uiBoardTileEffectTargetSwap.cgColor) }
    var skBoardTileEffectOpenGate: SKColor { SKColor(cgColor: uiBoardTileEffectOpenGate.cgColor) }
    #endif
}
