import Foundation

/// 座標を表す構造体
/// - 備考: 原点は左下、x は右方向、y は上方向に増加する
public struct GridPoint: Hashable, Codable {
    /// x 座標
    public let x: Int
    /// y 座標
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

    /// 座標を移動させた新しい座標を返す
    /// - Parameters:
    ///   - dx: x 方向の移動量
    ///   - dy: y 方向の移動量
    /// - Returns: 移動後の座標
    public func offset(dx: Int, dy: Int) -> GridPoint {
        GridPoint(x: x + dx, y: y + dy)
    }

    /// 指定した盤面サイズ内に収まっているかを判定する
    /// - Parameter boardSize: 盤面の一辺の長さ
    /// - Returns: 盤面内であれば true
    public func isInside(boardSize: Int) -> Bool {
        let range = 0..<boardSize
        return range.contains(x) && range.contains(y)
    }

    /// 指定された盤面サイズの中央座標を計算する
    /// - Parameter boardSize: 盤面の一辺の長さ
    /// - Returns: 中央付近の座標（偶数サイズの場合は下寄りの中央を返す）
    public static func center(of boardSize: Int) -> GridPoint {
        let index = boardSize / 2
        return GridPoint(x: index, y: index)
    }
}

/// 1 マスの状態
/// - untouched: 未踏破
/// - visited: 踏破済み
public enum TileState {
    case untouched
    case visited
}

/// 任意サイズの盤面を管理する構造体
/// SwiftUI の `onChange` で盤面の変化を検知できるよう Equatable に準拠
public struct Board: Equatable {
    /// 盤面のサイズ（NxN）
    public let size: Int

    /// 各マスの状態を保持する二次元配列
    /// y インデックスが先、x インデックスが後となる
    private var tiles: [[TileState]]

    /// 初期化。全マス未踏破として生成し、必要に応じて初期踏破マスを指定する
    /// - Parameters:
    ///   - size: 盤面の一辺の長さ
    ///   - initialVisitedPoints: 初期状態で踏破済みにしたいマスの集合
    public init(size: Int, initialVisitedPoints: [GridPoint] = []) {
        self.size = size
        let row = Array(repeating: TileState.untouched, count: size)
        self.tiles = Array(repeating: row, count: size)
        // 初期踏破マスを順番に処理し、盤面外の指定は安全に無視する
        for point in initialVisitedPoints where contains(point) {
            tiles[point.y][point.x] = .visited
        }
    }

    /// 指定座標が盤面内かどうかを判定する
    /// - Parameter point: 判定したい座標
    /// - Returns: 盤面内であれば true
    public func contains(_ point: GridPoint) -> Bool {
        point.isInside(boardSize: size)
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

public enum GameProgress {
    /// スポーン位置選択待ち
    case awaitingSpawn
    /// プレイ続行中
    case playing
    /// 全マス踏破でクリア
    case cleared
    /// 手詰まりなどで一時停止（ペナルティ対象）
    case deadlock
}

// MARK: - UI 連動用の要求モデル

/// 盤面タップでカード再生アニメーションを要求するときに利用する構造体
/// - Note: SwiftUI 側でアニメーションを実行 → 完了後に `GameCore.clearBoardTapPlayRequest` を呼ぶ想定
public struct BoardTapPlayRequest: Identifiable, Equatable {
    /// 各リクエストを一意に識別するための ID
    public let id: UUID
    /// 盤面タップ時に対応する手札スタックの識別子
    public let stackID: UUID
    /// `GameCore.playCard(at:)` に渡すインデックス
    public let stackIndex: Int
    /// アニメーション用に参照するスタック先頭のカード
    public let topCard: DealtCard

    /// 公開イニシャライザ
    /// - Parameters:
    ///   - id: 外部で識別子を指定したい場合に利用（省略時は自動生成）
    ///   - stackID: 対象スタックの識別子
    ///   - stackIndex: 手札スロット内での位置
    ///   - topCard: 要求時点での先頭カード
    public init(id: UUID = UUID(), stackID: UUID, stackIndex: Int, topCard: DealtCard) {
        self.id = id
        self.stackID = stackID
        self.stackIndex = stackIndex
        self.topCard = topCard
    }

    /// Equatable 実装
    /// - Note: 同じリクエストかどうかを識別子でのみ比較し、カード差し替え時も継続扱いにする
    public static func == (lhs: BoardTapPlayRequest, rhs: BoardTapPlayRequest) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - デバッグ支援
extension GridPoint: CustomStringConvertible {
    /// デバッグ出力時に座標を分かりやすく表示する
    /// - Returns: "(x, y)" 形式の文字列
    public var description: String { "(\(x),\(y))" }
}

#if DEBUG
// デバッグ専用のユーティリティを Release ビルドに含めないよう制限する
extension Board {
    /// 現在の盤面状態をコンソールに可視化する
    /// - Parameter current: 駒の現在位置（省略時は表示しない）
    func debugDump(current: GridPoint? = nil) {
        // y 軸を上から下へ走査し、行単位で文字列を構築する
        for y in stride(from: size - 1, through: 0, by: -1) {
            var row = ""
            for x in 0..<size {
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

