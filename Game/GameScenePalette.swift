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
        boardGuideHighlight: SKColor
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
        // NOTE: SwiftUI 側の踏破済みカラー変更に合わせ、濃いグレー (18%) を踏破完了時の基準に統一する
        boardTileVisited: SKColor(white: 0.82, alpha: 1.0),
        boardTileUnvisited: SKColor(white: 0.95, alpha: 1.0),
        // NOTE: マルチ踏破のベースは未踏破と同じトーンを採用し、段階演出はオーバーレイで表現する
        boardTileMultiBase: SKColor(white: 0.95, alpha: 1.0),
        // NOTE: 枠線はアクセント用のチャコールグレーを採用し、背景や塗りに埋もれない視認性を優先する
        boardTileMultiStroke: SKColor(white: 0.2, alpha: 1.0),
        // NOTE: トグルマスは常に存在感を出したいので、未踏破・踏破の状態差に影響されない濃いめのグレーを採用する
        boardTileToggle: SKColor(white: 0.6, alpha: 1.0),
        // NOTE: 移動不可マスは障害物として即座に判別できるよう、ほぼ黒に近いトーンで塗りつぶす
        boardTileImpassable: SKColor(white: 0.05, alpha: 1.0),
        boardKnight: SKColor(white: 0.1, alpha: 1.0),
        // NOTE: SwiftUI のライトテーマと同じ彩度を抑えたオレンジを採用し、テーマ適用前でも一貫した強調色を維持する
        boardGuideHighlight: SKColor(red: 0.94, green: 0.41, blue: 0.08, alpha: 0.85)
    )

    /// ダークテーマ適用前後でのデバッグ確認用のフォールバック
    static let fallbackDark = GameScenePalette(
        boardBackground: SKColor(white: 0.05, alpha: 1.0),
        boardGridLine: SKColor(white: 0.75, alpha: 1.0),
        // NOTE: ダークテーマでも踏破済みは 28% の白に統一し、完了時の判別を確実にする
        boardTileVisited: SKColor(white: 0.28, alpha: 1.0),
        boardTileUnvisited: SKColor(white: 0.18, alpha: 1.0),
        // NOTE: マルチ踏破のベース色も未踏破トーンに合わせ、踏破オーバーレイとのメリハリを最大化する
        boardTileMultiBase: SKColor(white: 0.18, alpha: 1.0),
        // NOTE: ダークテーマでは淡いライトグレーを用い、背景が暗くても輪郭がぼやけないようハイコントラストを維持する
        boardTileMultiStroke: SKColor(white: 0.85, alpha: 1.0),
        // NOTE: トグルマスは暗色背景でも埋もれないよう、訪問状態に左右されない明度のグレーを採用
        boardTileToggle: SKColor(white: 0.65, alpha: 1.0),
        // NOTE: ダークテーマ側でも障害物が沈まないよう、背景よりわずかに明度を下げた黒系で塗りつぶす
        boardTileImpassable: SKColor(white: 0.02, alpha: 1.0),
        boardKnight: SKColor(white: 0.95, alpha: 1.0),
        // NOTE: ダークテーマに合わせて明度を上げたオレンジを用い、背景の暗さに負けない発光感を演出する
        boardGuideHighlight: SKColor(red: 1.0, green: 0.74, blue: 0.38, alpha: 0.9)
    )
}
#endif
