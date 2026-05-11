import XCTest
@testable import MonoKnightApp
@testable import Game

/// GameBoardBridgeViewModel のハイライト分類ロジックを検証するテスト
/// - Note: UI モジュールの ViewModel は MainActor での実行を前提としているため、各テストにも @MainActor を付与する
@MainActor
final class GameBoardBridgeViewModelHighlightTests: XCTestCase {

    func testSceneRecordsMultiStepMovementPathForReplay() {
        let scene = GameScene(initialBoardSize: 5, initialVisitedPoints: [GridPoint(x: 0, y: 0)])
        let resolution = MovementResolution(
            path: [
                GridPoint(x: 1, y: 0),
                GridPoint(x: 2, y: 0),
                GridPoint(x: 3, y: 0)
            ],
            finalPosition: GridPoint(x: 3, y: 0)
        )

        scene.playMovementTransition(using: resolution)

        XCTAssertEqual(
            scene.latestMovementPathForTesting,
            resolution.path,
            "ワープなしの複数マス移動も、最終地点への一括移動ではなく経路を Scene に渡す想定です"
        )
    }

    func testSceneUsesReadableTimingForMultiStepMovementReplay() {
        let scene = GameScene(initialBoardSize: 5, initialVisitedPoints: [GridPoint(x: 0, y: 0)])
        let resolution = MovementResolution(
            path: [
                GridPoint(x: 1, y: 0),
                GridPoint(x: 2, y: 0),
                GridPoint(x: 3, y: 0),
                GridPoint(x: 4, y: 0)
            ],
            finalPosition: GridPoint(x: 4, y: 0)
        )

        scene.playMovementTransition(using: resolution)

        XCTAssertGreaterThanOrEqual(scene.latestMovementStepDurationForTesting, 0.14)
        XCTAssertLessThanOrEqual(scene.latestMovementStepDurationForTesting, 0.18)
        XCTAssertGreaterThanOrEqual(scene.latestMovementHoldDurationForTesting, 0.04)
        XCTAssertGreaterThanOrEqual(scene.latestMovementTotalDurationForTesting, 0.7)
    }

    func testSceneUsesLongerHoldForDamageMovementStep() {
        let scene = GameScene(initialBoardSize: 5, initialVisitedPoints: [GridPoint(x: 0, y: 0)])
        let damageStep = MovementResolution.PresentationStep(
            point: GridPoint(x: 2, y: 0),
            hpAfter: 2,
            handStacksAfter: [],
            collectedDungeonCardPickupIDsAfter: [],
            enemyStatesAfter: [],
            crackedFloorPointsAfter: [],
            collapsedFloorPointsAfter: [],
            tookDamage: true
        )
        let resolution = MovementResolution(
            path: [
                GridPoint(x: 1, y: 0),
                GridPoint(x: 2, y: 0)
            ],
            finalPosition: GridPoint(x: 2, y: 0),
            presentationSteps: [
                MovementResolution.PresentationStep(
                    point: GridPoint(x: 1, y: 0),
                    hpAfter: 3,
                    handStacksAfter: [],
                    collectedDungeonCardPickupIDsAfter: [],
                    enemyStatesAfter: [],
                    crackedFloorPointsAfter: [],
                    collapsedFloorPointsAfter: [],
                    tookDamage: false
                ),
                damageStep
            ]
        )

        scene.playMovementTransition(using: resolution)

        XCTAssertGreaterThan(
            scene.latestMovementDamageHoldDurationForTesting,
            scene.latestMovementHoldDurationForTesting
        )
        XCTAssertGreaterThanOrEqual(scene.latestMovementTotalDurationForTesting, 0.5)
    }

    func testSceneReplaysPresentationStepsForMultiStepMovement() {
        let scene = GameScene(initialBoardSize: 5, initialVisitedPoints: [GridPoint(x: 0, y: 0)])
        let stepPoints = [
            GridPoint(x: 1, y: 0),
            GridPoint(x: 2, y: 0),
            GridPoint(x: 3, y: 0)
        ]
        let resolution = MovementResolution(
            path: stepPoints,
            finalPosition: GridPoint(x: 3, y: 0),
            presentationSteps: stepPoints.map { point in
                MovementResolution.PresentationStep(
                    point: point,
                    hpAfter: 2,
                    handStacksAfter: [],
                    collectedDungeonCardPickupIDsAfter: [],
                    enemyStatesAfter: [],
                    crackedFloorPointsAfter: [],
                    collapsedFloorPointsAfter: [],
                    tookDamage: point == GridPoint(x: 2, y: 0)
                )
            }
        )
        var replayedSteps: [GridPoint] = []
        var completed = false

        scene.playMovementTransition(
            using: resolution,
            onStep: { replayedSteps.append($0.point) },
            onCompletion: { completed = true }
        )

        XCTAssertEqual(replayedSteps, stepPoints)
        XCTAssertTrue(completed)
    }

