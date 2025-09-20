import Foundation

/// 座標を表す構造体
/// - 備考: 原点は左下、x は右方向、y は上方向に増加する
public struct GridPoint: Hashable {
    /// x 座標 (0...4)
    public let x: Int
    /// y 座標 (0...4)
    public let y: Int

    /// 指定座標を生成するための公開イニシャライザ
    /// - Parameters:
    ///   - x: x 座標
    ///   - y: y 座標
    /// - Note: 外部モジュールからも `GridPoint` を構築できるよう `public` を付与する
    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    /// 盤面の範囲を表す定数
    public static let range = 0...4
    /// 盤面の中央位置 `(2,2)`
    public static let center = GridPoint(x: 2, y: 2)

    /// 座標を移動させた新しい座標を返す
    /// - Parameters:
    ///   - dx: x 方向の移動量
    ///   - dy: y 方向の移動量
    /// - Returns: 移動後の座標
    public func offset(dx: Int, dy: Int) -> GridPoint {
        GridPoint(x: x + dx, y: y + dy)
    }

    /// 盤面内に収まっているかを判定する
    public var isInside: Bool {
        GridPoint.range.contains(x) && GridPoint.range.contains(y)
    }
}

/// 1 マスの状態
/// - untouched: 未踏破
/// - visited: 踏破済み
public enum TileState {
    case untouched
    case visited
}

/// 5×5 の盤面を管理する構造体
/// SwiftUI の `onChange` で盤面の変化を検知できるよう Equatable に準拠
public struct Board: Equatable {
    /// 盤面のサイズ (5×5 固定)
    public static let size = 5

    /// 各マスの状態を保持する二次元配列
    /// y インデックスが先、x インデックスが後となる
    private var tiles: [[TileState]]

    /// 初期化。全マス未踏破として生成し、中央を踏破済みに設定する
    public init() {
        let row = Array(repeating: TileState.untouched, count: Board.size)
        self.tiles = Array(repeating: row, count: Board.size)
        markVisited(GridPoint.center)
    }

    /// 指定座標が盤面内かどうかを判定する
    /// - Parameter point: 判定したい座標
    /// - Returns: 盤面内であれば true
    public func contains(_ point: GridPoint) -> Bool {
        point.isInside
    }

    /// 指定座標の踏破状態を返す
    /// - Parameter point: 調べたい座標
    /// - Returns: 盤面内であれば状態を返し、盤外なら nil
    public func state(at point: GridPoint) -> TileState? {
        guard contains(point) else { return nil }
        return tiles[point.y][point.x]
    }

    /// 指定座標が踏破済みかどうかを返す
    /// - Parameter point: 調べたい座標
    /// - Returns: 踏破済みであれば true
    public func isVisited(_ point: GridPoint) -> Bool {
        state(at: point) == .visited
    }

    /// 指定座標を踏破済みに更新する
    /// - Parameter point: 更新したい座標
    public mutating func markVisited(_ point: GridPoint) {
        guard contains(point) else { return }
        tiles[point.y][point.x] = .visited
    }

    /// 未踏破マスの残数を計算して返す
    /// - Returns: まだ踏破していないマスの数
    public var remainingCount: Int {
        var count = 0
        for row in tiles {
            for tile in row where tile != .visited {
                count += 1
            }
        }
        return count
    }

    /// 全マスを踏破済みにしたかどうかを返す
    public var isCleared: Bool {
        for row in tiles {
            for tile in row {
                if tile != .visited { return false }
            }
        }
        return true
    }
}

/// ゲーム全体の進行状態
/// - SwiftUI 側の状態監視でも利用するため公開する
public enum GameProgress {
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
    public var description: String { "(\(x),\(y))" }
}

#if DEBUG
extension Board {
    /// 現在の盤面状態をコンソールに可視化する
    /// - Parameter current: 駒の現在位置（省略時は表示しない）
    func debugDump(current: GridPoint? = nil) {
        // y 軸を上から下へ走査し、行単位で文字列を構築する
        for y in stride(from: Board.size - 1, through: 0, by: -1) {
            var row = ""
            for x in 0..<Board.size {
                let point = GridPoint(x: x, y: y)
                if let current = current, current == point {
                    // 駒の位置は K で表現
                    row += "K "
                } else {
                    // 踏破済みマスは x、未踏破は . を使用
                    row += tiles[y][x] == .visited ? "x " : ". "
                }
            }
            // 末尾の空白を削除してからデバッグログに出力
            debugLog(row.trimmingCharacters(in: .whitespaces))
        }
    }
}
#endif

