#if canImport(UIKit)
import XCTest
import SwiftUI
#if canImport(SpriteKit)
import SpriteKit
#endif
@testable import MonoKnightApp

@MainActor
final class AppThemeTests: XCTestCase {
    func testRepresentativeChromeTokensRemainStableAcrossSchemes() {
        let light = AppTheme(colorScheme: .light)
        let dark = AppTheme(colorScheme: .dark)

        assertColor(light.menuIconBackground, equals: UIColor.black.withAlphaComponent(0.08))
        assertColor(dark.menuIconBackground, equals: UIColor.white.withAlphaComponent(0.12))
        assertColor(light.spawnOverlayBackground, equals: UIColor.white.withAlphaComponent(0.92))
        assertColor(dark.spawnOverlayBackground, equals: UIColor.black.withAlphaComponent(0.82))
        assertColor(light.penaltyBannerBorder, equals: UIColor.black.withAlphaComponent(0.15))
        assertColor(dark.penaltyBannerBorder, equals: UIColor.white.withAlphaComponent(0.35))
        assertColor(light.nextBadgeBorder, equals: UIColor.black.withAlphaComponent(0.35))
        assertColor(dark.nextBadgeBorder, equals: UIColor.white.withAlphaComponent(0.7))
    }

    func testCardAndBoardAccentRelationshipsRemainStable() {
        let light = AppTheme(colorScheme: .light)
        let dark = AppTheme(colorScheme: .dark)

        assertColor(light.warpCardAccent, equals: UIColor(red: 0.56, green: 0.42, blue: 0.86, alpha: 1.0))
        assertColor(dark.warpCardAccent, equals: UIColor(red: 0.70, green: 0.55, blue: 0.93, alpha: 1.0))
        assertColor(light.boardWarpHighlight, equals: UIColor(red: 0.56, green: 0.42, blue: 0.86, alpha: 0.9))
        assertColor(dark.boardWarpHighlight, equals: UIColor(red: 0.70, green: 0.55, blue: 0.93, alpha: 0.92))
        assertColor(light.boardMultiStepHighlight, equals: UIColor(red: 0.0, green: 0.68, blue: 0.86, alpha: 0.88))
        assertColor(dark.boardMultiStepHighlight, equals: UIColor(red: 0.35, green: 0.85, blue: 0.95, alpha: 0.92))
    }

