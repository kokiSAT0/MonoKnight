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

    var uiBoardStarChartLine: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardStarChartLine),
            dark: color(for: .dark, keyPath: \.boardStarChartLine)
        )
    }

    var uiBoardStarChartNode: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardStarChartNode),
            dark: color(for: .dark, keyPath: \.boardStarChartNode)
        )
    }

    var uiBoardConstellationLine: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardConstellationLine),
            dark: color(for: .dark, keyPath: \.boardConstellationLine)
        )
    }

    var uiBoardConstellationGlowLine: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardConstellationGlowLine),
            dark: color(for: .dark, keyPath: \.boardConstellationGlowLine)
        )
    }

    var uiBoardConstellationStar: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardConstellationStar),
            dark: color(for: .dark, keyPath: \.boardConstellationStar)
        )
    }

    var uiBoardConstellationStarGlow: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardConstellationStarGlow),
            dark: color(for: .dark, keyPath: \.boardConstellationStarGlow)
        )
    }

    var uiBoardStarParticle: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardStarParticle),
            dark: color(for: .dark, keyPath: \.boardStarParticle)
        )
    }

    var uiBoardNebulaDepth: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardNebulaDepth),
            dark: color(for: .dark, keyPath: \.boardNebulaDepth)
        )
    }

    var uiBoardDistantStar: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardDistantStar),
            dark: color(for: .dark, keyPath: \.boardDistantStar)
        )
    }

    var uiBoardDistantStarTwinkle: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardDistantStarTwinkle),
            dark: color(for: .dark, keyPath: \.boardDistantStarTwinkle)
        )
    }

    var uiBoardGlassHighlight: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardGlassHighlight),
            dark: color(for: .dark, keyPath: \.boardGlassHighlight)
        )
    }

    var uiBoardTileInnerGlow: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardTileInnerGlow),
            dark: color(for: .dark, keyPath: \.boardTileInnerGlow)
        )
    }

    var uiBoardAstralCore: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardAstralCore),
            dark: color(for: .dark, keyPath: \.boardAstralCore)
        )
    }

    var uiBoardAstralCoreRing: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardAstralCoreRing),
            dark: color(for: .dark, keyPath: \.boardAstralCoreRing)
        )
    }

    var uiBoardAstralCoreGlow: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardAstralCoreGlow),
            dark: color(for: .dark, keyPath: \.boardAstralCoreGlow)
        )
    }

    var uiBoardAstralCorePulse: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardAstralCorePulse),
            dark: color(for: .dark, keyPath: \.boardAstralCorePulse)
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

    var uiBoardTileEffectPoison: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardTileEffectPoison),
            dark: color(for: .dark, keyPath: \.boardTileEffectPoison)
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

    var uiBoardDungeonEnemy: UIColor {
        dynamicUIColor(light: color(for: .light, keyPath: \.boardDungeonEnemy), dark: color(for: .dark, keyPath: \.boardDungeonEnemy))
    }

    var uiBoardDungeonDanger: UIColor {
        dynamicUIColor(light: color(for: .light, keyPath: \.boardDungeonDanger), dark: color(for: .dark, keyPath: \.boardDungeonDanger))
    }

    var uiBoardDungeonWarning: UIColor {
        dynamicUIColor(light: color(for: .light, keyPath: \.boardDungeonWarning), dark: color(for: .dark, keyPath: \.boardDungeonWarning))
    }

    var uiBoardDungeonCardPickup: UIColor {
        dynamicUIColor(light: color(for: .light, keyPath: \.boardDungeonCardPickup), dark: color(for: .dark, keyPath: \.boardDungeonCardPickup))
    }

    var uiBoardDungeonRelicPickup: UIColor {
        dynamicUIColor(light: color(for: .light, keyPath: \.boardDungeonRelicPickup), dark: color(for: .dark, keyPath: \.boardDungeonRelicPickup))
    }

    var uiBoardDungeonSuspiciousRelicPickup: UIColor {
        dynamicUIColor(light: color(for: .light, keyPath: \.boardDungeonSuspiciousRelicPickup), dark: color(for: .dark, keyPath: \.boardDungeonSuspiciousRelicPickup))
    }

    var uiBoardDungeonDamageTrap: UIColor {
        dynamicUIColor(light: color(for: .light, keyPath: \.boardDungeonDamageTrap), dark: color(for: .dark, keyPath: \.boardDungeonDamageTrap))
    }

    var uiBoardDungeonHpHalvingTrap: UIColor {
        dynamicUIColor(light: color(for: .light, keyPath: \.boardDungeonHpHalvingTrap), dark: color(for: .dark, keyPath: \.boardDungeonHpHalvingTrap))
    }

    var uiBoardDungeonLavaTile: UIColor {
        dynamicUIColor(light: color(for: .light, keyPath: \.boardDungeonLavaTile), dark: color(for: .dark, keyPath: \.boardDungeonLavaTile))
    }

    var uiBoardDungeonHealingTile: UIColor {
        dynamicUIColor(light: color(for: .light, keyPath: \.boardDungeonHealingTile), dark: color(for: .dark, keyPath: \.boardDungeonHealingTile))
    }

    var uiBoardDungeonKey: UIColor {
        dynamicUIColor(light: color(for: .light, keyPath: \.boardDungeonKey), dark: color(for: .dark, keyPath: \.boardDungeonKey))
    }
    #endif

    #if canImport(SpriteKit) && canImport(UIKit)
    var skBoardBackground: SKColor { SKColor(cgColor: uiBoardBackground.cgColor) }
    var skBoardGridLine: SKColor { SKColor(cgColor: uiBoardGridLine.cgColor) }
    var skBoardStarChartLine: SKColor { SKColor(cgColor: uiBoardStarChartLine.cgColor) }
    var skBoardStarChartNode: SKColor { SKColor(cgColor: uiBoardStarChartNode.cgColor) }
    var skBoardConstellationLine: SKColor { SKColor(cgColor: uiBoardConstellationLine.cgColor) }
    var skBoardConstellationGlowLine: SKColor { SKColor(cgColor: uiBoardConstellationGlowLine.cgColor) }
    var skBoardConstellationStar: SKColor { SKColor(cgColor: uiBoardConstellationStar.cgColor) }
    var skBoardConstellationStarGlow: SKColor { SKColor(cgColor: uiBoardConstellationStarGlow.cgColor) }
    var skBoardStarParticle: SKColor { SKColor(cgColor: uiBoardStarParticle.cgColor) }
    var skBoardNebulaDepth: SKColor { SKColor(cgColor: uiBoardNebulaDepth.cgColor) }
    var skBoardDistantStar: SKColor { SKColor(cgColor: uiBoardDistantStar.cgColor) }
    var skBoardDistantStarTwinkle: SKColor { SKColor(cgColor: uiBoardDistantStarTwinkle.cgColor) }
    var skBoardGlassHighlight: SKColor { SKColor(cgColor: uiBoardGlassHighlight.cgColor) }
    var skBoardTileInnerGlow: SKColor { SKColor(cgColor: uiBoardTileInnerGlow.cgColor) }
    var skBoardAstralCore: SKColor { SKColor(cgColor: uiBoardAstralCore.cgColor) }
    var skBoardAstralCoreRing: SKColor { SKColor(cgColor: uiBoardAstralCoreRing.cgColor) }
    var skBoardAstralCoreGlow: SKColor { SKColor(cgColor: uiBoardAstralCoreGlow.cgColor) }
    var skBoardAstralCorePulse: SKColor { SKColor(cgColor: uiBoardAstralCorePulse.cgColor) }
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
    var skBoardTileEffectPoison: SKColor { SKColor(cgColor: uiBoardTileEffectPoison.cgColor) }
    var skBoardTileEffectSwamp: SKColor { SKColor(cgColor: uiBoardTileEffectSwamp.cgColor) }
    var skBoardTileEffectPreserveCard: SKColor { SKColor(cgColor: uiBoardTileEffectPreserveCard.cgColor) }
    var skBoardTileEffectDiscardHand: SKColor { SKColor(cgColor: uiBoardTileEffectDiscardHand.cgColor) }
    var skBoardDungeonEnemy: SKColor { SKColor(cgColor: uiBoardDungeonEnemy.cgColor) }
    var skBoardDungeonDanger: SKColor { SKColor(cgColor: uiBoardDungeonDanger.cgColor) }
    var skBoardDungeonWarning: SKColor { SKColor(cgColor: uiBoardDungeonWarning.cgColor) }
    var skBoardDungeonCardPickup: SKColor { SKColor(cgColor: uiBoardDungeonCardPickup.cgColor) }
    var skBoardDungeonRelicPickup: SKColor { SKColor(cgColor: uiBoardDungeonRelicPickup.cgColor) }
    var skBoardDungeonSuspiciousRelicPickup: SKColor { SKColor(cgColor: uiBoardDungeonSuspiciousRelicPickup.cgColor) }
    var skBoardDungeonDamageTrap: SKColor { SKColor(cgColor: uiBoardDungeonDamageTrap.cgColor) }
    var skBoardDungeonHpHalvingTrap: SKColor { SKColor(cgColor: uiBoardDungeonHpHalvingTrap.cgColor) }
    var skBoardDungeonLavaTile: SKColor { SKColor(cgColor: uiBoardDungeonLavaTile.cgColor) }
    var skBoardDungeonHealingTile: SKColor { SKColor(cgColor: uiBoardDungeonHealingTile.cgColor) }
    var skBoardDungeonKey: SKColor { SKColor(cgColor: uiBoardDungeonKey.cgColor) }
    #endif
}
