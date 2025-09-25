import SwiftUI  // SwiftUI の GeometryProxy や Size クラスを扱うために読み込む

/// GeometryReader から取得した値をテストやログ生成でも再利用しやすくするためのパラメータ構造体
/// - Note: GeometryProxy はテストコードから直接生成できないため、
///         必要な値だけを `GameViewLayoutParameters` として切り出し、
///         View 側は GeometryProxy ベース、テスト側は任意値ベースで初期化できるようにしている。
struct GameViewLayoutParameters {
    /// ビュー全体のサイズ（縦横の寸法）
    let size: CGSize
    /// セーフエリアの上方向量
    let safeAreaTop: CGFloat
    /// セーフエリアの下方向量
    let safeAreaBottom: CGFloat

    /// GeometryProxy から各種値を抽出して初期化するコンビニエンスイニシャライザ
    /// - Parameter geometry: GeometryReader が提供するプロキシ
    init(geometry: GeometryProxy) {
        self.init(
            size: geometry.size,
            safeAreaTop: geometry.safeAreaInsets.top,
            safeAreaBottom: geometry.safeAreaInsets.bottom
        )
    }

    /// テストやログ出力用に直接値を指定して初期化できる指定イニシャライザ
    /// - Parameters:
    ///   - size: コンテンツ領域のサイズ
    ///   - safeAreaTop: 上方向のセーフエリア量
    ///   - safeAreaBottom: 下方向のセーフエリア量
    init(size: CGSize, safeAreaTop: CGFloat, safeAreaBottom: CGFloat) {
        self.size = size
        self.safeAreaTop = safeAreaTop
        self.safeAreaBottom = safeAreaBottom
    }
}

/// GameView のレイアウト関連定数を一元管理するサポート列挙体
/// - Note: これまでは `GameView` ファイル内にネストされた定数群として定義されていたが、
///         レイアウト計算ロジックを専用ファイルへ切り出すにあたり、
///         ビュー本体と計算処理の両方から参照できるよう独立させている。
enum GameViewLayoutMetrics {
    /// 盤面セクションと手札セクションの間隔（VStack の spacing と一致させる）
    static let spacingBetweenBoardAndHand: CGFloat = 16
    /// 統計バッジと盤面の間隔（boardSection 内の spacing と一致させる）
    static let spacingBetweenStatisticsAndBoard: CGFloat = 12
    /// 盤面の正方形サイズへ乗算する縮小率（カードへ高さを譲るため 92% に設定）
    static let boardScale: CGFloat = 0.92
    /// 統計や手札によって縦方向が埋まった際でも盤面が消失しないよう確保する下限サイズ
    static let minimumBoardFallbackSize: CGFloat = 220
    /// 統計バッジ領域の最低想定高さ。初回レイアウトで 0 が返っても盤面がはみ出さないよう保険を掛ける
    static let statisticsSectionFallbackHeight: CGFloat = 72
    /// 手札と先読みカードを含めた最低想定高さ。カード 2 段構成とテキストを見越したゆとりを確保する
    static let handSectionFallbackHeight: CGFloat = 220
    /// 手札カード同士の横方向スペース（カード拡大後も全体幅が収まるよう微調整）
    static let handCardSpacing: CGFloat = 10
    /// 手札カードの幅。`MoveCardIllustrationView` 側の定義と同期させてサイズ差異を防ぐ
    static let handCardWidth: CGFloat = MoveCardIllustrationView.defaultWidth
    /// 手札カードの高さ。幅との比率を保ちながら僅かに拡張する
    static let handCardHeight: CGFloat = MoveCardIllustrationView.defaultHeight
    /// 手札セクションの基本的な下パディング。iPhone での視認性を最優先する基準値
    static let handSectionBasePadding: CGFloat = 16
    /// セーフエリア分の領域に加えて確保したいバッファ。ホームインジケータ直上に余白を置く
    static let handSectionSafeAreaAdditionalPadding: CGFloat = 8
    /// レギュラー幅（主に iPad）で追加する下方向マージン。指の位置とタブバーが干渉しないよう余裕を持たせる
    static let handSectionRegularAdditionalBottomPadding: CGFloat = 24
    /// 盤面上部のコントロールバーをステータスバーと離すための基本マージン
    static let controlRowBaseTopPadding: CGFloat = 16
    /// ステータスバーの高さに応じて追加で確保したい上方向の余白
    static let controlRowSafeAreaAdditionalPadding: CGFloat = 8
    /// ペナルティバナーが画面端に貼り付かないようにするための基準上パディング
    static let penaltyBannerBaseTopPadding: CGFloat = 12
    /// `safeAreaInsets.top` に加算しておきたいペナルティバナーの追加上マージン
    static let penaltyBannerSafeAreaAdditionalPadding: CGFloat = 6
    /// レギュラー幅端末で `safeAreaInsets.top` が 0 の場合に用いるフォールバック値
    static let regularWidthTopSafeAreaFallback: CGFloat = 24
    /// レギュラー幅端末で `safeAreaInsets.bottom` が 0 の場合に用いるフォールバック値
    static let regularWidthBottomSafeAreaFallback: CGFloat = 20
}

