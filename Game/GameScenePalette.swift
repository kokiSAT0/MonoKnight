#if canImport(SpriteKit)
import SpriteKit

/// SpriteKit で盤面表示に利用するカラーパレット
/// - Note: SwiftUI とは別モジュールになるため、必要な `SKColor` 値のみを厳選して保持する
struct GameScenePalette {
    /// 盤面の背景色
    let boardBackground: SKColor
    /// グリッド線の色
    let boardGridLine: SKColor
    /// 踏破済みタイルの塗り色
    let boardTileVisited: SKColor
    /// 未踏破タイルの塗り色
    let boardTileUnvisited: SKColor
    /// 駒の塗り色
    let boardKnight: SKColor
    /// ガイド枠の線色
    let boardGuideHighlight: SKColor

    /// 主要な色をまとめて指定できるイニシャライザ
    /// - Parameters:
    ///   - boardBackground: 盤面背景色
    ///   - boardGridLine: グリッド線色
    ///   - boardTileVisited: 踏破済みタイル色
    ///   - boardTileUnvisited: 未踏破タイル色
    ///   - boardKnight: 駒の塗り色
    ///   - boardGuideHighlight: ガイド枠の線色
    init(
        boardBackground: SKColor,
        boardGridLine: SKColor,
        boardTileVisited: SKColor,
        boardTileUnvisited: SKColor,
        boardKnight: SKColor,
        boardGuideHighlight: SKColor
    ) {
        self.boardBackground = boardBackground
        self.boardGridLine = boardGridLine
        self.boardTileVisited = boardTileVisited
        self.boardTileUnvisited = boardTileUnvisited
        self.boardKnight = boardKnight
        self.boardGuideHighlight = boardGuideHighlight
    }
}

extension GameScenePalette {
    /// SpriteKit 側にテーマが適用されるまで使用するフォールバック（ライト寄りの仮色）
    static let fallbackLight = GameScenePalette(
        boardBackground: SKColor(white: 0.94, alpha: 1.0),
        boardGridLine: SKColor(white: 0.15, alpha: 1.0),
        boardTileVisited: SKColor(white: 0.75, alpha: 1.0),
        boardTileUnvisited: SKColor(white: 0.98, alpha: 1.0),
        boardKnight: SKColor(white: 0.1, alpha: 1.0),
        boardGuideHighlight: SKColor(white: 0.4, alpha: 0.6)
    )

    /// ダークテーマ適用前後でのデバッグ確認用のフォールバック
    static let fallbackDark = GameScenePalette(
        boardBackground: SKColor(white: 0.05, alpha: 1.0),
        boardGridLine: SKColor(white: 0.75, alpha: 1.0),
        boardTileVisited: SKColor(white: 0.35, alpha: 1.0),
        boardTileUnvisited: SKColor(white: 0.12, alpha: 1.0),
        boardKnight: SKColor(white: 0.95, alpha: 1.0),
        boardGuideHighlight: SKColor(white: 0.85, alpha: 0.55)
    )
}
#endif
