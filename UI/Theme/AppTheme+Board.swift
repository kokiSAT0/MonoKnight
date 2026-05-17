import SwiftUI

extension AppTheme {
    /// SpriteKit で描画する盤面の背景色
    var boardBackground: Color {
        switch visualStyle {
        case .classic:
            return backgroundPrimary
        case .starChartSurveyTower:
            return schemeColor(
                light: Color(red: 0.94, green: 0.98, blue: 1.0),
                dark: Color(red: 0.92, green: 0.97, blue: 1.0)
            )
        }
    }

    /// グリッド線の色（ライト/ダークでコントラストを調整）
    var boardGridLine: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Color.black.opacity(0.65), dark: Color.white.opacity(0.75))
        case .starChartSurveyTower:
            return schemeColor(
                light: Color(red: 0.0, green: 0.56, blue: 0.78).opacity(0.30),
                dark: Color(red: 0.0, green: 0.58, blue: 0.82).opacity(0.34)
            )
        }
    }

    /// ネオングリッドテーマで床に薄く重ねるARパネル角の色
    var boardStarChartLine: Color {
        switch visualStyle {
        case .classic:
            return Color.clear
        case .starChartSurveyTower:
            return schemeColor(
                light: Color(red: 0.0, green: 0.64, blue: 0.86).opacity(0.22),
                dark: Color(red: 0.0, green: 0.68, blue: 0.88).opacity(0.24)
            )
        }
    }

    /// ネオングリッドテーマでは盤面上の鋲を使わない
    var boardStarChartNode: Color {
        switch visualStyle {
        case .classic:
            return Color.clear
        case .starChartSurveyTower:
            return schemeColor(
                light: Color.clear,
                dark: Color.clear
            )
        }
    }

    /// ネオングリッドテーマでは盤面全体の測量線を使わない
    var boardConstellationLine: Color {
        switch visualStyle {
        case .classic:
            return Color.clear
        case .starChartSurveyTower:
            return schemeColor(
                light: Color.clear,
                dark: Color.clear
            )
        }
    }

    /// ネオングリッドテーマでは盤面全体の測量線グローを使わない
    var boardConstellationGlowLine: Color {
        switch visualStyle {
        case .classic:
            return Color.clear
        case .starChartSurveyTower:
            return schemeColor(
                light: Color.clear,
                dark: Color.clear
            )
        }
    }

    /// ネオングリッドテーマでは盤面全体の鋲を使わない
    var boardConstellationStar: Color {
        switch visualStyle {
        case .classic:
            return Color.clear
        case .starChartSurveyTower:
            return schemeColor(
                light: Color.clear,
                dark: Color.clear
            )
        }
    }

    /// ネオングリッドテーマでは盤面全体の鋲グローを使わない
    var boardConstellationStarGlow: Color {
        switch visualStyle {
        case .classic:
            return Color.clear
        case .starChartSurveyTower:
            return schemeColor(
                light: Color.clear,
                dark: Color.clear
            )
        }
    }

    /// ネオングリッドテーマでは遠景星粒を使わない
    var boardStarParticle: Color {
        switch visualStyle {
        case .classic:
            return Color.clear
        case .starChartSurveyTower:
            return schemeColor(
                light: Color.clear,
                dark: Color.clear
            )
        }
    }

    /// ネオングリッドテーマでは宇宙背景を使わない
    var boardNebulaDepth: Color {
        switch visualStyle {
        case .classic:
            return Color.clear
        case .starChartSurveyTower:
            return schemeColor(
                light: Color.clear,
                dark: Color.clear
            )
        }
    }

    /// ネオングリッドテーマでは遠景星粒を使わない
    var boardDistantStar: Color {
        switch visualStyle {
        case .classic:
            return Color.clear
        case .starChartSurveyTower:
            return schemeColor(
                light: Color.clear,
                dark: Color.clear
            )
        }
    }

    /// ネオングリッドテーマでは瞬く星粒を使わない
    var boardDistantStarTwinkle: Color {
        switch visualStyle {
        case .classic:
            return Color.clear
        case .starChartSurveyTower:
            return schemeColor(
                light: Color.clear,
                dark: Color.clear
            )
        }
    }

    /// ネオングリッドテーマでタイルに薄いAR面差を足す色
    var boardGlassHighlight: Color {
        switch visualStyle {
        case .classic:
            return Color.clear
        case .starChartSurveyTower:
            return schemeColor(
                light: Color(red: 0.0, green: 0.78, blue: 1.0).opacity(0.10),
                dark: Color(red: 0.20, green: 0.90, blue: 1.0).opacity(0.12)
            )
        }
    }

    /// ネオングリッドテーマでは通常マスの内側発光枠を使わない
    var boardTileInnerGlow: Color {
        switch visualStyle {
        case .classic:
            return Color.clear
        case .starChartSurveyTower:
            return Color.clear
        }
    }

    /// ネオングリッドテーマでは盤面中央の方位鋲を使わない
    var boardAstralCore: Color {
        switch visualStyle {
        case .classic:
            return Color.clear
        case .starChartSurveyTower:
            return schemeColor(
                light: Color.clear,
                dark: Color.clear
            )
        }
    }

    /// ネオングリッドテーマでは盤面内の方位環を使わない
    var boardAstralCoreRing: Color {
        switch visualStyle {
        case .classic:
            return Color.clear
        case .starChartSurveyTower:
            return schemeColor(
                light: Color.clear,
                dark: Color.clear
            )
        }
    }

    /// ネオングリッドテーマでは盤面内の方位環グローを使わない
    var boardAstralCoreGlow: Color {
        switch visualStyle {
        case .classic:
            return Color.clear
        case .starChartSurveyTower:
            return schemeColor(
                light: Color.clear,
                dark: Color.clear
            )
        }
    }

    /// ネオングリッドテーマでは星核パルスを使わない
    var boardAstralCorePulse: Color {
        switch visualStyle {
        case .classic:
            return Color.clear
        case .starChartSurveyTower:
            return schemeColor(
                light: Color.clear,
                dark: Color.clear
            )
        }
    }

    /// 踏破済みマスの塗り色
    var boardTileVisited: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Color.black.opacity(0.30), dark: Color.white.opacity(0.38))
        case .starChartSurveyTower:
            return schemeColor(
                light: Color(red: 0.78, green: 0.92, blue: 1.0).opacity(0.92),
                dark: Color(red: 0.80, green: 0.94, blue: 1.0).opacity(0.92)
            )
        }
    }

    /// 未踏破マスの塗り色
    var boardTileUnvisited: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Color.black.opacity(0.025), dark: Color.white.opacity(0.05))
        case .starChartSurveyTower:
            return schemeColor(
                light: Color(red: 0.96, green: 0.995, blue: 1.0).opacity(0.96),
                dark: Color(red: 0.95, green: 0.99, blue: 1.0).opacity(0.96)
            )
        }
    }

    /// 暗闇フロアで視界外になっているマスの塗り色
    var boardDarknessHiddenTile: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Color.black.opacity(0.56), dark: Color.black.opacity(0.88))
        case .starChartSurveyTower:
            return schemeColor(
                light: Color(red: 0.03, green: 0.06, blue: 0.10).opacity(0.70),
                dark: Color(red: 0.02, green: 0.05, blue: 0.09).opacity(0.74)
            )
        }
    }

    /// 暗闇フロアで視界境界を示す線色
    var boardDarknessBoundary: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Color.white.opacity(0.72), dark: Color.white.opacity(0.42))
        case .starChartSurveyTower:
            return schemeColor(
                light: Color(red: 0.0, green: 0.88, blue: 1.0).opacity(0.76),
                dark: Color(red: 0.0, green: 0.88, blue: 1.0).opacity(0.78)
            )
        }
    }

    /// 複数回踏破マスの基準色
    var boardTileMultiBase: Color { boardTileUnvisited }

    /// 複数回踏破マス専用の枠線色
    var boardTileMultiStroke: Color { schemeColor(light: Color.black.opacity(0.78), dark: Color.white.opacity(0.82)) }

    /// トグルマスの塗り色
    var boardTileToggle: Color { schemeColor(light: Color.black.opacity(0.32), dark: Color.white.opacity(0.5)) }

    /// 移動不可マスの塗り色
    var boardTileImpassable: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Color.black, dark: Color.black.opacity(0.92))
        case .starChartSurveyTower:
            return schemeColor(
                light: Color(red: 0.16, green: 0.18, blue: 0.22),
                dark: Color(red: 0.13, green: 0.16, blue: 0.20)
            )
        }
    }

    /// 駒本体の塗り色
    var boardKnight: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Color.black, dark: Color.white)
        case .starChartSurveyTower:
            return schemeColor(
                light: Color(red: 0.02, green: 0.16, blue: 0.28),
                dark: Color(red: 0.02, green: 0.16, blue: 0.28)
            )
        }
    }

    /// ガイドモードで候補マスを照らす際の基準色
    var boardGuideHighlight: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Self.lightBoardGuideHighlight, dark: Self.darkBoardGuideHighlight)
        case .starChartSurveyTower:
            return schemeColor(light: Self.starLightOldGold, dark: Self.starDarkOldGold)
        }
    }

    /// 複数マス移動カード専用のガイド枠色
    var boardMultiStepHighlight: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Self.lightBoardMultiStepHighlight, dark: Self.darkBoardMultiStepHighlight)
        case .starChartSurveyTower:
            return schemeColor(light: Self.starLightSurveyCyan, dark: Self.starDarkSurveyCyan)
        }
    }

    /// ワープ床遷移のガイド枠色
    var boardWarpHighlight: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Self.lightBoardWarpHighlight, dark: Self.darkBoardWarpHighlight)
        case .starChartSurveyTower:
            return schemeColor(light: Self.starLightWarpViolet, dark: Self.starDarkWarpViolet)
        }
    }

    /// ワープ効果を描画する際のアクセントカラー
    var boardTileEffectWarp: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Self.lightBoardTileEffectWarp, dark: Self.darkBoardTileEffectWarp)
        case .starChartSurveyTower:
            return schemeColor(light: Self.starLightWarpViolet, dark: Self.starDarkWarpViolet)
        }
    }

    /// 手札シャッフル効果を描画する際のニュートラルカラー
    var boardTileEffectShuffle: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Self.lightBoardTileEffectShuffle, dark: Self.darkBoardTileEffectShuffle)
        case .starChartSurveyTower:
            return schemeColor(light: Color(red: 0.42, green: 0.48, blue: 0.54), dark: Color(red: 0.42, green: 0.50, blue: 0.56))
        }
    }

    /// 吹き飛ばし効果を描画する際のアクセントカラー
    var boardTileEffectBlast: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Self.lightBoardTileEffectBlast, dark: Self.darkBoardTileEffectBlast)
        case .starChartSurveyTower:
            return schemeColor(light: Self.starLightSurveyCyan, dark: Self.starDarkSurveyCyan)
        }
    }

    /// 麻痺罠を描画する際のアクセントカラー
    var boardTileEffectSlow: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Self.lightBoardTileEffectSlow, dark: Self.darkBoardTileEffectSlow)
        case .starChartSurveyTower:
            return schemeColor(light: Self.starLightWarpViolet, dark: Self.starDarkWarpViolet)
        }
    }

    /// 沼マスを描画する際のアクセントカラー
    var boardTileEffectSwamp: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Self.lightBoardTileEffectSwamp, dark: Self.darkBoardTileEffectSwamp)
        case .starChartSurveyTower:
            return schemeColor(light: Self.starLightHealingTeal, dark: Self.starDarkHealingTeal)
        }
    }

    /// カード温存効果を描画する際のアクセントカラー
    var boardTileEffectPreserveCard: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Self.lightBoardTileEffectPreserveCard, dark: Self.darkBoardTileEffectPreserveCard)
        case .starChartSurveyTower:
            return schemeColor(light: Self.starLightOldGold, dark: Self.starDarkOldGold)
        }
    }

    /// 手札喪失罠を描画する際のアクセントカラー
    var boardTileEffectDiscardHand: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(light: Self.lightBoardTileEffectDiscardHand, dark: Self.darkBoardTileEffectDiscardHand)
        case .starChartSurveyTower:
            return schemeColor(light: Self.starLightDangerRed, dark: Self.starDarkDangerRed)
        }
    }

    var boardDungeonEnemy: Color {
        switch visualStyle {
        case .classic:
            return Color(red: 0.86, green: 0.18, blue: 0.16)
        case .starChartSurveyTower:
            return schemeColor(light: Self.starLightDangerRed, dark: Self.starDarkDangerRed)
        }
    }

    var boardDungeonDanger: Color {
        switch visualStyle {
        case .classic:
            return Color(red: 0.90, green: 0.16, blue: 0.12)
        case .starChartSurveyTower:
            return schemeColor(light: Self.starLightDangerRed, dark: Self.starDarkDangerRed)
        }
    }

    var boardDungeonWarning: Color {
        switch visualStyle {
        case .classic:
            return Color(red: 1.0, green: 0.34, blue: 0.10)
        case .starChartSurveyTower:
            return schemeColor(light: Color(red: 1.0, green: 0.34, blue: 0.10), dark: Color(red: 1.0, green: 0.34, blue: 0.10))
        }
    }

    var boardDungeonCardPickup: Color {
        switch visualStyle {
        case .classic:
            return Color(red: 0.08, green: 0.58, blue: 0.50)
        case .starChartSurveyTower:
            return schemeColor(light: Self.starLightHealingTeal, dark: Self.starDarkHealingTeal)
        }
    }

    var boardDungeonRelicPickup: Color {
        switch visualStyle {
        case .classic:
            return Color(red: 0.96, green: 0.68, blue: 0.16)
        case .starChartSurveyTower:
            return schemeColor(light: Self.starLightOldGold, dark: Self.starDarkOldGold)
        }
    }

    var boardDungeonSuspiciousRelicPickup: Color {
        switch visualStyle {
        case .classic:
            return Color(red: 0.82, green: 0.12, blue: 0.12)
        case .starChartSurveyTower:
            return schemeColor(light: Self.starLightDangerRed, dark: Self.starDarkDangerRed)
        }
    }

    var boardDungeonDamageTrap: Color {
        switch visualStyle {
        case .classic:
            return Color(red: 0.76, green: 0.08, blue: 0.06)
        case .starChartSurveyTower:
            return schemeColor(light: Self.starLightDangerRed, dark: Self.starDarkDangerRed)
        }
    }

    var boardDungeonHpHalvingTrap: Color {
        switch visualStyle {
        case .classic:
            return Color(red: 0.55, green: 0.12, blue: 0.68)
        case .starChartSurveyTower:
            return schemeColor(light: Self.starLightWarpViolet, dark: Self.starDarkWarpViolet)
        }
    }

    var boardDungeonLavaTile: Color {
        switch visualStyle {
        case .classic:
            return Color(red: 0.94, green: 0.24, blue: 0.02)
        case .starChartSurveyTower:
            return schemeColor(light: Color(red: 1.0, green: 0.32, blue: 0.04), dark: Color(red: 1.0, green: 0.32, blue: 0.04))
        }
    }

    var boardDungeonHealingTile: Color {
        switch visualStyle {
        case .classic:
            return Color(red: 0.10, green: 0.62, blue: 0.34)
        case .starChartSurveyTower:
            return schemeColor(light: Self.starLightHealingTeal, dark: Self.starDarkHealingTeal)
        }
    }

    var boardDungeonKey: Color {
        switch visualStyle {
        case .classic:
            return Color(red: 0.96, green: 0.73, blue: 0.18)
        case .starChartSurveyTower:
            return schemeColor(light: Self.starLightOldGold, dark: Self.starDarkOldGold)
        }
    }
}

