import Foundation

/// 座標を表す構造体
/// - 備考: 原点は左下、x は右方向、y は上方向に増加する
struct GridPoint: Hashable {
    /// x 座標 (0...4)
    let x: Int
    /// y 座標 (0...4)
    let y: Int

    /// 盤面の範囲を表す定数
    static let range = 0...4
    /// 盤面の中央位置 `(2,2)`
    static let center = GridPoint(x: 2, y: 2)

    /// 座標を移動させた新しい座標を返す
    /// - Parameters:
    ///   - dx: x 方向の移動量
    ///   - dy: y 方向の移動量
    /// - Returns: 移動後の座標
    func offset(dx: Int, dy: Int) -> GridPoint {
        GridPoint(x: x + dx, y: y + dy)
    }

    /// 盤面内に収まっているかを判定する
    var isInside: Bool {
        GridPoint.range.contains(x) && GridPoint.range.contains(y)
    }
}

/// 1 マスの状態
/// - untouched: 未踏破
/// - visited: 踏破済み
enum TileState {
    case untouched
    case visited
}

/// 5×5 の盤面を管理する構造体
struct Board {
    /// 盤面のサイズ (5×5 固定)
    static let size = 5

    /// 各マスの状態を保持する二次元配列
    /// y インデックスが先、x インデックスが後となる
    private var tiles: [[TileState]]

    /// 初期化。全マス未踏破として生成し、中央を踏破済みに設定する
    init() {
        let row = Array(repeating: TileState.untouched, count: Board.size)
        self.tiles = Array(repeating: row, count: Board.size)
        markVisited(GridPoint.center)
    }

    /// 指定座標が盤面内かどうかを判定する
    /// - Parameter point: 判定したい座標
    /// - Returns: 盤面内であれば true
    func contains(_ point: GridPoint) -> Bool {
        point.isInside
    }

    /// 指定座標の踏破状態を返す
    /// - Parameter point: 調べたい座標
    /// - Returns: 盤面内であれば状態を返し、盤外なら nil
    func state(at point: GridPoint) -> TileState? {
        guard contains(point) else { return nil }
        return tiles[point.y][point.x]
    }

    /// 指定座標が踏破済みかどうかを返す
    /// - Parameter point: 調べたい座標
    /// - Returns: 踏破済みであれば true
    func isVisited(_ point: GridPoint) -> Bool {
        state(at: point) == .visited
    }

    /// 指定座標を踏破済みに更新する
    /// - Parameter point: 更新したい座標
    mutating func markVisited(_ point: GridPoint) {
        guard contains(point) else { return }
        tiles[point.y][point.x] = .visited
    }

    /// 未踏破マスの残数を計算して返す
    /// - Returns: まだ踏破していないマスの数
    var remainingCount: Int {
        var count = 0
        for row in tiles {
            for tile in row where tile != .visited {
                count += 1
            }
        }
        return count
    }

    /// 全マスを踏破済みにしたかどうかを返す
    var isCleared: Bool {
        for row in tiles {
            for tile in row {
                if tile != .visited { return false }
            }
        }
        return true
    }
}

/// ゲーム全体の進行状態
enum GameProgress {
    /// プレイ続行中
    case playing
    /// 全マス踏破でクリア
    case cleared
    /// 手詰まりなどで一時停止（ペナルティ対象）
    case deadlock
}

// MARK: - デバッグ支援
extension GridPoint: CustomStringConvertible {
    /// デバッグ出力時に座標を分かりやすく表示する
    /// - Returns: "(x, y)" 形式の文字列
    var description: String { "(\(x),\(y))" }
}

