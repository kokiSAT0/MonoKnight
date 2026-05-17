#if canImport(SpriteKit) && canImport(UIKit)
import Foundation
import SpriteKit
import UIKit
import XCTest
@testable import Game
@testable import MonoKnightApp

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

    private static func gameScenePalette(for theme: AppTheme) -> GameScenePalette {
        GameScenePalette(
            boardBackground: theme.skBoardBackground,
            boardGridLine: theme.skBoardGridLine,
            isNeonGridTheme: theme.visualStyle == .starChartSurveyTower,
            boardStarChartLine: theme.skBoardStarChartLine,
            boardStarChartNode: theme.skBoardStarChartNode,
            boardConstellationLine: theme.skBoardConstellationLine,
            boardConstellationGlowLine: theme.skBoardConstellationGlowLine,
            boardConstellationStar: theme.skBoardConstellationStar,
            boardConstellationStarGlow: theme.skBoardConstellationStarGlow,
            boardStarParticle: theme.skBoardStarParticle,
            boardNebulaDepth: theme.skBoardNebulaDepth,
            boardDistantStar: theme.skBoardDistantStar,
            boardDistantStarTwinkle: theme.skBoardDistantStarTwinkle,
            boardGlassHighlight: theme.skBoardGlassHighlight,
            boardTileInnerGlow: theme.skBoardTileInnerGlow,
            boardAstralCore: theme.skBoardAstralCore,
            boardAstralCoreRing: theme.skBoardAstralCoreRing,
            boardAstralCoreGlow: theme.skBoardAstralCoreGlow,
            boardAstralCorePulse: theme.skBoardAstralCorePulse,
            boardTileVisited: theme.skBoardTileVisited,
            boardTileUnvisited: theme.skBoardTileUnvisited,
            boardDarknessHiddenTile: theme.skBoardDarknessHiddenTile,
            boardDarknessBoundary: theme.skBoardDarknessBoundary,
            boardTileMultiBase: theme.skBoardTileMultiBase,
            boardTileMultiStroke: theme.skBoardTileMultiStroke,
            boardTileToggle: theme.skBoardTileToggle,
            boardTileImpassable: theme.skBoardTileImpassable,
            boardKnight: theme.skBoardKnight,
            boardGuideHighlight: theme.skBoardGuideHighlight,
            boardMultiStepHighlight: theme.skBoardMultiStepHighlight,
            boardWarpHighlight: theme.skBoardWarpHighlight,
            boardTileEffectWarp: theme.skBoardTileEffectWarp,
            boardTileEffectShuffle: theme.skBoardTileEffectShuffle,
            boardTileEffectBlast: theme.skBoardTileEffectBlast,
            boardTileEffectSlow: theme.skBoardTileEffectSlow,
            boardTileEffectSwamp: theme.skBoardTileEffectSwamp,
            boardTileEffectPreserveCard: theme.skBoardTileEffectPreserveCard,
            boardTileEffectDiscardHand: theme.skBoardTileEffectDiscardHand,
            boardDungeonEnemy: theme.skBoardDungeonEnemy,
            boardDungeonDanger: theme.skBoardDungeonDanger,
            boardDungeonWarning: theme.skBoardDungeonWarning,
            boardDungeonCardPickup: theme.skBoardDungeonCardPickup,
            boardDungeonRelicPickup: theme.skBoardDungeonRelicPickup,
            boardDungeonSuspiciousRelicPickup: theme.skBoardDungeonSuspiciousRelicPickup,
            boardDungeonDamageTrap: theme.skBoardDungeonDamageTrap,
            boardDungeonHpHalvingTrap: theme.skBoardDungeonHpHalvingTrap,
            boardDungeonLavaTile: theme.skBoardDungeonLavaTile,
            boardDungeonHealingTile: theme.skBoardDungeonHealingTile,
            boardDungeonKey: theme.skBoardDungeonKey,
            warpPairAccentColors: theme.skWarpPairAccentColors
        )
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
        let (scene, view, boardSize) = makeScene(impassablePoints: impassablePoints)
        defer { view.presentScene(nil) }

        XCTAssertEqual(scene.impassableMarkerCountForTesting(), impassablePoints.count)
        XCTAssertEqual(scene.impassableVeinMarkerCountForTesting(), impassablePoints.count, "障害物は岩/柱として読める内部線を持ちます")
        XCTAssertEqual(scene.stoneFloorTextureCountForTesting(), boardSize * boardSize - impassablePoints.count, "通常床だけに薄い石床ディテールを重ねます")
    }

    /// 通常床に薄い石床ディテールを重ね、平坦な盤面になりすぎないことを確認する
    func testVisibleFloorTilesShowStoneTexture() {
        let (scene, view, boardSize) = makeScene()
        defer { view.presentScene(nil) }

        XCTAssertEqual(scene.stoneFloorTextureCountForTesting(), boardSize * boardSize)
    }

    /// ネオングリッドテーマでは通常床を塗りとグリッド中心に留め、意味ありそうな盤面全体装飾を出さないことを確認する
    func testStarChartSurveyTowerThemeAddsSurveyTexture() {
        let (scene, view, _) = makeScene()
        defer { view.presentScene(nil) }

        XCTAssertEqual(scene.starChartTextureCountForTesting(), 0)
        XCTAssertEqual(scene.glassTileHighlightCountForTesting(), 0)
        XCTAssertEqual(scene.tileInnerGlowCountForTesting(), 0)
        XCTAssertEqual(scene.cosmicBackgroundNodeCountForTesting(), 0)
        XCTAssertEqual(scene.distantStarNodeCountForTesting(), 0)
        XCTAssertEqual(scene.twinklingDistantStarNodeCountForTesting(), 0)
        XCTAssertEqual(scene.constellationLayerNodeCountForTesting(), 0)
        XCTAssertEqual(scene.constellationGlowNodeCountForTesting(), 0)
        XCTAssertEqual(scene.astralCoreNodeCountForTesting(), 0)
        XCTAssertEqual(scene.surveyCompassRingCountForTesting(), 0)
        scene.applyTheme(Self.gameScenePalette(for: AppTheme(colorScheme: .dark, visualStyle: .starChartSurveyTower)))
        XCTAssertEqual(scene.starChartTextureCountForTesting(), 0, "ネオングリッドテーマでは通常床に移動ガイド枠と競合するARパネル角を重ねません")
        XCTAssertEqual(scene.glassTileHighlightCountForTesting(), 0, "ネオングリッドテーマでは通常床に左上光沢のようなAR面差を重ねません")
        XCTAssertEqual(scene.tileInnerGlowCountForTesting(), 0, "ネオングリッドテーマでは通常床に移動ガイド枠と競合する内側四角枠を出しません")
        XCTAssertEqual(scene.cosmicBackgroundNodeCountForTesting(), 0, "ネオングリッドテーマでは宇宙背景レイヤーを生成しません")
        XCTAssertEqual(scene.distantStarNodeCountForTesting(), 0, "ネオングリッドテーマでは遠景星粒を生成しません")
        XCTAssertEqual(scene.twinklingDistantStarNodeCountForTesting(), 0, "ネオングリッドテーマでは星粒の微アニメを生成しません")
        XCTAssertEqual(scene.constellationLayerNodeCountForTesting(), 0, "ネオングリッドテーマでは盤面全体の測量線レイヤーを生成しません")
        XCTAssertEqual(scene.constellationGlowNodeCountForTesting(), 0, "ネオングリッドテーマでは星座線や鋲の金属影を生成しません")
        XCTAssertEqual(scene.surveyCompassRingCountForTesting(), 0, "ネオングリッドテーマでは盤面全体に方位環を生成しません")
        XCTAssertEqual(scene.astralCoreNodeCountForTesting(), 0, "ネオングリッドテーマでは盤面中央に方位鋲を生成しません")

        scene.updateDungeonVisiblePoints([GridPoint(x: 0, y: 0)])
        XCTAssertEqual(scene.constellationLayerNodeCountForTesting(), 0, "暗闇フロアでは盤面全体の測量線レイヤーより暗闇表示を優先します")
        XCTAssertEqual(scene.surveyCompassRingCountForTesting(), 0, "暗闇フロアでは方位環より暗闇表示を優先します")
        XCTAssertEqual(scene.astralCoreNodeCountForTesting(), 0, "暗闇フロアでは方位鋲より暗闇表示を優先します")
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
        let relicPoint = GridPoint(x: 4, y: 2)
        let suspiciousRelicPoint = GridPoint(x: 0, y: 2)
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
            .dungeonRelicPickup: [relicPoint],
            .dungeonSuspiciousRelicPickup: [suspiciousRelicPoint],
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
        guard let relicStyle = scene.highlightStyleForTesting(
            kind: .dungeonRelicPickup,
            at: relicPoint
        ), let suspiciousRelicStyle = scene.highlightStyleForTesting(
            kind: .dungeonSuspiciousRelicPickup,
            at: suspiciousRelicPoint
        ) else {
            XCTFail("宝箱マーカーのノードを取得できません")
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
        ), let relicBounds = scene.highlightPathBoundsForTesting(
            kind: .dungeonRelicPickup,
            at: relicPoint
        ), let suspiciousRelicBounds = scene.highlightPathBoundsForTesting(
            kind: .dungeonSuspiciousRelicPickup,
            at: suspiciousRelicPoint
        ) else {
            XCTFail("基本移動、カード移動、拾得物、ダメージ罠のマーカーサイズを取得できません")
            return
        }
        guard let damageTrapElementCount = scene.highlightPathElementCountForTesting(
            kind: .dungeonDamageTrap,
            at: damageTrapPoint
        ), let relicElementCount = scene.highlightPathElementCountForTesting(
            kind: .dungeonRelicPickup,
            at: relicPoint
        ), let suspiciousRelicElementCount = scene.highlightPathElementCountForTesting(
            kind: .dungeonSuspiciousRelicPickup,
            at: suspiciousRelicPoint
        ) else {
            XCTFail("宝箱/ダメージ罠のマーカーパスを取得できません")
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
        XCTAssertGreaterThan(relicStyle.lineWidth, 0, "宝箱は発光アウトラインを持つ補給コンテナとして示します")
        XCTAssertFalse(relicStyle.fillColor.isEqual(SKColor.clear), "宝箱は取得前に見える塗りを持ちます")
        XCTAssertGreaterThan(relicBounds.width, cardMoveBounds.width * 0.45, "宝箱は小さな点ではなく横長の補給コンテナとして示します")
        XCTAssertGreaterThan(suspiciousRelicStyle.lineWidth, relicStyle.lineWidth, "怪しい宝箱は通常宝箱より強い警告アウトラインを持ちます")
        XCTAssertGreaterThan(suspiciousRelicElementCount, relicElementCount, "怪しい宝箱は通常宝箱に警告差分を追加した別形状にします")
        XCTAssertEqual(suspiciousRelicBounds.width, relicBounds.width, accuracy: cardMoveBounds.width * 0.15, "怪しい宝箱は通常宝箱と同系統の大きさを保ちます")
        XCTAssertEqual(damageTrapStyle.lineWidth, 0, "ダメージ罠は移動可能枠ではないためタイル枠を持ちません")
        XCTAssertFalse(damageTrapStyle.fillColor.isEqual(SKColor.clear), "ダメージ罠は踏む前に見える塗りを持ちます")
        XCTAssertGreaterThan(damageTrapBounds.width, cardMoveBounds.width * 0.45, "ダメージ罠は小さな点ではなく横幅のある棘マーカーで示します")
        XCTAssertGreaterThan(damageTrapBounds.height, cardMoveBounds.height * 0.45, "ダメージ罠は踏むと危険だと読める高さのある棘マーカーで示します")
        XCTAssertGreaterThan(damageTrapElementCount, 7, "ダメージ罠は単一三角ではなく複数の棘を持つパスで示します")
        XCTAssertEqual(keyStyle.lineWidth, 0, "塔鍵は移動可能枠ではなく、枠なしの小マーカーで示します")
        XCTAssertFalse(keyStyle.fillColor.isEqual(SKColor.clear), "塔鍵は取得前に見える塗りを持ちます")
        XCTAssertGreaterThan(crackedFloorStyle.lineWidth, 0, "ひび割れ床はタイル枠ではなく亀裂線で示します")
        XCTAssertGreaterThan(collapsedFloorStyle.lineWidth, 0, "崩落床は黒い穴に明るい縁取りを付け、ひび割れ床と形でも線でも区別します")
        XCTAssertFalse(collapsedFloorStyle.fillColor.isEqual(SKColor.clear), "崩落床は即落ち穴として読める塗りを持ちます")
    }

    func testStarChartSurveyTowerThemeKeepsDungeonMarkerSemantics() {
        let basicMovePoint = GridPoint(x: 1, y: 1)
        let singleMovePoint = GridPoint(x: 1, y: 2)
        let directTwoStepPoint = GridPoint(x: 1, y: 3)
        let damageTrapPoint = GridPoint(x: 2, y: 2)
        let keyPoint = GridPoint(x: 3, y: 2)
        let cardPoint = GridPoint(x: 4, y: 2)
        let healingPoint = GridPoint(x: 2, y: 3)
        let warningPoint = GridPoint(x: 3, y: 3)
        let (scene, view, _) = makeScene()
        defer { view.presentScene(nil) }

        scene.applyTheme(Self.gameScenePalette(for: AppTheme(colorScheme: .dark, visualStyle: .starChartSurveyTower)))
        scene.updateHighlights([
            .dungeonBasicMove: [basicMovePoint],
            .guideSingleCandidate: [singleMovePoint],
            .guideDirectTwoStepCandidate: [directTwoStepPoint],
            .dungeonDamageTrap: [damageTrapPoint],
            .dungeonKey: [keyPoint],
            .dungeonCardPickup: [cardPoint],
            .dungeonHealingTile: [healingPoint],
            .dungeonEnemyWarning: [warningPoint],
        ])

        guard let basicMoveStyle = scene.highlightStyleForTesting(kind: .dungeonBasicMove, at: basicMovePoint),
              let singleMoveStyle = scene.highlightStyleForTesting(kind: .guideSingleCandidate, at: singleMovePoint),
              let directTwoStepStyle = scene.highlightStyleForTesting(kind: .guideDirectTwoStepCandidate, at: directTwoStepPoint),
              let damageTrapStyle = scene.highlightStyleForTesting(kind: .dungeonDamageTrap, at: damageTrapPoint),
              let keyStyle = scene.highlightStyleForTesting(kind: .dungeonKey, at: keyPoint),
              let cardStyle = scene.highlightStyleForTesting(kind: .dungeonCardPickup, at: cardPoint),
              let healingStyle = scene.highlightStyleForTesting(kind: .dungeonHealingTile, at: healingPoint),
              let warningStyle = scene.highlightStyleForTesting(kind: .dungeonEnemyWarning, at: warningPoint)
        else {
            XCTFail("ネオングリッドテーマの主要ハイライトを取得できません")
            return
        }

        XCTAssertGreaterThan(basicMoveStyle.lineWidth, 0, "新テーマでも移動可能マスは枠で示します")
        XCTAssertGreaterThan(basicMoveStyle.glowWidth, 0, "新テーマの移動枠は淡いネオン輪郭を持ちます")
        XCTAssertGreaterThan(directTwoStepStyle.lineWidth, singleMoveStyle.lineWidth, "新テーマの2マス直接移動は通常単方向より強い枠で示します")
        XCTAssertGreaterThan(directTwoStepStyle.glowWidth, singleMoveStyle.glowWidth, "新テーマの2マス直接移動は通常単方向より強い発光を持ちます")
        XCTAssertTrue(directTwoStepStyle.fillColor.isClearForTesting, "2マス直接移動はレイ通過塗りではなく到達先枠として示します")
        XCTAssertEqual(damageTrapStyle.lineWidth, 0, "新テーマでも罠はタップ可能枠に見せません")
        XCTAssertFalse(damageTrapStyle.fillColor.isEqual(SKColor.clear), "新テーマでも罠は踏む前に見える塗りを持ちます")
        XCTAssertEqual(keyStyle.lineWidth, 0, "鍵は枠ではなくピクト中心で示します")
        XCTAssertEqual(cardStyle.lineWidth, 0, "カード拾得物は枠ではなくピクト中心で示します")
        XCTAssertEqual(healingStyle.lineWidth, 0, "回復マスは枠ではなくピクト中心で示します")
        XCTAssertGreaterThan(warningStyle.lineWidth, 0, "敵警告は警告ピクトとして線を持ちます")
        XCTAssertGreaterThan(warningStyle.glowWidth, 0, "敵警告は明るい盤面上で読める発光輪郭を持ちます")
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

    func testWatcherLaserNodesUpdateClearAndStartFromEnemyTile() {
        let (scene, view, _) = makeScene()
        defer { view.presentScene(nil) }

        scene.applyTheme(Self.gameScenePalette(for: AppTheme(colorScheme: .dark, visualStyle: .starChartSurveyTower)))
        scene.updateWatcherLaserPreviews([
            SceneWatcherLaserPreview(
                enemyID: "watcher",
                origin: GridPoint(x: 1, y: 1),
                direction: MoveVector(dx: 1, dy: 0),
                dangerPoints: [GridPoint(x: 2, y: 1), GridPoint(x: 3, y: 1)]
            )
        ])

        XCTAssertEqual(scene.watcherLaserCountForTesting(), 1, "見張り1体につきレーザーを1本表示します")
        XCTAssertEqual(scene.latestWatcherLaserPreviewsForTesting().first?.origin, GridPoint(x: 1, y: 1))
        guard let laserStyle = scene.watcherLaserStyleForTesting(enemyID: "watcher") else {
            XCTFail("見張りレーザーの描画スタイルを取得できません")
            return
        }
        XCTAssertGreaterThan(laserStyle.lineWidth, 2.8, "レーザーは細すぎない発光線で表示します")
        XCTAssertGreaterThan(laserStyle.glowWidth, 1.8, "ネオン調の読みやすい発光を持たせます")
        XCTAssertGreaterThan(
            laserStyle.bounds.width,
            scene.tileSizeForTesting() * 1.8,
            "レーザーのパスは最初の危険マスだけでなく敵マス側から伸ばします"
        )

        scene.updateWatcherLaserPreviews([])

        XCTAssertEqual(scene.watcherLaserCountForTesting(), 0, "レーザーが空になったら古い線を消す必要があります")
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

    func testDungeonEnemyMarkerColorUsesDamageWhileKeepingShapeKind() {
        let (scene, view, _) = makeScene()
        defer { view.presentScene(nil) }

        scene.updateDungeonEnemyMarkers([
            SceneDungeonEnemyMarker(
                enemyID: "damage-one",
                point: GridPoint(x: 1, y: 1),
                kind: .patrol,
                damage: 1
            ),
            SceneDungeonEnemyMarker(
                enemyID: "damage-two",
                point: GridPoint(x: 2, y: 1),
                kind: .patrol,
                damage: 2
            ),
            SceneDungeonEnemyMarker(
                enemyID: "damage-three",
                point: GridPoint(x: 3, y: 1),
                kind: .patrol,
                damage: 3
            )
        ])

        let markers = scene.latestDungeonEnemyMarkersForTesting()
        XCTAssertEqual(markers.map(\.kind), [.patrol, .patrol, .patrol])
        XCTAssertEqual(markers.map(\.damage), [1, 2, 3])

        let damageOneStyle = scene.dungeonEnemyMarkerStyleForTesting(enemyID: "damage-one")
        let damageTwoStyle = scene.dungeonEnemyMarkerStyleForTesting(enemyID: "damage-two")
        let damageThreeStyle = scene.dungeonEnemyMarkerStyleForTesting(enemyID: "damage-three")

        XCTAssertNotNil(damageOneStyle)
        XCTAssertNotNil(damageTwoStyle)
        XCTAssertNotNil(damageThreeStyle)
        XCTAssertFalse(damageTwoStyle?.strokeColor.matchesComponents(of: damageOneStyle?.strokeColor ?? .clear) ?? true)
        XCTAssertFalse(damageThreeStyle?.strokeColor.matchesComponents(of: damageTwoStyle?.strokeColor ?? .clear) ?? true)
        XCTAssertTrue(damageThreeStyle?.strokeColor.isStrongerEnemyRedForTesting == true)
    }

    func testStrongerHazardMarkersUseColorOnlyAndKeepShape() throws {
        let trapPoint = GridPoint(x: 1, y: 1)
        let strongTrapPoint = GridPoint(x: 2, y: 1)
        let lavaPoint = GridPoint(x: 1, y: 2)
        let strongLavaPoint = GridPoint(x: 2, y: 2)
        let (scene, view, _) = makeScene()
        defer { view.presentScene(nil) }

        scene.updateHighlights([
            .dungeonDamageTrap: [trapPoint],
            .dungeonStrongDamageTrap: [strongTrapPoint],
            .dungeonLavaTile: [lavaPoint],
            .dungeonStrongLavaTile: [strongLavaPoint],
        ])

        let trapStyle = try XCTUnwrap(scene.highlightStyleForTesting(kind: .dungeonDamageTrap, at: trapPoint))
        let strongTrapStyle = try XCTUnwrap(scene.highlightStyleForTesting(kind: .dungeonStrongDamageTrap, at: strongTrapPoint))
        let lavaStyle = try XCTUnwrap(scene.highlightStyleForTesting(kind: .dungeonLavaTile, at: lavaPoint))
        let strongLavaStyle = try XCTUnwrap(scene.highlightStyleForTesting(kind: .dungeonStrongLavaTile, at: strongLavaPoint))

        XCTAssertGreaterThan(strongTrapStyle.glowWidth, trapStyle.glowWidth)
        XCTAssertGreaterThan(strongLavaStyle.lineWidth, lavaStyle.lineWidth)
        XCTAssertGreaterThan(strongLavaStyle.glowWidth, lavaStyle.glowWidth)

        XCTAssertEqual(
            scene.highlightPathElementCountForTesting(kind: .dungeonDamageTrap, at: trapPoint),
            scene.highlightPathElementCountForTesting(kind: .dungeonStrongDamageTrap, at: strongTrapPoint)
        )
        XCTAssertEqual(
            scene.highlightPathElementCountForTesting(kind: .dungeonLavaTile, at: lavaPoint),
            scene.highlightPathElementCountForTesting(kind: .dungeonStrongLavaTile, at: strongLavaPoint)
        )
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

    var isStrongerEnemyRedForTesting: Bool {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return false }
        return red >= 0.85 && green <= 0.20 && blue <= 0.35 && alpha >= 0.90
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
