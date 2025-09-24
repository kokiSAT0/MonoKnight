import Foundation

/// 盤面サイズや座標計算を一元管理するユーティリティ
/// - Note: 5×5 固定だった定数をここへ集約し、将来的に盤面拡張が入っても差分箇所を最小化することを狙う。
public enum BoardGeometry {
    /// 正式リリース版で採用している標準盤面の一辺サイズ
    /// - Important: 既存のルール説明やランキング ID もこのサイズを前提にしているため、変更時は関連ドキュメントの更新が必須になる。
    public static let standardSize: Int = 5

    /// 指定サイズの盤面におけるデフォルトスポーン地点（中央マス）を返す
    /// - Parameter size: 盤面の一辺サイズ
    /// - Returns: 盤面中央付近の座標。サイズが 0 以下の場合は (0,0) を返し、安全側に倒す。
    public static func defaultSpawnPoint(for size: Int) -> GridPoint {
        // サイズが正の場合は単純に中央マスを返す。0 以下のケースは想定外だが、テスト環境などで扱えるよう (0,0) をフォールバックとして返す。
        guard size > 0 else { return GridPoint(x: 0, y: 0) }
        return GridPoint.center(of: size)
    }

    /// 指定サイズの盤面における初期踏破マス集合を返す
    /// - Parameter size: 盤面の一辺サイズ
    /// - Returns: 通常は中央 1 マスのみを含む配列。サイズが 0 以下なら空配列を返す。
    public static func defaultInitialVisitedPoints(for size: Int) -> [GridPoint] {
        // 無効サイズの場合は踏破マスが存在しないため空配列を返し、呼び出し元が安全に扱えるようにする。
        guard size > 0 else { return [] }
        return [defaultSpawnPoint(for: size)]
    }

    /// 指定された盤面に含まれる全座標を列挙する
    /// - Parameter size: 盤面の一辺サイズ
    /// - Returns: (0,0) から (size-1,size-1) までを走査した配列。サイズ 0 以下なら空配列を返す。
    public static func allPoints(for size: Int) -> [GridPoint] {
        guard size > 0 else { return [] }
        var points: [GridPoint] = []
        points.reserveCapacity(size * size)
        for y in 0..<size {
            for x in 0..<size {
                // 二重ループで全座標を生成し、盤面全体のスキャンやテストで再利用しやすいようにする。
                points.append(GridPoint(x: x, y: y))
            }
        }
        return points
    }
}
