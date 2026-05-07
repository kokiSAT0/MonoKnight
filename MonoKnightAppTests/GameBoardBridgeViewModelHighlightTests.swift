import XCTest
@testable import MonoKnightApp
@testable import Game

/// GameBoardBridgeViewModel のハイライト分類ロジックを検証するテスト
/// - Note: UI モジュールの ViewModel は MainActor での実行を前提としているため、各テストにも @MainActor を付与する
@MainActor
final class GameBoardBridgeViewModelHighlightTests: XCTestCase {

    /// 単一候補カードと複数候補カードが個別の集合へ分類されることを確認する
    func testRefreshGuideHighlightsSeparatesSingleAndMultipleCandidates() {
        // 右方向カードをテスト用に複数ベクトルへ差し替え、選択肢が 2 件になる状況を作る
        MoveCard.setTestMovementVectors([
            MoveVector(dx: 1, dy: 0),
            MoveVector(dx: -1, dy: 0)
        ], for: .kingRight)
        defer { MoveCard.setTestMovementVectors(nil, for: .kingRight) }

        let viewModel = makeViewModel()
        let origin = GridPoint(x: 2, y: 2)

        // 上 1 マスの単一ベクトルカードと、左右どちらかに進める複数ベクトルカードを手札として用意する
        let singleStack = HandStack(cards: [DealtCard(move: .kingUp)])
        let multipleStack = HandStack(cards: [DealtCard(move: .kingRight)])

        viewModel.refreshGuideHighlights(
            handOverride: [singleStack, multipleStack],
            currentOverride: origin,
            progressOverride: .playing
        )

        let buckets = viewModel.guideHighlightBuckets
        let expectedSingle: Set<GridPoint> = [GridPoint(x: 2, y: 3)]
        let expectedMultiple: Set<GridPoint> = [GridPoint(x: 3, y: 2), GridPoint(x: 1, y: 2)]

        XCTAssertEqual(buckets.singleVectorDestinations, expectedSingle, "単一候補カードのハイライト座標が想定と一致しません")
        XCTAssertEqual(buckets.multipleVectorDestinations, expectedMultiple, "複数候補カードのハイライト座標が期待通りに分類されていません")
    }

    /// 単一候補と複数候補が同一マスへ重なった場合でも両集合へ残ることを確認する
    func testRefreshGuideHighlightsKeepsOverlappingDestinations() {
        // 複数候補カードに「上1」も含めることで、単一候補カードと同じマスが重なるケースを再現する
        MoveCard.setTestMovementVectors([
            MoveVector(dx: 0, dy: 1),
            MoveVector(dx: 1, dy: 0)
        ], for: .kingRight)
        defer { MoveCard.setTestMovementVectors(nil, for: .kingRight) }

        let viewModel = makeViewModel()
        let origin = GridPoint(x: 2, y: 2)
        let singleDestination = GridPoint(x: 2, y: 3)

        let singleStack = HandStack(cards: [DealtCard(move: .kingUp)])
        let multipleStack = HandStack(cards: [DealtCard(move: .kingRight)])

        viewModel.refreshGuideHighlights(
            handOverride: [singleStack, multipleStack],
            currentOverride: origin,
            progressOverride: .playing
        )

        let buckets = viewModel.guideHighlightBuckets

        XCTAssertTrue(
            buckets.singleVectorDestinations.contains(singleDestination),
            "単一候補集合から重なりマスが欠落しています"
        )
        XCTAssertTrue(
            buckets.multipleVectorDestinations.contains(singleDestination),
            "複数候補集合に重なりマスが含まれておらず、重ね表示が機能しません"
        )
    }

