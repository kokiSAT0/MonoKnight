#if canImport(SpriteKit)
import SpriteKit

/// SpriteKit で盤面表示に利用するカラーパレット
/// - Note: SwiftUI とは別モジュールになるため、必要な `SKColor` 値のみを厳選して保持する
public struct GameScenePalette {
    /// 盤面の背景色
    public let boardBackground: SKColor
    /// グリッド線の色
    public let boardGridLine: SKColor
    /// 踏破済みタイルの塗り色
    public let boardTileVisited: SKColor
    /// 未踏破タイルの塗り色
    public let boardTileUnvisited: SKColor
    /// 複数回踏破マスの基準色
    /// - NOTE: 未踏破色とは別に持つことで、進捗に応じた補間でも濁りが生じないようにする
    public let boardTileMultiBase: SKColor
    /// 複数回踏破マス専用の枠線色
    /// - NOTE: 高コントラストな線色を個別に持たせ、ライト/ダーク双方で視認性を確保する
    public let boardTileMultiStroke: SKColor
    /// トグルマスの塗り色
    /// - NOTE: 踏破状態に関わらず専用色を固定し、盤面上でギミックマスを瞬時に識別できるようにする
    public let boardTileToggle: SKColor
    /// 移動不可マスの塗り色
    /// - NOTE: 障害物として直感的に認識できるよう、ほぼ黒に近いトーンを専用で保持する
    public let boardTileImpassable: SKColor
    /// 駒の塗り色
    public let boardKnight: SKColor
    /// ガイド枠の線色
    public let boardGuideHighlight: SKColor
    /// 複数マス移動カード専用のガイド線色
    public let boardMultiStepHighlight: SKColor
    /// ワープカード専用のガイド線色
    public let boardWarpHighlight: SKColor
    /// ワープ効果の基準アクセントカラー
    public let boardTileEffectWarp: SKColor
    /// ワープペアごとに使い分けるアクセントカラー配列
    /// - Note: 色覚多様性へ配慮するため、色と形の両面で識別できるよう SpriteKit 側で参照する
    public let warpPairAccentColors: [SKColor]
    /// 手札シャッフル効果のアクセントカラー
    public let boardTileEffectShuffle: SKColor

    /// 主要な色をまとめて指定できるイニシャライザ
    /// - Parameters:
    ///   - boardBackground: 盤面背景色
    ///   - boardGridLine: グリッド線色
    ///   - boardTileVisited: 踏破済みタイル色
    ///   - boardTileUnvisited: 未踏破タイル色
    ///   - boardTileMultiBase: 複数回踏破マスの基準色
    ///   - boardTileMultiStroke: 複数回踏破マス専用の枠線色
    ///   - boardTileToggle: トグルマスの塗り色
    ///   - boardTileImpassable: 移動不可マスの塗り色
    ///   - boardKnight: 駒の塗り色
    ///   - boardGuideHighlight: ガイド枠の線色
    ///   - boardMultiStepHighlight: 複数マス移動ガイドの線色
    public init(
        boardBackground: SKColor,
        boardGridLine: SKColor,
        boardTileVisited: SKColor,
        boardTileUnvisited: SKColor,
        boardTileMultiBase: SKColor,
        boardTileMultiStroke: SKColor,
        boardTileToggle: SKColor,
        boardTileImpassable: SKColor,
        boardKnight: SKColor,
        boardGuideHighlight: SKColor,
        boardMultiStepHighlight: SKColor,
        boardWarpHighlight: SKColor,
        boardTileEffectWarp: SKColor,
        boardTileEffectShuffle: SKColor,
        warpPairAccentColors: [SKColor]
    ) {
        self.boardBackground = boardBackground
        self.boardGridLine = boardGridLine
        self.boardTileVisited = boardTileVisited
        self.boardTileUnvisited = boardTileUnvisited
        self.boardTileMultiBase = boardTileMultiBase
        self.boardTileMultiStroke = boardTileMultiStroke
        self.boardTileToggle = boardTileToggle
        self.boardTileImpassable = boardTileImpassable
        self.boardKnight = boardKnight
        self.boardGuideHighlight = boardGuideHighlight
        self.boardMultiStepHighlight = boardMultiStepHighlight
        self.boardWarpHighlight = boardWarpHighlight
        self.boardTileEffectWarp = boardTileEffectWarp
        self.boardTileEffectShuffle = boardTileEffectShuffle
        self.warpPairAccentColors = warpPairAccentColors
    }
}

