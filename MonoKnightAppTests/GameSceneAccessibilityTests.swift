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

    /// 連続移動カードの途中マスは枠なしの塗り、終点は水色枠として描き分けることを確認する
    func testMultiStepPathHighlightUsesFillWithoutFrame() {
        let intermediatePoint = GridPoint(x: 2, y: 2)
        let destinationPoint = GridPoint(x: 4, y: 4)
        let (scene, view, _) = makeScene()
        defer { view.presentScene(nil) }

        scene.updateHighlights([
            .guideMultiStepPath: [intermediatePoint, destinationPoint],
            .guideMultiStepCandidate: [destinationPoint],
        ])

        guard let pathStyle = scene.highlightStyleForTesting(
            kind: .guideMultiStepPath,
            at: intermediatePoint
        ) else {
            XCTFail("連続移動の通過塗りノードを取得できません")
            return
        }
        guard let destinationStyle = scene.highlightStyleForTesting(
            kind: .guideMultiStepCandidate,
            at: destinationPoint
        ) else {
            XCTFail("連続移動の終点枠ノードを取得できません")
            return
        }

        XCTAssertEqual(pathStyle.lineWidth, 0, "途中マスはタップ可能な枠に見せないため線幅を持たない想定です")
        XCTAssertFalse(pathStyle.fillColor.isEqual(SKColor.clear), "途中マスは薄い水色塗りで通過範囲を示します")
        XCTAssertGreaterThan(destinationStyle.lineWidth, 0, "終点はタップ可能な移動先として水色枠を持つ想定です")
        XCTAssertTrue(destinationStyle.fillColor.isEqual(SKColor.clear), "終点枠自体は塗りを持たず、通過塗りと重ねます")
    }

    func testDungeonBasicMoveUsesFrameAndDungeonMarkersAvoidTileFrames() {
        let basicMovePoint = GridPoint(x: 1, y: 1)
        let cardPickupPoint = GridPoint(x: 2, y: 1)
        let crackedFloorPoint = GridPoint(x: 3, y: 1)
        let collapsedFloorPoint = GridPoint(x: 4, y: 1)
        let (scene, view, _) = makeScene()
        defer { view.presentScene(nil) }

        scene.updateHighlights([
            .dungeonBasicMove: [basicMovePoint],
            .dungeonCardPickup: [cardPickupPoint],
            .dungeonCrackedFloor: [crackedFloorPoint],
            .dungeonCollapsedFloor: [collapsedFloorPoint],
        ])

        guard let basicMoveStyle = scene.highlightStyleForTesting(
            kind: .dungeonBasicMove,
            at: basicMovePoint
        ) else {
            XCTFail("基本移動の枠ノードを取得できません")
            return
        }
        guard let cardPickupStyle = scene.highlightStyleForTesting(
            kind: .dungeonCardPickup,
            at: cardPickupPoint
        ) else {
            XCTFail("床落ちカードのマーカーノードを取得できません")
            return
        }
        guard let crackedFloorStyle = scene.highlightStyleForTesting(
            kind: .dungeonCrackedFloor,
            at: crackedFloorPoint
        ) else {
            XCTFail("ひび割れ床のマーカーノードを取得できません")
            return
        }
        guard let collapsedFloorStyle = scene.highlightStyleForTesting(
            kind: .dungeonCollapsedFloor,
            at: collapsedFloorPoint
        ) else {
            XCTFail("崩落床のマーカーノードを取得できません")
            return
        }

        XCTAssertGreaterThan(basicMoveStyle.lineWidth, 0, "基本移動はこのターンに移動可能なマスなので枠を持ちます")
        XCTAssertEqual(cardPickupStyle.lineWidth, 0, "床落ちカードは移動可能枠ではなく、枠なしの小マーカーで示します")
        XCTAssertFalse(cardPickupStyle.fillColor.isEqual(SKColor.clear), "床落ちカードは枠なしでも視認できる塗りを持ちます")
        XCTAssertEqual(crackedFloorStyle.lineWidth, 0, "ひび割れ床は移動可能枠ではないためタイル枠を持ちません")
        XCTAssertEqual(collapsedFloorStyle.lineWidth, 0, "崩落床は移動可能枠ではないためタイル枠を持ちません")
    }

    func testPatrolMovementArrowNodesUpdateAndClear() {
        let (scene, view, _) = makeScene()
        defer { view.presentScene(nil) }

        scene.updatePatrolMovementPreviews([
            ScenePatrolMovementPreview(
                enemyID: "patrol",
                current: GridPoint(x: 1, y: 1),
                next: GridPoint(x: 2, y: 1),
                vector: MoveVector(dx: 1, dy: 0)
            )
        ])

        XCTAssertEqual(scene.patrolMovementArrowCountForTesting(), 1, "巡回兵1体につき矢印を1本表示する想定です")

        scene.updatePatrolMovementPreviews([])

        XCTAssertEqual(scene.patrolMovementArrowCountForTesting(), 0, "巡回プレビューが空になったら古い矢印を消す必要があります")
    }
}
#endif