    /// ワープカードが専用の紫ガイド集合へ分類されることを検証する
    func testRefreshGuideHighlightsSeparatesWarpCandidates() {
        let viewModel = makeViewModel()
        let origin = GridPoint(x: 2, y: 2)
        let warpDestination = GridPoint(x: 2, y: 3)

        let warpStack = HandStack(cards: [DealtCard(move: .fixedWarp, fixedWarpDestination: warpDestination)])

        viewModel.refreshGuideHighlights(
            handOverride: [warpStack],
            currentOverride: origin,
            progressOverride: .playing
        )

        let buckets = viewModel.guideHighlightBuckets
        XCTAssertTrue(buckets.warpDestinations.contains(warpDestination), "ワープ専用集合に目的地が含まれていません")
        XCTAssertTrue(buckets.singleVectorDestinations.isEmpty, "ワープカードが単一候補集合へ混入しています")
        XCTAssertTrue(buckets.multipleVectorDestinations.isEmpty, "ワープカードが複数候補集合へ混入しています")
    }

    /// 連続移動カードは移動中に踏むマスの塗りと、タップ可能な終点枠を分けて Scene へ渡すことを検証する
    func testRefreshGuideHighlightsSeparatesMultiStepPathAndDestinationFrame() {
        let viewModel = makeViewModel()
        let origin = GridPoint(x: 1, y: 1)
        let rayStack = HandStack(cards: [DealtCard(move: .rayUpRight)])

        viewModel.refreshGuideHighlights(
            handOverride: [rayStack],
            currentOverride: origin,
            progressOverride: .playing
        )

        let expectedTraversedPoints: Set<GridPoint> = [
            GridPoint(x: 2, y: 2),
            GridPoint(x: 3, y: 3),
            GridPoint(x: 4, y: 4)
        ]
        let expectedDestination: Set<GridPoint> = [
            GridPoint(x: 4, y: 4)
        ]

        XCTAssertEqual(
            viewModel.guideHighlightBuckets.multiStepPathPoints,
            expectedTraversedPoints,
            "連続移動カードの水色塗りには、終点だけでなく途中で踏むマスも含める必要があります"
        )
        XCTAssertEqual(
            viewModel.scene.latestHighlightPoints(for: .guideMultiStepPath),
            expectedTraversedPoints,
            "Scene 側にも連続移動カードの通過マス全体を塗りとして渡す必要があります"
        )
        XCTAssertEqual(
            viewModel.guideHighlightBuckets.multiStepDestinations,
            expectedDestination,
            "連続移動カードの水色枠は、タップ可能な終点だけに出す必要があります"
        )
        XCTAssertEqual(
            viewModel.scene.latestHighlightPoints(for: .guideMultiStepCandidate),
            expectedDestination,
            "Scene 側にも連続移動カードの終点だけを枠として渡す必要があります"
        )
        XCTAssertTrue(
            viewModel.guideHighlightBuckets.singleVectorDestinations.isEmpty,
            "連続移動カードが単一候補集合へ混入しています"
        )
        XCTAssertTrue(
            viewModel.guideHighlightBuckets.multipleVectorDestinations.isEmpty,
            "連続移動カードが複数候補集合へ混入しています"
        )
    }

