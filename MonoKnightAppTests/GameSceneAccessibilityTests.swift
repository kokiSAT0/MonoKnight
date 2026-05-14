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

    /// 障害物マスには岩/柱として読める小マーカーを重ねることを確認する
    func testImpassableTilesShowRockMarkers() {
        let impassablePoints: Set<GridPoint> = [
            GridPoint(x: 0, y: 0),
            GridPoint(x: 2, y: 2)
        ]
        let (scene, view, _) = makeScene(impassablePoints: impassablePoints)
        defer { view.presentScene(nil) }

        XCTAssertEqual(scene.impassableMarkerCountForTesting(), impassablePoints.count)
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

    /// 塔の盤面表示で通常マスの踏破済み塗りを維持することを確認する
    func testVisitedTileFillRemainsVisibleForDungeonBoard() {
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
            "塔の盤面表示では踏破済み通常マスの塗り分けを維持します"
        )
    }

    /// 暗闇フロアでは視界外マスを専用の暗い塗りと境界線で示すことを確認する
    func testDarknessHiddenTilesUseDedicatedFillAndBoundaryStroke() {
        let visiblePoint = GridPoint(x: 1, y: 1)
        let boundaryHiddenPoint = GridPoint(x: 1, y: 0)
        let deepHiddenPoint = GridPoint(x: 4, y: 4)
        let (scene, view, _) = makeScene()
        defer { view.presentScene(nil) }

        scene.updateDungeonVisiblePoints([visiblePoint])

        guard let visibleStyle = scene.tileStyleForTesting(at: visiblePoint),
              let boundaryStyle = scene.tileStyleForTesting(at: boundaryHiddenPoint),
              let deepHiddenStyle = scene.tileStyleForTesting(at: deepHiddenPoint) else {
            XCTFail("暗闇タイルの描画スタイルを取得できません")
            return
        }

        XCTAssertTrue(
            visibleStyle.fillColor.matchesComponents(of: GameScenePalette.fallback.boardTileUnvisited),
            "視界内の通常マスは暗闇色へ変えず、通常の未踏破塗りを維持します"
        )
        XCTAssertTrue(
            boundaryStyle.fillColor.matchesComponents(of: GameScenePalette.fallback.boardDarknessHiddenTile),
            "視界外マスは背景色ではなく暗闇専用の塗りで示します"
        )
        XCTAssertFalse(
            boundaryStyle.fillColor.isEqual(GameScenePalette.fallback.boardBackground),
            "視界外マスを盤面背景に溶かさないようにします"
        )
        XCTAssertGreaterThan(
            boundaryStyle.lineWidth,
            deepHiddenStyle.lineWidth,
            "視界に接する暗闇マスは境界線を太くして境目を読ませます"
        )
        XCTAssertGreaterThan(
            boundaryStyle.strokeColor.alphaComponentForTesting,
            deepHiddenStyle.strokeColor.alphaComponentForTesting,
            "視界に接する暗闇マスは奥の暗闇より濃い境界線にします"
        )
    }

    /// 塔ダンジョンの出口は、階段形状で示すことを確認する
    func testDungeonExitHighlightUsesStaircaseShape() {
        let exitPoint = GridPoint(x: 3, y: 3)
        let (scene, view, _) = makeScene()
        defer { view.presentScene(nil) }

        scene.updateHighlights([
            .dungeonExit: [exitPoint],
        ])

        guard let exitBounds = scene.highlightPathBoundsForTesting(
            kind: .dungeonExit,
            at: exitPoint
        ), let exitElementCount = scene.highlightPathElementCountForTesting(
            kind: .dungeonExit,
            at: exitPoint
        ) else {
            XCTFail("出口のマーカー形状を取得できません")
            return
        }

        XCTAssertGreaterThan(exitElementCount, 3, "出口は段付きの階段形状として描きます")
        XCTAssertGreaterThan(exitBounds.width, exitBounds.height, "出口は横方向に段が並ぶ階段形状にします")
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
        XCTAssertTrue(destinationStyle.fillColor.isClearForTesting, "終点枠自体は塗りを持たず、通過塗りと重ねます")
    }

    func testDarknessMoveCandidatesUseHighContrastFrames() {
        let visibleBasicMovePoint = GridPoint(x: 1, y: 1)
        let hiddenBasicMovePoint = GridPoint(x: 2, y: 2)
        let visibleCardMovePoint = GridPoint(x: 1, y: 2)
        let hiddenCardMovePoint = GridPoint(x: 3, y: 2)
        let hiddenPathPoint = GridPoint(x: 2, y: 3)
        let (scene, view, _) = makeScene()
        defer { view.presentScene(nil) }

        scene.updateDungeonVisiblePoints([visibleBasicMovePoint, visibleCardMovePoint])
        scene.updateHighlights([
            .dungeonBasicMove: [visibleBasicMovePoint, hiddenBasicMovePoint],
            .guideSingleCandidate: [visibleCardMovePoint, hiddenCardMovePoint],
            .guideMultiStepPath: [hiddenPathPoint],
        ])

        guard let visibleBasicStyle = scene.highlightStyleForTesting(
            kind: .dungeonBasicMove,
            at: visibleBasicMovePoint
        ), let hiddenBasicStyle = scene.highlightStyleForTesting(
            kind: .dungeonBasicMove,
            at: hiddenBasicMovePoint
        ), let visibleCardStyle = scene.highlightStyleForTesting(
            kind: .guideSingleCandidate,
            at: visibleCardMovePoint
        ), let hiddenCardStyle = scene.highlightStyleForTesting(
            kind: .guideSingleCandidate,
            at: hiddenCardMovePoint
        ), let hiddenPathStyle = scene.highlightStyleForTesting(
            kind: .guideMultiStepPath,
            at: hiddenPathPoint
        ) else {
            XCTFail("暗闇上の移動候補スタイルを取得できません")
            return
        }

        XCTAssertTrue(visibleBasicStyle.strokeColor.isBlackForTesting, "視界内の基本移動は従来どおり黒枠を維持します")
        XCTAssertFalse(hiddenBasicStyle.strokeColor.isBlackForTesting, "暗闇上の基本移動は黒枠のままにしません")
        XCTAssertFalse(hiddenBasicStyle.fillColor.isClearForTesting, "暗闇上の基本移動は薄い塗りで暗い床から浮かせます")
        XCTAssertGreaterThan(hiddenBasicStyle.lineWidth, visibleBasicStyle.lineWidth, "暗闇上の基本移動は通常より少し太い枠にします")
        XCTAssertGreaterThan(hiddenBasicStyle.glowWidth, 0, "暗闇上の基本移動は薄い発光で視認性を上げます")
        XCTAssertGreaterThan(hiddenCardStyle.lineWidth, visibleCardStyle.lineWidth, "暗闇上のカード移動候補も枠を少し強めます")
        XCTAssertGreaterThan(hiddenCardStyle.glowWidth, 0, "暗闇上のカード移動候補にも薄い発光を足します")
        XCTAssertEqual(hiddenPathStyle.lineWidth, 0, "連続移動の途中マスは暗闇上でもタップ可能枠に見せません")
    }

    func testDungeonBasicMoveUsesFrameAndDungeonMarkersAvoidTileFrames() {
        let basicMovePoint = GridPoint(x: 1, y: 1)
        let cardMovePoint = GridPoint(x: 1, y: 2)
        let cardPickupPoint = GridPoint(x: 2, y: 1)
        let damageTrapPoint = GridPoint(x: 2, y: 2)
        let keyPoint = GridPoint(x: 3, y: 2)
        let crackedFloorPoint = GridPoint(x: 3, y: 1)
        let collapsedFloorPoint = GridPoint(x: 4, y: 1)
        let (scene, view, _) = makeScene()
        defer { view.presentScene(nil) }

        scene.updateHighlights([
            .guideSingleCandidate: [cardMovePoint],
            .dungeonBasicMove: [basicMovePoint],
            .dungeonCardPickup: [cardPickupPoint],
            .dungeonDamageTrap: [damageTrapPoint],
            .dungeonKey: [keyPoint],
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
        guard let cardMoveStyle = scene.highlightStyleForTesting(
            kind: .guideSingleCandidate,
            at: cardMovePoint
        ) else {
            XCTFail("カード移動の枠ノードを取得できません")
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
        guard let damageTrapStyle = scene.highlightStyleForTesting(
            kind: .dungeonDamageTrap,
            at: damageTrapPoint
        ) else {
            XCTFail("ダメージ罠のマーカーノードを取得できません")
            return
        }
        guard let keyStyle = scene.highlightStyleForTesting(
            kind: .dungeonKey,
            at: keyPoint
        ) else {
            XCTFail("鍵のマーカーノードを取得できません")
            return
        }
        guard let collapsedFloorStyle = scene.highlightStyleForTesting(
            kind: .dungeonCollapsedFloor,
            at: collapsedFloorPoint
        ) else {
            XCTFail("崩落床のマーカーノードを取得できません")
            return
        }
        guard let basicMoveBounds = scene.highlightPathBoundsForTesting(
            kind: .dungeonBasicMove,
            at: basicMovePoint
        ), let cardMoveBounds = scene.highlightPathBoundsForTesting(
            kind: .guideSingleCandidate,
            at: cardMovePoint
        ), let damageTrapBounds = scene.highlightPathBoundsForTesting(
            kind: .dungeonDamageTrap,
            at: damageTrapPoint
        ) else {
            XCTFail("基本移動、カード移動、ダメージ罠のマーカーサイズを取得できません")
            return
        }
        guard let damageTrapElementCount = scene.highlightPathElementCountForTesting(
            kind: .dungeonDamageTrap,
            at: damageTrapPoint
        ) else {
            XCTFail("ダメージ罠のマーカーパスを取得できません")
            return
        }

        XCTAssertGreaterThan(basicMoveStyle.lineWidth, 0, "基本移動はこのターンに移動可能なマスなので枠を持ちます")
        XCTAssertTrue(basicMoveStyle.strokeColor.isBlackForTesting, "基本移動はカードなしの初期移動として黒枠で示します")
        XCTAssertEqual(basicMoveStyle.lineWidth, cardMoveStyle.lineWidth, accuracy: 0.01, "基本移動枠はカード移動候補と同じ線幅に揃えます")
        XCTAssertEqual(basicMoveBounds.width, cardMoveBounds.width, accuracy: 0.01, "基本移動枠はカード移動候補と同じ横幅に揃えます")
        XCTAssertEqual(basicMoveBounds.height, cardMoveBounds.height, accuracy: 0.01, "基本移動枠はカード移動候補と同じ高さに揃えます")
        XCTAssertTrue(basicMoveStyle.fillColor.isClearForTesting, "基本移動枠自体は塗りを持たない想定です")
        XCTAssertEqual(cardPickupStyle.lineWidth, 0, "床落ちカードは移動可能枠ではなく、枠なしの小マーカーで示します")
        XCTAssertFalse(cardPickupStyle.fillColor.isEqual(SKColor.clear), "床落ちカードは枠なしでも視認できる塗りを持ちます")
        XCTAssertEqual(damageTrapStyle.lineWidth, 0, "ダメージ罠は移動可能枠ではないためタイル枠を持ちません")
        XCTAssertFalse(damageTrapStyle.fillColor.isEqual(SKColor.clear), "ダメージ罠は踏む前に見える塗りを持ちます")
        XCTAssertGreaterThan(damageTrapBounds.width, cardMoveBounds.width * 0.45, "ダメージ罠は小さな点ではなく横幅のある棘マーカーで示します")
        XCTAssertGreaterThan(damageTrapBounds.height, cardMoveBounds.height * 0.45, "ダメージ罠は踏むと危険だと読める高さのある棘マーカーで示します")
        XCTAssertGreaterThan(damageTrapElementCount, 7, "ダメージ罠は単一三角ではなく複数の棘を持つパスで示します")
        XCTAssertEqual(keyStyle.lineWidth, 0, "塔鍵は移動可能枠ではなく、枠なしの小マーカーで示します")
        XCTAssertFalse(keyStyle.fillColor.isEqual(SKColor.clear), "塔鍵は取得前に見える塗りを持ちます")
        XCTAssertGreaterThan(crackedFloorStyle.lineWidth, 0, "ひび割れ床はタイル枠ではなく亀裂線で示します")
        XCTAssertEqual(collapsedFloorStyle.lineWidth, 0, "崩落床は移動可能枠ではないためタイル枠を持ちません")
    }

    func testDungeonFallEffectAddsTransientNodes() {
        let fallPoint = GridPoint(x: 2, y: 2)
        let (scene, view, _) = makeScene()
        defer { view.presentScene(nil) }

        scene.moveKnight(to: fallPoint)
        scene.playDungeonFallEffect(at: fallPoint)

        XCTAssertGreaterThan(
            scene.transientEffectNodeCountForTesting(),
            0,
            "落下時は短い影やリングで落ちたことを示す必要があります"
        )
    }

    func testDamageEffectAddsTransientNodes() {
        let hitPoint = GridPoint(x: 2, y: 2)
        let (scene, view, _) = makeScene()
        defer { view.presentScene(nil) }

        scene.moveKnight(to: hitPoint)
        scene.playDamageEffect()

        XCTAssertGreaterThan(
            scene.transientEffectNodeCountForTesting(),
            0,
            "被ダメージ時は短い赤い反応で HP が減ったことを示す必要があります"
        )
    }

    func testMovementArrowNodesUpdateAndClear() {
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

        XCTAssertEqual(scene.patrolMovementArrowCountForTesting(), 1, "移動方向プレビュー1件につき矢印を1本表示する想定です")

        scene.updatePatrolMovementPreviews([])

        XCTAssertEqual(scene.patrolMovementArrowCountForTesting(), 0, "移動方向プレビューが空になったら古い矢印を消す必要があります")
    }

    func testPatrolRailNodesUpdateAndClearWithoutShowingArrow() {
        let (scene, view, _) = makeScene()
        defer { view.presentScene(nil) }

        scene.updatePatrolRailPreviews([
            ScenePatrolRailPreview(
                enemyID: "patrol",
                path: [
                    GridPoint(x: 1, y: 1),
                    GridPoint(x: 2, y: 1),
                    GridPoint(x: 3, y: 1)
                ]
            )
        ])

        XCTAssertEqual(scene.patrolRailCountForTesting(), 1, "巡回兵1体につきレールを1本表示する想定です")
        XCTAssertEqual(scene.patrolMovementArrowCountForTesting(), 0, "巡回兵の次方向は黄色い別矢印では表示しません")
        guard let railStyle = scene.patrolRailStyleForTesting(enemyID: "patrol") else {
            XCTFail("巡回レールの描画スタイルを取得できません")
            return
        }
        XCTAssertTrue(railStyle.strokeColor.isNeutralGrayForTesting, "巡回レールは黄色ではなく中間グレーで表示します")
        XCTAssertFalse(railStyle.strokeColor.isYellowForTesting, "巡回レールは黄色い次方向矢印とは別の見た目にします")
        XCTAssertGreaterThanOrEqual(railStyle.lineWidth, 2.0, "巡回レールは極端に細くならない太さにします")
        XCTAssertLessThanOrEqual(railStyle.lineWidth, 2.2, "巡回レールは節や点で太く見えない一本線の太さにします")

        scene.updatePatrolRailPreviews([])

        XCTAssertEqual(scene.patrolRailCountForTesting(), 0, "巡回レールが空になったら古いレールを消す必要があります")
        XCTAssertEqual(scene.patrolMovementArrowCountForTesting(), 0, "巡回レールを消しても黄色い別矢印は作られません")
    }

    func testPatrolEnemyMarkerFacingDoesNotCreateYellowArrowNode() {
        let (scene, view, _) = makeScene()
        defer { view.presentScene(nil) }

        scene.updateDungeonEnemyMarkers([
            SceneDungeonEnemyMarker(
                enemyID: "patrol",
                point: GridPoint(x: 1, y: 1),
                kind: .patrol,
                facingVector: MoveVector(dx: 0, dy: 1)
            )
        ])

        XCTAssertEqual(scene.latestDungeonEnemyMarkersForTesting().first?.facingVector, MoveVector(dx: 0, dy: 1))
        XCTAssertEqual(scene.patrolMovementArrowCountForTesting(), 0, "巡回兵の向きは敵アイコン内に持たせ、黄色い別矢印は作りません")
    }

    func testRotatingWatcherMarkerDirectionDoesNotCreateYellowArrowNode() {
        let (scene, view, _) = makeScene()
        defer { view.presentScene(nil) }

        scene.updateDungeonEnemyMarkers([
            SceneDungeonEnemyMarker(
                enemyID: "rotating-watcher",
                point: GridPoint(x: 1, y: 1),
                kind: .rotatingWatcher,
                rotationDirection: .counterclockwise
            )
        ])

        XCTAssertEqual(
            scene.latestDungeonEnemyMarkersForTesting().first?.rotationDirection,
            .counterclockwise
        )
        XCTAssertEqual(scene.patrolMovementArrowCountForTesting(), 0, "回転見張りの回転方向は敵アイコン内に持たせ、黄色い別矢印は作りません")
    }
}

private extension SKColor {
    var isBlackForTesting: Bool {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return false }
        return red <= 0.01 && green <= 0.01 && blue <= 0.01 && alpha >= 0.99
    }

    var isClearForTesting: Bool {
        cgColor.alpha <= 0.01
    }

    var isNeutralGrayForTesting: Bool {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return false }
        return abs(red - green) <= 0.02
            && abs(green - blue) <= 0.02
            && red >= 0.35
            && red <= 0.65
            && alpha >= 0.75
    }

    var isYellowForTesting: Bool {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return false }
        return red >= 0.85 && green >= 0.65 && blue <= 0.35 && alpha >= 0.75
    }

    var alphaComponentForTesting: CGFloat {
        cgColor.alpha
    }

    func matchesComponents(of expected: SKColor, accuracy: CGFloat = 0.001) -> Bool {
        let actualComponents = rgbaComponentsForTesting
        let expectedComponents = expected.rgbaComponentsForTesting
        return zip(actualComponents, expectedComponents).allSatisfy { actual, expected in
            abs(actual - expected) <= accuracy
        }
    }

    private var rgbaComponentsForTesting: [CGFloat] {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return [red, green, blue, alpha]
    }
}
#endif
