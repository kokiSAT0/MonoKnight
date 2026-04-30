#if canImport(SpriteKit) && canImport(UIKit)
import Foundation
import SpriteKit
import UIKit
import XCTest
@testable import Game

/// - Note: SpriteKit のアクセシビリティ出力が想定文言になっているか検証する
@MainActor
final class GameSceneAccessibilityTests: XCTestCase {
    /// テスト用に GameScene と紐付けた SKView を生成する
    /// - Parameters:
    ///   - impassablePoints: 初期障害物マス集合
    ///   - size: 盤面サイズ（省略時は 5×5）
    /// - Returns: 生成したシーンとビューのタプル
    private func makeScene(
        impassablePoints: Set<GridPoint> = [],
        size: Int = BoardGeometry.standardSize,
        initialVisitedPoints: [GridPoint]? = nil
    ) -> (scene: GameScene, view: SKView, boardSize: Int) {
        let scene = GameScene(
            initialBoardSize: size,
            initialVisitedPoints: initialVisitedPoints ?? BoardGeometry.defaultInitialVisitedPoints(for: size),
            requiredVisitOverrides: [:],
            togglePoints: [],
            impassablePoints: impassablePoints
        )
        scene.scaleMode = .resizeFill
        let view = SKView(frame: CGRect(origin: .zero, size: CGSize(width: 320, height: 320)))
        scene.size = view.bounds.size
        view.presentScene(scene)
        // SpriteKit が didMove 内でアクセシビリティ情報を構築できるよう、1 フレーム分だけ RunLoop を回しておく
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        return (scene, view, size)
    }

    /// 移動不可マスが VoiceOver で「移動不可」と読み上げられることを確認する
    func testAccessibilityLabelForImpassableTile() {
        let impassablePoint = GridPoint(x: 0, y: 0)
        let (scene, view, boardSize) = makeScene(impassablePoints: [impassablePoint])
        defer { view.presentScene(nil) }

        guard let elements = scene.accessibilityElements as? [UIAccessibilityElement] else {
            XCTFail("アクセシビリティ要素が生成されていない")
            return
        }
        let index = impassablePoint.y * boardSize + impassablePoint.x
        XCTAssertLessThan(index, elements.count, "障害物マスのインデックスが範囲外")
        XCTAssertEqual(elements[index].accessibilityLabel, "移動不可")
    }

    /// 駒が乗っている場合は「駒あり・状態」の書式で読み上げることを確認する
    func testAccessibilityLabelIncludesKnightPrefix() {
        let (scene, view, boardSize) = makeScene()
        defer { view.presentScene(nil) }

        let knightPoint = GridPoint(x: 1, y: 0)
        scene.moveKnight(to: knightPoint)

        guard let elements = scene.accessibilityElements as? [UIAccessibilityElement] else {
            XCTFail("アクセシビリティ要素が生成されていない")
            return
        }
        let index = knightPoint.y * boardSize + knightPoint.x
        XCTAssertLessThan(index, elements.count, "騎士位置のインデックスが範囲外")
        XCTAssertEqual(elements[index].accessibilityLabel, "駒あり・未踏破")
    }

    /// 目的地制では通常マスの踏破済み塗りを出さないことを確認する
    func testVisitedTileFillCanBeHiddenForTargetCollectionModes() {
        let visitedPoint = GridPoint(x: 0, y: 0)
        let unvisitedPoint = GridPoint(x: 1, y: 0)
        let (scene, view, _) = makeScene(initialVisitedPoints: [visitedPoint])
        defer { view.presentScene(nil) }

        scene.updateShowsVisitedTileFill(false)

        guard let visitedColor = scene.tileFillColorForTesting(at: visitedPoint),
              let unvisitedColor = scene.tileFillColorForTesting(at: unvisitedPoint) else {
            XCTFail("タイル塗り色を取得できません")
            return
        }
        XCTAssertTrue(
            visitedColor.isEqual(unvisitedColor),
            "目的地制では踏破済み通常マスも未踏破通常マスと同じ塗り色にします"
        )
    }

    /// 全踏破モードでは通常マスの踏破済み塗りを維持することを確認する
    func testVisitedTileFillRemainsVisibleForBoardClearModes() {
        let visitedPoint = GridPoint(x: 0, y: 0)
        let unvisitedPoint = GridPoint(x: 1, y: 0)
        let (scene, view, _) = makeScene(initialVisitedPoints: [visitedPoint])
        defer { view.presentScene(nil) }

        scene.updateShowsVisitedTileFill(true)

        guard let visitedColor = scene.tileFillColorForTesting(at: visitedPoint),
              let unvisitedColor = scene.tileFillColorForTesting(at: unvisitedPoint) else {
            XCTFail("タイル塗り色を取得できません")
            return
        }
        XCTAssertFalse(
            visitedColor.isEqual(unvisitedColor),
            "全踏破モードでは踏破済み通常マスの塗り分けを維持します"
        )
    }

    /// 通過で取れる目的地は、移動先候補として読み上げないことを確認する
    func testAccessibilityDoesNotDescribeTargetCaptureFrameAsMoveDestination() {
        let targetPoint = GridPoint(x: 3, y: 2)
        let (scene, view, boardSize) = makeScene()
        defer { view.presentScene(nil) }

        scene.updateHighlights([
            .currentTarget: [targetPoint],
            .targetCaptureCandidate: [targetPoint],
        ])

        guard let elements = scene.accessibilityElements as? [UIAccessibilityElement] else {
            XCTFail("アクセシビリティ要素が生成されていない")
            return
        }
        let index = targetPoint.y * boardSize + targetPoint.x
        XCTAssertLessThan(index, elements.count, "目的地マスのインデックスが範囲外")
        XCTAssertEqual(
            elements[index].accessibilityLabel,
            "表示中の目的地・未踏破",
            "通過で取れる目的地を移動先候補として読み上げない想定です"
        )
    }
}
#endif
