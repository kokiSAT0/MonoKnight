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

    /// スポーン選択待機状態から `.playing` 復帰直後にガイド集合が復元されることを検証する
    func testGuideHighlightsRestoreAfterSpawnSelection() {
        // スポーンを任意選択するモードで GameCore を初期化し、進行状態が awaitingSpawn で始まる状況を用意する
        let deck = Deck.makeTestDeck(cards: [.kingUp], configuration: .kingOnly)
        let core = GameCore.makeTestInstance(deck: deck, current: nil, mode: .dungeonPlaceholder)
        let viewModel = GameBoardBridgeViewModel(core: core, mode: .dungeonPlaceholder)

        XCTAssertEqual(core.progress, GameProgress.awaitingSpawn, "スポーン選択待機状態で開始できていません")

        // 復帰後に確認したい手札を退避させ、ガイド集合が一時的に空になることを確認する
        let singleStack = HandStack(cards: [DealtCard(move: .kingUp)])
        viewModel.refreshGuideHighlights(
            handOverride: [singleStack],
            progressOverride: GameProgress.awaitingSpawn
        )

        XCTAssertNotNil(viewModel.pendingGuideHand, "スポーン選択待機中でも手札退避が維持されていません")
        XCTAssertTrue(viewModel.guideHighlightBuckets.singleVectorDestinations.isEmpty, "待機中はガイドを非表示にしておく必要があります")
        XCTAssertTrue(viewModel.guideHighlightBuckets.multipleVectorDestinations.isEmpty, "待機中はガイドを非表示にしておく必要があります")

        // 任意スポーンを確定し、進行状態を playing に戻した直後の処理を模擬する
        let spawnPoint = GridPoint(x: 3, y: 3)
        core.simulateSpawnSelection(forTesting: spawnPoint)
        viewModel.handleProgressChange(core.progress)

        // 復帰後は pending 手札から再計算されたガイド集合が復元される
        let expectedDestination = GridPoint(x: spawnPoint.x, y: spawnPoint.y + 1)
        XCTAssertTrue(
            viewModel.guideHighlightBuckets.singleVectorDestinations.contains(expectedDestination),
            "スポーン確定直後に単一候補のガイドが復元されていません"
        )
        XCTAssertTrue(
            viewModel.guideHighlightBuckets.multipleVectorDestinations.isEmpty,
            "今回の手札では複数候補のガイドが存在しない想定です"
        )
        XCTAssertNil(viewModel.pendingGuideHand, "ガイド復元後は pending 手札を解放する必要があります")
        XCTAssertNil(viewModel.pendingGuideCurrent, "ガイド復元後は pending 現在地を解放する必要があります")
    }

    /// スポーン待機中でも目的地制の目的地マーカーが Scene へ送られることを検証する
    func testTargetHighlightsRemainVisibleWhileAwaitingSpawnSelection() {
        let core = GameCore(mode: .dungeonPlaceholder)
        let viewModel = GameBoardBridgeViewModel(core: core, mode: .dungeonPlaceholder)

        XCTAssertEqual(core.progress, GameProgress.awaitingSpawn)
        XCTAssertEqual(core.activeTargetPoints.count, 3, "スポーン選択前でも目的地が生成される想定です")
        XCTAssertEqual(
            viewModel.scene.latestHighlightPoints(for: .currentTarget),
            core.targetPoint.map { Set([$0]) } ?? [],
            "スポーン待機中でも現在目的地マーカーを Scene へ渡します"
        )
        XCTAssertEqual(
            viewModel.scene.latestHighlightPoints(for: .upcomingTarget),
            Set(core.upcomingTargetPoints),
            "スポーン待機中でも表示中目的地マーカーを Scene へ渡します"
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

    /// 目的地制では、通過で取れる目的地を移動先候補の枠として強調しないことを検証する
    func testRefreshGuideHighlightsDoesNotFramePassThroughTargetCapture() {
        let core = GameCore(mode: .dungeonPlaceholder)
        let viewModel = GameBoardBridgeViewModel(core: core, mode: .dungeonPlaceholder)
        let origin = GridPoint(x: 2, y: 2)
        let target = GridPoint(x: 4, y: 2)

        core.overrideTargetStateForTesting(targetPoint: target)

        let captureStack = HandStack(cards: [DealtCard(move: .straightRight2)])
        let approachStack = HandStack(cards: [DealtCard(move: .kingRight)])
        let neutralStack = HandStack(cards: [DealtCard(move: .kingUp)])

        viewModel.refreshGuideHighlights(
            handOverride: [captureStack, approachStack, neutralStack],
            currentOverride: origin,
            progressOverride: .playing
        )

        let buckets = viewModel.guideHighlightBuckets
        XCTAssertTrue(
            buckets.singleVectorDestinations.contains(target),
            "目的地へ到達する合法手は通常の移動先候補として残す必要があります"
        )
        XCTAssertTrue(
            buckets.singleVectorDestinations.contains(GridPoint(x: 3, y: 2)),
            "目的地に近づく合法手は通常の単一候補ガイドとして残す必要があります"
        )
        XCTAssertTrue(
            buckets.singleVectorDestinations.contains(GridPoint(x: 2, y: 3)),
            "目的地に近づかない合法手も従来の合法手ハイライトには残す必要があります"
        )
        XCTAssertTrue(
            viewModel.scene.latestHighlightPoints(for: .guideMultipleCandidate).isEmpty,
            "選択式カードがない場合はオレンジ枠を Scene へ送らない想定です"
        )
        XCTAssertTrue(
            viewModel.scene.latestHighlightPoints(for: .targetApproachCandidate).isEmpty,
            "目的地に近づくだけの候補はオレンジ系の接近ガイドとして Scene へ送らない想定です"
        )
        XCTAssertTrue(
            viewModel.scene.latestHighlightPoints(for: .targetCaptureCandidate).isEmpty,
            "通過で取れる目的地を移動先候補に見える紫枠として Scene へ送らない想定です"
        )
        XCTAssertEqual(
            viewModel.scene.latestHighlightPoints(for: .currentTarget),
            [target],
            "目的地マーカー自体は枠を消しても維持する必要があります"
        )
    }

    func testRefreshGuideHighlightsKeepsUpcomingTargetMarkerWithoutCaptureFrame() {
        let core = GameCore(mode: .dungeonPlaceholder)
        let viewModel = GameBoardBridgeViewModel(core: core, mode: .dungeonPlaceholder)
        let origin = GridPoint(x: 2, y: 2)
        let currentTarget = GridPoint(x: 4, y: 4)
        let upcomingTarget = GridPoint(x: 3, y: 2)

        core.overrideTargetStateForTesting(
            targetPoint: currentTarget,
            upcomingTargetPoints: [upcomingTarget]
        )

        let captureStack = HandStack(cards: [DealtCard(move: .kingRight)])
        viewModel.refreshGuideHighlights(
            handOverride: [captureStack],
            currentOverride: origin,
            progressOverride: .playing
        )

        XCTAssertTrue(
            viewModel.scene.latestHighlightPoints(for: .targetCaptureCandidate).isEmpty,
            "先読み側の目的地を取れる手でも、目的地通過用の紫枠は表示しない想定です"
        )
        XCTAssertEqual(
            viewModel.scene.latestHighlightPoints(for: .upcomingTarget),
            [upcomingTarget],
            "先読み側の目的地は獲得可能な目的地マーカーとして表示を維持します"
        )
    }

    /// 強制ハイライト表示中は通常ガイド枠を Scene へ送らず、目的地マーカーだけを維持することを検証する
    func testForcedSelectionHidesGuideCandidatesButKeepsTargetMarkers() {
        MoveCard.setTestMovementVectors([
            MoveVector(dx: 1, dy: 0),
            MoveVector(dx: -1, dy: 0)
        ], for: .kingRight)
        defer { MoveCard.setTestMovementVectors(nil, for: .kingRight) }

        let core = GameCore(mode: .dungeonPlaceholder)
        let viewModel = GameBoardBridgeViewModel(core: core, mode: .dungeonPlaceholder)
        let origin = GridPoint(x: 2, y: 2)
        let target = GridPoint(x: 4, y: 2)

        core.overrideTargetStateForTesting(
            targetPoint: target,
            upcomingTargetPoints: [GridPoint(x: 0, y: 0)]
        )

        let singleStack = HandStack(cards: [DealtCard(move: .kingUp)])
        let multipleStack = HandStack(cards: [DealtCard(move: .kingRight)])

        viewModel.refreshGuideHighlights(
            handOverride: [singleStack, multipleStack],
            currentOverride: origin,
            progressOverride: .playing
        )

        XCTAssertFalse(
            viewModel.scene.latestHighlightPoints(for: .guideSingleCandidate).isEmpty,
            "通常時は単一候補ガイドが Scene へ送られる想定です"
        )
        XCTAssertFalse(
            viewModel.scene.latestHighlightPoints(for: .guideMultipleCandidate).isEmpty,
            "通常時は複数候補ガイドが Scene へ送られる想定です"
        )

        let selectedDestinations: Set<GridPoint> = [GridPoint(x: 3, y: 2), GridPoint(x: 1, y: 2)]
        viewModel.updateForcedSelectionHighlights(selectedDestinations)

        XCTAssertTrue(
            viewModel.scene.latestHighlightPoints(for: .guideSingleCandidate).isEmpty,
            "カード選択中は単一候補ガイドを Scene へ送らない想定です"
        )
        XCTAssertTrue(
            viewModel.scene.latestHighlightPoints(for: .guideMultipleCandidate).isEmpty,
            "カード選択中は複数候補ガイドを Scene へ送らない想定です"
        )
        XCTAssertEqual(
            viewModel.scene.latestHighlightPoints(for: .forcedSelection),
            selectedDestinations,
            "選択中カードの移動候補だけを強制ハイライトとして表示する想定です"
        )
        XCTAssertEqual(
            viewModel.scene.latestHighlightPoints(for: .currentTarget),
            [target],
            "カード選択中でも現在目的地マーカーは維持する必要があります"
        )
        XCTAssertEqual(
            viewModel.scene.latestHighlightPoints(for: .upcomingTarget),
            [GridPoint(x: 0, y: 0)],
            "カード選択中でも次目的地マーカーは維持する必要があります"
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
        let core = GameCore(mode: .dungeonPlaceholder)
        return GameBoardBridgeViewModel(core: core, mode: .dungeonPlaceholder)
    }
}
