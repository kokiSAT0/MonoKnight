import CoreGraphics

/// 盤面レイアウトの実測値をまとめたスナップショット構造体
/// Equatable 準拠により差分検出が容易になり、診断ログの出力を最小限に抑えられる
struct BoardLayoutSnapshot: Equatable {
    /// 親ビューのサイズ
    let geometrySize: CGSize
    /// 盤面表示領域に割り当てられた高さ
    let availableHeight: CGFloat
    /// 横方向の基準となる盤面ベースサイズ
    let horizontalBoardBase: CGFloat
    /// 縦方向の基準となる盤面ベースサイズ
    let verticalBoardBase: CGFloat
    /// 最終的に採用された盤面ベースサイズ
    let boardBaseSize: CGFloat
    /// 実際に描画へ用いる盤面幅
    let boardWidth: CGFloat
    /// 生のトップセーフエリア値
    let rawTopInset: CGFloat
    /// 生のボトムセーフエリア値
    let rawBottomInset: CGFloat
    /// デフォルトのトップセーフエリア値
    let baseTopSafeAreaInset: CGFloat
    /// セーフエリアなどを反映した最終的なトップインセット
    let resolvedTopInset: CGFloat
    /// オーバーレイ考慮後のトップインセット
    let overlayAdjustedTopInset: CGFloat
    /// セーフエリアなどを反映した最終的なボトムインセット
    let resolvedBottomInset: CGFloat
    /// 統計表示エリアの高さ
    let statisticsHeight: CGFloat
    /// フォールバック適用後の統計表示エリアの高さ
    let resolvedStatisticsHeight: CGFloat
    /// 手札表示エリアの高さ
    let handSectionHeight: CGFloat
    /// フォールバック適用後の手札表示エリアの高さ
    let resolvedHandSectionHeight: CGFloat
    /// レギュラー幅向けの追加ボトム余白
    let regularAdditionalBottomPadding: CGFloat
    /// 手札エリア下部の余白
    let handSectionBottomPadding: CGFloat
    /// トップセーフエリアがフォールバックされたか
    let usedTopSafeAreaFallback: Bool
    /// ボトムセーフエリアがフォールバックされたか
    let usedBottomSafeAreaFallback: Bool
    /// 統計表示エリアがフォールバックされたか
    let usedStatisticsFallback: Bool
    /// 手札表示エリアがフォールバックされたか
    let usedHandSectionFallback: Bool
    /// コントロール行のトップ余白
    let controlRowTopPadding: CGFloat
    /// 盤面上部のオーバーレイ高さ
    let topOverlayHeight: CGFloat
}
