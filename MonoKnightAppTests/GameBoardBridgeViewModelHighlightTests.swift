import XCTest
@testable import MonoKnightApp
import Game

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
        let core = GameCore.makeTestInstance(deck: deck, current: nil, mode: .classicalChallenge)
        let viewModel = GameBoardBridgeViewModel(core: core, mode: .classicalChallenge)

        XCTAssertEqual(core.progress, .awaitingSpawn, "スポーン選択待機状態で開始できていません")

        // 復帰後に確認したい手札を退避させ、ガイド集合が一時的に空になることを確認する
        let singleStack = HandStack(cards: [DealtCard(move: .kingUp)])
        viewModel.refreshGuideHighlights(
            handOverride: [singleStack],
            progressOverride: .awaitingSpawn
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
                deadlockPenaltyCost: 5,
                manualRedrawPenaltyCost: 5,
                manualDiscardPenaltyCost: 1,
                revisitPenaltyCost: 0
            ),
            impassableTilePoints: [impassablePoint]
        )
        let mode = GameMode(
            identifier: .freeCustom,
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

    /// テストで使い回す ViewModel を生成するヘルパー
    private func makeViewModel() -> GameBoardBridgeViewModel {
        let core = GameCore(mode: .standard)
        return GameBoardBridgeViewModel(core: core, mode: .standard)
    }
}

