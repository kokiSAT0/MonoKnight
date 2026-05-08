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

/// 盤面タイルが持つ特殊効果を列挙するための型
/// - Important: 盤面と UI の双方で同じ効果種別を参照できるようモデル層で一元管理する
public enum TileEffect: Equatable, Codable {
    /// 対応するペア ID を共有するタイルへワープさせる
    /// - Parameters:
    ///   - pairID: ワープ経路を識別するための文字列（同一 ID のマス同士でリンクする）
    ///   - destination: 実際に移動させる座標（盤面サイズ外や障害物は `Board` 側で除外する）
    case warp(pairID: String, destination: GridPoint)
    /// 手札をランダムに並び替える効果
    case shuffleHand
    /// 指定方向へ障害物または盤端に当たる直前まで吹き飛ばす効果
    case blast(direction: MoveVector)
    /// このマスで残りの移動を止める効果
    case slow
    /// 使用したカードを消費せずに温存する効果
    case preserveCard
    /// 手札スロットをランダムに 1 つ失う効果
    case discardRandomHand
    /// 手札スロットをすべて失う効果
    case discardAllHands
}

/// 1 マスごとの踏破状態と必要踏破回数・挙動を保持する構造体
public struct TileState: Equatable {
    public enum VisitBehavior: Equatable {
        case single
        case impassable
    }

    public let visitBehavior: VisitBehavior
    private let traversable: Bool
    private(set) var remainingVisitCount: Int
    public private(set) var effect: TileEffect?

    public var requiredVisitCount: Int {
        switch visitBehavior {
        case .single: return 1
        case .impassable: return 0
        }
    }

    public init(
        visitBehavior: VisitBehavior = .single,
        remainingVisitCount: Int? = nil,
        isTraversable: Bool = true,
        effect: TileEffect? = nil
    ) {
        self.visitBehavior = visitBehavior
        self.traversable = isTraversable
        self.effect = effect
        guard isTraversable, visitBehavior != .impassable else {
            self.remainingVisitCount = 0
            return
        }
        let initial = remainingVisitCount ?? 1
        self.remainingVisitCount = min(max(initial, 0), 1)
    }

    public var isVisited: Bool {
        switch visitBehavior {
        case .impassable: return false
        case .single: return remainingVisitCount == 0
        }
    }

    public var isImpassable: Bool {
        if case .impassable = visitBehavior { return true }
        return false
    }

    public var isTraversable: Bool { traversable }

    public var completionProgress: Double {
        let required = requiredVisitCount
        guard required > 0 else { return 1.0 }
        let completed = required - remainingVisitCount
        let clampedCompleted = max(0, min(required, completed))
        return Double(clampedCompleted) / Double(required)
    }

    public var remainingVisits: Int { remainingVisitCount }

    public mutating func markVisited() {
        guard traversable, visitBehavior == .single, remainingVisitCount > 0 else { return }
        remainingVisitCount -= 1
    }