    func testSceneUsesReadableTimingForWarpMovementReplayApproach() {
        let scene = GameScene(initialBoardSize: 5, initialVisitedPoints: [GridPoint(x: 0, y: 0)])
        let path = [
            GridPoint(x: 1, y: 0),
            GridPoint(x: 2, y: 0),
            GridPoint(x: 4, y: 4)
        ]
        let resolution = MovementResolution(
            path: path,
            finalPosition: GridPoint(x: 4, y: 4),
            appliedEffects: [
                MovementResolution.AppliedEffect(
                    point: GridPoint(x: 2, y: 0),
                    effect: .warp(pairID: "test-warp", destination: GridPoint(x: 4, y: 4))
                )
            ],
            presentationSteps: path.map { point in
                MovementResolution.PresentationStep(
                    point: point,
                    hpAfter: 3,
                    handStacksAfter: [],
                    collectedDungeonCardPickupIDsAfter: [],
                    enemyStatesAfter: [],
                    crackedFloorPointsAfter: [],
                    collapsedFloorPointsAfter: [],
                    tookDamage: false,
                    stopReason: point == GridPoint(x: 4, y: 4) ? .warp : nil
                )
            }
        )
        var replayedSteps: [GridPoint] = []

        scene.playMovementTransition(
            using: resolution,
            onStep: { replayedSteps.append($0.point) }
        )

        XCTAssertEqual(scene.latestMovementPathForTesting, path)
        XCTAssertEqual(replayedSteps, path)
        XCTAssertGreaterThanOrEqual(scene.latestMovementStepDurationForTesting, 0.14)
        XCTAssertGreaterThanOrEqual(
            scene.latestMovementTotalDurationForTesting,
            0.7,
            "ワープ床へ入るまでの歩行と短いワープ演出を合わせても、旧来の一括移動に見えない長さを確保します"
        )
    }

    /// 単一候補カードと複数候補カードが個別の集合へ分類されることを確認する
    func testRefreshGuideHighlightsSeparatesSingleAndMultipleCandidates() {
        // 右方向カードをテスト用に複数ベクトルへ差し替え、選択肢が 2 件になる状況を作る
        MoveCard.setTestMovementVectors([
            MoveVector(dx: 1, dy: 0),
            MoveVector(dx: -1, dy: 0)
        ], for: .straightRight2)
        defer { MoveCard.setTestMovementVectors(nil, for: .straightRight2) }

        let viewModel = makeViewModel()
        let origin = GridPoint(x: 2, y: 2)

        // 上 1 マスの単一ベクトルカードと、左右どちらかに進める複数ベクトルカードを手札として用意する
        let singleStack = HandStack(cards: [DealtCard(move: .kingUpRight)])
        let multipleStack = HandStack(cards: [DealtCard(move: .straightRight2)])

        viewModel.refreshGuideHighlights(
            handOverride: [singleStack, multipleStack],
            currentOverride: origin,
            progressOverride: .playing
        )

        let buckets = viewModel.guideHighlightBuckets
        let expectedSingle: Set<GridPoint> = [GridPoint(x: 3, y: 3)]
        let expectedMultiple: Set<GridPoint> = [GridPoint(x: 3, y: 2), GridPoint(x: 1, y: 2)]

        XCTAssertEqual(buckets.singleVectorDestinations, expectedSingle, "単一候補カードのハイライト座標が想定と一致しません")
        XCTAssertEqual(buckets.multipleVectorDestinations, expectedMultiple, "複数候補カードのハイライト座標が期待通りに分類されていません")
    }