    func testBoardBridgePaletteRemainsStableAcrossSchemes() {
        let light = AppTheme(colorScheme: .light)
        let dark = AppTheme(colorScheme: .dark)

        assertUIColor(light.uiBoardGridLine, equals: UIColor.black.withAlphaComponent(0.65), userInterfaceStyle: .light)
        assertUIColor(dark.uiBoardGridLine, equals: UIColor.white.withAlphaComponent(0.75), userInterfaceStyle: .dark)
        assertUIColor(light.uiBoardTileEffectWarp, equals: UIColor(red: 0.36, green: 0.56, blue: 0.98, alpha: 0.95), userInterfaceStyle: .light)
        assertUIColor(dark.uiBoardTileEffectWarp, equals: UIColor(red: 0.56, green: 0.75, blue: 1.0, alpha: 0.95), userInterfaceStyle: .dark)
        assertUIColor(light.uiBoardTileEffectBlast, equals: UIColor(red: 0.0, green: 0.68, blue: 0.86, alpha: 0.95), userInterfaceStyle: .light)
        assertUIColor(dark.uiBoardTileEffectBlast, equals: UIColor(red: 0.35, green: 0.85, blue: 0.95, alpha: 0.95), userInterfaceStyle: .dark)
        assertUIColor(light.uiBoardTileEffectSlow, equals: UIColor(red: 0.82, green: 0.22, blue: 0.26, alpha: 0.95), userInterfaceStyle: .light)
        assertUIColor(dark.uiBoardTileEffectSlow, equals: UIColor(red: 1.0, green: 0.46, blue: 0.50, alpha: 0.95), userInterfaceStyle: .dark)
        assertUIColor(light.uiBoardTileEffectSwamp, equals: UIColor(red: 0.04, green: 0.58, blue: 0.50, alpha: 0.92), userInterfaceStyle: .light)
        assertUIColor(dark.uiBoardTileEffectSwamp, equals: UIColor(red: 0.30, green: 0.86, blue: 0.78, alpha: 0.94), userInterfaceStyle: .dark)
        assertUIColor(light.uiBoardTileEffectPreserveCard, equals: UIColor(red: 0.90, green: 0.54, blue: 0.06, alpha: 0.95), userInterfaceStyle: .light)
        assertUIColor(dark.uiBoardTileEffectPreserveCard, equals: UIColor(red: 1.0, green: 0.72, blue: 0.24, alpha: 0.95), userInterfaceStyle: .dark)
        XCTAssertEqual(light.uiWarpPairAccentColors.count, 6)
        XCTAssertEqual(dark.uiWarpPairAccentColors.count, 6)

        #if canImport(SpriteKit)
        assertSKColor(light.skBoardTileEffectShuffle, equals: UIColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 0.92))
        assertSKColor(dark.skBoardTileEffectShuffle, equals: UIColor.white.withAlphaComponent(0.9))
        assertSKColor(light.skBoardTileEffectBlast, equals: UIColor(red: 0.0, green: 0.68, blue: 0.86, alpha: 0.95))
        assertSKColor(dark.skBoardTileEffectBlast, equals: UIColor(red: 0.35, green: 0.85, blue: 0.95, alpha: 0.95))
        assertSKColor(light.skBoardTileEffectSlow, equals: UIColor(red: 0.82, green: 0.22, blue: 0.26, alpha: 0.95))
        assertSKColor(dark.skBoardTileEffectSlow, equals: UIColor(red: 1.0, green: 0.46, blue: 0.50, alpha: 0.95))
        assertSKColor(light.skBoardTileEffectSwamp, equals: UIColor(red: 0.04, green: 0.58, blue: 0.50, alpha: 0.92))
        assertSKColor(dark.skBoardTileEffectSwamp, equals: UIColor(red: 0.30, green: 0.86, blue: 0.78, alpha: 0.94))
        assertSKColor(light.skBoardTileEffectPreserveCard, equals: UIColor(red: 0.90, green: 0.54, blue: 0.06, alpha: 0.95))
        assertSKColor(dark.skBoardTileEffectPreserveCard, equals: UIColor(red: 1.0, green: 0.72, blue: 0.24, alpha: 0.95))
        XCTAssertEqual(light.skWarpPairAccentColors.count, 6)
        XCTAssertEqual(dark.skWarpPairAccentColors.count, 6)
        #endif
    }

    private func assertColor(
        _ color: Color,
        equals expected: UIColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertUIColor(UIColor(color), equals: expected, userInterfaceStyle: .unspecified, file: file, line: line)
    }

    private func assertUIColor(
        _ color: UIColor,
        equals expected: UIColor,
        userInterfaceStyle: UIUserInterfaceStyle,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let traits = UITraitCollection(userInterfaceStyle: userInterfaceStyle)
        let resolved = color.resolvedColor(with: traits)
        let expectedResolved = expected.resolvedColor(with: traits)
        XCTAssertEqual(resolved.rgbaComponents, expectedResolved.rgbaComponents, file: file, line: line)
    }

    #if canImport(SpriteKit)
    private func assertSKColor(
        _ color: SKColor,
        equals expected: UIColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertUIColor(UIColor(cgColor: color.cgColor), equals: expected, userInterfaceStyle: .unspecified, file: file, line: line)
    }
    #endif
}

private extension UIColor {
    var rgbaComponents: [CGFloat] {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return [red, green, blue, alpha]
    }
}
#endif
