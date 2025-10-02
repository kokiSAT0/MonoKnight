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
        size: Int = BoardGeometry.standardSize
    ) -> (scene: GameScene, view: SKView, boardSize: Int) {
        let scene = GameScene(
            initialBoardSize: size,
            initialVisitedPoints: BoardGeometry.defaultInitialVisitedPoints(for: size),
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
}
#endif