public extension GameScenePalette {
    /// SwiftUI 側でテーマが決まっていない時に使う共通フォールバック
    /// - Note: ライトテーマ向けの値を採用し、最低限の視認性を確保する
    static var fallback: GameScenePalette { fallbackLight }

    /// SpriteKit 側にテーマが適用されるまで使用するフォールバック（ライト寄りの仮色）
    static let fallbackLight = GameScenePalette(
        boardBackground: SKColor(white: 0.94, alpha: 1.0),
        boardGridLine: SKColor(white: 0.15, alpha: 1.0),
        // NOTE: SwiftUI のライトテーマと同じく黒成分 30% (≈70% ホワイト) へ合わせ、未踏破との差分 (約27.5%) を明示的に確保する
        boardTileVisited: SKColor(white: 0.70, alpha: 1.0),
        boardTileUnvisited: SKColor(white: 0.975, alpha: 1.0),
        // NOTE: マルチ踏破のベースも未踏破と同じ 97.5% ホワイトに揃え、進捗演出をオーバーレイ側へ集約する
        boardTileMultiBase: SKColor(white: 0.975, alpha: 1.0),
        // NOTE: 枠線はアクセント用のチャコールグレーを採用し、背景や塗りに埋もれない視認性を優先する
        boardTileMultiStroke: SKColor(white: 0.2, alpha: 1.0),
        // NOTE: トグルマスは常に存在感を出したいので、未踏破・踏破の状態差に影響されない濃いめのグレーを採用する
        boardTileToggle: SKColor(white: 0.6, alpha: 1.0),
        // NOTE: 移動不可マスは障害物として即座に判別できるよう、ほぼ黒に近いトーンで塗りつぶす
        boardTileImpassable: SKColor(white: 0.05, alpha: 1.0),
        boardKnight: SKColor(white: 0.1, alpha: 1.0),
        // NOTE: SwiftUI のライトテーマと同じ彩度を抑えたオレンジを採用し、テーマ適用前でも一貫した強調色を維持する
        boardGuideHighlight: SKColor(red: 0.94, green: 0.41, blue: 0.08, alpha: 0.85),
        // NOTE: 連続移動カードはカード枠と同じシアンを用い、盤面でも一目で識別できるようにする
        boardMultiStepHighlight: SKColor(red: 0.0, green: 0.68, blue: 0.86, alpha: 0.88),
        // NOTE: ワープカードのガイド枠はカード枠と統一した紫を採用し、カテゴリー差を明確にする
        boardWarpHighlight: SKColor(red: 0.56, green: 0.42, blue: 0.86, alpha: 0.9),
        // NOTE: ワープ効果は高コントラストなライトブルーを採用し、盤面上で瞬時に目に入るようにする
        boardTileEffectWarp: SKColor(red: 0.36, green: 0.56, blue: 0.98, alpha: 0.95),
        // NOTE: 手札シャッフルはモノトーン基調を維持しつつも差別化できるようニュートラルグレーを活用する
        boardTileEffectShuffle: SKColor(white: 0.3, alpha: 0.92),
        // NOTE: ワープペアの識別用に 6 色を用意し、同心円の層数と組み合わせて視認性を確保する
        warpPairAccentColors: [
            SKColor(red: 0.38, green: 0.68, blue: 1.0, alpha: 1.0),
            SKColor(red: 0.26, green: 0.82, blue: 0.78, alpha: 1.0),
            SKColor(red: 0.74, green: 0.54, blue: 0.96, alpha: 1.0),
            SKColor(red: 0.99, green: 0.68, blue: 0.46, alpha: 1.0),
            SKColor(red: 0.98, green: 0.60, blue: 0.80, alpha: 1.0),
            SKColor(red: 0.64, green: 0.88, blue: 0.68, alpha: 1.0),
        ]
    )

