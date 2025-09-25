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
}