private extension AppTheme {
    static let lightBoardGuideHighlight = Color(red: 0.94, green: 0.41, blue: 0.08).opacity(0.85)
    static let darkBoardGuideHighlight = Color(red: 1.0, green: 0.74, blue: 0.38).opacity(0.9)
    static let lightBoardMultiStepHighlight = Color(red: 0.0, green: 0.68, blue: 0.86).opacity(0.88)
    static let darkBoardMultiStepHighlight = Color(red: 0.35, green: 0.85, blue: 0.95).opacity(0.92)
    static let lightBoardWarpHighlight = Color(red: 0.56, green: 0.42, blue: 0.86).opacity(0.9)
    static let darkBoardWarpHighlight = Color(red: 0.70, green: 0.55, blue: 0.93).opacity(0.92)
    static let lightBoardTileEffectWarp = Color(red: 0.36, green: 0.56, blue: 0.98).opacity(0.95)
    static let darkBoardTileEffectWarp = Color(red: 0.56, green: 0.75, blue: 1.0).opacity(0.95)
    static let lightBoardTileEffectShuffle = Color(red: 0.3, green: 0.3, blue: 0.3).opacity(0.92)
    static let darkBoardTileEffectShuffle = Color.white.opacity(0.9)
    static let lightBoardTileEffectBlast = Color(red: 0.0, green: 0.68, blue: 0.86).opacity(0.95)
    static let darkBoardTileEffectBlast = Color(red: 0.35, green: 0.85, blue: 0.95).opacity(0.95)
    static let lightBoardTileEffectSlow = Color(red: 0.62, green: 0.20, blue: 0.78).opacity(0.95)
    static let darkBoardTileEffectSlow = Color(red: 0.94, green: 0.56, blue: 1.0).opacity(0.95)
    static let lightBoardTileEffectSwamp = Color(red: 0.04, green: 0.58, blue: 0.50).opacity(0.92)
    static let darkBoardTileEffectSwamp = Color(red: 0.30, green: 0.86, blue: 0.78).opacity(0.94)
    static let lightBoardTileEffectPreserveCard = Color(red: 0.90, green: 0.54, blue: 0.06).opacity(0.95)
    static let darkBoardTileEffectPreserveCard = Color(red: 1.0, green: 0.72, blue: 0.24).opacity(0.95)
    static let lightBoardTileEffectDiscardHand = Color(red: 0.72, green: 0.08, blue: 0.18).opacity(0.95)
    static let darkBoardTileEffectDiscardHand = Color(red: 1.0, green: 0.42, blue: 0.48).opacity(0.95)
    static let starLightOldGold = Color(red: 0.72, green: 0.90, blue: 0.10).opacity(0.96)
    static let starDarkOldGold = Color(red: 0.72, green: 0.90, blue: 0.10).opacity(0.96)
    static let starLightDangerRed = Color(red: 1.0, green: 0.08, blue: 0.42).opacity(0.96)
    static let starDarkDangerRed = Color(red: 1.0, green: 0.08, blue: 0.42).opacity(0.96)
    static let starLightHealingTeal = Color(red: 0.0, green: 0.76, blue: 0.54).opacity(0.95)
    static let starDarkHealingTeal = Color(red: 0.0, green: 0.76, blue: 0.54).opacity(0.95)
    static let starLightWarpViolet = Color(red: 0.52, green: 0.22, blue: 1.0).opacity(0.96)
    static let starDarkWarpViolet = Color(red: 0.52, green: 0.22, blue: 1.0).opacity(0.96)
    static let starLightSurveyCyan = Color(red: 0.0, green: 0.62, blue: 0.88).opacity(0.96)
    static let starDarkSurveyCyan = Color(red: 0.0, green: 0.62, blue: 0.88).opacity(0.96)
}