/// GeometryReader から収集した寸法を保持し、ビュー本体とログ出力の双方で利用できるようにした値オブジェクト
struct GameViewLayoutContext {
    let geometrySize: CGSize
    let rawTopInset: CGFloat
    let rawBottomInset: CGFloat
    let baseTopSafeAreaInset: CGFloat
    let usedTopFallback: Bool
    let usedBottomFallback: Bool
    let topOverlayHeight: CGFloat
    let overlayAdjustedTopInset: CGFloat
    let topInset: CGFloat
    let bottomInset: CGFloat
    let controlRowTopPadding: CGFloat
    let regularAdditionalBottomPadding: CGFloat
    let handSectionBottomPadding: CGFloat
    let statisticsHeight: CGFloat
    let resolvedStatisticsHeight: CGFloat
    let handSectionHeight: CGFloat
    let resolvedHandSectionHeight: CGFloat
    let availableHeightForBoard: CGFloat
    let horizontalBoardBase: CGFloat
    let verticalBoardBase: CGFloat
    let boardBaseSize: CGFloat
    let boardWidth: CGFloat
    let usedStatisticsFallback: Bool
    let usedHandSectionFallback: Bool
}

/// GameView のレイアウト値を算出する専用ヘルパー
/// - Note: 計算過程を View から切り離すことでメソッドの肥大化を防ぎ、
///         盤面が消える・余白が不足するといった不具合を調査する際に責務の境界を明確にする。
struct GameViewLayoutCalculator {
    /// レイアウト計算に必要なサイズとセーフエリア量
    let parameters: GameViewLayoutParameters
    /// 現在の横幅サイズクラス（iPad 最適化などでフォールバック値が必要か判断する）
    let horizontalSizeClass: UserInterfaceSizeClass?
    /// RootView が挿入したトップバーの高さ
    let topOverlayHeight: CGFloat
    /// システム由来セーフエリアの基準値
    let baseTopSafeAreaInset: CGFloat
    /// 直近で計測された統計バッジ領域の高さ
    let statisticsHeight: CGFloat
    /// 直近で計測された手札セクションの高さ
    let handSectionHeight: CGFloat

    /// GeometryProxy から生成したパラメータを用いて初期化するコンビニエンスイニシャライザ
    /// - Parameters:
    ///   - geometry: GeometryReader が提供するサイズ・セーフエリア情報
    ///   - horizontalSizeClass: 現在のサイズクラス
    ///   - topOverlayHeight: トップオーバーレイの高さ
    ///   - baseTopSafeAreaInset: ルートビューで測定したセーフエリア基準値
    ///   - statisticsHeight: 直近で計測された統計セクションの高さ
    ///   - handSectionHeight: 直近で計測された手札セクションの高さ
    init(
        geometry: GeometryProxy,
        horizontalSizeClass: UserInterfaceSizeClass?,
        topOverlayHeight: CGFloat,
        baseTopSafeAreaInset: CGFloat,
        statisticsHeight: CGFloat,
        handSectionHeight: CGFloat
    ) {
        self.init(
            parameters: GameViewLayoutParameters(geometry: geometry),
            horizontalSizeClass: horizontalSizeClass,
            topOverlayHeight: topOverlayHeight,
            baseTopSafeAreaInset: baseTopSafeAreaInset,
            statisticsHeight: statisticsHeight,
            handSectionHeight: handSectionHeight
        )
    }

    /// 任意のパラメータを指定して初期化する指定イニシャライザ
    /// - Parameters:
    ///   - parameters: レイアウト計算に必要な寸法情報
    ///   - horizontalSizeClass: 現在のサイズクラス
    ///   - topOverlayHeight: トップオーバーレイの高さ
    ///   - baseTopSafeAreaInset: ルートビューで測定したセーフエリア基準値
    ///   - statisticsHeight: 直近で計測された統計セクションの高さ
    ///   - handSectionHeight: 直近で計測された手札セクションの高さ
    init(
        parameters: GameViewLayoutParameters,
        horizontalSizeClass: UserInterfaceSizeClass?,
        topOverlayHeight: CGFloat,
        baseTopSafeAreaInset: CGFloat,
        statisticsHeight: CGFloat,
        handSectionHeight: CGFloat
    ) {
        self.parameters = parameters
        self.horizontalSizeClass = horizontalSizeClass
        self.topOverlayHeight = topOverlayHeight
        self.baseTopSafeAreaInset = baseTopSafeAreaInset
        self.statisticsHeight = statisticsHeight
        self.handSectionHeight = handSectionHeight
    }