    /// 単一候補と複数候補が同一マスへ重なった場合でも両集合へ残ることを確認する
    func testRefreshGuideHighlightsKeepsOverlappingDestinations() {
        // 複数候補カードに「右上1」も含めることで、単一候補カードと同じマスが重なるケースを再現する
        MoveCard.setTestMovementVectors([
            MoveVector(dx: 1, dy: 1),
            MoveVector(dx: 1, dy: 0)
        ], for: .straightRight2)
        defer { MoveCard.setTestMovementVectors(nil, for: .straightRight2) }

        let viewModel = makeViewModel()
        let origin = GridPoint(x: 2, y: 2)
        let singleDestination = GridPoint(x: 3, y: 3)

        let singleStack = HandStack(cards: [DealtCard(move: .kingUpRight)])
        let multipleStack = HandStack(cards: [DealtCard(move: .straightRight2)])

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

    func testRefreshGuideHighlightsPrioritizesDungeonDangerOverMultiStepPathFill() {
        let mode = makeRayDangerMode()
        let core = GameCore(mode: mode)
        let viewModel = GameBoardBridgeViewModel(core: core, mode: mode)
        let origin = GridPoint(x: 0, y: 0)
        let rayStack = HandStack(cards: [DealtCard(move: .rayRight)])
        let dangerPathPoint = GridPoint(x: 2, y: 0)
        let dangerDestinationPoint = GridPoint(x: 4, y: 0)

        XCTAssertTrue(core.enemyDangerPoints.contains(dangerPathPoint))
        XCTAssertTrue(core.enemyDangerPoints.contains(dangerDestinationPoint))

        viewModel.refreshGuideHighlights(
            handOverride: [rayStack],
            currentOverride: origin,
            progressOverride: .playing
        )

        XCTAssertFalse(
            viewModel.guideHighlightBuckets.multiStepPathPoints.contains(dangerPathPoint),
            "敵の危険範囲と重なるレイ通過マスは、青塗りではなく赤塗りを優先します"
        )
        XCTAssertFalse(
            viewModel.scene.latestHighlightPoints(for: .guideMultiStepPath).contains(dangerPathPoint),
            "Scene 側にも危険範囲と重なるレイ通過塗りを渡さない想定です"
        )
        XCTAssertEqual(
            viewModel.scene.latestHighlightPoints(for: .dungeonDanger),
            core.enemyDangerPoints,
            "敵の危険範囲は赤塗りとして残します"
        )
        XCTAssertTrue(
            viewModel.guideHighlightBuckets.multiStepDestinations.contains(dangerDestinationPoint),
            "危険範囲上の終点でも、タップ可能な水色枠は残します"
        )
        XCTAssertTrue(
            viewModel.scene.latestHighlightPoints(for: .guideMultiStepCandidate).contains(dangerDestinationPoint),
            "Scene 側にも危険範囲上の終点枠は渡します"
        )
    }

    func testRayMovementReplayRestoresInitialBoardAndAppliesStepBoards() {
        let mode = makeRayTrapMode()
        let core = GameCore.makeTestInstance(
            deck: Deck.makeTestDeck(
                cards: [.rayRight, .kingUpRight, .straightRight2, .straightLeft2, .straightDown2],
                configuration: mode.deckConfiguration
            ),
            current: GridPoint(x: 0, y: 0),
            mode: mode
        )
        let viewModel = GameBoardBridgeViewModel(core: core, mode: mode)
        var startedWithInitialBoard = false
        var stepSnapshots: [(point: GridPoint, firstTrapVisited: Bool, secondTrapVisited: Bool)] = []
        viewModel.onMovementPresentationStarted = { [weak viewModel] _ in
            startedWithInitialBoard = viewModel?.scene.boardIsVisitedForTesting(at: GridPoint(x: 1, y: 0)) == false
        }
        viewModel.onMovementPresentationStep = { [weak viewModel] step in
            stepSnapshots.append((
                point: step.point,
                firstTrapVisited: viewModel?.scene.boardIsVisitedForTesting(at: GridPoint(x: 1, y: 0)) == true,
                secondTrapVisited: viewModel?.scene.boardIsVisitedForTesting(at: GridPoint(x: 2, y: 0)) == true
            ))
        }

        let move = try! XCTUnwrap(core.availableMoves().first { $0.destination == GridPoint(x: 4, y: 0) })
        core.playCard(using: move)
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))