    public mutating func assignEffect(_ newEffect: TileEffect?) {
        effect = newEffect
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
    /// 効果付きタイルの辞書（盤面内のみ保持する）
    private var tileEffects: [GridPoint: TileEffect]

    /// 初期化。全マス未踏破として生成し、必要に応じて初期踏破マスを指定する
    /// - Parameters:
    ///   - size: 盤面の一辺の長さ
    ///   - initialVisitedPoints: 初期状態で踏破済みにしたいマスの集合
    ///   - impassablePoints: 完全に移動を禁止する障害物マス集合（他設定よりも優先して適用）

    public init(
        size: Int,
        initialVisitedPoints: [GridPoint] = [],
        impassablePoints: Set<GridPoint> = [],
        tileEffects: [GridPoint: TileEffect] = [:]
    ) {
        self.size = size
        let row = Array(repeating: TileState(), count: size)
        self.tiles = Array(repeating: row, count: size)
        var sanitizedEffects: [GridPoint: TileEffect] = [:]
        var warpGroups: [String: Set<GridPoint>] = [:]
        let validRange = 0..<size
        let isWithinBoard: (GridPoint) -> Bool = { point in
            validRange.contains(point.x) && validRange.contains(point.y)
        }
        // 最初に移動不可マスを反映し、以降の処理で上書きされないようにする
        for point in impassablePoints where isWithinBoard(point) {
            tiles[point.y][point.x] = TileState(visitBehavior: .single, remainingVisitCount: 0, isTraversable: false)
        }
        // 移動不可マスはギミック設定よりも優先して上書きし、障害物として確実に保持する
        for point in impassablePoints where isWithinBoard(point) {
            tiles[point.y][point.x] = TileState(visitBehavior: .impassable, isTraversable: false)
        }
        // タイル効果を事前に検証してから適用し、盤面外や障害物指定を安全に除外する
        for (point, effect) in tileEffects {
            guard isWithinBoard(point), !impassablePoints.contains(point) else { continue }
            switch effect {
            case .warp(let pairID, let destination):
                // 盤面外や障害物を参照するワープは破棄し、ログ負荷を避けつつ安全側に倒す
                guard isWithinBoard(destination), !impassablePoints.contains(destination) else { continue }
                sanitizedEffects[point] = effect
                warpGroups[pairID, default: []].insert(point)
            case .blast(let direction):
                let isOrthogonalOneStep = abs(direction.dx) + abs(direction.dy) == 1
                guard isOrthogonalOneStep else { continue }
                sanitizedEffects[point] = effect
            case .shuffleHand, .slow, .preserveCard, .discardRandomHand, .discardAllHands:
                sanitizedEffects[point] = effect
            }
        }

        // ワープは同一 pairID が複数存在する場合のみ有効化し、片側だけの登録ミスを検出する
        var validWarpPoints: Set<GridPoint> = []
        for (pairID, points) in warpGroups {
            let pointSet = points
            guard pointSet.count >= 2 else { continue }
            var isValidGroup = true
            for point in pointSet {
                guard case .warp(_, let destination) = sanitizedEffects[point], pointSet.contains(destination) else {
                    isValidGroup = false
                    break
                }
            }
            if isValidGroup {
                validWarpPoints.formUnion(pointSet)
            } else {
                // 片側だけが別座標を指す場合などはまとめて除外し、想定外のワープでプレイ体験を壊さない
                debugLog("Board.init: 無効なワープ定義を pairID=\(pairID) で検出しました")
            }
        }

        // 無効なワープを辞書から除外し、以降の描画や取得処理に流入させない
        var invalidWarpPoints: [GridPoint] = []
        for (point, effect) in sanitizedEffects {
            if case .warp = effect, !validWarpPoints.contains(point) {
                invalidWarpPoints.append(point)
            }
        }
        for point in invalidWarpPoints {
            sanitizedEffects.removeValue(forKey: point)
        }

        // 初期踏破マスを順番に処理し、盤面外の指定は安全に無視する
        for point in initialVisitedPoints where isWithinBoard(point) {
            tiles[point.y][point.x].markVisited()
        }
        // 効果の最終登録を行い、TileState にも同じ情報を保持させる
        for (point, effect) in sanitizedEffects {
            tiles[point.y][point.x].assignEffect(effect)
        }
        self.tileEffects = sanitizedEffects
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

    /// 指定座標に設定された特殊効果を返す
    /// - Parameter point: 調べたい座標
    /// - Returns: 効果が付与されていればその内容を返し、未設定なら nil
    public func effect(at point: GridPoint) -> TileEffect? {
        guard contains(point) else { return nil }
        return tileEffects[point]
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
        guard contains(point), tiles[point.y][point.x].isTraversable else { return }
        tiles[point.y][point.x].markVisited()
    }

    /// 指定座標を崩落床として通行不可へ変える
    /// - Parameter point: 崩落させたいマス
    /// - Returns: 実際に通行不可へ変わった場合は true
    @discardableResult
    public mutating func collapseFloor(at point: GridPoint) -> Bool {
        guard contains(point), tiles[point.y][point.x].isTraversable else { return false }
        tiles[point.y][point.x] = TileState(visitBehavior: .impassable, isTraversable: false)
        tileEffects.removeValue(forKey: point)
        return true
    }

    /// 指定座標が移動可能なマスかどうか
    /// - Parameter point: 判定したい座標
    /// - Returns: 盤面内に存在し、踏破可能であれば true
    public func isTraversable(_ point: GridPoint) -> Bool {
        guard let tile = state(at: point) else { return false }
        return tile.isTraversable
    }

    /// 移動可能な全マスを座標配列で返す
    public var allTraversablePoints: [GridPoint] {
        var points: [GridPoint] = []
        for y in 0..<size {
            for x in 0..<size {
                let point = GridPoint(x: x, y: y)
                if isTraversable(point) {
                    points.append(point)
                }
            }
        }
        return points
    }

    /// 現在踏破済みの全マスを座標配列で返す
    public var visitedPoints: [GridPoint] {
        var points: [GridPoint] = []
        for y in 0..<size {
            for x in 0..<size {
                let point = GridPoint(x: x, y: y)
                if isVisited(point) {
                    points.append(point)
                }
            }
        }
        return points
    }

    /// 指定座標が移動不可マスかどうか
    /// - Parameter point: 判定したい座標
    /// - Returns: 盤面内に存在し、障害物であれば true
    public func isImpassable(_ point: GridPoint) -> Bool {
        guard let tile = state(at: point) else { return false }
        return !tile.isTraversable
    }

    /// 未踏破マスの残数を計算して返す
    /// - Returns: まだ踏破していないマスの数
    public var remainingCount: Int {
        var count = 0
        for row in tiles {
            for tile in row where !tile.isVisited && !tile.isImpassable {
                count += 1
            }
        }
        return count
    }

}

/// ゲーム全体の進行状態

public enum GameProgress {
    /// スポーン位置選択待ち
    case awaitingSpawn
    /// プレイ続行中
    case playing
    /// フロアクリア
    case cleared
    /// HP 0 や手数切れなどで失敗
    case failed
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
    /// アニメーション再生に必要な経路情報
    public let resolution: MovementResolution
    /// 解決時点での代表移動ベクトル（UI 側の互換性維持用）
    public let moveVector: MoveVector
    /// 既存コード互換用に移動先座標を公開する計算プロパティ
    public var destination: GridPoint { resolution.finalPosition }
    /// 経路の生配列へアクセスしたい場合のショートカット
    public var path: [GridPoint] { resolution.path }

    /// 公開イニシャライザ
    /// - Parameters:
    ///   - id: 外部で識別子を指定したい場合に利用（省略時は自動生成）
    ///   - stackID: 対象スタックの識別子
    ///   - stackIndex: 手札スロット内での位置
    ///   - topCard: 要求時点での先頭カード
    ///   - path: 選択された移動経路
    public init(
        id: UUID = UUID(),
        stackID: UUID,
        stackIndex: Int,
        topCard: DealtCard,
        moveVector: MoveVector,
        resolution: MovementResolution
    ) {
        self.id = id
        self.stackID = stackID
        self.stackIndex = stackIndex
        self.topCard = topCard
        self.moveVector = moveVector
        self.resolution = resolution
    }

    /// ResolvedCardMove への変換を簡潔に行うための補助プロパティ
    /// - Important: UI 側ではこの値を利用して `GameCore.playCard(using:)` へそのまま引き渡すことで、複数候補カードでもユーザーの選択を忠実に再現する
    public var resolvedMove: ResolvedCardMove {
        ResolvedCardMove(
            stackID: stackID,
            stackIndex: stackIndex,
            card: topCard,
            moveVector: moveVector,
            resolution: resolution
        )
    }

    /// Equatable 実装
    /// - Note: 同じリクエストかどうかを識別子でのみ比較し、カード差し替え時も継続扱いにする
    public static func == (lhs: BoardTapPlayRequest, rhs: BoardTapPlayRequest) -> Bool {
        lhs.id == rhs.id
    }
}

/// 盤面タップでカードを使わない基本移動を要求するときに利用する構造体
public struct BoardTapBasicMoveRequest: Identifiable, Equatable {
    public let id: UUID
    public let move: BasicOrthogonalMove

    public init(id: UUID = UUID(), move: BasicOrthogonalMove) {
        self.id = id
        self.move = move
    }
}

/// 塔ダンジョンで使えるカードなしの上下左右 1 マス移動候補
public struct BasicOrthogonalMove: Equatable {
    public let moveVector: MoveVector
    public let resolution: MovementResolution

    public var destination: GridPoint { resolution.finalPosition }
    public var path: [GridPoint] { resolution.path }

    public init(moveVector: MoveVector, resolution: MovementResolution) {
        self.moveVector = moveVector
        self.resolution = resolution
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
                    // 踏破状況に応じて文字を変える。障害物は黒マス扱いで "■" を表示する。
                    let tile = tiles[y][x]
                    if !tile.isTraversable {
                        // 障害物マスは視認性を高めるため黒塗り風の記号を使う
                        row += "■ "
                    } else {
                        switch tile.visitBehavior {
                        case .single:
                            row += tile.isVisited ? "x " : ". "
                        case .impassable:
                            // ここへ到達するのは理論上想定外だが、安全のため障害物表記を維持する
                            row += "■ "
                        }
                    }
                }
            }
            // 末尾の空白を削除してからデバッグログに出力
            debugLog(row.trimmingCharacters(in: .whitespaces))
        }
    }
}
#endif
