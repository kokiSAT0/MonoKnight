import Foundation
import SharedSupport // ログユーティリティを利用するため追加

/// カードが持つ移動量を一括管理するためのベクトル構造体
/// - Note: `dx` / `dy` の組み合わせを 1 単位として扱い、今後の複数候補カードでも再利用しやすいよう共通モデル層へ配置する
public struct MoveVector: Hashable, Codable {
    /// x 方向への移動量
    public let dx: Int
    /// y 方向への移動量
    public let dy: Int

    /// 指定移動量で構造体を生成するためのイニシャライザ
    /// - Parameters:
    ///   - dx: x 方向に加算する値
    ///   - dy: y 方向に加算する値
    public init(dx: Int, dy: Int) {
        self.dx = dx
        self.dy = dy
    }
}

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

/// 1 マスごとの踏破状態と必要踏破回数を保持する構造体
/// - Note: 複数回踏む必要があるマスにも対応できるよう、必要回数と残り回数の両方を追跡する
public struct TileState: Equatable {
    /// クリアに必要な踏破回数（1 回以上）
    public let requiredVisitCount: Int
    /// 残り踏破回数
    private(set) var remainingVisitCount: Int

    /// 公開イニシャライザ
    /// - Parameters:
    ///   - requiredVisitCount: 必要踏破回数（0 以下が渡された場合は 0 として扱う）
    ///   - remainingVisitCount: 初期残数。省略時は `requiredVisitCount` と同じ値を採用する。
    public init(requiredVisitCount: Int = 1, remainingVisitCount: Int? = nil) {
        // 不正値が渡されてもクラッシュしないように安全側へ丸め込む
        let normalizedRequired = max(requiredVisitCount, 0)
        let initialRemaining = remainingVisitCount ?? normalizedRequired
        self.requiredVisitCount = normalizedRequired
        // 残数は 0〜requiredVisitCount の範囲に収まるよう丸める
        if normalizedRequired == 0 {
            self.remainingVisitCount = 0
        } else {
            self.remainingVisitCount = min(max(initialRemaining, 0), normalizedRequired)
        }
    }

    /// マスが完全踏破済みかどうか
    public var isVisited: Bool { remainingVisitCount == 0 }

    /// 複数回踏破が必要かどうか
    public var requiresMultipleVisits: Bool { requiredVisitCount > 1 }

    /// これまでに達成済みの踏破割合（0.0〜1.0）
    public var completionProgress: Double {
        guard requiredVisitCount > 0 else { return 1.0 }
        let completed = requiredVisitCount - remainingVisitCount
        let clampedCompleted = max(0, min(requiredVisitCount, completed))
        return Double(clampedCompleted) / Double(requiredVisitCount)
    }

    /// 現在の残り踏破回数を返す
    public var remainingVisits: Int { remainingVisitCount }

    /// 踏破処理を 1 回分適用する
    /// - Note: 残数が 0 の場合は何もせずに安全に抜ける
    public mutating func markVisited() {
        guard remainingVisitCount > 0 else { return }
        remainingVisitCount -= 1
    }
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
    public init(
        size: Int,
        initialVisitedPoints: [GridPoint] = [],
        requiredVisitOverrides: [GridPoint: Int] = [:]
    ) {
        self.size = size
        let row = Array(repeating: TileState(), count: size)
        self.tiles = Array(repeating: row, count: size)
        // 特殊マスの踏破必要回数を上書きし、複数回踏むステージに対応する
        for (point, requirement) in requiredVisitOverrides {
            guard contains(point) else { continue }
            tiles[point.y][point.x] = TileState(requiredVisitCount: requirement)
        }
        // 初期踏破マスを順番に処理し、盤面外の指定は安全に無視する
        for point in initialVisitedPoints where contains(point) {
            tiles[point.y][point.x].markVisited()
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
        state(at: point)?.isVisited == true
    }

    /// 指定座標を踏破済みに更新する
    /// - Parameter point: 更新したい座標
    public mutating func markVisited(_ point: GridPoint) {
        guard contains(point) else { return }
        tiles[point.y][point.x].markVisited()
    }

    /// 未踏破マスの残数を計算して返す
    /// - Returns: まだ踏破していないマスの数
    public var remainingCount: Int {
        var count = 0
        for row in tiles {
            for tile in row where !tile.isVisited {
                count += 1
            }
        }
        return count
    }

    /// 全マスを踏破済みにしたかどうかを返す
    public var isCleared: Bool {
        for row in tiles {
            for tile in row {
                if !tile.isVisited { return false }
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
    /// `GameCore.playCard(using:)` に渡す候補のうち、スタック位置を識別するためのインデックス
    public let stackIndex: Int
    /// アニメーション用に参照するスタック先頭のカード
    public let topCard: DealtCard
    /// リクエスト生成時に確定した移動先座標
    public let destination: GridPoint
    /// リクエスト生成時に選択された移動ベクトル
    public let moveVector: MoveVector

    /// 公開イニシャライザ
    /// - Parameters:
    ///   - id: 外部で識別子を指定したい場合に利用（省略時は自動生成）
    ///   - stackID: 対象スタックの識別子
    ///   - stackIndex: 手札スロット内での位置
    ///   - topCard: 要求時点での先頭カード
    ///   - destination: 選択された移動先座標
    ///   - moveVector: 実際に適用する移動ベクトル
    public init(
        id: UUID = UUID(),
        stackID: UUID,
        stackIndex: Int,
        topCard: DealtCard,
        destination: GridPoint,
        moveVector: MoveVector
    ) {
        self.id = id
        self.stackID = stackID
        self.stackIndex = stackIndex
        self.topCard = topCard
        self.destination = destination
        self.moveVector = moveVector
    }

    /// ResolvedCardMove への変換を簡潔に行うための補助プロパティ
    /// - Important: UI 側ではこの値を利用して `GameCore.playCard(using:)` へそのまま引き渡すことで、複数候補カードでもユーザーの選択を忠実に再現する
    public var resolvedMove: ResolvedCardMove {
        ResolvedCardMove(
            stackID: stackID,
            stackIndex: stackIndex,
            card: topCard,
            moveVector: moveVector,
            destination: destination
        )
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
                    // 踏破状況に応じて文字を変える。複数回必要なマスは残数を数字で表示する。
                    let tile = tiles[y][x]
                    if tile.isVisited {
                        row += "x "
                    } else if tile.requiresMultipleVisits {
                        row += "\(tile.remainingVisits) "
                    } else {
                        row += ". "
                    }
                }
            }
            // 末尾の空白を削除してからデバッグログに出力
            debugLog(row.trimmingCharacters(in: .whitespaces))
        }
    }
}
#endif