        XCTAssertTrue(startedWithInitialBoard)
        XCTAssertEqual(stepSnapshots.map(\.point), [
            GridPoint(x: 1, y: 0),
            GridPoint(x: 2, y: 0),
            GridPoint(x: 3, y: 0),
            GridPoint(x: 4, y: 0)
        ])
        XCTAssertEqual(stepSnapshots[0].firstTrapVisited, true)
        XCTAssertEqual(stepSnapshots[0].secondTrapVisited, false)
        XCTAssertEqual(stepSnapshots[1].secondTrapVisited, true)
    }

    func testRayMovementReplayKeepsEnemyVisibleUntilStompStep() {
        let enemyPoint = GridPoint(x: 2, y: 0)
        let mode = makeRayEnemyMode(enemyPoint: enemyPoint)
        let core = GameCore.makeTestInstance(
            deck: Deck.makeTestDeck(
                cards: [.rayRight, .kingUpRight, .straightRight2, .straightLeft2, .straightDown2],
                configuration: mode.deckConfiguration
            ),
            current: GridPoint(x: 0, y: 0),
            mode: mode
        )
        let viewModel = GameBoardBridgeViewModel(core: core, mode: mode)
        var enemyVisibleAtReplayStart = false
        var stepEnemySnapshots: [(point: GridPoint, enemyVisible: Bool)] = []
        viewModel.onMovementPresentationStarted = { [weak viewModel] _ in
            enemyVisibleAtReplayStart = viewModel?.scene.latestDungeonEnemyMarkersForTesting()
                .contains { $0.point == enemyPoint } == true
        }
        viewModel.onMovementPresentationStep = { [weak viewModel] step in
            stepEnemySnapshots.append((
                point: step.point,
                enemyVisible: viewModel?.scene.latestDungeonEnemyMarkersForTesting()
                    .contains { $0.point == enemyPoint } == true
            ))
        }

        let move = try! XCTUnwrap(core.availableMoves().first { $0.destination == GridPoint(x: 4, y: 0) })
        core.playCard(using: move)
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))

        XCTAssertTrue(enemyVisibleAtReplayStart, "Core の最終 enemyStates 通知が先に来ても、リプレイ開始時は移動前の敵を表示します")
        XCTAssertEqual(stepEnemySnapshots.map(\.point), [
            GridPoint(x: 1, y: 0),
            enemyPoint,
            GridPoint(x: 3, y: 0),
            GridPoint(x: 4, y: 0)
        ])
        XCTAssertEqual(stepEnemySnapshots[0].enemyVisible, true, "敵を踏む前の step では敵を残します")
        XCTAssertEqual(stepEnemySnapshots[1].enemyVisible, false, "敵マスへ到達した step 後にだけ敵を消します")
    }

    func testRayMovementReplayKeepsDangerHighlightsMatchedToDisplayedEnemies() {
        let mode = makeRayMovingEnemyMode()
        let core = GameCore.makeTestInstance(
            deck: Deck.makeTestDeck(
                cards: [.rayRight, .kingUpRight, .straightRight2, .straightLeft2, .straightDown2],
                configuration: mode.deckConfiguration
            ),
            current: GridPoint(x: 0, y: 0),
            mode: mode
        )
        let viewModel = GameBoardBridgeViewModel(core: core, mode: mode)
        let initialEnemyStates = core.enemyStates
        let initialDangerPoints = core.enemyDangerPoints(forDisplayedEnemyStates: initialEnemyStates)
        let initialEnemyPoints = Set(initialEnemyStates.map(\.position))
        var replayStartEnemyPoints: Set<GridPoint> = []
        var replayStartDangerPoints: Set<GridPoint> = []
        var firstStepDangerPoints: Set<GridPoint> = []

        viewModel.onMovementPresentationStarted = { [weak viewModel] _ in
            replayStartEnemyPoints = viewModel?.scene.latestHighlightPoints(for: .dungeonEnemy) ?? []
            replayStartDangerPoints = viewModel?.scene.latestHighlightPoints(for: .dungeonDanger) ?? []
        }
        viewModel.onMovementPresentationStep = { [weak viewModel] step in
            guard step.point == GridPoint(x: 1, y: 0) else { return }
            firstStepDangerPoints = viewModel?.scene.latestHighlightPoints(for: .dungeonDanger) ?? []
        }

        let move = try! XCTUnwrap(core.availableMoves().first { $0.destination == GridPoint(x: 4, y: 0) })
        core.playCard(using: move)
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))

        XCTAssertNotEqual(
            core.enemyDangerPoints,
            initialDangerPoints,
            "このテストでは Core の最終敵位置とリプレイ開始時の敵位置で危険範囲が変わる必要があります"
        )
        XCTAssertEqual(
            replayStartEnemyPoints,
            initialEnemyPoints,
            "リプレイ開始時の敵マーカーは移動前の敵位置を表示します"
        )
        XCTAssertEqual(
            replayStartDangerPoints,
            initialDangerPoints,
            "リプレイ開始時の赤い攻撃範囲も、画面上の敵マーカーと同じ移動前の敵状態から計算します"
        )
        XCTAssertEqual(
            firstStepDangerPoints,
            initialDangerPoints,
            "最初の一歩を踏んだ直後も、敵ターン後の最終危険範囲を先に出さない想定です"
        )
    }

    func testWarpRayMovementUsesReplayAndAppliesWarpSourceBeforeDestination() {
        let mode = makeRayWarpMode()
        let core = GameCore.makeTestInstance(
            deck: Deck.makeTestDeck(
                cards: [.rayRight, .kingUpRight, .straightRight2, .straightLeft2, .straightDown2],
                configuration: mode.deckConfiguration
            ),
            current: GridPoint(x: 0, y: 0),
            mode: mode
        )
        let viewModel = GameBoardBridgeViewModel(core: core, mode: mode)
        var replayStarted = false
        var stepSnapshots: [(point: GridPoint, warpSourceVisited: Bool, warpDestinationVisited: Bool)] = []
        viewModel.onMovementPresentationStarted = { _ in
            replayStarted = true
        }
        viewModel.onMovementPresentationStep = { [weak viewModel] step in
            stepSnapshots.append((
                point: step.point,
                warpSourceVisited: viewModel?.scene.boardIsVisitedForTesting(at: GridPoint(x: 2, y: 0)) == true,
                warpDestinationVisited: viewModel?.scene.boardIsVisitedForTesting(at: GridPoint(x: 4, y: 4)) == true
            ))
        }

        let move = try! XCTUnwrap(core.availableMoves().first { $0.destination == GridPoint(x: 4, y: 0) })
        core.playCard(using: move)
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))

        XCTAssertTrue(replayStarted, "ワープを含むレイ型移動も一歩ずつリプレイ経路へ入る想定です")
        XCTAssertEqual(stepSnapshots.map(\.point), [
            GridPoint(x: 1, y: 0),
            GridPoint(x: 2, y: 0),
            GridPoint(x: 4, y: 4)
        ])
        XCTAssertEqual(stepSnapshots[1].warpSourceVisited, true)
        XCTAssertEqual(stepSnapshots[1].warpDestinationVisited, false)
        XCTAssertEqual(stepSnapshots[2].warpDestinationVisited, true)
    }

    func testEnemyTurnWaitsUntilRayMovementReplayFinishes() throws {
        let viewModel = makeViewModel()
        let before = EnemyState(
            definition: EnemyDefinition(
                id: "wait-test-patrol",
                name: "巡回兵",
                position: GridPoint(x: 1, y: 1),
                behavior: .patrol(path: [GridPoint(x: 1, y: 1), GridPoint(x: 2, y: 1)])
            )
        )
        var after = before
        after.position = GridPoint(x: 2, y: 1)
        let event = DungeonEnemyTurnEvent(
            transitions: [
                DungeonEnemyTurnTransition(
                    enemyID: before.id,
                    name: before.name,
                    before: before,
                    after: after
                )
            ],
            attackedPlayer: false,
            hpBefore: 3,
            hpAfter: 3
        )
        var movementFinished = false
        var enemyTurnStartedAfterMovement = false
        viewModel.onMovementPresentationFinished = {
            movementFinished = true
        }
        viewModel.onEnemyTurnAnimationFinished = { _ in
            enemyTurnStartedAfterMovement = movementFinished
        }

        viewModel.setMovementReplayActiveForTesting(true)
        viewModel.playDungeonEnemyTurn(event)

        XCTAssertTrue(viewModel.isMovementReplayActive)
        XCTAssertFalse(viewModel.isEnemyTurnAnimationActive)
        XCTAssertNotNil(viewModel.pendingEnemyTurnEventAfterMovementReplay)

        movementFinished = true
        viewModel.setMovementReplayActiveForTesting(false)
        viewModel.playPendingEnemyTurnAfterMovementReplayForTesting()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        XCTAssertNil(viewModel.pendingEnemyTurnEventAfterMovementReplay)
        XCTAssertTrue(enemyTurnStartedAfterMovement)
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
            deckPreset: .standardLight,
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
            viewModel.scene.latestDungeonEnemyMarkersForTesting(),
            core.enemyStates.map { enemy in
                SceneDungeonEnemyMarker(
                    enemy,
                    facingVector: core.enemyPatrolMovementPreviews.first { $0.enemyID == enemy.id }?.vector
                )
            },
            "敵の種類を行動前に見分けられるよう、種類付きマーカーを Scene へ渡します"
        )
        XCTAssertEqual(
            viewModel.scene.latestHighlightPoints(for: .dungeonDanger),
            core.enemyDangerPoints,
            "危険範囲表示は GameCore の判定集合と一致させます"
        )
        XCTAssertEqual(
            viewModel.scene.latestHighlightPoints(for: .dungeonEnemyWarning),
            core.enemyWarningPoints,
            "メテオ兵の着弾予告範囲を専用ハイライトとして Scene へ渡します"
        )
        XCTAssertEqual(
            viewModel.scene.latestHighlightPoints(for: .dungeonCardPickup),
            Set(floor.cardPickups.map(\.point)),
            "床落ちカードも専用ハイライトとして Scene へ渡します"
        )

        let trapTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let trapFloor = try XCTUnwrap(trapTower.floors.first)
        let trapMode = trapFloor.makeGameMode(dungeonID: trapTower.id)
        let trapCore = GameCore(mode: trapMode)
        let trapViewModel = GameBoardBridgeViewModel(core: trapCore, mode: trapMode)

        XCTAssertEqual(
            trapViewModel.scene.latestHighlightPoints(for: .dungeonDamageTrap),
            trapCore.damageTrapPoints,
            "見えているダメージ罠を専用ハイライトとして Scene へ渡します"
        )

        let growthHealingTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let healingFloor = try XCTUnwrap(growthHealingTower.floors.first { floor in
            floor.hazards.contains { hazard in
                if case .healingTile(let points, _) = hazard {
                    return !points.isEmpty
                }
                return false
            }
        })
        let healingMode = healingFloor.makeGameMode(dungeonID: growthHealingTower.id)
        let healingCore = GameCore(mode: healingMode)
        let healingViewModel = GameBoardBridgeViewModel(core: healingCore, mode: healingMode)

        XCTAssertEqual(
            healingViewModel.scene.latestHighlightPoints(for: .dungeonHealingTile),
            healingCore.healingTilePoints,
            "成長塔の回復マスを専用ハイライトとして Scene へ渡します"
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
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let floor = tower.floors[0]
        let mode = floor.makeGameMode(dungeonID: tower.id)
        let core = GameCore(mode: mode)
        let viewModel = GameBoardBridgeViewModel(core: core, mode: mode)

        XCTAssertEqual(viewModel.boardSize, 9)
        XCTAssertEqual(
            viewModel.scene.latestPatrolMovementPreviewsForTesting(),
            [],
            "巡回兵の次移動方向は黄色い別矢印ではなく敵アイコンへ渡します"
        )
        XCTAssertEqual(
            viewModel.scene.latestDungeonEnemyMarkersForTesting(),
            core.enemyStates.map { enemy in
                SceneDungeonEnemyMarker(
                    enemy,
                    facingVector: core.enemyPatrolMovementPreviews.first { $0.enemyID == enemy.id }?.vector
                )
            },
            "巡回兵の次移動方向を敵アイコン内の向きとして Scene へ渡す必要があります"
        )
        XCTAssertEqual(
            viewModel.scene.latestPatrolRailPreviewsForTesting(),
            core.enemyPatrolRailPreviews.map(ScenePatrolRailPreview.init),
            "巡回兵の巡回範囲レールを Scene へ渡す必要があります"
        )

        guard let basicMove = core.availableBasicOrthogonalMoves().first(where: { $0.destination == GridPoint(x: 1, y: 0) }) else {
            XCTFail("基本移動候補が見つかりません")
            return
        }
        core.playBasicOrthogonalMove(using: basicMove)
        viewModel.refreshGuideHighlights()

        XCTAssertEqual(
            viewModel.scene.latestPatrolMovementPreviewsForTesting(),
            [],
            "敵ターン後も巡回兵の黄色い別矢印は表示しません"
        )
        XCTAssertEqual(
            viewModel.scene.latestDungeonEnemyMarkersForTesting(),
            core.enemyStates.map { enemy in
                SceneDungeonEnemyMarker(
                    enemy,
                    facingVector: core.enemyPatrolMovementPreviews.first { $0.enemyID == enemy.id }?.vector
                )
            },
            "敵ターン後も巡回兵の向きを敵アイコンへ同期します"
        )
        XCTAssertEqual(
            viewModel.scene.latestPatrolRailPreviewsForTesting(),
            core.enemyPatrolRailPreviews.map(ScenePatrolRailPreview.init),
            "敵ターン後も古い巡回レールを残さず更新する必要があります"
        )
    }

    func testDungeonEnemyTurnAnimationKeepsPatrolRailsVisible() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let floor = tower.floors[0]
        let mode = floor.makeGameMode(dungeonID: tower.id)
        let core = GameCore(mode: mode)
        let viewModel = GameBoardBridgeViewModel(core: core, mode: mode)
        let event = DungeonEnemyTurnEvent(
            transitions: [],
            attackedPlayer: false,
            hpBefore: core.dungeonHP,
            hpAfter: core.dungeonHP
        )

        XCTAssertFalse(core.enemyPatrolRailPreviews.isEmpty, "巡回塔1Fには巡回レールが必要です")

        viewModel.playDungeonEnemyTurn(event)

        XCTAssertEqual(
            viewModel.scene.latestPatrolRailPreviewsForTesting(),
            core.enemyPatrolRailPreviews.map(ScenePatrolRailPreview.init),
            "敵移動エフェクト中も巡回レールは消さずに表示します"
        )
    }

    func testDungeonRotatingWatcherDirectionIsPassedToEnemyMarkerWithoutSceneArrow() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let floor = tower.floors[6]
        let mode = floor.makeGameMode(dungeonID: tower.id)
        let core = GameCore(mode: mode)
        let viewModel = GameBoardBridgeViewModel(core: core, mode: mode)

        let rotatingWatcherMarker = try XCTUnwrap(
            viewModel.scene.latestDungeonEnemyMarkersForTesting()
                .first { $0.enemyID == "growth-7-rotating-watcher" }
        )
        XCTAssertEqual(
            rotatingWatcherMarker.rotationDirection,
            .counterclockwise,
            "回転見張りの右回り/左回りは敵アイコンへ渡します"
        )
        XCTAssertFalse(
            viewModel.scene.latestPatrolMovementPreviewsForTesting()
                .contains { $0.enemyID == "growth-7-rotating-watcher" },
            "回転見張りの次方向は Scene の軽量矢印へ渡しません"
        )
    }

    func testDungeonChaserMovementPreviewsArePassedToScene() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let floor = tower.floors[6]
        let mode = floor.makeGameMode(dungeonID: tower.id)
        let core = GameCore(mode: mode)
        let viewModel = GameBoardBridgeViewModel(core: core, mode: mode)

        let chaserPreviews = core.enemyChaserMovementPreviews.map(ScenePatrolMovementPreview.init)
        XCTAssertFalse(chaserPreviews.isEmpty, "成長塔7Fには追跡兵の次移動プレビューが必要です")
        XCTAssertEqual(
            viewModel.scene.latestPatrolMovementPreviewsForTesting(),
            chaserPreviews,
            "追跡兵の次移動先を Scene の軽量矢印へ渡す必要があります"
        )
    }

    func testDungeonMarkerWarningHighlightsArePassedToScene() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let floor = try XCTUnwrap(tower.floors.first { $0.id == "growth-17" })
        let mode = floor.makeGameMode(dungeonID: tower.id)
        let core = GameCore(mode: mode)
        let viewModel = GameBoardBridgeViewModel(core: core, mode: mode)

        XCTAssertFalse(core.enemyWarningPoints.isEmpty, "成長塔17Fにはメテオ兵の着弾予告マスが必要です")
        XCTAssertEqual(
            viewModel.scene.latestHighlightPoints(for: .dungeonEnemyWarning),
            core.enemyWarningPoints,
            "メテオ兵の着弾予告マスを Scene の専用ハイライトへ渡す必要があります"
        )
    }

    func testEnemyFreezeHidesThreatsButKeepsEnemyMarkers() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let floor = try XCTUnwrap(tower.floors.first { $0.id == "growth-17" })
        let mode = floor.makeGameMode(dungeonID: tower.id)
        let core = GameCore(mode: mode)
        core.overrideEnemyFreezeTurnsRemainingForTesting(2)
        let viewModel = GameBoardBridgeViewModel(core: core, mode: mode)

        XCTAssertEqual(viewModel.scene.latestHighlightPoints(for: .dungeonDanger), [])
        XCTAssertEqual(viewModel.scene.latestHighlightPoints(for: .dungeonEnemyWarning), [])
        XCTAssertEqual(
            viewModel.scene.latestHighlightPoints(for: .dungeonEnemy),
            Set(core.enemyStates.map(\.position))
        )
        XCTAssertTrue(core.enemyPatrolMovementPreviews.isEmpty)
        XCTAssertTrue(core.enemyChaserMovementPreviews.isEmpty)
    }

    func testDamageBarrierKeepsThreatHighlightsAndEnemyMarkers() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let floor = try XCTUnwrap(tower.floors.first { $0.id == "growth-17" })
        let mode = floor.makeGameMode(dungeonID: tower.id)
        let core = GameCore(mode: mode)
        core.overrideDamageBarrierTurnsRemainingForTesting(2)
        let viewModel = GameBoardBridgeViewModel(core: core, mode: mode)

        XCTAssertFalse(core.enemyDangerPoints.isEmpty)
        XCTAssertFalse(core.enemyWarningPoints.isEmpty)
        XCTAssertEqual(
            viewModel.scene.latestHighlightPoints(for: .dungeonDanger),
            core.enemyDangerPoints
        )
        XCTAssertEqual(
            viewModel.scene.latestHighlightPoints(for: .dungeonEnemyWarning),
            core.enemyWarningPoints
        )
        XCTAssertEqual(
            viewModel.scene.latestHighlightPoints(for: .dungeonEnemy),
            Set(core.enemyStates.map(\.position))
        )
        XCTAssertFalse(core.enemyPatrolMovementPreviews.isEmpty)
    }

    func testDungeonEnemyTurnAnimationSkipsRedDangerPulseButKeepsWarningPulse() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let floor = try XCTUnwrap(tower.floors.first { $0.id == "growth-17" })
        let mode = floor.makeGameMode(dungeonID: tower.id)
        let core = GameCore(mode: mode)
        let viewModel = GameBoardBridgeViewModel(core: core, mode: mode)
        let event = DungeonEnemyTurnEvent(
            transitions: [],
            attackedPlayer: false,
            hpBefore: core.dungeonHP,
            hpAfter: core.dungeonHP
        )

        XCTAssertFalse(core.enemyDangerPoints.isEmpty, "成長塔17Fには敵の危険範囲が必要です")
        XCTAssertFalse(core.enemyWarningPoints.isEmpty, "成長塔17Fにはメテオ兵の着弾予告マスが必要です")

        viewModel.playDungeonEnemyTurn(event)

        XCTAssertEqual(
            viewModel.scene.latestEnemyTurnDangerPulsePointsForTesting,
            [],
            "敵ターン演出後は通常の危険塗りへ戻るため、赤い角丸パルスは出しません"
        )
        XCTAssertEqual(
            viewModel.scene.latestEnemyTurnWarningPulsePointsForTesting,
            core.enemyWarningPoints,
            "着弾予告は通常の危険塗りとは別の専用パルスとして渡します"
        )
    }

    func testDungeonEnemyTurnAnimationLocksInputAndReleasesAfterPlayback() async throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let mode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower))
        let core = GameCore(mode: mode)
        let viewModel = GameBoardBridgeViewModel(core: core, mode: mode)
        let before = EnemyState(
            definition: EnemyDefinition(
                id: "patrol",
                name: "巡回兵",
                position: GridPoint(x: 1, y: 1),
                behavior: .patrol(path: [GridPoint(x: 1, y: 1), GridPoint(x: 2, y: 1)])
            )
        )
        var after = before
        after.position = GridPoint(x: 2, y: 1)
        let event = DungeonEnemyTurnEvent(
            transitions: [
                DungeonEnemyTurnTransition(
                    enemyID: before.id,
                    name: before.name,
                    before: before,
                    after: after
                )
            ],
            attackedPlayer: true,
            hpBefore: 3,
            hpAfter: 2
        )

        viewModel.playDungeonEnemyTurn(event)

        XCTAssertTrue(viewModel.isInputAnimationActive)
        XCTAssertEqual(
            viewModel.scene.latestHighlightPoints(for: .dungeonEnemy),
            [GridPoint(x: 1, y: 1)],
            "敵ターン演出の開始時は敵アイコンを移動前の位置に戻して表示します"
        )
        XCTAssertTrue(
            viewModel.scene.latestHighlightPoints(for: .dungeonDanger).isEmpty,
            "敵移動中は最終位置の危険マスだけが先に見えないよう一時的に隠します"
        )
        try await Task.sleep(nanoseconds: 180_000_000)
        XCTAssertFalse(viewModel.isInputAnimationActive)
        XCTAssertEqual(
            viewModel.scene.latestHighlightPoints(for: .dungeonEnemy),
            Set(core.enemyStates.map(\.position)),
            "敵ターン演出後は最新の敵位置へ同期します"
        )
        XCTAssertEqual(viewModel.damageEffectPlayCountForTesting, 1)
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

    func testGrowthTowerKeyDoorStateIsPassedToScene() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let floor = try XCTUnwrap(tower.floors.first { $0.exitLock != nil })
        let mode = floor.makeGameMode(dungeonID: tower.id)
        let core = GameCore(mode: mode)
        let viewModel = GameBoardBridgeViewModel(core: core, mode: mode)

        let doorPoint = GridPoint(x: 4, y: 4)

        XCTAssertEqual(viewModel.boardSize, 9)
        XCTAssertTrue(mode.tileEffects.isEmpty)
        XCTAssertTrue(core.board.isImpassable(doorPoint))
        XCTAssertTrue(
            viewModel.scene.boardIsImpassableForTesting(at: doorPoint),
            "成長塔の施錠階段フロアの扉マスも Scene の盤面へ渡す必要があります"
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

    private func makeRayDangerMode() -> GameMode {
        let pathWatcher = EnemyDefinition(
            id: "ray-danger-path",
            name: "見張り",
            position: GridPoint(x: 2, y: 1),
            behavior: .watcher(direction: MoveVector(dx: 0, dy: -1), range: 1)
        )
        let destinationWatcher = EnemyDefinition(
            id: "ray-danger-destination",
            name: "見張り",
            position: GridPoint(x: 4, y: 1),
            behavior: .watcher(direction: MoveVector(dx: 0, dy: -1), range: 1)
        )

        return GameMode(
            identifier: .dungeonFloor,
            displayName: "レイ危険表示テスト",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 0,
                allowsStacking: true,
                deckPreset: .standardLight,
                spawnRule: .fixed(GridPoint(x: 0, y: 0)),
                penalties: .init(
                    deadlockPenaltyCost: 0,
                    manualRedrawPenaltyCost: 0,
                    manualDiscardPenaltyCost: 0,
                    revisitPenaltyCost: 0
                ),
                completionRule: .dungeonExit(exitPoint: GridPoint(x: 4, y: 4)),
                dungeonRules: DungeonRules(
                    difficulty: .growth,
                    failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 8),
                    enemies: [pathWatcher, destinationWatcher]
                )
            ),
            leaderboardEligible: false
        )
    }

    private func makeRayTrapMode() -> GameMode {
        GameMode(
            identifier: .dungeonFloor,
            displayName: "レイ表示テスト",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 0,
                allowsStacking: true,
                deckPreset: .standardLight,
                spawnRule: .fixed(GridPoint(x: 0, y: 0)),
                penalties: .init(
                    deadlockPenaltyCost: 0,
                    manualRedrawPenaltyCost: 0,
                    manualDiscardPenaltyCost: 0,
                    revisitPenaltyCost: 0
                ),
                completionRule: .dungeonExit(exitPoint: GridPoint(x: 4, y: 4)),
                dungeonRules: DungeonRules(
                    difficulty: .growth,
                    failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 8),
                    hazards: [.damageTrap(points: [GridPoint(x: 1, y: 0), GridPoint(x: 2, y: 0)], damage: 1)]
                )
            ),
            leaderboardEligible: false
        )
    }

    private func makeRayEnemyMode(enemyPoint: GridPoint) -> GameMode {
        GameMode(
            identifier: .dungeonFloor,
            displayName: "レイ敵表示テスト",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 0,
                allowsStacking: true,
                deckPreset: .standardLight,
                spawnRule: .fixed(GridPoint(x: 0, y: 0)),
                penalties: .init(
                    deadlockPenaltyCost: 0,
                    manualRedrawPenaltyCost: 0,
                    manualDiscardPenaltyCost: 0,
                    revisitPenaltyCost: 0
                ),
                completionRule: .dungeonExit(exitPoint: GridPoint(x: 4, y: 4)),
                dungeonRules: DungeonRules(
                    difficulty: .growth,
                    failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 8),
                    enemies: [
                        EnemyDefinition(
                            id: "stomp-test-guard",
                            name: "番兵",
                            position: enemyPoint,
                            behavior: .guardPost
                        )
                    ]
                )
            ),
            leaderboardEligible: false
        )
    }

    private func makeRayMovingEnemyMode() -> GameMode {
        let patrol = EnemyDefinition(
            id: "moving-danger-patrol",
            name: "巡回兵",
            position: GridPoint(x: 2, y: 2),
            behavior: .patrol(path: [
                GridPoint(x: 2, y: 2),
                GridPoint(x: 3, y: 2)
            ])
        )

        return GameMode(
            identifier: .dungeonFloor,
            displayName: "レイ敵危険範囲同期テスト",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 0,
                allowsStacking: true,
                deckPreset: .standardLight,
                spawnRule: .fixed(GridPoint(x: 0, y: 0)),
                penalties: .init(
                    deadlockPenaltyCost: 0,
                    manualRedrawPenaltyCost: 0,
                    manualDiscardPenaltyCost: 0,
                    revisitPenaltyCost: 0
                ),
                completionRule: .dungeonExit(exitPoint: GridPoint(x: 4, y: 4)),
                dungeonRules: DungeonRules(
                    difficulty: .growth,
                    failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 8),
                    enemies: [patrol]
                )
            ),
            leaderboardEligible: false
        )
    }

    private func makeRayWarpMode() -> GameMode {
        GameMode(
            identifier: .dungeonFloor,
            displayName: "レイワープ表示テスト",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 0,
                allowsStacking: true,
                deckPreset: .standardLight,
                spawnRule: .fixed(GridPoint(x: 0, y: 0)),
                penalties: .init(
                    deadlockPenaltyCost: 0,
                    manualRedrawPenaltyCost: 0,
                    manualDiscardPenaltyCost: 0,
                    revisitPenaltyCost: 0
                ),
                warpTilePairs: [
                    "test-warp": [
                        GridPoint(x: 2, y: 0),
                        GridPoint(x: 4, y: 4)
                    ]
                ],
                completionRule: .dungeonExit(exitPoint: GridPoint(x: 0, y: 4)),
                dungeonRules: DungeonRules(
                    difficulty: .growth,
                    failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 8)
                )
            ),
            leaderboardEligible: false
        )
    }

}
