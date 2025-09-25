import SharedSupport  // debugLog を利用して詳細な診断ログを出力するために読み込む
import SwiftUI

// MARK: - レイアウト診断ログの整形
@MainActor
extension GameView {
    /// 実測値のスナップショットを比較しつつログへ出力する共通処理
    /// - Parameters:
    ///   - snapshot: 記録したいレイアウト値一式
    ///   - reason: ログ出力の契機（onAppear / 値更新など）
    func logLayoutSnapshot(_ snapshot: BoardLayoutSnapshot, reason: String) {
        // 同じ値での重複出力を避け、必要なタイミングのみに絞ってログを残す
        if viewModel.lastLoggedLayoutSnapshot == snapshot { return }
        viewModel.lastLoggedLayoutSnapshot = snapshot

        // 盤面縮小ロジックのどこで値が想定外になっているか突き止められるよう、多段の詳細ログを整形して出力する
        let message = """
        GameView.layout 観測: 理由=\(reason)
          geometry=\(snapshot.geometrySize)
          safeArea(rawTop=\(snapshot.rawTopInset), baseTop=\(snapshot.baseTopSafeAreaInset), rawBottom=\(snapshot.rawBottomInset), resolvedTop=\(snapshot.resolvedTopInset), overlayAdjustedTop=\(snapshot.overlayAdjustedTopInset), resolvedBottom=\(snapshot.resolvedBottomInset), fallbackTop=\(snapshot.usedTopSafeAreaFallback), fallbackBottom=\(snapshot.usedBottomSafeAreaFallback), overlayTop=\(snapshot.topOverlayHeight))
          sections(statistics=\(snapshot.statisticsHeight), resolvedStatistics=\(snapshot.resolvedStatisticsHeight), hand=\(snapshot.handSectionHeight), resolvedHand=\(snapshot.resolvedHandSectionHeight))
          paddings(controlTop=\(snapshot.controlRowTopPadding), handBottom=\(snapshot.handSectionBottomPadding), regularExtra=\(snapshot.regularAdditionalBottomPadding))
          fallbacks(statistics=\(snapshot.usedStatisticsFallback), hand=\(snapshot.usedHandSectionFallback), topSafeArea=\(snapshot.usedTopSafeAreaFallback), bottomSafeArea=\(snapshot.usedBottomSafeAreaFallback))
          boardBases(horizontal=\(snapshot.horizontalBoardBase), vertical=\(snapshot.verticalBoardBase), resolved=\(snapshot.boardBaseSize)) availableHeight=\(snapshot.availableHeight) boardScale=\(GameViewLayoutMetrics.boardScale) boardWidth=\(snapshot.boardWidth)
        """

        debugLog(message)

        if snapshot.availableHeight <= 0 || snapshot.boardWidth <= 0 {
            // 盤面がゼロサイズになる条件を明確化するため、異常時は追加で警告ログを残す
            debugLog(
                "GameView.layout 警告: availableHeight=\(snapshot.availableHeight), horizontalBase=\(snapshot.horizontalBoardBase), verticalBase=\(snapshot.verticalBoardBase), boardBase=\(snapshot.boardBaseSize), boardWidth=\(snapshot.boardWidth)"
            )
        }
    }
}

// MARK: - BoardLayoutSnapshot 補助イニシャライザ
extension BoardLayoutSnapshot {
    /// GameViewLayoutContext から BoardLayoutSnapshot を組み立てるための補助イニシャライザ
    /// - Parameter context: GeometryReader から取得したレイアウト情報をまとめたコンテキスト
    init(context: GameViewLayoutContext) {
        // GeometryReader から取得した実測値を丸ごとコピーし、ViewModel からも参照できる形へ変換
        self.init(
            geometrySize: context.geometrySize,
            availableHeight: context.availableHeightForBoard,
            horizontalBoardBase: context.horizontalBoardBase,
            verticalBoardBase: context.verticalBoardBase,
            boardBaseSize: context.boardBaseSize,
            boardWidth: context.boardWidth,
            rawTopInset: context.rawTopInset,
            rawBottomInset: context.rawBottomInset,
            baseTopSafeAreaInset: context.baseTopSafeAreaInset,
            resolvedTopInset: context.topInset,
            overlayAdjustedTopInset: context.overlayAdjustedTopInset,
            resolvedBottomInset: context.bottomInset,
            statisticsHeight: context.statisticsHeight,
            resolvedStatisticsHeight: context.resolvedStatisticsHeight,
            handSectionHeight: context.handSectionHeight,
            resolvedHandSectionHeight: context.resolvedHandSectionHeight,
            regularAdditionalBottomPadding: context.regularAdditionalBottomPadding,
            handSectionBottomPadding: context.handSectionBottomPadding,
            usedTopSafeAreaFallback: context.usedTopFallback,
            usedBottomSafeAreaFallback: context.usedBottomFallback,
            usedStatisticsFallback: context.usedStatisticsFallback,
            usedHandSectionFallback: context.usedHandSectionFallback,
            controlRowTopPadding: context.controlRowTopPadding,
            topOverlayHeight: context.topOverlayHeight
        )
    }
}