    /// ダークテーマ適用前後でのデバッグ確認用のフォールバック
    static let fallbackDark = GameScenePalette(
        boardBackground: SKColor(white: 0.05, alpha: 1.0),
        boardGridLine: SKColor(white: 0.75, alpha: 1.0),
        // NOTE: ダークテーマは白成分 38% を基準にし、未踏破との差分 (約33%) を確実に保って踏破完了のコントラストを向上させる
        boardTileVisited: SKColor(white: 0.38, alpha: 1.0),
        boardTileUnvisited: SKColor(white: 0.05, alpha: 1.0),
        // NOTE: マルチ踏破のベースも未踏破と同じ 5% ホワイトへ寄せ、進行オーバーレイによる変化を明確化する
        boardTileMultiBase: SKColor(white: 0.05, alpha: 1.0),
        // NOTE: ダークテーマでは淡いライトグレーを用い、背景が暗くても輪郭がぼやけないようハイコントラストを維持する
        boardTileMultiStroke: SKColor(white: 0.85, alpha: 1.0),
        // NOTE: トグルマスは暗色背景でも埋もれないよう、訪問状態に左右されない明度のグレーを採用
        boardTileToggle: SKColor(white: 0.65, alpha: 1.0),
        // NOTE: ダークテーマ側でも障害物が沈まないよう、背景よりわずかに明度を下げた黒系で塗りつぶす
        boardTileImpassable: SKColor(white: 0.02, alpha: 1.0),
        boardKnight: SKColor(white: 0.95, alpha: 1.0),
        // NOTE: ダークテーマに合わせて明度を上げたオレンジを用い、背景の暗さに負けない発光感を演出する
        boardGuideHighlight: SKColor(red: 1.0, green: 0.74, blue: 0.38, alpha: 0.9),
        // NOTE: 連続移動カードのシアンもダークテーマ向けに明度を調整し、背景との差を確保する
        boardMultiStepHighlight: SKColor(red: 0.35, green: 0.85, blue: 0.95, alpha: 0.92),
        // NOTE: ダークテーマのワープ枠も明度を上げた紫で描画し、暗所でも識別しやすくする
        boardWarpHighlight: SKColor(red: 0.70, green: 0.55, blue: 0.93, alpha: 0.92),
        // NOTE: ダークテーマのワープも明度を高めた青系で描画し、夜間でも視認できる発光感を持たせる
        boardTileEffectWarp: SKColor(red: 0.56, green: 0.75, blue: 1.0, alpha: 0.95),
        // NOTE: シャッフルはライトテーマよりも明度を上げ、背景とのコントラストを十分に確保する
        boardTileEffectShuffle: SKColor(white: 0.7, alpha: 0.9),
        // NOTE: ダークテーマ用にも発光感を残した 6 色を揃え、背景が暗くても埋もれないようにする
        warpPairAccentColors: [
            SKColor(red: 0.56, green: 0.78, blue: 1.0, alpha: 1.0),
            SKColor(red: 0.36, green: 0.88, blue: 0.82, alpha: 1.0),
            SKColor(red: 0.83, green: 0.66, blue: 1.0, alpha: 1.0),
            SKColor(red: 1.0, green: 0.80, blue: 0.54, alpha: 1.0),
            SKColor(red: 1.0, green: 0.70, blue: 0.88, alpha: 1.0),
            SKColor(red: 0.72, green: 0.94, blue: 0.78, alpha: 1.0),
        ]
    )
}
#endif