    /// 強制ハイライトが障害物マスを除外することを検証する
    func testForcedSelectionHighlightsExcludeImpassableTiles() {
        // --- 移動不可マスを含むモードを構築し、ViewModel に適用 ---
        let impassablePoint = GridPoint(x: 3, y: 2)
        let regulation = GameMode.Regulation(
            boardSize: BoardGeometry.standardSize,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standard,
            spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: BoardGeometry.standardSize)),
            penalties: GameMode.PenaltySettings(
                deadlockPenaltyCost: 3,
                manualRedrawPenaltyCost: 2,
                manualDiscardPenaltyCost: 1,
                revisitPenaltyCost: 0
            ),
            impassableTilePoints: [impassablePoint]
        )
        let mode = GameMode(
            identifier: .dungeonFloor,
            displayName: "ハイライト障害物テスト",
            regulation: regulation,
            leaderboardEligible: false
        )
        let core = GameCore(mode: mode)
        let viewModel = GameBoardBridgeViewModel(core: core, mode: mode)

        // --- 駒の現在地から右隣（障害物）を強制ハイライトへ指定 ---
        let origin = GridPoint(x: 2, y: 2)
        let movement = MoveVector(dx: 1, dy: 0)
        viewModel.updateForcedSelectionHighlights([], origin: origin, movementVectors: [movement])

        XCTAssertFalse(
            viewModel.forcedSelectionHighlightPoints.contains(impassablePoint),
            "移動不可マスが強制ハイライトへ含まれており、障害物を示唆してしまいます"
        )
        XCTAssertTrue(
            viewModel.forcedSelectionHighlightPoints.isEmpty,
            "有効マスが存在しない場合は空集合で保持する想定です"
        )
    }

    func testDungeonHighlightsExposeExitEnemyDangerAndHazards() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let floor = try XCTUnwrap(tower.floors.first { $0.id == "tutorial-3" })
        let mode = floor.makeGameMode(dungeonID: tower.id)
        let core = GameCore(mode: mode)
        let viewModel = GameBoardBridgeViewModel(core: core, mode: mode)

        XCTAssertEqual(
            viewModel.scene.latestHighlightPoints(for: .dungeonExit),
            [floor.exitPoint],
            "ダンジョン出口を Scene へ渡す必要があります"
        )
        XCTAssertEqual(
            viewModel.scene.latestHighlightPoints(for: .dungeonEnemy),
            Set(floor.enemies.map(\.position)),
            "敵位置を Scene へ渡す必要があります"
        )
        XCTAssertEqual(
            viewModel.scene.latestHighlightPoints(for: .dungeonDanger),
            core.enemyDangerPoints,
            "危険範囲表示は GameCore の判定集合と一致させます"
        )
        XCTAssertEqual(
            viewModel.scene.latestHighlightPoints(for: .dungeonCardPickup),
            Set(floor.cardPickups.map(\.point)),
            "床落ちカードも専用ハイライトとして Scene へ渡します"
        )

        let trapTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "trap-tower"))
        let trapFloor = try XCTUnwrap(trapTower.floors.first)
        let trapMode = trapFloor.makeGameMode(dungeonID: trapTower.id)
        let trapCore = GameCore(mode: trapMode)
        let trapViewModel = GameBoardBridgeViewModel(core: trapCore, mode: trapMode)

        XCTAssertEqual(
            trapViewModel.scene.latestHighlightPoints(for: .dungeonDamageTrap),
            trapCore.damageTrapPoints,
            "見えているダメージ罠を専用ハイライトとして Scene へ渡します"
        )

        let growthTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let lockedFloor = try XCTUnwrap(growthTower.floors.first { $0.exitLock != nil })
        let lockedMode = lockedFloor.makeGameMode(dungeonID: growthTower.id)
        let lockedCore = GameCore(mode: lockedMode)
        let lockedViewModel = GameBoardBridgeViewModel(core: lockedCore, mode: lockedMode)
        let unlockPoint = try XCTUnwrap(lockedFloor.exitLock?.unlockPoint)

        XCTAssertEqual(
            lockedViewModel.scene.latestHighlightPoints(for: .dungeonKey),
            [unlockPoint],
            "未取得の塔鍵を専用ハイライトとして Scene へ渡します"
        )

        core.overrideDungeonFloorStateForTesting(
            cracked: [GridPoint(x: 1, y: 2)],
            collapsed: [GridPoint(x: 2, y: 2)]
        )
        viewModel.refreshGuideHighlights()

        XCTAssertEqual(
            viewModel.scene.latestHighlightPoints(for: .dungeonCrackedFloor),
            [GridPoint(x: 1, y: 2)]
        )
        XCTAssertEqual(
            viewModel.scene.latestHighlightPoints(for: .dungeonCollapsedFloor),
            [GridPoint(x: 2, y: 2)]
        )
    }

    func testDungeonKeyHighlightDisappearsAfterUnlock() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let floor = try XCTUnwrap(tower.floors.first { $0.id == "growth-9" })
        let unlockPoint = try XCTUnwrap(floor.exitLock?.unlockPoint)
        let mode = floor.makeGameMode(dungeonID: tower.id)
        let core = GameCore(mode: mode)
        let viewModel = GameBoardBridgeViewModel(core: core, mode: mode)

        XCTAssertEqual(viewModel.scene.latestHighlightPoints(for: .dungeonKey), [unlockPoint])
        XCTAssertEqual(viewModel.scene.latestHighlightPoints(for: .dungeonExitLocked), [floor.exitPoint])

        for destination in [
            GridPoint(x: 0, y: 1),
            GridPoint(x: 1, y: 1),
            unlockPoint
        ] {
            guard let move = core.availableBasicOrthogonalMoves().first(where: { $0.destination == destination }) else {
                XCTFail("基本移動候補が見つかりません: \(destination)")
                return
            }
            core.playBasicOrthogonalMove(using: move)
        }
        viewModel.refreshGuideHighlights()

        XCTAssertTrue(core.isDungeonExitUnlocked)
        XCTAssertTrue(viewModel.scene.latestHighlightPoints(for: .dungeonKey).isEmpty)
        XCTAssertEqual(viewModel.scene.latestHighlightPoints(for: .dungeonExit), [floor.exitPoint])
        XCTAssertTrue(viewModel.scene.latestHighlightPoints(for: .dungeonExitLocked).isEmpty)
    }

    func testDungeonPatrolMovementPreviewsArePassedToScene() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "patrol-tower"))
        let floor = tower.floors[0]
        let mode = floor.makeGameMode(dungeonID: tower.id)
        let core = GameCore(mode: mode)
        let viewModel = GameBoardBridgeViewModel(core: core, mode: mode)

        XCTAssertEqual(viewModel.boardSize, 9)
        XCTAssertEqual(
            viewModel.scene.latestPatrolMovementPreviewsForTesting(),
            core.enemyPatrolMovementPreviews.map(ScenePatrolMovementPreview.init),
            "巡回兵の次移動プレビューを Scene へ渡す必要があります"
        )

        guard let basicMove = core.availableBasicOrthogonalMoves().first(where: { $0.destination == GridPoint(x: 1, y: 0) }) else {
            XCTFail("基本移動候補が見つかりません")
            return
        }
        core.playBasicOrthogonalMove(using: basicMove)
        viewModel.refreshGuideHighlights()

        XCTAssertEqual(
            viewModel.scene.latestPatrolMovementPreviewsForTesting(),
            core.enemyPatrolMovementPreviews.map(ScenePatrolMovementPreview.init),
            "敵ターン後も古い巡回プレビューを残さず更新する必要があります"
        )
    }

    func testDungeonRotatingWatcherDirectionPreviewsArePassedToScene() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let floor = tower.floors[6]
        let mode = floor.makeGameMode(dungeonID: tower.id)
        let core = GameCore(mode: mode)
        let viewModel = GameBoardBridgeViewModel(core: core, mode: mode)

        let rotatingWatcherPreviews = core.enemyRotatingWatcherDirectionPreviews.map(ScenePatrolMovementPreview.init)
        let expectedPreviews = (
            core.enemyPatrolMovementPreviews.map(ScenePatrolMovementPreview.init)
            + core.enemyChaserMovementPreviews.map(ScenePatrolMovementPreview.init)
            + rotatingWatcherPreviews
        )
        XCTAssertFalse(rotatingWatcherPreviews.isEmpty, "成長塔7Fには回転見張りの次方向プレビューが必要です")
        XCTAssertEqual(
            viewModel.scene.latestPatrolMovementPreviewsForTesting(),
            expectedPreviews,
            "回転見張りの次方向を Scene の軽量矢印へ渡す必要があります"
        )
    }

    func testDungeonChaserMovementPreviewsArePassedToScene() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let floor = tower.floors[6]
        let mode = floor.makeGameMode(dungeonID: tower.id)
        let core = GameCore(mode: mode)
        let viewModel = GameBoardBridgeViewModel(core: core, mode: mode)

        let chaserPreviews = core.enemyChaserMovementPreviews.map(ScenePatrolMovementPreview.init)
        let expectedPreviews = (
            core.enemyPatrolMovementPreviews.map(ScenePatrolMovementPreview.init)
            + chaserPreviews
            + core.enemyRotatingWatcherDirectionPreviews.map(ScenePatrolMovementPreview.init)
        )
        XCTAssertFalse(chaserPreviews.isEmpty, "成長塔7Fには追跡兵の次移動プレビューが必要です")
        XCTAssertEqual(
            viewModel.scene.latestPatrolMovementPreviewsForTesting(),
            expectedPreviews,
            "追跡兵の次移動先を Scene の軽量矢印へ渡す必要があります"
        )
    }

    func testDungeonInitialRewardCardGuideIsAvailableWithoutManualRefresh() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let runState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 1,
            carriedHP: 2,
            totalMoveCount: 4,
            clearedFloorCount: 1,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .straightRight2, rewardUses: 3)]
        )
        let floor = tower.floors[1]
        let mode = floor.makeGameMode(
            dungeonID: tower.id,
            carriedHP: runState.carriedHP,
            runState: runState
        )
        let core = GameCore(mode: mode)
        let viewModel = GameBoardBridgeViewModel(core: core, mode: mode)

        XCTAssertTrue(core.availableMoves().contains { $0.moveCard == .straightRight2 && $0.destination == GridPoint(x: 2, y: 0) })
        XCTAssertTrue(
            viewModel.scene.latestHighlightPoints(for: .guideSingleCandidate).contains(GridPoint(x: 2, y: 0)),
            "初期化直後から報酬カードの候補を盤面へ渡す必要があります"
        )
    }

    func testDungeonBasicMoveHighlightsAreSeparateFromCardCandidates() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let floor = try XCTUnwrap(tower.floors.first)
        let mode = floor.makeGameMode(dungeonID: tower.id)
        let core = GameCore(mode: mode)
        let viewModel = GameBoardBridgeViewModel(core: core, mode: mode)

        viewModel.refreshGuideHighlights(progressOverride: .playing)

        let expectedBasicMoves = Set(core.availableBasicOrthogonalMoves().map(\.destination))
        XCTAssertFalse(expectedBasicMoves.isEmpty, "基礎塔では基本移動候補が必要です")
        XCTAssertEqual(
            viewModel.guideHighlightBuckets.basicMoveDestinations,
            expectedBasicMoves,
            "基本移動候補はカード候補とは別集合で保持します"
        )
        XCTAssertEqual(
            viewModel.scene.latestHighlightPoints(for: .dungeonBasicMove),
            expectedBasicMoves,
            "Scene 側にも基本移動候補を専用ハイライトとして渡します"
        )

        viewModel.updateForcedSelectionHighlights([floor.exitPoint])
        XCTAssertTrue(
            viewModel.scene.latestHighlightPoints(for: .dungeonBasicMove).isEmpty,
            "カード選択中は基本移動候補を隠し、選択カードの候補を優先します"
        )
    }

    func testKeyDoorTowerOpenGateAndDoorStateArePassedToScene() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "key-door-tower"))
        let floor = try XCTUnwrap(tower.floors.first)
        let mode = floor.makeGameMode(dungeonID: tower.id)
        let core = GameCore(mode: mode)
        let viewModel = GameBoardBridgeViewModel(core: core, mode: mode)

        let keyPoint = GridPoint(x: 2, y: 6)
        let doorPoint = GridPoint(x: 4, y: 4)

        XCTAssertEqual(viewModel.boardSize, 9)
        XCTAssertEqual(mode.tileEffects[keyPoint], .openGate(target: doorPoint))
        XCTAssertTrue(core.board.isImpassable(doorPoint))
        XCTAssertTrue(
            viewModel.scene.boardIsImpassableForTesting(at: doorPoint),
            "鍵扉塔の扉マスも Scene の盤面へ渡す必要があります"
        )

        viewModel.refreshGuideHighlights(progressOverride: .playing)
        XCTAssertEqual(
            viewModel.scene.latestHighlightPoints(for: .dungeonBasicMove),
            Set(core.availableBasicOrthogonalMoves().map(\.destination)),
            "鍵扉塔でも基本移動候補を Scene へ渡します"
        )
    }

    /// テストで使い回す ViewModel を生成するヘルパー
    private func makeViewModel() -> GameBoardBridgeViewModel {
        let tower = DungeonLibrary.shared.dungeon(with: "tutorial-tower")!
        let mode = DungeonLibrary.shared.firstFloorMode(for: tower)!
        let core = GameCore(mode: mode)
        return GameBoardBridgeViewModel(core: core, mode: mode)
    }
}
