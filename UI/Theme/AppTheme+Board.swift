import SwiftUI

extension AppTheme {
    /// SpriteKit で描画する盤面の背景色
    var boardBackground: Color { backgroundPrimary }

    /// グリッド線の色（ライト/ダークでコントラストを調整）
    var boardGridLine: Color { schemeColor(light: Color.black.opacity(0.65), dark: Color.white.opacity(0.75)) }

    /// 踏破済みマスの塗り色
    var boardTileVisited: Color { schemeColor(light: Color.black.opacity(0.30), dark: Color.white.opacity(0.38)) }

    /// 未踏破マスの塗り色
    var boardTileUnvisited: Color { schemeColor(light: Color.black.opacity(0.025), dark: Color.white.opacity(0.05)) }

    /// 複数回踏破マスの基準色
    var boardTileMultiBase: Color { boardTileUnvisited }

    /// 複数回踏破マス専用の枠線色
    var boardTileMultiStroke: Color { schemeColor(light: Color.black.opacity(0.78), dark: Color.white.opacity(0.82)) }

    /// トグルマスの塗り色
    var boardTileToggle: Color { schemeColor(light: Color.black.opacity(0.32), dark: Color.white.opacity(0.5)) }

    /// 移動不可マスの塗り色
    var boardTileImpassable: Color { schemeColor(light: Color.black, dark: Color.black.opacity(0.92)) }

    /// 駒本体の塗り色
    var boardKnight: Color { schemeColor(light: Color.black, dark: Color.white) }

    /// ガイドモードで候補マスを照らす際の基準色
    var boardGuideHighlight: Color { schemeColor(light: Self.lightBoardGuideHighlight, dark: Self.darkBoardGuideHighlight) }

    /// 複数マス移動カード専用のガイド枠色
    var boardMultiStepHighlight: Color { schemeColor(light: Self.lightBoardMultiStepHighlight, dark: Self.darkBoardMultiStepHighlight) }

    /// ワープカード専用のガイド枠色
    var boardWarpHighlight: Color { schemeColor(light: Self.lightBoardWarpHighlight, dark: Self.darkBoardWarpHighlight) }

    /// ワープ効果を描画する際のアクセントカラー
    var boardTileEffectWarp: Color { schemeColor(light: Self.lightBoardTileEffectWarp, dark: Self.darkBoardTileEffectWarp) }

    /// 手札シャッフル効果を描画する際のニュートラルカラー
    var boardTileEffectShuffle: Color { schemeColor(light: Self.lightBoardTileEffectShuffle, dark: Self.darkBoardTileEffectShuffle) }

    /// 加速効果を描画する際のアクセントカラー
    var boardTileEffectBoost: Color { schemeColor(light: Self.lightBoardTileEffectBoost, dark: Self.darkBoardTileEffectBoost) }

    /// 減速効果を描画する際のアクセントカラー
    var boardTileEffectSlow: Color { schemeColor(light: Self.lightBoardTileEffectSlow, dark: Self.darkBoardTileEffectSlow) }

    /// NEXT 更新効果を描画する際のアクセントカラー
    var boardTileEffectNextRefresh: Color { schemeColor(light: Self.lightBoardTileEffectNextRefresh, dark: Self.darkBoardTileEffectNextRefresh) }

    /// 無料フォーカス効果を描画する際のアクセントカラー
    var boardTileEffectFreeFocus: Color { schemeColor(light: Self.lightBoardTileEffectFreeFocus, dark: Self.darkBoardTileEffectFreeFocus) }

    /// カード温存効果を描画する際のアクセントカラー
    var boardTileEffectPreserveCard: Color { schemeColor(light: Self.lightBoardTileEffectPreserveCard, dark: Self.darkBoardTileEffectPreserveCard) }
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
    static let lightBoardTileEffectBoost = Color(red: 0.0, green: 0.68, blue: 0.86).opacity(0.95)
    static let darkBoardTileEffectBoost = Color(red: 0.35, green: 0.85, blue: 0.95).opacity(0.95)
    static let lightBoardTileEffectSlow = Color(red: 0.82, green: 0.22, blue: 0.26).opacity(0.95)
    static let darkBoardTileEffectSlow = Color(red: 1.0, green: 0.46, blue: 0.50).opacity(0.95)
    static let lightBoardTileEffectNextRefresh = Color(red: 0.13, green: 0.62, blue: 0.36).opacity(0.95)
    static let darkBoardTileEffectNextRefresh = Color(red: 0.35, green: 0.86, blue: 0.56).opacity(0.95)
    static let lightBoardTileEffectFreeFocus = Color(red: 0.62, green: 0.38, blue: 0.88).opacity(0.95)
    static let darkBoardTileEffectFreeFocus = Color(red: 0.78, green: 0.62, blue: 1.0).opacity(0.95)
    static let lightBoardTileEffectPreserveCard = Color(red: 0.90, green: 0.54, blue: 0.06).opacity(0.95)
    static let darkBoardTileEffectPreserveCard = Color(red: 1.0, green: 0.72, blue: 0.24).opacity(0.95)
}
