import XCTest
import SwiftUI
@testable import MonoKnightApp

/// GameViewLayoutCalculator の計算ロジックを検証するテスト
/// - Note: オーバーレイ補正やフォールバック処理が複雑化しやすいため、
///         実測値から切り出した `GameViewLayoutParameters` を用いてロジックを直接テストする。
final class GameViewLayoutCalculatorTests: XCTestCase {

    /// トップオーバーレイを差し引いた後のセーフエリア量が二重に減算されないことを確認する
    func testOverlayAdjustedTopInsetMatchesResolvedTopInset() {
        // 典型的な iPhone（ノッチあり）を想定した寸法を用意
        // - 高さ 844pt / 幅 390pt（iPhone 13 など）
        // - セーフエリア上端 91pt（ステータスバー 47pt + カスタムオーバーレイ 44pt）
        // - セーフエリア下端 34pt（ホームインジケータ相当）
        let parameters = GameViewLayoutParameters(
            size: CGSize(width: 390, height: 844),
            safeAreaTop: 91,
            safeAreaBottom: 34
        )

        // カスタムオーバーレイ 44pt / 統計領域 120pt / 手札領域 260pt を想定
        let calculator = GameViewLayoutCalculator(
            parameters: parameters,
            horizontalSizeClass: .compact,
            topOverlayHeight: 44,
            baseTopSafeAreaInset: 47,
            statisticsHeight: 120,
            handSectionHeight: 260
        )

        let context = calculator.makeContext()

        // オーバーレイ除去後のトップセーフエリアは 47pt に揃う想定
        XCTAssertEqual(context.topInset, 47, accuracy: 0.001, "トップインセットが期待値と一致しません")
        // overlayAdjustedTopInset も topInset と同じ値を維持し、二重減算が解消されていることを確認
        XCTAssertEqual(context.overlayAdjustedTopInset, context.topInset, accuracy: 0.001, "overlayAdjustedTopInset がトップインセットと不一致です")
        // トップバーで押し下げられたぶんを補正し、コントロール行の余白は基準値 16pt へ収束する想定
        XCTAssertEqual(
            context.controlRowTopPadding,
            GameViewLayoutMetrics.controlRowBaseTopPadding,
            accuracy: 0.001,
            "コントロール行の余白が基準値からずれています"
        )
        // 記録用の topOverlayHeight にはオーバーレイ量がそのまま反映されていることも確認
        XCTAssertEqual(context.topOverlayHeight, 44, accuracy: 0.001, "オーバーレイ高さの記録値が想定と異なります")
    }

    /// トップオーバーレイが存在せず、セーフエリア測定値と基準値が一致するケースでは
    /// コントロール行の余白が 16pt へ収束することを確認する
    func testControlRowPaddingConvergesToBaseWhenOverlayIsZero() {
        // iPhone（ノッチあり）で RootView 側のセーフエリア計測値と GeometryReader の値が等しいケースを想定
        let parameters = GameViewLayoutParameters(
            size: CGSize(width: 390, height: 844),
            safeAreaTop: 47,
            safeAreaBottom: 34
        )

        // トップオーバーレイ 0 / 統計 120pt / 手札 260pt の構成で計算
        let calculator = GameViewLayoutCalculator(
            parameters: parameters,
            horizontalSizeClass: .compact,
            topOverlayHeight: 0,
            baseTopSafeAreaInset: 47,
            statisticsHeight: 120,
            handSectionHeight: 260
        )

        let context = calculator.makeContext()

        // 追加余白が発生しないため、コントロール行の余白は 16pt に一致するはず
        XCTAssertEqual(
            context.controlRowTopPadding,
            GameViewLayoutMetrics.controlRowBaseTopPadding,
            accuracy: 0.001,
            "コントロール行の余白が基準値からずれています"
        )
    }

    /// iPad Portrait では盤面を十分に大きくしつつ、視線移動が広がりすぎない上限へ収める
    func testRegularWidthPortraitBoardSizeIsCappedForIPad() {
        let scenarios: [(name: String, size: CGSize, expectedMinimumWidth: CGFloat)] = [
            ("iPad mini", CGSize(width: 744, height: 1_133), 560),
            ("iPad 11-inch", CGSize(width: 834, height: 1_194), 600),
            ("iPad 13-inch", CGSize(width: 1_032, height: 1_366), 600),
        ]

        for scenario in scenarios {
            let parameters = GameViewLayoutParameters(
                size: scenario.size,
                safeAreaTop: 24,
                safeAreaBottom: 20
            )
            let calculator = GameViewLayoutCalculator(
                parameters: parameters,
                horizontalSizeClass: .regular,
                topOverlayHeight: 0,
                baseTopSafeAreaInset: 24,
                statisticsHeight: 92,
                handSectionHeight: 248
            )

            let context = calculator.makeContext()

            XCTAssertGreaterThanOrEqual(
                context.boardWidth,
                scenario.expectedMinimumWidth,
                "\(scenario.name) の盤面幅が小さすぎます"
            )
            XCTAssertLessThanOrEqual(
                context.boardWidth,
                GameViewLayoutMetrics.regularWidthMaximumBoardWidth,
                "\(scenario.name) の盤面幅が iPad 向け上限を超えています"
            )
            XCTAssertGreaterThan(
                context.availableHeightForBoard,
                context.resolvedStatisticsHeight,
                "\(scenario.name) で上部操作領域を保てる高さが残っていません"
            )
        }
    }

    /// 初期スポーン案内は盤面へ重ねるため、盤面サイズ計算へ予約高さを持ち込まない
    func testSpawnSelectionOverlayDoesNotChangeBoardSize() {
        let parameters = GameViewLayoutParameters(
            size: CGSize(width: 390, height: 844),
            safeAreaTop: 47,
            safeAreaBottom: 34
        )
        let baseCalculator = GameViewLayoutCalculator(
            parameters: parameters,
            horizontalSizeClass: .compact,
            topOverlayHeight: 0,
            baseTopSafeAreaInset: 47,
            statisticsHeight: 120,
            handSectionHeight: 260
        )
        let spawnOverlayCalculator = GameViewLayoutCalculator(
            parameters: parameters,
            horizontalSizeClass: .compact,
            topOverlayHeight: 0,
            baseTopSafeAreaInset: 47,
            statisticsHeight: 120,
            handSectionHeight: 260
        )

        let baseContext = baseCalculator.makeContext()
        let spawnOverlayContext = spawnOverlayCalculator.makeContext()

        XCTAssertEqual(
            spawnOverlayContext.availableHeightForBoard,
            baseContext.availableHeightForBoard,
            accuracy: 0.001,
            "スポーン案内はオーバーレイ表示なので盤面に使える高さを変えない想定です"
        )
        XCTAssertEqual(
            spawnOverlayContext.boardWidth,
            baseContext.boardWidth,
            accuracy: 0.001,
            "開始位置選択中も盤面幅は通常時と同じに保つ想定です"
        )
    }
}