    /// レイアウト計算を実行し、`GameViewLayoutContext` を生成する
    func makeContext() -> GameViewLayoutContext {
        // MARK: - セーフエリアに対するフォールバック計算
        let rawTopInset = parameters.safeAreaTop
        let rawBottomInset = parameters.safeAreaBottom
        let overlayFromEnvironment = max(topOverlayHeight, 0)
        let baseSafeAreaTop = max(baseTopSafeAreaInset, 0)
        let overlayFromDifference = max(rawTopInset - baseSafeAreaTop, 0)
        let overlayCompensation = min(max(overlayFromEnvironment, overlayFromDifference), rawTopInset)
        let adjustedTopInset = max(rawTopInset - overlayCompensation, 0)
        // トップオーバーレイ分を差し引いた後の安全なセーフエリア量をそのまま保持し、
        // 以降の計算で二重に減算されないようにする。
        let overlayAdjustedTopInset = adjustedTopInset

        let usedTopFallback = adjustedTopInset <= 0 && horizontalSizeClass == .regular
        let usedBottomFallback = rawBottomInset <= 0 && horizontalSizeClass == .regular

        let topInset = adjustedTopInset > 0
            ? adjustedTopInset
            : (usedTopFallback ? GameViewLayoutMetrics.regularWidthTopSafeAreaFallback : 0)
        let bottomInset = rawBottomInset > 0
            ? rawBottomInset
            : (usedBottomFallback ? GameViewLayoutMetrics.regularWidthBottomSafeAreaFallback : 0)

        // MARK: - 盤面上部コントロールバーの余白を決定
        let controlRowTopPadding = max(
            GameViewLayoutMetrics.controlRowBaseTopPadding,
            overlayAdjustedTopInset + GameViewLayoutMetrics.controlRowSafeAreaAdditionalPadding
        )

        // MARK: - 手札セクション下部の余白を決定
        let regularAdditionalPadding = horizontalSizeClass == .regular
            ? GameViewLayoutMetrics.handSectionRegularAdditionalBottomPadding
            : 0
        let handSectionBottomPadding = max(
            GameViewLayoutMetrics.handSectionBasePadding,
            bottomInset
                + GameViewLayoutMetrics.handSectionSafeAreaAdditionalPadding
                + regularAdditionalPadding
        )

        // MARK: - 計測が完了していない高さのフォールバック処理
        let isStatisticsHeightMeasured = statisticsHeight > 0
        let resolvedStatisticsHeight = isStatisticsHeightMeasured
            ? statisticsHeight
            : GameViewLayoutMetrics.statisticsSectionFallbackHeight
        let isHandSectionHeightMeasured = handSectionHeight > 0
        let resolvedHandSectionHeight = isHandSectionHeightMeasured
            ? handSectionHeight
            : GameViewLayoutMetrics.handSectionFallbackHeight

        // MARK: - 盤面に割り当てられる高さと正方形サイズの算出
        let availableHeightForBoard = parameters.size.height
            - resolvedStatisticsHeight
            - resolvedHandSectionHeight
            - GameViewLayoutMetrics.spacingBetweenBoardAndHand
            - GameViewLayoutMetrics.spacingBetweenStatisticsAndBoard
            - handSectionBottomPadding
        let horizontalBoardBase = max(parameters.size.width, GameViewLayoutMetrics.minimumBoardFallbackSize)
        let verticalBoardBase = availableHeightForBoard > 0 ? availableHeightForBoard : horizontalBoardBase
        let boardBaseSize = min(horizontalBoardBase, verticalBoardBase)
        let boardWidth = boardBaseSize * GameViewLayoutMetrics.boardScale

        return GameViewLayoutContext(
            geometrySize: parameters.size,
            rawTopInset: rawTopInset,
            rawBottomInset: rawBottomInset,
            baseTopSafeAreaInset: baseSafeAreaTop,
            usedTopFallback: usedTopFallback,
            usedBottomFallback: usedBottomFallback,
            topOverlayHeight: overlayCompensation,
            overlayAdjustedTopInset: overlayAdjustedTopInset,
            topInset: topInset,
            bottomInset: bottomInset,
            controlRowTopPadding: controlRowTopPadding,
            regularAdditionalBottomPadding: regularAdditionalPadding,
            handSectionBottomPadding: handSectionBottomPadding,
            statisticsHeight: statisticsHeight,
            resolvedStatisticsHeight: resolvedStatisticsHeight,
            handSectionHeight: handSectionHeight,
            resolvedHandSectionHeight: resolvedHandSectionHeight,
            availableHeightForBoard: availableHeightForBoard,
            horizontalBoardBase: horizontalBoardBase,
            verticalBoardBase: verticalBoardBase,
            boardBaseSize: boardBaseSize,
            boardWidth: boardWidth,
            usedStatisticsFallback: !isStatisticsHeightMeasured,
            usedHandSectionFallback: !isHandSectionHeightMeasured
        )
    }
}
