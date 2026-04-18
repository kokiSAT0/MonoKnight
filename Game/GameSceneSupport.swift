#if canImport(SpriteKit)
    import SpriteKit

    extension SKColor {
        fileprivate func interpolated(to other: SKColor, fraction: CGFloat) -> SKColor {
            let clamped = max(0.0, min(1.0, fraction))
            let first = rgbaComponents()
            let second = other.rgbaComponents()
            return SKColor(
                red: first.r + (second.r - first.r) * clamped,
                green: first.g + (second.g - first.g) * clamped,
                blue: first.b + (second.b - first.b) * clamped,
                alpha: first.a + (second.a - first.a) * clamped
            )
        }

        private func rgbaComponents() -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
            #if canImport(UIKit)
                var r: CGFloat = 0
                var g: CGFloat = 0
                var b: CGFloat = 0
                var a: CGFloat = 0
                getRed(&r, green: &g, blue: &b, alpha: &a)
                return (r, g, b, a)
            #else
                let converted = usingColorSpace(.extendedSRGB) ?? self
                return (
                    converted.redComponent,
                    converted.greenComponent,
                    converted.blueComponent,
                    converted.alphaComponent
                )
            #endif
        }
    }
#endif
